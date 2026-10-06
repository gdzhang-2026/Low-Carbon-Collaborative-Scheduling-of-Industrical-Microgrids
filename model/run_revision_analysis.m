function results = run_revision_analysis(kind, selected)
% Run selected comparisons and print tables without creating graphics or files.
% NetProfit is retained as an internal field for compatibility; the displayed
% NetOperatingReturn excludes unmodeled raw materials, labor, CAPEX, and taxes.
p=revision_parameters(); results={};
if strcmpi(kind,'case') || strcmpi(kind,'img')
    if nargin<2, selected=0:3; end
    validateattributes(selected,{'numeric'}, ...
        {'vector','nonempty','integer','>=',0,'<=',3});
    selected=selected(:).';
    tb=table();
    for k=selected
        q=p;
        % All cases retain flexible EAL; only the stated mechanisms differ.
        if strcmpi(kind,'case'), q.caseNo=k; else, q.imgNo=k; end
        r=solve_revision_img(q); results{end+1}=r;
        row=struct2table(r.metrics); row.Scenario=string(sprintf('%s %d',upper(kind),k));
        row.Properties.VariableNames{'NetProfit'}='NetOperatingReturn';
        tb=[tb;row];
    end
    disp(tb);
elseif strcmpi(kind,'sensitivity')
    allowed={'electricityPriceMultiplier','carbonPriceMultiplier', ...
        'aluminumPriceMultiplier','gasPriceMultiplier', ...
        'drCompensationPriceMultiplier','greenCertificatePriceMultiplier', ...
        'freeAllowanceMultiplier'};
    if nargin<2
        selected={'electricityPriceMultiplier','carbonPriceMultiplier', ...
            'aluminumPriceMultiplier','freeAllowanceMultiplier'};
    end
    if isstring(selected), selected=cellstr(selected); end
    assert(iscellstr(selected) && ~isempty(selected) && ...
        all(ismember(selected,allowed)), 'Choose a supported input multiplier.');
    base=solve_revision_img(p); levels=[.6 .8 1 1.2 1.4];
    fields={'AluminumRevenue','DRRevenue','ElectricityCost','GTCost', ...
        'ESSDegradation','CETCost','GCTCost','NetProfit'};
    for j=1:numel(selected)
        key=selected{j}; assert(isfield(p,key),'Unknown parameter.');
        raw=zeros(numel(fields),5); tb=table();
        for k=1:5
            q=p; q.(key)=levels(k);
            if levels(k)==1, r=base; else, r=solve_revision_img(q); end
            results{end+1}=r;
            row=struct2table(r.metrics); row.Multiplier=levels(k);
            row.Properties.VariableNames{'NetProfit'}='NetOperatingReturn';
            tb=[tb;row];
            for a=1:numel(fields), raw(a,k)=r.metrics.(fields{a}); end
        end
        % A zero baseline has no defined percentage change; retain NaN.
        pct=100*(raw-raw(:,3))./abs(raw(:,3));
        pct(abs(raw(:,3))<1e-7,:)=nan;
        fprintf('\n%s: annual values, then percentage changes\n',key); disp(tb);
        labels=fields; labels{end}='NetOperatingReturn';
        disp(array2table(pct,'VariableNames',{'x06','x08','x10','x12','x14'},'RowNames',labels));
    end
else
    error('Use case, img, or sensitivity.');
end
end
