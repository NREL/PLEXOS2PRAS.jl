function string_table!(
    f::HDF5Group,
    tablename::String, colnames::Vector{String},
    data::Matrix{<:AbstractString}, strlen::Int)

    ncols = size(data, 1)
    nrows = size(data, 2)

    length(colnames) == ncols ||
        error("Column names do not match matrix dimensions")

    stringtype_id = HDF5.h5t_copy(HDF5.hdf5_type_id(String))
    HDF5.h5t_set_size(stringtype_id, strlen)
    stringtype = HDF5.HDF5Datatype(stringtype_id)

    dt_id = HDF5.h5t_create(HDF5.H5T_COMPOUND, ncols * strlen)
    for (i, colname) in enumerate(colnames)
        HDF5.h5t_insert(dt_id, colname, (i-1)*strlen, stringtype)
    end

    rawdata = UInt8.(vcat(vec(convertstring.(data, strlen))...))

    dset = HDF5.d_create(f, tablename, HDF5.HDF5Datatype(dt_id),
                    HDF5.dataspace((nrows,)))
    HDF5.h5d_write(
        dset, dt_id, HDF5.H5S_ALL, HDF5.H5S_ALL, HDF5.H5P_DEFAULT, rawdata)

end

convertstring(s::AbstractString, strlen::Int) =
    Vector{Char}.(rpad(ascii(s), strlen, '\0')[1:strlen])

#readcompound(x::HDF5.HDF5Compound) = (; zip(Symbol(x.membername), x.data)...)
