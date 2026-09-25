%% LDFPipelineTest.m
% =========================================================================
% LDF PIPELINE: SAME NUMBERS AS LDF PROCESSING, DEMO TRUTH RECOVERED
% =========================================================================
% core/LDFPipeline.m holds the decimate / filter / segment code that used
% to live inside ProcessingLDFApp. These tests check that
%   - segmentation and processing give exactly what the app's previous
%     inline code gave (copied below as legacy* reference functions),
%   - the window (driven through its dialog-free methods) and the headless
%     pipeline give the same trials on the demo recording,
%   - the pipeline recovers the demo truth (8 trials, response peaking
%     ~4 s after onset at ~+30 PU),
%   - invalid settings and files raise clear errors.
% Filtering needs the Signal Processing Toolbox; the window test needs a
% display. Those tests are skipped otherwise.
% =========================================================================

function tests = LDFPipelineTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.demo = DemoData.ldfCropped();
    % Settings of the LDF walkthrough: 10x decimation, 4th-order Butterworth low-pass at 1 Hz
    tests.TestData.proc = struct('downsample', 10, 'filterType', 2, 'designType', 1, 'filterOrder', 4, ...
        'cutoffLow', NaN, 'cutoffHigh', 1);
    tests.TestData.seg = struct('threshold', 2.5, 'preSec', 5, 'postSec', 20, 'minISI', 10);
end

function assumeSPT(tests)
    tests.assumeTrue(license('test', 'Signal_Toolbox') && exist('decimate', 'file') == 2 && ...
        exist('filtfilt', 'file') == 2, 'Needs the Signal Processing Toolbox');
end

%% testSegmentMatchesLegacyCode - Onsets and trials identical to the old app code
function testSegmentMatchesLegacyCode(tests)
    s = tests.TestData.demo;
    for thrIsi = [2.5 10; 0.5 1; 2.5 0]'
        [seg, tSeg, onsets] = LDFPipeline.segment(s.LDF, s.stim, s.Fs, thrIsi(1), 5, 20, thrIsi(2));
        [segRef, tRef, onRef] = legacySegment(s.LDF, s.stim, s.Fs, thrIsi(1), 5, 20, thrIsi(2));
        verifyEqual(tests, seg, segRef);
        verifyEqual(tests, tSeg, tRef);
        verifyEqual(tests, onsets, onRef);
    end
    % Column vectors and windows that do not fit anywhere
    [seg, ~, onsets] = LDFPipeline.segment(s.LDF(:), s.stim(:), s.Fs, 2.5, 200, 200, 10);
    verifyEmpty(tests, seg);
    verifyNumElements(tests, onsets, 9);
end

%% testDemoOnsetsAndTrials - 9 onsets at the simulated times, 8 complete trials (no toolbox)
function testDemoOnsetsAndTrials(tests)
    s = tests.TestData.demo;
    seg = tests.TestData.seg;
    onsets = LDFPipeline.detectOnsets(s.stim, s.Fs, seg.threshold, seg.minISI);
    verifyEqual(tests, onsets, s.truth.onsets * s.Fs + 1, 'AbsTol', 1);
    [trials, tSeg] = LDFPipeline.segment(s.LDF, s.stim, s.Fs, seg.threshold, seg.preSec, seg.postSec, seg.minISI);
    verifySize(tests, trials, [8, 25 * s.Fs + 1]);
    verifyEqual(tests, tSeg([1 end]), [-5 20], 'AbsTol', 1e-12);
end

%% testProcessMatchesLegacyCode - Decimation and every filter design as before
function testProcessMatchesLegacyCode(tests)
    assumeSPT(tests);
    s = tests.TestData.demo;
    sets = {tests.TestData.proc, ...
        struct('downsample', 1, 'filterType', 1, 'designType', 1, 'filterOrder', 4, 'cutoffLow', NaN, 'cutoffHigh', NaN), ...
        struct('downsample', 5, 'filterType', 1, 'designType', 1, 'filterOrder', 4, 'cutoffLow', NaN, 'cutoffHigh', NaN), ...
        struct('downsample', 10, 'filterType', 3, 'designType', 3, 'filterOrder', 30, 'cutoffLow', 0.05, 'cutoffHigh', NaN), ...
        struct('downsample', 10, 'filterType', 4, 'designType', 2, 'filterOrder', 2, 'cutoffLow', 0.1, 'cutoffHigh', 2), ...
        struct('downsample', 2, 'filterType', 5, 'designType', 1, 'filterOrder', 2, 'cutoffLow', 5, 'cutoffHigh', 7)};
    for k = 1:numel(sets)
        p = sets{k};
        verifyEmpty(tests, LDFPipeline.validateProcessing(p, s.Fs));
        [L, st, t, Fs, b, a] = LDFPipeline.process(s.LDF, s.stim, s.t, s.Fs, p);
        [Lr, str, tr, Fsr, br, ar] = legacyProcess(s.LDF, s.stim, s.t, s.Fs, p);
        verifyEqual(tests, L, Lr, 'AbsTol', 1e-12, sprintf('set %d: LDF', k));
        % The trigger keeps each block's maximum (short pulses survive): same
        % onsets as the legacy sample picking, never below it
        verifyEqual(tests, LDFPipeline.detectOnsets(st, Fs, 2.5, 10), ...
            LDFPipeline.detectOnsets(str, Fsr, 2.5, 10), sprintf('set %d: stim onsets', k));
        verifyEqual(tests, size(st), size(str), sprintf('set %d: stim size', k));
        verifyTrue(tests, all(st(:) >= str(:)), sprintf('set %d: stim below legacy', k));
        verifyEqual(tests, t, tr, sprintf('set %d: t', k));
        verifyEqual(tests, Fs, Fsr);
        verifyEqual(tests, b, br);
        verifyEqual(tests, a, ar);
    end
end

%% testAppMatchesPipeline - The window's trials equal LDFPipeline.run on the demo file
function testAppMatchesPipeline(tests)
    assumeSPT(tests);
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
    app = ProcessingLDFApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();                                    % threshold 2.5, pre 5, post 20, ISI 10
    tests.verifyTrue(logical(app.applyProcessingParams(tests.TestData.proc)));
    app.segmentByOnsetsConfig();

    s = LDFPipeline.loadCropped(DemoData.file('ldfCropped'));
    r = LDFPipeline.run(s.LDF, s.stim, s.t, s.Fs, catStruct(tests.TestData.proc, tests.TestData.seg));
    verifyEqual(tests, app.SegmentedLDF, r.segmentedLDF, 'AbsTol', 1e-12);
    verifyEqual(tests, app.SegmentedTime, r.segmentedTime, 'AbsTol', 1e-12);
    verifyEqual(tests, app.Fs, r.Fs);
    verifyEqual(tests, app.LDF, r.LDF, 'AbsTol', 1e-12);

    % Saved file format unchanged: segmentedLDF, segmentedTime, Fs
    out = [tempname '.mat'];
    c2 = onCleanup(@() deleteIfExists(out));
    app.saveData(out);
    saved = load(out);
    verifyEqual(tests, sort(fieldnames(saved)), sort({'Fs'; 'segmentedLDF'; 'segmentedTime'}));
    verifyEqual(tests, saved.segmentedLDF, r.segmentedLDF, 'AbsTol', 1e-12);
end

%% testDemoTruth - 8 trials; mean response peaks ~4 s after onset at ~+30 PU
function testDemoTruth(tests)
    assumeSPT(tests);
    s = tests.TestData.demo;
    r = LDFPipeline.run(s.LDF, s.stim, s.t, s.Fs, catStruct(tests.TestData.proc, tests.TestData.seg));
    verifyEqual(tests, r.Fs, 100);
    verifyEqual(tests, r.nOnsets, 9);
    verifyEqual(tests, r.nTrials, 8);
    m = mean(r.segmentedLDF, 1);
    tSeg = r.segmentedTime;
    base = mean(m(tSeg < 0));
    [lat, pk] = SignalFeatures.peakLatency(tSeg, m, 0, 'max');
    verifyEqual(tests, lat, s.truth.responsePeakDelay, 'AbsTol', 0.5);
    verifyEqual(tests, pk - base, s.truth.responseAmplitude, 'AbsTol', 5);
    verifyEqual(tests, base, s.truth.baseline, 'AbsTol', 8);
end

%% testErrors - Invalid filter, no trials, missing variables
function testErrors(tests)
    s = tests.TestData.demo;
    bad = catStruct(tests.TestData.proc, tests.TestData.seg);
    bad.cutoffHigh = 80;                               % above Nyquist (50 Hz after 10x)
    verifySubstring(tests, LDFPipeline.validateProcessing(bad, s.Fs), 'Nyquist');
    verifyError(tests, @() LDFPipeline.run(s.LDF, s.stim, s.t, s.Fs, bad), 'NeuroAnalyzer:LDFPipeline:invalidFilter');
    band = struct('downsample', 1, 'filterType', 4, 'designType', 1, 'filterOrder', 2, 'cutoffLow', 3, 'cutoffHigh', 2);
    verifySubstring(tests, LDFPipeline.validateProcessing(band, s.Fs), 'Low cutoff');
    none = struct('downsample', 1, 'filterType', 1, 'threshold', 10);   % stimulus never reaches 10
    verifyError(tests, @() LDFPipeline.run(s.LDF, s.stim, s.t, s.Fs, none), 'NeuroAnalyzer:LDFPipeline:noTrials');
    f = [tempname '.mat'];
    c = onCleanup(@() deleteIfExists(f));
    LDF = s.LDF; save(f, 'LDF');
    verifyError(tests, @() LDFPipeline.loadCropped(f), 'NeuroAnalyzer:LDFPipeline:missingVars');
    verifyEqual(tests, LDFPipeline.filterMode(5), 'stop');
    verifyEqual(tests, LDFPipeline.filterMode(99), 'low');
end

%% ------------------------------------------------------------------------
%  Reference: the code ProcessingLDFApp ran before LDFPipeline existed
%% ------------------------------------------------------------------------

%% legacySegment - segmentLDFByOnsets (onset detection + trial matrix), verbatim
function [ldfSegments, t_seg, onsets] = legacySegment(ldf, stim, Fs, threshold, preSec, postSec, minISI_sec)
    stimLogic = stim > threshold;
    stimLogic = stimLogic(:);
    rawOnsets = find(diff([0; stimLogic]) == 1);
    minISI_samp = round(minISI_sec * Fs);
    onsets = [];
    lastAccepted = -inf;
    for i = 1:length(rawOnsets)
        if rawOnsets(i) - lastAccepted >= minISI_samp
            onsets(end+1) = rawOnsets(i); %#ok<AGROW>
            lastAccepted = rawOnsets(i);
        end
    end
    preSamp = round(preSec * Fs);
    postSamp = round(postSec * Fs);
    segLength = preSamp + postSamp + 1;
    validSegments = zeros(0, 2);
    for i = 1:length(onsets)
        idx = onsets(i);
        startIdx = idx - preSamp;
        endIdx = idx + postSamp;
        if startIdx > 0 && endIdx <= length(ldf)
            validSegments = [validSegments; startIdx endIdx]; %#ok<AGROW>
        end
    end
    nTrials = size(validSegments, 1);
    ldfSegments = zeros(nTrials, segLength);
    for i = 1:nTrials
        ldfSegments(i,:) = ldf(validSegments(i,1):validSegments(i,2));
    end
    t_seg = (-preSamp:postSamp) / Fs;
end

%% legacyProcess - applyFilter's downsample + filter block, verbatim
function [filteredLDF, stim, t, Fs, b, a] = legacyProcess(LDF, stim, t, Fs, p)
    if p.downsample > 1
        LDFdec = decimate(double(LDF(:)), p.downsample);
        if isrow(LDF), LDFdec = LDFdec.'; end
        LDF = LDFdec;
        stim = downsample(stim, p.downsample);
        t = downsample(t, p.downsample);
        n = min([numel(LDF), numel(stim), numel(t)]);
        LDF = LDF(1:n); stim = stim(1:n); t = t(1:n);
        Fs = Fs / p.downsample;
    end
    b = []; a = [];
    if p.filterType == 1
        filteredLDF = LDF;
    else
        Wn = [];
        switch p.filterType
            case 2, Wn = p.cutoffHigh / (Fs/2);
            case 3, Wn = p.cutoffLow / (Fs/2);
            case 4, Wn = [p.cutoffLow p.cutoffHigh] / (Fs/2);
            case 5, Wn = [p.cutoffLow p.cutoffHigh] / (Fs/2);
        end
        modes = {'low', 'low', 'high', 'bandpass', 'stop'};
        mode = modes{p.filterType};
        switch p.designType
            case 1, [b, a] = butter(p.filterOrder, Wn, mode);
            case 2, [b, a] = cheby1(p.filterOrder, 0.5, Wn, mode);
            case 3, b = fir1(p.filterOrder, Wn, mode); a = 1;
        end
        filteredLDF = filtfilt(b, a, LDF);
    end
end

%% catStruct - Fields of b added to a
function a = catStruct(a, b)
    fn = fieldnames(b);
    for i = 1:numel(fn), a.(fn{i}) = b.(fn{i}); end
end

function deleteIfExists(f)
    if exist(f, 'file') == 2, delete(f); end
end

%% testShortPulsesSurviveDownsampling - Pulses shorter than the factor are not lost
function testShortPulsesSurviveDownsampling(tests)
    Fs = 1000; r = 10;
    stim = zeros(1, 20000);
    on = 1003:1537:19000;                    % 12 pulses of 5 samples (5 ms)
    for o = on, stim(o:o + 4) = 5; end
    y = LDFPipeline.downsampleTrigger(stim, r);
    verifyNumElements(tests, y, ceil(numel(stim) / r));
    found = LDFPipeline.detectOnsets(y, Fs / r, 2.5, 1);
    verifyNumElements(tests, found, numel(on));
    % Each onset is the first kept sample at or after the pulse start
    lag = (found - 1) * r + 1 - on;
    verifyGreaterThanOrEqual(tests, lag, 0);
    verifyLessThan(tests, lag, r);
    % Plain sample picking loses some of them (the bug this fixes)
    verifyLessThan(tests, numel(LDFPipeline.detectOnsets(stim(1:r:end), Fs / r, 2.5, 1)), numel(on));
    % Column input stays a column; long pulses give the same onsets as sample picking
    verifyEqual(tests, size(LDFPipeline.downsampleTrigger(stim(:), r)), [ceil(numel(stim) / r) 1]);
    long = zeros(1, 10007);
    for o = [500 3000 7001], long(o:o + 299) = 5; end
    for rr = [3 10 100]
        verifyEqual(tests, LDFPipeline.detectOnsets(LDFPipeline.downsampleTrigger(long, rr), Fs / rr, 2.5, 0.1), ...
            LDFPipeline.detectOnsets(long(1:rr:end), Fs / rr, 2.5, 0.1));
    end
end
