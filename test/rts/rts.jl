@testset "RTS" begin

    testpath = dirname(@__FILE__) * "/"

    @testset "Pre-PLEXOS" begin

        xlsx_in = testpath * "rts_PLEXOS.xlsx"
        xlsx_out = testpath * "rts_PLEXOS_PRAS.xlsx"
        process_workbook(xlsx_in, xlsx_out,
            charge_capacities=true, charge_efficiencies=false)

    end

    @testset "Post-PLEXOS" begin

        zipfile = testpath * "Model DAY_AHEAD_PRAS Solution.zip"
        h5file = testpath * "Model DAY_AHEAD_PRAS Solution.h5"
        prasfile = testpath * "rts.pras"

        process(zipfile, h5file) # zip -> hdf5
        process_solution(h5file, prasfile, # hdf5 -> pras
            exclude_categories=["Sync Cond"],
            charge_capacities=true, charge_efficiencies=false)

        # Note that the "correct" battery charge efficiency should actually be
        # 0.85, not 1.0 as suggested below. But given PLEXOS' limit of three
        # passthrough variables, we're forced to choose between accurate charge
        # capacity and accurate charge efficiency. In this case, we decide that
        # modelling the CSP plant's inability to charge from the grid is more
        # important than correctly representing battery charging losses.

        sys = SystemModel(prasfile)

        @testset "Regions" begin

            @test length(sys.regions) == 3

            r = findfirst(isequal("1"), sys.regions.names)
            @test sys.regions.load[r, 1] == 985
            @test sys.regions.load[r, 8784] == 1081

        end

        @testset "Generators" begin

            gens = sys.generators
            @test length(gens) == 153

            g = findfirst(isequal("121_NUCLEAR_1"), gens.names)
            @test gens.categories[g] == "Nuclear"
            @test all(isequal(400), gens.capacity[g, :])
            @test all(isequal(1/1100), gens.λ[g, :])
            @test all(isequal(1/150), gens.μ[g, :])

            g = findfirst(isequal("313_CC_1"), gens.names)
            @test gens.categories[g] == "Gas CC"
            @test all(isequal(355), gens.capacity[g, :])
            @test all(isequal(1/967), gens.λ[g, :])
            @test all(isequal(1/33), gens.μ[g, :])

            g = findfirst(isequal("122_WIND_1"), gens.names)
            @test gens.categories[g] == "Wind"
            @test gens.capacity[g, 1] == 713
            @test gens.capacity[g, 8784] == 130
            @test all(iszero, gens.λ[g, :])
            @test all(isone, gens.μ[g, :])

        end

        @testset "Storages" begin

            stors = sys.storages

            @test length(stors) == 1
            @test stors.names == ["313_STORAGE_1"]
            @test stors.categories == ["Storage"]

            @test all(isequal(50), stors.charge_capacity)
            @test all(isequal(50), stors.discharge_capacity)
            @test all(isequal(150), stors.energy_capacity)

            @test all(isone, stors.charge_efficiency)
            @test all(isequal(1.0), stors.discharge_efficiency)
            @test all(isequal(1.0), stors.carryover_efficiency)
            @test all(iszero, stors.λ)
            @test all(isone, stors.μ)

        end

        @testset "GeneratorStorages" begin

            genstors = sys.generatorstorages
            @test length(sys.generatorstorages) == 1
            @test sys.generatorstorages.names == ["212_CSP_1"]
            @test sys.generatorstorages.categories== ["CSP"]

            @test all(isequal(0), genstors.charge_capacity)
            @test all(isequal(200), genstors.discharge_capacity)
            @test all(isequal(1200), genstors.energy_capacity)
            @test all(isequal(1.0), genstors.charge_efficiency)
            @test all(isequal(1.0), genstors.discharge_efficiency)
            @test all(isequal(1.0), genstors.carryover_efficiency)
            @test all(isequal(200), genstors.gridinjection_capacity)
            @test all(iszero, genstors.gridwithdrawal_capacity)
            @test all(isequal(1/576), genstors.λ)
            @test all(isequal(1/24), genstors.μ)
            @test genstors.inflow[1] == 0
            @test genstors.inflow[11] == 33
            @test genstors.inflow[4451] == 345
            @test genstors.inflow[8784] == 0

        end

        @testset "Interfaces" begin

            @test length(sys.interfaces) == 3

        end

        @testset "Lines" begin

            lines = sys.lines
            @test length(lines) == 6

            l = findfirst(isequal("AB1"), lines.names)
            @test lines.categories[l] == "Interregion_AC"
            @test all(isequal(175), lines.forward_capacity[l,:])
            @test all(isequal(175), lines.backward_capacity[l,:])

            l = findfirst(isequal("113_316_1"), lines.names)
            @test lines.categories[l] == "Interregion_DC"
            @test all(isequal(100), lines.forward_capacity[l,:])
            @test all(isequal(100), lines.backward_capacity[l,:])

        end

    end

end
