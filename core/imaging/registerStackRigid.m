function [registered, shifts, info] = registerStackRigid(stack, ref, varargin)
% registerStackRigid - Rigid (translation-only) motion correction of an image stack.
%
% Estimates, for every frame, the translation [dy dx] that best aligns it
% with a reference image, then shifts the frame back. Handles the frame-to-
% frame jitter of in-vivo imaging (breathing, heartbeat); it does not
% correct rotation, scaling or non-rigid deformation.
%
% Method: FFT phase correlation. The cross-power spectrum of frame and
% reference, normalised to unit magnitude, is the Fourier transform of a
% delta at the displacement. It is weighted by a Gaussian low-pass
% ('PeakSigma', in px) so that the correlation surface becomes a smooth
% Gaussian peak centred on the true, sub-pixel displacement and high
% spatial frequencies (mostly noise) are down-weighted. The integer peak
% is refined to sub-pixel precision with a 3-point fit in y and in x:
% a Gaussian fit (parabola through the log of the peak and its
% neighbours, exact for a Gaussian peak) or a plain parabolic fit. Frames
% and reference are mean-subtracted and tapered at the borders (raised
% cosine) before the FFT to reduce wrap-around edge effects.
% With ref = 'mean' the reference is the mean of the stack, and the
% registration is repeated ('Iterations', default 2) with the mean of the
% registered stack as the new, sharper reference; the shifts are then
% centred (zero mean), i.e. frames are registered onto their average
% position.
% Shifts are applied with bilinear interpolation (interp2; pixels that
% come from outside the frame take the nearest edge value) or, with
% 'Apply', 'fft', by a Fourier phase shift (exact for sub-pixel shifts
% but wraps around the borders).
%
% Usage:
%   [reg, shifts] = registerStackRigid(stack);              % reference = mean
%   [reg, shifts] = registerStackRigid(stack, 1);           % reference = frame 1
%   [reg, shifts, info] = registerStackRigid(stack, 'mean', struct('MaxShift', 10));
%   [reg, shifts] = registerStackRigid(stack, refImage, 'Apply', 'fft');
%
% INPUT:
%   stack - H x W x N (or H x W x C x N: shifts are estimated on the mean
%           over channels and applied to every channel).
%   ref   - (optional) 'mean' (default), a frame index, or an H x W image.
%   Options (struct or name-value pairs, case-insensitive):
%     'MaxShift'   - largest shift searched, px (default: a quarter of the smaller image side).
%     'PeakSigma'  - width of the correlation peak, px (default 1).
%     'PeakFit'    - 'gaussian' (default) or 'parabolic'.
%     'Iterations' - reference refinements for ref = 'mean' (default 2).
%     'Apply'      - 'interp' (default) or 'fft'.
%     'Taper'      - fraction of each side tapered to zero before the FFT (default 0.25).
% OUTPUT:
%   registered - stack of the same size, frames shifted onto the
%                reference (single if the input is single, else double).
%   shifts     - N x 2, [dy dx] in px: displacement of each frame's
%                content relative to the reference (content that sits at
%                (y, x) in the reference is at (y + dy, x + dx) in the
%                frame). For ref = 'mean' they have zero mean.
%   info       - struct: reference (H x W image used in the last pass),
%                peak (1 x N, correlation peak height: low values mean an
%                unreliable estimate), iterations, validMask (H x W logical,
%                pixels inside every shifted frame; outside it the values
%                are copies of the frame edge).
%
% Toolbox-free (base MATLAB only: fft2, interp2).
%
if nargin < 2 || isempty(ref), ref = 'mean'; end
opt = parseOptions(varargin);

isRGB = ndims(stack) == 4;
if isRGB
    [H, W, C, N] = size(stack);
    gray = reshape(mean(double(stack), 3), H, W, N);
else
    [H, W, N] = size(stack);
    C = 1;
    gray = double(stack);
end
if isempty(opt.maxshift), opt.maxshift = floor(min(H, W) / 4); end

useMean = ischar(ref) || isstring(ref);
if useMean
    if ~strcmpi(char(ref), 'mean')
        error('NeuroAnalyzer:registerStackRigid:ref', 'ref must be ''mean'', a frame index or an H x W image.');
    end
    refImg = mean(gray, 3);
    nIter = max(1, round(opt.iterations));
elseif isscalar(ref)
    if ref < 1 || ref > N || ref ~= round(ref)
        error('NeuroAnalyzer:registerStackRigid:ref', 'Reference frame must be an integer between 1 and %d.', N);
    end
    refImg = gray(:, :, ref);
    nIter = 1;
else
    if ~isequal(size(ref), [H W])
        error('NeuroAnalyzer:registerStackRigid:ref', 'Reference image must be %d x %d.', H, W);
    end
    refImg = double(ref);
    nIter = 1;
end

win = taperWindow(H, W, opt.taper);
% Gaussian weight of the cross-power spectrum (frequencies in cycles/px)
fy = ifftshift((0:H-1) - floor(H / 2)) / H;
fx = ifftshift((0:W-1) - floor(W / 2)) / W;
[FX, FY] = meshgrid(fx, fy);
G = exp(-2 * pi^2 * opt.peaksigma^2 * (FX.^2 + FY.^2));

shifts = zeros(N, 2);
peak = zeros(1, N);
for it = 1:nIter
    R = fft2(prepare(refImg, win));
    for k = 1:N
        [shifts(k, :), peak(k)] = estimateShift(fft2(prepare(gray(:, :, k), win)), R, G, opt);
    end
    if useMean
        % Register onto the average position of the frames (zero-mean
        % shifts), so the result does not depend on how the blurred first
        % template happened to sit
        shifts = shifts - mean(shifts, 1);
    end
    if it < nIter
        refImg = mean(applyShifts(gray, shifts, opt.apply), 3);
    end
end

% Apply to the full stack (each channel for RGB)
if isRGB
    registered = zeros(H, W, C, N);
    for c = 1:C
        registered(:, :, c, :) = reshape(applyShifts(reshape(double(stack(:, :, c, :)), H, W, N), ...
            shifts, opt.apply), H, W, 1, N);
    end
else
    registered = applyShifts(gray, shifts, opt.apply);
end
if isa(stack, 'single'), registered = single(registered); end
% Pixels that every shifted frame covers (outside them values are edge copies)
valid = false(H, W);
y1 = max(1, ceil(1 - min(shifts(:, 1)))); y2 = min(H, floor(H - max(shifts(:, 1))));
x1 = max(1, ceil(1 - min(shifts(:, 2)))); x2 = min(W, floor(W - max(shifts(:, 2))));
valid(y1:y2, x1:x2) = true;
info = struct('reference', refImg, 'peak', peak, 'iterations', nIter, 'validMask', valid);
end

%% estimateShift - Sub-pixel displacement of a frame (spectrum F) relative to the reference (spectrum R)
function [d, pk] = estimateShift(F, R, G, opt)
[H, W] = size(F);
X = F .* conj(R);
X = X ./ max(abs(X), eps) .* G;
c = real(ifft2(X));
% Only displacements within MaxShift (circular indexing: 1 = zero shift)
m = opt.maxshift;
dyAll = [0:floor(H / 2), -ceil(H / 2) + 1:-1];
dxAll = [0:floor(W / 2), -ceil(W / 2) + 1:-1];
cs = c;
cs(abs(dyAll) > m, :) = -Inf;
cs(:, abs(dxAll) > m) = -Inf;
[pk, idx] = max(cs(:));
[iy, ix] = ind2sub([H W], idx);
% 3-point refinement in each direction (circular neighbours)
yN = c(mod(iy - 2, H) + 1, ix); yP = c(mod(iy, H) + 1, ix);
xN = c(iy, mod(ix - 2, W) + 1); xP = c(iy, mod(ix, W) + 1);
d = [dyAll(iy) + subpixel(yN, pk, yP, opt.peakfit), dxAll(ix) + subpixel(xN, pk, xP, opt.peakfit)];
end

%% subpixel - Offset of the true peak from the middle sample (in [-0.5, 0.5])
function off = subpixel(a, b, c, kind)
off = 0;
if strcmpi(kind, 'gaussian') && a > 0 && b > 0 && c > 0
    la = log(a); lb = log(b); lc = log(c);
    den = la - 2 * lb + lc;
    if den < 0, off = 0.5 * (la - lc) / den; end
else
    den = a - 2 * b + c;
    if den < 0, off = 0.5 * (a - c) / den; end
end
off = max(-0.5, min(0.5, off));
end

%% prepare - Mean-subtract and taper a frame before the FFT
function f = prepare(img, win)
f = (img - mean(img(:))) .* win;
end

%% taperWindow - Separable raised-cosine taper over a fraction of each side
function w = taperWindow(H, W, frac)
w = taper1(H, frac) * taper1(W, frac)';
end

function v = taper1(n, frac)
v = ones(n, 1);
m = floor(frac * n);
if m < 1, return; end
r = 0.5 * (1 - cos(pi * (1:m)' / (m + 1)));
v(1:m) = r;
v(end-m+1:end) = flipud(r);
end

%% applyShifts - Move every frame back by its [dy dx]
function out = applyShifts(stack, shifts, method)
[H, W, N] = size(stack);
out = zeros(H, W, N);
if strcmpi(method, 'fft')
    fy = ifftshift((0:H-1) - floor(H / 2)) / H;
    fx = ifftshift((0:W-1) - floor(W / 2)) / W;
    [FX, FY] = meshgrid(fx, fy);
    for k = 1:N
        % out(y, x) = frame(y + dy, x + dx)  ->  multiply by exp(+i 2 pi (fy dy + fx dx))
        ph = exp(1i * 2 * pi * (FY * shifts(k, 1) + FX * shifts(k, 2)));
        out(:, :, k) = real(ifft2(fft2(stack(:, :, k)) .* ph));
    end
    return;
end
[X, Y] = meshgrid(1:W, 1:H);
for k = 1:N
    xs = min(max(X + shifts(k, 2), 1), W);    % nearest edge value outside the frame
    ys = min(max(Y + shifts(k, 1), 1), H);
    out(:, :, k) = interp2(stack(:, :, k), xs, ys, 'linear');
end
end

%% parseOptions - Struct or name-value pairs into lower-case option struct
function opt = parseOptions(args)
opt = struct('maxshift', [], 'peaksigma', 1, 'peakfit', 'gaussian', 'iterations', 2, ...
    'apply', 'interp', 'taper', 0.25);
if numel(args) == 1 && isstruct(args{1})
    s = args{1};
    f = fieldnames(s);
    args = cell(1, 2 * numel(f));
    for k = 1:numel(f)
        args{2*k - 1} = f{k}; args{2*k} = s.(f{k});
    end
end
if mod(numel(args), 2) ~= 0
    error('NeuroAnalyzer:registerStackRigid:options', 'Options must be a struct or name-value pairs.');
end
for k = 1:2:numel(args)
    name = lower(char(args{k}));
    if ~isfield(opt, name)
        error('NeuroAnalyzer:registerStackRigid:options', 'Unknown option ''%s''.', args{k});
    end
    opt.(name) = args{k + 1};
end
end
