function readsingleband(
    dset::HDF5.Dataset, resourceidxs::AbstractVector{Int}=Int[])

    rawdata = read(dset)
    datasize = size(rawdata)
    length(datasize) == 3 || error("Provided data was not three-dimensional")
    datasize[1] == 1 || error("Provided data was not single-band")

    data = reshape(rawdata, datasize[2:end])

    if length(resourceidxs) > 0
        data = data[:, resourceidxs]
    end

    return permutedims(data)

end

# Read to DataFrame

readcompound(d::HDF5.Dataset, colnames::Vector{Symbol}=Symbol[]) =
    readcompound(read(d), colnames)

function readcompound(
    rawdata::Vector{<:NamedTuple}, colnames::Vector{Symbol}) where C

    # If no colnames specified, use the default ones
    if length(colnames) == 0
        colnames = collect(keys(rawdata[1]))
    end

    return DataFrame((col => readvector(rawdata, i) for (i, col) in enumerate(colnames))...)

end

# Write from DataFrame

function string_table!(
    f::HDF5.Group, tablename::String,
    data::DataFrame, strlen::Int)

    nrows, ncols = size(data)

    stringtype_id = HDF5.API.h5t_copy(HDF5.hdf5_type_id(String))
    HDF5.API.h5t_set_size(stringtype_id, strlen)
    stringtype = HDF5.Datatype(stringtype_id)

    dt_id = HDF5.API.h5t_create(HDF5.API.H5T_COMPOUND, ncols * strlen)
    for (i, colname) in enumerate(string.(names(data)))
        HDF5.API.h5t_insert(dt_id, colname, (i-1)*strlen, stringtype)
    end

    rawdata = UInt8.(vcat(vec(convertstring.(
        permutedims(Matrix{String}(data)), strlen)
    )...))

    dset = create_dataset(f, tablename, HDF5.Datatype(dt_id),
                          HDF5.dataspace((nrows,)))
    HDF5.API.h5d_write(
        dset, dt_id, HDF5.API.H5S_ALL, HDF5.API.H5S_ALL, HDF5.API.H5P_DEFAULT, rawdata)

    return

end

function convertstring(s::AbstractString, strlen::Int)

    oldstring = ascii(s)
    newstring = fill('\0', strlen)

    for i in 1:min(length(oldstring), length(newstring))
        newstring[i] = oldstring[i]
    end

    return newstring

end

function plexosoutages_to_transitionprobs(
    for_raw::Matrix{V}, mttr_raw::Matrix{V}, timestep::T,
) where {V <: Real, T <: Period}

    # From PLEXOS, raw MTTR is in hours, raw FOR is a percentage

    mttrs = mttr_raw .* conversionfactor(Hour, T) ./ timestep.value

    μ = 1 ./ mttrs
    μ[mttrs .== 0] .= one(V) # Interpret zero MTTR as μ = 1.

    fors = for_raw ./ 100
    λ = μ .* fors ./ (1 .- fors)
    λ[fors .== 0] .= zero(V) # Interpret zero FOR as λ = 0.

    return λ, μ

end

function carryoverefficiency_conversion(
    carryoverefficiency_raw::Matrix{V}, timestep::T
) where {V <: Real, T <: Period}
    # From PLEXOS, carryover efficiency (actually loss rate) is in % per hour
    factor = timestep.value / conversionfactor(Hour, T)
    return carryoverefficiency_raw .^ factor
end
