@testset "RTS" begin

    testpath = dirname(@__FILE__) * "/"

    @testset "Pre-PLEXOS" begin

        xlsx_in = testpath * "rts_PLEXOS.xlsx"
        xlsx_out = testpath * "rts_PLEXOS_PRAS.xlsx"
        process_workbook(xlsx_in, xlsx_out)

    end

    @testset "Post-PLEXOS" begin

        zipfile = testpath * "Model DAY_AHEAD_PRAS Solution.zip"
        h5file = testpath * "Model DAY_AHEAD_PRAS Solution.h5"
        prasfile = testpath * "rts.pras"

        process(zipfile, h5file) # zip -> hdf5
        process_solution(h5file, prasfile) # hdf5 -> pras
        sys = SystemModel(prasfile)
        # TODO: Test sys

    end

end
