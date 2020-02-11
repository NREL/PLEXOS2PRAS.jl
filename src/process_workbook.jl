function process_workbook(
    infile::String, outfile::Union{String,Nothing}=nothing;
    suffix::String="PRAS",
    charge_capacities::Bool=false, charge_efficiencies::Bool=true)

    xor(charge_capacities, charge_efficiencies) || @error(
        "Exactly one of charge_capacities, charge_efficiencies must be true")
    gen_z_property = charge_capacities ? "Pump Load" : "Pump Efficiency"

    suffix = "_" * suffix

    workbook = PLEXOSWorkbook(infile)
    return workbook

    remove_properties!(workbook, [("Generators", "x"),
                                  ("Generators", "y"),
                                  ("Generators", "z"),
                                  ("Generators", "Maintenance Rate"),
                                  ("Storages", "x"),
                                  ("Lines", "x"),
                                  ("Lines", "y"),
                                  ("Lines", "Maintenance Rate")])

    convert_properties!(workbook, "Generators",
                        "Forced Outage Rate" => "x",
                        "Mean Time to Repair" => "y",
                        gen_z_property => "z")

    convert_properties!(workbook, "Lines",
                        "Forced Outage Rate" => "x",
                        "Mean Time to Repair" => "y")

    convert_properties!(properties, "Storages",
                        "Loss Rate" => "x")

    blanket_properties!(workbook, "Generator", "Generators",
                        "Forced Outage Rate" => 0,
                        "Maintenance Rate" => 0,
                        "Mean Time to Repair" => 0)

    blanket_properties!(workbook, "Line", "Lines",
                        "Forced Outage Rate" => 0,
                        "Maintenance Rate" => 0,
                        "Mean Time to Repair" => 0)

    # New PRAS-specific ST object
    push!(workbook.objects, (class="ST Schedule", name=suffix), cols=:subset)
    push!(workbook.attributes,
          (class="ST Schedule", name=suffix, attribute="Transmission Detail", value=0),
          cols=:subset)
    push!(workbook.attributes,
          (class="ST Schedule", name=suffix, attribute="Stochastic Method", value=0),
          cols=:subset)


    # New PRAS-specific Report object

    reportrow(nt::NamedTuple) = (object=suffix, parent_class="System", phase_id=4,
           report_period=true, report_summary=false, report_statistics=false,
           report_samples=false, nt...)

    push!(workbook.objects, (class="Report", name=suffix), cols=:subset)

    push!(workbook.reports, reportrow(
              (child_class="Region", collection="Regions", property="Load")),
          cols=:subset)

    push!(workbook.reports, reportrow(
              (child_class="Interface", collection="Interfaces", property="Import Limit")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Interface", collection="Interfaces", property="Export Limit")),
          cols=:subset)

    push!(workbook.reports, reportrow(
              (child_class="Line", collection="Lines", property="Import Limit")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Line", collection="Lines", property="Export Limit")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Line", collection="Lines", property="x")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Line", collection="Lines", property="y")),
          cols=:subset)

    push!(workbook.reports, reportrow(
              (child_class="Generator", collection="Generators", property="Available Capacity")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Generator", collection="Generators", property="Installed Capacity")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Generator", collection="Generators", property="x")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Generator", collection="Generators", property="y")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Generator", collection="Generators", property="z")),
          cols=:subset)

    push!(workbook.reports, reportrow(
              (child_class="Storage", collection="Storages", property="Min Volume")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Storage", collection="Storages", property="Max Volume")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Storage", collection="Storages", property="Natural Inflow")),
          cols=:subset)
    push!(workbook.reports, reportrow(
              (child_class="Storage", collection="Storages", property="x")),
          cols=:subset)

    # Replace all existing Report memberships with new Report
    memberships.loc[memberships["child_class"] == "Report",
                    "child_object"] = new_obj_name

    # Add suffix to all Model names

    objects.loc[objects["class"] == "Model",
                "name"] .*= suffix

    memberships.loc[memberships["parent_class"] == "Model",
                    "parent_object"] .*= suffix

    attributes.loc[attributes["class"] == "Model",
                   "name"] .*= suffix

    remove_attributes!(workbook, [("Model", "Run Mode"),
                                  ("Model", "Output to Folder"),
                                  ("Model", "Write Input")])

    blanket_attributes!(workbook, "Model",
                        "Run Mode" => 1,
                        "Output to Folder" => -1,
                        "Write Input" => 0)

    outfile == nothing || writeworkbook(workbook, outfile)

    return workbook

end

struct PLEXOSWorkbook
    objects::DataFrame
    categories::DataFrame
    memberships::DataFrame
    attributes::DataFrame
    properties::DataFrame
    reports::DataFrame
end

PLEXOSWorkbook(filename::String) = XLSX.openxlsx(filename) do xf
    return PLEXOSWorkbook(
        map(sheet -> DataFrame(XLSX.gettable(xf[sheet])...),
        ["Objects", "Categories", "Memberships",
         "Attributes","Properties", "Reports"])...)
end

function writeworkbook(wb::PLEXOSWorkbook, filename::String)
    # TODO
end

function remove_properties!(
    wb::PLEXOSWorkbook, colls_props::Vector{Tuple{String,String}})

end

function convert_properties!()

end

function blanket_properties!()

end

function remove_attributes!()

end

function blanket_attributes!()

end
