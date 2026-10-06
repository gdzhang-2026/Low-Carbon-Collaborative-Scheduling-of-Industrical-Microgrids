# Numerical Inputs

These four MAT files provide the numerical inputs for the shared model.
Each MAT file contains one numeric array with the same name as the file stem.

| MAT file / array | Shape | Columns | Units |
| --- | --- | --- | --- |
| `price_data` | 12 x 97 | Month index, then 96 quarter-hourly prices | CNY/kWh |
| `cef_data` | 12 x 97 | Month index, then 96 quarter-hourly factors | tCO2/MWh |
| `pv_data` | 12 x 97 | Month index, then 96 quarter-hourly PV outputs | MW |
| `cea_data` | 12 x 7 | Month, open, close, high, low, volume, average | Prices: CNY/tCO2; volume: tCO2 |

Rows are January through December. The intraday values describe 96 intervals
beginning at 00:00, 00:15, ..., 23:45. The solver transposes each profile to
time-by-month format and reads column 7 of `cea_data` as the monthly carbon
price. It converts electricity prices from CNY/kWh to CNY/MWh once.

Electricity and PV profiles originate from an industrial park in Yunnan,
China, and were preprocessed and anonymized by the authors. The DCEF profiles
were preprocessed from the team's published dataset:

Li, Y., Zhang, S., Li, W. et al. High temporal and spatial resolution projected
electricity carbon emission factors of China from 2025-2060. Scientific Data
(2026). DOI: 10.1038/s41597-026-07272-6.

The CEA observations are from the Chinese carbon market. The source dataset,
including its separate license and citation information, is available at
[Mendeley Data](https://data.mendeley.com/datasets/5sr93z33kd/1): Zhang,
Guangdou (2026), V1, DOI: 10.17632/5sr93z33kd.1.
