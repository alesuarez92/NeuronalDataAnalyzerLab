%% ScalpMapTest.m
% =========================================================================
% UNIT TESTS FOR SCALP MAPS (core/ScalpMap.m)
% =========================================================================
% Spherical splines checked against Perrin et al. (1989): g(x) as the
% Legendre series, exact values at the electrodes, a smooth dipolar field
% reproduced between the 32 electrodes of the demo, smoothing (lambda) and
% coincident electrodes; thin-plate
% splines against scipy 1.x RBFInterpolator ('thin_plate_spline', degree
% 1); exact values at the electrodes, constants and planes kept; the
% demo's known scalp distributions (P300 at Pz, N1 at Cz) recovered
% between the electrodes and found where they are in the demo study; the
% rodent VEP over V1 on a flat skull map drawn only inside the electrodes;
% channel matching, left-out channels, colour limits, drawing and errors.
% =========================================================================

function tests = ScalpMapTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.tmp = fullfile(tempdir, ['NeuroAnalyzerScalpMapTest_' char(java.util.UUID.randomUUID)]);
    mkdir(tests.TestData.tmp);
    tests.TestData.demo = demoEEG(fullfile(tests.TestData.tmp, 'demo'), 'Participants', 3, ...
        'Kinds', {'scalp', 'rodent'}, 'Formats', {'eeglab'});
end

function teardownOnce(tests)
    if exist(tests.TestData.tmp, 'dir') == 7, rmdir(tests.TestData.tmp, 's'); end
end

%% --------------------------------------------------- Perrin et al. (1989) and scipy

function testSphericalSplinePerrin(tests)
    % g(x) = 1/(4 pi) sum_{n=1..50} (2n + 1) / (n (n + 1))^4 P_n(x), P_n from Bonnet's recurrence
    x = linspace(-1, 1, 401)';
    p0 = ones(size(x));
    p1 = x;
    g = 3 / 2 ^ 4 * p1;
    for n = 2:50
        p2 = ((2 * n - 1) * x .* p1 - (n - 1) * p0) / n;
        g = g + (2 * n + 1) / (n * (n + 1)) ^ 4 * p2;
        p0 = p1;
        p1 = p2;
    end
    verifyEqual(tests, ScalpMap.gFunction(x, 4, 50), g / (4 * pi), 'AbsTol', 1e-15);
    verifyEqual(tests, ScalpMap.gFunction(1, 1, 1), 3 / 2 / (4 * pi), 'AbsTol', 1e-15, 'one term: 3 / 2 P_1(1) / 4 pi');
    % A smooth field (a dipole 0.3 radii deep under the vertex, tilted, as on a
    % spherical head), average-referenced: between the electrodes over the cap
    [u, ~, labels] = demoPositions();
    r0 = [0.05 0 0.3];
    p = [0.3 0.2 1];
    dip = @(e) ((e - r0) * p') ./ sum((e - r0) .^ 2, 2) .^ 1.5;
    ref = mean(dip(u));
    [A, E] = meshgrid(-180:5:175, 0:5:85);
    to = azelVectors([A(:), E(:)]);
    est = ScalpMap.sphericalSpline(u, dip(u) - ref, to);
    err = max(abs(est - (dip(to) - ref))) / max(abs(dip(u) - ref));
    verifyLessThan(tests, err, 0.03, sprintf('dipolar field: largest error %.3f of the peak', err));
    % ... and at each inner electrode left out in turn
    worst = 0;
    for k = find(u(:, 3) > 0.3)'
        keep = setdiff(1:numel(labels), k);
        worst = max(worst, abs(ScalpMap.sphericalSpline(u(keep, :), dip(u(keep, :)), u(k, :)) - dip(u(k, :))));
    end
    verifyLessThan(tests, worst / max(abs(dip(u) - ref)), 0.05, 'leave-one-out');
    % Smoothing (Perrin's lambda) moves the map off the electrodes, towards a flatter map
    [u, v] = demoPositions();
    s = ScalpMap.sphericalSpline(u, v, u, 'Lambda', 1e-3);
    verifyGreaterThan(tests, max(abs(s - v)), 1e-3);
    verifyLessThan(tests, max(abs(s)), max(abs(v)));
    % Two electrodes at the same place: the map takes their mean there
    o = ScalpMap.sphericalSpline([u; u(14, :)], [v; v(14) + 0.1], u(14, :));
    verifyEqual(tests, o, v(14) + 0.05, 'AbsTol', 1e-6);
    % positions need not be unit vectors; values as a row
    to = azelVectors([180 67.5; 0 67.5; 45 22; -100 -10]);
    verifyEqual(tests, ScalpMap.sphericalSpline(85 * u, v', 2 * to), ScalpMap.sphericalSpline(u, v, to), 'AbsTol', 1e-12);
end

function testThinPlateAsScipy(tests)
    % scipy.interpolate.RBFInterpolator(xy, v, kernel='thin_plate_spline', degree=1)(to)
    xy = [-1.5 1; 1.5 1; -2.5 -3.5; 2.5 -3.5];
    to = [0 0; 0 -2; -1 -1; 1.2 -3; 0.3 0.5];
    verifyEqual(tests, ScalpMap.thinPlate(xy, [-12; -11; -40; -38], to), ...
        [-17.611111111111; -29.833333333333; -24.086506777313; -35.46706258679; -14.455708306207], 'AbsTol', 1e-9);
    xy = [0 0; 1 0; 0 1; 1 1; 0.5 0.3; 2 1.5];
    verifyEqual(tests, ScalpMap.thinPlate(xy, [1 2 -1 0.5 3 -2], [0.2 0.7; 1.5 0.9; 0.9 0.1]), ...
        [0.882703988213; 0.171871730806; 2.301951051091], 'AbsTol', 1e-9);
end

%% --------------------------------------------------- Properties

function testExactConstantsAndPlanes(tests)
    [u, v] = demoPositions();
    verifyEqual(tests, ScalpMap.sphericalSpline(u, v, u), v, 'AbsTol', 1e-9, 'passes through every electrode');
    to = azelVectors([0 30; 77 12; -150 50; 10 89]);
    verifyEqual(tests, ScalpMap.sphericalSpline(u, 5 * ones(32, 1), to), 5 * ones(4, 1), 'AbsTol', 1e-9, ...
        'a constant stays constant');
    two = ScalpMap.sphericalSpline(u, [v, -2 * v], to);
    verifyEqual(tests, two, [1 -2] .* ScalpMap.sphericalSpline(u, v, to), 'AbsTol', 1e-12, 'several maps at once');
    seven = ScalpMap.sphericalSpline(u, v, to, 'Terms', 7);    % 7 Legendre terms instead of 50
    verifyEqual(tests, seven, ScalpMap.sphericalSpline(u, v, to), 'AbsTol', 0.03 * max(abs(v)));
    xy = [0 0; 3 0; 0 2; 3 2; 1.2 0.7; -1 1.5];
    to = [0.5 0.5; 2.5 1.9; -0.5 1; 1.5 1.5];
    plane = @(p) 2 + 3 * p(:, 1) - p(:, 2);
    verifyEqual(tests, ScalpMap.thinPlate(xy, plane(xy), to), plane(to), 'AbsTol', 1e-9, 'a plane stays a plane');
    verifyEqual(tests, ScalpMap.thinPlate(xy, [1; -2; 0.5; 4; 0; 2], xy), [1; -2; 0.5; 4; 0; 2], 'AbsTol', 1e-9);
end

function testKnownScalpDistribution(tests)
    % The demo's P300 (Gaussian over Pz, 0.8 rad) and N1 (over Cz, 0.6 rad),
    % average-referenced, from the 32 electrodes: between them, over the cap
    [u, ~, labels] = demoPositions();
    [A, E] = meshgrid(-180:6:174, -10:6:88);
    to = azelVectors([A(:), E(:)]);
    for c = {{'Pz', 0.8, 0.02}, {'Cz', 0.6, 0.05}}
        [name, sig, tol] = c{1}{:};
        f = @(p) exp(-(acos(max(-1, min(1, p * u(strcmp(labels, name), :)'))) / sig) .^ 2);
        ref = mean(f(u));
        est = ScalpMap.sphericalSpline(u, f(u) - ref, to);
        err = max(abs(est - (f(to) - ref))) / max(abs(f(u) - ref));
        verifyLessThan(tests, err, tol, sprintf('%s: largest error %.3f of the peak', name, err));
    end
    % As a map: the largest value lies on Pz
    L = struct('kind', 'scalp', 'labels', {labels}, 'pos', [-u(:, 2), u(:, 1), u(:, 3)]);   % x right, y nose
    pz = u(strcmp(labels, 'Pz'), :);
    v = exp(-(acos(max(-1, min(1, u * pz'))) / 0.8) .^ 2);
    M = ScalpMap.make(L, v - mean(v));
    verifyEqual(tests, M.method, 'spherical spline');
    verifyEqual(tests, M.radius, 1.2, 'AbsTol', 1e-9, 'out to TP9 / PO9, 18 deg below the head line');
    verifySize(tests, M.z, [101 101]);
    verifyTrue(tests, isnan(M.z(1, 1)), 'corners are outside the head');
    [~, i] = max(M.z(:));
    [r, k] = ind2sub(size(M.z), i);
    xy = EEGLayout.project(L);
    verifyEqual(tests, [M.x(k) M.y(r)], xy(strcmp(labels, 'Pz'), :), 'AbsTol', 0.03);
    verifyEqual(tests, M.values, v - mean(v), 'AbsTol', 1e-12);
    verifyEmpty(tests, M.left);
    verifyTrue(tests, startsWith(ScalpMap.describe(M), 'Spherical spline over the head (m = 4, 50 Legendre terms) from 32 electrodes'));
end

%% --------------------------------------------------- The demo study

function testDemoStudyMaps(tests)
    d = tests.TestData.demo;
    erps = cell(1, 3);
    for p = 1:3
        eeg = readEEGLAB(d.scalp(p).eeglab);
        erps{p} = EEGAnalysis.conditionERPs(eeg, 'Baseline', [-0.2 0]);
    end
    ga = EEGAnalysis.grandAverage(erps);
    L = EEGLayout.fromEEG(readEEGLAB(d.scalp(1).eeglab));
    xy = EEGLayout.project(L);
    at = @(name) xy(strcmp(L.labels, name), :);
    % P300: Target 300-400 ms largest over Pz, also in Target minus Standard
    M = ScalpMap.make(L, EEGAnalysis.windowMean(ga, [0.3 0.4], 'Target'), 'Labels', ga.labels);
    verifyLessThan(tests, norm(peakAt(M, 'max') - at('Pz')), 0.15, 'P300 maximum near Pz');
    [~, i] = max(M.values);
    verifyEqual(tests, M.labels{i}, 'Pz');
    D = ScalpMap.make(L, EEGAnalysis.windowMean(ga, [0.3 0.4], 'Target', 'Standard'), 'Labels', ga.labels);
    verifyLessThan(tests, norm(peakAt(D, 'max') - at('Pz')), 0.15, 'Target minus Standard largest near Pz');
    verifyGreaterThan(tests, max(D.values), 3, 'about 5.5 uV at Pz after the average reference');
    % N1: Standard at 100 ms most negative over Cz
    N = ScalpMap.make(L, EEGAnalysis.windowMean(ga, [0.1 0.1], 'Standard'), 'Labels', ga.labels);
    verifyLessThan(tests, norm(peakAt(N, 'min') - at('Cz')), 0.15, 'N1 minimum near Cz');
    lim = ScalpMap.limits([M D N]);
    verifyEqual(tests, lim(2), -lim(1));
    verifyEqual(tests, lim(2), max(abs([M.range D.range N.range])));
end

function testSkullFlatMap(tests)
    d = tests.TestData.demo;
    L = EEGLayout.fromEEG(readEEGLAB(d.rodent.eeglab));
    verifyEqual(tests, L.kind, 'skull');
    % The VEP trough at 50 ms: -40 uV over V1, 30% of it over M1 (demoEEG)
    v = -40 * [0.3 0.3 1 1];
    M = ScalpMap.make(L, v);
    verifyEqual(tests, M.method, 'thin-plate spline');
    verifyEqual(tests, M.range, [-40 -12], 'AbsTol', 1e-9);
    % M1 at AP +1 mm, V1 at -3.5 mm: the values are a plane in AP, and so is the map
    [X, Y] = meshgrid(M.x, M.y);
    in = isfinite(M.z);
    verifyEqual(tests, M.z(in), -12 + 28 * (Y(in) - 1) / 4.5, 'AbsTol', 1e-9);
    verifyEqual(tests, [min(M.x) max(M.x) min(M.y) max(M.y)], [-2.5 2.5 -3.5 1], 'AbsTol', 1e-9);
    verifyTrue(tests, isnan(M.z(end, 1)), 'left of M1-L, in front of V1-L: outside the electrodes');
    verifyEqual(tests, M.z(1, 1), -40, 'AbsTol', 1e-9, 'V1-L itself');
    verifySize(tests, M.hull, [5 2]);
    verifyTrue(tests, isnan(M.radius));
    verifyEqual(tests, ScalpMap.describe(M), ['Flat map (thin-plate spline in mm from bregma) from 4 ' ...
        'electrodes, drawn only inside their outline.']);
    % One screw left out: still a map (3 screws, not on one line)
    M = ScalpMap.make(L, [v(1:3) NaN]);
    verifyEqual(tests, M.left, {'V1-R'});
    verifySize(tests, M.leftXY, [1 2]);
    verifyTrue(tests, endsWith(ScalpMap.describe(M), 'left out: V1-R.'));
end

%% --------------------------------------------------- Channels, limits, drawing, errors

function testChannelsByName(tests)
    [u, v, labels] = demoPositions();
    L = struct('kind', 'scalp', 'labels', {[labels, {'VEOG'}]}, 'pos', [u; NaN NaN NaN]);
    names = [fliplr(lower(labels)), {'EMG'}];
    M = ScalpMap.make(L, [flipud(v); 99], 'Labels', names);
    verifyEqual(tests, M.labels, labels, 'in the order of the layout, case ignored');
    verifyEqual(tests, M.values, v, 'AbsTol', 1e-12);
    verifyEqual(tests, M.left, {'VEOG'}, 'no value and no position');
    verifyEmpty(tests, M.leftXY, 'VEOG has no position to draw');
    w = v;
    w(strcmp(labels, 'T7')) = NaN;                            % a bad channel
    M = ScalpMap.make(L, [w; 0], 'GridSize', 41);
    verifyEqual(tests, M.left, {'T7', 'VEOG'});
    verifySize(tests, M.leftXY, [1 2]);
    verifySize(tests, M.z, [41 41]);
end

function testLimitsAndColours(tests)
    a = struct('range', [-3 1]);
    b = struct('range', [0.5 2]);
    verifyEqual(tests, ScalpMap.limits([a b]), [-3 3]);
    verifyEqual(tests, ScalpMap.limits(struct('range', [0 0])), [-1 1], 'a flat map still has a scale');
    c = ScalpMap.colormap();
    verifySize(tests, c, [256 3]);
    verifyGreaterThan(tests, c(1, 3), c(1, 1), 'negative end blue');
    verifyGreaterThan(tests, c(end, 1), c(end, 3), 'positive end red');
    verifyGreaterThan(tests, min(mean(c(128:129, :), 1)), 0.95, 'white at 0');
    verifySize(tests, ScalpMap.colormap(11), [11 3]);
end

function testPlot(tests)
    assumeGraphics(tests);
    [u, v, labels] = demoPositions();
    L = struct('kind', 'scalp', 'labels', {labels}, 'pos', [-u(:, 2), u(:, 1), u(:, 3)]);
    w = v;
    w(1) = NaN;
    M = ScalpMap.make(L, w, 'GridSize', 41);
    f = figure('Visible', 'off');
    c = onCleanup(@() close(f));
    ax = axes('Parent', f);
    h = ScalpMap.plot(ax, M, 'Title', 'Target', 'Labels', true, 'CLim', [-2 2]);
    verifyEqual(tests, get(h.map, 'Type'), 'image');
    verifyEqual(tests, get(ax, 'CLim'), [-2 2]);
    verifyNotEmpty(tests, h.contours);
    verifyNotEmpty(tests, h.outline);
    verifyNumElements(tests, get(h.electrodes, 'XData'), 31);
    verifyNumElements(tests, get(h.left, 'XData'), 1, 'Fp1 left out: a ring');
    verifyNumElements(tests, h.labels, 31);
    verifyEqual(tests, get(get(ax, 'Title'), 'String'), 'Target');
    verifyEqual(tests, get(ax, 'DataAspectRatio'), [1 1 1]);
    cla(ax);
    h = ScalpMap.plot(ax, ScalpMap.make(struct('kind', 'skull', 'labels', {{'A', 'B', 'C'}}, ...
        'pos', [-1 1 0; 1 1 0; 0 -3 0]), [1 2 3]), 'Contours', false);
    verifyEmpty(tests, h.contours);
    verifyEqual(tests, get(ax, 'CLim'), [-3 3], 'default: symmetric about 0');
    ax2 = axes('Parent', f);
    ScalpMap.colorScale(ax2, [-4 4], [char(181) 'V']);
    verifyEqual(tests, get(ax2, 'YLim'), [-4 4]);
    verifyEqual(tests, get(get(ax2, 'YLabel'), 'String'), [char(181) 'V']);
end

function testErrors(tests)
    [u, v, labels] = demoPositions();
    L = struct('kind', 'scalp', 'labels', {labels}, 'pos', u);
    verifyError(tests, @() ScalpMap.make(struct('kind', 'none', 'labels', {labels}, 'pos', NaN(32, 3)), v), ...
        'NeuroAnalyzer:eeg:invalid');
    verifyError(tests, @() ScalpMap.make(L, v(1:31)), 'NeuroAnalyzer:eeg:invalid');
    verifyError(tests, @() ScalpMap.make(L, v(1:3), 'Labels', labels(1:2)), 'NeuroAnalyzer:eeg:invalid');
    w = NaN(32, 1);
    w(1:2) = 1;
    verifyError(tests, @() ScalpMap.make(L, w), 'NeuroAnalyzer:eeg:invalid');
    S = struct('kind', 'skull', 'labels', {{'A', 'B', 'C'}}, 'pos', [0 0 0; 1 1 0; 2 2 0]);
    verifyError(tests, @() ScalpMap.make(S, [1 2 3]), 'NeuroAnalyzer:eeg:invalid', 'three screws on one line');
    verifyError(tests, @() ScalpMap.make(L, v, 'Grid', 41), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() ScalpMap.sphericalSpline(u, v(1:5), u), 'NeuroAnalyzer:eeg:invalid');
    verifyError(tests, @() ScalpMap.thinPlate([0 0; 1 0; 0 1], [1 2], [0 0]), 'NeuroAnalyzer:eeg:invalid');
end

%% --------------------------------------------------- Helpers

%% demoPositions - The 32 channels of demoEEG (azimuth from the nose, + left; elevation) and the P300 values
function [u, v, labels] = demoPositions()
    labels = {'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'FC5', 'FC1', 'FC2', 'FC6', 'T7', ...
        'C3', 'Cz', 'C4', 'T8', 'TP9', 'CP5', 'CP1', 'CP2', 'CP6', 'TP10', 'P7', 'P3', 'Pz', ...
        'P4', 'P8', 'PO9', 'O1', 'Oz', 'O2', 'PO10'};
    u = azelVectors([18 0; -18 0; 54 0; 40 42; 0 45; -40 42; -54 0; 69 21; 45 67; -45 67; -69 21; ...
        90 0; 90 45; 0 90; -90 45; -90 0; 108 -18; 111 21; 135 67; -135 67; -111 21; -108 -18; ...
        126 0; 140 42; 180 45; -140 42; -126 0; 144 -18; 162 0; 180 0; -162 0; -144 -18]);
    v = exp(-(acos(max(-1, min(1, u * u(25, :)'))) / 0.8) .^ 2);
    v = v - mean(v);
end

%% azelVectors - Unit vectors (x nose, y left ear, z up) from [azimuth elevation] in deg
function u = azelVectors(ae)
    u = [cosd(ae(:, 2)) .* cosd(ae(:, 1)), cosd(ae(:, 2)) .* sind(ae(:, 1)), sind(ae(:, 2))];
end

%% peakAt - Drawing coordinates of the largest ('max') or smallest ('min') value of a map
function p = peakAt(M, which)
    z = M.z;
    if strcmp(which, 'min'), z = -z; end
    z(isnan(z)) = -Inf;
    [~, i] = max(z(:));
    [r, k] = ind2sub(size(z), i);
    p = [M.x(k) M.y(r)];
end

function assumeGraphics(tests)
    try
        f = figure('Visible', 'off');
        ax = axes('Parent', f);
        plot(ax, 0, 0);
        close(f);
        canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'figures cannot be drawn here');
end
