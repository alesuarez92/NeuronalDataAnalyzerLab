function s = demoLSCI(opts)
% demoLSCI - Synthetic laser speckle recording with known blood flow.
%
% Raw speckle images of a rodent cortex, 64 x 80 px, 10 frames per second
% for 90 s (900 frames), camera exposure 5 ms, with known ground truth:
%   * Each pixel is an independent speckle: its intensity follows a gamma
%     distribution with mean I0 and contrast K (SD / mean = K exactly),
%     K^2 = beta (exp(-2x) - 1 + 2x) / (2 x^2) with x = T / tau_c, beta = 1
%     (the exposure model of Bandyopadhyay et al. 2005, Boas & Dunn 2010).
%   * Parenchyma: tau_c = T / 20 (K = 0.221).
%   * A vessel (vertical band at x = 14-25 px): tau_c = T / 200 (K = 0.071).
%   * A static region (bone / tape, x >= 68 and y >= 52): K = 0.7, no flow.
%   * Activated area: a disk at (x, y) = (52, 28), radius 12 px. Flow
%     (1 / tau_c) rises by 25% after each stimulus: flow(t) = baseline x
%     (1 + 0.25 g(t - onset)), g = u^3 exp(3 (1 - u)), u = (t - onset) / 4 s
%     (peak 1 at 4 s). Flow everywhere else does not change.
%   * Stimuli: 5 s pulses (5 V, channel stim) at 10, 30, 50 and 70 s.
%   * Illumination: Gaussian fall-off, mean intensity about 1300-2000
%     counts; a camera dark level of 100 counts is added; uint16 frames.
%
% With Faults = true the same recording carries faults that the quality
% checks find (demo_lsci_faults.mat):
%   * speckles smaller than a pixel: each pixel averages 2 independent
%     speckles, so the contrast is 1/sqrt(2) of the model (cortex K = 0.16);
%   * the whole field (vessel, activated area, static corner, illumination)
%     shifts 4 px to the right at 45 s, as when the head or camera moves;
%   * the illumination falls linearly by 20% over the recording;
%   * the file says exposure 25 ms (outside the usual 1-20 ms; the flow
%     itself is simulated as above);
%   * a fourth ROI 'Thinned skull' on the static corner (K = 0.49 there:
%     static scattering).
%
% Usage:
%   s = demoLSCI();
%   s = demoLSCI(struct('Seconds', 30));   % shorter recording (tests)
%   s = demoLSCI(struct('Faults', true));  % the faults demo
%
% INPUT:
%   opts - (optional) struct: Seconds (90), Seed (20260930), Faults (false).
% OUTPUT:
%   s - struct saved as the demo .mat file:
%       frames     - 64 x 80 x N uint16 raw speckle images
%       t          - 1 x N, s          fps - 10
%       exposureMs - 5                 dark - 100 (counts)
%       stim       - 1 x N (0 / 5 V)   kind - 'raw speckle'
%       roiMasks   - 64 x 80 x 3 logical: 'Activated area' (disk r = 7 in
%                    the activated disk, so 7 x 7 contrast windows centred
%                    in it stay inside), 'Control cortex' (disk r = 8 at
%                    (40, 50)), 'Vessel' (x = 18-21, y = 8-56: 7 x 7 windows
%                    centred there see only the vessel)
%       roiNames   - 1 x 3 cellstr
%       truth      - struct: fps, exposureMs, beta, dark, onsets (s),
%                    stimSec (5), xBase (H x W, T / tau_c before stimuli),
%                    Kbase (H x W), activeMask, activeCenter, activeRadius,
%                    responsePeak (0.25), peakLatency (4 s), flowRatio
%                    (1 x N, true flow / baseline in the activated area),
%                    invK2Ratio (1 x N, the same seen through 1/K^2),
%                    peakInvK2Pct (%, 1/K^2 change at the peak), staticK,
%                    faults (struct: speckleAverage 1 | 2, shiftPx [dx dy],
%                    shiftSec, illuminationDrop, exposureMs as written).
%
% Deterministic (RandStream 'mt19937ar', fixed seed). Base MATLAB only.
%
if nargin < 1 || isempty(opts), opts = struct(); end
secs = getOpt(opts, 'Seconds', 90);
seed = getOpt(opts, 'Seed', 20260930);
faulty = logical(getOpt(opts, 'Faults', false));
rs = RandStream('mt19937ar', 'Seed', seed);

H = 64; W = 80; fps = 10; Tms = 5; beta = 1; dark = 100;
N = round(secs * fps);
t = (0:N-1) / fps;
[X, Y] = meshgrid(1:W, 1:H);
faults = struct('speckleAverage', 1, 'shiftPx', [0 0], 'shiftSec', NaN, 'illuminationDrop', 0, ...
    'exposureMs', Tms);
if faulty
    faults = struct('speckleAverage', 2, 'shiftPx', [4 0], 'shiftSec', 45, 'illuminationDrop', 0.2, ...
        'exposureMs', 25);
end

% --- Baseline flow: x = T / tau_c per pixel (the scene before any shift) ---
staticK = 0.7;
activeCenter = [52 28]; activeRadius = 12;
[xBase, Kbase, active, ~, I0] = scene(X, Y, beta, staticK, activeCenter, activeRadius);
if faulty
    [~, KbaseS, activeS, ~, I0S] = scene(X - faults.shiftPx(1), Y - faults.shiftPx(2), beta, staticK, ...
        activeCenter, activeRadius);
end

% --- Stimuli and the flow response of the activated area ---
onsets = 10:20:secs - 15;
stimSec = 5;
stim = zeros(1, N);
for o = onsets
    stim(t >= o & t < o + stimSec) = 5;
end
g = zeros(1, N);
for o = onsets
    u = (t - o) / 4;
    on = u > 0;
    g(on) = g(on) + u(on) .^ 3 .* exp(3 * (1 - u(on)));
end
flowRatio = 1 + 0.25 * g;
kActive2 = modelK2(20 * flowRatio, beta);         % K^2 of the activated parenchyma over time
invK2Ratio = modelK2(20, beta) ./ kActive2;

% --- Illumination and the speckle images ---
frames = zeros(H, W, N, 'uint16');
nAvg = faults.speckleAverage;
for n = 1:N
    Kb = Kbase; act = active; Ib = I0;
    if faulty && t(n) >= faults.shiftSec
        Kb = KbaseS; act = activeS; Ib = I0S;
    end
    K = Kb;
    K(act) = sqrt(kActive2(n));
    a = 1 ./ K .^ 2;                              % gamma shape: SD / mean = K
    g = gammaSample(rs, a);
    for j = 2:nAvg                                % speckles smaller than a pixel: their mean
        g = g + gammaSample(rs, a);
    end
    g = g / nAvg;
    I = g .* (Ib ./ a) * (1 - faults.illuminationDrop * t(n) / max(t(end), eps)) + dark;
    frames(:, :, n) = uint16(min(round(I), 65535));
end

% --- ROIs ---
roiMasks = false(H, W, 3);
roiMasks(:, :, 1) = hypot(X - activeCenter(1), Y - activeCenter(2)) <= 7;
roiMasks(:, :, 2) = hypot(X - 40, Y - 50) <= 8;
roiMasks(:, :, 3) = X >= 18 & X <= 21 & Y >= 8 & Y <= 56;
roiNames = {'Activated area', 'Control cortex', 'Vessel'};
if faulty
    roiMasks(:, :, 4) = X >= 74 & X <= 79 & Y >= 55 & Y <= 63;
    roiNames{4} = 'Thinned skull';
    Kbase = Kbase / sqrt(nAvg);
end

truth = struct('fps', fps, 'exposureMs', Tms, 'beta', beta, 'dark', dark, ...
    'onsets', onsets, 'stimSec', stimSec, 'xBase', xBase, 'Kbase', Kbase, ...
    'activeMask', active, 'activeCenter', activeCenter, 'activeRadius', activeRadius, ...
    'responsePeak', 0.25, 'peakLatency', 4, 'flowRatio', flowRatio, ...
    'invK2Ratio', invK2Ratio, 'peakInvK2Pct', 100 * (max(invK2Ratio) - 1), 'staticK', staticK / sqrt(nAvg), ...
    'faults', faults);
s = struct('frames', frames, 't', t, 'fps', fps, 'exposureMs', faults.exposureMs, 'dark', dark, ...
    'stim', stim, 'kind', 'raw speckle', 'roiMasks', roiMasks, 'roiNames', {roiNames}, ...
    'truth', truth);
end

%% scene - Flow (x = T / tau_c), baseline contrast, activated / static areas and illumination at X, Y
function [xBase, Kbase, active, static, I0] = scene(X, Y, beta, staticK, activeCenter, activeRadius)
xBase = 20 * ones(size(X));                       % parenchyma
vessel = X >= 14 & X <= 25;
xBase(vessel) = 200;
static = X >= 68 & Y >= 52;
active = hypot(X - activeCenter(1), Y - activeCenter(2)) <= activeRadius;
Kbase = sqrt(modelK2(xBase, beta));
Kbase(static) = staticK;
I0 = 1300 + 700 * exp(-((X - 40) .^ 2 + (Y - 32) .^ 2) / (2 * 30 ^ 2));
end

%% modelK2 - K^2 = beta (exp(-2x) - 1 + 2x) / (2 x^2)
function g = modelK2(x, beta)
g = beta * (expm1(-2 * x) + 2 * x) ./ (2 * x .^ 2);
end

%% gammaSample - Gamma(a, 1) samples, a >= 1 (Marsaglia & Tsang 2000), one per element of a
function x = gammaSample(rs, a)
d = a - 1 / 3;
c = 1 ./ sqrt(9 * d);
x = zeros(size(a));
todo = true(size(a));
while any(todo(:))
    idx = find(todo);
    z = randn(rs, numel(idx), 1);
    u = rand(rs, numel(idx), 1);
    v = (1 + c(idx) .* z) .^ 3;
    ok = v > 0;
    lv = log(max(v, realmin));
    ok = ok & log(u) < 0.5 * z .^ 2 + d(idx) - d(idx) .* v + d(idx) .* lv;
    x(idx(ok)) = d(idx(ok)) .* v(ok);
    todo(idx(ok)) = false;
end
end

function v = getOpt(opts, name, default)
if isfield(opts, name), v = opts.(name); else, v = default; end
end
