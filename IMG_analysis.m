clear; clc

% Compare resource configurations under the same Case-3 market mechanisms.
% IMG 0: EAL only. IMG 1: EAL, PV, and ESS.
% IMG 2: EAL and GT. IMG 3: EAL, PV, ESS, and GT.
% The import limit is 500 MW with ESS and 495 MW without its 5-MW charging load.
% These are the revised manuscript settings, not the original 480-MW limits.
addpath(fullfile(fileparts(mfilename('fullpath')), 'model'));
selectedIMGs = 0:3;
results = run_revision_analysis('img', selectedIMGs);

