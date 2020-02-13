function process_solution(
    inputpath_h5::String,
    outputpath_h5::String;
    timestep::Period=Hour(1),
    timezone::TimeZone=tz"UTC",
    exclude_categories::Vector{String}=String[],
    use_interfaces::Bool=false,
    charge_capacities::Bool=false,
    carryover_efficiencies::Bool=true,
    string_length::Int=64,
    compression_level::Int=1)

    xor(charge_capacities, carryover_efficiencies) ||
        @error("Only one of charge_capacities, carryover_efficiencies " *
               "can be selected as true.")

    h5open(inputpath_h5, "r") do plexosfile::HDF5File
        h5open(outputpath_h5, "w") do prasfile::HDF5File

            process_metadata!(
                prasfile, plexosfile, timestep, timezone)

            process_regions!(
                prasfile, plexosfile,
                string_length, compression_level)

            process_generators_storages!(
                prasfile, plexosfile, timestep,
                exclude_categories, charge_capacities,
                string_length, compression_level)

            process_lines_interfaces!(
                prasfile, plexosfile, timestep,
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

    # Save data to prasfile
    regions = g_create(prasfile, "regions")
    string_table!(regions, "_core", regiondata[!, [:name]], stringlength)
    regions["load", "compress", compressionlevel] = round.(UInt32, load)

    return

end
