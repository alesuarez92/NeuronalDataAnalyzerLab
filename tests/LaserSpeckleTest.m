%% LaserSpeckleTest.m
% =========================================================================
% LASER SPECKLE CONTRAST AND FLOW (core/LaserSpeckle.m, core/demo/demoLSCI.m)
% =========================================================================
% Speckle contrast of synthetic speckle with a known contrast (spatial and
% temporal), the exposure model and its inverse, the flow indices, and the
% whole analysis on the demo recording, whose flow is known: contrast of
% parenchyma, vessel and static tissue, 1/tau_c, the +25% flow response of
% the activated area (and none elsewhere), the response map, the trials,
% the dark level, the three input types and the plain-language checks.
% No display needed.
% =========================================================================

function tests = LaserSpeckleTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'demo'));
    addpath(fullfile(root, 'core', 'io'));
    tests.TestData.demo = demoLSCI();
    tests.TestData.dir = tempname;
    mkdir(tests.TestData.dir);
end

function teardownOnce(tests)
    try, rmdir(tests.TestData.dir, 's'); catch, end
end

%% speckle - H x W x N independent speckle, intensity Gamma(a) scaled to mean m (K = 1/sqrt(a))
function I = speckle(rs, H, W, N, a, m)
    I = zeros(H, W, N);
    for k = 1:a
        I = I - log(rand(rs, H, W, N));   % sum of a exponentials: Gamma(a, 1)
    end
    I = I * (m / a);
end

function p = demoParams(s)
    p = LaserSpeckle.defaults();
    p.Dark = s.dark;
    p.Fps = s.fps;
    p.ExposureMs = s.exposureMs;
    p.Frames = 5;
    p.Onsets = LaserSpeckle.onsetsFromStimulus(s.stim, s.t, 1);
end

function testSpatialContrastOfKnownSpeckle(tests)
    rs = RandStream('mt19937ar', 'Seed', 1);
    I = speckle(rs, 160, 160, 2, 11, 1000);             % K = 1/sqrt(11) = 0.3015
    K = LaserSpeckle.spatialContrast(I, 7);
    tests.verifyEqual(size(K), size(I));
    tests.verifyEqual(median(K(:)), 1 / sqrt(11), 'RelTol', 0.03);
    % A flat image has no speckle; an empty one has no contrast at all
    tests.verifyEqual(LaserSpeckle.spatialContrast(500 * ones(20, 20), 5), zeros(20, 20), 'AbsTol', 1e-6);
    tests.verifyTrue(all(isnan(LaserSpeckle.spatialContrast(zeros(10, 10), 5)), 'all'));
    % Contrast does not depend on the brightness
    K2 = LaserSpeckle.spatialContrast(3 * I, 7);
    tests.verifyEqual(K2, K, 'AbsTol', 1e-10);
end

function testTemporalContrastOfKnownSpeckle(tests)
    rs = RandStream('mt19937ar', 'Seed', 2);
    I = speckle(rs, 40, 40, 50, 25, 800);               % K = 0.2
    K = LaserSpeckle.temporalContrast(I, 25);
    tests.verifyEqual(size(K), [40 40 2]);
    tests.verifyEqual(median(K(:)), 0.2, 'RelTol', 0.03);
    tests.verifyError(@() LaserSpeckle.temporalContrast(I, 2), 'NeuroAnalyzer:LaserSpeckle:frames');
    tests.verifyError(@() LaserSpeckle.temporalContrast(I(:, :, 1:10), 25), 'NeuroAnalyzer:LaserSpeckle:frames');
    tests.verifyError(@() LaserSpeckle.spatialContrast(I, 6), 'NeuroAnalyzer:LaserSpeckle:window');
end

function testExposureModelAndItsInverse(tests)
    x = logspace(-2, 4, 60);
    for beta = [1 0.6]
        g = LaserSpeckle.modelK2(x, beta);
        tests.verifyTrue(all(diff(g) < 0), 'K^2 falls as flow rises');
        tests.verifyEqual(LaserSpeckle.invertModel(g, beta), x, 'RelTol', 1e-4);
    end
    % Limits: no motion gives beta; fast motion gives beta / x (the 1/K^2 rule)
    tests.verifyEqual(LaserSpeckle.modelK2(1e-6, 0.8), 0.8, 'RelTol', 1e-5);
    tests.verifyEqual(LaserSpeckle.modelK2(1e4, 1), 1e-4, 'RelTol', 1e-3);
    tests.verifyEqual(LaserSpeckle.modelK2(5, 1), (exp(-10) - 1 + 10) / 50, 'RelTol', 1e-12);
    tests.verifyEqual(LaserSpeckle.invertModel([1.2 NaN 0], 1), [0 NaN NaN]);
    tests.verifyError(@() LaserSpeckle.invertModel(0.1, 1.5), 'NeuroAnalyzer:LaserSpeckle:beta');
end

function testFlowIndices(tests)
    p = LaserSpeckle.defaults();
    tests.verifyEqual(LaserSpeckle.flowFromK2([0.04 0.25], p), [25 4], 'RelTol', 1e-12);
    p.FlowModel = 'tauc';
    tests.verifyError(@() LaserSpeckle.flowFromK2(0.04, p), 'NeuroAnalyzer:LaserSpeckle:exposure');
    p.ExposureMs = 5;
    x = 20;
    F = LaserSpeckle.flowFromK2(LaserSpeckle.modelK2(x, 1), p);
    tests.verifyEqual(F, x / 0.005, 'RelTol', 1e-4, '1/tau_c in 1/s');
    tests.verifyEqual(LaserSpeckle.flowLabel(p), ['1/' char(964) 'c (1/s)']);
end

function testOnsetsFromStimulus(tests)
    t = (0:999) / 100;
    stim = zeros(1, 1000);
    stim(t >= 1 & t < 1.5) = 5; stim(t >= 4 & t < 4.5) = 5;
    stim(t >= 4.6 & t < 4.7) = 5;                         % a second pulse of the same train
    tests.verifyEqual(LaserSpeckle.onsetsFromStimulus(stim, t, 1), [1 4], 'AbsTol', 1e-9);
    tests.verifyEqual(numel(LaserSpeckle.onsetsFromStimulus(stim, t, 0)), 3);
    tests.verifyEmpty(LaserSpeckle.onsetsFromStimulus(zeros(1, 10), 1:10, 0));
end

function testDemoContrastAndFlow(tests)
    s = tests.TestData.demo;
    tr = s.truth;
    tests.verifyEqual(class(s.frames), 'uint16');
    tests.verifyEqual(size(s.frames), [64 80 900]);
    p = demoParams(s);
    tests.verifyEqual(p.Onsets, tr.onsets, 'AbsTol', 1e-9);
    R = LaserSpeckle.analyze(s.frames, s.t, s.roiMasks, p);
    K = sqrt(R.K2Mean);
    par = tr.xBase == 20 & ~tr.activeMask;
    par(:, 1:30) = false; par(:, 65:end) = false;          % away from the vessel and static edges
    tests.verifyEqual(median(K(par)), tr.Kbase(40, 40), 'RelTol', 0.03, 'parenchyma K');
    tests.verifyEqual(median(K(s.roiMasks(:, :, 3))), tr.Kbase(30, 20), 'RelTol', 0.05, 'vessel K');
    tests.verifyEqual(median(K(56:end, 72:end), 'all'), tr.staticK, 'RelTol', 0.05, 'static K');
    tests.verifyEqual(R.fps, 2, 'AbsTol', 1e-9, '10 fps averaged by 5');
    % 1/tau_c from the model: 4000 /s in the cortex, 40000 /s in the vessel
    p.FlowModel = 'tauc';
    R2 = LaserSpeckle.analyze(s.frames, s.t, s.roiMasks, p);
    tests.verifyEqual(mean(R2.roiFlow(2, :)), 20 / 0.005, 'RelTol', 0.05);
    tests.verifyEqual(mean(R2.roiFlow(3, :)), 200 / 0.005, 'RelTol', 0.12);
end

function testDemoResponse(tests)
    s = tests.TestData.demo;
    tr = s.truth;
    p = demoParams(s);
    R = LaserSpeckle.analyze(s.frames, s.t, s.roiMasks, p);
    tests.verifyEqual(numel(R.onsets), 4, 'every trial fits');
    tests.verifyEqual(size(R.trials), [3 4 numel(R.trialTime)]);
    tests.verifyEqual(R.trialTime([1 end]), [-5 15], 'AbsTol', 1e-9);
    % Mean % change 2-6 s after onset, as seen through 1/K^2 and as true flow
    w = s.t - tr.onsets(1) >= 2 & s.t - tr.onsets(1) <= 6;
    want = 100 * (mean(tr.invK2Ratio(w)) - 1);            % 21.3 %
    tests.verifyEqual(R.response(1), want, 'AbsTol', 4.5, 'activated area');
    tests.verifyLessThan(abs(R.response(2)), 3, 'control cortex: no response');
    tests.verifyLessThan(abs(R.response(3)), 3, 'vessel: no response');
    tests.verifyEqual(R.peakTime(1), tr.peakLatency, 'AbsTol', 1.5);
    % Response map: the activated disk lights up, the rest does not
    M = R.responseMap;
    tests.verifyGreaterThan(mean(M(s.roiMasks(:, :, 1))), 15);
    tests.verifyLessThan(abs(mean(M(s.roiMasks(:, :, 2)))), 3);
    % The model gives a slightly larger change than 1/K^2 (flow +25% at the peak)
    p.FlowModel = 'tauc';
    R2 = LaserSpeckle.analyze(s.frames, s.t, s.roiMasks, p);
    tests.verifyGreaterThan(R2.response(1), R.response(1));
    tests.verifyEqual(R2.response(1), 100 * (mean(tr.flowRatio(w)) - 1), 'AbsTol', 4.5);
    % Continuous trace relative to the time before the first stimulus
    tests.verifyEqual(R.baselineSec, [R.t(1) 10], 'AbsTol', 1e-9);
    tests.verifyEqual(mean(R.roiRel(2, R.t < 10)), 1, 'AbsTol', 1e-9);
end

function testDarkLevel(tests)
    s = tests.TestData.demo;
    p = demoParams(s);
    p.Frames = 10;
    R = LaserSpeckle.analyze(s.frames, s.t, s.roiMasks(:, :, 2), p);
    p.Dark = 0;
    R0 = LaserSpeckle.analyze(s.frames, s.t, s.roiMasks(:, :, 2), p);
    % The offset adds to the mean, not to the SD: the contrast looks lower
    m = s.roiMasks(:, :, 2);
    tests.verifyLessThan(median(sqrt(R0.K2Mean(m))), 0.97 * median(sqrt(R.K2Mean(m))));
    tests.verifyTrue(any(contains(R0.checks, 'no dark level')), strjoin(R0.checks, newline));
end

function testInputTypes(tests)
    s = tests.TestData.demo;
    p = demoParams(s);
    p.Frames = 1;
    Rraw = LaserSpeckle.analyze(s.frames(:, :, 1:200), s.t(1:200), s.roiMasks, p);
    % Contrast images: the same flow as from the raw images
    K = LaserSpeckle.spatialContrast(double(s.frames(:, :, 1:200)) - s.dark, 7);
    pc = p; pc.InputType = 'contrast';
    Rk = LaserSpeckle.analyze(K, s.t(1:200), s.roiMasks, pc);
    tests.verifyEqual(Rk.roiFlow, Rraw.roiFlow, 'RelTol', 1e-9);
    % Perfusion images (a commercial system's export): used as they are
    t = (0:299) / 5;
    F = 100 * ones(8, 8, 300);
    bump = 1 + 0.2 * exp(-((t - 23) / 0.8) .^ 2);          % +20% 3 s after the onset at 20 s
    F = F .* reshape(bump, 1, 1, []);
    pf = LaserSpeckle.defaults();
    pf.InputType = 'flow'; pf.Onsets = 20; pf.ResponseSec = [2.5 3.5];
    Rf = LaserSpeckle.analyze(F, t, [], pf);
    tests.verifyEqual(Rf.peak, 20, 'AbsTol', 0.01);
    tests.verifyEqual(Rf.peakTime, 3, 'AbsTol', 1e-9);
    tests.verifyEqual(Rf.units, 'Perfusion (as exported)');
    tests.verifyEqual(mean(Rf.responseMap(:)), Rf.response, 'AbsTol', 1e-9);
end

function testChecksAndErrors(tests)
    I = uint8(200 * ones(30, 30, 4));
    I(1:10, :, :) = 255;                                   % a third of the pixels saturated
    p = LaserSpeckle.defaults(); p.Fps = 10; p.Window = 3;
    R = LaserSpeckle.analyze(I, [], [], p);
    txt = strjoin(R.checks, newline);
    tests.verifyTrue(contains(txt, 'saturated'), txt);
    tests.verifyTrue(contains(txt, '3 x 3 window'), txt);
    tests.verifyTrue(contains(txt, 'No stimulus onsets'), txt);
    tests.verifyError(@() LaserSpeckle.analyze(I, [], true(5, 5), p), 'NeuroAnalyzer:LaserSpeckle:masks');
    p.Fps = NaN;
    tests.verifyError(@() LaserSpeckle.analyze(I, [], [], p), 'NeuroAnalyzer:LaserSpeckle:input');
    % Trials that do not fit are left out and reported
    s = tests.TestData.demo;
    q = demoParams(s);
    q.Onsets = [2 30 88];
    R = LaserSpeckle.analyze(s.frames, s.t, s.roiMasks(:, :, 1), q);
    tests.verifyEqual(R.onsets, 30);
    tests.verifyTrue(any(contains(R.checks, '2 of 3 stimuli were left out')), strjoin(R.checks, newline));
end

