# Read to DataFrame

readcompound(d::HDF5.HDF5Dataset) = readcompound(read(d))

function readcompound(rawdata::Vector{HDF5.HDF5Compound{C}}) where C

    nrows = length(rawdata)
    firstrow = first(rawdata)

    result = DataFrame(
        (Symbol(string(firstrow.membername[c])) =>
        Vector{firstrow.membertype[c]}(undef, nrows) for c in 1:C)...,
        copycols=false)

    for i in 1:nrows
        result[i, :] = rawdata[i].data
    end

    return result

end

# Write from DataFrame

function string_table!(
    f::HDF5Group, tablename::String,
    data::DataFrame, strlen::Int)

    nrows, ncols = size(data)

    stringtype_id = HDF5.h5t_copy(HDF5.hdf5_type_id(String))
    HDF5.h5t_set_size(stringtype_id, strlen)
    stringtype = HDF5.HDF5Datatype(stringtype_id)

    dt_id = HDF5.h5t_create(HDF5.H5T_COMPOUND, ncols * strlen)
    for (i, colname) in enumerate(string.(names(data)))
        HDF5.h5t_insert(dt_id, colname, (i-1)*strlen, stringtype)
    end

    rawdata = UInt8.(vcat(vec(convertstring.(
        permutedims(Matrix{String}(data)), strlen)
    )...))

    dset = HDF5.d_create(f, tablename, HDF5.HDF5Datatype(dt_id),
                    HDF5.dataspace((nrows,)))
    HDF5.h5d_write(
        dset, dt_id, HDF5.H5S_ALL, HDF5.H5S_ALL, HDF5.H5P_DEFAULT, rawdata)

    return

end

convertstring(s::AbstractString, strlen::Int) =
    Vector{Char}.(rpad(ascii(s), strlen, '\0')[1:strlen])
