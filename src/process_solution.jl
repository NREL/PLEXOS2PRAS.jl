function loadsystem(
    inputpath_zip::String,
    vg_categories::Vector{String}, exclude_categories::Vector{String},
    useplexosinterfaces::Bool)

    inputpath_h5 = h5plexos(inputpath_zip)
    rawdata = loadh5(inputpath_h5, vg_categories, exclude_categories)

    n_periods = length(rawdata.timestamps)

    vgprofiles = aggregate_vg_regionally(rawdata)

    interfaces, linespecs, linespecs_timelookup, lines_interfaceidx =
        process_lines(rawdata, useplexosinterfaces)

    genspecs, genspecs_timelookup, gens_regionidx =
        process_dispatchable_generators(rawdata)

    storspecs, storspecs_timelookup, stors_regionidx =
        process_storages(rawdata)

    return ResourceAdequacy.SystemModel{n_periods,1,Hour,MW,MWh}(
        rawdata.regionnames,
        genspecs, gens_regionidx, storspecs, stors_regionidx,
        interfaces, linespecs, lines_interfaceidx,
        rawdata.timestamps, genspecs_timelookup,
        storspecs_timelookup, linespecs_timelookup,
        vgprofiles, permutedims(rawdata.demand))

end

function h5plexos(zippath::String)
    h5path = replace(zippath, r"^(.*)\.zip$" => s"\1.h5")
    h5process[:process_solution](zippath, h5path)[:close]()
    return h5path
end

function process_lines(rawdata::RawSystemData{T,V},
                       useplexosinterfaces::Bool) where {T,V}

    if useplexosinterfaces
        n_interfaces = length(rawdata.interfaceregions)
        n_timesteps = length(rawdata.timestamps)
        lineregions = rawdata.interfaceregions
        linecapacities = rawdata.interfacecapacity
        λ = zeros(n_timesteps, n_interfaces)
        μ = ones(n_timesteps, n_interfaces)
    else
        lineregions = rawdata.lineregions
        linecapacities = rawdata.linecapacity
        λ, μ = plexosoutages_to_transitionprobs(rawdata.lineoutagerate, rawdata.linemttr)
    end

    interfaces = unique(lineregions)
    lines_interfacestart = groupstartidxs(interfaces, lineregions)
    linespecs, linespecs_lookup = deduplicatespecs(
        ResourceAdequacy.LineSpec, linecapacities, λ, μ)

    return interfaces, linespecs, linespecs_lookup, lines_interfacestart

end

function aggregate_vg_regionally(rawdata::RawSystemData{T,V}) where {T, V}

    n_regions = length(rawdata.regionnames)
    n_periods = size(rawdata.vgcapacity, 1)
    vgprofiles = zeros(V, n_regions, n_periods)

    for (i, r) in enumerate(rawdata.vgregions)
        vgprofiles[r, :] .+= rawdata.vgcapacity[:, i]
    end

    return vgprofiles

end

function process_dispatchable_generators(rawdata::RawSystemData{T,V}) where {T,V}

    n_regions = length(rawdata.regionnames)
    generators_regionstart = groupstartidxs(collect(1:n_regions), rawdata.dispregions)
    λ, μ = plexosoutages_to_transitionprobs(rawdata.dispoutagerate, rawdata.dispmttr)
    genspecs, genspecs_lookup = deduplicatespecs(
        ResourceAdequacy.DispatchableGeneratorSpec, rawdata.dispcapacity, λ, μ)

    return genspecs, genspecs_lookup, generators_regionstart

end

function process_storages(rawdata::RawSystemData{T,V}) where {T,V}
    n_periods = length(rawdata.timestamps)
    n_regions = length(rawdata.regionnames)
    return Matrix{ResourceAdequacy.StorageDeviceSpec{Float64}}(undef, 0, 1),
           ones(Int, n_periods), ones(Int, n_regions)
end

function groupstartidxs(groups::Vector{T}, unitgroups::Vector{T}) where {T}

    @assert issorted(groups)
    @assert issorted(unitgroups)

    n_groups = length(groups)
    n_units = length(unitgroups)
    groupstart_idxs = Vector{Int}(undef, n_groups)

    group_idx = unit_idx = 0
    remaining_units = n_units > 0
    remaining_groups = n_groups > 0
    group = nullgroup(T)
    unitgroup = nullgroup(T)

    while remaining_groups

        while unitgroup == group && remaining_units
            unit_idx += 1
            unitgroup = unitgroups[unit_idx]
            unit_idx == n_units && (remaining_units = false)
        end

        while !(unitgroup == group && remaining_units) && remaining_groups
            group_idx += 1
            group = groups[group_idx]
            groupstart_idxs[group_idx] = group <= unitgroup ? unit_idx : n_units + 1
            group_idx == n_groups && (remaining_groups = false)
        end

    end

    return groupstart_idxs

end

nullgroup(::Type{Int}) = -1
nullgroup(::Type{NTuple{N,T}}) where {N,T} = ntuple(_ -> nullgroup(T), N)

function plexosoutages_to_transitionprobs(outagerate::Matrix{V}, mttr::Matrix{V}) where {V <: Real}

    # TODO: Generalize to non-hourly intervals
    μ = 1 ./ mttr
    μ[mttr .== 0] .= one(V) # Interpret zero MTTR as μ = 1.

    outagerate = outagerate ./ 100
    λ = μ .* outagerate ./ (1 .- outagerate)
    λ[outagerate .== 0] .= zero(V) # Interpret zero FOR as λ = 0.

    return λ, μ

end

function deduplicatespecs(Spec::Type{<:ResourceAdequacy.AssetSpec},
                          rawspecs::Matrix{V}...) where {V<:Real}

    n_periods = size(rawspecs[1], 1)
    n_assets = size(rawspecs[1], 2)

    hashes = UInt[]
    specs_lookup = Vector{Int}(undef, n_periods)
    specs = Matrix{Spec{V}}(undef, n_assets, n_periods)
    nuniques = 0

    for t in 1:n_periods

        specs_t = Spec.(
            (view(rawspec, t, :) for rawspec in rawspecs)...)

        specshash = hash(specs_t)
        hashidx = findfirst(isequal(hashes), specshash)

        if hashidx !== nothing
            specs_lookup[t] = hashidx
        else
            push!(hashes, specshash)
            nuniques += 1
            specs[:, nuniques] = specs_t
            specs_lookup[t] = nuniques
        end

    end

    return specs[:, 1:nuniques], specs_lookup

end
