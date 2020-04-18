mutable struct PLEXOSWorkbook
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
    XLSX.writetable(filename, overwrite=true,
        Objects=(collect(eachcol(wb.objects)), names(wb.objects)),
        Categories=(collect(eachcol(wb.categories)), names(wb.categories)),
        Memberships=(collect(eachcol(wb.memberships)), names(wb.memberships)),
        Attributes=(collect(eachcol(wb.attributes)), names(wb.attributes)),
        Properties=(collect(eachcol(wb.properties)), names(wb.properties)),
        Reports=(collect(eachcol(wb.reports)), names(wb.reports)),
    )
    return
end

function add_object!(wb::PLEXOSWorkbook, class::String, name::String)
    push!(wb.objects, (class=class, name=name), cols=:subset)
    return
end

function remove_properties!(
    wb::PLEXOSWorkbook, collection::String, props::Vector{String})

    exclusions = DataFrame(collection=collection, property=props)

    wb.properties = join(
        wb.properties, exclusions, on=[:collection, :property], kind=:anti)

    return

end

function convert_properties!(
    wb::PLEXOSWorkbook, collection::String, props_raw::Vector{Pair{String,String}})

    props = Dict(props_raw)
    target_props = keys(props)

    for row in eachrow(wb.properties)
        if (row.collection == collection) && (row.property in target_props)
            row.property = props[row.property]
        end
    end

    return

end

function blanket_properties!(
    wb::PLEXOSWorkbook, class::String, collection::String,
    propvals::Vector{Pair{String,T}}) where T

    objects = wb.objects[wb.objects.class .== class, :name]

    for object in objects
        for propval in propvals
            push!(wb.properties,
                  (parent_class="System", child_class=class,
                   collection=collection,
                   parent_object="System", child_object=object,
                   property=propval.first, band_id=1, value=propval.second),
                  cols=:subset) 
        end
    end

    return

end

function report_properties!(
    wb::PLEXOSWorkbook, report::String, class::String, collection::String,
    props::Vector{String})

    reportrow = (
        object=report, parent_class="System", child_class=class,
        collection=collection, phase_id=4,
        report_period=true, report_summary=false, report_statistics=false,
        report_samples=false)

    for prop in props
        push!(wb.reports, (property=prop, reportrow...), cols=:subset)
    end

    return

end

function add_attributes!(
    wb::PLEXOSWorkbook, class::String, name::String,
    attrs_vals::Vector{Pair{String,T}}) where T

    for attrval in attrs_vals
        push!(wb.attributes,
              (class=class, name=name, attribute=attrval.first, value=attrval.second),
              cols=:subset)
    end

    return

end

function remove_attributes!(
    wb::PLEXOSWorkbook, class::String, attrs::Vector{String})

    exclusions = DataFrame(class=class, attribute=attrs)

    wb.attributes = join(
        wb.attributes, exclusions, on=[:class, :attribute], kind=:anti)

    return

end

function blanket_attributes!(
    wb::PLEXOSWorkbook, class::String, attrs_vals::Vector{Pair{String,T}}) where T

    objects = wb.objects[wb.objects.class .== class, :name]

    for object in objects
        for attrval in attrs_vals
            push!(wb.attributes,
                  (name=object, class=class,
                   attribute=attrval.first, value=attrval.second),
                  cols=:subset)
        end
    end

    return

end
