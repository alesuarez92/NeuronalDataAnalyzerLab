function [masks, props, labels, thr] = detectCellsFromCorrelation(corrImg, varargin)
% detectCellsFromCorrelation - Find active cells as compact bright blobs of a correlation image.
%
% Thresholds the local correlation image (see localCorrelationImage),
% splits the result into connected components (8-connected) and keeps
% the components that look like cell bodies: area between 'MinArea' and
% 'MaxArea' and not elongated (vessels and their walls, whose pixels also
% co-fluctuate, form long bands). Holes inside a component (e.g. a dim
% nucleus) are filled. Cells are returned sorted by mean correlation,
% most active first. Touching cells merge into one component; lower the
% threshold's sensitivity (higher 'Threshold' or 'NSigma') to separate them.
%
% Method: automatic threshold = median + NSigma x robust SD of the image
% (robust SD = 1.4826 x median absolute deviation), since most pixels are
% background. Elongation = sqrt(lambda1 / lambda2) of the covariance of the
% component's pixel coordinates (major / minor axis ratio; 1 for a disk).
% Connected components use bwlabel when the Image Processing Toolbox is
% installed and a toolbox-free flood fill otherwise (same result).
%
% Usage:
%   masks = detectCellsFromCorrelation(localCorrelationImage(stack));
%   [masks, props, labels, thr] = detectCellsFromCorrelation(C, 'MinArea', 30, 'MaxArea', 400);
%   masks = detectCellsFromCorrelation(C, struct('Threshold', 0.5));
%
% INPUT:
%   corrImg - H x W correlation image.
%   Options (name-value or struct, case-insensitive):
%     'Threshold'     - correlation threshold, or 'auto' (default).
%     'NSigma'        - robust SDs above the median for 'auto' (default 4).
%     'MinThreshold'  - lower bound of the automatic threshold (default 0.2).
%     'MinArea'       - smallest cell, px (default 20).
%     'MaxArea'       - largest cell, px (default 1000).
%     'MaxElongation' - largest major / minor axis ratio (default 3).
%     'FillHoles'     - true (default) | false.
%     'MaxCells'      - keep at most this many, most correlated first (default Inf).
%     'BorderMargin'  - ignore pixels closer than this to the image border, px
%                       (default 0). After motion correction use the largest
%                       shift: border pixels there are edge copies whose time
%                       series are spuriously correlated.
%     'UseToolbox'    - true (default): use bwlabel when available.
% OUTPUT:
%   masks  - 1 x K cell array of H x W logical masks.
%   props  - 1 x K struct array: centroid ([x y], px), area (px),
%            meanCorr, peakCorr, elongation, bbox ([x y w h]).
%   labels - H x W double, 0 = background, k = cell k.
%   thr    - threshold that was applied.
%
% Base MATLAB; the Image Processing Toolbox (bwlabel) is optional.
%
opt = parseOptions(varargin);
C = double(corrImg);
[H, W] = size(C);
finite = isfinite(C);

if ischar(opt.threshold) || isstring(opt.threshold)
    v = C(finite);
    m = median(v);
    thr = max(opt.minthreshold, m + opt.nsigma * 1.4826 * median(abs(v - m)));
else
    thr = opt.threshold;
end
bw = finite & C >= thr;
mg = min(max(0, round(opt.bordermargin)), floor(min(H, W) / 2));
if mg > 0
    bw([1:mg, end-mg+1:end], :) = false;
    bw(:, [1:mg, end-mg+1:end]) = false;
end

useBw = opt.usetoolbox && exist('bwlabel', 'file') == 2;
if useBw
    L = bwlabel(bw, 8);
else
    L = labelComponents(bw, 8);
end

nComp = max(L(:));
masks = {};
props = struct('centroid', {}, 'area', {}, 'meanCorr', {}, 'peakCorr', {}, ...
    'elongation', {}, 'bbox', {});
if nComp == 0
    labels = zeros(H, W);
    return;
end
pix = accumarray(L(L > 0), find(L > 0), [nComp 1], @(v) {v});
for k = 1:nComp
    idx = pix{k};
    m = false(H, W);
    m(idx) = true;
    if opt.fillholes
        m = fillHoles(m);
        idx = find(m);
    end
    area = numel(idx);
    if area < opt.minarea || area > opt.maxarea, continue; end
    [yy, xx] = ind2sub([H W], idx);
    ev = sort(eig(cov([xx yy], 1) + eye(2) / 12), 'descend');   % + pixel extent
    elong = sqrt(ev(1) / ev(2));
    if elong > opt.maxelongation, continue; end
    masks{end + 1} = m; %#ok<AGROW>
    props(end + 1) = struct('centroid', [mean(xx) mean(yy)], 'area', area, ... %#ok<AGROW>
        'meanCorr', mean(C(idx)), 'peakCorr', max(C(idx)), 'elongation', elong, ...
        'bbox', [min(xx), min(yy), max(xx) - min(xx) + 1, max(yy) - min(yy) + 1]);
end

% Most correlated first, at most MaxCells
[~, order] = sort([props.meanCorr], 'descend');
order = order(1:min(numel(order), opt.maxcells));
masks = masks(order);
props = props(order);
labels = zeros(H, W);
for k = 1:numel(masks)
    labels(masks{k} & labels == 0) = k;
end
end

%% labelComponents - Toolbox-free connected-component labelling (4 or 8 connectivity)
% Components are numbered in the order of their first pixel in
% column-major order, as bwlabel does.
function L = labelComponents(bw, conn)
[H, W] = size(bw);
Hp = H + 2;
P = false(Hp, W + 2);
P(2:end-1, 2:end-1) = bw;
LP = zeros(Hp, W + 2);
nb = [-1, 1, -Hp, Hp];
if conn == 8, nb = [nb, -Hp - 1, -Hp + 1, Hp - 1, Hp + 1]; end
queue = zeros(nnz(P), 1);
n = 0;
for seed = find(P)'
    if LP(seed) > 0, continue; end
    n = n + 1;
    LP(seed) = n;
    queue(1) = seed; head = 1; tail = 1;
    while head <= tail
        cur = queue(head); head = head + 1;
        nbr = cur + nb;
        nbr = nbr(P(nbr) & LP(nbr) == 0);
        LP(nbr) = n;
        queue(tail + 1:tail + numel(nbr)) = nbr;
        tail = tail + numel(nbr);
    end
end
L = LP(2:end-1, 2:end-1);
end

%% fillHoles - Fill background regions enclosed by the mask (4-connected background)
function m = fillHoles(m)
[r, c] = find(m);
r1 = max(1, min(r) - 1); r2 = min(size(m, 1), max(r) + 1);
c1 = max(1, min(c) - 1); c2 = min(size(m, 2), max(c) + 1);
sub = m(r1:r2, c1:c2);
Lb = labelComponents(~sub, 4);
edgeLabels = unique([Lb(1, :), Lb(end, :), Lb(:, 1)', Lb(:, end)']);
holes = Lb > 0 & ~ismember(Lb, edgeLabels);
sub(holes) = true;
m(r1:r2, c1:c2) = sub;
end

%% parseOptions - Struct or name-value pairs into lower-case option struct
function opt = parseOptions(args)
opt = struct('threshold', 'auto', 'nsigma', 4, 'minthreshold', 0.2, 'minarea', 20, ...
    'maxarea', 1000, 'maxelongation', 3, 'fillholes', true, 'maxcells', Inf, 'usetoolbox', true, ...
    'bordermargin', 0);
if numel(args) == 1 && isstruct(args{1})
    s = args{1};
    f = fieldnames(s);
    args = cell(1, 2 * numel(f));
    for k = 1:numel(f)
        args{2*k - 1} = f{k}; args{2*k} = s.(f{k});
    end
end
if mod(numel(args), 2) ~= 0
    error('NeuroAnalyzer:detectCells:options', 'Options must be a struct or name-value pairs.');
end
for k = 1:2:numel(args)
    name = lower(char(args{k}));
    if ~isfield(opt, name)
        error('NeuroAnalyzer:detectCells:options', 'Unknown option ''%s''.', args{k});
    end
    opt.(name) = args{k + 1};
end
if isempty(opt.threshold), opt.threshold = 'auto'; end
end
