function loadh5(h5path::String, vg_categories::Vector{String},
                exclude_categories::Vector{String})

    # TODO: Would be nice to check that the necessary properties
    # are reported by PLEXOS before starting to load things in

    # Load metadata DataFrames
    timestamps, regions, generators, lines, interfaces = load_metadata(h5path)

    regionnames = regions[:Region]

    vgs_idxs, disps_idxs = partition_generators(
        generators, vg_categories, exclude_categories)
    vgs_region = generators[vgs_idxs, :RegionIdx]
    disps_region = generators[disps_idxs, :RegionIdx]

    lines_idxs = lines[:LineIdx]
    lines_regions = tuple.(lines[:RegionFrom], lines[:RegionTo])

    interface_idxs = interfaces[:InterfaceIdx]
    interface_regions = tuple.(interfaces[:RegionFrom], interfaces[:RegionTo])

    # Load time series data
    (timestamps, demand, vgs_capacity, disps_capacity, disps_outagerate, disps_mttr,
     lines_capacity, lines_outagerate, lines_mttr, interface_capacity) =
        load_data(h5path, timestamps, vgs_idxs, disps_idxs, lines_idxs, interface_idxs)

    return RawSystemData(
        timestamps, regionnames, demand, vgs_region, vgs_capacity,
        disps_region, disps_capacity, disps_outagerate, disps_mttr,
        interface_regions, interface_capacity,
        lines_regions, lines_capacity, lines_outagerate, lines_mttr)

end

function load_metadata(h5file::PyObject, dtfmt::DateFormat)

end
function load_metadata(h5path::String,
                       dtfmt::DateFormat=dateformat"d/m/y H:M:S")

    h5file = h5py.File(h5path, "r")

    # Load timestamps
    timestamps = DateTime.(
        PyVector(np.array(get(h5file, "metadata/times/interval"))), dtfmt)

    #TODO: Support importing arbitrary interval lengths from PLEXOS
    if timestamps[1] + Hour(1) != timestamps[2]
        warn("The importer currently assumes your PLEXOS intervals are hourly" *
            " but this doesn't seem to be the case with your data. Time-related" *
            " reliability metrics, units, and timestamps will likely be incorrect.")
    end

    timerange = first(timestamps):Hour(1):last(timestamps)

    regions = meta_dataframe(
        h5file, "metadata/objects/region",
        [:Region, :RegionCategory, :RegionIdx])

    # Generation
    generators = meta_dataframe(
        h5file, "metadata/objects/generator",
        [:Generator, :GeneratorCategory, :GeneratorIdx])
    region_generators = meta_dataframe(
        h5file, "metadata/relations/region_generators",
        [:Region, :Generator, :RGIdx])

    generators = join(generators, region_generators, on=:Generator)
    generators = join(generators, regions, on=:Region)

    # Ensure no duplicated generators (if so, just pick the first region)
    if !allunique(generators[:GeneratorIdx])
        generators =
            by(generators,
               [:Generator, :GeneratorCategory, :GeneratorIdx],
               d -> (Region=d[1, :Region], RegionCategory=d[1, :RegionCategory],
                     RegionIdx=d[1, :RegionIdx], RGIdx=d[1, :RGIdx]))
    end

    # Load line data and regional relations
    lines = meta_dataframe(
        h5file, "metadata/objects/line",
        [:Line, :LineCategory, :LineIdx])
    regions_lines = meta_dataframe(
        h5file, "metadata/relations/region_interregionallines",
        [:Region, :Line, :RLIdx])
    lines = join(lines, regions_lines, on=:Line)
    lines = join(lines, regions, on=:Region)

    # Filter out intraregional lines and report region IDs
    # for interregional lines
    lines = by(lines, [:LineIdx, :Line]) do d::AbstractDataFrame

        size(d, 1) != 2 && error("Unexpected Line data:\n$d")

        from, to = minmax(d[1,:RegionIdx], d[2,:RegionIdx])
        return from == to ?
            DataFrame(RegionFrom=Int[], RegionTo=Int[]) :
            DataFrame(RegionFrom=from, RegionTo=to)

    end

    interfaces = meta_dataframe(
       h5file, "metadata/objects/interface",
       [:Interface, :InterfaceCategory, :InterfaceIdx])

    interface_lines = meta_dataframe(
        h5file, "metadata/relations/interface_lines",
        [:Interface, :Line, :ILIdx])

    # Filter out interfaces that aren't comprised of lines between two exclusive regions
    interface_lines = join(interfaces, interface_lines, on=:Interface, kind=:inner)
    interface_regions = join(interface_lines, lines, on=:Line, kind=:inner)
    interfaces = by(interface_regions, [:InterfaceIdx, :Interface]) do d::AbstractDataFrame
        from_tos = unique(zip(d[:RegionFrom], d[:RegionTo]))
        # TODO: Warn about interfaces that are dropped?
        return length(from_tos) == 1 ?
            DataFrame(RegionFrom=from_tos[1][1], RegionTo=from_tos[1][2]) :
            DataFrame(RegionFrom=Int[], RegionTo=Int[])
    end

    sort!(generators, :GeneratorIdx)
    sort!(lines, :LineIdx)
    sort!(interfaces, :InterfaceIdx)

    h5file.close()

    return timerange, regions, generators, lines, interfaces

end

function partition_generators(gens::DataFrame, vgs::Vector{String},
                              excludes::Vector{String})

    vg_idxs = Int[]
    disp_idxs = Int[]

    for (genidx, category) in zip(gens[:GeneratorIdx], gens[:GeneratorCategory])
        if category ∉ excludes
            if category ∈ vgs
                push!(vg_idxs, genidx)
            else
                push!(disp_idxs, genidx)
            end
        end
    end

    return vg_idxs, disp_idxs

end

load_data(h5path::String, timestamps::StepRange,
          vg_idxs::Vector{Int}, disp_idxs::Vector{Int},
          line_idxs::Vector{Int}, interface_idxs::Vector{Int}) =
    h5open(f -> load_data(f, timestamps, vg_idxs, disp_idxs,
                          line_idxs, interface_idxs), h5path, "r")

function load_data(h5file::HDF5File, timestamps::StepRange,
                   vg_idxs::Vector{Int}, disp_idxs::Vector{Int},
                   line_idxs::Vector{Int}, interface_idxs::Vector{Int})

    demand = load_singlebanddata(h5file, "data/ST/interval/region/Load")
    keep_periods = .!isnan.(demand[:, 1])
    demand = demand[keep_periods, :]

    new_timestamps = timestamps[keep_periods]
    new_timestamps = first(new_timestamps):step(timestamps):last(new_timestamps)

    available_capacity = load_singlebanddata(
        h5file, "data/ST/interval/generator/Available Capacity", keep_periods)

    vg_capacity = available_capacity[:, vg_idxs]

    disp_capacity = available_capacity[:, disp_idxs]
    disp_outagerate = load_singlebanddata(
        h5file, "data/ST/interval/generator/x", keep_periods)[:, disp_idxs]
    disp_mttr = load_singlebanddata(
        h5file, "data/ST/interval/generator/y", keep_periods)[:, disp_idxs]

    # TODO: Check Import/Export Limits and warn / take more conservative if not symmetrical
    line_capacity = load_singlebanddata(
        h5file, "data/ST/interval/line/Export Limit", keep_periods)[:, line_idxs]
    line_outagerate = load_singlebanddata(
        h5file, "data/ST/interval/line/x", keep_periods)[:, line_idxs]
    line_mttr = load_singlebanddata(
        h5file, "data/ST/interval/line/y", keep_periods)[:, line_idxs]

    interface_capacity = load_singlebanddata(
       h5file, "data/ST/interval/interface/Export Limit", keep_periods)[:, interface_idxs]

    return (new_timestamps, demand, vg_capacity,
            disp_capacity, disp_outagerate, disp_mttr,
            line_capacity, line_outagerate, line_mttr,
            interface_capacity)

end

function meta_dataframe(h5file::PyObject, path::String,
                        columns::Vector{Symbol}=Symbol[])

    h5dset = get(h5file, path)
    colnames = collect(h5dset.dtype.names)
    cols = Any[Array{String}(PyVector(get(h5dset, colname)))
               for colname in colnames]

    result = DataFrame(cols, Symbol.(colnames))
    result[:idx] = 1:size(result, 1)

    length(columns) > 0 && names!(result, columns)

    return result

end

load_singlebanddata(h5file, path) = dropdims(h5file[path][1, :, :], dims=1)
load_singlebanddata(h5file, path, keepperiods) =
    load_singlebanddata(h5file, path)[keepperiods, :]

