function process_workbook(
    infile::String, outfile::Union{String,Nothing}=nothing;
    suffix::String="PRAS",
    charge_capacities::Bool=false, charge_efficiencies::Bool=true,
    pump_capacities::Bool=false, pump_efficiencies::Bool=true,
    battery_availabilities::Bool=false, battery_efficiencies::Bool=true)


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
        error("Only one of pump_capacities, pump_efficiencies " *
              "can be selected as true")

    gen_z_property = pump_capacities ? "Pump Load" : "Pump Efficiency"

    xor(battery_availabilities, battery_efficiencies) ||
        error("Only one of battery_availabilities, battery_efficiencies " *
              "can be selected as true")

    batt_x_property = battery_availabilities ?
        "Forced Outage Rate" : "Charge Efficiency"

    batt_y_property = battery_availabilities ?
        "Mean Time to Repair" : "Discharge Efficiency"

    disambiguator = "_" * suffix

    workbook = PLEXOSWorkbook(infile)

    # Remove property definitions that are to be replaced

    remove_properties!(workbook, "Generators", ["x", "y", "z", "Maintenance Rate"])
    remove_properties!(workbook, "Storages", ["x"])
    remove_properties!(workbook, "Batteries", ["x", "y", "z", "Maintenance Rate"])
    remove_properties!(workbook, "Lines", ["x", "y", "Maintenance Rate"])

    # Convert targeted property values to new property names

    convert_properties!(workbook, "Generators",
                        ["Forced Outage Rate" => "x",
                         "Mean Time to Repair" => "y"])

    copy_properties!(workbook, "Generators",
                     [gen_z_property => "z"])

    convert_properties!(workbook, "Batteries",
                        [batt_x_property => "x",
                         batt_y_property => "y"])

    copy_properties!(workbook, "Batteries",
                     ["Capacity" => "z"])

    convert_properties!(workbook, "Lines",
                        ["Forced Outage Rate" => "x",
                         "Mean Time to Repair" => "y"])

    copy_properties!(workbook, "Storages",
                        ["Loss Rate" => "x"])

    # Reset targeted properties to necessary values

    blanket_properties!(workbook, "Generator", "Generators",
                        ["Forced Outage Rate" => 0,
                         "Maintenance Rate" => 0,
                         "Mean Time to Repair" => 0])

    blanket_properties!(workbook, "Battery", "Batteries",
                        ["Forced Outage Rate" => 0,
                         "Maintenance Rate" => 0,
                         "Mean Time to Repair" => 0])

    blanket_properties!(workbook, "Line", "Lines",
                        ["Forced Outage Rate" => 0,
                         "Maintenance Rate" => 0,
                         "Mean Time to Repair" => 0])

    # Define new PRAS-specific ST object and associate with all models

    add_object!(workbook, "ST Schedule", disambiguator)

    add_attributes!(workbook, "ST Schedule", disambiguator,
                    ["Transmission Detail" => 0,
                     "Stochastic Method" => 0])

    workbook.memberships[
        workbook.memberships.child_class .== "ST Schedule",
        :child_object] .= disambiguator

    # Remove memberships to other phases (LT, PASA, MT)

    workbook.memberships = antijoin(
        workbook.memberships, DataFrame(child_class=["LT Plan", "PASA", "MT Schedule"]),
        on=:child_class)

    # Define new PRAS-specific Report object and associate with all models

    add_object!(workbook, "Report", disambiguator)

    report_properties!(
        workbook, disambiguator, "Region", "Regions",
        ["Load"])

    report_properties!(
        workbook, disambiguator, "Interface", "Interfaces",
        ["Import Limit", "Export Limit"])

    report_properties!(
        workbook, disambiguator, "Line", "Lines",
        ["Import Limit", "Export Limit", "x", "y"])

    report_properties!(
        workbook, disambiguator, "Generator", "Generators",
        ["Available Capacity", "Installed Capacity", "x", "y", "z"])

    report_properties!(
        workbook, disambiguator, "Storage", "Storages",
        ["Min Volume", "Max Volume", "Natural Inflow", "x"])

    report_properties!(
        workbook, disambiguator, "Battery", "Batteries",
        ["Units", "Installed Capacity", "x", "y", "z"])

    workbook.memberships[
        workbook.memberships.child_class .== "Report",
        :child_object] .= disambiguator

    # Add disambiguator to all Model names

    workbook.objects[
        workbook.objects.class .== "Model",
        :name] .*= disambiguator

    workbook.memberships[
        workbook.memberships.parent_class .== "Model",
        :parent_object] .*= disambiguator

    workbook.attributes[
        workbook.attributes.class .== "Model",
        :name] .*= disambiguator

    # Reset Model attributes

    remove_attributes!(workbook, "Model",
                       ["Run Mode", "Output to Folder", "Write Input"])

    blanket_attributes!(workbook, "Model",
                        ["Run Mode" => 1,
                         "Output to Folder" => -1,
                         "Write Input" => 0])

    outfile == nothing || writeworkbook(workbook, outfile)

    return workbook

end
