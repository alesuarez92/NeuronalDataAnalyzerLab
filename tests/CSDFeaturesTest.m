%% CSDFeaturesTest.m
% =========================================================================
% UNIT TESTS FOR THE CSD METHODS (core/CSDMethods) ON KNOWN GROUND TRUTH
% =========================================================================
% core/demo/demoCSD builds laminar potentials from a known CSD (a Gaussian
% sink with balancing sources, discs of 500 um diameter, forward-modelled
% with the disc solution of Pettersen et al. 2006). The tests check that:
%   - every method (standard, iCSD delta / step / spline, kCSD) puts the
%     sink within one contact of the true depth;
%   - with sources of finite lateral extent the inverse methods have a
%     lower relative L2 error and a higher correlation with the true CSD
%     than the standard second derivative, and kCSD (and delta iCSD on the
%     8-contact probe) also near the probe ends;
%   - the standard method is unchanged: bit-identical to ERPAnalysis.csd
%     on DemoData's LFP ERP; the other methods find the demo sink too;
%   - kCSD cross-validation picks a finite, positive lambda, and more
%     regularisation for noisier data;
%   - units: forward-inverse round trips, linearity in V, 1 / sigma
%     scaling, the disc formula, and standard x sigma = CSD for laterally
%     infinite sources;
%   - bad inputs raise NeuroAnalyzer:CSDMethods:* errors.
% Errors are relative L2 (||est - true|| / ||true||) and Pearson
% correlation over contacts x time; the standard method is multiplied by
% sigma (0.3 S/m) to give A/m^3.
% =========================================================================

function tests = CSDFeaturesTest
    tests = functiontests(localfunctions);
end

%% setupOnce - Paths
function setupOnce(~)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'demo'));
end

%% --------------------------------------------------------- Demo ground truth

function testDemoGroundTruth(tests)
    s = demoCSD('laminar16');
    tr = s.truth;
    verifySize(tests, s.potentials, [16 numel(s.t)]);
    verifyEqual(tests, s.depthsUm, (1:16) * 100);
    verifyEqual(tests, tr.sinkContact, 8);
    verifyEqual(tests, tr.sinkTimeS, 0.015, 'AbsTol', 1e-12);
    % Balanced: no net current across depth
    net = sum(tr.csdGrid, 1) * (tr.zGridUm(2) - tr.zGridUm(1)) * 1e-6;       % A/m^2
    verifyLessThan(tests, max(abs(net)), 1e-6 * tr.amplitude * 1e-4);
    % The true CSD is most negative (sink) at the sink contact at 15 ms
    [mn, k] = min(tr.csdAtContacts(:, tr.sinkTimeIdx));
    verifyEqual(tests, k, 8);
    verifyLessThan(tests, mn, -0.9 * tr.amplitude);
    verifyGreaterThan(tests, mn, -tr.amplitude);
    % A sink gives a potential trough there
    [~, kv] = min(s.potentials(:, tr.sinkTimeIdx));
    verifyEqual(tests, kv, 8);
    % Deterministic, noise at the requested level
    a = demoCSD('laminar16', 0.02); b = demoCSD('laminar16', 0.02);
    verifyEqual(tests, a.potentials, b.potentials);
    d = a.potentials - a.truth.cleanPotentials;
    verifyEqual(tests, std(d(:)), 0.02 * max(abs(a.truth.cleanPotentials(:))), 'RelTol', 0.1);
    verifyEqual(tests, a.truth.cleanPotentials, s.potentials);
    % The other cases
    e = demoCSD('edge16'); verifyEqual(tests, e.truth.sinkContact, 2);
    verifyLessThan(tests, e.truth.sourceDepthsUm(1), e.depthsUm(1));   % a source above the probe
    d8 = demoCSD('demo8');
    verifyEqual(tests, d8.depthsUm, (0:7) * 100);
    verifyEqual(tests, d8.truth.sinkContact, 4);
    verifyError(tests, @() demoCSD('nope'), 'NeuroAnalyzer:demoCSD:badCase');
end

%% --------------------------------------------------------- Sink depth

function testEveryMethodFindsTheSink(tests)
    cases = {'laminar16', 'edge16', 'demo8'};
    ids = CSDMethods.methodIds();
    for c = 1:numel(cases)
        for noise = [0 0.01]
            s = demoCSD(cases{c}, noise);
            ip = s.truth.sinkTimeIdx;
            for m = 1:numel(ids)
                [csd, info] = CSDMethods.estimate(s.potentials, s.depthsUm, ids{m});
                [mn, k] = min(csd(:, ip));
                msg = sprintf('%s, noise %g, %s', cases{c}, noise, ids{m});
                verifyLessThanOrEqual(tests, abs(k - s.truth.sinkContact), 1, msg);
                verifyLessThan(tests, mn, 0, msg);
                % Finer grid (spline, kCSD): sink within one spacing of the true depth
                [~, kg] = min(info.csdGrid(:, ip));
                verifyLessThanOrEqual(tests, abs(info.zGridUm(kg) - s.truth.sinkDepthUm), s.spacingUm, msg);
            end
        end
    end
end

%% --------------------------------------------------------- Finite extent

function testInverseMethodsBeatStandardForFiniteSources(tests)
    % Discs of 500 um diameter: the standard method (infinite layers) is biased
    s = demoCSD('laminar16', 0);
    T = s.truth.csdAtContacts;
    [eStd, cStd] = scoreMethod(s, 'standard', struct(), T, []);
    verifyGreaterThan(tests, eStd, 0.25);                  % the bias is real
    for id = {'delta', 'step', 'spline', 'kcsd'}
        [e, c] = scoreMethod(s, id{1}, struct(), T, []);
        verifyLessThan(tests, e, 0.5 * eStd, id{1});
        verifyGreaterThan(tests, c, cStd, id{1});
        verifyGreaterThan(tests, c, 0.995, id{1});
    end
    % 1 % noise: kCSD and delta iCSD directly, step / spline iCSD with 75 um smoothing
    s = demoCSD('laminar16', 0.01);
    [eStd, cStd] = scoreMethod(s, 'standard', struct(), T, []);
    runs = {'kcsd', struct(); 'delta', struct(); 'step', struct('smoothUm', 75); 'spline', struct('smoothUm', 75)};
    for k = 1:size(runs, 1)
        [e, c] = scoreMethod(s, runs{k, 1}, runs{k, 2}, T, []);
        verifyLessThan(tests, e, eStd, runs{k, 1});
        verifyGreaterThan(tests, c, cStd, runs{k, 1});
    end
    [e, c] = scoreMethod(s, 'kcsd', struct(), T, []);
    verifyLessThan(tests, e, 0.2);
    verifyGreaterThan(tests, c, 0.98);
end

%% --------------------------------------------------------- Probe ends

function testEdgeEffects(tests)
    % Sink at contact 2, upper source above the probe: rows 1-2
    s = demoCSD('edge16', 0);
    T = s.truth.csdAtContacts;
    csdStd = CSDMethods.estimate(s.potentials, s.depthsUm, 'standard');
    verifyEqual(tests, csdStd(1, :), csdStd(2, :));        % standard: end row copied
    [eStd, cStd] = scoreMethod(s, 'standard', struct(), T, 1:2);
    [e, c] = scoreMethod(s, 'kcsd', struct(), T, 1:2);
    verifyLessThan(tests, e, 0.5 * eStd);
    verifyGreaterThan(tests, c, cStd);
    % 8 contacts (like the demo LFP), sources centred on contacts 1 and 7
    for noise = [0 0.01]
        s = demoCSD('demo8', noise);
        T = s.truth.csdAtContacts;
        [eStd, cStd] = scoreMethod(s, 'standard', struct(), T, 1:2);
        for id = {'delta', 'kcsd'}
            [e, c] = scoreMethod(s, id{1}, struct(), T, 1:2);
            verifyLessThan(tests, e, 0.75 * eStd, sprintf('%s, noise %g', id{1}, noise));
            verifyGreaterThan(tests, c, cStd, sprintf('%s, noise %g', id{1}, noise));
        end
    end
end

%% --------------------------------------------------------- Standard = legacy

function testStandardUnchangedOnDemoLFP(tests)
    s = DemoData.lfpFile();
    on = ERPAnalysis.detectOnsets(s.stim_data, s.stim_fs, 0.5, 0.5);
    [erp, ~, t] = ERPAnalysis.average(s.lfp_data, s.lfp_fs, on, 0.05, 0.2);
    ref = ERPAnalysis.csd(erp, 100);
    depths = (0:7) * 100;
    verifyEqual(tests, CSDMethods.estimate(erp, depths, 'standard'), ref);
    verifyEqual(tests, CSDMethods.estimate(erp, depths, 'Standard'), ref);
    verifyEqual(tests, CSDMethods.standard(erp(8:-1:1, :), depths), ERPAnalysis.csd(erp, 100, 8:-1:1));
    % Legacy formula (LFPAnalysisApp before ERPAnalysis)
    dz = 100 * 1e-6;   % as ERPAnalysis.csd computes it (100e-6 differs in the last bit)
    c = -diff(erp, 2, 1) / dz^2;
    verifyEqual(tests, ref, [c(1, :); c; c(end, :)]);
    [~, info] = CSDMethods.estimate(erp, depths, 'standard');
    verifyEqual(tests, info.toAm3, 0.3);
    % Every method puts the demo sink at channel 4 (+/- 1) at the N1 (15 ms)
    [~, iN1] = min(abs(t - s.truth.n1LatencyS));
    ids = CSDMethods.methodIds();
    for m = 1:numel(ids)
        csd = CSDMethods.estimate(erp, depths, ids{m});
        [~, k] = min(csd(:, iN1));
        verifyLessThanOrEqual(tests, abs(k - s.truth.sinkChannel), 1, ids{m});
    end
end

%% --------------------------------------------------------- kCSD CV

function testKcsdCrossValidation(tests)
    s = demoCSD('laminar16', 0.01);
    [csd, info] = CSDMethods.kCSD(s.potentials, s.depthsUm);
    verifySize(tests, csd, size(s.potentials));
    verifyTrue(tests, isfinite(info.lambda) && info.lambda > 0);
    verifyTrue(tests, ismember(info.lambdaRel, info.lambdaGrid));
    verifyTrue(tests, ismember(info.R, info.RGridUm));
    verifyEqual(tests, info.RGridUm, 100 * [0.5 0.75 1 1.5 2 3]);
    verifySize(tests, info.cvError, [numel(info.RGridUm) numel(info.lambdaGrid)]);
    verifyTrue(tests, all(isfinite(info.cvError(:))));
    verifyEqual(tests, info.cvErrorMin, min(info.cvError(:)));
    verifyGreaterThan(tests, info.lambdaRel, min(info.lambdaGrid));   % noisy data: regularised
    % Estimation grid: 25 um steps from the first to the last contact
    verifyEqual(tests, info.zGridUm([1 end]), [100 1600]);
    verifyEqual(tests, numel(info.zGridUm), 61);
    verifySize(tests, info.csdGrid, [61 numel(s.t)]);
    % Noisier data -> at least as much regularisation
    [~, info5] = CSDMethods.kCSD(demoCSD('laminar16', 0.05).potentials, s.depthsUm);
    verifyGreaterThanOrEqual(tests, info5.lambdaRel, info.lambdaRel);
    % Fixed R and lambda: no cross-validation
    [~, fx] = CSDMethods.kCSD(s.potentials, s.depthsUm, struct('RUm', 120, 'lambda', 1e-3));
    verifyEqual(tests, fx.R, 120);
    verifyEqual(tests, fx.lambdaRel, 1e-3);
    verifyTrue(tests, all(isnan(fx.cvError(:))));
end

%% --------------------------------------------------------- Units

function testUnitsAndRoundTrips(tests)
    z = (0:9) * 100;
    C = 1000 * sin((1:10)' * [1 2 3] / 3);                  % A/m^3, 10 contacts x 3 samples
    for id = {'delta', 'step', 'spline'}
        F = CSDMethods.forwardMatrix(id{1}, z);
        V = F * C;
        [est, info] = CSDMethods.estimate(V, z, id{1});
        verifyEqual(tests, est, C, 'RelTol', 1e-6);
        verifyEqual(tests, info.unit, 'A/m^3');
        % Linear in V; 1 / sigma scaling of the forward model -> CSD proportional to sigma
        verifyEqual(tests, CSDMethods.estimate(2 * V, z, id{1}), 2 * est, 'RelTol', 1e-9);
        verifyEqual(tests, CSDMethods.estimate(V, z, id{1}, struct('sigma', 0.6)), 2 * est, 'RelTol', 1e-9);
    end
    % Potential magnitudes: ~100 uV for a 1000 A/m^3 (1 uA/mm^3) sink of 500 um diameter
    s = demoCSD('laminar16');
    verifyGreaterThan(tests, max(abs(s.potentials(:))), 20e-6);
    verifyLessThan(tests, max(abs(s.potentials(:))), 500e-6);
    % Thin layer (h = 10 um, 1000 A/m^3, radius R = 250 um) at its centre:
    % phi = C / (2 sigma) * integral of sqrt(z^2 + R^2) - |z| = C / (2 sigma) (h R - h^2 / 4 + O(h^3 / R))
    zg = -5:0.01:5;
    phi = CSDMethods.forwardDisc(0, zg, 1000 * ones(numel(zg), 1), 250, 0.3);
    verifyEqual(tests, phi, 1000 / (2 * 0.3) * (10e-6 * 250e-6 - (10e-6)^2 / 4), 'RelTol', 1e-3);
    % Laterally (almost) infinite discs: standard x sigma recovers the CSD inside the probe
    s = demoCSD('laminar16', 0, struct('radiusUm', 1e6));
    csd = CSDMethods.estimate(s.potentials, s.depthsUm, 'standard') * 0.3;
    T = s.truth.csdAtContacts;
    in = 2:15;
    verifyLessThan(tests, norm(csd(in, :) - T(in, :), 'fro') / norm(T(in, :), 'fro'), 0.15);
    % kCSD is linear in V (fixed R and lambda)
    p = struct('RUm', 100, 'lambda', 1e-4);
    verifyEqual(tests, CSDMethods.kCSD(3 * s.potentials, s.depthsUm, p), ...
        3 * CSDMethods.kCSD(s.potentials, s.depthsUm, p), 'RelTol', 1e-9);
end

%% --------------------------------------------------------- Names and errors

function testMethodNames(tests)
    verifyEqual(tests, CSDMethods.methodId('iCSD step'), 'step');
    verifyEqual(tests, CSDMethods.methodId('KCSD'), 'kcsd');
    [id, label] = CSDMethods.methodId('spline');
    verifyEqual(tests, {id, label}, {'spline', 'iCSD spline'});
    verifyEqual(tests, CSDMethods.methodId('laplacian'), '');
    verifyEqual(tests, CSDMethods.methodIds(), {'standard', 'delta', 'step', 'spline', 'kcsd'});
end

function testBadInputs(tests)
    V = randn(5, 20) * 1e-5; z = (0:4) * 100;
    pre = 'NeuroAnalyzer:CSDMethods:';
    verifyError(tests, @() CSDMethods.estimate(V, z, 'nope'), [pre 'badMethod']);
    Vn = V; Vn(2, 3) = NaN;
    verifyError(tests, @() CSDMethods.estimate(Vn, z, 'delta'), [pre 'badPotentials']);
    verifyError(tests, @() CSDMethods.estimate('abc', z, 'delta'), [pre 'badPotentials']);
    verifyError(tests, @() CSDMethods.estimate(V, z(1:4), 'step'), [pre 'badDepths']);
    verifyError(tests, @() CSDMethods.estimate(V, [0 100 100 200 300], 'step'), [pre 'badDepths']);
    verifyError(tests, @() CSDMethods.estimate(V(1:2, :), [0 100], 'kcsd'), [pre 'tooFewChannels']);
    verifyError(tests, @() CSDMethods.estimate(V, [0 100 250 300 400], 'standard'), [pre 'nonUniformSpacing']);
    verifyError(tests, @() CSDMethods.estimate(V, z, 'delta', struct('sigma', 0)), [pre 'badParameter']);
    verifyError(tests, @() CSDMethods.estimate(V, z, 'step', struct('diameterUm', -1)), [pre 'badParameter']);
    verifyError(tests, @() CSDMethods.estimate(V, z, 'step', struct('smoothUm', -5)), [pre 'badParameter']);
    verifyError(tests, @() CSDMethods.estimate(V, z, 'kcsd', struct('lambdaGrid', [])), [pre 'badParameter']);
    verifyError(tests, @() CSDMethods.estimate(V, z, 'kcsd', struct('RUm', NaN)), [pre 'badParameter']);
    verifyError(tests, @() CSDMethods.estimate(V, z, 'spline', struct('splineEnds', 'wrap')), [pre 'badParameter']);
    verifyError(tests, @() CSDMethods.forwardMatrix('kcsd', z), [pre 'badMethod']);
end

%% ------------------------------------------------------------------ Helpers

%% scoreMethod - Relative L2 error and correlation (A/m^3) vs truth T, over rows (all if empty)
function [e, c] = scoreMethod(s, id, params, T, rows)
    [est, info] = CSDMethods.estimate(s.potentials, s.depthsUm, id, params);
    est = est * info.toAm3;
    if isempty(rows), rows = 1:size(T, 1); end
    a = est(rows, :); b = T(rows, :);
    e = norm(a(:) - b(:)) / norm(b(:));
    r = corrcoef(a(:), b(:));
    c = r(1, 2);
end
