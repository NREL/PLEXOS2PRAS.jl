function process_plexossolution(
    inputpath_h5::String,
    outputpath_h5::String;
    timestep::Period=Hour(1),
    timezone::TimeZone=tz"UTC",
    exclude_categories::Vector{String}=String[],
    use_interfaces::Bool=false,
    string_length::Int=128,
    compression_level::Int=1)

    h5open(inputpath_h5, "r") do plexosfile::HDF5File
        h5open(outputpath_h5, "w") do prasfile::HDF5File

            process_metadata!(
                prasfile, plexosfile, timestep, timezone)

            process_regions!(
                prasfile, plexosfile,
                string_length, compression_level)

            #process_generators_storages!(
                #prasfile, plexosfile,
                #exclude_categories, string_length, compression_level)

            # process_lines_interfaces!(
            #     prasfile, plexosfile,
            #     use_interfaces, string_length, compression_level)

        end
    end

    return

end

function process_metadata!(
    prasfile::HDF5File,
    plexosfile::HDF5File,
    timestep::Period,
    timezone::TimeZone)

    attributes = attrs(prasfile)

    attributes["pras_dataversion"] = "v0.2.1"

    # TODO: Are other values possible for these units?
    attributes["power_unit"] = "MW"
    attributes["energy_unit"] = "MWh"

    timestamps = ZonedDateTime.(
        DateTime.(
            read(plexosfile["metadata/times/interval"]),
            dateformat"yyyy-mm-ddTHH:MM:SS"), timezone)

    all(timestamps[1:end-1] .+ timestep .== timestamps[2:end]) ||
        error("PLEXOS result timestep durations did not " *
              "all match provided timestep ($timestep)")

    attributes["start_timestamp"] = string(first(timestamps))
    attributes["timestep_count"] = length(timestamps)
    attributes["timestep_length"] = timestep.value
    attributes["timestep_unit"] = unitsymbol(typeof(timestep))

    return

end

function process_regions!(
    prasfile::HDF5File, plexosfile::HDF5File,
    stringlength::Int, compressionlevel::Int)

    # Load required data from plexosfile

    regiondata = readcompound(plexosfile["/metadata/objects/region"])
    load = read(plexosfile["/data/ST/interval/region/Load"])

    n_regions = size(regiondata, 1)
    n_periods = read(attrs(prasfile)["timestep_count"])

    # Save data to prasfile

    regions = g_create(prasfile, "regions")

    string_table!(regions, "_core", regiondata[!, [:name]], stringlength)

    regions["load", "compress", compressionlevel] =
        round.(UInt32, permutedims(reshape(load, n_periods, n_regions)))

    return

end

function process_lines_interfaces!(
    prasfile::HDF5File, plexosfile::HDF5File,
    useplexosinterfaces::Bool, stringlength::Int, compressionlevel::Int)

    if useplexosinterfaces
        # Load in interface data
        n_interfaces = length(rawdata.interfaceregions)
        lineregions = rawdata.interfaceregions
        linecapacities = rawdata.interfacecapacity
        λ = zeros(n_timesteps, n_interfaces)
        μ = ones(n_timesteps, n_interfaces)
    else
        # Load in line data
        lineregions = rawdata.lineregions
        linecapacities = rawdata.linecapacity
        λ, μ = plexosoutages_to_transitionprobs(rawdata.lineoutagerate, rawdata.linemttr)
    end

    interfaceregions = unique(lineregions)
    n_interfaces = length(interfaces)
    infinitecapacity = fill(typemax(UInt32), n_interfaces, n_periods)

    # Save data to prasfile

    interfaces = g_create(prasfile, "interfaces")

    string_table!(interfaces, "_core", ["region1", "region2"],
                  interfaceregions, stringlength)

    interfaces["forwardcapacity", "compress", compressionlevel] =
        infinitecapacity

    interfaces["backwardcapacity", "compress", compressionlevel] =
        infinitecapacity

    return

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
    n_storages = length(rawdata.storregions)

    stors_regionstart = groupstartidxs(collect(1:n_regions), rawdata.storregions)
    λ, μ = plexosoutages_to_transitionprobs(rawdata.storoutagerate, rawdata.stormttr)

    storspecs, storspecs_lookup = deduplicatespecs(
        ResourceAdequacy.StorageDeviceSpec,
        rawdata.storcapacity, rawdata.storenergy,
        ones(n_periods, n_storages), λ, μ)

    return storspecs, storspecs_lookup, stors_regionstart

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
        hashidx = findfirst(isequal(specshash), hashes)

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
