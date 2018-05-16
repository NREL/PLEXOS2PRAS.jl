import sys
import argparse
import re

def process_workbook(infile, outfile, suffix):
    pass


def _process_workbook(args=None):

    if args is None:
        args = sys.argv[1:]

    argparser = argparse.ArgumentParser(prog="process-workbook")
    argparser.add_argument(
        "inputfile",
        help="Name of the input Excel workbook"
    )
    argparser.add_argument(
        "outputfile", nargs='?',
        help="Name of the output Excel workbook containing the modified " +
        "system / models"
    )
    argparser.add_argument(
        "--suffix", default="PRAS",
        help="Suffix to append to the names of modified PLEXOS models " +
        "in the output workbook"
    )
    args = argparser.parse_args(args)

    if args.outputfile:
        outputfile = args.outputfile

    else:
        inputfile_re = re.match("(.+)\.(.+)", args.inputfile)
        outputfile = inputfile_re[1] + "_" + args.suffix + "." + inputfile_re[2]

    print(args.inputfile, outputfile, args.suffix)
    process_workbook(args.inputfile, outputfile, args.suffix)


if __name__ == "__main__":
    _process_workbook()
