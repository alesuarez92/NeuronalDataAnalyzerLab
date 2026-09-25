%% HistologyWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: HISTOLOGY / CULTURE WINDOW ON THE DEMO IMAGES
% =========================================================================
% Drives HistologyApp through its public methods (no dialogs):
%   demo -> align channels and images (automatic shift) -> count cells ->
%   threshold view -> regions A / B -> checks -> export .csv / .mat ->
%   session save / reopen, and the landmark alignment. Checks the results
%   against the demo ground truth (core/demo/demoHistology.m) and saves a
%   frame after every step to
%   test-artifacts/screens/walkthrough/HistologyApp_<NN>_<step>.png.
% Skipped when no display is available.
% =========================================================================

function tests = HistologyWalkthroughTest
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
        warning('HistologyWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

function testHistologyDemo(tests)
    app = HistologyApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyEqual(HelpApp.demoWindow('Histology'), 'HistologyApp');

    % 1. Demo: two images, two channels, pixel size from the "file"
    tests.verifyTrue(logical(app.loadDemo()));
    tr = app.DemoTruth;
    tests.verifyNumElements(app.Images, 2);
    tests.verifyEqual(size(app.Images{1}), [400 400 2]);
    tests.verifyEqual(app.PixelSizeEdit.Value, 1);
    tests.verifyTrue(app.PixelSizeFromFile);
    tests.verifyEqual(char(app.ExportBtn.Enable), 'off');
    shot(tests, app, 'HistologyApp_01_demo_loaded');

    % 2. Align channels and images (automatic shift on the nuclei)
    app.setAlignment('shift', 1, true);
    tests.verifyTrue(logical(app.align()));
    tests.verifyEqual(app.AlignedMethod, 'shift');
    tests.verifyEqual(app.Shifts(2, :), tr.shifts(2, :), 'AbsTol', 0.3);
    tests.verifyEqual(app.ChannelShifts{1}(2, :), tr.chromaticShift, 'AbsTol', 0.75);
    tests.verifyTrue(startsWith(app.AlignInfo.Text, 'Aligned'));
    app.setView(2, 'Composite');
    shot(tests, app, 'HistologyApp_02_aligned');

    % 3. Count with the default settings: every nucleus, debris and fibre left out
    tests.verifyTrue(logical(app.countCells()));
    n = cellfun(@(r) r.n, app.Results);
    tests.verifyEqual(n, [tr.nCells tr.nCells]);
    tests.verifyEqual(cellfun(@(p) p{1}.nPositive, app.Positives), tr.nPositive);
    tests.verifyEqual(app.Results{1}.nRejected.tooSmall, size(tr.debrisXY, 1));
    tests.verifyEqual(app.Results{1}.nRejected.elongated, 1);
    tests.verifyEqual(char(app.ExportBtn.Enable), 'on');
    rows = app.CountsTable.Data;
    tests.verifySize(rows, [2 7]);   % one whole-image row per image
    tests.verifyEqual(rows{1, 3}, 60);
    tests.verifyEqual(rows{1, 5}, 375, 'AbsTol', 0.1);
    tests.verifyEqual(size(app.CellsTable.Data, 1), 120);
    app.setView(1, 'Composite');
    shot(tests, app, 'HistologyApp_03_counted', 'Counts');
    app.setView(1, app.ViewThresholded);
    shot(tests, app, 'HistologyApp_04_thresholded', 'Cells');

    % 4. Regions A (left half) and B (right half)
    for r = 1:numel(tr.regions)
        app.addRegion(tr.regions(r).name, tr.regions(r).xy);
    end
    tests.verifyNumElements(app.Regions, 2);
    for k = 1:2
        S = app.RegionStats{k};
        for r = 1:2
            tests.verifyEqual(S(r).nCells, tr.counts(r).nCells, sprintf('image %d, %s', k, S(r).name));
            tests.verifyEqual(S(r).nPositive, tr.counts(r).nPositive(k), sprintf('image %d, %s', k, S(r).name));
            tests.verifyEqual(S(r).perMm2, 375, 'AbsTol', 1e-6);
        end
    end
    tests.verifySize(app.CountsTable.Data, [4 7]);
    app.setView(2, 'Composite');
    shot(tests, app, 'HistologyApp_05_regions', 'Counts');

    % 5. Checks: nothing to warn about on the aligned demo
    chk = app.ChecksTable.Data;
    tests.verifyNotEmpty(chk);
    tests.verifyFalse(any(strcmp(chk(:, 1), 'Warning')), 'No warnings on the aligned demo');
    tests.verifyTrue(any(strcmp(chk(:, 2), 'Touching cells')));
    shot(tests, app, 'HistologyApp_06_checks', 'Checks');

    % 6. Export .csv (+ _counts.csv) and .mat
    csvPath = fullfile(tests.TestData.tmp, 'histology_cells.csv');
    tests.verifyTrue(logical(app.exportResultsTo(csvPath)));
    tests.verifyEqual(exist(csvPath, 'file'), 2);
    countsPath = fullfile(tests.TestData.tmp, 'histology_cells_counts.csv');
    tests.verifyEqual(exist(countsPath, 'file'), 2);
    lines = strsplit(strtrim(fileread(csvPath)), newline);
    tests.verifyNumElements(lines, 121);   % header + 120 cells
    lines = strsplit(strtrim(fileread(countsPath)), newline);
    tests.verifyNumElements(lines, 5);     % header + 2 images x 2 regions
    matPath = fullfile(tests.TestData.tmp, 'histology.mat');
    tests.verifyTrue(logical(app.exportResultsTo(matPath)));
    m = load(matPath);
    tests.verifyTrue(isfield(m, 'results') && isfield(m.results, 'labels'));
    tests.verifyEqual(size(m.results.labels{1}), [400 400]);

    % 7. Session: save, reopen in a new window, same counts
    tests.verifyEqual(char(app.SessionBtns.Save.Enable), 'on');
    p = fullfile(tests.TestData.tmp, ['HistologyApp' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, 'Histology walkthrough: demo data')));
    b = HistologyApp(); cb = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)), 'session not reopened');
    tests.verifyEqual(b.AlignedMethod, 'shift');
    tests.verifyNumElements(b.Regions, 2);
    tests.verifyEqual(b.CountsTable.Data, app.CountsTable.Data);
    shot(tests, b, 'HistologyApp_07_session_reopened', 'Counts');

    % Methods text of this analysis
    txt = MethodsWriter.fromSession(Session.capture(app));
    tests.verifyTrue(contains(txt, 'Cells were counted in the Nuclei (DAPI) channel'));
end

function testHistologyLandmarks(tests)
    app = HistologyApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tr = app.DemoTruth;
    % Four cell centres as landmarks: day 1 position, and where they are on day 3
    idx = [1 15 35 50];
    fixed = tr.centers(idx, :);
    moving = fixed + [tr.shifts(2, 2) tr.shifts(2, 1)];   % [x y] + [dx dy]
    app.setAlignment('landmarks');
    app.setLandmarks(2, moving, fixed);
    tests.verifyTrue(logical(app.align()));
    tests.verifyEqual(app.AlignedMethod, 'landmarks');
    tests.verifyLessThan(app.LandmarkRms(2), 0.1);
    tests.verifyTrue(logical(app.countCells()));
    for r = 1:numel(tr.regions)
        app.addRegion(tr.regions(r).name, tr.regions(r).xy);
    end
    S = app.RegionStats{2};
    tests.verifyEqual([S.nCells], [tr.counts.nCells]);
    shot(tests, app, 'HistologyApp_08_landmarks', 'Checks');
end
