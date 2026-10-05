%% StableFormatsTest.m
% =========================================================================
% UNIT TESTS: FROZEN NAMES OF THE RESULTS SCRIPTS AND FILES DEPEND ON (1.0)
% =========================================================================
% Scripts, saved results and the summary files of other labs read these
% names, so from 1.0 on they only grow: every name listed here must still
% be there (new fields and columns are allowed; renaming or removing one
% fails, and the message names what is missing). Checked on small
% synthetic inputs and the demo data:
%   * GroupStats.compare (every design), its test results (main / check),
%     comparisons, GroupStats.describe and GroupStats.checkOptions;
%   * EEGAnalysis.measure, conditionERPs and measureTable (the columns of
%     the window's .csv and of Batch, in this order);
%   * the EEG struct of EEGSource.open;
%   * Batch.pipelines, Batch.columns of every pipeline (names, order and
%     types exactly), Batch.run's result R, R.record and the variables of
%     <Name>_summary.mat;
%   * LDFPipeline.run and defaultParams, MUAPipeline.defaultParams,
%     LaserSpeckle.analyze and defaults, QualityChecks.none.
% The window export files are locked in the walkthrough tests that write
% them (LFP, MUA, LSCI, ROI, Histology, EEG, Signal Characterization, LDF
% Processing, Extract LDF).
% Base MATLAB only; everything but the table checks also runs in GNU Octave.
% =========================================================================

function tests = StableFormatsTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.tmp = tempname;
    mkdir(tests.TestData.tmp);
end

function teardownOnce(tests)
    if exist(tests.TestData.tmp, 'dir') == 7, rmdir(tests.TestData.tmp, 's'); end
end

%% frozen - Every frozen name is present (struct fields, table columns or a cellstr)
function frozen(tests, have, names, what)
    if isstruct(have)
        have = fieldnames(have);
    elseif isa(have, 'table')
        have = have.Properties.VariableNames;
    end
    missing = names(~ismember(names, have));
    tests.verifyEmpty(missing, sprintf('%s: missing %s (frozen for 1.0: add, never rename or remove)', ...
        what, strjoin(missing, ', ')));
end

%% ------------------------------------------------------------- GroupStats

function testGroupStatsCompare(tests)
    a = [10 12 11 14 13 15 12 11];
    b = [13 15 14 18 15 19 14 13];
    c = [16 18 15 21 19 20 17 16];
    resFields = {'design', 'method', 'groupNames', 'values', 'nExcluded', 'desc', 'main', 'check', ...
        'checkAgrees', 'comparisons', 'assumptions', 'summary'};
    testFields = {'test', 'statName', 'stat', 'df', 'p', 'n', 'nExcluded', 'meanDiff', 'medianDiff', ...
        'ci', 'effectName', 'effect', 'effect2Name', 'effect2', 'method', 'note'};
    cmpFields = {'a', 'b', 'label', 'diff', 'ci', 'stat', 'p', 'method'};
    cases = {'paired', {a, b}; 'unpaired', {a, b}; 'anova', {a, b, c}; 'rm', {a, b, c}};
    for i = 1:size(cases, 1)
        for method = {'parametric', 'nonparametric'}
            what = sprintf('GroupStats.compare %s %s', cases{i, 1}, method{1});
            names = arrayfun(@(k) sprintf('G%d', k), 1:numel(cases{i, 2}), 'UniformOutput', false);
            res = GroupStats.compare(cases{i, 2}, names, cases{i, 1}, method{1});
            frozen(tests, res, resFields, what);
            frozen(tests, res.main, testFields, [what ' main']);
            frozen(tests, res.check, testFields, [what ' check']);
            frozen(tests, res.comparisons, cmpFields, [what ' comparisons']);
        end
    end
    res = GroupStats.compare({a, b, c}, {'A', 'B', 'C'}, 'rm', 'parametric');
    frozen(tests, res.comparisons, {'pRaw', 'effectName', 'effect', 'effectCI'}, 'rm comparisons');
    frozen(tests, res.main, {'groupNames', 'means', 'table', 'posthoc', 'sphericity'}, 'rmAnova');
    res = GroupStats.compare({a, b, c}, {'A', 'B', 'C'}, 'anova', 'parametric');
    frozen(tests, res.main, {'groupNames', 'means', 'table', 'posthoc'}, 'anova1way');
end

function testGroupStatsDescribeAndOptions(tests)
    frozen(tests, GroupStats.describe([1 2 3 NaN]), {'n', 'nMissing', 'mean', 'sd', 'sem', 'median', ...
        'q1', 'q3', 'iqr', 'min', 'max', 'ci95'}, 'GroupStats.describe');
    frozen(tests, GroupStats.describe([]), {'n', 'nMissing', 'mean', 'sd', 'sem', 'median', ...
        'q1', 'q3', 'iqr', 'min', 'max', 'ci95'}, 'GroupStats.describe (empty)');
    frozen(tests, GroupStats.checkOptions(), {'subjectMode', 'nFiles', 'labels', 'subject', ...
        'valuesTab', 'missingAction'}, 'GroupStats.checkOptions');
end

function testQualityChecksRow(tests)
    frozen(tests, QualityChecks.none(), {'level', 'topic', 'found', 'why', 'action'}, 'QualityChecks.none');
    Q = QualityChecks.add(QualityChecks.none(), 'check', 'Topic', 'Found.', 'Why.', 'Action.');
    frozen(tests, Q, {'level', 'topic', 'found', 'why', 'action'}, 'QualityChecks.add');
end

%% ------------------------------------------------------------------ EEG

function testEEGMeasureAndERPs(tests)
    eeg = tinyEEG();
    erp = EEGAnalysis.conditionERPs(eeg, 'Baseline', [-0.2 0]);
    frozen(tests, erp, {'mean', 'sem', 'n', 'conditions', 'times', 'labels', 'fs', 'baseline', 'bad'}, ...
        'EEGAnalysis.conditionERPs');
    for kind = {'mean', 'peak'}
        r = EEGAnalysis.measure(erp, 'Window', [0 0.2], 'Measure', kind{1});
        frozen(tests, r, {'condition', 'value', 'latency', 'atEdge', 'n'}, ['EEGAnalysis.measure ' kind{1}]);
    end
end

function testEEGMeasureTableColumns(tests)
    eeg = tinyEEG();
    T = EEGAnalysis.measureTable({eeg, eeg}, {'sub-01', 'sub-02'}, 'Window', [0 0.2], 'Measure', 'peak');
    tests.verifyEqual(T.Properties.VariableNames, {'Participant', 'Condition', 'Value_uV', 'Latency_ms', ...
        'Trials', 'PeakAtEdge'}, 'EEGAnalysis.measureTable columns (exactly; the window .csv and Batch match)');
end

function testEEGSourceStruct(tests)
    d = demoEEG(fullfile(tests.TestData.tmp, 'eeg'), 'Participants', 1, 'Kinds', {'scalp'}, ...
        'Formats', {'eeglab'});
    eeg = EEGSource.open(d.scalp(1).eeglab);
    names = {'data', 'fs', 'times', 'labels', 'chanlocs', 'coordSystem', 'isEpoched', 'trials', ...
        'conditions', 'events', 'reference', 'bad', 'history', 'notes', 'source', 'format', 'file'};
    frozen(tests, eeg, names, 'EEGSource.open');
    frozen(tests, eeg.trials, {'condition'}, 'EEG trials');
    frozen(tests, eeg.chanlocs, {'label', 'labels', 'x', 'y', 'z', 'theta', 'radius'}, 'EEG chanlocs');
    tests.verifyEqual({eeg.chanlocs.labels}, eeg.labels, 'chanlocs labels = the channel names (EEGLAB)');
    frozen(tests, tinyEEG(), names, 'EEGSource.make');
end

%% ---------------------------------------------------------------- Batch

function testBatchPipelinesAndColumns(tests)
    tests.verifyEqual(Batch.pipelines(), {'ldf', 'erp', 'mua', 'eeg', 'roi', 'features'}, 'Batch.pipelines');
    feat = {'PeakLatency_s', 'double'; 'OnsetDelay_s', 'double'; 'FWHM_s', 'double'; 'AUCpos', 'double'; ...
        'AUCneg', 'double'; 'RiseTime_s', 'double'; 'DecayTime_s', 'double'; 'PeakAmp', 'double'; ...
        'Integral', 'double'};
    tests.verifyEqual(Batch.FeatureColumns, feat(:, 1)', 'Batch.FeatureColumns');
    want = struct();
    want.ldf = [{'Fs_Hz', 'double'; 'nOnsets', 'double'; 'nTrials', 'double'; 'Baseline', 'double'}; feat; ...
        {'TrialFile', 'char'; 'Checks', 'char'}];
    want.erp = {'Channel', 'double'; 'nOnsets', 'double'; 'nEpochs', 'double'; 'N1Latency_ms', 'double'; ...
        'N1Amp', 'double'; 'P2Latency_ms', 'double'; 'P2Amp', 'double'; 'PeakToPeak', 'double'; ...
        'AmpUnit', 'char'; 'CSDMin', 'double'; 'CSDMinLatency_ms', 'double'; 'SinkChannel', 'double'; ...
        'Checks', 'char'};
    want.mua = {'Channel', 'double'; 'Duration_s', 'double'; 'nDetected', 'double'; 'nSpikes', 'double'; ...
        'nUnits', 'double'; 'nGoodUnits', 'double'; 'nRejected', 'double'; 'MeanRate_Hz', 'double'; ...
        'UnitRates_Hz', 'char'; 'MeanSNR', 'double'; 'MaxISIViol_pct', 'double'; 'nOnsets', 'double'; ...
        'BaselineRate_Hz', 'double'; 'EvokedRate_Hz', 'double'; 'Checks', 'char'};
    want.eeg = {'Condition', 'char'; 'Trials', 'double'; 'Rejected', 'double'; 'Value_uV', 'double'; ...
        'Latency_ms', 'double'; 'PeakAtEdge', 'double'; 'Channels', 'char'; 'BadChannels', 'char'; ...
        'Reference', 'char'; 'Fs_Hz', 'double'; 'Checks', 'char'};
    want.roi = {'ROI', 'char'; 'nFrames', 'double'; 'FrameRate_Hz', 'double'; 'MeanBrightness', 'double'; ...
        'PeakDFF', 'double'; 'PeakDFFTime_s', 'double'; 'MeanDiameter_px', 'double'; ...
        'MinDiameter_px', 'double'; 'MaxDiameter_px', 'double'; 'nDiameterOutliers', 'double'};
    want.features = [{'Series', 'char'; 'nSeries', 'double'; 'DataType', 'char'; 'Baseline', 'double'}; feat];
    for p = Batch.pipelines()
        tests.verifyEqual(Batch.columns(p{1}), want.(p{1}), sprintf('Batch.columns(''%s''): names, order and types', p{1}));
    end
end

function testBatchRunResult(tests)
    out = fullfile(tests.TestData.tmp, 'batch');
    R = Batch.run('features', {DemoData.file('ldfTrials')}, [], out, 'Name', 'frozen');
    frozen(tests, R, {'pipeline', 'params', 'files', 'summary', 'fileStatus', 'messages', 'log', 'paths', ...
        'nOK', 'nWarning', 'nError', 'nSkipped', 'cancelled', 'elapsed', 'record'}, 'Batch.run R');
    rec = {'pipeline', 'params', 'files', 'fileStatus', 'messages', 'log', 'created'};
    frozen(tests, R.record, rec, 'Batch.run R.record');
    frozen(tests, R.paths, {'folder', 'csv', 'mat', 'log', 'trials'}, 'Batch.run R.paths');
    tests.verifyEqual(R.nOK, 1, strjoin(R.log, newline));
    c = Batch.columns('features');                % name, type
    cols = [{'File'; 'Status'; 'Message'}; c(:, 1)];
    frozen(tests, R.summary, cols', 'Batch.run R.summary');
    s = load(R.paths.mat);
    frozen(tests, s, {'summary', 'batch'}, '<Name>_summary.mat');
    frozen(tests, s.batch, rec, '<Name>_summary.mat batch');
    T = readtable(R.paths.csv);
    frozen(tests, T, cols', '<Name>_summary.csv');
end

%% ---------------------------------------------------- Pipelines (no window)

function testLDFPipeline(tests)
    frozen(tests, LDFPipeline.defaultParams(), {'downsample', 'filterType', 'designType', 'filterOrder', ...
        'cutoffLow', 'cutoffHigh', 'threshold', 'preSec', 'postSec', 'minISI'}, 'LDFPipeline.defaultParams');
    s = LDFPipeline.loadCropped(DemoData.file('ldfCropped'));
    r = LDFPipeline.run(s.LDF, s.stim, s.t, s.Fs, LDFPipeline.defaultParams());   % no filter: base MATLAB
    frozen(tests, r, {'segmentedLDF', 'segmentedTime', 'Fs', 'onsets', 'nOnsets', 'nTrials', 'LDF', ...
        'stim', 't', 'checkRows'}, 'LDFPipeline.run');
end

function testMUAPipelineParams(tests)
    frozen(tests, MUAPipeline.defaultParams(), {'detectMethod', 'clusterMethod', 'threshold', ...
        'refractoryMs', 'alignWinMs', 'polarity', 'filter', 'bpLow', 'bpHigh', 'featureMethod', ...
        'numComponents', 'normalize', 'minSpikesPerCluster', 'randomSeed', 'enableDriftCorrection', ...
        'driftMethod', 'driftBinWidth', 'enableGridSearchCheck', 'dbscanEpsilon', 'autoMerge', ...
        'mergeThreshold', 'mergeMinAmpRatio'}, 'MUAPipeline.defaultParams');
end

function testLaserSpeckle(tests)
    p = LaserSpeckle.defaults();
    frozen(tests, p, {'InputType', 'Contrast', 'Window', 'Frames', 'Dark', 'FlowModel', 'Beta', ...
        'ExposureMs', 'Fps', 'Onsets', 'PreSec', 'PostSec', 'ResponseSec', 'BaselineSec'}, 'LaserSpeckle.defaults');
    rs = RandStream('mt19937ar', 'Seed', 7);
    I = 100 + 30 * rand(rs, 24, 24, 60);
    t = (0:59) / 10;
    p.Onsets = [2 4];
    p.PreSec = 1;
    p.PostSec = 1.5;
    p.ResponseSec = [0.2 1];
    masks = false(24, 24, 2);
    masks(3:10, 3:10, 1) = true;
    masks(14:20, 14:20, 2) = true;
    R = LaserSpeckle.analyze(I, t, masks, p, {'A', 'B'});
    frozen(tests, R, {'params', 'roiNames', 'meanImage', 'intensity', 't', 'fps', 'units', 'flowMean', ...
        'K2Mean', 'roiFlow', 'baselineSec', 'roiRel', 'roiK', 'shift', 'trialTime', 'onsets', 'trials', ...
        'trialMean', 'trialSD', 'peak', 'peakTime', 'response', 'responseMap', 'checks', 'checkRows'}, ...
        'LaserSpeckle.analyze');
    frozen(tests, R.shift, {'t', 'dx', 'dy'}, 'LaserSpeckle.analyze shift');
end

%% ---------------------------------------------------------------- helpers

%% tinyEEG - 2 channels x 5 samples x 4 trials, conditions A and B
function eeg = tinyEEG()
    x = zeros(2, 5, 4);
    for k = 1:4
        x(:, :, k) = k + [1; 2] * [0 0 3 6 3];
    end
    eeg = EEGSource.make(x, 10, 'Times', (-2:2) / 10, 'Labels', {'Fz', 'Cz'}, ...
        'Conditions', {'A', 'B', 'A', 'B'}, 'IsEpoched', true, 'Unit', 'uV');
end
