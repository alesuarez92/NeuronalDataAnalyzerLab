%% PerfusionChecksTest.m
% =========================================================================
% UNIT TESTS: BLOOD-FLOW QUALITY CHECKS FOR THE PROBE AND FOR IMAGES
% =========================================================================
% core/PerfusionChecks.m (the checks every blood-flow source shares) and
% the source checks built on it:
%   * drift (%/min, before the first stimulus or across trial baselines;
%     a note when too short), movement artefacts (in or outside trials),
%     signal stuck at 0 or at the top, trials left out / too few, short
%     trial baselines, time resolution; several ROIs in one row;
%   * LDFPipeline.checks: the clean demo gives no warnings; the faults demo
%     (DemoData.ldfFaults: drift, a jump in trial 3, a dropout to 0) fires
%     each check; baseline plausibility and filter cut-offs;
%   * LaserSpeckle.checks: the clean speckle demo gives no warnings; the
%     faults demo (demoLSCI Faults: field shift, illumination, exposure,
%     a ROI through the skull) and the perfusion demo (clipped at 3000 PU,
%     one image per second) fire their checks;
%   * Batch 'ldf': the Checks column and the log line.
% Base MATLAB only, except the Batch test (table): the rest also runs in
% GNU Octave (with a RandStream shim).
% =========================================================================

function tests = PerfusionChecksTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
end

%% row - The first row of a topic ([] when none)
function r = row(Q, topic)
    k = find(strcmp({Q.topic}, topic), 1);
    if isempty(k), r = []; else, r = Q(k); end
end

%% expect - A row of this topic with this level whose finding has the text
function expect(tests, Q, topic, level, text)
    r = row(Q, topic);
    txt = strjoin(QualityChecks.lines(Q), newline);
    tests.verifyNotEmpty(r, sprintf('no %s row:\n%s', topic, txt));
    if isempty(r), return; end
    tests.verifyEqual(r.level, level, sprintf('%s: %s', topic, r.found));
    if nargin >= 5
        tests.verifyTrue(~isempty(strfind(r.found, text)), sprintf('%s: "%s" not in "%s"', topic, text, r.found)); %#ok<STREMP>
    end
end

%% trace - 300 s at 10 Hz around 100 (+ slope PU/s), noise SD 1, stimuli every 30 s from 30 s
function [y, t, o] = trace(slope)
    t = (0:2999) / 10;
    y = 100 + slope * t + sin(2 * pi * 0.37 * t) + 0.5 * cos(2 * pi * 1.3 * t);
    o = PerfusionChecks.options();
    o.onsets = 30:30:270;
    o.preSec = 5; o.postSec = 20;
end

function testDrift(tests)
    [y, t, o] = trace(0);
    expect(tests, PerfusionChecks.drift([], y, t, o), 'Baseline drift', 'ok', 'trial');
    [y, t, o] = trace(0.1);                                % +6 PU/min on ~115 PU: ~5%/min
    Q = PerfusionChecks.drift([], y, t, o);
    expect(tests, Q, 'Baseline drift', 'check', '%/min');
    [rate, how] = PerfusionChecks.driftRate(y, t, o);
    tests.verifyEqual(how, 'trial baselines');
    tests.verifyEqual(rate, 100 * 6 / mean(y(t >= 25 & t < 270)), 'RelTol', 0.05);
    [y, t, o] = trace(0.3);
    expect(tests, PerfusionChecks.drift([], y, t, o), 'Baseline drift', 'warning');
    % A long baseline before the first stimulus is used first
    o.onsets = 200; o.trialOnsets = 200;
    [rate, how, span] = PerfusionChecks.driftRate(y, t, o);
    tests.verifyEqual(how, 'before the first stimulus');
    tests.verifyGreaterThan(span, 190);
    tests.verifyEqual(rate, 100 * 18 / mean(y(t < 200)), 'RelTol', 0.02);
    % Too short to judge: a note
    o.onsets = [10 30]; o.trialOnsets = NaN;
    expect(tests, PerfusionChecks.drift([], y, t, o), 'Baseline drift', 'note', 'Too short');
end

function testArtefacts(tests)
    [y, t, o] = trace(0);
    expect(tests, PerfusionChecks.artefacts([], y, t, o), 'Movement artefacts', 'ok', 'No movement');
    yi = y; yi(t >= 72 & t < 72.3) = 400;                 % inside trial 2 (onset 60 s)
    Q = PerfusionChecks.artefacts([], yi, t, o);
    expect(tests, Q, 'Movement artefacts', 'warning', 'trial 2');
    tests.verifyTrue(~isempty(strfind(Q(1).found, '72.0')), Q(1).found); %#ok<STREMP>
    ev = PerfusionChecks.events(yi, t);
    tests.verifyNumElements(ev, 1);
    tests.verifyEqual(ev.start, 72, 'AbsTol', 0.05);
    tests.verifyGreaterThan(ev.size, 250);
    yo = y; yo(t >= 3 & t < 3.2) = 0;                      % before the first trial
    expect(tests, PerfusionChecks.artefacts([], yo, t, o), 'Movement artefacts', 'check', 'outside the trials');
    % Small wiggles (below 25% of the baseline) are not artefacts
    ys = y; ys(t >= 72 & t < 72.3) = 120;
    expect(tests, PerfusionChecks.artefacts([], ys, t, o), 'Movement artefacts', 'ok');
end

function testStuck(tests)
    [y, ~, o] = trace(0);
    expect(tests, PerfusionChecks.stuck([], y, o), 'Signal range', 'ok');
    y0 = y; y0(100:120) = 0;                                % 0.7% at 0
    expect(tests, PerfusionChecks.stuck([], y0, o), 'Signal range', 'warning', 'at 0');
    yt = min(y, 100.8);                                     % flat top: clipped
    expect(tests, PerfusionChecks.stuck([], yt, o), 'Signal range', 'warning', 'stuck at the top');
    o.ceiling = 3000;                                       % below the device ceiling: fine
    expect(tests, PerfusionChecks.stuck([], yt, o), 'Signal range', 'ok');
end

function testTrialsAndTiming(tests)
    o = PerfusionChecks.options();
    o.onsets = [10 30 50]; o.trialOnsets = 30; o.preSec = 5; o.postSec = 15;
    Q = PerfusionChecks.trials([], o);
    tests.verifyEqual({Q.level}, {'check', 'check'});
    tests.verifyTrue(~isempty(strfind(Q(1).found, '2 of 3 stimuli were left out')), Q(1).found); %#ok<STREMP>
    tests.verifyTrue(~isempty(strfind(Q(2).found, 'Only 1 trial')), Q(2).found); %#ok<STREMP>
    o.trialOnsets = NaN;
    expect(tests, PerfusionChecks.trials([], o), 'Trials', 'ok', '3 trials averaged');
    o.onsets = [];
    expect(tests, PerfusionChecks.trials([], o), 'Trials', 'note', 'No stimulus onsets');

    o = PerfusionChecks.options();
    o.onsets = [10 30]; o.preSec = 1; o.postSec = 15;
    expect(tests, PerfusionChecks.trialBaseline([], 0.1, o), 'Trial baseline', 'check', '1 s');
    o.preSec = 5;
    expect(tests, PerfusionChecks.trialBaseline([], 0.1, o), 'Trial baseline', 'ok', '50 samples');
    expect(tests, PerfusionChecks.trialBaseline([], 2, o), 'Trial baseline', 'check', '3 samples');
    % 2 Hz (the laser speckle demo) is OK; 1 s per value: Check; 4 s: Warning
    expect(tests, PerfusionChecks.timeResolution([], 0.5, o), 'Time resolution', 'ok', '2 Hz');
    expect(tests, PerfusionChecks.timeResolution([], 1, o), 'Time resolution', 'check', '1 s');
    expect(tests, PerfusionChecks.timeResolution([], 4, o), 'Time resolution', 'warning', '4 s');
    o.responseSec = [2 2.5];
    expect(tests, PerfusionChecks.timeResolution([], 1, o), 'Time resolution', 'warning', 'response window');
end

function testSeveralTraces(tests)
    [y, t, o] = trace(0);
    y2 = y + 0.3 * t;                                        % the second ROI drifts
    o.names = {'Cortex', 'Vessel'};
    Q = PerfusionChecks.run([y; y2], t, o);
    expect(tests, Q, 'Baseline drift', 'warning', 'Vessel');
    r = row(Q, 'Baseline drift');
    tests.verifyLessThan(strfind(r.found, 'Vessel'), strfind(r.found, 'Cortex'), 'worst first');
    tests.verifyEqual(nnz(strcmp({Q.topic}, 'Baseline drift')), 1, 'one row for both traces');
    y2(t >= 100 & t < 100.3) = 900;
    Q = PerfusionChecks.artefacts([], [y; y2], t, o);
    expect(tests, Q, 'Movement artefacts', 'warning', 'Vessel: 1 jump at 100.0 s');
end

function testProbeDemo(tests)
    p = LDFPipeline.defaultParams();
    p.threshold = 2.5; p.preSec = 5; p.postSec = 20; p.minISI = 10;
    s = DemoData.ldfCropped();
    r = LDFPipeline.run(s.LDF, s.stim, s.t, s.Fs, p);
    Q = r.checkRows;
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 0, strjoin(QualityChecks.lines(Q), newline));
    expect(tests, Q, 'Trials', 'check', '1 of 9 stimuli were left out');
    expect(tests, Q, 'Baseline', 'ok', 'PU');
    tests.verifyEqual(sscanf(row(Q, 'Baseline').found, 'Baseline %f'), 120, 'AbsTol', 6);
    expect(tests, Q, 'Baseline drift', 'ok', '8 trials');
    expect(tests, Q, 'Movement artefacts', 'ok');
    expect(tests, Q, 'Signal range', 'ok');
    expect(tests, Q, 'Filter', 'ok', 'No filter');
    expect(tests, Q, 'Time resolution', 'ok', '1000 Hz');

    f = DemoData.ldfFaults();
    tests.verifyEqual(f.truth.artefactSec, [72 72.3]);
    r = LDFPipeline.run(f.LDF, f.stim, f.t, f.Fs, p);
    Q = r.checkRows;
    expect(tests, Q, 'Baseline drift', 'check', '+5');
    expect(tests, Q, 'Movement artefacts', 'warning', 'trial 3');
    tests.verifyTrue(~isempty(strfind(row(Q, 'Movement artefacts').found, '72.0')), row(Q, 'Movement artefacts').found); %#ok<STREMP>
    expect(tests, Q, 'Signal range', 'warning', 'at 0');
    tests.verifyEqual(QualityChecks.brief(Q), ['2 warnings: Movement artefacts: ' row(Q, 'Movement artefacts').found]);
end

function testProbeBaselineAndFilter(tests)
    p = LDFPipeline.defaultParams();
    p.preSec = 5; p.postSec = 20;
    s = DemoData.ldfCropped();
    Fs = s.Fs;
    on = round((s.truth.onsets) * Fs) + 1;
    Q = LDFPipeline.checks(s.LDF / 50, s.t, Fs, on, 8, p);                 % in volts, not PU
    expect(tests, Q, 'Baseline', 'check', 'outside the usual 30-600 PU');
    p.filterType = 2; p.cutoffHigh = 0.3;
    expect(tests, LDFPipeline.checks(s.LDF, s.t, Fs, on, 8, p), 'Filter', 'check', 'below 0.5 Hz');
    p.filterType = 2; p.cutoffHigh = 1;
    expect(tests, LDFPipeline.checks(s.LDF, s.t, Fs, on, 8, p), 'Filter', 'ok', 'low-pass at 1 Hz');
    p.filterType = 3; p.cutoffLow = 0.05;
    expect(tests, LDFPipeline.checks(s.LDF, s.t, Fs, on, 8, p), 'Filter', 'check', 'above 0.02 Hz');
    p.filterType = 4; p.cutoffLow = 0.2; p.cutoffHigh = 2;
    expect(tests, LDFPipeline.checks(s.LDF, s.t, Fs, on, 8, p), 'Filter', 'warning', 'band-pass');
    p.filterType = 1;
    % Decimated: the time resolution says so
    y = s.LDF(1:10:end);
    Q = LDFPipeline.checks(y, s.t(1:10:end), Fs / 10, round(s.truth.onsets * Fs / 10) + 1, 8, p, s.LDF, Fs);
    expect(tests, Q, 'Time resolution', 'ok', 'after downsampling by 10');
end

function testSpeckleDemo(tests)
    s = demoLSCI();
    R = runSpeckle(s);
    Q = R.checkRows;
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 0, strjoin(QualityChecks.lines(Q), newline));
    expect(tests, Q, 'Field shift', 'ok', 'does not move');
    expect(tests, Q, 'Exposure', 'ok', '5 ms');
    expect(tests, Q, 'Illumination', 'ok');
    expect(tests, Q, 'Baseline contrast', 'ok');
    expect(tests, Q, 'Speckle size', 'check', 'one pixel or smaller');   % the demo's speckles are one pixel each
    expect(tests, Q, 'Time resolution', 'ok', '2 Hz');
    expect(tests, Q, 'Trials', 'ok', '4 trials averaged');
    expect(tests, Q, 'Movement artefacts', 'ok');
    tests.verifyEqual(R.roiNames, s.roiNames);
    tests.verifyEqual(R.roiK(:)', [s.truth.Kbase(28, 52) s.truth.Kbase(50, 40) s.truth.Kbase(30, 20)], 'RelTol', 0.06);
    tests.verifyEqual(numel(R.intensity), size(s.frames, 3));
end

function testSpeckleFaults(tests)
    s = demoLSCI(struct('Faults', true));
    tests.verifyEqual(s.roiNames{4}, 'Thinned skull');
    tests.verifyEqual(s.exposureMs, 25);
    R = runSpeckle(s);
    Q = R.checkRows;
    expect(tests, Q, 'Field shift', 'warning', 'first above 1 px at 4');
    tests.verifyEqual(max(R.shift.dx), 4, 'AbsTol', 0.6, 'the field moves 4 px to the right');
    tests.verifyLessThan(max(abs(R.shift.dy)), 1);
    expect(tests, Q, 'Illumination', 'check', 'changes by');
    expect(tests, Q, 'Exposure', 'check', '25 ms');
    expect(tests, Q, 'Baseline contrast', 'check', 'Thinned skull');
    expect(tests, Q, 'Speckle size', 'check');
    expect(tests, Q, 'Speckle contrast', 'ok');
    k = sqrt(R.K2Mean(isfinite(R.K2Mean)));
    tests.verifyLessThan(median(k), 0.19, 'two speckles per pixel lower K');
end

function testPerfusionFaults(tests)
    s = demoPerfusion();
    p = LaserSpeckle.defaults();
    p.InputType = 'flow'; p.Fps = s.fps;
    p.Onsets = LaserSpeckle.onsetsFromStimulus(s.stim, s.t, 1);
    R = LaserSpeckle.analyze(s.frames, s.t, s.roiMasks, p, s.roiNames);
    Q = R.checkRows;
    expect(tests, Q, 'Export range', 'warning', '(3000)');
    expect(tests, Q, 'Time resolution', 'check', '1 s');
    expect(tests, Q, 'Units', 'note', 'device');
    expect(tests, Q, 'Raw images', 'note', 'dark level');
    tests.verifyEmpty(row(Q, 'Speckle size'), 'no speckle checks on perfusion images');
    tests.verifyEmpty(row(Q, 'Flow index'));
    tests.verifyEqual(R.response(1), 100 * (mean(s.truth.flowRatio(s.t >= 12 & s.t <= 16)) - 1), 'AbsTol', 3);
end

function testBatchChecksColumn(tests)
    tests.assumeTrue(exist('table', 'file') > 0 && exist('writetable', 'file') > 0, 'Needs table / writetable');
    d = fullfile(tempdir, sprintf('PerfusionChecksTest_%d', round(1e6 * rand)));
    mkdir(d); c = onCleanup(@() rmdir(d, 's'));
    clean = fullfile(d, 'clean.mat'); faults = fullfile(d, 'faults.mat');
    s = DemoData.ldfCropped(); save(clean, '-struct', 's');
    s = DemoData.ldfFaults(); save(faults, '-struct', 's');
    p = struct('downsample', 1, 'filterType', 'None', 'threshold', 2.5, 'preSec', 5, 'postSec', 20, ...
        'minISI', 10, 'saveTrials', false);
    R = Batch.run('ldf', {clean, faults}, p, fullfile(d, 'out'), 'Name', 'checks');
    T = R.summary;
    tests.verifyEqual(R.fileStatus, {'ok', 'ok'}, 'the checks do not change the status');
    tests.verifyTrue(ismember('Checks', T.Properties.VariableNames));
    tests.verifyTrue(strncmp(T.Checks{1}, '1 to check: Trials', 18), T.Checks{1});
    tests.verifyTrue(strncmp(T.Checks{2}, '2 warnings: Movement artefacts', 30), T.Checks{2});
    logText = fileread(R.paths.log);
    tests.verifyTrue(~isempty(strfind(logText, 'checks: 2 warnings')), logText); %#ok<STREMP>
end

%% runSpeckle - The demo through LaserSpeckle.analyze with the window's demo settings
function R = runSpeckle(s)
    p = LaserSpeckle.defaults();
    p.Frames = 5; p.Dark = s.dark; p.Fps = s.fps; p.ExposureMs = s.exposureMs;
    p.Onsets = LaserSpeckle.onsetsFromStimulus(s.stim, s.t, 1);
    R = LaserSpeckle.analyze(s.frames, s.t, s.roiMasks, p, s.roiNames);
end
