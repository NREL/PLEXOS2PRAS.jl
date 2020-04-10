# Note: PLEXOS "Storages" are referred to as "reservoirs" here to avoid
# confusion with PRAS "storages" (which combine both reservoir and
# injection/withdrawal capabilities)

function process_generators_storages!(
    prasfile::HDF5File, plexosfile::HDF5File, timestep::Period,
    excludecategories::Vector{String}, charge_capacities::Bool,
    stringlength::Int, compressionlevel::Int)

    plexosgens = readgenerators(plexosfile, excludecategories)
    plexosreservoirs = readreservoirs(plexosfile)

    # plexosgens without reservoirs are PRAS generators
    gens = join(plexosgens, plexosreservoirs, on=:generator, kind=:anti)
    generators_core = gens[!, [:generator, :generator_category, :region]]
    gen_idxs = gens.generator_idx
    rename!(generators_core, [:name, :category, :region])

    if length(gen_idxs) > 0 # Load generator data

        gen_capacity = readsingleband(
            plexosfile["/data/ST/interval/generator/Available Capacity"], gen_idxs)
        gen_for = readsingleband(
            plexosfile["/data/ST/interval/generator/x"], gen_idxs)
        gen_mttr = readsingleband(
            plexosfile["/data/ST/interval/generator/y"], gen_idxs)
        λ, μ = plexosoutages_to_transitionprobs(gen_for, gen_mttr, timestep)

        generators = g_create(prasfile, "generators")
        string_table!(generators, "_core", generators_core, stringlength)
        generators["capacity", "compress", compressionlevel] = round.(UInt32, gen_capacity)
        generators["failureprobability", "compress", compressionlevel] = λ
        generators["repairprobability", "compress", compressionlevel] = μ

    end

    stors_genstors = consolidatestors(plexosgens, plexosreservoirs)
    storages_core = DataFrame(name=String[], category=String[], region=String[])
    generatorstorages_core = deepcopy(storages_core)

    n_stors_genstors = size(stors_genstors, 1)
    n_periods = read(attrs(prasfile)["timestep_count"])

    if n_stors_genstors > 0 # Load storage and genstorage data

        raw_dischargecapacity =
            readsingleband(plexosfile["/data/ST/interval/generator/Available Capacity"])
        raw_fors =
            readsingleband(plexosfile["/data/ST/interval/generator/x"])
        raw_mttrs =
            readsingleband(plexosfile["/data/ST/interval/generator/y"])

        if charge_capacities # Generator.z is Pump Load
            raw_chargecapacity =
                readsingleband(plexosfile["/data/ST/interval/generator/z"])
            raw_chargeefficiency = ones(Float64, size(raw_chargecapacity)...)
        else # Generator.z is Pump Efficiency
            raw_chargecapacity = raw_dischargecapacity
            raw_chargeefficiency =
                readsingleband(plexosfile["/data/ST/interval/generator/z"]) ./ 100
        end

        raw_inflows =
            readsingleband(plexosfile["/data/ST/interval/storage/Natural Inflow"])
        raw_carryoverefficiency = # TODO: Adjust units to time period length
            1 .- readsingleband(plexosfile["/data/ST/interval/storage/x"]) ./ 100
        raw_energycapacity_min =
            readsingleband(plexosfile["/data/ST/interval/storage/Min Volume"])
        raw_energycapacity_max =
            readsingleband(plexosfile["/data/ST/interval/storage/Max Volume"])
        raw_energycapacity = raw_energycapacity_max .- raw_energycapacity_min

        inflow = Matrix{UInt32}(undef, n_stors_genstors, n_periods)

        chargecapacity = Matrix{UInt32}(undef, n_stors_genstors, n_periods)
        dischargecapacity = Matrix{UInt32}(undef, n_stors_genstors, n_periods)
        energycapacity = Matrix{UInt32}(undef, n_stors_genstors, n_periods)

        chargeefficiency = Matrix{Float64}(undef, n_stors_genstors, n_periods)
        dischargeefficiency = ones(Float64, n_stors_genstors, n_periods)
        carryoverefficiency = Matrix{Float64}(undef, n_stors_genstors, n_periods)

        fors = Matrix{Float64}(undef, n_stors_genstors, n_periods)
        mttrs = Matrix{Float64}(undef, n_stors_genstors, n_periods)

        genstor_idx = 0
        stor_idx = 0

        for row in eachrow(stors_genstors)

            res_idxs = row.reservoir_idxs[]
            gen_idxs = row.generator_idxs[]

            row_inflows = sum(raw_inflows[res_idxs, :], dims=1)

            if sum(row_inflows) > 0. # device is a generatorstorage

                genstor_idx += 1
                idx = genstor_idx # populate from first row down

                push!(generatorstorages_core,
                      (name=row.storage, category=row.storage_category,
                       region=row.region))

                inflow[idx, :] = round.(UInt32, row_inflows)

            else # device is just a storage

                stor_idx += 1
                idx = n_stors_genstors + 1 - stor_idx # populate from last row up

                push!(storages_core,
                      (name=row.storage, category=row.storage_category,
                       region=row.region))
            end

            chargecapacity[idx, :] =
                round.(UInt32, sum(raw_chargecapacity[gen_idxs, :], dims=1))
            dischargecapacity[idx, :] =
                round.(UInt32, sum(raw_dischargecapacity[gen_idxs, :], dims=1))
            energycapacity[idx, :] =
                round.(UInt32, sum(raw_energycapacity[res_idxs, :], dims=1))

            # Take efficiency of worst component as efficiency for overall system
            chargeefficiency[idx, :] =
                minimum(raw_chargeefficiency[gen_idxs, :], dims=1)
            carryoverefficiency[idx, :] =
                minimum(raw_carryoverefficiency[res_idxs, :], dims=1)

            # Just take largest FOR and MTTR out of all associated generators
            # as the device's FOR and MTTR
            fors[idx, :] = maximum(raw_fors[gen_idxs, :], dims=1)
            mttrs[idx, :] = maximum(raw_mttrs[gen_idxs, :], dims=1)

        end

        λ, μ = plexosoutages_to_transitionprobs(fors, mttrs, timestep)

        # write results to prasfile

        if stor_idx > 0

            stor_idxs = 1:stor_idx

            storages = g_create(prasfile, "storages")
            string_table!(storages, "_core", storages_core, stringlength)

            storages["chargecapacity", "compress", compressionlevel] =
                chargecapacity[stor_idxs, :]
            storages["dischargecapacity", "compress", compressionlevel] =
                dischargecapacity[stor_idxs, :]
            storages["energycapacity", "compress", compressionlevel] =
                energycapacity[stor_idxs, :]

            storages["chargeefficiency", "compress", compressionlevel] =
                chargeefficiency[stor_idxs, :]
            storages["dischargeefficiency", "compress", compressionlevel] =
                dischargeefficiency[stor_idxs, :]
            storages["carryoverefficiency", "compress", compressionlevel] =
                carryoverefficiency[stor_idxs, :]

            storages["failureprobability", "compress", compressionlevel] =
                λ[stor_idxs, :]
            storages["repairprobability", "compress", compressionlevel] =
                μ[stor_idxs, :]

        end

        if genstor_idx > 0

            genstor_idxs = n_stors_genstors .- (0:(genstor_idx-1))

            generatorstorages = g_create(prasfile, "generatorstorages")
            string_table!(generatorstorages, "_core", generatorstorages_core, stringlength)

            generatorstorages["inflow", "compress", compressionlevel] =
                inflow[genstor_idxs, :]
            generatorstorages["gridwithdrawalcapacity", "compress", compressionlevel] =
                chargecapacity[genstor_idxs, :]
            generatorstorages["gridinjectioncapacity", "compress", compressionlevel] =
                dischargecapacity[genstor_idxs, :]

            generatorstorages["chargecapacity", "compress", compressionlevel] =
                chargecapacity[genstor_idxs, :]
            generatorstorages["dischargecapacity", "compress", compressionlevel] =
                dischargecapacity[genstor_idxs, :]
            generatorstorages["energycapacity", "compress", compressionlevel] =
                energycapacity[genstor_idxs, :]

            generatorstorages["chargeefficiency", "compress", compressionlevel] =
                chargeefficiency[genstor_idxs, :]
            generatorstorages["dischargeefficiency", "compress", compressionlevel] =
                dischargeefficiency[genstor_idxs, :]
            generatorstorages["carryoverefficiency", "compress", compressionlevel] =
                carryoverefficiency[genstor_idxs, :]

            generatorstorages["failureprobability", "compress", compressionlevel] =
                λ[genstor_idxs, :]
            generatorstorages["repairprobability", "compress", compressionlevel] =
                μ[genstor_idxs, :]

         end

    end

end

function readgenerators(f::HDF5File, excludecategories::Vector{String})

    generators = readcompound(
        f["metadata/objects/generator"], [:generator, :generator_category])
    generators.generator_idx = 1:size(generators, 1)

    generators = join(
        generators, DataFrame(generator_category=excludecategories),
        on=:generator_category, kind=:anti)

    generator_regions = readcompound(
        f["metadata/relations/region_generators"], [:region, :generator])

    # Ensure no duplicated generators across regions
    # (if so, just pick the first region occurence)
    if !allunique(generator_regions.generator)
        generator_regions =
            by(generator_regions, :generator, d -> (region=d[1, :region],))
    end

    generators = join(generators, generator_regions, on=:generator, kind=:inner)

    return generators

end

# TODO: If system has no storages, return empty results
function readreservoirs(f::HDF5File)

    reservoirs = readcompound(
        f["metadata/objects/storage"], [:reservoir, :reservoir_category])
    reservoirs.reservoir_idx = 1:size(reservoirs, 1)

    generator_reservoirs = readcompound(
        f["metadata/relations/generator_headstorage"], [:generator, :reservoir])

    reservoirs = join(reservoirs, generator_reservoirs, on=:reservoir, kind=:inner)

    return reservoirs

end

function consolidatestors(gens::DataFrame, reservoirs::DataFrame)

    # gens cols: generator, generator_idx, generator_category, region
    # reservoirs cols: reservoir, reservoir_idx, reservoir_category, generator

    gen_reservoirs = join(gens[!, [:generator, :generator_idx]],
                          reservoirs[!, [:generator, :reservoir_idx]],
                          on=:generator, kind=:inner
                         )[!, [:generator_idx, :reservoir_idx]]

    gen_reservoirs[!, :storage_idx] .= 0
    npairs = size(gen_reservoirs, 1)

    stor_idx = 0
    gs = BitSet()
    rs = BitSet()

    for i in 1:npairs

        row1 = gen_reservoirs[i, :]
        row1.storage_idx > 0 && continue

        stor_idx += 1

        push!(gs, row1.generator_idx)
        push!(rs, row1.reservoir_idx)
        row1.storage_idx = stor_idx

        changed = true

        while changed == true

            changed = false

            for j in (i+1):npairs

                row = gen_reservoirs[j, :]
                row.storage_idx > 0 && continue

                g = row.generator_idx
                r = row.reservoir_idx

                gen_labelled = g in gs
                res_labelled = r in rs

                # TODO: May need to update storage_idx even if
                #       no new network nodes discovered?
                if xor(gen_labelled, res_labelled)
                    gen_labelled ? push!(rs, r) : push!(gs, g)
                    row.storage_idx = stor_idx
                    changed = true
                end

            end

        end

        empty!(gs)
        empty!(rs)

    end

    storages = join(gens, gen_reservoirs, on=:generator_idx, kind=:inner)
    storages = join(storages,
                    reservoirs[!, [:reservoir_idx, :reservoir, :reservoir_category]],
                    on=:reservoir_idx, kind=:inner)

    storages = by(storages, :storage_idx) do d::AbstractDataFrame

        generators = unique(d[!, :generator])
        reservoirs = unique(d[!, :reservoir])
        regions = unique(d[!, :region])

        stor_name = join(generators, "_")
        stor_category = join(unique(d[!, :generator_category]), "_")
        stor_region = first(regions)

        @info "Combining generators $generators and reservoirs $reservoirs " *
              "into single device $(stor_name)"

        length(regions) > 1 && @warn "Storage device $stor has components " *
            "spanning multiple regions: $regions - the device will be " *
            "assigned to region $stor_region"

        return (
            storage=stor_name, storage_category=stor_category,
            region=stor_region,
            generator_idxs=Ref(unique(d[!, :generator_idx])),
            reservoir_idxs=Ref(unique(d[!, :reservoir_idx]))
        )

    end

    return storages

end
