module PLEXOS2PRAS

import Dates: Day, Hour, Minute, Second
import TimeZones: ZonedDateTime, @tz
import PyCall: pyimport, PyNULL, PyVector
import HDF5: h5open, read
using DataFrames
import PRASBase: unitsymbol

const processworkbook = PyNULL()

function __init__()
    # TODO: Port this to Julia and eliminate PyCall dependency
    # (the overall import workflow will still use h5plexos but
    #  it won't need to talk to Julia)
    pushfirst!(PyVector(pyimport("sys")."path"), @__DIR__)
    copy!(processworkbook, pyimport("processworkbook"))
end

export process_plexosworkbook, process_plexossolution

include("utils.jl")

# Excel input processing
include("process_workbook.jl")

# Zipfile output processing
include("RawSystemData.jl")
include("loadh5.jl")
include("process_solution.jl")

end
