# Worksheet Modification Process

The worksheet modification utility creates a copy of the input database with the following changes:

 - The pass-through output property `x` for each Generator object is assigned (or reassigned, if already in use) to mirror each Generator's Forced Outage Rate input property.

 - The pass-through output property `y` for each Generator object is assigned (or reassigned, if already in use) to mirror each Generator's Mean Time to Repair input property.

- The Forced Outage Rate for each Generator object is set to zero.

- The Maintenance Rate for each Generator object is set to zero.

- A new ST Schedule object that aggregates transmission regionally is created and associated with every Model.

- A new Report object is created and associated with every Model. The new Report outputs the following properties for the Interval time period:

    - Region: Load
	- Region.Region: Available Transfer Capacity
    - Generator: Available Capacity
    - Generator: x (FOR)
    - Generator: y (MTTR)
