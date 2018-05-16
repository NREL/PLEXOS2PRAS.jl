import sys
import argparse
import re

def process_solutions(inputdir, outputfile, nprocs, suffix):
    pass

def _process_solutions(args=None):

    if args is None:
        args = sys.argv

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
        "--suffix", default="PRAS",
        help="Model name suffix identifying results to be read in to PRAS"
    )
    args = argparser.parse_args(args)

    print(args.inputdir, args.outputfile, args.nprocs, args.suffix)
    process_solutions(args.inputdir, args.outputfile, args.nprocs, args.suffix)

if __name__ == "__main__":
    _process_solutions()
