function s = demoPerfusion(opts)
% demoPerfusion - Synthetic perfusion images as a commercial imager exports them.
%
% Perfusion / flux images of a rodent cortex (as PeriCam PSI / PIMSoft,
% moorFLPI or a laser Doppler imager export them: one perfusion value per
% pixel, in the device's units), 64 x 80 px, one image per second for 90 s,
% with faults that the quality checks find:
%   * Parenchyma 1000 PU; a vessel (vertical band at x = 14-25 px) at
%     3400 PU, above the export range: every value is clipped at 3000 PU
%     (PIMSoft exports 0-3000 PU), so the vessel sits at the top.
%   * Activated area: a disk at (x, y) = (52, 28), radius 12 px, whose
%     perfusion rises by 25% after each stimulus (the shape of demoLSCI:
%     peak 4 s after onset).
%   * Speckle-like noise: each value is the true perfusion times a gamma
%     variable of mean 1 and SD 0.1.
%   * One image per second: the time resolution is coarse for a response
%     that rises in 1-2 s.
%   * Stimuli: 5 s pulses (5 V, channel stim) at 10, 30, 50 and 70 s.
%
% Usage:
%   s = demoPerfusion();
%
% INPUT:
%   opts - (optional) struct: Seconds (90), Seed (20261003).
% OUTPUT:
%   s - struct saved as the demo .mat file:
%       frames   - 64 x 80 x N double perfusion images (PU, 0-3000)
%       t        - 1 x N, s        fps - 1
%       stim     - 1 x N (0 / 5 V) kind - 'perfusion'
%       units    - 'PU'
%       roiMasks - 64 x 80 x 3 logical: 'Activated area' (disk r = 7),
%                  'Control cortex' (disk r = 8 at (40, 50)), 'Vessel'
%                  (x = 18-21, y = 8-56)
%       roiNames - 1 x 3 cellstr
%       truth    - struct: fps, onsets (s), stimSec, base (H x W, PU before
%                  clipping), ceiling (3000), vesselPU (3400), responsePeak
%                  (0.25), peakLatency (4 s), flowRatio (1 x N), activeMask.
%
% Deterministic (RandStream 'mt19937ar', fixed seed). Base MATLAB only.
%
if nargin < 1 || isempty(opts), opts = struct(); end
secs = getOpt(opts, 'Seconds', 90);
seed = getOpt(opts, 'Seed', 20261003);
rs = RandStream('mt19937ar', 'Seed', seed);

H = 64; W = 80; fps = 1; ceiling = 3000; vesselPU = 3400;
N = round(secs * fps);
t = (0:N-1) / fps;
[X, Y] = meshgrid(1:W, 1:H);
base = 1000 * ones(H, W);
base(X >= 14 & X <= 25) = vesselPU;
activeCenter = [52 28];
active = hypot(X - activeCenter(1), Y - activeCenter(2)) <= 12;

onsets = 10:20:secs - 15;
stimSec = 5;
stim = zeros(1, N);
g = zeros(1, N);
for o = onsets
    stim(t >= o & t < o + stimSec) = 5;
    u = (t - o) / 4;
    on = u > 0;
    g(on) = g(on) + u(on) .^ 3 .* exp(3 * (1 - u(on)));
end
flowRatio = 1 + 0.25 * g;

frames = zeros(H, W, N);
shape = 100;                                      % gamma(100, 1/100): mean 1, SD 0.1
for n = 1:N
    P = base;
    P(active) = base(active) * flowRatio(n);
    noise = zeros(H, W);
    for j = 1:shape / 10                          % sum of 10 gamma(10) = gamma(100)
        noise = noise + gamma10(rs, H, W);
    end
    frames(:, :, n) = min(P .* noise / shape, ceiling);
end

roiMasks = false(H, W, 3);
roiMasks(:, :, 1) = hypot(X - activeCenter(1), Y - activeCenter(2)) <= 7;
roiMasks(:, :, 2) = hypot(X - 40, Y - 50) <= 8;
roiMasks(:, :, 3) = X >= 18 & X <= 21 & Y >= 8 & Y <= 56;
roiNames = {'Activated area', 'Control cortex', 'Vessel'};

truth = struct('fps', fps, 'onsets', onsets, 'stimSec', stimSec, 'base', base, 'ceiling', ceiling, ...
    'vesselPU', vesselPU, 'responsePeak', 0.25, 'peakLatency', 4, 'flowRatio', flowRatio, ...
    'activeMask', active);
s = struct('frames', frames, 't', t, 'fps', fps, 'stim', stim, 'kind', 'perfusion', 'units', 'PU', ...
    'roiMasks', roiMasks, 'roiNames', {roiNames}, 'truth', truth);
end

%% gamma10 - Gamma(10, 1) samples (sum of 10 exponentials), H x W
function x = gamma10(rs, H, W)
x = -sum(log(rand(rs, H, W, 10)), 3);
end

function v = getOpt(opts, name, default)
if isfield(opts, name), v = opts.(name); else, v = default; end
end
