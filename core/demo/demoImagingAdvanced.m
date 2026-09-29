function s = demoImagingAdvanced(opts)
% demoImagingAdvanced - Synthetic imaging stack for motion correction, cell detection and robust diameter.
%
% 96 x 96 px, 150 frames at 10 Hz (15 s), with known ground truth:
%   * Rigid jitter: every frame is translated by a sub-pixel [dy dx] that
%     follows a smooth random walk, zero mean, at most 3 px in each
%     direction (rendered exactly: the scene is evaluated at the shifted
%     coordinates, the background texture is shifted in the Fourier domain).
%   * Three cells (soft disks) with calcium transients at distinct times:
%       cell 1 at (22, 24), r = 6 px, events at 4.0, 8.5, 13.0 s
%       cell 2 at (26, 78), r = 5 px, events at 5.5, 10.5 s
%       cell 3 at (82, 30), r = 7 px, events at 7.0, 12.0 s
%     Inside a cell the intensity is F0 * (1 + dF/F) with F0 = 0.9 and
%     dF/F = amp * exp(-(t - e) / 0.8) * (1 - exp(-(t - e) / 0.1)), amp = 1.0, 0.8, 1.2.
%   * A dark vertical vessel at x = 60 whose diameter is 12 + 3 sin(2 pi 0.2 t) px.
%   * A bright red blood cell (Gaussian spot, sigma 2 px, +1.0) moving down
%     the vessel at 3 px/frame over the whole image height, so it crosses
%     the diameter line (y = 64, from x = 35 to 85) about every 3 s. With
%     the default min/max half level the vessel diameter jumps for those
%     frames; the robust diameter does not.
%   * Sensor noise: Gaussian, SD 0.02 (not shifted with the scene).
%
% Usage:
%   s = demoImagingAdvanced();                         % with jitter
%   s = demoImagingAdvanced(struct('Jitter', false));  % same scene, no motion
%
% INPUT:
%   opts - (optional) struct: Jitter (true), RBC (true), Seed (20260965).
% OUTPUT:
%   s - struct with
%       stack   - 96 x 96 x 150 single
%       timeVec - 1 x 150, seconds
%       truth   - struct: fps, shifts (N x 2, [dy dx] of each frame's
%                 content relative to the motion-free scene, px),
%                 cellCenters (3 x 2, [x y]), cellRadii, cellMasks
%                 (96 x 96 x 3 logical, disks in scene coordinates),
%                 eventTimes (1 x 3 cell, s), dff (3 x N), cellF0,
%                 vesselCenterX, diameter (1 x N, px), lineStart / lineEnd
%                 (diameter line, [x y]), rbcPath (N x 2, [x y] in scene
%                 coordinates), rbcSpeedPxPerFrame, rbcCrossFrames (frames
%                 with the RBC within 4 px of the line), rbcAmplitude.
%
% Deterministic (RandStream 'mt19937ar' with a fixed seed). Base MATLAB only.
%
if nargin < 1 || isempty(opts), opts = struct(); end
jitter = getOpt(opts, 'Jitter', true);
withRBC = getOpt(opts, 'RBC', true);
seed = getOpt(opts, 'Seed', 20260965);
rs = RandStream('mt19937ar', 'Seed', seed);

H = 96; W = 96; N = 150; fps = 10;
t = (0:N-1) / fps;
[X, Y] = meshgrid(1:W, 1:H);

% --- Background texture: smooth, periodic on a 128 x 128 canvas ---
Cn = 128; off = (Cn - H) / 2;
fy = ifftshift((0:Cn-1) - Cn / 2) / Cn;
[FX, FY] = meshgrid(fy, fy);
TEX = fft2(randn(rs, Cn, Cn)) .* exp(-2 * pi^2 * 2.5^2 * (FX.^2 + FY.^2));
tex0 = real(ifft2(TEX));
TEX = TEX * (0.05 / std(tex0(:)));             % texture SD 0.05

% --- Rigid jitter: smooth random walk, zero mean, max |shift| = 3 px ---
walk = cumsum(0.7 * randn(rs, N, 2), 1);
walk = walk - mean(walk, 1);
walk = 3 * walk ./ max(abs(walk), [], 1);
if ~jitter, walk = zeros(N, 2); end

% --- Cells ---
cellXY = [22 24; 26 78; 82 30];
cellR = [6 5 7];
events = {[4.0 8.5 13.0], [5.5 10.5], [7.0 12.0]};
amp = [1.0 0.8 1.2];
cellF0 = 0.9;
nCell = size(cellXY, 1);
dff = zeros(nCell, N);
for i = 1:nCell
    for e = events{i}
        on = t >= e;
        dff(i, on) = dff(i, on) + amp(i) * exp(-(t(on) - e) / 0.8) .* (1 - exp(-(t(on) - e) / 0.1));
    end
end
cellMasks = false(H, W, nCell);
for i = 1:nCell
    cellMasks(:, :, i) = (X - cellXY(i, 1)).^2 + (Y - cellXY(i, 2)).^2 <= cellR(i)^2;
end

% --- Vessel and red blood cell ---
cx = 60;
diam = 12 + 3 * sin(2 * pi * 0.2 * t);
rbcSpeed = 3; rbcAmp = 1.0 * withRBC;
rbcY = 2 + mod(rbcSpeed * (0:N-1), 92);
lineY = 64; lineStart = [35 lineY]; lineEnd = [85 lineY];

stack = zeros(H, W, N, 'single');
for k = 1:N
    dy = walk(k, 1); dx = walk(k, 2);
    Xs = X - dx; Ys = Y - dy;                  % scene coordinates of each pixel
    tex = real(ifft2(TEX .* exp(-1i * 2 * pi * (FY * dy + FX * dx))));
    frame = 0.6 + tex(off + (1:H), off + (1:W));
    vessel = 1 ./ (1 + exp((abs(Xs - cx) - diam(k) / 2) / 0.8));   % 1 inside
    frame = frame .* (1 - 0.7 * vessel);
    for i = 1:nCell
        soft = 1 ./ (1 + exp((hypot(Xs - cellXY(i, 1), Ys - cellXY(i, 2)) - cellR(i)) / 0.5));
        frame = frame .* (1 - soft) + soft * cellF0 * (1 + dff(i, k));
    end
    frame = frame + rbcAmp * exp(-((Xs - cx).^2 + (Ys - rbcY(k)).^2) / (2 * 2^2));
    frame = frame + 0.02 * randn(rs, H, W);
    stack(:, :, k) = single(frame);
end

s.stack = stack;
s.timeVec = t;
s.truth = struct('fps', fps, 'shifts', walk, 'cellCenters', cellXY, 'cellRadii', cellR, ...
    'cellMasks', cellMasks, 'eventTimes', {events}, 'dff', dff, 'cellF0', cellF0, ...
    'vesselCenterX', cx, 'diameter', diam, 'lineStart', lineStart, 'lineEnd', lineEnd, ...
    'rbcPath', [cx * ones(N, 1), rbcY(:)], 'rbcSpeedPxPerFrame', rbcSpeed, ...
    'rbcCrossFrames', find(abs(rbcY - lineY) <= 4 & withRBC), 'rbcAmplitude', rbcAmp);
end

function v = getOpt(opts, name, default)
% Field of opts (case-insensitive), or default when missing.
v = default;
f = fieldnames(opts);
k = find(strcmpi(f, name), 1);
if ~isempty(k), v = opts.(f{k}); end
end
