using H5PLEXOS
using PLEXOS2PRAS
using PRAS

using Dates
using Test

@testset "PLEXOS2PRAS" begin
    include("toy/toy.jl")
    include("rts/rts.jl")
end
