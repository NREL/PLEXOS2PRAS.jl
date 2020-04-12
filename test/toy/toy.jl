@testset "Toy Model" begin

    testpath = dirname(@__FILE__) * "/"

    @testset "Pre-PLEXOS" begin

        xlsx_in = testpath * "three_nodes.xlsx"
        xlsx_out = testpath * "three_nodes_PRAS.xlsx"
        process_workbook(xlsx_in, xlsx_out)

    end

    @testset "Post-PLEXOS" begin

        zipfile = testpath * "Model Base_PRAS Solution.zip"
        h5file = testpath * "Model Base_PRAS Solution.h5"
        prasfile = testpath * "toymodel.pras"

        process(zipfile, h5file) # zip -> hdf5
        process_solution(h5file, prasfile, timestep=Minute(5)) # hdf5 -> pras
        sys = SystemModel(prasfile)
        # TODO: Test sys

    end

end
