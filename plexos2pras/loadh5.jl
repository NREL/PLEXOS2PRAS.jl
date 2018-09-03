using Base.Dates
using DataFrames
using PyCall
@pyimport numpy as np
@pyimport h5py

struct RawSystemData{T<:Period,V<:Real}

    timestamps::StepRange{DateTime, T}

    regionnames::Vector{String}
    demand::Matrix{V}

    vgregions::Vector{Int}
    vgcapacity::Matrix{V}

    dispregions::Vector{Int}
    dispcapacity::Matrix{V}
    dispoutagerate::Matrix{V}
    dispmttr::Matrix{V}

    interfaceregions::Vector{Int,Int}
    interfacecapacity::Matrix{V}

    lineregions::Vector{Int,Int}
    linecapacity::Matrix{V}
    lineoutagerate::Matrix{V}
    linemttr::Matrix{V}


    function RawSystemData{T,V}(
        timestamps::StepRange{DateTime,T},
        regionnames::Vector{String},
        demand::Matrix{V},
        vgregions::Vector{Int},
        vgcapacity::Matrix{V},
        dispregions::Vector{Int},
        dispcapacity::Matrix{V},
        dispoutagerate::Matrix{V},
        dispmttr::Matrix{V},
        interfaceregions::Vector{Int,Int},
        interfacecapacity::Matrix{V},
        lineregions::Vector{Int,Int},
        linecapacity::Matrix{V},
        lineoutagerate::Matrix{V},
        linemttr::Matrix{V}) where {T<:Period, V<:Real}

        # TODO: Sort regions, interfaces, lines by region and reorder data accordingly
        n_periods = length(timestamps)
        n_regions = length(regionnames)
        n_vg = length(vgregions)
        n_disp = length(dispregions)
        n_interfaces = length(interfaceregions)
        n_lines = length(lineregions)

        @assert size(demand) == (n_periods, n_regions)

        @assert size(vgcapacity) == (n_periods, n_vg)

        @assert size(dispcapacity) == (n_periods, n_disp)
        @assert size(dispoutagerate) == (n_periods, n_disp)
        @assert size(dispmttr) == (n_periods, n_disp)

        @assert size(interfacecapacity) == (n_periods, n_interfaces)

        @assert size(linecapacity) == (n_periods, n_lines)
        @assert size(lineoutagerate) == (n_periods, n_lines)
        @assert size(linemttr) == (n_periods, n_lines)

        new(timestamps, demand,
            vgregions, vgcapacity,
            dispregions, dispcapacity, dispoutagerate, dispmttr,
            interfaceregions, interfacecapacity,
            lineregions, linecapacity, lineoutagerate, linemttr)

    end

end

load_singlebanddata(h5file, path) = squeeze(h5file[path][1, :, :], 1)
load_singlebanddata(h5file, path, keepperiods) =
    load_singlebanddata(h5file, path)[keepperiods, :]

function meta_dataframe(h5file::PyObject, path::String,
                        columns::Vector{Symbol}=Symbol[])

    h5dset = get(h5file, path)
    colnames = collect(h5dset[:dtype][:names])
    cols = Any[Array{String}(get(h5dset, colname))
               for colname in colnames]

    result = DataFrame(cols, Symbol.(colnames))
    result[:idx] = 1:size(result, 1)

    length(columns) > 0 && names!(result, columns)

    return result

end

function load_metadata(inputpath_h5::String,
                       dtfmt::DateFormat=dateformat"d/m/y H:M:S")

    @pywith h5py.File(inputpath_h5, "r") as h5file begin

        # Load timestamps
        timestamps = Array{String}(
            np.array(get(h5file, "metadata/times/interval")))
        timestamps = DateTime.(timestamps, dtfmt)

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
                   d -> d[1, [:Region, :RegionCategory, :RegionIdx, :RGIdx]])
        end

        # Load line data and regional relations
        lines = meta_dataframe(
            h5file, "metadata/objects/lines",
            [:Line, :LineCategory, :LineIdx])
        regions_lines = meta_dataframe(
            h5file, "metadata/relations/region_interregionallines",
            [:Region, :Line])
        lines = join(lines, region_lines, on=:Line)
        lines = join(lines, regions, on=:Region)

        # Filter out intraregional lines and report region IDs
        # for interregional lines
        lines = by(lines, [:LineIdx, :Line]) do d::AbstractDataFrame

            size(d, 1) != 2 && error("Unexpected Line data:\n$d")

            from, to = minmax(d[1,:RegionIdx], d[2,:RegionIdx])
            from == to && return DataFrame(
                RegionFrom=Int[], RegionTo=Int[])

            return DataFrame(RegionFrom=from, RegionTo=to)

        end

        interfaces = meta_dataframe(
            h5file, "metadata/objects/interfaces",
            [:Interface, :InterfaceCategory, :InterfaceIdx])
        # TODO: Determine interface to/froms
        # region_generators = meta_dataframe(
        #     h5file, "metadata/relations/region_generators",
        #     [:Region, :Generator, :RGIdx])

        sort!(generators, :GeneratorIdx)
        sort!(lines, :LineIdx)

        return timerange, regions, generators, lines, interfaces

    end

end

function load_data(f::HDF5File, vg_idxs::Vector{Int},
                   disp_idxs::Vector{Int}, line_idxs::Vector{Int})

    demand = load_singlebanddata(h5file, "data/ST/interval/region/Load")
    keep_periods = .!isnan.(demand[:, 1])
    demand = demand[keep_periods, :]'

    available_capacity = load_singlebanddata(
        h5file, "data/ST/interval/generator/Available Capacity", keep_periods)

    vg_capacity = available_capacity[:, vg_idxs]

    disp_capacity = available_capacity[:, disp_idxs]
    disp_outagerate = load_singlebanddata(
        h5file, "data/ST/interval/generator/x", keep_periods)[:, disp_idxs]
    disp_mttr = load_singlebanddata(
        h5file, "data/ST/interval/generator/y", keep_periods)[:, disp_idxs]

    #TODO: Check Min Flows and warn / take more conservative if not symmetrical
    line_capacity = load_singlebanddata(
        h5file, "data/ST/interval/line/Max Flow", keep_periods)[:, line_idxs]
    line_outagerate = load_singlebanddata(
        h5file, "data/ST/interval/line/x", keep_periods)[:, line_idxs]
    line_mttr = load_singlebanddata(
        h5file, "data/ST/interval/line/y", keep_periods)[:, line_idxs]


    interface_capacity = load_singlebanddata(
        h5file, "data/ST/interval/interface/Max Flow", keep_periods)

    return (demand, vg_capacity,
            disp_capacity, disp_outagerate, disp_mttr,
            line_capacity, line_outagerate, line_mttr,
            interface_capacity)

end

load_data(h5file::String, isvg::Vector{Bool}) =
    h5open(f -> load_data(f, isvg), h5file, "r")

function partition_generators(gens::DataFrame, vgs::Vector{String},
                              excludes::Vector{String})

    vg_idxs = Int[]
    disp_idxs = Int[]

    for (genidx, category) in zip(gens[:GeneratorIdx], gens[:GeneratorCategory])
        if category ∉ excludes
            if category ∈ vg
                push!(vg_idxs, genidx)
            else
                push!(disp_idxs, genidx)
            end
        end
    end

    return vg_idxs, disp_idxs

end

function loadh5(h5path::String, vg_categories::Vector{String},
                exclude_categories::Vector{String})

    # TODO: Would be nice to check that the necessary properties
    # are reported before starting to load things in

    # Load metadata DataFrames
    timestamps, regions, generators, lines, interfaces = load_metadata(inputpath_h5)

    regionnames = regions[:Region]

    vg_idxs, disp_idxs = partition_generators(
        generators, vg_categories, exclude_categories)
    vg_regions = generators[vg_idxs, :RegionIdx]
    disp_regions = generators[disp_idxs, :RegionIdx]

    line_idxs = lines[:LineIdx]
    line_regions = tuple.(lines[:RegionFrom], lines[:RegionTo])

    # Load time series data
    (demand, vg_capacity, disp_capacity, disp_outagerate, disp_mttr,
     line_capacity, line_outagerate, line_mttr) =
        load_data(inputpath_h5, vg_idxs, disp_idxs, line_idxs)

    return RawSystemData(
        timestamps, regionnames, demand, vg_regions, vg_capacity,
        disp_regions, disp_capacity, disp_outagerate, disp_mttr,
        # interface_regions, interface_capacity,
        Int[], similar(line_capacity, length(timestamps), 0),
        line_regions, line_capacity, line_outagerate, lines_mttr)

end
