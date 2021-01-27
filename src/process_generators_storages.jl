# Note: PLEXOS "Storages" are referred to as "reservoirs" here to avoid
# confusion with PRAS "storages" (which combine both reservoir and
# injection/withdrawal capabilities)

function process_generators_storages!(
    prasfile::HDF5File, plexosfile::HDF5File, timestep::Period,
    excludecategories::Vector{String},
    pump_capacities::Bool, battery_availabilities::Bool,
    stringlength::Int, compressionlevel::Int)

    plexosgens = readgenerators(plexosfile, excludecategories)
    plexosreservoirs = readreservoirs(plexosfile)
    plexosbatteries = readbatteries(plexosfile)

    # plexosgens without reservoirs are PRAS generators
    gens = antijoin(plexosgens, plexosreservoirs, on=:generator)
    generators_core = gens[!, [:generator, :generator_category, :region]]
    gen_idxs = gens.generator_idx
    rename!(generators_core, [:name, :category, :region])

    if length(gen_idxs) > 0 # Load generator data

        gen_capacity = readsingleband(
            plexosfile["/data/ST/interval/generators/Available Capacity"], gen_idxs)
        gen_for = readsingleband(
            plexosfile["/data/ST/interval/generators/x"], gen_idxs)
        gen_mttr = readsingleband(
            plexosfile["/data/ST/interval/generators/y"], gen_idxs)
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

    n_batts = nrow(plexosbatteries)
    n_stors_genstors = nrow(stors_genstors)
    n_periods = read(attrs(prasfile)["timestep_count"])

    if n_stors_genstors > 0 # Load storage and genstorage data

        raw_gridinjectioncapacity =
            readsingleband(plexosfile["/data/ST/interval/generators/Available Capacity"])
        raw_fors =
            readsingleband(plexosfile["/data/ST/interval/generators/x"])
        raw_mttrs =
            readsingleband(plexosfile["/data/ST/interval/generators/y"])

        if pump_capacities # Generator.z is Pump Load

            raw_gridwithdrawalcapacity =
                readsingleband(plexosfile["/data/ST/interval/generators/z"])
            # assume fully efficient charging
            raw_chargeefficiency = ones(Float64, size(raw_gridwithdrawalcapacity)...)

        else # Generator.z is Pump Efficiency

            raw_gridwithdrawalcapacity = raw_gridinjectioncapacity # assume symmetric
            raw_chargeefficiency =
                readsingleband(plexosfile["/data/ST/interval/generators/z"]) ./ 100

            any(iszero, raw_chargeefficiency) &&
                @error "Generator(s) with 0% pump efficiency detected. " *
                       "This is often a sign that the system includes " *
                       "discharge-only Generator-Storage pairings that are " *
                       "not being represented correctly by PLEXOS2PRAS. " *
                       "Consider running `process_workbook` and " *
                       "`process_solution` with `pump_capacities=true` " *
                       "and `pump_efficiencies=false` instead."

        end

        raw_inflows =
            readsingleband(plexosfile["/data/ST/interval/storages/Natural Inflow"])
        raw_decayrate =
            readsingleband(plexosfile["/data/ST/interval/storages/x"]) ./ 100
        raw_carryoverefficiency =
            carryoverefficiency_conversion(1 .- raw_decayrate, timestep)
        raw_energycapacity_min =
            readsingleband(plexosfile["/data/ST/interval/storages/Min Volume"])
        raw_energycapacity_max =
            readsingleband(plexosfile["/data/ST/interval/storages/Max Volume"])
        raw_energycapacity = (raw_energycapacity_max .- raw_energycapacity_min) .* 1000

        inflow = Matrix{UInt32}(undef, n_stors_genstors, n_periods)

        gridwithdrawalcapacity = Matrix{UInt32}(undef, n_stors_genstors, n_periods)
        gridinjectioncapacity = Matrix{UInt32}(undef, n_stors_genstors, n_periods)
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

            gridwithdrawalcapacity[idx, :] =
                round.(UInt32, sum(raw_gridwithdrawalcapacity[gen_idxs, :], dims=1))
            gridinjectioncapacity[idx, :] =
                round.(UInt32, sum(raw_gridinjectioncapacity[gen_idxs, :], dims=1))
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

        # Load storages from PLEXOS batteries

        if n_batts > 0

            for row in eachrow(plexosbatteries)
                push!(storages_core,
                      (name=row.battery, category=row.battery_category,
                       region=row.region))
            end

            battery_dischargecapacity = round.(UInt32, readsingleband(
                plexosfile["/data/ST/interval/batteries/Installed Capacity"]))

            battery_chargecapacity = battery_dischargecapacity

            battery_energycapacity = round.(UInt32,
                readsingleband(plexosfile["data/ST/interval/batteries/z"]) .*
                readsingleband(plexosfile["data/ST/interval/batteries/Units"])
            )

            battery_carryoverefficiency = ones(Float64, n_batts, n_periods)

            if battery_availabilities

                battery_chargeefficiency = ones(Float64, n_batts, n_periods)
                battery_dischargeefficiency = ones(Float64, n_batts, n_periods)

                battery_fors = readsingleband(
                    plexosfile["data/ST/interval/batteries/x"])
                battery_mttrs = readsingleband(
                    plexosfile["data/ST/interval/batteries/y"])

            else

                battery_chargeefficiency = readsingleband(
                    plexosfile["/data/ST/interval/batteries/x"]) ./ 100
                battery_dischargeefficiency = readsingleband(
                    plexosfile["/data/ST/interval/batteries/y"]) ./ 100

                battery_fors = zeros(Float64, n_batts, n_periods)
                battery_mttrs = ones(Float64, n_batts, n_periods)

            end

            battery_λ, battery_μ =
                plexosoutages_to_transitionprobs(battery_fors, battery_mttrs, timestep)

        end

        # write results to prasfile

        if stor_idx > 0 || n_batts > 0
            storages = g_create(prasfile, "storages")
            string_table!(storages, "_core", storages_core, stringlength)
        end

        if stor_idx > 0
            stor_idxs = n_stors_genstors:-1:(genstor_idx+1)
        end

        if stor_idx > 0 && n_batts > 0

            storages["chargecapacity", "compress", compressionlevel] =
                vcat(gridwithdrawalcapacity[stor_idxs, :], battery_chargecapacity)
            storages["dischargecapacity", "compress", compressionlevel] =
                vcat(gridinjectioncapacity[stor_idxs, :], battery_dischargecapacity)
            storages["energycapacity", "compress", compressionlevel] =
                vcat(energycapacity[stor_idxs, :], battery_energycapacity)

            storages["chargeefficiency", "compress", compressionlevel] =
                vcat(chargeefficiency[stor_idxs, :], battery_chargeefficiency)
            storages["dischargeefficiency", "compress", compressionlevel] =
                vcat(dischargeefficiency[stor_idxs, :], battery_dischargeefficiency)
            storages["carryoverefficiency", "compress", compressionlevel] =
                vcat(carryoverefficiency[stor_idxs, :], battery_carryoverefficiency)

            storages["failureprobability", "compress", compressionlevel] =
                vcat(λ[stor_idxs, :], battery_λ)
            storages["repairprobability", "compress", compressionlevel] =
                vcat(μ[stor_idxs, :], battery_μ)

        elseif stor_idx > 0

            storages["chargecapacity", "compress", compressionlevel] =
                gridwithdrawalcapacity[stor_idxs, :]
            storages["dischargecapacity", "compress", compressionlevel] =
                gridinjectioncapacity[stor_idxs, :]
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

        elseif n_batts > 0

            storages["chargecapacity", "compress", compressionlevel] =
                battery_chargecapacity
            storages["dischargecapacity", "compress", compressionlevel] =
                battery_dischargecapacity
            storages["energycapacity", "compress", compressionlevel] =
                battery_energycapacity

            storages["chargeefficiency", "compress", compressionlevel] =
                battery_chargeefficiency
            storages["dischargeefficiency", "compress", compressionlevel] =
                battery_dischargeefficiency
            storages["carryoverefficiency", "compress", compressionlevel] =
                battery_carryoverefficiency

            storages["failureprobability", "compress", compressionlevel] =
                battery_λ
            storages["repairprobability", "compress", compressionlevel] =
                battery_μ

        end

        if genstor_idx > 0

            genstor_idxs = 1:genstor_idx

            generatorstorages = g_create(prasfile, "generatorstorages")
            string_table!(generatorstorages, "_core", generatorstorages_core, stringlength)

            generatorstorages["inflow", "compress", compressionlevel] =
                inflow[genstor_idxs, :]
            generatorstorages["gridwithdrawalcapacity", "compress", compressionlevel] =
                gridwithdrawalcapacity[genstor_idxs, :]
            generatorstorages["gridinjectioncapacity", "compress", compressionlevel] =
                gridinjectioncapacity[genstor_idxs, :]

            generatorstorages["chargecapacity", "compress", compressionlevel] =
                gridwithdrawalcapacity[genstor_idxs, :] .+ inflow[genstor_idxs, :]
            generatorstorages["dischargecapacity", "compress", compressionlevel] =
                gridinjectioncapacity[genstor_idxs, :]
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
        f["metadata/objects/generators"], [:generator, :generator_category])
    generators.generator_idx = 1:nrow(generators)

    generators = antijoin(
        generators, DataFrame(generator_category=excludecategories),
        on=:generator_category)

    generator_regions = readcompound(
        f["metadata/relations/regions_generators"], [:region, :generator])

    # Ensure no duplicated generators across regions
    # (if so, just pick the first region occurence)
    if !allunique(generator_regions.generator)
        generator_regions = combine(
            d -> (region=d[1, :region],),
            groupby(generator_regions, :generator))
    end

    generators = innerjoin(generators, generator_regions, on=:generator)

    return generators

end

function readreservoirs(f::HDF5File)

    storage_path = "metadata/objects/storages"
    storagerel_path = "metadata/relations/exportinggenerators_headstorage"

    if !exists(f, storage_path) || !exists(f, storagerel_path)
        return DataFrame(reservoir=String[], reservoir_idx=Int[],
                         reservoir_category=String[], generator=String[])
    end

    reservoirs = readcompound(
        f[storage_path], [:reservoir, :reservoir_category])
    reservoirs.reservoir_idx = 1:nrow(reservoirs)

    generator_reservoirs = readcompound(
        f[storagerel_path], [:generator, :reservoir])

    reservoirs = innerjoin(reservoirs, generator_reservoirs, on=:reservoir)

    return reservoirs

end

function readbatteries(f::HDF5File)

    battery_path = "metadata/objects/batteries"

    if !exists(f, battery_path)
        return DataFrame(battery=String[], battery_category=String[],
                         region=String[])
    end

    batteries = readcompound(
        f[battery_path], [:battery, :battery_category])
    battery_regions = readcompound(
        f["metadata/relations/regions_batteries"], [:region, :battery])

    # Ensure no duplicated batteries across regions
    # (if so, just pick the first region occurence)
    if !allunique(battery_regions.battery)
        battery_regions = combine(
            d -> (region=d[1, :region],),
            groupby(battery_regions, :battery))
    end

    batteries = innerjoin(batteries, battery_regions, on=:battery)

    return batteries

end

function consolidatestors(gens::DataFrame, reservoirs::DataFrame)

    # gens cols: generator, generator_idx, generator_category, region
    # reservoirs cols: reservoir, reservoir_idx, reservoir_category, generator

    gen_reservoirs = innerjoin(gens[!, [:generator, :generator_idx]],
                          reservoirs[!, [:generator, :reservoir_idx]],
                          on=:generator)[!, [:generator_idx, :reservoir_idx]]

    gen_reservoirs[!, :storage_idx] .= 0
    npairs = nrow(gen_reservoirs)

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

                gen_related = g in gs
                res_related = r in rs

                if gen_related || res_related
                    push!(gs, g)
                    push!(rs, r)
                    row.storage_idx = stor_idx
                    changed = true
                end

            end

        end

        empty!(gs)
        empty!(rs)

    end

    storages = innerjoin(gens, gen_reservoirs, on=:generator_idx)
    storages = innerjoin(storages,
                    reservoirs[!, [:reservoir_idx, :reservoir, :reservoir_category]],
                    on=:reservoir_idx)

    storages = combine(groupby(storages, :storage_idx)) do d::AbstractDataFrame

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
