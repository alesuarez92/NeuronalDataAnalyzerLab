%% ImagingFeaturesTest.m
% =========================================================================
% UNIT TESTS: MOTION CORRECTION, CELL DETECTION, ROBUST VESSEL DIAMETER
% =========================================================================
% Checks the imaging algorithms against known ground truth:
%   * registerStackRigid recovers the sub-pixel jitter of the advanced
%     demo stack (core/demo/demoImagingAdvanced) and of a Fourier-shifted
%     image;
%   * vesselDiameterFromLine locates the walls to sub-pixel precision on
%     synthetic profiles, and 'Robust' removes the spikes caused by a red
%     blood cell crossing the diameter line;
%   * robustTimeSeries (Hampel filter) flags exactly the injected spikes;
%   * localCorrelationImage + detectCellsFromCorrelation find the three
%     demo cells, and per-cell dF/F peaks at each cell's own event times.
% =========================================================================

function tests = ImagingFeaturesTest
    tests = functiontests(localfunctions);
end

%% setupOnce - Paths, the advanced demo (with and without jitter) and its registration
function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.demo = demoImagingAdvanced();
    tests.TestData.still = demoImagingAdvanced(struct('Jitter', false));
    [tests.TestData.reg, tests.TestData.shifts, tests.TestData.regInfo] = ...
        registerStackRigid(tests.TestData.demo.stack, 'mean');
    % Border pixels within the largest shift are edge copies after correction
    tests.TestData.margin = ceil(max(abs(tests.TestData.shifts(:))));
end

%% --- Demo generator ------------------------------------------------------

function testAdvancedDemoTruth(tests)
    s = tests.TestData.demo;
    verifyEqual(tests, size(s.stack), [96 96 150]);
    verifyEqual(tests, size(s.truth.shifts), [150 2]);
    verifyLessThanOrEqual(tests, max(abs(s.truth.shifts(:))), 3 + 1e-9);
    verifyEqual(tests, mean(s.truth.shifts, 1), [0 0], 'AbsTol', 1e-9);
    verifyEqual(tests, size(s.truth.cellMasks, 3), 3);
    verifyNotEmpty(tests, s.truth.rbcCrossFrames);
    % Deterministic
    s2 = demoImagingAdvanced();
    verifyEqual(tests, s2.stack(:, :, 10), s.stack(:, :, 10));
end

%% --- Motion correction ---------------------------------------------------

function testRegistrationRecoversDemoShifts(tests)
    truth = tests.TestData.demo.truth.shifts;
    % 'mean' reference: frames registered onto their average position,
    % which is the motion-free scene because the simulated jitter has zero mean
    err = tests.TestData.shifts - truth;
    verifyLessThan(tests, max(abs(err(:))), 0.3);
end

function testRegistrationToFrameOne(tests)
    % A single noisy frame is a weaker reference than the mean: looser bound
    s = tests.TestData.demo;
    [~, sh] = registerStackRigid(s.stack, 1);
    err = sh - (s.truth.shifts - s.truth.shifts(1, :));
    verifyLessThan(tests, max(abs(err(:))), 0.4);
    verifyEqual(tests, sh(1, :), [0 0], 'AbsTol', 0.05);
end

function testRegistrationValidMask(tests)
    v = tests.TestData.regInfo.validMask;
    sh = tests.TestData.shifts;
    verifyEqual(tests, size(v), [96 96]);
    verifyEqual(tests, nnz(any(v, 2)), numel(max(1, ceil(1 - min(sh(:, 1)))):min(96, floor(96 - max(sh(:, 1))))));
    verifyTrue(tests, v(48, 48));
    verifyFalse(tests, v(1, 1));
end

function testRegistrationAlignsTheScene(tests)
    % After correction, the stack matches the jitter-free stack far better
    still = double(tests.TestData.still.stack);
    inner = 8:89;                                  % away from the borders
    before = double(tests.TestData.demo.stack(inner, inner, :)) - still(inner, inner, :);
    after = tests.TestData.reg(inner, inner, :) - still(inner, inner, :);
    verifyLessThan(tests, sqrt(mean(after(:).^2)), 0.5 * sqrt(mean(before(:).^2)));
end

function testRegistrationFourierShiftAndOptions(tests)
    % Smooth periodic image shifted by a known sub-pixel amount in the Fourier domain
    rs = RandStream('mt19937ar', 'Seed', 7);
    n = 64;
    f = ifftshift((0:n-1) - n / 2) / n;
    [FX, FY] = meshgrid(f, f);
    A = fft2(randn(rs, n)) .* exp(-2 * pi^2 * 2^2 * (FX.^2 + FY.^2));
    d = [1.3 -2.6];
    img1 = real(ifft2(A));
    img2 = real(ifft2(A .* exp(-1i * 2 * pi * (FY * d(1) + FX * d(2)))));
    stack = cat(3, img1, img2);
    [reg, sh, info] = registerStackRigid(stack, 1, struct('Apply', 'fft', 'Taper', 0));
    verifyEqual(tests, sh(2, :), d, 'AbsTol', 0.1);
    verifyLessThan(tests, max(abs(reg(:, :, 2) - img1), [], 'all'), 0.05 * max(abs(img1(:))));
    verifyEqual(tests, numel(info.peak), 2);
    % Parabolic fit, name-value options and RGB (H x W x 3 x N) input
    rgb = permute(repmat(stack, 1, 1, 1, 3), [1 2 4 3]);
    [regRGB, sh2] = registerStackRigid(rgb, 1, 'PeakFit', 'parabolic', 'Taper', 0);
    verifyEqual(tests, size(regRGB), size(rgb));
    verifyEqual(tests, sh2(2, :), d, 'AbsTol', 0.2);
end

%% --- Vessel diameter -----------------------------------------------------

function testSubPixelDiameterOnSyntheticProfiles(tests)
    % Dark vessel with soft walls; half-depth width = true diameter
    [X, ~] = meshgrid(1:96, 1:96);
    ds = 6:0.37:18;
    err = zeros(size(ds)); errRobust = err; errLegacy = err;
    for i = 1:numel(ds)
        v = 1 ./ (1 + exp((abs(X - 60.3) - ds(i) / 2) / 0.8));
        frame = 0.6 * (1 - 0.7 * v);
        err(i) = vesselDiameterFromLine(frame, [35 50], [85 50]) - ds(i);
        errRobust(i) = vesselDiameterFromLine(frame, [35 50], [85 50], [], 'fwhm', 'Robust', true) - ds(i);
        errLegacy(i) = vesselDiameterFromLine(frame, [35 50], [85 50], [], 'fwhm', 'SubPixel', false) - ds(i);
    end
    verifyLessThan(tests, max(abs(err)), 0.5);
    verifyLessThan(tests, max(abs(errRobust)), 0.5);
    % Sample counting is quantised: sub-pixel is clearly better
    verifyLessThan(tests, max(abs(err)), max(abs(errLegacy)));
end

function testSubPixelDiameterDiagonalAndBright(tests)
    [X, Y] = meshgrid(1:96, 1:96);
    dist = abs((X - 48) + (Y - 48)) / sqrt(2);      % distance to a 45-degree vessel axis
    v = 1 ./ (1 + exp((dist - 10.6 / 2) / 0.8));
    verifyEqual(tests, vesselDiameterFromLine(0.6 * (1 - 0.7 * v), [30 30], [66 66]), 10.6, 'AbsTol', 0.5);
    % Fluorescent (bright) lumen
    verifyEqual(tests, vesselDiameterFromLine(0.2 + 0.7 * v, [30 30], [66 66], [], 'fwhm', ...
        'Polarity', 'bright'), 10.6, 'AbsTol', 0.5);
end

function testRobustDiameterRemovesRbcSpikes(tests)
    s = tests.TestData.still;                      % no jitter: truth is exact
    tr = s.truth;
    cross = tr.rbcCrossFrames;
    plain = vesselDiameterFromLine(s.stack, tr.lineStart, tr.lineEnd, s.timeVec, 'fwhm');
    [robust, ~, ~, isOut, info] = vesselDiameterFromLine(s.stack, tr.lineStart, tr.lineEnd, ...
        s.timeVec, 'fwhm', 'Robust', true);
    % Without robust levels the RBC makes the width jump by > 10 px ...
    verifyGreaterThan(tests, max(abs(plain(cross) - tr.diameter(cross))), 10);
    % ... with them the error stays small in every frame (what remains
    % comes from the background texture, as in frames without the RBC)
    verifyLessThan(tests, max(abs(robust - tr.diameter)), 2.5);
    verifyLessThan(tests, sqrt(mean((robust - tr.diameter).^2)), 1);
    verifyTrue(tests, all(isfinite(robust)));
    verifyTrue(tests, islogical(isOut) && numel(isOut) == numel(robust));
    verifyEqual(tests, size(info.edges), [numel(robust) 2]);
    % Frames where the RBC fills the lumen on the line give no width and
    % are filled in by the temporal filter
    verifyTrue(tests, any(isOut(cross)));
    verifyTrue(tests, any(isnan(info.rawDiameter(cross))));
end

function testRobustDiameterAfterMotionCorrection(tests)
    tr = tests.TestData.demo.truth;
    d = vesselDiameterFromLine(tests.TestData.reg, tr.lineStart, tr.lineEnd, [], 'Robust', true);
    verifyLessThan(tests, max(abs(d - tr.diameter)), 2.5);
    % Averaging parallel lines gives the same answer
    d3 = vesselDiameterFromLine(tests.TestData.reg, tr.lineStart, tr.lineEnd, [], 'Robust', true, 'LineWidth', 3);
    verifyLessThan(tests, max(abs(d3 - tr.diameter)), 2.5);
end

function testVesselDiameterLegacyForms(tests)
    stack = ones(40, 40, 3);
    stack(:, 16:25, :) = 0;                        % 10 px dark band
    verifyEqual(tests, vesselDiameterFromLine(stack, [1 20], [40 20], [], 'threshold'), 9 * ones(1, 3));
    verifyEqual(tests, vesselDiameterFromLine(stack, [1 20 40 20], [], [], 'fwhm', 'SubPixel', false), ...
        9 * ones(1, 3));
    d = vesselDiameterFromLine(stack, [1 20], [40 20], 'Robust', true);   % options right after the line
    verifyEqual(tests, d, 10 * ones(1, 3), 'AbsTol', 0.5);
end

%% --- Hampel filter -------------------------------------------------------

function testRobustTimeSeriesFlagsSpikes(tests)
    x = 10 + sin(2 * pi * (1:100) / 50);
    spikes = [20 55 56 80];
    x(spikes) = x(spikes) + [8 -6 -6 12];
    x(90) = NaN;
    [y, isOut] = robustTimeSeries(x, 7, 3);
    verifyEqual(tests, find(isOut), sort([spikes 90]));
    clean = 10 + sin(2 * pi * (1:100) / 50);
    verifyEqual(tests, y, clean, 'AbsTol', 0.3);      % replaced by the local median
    % A clean smooth series is left untouched
    [y2, isOut2] = robustTimeSeries(clean);
    verifyFalse(tests, any(isOut2));
    verifyEqual(tests, y2, clean);
end

%% --- Correlation image and cell detection --------------------------------

function testLocalCorrelationImage(tests)
    rs = RandStream('mt19937ar', 'Seed', 11);
    n = 200;
    stack = 0.1 * randn(rs, 30, 30, n);
    common = reshape(randn(rs, 1, n), 1, 1, n);
    stack(11:18, 11:18, :) = stack(11:18, 11:18, :) + common;   % coherent patch
    stack(1:3, 25:30, :) = 5;                                     % constant pixels
    C = localCorrelationImage(stack);
    verifyGreaterThan(tests, min(C(12:17, 12:17), [], 'all'), 0.9);
    bg = C(21:28, 3:10);
    verifyLessThan(tests, abs(mean(bg(:))), 0.05);
    verifyEqual(tests, C(2, 27), 0);
    verifyLessThanOrEqual(tests, max(abs(C(:))), 1 + 1e-12);
end

function testDetectCellsFindsDemoCells(tests)
    tr = tests.TestData.demo.truth;
    C = localCorrelationImage(tests.TestData.reg);
    [masks, props] = detectCellsFromCorrelation(C, 'BorderMargin', tests.TestData.margin);
    verifyEqual(tests, numel(masks), 3, 'expected the three simulated cells only');
    cents = reshape([props.centroid], 2, []).';
    for i = 1:3
        verifyLessThan(tests, min(vecnorm(cents - tr.cellCenters(i, :), 2, 2)), 3, sprintf('cell %d', i));
    end
    % Toolbox-free labelling gives the same cells
    masks2 = detectCellsFromCorrelation(C, 'UseToolbox', false, 'BorderMargin', tests.TestData.margin);
    verifyEqual(tests, numel(masks2), numel(masks));
    for k = 1:numel(masks)
        verifyEqual(tests, masks2{k}, masks{k});
    end
end

function testMultiRoiDffPeaksAtEventTimes(tests)
    s = tests.TestData.demo;
    tr = s.truth;
    t = s.timeVec;
    [masks, props] = detectCellsFromCorrelation(localCorrelationImage(tests.TestData.reg), ...
        'BorderMargin', tests.TestData.margin);
    cents = reshape([props.centroid], 2, []).';
    for i = 1:3
        [~, j] = min(vecnorm(cents - tr.cellCenters(i, :), 2, 2));
        dff = deltaFOverF(tests.TestData.reg, masks{j}, t, 'first', 30);
        quiet = true(size(t));
        for e = tr.eventTimes{i}
            win = t >= e - 0.5 & t <= e + 1.5;
            [pk, iPk] = max(dff(win));
            tw = t(win);
            verifyEqual(tests, tw(iPk), e, 'AbsTol', 0.5, sprintf('cell %d event %.1f s', i, e));
            verifyGreaterThan(tests, pk, 0.2);
            quiet(t >= e - 0.2 & t <= e + 4) = false;
        end
        % No cross-talk: flat at the other cells' events
        verifyLessThan(tests, max(abs(dff(quiet))), 0.1, sprintf('cell %d outside its events', i));
    end
end
