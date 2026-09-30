%% LSCIWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: LASER SPECKLE WINDOW ON THE DEMO RECORDING
% =========================================================================
% Drives LSCIAnalysisApp through its public methods (no dialogs):
%   demo -> Run (spatial contrast, 1/K^2) -> response map, average
%   response, checks -> contrast and flow displays -> exposure model ->
%   ROIs added / renamed / removed -> regular onsets -> export .csv / .mat
%   -> trials opened by LDF Average -> session save / reopen -> report,
%   and exported perfusion images from a TIFF. Checks the numbers against
%   the demo ground truth (core/demo/demoLSCI.m) and saves a frame after
%   every step to test-artifacts/screens/walkthrough/LSCIAnalysisApp_<NN>_<step>.png.
% Skipped when no display is available.
% =========================================================================

function tests = LSCIWalkthroughTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.outDir = fullfile(root, 'test-artifacts', 'screens', 'walkthrough');
    if ~exist(tests.TestData.outDir, 'dir'), mkdir(tests.TestData.outDir); end
    tests.TestData.tmp = tempname;
    mkdir(tests.TestData.tmp);
end

function teardownOnce(tests)
    try, rmdir(tests.TestData.tmp, 's'); catch, end
end

function setup(tests)
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end

function shot(tests, app, name, tabTitle)
    if nargin >= 4 && ~isempty(tabTitle)
        tab = findobj(app.UIFig, 'Type', 'uitab', 'Title', tabTitle);
        tests.verifyNotEmpty(tab, sprintf('%s: no tab "%s"', name, tabTitle));
        if ~isempty(tab), tab(1).Parent.SelectedTab = tab(1); end
    end
    drawnow; pause(0.5);
    try
        exportapp(app.UIFig, fullfile(tests.TestData.outDir, [name '.png']));
    catch ME
        warning('LSCIWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

function testLaserSpeckleDemo(tests)
    app = LSCIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyEqual(char(app.RunBtn.Enable), 'off', 'nothing to run before loading');
    shot(tests, app, 'LSCIAnalysisApp_01_empty');

    % 1. Demo: settings from the file
    tests.verifyTrue(logical(app.loadDemo()));
    tr = app.DemoTruth;
    tests.verifyEqual(app.InputDropdown.Value, 'raw');
    tests.verifyEqual([app.FpsEdit.Value app.ExposureEdit.Value app.DarkEdit.Value], [10 5 100]);
    tests.verifyEqual(app.FramesEdit.Value, 5);
    tests.verifyEqual(app.OnsetDropdown.Value, 'file');
    tests.verifyEqual({app.ROIs.Name}, {'Activated area', 'Control cortex', 'Vessel'});
    tests.verifyEqual(size(app.ROITable.Data, 1), 3);
    tests.verifyEqual(char(app.RunBtn.Enable), 'on');
    tests.verifyEqual(char(app.ExportBtn.Enable), 'off');
    shot(tests, app, 'LSCIAnalysisApp_02_demo_loaded');

    % 2. Run: +21% in the activated area, nothing elsewhere
    tests.verifyTrue(logical(app.run()));
    R = app.Result;
    tests.verifyEqual(R.onsets, tr.onsets, 'AbsTol', 1e-9);
    w = (0:899) / 10 - 10;
    w = w >= 2 & w <= 6;
    want = 100 * (mean(tr.invK2Ratio(w)) - 1);
    tests.verifyEqual(R.response(1), want, 'AbsTol', 4.5, 'activated area');
    tests.verifyLessThan(abs(R.response(2:3)), 3, 'control cortex and vessel');
    tests.verifyEqual(app.ShowDropdown.Value, 'Response map (%)');
    tests.verifyEqual(app.ResultTabs.SelectedTab, app.AvgTab);
    tests.verifyEqual(char(app.ExportBtn.Enable), 'on');
    tests.verifyEqual(char(app.TrialsBtn.Enable), 'on');
    tests.verifyTrue(contains(app.W.Status.Text, '4 trials'), app.W.Status.Text);
    shot(tests, app, 'LSCIAnalysisApp_03_response_map', 'Average response');
    shot(tests, app, 'LSCIAnalysisApp_04_flow_over_time', 'Flow over time');
    checks = strjoin(app.ChecksArea.Value, ' ');
    tests.verifyTrue(contains(checks, 'OK: 4 trials averaged'), checks);
    tests.verifyTrue(contains(checks, 'OK: no saturated pixels'), checks);
    shot(tests, app, 'LSCIAnalysisApp_05_checks', 'Checks');

    % 3. The other displays
    app.setDisplay('contrast');
    tests.verifyEqual(app.ShowDropdown.Value, 'Speckle contrast K');
    shot(tests, app, 'LSCIAnalysisApp_06_contrast');
    app.setDisplay('Flow index');
    shot(tests, app, 'LSCIAnalysisApp_07_flow_index');

    % 4. Exposure model: a changed setting clears the results; 1/tau_c ~ 4000 /s in the cortex
    app.setParams(struct('FlowModel', 'tauc', 'Beta', 1));
    tests.verifyEmpty(app.Result, 'settings changed: results cleared');
    tests.verifyEqual(char(app.BetaEdit.Enable), 'on');
    tests.verifyTrue(logical(app.run()));
    tests.verifyEqual(mean(app.Result.roiFlow(2, :)), 4000, 'RelTol', 0.06);
    tests.verifyGreaterThan(app.Result.response(1), R.response(1));
    tests.verifyTrue(contains(strjoin(app.ChecksArea.Value, ' '), 'exposure model'));
    app.setParams(struct('FlowModel', 'invK2'));

    % 5. ROIs: add one, rename it, remove it; regular onsets give the same trials
    m = false(64, 80); m(40:50, 45:60) = true;
    k = app.addROI(m, 'Extra');
    tests.verifyEqual(k, 4);
    app.renameROI(4, 'Lower cortex');
    tests.verifyEqual(app.ROIs(4).Name, 'Lower cortex');
    tests.verifyEqual(app.ROITable.Data{4, 2}, 'Lower cortex');
    app.removeROI(4);
    tests.verifyNumElements(app.ROIs, 3);
    app.setStimulus('regular', 10, 20, 4);
    tests.verifyEqual(char(app.FirstOnsetEdit.Enable), 'on');
    tests.verifyTrue(logical(app.run()));
    tests.verifyEqual(app.Result.onsets, [10 30 50 70], 'AbsTol', 1e-9);
    tests.verifyEqual(app.Result.response, R.response, 'AbsTol', 1e-9, 'same onsets, same answer');

    % 6. Export .csv / .mat and the trials for LDF Average
    fcsv = fullfile(tests.TestData.tmp, 'lsci.csv');
    tests.verifyTrue(logical(app.exportResultsTo(fcsv)));
    tbl = readtable(fcsv);
    tests.verifyEqual(width(tbl), 7);                     % time + change and flow index per ROI
    tests.verifyEqual(height(tbl), numel(app.Result.t));
    tests.verifyTrue(any(contains(tbl.Properties.VariableNames, 'FlowChange_pct_Activated')));
    fmat = fullfile(tests.TestData.tmp, 'lsci.mat');
    tests.verifyTrue(logical(app.exportResultsTo(fmat)));
    r = load(fmat);
    tests.verifyEqual(size(r.results.responseMap), [64 80]);
    tests.verifyEqual(r.results.roiNames, {'Activated area', 'Control cortex', 'Vessel'});
    ftr = fullfile(tests.TestData.tmp, 'lsci_trials.mat');
    tests.verifyTrue(logical(app.saveTrialsTo(ftr, 1)));
    q = load(ftr);
    tests.verifyEqual(size(q.segmentedLDF), [4 numel(q.segmentedTime)]);
    tests.verifyEqual(q.Fs, 2, 'AbsTol', 1e-9);
    avg = LDFGrandAverageApp(); ca = onCleanup(@() delete(avg.UIFig));
    tests.verifyEqual(avg.openFiles({ftr}), 4, 'LDF Average opens the 4 saved trials');

    % 7. Session: save, reopen in a new window, same numbers; report
    ps = fullfile(tests.TestData.tmp, ['lsci' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(ps, 'Laser speckle walkthrough')));
    b = LSCIAnalysisApp(); cb = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(ps)), 'session not reopened');
    tests.verifyEqual({b.ROIs.Name}, {'Activated area', 'Control cortex', 'Vessel'});
    tests.verifyEqual(b.OnsetDropdown.Value, 'regular');
    tests.verifyEqual(b.Result.response, app.Result.response, 'AbsTol', 1e-9);
    shot(tests, b, 'LSCIAnalysisApp_08_session_reopened');
    pdf = fullfile(tests.TestData.tmp, 'lsci.pdf');
    tests.verifyTrue(logical(app.makeReport(pdf)));
    tests.verifyEqual(exist(pdf, 'file'), 2);
end

function testPerfusionImagesFromTiff(tests)
    % A commercial system's perfusion export: 16-bit TIFF, no speckle, used as it is
    app = LSCIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    f = fullfile(tests.TestData.tmp, 'perfusion.tif');
    t = (0:199) / 4;                                        % 4 Hz, 50 s
    img = 300 * ones(32, 40);
    for n = 1:numel(t)
        fr = img;
        fr(10:20, 10:20) = 300 * (1 + 0.3 * exp(-((t(n) - 23) / 1.5) ^ 2));   % +30% 3 s after 20 s
        if n == 1
            imwrite(uint16(fr), f, 'Compression', 'none');
        else
            imwrite(uint16(fr), f, 'WriteMode', 'append', 'Compression', 'none');
        end
    end
    tests.verifyTrue(logical(app.openFile(f)));
    tests.verifyEqual(app.InputDropdown.Value, 'flow', 'smooth images without speckle: perfusion');
    tests.verifyEqual(app.FramesEdit.Value, 1, 'perfusion images are not averaged by default');
    tests.verifyEqual(char(app.ContrastDropdown.Enable), 'off', 'no contrast settings for perfusion images');
    app.setInputType('raw');
    tests.verifyEqual(char(app.ContrastDropdown.Enable), 'on');
    app.setInputType('flow');
    app.setParams(struct('Fps', 4, 'Frames', 1));
    app.setStimulus('regular', 20, 20, 1);
    app.setTrialWindow(5, 15, 2.5, 3.5);
    m = false(32, 40); m(12:18, 12:18) = true;
    app.addROI(m, 'Hot spot');
    tests.verifyTrue(logical(app.run()));
    tests.verifyEqual(app.Result.peak, 30, 'AbsTol', 0.5);
    tests.verifyEqual(app.Result.peakTime, 3, 'AbsTol', 0.25);
    tests.verifyEqual(app.Result.units, 'Perfusion (as exported)');
    shot(tests, app, 'LSCIAnalysisApp_09_perfusion_tiff', 'Average response');
end
