function process_lines_interfaces!(
    prasfile::HDF5File, plexosfile::HDF5File, timestep::Period,
    useplexosinterfaces::Bool, stringlength::Int, compressionlevel::Int)

    lineregions = readlines(plexosfile)

    if useplexosinterfaces

        interfaceregions = readinterfaces(plexosfile, lineregions)
        lines_core = interfaceregions[!, [:interface, :interface_category,
                                          :region_from, :region_to]]
        idxs = interfaceregions.interface_idx

    else

        lines_core = lineregions[!, [:line, :line_category,
                                     :region_from, :region_to]]
        idxs = lineregions.line_idx

    end

    length(idxs) > 0 || return

    if useplexosinterfaces

        # TODO: How to respect intended reference direction?
        forwardcapacity = .- readsingleband(
            plexosfile["/data/ST/interval/interfaces/Import Limit"], idxs)
        backwardcapacity = readsingleband(
            plexosfile["/data/ST/interval/interfaces/Export Limit"], idxs)

        λ = zeros(size(forwardcapacity)...)
        μ = ones(size(forwardcapacity)...)

    else

        forwardcapacity = .- readsingleband(
            plexosfile["/data/ST/interval/lines/Import Limit"], idxs)
        backwardcapacity = readsingleband(
            plexosfile["/data/ST/interval/lines/Export Limit"], idxs)

        fors = readsingleband(plexosfile["/data/ST/interval/lines/x"], idxs)
        mttrs = readsingleband(plexosfile["/data/ST/interval/lines/y"], idxs)
        λ, μ = plexosoutages_to_transitionprobs(fors, mttrs, timestep)

    end

    rename!(lines_core, [:name, :category, :region_from, :region_to])

    int_regions = unique(minmax(r.region_from, r.region_to)
                         for r in eachrow(lines_core))
    interfaces_core = DataFrame(
        region_from=first.(int_regions), region_to=last.(int_regions))

    infinitecapacity = fill(
        typemax(UInt32), size(interfaces_core, 1), size(forwardcapacity, 2))

    # Save data to prasfile

    lines = g_create(prasfile, "lines")
    string_table!(lines, "_core", lines_core, stringlength)
    lines["forwardcapacity", "compress", compressionlevel] =
        round.(UInt32, forwardcapacity)
    lines["backwardcapacity", "compress", compressionlevel] =
        round.(UInt32, backwardcapacity)
    lines["failureprobability", "compress", compressionlevel] = λ
    lines["repairprobability", "compress", compressionlevel] = μ

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
        f["/metadata/objects/lines"],
        [:line, :line_category])
    lines.line_idx = 1:size(lines, 1)

    region_froms = readcompound(
        f["/metadata/relations/region_exportinglines"],
        [:region_from, :line])

    region_tos = readcompound(
        f["/metadata/relations/region_importinglines"],
        [:region_to, :line])

    lines = innerjoin(lines, region_froms, on=:line)
    lines = innerjoin(lines, region_tos, on=:line)

    return lines

end

"""
Read in PLEXOS interfaces (to be treated as PRAS lines)
"""
function readinterfaces(f::HDF5File, line_regions::DataFrame)

    interfaces = readcompound(
        f["/metadata/objects/interfaces"],
        [:interface, :interface_category])
    interfaces.interface_idx = 1:size(interfaces, 1)

    interface_lines = readcompound(
        f["/metadata/relations/interfaces_lines"],
        [:interface, :line])

    interface_lines = innerjoin(interfaces, interface_lines, on=:interface)
    interface_regions = innerjoin(interface_lines, line_regions, on=:line)

    # TODO: Need better checks that the from->to definition aligns with
    #       intended directional flow limits
    interfaces =
        combine(groupby(
            interface_regions, [:interface, :interface_category, :interface_idx])
          ) do d::AbstractDataFrame

        from_to = minmax(d[1, :region_from], d[1, :region_to])

        for r in eachrow(d)
            if minmax(r.region_from, r.region_to) != from_to
                name = r.interface
                @warn("Interface $name is not strictly biregional and " *
                      "will be ignored")
                return DataFrame()
            end
        end

        return DataFrame(region_from=from_to[1], region_to=from_to[2])

    end

end
