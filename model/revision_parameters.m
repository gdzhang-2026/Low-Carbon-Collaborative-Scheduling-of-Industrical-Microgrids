function p = revision_parameters()
% Shared assumptions for all three analyses; paths are relative to this package.
% Power: MW. Energy: MWh. Time: h. Money: CNY. Production: tAl.
p.root = fileparts(fileparts(mfilename('fullpath')));
% One ordinary schedule and one invited-DR schedule per monthly input profile.
p.dt = 0.25;
p.days = [31 28 31 30 31 30 31 31 30 31 30 31];
p.ratedCurrent = 400; % kA
p.resistance = 1.26e-3; % ohm
p.backEMF = 472; % V
p.ratedPower = 390.4; % MW
p.ratedTemperature = 960; % degC
p.temperatureLimits = [950 970];
p.heatCapacity = 4; % MWh/degC, retained from the original case study
% Effective conductance is a transparent reduced-model assumption, not a fit.
% At rated current, Joule heating balances the equivalent ambient heat loss.
p.ambientTemperature = 25;
p.heatConductance = p.resistance*p.ratedCurrent^2 / ...
    (p.ratedTemperature-p.ambientTemperature);
p.currentBreakpoints = unique([0.90:0.01:1.05, 1.0, 1.05]);
p.currentEfficiency = 0.94;
p.cells = 262;
p.faraday = 0.0003356; % tAl/(kA h)
p.minimumProductionRatio = 0.95; % disclosed order assumption, not plant data
p.maximumProductionRatio = 1.05;
p.ealRamp = 0.05*p.ratedPower;
p.essCapacity = 20; % MWh, an energy capacity
p.essPower = 5; % MW, the charge/discharge power limit
p.essEfficiency = 0.92;
p.socLimits = [0.1 0.9];
p.initialSOC = 0.5;
p.gtMaximum = 50;
p.gtRamp = 10; % MW/h
p.tieMaximum = 500;
p.aluminumPrice = 8000; % CNY/tAl
p.gasPrice = 350; % CNY/MWh of GT generation
p.degradationPrice = 10; % CNY/MWh of charge/discharge throughput
p.gtEmissionFactor = 0.376; % tCO2/MWh
% Process emissions: carbon-anode consumption plus anode-effect equivalents.
p.ealEmissionFactor = 0.411*(1-0.02-0.004)*44/12 + ...
    0.034e-3*6500 + 0.0034e-3*9200;
p.freeAllowanceFactor = 0.411; % tCO2/tAl; illustrative benchmark allocation
p.gcPrice = 100; % CNY/certificate
p.gcConversion = 1; % tCO2/certificate, hypothetical conversion only
p.allowGCOffset = false; % no direct GC-to-CEA compliance conversion in main runs
p.shortfallPrice = 5000; % CNY/MWh
p.excessPrice = 3000; % CNY/MWh
p.drPrice = [1500 4000]; % CNY/MWh; all DR rates multiply power and dt
p.compensationCap = 1.2;
p.drDays = ones(1,12); % one invited event day per month; scenario assumption
p.caseNo = 3;
p.enableDR = true;
p.imgNo = 3;
p.fixedEAL = false; % shared flexibility in Cases 0--3
p.verbose = 0; % tables only; set to 1 to inspect the solver log
p.timeLimit = 300;
p.mipGap = 1e-4;
% Monetary/allocation perturbations; equipment capacities are held unchanged.
p.electricityPriceMultiplier = 1;
p.carbonPriceMultiplier = 1;
p.aluminumPriceMultiplier = 1;
p.gasPriceMultiplier = 1;
p.drCompensationPriceMultiplier = 1;
p.greenCertificatePriceMultiplier = 1;
p.freeAllowanceMultiplier = 1;
end
