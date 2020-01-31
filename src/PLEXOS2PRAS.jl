module PLEXOS2PRAS

import Dates: @dateformat_str, DateTime, Hour, Period
import DataFrames: AbstractDataFrame, by, DataFrame
import TimeZones: TimeZone, @tz_str, ZonedDateTime
import PyCall: pyimport, PyNULL, PyVector
import HDF5
import HDF5: attrs, g_create, h5open, HDF5File, HDF5Group, read
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
include("process_workbook.jl")

include("process_generators_storages.jl")
include("process_lines_interfaces.jl")
include("process_solution.jl")

end
