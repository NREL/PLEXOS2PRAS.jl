import sys
import argparse
import re
from os import path
import numpy as np
import pandas as pd

def remove_properties(props, colls_props):

    filter_idx = np.full(props.shape[0], False)

    for (coll, prop) in colls_props:
        filter_idx |= (props["collection"] == coll) & (props["property"] == prop)

    return props.loc[~filter_idx, :]

def convert_properties(props, collection, old_prop, new_prop):

    idxs = (props["collection"] == collection) & (props["property"] == old_prop)
    props.loc[idxs, "property"] = new_prop

def blanket_properties(props, objs, obj_class, collection, prop, value):

    obj_names = objs.loc[objs["class"] == obj_class, "name"]

    new_props = pd.DataFrame(
        {"parent_class": "System",
         "child_class": obj_class,
         "collection": collection,
         "parent_object": "System",
         "child_object": obj_names,
         "property": prop,
         "band_id": 1,
         "value": value})

    return props.append(new_props, ignore_index=True, sort=False)


def remove_attributes(attrs, class_attrs):

    filter_idx = np.full(attrs.shape[0], False)

    for (cls, attr) in class_attrs:
        filter_idx |= (attrs["class"] == cls) & (attrs["attribute"] == attr)

    return attrs.loc[~filter_idx, :]

def blanket_attributes(attrs, objs, obj_class, attr, value):

    obj_names = objs.loc[objs["class"] == obj_class, "name"]

    new_attrs = pd.DataFrame(
        {"name": obj_names,
         "class": obj_class,
         "attribute": attr,
         "value": value})

    return attrs.append(new_attrs, ignore_index=True, sort=False)


def process_workbook(infile, outfile, suffix):

    new_obj_name = "_" + suffix

    # Load in file
    with pd.ExcelFile(infile) as f:
        objects = f.parse("Objects")
        categories = f.parse("Categories")
        memberships = f.parse("Memberships")
        attributes = f.parse("Attributes")
        properties = f.parse("Properties")
        reports = f.parse("Reports")


    # Remove x, y, and Maintenance Rate properties
    properties = remove_properties(properties,
                                   [("Generators", "x"),
                                    ("Generators", "y"),
                                    ("Generators", "Maintenance Rate")])

    # Find all FOR property rows and convert to x
    convert_properties(properties, "Generators", "Forced Outage Rate", "x")

    # Find all MTTR property rows and convert to y
    convert_properties(properties, "Generators", "Mean Time to Repair", "y")

    # Add new FOR property (set to zero) for each generator object
    properties = blanket_properties(properties, objects, "Generator",
                                    "Generators", "Forced Outage Rate", 0)

    # Add new Maintenance Rate property (set to zero) for each generator object
    properties = blanket_properties(properties, objects, "Generator",
                                    "Generators", "Maintenance Rate", 0)

    # Add new/irrelevant MTTR property (to supress PLEXOS warnings)
    properties = blanket_properties(properties, objects, "Generator",
                                    "Generators", "Mean Time to Repair", 0)

    # Create new ST Schedule object
    objects = objects.append(pd.DataFrame({
        "class": "ST Schedule",
        "name": new_obj_name}, index=[0]), ignore_index=True, sort=False)

    # Set Transmission Aggregation, Stochastic Method ST attributes
    attributes = attributes.append(pd.DataFrame({
        "name": new_obj_name,
        "class": "ST Schedule",
        "attribute": ["Transmission Detail", "Stochastic Method"],
        "value": [0, 0]}), ignore_index=True, sort=False)

    # Replace all existing ST Memberships with new ST
    memberships.loc[memberships["child_class"] == "ST Schedule",
                    "child_object"] = new_obj_name


    # Create new Report object
    objects = objects.append(pd.DataFrame({
        "class": "Report",
        "name": new_obj_name}, index=[0]), ignore_index=True, sort=False)

    # Add desired properties output
    reports = reports.append(pd.DataFrame({
        "object": new_obj_name,
        "parent_class": ["System", "Region", "System", "System", "System"],
        "child_class": ["Region", "Region", "Generator", "Generator", "Generator"],
        "collection": ["Regions", "Regions", "Generators", "Generators", "Generators"],
        "property": ["Load", "Available Transfer Capability", "Available Capacity", "x", "y"],
        "phase_id": 4,
        "report_period": True,
        "report_summary": False,
        "report_statistics": False,
        "report_samples": False,
    }), ignore_index=True, sort=False)

    # Replace all existing Report memberships with new Report
    memberships.loc[memberships["child_class"] == "Report",
                    "child_object"] = new_obj_name


    # Add suffix to all Model names
    objects.loc[objects["class"] == "Model",
                "name"] += new_obj_name
    memberships.loc[memberships["parent_class"] == "Model",
                    "parent_object"] += new_obj_name
    attributes.loc[attributes["class"] == "Model",
                   "name"] += new_obj_name

    # Delete all Model dry run attributes
    attributes = remove_attributes(attributes, [("Model", "Run Mode")])

    # Create new Model dry run attributes
    attributes = blanket_attributes(attributes, objects, "Model", "Run Mode", 1)

    # Save out results to new file
    with pd.ExcelWriter(outfile) as f:
        objects.to_excel(f, "Objects", index=False)
        categories.to_excel(f, "Categories", index=False)
        memberships.to_excel(f, "Memberships", index=False)
        attributes.to_excel(f, "Attributes", index=False)
        properties.to_excel(f, "Properties", index=False)
        reports.to_excel(f, "Reports", index=False)

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
        filepath, fileextension = path.splitext(args.inputfile)
        outputfile = filepath + "_" + args.suffix + fileextension

    process_workbook(args.inputfile, outputfile, args.suffix)


if __name__ == "__main__":
    _process_workbook()
