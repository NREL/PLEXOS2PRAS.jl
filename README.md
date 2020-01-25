# PLEXOS2PRAS

This repository provides tools to allow power system models formulated for
PLEXOS to be read into NREL's Probabilistic Resource Adequacy Suite (PRAS).
PLEXOS model specifications can be very complicated, so unfortunately the
process for mapping them to PRAS inputs can be a bit involved as well!
The following workflow aims to minimize the effort required:

__Step 0: Prepare your environment__

Follow the PRAS
[installation instructions](https://nrel.github.io/PRAS/installation)
to ensure your environment is ready to run both the PLEXOS2PRAS import tools
and PRAS itself.

By default, PRAS doesn't reexport the PLEXOS2PRAS tools, so you'll need to
explicitly add that package to your project (it should already be downloaded
during the PRAS installation process, just not directly available for import):

```
(v1.1) pkg> add PLEXOS2PRAS
```

__Step 1: Represent your PLEXOS system in the Excel workbook format__

If your system has been generated from ReEDS results, RPM results, or PIDG,
it should already be available in this format.

If you only have the XML database file, you'll need to export your database
via the PLEXOS GUI (File -> Export). Note that recent versions of PLEXOS have
a bug that renders the Excel exports invalid for larger systems, so you may
need to load your XML file in an older version of the PLEXOS GUI for this to
work!

__Step 2: Run the pre-PRAS worksheet modification utility__

Once you have your PLEXOS system in an Excel workbook, run the workbook
modification function from a Julia script:

```julia
using PLEXOS2PRAS
process_plexosworkbook("yourworkbookname.xlsx", "yourworkbookname_PRAS.xlsx")
```

This will create a new workbook file called `yourworkbookname_PRAS.xlsx`
with changes to the system and output settings that are compatible with
importing to PRAS. Note that if need be, you can also apply these changes
manually in the PLEXOS GUI, and skip steps 1-3 here. For details, consult the
[worksheet modification reference](worksheet_modification.md).

__Step 3: Import the modified system back into PLEXOS__

Import the modified system (`yourworkbookname_PRAS.xlsx` from the above
example) into PLEXOS as you normally would. As with a normal import, you may
want to use an empty template file.

__Step 4: Run the PLEXOS Models that you want to import into PRAS__

Run the relevant PLEXOS models (either via the GUI or CLI). The runs should
finish much faster than normal since they're being executed in "dry run" mode,
without solving for any decision variables. PRAS only needs PLEXOS' definition
of certain inputs and constraints.

At this point, you can open the solution in the PLEXOS GUI and confirm that the
results match your expectations. You can manually fine-tune properties in the
newly-created database and re-run specific Models if you find elements that are
unsatisfactory.

__Step 5: Run h5plexos__

Once you have PLEXOS zipfiles containing results for all of the Models you want
to represent in PRAS, run
[`h5plexos`]()
to convert them all to HDF5 files.

```sh
h5plexos myplexossolution.zip
```

__Step 6: Run the solution processor utility__

Once each PLEXOS model result is processed into an HDF5 file, run the solution
processing function from a Julia script to generate the corresponding PRAS
model file.

```julia
using PLEXOS2PRAS
process_plexossolution("myplexossolution.h5", "myprasmodel.pras")
```

The function provides keyword arguments to exclude certain
generator categories, change how interregional limits are defined,
etc.

__Step 7: Load into PRAS__

You can now run PRAS as you normally would. After loading the
`PRAS` module in Julia, the system representation stored in the .pras file
can be loaded directly into a `SystemModel` struct:

```julia
using PRAS

# Load in the system
system = SystemModel("prasmodel.pras")

# Assess the reliability of the system
assess(Modern(samples=100_000), Minimal(), system)
```
