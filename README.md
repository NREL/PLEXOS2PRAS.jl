# PLEXOS2PRAS

This repository provides tools to allow power system models formulated for PLEXOS to be read into NREL's Probabilistic Resource Adequacy Suite (PRAS). PLEXOS model specifications can be very complicated, so unfortunately the process for mapping them to PRAS inputs can be a bit involved as well! The following workflow aims to minimize the effort required:

__Step 0: Prepare your environment__

This will ensure your environment is ready to run both the PLEXOS import tools and PRAS (this means you can skip the PRAS standalone installation instructions).

 - Peregrine quick-install
 - Manual install

__Step 1: Represent your PLEXOS system in the Excel workbook format__

If your system has been generated from ReEDS results, RPM results, or PIDG, it should already be available in this format.

If you only have the XML database file, you'll need to export your database via the PLEXOS GUI (File -> Export). Note that recent versions of PLEXOS have a bug that renders the Excel exports invalid for larger systems, so you may need to load your XML file in an older version of the PLEXOS GUI for this to work!

__Step 2: Run the pre-PRAS worksheet modification utility__

Once you have your PLEXOS system in an Excel workbook, run the workbook modification script on the file:

```
process-workbook yourworkbookname.xlsx yourworkbookname_PRAS.xlsx
```

This will create a new workbook file called `yourworkbookname_PRAS.xlsx` with changes to the system and output settings that are compatible with importing to PRAS. Note that if need be, you can also apply these changes manually in the PLEXOS GUI, and skip steps 1-3 here. For details, consult the [worksheet modification reference](worksheet_modification.md).

__Step 3: Import the modified system back into PLEXOS__

Import the modified system (`yourworkbookname_PRAS.xlsx` from the above example) into PLEXOS as you normally would. As with a normal import, you may want to use an empty template file.

__Step 4: Run the PLEXOS Models that you want to import into PRAS__

Run the relevant PLEXOS models (either via the GUI or CLI). The runs should finish much faster than normal since they're being executed in "dry run" mode, without solving for any decision variables. PRAS only needs PLEXOS' definition of certain inputs and constraints.

At this point, you can open the solution in the PLEXOS GUI and confirm that the results match your expectations. You can manually fine-tune properties in the newly-created database and re-run specific Models if you find elements that are unsatisfactory.

__Step 5: Run the solution processor utility__

Once you have results for all of the Models you want to represent in PRAS, run the solution processing script to convert them all to JLD files. Run this in the same folder as your XML database - the script will automatically find the relevant solution files, run `h5plexos` on them, convert the HDF5 files to PRAS systems, and save all of the systems into a single JLD file:

```
process-solutions --nprocs 4 . PRAS_systems.jld
```

In the above example, the `--nprocs 4` defines the max number of solutions to be processed in parallel. If you have more than four solutions to process, have more than four logical cores on your machine, and can afford to use extra memory, you can increase the number to something higher.

__Step 6: Load into PRAS__

You can now run PRAS as you normally would. After loading the `ResourceAdequacy` module in Julia, use the `JLD` package to load in the systems from disk:

```julia
using ResourceAdequacy
using JLD

# Load in the systems
systems = load("PRAS_systems.jld")
model1system = systems["model1"]
model2system = systems["model2"]

# Assess the reliability of a system
assess(REPRA(1,10), NonSequentialNetworkFlow(100_000), MinimalResult(), model1system)
```
