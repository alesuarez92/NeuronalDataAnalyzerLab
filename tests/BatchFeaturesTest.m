%% BatchFeaturesTest.m
% =========================================================================
% BATCH PROCESSING: EVERY PIPELINE RECOVERS THE DEMO TRUTHS, ERRORS LOGGED
% =========================================================================
% Runs core/Batch.m on the demo sets of core/demo/demoBatch.m (a few files
% per pipeline with known, slightly different answers) and checks, per
% file, that the summary table recovers what was simulated. Also checks
% that a corrupt or wrong file is recorded as an error while the other
% files still run, that the CSV, MAT and log files are written, that
% Cancel skips the remaining files, and that MUA sorting is repeatable
% (seeded) and leaves the global random stream as it was.
% 'ldf' needs the Signal Processing Toolbox and 'mua' also the Statistics
% and Machine Learning Toolbox; those tests are skipped without them.
% =========================================================================

function tests = BatchFeaturesTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.dir = tempname;
    mkdir(tests.TestData.dir);
end

function teardownOnce(tests)
    if exist(tests.TestData.dir, 'dir') == 7, rmdir(tests.TestData.dir, 's'); end
end

function hasSPT = assumeSPT(tests)
    hasSPT = license('test', 'Signal_Toolbox') && exist('decimate', 'file') == 2 && exist('filtfilt', 'file') == 2;
    tests.assumeTrue(hasSPT, 'Needs the Signal Processing Toolbox');
end

%% testLDF - Trials and response features per file; bad files logged, the rest run
function testLDF(tests)
    assumeSPT(tests);
    d = tests.TestData.dir;
    demo = demoBatch('ldf', fullfile(d, 'ldf'));
    corrupt = fullfile(d, 'corrupt_ldf.mat');
    writeText(corrupt, 'this is not a MAT file');
    wrong = fullfile(d, 'wrong_vars.mat');
    x = 1:10; save(wrong, 'x');
    files = [demo.files(1:2), {corrupt}, demo.files(3:end), {wrong}];
    out = fullfile(d, 'out_ldf');
    R = Batch.run('ldf', files, demo.params, out, 'Name', 'ldf_test');

    T = R.summary;
    verifyEqual(tests, height(T), numel(files));
    verifyEqual(tests, [R.nOK R.nError R.nSkipped], [numel(demo.files) 2 0]);
    verifyEqual(tests, R.fileStatus, {'ok', 'ok', 'error', 'ok', 'ok', 'error'});
    verifyEqual(tests, T.Status{3}, 'error');
    verifyNotEmpty(tests, T.Message{3});
    verifySubstring(tests, T.Message{6}, 'Missing variable');
    verifyTrue(tests, all(isnan(T.PeakAmp([3 6]))));

    good = find(strcmp(T.Status, 'ok'));
    for i = 1:numel(good)
        r = good(i);
        tr = demo.truth(i);
        verifyEqual(tests, T.nOnsets(r), tr.nOnsets, sprintf('%s: onsets', T.File{r}));
        verifyEqual(tests, T.nTrials(r), tr.nTrials, sprintf('%s: trials', T.File{r}));
        verifyEqual(tests, T.Fs_Hz(r), 100);
        verifyEqual(tests, T.PeakLatency_s(r), tr.peakDelay, 'AbsTol', 0.4, sprintf('%s: peak latency', T.File{r}));
        verifyEqual(tests, T.PeakAmp(r), tr.amplitude, 'AbsTol', 3, sprintf('%s: amplitude', T.File{r}));
        verifyEqual(tests, T.Baseline(r), tr.baseline, 'AbsTol', 8);
        % Trial file in the LDF Processing format
        s = load(fullfile(out, T.TrialFile{r}));
        verifySize(tests, s.segmentedLDF, [tr.nTrials, 2501]);
        verifyEqual(tests, s.segmentedTime([1 end]), [-5 20], 'AbsTol', 1e-9);
        verifyEqual(tests, s.Fs, 100);
    end
    % Larger simulated responses give larger measured ones (file order)
    verifyTrue(tests, all(diff(T.PeakAmp(good)) > 0));

    checkOutputs(tests, R, numel(files));
    logText = fileread(R.paths.log);
    verifySubstring(tests, logText, 'corrupt_ldf.mat: ERROR');
    verifySubstring(tests, logText, 'threshold = 2.5');
end

%% testERP - N1 latency and CSD sink channel per file (folder input)
function testERP(tests)
    demo = demoBatch('erp', fullfile(tests.TestData.dir, 'erp'));
    R = Batch.run('erp', demo.folder, demo.params, fullfile(tests.TestData.dir, 'out_erp'), 'Name', 'erp_test');
    T = R.summary;
    verifyEqual(tests, R.nOK, numel(demo.files));
    verifyEqual(tests, height(T), 8 * numel(demo.files));     % one row per channel
    for k = 1:numel(demo.files)
        [~, nm, ex] = fileparts(demo.files{k});
        rows = strcmp(T.File, [nm ex]);
        tr = demo.truth(k);
        verifyEqual(tests, unique(T.SinkChannel(rows)), tr.sinkChannel, sprintf('%s: sink', nm));
        r = rows & T.Channel == tr.sinkChannel;
        verifyEqual(tests, T.nEpochs(r), tr.nOnsets);
        verifyEqual(tests, T.N1Latency_ms(r), tr.n1LatencyMs, 'AbsTol', 1.5, sprintf('%s: N1 latency', nm));
        verifyEqual(tests, T.N1Amp(r), tr.n1AmplitudeUv, 'RelTol', 0.2, sprintf('%s: N1 amplitude', nm));
        verifyEqual(tests, T.CSDMinLatency_ms(r), tr.n1LatencyMs, 'AbsTol', 2);
        verifyLessThan(tests, T.CSDMin(r), 0);
        % The largest N1 is on the sink channel
        [~, iMin] = min(T.N1Amp(rows));
        ch = T.Channel(rows);
        verifyEqual(tests, ch(iMin), tr.sinkChannel);
    end
    verifyEqual(tests, unique(T.AmpUnit), {'uV'});

    % Subset of channels, CSD off
    p = demo.params; p.channels = [2 3 4]; p.computeCSD = false;
    R2 = Batch.run('erp', demo.files(1), p, fullfile(tests.TestData.dir, 'out_erp'), 'Name', 'erp_sub');
    verifyEqual(tests, R2.summary.Channel', [2 3 4]);
    verifyTrue(tests, all(isnan(R2.summary.SinkChannel)));
    % A channel that is not in the file: that file fails with a clear message
    p.channels = 12;
    R3 = Batch.run('erp', demo.files(1), p, fullfile(tests.TestData.dir, 'out_erp'), 'Name', 'erp_bad');
    verifyEqual(tests, R3.fileStatus, {'error'});
    verifySubstring(tests, R3.messages{1}, 'not in the file');
end

%% testROI - Peak dF/F of the cell and mean vessel diameter per stack
function testROI(tests)
    demo = demoBatch('roi', fullfile(tests.TestData.dir, 'roi'));
    R = Batch.run('roi', demo.files, demo.params, fullfile(tests.TestData.dir, 'out_roi'), 'Name', 'roi_test');
    T = R.summary;
    verifyEqual(tests, R.nOK, numel(demo.files));
    verifyEqual(tests, height(T), numel(demo.files));         % one ROI per stack
    for k = 1:numel(demo.files)
        tr = demo.truth(k);
        verifyEqual(tests, T.PeakDFF(k), tr.peakDFF, 'AbsTol', 0.1, sprintf('file %d: peak dF/F', k));
        verifyEqual(tests, T.PeakDFFTime_s(k), tr.peakDFFTime, 'AbsTol', 0.15);
        verifyEqual(tests, T.MeanDiameter_px(k), tr.meanDiameter, 'AbsTol', 0.75, sprintf('file %d: diameter', k));
        verifyEqual(tests, T.FrameRate_Hz(k), 10, 'AbsTol', 1e-6);
        verifyEqual(tests, T.nFrames(k), 100);
    end
    % Only the diameter: one row per file without ROI values
    p = demo.params; p.measure = 'Vessel diameter';
    R2 = Batch.run('roi', demo.files(1), p, fullfile(tests.TestData.dir, 'out_roi'), 'Name', 'roi_diam');
    verifyTrue(tests, isnan(R2.summary.PeakDFF));
    verifyEqual(tests, R2.summary.MeanDiameter_px, T.MeanDiameter_px(1), 'AbsTol', 1e-12);
    % Diameter asked for without a line: clear error
    p.line = [];
    R3 = Batch.run('roi', demo.files(1), p, fullfile(tests.TestData.dir, 'out_roi'), 'Name', 'roi_noline');
    verifySubstring(tests, R3.messages{1}, 'needs a line');
end

%% testFeatures - Response features of the mean trace, or of every series
function testFeatures(tests)
    demo = demoBatch('features', fullfile(tests.TestData.dir, 'features'));
    R = Batch.run('features', demo.files, demo.params, fullfile(tests.TestData.dir, 'out_feat'), 'Name', 'feat_test');
    T = R.summary;
    verifyEqual(tests, R.nOK, numel(demo.files));
    for k = 1:numel(demo.files)
        tr = demo.truth(k);
        verifyEqual(tests, T.nSeries(k), tr.nTrials);
        verifyEqual(tests, T.PeakLatency_s(k), tr.peakDelay, 'AbsTol', 0.35, sprintf('file %d: latency', k));
        verifyEqual(tests, T.PeakAmp(k), tr.amplitude, 'AbsTol', 1.5, sprintf('file %d: amplitude', k));
        verifyEqual(tests, T.Baseline(k), tr.baseline, 'AbsTol', 1);
    end
    verifyEqual(tests, T.DataType{1}, 'LDF segments');

    % Same numbers as Batch.seriesFeatures on the mean trial by hand
    s = load(demo.files{1});
    v = Batch.seriesFeatures(s.segmentedTime, mean(s.segmentedLDF, 1), 0, [s.segmentedTime(1) 0], 'Auto');
    verifyEqual(tests, [T.PeakLatency_s(1) T.PeakAmp(1) T.FWHM_s(1)], v([1 8 3]), 'AbsTol', 1e-12);

    p = demo.params; p.seriesMode = 'Each series';
    R2 = Batch.run('features', demo.files(1:2), p, fullfile(tests.TestData.dir, 'out_feat'), 'Name', 'feat_each');
    verifyEqual(tests, height(R2.summary), 2 * demo.truth(1).nTrials);
    verifyEqual(tests, R2.summary.Series{3}, 'Trial 3');
end

%% testMUA - Units per channel, seeded (repeatable) sorting, gain-invariant counts
function testMUA(tests)
    tests.assumeTrue(license('test', 'Statistics_Toolbox') && license('test', 'Signal_Toolbox') && ...
        exist('kmeans', 'file') == 2 && exist('findpeaks', 'file') == 2, ...
        'Spike sorting needs the Signal Processing and Statistics and Machine Learning Toolboxes');
    demo = demoBatch('mua', fullfile(tests.TestData.dir, 'mua'));
    rng(123, 'twister');
    R = Batch.run('mua', demo.files, demo.params, fullfile(tests.TestData.dir, 'out_mua'), 'Name', 'mua_test');
    after = rand(1, 3);
    rng(123, 'twister');
    verifyEqual(tests, after, rand(1, 3), 'Batch.run must leave the global random stream as it was');

    T = R.summary;
    verifyEqual(tests, R.nOK, 2);
    verifyEqual(tests, T.Channel', [4 4]);
    for k = 1:2
        verifyGreaterThanOrEqual(tests, T.nUnits(k), 2);
        verifyLessThanOrEqual(tests, T.nUnits(k), 3);
        verifyGreaterThan(tests, T.nSpikes(k), 300);
        verifyGreaterThan(tests, T.EvokedRate_Hz(k), 3 * T.BaselineRate_Hz(k));
        verifyEqual(tests, T.nOnsets(k), numel(demo.truth(k).demo.onsets));
        verifyGreaterThan(tests, T.MeanSNR(k), 2);
    end
    % Twice the gain: the same spikes (sorting is scale-invariant)
    verifyEqual(tests, T.nSpikes(2), T.nSpikes(1), 'RelTol', 0.05);
    % Seeded: the same file gives the same result again
    R2 = Batch.run('mua', demo.files(1), demo.params, fullfile(tests.TestData.dir, 'out_mua'), 'Name', 'mua_again');
    verifyEqual(tests, [R2.summary.nSpikes R2.summary.nUnits], [T.nSpikes(1) T.nUnits(1)]);
end

%% testErrorsAndCancel - Unreadable / unsupported files logged; Cancel skips the rest
function testErrorsAndCancel(tests)
    d = tests.TestData.dir;
    demo = demoBatch('features', fullfile(d, 'features_err'), 3);
    bad = fullfile(d, 'garbage.mat');
    writeText(bad, 'garbage');
    other = fullfile(d, 'unsupported.mat');
    q = magic(3); save(other, 'q');
    files = [demo.files(1), {bad, other}, demo.files(2:3), {fullfile(d, 'missing.mat')}];
    R = Batch.run('features', files, [], fullfile(d, 'out_err'), 'Name', 'errors');
    verifyEqual(tests, R.fileStatus, {'ok', 'error', 'error', 'ok', 'ok', 'error'});
    verifySubstring(tests, R.messages{3}, 'No supported variables');
    verifySubstring(tests, R.messages{6}, 'not found');
    verifyEqual(tests, R.nOK, 3);
    checkOutputs(tests, R, numel(files));

    % Cancel after the second file: the others are recorded as skipped
    flag = fullfile(d, 'cancel.flag');
    progress = @(k, n, f, st, msg) cancelAfter(k, 2, st, flag);
    R2 = Batch.run('features', demo.files, [], fullfile(d, 'out_err'), 'Name', 'cancel', ...
        'Progress', progress, 'Cancel', @() exist(flag, 'file') == 2);
    verifyTrue(tests, R2.cancelled);
    verifyEqual(tests, R2.fileStatus, {'ok', 'ok', 'skipped'});
    verifyEqual(tests, R2.summary.Status', {'ok', 'ok', 'skipped'});
    verifyEqual(tests, R2.nSkipped, 1);
    verifySubstring(tests, fileread(R2.paths.log), 'cancelled');
end

%% testDefaultsAndInputs - Settings, form fields, file listing, bad calls
function testDefaultsAndInputs(tests)
    for name = Batch.pipelines()
        p = Batch.defaults(name{1});
        spec = Batch.paramSpec(name{1});
        verifyTrue(tests, all(isfield(p, {spec.name})), name{1});
        d = Batch.describe(name{1});
        verifyNotEmpty(tests, d.label);
        q = Batch.completeParams(name{1}, struct());
        verifyEqual(tests, sort(fieldnames(q)), sort(fieldnames(p)));
        cols = Batch.columns(name{1});
        T = Batch.rowsToTable(name{1}, {struct('File', 'a.mat', 'Status', 'error', 'Message', 'boom')});
        verifyEqual(tests, width(T), 3 + size(cols, 1));
    end
    verifyError(tests, @() Batch.defaults('nope'), 'NeuroAnalyzer:Batch:unknownPipeline');
    verifyError(tests, @() Batch.run('features', {}, [], tests.TestData.dir), 'NeuroAnalyzer:Batch:noInputs');

    folder = fullfile(tests.TestData.dir, 'listing');
    mkdir(folder);
    x = 1; save(fullfile(folder, 'b.mat'), 'x'); save(fullfile(folder, 'a.mat'), 'x');
    writeText(fullfile(folder, 'notes.txt'), 'x');
    writeText(fullfile(folder, 'c.tif'), 'x');
    files = Batch.listInputs(folder, 'features');
    verifyEqual(tests, files, {fullfile(folder, 'a.mat'), fullfile(folder, 'b.mat')});
    verifyNumElements(tests, Batch.listInputs(folder, 'roi'), 3);   % .mat and .tif
    verifyNumElements(tests, Batch.listInputs({folder, fullfile(folder, 'notes.txt')}, 'features'), 3);
end

%% ------------------------------------------------------------------------
%  Helpers
%% ------------------------------------------------------------------------

%% checkOutputs - CSV, MAT and log written and consistent with the result
function checkOutputs(tests, R, nFiles)
    verifyEqual(tests, exist(R.paths.csv, 'file'), 2);
    verifyEqual(tests, exist(R.paths.mat, 'file'), 2);
    verifyEqual(tests, exist(R.paths.log, 'file'), 2);
    csv = readtable(R.paths.csv);
    verifyEqual(tests, height(csv), height(R.summary));
    verifyEqual(tests, csv.Properties.VariableNames, R.summary.Properties.VariableNames);
    m = load(R.paths.mat);
    verifyTrue(tests, isfield(m, 'summary') && isfield(m, 'batch'));
    verifyEqual(tests, height(m.summary), height(R.summary));
    verifyEqual(tests, m.batch.fileStatus, R.fileStatus);
    logText = fileread(R.paths.log);
    for k = 1:nFiles
        [~, nm, ex] = fileparts(R.files{k});
        verifySubstring(tests, logText, sprintf('[%d/%d] %s%s', k, nFiles, nm, ex));
    end
end

%% cancelAfter - Progress callback that asks to cancel once file k0 is done
function cancelAfter(k, k0, status, flag)
    if k >= k0 && ~strcmp(status, 'running')
        writeText(flag, 'cancel');
    end
end

function writeText(path, text)
    fid = fopen(path, 'w');
    fprintf(fid, '%s', text);
    fclose(fid);
end
