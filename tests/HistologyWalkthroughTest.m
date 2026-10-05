%% HistologyWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: HISTOLOGY / CULTURE WINDOW ON THE DEMO IMAGES
% =========================================================================
% Drives HistologyApp through its public methods (no dialogs):
%   demo -> align channels and images (automatic shift) -> count cells ->
%   threshold view -> regions A / B -> checks -> export .csv / .mat ->
%   session save / reopen, the landmark alignment, and the Checks tab warning
%   when regions are drawn on images that were not aligned. Checks the results
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
    addpath(fullfile(root, 'core', 'io'));
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
    tests.verifyEqual(app.ChecksText.Value{1}, sprintf('%s. Click a row to read it in full.', ...
        QualityChecks.summary(app.Checks)));
    % A click on the channel row: what was found and what to try
    k = find(strcmp(chk(:, 2), 'Channels'), 1);
    tests.verifyEqual(chk{k, 1}, 'Check');
    UIKit.checkSelected(app.ChecksTable, struct('Indices', [k 2]), app.ChecksText);
    tests.verifyEqual(app.ChecksText.Value{1}, 'Check: Channels');
    tests.verifyTrue(any(startsWith(app.ChecksText.Value, 'What to try: ')), strjoin(app.ChecksText.Value, ' '));
    shot(tests, app, 'HistologyApp_06_checks', 'Checks');

    % 6. Export .csv (+ _counts.csv) and .mat
    csvPath = fullfile(tests.TestData.tmp, 'histology_cells.csv');
    tests.verifyTrue(logical(app.exportResultsTo(csvPath)));
    tests.verifyEqual(exist(csvPath, 'file'), 2);
    countsPath = fullfile(tests.TestData.tmp, 'histology_cells_counts.csv');
    tests.verifyEqual(exist(countsPath, 'file'), 2);
    lines = strsplit(strtrim(fileread(csvPath)), newline);
    tests.verifyNumElements(lines, 121);   % header + 120 cells
    % Frozen headers (1.0): the fixed columns, then two per marker channel
    markers = app.ChannelNames(setdiff(1:size(app.Images{1}, 3), app.CountSettings.channel));
    markers = markers(:)';
    tests.verifyNotEmpty(markers);
    frozen(tests, csvHeader(lines{1}), [{'Image', 'Cell', 'x (um)', 'y (um)', 'Area (um2)', 'Elongation', ...
        'Region'}, strcat(markers, ' positive'), strcat(markers, ' part of cell (%)')], 'Histology cells .csv');
    lines = strsplit(strtrim(fileread(countsPath)), newline);
    tests.verifyNumElements(lines, 5);     % header + 2 images x 2 regions
    frozen(tests, csvHeader(lines{1}), [{'Image', 'Region', 'Cells', 'Area (mm2)', 'Cells per mm2'}, ...
        strcat('Positive', {' '}, markers), strcat('%', {' '}, markers)], 'Histology counts .csv');
    matPath = fullfile(tests.TestData.tmp, 'histology.mat');
    tests.verifyTrue(logical(app.exportResultsTo(matPath)));
    m = load(matPath);
    frozen(tests, m, {'results'}, 'Histology .mat export');
    frozen(tests, m.results, {'imageNames', 'channelNames', 'pixelSizeUm', 'settings', 'regions', ...
        'alignMethod', 'shifts', 'landmarks', 'landmarkRms', 'channelShifts', 'countsHeader', 'counts', ...
        'cellsHeader', 'cells', 'labels', 'count', 'markers'}, 'Histology .mat export results');
    tests.verifyTrue(isfield(m, 'results') && isfield(m.results, 'labels'));
    tests.verifyEqual(size(m.results.labels{1}), [400 400]);

    % 7. Session: save, reopen in a new window, same counts
    tests.verifyEqual(char(app.SessionBtns.Save.Enable), 'on');
    p = fullfile(tests.TestData.tmp, ['HistologyApp' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, 'Histology walkthrough: demo data')));
    b = HistologyApp(); cb = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)), 'session not reopened');
    tests.verifyEqual(b.AlignedMethod, 'shift');
    tests.verifyTrue(b.PixelSizeFromFile);
    tests.verifyEqual(b.PixelSizeNote.Text, 'Read from the file.');
    tests.verifyNumElements(b.Regions, 2);
    tests.verifyEqual(b.CountsTable.Data, app.CountsTable.Data);
    tests.verifyEqual(b.ChecksTable.Data, app.ChecksTable.Data, 'the same checks after reopening');
    s = Session.load(p);
    tests.verifyEqual(s.checks, app.Checks);
    shot(tests, b, 'HistologyApp_07_session_reopened', 'Counts');

    % Methods text of this analysis, with what the checks reported
    txt = MethodsWriter.fromSession(Session.capture(app));
    tests.verifyTrue(contains(txt, 'Cells were counted in the Nuclei (DAPI) channel'));
    tests.verifyTrue(contains(txt, 'The built-in quality checks reported'), txt);
end

function testHistologyChecksWarn(tests)
    % The demo counted without aligning, with regions: the Checks tab warns
    app = HistologyApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tr = app.DemoTruth;
    tests.verifyTrue(logical(app.countCells()));
    for r = 1:numel(tr.regions)
        app.addRegion(tr.regions(r).name, tr.regions(r).xy);
    end
    chk = app.ChecksTable.Data;
    k = find(strcmp(chk(:, 2), 'Alignment'));
    tests.verifyNumElements(k, 1);
    tests.verifyEqual(chk{k, 1}, 'Warning');
    tests.verifyEqual(QualityChecks.count(app.Checks, 'warning'), 1);
    tests.verifyTrue(contains(app.ChecksText.Value{1}, '1 warning'), app.ChecksText.Value{1});
    UIKit.checkSelected(app.ChecksTable, struct('Indices', [k 1]), app.ChecksText);
    tests.verifyEqual(app.ChecksText.Value{end}, 'What to try: Align them in step 2.');
    shot(tests, app, 'HistologyApp_10_checks_warning', 'Checks');
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

function testHistologyImportedRegions(tests)
    % The demo regions drawn in ImageJ (RoiSet.zip) or QuPath (GeoJSON) give the same counts
    app = HistologyApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tr = app.DemoTruth;
    tests.verifyTrue(logical(app.align()));
    tests.verifyTrue(logical(app.countCells()));
    d = tests.TestData.tmp;
    names = cell(1, numel(tr.regions));
    feats = cell(1, numel(tr.regions));
    for r = 1:numel(tr.regions)
        names{r} = sprintf('%04d.roi', r);
        xy = tr.regions(r).xy - 0.5;                       % ImageJ / QuPath put the pixel corner at 0
        writeImageJRoi(fullfile(d, names{r}), xy, tr.regions(r).name, 'polygon', true);
        ring = [xy; xy(1, :)];
        pts = strjoin(arrayfun(@(i) sprintf('[%.4f,%.4f]', ring(i, 1), ring(i, 2)), 1:size(ring, 1), ...
            'UniformOutput', false), ',');
        feats{r} = sprintf(['{"type":"Feature","geometry":{"type":"Polygon","coordinates":[[%s]]},' ...
            '"properties":{"objectType":"annotation","name":"%s"}}'], pts, tr.regions(r).name);
    end
    z = fullfile(d, 'RoiSet.zip');
    zip(z, names, d);
    tests.verifyEqual(app.importRegions(z), numel(tr.regions));
    tests.verifyEqual({app.Regions.name}, {tr.regions.name});
    S = app.RegionStats{2};
    tests.verifyEqual([S.nCells], [tr.counts.nCells]);
    for r = numel(app.Regions):-1:1, app.removeRegion(r); end
    g = fullfile(d, 'annotations.geojson');
    fid = fopen(g, 'w');
    fprintf(fid, '{"type":"FeatureCollection","features":[%s]}', strjoin(feats, ','));
    fclose(fid);
    tests.verifyEqual(app.importRegions(g), numel(tr.regions));
    S = app.RegionStats{2};
    tests.verifyEqual([S.nCells], [tr.counts.nCells]);
    tests.verifyEqual(app.importRegions(fullfile(d, 'missing.roi')), 0);
    shot(tests, app, 'HistologyApp_09_imported_regions', 'Counts');
end

%% csvHeader - Column names of a header line written with every name in double quotes
function h = csvHeader(line)
    h = regexp(strtrim(line), '"((?:[^"]|"")*)"', 'tokens');
    h = strrep(cellfun(@(c) c{1}, h, 'UniformOutput', false), '""', '"');
end

%% frozen - Every frozen name (1.0) is present: struct fields, table columns or a cellstr
function frozen(tests, have, names, what)
    if isstruct(have)
        have = fieldnames(have);
    elseif istable(have)
        have = have.Properties.VariableNames;
    end
    missing = names(~ismember(names, have));
    tests.verifyEmpty(missing, sprintf('%s: missing %s (frozen for 1.0)', what, strjoin(missing, ', ')));
end
