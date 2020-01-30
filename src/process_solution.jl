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

            process_lines_interfaces!(
                prasfile, plexosfile,
                use_interfaces, string_length, compression_level)

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
    load = readsingleband(plexosfile["/data/ST/interval/region/Load"])

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

    lineregions = readlines(plexosfile)

    if useplexosinterfaces

        interfaceregions = readinterfaces(plexosfile, lineregions)
        lines_core = interfaceregions[!, [:interface, :interface_category, :region1, :region2]]
        idx = interfaceregions.interface_idx

        forwardcapacity = readsingleband(
            plexosfile["/data/ST/interval/interface/Import Limit"], idxs)
        backwardcapacity = readsingleband(
            plexosfile["/data/ST/interval/interface/Export Limit"], idxs)

        λ = zeros(n_interfaces, n_timesteps)
        μ = ones(n_interfaces, n_timesteps)

    else

        lines_core = lineregions[!, [:line, :line_category, :region1, :region2]]
        idxs = lineregions.line_idx

        forwardcapacity = readsingleband(
            plexosfile["/data/ST/interval/line/Import Limit"], idxs)
        backwardcapacity = readsingleband(
            plexosfile["/data/ST/interval/line/Export Limit"], idxs)

        fors = readsingleband(plexosfile["/data/ST/interval/line/x"], idxs)
        mttrs = readsingleband(plexosfile["/data/ST/interval/line/y"], idxs)
        λ, μ = plexosoutages_to_transitionprobs(fors, mttrs, _timeperiod_length)

    end

    names!(lines_core, [:name, :category, :region1, :region2])

    interfaces_core = unique(lines[!, [:region1, :region2]])
    infinitecapacity = fill(
        typemax(UInt32), size(interfaces_core, 1), n_periods)

    # Save data to prasfile

    lines = g_create(prasfile, "lines")
    string_table!(lines, "_core", lines_core, stringlength)
    lines["forwardcapacity", "compress", compressionlevel] =
        round.(UInt32, forwardcapacity)
    lines["backwardcapacity", "compress", compressionlevel] =
        round.(UInt32, backwardcapacity)
    lines["failureprob", "compress", compressionlevel] = λ
    lines["repairprob", "compress", compressionlevel] = μ

    interfaces = g_create(prasfile, "interfaces")
    string_table!(interfaces, "_core", interfaces_core, stringlength)
    interfaces["forwardcapacity", "compress", compressionlevel] =
        infinitecapacity
    interfaces["backwardcapacity", "compress", compressionlevel] =
        infinitecapacity

    return

end

function readlines(f::HDF5File)

    lines = readcompound(
        f["/metadata/objects/line"],
        [:line, :line_category])
    lines.line_idx = 1:size(lines, 1)

    region_lines = readcompound(
        f["/metadata/relations/region_interregionallines"],
        [:region, :line])

    region_lines = join(lines, region_lines, on=:line, kind=:inner)

    result = by(region_lines, [:line, :line_category, :line_idx]) do d::AbstractDataFrame
        size(d, 1) != 2 && error("Unexpected Line data:\n$d")
        from, to = minmax(d[1, :region], d[2, :region])
        return from != to ?
            DataFrame(region1=from, region2=to) :
            DataFrame(region1=Int[], region2=Int[])
    end

    return result

end

function readinterfaces(f::HDF5File, line_regions::DataFrame)

    interfaces = readcompound(
        f["/metadata/objects/interface"],
        [:interface, :interface_category])
    interfaces.interface_idx = 1:size(interfaces, 1)

    interface_lines = readcompound(
        f["/metadata/relations/interface_lines"],
        [:interface, :line])

    interface_lines = join(interfaces, interface_lines, on=:interface, kind=:inner)
    interface_regions = join(interface_lines, line_regions, on=:line, kind=:inner)

    interfaces =
        by(interface_regions, [:interface, :interface_category, :interface_idx]
          ) do d::AbstractDataFrame
        from_tos = unique(zip(d[:region1], d[:region2]))
        return length(from_tos) == 1 ?
            DataFrame(region1=from_tos[1][1], region2=from_tos[1][2]) :
            DataFrame(region1=Int[], region2=Int[])
    end

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
