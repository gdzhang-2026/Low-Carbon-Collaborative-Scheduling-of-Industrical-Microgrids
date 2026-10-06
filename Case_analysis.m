clear; clc

% Compare market mechanisms using the same resource and production constraints.
% Case 0: no DR; electricity cost is excluded from the scheduling objective.
% Case 1: enable DR with the same EAL flexibility as Case 0.
% Case 2: additionally include electricity purchasing cost in the objective.
% Case 3: additionally use monthly rather than annual-average CEA prices.
% Actual electricity bills are included in the reported return for every case.
% Each entry in results contains schedules, annual metrics, and residual checks.
addpath(fullfile(fileparts(mfilename('fullpath')), 'model'));
selectedCases = 0:3;
results = run_revision_analysis('case', selectedCases);

