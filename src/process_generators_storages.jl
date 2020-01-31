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
        generators["capacity", "compress", compressionlevel] = UInt32.(gen_capacity)
        generators["failureprob", "compress", compressionlevel] = UInt32.(λ)
        generators["repairprob", "compress", compressionlevel] = UInt32.(μ)

    end

    stors_genstors = consolidatestors(plexosgens, plexosreservoirs)

    if size(stors_genstors, 1) > 0
        # split up stors and genstors
        # preallocate relevant data matrices
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
    storages = by(storages, :storage_idx) do d::DataFrame

        stor_name = join(d[!, :generator], "_")
        stor_category = join(unique(d[!, :generator_category]), "_")
        stor_region = first(unique(d[!, :region]))

        return (
            storage=stor_name, storage_category=stor_category,
            region=stor_region,
            generator_idxs=unique(d[!, :generator_idxs]),
            reservoir_idxs=unique(d[!, :reservoir_idxs])
        )

    end

    return storages

end
