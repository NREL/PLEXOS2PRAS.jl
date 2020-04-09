function process_lines_interfaces!(
    prasfile::HDF5File, plexosfile::HDF5File, timestep::Period,
    useplexosinterfaces::Bool, stringlength::Int, compressionlevel::Int)

    lineregions = readlines(plexosfile)

    if useplexosinterfaces

        interfaceregions = readinterfaces(plexosfile, lineregions)
        lines_core = interfaceregions[!, [:interface, :interface_category, :region1, :region2]]
        idxs = interfaceregions.interface_idx

    else

        lines_core = lineregions[!, [:line, :line_category, :region1, :region2]]
        idxs = lineregions.line_idx

    end

    length(idxs) > 0 || return

    if useplexosinterfaces

        forwardcapacity = .- readsingleband(
            plexosfile["/data/ST/interval/interface/Import Limit"], idxs)
        backwardcapacity = readsingleband(
            plexosfile["/data/ST/interval/interface/Export Limit"], idxs)

        λ = zeros(size(forwardcapacity)...)
        μ = ones(size(forwardcapacity)...)

    else

        forwardcapacity = .- readsingleband(
            plexosfile["/data/ST/interval/line/Import Limit"], idxs)
        backwardcapacity = readsingleband(
            plexosfile["/data/ST/interval/line/Export Limit"], idxs)

        fors = readsingleband(plexosfile["/data/ST/interval/line/x"], idxs)
        mttrs = readsingleband(plexosfile["/data/ST/interval/line/y"], idxs)
        λ, μ = plexosoutages_to_transitionprobs(fors, mttrs, timestep)

    end

    rename!(lines_core, [:name, :category, :region_from, :region_to])

    interfaces_core = unique(lines_core[!, [:region_from, :region_to]])
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
        f["/metadata/objects/line"],
        [:line, :line_category])
    lines.line_idx = 1:size(lines, 1)

    region_lines = readcompound(
        f["/metadata/relations/region_interregionallines"],
        [:region, :line])

    region_lines = join(lines, region_lines, on=:line, kind=:inner)

    # TODO: Need to ensure correct flow directions respected!
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
