function [diameter, t, profile, isOutlier, info] = vesselDiameterFromLine(stack, lineStart, lineEnd, timeVec, method, varargin)
% vesselDiameterFromLine - Vessel diameter over time from intensity profile along perpendicular line.
%
% For each frame, sample intensity along the line (see kymograph) and
% measure the width of the vessel at half depth: the two walls are where
% the profile crosses the level halfway between the background and the
% vessel core. By default the vessel is dark (e.g. unlabelled lumen in
% 2-photon or reflectance images); use 'Polarity', 'bright' for a
% fluorescent lumen.
%
% method: 'fwhm' (default) - full width at half depth. With 'SubPixel'
%           (default true) each wall is located between two samples by
%           linear interpolation of the profile, so the width is not
%           quantised to whole samples.
%         'threshold' - legacy sample counting: number of samples at or
%           beyond the half level, times line length / number of samples.
%
% Levels: by default the half level is the midpoint between the darkest
% and the brightest sample of the profile (backward compatible). A bright
% object inside a dark vessel (a red blood cell in the lumen) raises the
% brightest sample, so the half level can reach the background and the
% width jumps to the whole line for that frame. 'Robust', true instead
% takes the background from the two ends of the line (median of the
% first / last 'EdgeFraction' of samples, one level per wall, so uneven
% illumination is tolerated) and the vessel core from a low percentile
% ('CorePercentile') of the profile. Both are replaced by their running
% median over 'Window' frames, because lumen darkness and background
% change slowly while a red blood cell that fills the lumen raises the
% core for a frame or two. Walls are the outermost crossings of the half
% level, so a bright spot inside the lumen moves neither the level nor
% the walls. Remaining per-frame spikes (and frames where the lumen was
% hidden, which give no width) are then replaced by a Hampel filter over
% time (running median +/- 'NMad' robust SDs over 'Window' frames, see
% robustTimeSeries); replaced frames are flagged in isOutlier.
%
% Usage:
%   d = vesselDiameterFromLine(stack, [x1 y1], [x2 y2], timeVec, 'fwhm');
%   d = vesselDiameterFromLine(stack, [x1 y1 x2 y2], [], timeVec);
%   [d, t, profile, isOutlier, info] = vesselDiameterFromLine(stack, p1, p2, timeVec, 'fwhm', ...
%           'Robust', true, 'Window', 7, 'NMad', 3);
%   d = vesselDiameterFromLine(stack, p1, p2, 'Robust', true);   % options right after the line
%
% INPUT:
%   stack    - H x W x N (or H x W x 3 x N).
%   lineStart, lineEnd - line perpendicular to vessel ([x y] in pixels),
%              or lineStart = [x1 y1 x2 y2] and lineEnd = []. The line
%              should extend beyond each wall by at least one vessel
%              radius so that its ends sample the background.
%   timeVec  - (optional) 1 x N.
%   method   - (optional) 'fwhm' (default) or 'threshold'.
%   Name-value options:
%     'SubPixel'       - true (default) | false: interpolate the wall positions ('fwhm').
%     'Robust'         - false (default) | true: edge baseline, percentile core,
%                        outermost crossings and Hampel filter over time.
%     'Window'         - Hampel window in frames (default 7; 'Robust' only).
%     'NMad'           - Hampel threshold in robust SDs (default 3; 'Robust' only).
%     'EdgeFraction'   - fraction of samples at each end used as background (default 0.15).
%     'CorePercentile' - percentile of the profile used as vessel core (default 2).
%     'Polarity'       - 'dark' (default) or 'bright' vessel.
%     'LineWidth'      - number of parallel lines, 1 px apart, whose profiles
%                        are averaged (default 1 = the line only). Wider lines
%                        reduce noise; keep them within a straight vessel segment.
% OUTPUT:
%   diameter  - 1 x N (in pixels); after the temporal filter when 'Robust'.
%   t         - 1 x N.
%   profile   - nPix x N (optional; intensity profiles, as from kymograph,
%               averaged over 'LineWidth' lines).
%   isOutlier - 1 x N logical; frames replaced by the Hampel filter
%               (all false unless 'Robust').
%   info      - struct: rawDiameter (1 x N, per-frame value before the
%               temporal filter), edges (N x 2, wall positions in px from
%               lineStart), level (N x 2, half level at each wall),
%               baseline (N x 2), core (1 x N), spacing (px per sample).
%
% Toolbox-free (base MATLAB only).
%
if nargin < 4, timeVec = []; end
if nargin < 5, method = 'fwhm'; end
% Options may follow the line directly: (stack, p1, p2, 'Robust', true)
optNames = {'subpixel', 'robust', 'window', 'nmad', 'edgefraction', 'corepercentile', 'polarity', 'linewidth'};
if (ischar(timeVec) || isstring(timeVec)) && any(strcmpi(char(timeVec), optNames))
    varargin = [{timeVec, method}, varargin];
    timeVec = []; method = 'fwhm';
elseif (ischar(method) || isstring(method)) && any(strcmpi(char(method), optNames))
    varargin = [{method}, varargin];
    method = 'fwhm';
end
if isempty(method), method = 'fwhm'; end
opt = parseOptions(varargin, optNames);

if numel(lineStart) == 4
    lineEnd = lineStart(3:4);
    lineStart = lineStart(1:2);
end
lineLen = sqrt((lineEnd(1)-lineStart(1))^2 + (lineEnd(2)-lineStart(2))^2);

[profile, ~, t] = kymograph(stack, lineStart, lineEnd, timeVec);
nLines = max(1, round(opt.linewidth));
if nLines > 1 && lineLen > 0
    % Average parallel profiles, 1 px apart, centred on the line
    nrm = [-(lineEnd(2) - lineStart(2)), lineEnd(1) - lineStart(1)] / lineLen;
    for o = (1:nLines) - (nLines + 1) / 2
        if o == 0, continue; end
        profile = profile + kymograph(stack, lineStart + o * nrm, lineEnd + o * nrm, timeVec);
    end
    profile = profile / nLines;
end
N = size(profile, 2);
nPix = size(profile, 1);
spacing = lineLen / max(nPix - 1, 1);    % px between consecutive samples
useThreshold = strcmpi(method, 'threshold');
nEdge = max(2, round(opt.edgefraction * nPix));
nEdge = min(nEdge, max(1, floor(nPix / 2)));

diameter = NaN(1, N);
edges = NaN(N, 2);
P = double(profile);
if strcmpi(opt.polarity, 'bright'), P = -P; end        % vessel = low values from here on
flat = max(P, [], 1) - min(P, [], 1) < eps;

% Background (per wall) and vessel core of every frame
if opt.robust
    core = NaN(1, N);
    for k = 1:N, core(k) = pctl(P(:, k), opt.corepercentile); end
    baseline = [median(P(1:nEdge, :), 1)', median(P(end-nEdge+1:end, :), 1)'];
    % Lumen darkness and background change slowly; their running medians
    % over the filter window ignore frames where a bright object fills the lumen
    [~, ~, core] = robustTimeSeries(core, opt.window, Inf);
    [~, ~, bL] = robustTimeSeries(baseline(:, 1)', opt.window, Inf);
    [~, ~, bR] = robustTimeSeries(baseline(:, 2)', opt.window, Inf);
    baseline = [bL(:), bR(:)];
else
    core = min(P, [], 1);
    baseline = repmat(max(P, [], 1)', 1, 2);
end
levels = (baseline + core(:)) / 2;                         % half level at the left / right wall

for k = 1:N
    p = P(:, k);
    L = levels(k, :);
    if flat(k) || any(~isfinite(L)) || min(baseline(k, :)) - core(k) <= eps, continue; end
    i1 = find(p <= L(1), 1);                          % outermost samples inside the vessel
    i2 = find(p <= L(2), 1, 'last');
    if isempty(i1) || isempty(i2) || i2 < i1, continue; end
    if useThreshold
        diameter(k) = (i2 - i1 + 1) / nPix * lineLen;
        edges(k, :) = ([i1 i2] - 1) * spacing;
        continue;
    end
    if i2 - i1 + 1 < 2, continue; end                 % FWHM needs at least two samples
    if ~opt.subpixel
        diameter(k) = (i2 - i1 + 1) / nPix * lineLen;
        edges(k, :) = ([i1 i2] - 1) * spacing;
        continue;
    end
    % Sub-pixel walls: linear interpolation between the samples that straddle the level
    x1 = i1;
    if i1 > 1 && p(i1 - 1) > p(i1)
        x1 = (i1 - 1) + (p(i1 - 1) - L(1)) / (p(i1 - 1) - p(i1));
    end
    x2 = i2;
    if i2 < nPix && p(i2 + 1) > p(i2)
        x2 = i2 + (L(2) - p(i2)) / (p(i2 + 1) - p(i2));
    end
    edges(k, :) = ([x1 x2] - 1) * spacing;
    diameter(k) = (x2 - x1) * spacing;
end

rawDiameter = diameter;
isOutlier = false(1, N);
if opt.robust
    [diameter, isOutlier] = robustTimeSeries(rawDiameter, opt.window, opt.nmad);
end
info = struct('rawDiameter', rawDiameter, 'edges', edges, 'level', levels, ...
    'baseline', baseline, 'core', core(:)', 'spacing', spacing);
if strcmpi(opt.polarity, 'bright')
    info.level = -info.level; info.baseline = -info.baseline; info.core = -info.core;
end
end

function opt = parseOptions(args, names)
% Name-value pairs (case-insensitive) into a struct with defaults.
opt = struct('subpixel', true, 'robust', false, 'window', 7, 'nmad', 3, ...
    'edgefraction', 0.15, 'corepercentile', 2, 'polarity', 'dark', 'linewidth', 1);
if mod(numel(args), 2) ~= 0
    error('NeuroAnalyzer:vesselDiameter:options', 'Options must be name-value pairs.');
end
for k = 1:2:numel(args)
    name = lower(char(args{k}));
    if ~any(strcmp(name, names))
        error('NeuroAnalyzer:vesselDiameter:options', 'Unknown option ''%s''.', args{k});
    end
    v = args{k + 1};
    if any(strcmp(name, {'subpixel', 'robust'})), v = logical(v); end
    if strcmp(name, 'polarity'), v = char(v); end
    opt.(name) = v;
end
end

function v = pctl(x, p)
% Percentile with linear interpolation; toolbox-free stand-in for prctile.
x = sort(x(isfinite(x(:))));
n = numel(x);
if n == 0, v = NaN; return; end
if n == 1, v = x; return; end
pos = 1 + (n - 1) * p / 100;
lo = floor(pos);
hi = min(lo + 1, n);
v = x(lo) + (pos - lo) * (x(hi) - x(lo));
end
