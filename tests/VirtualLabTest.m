%% VirtualLabTest.m
% =========================================================================
% VIRTUAL LAB: SIMULATOR, REFERENCE ANALYSIS AND FEEDBACK (NO WINDOWS)
% =========================================================================
% core/VirtualLab.m: the same student and plan always give the same
% recording, other students get other data, the recording holds no answer
% and loads like a LabChart export, the true answer of the demo student
% is the one Help states, a careful analysis recovers it within the
% noise, and the feedback marks good and bad plans, processing settings
% and answers as documented. Submissions round-trip and a folder is
% graded into one table (with a broken file reported, not fatal).
% =========================================================================

function tests = VirtualLabTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    tests.TestData.work = tempname;
    mkdir(tests.TestData.work);
end

function teardownOnce(tests)
    if exist(tests.TestData.work, 'dir') == 7, rmdir(tests.TestData.work, 's'); end
end

%% goodDesign - The plan of Help's demo (every Plan item OK)
function d = goodDesign()
    d = struct('probe', VirtualLab.Probes{1}, 'stimS', 5, 'nStim', 15, ...
        'isiS', 25, 'baselineS', 30, 'fs', 40);
end

%% statusOf - Status of the item named name
function st = statusOf(g, name)
    k = find(strcmp({g.items.item}, name), 1);
    if isempty(k), st = ''; else, st = g.items(k).status; end
end

function testSameStudentSameRecording(tests)
    d = goodDesign();
    a = VirtualLab.record('Ana', d);
    b = VirtualLab.record('Ana', d);
    verifyEqual(tests, a.data, b.data);
    % Case and surrounding spaces do not change the student
    c = VirtualLab.record(' ana ', d);
    verifyEqual(tests, a.data, c.data);
    % Another student: another animal
    o = VirtualLab.record('Bob', d);
    verifyNotEqual(tests, VirtualLab.truth('Ana', d).peakChangePU, VirtualLab.truth('Bob', d).peakChangePU);
    verifyNotEqual(tests, a.data, o.data);
end

function testRecordingLoadsAsExportWithoutAnswers(tests)
    d = goodDesign();
    rec = VirtualLab.record('Ana', d);
    info = VirtualLab.describeDesign(d);
    verifyEqual(tests, info.durationS, 30 + 14 * 25 + 40);
    verifyEqual(tests, info.nSamples, round(info.durationS * 40));
    verifyTrue(tests, Validation.isValidLDFStruct(rec));
    A = struct('RawStim', [], 'RawLDF', [], 'SamplingRate', 1000, 'FilePath', '', 'Metadata', struct());
    A = DataLoader.load(A, 'FromStruct', rec);
    verifyEqual(tests, numel(A.RawLDF), info.nSamples);
    verifyEqual(tests, numel(A.RawStim), info.nSamples);
    verifyEqual(tests, A.SamplingRate, 40);
    % 15 stimulus pulses of 5 V
    onsets = find(diff([0, A.RawStim > 2.5]) == 1);
    verifyNumElements(tests, onsets, 15);
    verifyEqual(tests, (onsets(1) - 1) / 40, 30, 'AbsTol', 1 / 40);
    % No answer inside the file
    verifyFalse(tests, isfield(rec, 'truth'));
    verifyEqual(tests, sort(fieldnames(rec.virtualLab))', ...
        sort({'scenario', 'studentId', 'design', 'toolboxVersion', 'created'}));
    p = VirtualLab.recordTo(fullfile(tests.TestData.work, 'rec'), 'Ana', d);
    verifyEqual(tests, exist(p, 'file'), 2);
end

function testDemoStudentTruthMatchesHelp(tests)
    tr = VirtualLab.truth('Demo student', goodDesign());
    verifyEqual(tests, tr.baselinePU, 114.7, 'AbsTol', 0.05);
    verifyEqual(tests, tr.peakChangePU, 38.6, 'AbsTol', 0.05);
    verifyEqual(tests, tr.peakPercent, 33.6, 'AbsTol', 0.05);
    verifyEqual(tests, tr.peakLatencyS, 5.8, 'AbsTol', 0.03);
    verifyEqual(tests, tr.returnS, 10.7, 'AbsTol', 0.05);
end

function testResponseScalesWithProbeAndStimulus(tests)
    d = goodDesign();
    c = VirtualLab.truth('Ana', d);
    d.probe = VirtualLab.Probes{2}; e = VirtualLab.truth('Ana', d);
    d.probe = VirtualLab.Probes{3}; f = VirtualLab.truth('Ana', d);
    verifyEqual(tests, e.peakChangePU / c.peakChangePU, 0.45, 'AbsTol', 1e-12);
    verifyEqual(tests, f.peakChangePU / c.peakChangePU, 0.08, 'AbsTol', 1e-12);
    d = goodDesign(); d.stimS = 2; s2 = VirtualLab.truth('Ana', d);
    d.stimS = 10; s10 = VirtualLab.truth('Ana', d);
    verifyLessThan(tests, s2.peakChangePU, c.peakChangePU);
    verifyGreaterThan(tests, s10.peakChangePU, c.peakChangePU);
    verifyLessThan(tests, s2.peakLatencyS, c.peakLatencyS);
    verifyGreaterThan(tests, s10.peakLatencyS, c.peakLatencyS);
end

function testReferenceAnalysisRecoversTruth(tests)
    for id = {'Demo student', 'Ana', 'Bob'}
        d = goodDesign();
        tr = VirtualLab.truth(id{1}, d);
        ref = VirtualLab.referenceAnalysis(id{1}, d);
        verifyEqual(tests, ref.nTrials, 15);
        verifyEqual(tests, ref.peakChangePU, tr.peakChangePU, 'AbsTol', 4 * ref.peakSE + 1, id{1});
        verifyEqual(tests, ref.peakLatencyS, tr.peakLatencyS, 'AbsTol', 0.6, id{1});
        verifyEqual(tests, ref.baselinePU, tr.baselinePU, 'AbsTol', 7, id{1});
        verifyGreaterThan(tests, ref.peakSE, 0);
    end
end

function testOverlappingResponsesShrinkThePeak(tests)
    % 10 s between 5 s stimuli: Demo student's flow is back only ~10.7 s
    % after onset, so every baseline contains the previous response
    d = goodDesign(); d.isiS = 10; d.nStim = 30;
    tr = VirtualLab.truth('Demo student', d);
    ref = VirtualLab.referenceAnalysis('Demo student', d);
    verifyLessThan(tests, ref.peakChangePU, 0.9 * tr.peakChangePU);
    g = VirtualLab.grade('Demo student', d, VirtualLab.emptyAnswers());
    verifyEqual(tests, statusOf(g, 'Time between stimuli'), 'fail');
end

function testGoodPlanAndCorrectAnswersPass(tests)
    d = goodDesign();
    ref = VirtualLab.referenceAnalysis('Ana', d);
    a = struct('baselinePU', ref.baselinePU, 'peakChangePU', ref.peakChangePU, ...
        'peakPercent', ref.peakPercent, 'peakLatencyS', ref.peakLatencyS, 'nTrials', ref.nTrials);
    good = struct('app', {'ProcessingLDFApp', 'LDFGrandAverageApp'}, 'settings', { ...
        struct('preS', 5, 'postS', 20, 'processing', struct('filterType', 1, 'cutoffLow', NaN, 'cutoffHigh', NaN)), ...
        struct('relativeToBaseline', true)});
    g = VirtualLab.grade('Ana', d, a, num2cell(good));
    st = {g.items.status};
    verifyTrue(tests, all(ismember(st, {'pass', 'info'})), strjoin({g.items(~ismember(st, {'pass', 'info'})).item}, ', '));
    verifyEqual(tests, g.score, 100);
    verifyEqual(tests, statusOf(g, 'Noise-free answer'), 'info');
    % Small reading differences are still OK
    a.peakChangePU = a.peakChangePU * 1.1; a.peakLatencyS = a.peakLatencyS + 0.5;
    g = VirtualLab.grade('Ana', d, a, num2cell(good));
    verifyEqual(tests, statusOf(g, 'Peak increase (PU)'), 'pass');
    verifyEqual(tests, statusOf(g, 'Time to peak (s)'), 'pass');
end

function testPoorPlanIsExplained(tests)
    % 5 stimuli every 15 s at 40 Hz; Demo student's flow is back ~10.7 s after onset
    d = VirtualLab.defaultDesign();
    g = VirtualLab.grade('Demo student', d, VirtualLab.emptyAnswers());
    verifyEqual(tests, statusOf(g, 'Number of stimuli'), 'fail');
    verifyEqual(tests, statusOf(g, 'Time between stimuli'), 'check');
    d = goodDesign(); d.fs = 10; d.probe = VirtualLab.Probes{3}; d.nStim = 8; d.baselineS = 15;
    g = VirtualLab.grade('Ana', d, VirtualLab.emptyAnswers());
    verifyEqual(tests, statusOf(g, 'Sampling rate'), 'check');
    verifyTrue(tests, contains(g.items(strcmp({g.items.item}, 'Sampling rate')).feedback, 'aliasing'));
    verifyEqual(tests, statusOf(g, 'Probe position'), 'fail');
    verifyEqual(tests, statusOf(g, 'Number of stimuli'), 'check');
    verifyEqual(tests, statusOf(g, 'Baseline before the first stimulus'), 'check');
    % Missing answers are marked, not guessed
    verifyEqual(tests, statusOf(g, 'Peak increase (PU)'), 'fail');
    verifyEqual(tests, g.items(strcmp({g.items.item}, 'Peak increase (PU)')).yours, 'not given');
    % No sessions attached: processing is not scored
    verifyEqual(tests, statusOf(g, 'Trial cutting (Process LDF session)'), 'info');
end

function testBadProcessingIsExplained(tests)
    d = goodDesign();
    bad = struct('app', {'ProcessingLDFApp', 'LDFGrandAverageApp'}, 'settings', { ...
        struct('preS', 1, 'postS', 4, 'processing', struct('filterType', 3, 'cutoffLow', 0.1, 'cutoffHigh', NaN)), ...
        struct('relativeToBaseline', false)});
    g = VirtualLab.grade('Ana', d, VirtualLab.emptyAnswers(), num2cell(bad));
    verifyEqual(tests, statusOf(g, 'Window after the stimulus'), 'fail');
    verifyEqual(tests, statusOf(g, 'Baseline window before the stimulus'), 'check');
    verifyEqual(tests, statusOf(g, 'Filter'), 'fail');
    verifyEqual(tests, statusOf(g, 'Relative to baseline'), 'check');
    lp = bad(1); lp.settings.postS = 12; lp.settings.preS = 3;
    lp.settings.processing = struct('filterType', 2, 'cutoffLow', NaN, 'cutoffHigh', 0.2);
    g = VirtualLab.grade('Ana', d, VirtualLab.emptyAnswers(), {lp});
    verifyEqual(tests, statusOf(g, 'Filter'), 'check');
    verifyEqual(tests, statusOf(g, 'Window after the stimulus'), 'pass');
end

function testInvalidPlans(tests)
    d = goodDesign(); d.fs = 1000; d.nStim = 40; d.isiS = 120;
    verifyTrue(tests, contains(VirtualLab.validateDesign(d), 'samples'));
    verifyError(tests, @() VirtualLab.record('Ana', d), 'NeuroAnalyzer:VirtualLab:invalidDesign');
    d = goodDesign(); d.isiS = 5;
    verifyNotEmpty(tests, VirtualLab.validateDesign(d));
    d = goodDesign(); d.fs = 33;
    verifyNotEmpty(tests, VirtualLab.validateDesign(d));
    d = goodDesign(); d.probe = 'Somewhere';
    verifyNotEmpty(tests, VirtualLab.validateDesign(d));
    verifyEmpty(tests, VirtualLab.validateDesign(goodDesign()));
end

function testSubmissionsAndFolderGrading(tests)
    folder = fullfile(tests.TestData.work, 'class');
    mkdir(folder);
    d = goodDesign();
    ref = VirtualLab.referenceAnalysis('Ana', d);
    a = struct('baselinePU', ref.baselinePU, 'peakChangePU', ref.peakChangePU, ...
        'peakPercent', ref.peakPercent, 'peakLatencyS', ref.peakLatencyS, 'nTrials', ref.nTrials);
    p1 = VirtualLab.saveSubmission(fullfile(folder, 'ana.mat'), VirtualLab.submission('Ana', d, a, {}, 2, false));
    verifyTrue(tests, endsWith(p1, VirtualLab.Extension));
    s = VirtualLab.loadSubmission(p1);
    verifyEqual(tests, s.studentId, 'Ana');
    verifyEqual(tests, s.attempts, 2);
    VirtualLab.saveSubmission(fullfile(folder, 'bob'), VirtualLab.submission('Bob', VirtualLab.defaultDesign(), ...
        VirtualLab.emptyAnswers(), {}, 1, true));
    fid = fopen(fullfile(folder, ['broken' VirtualLab.Extension]), 'w'); fprintf(fid, 'x'); fclose(fid);
    csv = fullfile(folder, 'grades.csv');
    T = VirtualLab.gradeFolder(folder, csv);
    verifyEqual(tests, height(T), 3);
    verifyEqual(tests, exist(csv, 'file'), 2);
    ana = strcmp(T.Student, 'Ana');
    verifyEqual(tests, T.Score(ana), 100);
    verifyEqual(tests, T.Ref_nTrials(ana), 15);
    bob = strcmp(T.Student, 'Bob');
    verifyLessThan(tests, T.Score(bob), 50);
    verifyTrue(tests, T.SolutionShown(bob));
    broken = contains(T.File, 'broken');
    verifyNotEqual(tests, T.Status{broken}, 'ok');
    verifyTrue(tests, isnan(T.Score(broken)));
    verifyError(tests, @() VirtualLab.loadSubmission(csv), ?MException);
end

function testLearnAndProtocolText(tests)
    txt = VirtualLab.learnText();
    verifyTrue(tests, contains(txt, 'Doppler'));
    verifyTrue(tests, contains(txt, 'perfusion unit'));
    lines = VirtualLab.protocolText('Ana', goodDesign());
    verifyTrue(tests, any(contains(lines, '15 times, every 25 s')));
    verifyError(tests, @() VirtualLab.scenario('mri'), 'NeuroAnalyzer:VirtualLab:unknownScenario');
end
