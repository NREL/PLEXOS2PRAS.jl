using ResourceAdequacy
using JLD

include("utils.jl")

outputpath = ARGS[1]
suffix = ARGS[2]
inputpaths = ARGS[3:end]

systemnames = extract_modelname.(inputpaths, suffix)

jldopen(outputpath, "w") do file

    addrequire(file, ResourceAdequacy)

    for (inputpath, systemname) in zip(inputpaths, systemnames)

        system = load(inputpath)[systemname]
        write(file, systemname, system)
        rm(inputpath)

    end

end
