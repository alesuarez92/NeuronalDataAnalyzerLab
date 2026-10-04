%% MUAChecksTest.m
% =========================================================================
% UNIT TESTS: SPIKE SORTING QUALITY CHECKS (MUA ANALYSIS AND BATCH)
% =========================================================================
% MUAPipeline.checks on the clusters of one sorted channel:
%   * refractory period: % of intervals shorter than the refractory period
%     per unit (OK at or below 1%, Check above or when a unit was rejected
%     for it, Warning when a kept unit is above 2%);
%   * signal-to-noise: Check when a kept unit is below SNR 3, Warning when
%     no unit reaches 3.5; clusters rejected for SNR < 2 named as noise;
%   * amplitude drift: the spike peak of each kept unit over time (Check
%     above 20%, Warning above 40%), also for a drifting unit split in two
%     clusters; a note when no unit has 50 spikes;
%   * odd input gives fewer rows, never an error;
%   * the clean demo (channels 4 and 5) gives no warnings; the faults demo
%     (DemoData.muaFaults: low SNR on channel 3, a unit without a
%     refractory period on channel 4, a shrinking unit on channel 5) fires
%     each check;
%   * Batch 'mua': the Checks column and the log line.
% The rules run on synthetic clusters (base MATLAB, also GNU Octave); the
% demo tests need the real sorter (Signal Processing and Statistics and
% Machine Learning Toolboxes) and the Batch test tables: skipped without.
% =========================================================================

function tests = MUAChecksTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'demo'));
end

%% row - The first row of a topic ([] when none)
function r = row(Q, topic)
    r = [];
    if isempty(Q), return; end
    k = find(strcmp({Q.topic}, topic), 1);
    if ~isempty(k), r = Q(k); end
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

%% qcs - Cluster QC as MUAPipeline.qualityMetrics gives it
function qc = qcs(ids, snr, isi, rejected, reason)
    if nargin < 4, rejected = zeros(size(ids)); end
    if nargin < 5, reason = repmat({''}, size(ids)); end
    qc = struct('id', num2cell(ids), 'n', 100, 'snr', num2cell(snr), 'isiPct', num2cell(isi), ...
        'isiMs', {[]}, 'rejected', num2cell(logical(rejected)), 'reason', reason);
end

%% checksOf - The checks of clusters without waveforms (no amplitude row)
function Q = checksOf(qc, params)
    if nargin < 2, params = struct(); end
    Q = MUAPipeline.checks(struct(), struct('qc', qc), params);
end

%% driftData - Units over 30 s whose negative peak goes from a(1) to a(2) (V)
% amps: one [start end] per unit; n spikes each. Waveforms: a Gaussian
% trough at the centre of 61 samples plus a little noise.
function [res, info] = driftData(amps, n)
    rs = RandStream('mt19937ar', 'Seed', 7);
    shape = -exp(-((-30:30) / 4).^2);
    t = []; lab = []; W = [];
    for u = 1:numel(amps)
        tu = sort(30 * rand(rs, n, 1));
        a = amps{u}(1) + (amps{u}(2) - amps{u}(1)) * tu / 30;
        t = [t; tu]; lab = [lab; u * ones(n, 1)]; %#ok<AGROW>
        W = [W; a * shape + 0.02 * max(amps{u}) * randn(rs, n, numel(shape))]; %#ok<AGROW>
    end
    res = struct('spikeTimes', t, 'clusterIdx', lab);
    info = struct('qc', qcs(1:numel(amps), 6 * ones(1, numel(amps)), zeros(1, numel(amps))), 'waves', W);
end

function testRefractoryPeriod(tests)
    Q = checksOf(qcs([0 1 2], [1.5 5 4], [3 0.2 0.5]));
    expect(tests, Q, 'Refractory period', 'ok', 'at most 0.5% (unit 2)');      % noise (0) is not judged
    expect(tests, Q, 'Refractory period', 'ok', 'check above 1%');
    Q = checksOf(qcs([1 2], [5 4], [0.2 1.5]));
    expect(tests, Q, 'Refractory period', 'check', 'unit 2 1.5%');
    Q = checksOf(qcs([1 2 3], [5 4 4], [0 6.6 0.3], [0 1 0], {'', 'ISI Violation', ''}));
    expect(tests, Q, 'Refractory period', 'check', 'unit 2 6.6% (rejected for it)');
    tests.verifyTrue(~isempty(row(Q, 'Refractory period').why), 'the row says why it matters');
    tests.verifyTrue(~isempty(row(Q, 'Refractory period').action), 'and what to try');
    Q = checksOf(qcs([1 2], [5 4], [3.1 0]));                                  % kept above 2% (e.g. other QC limits)
    expect(tests, Q, 'Refractory period', 'warning', 'unit 1 3.1%');
    Q = checksOf(qcs(1, 5, 0.3), struct('refractoryMs', 2));
    expect(tests, Q, 'Refractory period', 'ok', '(2 ms)');
    Q = checksOf(qcs([1 2], [1.5 1.8], [0 0], [1 1], {'Low SNR', 'Low SNR'}));
    tests.verifyEmpty(row(Q, 'Refractory period'), 'every unit rejected as noise: the SNR row says it');
end

function testSignalToNoise(tests)
    Q = checksOf(qcs([1 2], [5.2 3.8], [0 0]));
    expect(tests, Q, 'Signal-to-noise', 'ok', 'lowest: unit 2, 3.8');
    Q = checksOf(qcs([1 2 3], [5.2 2.2 2.8], [0 0 0]));
    expect(tests, Q, 'Signal-to-noise', 'check', 'unit 2 (2.2), unit 3 (2.8)');
    expect(tests, Q, 'Signal-to-noise', 'check', 'best: unit 1 (5.2)');
    Q = checksOf(qcs([1 2 3], [2.4 2.7 3.2], [0 0 0]));
    expect(tests, Q, 'Signal-to-noise', 'warning', 'No unit reaches SNR 3.5: unit 1 (2.4)');
    Q = checksOf(qcs([1 2 3], [5 4 1.7], [0 0 0], [0 0 1], {'', '', 'Low SNR'}));
    expect(tests, Q, 'Signal-to-noise', 'ok', 'Cluster 3 was rejected as noise (SNR below 2)');
    Q = checksOf(qcs([1 2], [1.5 1.8], [0 0], [1 1], {'Low SNR', 'Low SNR'}));
    expect(tests, Q, 'Signal-to-noise', 'warning', 'Clusters 1 and 2 were rejected as noise');
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 1);
end

function testAmplitudeDrift(tests)
    [res, info] = driftData({[100e-6 100e-6], [100e-6 50e-6]}, 200);
    Q = MUAPipeline.checks(res, info, struct());
    expect(tests, Q, 'Amplitude drift', 'warning', 'last spike: unit 2 -');   % the worst first
    expect(tests, Q, 'Amplitude drift', 'warning', ' uV over 30 s)');
    m = res.clusterIdx == 2;
    chg = MUAPipeline.amplitudeChange(res.spikeTimes(m), abs(info.waves(m, 31)));
    tests.verifyEqual(chg, -50, 'AbsTol', 3);
    [res, info] = driftData({[100e-6 70e-6]}, 200);
    expect(tests, MUAPipeline.checks(res, info, struct()), 'Amplitude drift', 'check', 'unit 1 -');
    [res, info] = driftData({[100e-6 90e-6]}, 200);
    expect(tests, MUAPipeline.checks(res, info, struct()), 'Amplitude drift', 'ok', 'check above 20%');
    % Not in volts: the values without a unit
    [res, info] = driftData({[100 50]}, 200);
    Q = MUAPipeline.checks(res, info, struct());
    expect(tests, Q, 'Amplitude drift', 'warning', ' over 30 s)');
    tests.verifyTrue(isempty(strfind(row(Q, 'Amplitude drift').found, 'uV')), row(Q, 'Amplitude drift').found); %#ok<STREMP>
    % One drifting unit split in two clusters by size: measured together
    [res, info] = driftData({[100e-6 50e-6]}, 400);
    res.clusterIdx(res.spikeTimes >= 15) = 2;
    info.qc = qcs([1 2], [6 5], [0 0]);
    Q = MUAPipeline.checks(res, info, struct());
    expect(tests, Q, 'Amplitude drift', 'warning', 'last spike: units 1 + 2 (the same shape, one after the other');
    % Rejected units are not judged; too few spikes: a note
    [res, info] = driftData({[100e-6 50e-6], [100e-6 100e-6]}, 200);
    info.qc(1).rejected = true; info.qc(1).reason = 'ISI Violation';
    expect(tests, MUAPipeline.checks(res, info, struct()), 'Amplitude drift', 'ok');
    [res, info] = driftData({[100e-6 50e-6]}, 30);
    expect(tests, MUAPipeline.checks(res, info, struct()), 'Amplitude drift', 'note', 'Not judged');
    % No waveforms (e.g. a session too large to store them): no row
    tests.verifyEmpty(row(MUAPipeline.checks(res, rmfield(info, 'waves'), struct()), 'Amplitude drift'));
end

function testOddInput(tests)
    tests.verifyEmpty(MUAPipeline.checks([], [], []));
    tests.verifyEmpty(MUAPipeline.checks(struct(), struct('qc', []), []));
    tests.verifyEmpty(MUAPipeline.checks(struct(), struct('qc', qcs(0, 2, 0)), []), 'noise only: no units to judge');
    [res, info] = driftData({[100e-6 50e-6]}, 100);
    info.waves = info.waves(1:50, :);                                         % does not match the spikes
    Q = MUAPipeline.checks(res, info, []);
    tests.verifyEmpty(row(Q, 'Amplitude drift'));
    tests.verifyNotEmpty(row(Q, 'Signal-to-noise'));
    Q = checksOf(qcs([1 2], [NaN NaN], [0 0]));
    tests.verifyEmpty(row(Q, 'Signal-to-noise'), 'no SNR to judge');
    tests.verifyTrue(isnan(MUAPipeline.amplitudeChange(1:5, 1:5)), 'too few spikes');
end

%% assumeSorter - The demo tests run the real sorter
function assumeSorter(tests)
    tests.assumeTrue(license('test', 'Statistics_Toolbox') && license('test', 'Signal_Toolbox') && ...
        exist('kmeans', 'file') == 2 && exist('findpeaks', 'file') == 2, ...
        'Spike sorting needs the Signal Processing and Statistics and Machine Learning Toolboxes');
end

%% sortChecks - Sort one channel with the demo settings of MUA Analysis (seed 0) and check it
function [Q, qc] = sortChecks(s, ch)
    c = find(s.mua_channels == ch, 1);
    p = MUAPipeline.completeParams(struct('detectMethod', 'MAD', 'threshold', 4, 'polarity', 'negative'));
    prevRng = rng; restore = onCleanup(@() rng(prevRng));
    rng(p.randomSeed, 'twister');
    x = double(s.mua_data(c, :)); t = s.t_mua; fs = s.mua_fs; %#ok<NASGU>
    res = []; info = []; %#ok<NASGU>
    evalc('[res, info] = MUAPipeline.sort(x, t, fs, p);');
    Q = MUAPipeline.checks(res, info, p);
    qc = info.qc;
end

function testCleanDemo(tests)
    assumeSorter(tests);
    s = DemoData.muaFile();
    for ch = [4 5]          % channel 3 has no unit of its own (units 1-2 seen from 100 um, under the threshold)
        Q = sortChecks(s, ch);
        txt = sprintf('ch %d:\n%s', ch, strjoin(QualityChecks.lines(Q), newline));
        tests.verifyEqual(QualityChecks.count(Q, 'warning'), 0, txt);
        expect(tests, Q, 'Refractory period', 'ok');
        expect(tests, Q, 'Amplitude drift', 'ok');
        r = row(Q, 'Signal-to-noise');
        tests.verifyNotEmpty(r, txt);
        if ~isempty(r)   % a weak cluster (unit 3 seen from afar, noise crossings) may be a Check
            tests.verifyTrue(any(strcmp(r.level, {'ok', 'check'})), txt);
        end
    end
end

function testFaultsDemo(tests)
    s = DemoData.muaFaults();
    tests.verifyEqual(s.mua_channels, 3:5);
    tests.verifyEqual(size(s.mua_data), [3 numel(s.t_mua)]);
    tests.verifyEqual([s.truth.faults.channel], 3:5);
    tests.verifyEqual({s.truth.faults.check}, {'Signal-to-noise', 'Refractory period', 'Amplitude drift'});
    tests.verifyEqual(s.truth.noiseUV, [40 10 10]);
    % The unit without a refractory period has intervals < 1 ms; the others none < 2 ms
    isi = diff(s.truth.units(4).spikeTimes);
    tests.verifyGreaterThan(mean(isi < 1e-3), 0.1);
    tests.verifyGreaterThanOrEqual(min(diff(s.truth.units(3).spikeTimes)), 2e-3);
    assumeSorter(tests);
    expect(tests, sortChecks(s, 3), 'Signal-to-noise', 'warning', 'No unit reaches SNR 3.5');
    Q = sortChecks(s, 4);
    r = row(Q, 'Refractory period');
    tests.verifyNotEmpty(r, strjoin(QualityChecks.lines(Q), newline));
    if ~isempty(r), tests.verifyTrue(any(strcmp(r.level, {'check', 'warning'})), r.found); end
    expect(tests, sortChecks(s, 5), 'Amplitude drift', 'warning', 'unit');
end

function testBatchChecksColumn(tests)
    tests.assumeTrue(exist('table', 'file') > 0 && exist('writetable', 'file') > 0, 'Needs table / writetable');
    assumeSorter(tests);
    d = fullfile(tempdir, sprintf('MUAChecksTest_%d', round(1e6 * rand)));
    mkdir(d); c = onCleanup(@() rmdir(d, 's'));
    clean = fullfile(d, 'clean.mat'); faults = fullfile(d, 'faults.mat');
    s = DemoData.muaFile(); save(clean, '-struct', 's');
    s = DemoData.muaFaults(); save(faults, '-struct', 's');
    p = Batch.completeParams('mua', struct('channels', [4 5]));
    R = Batch.run('mua', {clean}, p, fullfile(d, 'out'), 'Name', 'clean');
    T = R.summary;
    tests.verifyTrue(ismember('Checks', T.Properties.VariableNames));
    tests.verifyEqual(T.Status', {'ok', 'ok'}, 'the checks do not change the status');
    for k = 1:height(T)
        tests.verifyNotEmpty(T.Checks{k});
        tests.verifyTrue(isempty(strfind(T.Checks{k}, 'warning')), T.Checks{k}); %#ok<STREMP>
    end
    p.channels = [];
    R = Batch.run('mua', {faults}, p, fullfile(d, 'out'), 'Name', 'faults');
    T = R.summary;
    tests.verifyEqual(R.fileStatus, {'ok'}, 'the checks do not change the status');
    tests.verifyEqual(T.Channel', 3:5);
    tests.verifyTrue(strncmp(T.Checks{1}, '1 warning: Signal-to-noise', 26), T.Checks{1});
    tests.verifyTrue(~isempty(strfind(T.Checks{2}, 'Refractory period')), T.Checks{2}); %#ok<STREMP>
    tests.verifyTrue(strncmp(T.Checks{3}, '1 warning: Amplitude drift', 26), T.Checks{3});
    logText = fileread(R.paths.log);
    tests.verifyTrue(~isempty(strfind(logText, 'checks: ch 3: 1 warning: Signal-to-noise')), logText); %#ok<STREMP>
end
