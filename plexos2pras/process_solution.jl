using ResourceAdequacy

include("loadh5.jl")

function extract_modelname(filename::String,
                           suffix::String,
                           default::String="system")::String

    rgx = Regex(".*Model (.+)_" * suffix * " Solution.*")
    result = match(rgx, filename)

    if result isa Void
        warn("Could not determine PLEXOS model name from filename $filename, " *
             "falling back on default '$default'")
        return  default
    else
        return result.captures[1]
    end

end

function process_dispatchable_generators(
    capacity::Matrix{T}, λ::Matrix{T}, μ::Matrix{T}) where {T <: Real}

    #TODO: Group generators into regions for non-copperplate

    # Assign each time period to a de-deduplicated generators spec limit
    n_periods = size(capacity, 1)
    hashes = UInt[]
    genspecs_lookup = Vector{Int}(n_periods)
    genspecs = Matrix{ResourceAdequacy.DispatchableGeneratorSpec{T}}(size(capacity, 2), size(capacity, 1))
    nuniques = 0

    for t in 1:n_periods

        genspecs_t = ResourceAdequacy.DispatchableGeneratorSpec.(
            view(capacity, t, :), view(λ, t, :), view(μ, t, :))

        genspecshash = hash(genspecs_t)
        hashidx = findfirst(hashes, genspecshash)

        if hashidx > 0
            genspecs_lookup[t] = hashidx
        else
            push!(hashes, genspecshash)
            nuniques += 1
            genspecs[:, nuniques] = genspecs_t
            genspecs_lookup[t] = nuniques
        end

    end

    return genspecs[:, 1:nuniques], genspecs_lookup

end

function aggregate_vg_regionally(
    n_regions::Int, vg_capacity::Matrix{T},
    regions::Vector{Int}) where {T <: Real}

    vgprofiles = zeros(T, n_regions, size(vg_capacity, 1))

    for (i, r) in enumerate(regions)
        vgprofiles[r, :] .+= vg_capacity[:, i]
    end

    return vgprofiles

end

function loadsystem(
    inputpath_h5::String, suffix::String, vg_categories::Vector{String},
    exclude::Vector{String}, useinterfaces::Bool)

    systemname = extract_modelname(inputpath_h5, suffix)
    rawdata = loadh5(inputpath_h5, vg_categories, exclude_categories)

    # Region Data
    regions = unique(region_regions[[:ParentRegion, :ParentRegionIdx]], :ParentRegionIdx)
    sort!(regions, :ParentRegionIdx)
    regionnames = regions[:ParentRegion]
    n_regions = length(regionnames)

    # Load Data

    # loaddata = load_singlebanddata(h5file, "data/ST/interval/region/Load")
    @assert n_regions == size(loaddata, 2)

    keep_periods = .!isnan.(loaddata[:, 1])
    loaddata = loaddata[keep_periods, :]'
    timestamps = tstamps[keep_periods]
    timerange = first(timestamps):Hour(1):last(timestamps)
    n_periods = length(timerange)

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

    # VG Data
    vgprofiles = aggregate_vg_regionally(
        n_regions, vg_capacity,
        generators[isvg, :RegionIdx])

    # Dispatchable Generator Data
    μ = 1 ./ mttr
    λ = μ .* outagerate ./ (1 .- outagerate)
    generatorspecs, timestamps_generatorset =
        process_dispatchable_generators(dispatchable_capacity, λ, μ)

    # Single-node system for now
    system =
        ResourceAdequacy.MultiPeriodSystem{1,Hour,n_periods,Hour,MW,MWh}(
            generatorspecs, Matrix{ResourceAdequacy.StorageDeviceSpec{Float64}}(0,1),
            timerange, timestamps_generatorset, ones(Int, n_periods),
            reshape(sum(vgprofiles, 1), :), reshape(sum(loaddata, 1), :))


    return system

end
