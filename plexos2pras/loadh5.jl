using Base.Dates
using DataFrames
using PyCall
@pyimport numpy as np
@pyimport h5py

function meta_dataframe(h5file::PyObject, path::String,
                        columns::Vector{Symbol}=Symbol[]::DataFrame)

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
            np.array(get(h5file, "metadata/times/ST")))
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

load_singlebanddata(h5file, path) = squeeze(h5file[path][1, :, :], 1)
