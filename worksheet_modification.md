# Worksheet Modification Process

The worksheet modification utility creates a copy of the input database with
the following changes:

 - The pass-through output property `x` for each Generator and Line object
   is assigned (or reassigned, if already in use) to mirror each Generator or
   Line's Forced Outage Rate input property.

 - The pass-through output property `x` for each Storage object
   is assigned (or reassigned, if already in use) to mirror each Storage's
   Loss Rate input property.

 - The pass-through output property `x` for each Battery object
   is assigned (or reassigned, if already in use) to mirror each Battery's
   Charge Efficiency or Forced Outage Rate input property, depending on the
   option selected.

 - The pass-through output property `y` for each Generator and Line object
   is assigned (or reassigned, if already in use) to mirror each Generator or
   Line's Mean Time to Repair input property.

 - The pass-through output property `y` for each Battery object
   is assigned (or reassigned, if already in use) to mirror each Battery's
   Discharge Efficiency or Mean Time to Repair input property, depending on the
   option selected.

 - The pass-through output property `z` for each Generator object
   is assigned (or reassigned, if already in use) to mirror each Generator's
   Pump Efficiency or Pump Load input property, depending on the option selected.

 - The pass-through output property `z` for each Battery object
   is assigned (or reassigned, if already in use) to mirror each Battery's
   Energy Capacity.

- The Forced Outage Rate for each Generator, Line and Battery object is
  set to zero.

- The Maintenance Rate for each Generator, Line and Battery object is
  set to zero.

- The Mean Time to Repair for each Generator, Line and Battery object is
  set to zero.

- A new ST Schedule object that aggregates transmission regionally is created
  and associated with every Model, and all other phase memberships (PASA, MT,
  etc) are removed.

- A new Report object is created and associated with every Model.
  The new Report outputs the following properties for the Interval time period:

    - Region: Load
    - Line: Import Limit
    - Line: Export Limit
    - Line: x (FOR)
    - Line: y (MTTR)
    - Interface: Import Limit
    - Interface: Export Limit
    - Generator: Available Capacity
    - Generator: Installed Capacity
    - Generator: x (FOR)
    - Generator: y (MTTR)
    - Generator: z (Pump Efficiency or Pump Load)
    - Storage: Min Volume
    - Storage: Max Volume
    - Storage: Natural Inflow
    - Storage: x (Loss Rate)
    - Battery: Units
    - Battery: Installed Capacity
    - Battery: x (Charge Efficiency or FOR)
    - Battery: y (Discharge Efficiency or MTTR)
    - Battery: z (Energy Capacity)

