using ResourceAdequacy
using Distributions
using HDF5
using JLD

include("utils.jl")
include("loadh5.jl")

function aggregate_dispatchables_regionally(
    n_regions::Int
    available_capacity::Vector{T},
    outage_rate::Vector{T},
    regions::Vector{Int}) where {T<:Real}

    dispcaps = [Int[] for _ in 1:n_regions for 1:n_periods]
    dispors = [T[] for _ in 1:n_regions]

    for (i, r) in enumerate(regions)
            push!(dispcaps[r], round(Int, available_capacity[i]))
            push!(dispors[r], 1-outage_rate[i]/100)
    end

    dispdistrs = Vector{Generic{Float64,Float64,Vector{Float64}}}(n_regions)
    for (i, (dispcap, dispor)) in enumerate(zip(dispcaps, dispors))
        if length(dispcap) == 0
            dispdistrs[i] = Generic([0.],[1.])
        else
            dist = ResourceAdequacy.spconv(dispcap, dispor)
            dispdistrs[i] = Generic(Vector{Float64}(support(dist)),
                                    Distributions.probs(dist))
        end
    end

    return dispdistrs

end

function aggregate_vg_regionally(n_regions::Int,
                                 available_capacity::Matrix{T}
                                 regions::Vector{Int})

    vg_capacity = available_capacity[:, isvgs]
    vg_regions = regions[isvgs]
    vgprofiles = zeros(T, n_regions, size(available_capacity, 1))

    for (i, r) in enumerate(vg_regions)
        vgprofiles[r, :] .+= vg_capacity[:, i]
    end

    return vgprofiles

end

function aggregate_regionally(n_regions::Int,
                              n_periods::Int,
                              available_capacity::Matrix{T},
                              outage_rate::Matrix{T},
                              regions::Vector{Int},
                              isvgs::Vector{Bool}) where T

    vgprofiles = aggregate_vg_regionally(
        n_regions, available_capacity, regions)

    # Deduplicate and store dispatchable capacity distribution
    # in each region

    dispatchables_capacity = available_capacity[:, !isvgs]
    dispatchables_outagerate = outate_rate[:, !isvgs]
    dispatchables_regions = regions[!isvgs]

    genshashes = UInt[]
    gendistrs = CapacityDistribution{T}[]
    nuniques = 0
    gendistrlookup = Vector{Int}(n_periods)

    for i in 1:n_periods

        capacities = dispatchables_capacity[i, :]
        outagerates = dispatchables_outagerate[i, :]

        genshash = hash((capacities, outagerates))
        hashidx = findfirst(genshashes, genshash)

        if hashidx > 0
            gendistrlookup[i] = hashidx
        else
            distrs = aggregate_dispatchables_regionally(
                n_regions, capacities,
                outagerates, dispatchables_regions)
            nuniques += 1
            push!(genshashes, genshash)
            push!(gendistrs, distrs)
            gendistrlookup[i] = nuniques
        end

    end

    return vgprofiles, hcat(gendistrs...)

end

inputpath_h5 = ARGS[1]
outputpath_jld = ARGS[2]
suffix = ARGS[3]
vg_categories = length(ARGS) > 3 ? ARGS[4:end] : String[]

systemname = extract_modelname(inputpath_h5, suffix)

vgcategory(x::String) = x in vg_categories
pointdistr(x) = Generic(Float64[x], [1.])

# TODO: Would be nice to check that the necessary properties
# are reported before starting to load things in

tstamps, generators, region_regions = load_metadata(inputpath_h5)
generators[:VG] = vgcategory.(generators[:GeneratorCategory])

#TODO: Support importing arbitrary interval lengths from PLEXOS
if tstamps[1] + Hour(1) != tstamps[2]
    warn("The importer currently assumes your PLEXOS intervals are hourly" *
         " but this doesn't seem to be the case with your data. Time-related" *
         " reliability metrics and units will likely be incorrect.")
end

# Region Data
regions = unique(region_regions[[:ParentRegion, :ParentRegionIdx]], :ParentRegionIdx)
sort!(regions, :ParentRegionIdx)
regionnames = regions[:ParentRegion]
n_regions = length(regionnames)

h5open(inputpath_h5, "r") do h5file

    # Load Data

    loaddata = load_singlebanddata(h5file, "data/ST/interval/region/Load")
    @assert n_regions == size(loaddata, 2)

    keep_periods = .!isnan.(loaddata[:, 1])
    loaddata = loaddata[keep_periods, :]'
    timestamps = tstamps[keep_periods]
    n_periods = length(timestamps)

    # Transmission Data

    transfers = load_singlebanddata(
        h5file,
        "data/ST/interval/region_regions/Available Transfer Capability",
        keep_periods)

    # # Eliminate self-transfer columns
    # isexchange =
    #     region_regions[:ParentRegionIdx] .!= region_regions[:ChildRegionIdx]
    # region_regions = region_regions[isexchange, :]
    # transfers = transfers_all[:, isexchange]

    region_regions_edgelabels = map(
        (pi,ci) -> (min(pi, ci), max(pi, ci)),
        region_regions[:ParentRegionIdx], region_regions[:ChildRegionIdx])

    # Combine both flow directions into single columns
    edgelabels = [(i,j) for i in 1:n_regions for j in (i+1):n_regions]
    transfers_deduplicated = similar(
        transfers, dims=(n_periods, n_regions*(n_regions-1)/2))

    for (i, (from, to)) in enumerate(edgelabels)
        idxs = find(label -> label == (from, to),
                    region_regions_edgelabels)
        length(idxs) != 2 &&
            error("Expected two matching edge labels for $((from, to)) ",
                  "but got $(length(idxs))")
        transfers_deduplicated[:, i] =
            min.(transfers[:, idxs[1]], transfers[:, idxs[2]])
    end

    # Determine which interfaces are always zero-limit and remove
    nonzero_interfaces = reshape(any(x -> x>0, transfers_deduplicated, 1), :)
    edgelabels = edgelabels[nonzero_interfaces]
    transfers_nonzero = transfers_deduplicated[:, nonzero_interfaces]

    # Assign each time period to a de-deduplicated interface transfer limit
    hashes = UInt[]
    interface_distrs = Generic{Float64,Float64,Vector{Float64}}[]
    interface_lookups = Vector{Int}(n_periods)
    nuniques = 0

    for i in 1:n_periods

        maxtransfers = transfers_nonzero[i, :]
        transfershash = hash(maxtransfers)
        hashidx = findfirst(hashes, transfershash)

        if hashidx > 0
            interface_lookups[i] = hashidx
        else
            push!(hashes, transfershash)
            push!(interface_distrs, pointdistr.(maxtransfers))
            nuniques += 1
            interface_lookups[i] = nuniques
        end

    end

    # Generator Data

    outagerate = load_singlebanddata(
        h5file, "data/ST/interval/generator/x", keep_periods) ./ 100

    available_capacity = load_singlebanddata(
        h5file, "data/ST/interval/generator/Available Capacity", keep_periods)

    vgprofiles, maxgen_distrs = aggregate_regionally(
        n_regions, n_periods, available_capacity, outagerate,
        Vector(generators[:RegionIdx]), Vector(generators[:VG]))

    system =
        ResourceAdequacy.SystemDistributionSet{1,Hour,n_periods,Hour,MW,MWh}(
            timestamps,
            regionnames, maxgen_distrs, maxgen_lookups,
            vgprofiles,
            edgelabels, hcat(interface_distrs...), interface_lookups,
            loaddata)

    save(outputpath_jld, systemname, system)

end
