# Note: PLEXOS "Storages" are referred to as "reservoirs" here to avoid
# confusion with PRAS "storages" (which combine both reservoir and
# injection/withdrawal capabilities)

function process_generators_storages!(
    prasfile::HDF5File, plexosfile::HDF5File,
    excludecategories::Vector{String}, stringlength::Int, compressionlevel::Int)

    plexosgens = readgenerators(plexosfile, excludecategories)
    plexosreservoirs = readreservoirs(plexosfile)

    # plexosgens without reservoirs are PRAS generators
    gens = join(plexosgens, plexosreservoirs, on=:generator, kind=:anti)
    generators_core = gens[!, [:generator, :generator_category, :region]]
    gen_idxs = gens.generator_idx
    names!(generators_core, [:name, :category, :region])

    if length(gen_idxs) > 0 # Save out generator data to prasfile

        gen_capacity = readsingleband(
            plexosfile["/data/ST/interval/generator/Available Capacity"], gen_idxs)
        gen_for = readsingleband(
            plexosfile["/data/ST/interval/generator/x"], gen_idxs)
        gen_mttr = readsingleband(
            plexosfile["/data/ST/interval/generator/y"], gen_idxs)
        λ, μ = plexosoutages_to_transitionprobs(gen_for, gen_mttr, _timeperiod_length)

        generators = g_create(prasfile, "generators")
        string_table!(generators, "_core", generators_core, stringlength)
        generators["capacity", "compress", compressionlevel] = round.(UInt32, gen_capacity)
        generators["failureprob", "compress", compressionlevel] = λ
        generators["repairprob", "compress", compressionlevel] = μ

    end

    stors_genstors = consolidatestors(plexosgens, plexosreservoirs)
    storages_core = DataFrame(name=String[], category=String[], region=String[])
    generatorstorages_core = deepcopy(storages_core)

    n_stors_genstors = size(stors_genstors, 1)
    n_periods = read(attrs(prasfile)["timestep_count"])

    if n_stors_genstors > 0

        raw_dischargecapacity =
            readsingleband(plexosfile["/data/ST/interval/generator/Available Capacity"])
        raw_chargeefficiency =
            readsingleband(plexosfile["/data/ST/interval/generator/Pump Efficiency"])
        raw_fors =
            readsingleband(plexosfile["/data/ST/interval/generator/x"])
        raw_mttrs =
            readsingleband(plexosfile["/data/ST/interval/generator/y"])

        raw_inflows =
            readsingleband(plexosfile["/data/ST/interval/storage/Natural Inflow"])
        raw_lossrate =
            readsingleband(plexosfile["/data/ST/interval/storage/Loss Rate"])
        raw_energycapacity_min =
            readsingleband(plexosfile["/data/ST/interval/storage/Min Volume"])
        raw_energycapacity_max =
            readsingleband(plexosfile["/data/ST/interval/storage/Max Volume"])
        raw_energycapacity = energycapacities_max .- energycapacities_min

        inflow = Matrix{UInt32}(undef, n_stors_genstors, n_periods)

        #chargecapacity = Matrix{UInt32}(undef, n_stors_genstors, n_periods)
        dischargecapacity = Matrix{UInt32}(undef, n_stors_genstors, n_periods)
        energycapacity = Matrix{UInt32}(undef, n_stors_genstors, n_periods)

        chargeefficiency = Matrix{Float64}(undef, n_stors_genstors, n_periods)
        #dischargeefficiency = Matrix{Float64}(undef, n_stors_genstors, n_periods)
        carryoverefficiency = Matrix{Float64}(undef, n_stors_genstors, n_periods)

        fors = Matrix{Float64}(undef, n_stors_genstors, n_periods)
        mttrs = Matrix{Float64}(undef, n_stors_genstors, n_periods)

        genstor_idx = 0
        stor_idx = 0

        for row in eachrow(stor_genstors)

            row_inflows = sum(raw_inflows[:, row.reservoir_idxs], 2)

            if sum(row_inflows) > 0 # device is a generatorstorage

                genstor_idx += 1
                idx = genstor_idx # populate from first row down
                # push new row to generatorstorages_core

                inflow[genstor_idx, :] = row_inflows
                # gridwithdrawalcapacity - set to chargecapacity
                # gridinjectioncapacity - set to dischargecapacity

            else # device is just a storage

                stor_idx += 1
                idx = n_stors_genstors + 1 - genstor_idx # populate from last row up
                # push new row to storages_core

            end

            # chargecapacity
            dischargecapacity[idx, :] =
                sum(raw_dischargecapacity[:, row.reservoir_idxs], dims=2)
            energycapacity[idx, :] =
                sum(raw_energycapacity[:, row.reservoir_idxs], dims=2)

            # Take efficiency of worst component as efficiency for overall system
            chargeefficiency[idx, :] =
                minimum(raw_chargeefficiency[:, row.reservoir_idxs], dims=2)
            # dischargeefficiency - set to 1?
            carryoverefficiency[idx, :] =
                1 .- maximum(raw_lossrate[:, row.reservoir_idxs], dims=2)

            # Just take largest FOR and MTTR out of all associated generators
            # as the device's FOR and MTTR
            fors[idx, :] = maximum(raw_fors[:, row.reservoir_idxs], dims=2)
            mttrs[idx, :] = maximum(raw_mttrs[:, row.reservoir_idxs], dims=2)

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
    if !allunique(generator_regions[!, :generator])
        generator_regions =
            by(generator_regions, :generator, d -> (region=d[1, :region]))
    end

    generators = join(generators, generator_regions, on=:generator, kind=:inner)

    return generators

end

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

    gen_reservoirs = join(gens[!, [:generator, :generator_idx]],
                          reservoirs[!, [:generator, :reservoir_idx]],
                          on=:generator, kind=:inner
                         )[!, [:generator_idx, :reservoir_idx]]

    gen_reservoirs.storage_idx = 0
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
    storages = join(storages, reservoirs, on=:reservoir_idx, kind=:inner)
    storages = by(storages, :storage_idx) do d::AbstractDataFrame

        generators = unique(d[!, :generators])
        reservoirs = unique(d[!, :reservoirs])
        regions = unique(d[!, :region])

        stor_name = join(generators, "_")
        stor_category = join(unique(d[!, :generator_category]), "_")
        stor_region = first(regions)

        @info "Combining generators $generators and reservoirs $reservoirs" *
              "into storage/generatorstorage device $(stor_name)"

        length(regions) > 1 && @warn "Storage device $stor has components" *
            "spanning multiple regions: $regions - the device will be " *
            "assigned to region $stor_region"

        return (
            storage=stor_name, storage_category=stor_category,
            region=stor_region,
            generator_idxs=unique(d[!, :generator_idxs]),
            reservoir_idxs=unique(d[!, :reservoir_idxs])
        )

    end

    return storages

end
