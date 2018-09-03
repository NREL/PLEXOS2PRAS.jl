using ResourceAdequacy

include("loadh5.jl")

function loadsystem(
    inputpath_h5::String, suffix::String,
    vg_categories::Vector{String}, exclude_categories::Vector{String},
    useplexosinterfaces::Bool)

    systemname = extract_modelname(inputpath_h5, suffix)
    rawdata = loadh5(inputpath_h5, vg_categories, exclude_categories)

    n_periods = length(rawdata.timestamps)

    vgprofiles = aggregate_vg_regionally(rawdata)

    interfaces, linespecs, linespecs_timelookup, lines_interfaceidx =
        process_lines(rawdata, useplexosinterfaces)

    genspecs, genspecs_timelookup, gens_regionidx =
        process_dispatchable_generators(rawdata)

    storspecs, storspecs_timelookup, stors_regionidx =
        process_storages(rawdata)

    system =
        ResourceAdequacy.MultiPeriodSystem{1,Hour,n_periods,Hour,MW,MWh}(
            rawdata.regionnames,
            genspecs, gens_regionidx, storspecs, storspecs_regionidx,
            interfaces, linespecs, lines_interfaceidx,
            rawdata.timestamps, genspecs_timelookup,
            storspecs_timelookup, linespecs_timelookup,
            vgprofiles, loaddata)

    return systemname, system

end

function process_lines(rawdata::RawSystemData{T,V},
                       useplexosinterfaces::Bool) where {T,V}

    # TODO: Respect useplexosinterfaces - load in pseudo-lines based on
    #       PLEXOS interfaces if requested

    lines_interfacestart = groupstartidxs(rawdata.lineregions)
    λ, μline_λ, line_\mu =
        plexosoutages_to_transitionprobs(rawdata.line_outagerate, rawdata.line_mttr)
    timestamps_lineset, lines =
        deduplicatespecs(ResourceAdequacy.LineSpec, linecapacity, λ, μline_\lambda, line_\mu)

    return timestamps_lineset, lines, lines_interfacestart

end

function aggregate_vg_regionally(rawdata::RawSystemData{T,V}) where {T, V}

    n_regions = length(rawdata.regionnames)
    n_periods = size(rawdata.vgcapacity, 1)
    vgprofiles = zeros(T, n_regions, n_periods)

    for (i, r) in enumerate(rawdata.vgregions)
        vgprofiles[r, :] .+= rawdata.vg_capacity[:, i]
    end

    return vgprofiles

end

function process_dispatchable_generators(rawdata::RawSystemData{T,V}) where {T,V}

    generators_regionstart = groupstartidxs(rawdata.dispregions)
    λ, μ = plexosoutages_to_transitionprobs(rawdata.dispoutagerate, rawdata.dispmttr)
    genspecs, genspecs_lookup =
        deduplicatespecs(ResourceAdequacy.DispatchableGeneratorSpec, rawdata.dispcapacity, λ, μ)

    return genspecs, genspecs_lookup, generators_regionstart

end

function process_storages(rawdata::RawSystemData{T,V}) where {T,V}
    n_periods = length(rawdata.timestamps)
    return Matrix{ResourceAdequacy.StorageDeviceSpec{Float64}}(0,1), ones(Int, n_periods), Int[]
end

function groupstartidxs(alllabels::Vector{T}) where {T}

    @assert sorted(alllabels)
    prev_grouplabel = nulllabel(T)
    grouplabels = []
    groupstart_idxs = []

    for (i, grouplabel) in enumerate(alllabels)
        if grouplabel != prev_grouplabel
            push!(grouplabels, grouplabel)
            push!(groupstart_idxs, i)
        end
    end

    return groupslabels, groupstart_idxs

end

nulllabel(::Type{Int}) = -1
nulllabel(::Type{NTuple{N,T}) where {N,T} = ntuple(_ -> nulllabel(T), N)

function plexosoutages_to_transitionprobs(outagrate::Matrix{V}, mttr::Matrix{V}) where {V <: Real}
    # TODO: Generalize to non-hourly intervals
    μ = 1 ./ mttr
    outagerate = outagerate ./ 100
    λ = μ .* outagerate ./ (1 .- outagerate)
    return λ, μ
end

function deduplicatespecs(Spec::Type{<:ResouceAdequacy.AssetSpec{V}},
                          rawspecs::Matrix{V}...) where {V<:Real}

    n_periods = size(rawspecs[1], 1)
    n_assets = size(rawspecs[1], 2)

    hashes = UInt[]
    specs_lookup = Vector{Int}(n_periods)
    specs = Matrix{Spec}(n_assets, n_periods)
    nuniques = 0

    for t in 1:n_periods

        specs_t = Spec.(
            (view(rawspec, t, :) for rawspec in rawspecs)...)

        specshash = hash(specs_t)
        hashidx = findfirst(hashes, specshash)

        if hashidx > 0
            specs_lookup[t] = hashidx
        else
            push!(hashes, specshash)
            nuniques += 1
            specs[:, nuniques] = specs_t
            specs_lookup[t] = nuniques
        end

    end

    return specs_lookup, specs[:, 1:nuniques]

end

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

