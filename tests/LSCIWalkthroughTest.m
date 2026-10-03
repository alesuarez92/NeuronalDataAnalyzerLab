%% LSCIWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: LASER SPECKLE WINDOW ON THE DEMO RECORDING
% =========================================================================
% Drives LSCIAnalysisApp through its public methods (no dialogs):
%   demo -> Run (spatial contrast, 1/K^2) -> response map, average
%   response, checks -> contrast and flow displays -> exposure model ->
%   no dark level (a row to check) ->
%   ROIs added / renamed / removed -> regular onsets -> export .csv / .mat
%   -> trials opened by LDF Average -> session save / reopen -> report,
%   and exported perfusion images from a TIFF; the faults demos (field
%   shift, illumination, exposure, a ROI through the skull; perfusion
%   images clipped at 3000 PU) and their checks. Checks the numbers against
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
    chk = app.ChecksTable.Data;
    tests.verifyTrue(hasCheck(chk, 'OK', 'Trials', '4 trials averaged'), strjoin(chk(:, 3), ' | '));
    tests.verifyTrue(hasCheck(chk, 'OK', 'Saturation', 'No saturated pixels'), strjoin(chk(:, 3), ' | '));
    tests.verifyTrue(hasCheck(chk, 'Note', 'Flow index', '1/K'), strjoin(chk(:, 3), ' | '));
    tests.verifyFalse(any(strcmp(chk(:, 1), 'Warning')), 'No warnings on the demo');
    tests.verifyTrue(any(contains(R.checks, 'OK: 4 trials averaged')), 'R.checks keeps its lines');
    % A click on a row shows it in full (found, why it matters, what to try)
    k = find(strcmp(chk(:, 2), 'Flow index'), 1);
    UIKit.checkSelected(app.ChecksTable, struct('Indices', [k 3]), app.ChecksText);
    txt = strjoin(app.ChecksText.Value, ' ');
    tests.verifyTrue(contains(txt, 'Why it matters:') && contains(txt, 'What to try:'), txt);
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
    tests.verifyTrue(hasCheck(app.ChecksTable.Data, 'Note', 'Flow index', 'exposure model'));
    app.setParams(struct('FlowModel', 'invK2'));
    % No dark level: the Checks tab asks for it (the demo camera has an offset of 100)
    app.setParams(struct('Dark', 0));
    tests.verifyTrue(logical(app.run()));
    tests.verifyTrue(hasCheck(app.ChecksTable.Data, 'Check', 'Dark level', 'no dark level was subtracted'), ...
        strjoin(app.ChecksTable.Data(:, 3), ' | '));
    shot(tests, app, 'LSCIAnalysisApp_11_checks_dark_level', 'Checks');
    app.setParams(struct('Dark', 100));

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
    s = Session.load(ps);
    tests.verifyEqual({s.checks.topic}, {app.Result.checkRows.topic}, 'the checks are in the session');
    tests.verifyTrue(any(strcmp(s.summary, ['Checks: ' QualityChecks.summary(s.checks)])), strjoin(s.summary, newline));
    left = Report.lines(s);
    tests.verifyTrue(any(strncmp(left, 'CHECKS (', 8)), 'the report has a CHECKS block');
    tests.verifyTrue(contains(MethodsWriter.fromSession(s), 'quality checks'), 'the methods text names the checks');
    tests.verifyEqual(b.ChecksTable.Data, app.ChecksTable.Data, 'the reopened window shows the same checks');
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

function testPerimedDatFile(tests)
    % A PIMSoft .dat of the demo: variance and intensity images give the same flow as the contrast images
    s = demoLSCI();
    n = 200;
    K = LaserSpeckle.spatialContrast(double(s.frames(:, :, 1:n)) - s.dark, 7);
    I = 1000 * ones(size(K));
    beta = 0.95;
    V = (K .* I / beta) .^ 2;
    f = fullfile(tests.TestData.tmp, 'demo_pimsoft.dat');
    writePerimedDat(f, V, I, struct('version', 2, 'gain', 1, 'beta', beta, 'name', 'Demo', ...
        'frameRateText', sprintf('%g img/s', s.fps), 'resolutionMm', 0.01));
    app = LSCIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.openFile(f)));
    tests.verifyEqual(app.InputDropdown.Value, 'contrast', 'PIMSoft files open as contrast images');
    tests.verifyEqual(double(app.Data.stack), K, 'RelTol', 1e-5);
    tests.verifyEqual(app.Data.fps, s.fps, 'RelTol', 1e-9);
    tests.verifyEqual(app.Data.pixelSizeUm, 10, 'AbsTol', 1e-9);
    tests.verifyEqual(app.Data.info.format, 'perimed');
    shot(tests, app, 'LSCIAnalysisApp_10_pimsoft_dat', '');
end

%% testLaserSpeckleFaults - The faults demos: each blood-flow check fires
function testLaserSpeckleFaults(tests)
    app = LSCIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    % Raw speckle: the field moves 4 px at 45 s, the light falls by 20%, 25 ms exposure, a ROI on the skull
    tests.verifyTrue(logical(app.openFile(DemoData.file('lsciFaults'))));
    tests.verifyEqual(app.FramesEdit.Value, 5);
    tests.verifyEqual(numel(app.ROIs), 4);
    tests.verifyTrue(logical(app.run()));
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Field shift', 'moves by up to'), txt);
    tests.verifyTrue(hasCheck(chk, 'Check', 'Illumination', 'changes by'), txt);
    tests.verifyTrue(hasCheck(chk, 'Check', 'Exposure', '25 ms'), txt);
    tests.verifyTrue(hasCheck(chk, 'Check', 'Baseline contrast', 'Thinned skull'), txt);
    tests.verifyTrue(hasCheck(chk, 'Check', 'Speckle size', 'one pixel or smaller'), txt);
    tests.verifyTrue(contains(app.W.Status.Text, '1 warning'), app.W.Status.Text);
    k = find(strcmp(chk(:, 2), 'Field shift'), 1);
    UIKit.checkSelected(app.ChecksTable, struct('Indices', [k 3]), app.ChecksText);
    tests.verifyTrue(contains(strjoin(app.ChecksText.Value, ' '), 'What to try:'));
    shot(tests, app, 'LSCIAnalysisApp_12_checks_faults', 'Checks');

    % Perfusion images from an imager: clipped at 3000 PU, one image per second
    tests.verifyTrue(logical(app.openFile(DemoData.file('perfusionFaults'))));
    tests.verifyEqual(app.InputDropdown.Value, 'flow');
    tests.verifyTrue(logical(app.run()));
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Export range', '(3000)'), txt);
    tests.verifyTrue(hasCheck(chk, 'Check', 'Time resolution', 'One value every 1 s'), txt);
    tests.verifyTrue(hasCheck(chk, 'Note', 'Units', 'device'), txt);
    tests.verifyTrue(hasCheck(chk, 'Note', 'Raw images', 'dark level'), txt);
    tests.verifyFalse(any(strcmp(chk(:, 2), 'Speckle size')), 'no speckle checks on perfusion images');
    tests.verifyEqual(app.Result.response(1), 20, 'AbsTol', 4, 'the activated area still rises by ~20%');
    shot(tests, app, 'LSCIAnalysisApp_13_checks_perfusion', 'Checks');
end

%% hasCheck - A row of the Checks table with this result, topic and finding text
function tf = hasCheck(chk, result, topic, finding)
    tf = any(strcmp(chk(:, 1), result) & strcmp(chk(:, 2), topic) & contains(chk(:, 3), finding));
end
