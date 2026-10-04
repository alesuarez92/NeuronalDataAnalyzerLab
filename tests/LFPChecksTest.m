%% LFPChecksTest.m
% =========================================================================
% UNIT TESTS: QUALITY CHECKS OF THE ERP AND THE CSD (LFP ANALYSIS, BATCH)
% =========================================================================
% core/ERPAnalysis.m checks (ERPAnalysis.checks, one row per topic):
%   * Epochs: stimuli left out (their epoch does not fit), fewer than 10;
%   * Stimulus artefact: an artefact at the onset that lasts into the N1
%     window (Warning) vs one that ends before it or none (OK), the same
%     on every contact or not; a note without a pre-onset part;
%   * Electrode spacing: from the file, typed, the batch settings, the
%     default because the file does not give it (Check), a spacing other
%     than the file's (Check), none (Warning);
%   * CSD sink: at an edge contact (standard: contacts 1-2 and n-1..n,
%     the end rows being copies; other methods: 1 and n) is a Warning,
%     inside the probe OK, no sink a Check; demoCSD 'edge16' (sink at
%     contact 2) gives the Warning;
%   * the clean demo LFP (DemoData.lfpFile) gives no warnings and nothing
%     to check; the faults demo (DemoData.lfpFaults: an artefact on every
%     contact, the sink at the deepest contact, no spacing in the file)
%     fires each check; odd input gives fewer rows, never an error;
%   * Batch 'erp': the checks of each file (Batch.processFile rows, also
%     in Octave) and the Checks column with the log line (Batch.run).
% Base MATLAB only, except the Batch.run test (table): the rest also runs
% in GNU Octave (with a RandStream shim).
% =========================================================================

function tests = LFPChecksTest
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

%% has - The text is in s
function tf = has(s, text)
    tf = ~isempty(strfind(s, text)); %#ok<STREMP>
end

%% erp - Synthetic ERP: nCh channels, -50..200 ms at 1 kHz, deterministic noise (SD ~2 uV),
% an N1 of -100 uV at 15 ms on the middle channels
function [x, t, o] = erp(nCh)
    if nargin < 1, nCh = 4; end
    t = (-50:200) / 1000;
    x = zeros(nCh, numel(t));
    for c = 1:nCh
        noise = 2e-6 * (sin(2 * pi * 137 * t + c) + 0.7 * sin(2 * pi * 291 * t + 2 * c) + 0.5 * sin(2 * pi * 53 * t + 3 * c));
        x(c, :) = noise - 100e-6 * exp(-(c - (nCh + 1) / 2)^2 / 2) * exp(-(t - 0.015).^2 / (2 * 0.005^2));
    end
    o = ERPAnalysis.checkOptions();
    o.nOnsets = 15; o.nEpochs = 15; o.preSec = 0.05; o.postSec = 0.2;
end

%% artefact - amp (V) * exp(-t / tau) from the onset on
function a = artefact(t, amp, tauS)
    a = zeros(size(t));
    on = t >= 0;
    a(on) = amp * exp(-t(on) / tauS);
end

%% laminar - ERP of 8 contacts 100 um apart whose depth profile peaks at contact k
function [x, t] = laminar(k)
    t = (-50:200) / 1000;
    depth = (0:7) * 100;
    profile = exp(-(depth - (k - 1) * 100).^2 / (2 * 150^2));
    x = profile(:) * (-100e-6 * exp(-(t - 0.015).^2 / (2 * 0.005^2)));
end

function testEpochs(tests)
    o = ERPAnalysis.checkOptions();
    o.nOnsets = 15; o.nEpochs = 15; o.preSec = 0.1; o.postSec = 0.3;
    expect(tests, ERPAnalysis.checks([], [], o), 'Epochs', 'ok', '15 of 15 stimuli averaged');
    o.nEpochs = 13;
    expect(tests, ERPAnalysis.checks([], [], o), 'Epochs', 'check', ...
        '2 of 15 stimuli were left out because their epoch (0.1 s before to 0.3 s after the onset) does not fit');
    o.nOnsets = 8; o.nEpochs = 6;
    Q = ERPAnalysis.checks([], [], o);
    expect(tests, Q, 'Epochs', 'check', 'only 6 epoch(s) averaged');
    tests.verifyEqual(nnz(strcmp({Q.topic}, 'Epochs')), 1, 'one row for both findings');
    tests.verifyTrue(has(row(Q, 'Epochs').why, 'fewer than 10 epochs'));
    o.nOnsets = 9; o.nEpochs = 9;
    expect(tests, ERPAnalysis.checks([], [], o), 'Epochs', 'check', 'Only 9 epoch(s)');
    o.nOnsets = 10; o.nEpochs = 10;
    expect(tests, ERPAnalysis.checks([], [], o), 'Epochs', 'ok', '10 of 10');
end

function testStimulusArtefact(tests)
    [x, t, o] = erp(4);
    expect(tests, ERPAnalysis.checks(x, t, o), 'Stimulus artefact', 'ok', 'No stimulus artefact');
    % +600 uV decaying with tau 3 ms on every contact: still large at 5 ms -> into the N1 window
    a = artefact(t, 600e-6, 0.003);
    Q = ERPAnalysis.checks(x + repmat(a, 4, 1), t, o);
    expect(tests, Q, 'Stimulus artefact', 'warning', 'into the N1 window (from 5 ms)');
    r = row(Q, 'Stimulus artefact');
    tests.verifyTrue(has(r.found, 'the same on all 4 channels'), r.found);
    tests.verifyTrue(has(r.found, 'up to +60'), r.found);
    tests.verifyTrue(has(r.why, 'largely cancels in the CSD'), r.why);
    tests.verifyTrue(has(r.action, 'Measure the N1 after the artefact'), r.action);
    tEnd = sscanf(r.found(strfind(r.found, 'lasts until') + 12:end), '%f');
    tests.verifyGreaterThan(tEnd, 6, 'ends near 3 ln(20) = 9 ms');
    tests.verifyLessThan(tEnd, 11);
    % The same artefact with the N1 window from 12 ms: it ends before -> OK
    o2 = o; o2.n1WindowMs = [12 50];
    expect(tests, ERPAnalysis.checks(x + repmat(a, 4, 1), t, o2), 'Stimulus artefact', 'ok', 'before the N1 window (from 12 ms)');
    % A short artefact (tau 0.5 ms) ends before 5 ms -> OK, says when it ends
    Q = ERPAnalysis.checks(x + repmat(artefact(t, 600e-6, 0.0005), 4, 1), t, o);
    expect(tests, Q, 'Stimulus artefact', 'ok', 'ends at');
    tests.verifyTrue(has(row(Q, 'Stimulus artefact').found, 'the same on all 4 channels'));
    % On one channel only: named, and it enters the CSD; a negative artefact too
    y = x; y(2, :) = y(2, :) + artefact(t, -500e-6, 0.004);
    o.channels = [11 12 13 14];
    Q = ERPAnalysis.checks(y, t, o);
    expect(tests, Q, 'Stimulus artefact', 'warning', 'on channel 12');
    tests.verifyTrue(has(row(Q, 'Stimulus artefact').found, 'up to -50'), row(Q, 'Stimulus artefact').found);
    tests.verifyTrue(has(row(Q, 'Stimulus artefact').why, 'also enters the CSD'));
    % Different sizes on every contact: not 'the same'
    y = x + [1; 0.5; 0.3; 1] * artefact(t, 600e-6, 0.003);
    expect(tests, ERPAnalysis.checks(y, t, o), 'Stimulus artefact', 'warning', 'on all 4 channels but of different sizes');
    % No time before the onset: a note, not a guess
    keep = t >= 0;
    expect(tests, ERPAnalysis.checks(x(:, keep), t(keep), o), 'Stimulus artefact', 'note', 'Not checked');
end

function testElectrodeSpacing(tests)
    [x, t] = laminar(4);
    o = ERPAnalysis.checkOptions();
    o.computeCSD = true;
    % Batch: no spacing in the settings or the file -> no CSD, a Warning
    Q = ERPAnalysis.checks(x, t, o);
    expect(tests, Q, 'Electrode spacing', 'warning', 'No electrode spacing: the CSD was not computed.');
    tests.verifyEmpty(row(Q, 'CSD sink'), 'no CSD, no sink row');
    o.csd = ERPAnalysis.csd(x, 100);
    o.spacingUm = 100;
    o.spacingSource = 'default';
    Q = ERPAnalysis.checks(x, t, o);
    expect(tests, Q, 'Electrode spacing', 'check', 'The file does not give the electrode spacing; the CSD used the default 100');
    tests.verifyTrue(has(row(Q, 'Electrode spacing').action, 'datasheet'));
    o.spacingSource = 'file'; o.spacingFile = 100;
    expect(tests, ERPAnalysis.checks(x, t, o), 'Electrode spacing', 'ok', 'from the file (lfp_spacing_um)');
    o.spacingSource = 'typed'; o.spacingUm = 50;
    o.csd = ERPAnalysis.csd(x, 50);
    expect(tests, ERPAnalysis.checks(x, t, o), 'Electrode spacing', 'check', 'but the file gives an electrode spacing of 100');
    o.spacingFile = NaN;
    expect(tests, ERPAnalysis.checks(x, t, o), 'Electrode spacing', 'ok', '50 ');
    expect(tests, ERPAnalysis.checks(x, t, o), 'Electrode spacing', 'ok', 'typed');
    o.spacingSource = 'setting'; o.spacingUm = 100; o.spacingFile = 100;
    o.csd = ERPAnalysis.csd(x, 100);
    expect(tests, ERPAnalysis.checks(x, t, o), 'Electrode spacing', 'ok', 'from the batch settings (the file gives the same)');
    % Without a CSD (none computed or attempted) the spacing is not checked
    o.computeCSD = false; o.csd = [];
    tests.verifyEmpty(row(ERPAnalysis.checks(x, t, o), 'Electrode spacing'));
end

function testCSDSink(tests)
    o = ERPAnalysis.checkOptions();
    o.computeCSD = true; o.spacingUm = 100; o.spacingSource = 'typed';
    % Inside the probe: OK for the standard method and for the spline iCSD
    [x, t] = laminar(4);
    o.csd = ERPAnalysis.csd(x, 100);
    expect(tests, ERPAnalysis.checks(x, t, o), 'CSD sink', 'ok', 'contact 4 of 8 (channel 4), inside the probe');
    o.csd = CSDMethods.estimate(x, (0:7) * 100, 'spline');
    o.csdMethod = 'spline';
    expect(tests, ERPAnalysis.checks(x, t, o), 'CSD sink', 'ok', 'contact 4 of 8');
    % Sink at contact 2, standard: rows 1 and 2 tie (row 1 is a copy); contact 2 is reported, at the edge
    [x, t] = laminar(2);
    c = ERPAnalysis.csd(x, 100);
    tests.verifyEqual(c(1, :), c(2, :));
    [~, k] = min(min(c, [], 2));
    tests.verifyEqual(k, 1, 'min finds the copied row first');
    o.csd = c; o.csdMethod = 'standard'; o.csdOrder = 8:-1:1;
    Q = ERPAnalysis.checks(x, t, o);
    expect(tests, Q, 'CSD sink', 'warning', 'contact 2 of 8 (channel 7), at the edge of the probe');
    tests.verifyTrue(has(row(Q, 'CSD sink').found, 'copies contacts 2 and 7'));
    tests.verifyTrue(has(row(Q, 'CSD sink').why, 'beyond the end of the probe'));
    tests.verifyTrue(has(row(Q, 'CSD sink').action, 'middle of the shank'));
    % Contact 7: an edge for the standard CSD, inside the probe for the spline iCSD
    [x, t] = laminar(7);
    o.csdOrder = [];
    o.csd = ERPAnalysis.csd(x, 100);
    expect(tests, ERPAnalysis.checks(x, t, o), 'CSD sink', 'warning', 'contact 7 of 8');
    o.csd = CSDMethods.estimate(x, (0:7) * 100, 'spline'); o.csdMethod = 'spline';
    expect(tests, ERPAnalysis.checks(x, t, o), 'CSD sink', 'ok', 'contact 7 of 8');
    % Contact 1 with the spline iCSD: the edge
    [x, t] = laminar(1);
    o.csd = CSDMethods.estimate(x, (0:7) * 100, 'spline');
    expect(tests, ERPAnalysis.checks(x, t, o), 'CSD sink', 'warning', 'contact 1 of 8');
    % demoCSD 'edge16': the sink at contact 2 of 16
    s = demoCSD('edge16');
    o.csdMethod = 'standard'; o.csd = ERPAnalysis.csd(s.potentials, s.spacingUm);
    expect(tests, ERPAnalysis.checks(s.potentials, s.t, o), 'CSD sink', 'warning', 'contact 2 of 16');
    % No negative CSD in the N1 window: a Check
    o.csd = abs(ERPAnalysis.csd(x, 100)) + 1;
    expect(tests, ERPAnalysis.checks(x, t, o), 'CSD sink', 'check', 'no sink');
end

function testOddInput(tests)
    % Never an error: fewer rows instead
    Q = ERPAnalysis.checks([], []);
    tests.verifyEmpty(Q);
    Q = ERPAnalysis.checks('text', 1:3, struct('csd', 'x', 'n1WindowMs', 'y', 'channels', {{1}}, 'spacingUm', [1 2]));
    tests.verifyTrue(isstruct(Q));
    [x, t, o] = erp(3);
    o.csd = ones(3, 5);                             % does not match t: no sink row
    o.computeCSD = true; o.spacingUm = 100;
    Q = ERPAnalysis.checks(x, t, o);
    tests.verifyEmpty(row(Q, 'CSD sink'));
    expect(tests, Q, 'Electrode spacing', 'ok');
    x(:, t < 0) = NaN;                              % no usable baseline: no artefact row
    tests.verifyEmpty(row(ERPAnalysis.checks(x, t, o), 'Stimulus artefact'));
    tests.verifyNotEmpty(row(ERPAnalysis.checks(x, t, o), 'Epochs'));
end

function testCleanDemo(tests)
    s = DemoData.lfpFile();
    tests.verifyEqual(s.lfp_spacing_um, 100);
    on = ERPAnalysis.detectOnsets(s.stim_data, s.stim_fs, 0.5, 0.5);
    [x, ~, t, nValid] = ERPAnalysis.average(s.lfp_data, s.lfp_fs, on, 0.05, 0.2);
    o = ERPAnalysis.checkOptions();
    o.nOnsets = numel(on); o.nEpochs = nValid; o.preSec = 0.05; o.postSec = 0.2;
    o.computeCSD = true; o.spacingUm = 100; o.spacingFile = s.lfp_spacing_um; o.spacingSource = 'file';
    for m = {'standard', 'spline'}
        if strcmp(m{1}, 'standard')
            o.csd = ERPAnalysis.csd(x, 100);
        else
            o.csd = CSDMethods.estimate(x, (0:7) * 100, 'spline');
        end
        o.csdMethod = m{1};
        Q = ERPAnalysis.checks(x, t, o);
        txt = strjoin(QualityChecks.lines(Q), newline);
        tests.verifyEqual(QualityChecks.count(Q, 'warning'), 0, txt);
        tests.verifyEqual(QualityChecks.count(Q, 'check'), 0, txt);
        expect(tests, Q, 'Epochs', 'ok', '15 of 15 stimuli averaged');
        expect(tests, Q, 'Stimulus artefact', 'ok', 'No stimulus artefact');
        expect(tests, Q, 'Electrode spacing', 'ok', 'from the file');
        expect(tests, Q, 'CSD sink', 'ok', 'contact 4 of 8 (channel 4), inside the probe');
        tests.verifyEqual(QualityChecks.brief(Q), 'OK');
    end
    % The longer window of Batch's defaults (0.1 s / 0.3 s): still no artefact
    [x, ~, t] = ERPAnalysis.average(s.lfp_data, s.lfp_fs, on, 0.1, 0.3);
    expect(tests, ERPAnalysis.checks(x, t, o), 'Stimulus artefact', 'ok', 'No stimulus artefact');
end

function testFaultsDemo(tests)
    s = DemoData.lfpFaults();
    c = DemoData.lfpFile();
    tests.verifyFalse(isfield(s, 'lfp_spacing_um'), 'no spacing in the faults file');
    tests.verifyEqual(s.truth.artefactUV, 800);
    tests.verifyEqual(s.truth.sinkChannel, 8);
    tests.verifyTrue(s.truth.sinkAtEdge);
    tests.verifyFalse(s.truth.spacingInFile);
    early = s.t_lfp < 0.99;                          % before the first stimulus: the same noise
    tests.verifyEqual(s.lfp_data(:, early), c.lfp_data(:, early));
    on = ERPAnalysis.detectOnsets(s.stim_data, s.stim_fs, 0.5, 0.5);
    [x, ~, t, nValid] = ERPAnalysis.average(s.lfp_data, s.lfp_fs, on, 0.05, 0.2);
    o = ERPAnalysis.checkOptions();
    o.nOnsets = numel(on); o.nEpochs = nValid; o.preSec = 0.05; o.postSec = 0.2;
    o.computeCSD = true; o.spacingUm = 100; o.spacingSource = 'default';
    o.csd = ERPAnalysis.csd(x, 100);
    Q = ERPAnalysis.checks(x, t, o);
    expect(tests, Q, 'Epochs', 'ok', '15 of 15');
    expect(tests, Q, 'Stimulus artefact', 'warning', 'the same on all 8 channels');
    r = row(Q, 'Stimulus artefact');
    tEnd = sscanf(r.found(strfind(r.found, 'lasts until') + 12:end), '%f');
    tests.verifyGreaterThan(tEnd, 7.5, 'well into the N1 window (from 5 ms)');
    expect(tests, Q, 'Electrode spacing', 'check', 'the default 100');
    expect(tests, Q, 'CSD sink', 'warning', 'contact 7 of 8 (channel 7), at the edge of the probe');
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 2);
    tests.verifyTrue(strncmp(QualityChecks.brief(Q), '2 warnings: Stimulus artefact', 29), QualityChecks.brief(Q));
    % The spline iCSD puts the sink on the deepest contact itself
    o.csd = CSDMethods.estimate(x, (0:7) * 100, 'spline'); o.csdMethod = 'spline';
    expect(tests, ERPAnalysis.checks(x, t, o), 'CSD sink', 'warning', 'contact 8 of 8 (channel 8)');
end

function testBatchRows(tests)
    d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's'));
    clean = fullfile(d, 'clean.mat'); faults = fullfile(d, 'faults.mat');
    s = DemoData.lfpFile(); save(clean, '-struct', 's');
    s = DemoData.lfpFaults(); save(faults, '-struct', 's');
    p = Batch.completeParams('erp', struct('preTime', 0.05, 'postTime', 0.2));
    [rows, info] = Batch.processFile('erp', clean, p);
    tests.verifyEqual(unique({rows.Checks}), {'OK'});
    tests.verifyTrue(has(info, 'checks: OK'), info);
    [rows, info] = Batch.processFile('erp', faults, p);
    tests.verifyTrue(all(strcmp({rows.Status}, 'ok')), 'the checks do not change the status');
    tests.verifyTrue(strncmp(rows(1).Checks, '2 warnings: Stimulus artefact', 29), rows(1).Checks);
    tests.verifyTrue(has(info, 'checks: 2 warnings'), info);
    % Spacing 0 = the file's lfp_spacing_um: the clean file has it (same sink)
    p.spacingUm = 0;
    rows = Batch.processFile('erp', clean, p);
    tests.verifyEqual(unique([rows.SinkChannel]), 4);
    tests.verifyEqual(unique({rows.Checks}), {'OK'});
    % ... the faults file has none: no CSD, the ERP rows are still there, a Warning says why
    rows = Batch.processFile('erp', faults, p);
    tests.verifyNumElements(rows, 8);
    tests.verifyTrue(all(isnan([rows.SinkChannel])));
    tests.verifyTrue(all(isfinite([rows.N1Latency_ms])));
    tests.verifyTrue(has(rows(1).Checks, '2 warnings'), rows(1).Checks);
    % A spacing other than the file's: to check
    p.spacingUm = 50;
    rows = Batch.processFile('erp', clean, p);
    tests.verifyTrue(strncmp(rows(1).Checks, '1 to check: Electrode spacing', 29), rows(1).Checks);
end

function testBatchChecksColumn(tests)
    tests.assumeTrue(exist('table', 'file') > 0 && exist('writetable', 'file') > 0, 'Needs table / writetable');
    d = fullfile(tempdir, sprintf('LFPChecksTest_%d', round(1e6 * rand)));
    mkdir(d); c = onCleanup(@() rmdir(d, 's'));
    clean = fullfile(d, 'clean.mat'); faults = fullfile(d, 'faults.mat');
    s = DemoData.lfpFile(); save(clean, '-struct', 's');
    s = DemoData.lfpFaults(); save(faults, '-struct', 's');
    p = struct('preTime', 0.05, 'postTime', 0.2, 'spacingUm', 0);
    R = Batch.run('erp', {clean, faults}, p, fullfile(d, 'out'), 'Name', 'checks');
    T = R.summary;
    tests.verifyEqual(R.fileStatus, {'ok', 'ok'}, 'the checks do not change the status');
    tests.verifyTrue(ismember('Checks', T.Properties.VariableNames));
    tests.verifyEqual(unique(T.Checks(strcmp(T.File, 'clean.mat'))), {'OK'});
    f = T.Checks(strcmp(T.File, 'faults.mat'));
    tests.verifyTrue(all(strncmp(f, '2 warnings: Stimulus artefact', 29)), f{1});
    logText = fileread(R.paths.log);
    tests.verifyTrue(has(logText, 'checks: 2 warnings: Stimulus artefact'), logText);
    tests.verifyTrue(has(logText, 'checks: OK'), logText);
end
