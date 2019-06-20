function loadh5(h5path::String, vg_categories::Vector{String},
                exclude_categories::Vector{String}, use_interfaces::Bool)

    # TODO: Would be nice to check that the necessary properties
    # are reported by PLEXOS before starting to load things in

    # Load metadata DataFrames
    timestamps, regions, generators, storages, lines, interfaces =
        load_metadata(h5path, exclude_categories, use_interfaces)

    regionnames = regions[:Region]

    vgs_idxs, disps_idxs = partition_generators(generators, vg_categories)

    vgs_region = join(generators, DataFrame(GeneratorIdx=vgs_idxs),
                      on=:GeneratorIdx, kind=:semi)[:RegionIdx]
    disps_region = join(generators, DataFrame(GeneratorIdx=disps_idxs),
                      on=:GeneratorIdx, kind=:semi)[:RegionIdx]

    storages = by(storages, [:StorageIdx, :Storage], sort=true) do d

        storname = d[1, :Storage]
        regions = unique(d[:Region])

        length(regions) > 1 && error(
            "All generators associated with a single storage device " *
            "should be in the same region, but device $storname had " *
            "generators in the regions $regions")

        return DataFrame(GeneratorIdxs=[d[:GeneratorIdx]], RegionIdx=d[1, :RegionIdx])

    end

    stors_idxs = storages[:StorageIdx]
    stors_gen_idxs = storages[:GeneratorIdxs]
    stors_region = storages[:RegionIdx]

    lines_idxs = lines[:LineIdx]
    lines_regions = tuple.(lines[:RegionFrom], lines[:RegionTo])

    interface_idxs = interfaces[:InterfaceIdx]
    interface_regions = tuple.(interfaces[:RegionFrom], interfaces[:RegionTo])

    # Load time series data
    (timestamps, demand, vgs_capacity, disps_capacity, disps_outagerate, disps_mttr,
     stors_capacity, stors_energy, stors_outagerate, stors_mttr,
     lines_capacity, lines_outagerate, lines_mttr, interface_capacity) =
        load_data(h5path, timestamps, vgs_idxs, disps_idxs, stors_idxs,
                  stors_gen_idxs, lines_idxs, interface_idxs, use_interfaces)

    return RawSystemData(
        timestamps, regionnames, demand, vgs_region, vgs_capacity,
        disps_region, disps_capacity, disps_outagerate, disps_mttr,
        stors_region, stors_capacity, stors_energy, stors_outagerate, stors_mttr,
        interface_regions, interface_capacity,
        lines_regions, lines_capacity, lines_outagerate, lines_mttr)

end

function load_metadata(h5path::String, excludes::Vector{String},
                       use_interfaces::Bool,
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

    generators = join(generators, DataFrame(GeneratorCategory=excludes),
                      on=:GeneratorCategory, kind=:anti)
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

    # Storage
    storages = meta_dataframe(
        h5file, "metadata/objects/storage",
        [:Storage, :StorageCategory, :StorageIdx])
    generator_storages = meta_dataframe(
        h5file, "metadata/relations/generator_headstorage",
        [:Generator, :Storage, :GSIdx])

    storages = join(storages, generator_storages, on=:Storage)
    storages = join(storages, generators, on=:Generator)

    # Remove storage devices from generators table
    generators = join(generators, generator_storages, on=:Generator, kind=:anti)

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

    if use_interfaces

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

        sort!(interfaces, :InterfaceIdx)

    else

        interfaces = DataFrame(InterfaceIdx=Int[], Interface=String[],
                               RegionFrom=Int[], RegionTo=Int[])

    end

    sort!(generators, :GeneratorIdx)
    sort!(storages, :StorageIdx)
    sort!(lines, :LineIdx)

    h5file.close()

    return timerange, regions, generators, storages, lines, interfaces

end

function partition_generators(gens::DataFrame, vgs::Vector{String})

    vg_idxs = Int[]
    disp_idxs = Int[]

    for (genidx, category) in zip(gens[:GeneratorIdx], gens[:GeneratorCategory])
        if category ∈ vgs
            push!(vg_idxs, genidx)
        else
            push!(disp_idxs, genidx)
        end
    end

    return vg_idxs, disp_idxs

end

load_data(h5path::String, timestamps::StepRange,
          vg_idxs::Vector{Int}, disp_idxs::Vector{Int},
          stor_idxs::Vector{Int}, stor_gen_idxs::Vector{<:AbstractVector{Int}},
          line_idxs::Vector{Int}, interface_idxs::Vector{Int},
          use_interfaces::Bool) =
    h5open(f -> load_data(f, timestamps, vg_idxs, disp_idxs, stor_idxs,
                          stor_gen_idxs, line_idxs, interface_idxs,
                          use_interfaces),
           h5path, "r")

function load_data(
    h5file::HDF5File, timestamps::StepRange, vg_idxs::Vector{Int},
    disp_idxs::Vector{Int}, stor_idxs::Vector{Int}, stor_gen_idxs::Vector{<:AbstractVector{Int}},
    line_idxs::Vector{Int}, interface_idxs::Vector{Int}, use_interfaces::Bool)

    demand = load_singlebanddata(h5file, "data/ST/interval/region/Load")
    # TODO: Is this up-to-date with latest h5plexos behaviour?
    keep_periods = .!isnan.(demand[:, 1])
    demand = demand[keep_periods, :]

    new_timestamps = timestamps[keep_periods]
    new_timestamps = first(new_timestamps):step(timestamps):last(new_timestamps)

    available_capacity = load_singlebanddata(
        h5file, "data/ST/interval/generator/Available Capacity", keep_periods)
    outagerate = load_singlebanddata(
        h5file, "data/ST/interval/generator/x", keep_periods)
    mttr = load_singlebanddata(
        h5file, "data/ST/interval/generator/y", keep_periods)

    vg_capacity = available_capacity[:, vg_idxs]

    disp_capacity = available_capacity[:, disp_idxs]
    disp_mttr = mttr[:, disp_idxs]
    disp_outagerate = outagerate[:, disp_idxs]

    # Combine all generators sharing a head storage into a single storage device
    # TODO: No mathematical justification for this, it's just convenient!
    #       Ideally there would be an explicit storage-generator mapping to
    #       obviate the need for collapsing generators down to a single device

    n_stors = length(stor_idxs)
    n_interfaces = length(interface_idxs)
    n_periods = length(new_timestamps)
    stor_capacity = fill(0., n_periods, n_stors)
    stor_outagerate = fill(-Inf, n_periods, n_stors)
    stor_mttr = fill(-Inf, n_periods, n_stors)

    for (s, sgis) in enumerate(stor_gen_idxs)
        for g in sgis
            stor_capacity[:, s] .+= available_capacity[:, g]
            stor_outagerate[:, s] .= max.(stor_outagerate[:, s], outagerate[:, g])
            stor_mttr[:, s] .= max.(stor_mttr[:, s], mttr[:, g])
        end
    end

    min_storage_energy = load_singlebanddata(
        h5file, "data/ST/interval/storage/Min Volume", keep_periods)[:, stor_idxs]
    max_storage_energy = load_singlebanddata(
        h5file, "data/ST/interval/storage/Max Volume", keep_periods)[:, stor_idxs]
    stor_energy = (max_storage_energy .- min_storage_energy) .* 1000 # Convert from GWh to MWh

    # TODO: Check Import/Export Limits and warn / take more conservative if not symmetrical
    line_capacity = load_singlebanddata(
        h5file, "data/ST/interval/line/Export Limit", keep_periods)[:, line_idxs]
    line_outagerate = load_singlebanddata(
        h5file, "data/ST/interval/line/x", keep_periods)[:, line_idxs]
    line_mttr = load_singlebanddata(
        h5file, "data/ST/interval/line/y", keep_periods)[:, line_idxs]

    if use_interfaces
        interface_capacity = load_singlebanddata(
           h5file, "data/ST/interval/interface/Export Limit",
           keep_periods)[:, interface_idxs]
    else
        interface_capacity = fill(NaN, n_periods, n_interfaces)
    end

    return (new_timestamps, demand, vg_capacity,
            disp_capacity, disp_outagerate, disp_mttr,
            stor_capacity, stor_energy, stor_outagerate, stor_mttr,
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

