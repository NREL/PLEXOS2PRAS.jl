module PLEXOS2PRAS

using Base.Filesystem
using Dates
using PyCall
using HDF5
using DataFrames
using ResourceAdequacy
using JLD

const np = PyNULL()
const h5py = PyNULL()
const h5process = PyNULL()
const processworkbook = PyNULL()

function __init__()
    copy!(np, pyimport_conda("numpy", "numpy"))
    copy!(h5py, pyimport_conda("h5py", "h5py"))
    copy!(h5process, pyimport("h5plexos.process"))
    pushfirst!(PyVector(pyimport("sys")."path"), @__DIR__)
    copy!(processworkbook, pyimport("processworkbook"))
end

export process_workbook, process_solutions

# Excel input processing
include("process_workbook.jl")

# Zipfile output processing
include("RawSystemData.jl")
include("loadh5.jl")
include("process_solution.jl")
include("process_solutions.jl")

end
