# Open-Source MATLAB Code

This folder contains the MATLAB scripts used for the numerical analyses in the paper **"Low-Carbon Collaborative Scheduling of Industrial Microgrids"**.

The scripts in this folder are simplified open-source versions of the original analysis files. They keep the optimization models and command-line table outputs, while removing figure generation and file-export functions.

## Files

- `Case_analysis.m`  
  Solves the four market-mechanism cases and prints the economic comparison table in the MATLAB command window.

- `IMG_analysis.m`  
  Solves the four industrial microgrid (IMG) configurations and prints the economic comparison table in the MATLAB command window.

- `Sensitivity_analysis.m`  
  Performs one-at-a-time sensitivity analysis for Case 3. The default enabled parameters are electricity price, carbon price, aluminum selling price, and initial free CEA allowance. The script prints metric values, percentage changes relative to the 1.0x case, and solver status tables.

## Required Environment

- MATLAB
- YALMIP
- Gurobi Optimizer with a valid license

The optimization problems are formulated with YALMIP and solved using Gurobi.

## Required Data

The scripts expect a `data_sources` folder either:

1. next to the scripts in `Code_upload/data_sources`, or
2. in the parent project folder as `../data_sources`.

The following preprocessed MAT files are required:

- `price_data.mat`
- `cef_data.mat`
- `pv_data.mat`
- `cea_data.mat`

The original input dataset is available from Mendeley Data:

Zhang, Guangdou (2026), "The input dataset of the paper Low-Carbon Collaborative Scheduling of Industrial Microgrids", Mendeley Data, V1, doi: `10.17632/5sr93z33kd.1`.

## Usage

Run one of the scripts directly in MATLAB:

```matlab
Case_analysis
IMG_analysis
Sensitivity_analysis
```

The results are printed as MATLAB tables in the command window.

## License

The source code is released under the MIT License. If you use this code or the associated dataset, please cite the related paper and dataset DOI.
