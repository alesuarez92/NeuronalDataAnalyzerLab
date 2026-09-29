%% HistologyTest.m
% =========================================================================
% UNIT TESTS: CELL COUNTING, CO-LOCALISATION AND ALIGNMENT (core/Histology)
% =========================================================================
% Checks the histology / culture algorithms against the known answers of
% the demo (core/demo/demoHistology: 60 nuclei including 6 touching pairs,
% 24 / 39 marker-positive cells on day 1 / day 3, 20 specks of debris and
% a fibre that must not be counted, day 3 shifted by [6.4 -9.2] px,
% channel 2 by [1 2] px) and on small hand-made masks:
%   * labelComponents (8-connectivity), fillHoles, otsu;
%   * countCells: exact count on both days, touching pairs split, debris
%     rejected as too small and the fibre as elongated, cells within 1 px
%     of the true centres; without splitting the pairs count as one;
%   * positive: exact marker-positive cells on both days;
%   * alignImagesRigid recovers the stage shift, alignChannels the
%     chromatic shift; after alignment the counts per region are exact;
%   * fitAffine / warpAffine: exact for an affine map, error for too few
%     or collinear landmarks;
%   * readImage: multi-page TIFF (pages = channels), .mat with images.
% Base MATLAB only: also runs in GNU Octave (with a RandStream shim).
% =========================================================================

function tests = HistologyTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'demo'));
    s = demoHistology();
    tests.TestData.demo = s;
    for k = 1:2
        ch = double(s.images(:, :, 1, k));
        R{k} = Histology.countCells(ch, struct('MinAreaPx', 20)); %#ok<AGROW>
    end
    tests.TestData.R = R;
end

%% match - Index of the nearest true centre for each counted cell, and distance
function [idx, d] = match(R, centers, shift)
    c = centers + [shift(2) shift(1)];
    D = hypot(R.centroid(:, 1) - c(:, 1)', R.centroid(:, 2) - c(:, 2)');
    [d, idx] = min(D, [], 2);
end

%% --- Building blocks ------------------------------------------------------

function testLabelComponents(tests)
    m = logical([1 0 0 1; 0 1 0 1; 0 0 0 0; 1 1 0 1]);
    [L, n] = Histology.labelComponents(m);
    verifyEqual(tests, n, 4);                           % diagonal pixels join (8-connected)
    verifyEqual(tests, L(1, 1), L(2, 2));
    verifyEqual(tests, numel(unique(L(m))), 4);
    verifyEqual(tests, nnz(L), nnz(m));
    [~, n0] = Histology.labelComponents(false(5));
    verifyEqual(tests, n0, 0);
end

function testFillHoles(tests)
    m = false(7); m(2:6, 2:6) = true; m(4, 4) = false;
    filled = m; filled(4, 4) = true;
    verifyEqual(tests, Histology.fillHoles(m), filled);
    open = false(5); open(1:3, 1:3) = true; open(2, 1) = false;   % touches the border: not a hole
    verifyEqual(tests, Histology.fillHoles(open), open);
end

function testOtsuSeparatesTwoLevels(tests)
    v = [zeros(1, 500), ones(1, 100)] + 0.01 * sin(1:600);
    t = Histology.otsu(v);
    verifyGreaterThan(tests, t, 0.05);
    verifyLessThan(tests, t, 0.95);
end

%% --- Counting --------------------------------------------------------------

function testCountsEveryNucleusOnBothDays(tests)
    s = tests.TestData.demo;
    for k = 1:2
        R = tests.TestData.R{k};
        verifyEqual(tests, R.n, s.truth.nCells, sprintf('day %d', 2 * k - 1));
        [idx, d] = match(R, s.truth.centers, s.truth.shifts(k, :));
        verifyLessThan(tests, max(d), 1, 'every cell within 1 px of a true centre');
        verifyEqual(tests, numel(unique(idx)), s.truth.nCells, 'each true nucleus counted once');
    end
end

function testTouchingPairsAreSplit(tests)
    s = tests.TestData.demo;
    R = tests.TestData.R{1};
    verifyEqual(tests, R.nSplit, max(s.truth.pairId));
    noSplit = Histology.countCells(double(s.images(:, :, 1, 1)), struct('MinAreaPx', 20, 'Split', false));
    verifyEqual(tests, noSplit.n, s.truth.nCells - max(s.truth.pairId));
end

function testDebrisAndFibreRejected(tests)
    s = tests.TestData.demo;
    R = tests.TestData.R{1};
    verifyEqual(tests, R.nRejected.tooSmall, size(s.truth.debrisXY, 1));
    verifyEqual(tests, R.nRejected.elongated, 1);
    verifyEqual(tests, R.nRejected.tooLarge, 0);
    verifyTrue(tests, R.thresholdAuto);
    verifyGreaterThanOrEqual(tests, R.threshold, R.noiseFloor);
    % A lower size limit lets the debris in
    loose = Histology.countCells(double(s.images(:, :, 1, 1)), struct('MinAreaPx', 2));
    verifyGreaterThan(tests, loose.n, R.n);
end

function testManualThreshold(tests)
    s = tests.TestData.demo;
    R = Histology.countCells(double(s.images(:, :, 1, 1)), struct('MinAreaPx', 20, 'Threshold', 0.3));
    verifyFalse(tests, R.thresholdAuto);
    verifyEqual(tests, R.threshold, 0.3);
    verifyEqual(tests, R.n, s.truth.nCells);
end

function testMarkerPositiveCells(tests)
    s = tests.TestData.demo;
    for k = 1:2
        R = tests.TestData.R{k};
        P = Histology.positive(R.L, double(s.images(:, :, 2, k)));
        idx = match(R, s.truth.centers, s.truth.shifts(k, :));
        verifyEqual(tests, P.nPositive, s.truth.nPositive(k));
        verifyEqual(tests, P.isPositive, s.truth.positive(idx, k));
    end
end

%% --- Alignment and regions -------------------------------------------------

function testAlignImagesAndCountPerRegion(tests)
    s = tests.TestData.demo;
    imgs = {double(s.images(:, :, :, 1)), double(s.images(:, :, :, 2))};
    [al, sh] = Histology.alignImagesRigid(imgs, 1);
    verifyEqual(tests, sh(2, :), s.truth.shifts(2, :), 'AbsTol', 0.2);
    R = Histology.countCells(al{2}(:, :, 1), struct('MinAreaPx', 20));
    P = Histology.positive(R.L, al{2}(:, :, 2));
    S = Histology.regionCounts(R, {P}, s.truth.regions, s.pixelSizeUm);
    for r = 1:2
        verifyEqual(tests, S(r).nCells, s.truth.counts(r).nCells, S(r).name);
        verifyEqual(tests, S(r).nPositive, s.truth.counts(r).nPositive(2), S(r).name);
        verifyEqual(tests, S(r).areaMm2, s.truth.counts(r).areaMm2, 'RelTol', 1e-9);
        verifyEqual(tests, S(r).perMm2, s.truth.counts(r).perMm2, 'RelTol', 1e-9);
    end
    % The answers given in Help: 12 + 12 positive on day 1, 18 + 21 on day 3
    verifyEqual(tests, reshape([s.truth.counts.nPositive], 2, 2)', [12 18; 12 21]);
    whole = Histology.regionCounts(R, {P}, [], s.pixelSizeUm);
    verifyEqual(tests, whole.nCells, s.truth.nCells);
    verifyEqual(tests, whole.areaMm2, 0.16, 'RelTol', 1e-9);
end

function testAlignImagesSizeMismatch(tests)
    verifyError(tests, @() Histology.alignImagesRigid({zeros(20, 20), zeros(20, 30)}, 1), ...
        'NeuroAnalyzer:Histology:sizeMismatch');
end

function testAlignChannelsRecoversChromaticShift(tests)
    s = tests.TestData.demo;
    [al, sh] = Histology.alignChannels(double(s.images(:, :, :, 1)), 1);
    verifyEqual(tests, sh(1, :), [0 0]);
    verifyEqual(tests, sh(2, :), s.truth.chromaticShift, 'AbsTol', 0.75);
    verifyEqual(tests, size(al), size(s.images(:, :, :, 1)));
end

function testAffineFromLandmarks(tests)
    th = 0.06;
    A = [cos(th) -sin(th); sin(th) cos(th)] * 1.03;
    fixed = [50 60; 300 80; 200 320; 90 250];
    moving = fixed * A' + [5 -7];
    [M, rms] = Histology.fitAffine(moving, fixed);
    verifyLessThan(tests, rms, 1e-9);
    % Warping a smooth image with the transform matches the direct formula
    [X, Y] = meshgrid(1:120, 1:100);
    img = sin(X / 9) + cos(Y / 7);
    w = Histology.warpAffine(img, [1 0; 0 1; 2.5 -1.5]);   % pure shift
    verifyEqual(tests, w(20:80, 20:100), sin((X(20:80, 20:100) + 2.5) / 9) + cos((Y(20:80, 20:100) - 1.5) / 7), ...
        'AbsTol', 0.01);
    verifyError(tests, @() Histology.fitAffine(moving(1:2, :), fixed(1:2, :)), 'NeuroAnalyzer:Histology:landmarks');
    verifyError(tests, @() Histology.fitAffine([1 1; 2 2; 3 3], [1 1; 2 2; 3 3]), 'NeuroAnalyzer:Histology:collinear');
end

%% --- Loading ----------------------------------------------------------------

function testReadMultiPageTiff(tests)
    s = tests.TestData.demo;
    f = [tempname '.tif'];
    c = onCleanup(@() delete(f));
    a = uint16(1000 * s.images(:, :, 1, 1));
    b = uint16(1000 * s.images(:, :, 2, 1));
    imwrite(a, f);
    imwrite(b, f, 'WriteMode', 'append');
    [img, info] = Histology.readImage(f);
    verifyEqual(tests, size(img), [400 400 2]);
    verifyEqual(tests, img(:, :, 2), double(b));
    verifyEqual(tests, info.channelNames, {'Channel 1', 'Channel 2'});
    verifyEmpty(tests, info.pixelSizeUm);
end

function testReadMatWithImages(tests)
    s = tests.TestData.demo;
    f = [tempname '.mat'];
    c = onCleanup(@() delete(f));
    save(f, '-struct', 's');
    [img, info] = Histology.readImage(f);
    verifyEqual(tests, size(img), [400 400 2 2]);
    verifyEqual(tests, info.channelNames, s.channelNames);
    verifyEqual(tests, info.imageNames, s.imageNames);
    verifyEqual(tests, info.pixelSizeUm, 1);
    verifyEqual(tests, info.truth.nCells, 60);
end

function testPixelSizeFromImageJTiff(tests)
    fi = struct('XResolution', 2, 'ResolutionUnit', 'None', 'ImageDescription', sprintf('ImageJ=1.54\nunit=micron\n'));
    verifyEqual(tests, Histology.pixelSizeFromTiff(fi), 0.5);
    fi = struct('XResolution', 10000, 'ResolutionUnit', 'Centimeter');
    verifyEqual(tests, Histology.pixelSizeFromTiff(fi), 1);
    fi = struct('XResolution', 72, 'ResolutionUnit', 'Inch');
    verifyEmpty(tests, Histology.pixelSizeFromTiff(fi));
end
