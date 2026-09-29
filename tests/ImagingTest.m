%% ImagingTest.m
% =========================================================================
% UNIT TESTS FOR core/imaging
% =========================================================================
% Synthetic stacks with known answers: ROI intensity, ΔF/F, movement on
% RGB (4-D) stacks, propagation speed of a moving spot, vessel diameter of
% a dark band, and edge-preserving smoothing of a constant image.
% =========================================================================

function tests = ImagingTest
    tests = functiontests(localfunctions);
end

%% setupOnce - Add toolbox root, core, and core/imaging to path
function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
end

function testRoiIntensityOverTime(tests)
    stack = zeros(10, 10, 4);
    for k = 1:4, stack(:, :, k) = k; end
    mask = false(10); mask(3:5, 3:5) = true;
    [I, t] = roiIntensityOverTime(stack, mask);
    verifyEqual(tests, I, 1:4, 'AbsTol', 1e-12);
    verifyEqual(tests, t, 1:4);
end

function testDeltaFOverF_first(tests)
    stack = 10 * ones(8, 8, 6);
    stack(:, :, 4:6) = 15;
    mask = true(8);
    dff = deltaFOverF(stack, mask, [], 'first', 3);
    verifyEqual(tests, dff, [0 0 0 0.5 0.5 0.5], 'AbsTol', 1e-9);
end

function testDeltaFOverF_percentile(tests)
    stack = reshape(repmat(1:10, 16, 1), 4, 4, 10);
    dff = deltaFOverF(stack, true(4), [], 'percentile', 0);
    verifyEqual(tests, dff(1), 0, 'AbsTol', 1e-9);
    verifyEqual(tests, dff(end), 9, 'AbsTol', 1e-9);
end

function testRoiMovement_varianceOnRgbStack(tests)
    stack = rand(6, 6, 3, 5);
    mask = true(6);
    [m, t] = roiMovement(stack, mask, [], 'variance');
    verifyEqual(tests, numel(m), 5);
    verifyEqual(tests, numel(t), 5);
    f = mean(stack(:, :, :, 2), 3);
    verifyEqual(tests, m(2), var(f(:)), 'AbsTol', 1e-12);
end

function testPropagationSpeed_allMethods(tests)
    ns = 80; nt = 20; v = 2;          % spot moves 2 px per frame
    x = (1:ns)';
    ky = zeros(ns, nt);
    for k = 1:nt
        ky(:, k) = exp(-(x - (15 + v * (k - 1))).^2 / (2 * 3^2));
    end
    verifyEqual(tests, propagationSpeedFromKymograph(ky, 'maxgrad'), v, 'RelTol', 0.1);
    verifyEqual(tests, propagationSpeedFromKymograph(ky, 'correlation'), v, 'AbsTol', 1e-9);
    verifyEqual(tests, propagationSpeedFromKymograph(ky, 'fit'), v, 'AbsTol', 1e-9);
end

function testVesselDiameter_darkBand(tests)
    stack = ones(40, 40, 3);
    stack(:, 16:25, :) = 0;           % vertical vessel, 10 px wide
    d1 = vesselDiameterFromLine(stack, [1 20], [40 20]);
    d2 = vesselDiameterFromLine(stack, [1 20 40 20], []);   % [x1 y1 x2 y2] form
    verifyEqual(tests, d1, 10 * ones(1, 3), 'AbsTol', 1.5);
    verifyEqual(tests, d2, d1);
end

function testImageStackSmooth_constantPreserved(tests)
    stack = 7 * ones(12, 12, 2);
    out = imageStackSmooth(stack, 2, 'gaussian');
    verifyEqual(tests, out, stack, 'AbsTol', 1e-9);
end

function testImageStackNormalize_percentileRange(tests)
    stack = reshape(0:99, 10, 10, 1);
    out = imageStackNormalize(stack, 'percentile', [0 100]);
    verifyEqual(tests, min(out(:)), 0, 'AbsTol', 1e-9);
    verifyEqual(tests, max(out(:)), 1, 'AbsTol', 1e-9);
end

%% testFlowSpeedIsFrameDifference - roiFlowSpeed is not a speed: it equals Movement 'diff'
% (the reason "Speed (flow)" was removed from ROI Analysis)
function testFlowSpeedIsFrameDifference(tests)
    rs = RandStream('mt19937ar', 'Seed', 7);
    stack = rand(rs, 12, 12, 6);
    mask = false(12); mask(3:9, 4:10) = true;
    verifyEqual(tests, roiFlowSpeed(stack, mask), roiMovement(stack, mask, [], 'diff'), 'AbsTol', 1e-12);
end
