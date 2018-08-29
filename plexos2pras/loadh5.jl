using Base.Dates
using DataFrames
using PyCall
@pyimport numpy as np
@pyimport h5py

struct RawSystemData{T<:Period,V<:Real}

    timestamps::StepRange{DateTime, T}

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
        timestamps::StepRange{DateTime,T}
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
        linemttr::Matrix{V}) where {T<:Period, V<:Real}

        n_periods = length(timestamps)
        n_regions = length(regions)
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
                        columns::Vector{Symbol}=Symbol[])::DataFrame

    h5dset = get(h5file, path)
    colnames = collect(h5dset[:dtype][:names])
    cols = Any[Array{String}(get(h5dset, colname))
               for colname in colnames]

    result = DataFrame(cols, Symbol.(colnames))
    result[:idx] = 1:size(result, 1)

    length(columns) > 0 && names!(result, columns)

    return result

end

function load_metadata(inputpath_h5::String)

    @pywith h5py.File(inputpath_h5, "r") as h5file begin

        # Load timestamps
        timestamps = Array{String}(
            np.array(get(h5file, "metadata/times/interval")))
        timestamps = DateTime.(timestamps, dateformat"d/m/y H:M:S")

        regions = meta_dataframe(h5file,
                                "metadata/objects/region",
                                [:Region, :RegionCategory, :RegionIdx])

        # Generation
        generators = meta_dataframe(h5file,
                                    "metadata/objects/generator",
                                    [:Generator, :GeneratorCategory, :GeneratorIdx])
        region_generators = meta_dataframe(h5file,
                                        "metadata/relations/region_generators",
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

        # Transmission
        parentregions = copy(regions)
        names!(parentregions, [:ParentRegion, :ParentRegionCategory,
                               :ParentRegionIdx])

        childregions = copy(regions)
        names!(childregions, [:ChildRegion, :ChildRegionCategory, :ChildRegionIdx])

        region_regions = meta_dataframe(h5file,
                                        "metadata/relations/region_regions",
                                        [:ParentRegion, :ChildRegion, :RRIdx])

        region_regions = join(region_regions, parentregions, on=:ParentRegion)
        region_regions = join(region_regions, childregions, on=:ChildRegion)
        sort!(region_regions, :RRIdx)

        return timestamps, generators, region_regions

    end

end

function load_data(f::HDF5File, isvg::Vector{Bool})

    notvg = .!isvg

    demand = load_singlebanddata(h5file, "data/ST/interval/region/Load")
    keep_periods = .!isnan.(demand[:, 1])
    demand = demand[keep_periods, :]'

    # transfers = load_singlebanddata(
    #     h5file,
    #     "data/ST/interval/line/Max Flow",
    #     keep_periods)

    available_capacity = load_singlebanddata(
        h5file, "data/ST/interval/generator/Available Capacity", keep_periods)
    vg_capacity = available_capacity[:, isvg]
    dispatchable_capacity = available_capacity[:, notvg]

    outagerate = load_singlebanddata(
        h5file, "data/ST/interval/generator/x", keep_periods)[:, notvg] ./ 100
    mttr = load_singlebanddata(
        h5file, "data/ST/interval/generator/y", keep_periods)[:, notvg]

    return demand, vg_capacity, dispatchable_capacity, outagerate, mttr

end

load_data(h5file::String, isvg::Vector{Bool}) =
    h5open(f -> load_data(f, isvg), h5file, "r")

function loadh5(h5path::String)

    # TODO: Would be nice to check that the necessary properties
    # are reported before starting to load things in
    vgcategory(x::String) = x in vg_categories
    tstamps, generators, region_regions = load_metadata(inputpath_h5)
    isvg = vgcategory.(generators[:GeneratorCategory])
    _, _ = load_data(inputpath_h5, isvg)

    #TODO: Support importing arbitrary interval lengths from PLEXOS
    if tstamps[1] + Hour(1) != tstamps[2]
        warn("The importer currently assumes your PLEXOS intervals are hourly" *
            " but this doesn't seem to be the case with your data. Time-related" *
            " reliability metrics, units, and timestamps will likely be incorrect.")
    end

    return RawSystemData()

end
