function r = solve_revision_img(p)
% Solve the shared revised formulation and return schedules and annual metrics.
% Daily states have 97 boundaries and 96 controls.
% Two schedules per monthly profile distinguish event and non-event days.
% An SOS2 interpolation of the electrical characteristic makes this an MILP.
yalmip('clear');
nt = 96; nd = 24; dt = p.dt;
% Odd columns represent ordinary days; even columns represent invited DR days.
month = repelem(1:12,2);
eventDay = repmat([false true],1,12);
weights = reshape([p.days-p.drDays; p.drDays],1,[]);
assert(all(weights>=0) && sum(weights)==365);
% Rows in each profile MAT file are months. Column 1 is the month index.
% Convert the imported electricity price from CNY/kWh to CNY/MWh exactly once.
data = fullfile(p.root,'data_sources');
v=load(fullfile(data,'price_data.mat')); price=1000*v.price_data(:,2:end).';
v=load(fullfile(data,'cef_data.mat')); cef=v.cef_data(:,2:end).';
v=load(fullfile(data,'pv_data.mat')); pv=v.pv_data(:,2:end).';
v=load(fullfile(data,'cea_data.mat')); cp=v.cea_data(:,7);
assert(isequal(size(price),[96 12]) && isequal(size(cef),[96 12]));
assert(isequal(size(pv),[96 12]) && isequal(size(cp),[12 1]));
assert(all(isfinite([price(:);cef(:);pv(:);cp(:)])) && ...
    all(cef(:)>=0) && all(pv(:)>=0) && all(cp(:)>=0));
price=price(:,month)*p.electricityPriceMultiplier;
cef=cef(:,month); pv=pv(:,month);
cp=cp*p.carbonPriceMultiplier;
hasESS=ismember(p.imgNo,[1 3]); hasPV=ismember(p.imgNo,[1 3]);
hasGT=ismember(p.imgNo,[2 3]);
if ~hasPV, pv(:)=0; end
% Remove only charging POWER (5 MW), not battery ENERGY (20 MWh).
tieMax=p.tieMaximum-(~hasESS)*p.essPower;
u=sdpvar(nt,nd,'full'); pe=sdpvar(nt,nd,'full');
% u is current in per unit; temperature and SOC are interval-boundary states.
temp=sdpvar(nt+1,nd,'full'); soc=sdpvar(nt+1,nd,'full');
ch=sdpvar(nt,nd,'full'); dis=sdpvar(nt,nd,'full');
mode=binvar(nt,nd,'full'); gt=sdpvar(nt,nd,'full');
tie=pe+ch-dis-gt-pv;
% Positive tie-line power denotes imports; electricity export is excluded.
f=[0<=tie<=tieMax, p.temperatureLimits(1)<=temp<=p.temperatureLimits(2), ...
   p.socLimits(1)<=soc<=p.socLimits(2), 0<=ch<=hasESS*p.essPower*mode, ...
   0<=dis<=hasESS*p.essPower*(1-mode), 0<=gt<=hasGT*p.gtMaximum];
bp=p.currentBreakpoints; bpP=p.resistance*(p.ratedCurrent*bp).^2+ ...
    p.backEMF*p.ratedCurrent*bp/1000;
% SOS2 weights interpolate adjacent current/power breakpoints only.
for d=1:nd
    if p.fixedEAL
        f=[f,u(:,d)==1,pe(:,d)==p.ratedPower];
    else
        lam=sdpvar(numel(bp),nt,'full');
        f=[f,lam>=0,sum(lam,1)==1,u(:,d)==(bp*lam).',pe(:,d)==(bpP*lam).'];
        f=[f,sos2(lam.')];
    end
    % Electrical power minus the back-EMF term supplies the effective heat input.
    % Heat loss follows the nominal balance and the stated ambient assumption.
    q=pe(:,d)-p.backEMF*p.ratedCurrent*u(:,d)/1000;
    thermalChange=dt*(q-p.heatConductance* ...
        (temp(1:end-1,d)-p.ambientTemperature));
    % Daily endpoint constraints close both the thermal and storage cycles.
    f=[f,temp(1,d)==p.ratedTemperature,temp(end,d)==p.ratedTemperature, ...
        p.heatCapacity*diff(temp(:,d))==thermalChange, ...
        soc(1,d)==p.initialSOC,soc(end,d)==p.initialSOC, ...
        p.essCapacity*diff(soc(:,d))==dt*(p.essEfficiency*ch(:,d)-dis(:,d)/p.essEfficiency), ...
        -p.ealRamp<=diff([p.ratedPower;pe(:,d);p.ratedPower])<=p.ealRamp, ...
        -p.ealRamp<=pe(1,d)-pe(end,d)<=p.ealRamp, ...
        -p.gtRamp*dt<=diff([gt(end,d);gt(:,d)])<=p.gtRamp*dt];
end
production=p.cells*p.faraday*p.ratedCurrent*p.currentEfficiency*dt*u;
% Weight each daily schedule once when calculating annual output and emissions.
annualProduction=sum(production,1)*weights.';
nominalProduction=p.cells*p.faraday*p.ratedCurrent*p.currentEfficiency*24*365;
f=[f,p.minimumProductionRatio*nominalProduction<=annualProduction<= ...
    p.maximumProductionRatio*nominalProduction];
% Prescribed DR invitations, in hours of day. Awards are not optimized bids.
starts={[8 17],[8 17],[8 12 18],[8 12 18],[8 12 18],[9 17], ...
    [9 17],[9 17],[8 12 20],[8 12 20],[8 12 20],[8 17]};
ends={[9 19],[9 19],[10 13 20],[10 13 20],[10 13 20],[10 19], ...
    [10 19],[10 19],[10 13 22],[10 13 22],[10 13 22],[9 19]};
bid=zeros(nt,nd); tariff=bid;
for d=1:nd
    if ~eventDay(d) || p.caseNo<1 || ~p.enableDR, continue; end
    m=month(d);
    for j=1:numel(starts{m})
        h=starts{m}(j); idx=h/dt+1:ends{m}(j)/dt;
        if h>=17, b=50; c=p.drPrice(2);
        elseif h==12, b=40; c=p.drPrice(1);
        else, b=35; c=p.drPrice(1); end
        bid(idx,d)=b; tariff(idx,d)=c*p.drCompensationPriceMultiplier;
    end
end
act=sdpvar(nt,nd,'full'); comp=sdpvar(nt,nd,'full');
short=sdpvar(nt,nd,'full'); over=sdpvar(nt,nd,'full');
active=find(bid>0); inactive=find(bid==0);
f=[f,act(inactive)==0,comp(inactive)==0,short(inactive)==0,over(inactive)==0, ...
    act(active)==p.ratedPower-tie(active),act(active)>=0, ...
    comp(active)>=0,short(active)>=0,over(active)>=0];
z=binvar(5,numel(active),'full');
% Select one of five performance intervals and enforce its settlement rule.
% Shared threshold endpoints retain the revised model's MILP convention.
f=[f,sum(z,1)==1];
big=2*p.tieMaximum;
if ~isempty(active)
    b=bid(active).'; a=act(active).'; zerosA=zeros(size(b));
    lo=[0 .5 .8 1.2 1.5].'*b;
    hi=[[.5 .8 1.2 1.5].'*b; p.ratedPower*ones(size(b))];
    cv=[zerosA;.6*b;a;p.compensationCap*b;p.compensationCap*b];
    sv=[b;repmat(zerosA,4,1)]; ov=[repmat(zerosA,4,1);a-1.5*b];
    for j=1:5
        f=[f,lo(j,:)-big*(1-z(j,:))<=a<=hi(j,:)+big*(1-z(j,:)), ...
            -big*(1-z(j,:))<=comp(active).'-cv(j,:)<=big*(1-z(j,:)), ...
            -big*(1-z(j,:))<=short(active).'-sv(j,:)<=big*(1-z(j,:)), ...
            -big*(1-z(j,:))<=over(active).'-ov(j,:)<=big*(1-z(j,:))];
    end
end
% CNY/MWh times MW times hours gives interval compensation/penalties in CNY.
dr=(tariff.*comp-p.shortfallPrice*short-p.excessPrice*over)*dt;
al=p.aluminumPrice*p.aluminumPriceMultiplier*production;
ce=price.*tie*dt;
cg=p.gasPrice*p.gasPriceMultiplier*gt*dt;
cd=p.degradationPrice*(ch+dis)*dt;
edir=p.ealEmissionFactor*production+p.gtEmissionFactor*gt*dt;
eind=cef.*tie*dt;
annualEmission=sum(edir+eind,1)*weights.';
% Fixed free allocation uses rated annual output, not optimized production.
free=p.freeAllowanceFactor*p.freeAllowanceMultiplier*nominalProduction;
buy=sdpvar(12,1); sell=sdpvar(12,1); bank=sdpvar(13,1);
gc=sdpvar(1); deficit=sdpvar(1); surplus=sdpvar(1); hasDeficit=binvar(1);
% CEA quantities are in tCO2. bank(1) is the initial annual allocation;
% bank(k+1) is the inventory after purchases/sales in month k.
% deficit = max(annualEmission-free,0); surplus = max(free-annualEmission,0).
% The binary variable makes deficit and surplus mutually exclusive.
% The finite bound follows from maximum process, grid, and GT emissions.
emax=365*24*(p.ealEmissionFactor*p.cells*p.faraday*p.ratedCurrent* ...
    p.currentEfficiency*1.05+max(cef(:))*tieMax+p.gtEmissionFactor*p.gtMaximum);
bound=emax+free+1;
f=[f,buy>=0,sell>=0,bank>=0,gc>=0,deficit>=0,surplus>=0, ...
    deficit-surplus==annualEmission-free, ...
    deficit<=bound*hasDeficit,surplus<=bound*(1-hasDeficit), ...
    sum(sell)<=surplus, sum(buy)<=deficit, ...
    p.gcConversion*gc<=deficit,bank(1)==free, ...
    bank(2:end)==bank(1:end-1)+buy-sell, ...
    bank(end)+p.gcConversion*gc>=annualEmission];
% R1.6 accounting correspondence:
% - Purchases are capped by annual emissions exceeding the free allocation.
% - Sales are capped by the free allocation exceeding emissions BEFORE offsets.
% - Monthly updates contain transactions only; no monthly emissions are deducted.
% - The final constraint surrenders annual emissions once, at year end.
% - GC offsets affect final compliance only, never the CEA inventory/sale cap.
% These restrictions exclude short selling and purchasing allowances for resale.
if ~p.allowGCOffset, f=[f,gc==0]; end
% Cases 0--2 settle at one annual weighted price, to isolate timing in Case 3.
if p.caseNo<3
    priceC=repmat((p.days*cp)/365,12,1);
else
    priceC=cp;
end
cet=priceC.'*(buy-sell);
gct=p.gcPrice*p.greenCertificatePriceMultiplier*gc;
allCost=sum(al+dr-cg-cd,1)*weights.'-cet-gct;
if p.caseNo>=2, obj=allCost-sum(ce,1)*weights.'; else, obj=allCost; end
ops=sdpsettings('solver','gurobi','verbose',p.verbose,'savesolveroutput',1, ...
    'gurobi.TimeLimit',p.timeLimit,'gurobi.MIPGap',p.mipGap, ...
    'gurobi.Threads',8,'gurobi.Seed',1);
% Older YALMIP defaults include a negative TuneTimeLimit rejected by Gurobi 12.
ops.gurobi.TuneTimeLimit=0;
tic; diagnostics=optimize(f,-obj/1e6,ops); elapsed=toc;
if diagnostics.problem~=0
    error('Revision:Unsolved','Case %d IMG %d: %s',p.caseNo,p.imgNo,diagnostics.info);
end
r.parameters=p; r.weights=weights; r.month=month; r.eventDay=eventDay;
r.thermalModel='heat-balance';
r.current=value(u); r.power=value(pe); r.temperature=value(temp);
r.soc=value(soc); r.charge=value(ch); r.discharge=value(dis); r.gt=value(gt);
r.tie=value(tie); r.pv=pv; r.production=value(production);
r.direct=value(edir); r.indirect=value(eind); r.act=value(act);
r.comp=value(comp); r.short=value(short); r.over=value(over); r.bid=bid;
r.buy=value(buy); r.sell=value(sell); r.bank=value(bank); r.free=free;
r.gc=value(gc); r.solveSeconds=elapsed; r.solver=diagnostics.solveroutput;
r.metrics.AluminumRevenue=value(sum(al,1)*weights.');
r.metrics.DRRevenue=value(sum(dr,1)*weights.');
r.metrics.ElectricityCost=value(sum(ce,1)*weights.');
r.metrics.GTCost=value(sum(cg,1)*weights.');
r.metrics.ESSDegradation=value(sum(cd,1)*weights.');
r.metrics.CETCost=value(cet); r.metrics.GCTCost=value(gct);
% Keep this internal field name for compatibility; tables use NetOperatingReturn.
r.metrics.NetProfit=value(allCost-sum(ce,1)*weights.');
r.metrics.Production=value(annualProduction);
r.metrics.DirectEmissions=value(sum(edir,1)*weights.');
r.metrics.IndirectEmissions=value(sum(eind,1)*weights.');
r.metrics.TotalEmissions=value(annualEmission);
r.metrics.EmissionIntensity=value(annualEmission/annualProduction);
r.metrics.FreeCEA=free; r.metrics.PurchasedCEA=value(sum(buy));
r.metrics.SoldCEA=value(sum(sell)); r.metrics.GC=value(gc);
r.metrics.FinalBalance=value(bank(end)+p.gcConversion*gc-annualEmission);
r.metrics.SolveSeconds=elapsed;
% Independent physical/accounting residuals; never rely only on solver status.
qp=r.power-p.backEMF*p.ratedCurrent*r.current/1000;
thermalChange=dt*(qp-p.heatConductance* ...
    (r.temperature(1:end-1,:)-p.ambientTemperature));
r.checks.heatResidual=max(abs(p.heatCapacity*diff(r.temperature)- ...
    thermalChange),[],'all');
r.checks.socResidual=max(abs(p.essCapacity*diff(r.soc)- ...
    dt*(p.essEfficiency*r.charge-r.discharge/p.essEfficiency)),[],'all');
r.checks.exactPowerError=max(abs(r.power-(p.resistance*(p.ratedCurrent*r.current).^2+ ...
    p.backEMF*p.ratedCurrent*r.current/1000)),[],'all');
r.checks.bankResidual=max(abs(diff(r.bank)-r.buy+r.sell));
r.checks.minConstraintResidual=min(check(f));
r.checks.ealBoundaryRamp=max(abs(r.power(1,:)-r.power(end,:)));
assert(r.checks.ealBoundaryRamp<=p.ealRamp+1e-5);
assert(r.checks.heatResidual<1e-4 && r.checks.socResidual<1e-4);
assert(r.checks.bankResidual<1e-4 && r.metrics.FinalBalance>=-1e-3);
% Check the sale and purchase bounds against numeric pre-offset emissions.
annualDeficit=max(r.metrics.TotalEmissions-r.free,0);
annualSurplus=max(r.free-r.metrics.TotalEmissions,0);
assert(r.metrics.PurchasedCEA<=annualDeficit+1e-3);
assert(r.metrics.SoldCEA<=annualSurplus+1e-3);
assert(r.gc*p.gcConversion<=annualDeficit+1e-3);
assert(min(r.bank)>=-1e-5 && abs(r.bank(1)-r.free)<1e-4);
if ~p.allowGCOffset, assert(abs(r.gc)<1e-5); end
end
