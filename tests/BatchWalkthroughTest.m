%% BatchWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: BATCH PROCESSING ON DEMO FILES
% =========================================================================
% Drives BatchApp through its public methods (no dialogs): demo batch for
% each pipeline -> Run -> summary, including a corrupt file (red row, the
% other files still processed), removing files and exporting. Checks the
% summaries against the demo truths and saves a frame after every step to
% test-artifacts/screens/walkthrough/BatchApp_x<NN>_<step>.png.
% Skipped when no display is available; the LDF and MUA steps need their
% toolboxes and are left out without them.
% =========================================================================

function tests = BatchWalkthroughTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'demo'));
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
        warning('BatchWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

function tf = hasSPT()
    tf = license('test', 'Signal_Toolbox') && exist('decimate', 'file') == 2 && exist('filtfilt', 'file') == 2;
end

%% testBatchPipelines - Demo batch per pipeline, with an error row and file edits
function testBatchPipelines(tests)
    app = BatchApp(); c = onCleanup(@() delete(app.UIFig));
    work = tests.TestData.work;
    verifyEqual(tests, app.Pipeline, 'ldf');
    verifyEqual(tests, char(app.RunBtn.Enable), 'off');
    shot(tests, app, 'BatchApp_x01_start');

    % --- LDF: 4 recordings + a corrupt file -> 4 OK rows, 1 red error row ---
    if hasSPT()
        verifyTrue(tests, logical(app.loadDemo('ldf')));
        verifyNumElements(tests, app.Files, 4);
        corrupt = fullfile(work, 'corrupt_recording.mat');
        fid = fopen(corrupt, 'w'); fprintf(fid, 'not a MAT file'); fclose(fid);
        verifyEqual(tests, app.addFiles(corrupt), 1);
        shot(tests, app, 'BatchApp_x02_ldf_demo_loaded');
        [ok, R] = app.runBatch(fullfile(work, 'ldf'));
        verifyTrue(tests, ok);
        verifyEqual(tests, [R.nOK R.nError], [4 1]);
        T = R.summary;
        verifyEqual(tests, T.nTrials(1:4)', [6 6 6 6]);
        verifyEqual(tests, T.PeakAmp(1:4)', [20 25 30 35], 'AbsTol', 3);
        verifyEqual(tests, T.PeakLatency_s(1:4)', [3 3.5 4 4.5], 'AbsTol', 0.4);
        verifyEqual(tests, T.Status{5}, 'error');
        verifyEqual(tests, height(app.Table.Data), 5);
        verifyEqual(tests, exist(R.paths.csv, 'file'), 2);
        verifyNotEmpty(tests, app.LogArea.Value);
        shot(tests, app, 'BatchApp_x03_ldf_summary_with_error');

        % Export a copy, then remove the corrupt file: results are cleared
        verifyTrue(tests, logical(app.exportSummary(fullfile(work, 'ldf_copy.csv'))));
        verifyEqual(tests, exist(fullfile(work, 'ldf_copy.csv'), 'file'), 2);
        app.removeFiles(5);
        verifyNumElements(tests, app.Files, 4);
        verifyEmpty(tests, app.Result);
        shot(tests, app, 'BatchApp_x04_ldf_file_removed');
    end

    % --- ERP: N1 latency and CSD sink per file ---
    verifyTrue(tests, logical(app.loadDemo('erp')));
    verifyNumElements(tests, app.ParamSpec, numel(Batch.paramSpec('erp')));
    shot(tests, app, 'BatchApp_x05_erp_settings');
    [ok, R] = app.runBatch(fullfile(work, 'erp'));
    verifyTrue(tests, ok);
    verifyEqual(tests, R.nOK, 3);
    T = R.summary;
    for k = 1:3
        rows = strcmp(T.File, sprintf('lfp_animal%02d.mat', k));
        verifyEqual(tests, unique(T.SinkChannel(rows)), k + 2);
        r = rows & T.Channel == k + 2;
        verifyEqual(tests, T.N1Latency_ms(r), 9 + 3 * k, 'AbsTol', 1.5);
    end
    shot(tests, app, 'BatchApp_x06_erp_summary');

    % --- Imaging: peak dF/F and vessel diameter ---
    verifyTrue(tests, logical(app.loadDemo('roi')));
    p = app.getParams();
    verifyEqual(tests, p.line, [25 50 63 50]);
    [ok, R] = app.runBatch(fullfile(work, 'roi'));
    verifyTrue(tests, ok);
    verifyEqual(tests, R.summary.PeakDFF', [0.5 1 1.5], 'AbsTol', 0.1);
    verifyEqual(tests, R.summary.MeanDiameter_px', [10 12 14], 'AbsTol', 0.75);
    shot(tests, app, 'BatchApp_x07_roi_summary');

    % --- Response features: one row per series ---
    verifyTrue(tests, logical(app.loadDemo('features')));
    app.setParams(struct('seriesMode', 'Each series'));
    [ok, R] = app.runBatch(fullfile(work, 'features'));
    verifyTrue(tests, ok);
    verifyEqual(tests, height(R.summary), 32);
    shot(tests, app, 'BatchApp_x08_features_each_series');
    app.setParams(struct('seriesMode', 'Mean of series'));
    [~, R] = app.runBatch();
    verifyEqual(tests, R.summary.PeakAmp', [20 25 30 35], 'AbsTol', 1.5);
    shot(tests, app, 'BatchApp_x09_features_mean');

    % --- MUA: settings for the demo (sorting itself is covered by BatchFeaturesTest) ---
    verifyTrue(tests, logical(app.setPipeline('mua')));
    app.setParams(struct('channels', 4, 'seed', 0));
    p = app.getParams();
    verifyEqual(tests, p.channels, 4);
    verifyEqual(tests, p.detectMethod, 'MAD');
    app.clearFiles();
    verifyEqual(tests, char(app.RunBtn.Enable), 'off');
    shot(tests, app, 'BatchApp_x10_mua_settings');
end

%% testBatchMUA - MUA demo batch in the window (two files, channel 4)
function testBatchMUA(tests)
    tests.assumeTrue(license('test', 'Statistics_Toolbox') && hasSPT() && exist('kmeans', 'file') == 2 && ...
        exist('findpeaks', 'file') == 2, 'Spike sorting needs the Signal Processing and Statistics Toolboxes');
    app = BatchApp(); c = onCleanup(@() delete(app.UIFig));
    verifyTrue(tests, logical(app.loadDemo('mua')));
    [ok, R] = app.runBatch(fullfile(tests.TestData.work, 'mua'));
    verifyTrue(tests, ok);
    verifyEqual(tests, R.nOK, 2);
    verifyGreaterThanOrEqual(tests, min(R.summary.nUnits), 2);
    verifyLessThanOrEqual(tests, max(R.summary.nUnits), 3);
    verifyEqual(tests, R.summary.nSpikes(2), R.summary.nSpikes(1), 'RelTol', 0.05);
    shot(tests, app, 'BatchApp_x11_mua_summary');
end
