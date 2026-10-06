clear; clc

% Reoptimize Case 3 at 0.6, 0.8, 1.0, 1.2, and 1.4 times each selected input.
% Only one input changes at a time; the solved 1.0x baseline is reused.
% Print annual values and percentage changes; no figures or files are generated.
addpath(fullfile(fileparts(mfilename('fullpath')), 'model'));
% Enable only the desired single-input perturbations. No capacity sweeps.
runElectricityPriceSensitivity = true;
runCarbonPriceSensitivity = true;
runAluminumPriceSensitivity = true;
runGasPriceSensitivity = false;
runDRCompensationPriceSensitivity = false;
runGreenCertificatePriceSensitivity = false;
% GC price has no effect in the principal setup because GC offsets are disabled.
runFreeAllowanceSensitivity = true;
fields = {'electricityPriceMultiplier','carbonPriceMultiplier', ...
    'aluminumPriceMultiplier','gasPriceMultiplier', ...
    'drCompensationPriceMultiplier','greenCertificatePriceMultiplier', ...
    'freeAllowanceMultiplier'};
enabled = [runElectricityPriceSensitivity,runCarbonPriceSensitivity, ...
    runAluminumPriceSensitivity,runGasPriceSensitivity, ...
    runDRCompensationPriceSensitivity,runGreenCertificatePriceSensitivity, ...
    runFreeAllowanceSensitivity];
assert(any(enabled),'No sensitivity parameter is enabled.');
results = run_revision_analysis('sensitivity',fields(enabled));

