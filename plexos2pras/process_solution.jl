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
    capacity::Matrix{T}, outagerate::Matrix{T}, mttr::Matrix{T}) where {T <: Real}

    μ = 1 ./ mttr # TODO: Generalize to non-hourly intervals

    outagerate = outagerate ./ 100
    λ = μ .* outagerate ./ (1 .- outagerate)

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

    n_regions = length(rawdata.regionnames)
    n_periods = length(rawdata.timestamps)

    # Transmission Data
    if useinterfaces
        # Load in pseudo-lines based on interfaces
    else
        # Load in transmission lines
    end

    # Load line flow limits
    # Min and max flows? (and warn if not symmetrical?)

    # VG Data
    vgprofiles = aggregate_vg_regionally(rawdata)

    # Dispatchable Generator Data
    generatorspecs, timestamps_generatorset, generators_regionstart =
        process_dispatchable_generators(rawdata)

    system =
        ResourceAdequacy.MultiPeriodSystem{1,Hour,n_periods,Hour,MW,MWh}(
            rawdata.regionnames, generatorspecs, generators_regionstart,
            Matrix{ResourceAdequacy.StorageDeviceSpec{Float64}}(0,1), Int[],
            _, _, _, # Interface and line data
            rawdata.timestamps, timestamps_generatorset,
            ones(Int, n_periods), timestamps_lineset,
            vgprofiles, loaddata)

    return system

end
