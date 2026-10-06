# Industrial Microgrid Electricity-Carbon Scheduling

MATLAB/YALMIP implementation accompanying **Low-Carbon Collaborative Scheduling
of Industrial Microgrids with Electrolytic Aluminum Load Considering
Electricity-Carbon Trading**. This standalone package contains the revised
formulation for replacing the earlier released implementation.

The entry scripts print command-window tables and return schedules in the
`results` cell array. They do not create figures or write result files.

## Files and Requirements

| File | Purpose |
| --- | --- |
| `Case_analysis.m` | Compare four market-mechanism cases. |
| `IMG_analysis.m` | Compare four resource configurations under Case 3. |
| `Sensitivity_analysis.m` | Reoptimize one input multiplier at a time. |
| `Verify_implementation.m` | Check input data, units, and CEA accounting. |
| `model/revision_parameters.m` | Shared parameter settings and package-relative paths. |
| `model/solve_revision_img.m` | Shared MILP constraints, objective, and result checks. |
| `model/run_revision_analysis.m` | Scenario selection and command-window tables. |
| `data_sources/` | Four numerical MAT input files and their documentation. |

Requirements: MATLAB R2024a or a compatible newer release, YALMIP, and Gurobi
with a valid license. The study used Gurobi 12.0.1. Add YALMIP and the Gurobi
MATLAB interface to the MATLAB path before running an optimization.
These third-party dependencies are not included.

The default solver settings are eight threads, seed 1, relative MIP gap
`1e-4`, and a 300-second limit per scenario. A nonzero YALMIP solve status raises
an error; an incomplete solve is not printed as an optimal result.

## Quick Start

Set the MATLAB current folder to this package, then run:

```matlab
Verify_implementation;       % Input, unit, and account checks; no solver needed
Case_analysis;              % Four market-mechanism cases
IMG_analysis;               % Four resource configurations
Sensitivity_analysis;       % Default: four inputs, five levels each
```

For a single principal case and a check of its solved account:

```matlab
addpath(fullfile(pwd,'model'));
results = run_revision_analysis('case',3);
Verify_implementation(results{1});
```

Edit `selectedCases`, `selectedIMGs`, or the seven sensitivity switches in the
entry scripts to select runs. Sensitivity levels are 0.6, 0.8, 1.0, 1.2, and
1.4 times the baseline; each non-baseline point is reoptimized with all other
inputs unchanged. The solved 1.0x baseline is reused. Percentage changes use
`100*(value-baseline)/abs(baseline)`; a zero baseline is displayed as `NaN`.
The four default inputs are electricity price, carbon price, aluminum price,
and initial free CEA allocation. GC-price sensitivity has no effect while
direct GC offsets remain disabled.

## Annual CEA Account

The carbon account follows Section 2.1.3 of the revised manuscript. All
allowance and emission quantities below are in tCO2.

| Manuscript quantity or restriction | Implementation |
| --- | --- |
| Fixed annual free allocation | `free`, calculated from rated annual production |
| Annual actual emissions before offsets | `annualEmission`, weighted ordinary/event-day emissions |
| Monthly purchases and sales | `buy(k)` and `sell(k)`, for 12 trading months |
| Initial inventory | `bank(1) == free` |
| Inventory after month k | `bank(k+1) == bank(k) + buy(k) - sell(k)` |
| No short selling | `bank >= 0` |
| Annual deficit | `max(annualEmission-free,0)` |
| Annual surplus | `max(free-annualEmission,0)` |
| Purchase limit | `sum(buy) <= deficit` |
| Sale limit before offsets | `sum(sell) <= surplus` |
| Annual surrender | `bank(end) + gcConversion*gc >= annualEmission` |
| Post-surrender balance | `bank(end) + gcConversion*gc - annualEmission` |

Monthly inventory updates contain transactions only. Emissions are surrendered
once at year end. A binary variable selects the deficit or surplus branch;
the finite bound is derived from maximum production and power limits. These
restrictions prevent buying allowances for resale.

An optional certificate offset can reduce the annual compliance obligation,
but cannot enter the CEA inventory or enlarge the pre-offset sale limit.
`allowGCOffset=false` in all principal runs. Direct GC-to-CEA conversion is
a hypothetical policy extension, separate from the principal comparisons.

CEA cost is the sum of monthly prices times net purchases. Cases 0--2 use the
same day-weighted annual-average price in all trading months; Case 3 uses the
monthly input prices. Trading rights and annual compliance restrictions are
the same across cases. Physical emissions are reported before offsets.

## Shared Settings and Units

- Power is MW, energy MWh, time h, production tAl, and monetary values CNY.
  Raw electricity prices in CNY/kWh are converted to CNY/MWh once on import.
  DR compensation and penalties in CNY/MWh multiply power and `dt=0.25 h`.
- Twelve monthly input profiles each have an ordinary-day schedule and an
  invited-event-day schedule: 353 ordinary days and 12 assumed DR days in a
  non-leap year. Every interval-based annual quantity uses these day weights.
  Annual CEA and certificate transactions are counted once.
- Each daily schedule has 96 controls and 97 SOC/temperature boundary states.
  SOC and temperature return to their initial values at the daily endpoint.
- EAL current is 0.90--1.05 p.u. with constant efficiency 0.94. Annual production
  stays within 95--105% of rated annual production. A net heat balance models
  thermal accumulation; its effective heat-loss coefficient follows nominal
  heat balance with an assumed ambient temperature of 25 degrees C.
- SOS2 interpolation of the electrical characteristic uses 0.01-p.u. current
  spacing. The corresponding maximum interpolation error is 0.00504 MW.
- Cases 0 and 1 have identical EAL flexibility; Case 1 enables DR. Case 2 adds
  electricity cost to the objective; Case 3 adds monthly CEA pricing. Actual
  electricity bills are included in the reported return for every case.
- IMG 0 contains EAL; IMG 1 adds PV and ESS; IMG 2 adds GT to EAL; IMG 3 contains
  EAL, PV, ESS, and GT. ESS capacity is 20 MWh with a 5-MW power limit. Import
  capacity is 500 MW with ESS and 495 MW without ESS.
- `NetOperatingReturn` is aluminum revenue plus DR revenue minus modeled
  electricity, GT, ESS degradation, CEA, and GC costs. The internal result field
  remains `NetProfit` for compatibility. Other industrial costs are outside
  this operating-return calculation.
- Known price profiles, zero transaction fees, a rated-power DR baseline, and
  the stated carbon-accounting boundary are study assumptions.

The package contains the revised heat equation only. Historical thermal-law
comparisons, manuscript plotting/export routines, and stored case-study
results are not required to run it and are not included.

## Data, Attribution, and License

Input data: Zhang, Guangdou (2026), Mendeley Data, V1,
[doi:10.17632/5sr93z33kd.1](https://data.mendeley.com/datasets/5sr93z33kd/1).
See `data_sources/README.md` for array layouts, units, and provenance.

The MATLAB source is distributed under the accompanying MIT License. Data
licensing and attribution are governed separately by the dataset record;
the code license does not replace the data license. Please cite the related
paper and dataset when using this work. MATLAB, YALMIP, and Gurobi retain
their respective licenses.
