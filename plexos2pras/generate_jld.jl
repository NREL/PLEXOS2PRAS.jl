using ResourceAdequacy
using DataFrames
using HDF5
using JLD

include("utils.jl")
include("loadh5.jl")

function process_dispatchable_generators(
    capacity::Matrix{T}, λ::Matrix{T}, μ::Matrix{T}) where {T <: Real}

    # Assign each time period to a de-deduplicated generators spec limit
    hashes = UInt[]
    genspecs_lookup = Vector{Int}(n_periods)
    genspecs = Matrix{DispatchableGeneratorSpec{T}}(size(capacity, 2), size(capacity, 1))
    nuniques = 0

    for t in 1:n_periods

        genspecs_t = DispatchableGeneratorSpec.(
            view(capacity, t, :), view(λ, t, :), view(μ, t, :))

        genspecshash = hash(genspecs_t)
        hashidx = findfirst(hashes, genspecshash)

        if hashidx > 0
            genspecs_lookup[t] = hashidx
        else
            push!(hashes, genspecshash)
            nuniques += 1
            genspecs[nuniques, :] = genspecs_t
            genspecs_lookup[t] = nuniques
        end

    end

    return genspecs[1:nuniques, :], genspecs_lookup

end

function aggregate_vg_regionally(n_regions::Int,
                                 available_capacity::Matrix{T}
                                 regions::Vector{Int})

    vgprofiles = zeros(T, n_regions, size(available_capacity, 1))

    for (i, r) in enumerate(regions)
        vgprofiles[r, :] .+= vg_capacity[:, i]
    end

    return vgprofiles

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
    # For now we ignore and load system as copper plate

    # Load interregional lines
    # TODO

    # TODO: Determine line source and destination

    # Load line flow limits
    # Min and max flows? (and warn if not symmetrical?)
    # transfers = load_singlebanddata(
    #     h5file,
    #     "data/ST/interval/line/Max Flow",
    #     keep_periods)

    # TODO: Associate interregional lines with max flows

    isvg = generators[:VG]

    available_capacity = load_singlebanddata(
        h5file, "data/ST/interval/generator/Available Capacity", keep_periods)

    # VG Data
    vg_capacity = available_capacity[:, isvg]
    vgprofiles = aggregate_vg_regionally(
        n_regions, vg_capacity,
        generators[:RegionIdx, isvg])

    # Dispatchable Generator Data
    dispatchable_capacity = available_capacity[:, !isvg]
    outagerate = load_singlebanddata(
        h5file, "data/ST/interval/generator/x", keep_periods)[:, !isvg] ./ 100
    mttr = load_singlebanddata(
        h5file, "data/ST/interval/generator/y", keep_periods)[:, !isvg]
    μ = 1 ./ mttr
    λ = μ .* outagerate ./ (1 .- outagerate)
    generators, timestamps_generatorset = process_dispatchable_generators(
        generators[:, !isvg], dispatchable_capacity, λ, μ)

    # Single-node system for now
    system =
        ResourceAdequacy.MultiPeriodSystem{1,Hour,n_periods,Hour,MW,MWh}(
            generators, StorageDeviceSpec{Float64}[],
            timestamps, timestamps_generatorset, ones(Int, length(timestamps))
            reshape(sum(vgprofiles, 1), :), reshape(sum(loaddata, 1), :))

    save(outputpath_jld, systemname, system)

end
