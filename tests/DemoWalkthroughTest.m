%% DemoWalkthroughTest.m
% =========================================================================
% WALKTHROUGHS: DRIVE EACH WINDOW THROUGH ITS STEPS ON DEMO DATA
% =========================================================================
% Opens each window, loads its demo data and runs the workflow step by
% step through the windows' public methods (no dialogs), saving a frame
% after every step to test-artifacts/screens/walkthrough/<App>_NN_<step>.png.
% The frames feed the Help walkthroughs and the project website, and the
% test fails if any step errors. Skipped when no display is available.
% =========================================================================

function tests = DemoWalkthroughTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    tests.TestData.outDir = fullfile(root, 'test-artifacts', 'screens', 'walkthrough');
    if ~exist(tests.TestData.outDir, 'dir'), mkdir(tests.TestData.outDir); end
end

function setup(tests)
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end

%% shot - Save a frame of the app window, optionally after selecting a tab
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
        warning('DemoWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

function testExtractLDF(tests)
    app = ExtractLDFApp(); c = onCleanup(@() delete(app.UIFig));
    shot(tests, app, 'ExtractLDFApp_01_start');
    app.loadDemo();
    shot(tests, app, 'ExtractLDFApp_02_demo_loaded');
    app.processData();
    shot(tests, app, 'ExtractLDFApp_03_cropped');
end

function testProcessingLDF(tests)
    app = ProcessingLDFApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    shot(tests, app, 'ProcessingLDFApp_01_demo_loaded');
    % Downsample 10x to 100 Hz, 4th-order Butterworth low-pass at 1 Hz
    p = struct('downsample', 10, 'filterType', 2, 'designType', 1, 'filterOrder', 4, ...
        'cutoffLow', NaN, 'cutoffHigh', 1);
    tests.verifyTrue(logical(app.applyProcessingParams(p)));
    shot(tests, app, 'ProcessingLDFApp_02_filtered', 'Signals');
    shot(tests, app, 'ProcessingLDFApp_03_filter_response', 'Filter response');
    app.segmentByOnsetsConfig();
    shot(tests, app, 'ProcessingLDFApp_04_trials', 'Trials');
end

function testLDFGrandAverage(tests)
    app = LDFGrandAverageApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    shot(tests, app, 'LDFGrandAverageApp_01_demo_loaded');
    app.plotGrandAverage();
    shot(tests, app, 'LDFGrandAverageApp_02_grand_average');
end

function testExtractEphys(tests)
    app = ExtractEphysApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    shot(tests, app, 'ExtractEphysApp_01_demo_loaded');
    app.processLFPData(struct());
    shot(tests, app, 'ExtractEphysApp_02_lfp');
    app.processMUAData(struct());
    shot(tests, app, 'ExtractEphysApp_03_mua');
end

function testLFPAnalysis(tests)
    app = LFPAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    shot(tests, app, 'LFPAnalysisApp_01_demo_loaded', 'Stimulus');
    app.runERP(struct('preTime', 0.05, 'postTime', 0.2, 'threshold', 0.5, 'minISI', 0.5));
    shot(tests, app, 'LFPAnalysisApp_02_erp_overlay', 'ERP overlay');
    shot(tests, app, 'LFPAnalysisApp_03_erp_per_channel', 'ERP per channel');
    app.computeCSD(100, 1:8);
    shot(tests, app, 'LFPAnalysisApp_04_csd', 'CSD');
end

function testMUAAnalysis(tests)
    app = MUAAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    shot(tests, app, 'MUAAnalysisApp_01_demo_loaded', 'Signal & spikes');
    tests.verifyTrue(logical(app.runSorting([])));
    shot(tests, app, 'MUAAnalysisApp_02_spikes', 'Signal & spikes');
    shot(tests, app, 'MUAAnalysisApp_03_waveforms', 'Waveforms');
    shot(tests, app, 'MUAAnalysisApp_04_clusters', 'Clusters (feature space)');
    shot(tests, app, 'MUAAnalysisApp_05_spike_rate', 'Spike rate');
    shot(tests, app, 'MUAAnalysisApp_06_quality', 'Quality');
end

function testROIAnalysis(tests)
    app = ROIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    shot(tests, app, 'ROIAnalysisApp_01_demo_loaded');
    tests.verifyTrue(logical(app.runAnalysis('dff')));
    shot(tests, app, 'ROIAnalysisApp_02_dff');
    tests.verifyTrue(logical(app.runAnalysis('Vessel')));
    shot(tests, app, 'ROIAnalysisApp_03_vessel_diameter');
    tests.verifyTrue(logical(app.runAnalysis('Kymo')));
    shot(tests, app, 'ROIAnalysisApp_04_kymograph');
end

function testSignalCharacterization(tests)
    app = SignalCharacterizationApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    shot(tests, app, 'SignalCharacterizationApp_01_demo_loaded');
    tests.verifyTrue(logical(app.extract()));
    shot(tests, app, 'SignalCharacterizationApp_02_features');
end

function testHelpTryDemo(tests)
    h = HelpApp('LDF Average'); c = onCleanup(@() delete(h.UIFig));
    shot(tests, h, 'HelpApp_01_topic_with_demo_button');
    win = h.tryDemo('LDF Average');
    c2 = onCleanup(@() delete(win.UIFig));
    tests.verifyTrue(isvalid(win.UIFig));
end
