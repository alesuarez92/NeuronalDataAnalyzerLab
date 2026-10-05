%% ImagingChecksTest.m
% =========================================================================
% UNIT TESTS: IMAGING ROI QUALITY CHECKS (ROI ANALYSIS)
% =========================================================================
% ImagingChecks on synthetic inputs and on the demo stacks:
%   * motion: the movement of the frames against the size of the smallest
%     ROI (OK up to 20% of it, Check above, Warning from half of it), the
%     residual after motion correction, a Check when the correction moved
%     frames by more than a whole ROI, line methods in px;
%   * bleaching: the ROI baseline at the end against the start (Check
%     above 10%, Warning above 25% darker; a Check when it brightens);
%     only for the brightness methods;
%   * saturation: ROI pixels at the top value (Check above 0.1%, Warning
%     above 1% of a ROI's pixel-frames), the camera ceiling named;
%   * preprocessing: frames normalised to 0-1 before ΔF/F (Check);
%   * estimateShifts finds the slide of the faults demo;
%   * the clean demo (DemoData.imagingStack) gives no warnings; the faults
%     demo (DemoData.imagingFaults: the field slides 14 px, the dye fades
%     to ~65%, Cell 2 clipped at 4095) fires Motion, Bleaching and
%     Saturation, and Motion is OK once motion correction is on.
% Base MATLAB only; also runs in GNU Octave.
% =========================================================================

function tests = ImagingChecksTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'demo'));
end

%% row - The first row of a topic ([] when none)
function r = row(Q, topic)
    r = [];
    if isempty(Q), return; end
    k = find(strcmp({Q.topic}, topic), 1);
    if ~isempty(k), r = Q(k); end
end

%% expect - A row of this topic with this level whose finding has the text
function expect(tests, Q, topic, level, text)
    r = row(Q, topic);
    txt = strjoin(QualityChecks.lines(Q), newline);
    tests.verifyNotEmpty(r, sprintf('no %s row:\n%s', topic, txt));
    if isempty(r), return; end
    tests.verifyEqual(r.level, level, sprintf('%s: %s', topic, r.found));
    if nargin >= 5
        tests.verifyTrue(~isempty(strfind(r.found, text)), sprintf('%s: "%s" not in "%s"', topic, text, r.found)); %#ok<STREMP>
    end
end

%% disc - H x W logical disc of radius r at (x, y)
function m = disc(H, W, x, y, r)
    [X, Y] = meshgrid(1:W, 1:H);
    m = (X - x).^2 + (Y - y).^2 <= r^2;
end

%% opts - ImagingChecks options for a method
function o = opts(method, shifts)
    o = ImagingChecks.options();
    o.method = method;
    if nargin >= 2, o.shifts = shifts; end
end

%% sideways - N x 2 shifts sliding sideways from -a to +a px
function s = sideways(a, N)
    if nargin < 2, N = 50; end
    s = [zeros(N, 1), linspace(-a, a, N)'];
end

%% demoChecks - The checks ROI Analysis runs on a stack with file ROIs
function Q = demoChecks(s, masks, names, corrected)
    o = ImagingChecks.options();
    o.names = names;
    o.method = 'ΔF/F (gCaMP)';
    o.baselineFrames = 30;
    g = double(s.stack);
    if corrected
        [g, sh] = registerStackRigid(g, 'mean');
        o.motionCorrected = true;
        o.shifts = sh;
        o.residual = ImagingChecks.estimateShifts(g);
    else
        o.shifts = ImagingChecks.estimateShifts(s.stack);
    end
    N = size(g, 3);
    K = size(masks, 3);
    F = zeros(K, N);
    for k = 1:K
        F(k, :) = roiIntensityOverTime(g, masks(:, :, k), []);
    end
    Q = ImagingChecks.run(s.stack, masks, F, s.timeVec, o);
end

function testRoiSizeAndMotionSize(tests)
    tests.verifyEqual(ImagingChecks.roiSize(disc(64, 64, 32, 32, 5)), 10, 'AbsTol', 0.6);
    tests.verifyEqual(ImagingChecks.motionSize(sideways(4)), 4, 'AbsTol', 0.1);
    tests.verifyEqual(ImagingChecks.motionSize([0 0; 3 4; 0 0]), 5, 'AbsTol', 1e-12);
    tests.verifyTrue(isnan(ImagingChecks.motionSize([])));
end

function testMotionRules(tests)
    m = disc(64, 64, 32, 32, 5);                 % 10 px across
    Q = ImagingChecks.motion([], m, opts('Brightness', sideways(1.5)));
    expect(tests, Q, 'Motion', 'ok', '10 px across');
    Q = ImagingChecks.motion([], m, opts('Brightness', sideways(3)));
    expect(tests, Q, 'Motion', 'check', 'motion correction is off');
    Q = ImagingChecks.motion([], m, opts('Brightness', sideways(6)));
    expect(tests, Q, 'Motion', 'warning', '% of a ROI');
    Q = ImagingChecks.motion([], m, opts('Brightness', sideways(12)));
    expect(tests, Q, 'Motion', 'warning', 'more than a whole ROI');
    tests.verifyTrue(~isempty(strfind(row(Q, 'Motion').action, 'Motion correction'))); %#ok<STREMP>
    % Several ROIs: the smallest one sets the size, by name
    masks = cat(3, disc(64, 64, 20, 20, 8), disc(64, 64, 44, 44, 3));
    o = opts('Brightness', sideways(3.5)); o.names = {'Big', 'Small'};
    Q = ImagingChecks.motion([], masks, o);
    expect(tests, Q, 'Motion', 'warning', 'Small');
end

function testMotionCorrected(tests)
    m = disc(64, 64, 32, 32, 5);
    o = opts('ΔF/F (gCaMP)', sideways(4)); o.motionCorrected = true; o.residual = sideways(0.3);
    expect(tests, ImagingChecks.motion([], m, o), 'Motion', 'ok', 'Motion corrected');
    o.shifts = sideways(12);
    expect(tests, ImagingChecks.motion([], m, o), 'Motion', 'check', 'more than a whole ROI');
    o.shifts = sideways(4); o.residual = sideways(3);
    expect(tests, ImagingChecks.motion([], m, o), 'Motion', 'check', 'still move');
    o.residual = [];                              % residual not measured
    expect(tests, ImagingChecks.motion([], m, o), 'Motion', 'ok');
end

function testMotionLineMethods(tests)
    Q = ImagingChecks.motion([], [], opts('Vessel diameter', sideways(3)));
    expect(tests, Q, 'Motion', 'check', '3.0 px');
    Q = ImagingChecks.motion([], [], opts('Kymograph', sideways(1)));
    expect(tests, Q, 'Motion', 'ok');
    tests.verifyEmpty(ImagingChecks.motion([], [], opts('Kymograph', [])), 'no shifts, no row');
end

function testBleachingRules(tests)
    t = (0:299) / 10;
    fade = @(loss) 1000 * (1 - loss + loss * exp(-t / 8));
    Q = ImagingChecks.bleaching([], fade(0.4), t, opts('ΔF/F (gCaMP)'));
    expect(tests, Q, 'Bleaching', 'warning', 'darker');
    tests.verifyTrue(~isempty(strfind(row(Q, 'Bleaching').why, 'F0'))); %#ok<STREMP>
    Q = ImagingChecks.bleaching([], fade(0.18), t, opts('Brightness'));
    expect(tests, Q, 'Bleaching', 'check', 'darker');
    Q = ImagingChecks.bleaching([], 1000 + 5 * sin(t), t, opts('Both'));
    expect(tests, Q, 'Bleaching', 'ok');
    Q = ImagingChecks.bleaching([], 1000 * (1 + 0.2 * t / t(end)), t, opts('Brightness'));
    expect(tests, Q, 'Bleaching', 'check', 'brighter');
    tests.verifyEmpty(ImagingChecks.bleaching([], fade(0.4), t, opts('Movement')), ...
        'Movement does not measure brightness');
    % Transients on top of a flat baseline are not bleaching
    f = 1000 * ones(size(t)); f(mod(1:300, 60) < 10) = 1800;
    expect(tests, ImagingChecks.bleaching([], f, t, opts('ΔF/F (gCaMP)')), 'Bleaching', 'ok');
    % Several ROIs: the worst one named, the others listed
    o = opts('ΔF/F (gCaMP)'); o.names = {'A', 'B', 'C'};
    Q = ImagingChecks.bleaching([], [fade(0.15); fade(0.4); 1000 + 0 * t], t, o);
    expect(tests, Q, 'Bleaching', 'warning', '(B; also A)');
end

function testSaturationRules(tests)
    H = 40; W = 40; N = 100;
    stack = uint16(1000 + zeros(H, W, N));
    m = disc(H, W, 20, 20, 5);                    % 81 px
    expect(tests, ImagingChecks.saturation([], stack + uint16(rand(H, W, N) * 10), m, opts('Brightness')), ...
        'Saturation', 'ok', 'No ROI pixel');
    s = stack; s(20, 20, 1:20) = 1500; s(20, 21, 1:5) = 1499;   % values piled up at 1500
    expect(tests, ImagingChecks.saturation([], s, m, opts('Brightness')), 'Saturation', 'check', '1500');
    s = stack; s(20, 20, 1:20) = 4095;            % 20 of 8100 pixel-frames: 0.25%
    expect(tests, ImagingChecks.saturation([], s, m, opts('Brightness')), 'Saturation', 'check', '12-bit');
    s = stack; s(18:22, 18:22, 1:20) = 4095;      % 500 / 8100: 6%
    Q = ImagingChecks.saturation([], s, m, opts('Brightness'));
    expect(tests, Q, 'Saturation', 'warning', '4095');
    s = stack; s(20, 20, 5) = 4095;               % one brightest pixel is not a ceiling
    expect(tests, ImagingChecks.saturation([], s, m, opts('Brightness')), 'Saturation', 'ok');
    s = uint8(100 + zeros(H, W, N)); s(19:21, 19:21, :) = 255;
    expect(tests, ImagingChecks.saturation([], s, m, opts('Brightness')), 'Saturation', 'warning', ...
        'largest uint8 value');
    % Clipped outside the ROIs only: OK with the count
    s = stack; s(1:3, 1:3, :) = 4095;
    expect(tests, ImagingChecks.saturation([], s, m, opts('Brightness')), 'Saturation', 'ok');
    % Several ROIs: the clipped one is named
    masks = cat(3, m, disc(H, W, 8, 8, 4)); o = opts('Brightness'); o.names = {'Dim', 'Bright'};
    s = stack; s(6:10, 6:10, 1:30) = 4095;
    expect(tests, ImagingChecks.saturation([], s, masks, o), 'Saturation', 'warning', 'Bright');
    % RGB stacks: a pixel clipped in any channel
    s = uint8(100 + zeros(H, W, 3, 10)); s(20, 20, 2, :) = 255; s(21, 20, 2, :) = 255;
    expect(tests, ImagingChecks.saturation([], s, m, opts('Brightness')), 'Saturation', 'warning');
end

function testPreprocessing(tests)
    o = opts('ΔF/F (gCaMP)'); o.normalize = true;
    expect(tests, ImagingChecks.preprocessing([], o), 'Preprocessing', 'check', 'normalised');
    o.method = 'Movement';
    tests.verifyEmpty(ImagingChecks.preprocessing([], o));
    o.method = 'Brightness'; o.normalize = false;
    tests.verifyEmpty(ImagingChecks.preprocessing([], o));
end

function testEstimateShiftsOnTheFaultsDemo(tests)
    s = DemoData.imagingFaults();
    sh = ImagingChecks.estimateShifts(s.stack, 50);
    tests.verifyEqual(size(sh), [50 2]);
    tests.verifyEqual(max(sh(:, 2)) - min(sh(:, 2)), 14, 'AbsTol', 1, 'the field slides 14 px sideways');
    tests.verifyLessThan(max(abs(sh(:, 1))), 0.5, 'and not up or down');
    tests.verifyEqual(ImagingChecks.motionSize(sh), 7, 'AbsTol', 0.6);
end

function testFaultsDemo(tests)
    s = DemoData.imagingFaults();
    tests.verifyEqual(class(s.stack), 'uint16');
    tests.verifyEqual(double(max(s.stack(:))), 4095);
    Q = demoChecks(s, s.roiMasks, s.roiNames, false);
    expect(tests, Q, 'Motion', 'warning', 'motion correction is off');
    expect(tests, Q, 'Bleaching', 'warning', 'darker');
    expect(tests, Q, 'Saturation', 'warning', 'Cell 2');
    tests.verifyTrue(~isempty(strfind(row(Q, 'Saturation').found, '12-bit'))); %#ok<STREMP>
    Q = demoChecks(s, s.roiMasks, s.roiNames, true);
    expect(tests, Q, 'Motion', 'ok', 'Motion corrected');
    expect(tests, Q, 'Bleaching', 'warning');
    expect(tests, Q, 'Saturation', 'warning', 'Cell 2');
end

function testCleanDemoHasNoWarnings(tests)
    s = DemoData.imagingStack();
    Q = demoChecks(s, s.roiMask, {'Cell'}, false);
    txt = strjoin(QualityChecks.lines(Q), newline);
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 0, txt);
    tests.verifyEqual(QualityChecks.count(Q, 'check'), 0, txt);
    expect(tests, Q, 'Motion', 'ok');
    expect(tests, Q, 'Bleaching', 'ok');
    expect(tests, Q, 'Saturation', 'ok');
end

function testOddInputGivesFewerRows(tests)
    tests.verifyEmpty(ImagingChecks.run([], [], [], [], ImagingChecks.options()));
    Q = ImagingChecks.run(zeros(4, 4, 3), true(4, 4), zeros(1, 3), 1:3, opts('Brightness', zeros(3, 2)));
    tests.verifyTrue(all(ismember({Q.level}, {'ok', 'check', 'warning', 'note'})));
end
