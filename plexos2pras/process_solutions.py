import sys
import argparse
import os
from glob import glob
import subprocess
from multiprocessing import Pool
from h5plexos.process import process_solution as process_to_h5

def scriptpath(scriptname):
    return os.path.join(os.path.dirname(__file__), scriptname)


def changeextension(filepath, newextension, suffix=None):

    filepath, _ = os.path.splitext(filepath)

    if suffix:
        filepath += "_" + suffix

    filepath += "." + newextension

    return filepath


def process_solution(zipinputpath, jldoutputpath, suffix, vgcats):

    h5outputpath = changeextension(zipinputpath, "h5", suffix="temp")

    # Convert zip solution to H5 solution
    process_to_h5(zipinputpath, h5outputpath).close()

    # Convert H5 solution to JLD PRAS data
    subprocess.run(
        ["julia", scriptpath("generate_jld.jl"), h5outputpath, jldoutputpath, suffix] + vgcats,
        check=True)

    # Remove H5 solution
    os.remove(h5outputpath)

    return jldoutputpath


def process_solutions(inputdir, outputfile, nproc, suffix, vgcats):
    "Assumes zip files names are in the standard Model {modelname} Solution.zip format"

    # Find relevant solutions and report that they're being processed
    filepaths = glob(os.path.join(inputdir, "**/Model *_" + suffix + " Solution.zip"),
                     recursive=True)
    print(len(filepaths), " solution files will be processed:\n",
          "\n".join(filepaths), sep="")

    # Generate JLD filenames and files
    julia_args = [
        (zippath, changeextension(zippath, "jld", suffix="temp"), suffix, vgcats)
        for zippath in filepaths]

    with Pool(processes=nproc) as pool:
        jldpaths = pool.starmap(process_solution, julia_args)

    # Collect JLD filepaths and run consolidation script
    subprocess.run(
        ["julia", scriptpath("combine_jld.jl"), outputfile, suffix] + jldpaths,
        check=True
    )


def _process_solutions(args=None):

    if args is None:
        args = sys.argv[1:]

    argparser = argparse.ArgumentParser(prog="process-solutions")
    argparser.add_argument(
        "inputdir",
        help="Path to the PLEXOS directory containing the solution " +
        "directories to be searched/processed"
    )
    argparser.add_argument(
        "outputfile",
        help="Name of the JLD file to store processed RAS systems"
    )
    argparser.add_argument(
        "--nprocs", default=4, type=int,
        help="Maximum number of PLEXOS solution files to process in parallel"
    )
    argparser.add_argument(
        "--vg", action="append",
        help="Generator category to be considered as VG instead of dispatchable"
    )
    argparser.add_argument(
        "--suffix", default="PRAS",
        help="Model name suffix identifying results to be read in to PRAS"
    )
    args = argparser.parse_args(args)

    process_solutions(args.inputdir, args.outputfile, args.nprocs, args.suffix, args.vg)


if __name__ == "__main__":
    _process_solutions()
