using ResourceAdequacy
using HDF5
using JLD

include("utils.jl")
include("loadh5.jl")

function aggregate_regionally(available_capacity::Matrix{T},
                              outage_rate::Matrix{T},
                              regions::Vector{Int},
                              isvgs::Vector{Bool}) where T

    n_regions = length(unique(region))

    vgprofiles = zeros(T, size(data,1), n_regions)
    dispcaps = fill(Int[], n_regions)
    dispors = fill(T[], n_regions)

    for (i, (region, isvg)) in enumerate(zip(regions, isvgs))
        if isvg
            vgprofiles[:, r] .+= available_capacity[:, i]
        else
            push!(dispcaps[r], round(Int, available_capacity[1, i]))
            push!(dispors[r], outage_rate[1, i])
        end
    end

    dispdistrs = ResourceAdequacy.spconv.(dispcaps, dispors)
    return vgprofiles, dispdistrs

end

# Use h5py to load compound data
inputpath_h5 = ARGS[1]
outputpath_jld = ARGS[2]
suffix = ARGS[3]
vg_categories = length(ARGS) > 3 ? ARGS[4:end] : String[]
systemname = extract_modelname(inputpath_h5, suffix)

vgcat(x::String) = x in vg_categories

# TODO: Would be nice to check that the nessecary properties
# are reported before starting to load things in

timestamps, generators, region_regions = load_metadata(inputpath_h5)
generators[:VG] = vgcat.(generators[:GeneratorCategory])

h5open(inputpath_h5, "r") do h5file

    # Load Data

    loaddata = load_singlebanddata(h5file, "data/ST/interval/region/Load")
    n_regions = size(loaddata, 2)

    # Transmission Data

    transfers = load_singlebanddata(
        h5file,
        "data/ST/interval/region_regions/Available Transfer Capability")
    # Static flow bounds for now
    region_regions[:TransferLimit] = collect(transfers[1,:])

    #TODO: Verify parallel flow, eliminate duplicates, and extract labels / limits
    display(region_regions)

    # Generator Data

    available_capacity = round(Int, load_singlebanddata(
        h5file, "data/ST/interval/generator/Available Capacity"))
    outagerate = loadsinglebanddata(
        h5file, "data/ST/interval/generator/x") ./ 100

    vgprofiles, dispdistrs = regional_aggregation(
        available_capacity, outagerate,
        generators[:RegionIdx], generators[:VG])

    display(vgprofiles)
    display(dispdistrs)

    # Create and persist the RAS representation of the system
    # Need:
    # - Vector of timestamps - ok
    # - Dispatchable distr per region - ok
    # - VG profile per region - ok
    # - Edge labels
    # - Edge distributions
    # - Load - ok

    system = ResourceAdequacy.SystemDistributionSet{}(
        timestamps, dispdistrs, vgprofiles,
        _, _, loaddata)
    save(outputpath_jld, systemname, system)

end
