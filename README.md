# PLEXOS2PRAS

This repository provides tools to allow power system models formulated for
PLEXOS to be read into NREL's Probabilistic Resource Adequacy Suite (PRAS).
PLEXOS model specifications can be very complicated, so unfortunately the
process for mapping them to PRAS inputs can be a bit involved as well!
The following workflow aims to minimize the effort required:

__Step 0: Installation__

Follow the PRAS
[installation instructions](https://nrel.github.io/PRAS/installation)
to ensure your environment is ready to run both the PLEXOS2PRAS import tools
and PRAS itself. Next, install PLEXOS2PRAS:

```
(v1.3) pkg> add PLEXOS2PRAS
```

__Step 1: Represent your PLEXOS system in the Excel workbook format__

If your system has been generated from ReEDS results, RPM results, or PIDG,
it should already be available in this format.

If you only have the XML database file, you'll need to export your database
via the PLEXOS GUI (File -> Export). Note that recent versions of PLEXOS have
a bug that renders the Excel exports invalid for larger systems, so you may
need to load your XML file in an older version of the PLEXOS GUI (7.2 or
earlier) for this to work!

__Step 2: Run the pre-PRAS worksheet modification utility__

Once you have your PLEXOS system in an Excel workbook, run the workbook
modification function from a Julia script:

```julia
using PLEXOS2PRAS
process_workbook("yourworkbookname.xlsx", "yourworkbookname_PRAS.xlsx")
```

This will create a new workbook file called `yourworkbookname_PRAS.xlsx`
with changes to the system and output settings that are compatible with
importing to PRAS. Note that if need be, you can also apply these changes
manually in the PLEXOS GUI, and skip steps 1-3 here. For details, consult the
[worksheet modification reference](worksheet_modification.md).

The function takes two sets of optional keyword arguments. Unfortunately, due
to limitations with PLEXOS passthrough variables, only one argument from each
set can be true at a time.

Pumped hydro options:

`pump_capacities`: For `Storage` and `GeneratorStorage` resources loaded from
PLEXOS pumped storage resources, should charge
capacities be read in from the PLEXOS `Pump Load` property? Defaults to
`false`, in which case the resources will be assumed to have symmetric charge
/ discharge capacities. If not using the default, be sure to provide the same
option to the `process_solution` function later.

`pump_efficiencies`: For `Storage` and `GeneratorStorage` resources loaded
from PLEXOS pumped storage resources, should charge
efficiencies be read in from the PLEXOS `Pump Efficiency` property? Defaults to
`true`. If `false`, the resources will be assumed to have 100% charge
efficiency. If not using the default, be sure to provide the same option
to the `process_solution` function later.

Battery options:

`battery_availabilities`: For `Storage` resources loaded from PLEXOS battery
objects, should availability data be read in from the PLEXOS
`Forced Outage Rate` and `Mean Time to Repair` properties? Defaults to `false`,
in which case the resource will be assumed to have perfect availability (0%
forced outage rate). If not using the default, be sure to provide the same
option to the `process_solution` function later.

`battery_efficiencies`: For `Storage` resources loaded from PLEXOS battery
objects, should efficiencies be read in from the PLEXOS `Charge Efficiency` and
`Discharge Efficiency` properties? Defaults to `true`. If `false`, the
resources are assumed to be 100% efficient. If not using the default, be sure
to provide the same option to the `process_solution` function later.

_Note that PLEXOS battery objects are particularly constrained by PLEXOS
passthrough variables. There are six PLEXOS properties requiring passthrough
(`Capacity`, `Max Load`, `Charge Efficiency`, `Discharge Efficiency`,
`Forced Outage Rate`, `Mean Time To Repair`) but only three passthrough
variables available (`x`, `y`, `z`). Because of these limitations, PRAS
`Storage` resources imported from PLEXOS battery objects will always assume
symmetric charge and discharge capabilities (i.e. the PLEXOS `Max Load`
property will be ignored)._

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

__Step 5: Run H5PLEXOS and the solution processor__

Once you have a PLEXOS zipfile containing results for the Model run you want
to represent in PRAS, use [H5PLEXOS.jl](https://github.com/NREL/H5PLEXOS.jl)
to convert it to an HDF5 files.

```julia
using H5PLEXOS
process("Model MyRun Solution.zip", "Model MyRun Solution.h5")
```

__Step 6: Run the solution processor utility__

Once each PLEXOS model result is processed into an HDF5 file, run the solution
processing function from a Julia script to generate the corresponding PRAS
model file.

```julia
using PLEXOS2PRAS
process_solution("Model MyRun Solution.h5", "mysystem.pras")
```

The function provides a number of optional keyword arguments, including two
sets of mutually-exclusive options:

`pump_capacities` vs `pump_efficiencies`: Boolean values that determine how
reported PLEXOS pumped storage properties should map to PRAS Storage and
GeneratorStorage properties. The provided values should match the options set
in the earlier `process_workbook` function call.

`battery_availabilities` vs `battery_efficiencies`: Boolean values that
determine how reported PLEXOS Battery properties should map to PRAS Storage
properties. The provided values should match the options set in the earlier
`process_workbook` function call.

`timestep`: The length of a simulation timestep as a `Dates.TimePeriod`, e.g.
`Hour(1)` or `Minute(5)`. Defaults to `Hour(1)`.

`timezone`: The `TimeZones.TimeZone` associated with PRAS system timestamps.
Defaults to `tz"UTC"`, although providing a more accurate value is
recommended for clarity, especially if your system geography spans multiple
time zones.

`use_interfaces`: Should interregional power transfer limits in PRAS be defined
based on PLEXOS interface limits instead of the sum of interregional line
limits? Defaults to `false`.

`exclude_categories`: A `Vector{String}` of PLEXOS generator category names
that will be ignored/excluded when creating the PRAS model. Defaults to an
empty list.

__Step 7: Load into PRAS__

You can now run PRAS as you normally would. After loading the
`PRAS` module in Julia, the system representation stored in the .pras file
can be loaded directly into a `SystemModel` struct:

```julia
using PRAS

# Load in the system
system = SystemModel("mysystem.pras")

# Assess the reliability of the system
assess(SequentialMonteCarlo(samples=100_000), Minimal(), system)
```
