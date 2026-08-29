# Data instructions

The raw flight file is deliberately excluded from this repository.

The analysis expects a January 2019 CSV containing these fields:

- `YEAR`, `DAY_OF_WEEK`, `FL_DATE`
- `ORIGIN_AIRPORT_ID`, `ORIGIN_CITY_NAME`
- `DEST_AIRPORT_ID`, `DEST_CITY_NAME`
- `DEP_DELAY`, `ARR_TIME`, `ARR_DELAY`, `ARR_DELAY_NEW`, `ARR_DEL15`

Download the corresponding On-Time Performance data from the U.S. Department
of Transportation Bureau of Transportation Statistics:

<https://www.bts.gov/airline-data-downloads>

Place the downloaded CSV anywhere outside the Git repository and pass its path
to `run.R`. This avoids committing a large raw extract and keeps the data source
and retrieval process explicit.

The locally supplied course extract used for verification was named
`Flights1_2019_1 (1).csv`; it is not redistributed here.
