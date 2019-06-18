function process_solutions(
    inputdir::String, outputfile::String;
    useinterfaces::Bool=false, nparallel::Int=1, suffix::String="PRAS",
    vg::Vector{String}=String[], exclude::Vector{String}=String[],
    persist::Bool=true)

    # Find relevant solutions and report that they're being processed
    solutions = findsolutions(inputdir, suffix)
    println(length(solutions), " solution files will be processed:\n",
            join(map(sol -> sol[2], solutions), "\n"))

    # Process systems
    systems = Dict(map(
        solution -> (solution[1], 
                     loadsystem(solution[2], vg, exclude, useinterfaces)),
        solutions))

    # Save systems to disk
    persist && jldopen(outputfile, "w") do file
        print("Writing results to $outputfile...")
        addrequire(file, Dates)
        addrequire(file, ResourceAdequacy)
        for (systemname, system) in systems
            write(file, systemname, system)
        end
        println(" done.")
    end

    return systems

end

function findsolutions(inputdir::String, suffix::String)
    solutions = Tuple{String,String}[]
    rgx = Regex("^Model (.+)_" * suffix * " Solution.zip\$")
    for (folder, _, files) in walkdir(inputdir), file in files
        matchresult = match(rgx, file)
        if matchresult !== nothing
            systemname = matchresult[1]
            systempath = folder * "/" * file
            push!(solutions, (systemname, systempath))
        end
    end
    return solutions
end
