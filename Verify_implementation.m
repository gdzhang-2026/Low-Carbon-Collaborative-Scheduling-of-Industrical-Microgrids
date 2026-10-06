function checks = Verify_implementation(r)
% Run data, unit, and CEA-account checks without solving an optimization problem.
% Call Verify_implementation() for lightweight checks.
% Call Verify_implementation(results{1}) to check an already solved result.
addpath(fullfile(fileparts(mfilename('fullpath')), 'model'));
p=revision_parameters();
assert(p.dt==0.25 && sum(p.days)==365);
assert(sum(p.drDays)==12 && sum(p.days-p.drDays)==353);
assert(~p.allowGCOffset && ~p.fixedEAL);
assert(p.essCapacity==20 && p.essPower==5);
assert(p.tieMaximum-p.essPower==495);
assert(abs(p.resistance*p.ratedCurrent^2+ ...
    p.backEMF*p.ratedCurrent/1000-p.ratedPower)<1e-10);

% MAT data dimensions, month ordering, and raw input units.
names={'price_data','cef_data','pv_data','cea_data'};
for k=1:numel(names)
    key=names{k}; loaded=load(fullfile(p.root,'data_sources',[key '.mat']));
    assert(isfield(loaded,key), 'Missing input array: %s',key);
    a=loaded.(key);
    expectedColumns=97;
    if strcmp(key,'cea_data'), expectedColumns=7; end
    assert(isequal(size(a),[12 expectedColumns]));
    assert(isequal(a(:,1),(1:12).') && all(isfinite(a(:))));
    if ~strcmp(key,'price_data'), assert(all(a(:,2:end)>=0,'all')); end
end
% Electricity and DR are energy settlements: CNY/MWh * MW * h.
assert(abs(0.5*1000*40*p.dt-5000)<1e-10);
assert(abs(1500*40*p.dt-15000)<1e-10);

% Rated Joule heating balances the assumed ambient heat loss.
heat=p.resistance*p.ratedCurrent^2;
loss=p.heatConductance*(p.ratedTemperature-p.ambientTemperature);
assert(abs(heat-loss)<1e-10);

% Deficit, surplus, and optional-offset examples exercise all account branches.
% They are algebraic checks, not additional case-study results.
annualEmissions=[100;100;100]; freeCEA=[60;140;60]; offsets=[0;0;30];
deficit=max(annualEmissions-freeCEA,0);
surplus=max(freeCEA-annualEmissions,0);
buys=zeros(12,3); sells=buys;
buys(4,:)=(deficit-offsets).'; sells(9,:)=surplus.';
inventory=[freeCEA.';freeCEA.'+cumsum(buys-sells,1)];
finalBalance=inventory(end,:).'+offsets-annualEmissions;
assert(all(inventory>=0,'all'));
assert(all(sum(buys,1).'<=(deficit+1e-10)));
assert(all(sum(sells,1).'<=(surplus+1e-10)));
assert(all(offsets<=deficit) && all(abs(finalBalance)<1e-10));
assert(all(abs(diff(inventory)-buys+sells)<1e-10,'all'));
checks=table(["Deficit";"Surplus";"OptionalOffset"],annualEmissions, ...
    freeCEA,offsets,sum(buys,1).',sum(sells,1).',finalBalance, ...
    'VariableNames',{'Check','Emissions','FreeCEA','Offset','PurchasedCEA', ...
    'SoldCEA','PostSurrenderBalance'});
disp(checks);

if nargin>0
    % Recalculate annual emissions from interval schedules and day weights.
    emissions=sum(r.direct+r.indirect,1)*r.weights.';
    free=r.free; purchased=sum(r.buy); sold=sum(r.sell);
    offset=r.parameters.gcConversion*r.gc;
    balance=r.bank(end)+offset-emissions;
    assert(abs(emissions-r.metrics.TotalEmissions)<1e-3);
    assert(abs(r.bank(1)-free)<1e-4 && min(r.bank)>=-1e-5);
    assert(max(abs(diff(r.bank)-r.buy+r.sell))<1e-4);
    assert(purchased<=max(emissions-free,0)+1e-3);
    assert(sold<=max(free-emissions,0)+1e-3);
    assert(offset<=max(emissions-free,0)+1e-3 && balance>=-1e-3);
    assert(abs(balance-r.metrics.FinalBalance)<1e-4);
    if ~r.parameters.allowGCOffset, assert(abs(r.gc)<1e-5); end
    assert(max(abs(r.tie-r.power-r.charge+r.discharge+r.gt+r.pv),[],'all')<1e-5);
    assert(r.checks.heatResidual<1e-4 && r.checks.socResidual<1e-4);
    assert(max(abs(r.power(1,:)-r.power(end,:)))<=r.parameters.ealRamp+1e-5, ...
        'EAL last-to-first power change exceeds the repeated-day ramp limit.');
    numeric=table(emissions,free,purchased,sold,offset,r.bank(end),balance, ...
        'VariableNames',{'AnnualEmissions','InitialFreeCEA','PurchasedCEA', ...
        'SoldCEA','OptionalOffset','PreSurrenderInventory','PostSurrenderBalance'});
    fprintf('\nSolved annual account (tCO2):\n'); disp(numeric);
end
fprintf('All requested implementation checks passed.\n');
end
