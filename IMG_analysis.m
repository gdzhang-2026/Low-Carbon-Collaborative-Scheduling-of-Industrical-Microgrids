clear; clc

% IMG configuration analysis for the industrial microgrid scheduling model.
% This open-source version keeps only command-line table outputs.

imgNames = {'IMG 0', 'IMG 1', 'IMG 2', 'IMG 3'};
imgDescriptions = {
    'EAL only';
    'EAL + PV + ESS';
    'EAL + GT';
    'EAL + PV + ESS + GT'
};
imgResults = cell(1, 4);
for imgNo = 0:3
    fprintf('\n========== Solving IMG %d ==========\n', imgNo);
    try
        imgResults{imgNo+1} = solve_img_12M(imgNo);
    catch ME
        warning('IMG %d optimization failed. %s', imgNo, ME.message);
        imgResults{imgNo+1} = empty_img_result(imgNo, ME.message);
    end
end

compareTable = table(imgNames(:), imgDescriptions(:), ...
    string(cellfun(@(r) r.Status, imgResults(:), 'UniformOutput', false)), ...
    cellfun(@(r) r.PTieMax, imgResults(:)), ...
    cellfun(@(r) r.metrics.AluminumRevenue, imgResults(:)), ...
    cellfun(@(r) r.metrics.DRRevenue, imgResults(:)), ...
    cellfun(@(r) r.metrics.ElectricityCost, imgResults(:)), ...
    cellfun(@(r) r.metrics.GasCost, imgResults(:)), ...
    cellfun(@(r) r.metrics.ESSDegradation, imgResults(:)), ...
    cellfun(@(r) r.metrics.CETCost, imgResults(:)), ...
    cellfun(@(r) r.metrics.GCTCost, imgResults(:)), ...
    cellfun(@(r) r.metrics.NetProfit, imgResults(:)), ...
    cellfun(@(r) r.metrics.NGC, imgResults(:)), ...
    cellfun(@(r) r.metrics.QBuyTotal, imgResults(:)), ...
    cellfun(@(r) r.metrics.QSellTotal, imgResults(:)), ...
    string(cellfun(@(r) r.SolverInfo, imgResults(:), 'UniformOutput', false)), ...
    'VariableNames', {'IMG', 'Configuration', 'Status', 'PTieMax_MW', ...
    'AluminumRevenue_CNY', 'DRRevenue_CNY', 'ElectricityCost_CNY', ...
    'GTCost_CNY', 'ESSDegradation_CNY', 'CETCost_CNY', 'GCTCost_CNY', ...
    'NetProfit_CNY', 'NGC', 'QBuyTotal_tCO2', 'QSellTotal_tCO2', 'SolverInfo'});
disp(compareTable);

% The following local function solves each IMG configuration and returns economic metrics.

function result = solve_img_12M(imgNo)
    M = 12;
    T = 24;
    delta_t = 0.25;
    I = 1;
    N_t = M*T/delta_t;
    stepsPerMonth = T/delta_t;
    dataFolder = locate_data_sources();

    hasPV = imgNo == 1 || imgNo == 3;
    hasESS = imgNo == 1 || imgNo == 3;
    hasGT = imgNo == 2 || imgNo == 3;

    P_tie_max = img_tie_max(imgNo);

    I_N = 400e3;
    R_m = 1.26e-3;
    E_m = 472;
    P_N = 390.4;
    n_al = 262;
    K_al = 0.3356;
    eta_N = 0.94;
    T_N = 960;
    c_al = 1.44e10/3.6e9;

    E_ES = 20;
    eta_ch = 0.92;
    eta_dis = 0.92;
    SOC_min = 0.10;
    SOC_max = 0.90;
    SOC_ini = 0.50;
    P_ch_max = 5;
    P_dis_max = 5;
    pi_deg = 10;

    P_Gmin = 0;
    P_Gmax = 50;
    R_Gup = 10;
    R_Gdown = 10;
    pi_Gas = 350;
    e_Gas = 0.376;

    price = load(fullfile(dataFolder, 'price_data.mat'), 'price_data');
    price_data_12M = price.price_data(:, 2:end);
    check_monthly_data(price_data_12M, M, stepsPerMonth, 'price_data');
    pi_b = reshape(price_data_12M.', 1, []);

    cef = load(fullfile(dataFolder, 'cef_data.mat'), 'cef_data');
    cef_data_12M = cef.cef_data(:, 2:end);
    check_monthly_data(cef_data_12M, M, stepsPerMonth, 'cef_data');
    e_grid = reshape(cef_data_12M.', 1, []);

    pv = load(fullfile(dataFolder, 'pv_data.mat'), 'pv_data');
    pv_data_12M = pv.pv_data(:, 2:end);
    check_monthly_data(pv_data_12M, M, stepsPerMonth, 'pv_data');
    P_PV = reshape(pv_data_12M.', 1, []);
    if ~hasPV
        P_PV = zeros(1, N_t);
    end

    cea = load(fullfile(dataFolder, 'cea_data.mat'), 'cea_data');
    pi_C_month = cea.cea_data(:, 7).';
    if numel(pi_C_month) ~= M
        error('cea_data column 7 must contain %d monthly carbon price values.', M);
    end
    pi_C = kron(pi_C_month, ones(1, stepsPerMonth));

    T_DR = zeros(1, N_t);
    T_DR_start = {[8,17], [8,17], [8,12,18], [8,12,18], [8,12,18], ...
        [9,17], [9,17], [9,17], [8,12,20], [8,12,20], [8,12,20], [8,17]};
    T_DR_end = {[9,19], [9,19], [10,13,20], [10,13,20], [10,13,20], ...
        [10,19], [10,19], [10,19], [10,13,22], [10,13,22], [10,13,22], [9,19]};
    for m = 1:M
        base = (m-1)*stepsPerMonth;
        for k = 1:length(T_DR_start{m})
            idx_s = base + T_DR_start{m}(k)/delta_t;
            idx_e = base + T_DR_end{m}(k)/delta_t;
            T_DR(idx_s:idx_e) = 1;
        end
    end

    P_bid_vec = zeros(1, N_t);
    pi_DR = zeros(1, N_t);
    for m = 1:M
        base = (m-1)*stepsPerMonth;
        for k = 1:length(T_DR_start{m})
            idx_s = base + T_DR_start{m}(k)/delta_t;
            idx_e = base + T_DR_end{m}(k)/delta_t;
            h_start = T_DR_start{m}(k);
            if h_start == 8
                P_bid_vec(idx_s:idx_e) = 35;
            elseif h_start >= 17
                P_bid_vec(idx_s:idx_e) = 50;
            elseif h_start == 12
                P_bid_vec(idx_s:idx_e) = 40;
            end

            if h_start >= 17
                pi_DR(idx_s:idx_e) = 4000;
            else
                pi_DR(idx_s:idx_e) = 1500;
            end
        end
    end

    P_base = P_N;
    psi_DR = 5000;
    psi_over = 3000;
    theta_max = 1.2;

    pi_GC = 100;
    gamma_GC = 1;
    N_GC = sdpvar(1, 1);
    mu_EAL = 0.411;
    M_cN = 0.411;
    S_c = 0.02;
    A_c = 0.004;
    E_CF4 = 0.034e-3;
    E_C2F6 = 0.0034e-3;
    G_CF4 = 6500;
    G_C2F6 = 9200;

    I_EAL = sdpvar(I, N_t, 'full');
    P_EAL = sdpvar(I, N_t, 'full');
    T_EAL = sdpvar(I, N_t, 'full');
    M_EAL = sdpvar(I, N_t, 'full');
    E_ne = sdpvar(I, N_t, 'full');
    Q_buy = sdpvar(I, N_t, 'full');
    Q_sell = sdpvar(I, N_t, 'full');
    Q_bank = sdpvar(I, N_t, 'full');

    P_tie = sdpvar(I, N_t, 'full');
    P_ESS_ch = sdpvar(I, N_t, 'full');
    P_ESS_dis = sdpvar(I, N_t, 'full');
    S_SOC = sdpvar(I, N_t, 'full');
    P_Gas = sdpvar(I, N_t, 'full');

    P_act = sdpvar(I, N_t, 'full');
    P_comp = sdpvar(I, N_t, 'full');
    P_short = sdpvar(I, N_t, 'full');
    P_over = sdpvar(I, N_t, 'full');

    alpha_ch = binvar(I, N_t, 'full');
    alpha_dis = binvar(I, N_t, 'full');
    z_DR = binvar(5, N_t, 'full');

    Constraints = [];

    I_min = 0.9*I_N*ones(I, N_t);
    I_max = 1.05*I_N*ones(I, N_t);
    Constraints = [Constraints, I_min <= I_EAL & I_EAL <= I_max];
    Constraints = [Constraints, P_EAL == (I_EAL.*I_EAL*R_m + I_EAL*E_m)/1e6];
    P_min_val = (I_min.*I_min*R_m + I_min*E_m)/1e6;
    P_max_val = (I_max.*I_max*R_m + I_max*E_m)/1e6;
    Constraints = [Constraints, P_min_val <= P_EAL & P_EAL <= P_max_val];

    R_EAL = 0.05*P_N;
    for t = 2:N_t
        Constraints = [Constraints, -R_EAL <= P_EAL(I,t)-P_EAL(I,t-1) <= R_EAL];
        Constraints = [Constraints, (P_EAL(I,t)-P_EAL(I,t-1))*delta_t ...
            == c_al*(T_EAL(I,t)-T_EAL(I,t-1))];
    end
    T_EAL_min = 950;
    T_EAL_max = 970;
    Constraints = [Constraints, T_EAL_min*ones(I,N_t) <= T_EAL ...
        & T_EAL <= T_EAL_max*ones(I,N_t)];
    Constraints = [Constraints, I_EAL(I,1) == I_N, P_EAL(I,1) == P_N, ...
        T_EAL(I,1) == T_N];
    Constraints = [Constraints, M_EAL == n_al*K_al*eta_N*I_EAL*delta_t/1e6];

    if hasESS
        for t = 2:N_t
            Constraints = [Constraints, S_SOC(I,t) == S_SOC(I,t-1) ...
                + (eta_ch*P_ESS_ch(I,t) - P_ESS_dis(I,t)/eta_dis)*delta_t/E_ES];
        end
        Constraints = [Constraints, S_SOC(I,1) == SOC_ini];
        for m = 2:M
            firstIdx = (m-1)*stepsPerMonth + 1;
            prevIdx = firstIdx - 1;
            Constraints = [Constraints, S_SOC(I,firstIdx) == S_SOC(I,prevIdx) ...
                + (eta_ch*P_ESS_ch(I,firstIdx) - P_ESS_dis(I,firstIdx)/eta_dis)*delta_t/E_ES];
        end
        Constraints = [Constraints, S_SOC(I,end) == SOC_ini];
        Constraints = [Constraints, SOC_min <= S_SOC & S_SOC <= SOC_max];
        Constraints = [Constraints, 0 <= P_ESS_ch & P_ESS_ch <= alpha_ch*P_ch_max, ...
            0 <= P_ESS_dis & P_ESS_dis <= alpha_dis*P_dis_max, alpha_ch + alpha_dis <= 1];
    else
        Constraints = [Constraints, P_ESS_ch == 0, P_ESS_dis == 0, ...
            S_SOC == SOC_ini, alpha_ch == 0, alpha_dis == 0];
    end

    if hasGT
        Constraints = [Constraints, P_Gmin <= P_Gas & P_Gas <= P_Gmax];
        for t = 2:N_t
            Constraints = [Constraints, -R_Gdown*delta_t <= P_Gas(I,t)-P_Gas(I,t-1) <= R_Gup*delta_t];
        end
    else
        Constraints = [Constraints, P_Gas == 0];
    end

    Constraints = [Constraints, P_tie == P_EAL + P_ESS_ch - P_ESS_dis - P_Gas - P_PV];
    Constraints = [Constraints, P_tie <= P_tie_max];

    P_act_bigM = P_base - min(P_min_val, [], 'all') + P_dis_max*hasESS + P_Gmax*hasGT + max(P_PV);
    P_comp_bigM = theta_max * max(P_bid_vec);
    Constraints = [Constraints, 0 <= P_comp, 0 <= P_short, 0 <= P_over];
    for t = 1:N_t
        if T_DR(t) == 1
            Constraints = [Constraints, P_act(I,t) == P_base - P_tie(I,t), ...
                0 <= P_act(I,t) <= P_act_bigM];
            bid = P_bid_vec(t);
            z = z_DR(:, t);
            Constraints = [Constraints, sum(z) == 1];
            Constraints = [Constraints, ...
                P_act(I,t) >= 0.0*bid - P_act_bigM*(1-z(1)), ...
                P_act(I,t) <= 0.5*bid + P_act_bigM*(1-z(1)), ...
                P_act(I,t) >= 0.5*bid - P_act_bigM*(1-z(2)), ...
                P_act(I,t) <= 0.8*bid + P_act_bigM*(1-z(2)), ...
                P_act(I,t) >= 0.8*bid - P_act_bigM*(1-z(3)), ...
                P_act(I,t) <= 1.2*bid + P_act_bigM*(1-z(3)), ...
                P_act(I,t) >= 1.2*bid - P_act_bigM*(1-z(4)), ...
                P_act(I,t) <= 1.5*bid + P_act_bigM*(1-z(4)), ...
                P_act(I,t) >= 1.5*bid - P_act_bigM*(1-z(5))];
            Constraints = [Constraints, ...
                P_comp(I,t) <= P_comp_bigM*(1-z(1)), ...
                P_comp(I,t) >= 0.6*bid - P_comp_bigM*(1-z(2)), ...
                P_comp(I,t) <= 0.6*bid + P_comp_bigM*(1-z(2)), ...
                P_comp(I,t) >= P_act(I,t) - P_comp_bigM*(1-z(3)), ...
                P_comp(I,t) <= P_act(I,t) + P_comp_bigM*(1-z(3)), ...
                P_comp(I,t) >= theta_max*bid - P_comp_bigM*(1-z(4)), ...
                P_comp(I,t) <= theta_max*bid + P_comp_bigM*(1-z(4)), ...
                P_comp(I,t) >= theta_max*bid - P_comp_bigM*(1-z(5)), ...
                P_comp(I,t) <= theta_max*bid + P_comp_bigM*(1-z(5))];
            Constraints = [Constraints, ...
                P_short(I,t) >= bid - P_act_bigM*(1-z(1)), ...
                P_short(I,t) <= bid + P_act_bigM*(1-z(1)), ...
                P_short(I,t) <= P_act_bigM*(1-z(2)), ...
                P_short(I,t) <= P_act_bigM*(1-z(3)), ...
                P_short(I,t) <= P_act_bigM*(1-z(4)), ...
                P_short(I,t) <= P_act_bigM*(1-z(5))];
            Constraints = [Constraints, ...
                P_over(I,t) <= P_act_bigM*(1-z(1)), ...
                P_over(I,t) <= P_act_bigM*(1-z(2)), ...
                P_over(I,t) <= P_act_bigM*(1-z(3)), ...
                P_over(I,t) <= P_act_bigM*(1-z(4)), ...
                P_over(I,t) >= P_act(I,t) - 1.5*bid - P_act_bigM*(1-z(5)), ...
                P_over(I,t) <= P_act(I,t) - 1.5*bid + P_act_bigM*(1-z(5))];
        else
            Constraints = [Constraints, P_act(I,t) == 0, P_comp(I,t) == 0, ...
                P_short(I,t) == 0, P_over(I,t) == 0, z_DR(:,t) == 0];
        end
    end

    E_er = M_EAL * M_cN*(1-S_c-A_c)*44/12;
    E_ae = M_EAL * (E_CF4*G_CF4 + E_C2F6*G_C2F6);
    E_dir = E_er + E_ae + e_Gas*P_Gas*delta_t;
    for t = 1:N_t
        Constraints = [Constraints, E_ne(I,t) == e_grid(t)*P_tie(I,t)*delta_t];
    end

    E_act = sum(E_dir + E_ne, 'all');
    M_N_t = n_al*K_al*eta_N*I_N*delta_t/1e6;
    M_N_total = M_N_t*N_t;
    Q_free_total = mu_EAL*M_N_total;
    Constraints = [Constraints, 0 <= Q_buy, 0 <= Q_sell, 0 <= Q_bank, N_GC >= 0];
    Constraints = [Constraints, Q_bank(I,1) == Q_free_total + gamma_GC*N_GC ...
        + Q_buy(I,1) - Q_sell(I,1) - E_dir(I,1) - E_ne(I,1)];
    for t = 2:N_t
        Constraints = [Constraints, Q_bank(I,t) == Q_bank(I,t-1) ...
            + Q_buy(I,t) - Q_sell(I,t) - E_dir(I,t) - E_ne(I,t)];
    end
    Constraints = [Constraints, Q_bank(I,end) >= 0];
    Constraints = [Constraints, sum(Q_buy,'all') <= E_act];
    Constraints = [Constraints, sum(Q_sell,'all') <= Q_free_total + sum(Q_buy,'all') - E_act];

    C_CET = sum(sum(pi_C .* Q_buy)) - sum(sum(pi_C .* Q_sell));
    C_GCT = pi_GC*N_GC;

    pi_Al = 8000;
    R_Al = pi_Al * M_EAL;
    G_DR = sdpvar(I, N_t, 'full');
    C_e = sdpvar(I, N_t, 'full');
    C_Gas = sdpvar(I, N_t, 'full');
    C_deg = sdpvar(I, N_t, 'full');
    for t = 1:N_t
        G_DR(I,t) = pi_DR(t)*P_comp(I,t) - psi_DR*P_short(I,t) - psi_over*P_over(I,t);
        C_e(I,t) = pi_b(t)*P_tie(I,t)*delta_t*1000;
        C_Gas(I,t) = pi_Gas*P_Gas(I,t)*delta_t;
        C_deg(I,t) = pi_deg*(P_ESS_ch(I,t) + P_ESS_dis(I,t))*delta_t;
    end

    Objective = -(sum(R_Al,'all') + sum(G_DR,'all') ...
        - sum(C_e,'all') - sum(C_Gas,'all') - sum(C_deg,'all') - C_CET - C_GCT);

    options = sdpsettings('solver', 'gurobi');
    sol = optimize(Constraints, Objective, options);
    if sol.problem ~= 0
        error('IMG %d optimization failed: %s', imgNo, sol.info);
    end

    result.PTieMax = P_tie_max;
    result.Status = "Solved";
    result.SolverInfo = "";
    result.metrics.Objective = -value(Objective);
    result.metrics.AluminumRevenue = sum(value(R_Al),'all');
    result.metrics.DRRevenue = sum(value(G_DR),'all');
    result.metrics.ElectricityCost = sum(value(C_e),'all');
    result.metrics.GasCost = sum(value(C_Gas),'all');
    result.metrics.ESSDegradation = sum(value(C_deg),'all');
    result.metrics.CETCost = value(C_CET);
    result.metrics.GCTCost = value(C_GCT);
    result.metrics.NetProfit = result.metrics.AluminumRevenue + result.metrics.DRRevenue ...
        - result.metrics.ElectricityCost - result.metrics.GasCost ...
        - result.metrics.ESSDegradation - result.metrics.CETCost - result.metrics.GCTCost;
    result.metrics.NGC = value(N_GC);
    result.metrics.QBuyTotal = sum(value(Q_buy),'all');
    result.metrics.QSellTotal = sum(value(Q_sell),'all');

    summary = table({'Aluminum revenue'; 'DR revenue'; 'Electricity cost'; ...
        'GT cost'; 'ESS degradation'; 'CET cost'; 'GCT cost'; 'Net profit'}, ...
        [result.metrics.AluminumRevenue; result.metrics.DRRevenue; ...
        result.metrics.ElectricityCost; result.metrics.GasCost; ...
        result.metrics.ESSDegradation; result.metrics.CETCost; ...
        result.metrics.GCTCost; result.metrics.NetProfit], ...
        'VariableNames', {'Item', 'Value_CNY'});
    fprintf('IMG %d economic summary:\n', imgNo);
    disp(summary);
end

function result = empty_img_result(imgNo, solverInfo)
    result.PTieMax = img_tie_max(imgNo);
    result.Status = "Failed";
    result.SolverInfo = string(solverInfo);
    result.metrics.Objective = NaN;
    result.metrics.AluminumRevenue = NaN;
    result.metrics.DRRevenue = NaN;
    result.metrics.ElectricityCost = NaN;
    result.metrics.GasCost = NaN;
    result.metrics.ESSDegradation = NaN;
    result.metrics.CETCost = NaN;
    result.metrics.GCTCost = NaN;
    result.metrics.NetProfit = NaN;
    result.metrics.NGC = NaN;
    result.metrics.QBuyTotal = NaN;
    result.metrics.QSellTotal = NaN;
end

function P_tie_max = img_tie_max(imgNo)
    hasESS = imgNo == 1 || imgNo == 3;

    essTieAllowance = 20;
    P_tie_max = 500 - (~hasESS)*essTieAllowance;
end

function dataFolder = locate_data_sources()
    % Prefer a data_sources folder next to this open-source script.
    scriptFolder = fileparts(mfilename('fullpath'));
    candidateFolders = {
        fullfile(scriptFolder, 'data_sources');
        fullfile(fileparts(scriptFolder), 'data_sources')
    };

    for k = 1:numel(candidateFolders)
        if exist(candidateFolders{k}, 'dir')
            dataFolder = candidateFolders{k};
            return
        end
    end

    error('Cannot find data_sources. Place the required MAT files next to Code_upload or in the parent project folder.');
end

