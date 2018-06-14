using ResourceAdequacy
using Distributions
using HDF5
using JLD

include("utils.jl")
include("loadh5.jl")

function aggregate_regionally(n_regions::Int,
                              available_capacity::Matrix{T},
                              outage_rate::Matrix{T},
                              regions::Vector{Int},
                              isvgs::Vector{Bool}) where T

    vgprofiles = zeros(T, n_regions, size(available_capacity, 1))
    dispcaps = [Int[] for _ in 1:n_regions]
    dispors = [T[] for _ in 1:n_regions]

    for (i, (r, isvg)) in enumerate(zip(regions, isvgs))
        if isvg
            vgprofiles[r, :] .+= available_capacity[:, i]
        else
            push!(dispcaps[r], round(Int, available_capacity[1, i]))
            push!(dispors[r], 1.-outage_rate[1, i]./100)
        end
    end

    dispdistrs = Vector{Generic{Float64,Float64,Vector{Float64}}}(n_regions)
    for (i, (dispcap, dispor)) in enumerate(zip(dispcaps, dispors))
        if length(dispcap) == 0
            dispdistrs[i] = Generic([0.],[1.])
        else
            dist = ResourceAdequacy.spconv(dispcap, dispor)
            dispdistrs[i] = Generic(Vector{Float64}(support(dist)), Distributions.probs(dist))
        end
    end

    return vgprofiles, dispdistrs

end

# Use h5py to load compound data
inputpath_h5 = ARGS[1]
outputpath_jld = ARGS[2]
suffix = ARGS[3]
vg_categories = length(ARGS) > 3 ? ARGS[4:end] : String[]

systemname = extract_modelname(inputpath_h5, suffix)

vgcategory(x::String) = x in vg_categories

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

h5open(inputpath_h5, "r") do h5file

    # Load Data

    loaddata = load_singlebanddata(h5file, "data/ST/interval/region/Load")
    n_regions = size(loaddata, 2)

    # Transmission Data

    transfers = load_singlebanddata(
        h5file,
        "data/ST/interval/region_regions/Available Transfer Capability")

    region_regions[:TransferLimit] = collect(transfers[1,:]) # Static flow bounds for now

    region_regions[:EdgeLabel] = map((pi,ci) -> (min(pi, ci), max(pi, ci)),
                                     region_regions[:ParentRegionIdx],
                                     region_regions[:ChildRegionIdx])

    edges = by(region_regions, :EdgeLabel) do d::AbstractDataFrame

        if size(d,1) != 2
            label = d[1, :EdgeLabel]
            label[1] == label[2] && return DataFrame(TransferLimit=[]) # Ignore self-transfer data
            error("Unexpected line flow data: $d") # Non self-transfers should only ever have 2 flows
        end

        limit1 = d[1, :TransferLimit]
        limit2 = d[2, :TransferLimit]

        if limit1 == limit2
            return DataFrame(TransferLimit=limit1) # Symmetrical constraints
        else
            region1 = d[1, :ParentRegion]
            region2 = d[2, :ParentRegion]
            warn("Asymmetrical transfer limits between $region1 and $region2" *
                    "($limit1 and $limit2). Using the lower of the two values.")
            return DataFrame(TransferLimit=min(limit1, limit2))
        end
    end

    edgelabels = Vector{Tuple{Int,Int}}(edges[:EdgeLabel])
    edgedistrs = [Generic(Float64[l], [1.]) for l in edges[:TransferLimit]]

    # Generator Data

    outagerate = load_singlebanddata(
        h5file, "data/ST/interval/generator/x") ./ 100

    keep_periods = .!isnan.(outagerate[:, 1])

    timestamps = tstamps[keep_periods]
    outagerate = outagerate[keep_periods, :]
    available_capacity = load_singlebanddata(
        h5file, "data/ST/interval/generator/Available Capacity")[keep_periods, :]
    loaddata = loaddata[keep_periods, :]'
    vgprofiles, dispdistrs = aggregate_regionally(
        n_regions, available_capacity, outagerate,
        Vector(generators[:RegionIdx]), Vector(generators[:VG]))

    n = length(timestamps)

    system = ResourceAdequacy.SystemDistributionSet{
        1,Hour,n,Hour,MW,Float64}(
        timestamps, dispdistrs, vgprofiles,
        edgelabels, edgedistrs, loaddata, 10, 1)

    save(outputpath_jld, systemname, system)

end
