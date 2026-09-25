%% VirtualLabWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: A STUDENT DOES THE VIRTUAL LDF EXPERIMENT END TO END
% =========================================================================
% Drives VirtualLabApp and the LDF windows through their public methods
% (no dialogs): plan (live preview), record the demo student, open the
% recording in Extract LDF, crop and save, Process LDF (trials -5..+20 s,
% session), Average LDF (relative to baseline, results under the button,
% session), report those numbers in the Virtual Lab, attach the sessions,
% check (every Plan / Processing / Your results item OK), show the
% solution, save the submission and grade the folder. Saves a frame after
% every step to test-artifacts/screens/walkthrough/VirtualLabApp_<NN>_<step>.png.
% Skipped when no display is available.
% =========================================================================

function tests = VirtualLabWalkthroughTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    tests.TestData.outDir = fullfile(root, 'test-artifacts', 'screens', 'walkthrough');
    if ~exist(tests.TestData.outDir, 'dir'), mkdir(tests.TestData.outDir); end
    tests.TestData.work = tempname;
    mkdir(tests.TestData.work);
end

function teardownOnce(tests)
    if exist(tests.TestData.work, 'dir') == 7, rmdir(tests.TestData.work, 's'); end
end

function setup(tests)
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end

%% shot - Save a frame of a window, optionally after selecting a tab
function shot(tests, fig, name, tabTitle)
    if nargin >= 4 && ~isempty(tabTitle)
        tab = findobj(fig, 'Type', 'uitab', 'Title', tabTitle);
        tests.verifyNotEmpty(tab, sprintf('%s: no tab "%s"', name, tabTitle));
        if ~isempty(tab), tab(1).Parent.SelectedTab = tab(1); end
    end
    drawnow; pause(0.5);
    try
        exportapp(fig, fullfile(tests.TestData.outDir, [name '.png']));
    catch ME
        warning('VirtualLabWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

function testStudentDoesTheExperiment(tests)
    work = tests.TestData.work;
    lab = VirtualLabApp(); c1 = onCleanup(@() delete(lab.UIFig));
    shot(tests, lab.UIFig, 'VirtualLabApp_01_learn', 'Learn');
    verifyEqual(tests, char(lab.RecordBtn.Enable), 'off');   % no name yet

    % --- Plan: a poor plan first (live preview), then the demo plan ---
    lab.setStudent('Demo student');
    lab.setDesign(struct('fs', 1000, 'nStim', 40, 'isiS', 120));
    verifyTrue(tests, contains(lab.PlanInfo.Text, 'samples'));
    verifyEqual(tests, char(lab.RecordBtn.Enable), 'off');   % too large
    shot(tests, lab.UIFig, 'VirtualLabApp_02_plan_too_large', 'Plan');
    lab.setDesign(struct('probe', VirtualLab.Probes{1}, 'stimS', 5, 'nStim', 15, ...
        'isiS', 25, 'baselineS', 30, 'fs', 40));
    verifyEqual(tests, char(lab.RecordBtn.Enable), 'on');
    verifyTrue(tests, contains(lab.PlanInfo.Text, '7 min'));
    shot(tests, lab.UIFig, 'VirtualLabApp_03_plan', 'Plan');

    % --- Record ---
    rec = fullfile(work, 'virtual_ldf_demo.mat');
    verifyTrue(tests, logical(lab.recordTo(rec)));
    verifyEqual(tests, exist(rec, 'file'), 2);
    shot(tests, lab.UIFig, 'VirtualLabApp_04_recorded', 'Recording');

    % --- Analyse in the normal windows ---
    ex = lab.openInExtract(); c2 = onCleanup(@() delete(ex.UIFig));
    verifyNotEmpty(tests, ex.AppData.RawLDF);
    ex.setRange(0, numel(ex.AppData.RawLDF) / ex.AppData.SamplingRate);
    ex.processData();
    cropped = fullfile(work, 'cropped.mat');
    verifyTrue(tests, logical(ex.saveCroppedTo(cropped)));
    shot(tests, ex.UIFig, 'VirtualLabApp_05_extract_ldf');

    pr = ProcessingLDFApp(); c3 = onCleanup(@() delete(pr.UIFig));
    verifyTrue(tests, logical(pr.openFile(cropped)));
    pr.applyProcessingParams(struct('downsample', 1, 'filterType', 1, 'designType', 1, ...
        'filterOrder', 4, 'cutoffLow', NaN, 'cutoffHigh', NaN));
    pr.setSegmentParams(2.5, 5, 20, 10);
    pr.segmentByOnsetsConfig();
    verifyEqual(tests, size(pr.SegmentedLDF, 1), 15);
    trials = fullfile(work, 'trials.mat');
    pr.saveData(trials);
    s1 = fullfile(work, 'process.nasession.mat');
    verifyTrue(tests, logical(pr.saveSessionTo(s1, 'virtual lab')));
    shot(tests, pr.UIFig, 'VirtualLabApp_06_process_ldf', 'Trials');

    av = LDFGrandAverageApp(); c4 = onCleanup(@() delete(av.UIFig));
    verifyEqual(tests, av.openFiles({trials}), 1);
    av.setRelative(true);
    av.plotGrandAverage();
    m = av.responseMeasures();
    verifyEqual(tests, m.nTrials, 15);
    verifyTrue(tests, contains(av.ResultLabel.Text, 'Peak increase'));
    s2 = fullfile(work, 'average.nasession.mat');
    verifyTrue(tests, logical(av.saveSessionTo(s2, 'virtual lab')));
    shot(tests, av.UIFig, 'VirtualLabApp_07_average_ldf');

    % --- Report, check, solution, submission ---
    lab.setAnswers(struct('baselinePU', m.baseline, 'peakChangePU', m.peakChange, ...
        'peakPercent', m.peakPercent, 'peakLatencyS', m.peakLatency, 'nTrials', m.nTrials));
    verifyEqual(tests, lab.attachSessions({s1, s2}), 2);
    g = lab.checkResults();
    verifyNotEmpty(tests, g);
    scored = ~strcmp({g.items.status}, 'info');
    verifyTrue(tests, all(strcmp({g.items(scored).status}, 'pass')), ...
        strjoin(arrayfun(@(it) sprintf('%s=%s (%s vs %s)', it.item, it.status, it.yours, it.reference), ...
        g.items(scored & ~strcmp({g.items.status}, 'pass')), 'UniformOutput', false), '; '));
    verifyEqual(tests, g.score, 100);
    verifyTrue(tests, any(contains(lab.FeedbackTable.Data(:, 5), 'hidden')));
    shot(tests, lab.UIFig, 'VirtualLabApp_08_feedback', 'Feedback');
    % A wrong answer is caught
    lab.setAnswers(struct('peakLatencyS', 3.9));
    g = lab.checkResults();
    verifyEqual(tests, g.items(strcmp({g.items.item}, 'Time to peak (s)')).status, 'fail');
    shot(tests, lab.UIFig, 'VirtualLabApp_09_feedback_wrong_latency', 'Feedback');
    lab.showSolution();
    verifyTrue(tests, lab.SolutionShown);
    verifyFalse(tests, any(contains(lab.FeedbackTable.Data(:, 5), 'hidden')));
    shot(tests, lab.UIFig, 'VirtualLabApp_10_solution', 'Feedback');

    classDir = fullfile(work, 'class'); mkdir(classDir);
    out = lab.saveSubmissionTo(fullfile(classDir, 'demo_student'));
    verifyEqual(tests, exist(out, 'file'), 2);
    sub = VirtualLab.loadSubmission(out);
    verifyEqual(tests, sub.attempts, 2);
    verifyTrue(tests, sub.solutionShown);
    verifyNumElements(tests, sub.sessions, 2);
    T = lab.gradeFolderTo(classDir, fullfile(classDir, 'grades.csv'));
    verifyEqual(tests, height(T), 1);
    verifyEqual(tests, T.Student{1}, 'Demo student');
    verifyLessThan(tests, T.Score(1), 100);   % the latency in the submission is wrong
    shot(tests, lab.UIFig, 'VirtualLabApp_11_graded');
end

function testDemoFromHelp(tests)
    lab = VirtualLabApp(); c = onCleanup(@() delete(lab.UIFig));
    verifyTrue(tests, logical(lab.loadDemo()));
    verifyEqual(tests, lab.StudentInput.Value, 'Demo student');
    verifyEqual(tests, exist(lab.RecordingPath, 'file'), 2);
    verifyEqual(tests, HelpApp.demoWindow('Virtual lab'), 'VirtualLabApp');
end
