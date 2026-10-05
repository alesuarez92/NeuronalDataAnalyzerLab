%% ImagingWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: ROI ANALYSIS ADVANCED TOOLS ON DEMO DATA
% =========================================================================
% Drives ROIAnalysisApp through its public methods (no dialogs):
%   advanced demo -> motion correction -> cell detection -> ΔF/F per cell
%   -> export -> vessel diameter standard vs robust, and multi-ROI editing
%   on the basic demo. Checks the results against the demo ground truth and
%   saves a frame after every step to
%   test-artifacts/screens/walkthrough/ROIAnalysisApp_x<NN>_<step>.png.
% Skipped when no display is available.
% =========================================================================

function tests = ImagingWalkthroughTest
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
        warning('ImagingWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

%% roiCentres - [x y] centroid of every ROI in the app
function c = roiCentres(app)
    c = zeros(numel(app.ROIs), 2);
    for k = 1:numel(app.ROIs)
        [yy, xx] = find(app.ROIs(k).Mask);
        c(k, :) = [mean(xx) mean(yy)];
    end
end

function testROIAdvancedDemo(tests)
    app = ROIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadAdvancedDemo()));
    tr = app.DemoTruth;
    tests.verifyTrue(isstruct(tr) && isfield(tr, 'shifts'));
    tests.verifyEmpty(app.ROIs);
    shot(tests, app, 'ROIAnalysisApp_x01_advanced_demo');

    % 1. Motion correction recovers the simulated jitter
    tests.verifyTrue(logical(app.runMotionCorrection()));
    tests.verifyTrue(logical(app.MotionCb.Value));
    err = app.Shifts - tr.shifts;
    tests.verifyLessThan(max(abs(err(:))), 0.3);
    shot(tests, app, 'ROIAnalysisApp_x02_motion_corrected', 'Motion correction');

    % 2. Cell detection on the correlation image finds the three cells
    app.setDisplay('correlation');
    n = app.detectCells();
    tests.verifyEqual(n, 3);
    cents = roiCentres(app);
    tests.verifyTrue(issorted(cents(:, 1)), 'detected cells are numbered left to right');
    for i = 1:3
        tests.verifyLessThan(min(vecnorm(cents - tr.cellCenters(i, :), 2, 2)), 3, sprintf('cell %d', i));
    end
    shot(tests, app, 'ROIAnalysisApp_x03_cells_detected');

    % 3. One ΔF/F trace per cell, peaking at that cell's own events
    tests.verifyTrue(logical(app.runAnalysis('dff')));
    tests.verifyEqual(size(app.DFF), [3 numel(app.T)]);
    for i = 1:3
        [~, k] = min(vecnorm(cents - tr.cellCenters(i, :), 2, 2));
        for e = tr.eventTimes{i}
            win = app.T >= e - 0.5 & app.T <= e + 1.5;
            [~, iPk] = max(app.DFF(k, win));
            tw = app.T(win);
            tests.verifyEqual(tw(iPk), e, 'AbsTol', 0.5, sprintf('cell %d event %.1f s', i, e));
        end
    end
    app.setDisplay('mean');
    shot(tests, app, 'ROIAnalysisApp_x04_multi_roi_dff', 'Result');

    % 4. Export holds every ROI
    fcsv = [tempname '.csv']; c2 = onCleanup(@() deleteIfExists(fcsv));
    tests.verifyTrue(logical(app.exportResultsTo(fcsv)));
    tbl = readtable(fcsv);
    tests.verifyEqual(width(tbl), 4);                 % Time_s + one DFF column per cell
    % Frozen for 1.0: Time_s, then <measure>_<ROI>
    frozen(tests, tbl, [{'Time_s'}, matlab.lang.makeValidName(strcat('DFF_', app.ResultROINames(:)'))], ...
        'ROI .csv export');
    fmat = [tempname '.mat']; c3 = onCleanup(@() deleteIfExists(fmat));
    tests.verifyTrue(logical(app.exportResultsTo(fmat)));
    r = load(fmat);
    frozen(tests, r, {'results'}, 'ROI .mat export');
    frozen(tests, r.results, {'method', 'sourceFile', 't', 'intensity', 'movement', 'dff', 'speed', ...
        'kymograph', 'diameter', 'roiMask', 'roiMasks', 'roiNames', 'lineStart', 'lineEnd', ...
        'motionCorrection', 'shifts', 'bw256', 'smooth', 'normalize', 'dffBaselineFrames', ...
        'robustDiameter', 'diameterStandard', 'diameterPerFrame', 'diameterReplaced'}, 'ROI .mat export results');
    tests.verifyEqual(size(r.results.roiMasks, 3), 3);
    tests.verifyEqual(numel(r.results.roiNames), 3);
    tests.verifyTrue(logical(r.results.motionCorrection));

    % 5. Vessel diameter: the standard width jumps when the RBC crosses the line ...
    app.setRobustDiameter(false);
    tests.verifyTrue(logical(app.runAnalysis('Vessel')));
    cross = tr.rbcCrossFrames;
    tests.verifyGreaterThan(max(abs(app.Diameter(cross) - tr.diameter(cross))), 10);
    shot(tests, app, 'ROIAnalysisApp_x05_diameter_standard', 'Result');
    % ... the robust one follows the true diameter
    app.setRobustDiameter(true);
    tests.verifyTrue(logical(app.runAnalysis('Vessel')));
    tests.verifyLessThan(max(abs(app.Diameter - tr.diameter)), 2.5);
    tests.verifyTrue(any(app.DiameterOutliers));
    tests.verifyEqual(numel(app.DiameterPlain), numel(app.Diameter));
    shot(tests, app, 'ROIAnalysisApp_x06_diameter_robust', 'Result');
end

function testROIMultiRoiEditing(tests)
    app = ROIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyEqual(numel(app.ROIs), 1);            % roiMask from the file = ROI 1
    events = [3 7 11];
    bg = false(96); bg(80:90, 5:15) = true;           % background, away from cell and vessel
    tests.verifyEqual(app.addROI(bg, 'Background'), 2);
    tests.verifyTrue(logical(app.runAnalysis('dff')));
    tests.verifyEqual(size(app.DFF, 1), 2);
    for e = events
        win = app.T >= e - 0.5 & app.T <= e + 1.5;
        [~, iPk] = max(app.DFF(1, win));
        tw = app.T(win);
        tests.verifyEqual(tw(iPk), e, 'AbsTol', 0.6);
    end
    tests.verifyLessThan(max(abs(app.DFF(2, :))), 0.1);
    shot(tests, app, 'ROIAnalysisApp_x07_two_rois', 'Result');

    app.renameROI(2, 'Neuropil');
    tests.verifyEqual(app.ROIs(2).Name, 'Neuropil');
    app.removeROI(2);
    tests.verifyEqual(numel(app.ROIs), 1);
    tests.verifyEmpty(app.LastMethod);                % results no longer match the ROIs

    % Motion correction on a motion-free stack finds (almost) no motion
    tests.verifyTrue(logical(app.setMotionCorrection(true)));
    tests.verifyLessThan(max(abs(app.Shifts(:))), 0.3);
    tests.verifyTrue(logical(app.runAnalysis('Both')));
    tests.verifyEqual(size(app.Intensity, 1), 1);
    shot(tests, app, 'ROIAnalysisApp_x08_both_single_roi', 'Result');

    % One ROI: the .csv still names the ROI in every column (frozen for 1.0)
    fcsv = [tempname '.csv']; c2 = onCleanup(@() deleteIfExists(fcsv));
    tests.verifyTrue(logical(app.exportResultsTo(fcsv)));
    tbl = readtable(fcsv);
    roi = app.ResultROINames{1};
    frozen(tests, tbl, {'Time_s', matlab.lang.makeValidName(['Intensity_' roi]), ...
        matlab.lang.makeValidName(['Movement_' roi])}, 'ROI .csv export, one ROI');
    tests.verifyEqual(width(tbl), 3);
end

function deleteIfExists(f)
    if exist(f, 'file') == 2, delete(f); end
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

function n = nFrames(app)
    % Frames of the loaded stack (last dimension: 3 for gray, 4 for RGB stacks)
    if ndims(app.Stack) == 4, n = size(app.Stack, 4); else, n = size(app.Stack, 3); end
end

function testMicroscopeFiles(tests)
    % Files from microscope software open with their frame rate and channel choice
    d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's'));
    st = uint16(repmat(reshape(1:12, 1, 1, 12), 16, 20) * 10);
    st(4:8, 5:9, :) = st(4:8, 5:9, :) + 500;
    app = ROIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    f = fullfile(d, 'movie.isxd');
    writeImagingFormat('isxd', f, st, 'Fps', 20);
    tests.verifyTrue(logical(app.openFile(f)));
    tests.verifyEqual(nFrames(app), 12);
    tests.verifyTrue(app.TimeFromFile);
    tests.verifyEqual(app.TimeVec(end), 11 / 20, 'AbsTol', 1e-9);
    thor = fullfile(d, 'thor');
    writeImagingFormat('thorimage', thor, cat(4, reshape(st, 16, 20, 1, 12), reshape(st + 1, 16, 20, 1, 12)), 'Fps', 30);
    tests.verifyTrue(logical(app.openFile(fullfile(thor, 'Experiment.xml'))));
    tests.verifyEqual(app.TimeVec(2), 1 / 30, 'AbsTol', 1e-9);
    tests.verifyEqual(double(app.Stack(:, :, 3)), double(st(:, :, 3)));
    % An ImageJ TIFF with a frame interval
    tf = fullfile(d, 'ij.tif');
    t = Tiff(tf, 'w');
    for k = 1:12
        if k > 1, t.writeDirectory(); end
        tags = struct('ImageLength', 16, 'ImageWidth', 20, 'Photometric', Tiff.Photometric.MinIsBlack, ...
            'BitsPerSample', 16, 'SamplesPerPixel', 1, 'PlanarConfiguration', Tiff.PlanarConfiguration.Chunky, ...
            'Compression', Tiff.Compression.None);
        if k == 1
            tags.ImageDescription = sprintf('ImageJ=1.54f\nimages=12\nframes=12\nunit=\\u00B5m\nfinterval=0.25\n');
            tags.XResolution = 2; tags.YResolution = 2; tags.ResolutionUnit = Tiff.ResolutionUnit.None;
        end
        t.setTag(tags);
        t.write(st(:, :, k));
    end
    t.close();
    tests.verifyTrue(logical(app.openFile(tf)));
    tests.verifyEqual(app.TimeVec(end), 11 * 0.25, 'AbsTol', 1e-9);
    M = tiffMeta(imfinfo(tf));
    tests.verifyEqual(M.pixelSizeUm, 0.5, 'AbsTol', 1e-9, 'ImageJ um written as \\u00B5m');
    % A UCLA Miniscope (V4) folder: two numbered videos, time stamps, metadata
    ms = fullfile(d, 'Miniscope'); mkdir(ms);
    for v = 0:1
        w = VideoWriter(fullfile(ms, sprintf('%d.avi', v)), 'Grayscale AVI');
        w.FrameRate = 30;
        open(w);
        for k = 1:6, writeVideo(w, uint8(st(:, :, v * 6 + k) / 10)); end
        close(w);
    end
    ts = 1000 + (0:11) * 33.4;                              % ms, not exactly 30 Hz
    fid = fopen(fullfile(ms, 'timeStamps.csv'), 'w');
    fprintf(fid, 'Frame Number,Time Stamp (ms),Buffer Index\n');
    fprintf(fid, '%d,%.1f,0\n', [0:11; ts]);
    fclose(fid);
    fid = fopen(fullfile(ms, 'metaData.json'), 'w');
    fprintf(fid, '{"deviceName": "Miniscope", "deviceType": "Miniscope_V4_BNO", "frameRate": "30FPS"}');
    fclose(fid);
    tests.verifyTrue(logical(app.openFile(fullfile(ms, '0.avi'))));
    tests.verifyEqual(nFrames(app), 12, 'both videos');
    tests.verifyEqual(app.TimeVec, (ts - ts(1)) / 1000, 'AbsTol', 1e-6, 'times from timeStamps.csv');
    shot(tests, app, 'ROIAnalysisApp_microscope_files');
end
