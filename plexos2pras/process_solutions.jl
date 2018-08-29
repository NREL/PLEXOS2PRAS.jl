using ArgParse

include("process_solution.jl")

function parse_commandline(args::Vector{String}=ARGS)

    s = ArgParseSettings()
    @add_arg_table s begin
        "inputdir"
            help = "Path to the PLEXOS directory containing the solution " *
            "directories to be searched/processed"
            action = :store_arg
            arg_type = String
            required = true
        "outputfile"
            help = "Name of the JLD file to store processed PRAS systems"
            action = :store_arg
            arg_type = String
            required = true
        "--parallel", "-p"
            help = "Maximum number of PLEXOS solution files to process in parallel"
            action = :store_arg
            arg_type = Int
            default = 1
        "--suffix", "-s"
            help = "Model name suffix identifying results to be read in to PRAS"
            action = :store_arg
            arg_type = String
            default = "PRAS"
        "--vg"
            help = "Generator categories to be considered as VG instead of dispatchable"
            action = :store_arg
            nargs = '*'
            arg_type = String
        "--exclude"
            help = "Generator categories to omit from the processed PRAS systems"
            action = :store_arg
            nargs = '*'
            arg_type = String
        "--useinterfaces"
            help = "Use biregional interfaces to define interregional transfer limits, " *
            "instead of using interregional lines"
            action = :store_true
    end

    return parse_args(args, s)

end

function process_solutions(
    inputdir::String, outputfile::String, nparalllel::Int, suffix::String,
    vg::Vector{String}, exclude::Vector{String}, useinterfaces::Bool;
    persist::Bool=false)

    # Find relevant solutions and report that they're being processed
    inputfiles = _
    println(length(inputfiles), " solution files will be processed:\n",
            join(filepaths, "\n"))

    # Process systems
    systems = Dict(pmap(
        inputfile -> loadsystem(inputfile, suffix, vg, exclude, useinterfaces),
        inputfiles))

    # Save systems to disk
    persist && jldopen(outputfile, "w") do file
        print("Writing results to $outputfile...")
        addrequire(file, ResourceAdequacy)
        for (system, systemname) in systems
            write(file, systemname, system)
        end
        println(" done.")
    end

    return systems

end

args = parse_commandline(ARGS, as_symbols=true)
process_solutions(args[:inputdir], args[:outputfile], args[:parallel], args[:suffix],
                  args[:vg], args[:exclude], args[:useinterfaces], persist=true)
