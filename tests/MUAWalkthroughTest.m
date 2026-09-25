%% MUAWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: MUA CLUSTER CLEAN-UP, RASTER & PSTH AND CORRELOGRAMS
% =========================================================================
% Drives MUA Analysis on the demo data through its public, dialog-free
% methods: load the demo, sort without auto-merge (K-means over-splits),
% auto-merge, Raster & PSTH, Correlograms, a manual merge, Undo, a split
% and Undo back to the sorted clusters. A frame is saved after every step
% to test-artifacts/screens/walkthrough/MUAAnalysisApp_x<NN>_<step>.png
% for the Help walkthroughs and the website. Skipped when no display is
% available.
% =========================================================================

function tests = MUAWalkthroughTest
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
        warning('MUAWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

%% unitIds - Current unit IDs (noise 0 excluded), as a row
function ids = unitIds(app)
    ids = unique(app.SpikeResults.clusterIdx);
    ids = reshape(ids(ids > 0), 1, []);
end

function testMUAClusterEditingAndResponses(tests)
    hasTb = license('test', 'Statistics_Toolbox') && license('test', 'Signal_Toolbox') && ...
        exist('kmeans', 'file') == 2 && exist('findpeaks', 'file') == 2;
    tests.assumeTrue(hasTb, 'Spike sorting needs the Signal Processing and Statistics toolboxes');
    app = MUAAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    prevRng = rng; rng(0, 'twister'); r = onCleanup(@() rng(prevRng));

    tests.verifyTrue(logical(app.loadDemo()));
    shot(tests, app, 'MUAAnalysisApp_x01_demo_loaded', 'Signal & spikes');

    % 1) Sort with the demo settings but without auto-merge: K-means tends
    %    to split a unit in two
    p = app.SpikeSortParams;
    p.autoMerge = 0;
    tests.verifyTrue(logical(app.runSorting(p)));
    nSorted = numel(unitIds(app));
    tests.verifyEmpty(app.EditHistory);
    shot(tests, app, 'MUAAnalysisApp_x02_sorted_no_merge', 'Waveforms');

    % 2) Auto-merge clusters with the same shape and size
    [ok, mergeLog] = app.autoMergeClusters();
    tests.verifyTrue(logical(ok));
    merged = unitIds(app);
    tests.verifyEqual(numel(merged), nSorted - numel(mergeLog));
    tests.verifyGreaterThanOrEqual(numel(merged), 2);
    tests.verifyLessThanOrEqual(numel(merged), 3);
    shot(tests, app, 'MUAAnalysisApp_x03_auto_merged', 'Waveforms');

    % 3) Raster & PSTH around each stimulus (every 2 s): response 5-55 ms
    tests.verifyTrue(logical(app.showRasterPSTH(merged, [-0.1 0.3], 0.005)));
    tests.verifyNotEmpty(findobj(app.RasterPanel, 'Type', 'axes'));
    shot(tests, app, 'MUAAnalysisApp_x04_raster_psth', 'Raster & PSTH');

    % 4) Auto- and cross-correlograms with the refractory band
    tests.verifyTrue(logical(app.showCorrelograms(merged, 50, 1)));
    nShown = min(4, numel(merged));
    tests.verifyNumElements(findobj(app.CorrPanel, 'Type', 'axes'), nShown^2);
    shot(tests, app, 'MUAAnalysisApp_x05_correlograms', 'Correlograms');

    % 5) Manual merge of two units, then Undo
    tests.verifyTrue(logical(app.mergeClusters(merged(1:2))));
    tests.verifyEqual(unitIds(app), setdiff(merged, merged(2)));
    shot(tests, app, 'MUAAnalysisApp_x06_manual_merge', 'Waveforms');
    tests.verifyTrue(logical(app.undoClusterEdit()));
    tests.verifyEqual(unitIds(app), merged);
    shot(tests, app, 'MUAAnalysisApp_x07_undo_merge', 'Waveforms');

    % 6) Split a unit in two (new ID = highest + 1), then Undo
    tests.verifyTrue(logical(app.splitCluster(merged(1))));
    tests.verifyEqual(unitIds(app), [merged, max(merged) + 1]);
    shot(tests, app, 'MUAAnalysisApp_x08_split', 'Clusters (feature space)');
    tests.verifyTrue(logical(app.undoClusterEdit()));
    tests.verifyEqual(unitIds(app), merged);

    % 7) Undo the auto-merge too: back to the K-means clusters
    if ~isempty(mergeLog)
        tests.verifyTrue(logical(app.undoClusterEdit()));
        tests.verifyNumElements(unitIds(app), nSorted);
    end
    tests.verifyFalse(logical(app.undoClusterEdit()));   % nothing left to undo
    shot(tests, app, 'MUAAnalysisApp_x09_undo_all', 'Quality');
end

function testMUARasterWithoutStimulus(tests)
    % A MUA file without a stimulus channel: the Raster & PSTH tab explains why it is empty
    s = load(DemoData.file('mua'));
    s = rmfield(s, {'stim_data', 'stim_fs', 't_stim'});
    f = [tempname '.mat'];
    save(f, '-struct', 's');
    cf = onCleanup(@() delete(f));
    app = MUAAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.openFile(f, false)));
    % Before sorting: nothing to show, merge or undo (status bar says so, no errors)
    tests.verifyFalse(logical(app.showRasterPSTH()));
    tests.verifyFalse(logical(app.showCorrelograms()));
    tests.verifyFalse(logical(app.mergeClusters([1 2])));
    tests.verifyFalse(logical(app.undoClusterEdit()));
    hasTb = license('test', 'Statistics_Toolbox') && license('test', 'Signal_Toolbox') && ...
        exist('kmeans', 'file') == 2 && exist('findpeaks', 'file') == 2;
    if hasTb
        prevRng = rng; rng(0, 'twister'); r = onCleanup(@() rng(prevRng));
        app.ChannelMenu.Value = find(app.MUAData.channels == 4, 1);
        p = app.SpikeSortParams;
        p.detectMethod = 'MAD'; p.threshold = 4; p.polarity = 'negative';
        tests.verifyTrue(logical(app.runSorting(p)));
        tests.verifyFalse(logical(app.showRasterPSTH()));
        tests.verifyTrue(contains(app.StatusLabel.Text, 'No stimulus'));
        % Correlograms do not need a stimulus
        tests.verifyTrue(logical(app.showCorrelograms()));
    end
    shot(tests, app, 'MUAAnalysisApp_x10_no_stimulus', 'Raster & PSTH');
end
