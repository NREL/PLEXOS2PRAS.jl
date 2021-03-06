function process_solution(
    inputpath_h5::String,
    outputpath_h5::String;
    timestep::Period=Hour(1),
    timezone::TimeZone=tz"UTC",
    exclude_categories::Vector{String}=String[],
    use_interfaces::Bool=false,
    charge_capacities::Bool=false, charge_efficiencies::Bool=true,
    pump_capacities::Bool=false, pump_efficiencies::Bool=true,
    battery_availabilities::Bool=false, battery_efficiencies::Bool=true,
    string_length::Int=64,
    compression_level::Int=1)

    # Set pump options based on old charge options, if needed.
    # Can be removed along with charge options in PLEXOS2PRAS 0.6

    if charge_capacities
        @warn("The charge_capacities option is deprecated, " *
              "use pump_capacities instead")
        pump_capacities = true
    end

    if !charge_efficiencies
        @warn("The charge_efficiencies option is deprecated, " *
              "use pump_efficiencies instead")
        pump_efficiencies = false
    end

    # Check mutually-exclusive options are respected

    xor(pump_capacities, pump_efficiencies) ||
        error("Exactly one of pump_capacities, pump_efficiencies " *
              "must be selected as true")

    xor(battery_availabilities, battery_efficiencies) ||
        error("Exactly one of battery_availabilities, battery_efficiencies " *
              "must be selected as true")

    h5open(inputpath_h5, "r") do plexosfile::HDF5.File
        h5open(outputpath_h5, "w") do prasfile::HDF5.File

            process_metadata!(
                prasfile, plexosfile, timestep, timezone)

            n_regions = process_regions!(
                prasfile, plexosfile,
                string_length, compression_level)

            process_generators_storages!(
                prasfile, plexosfile, timestep,
                exclude_categories, pump_capacities, battery_availabilities,
                string_length, compression_level)

            n_regions > 1 && process_lines_interfaces!(
                prasfile, plexosfile, timestep,
                use_interfaces, string_length, compression_level)

        end
    end

    return

end

function process_metadata!(
    prasfile::HDF5.File,
    plexosfile::HDF5.File,
    timestep::Period,
    timezone::TimeZone)

    version_message = "Only H5PLEXOS v0.6 files are supported"
    if haskey(attributes(plexosfile), "h5plexos")
        version = read(attributes(plexosfile)["h5plexos"])
        version_match = match(r"^v0.6.\d+$", version)
        isnothing(version_match) && error(version_message * ", got " * version)
    else
        error(version_message)
    end

    attrs = attributes(prasfile)

    attrs["pras_dataversion"] = "v0.6.0"

    # TODO: Are other values possible for these units?
    attrs["power_unit"] = "MW"
    attrs["energy_unit"] = "MWh"

    dset = plexosfile["data/ST/interval/regions/Load"]
    offset = read(attributes(dset)["period_offset"])
    timestamp_range = offset .+ (1:size(dset, 2))

    timestamps_raw = read(plexosfile["metadata/times/interval"])[timestamp_range]
    timestamps = ZonedDateTime.(
        DateTime.(timestamps_raw, dateformat"yyyy-mm-ddTHH:MM:SS"), timezone)

    all(timestamps[1:end-1] .+ timestep .== timestamps[2:end]) ||
        error("PLEXOS result timestep durations did not " *
              "all match provided timestep ($timestep)")

    attrs["start_timestamp"] = string(first(timestamps))
    attrs["timestep_count"] = length(timestamps)
    attrs["timestep_length"] = timestep.value
    attrs["timestep_unit"] = unitsymbol(typeof(timestep))

    return

end

function process_regions!(
    prasfile::HDF5.File, plexosfile::HDF5.File,
    stringlength::Int, compressionlevel::Int)

    # Load required data from plexosfile
    regiondata = readcompound(plexosfile["/metadata/objects/regions"])
    load = readsingleband(plexosfile["/data/ST/interval/regions/Load"])

    n_regions = size(regiondata, 1)

    # Save data to prasfile
    regions = create_group(prasfile, "regions")
    string_table!(regions, "_core", regiondata[!, [:name]], stringlength)
    regions["load", compress=compressionlevel] = round.(UInt32, load)

    return n_regions

end
