function s = demoHistology(opts)
% demoHistology - Synthetic culture images for cell counting, co-localisation and alignment.
%
% Two images of the same field of a culture (day 1 and day 3), each with
% two channels, 400 x 400 px at 1 um per pixel (0.16 mm2), with known
% ground truth:
%   * Channel 1 "Nuclei (DAPI)": 60 nuclei (soft disks, radius 4.5-6.5 px,
%     brightness 0.45-0.75): 48 single nuclei and 6 touching pairs
%     (edges touching), 30 in Region A (left half, x <= 200) and
%     30 in Region B (right half).
%   * Channel 2 "Marker (GFP)": a soft disk 3 px larger than the nucleus in
%     marker-positive cells: 24 of 60 on day 1, 39 of 60 on day 3 (every
%     day-1 positive stays positive).
%   * Things that must NOT be counted: 20 small bright specks (debris,
%     under 15 px) and one long fibre (60 x 5 px) in channel 1.
%   * Uneven illumination (a broad bright patch and a left-right ramp,
%     fixed to the microscope, not the sample) and noise (SD 0.025).
%   * Day 3 was imaged after the dish was put back on the stage: its content
%     is shifted by [dy dx] = [6.4 -9.2] px relative to day 1.
%   * Channel 2 is shifted by [1.0 2.0] px relative to channel 1 in both
%     images (chromatic shift of the optics).
% Cells stay at least 25 px from the border (visible in both images) and
% 6 px from the region boundary x = 200.5.
%
% Usage:
%   s = demoHistology();
%   s = demoHistology(struct('Seed', 7));
%
% OUTPUT: struct with
%   images       - 400 x 400 x 2 x 2 single (H x W x channel x image)
%   channelNames - {'Nuclei (DAPI)', 'Marker (GFP)'}
%   imageNames   - {'Culture, day 1', 'Culture, day 3'}
%   pixelSizeUm  - 1
%   truth        - struct: centers (60 x 2 [x y], day-1 coordinates),
%                  radii, pairId (0 = single), positive (60 x 2 logical,
%                  day 1 / day 3), shifts (2 x 2 [dy dx] per image),
%                  chromaticShift ([dy dx] of channel 2), regions (struct
%                  name / xy polygons), counts (struct per region: nCells,
%                  nPositive (1 x 2 per day), areaMm2, perMm2), nCells,
%                  nPositive (1 x 2), debrisXY, fibre ([x1 y1; x2 y2]).
%
% Deterministic (RandStream 'mt19937ar', fixed seed). Base MATLAB only.

if nargin < 1 || isempty(opts), opts = struct(); end
seed = 20260925;
if isfield(opts, 'Seed'), seed = opts.Seed; end
rs = RandStream('mt19937ar', 'Seed', seed);

H = 400; W = 400; px = 1;
border = 25; midX = 200.5; midGap = 6;
[X, Y] = meshgrid(1:W, 1:H);

% --- Place nuclei: 24 singles + 3 pairs in each half ---
centers = zeros(0, 2); radii = zeros(0, 1); pairId = zeros(0, 1);
blocked = zeros(0, 3);                      % [x y r] of placed units (for spacing)
nextPair = 0;
for half = 1:2
    for kind = [ones(1, 3) * 2, ones(1, 24)]   % pairs first (need more room)
        for attempt = 1:5000
            r = 4.5 + 2 * rand(rs);
            if kind == 1
                c = [border + rand(rs) * (W - 2 * border), border + rand(rs) * (H - 2 * border)];
                pts = c; rr = r;
            else
                r2 = 4.5 + 2 * rand(rs);
                ang = 2 * pi * rand(rs);
                c = [border + rand(rs) * (W - 2 * border), border + rand(rs) * (H - 2 * border)];
                d = r + r2;
                pts = [c; c + d * [cos(ang) sin(ang)]];
                rr = [r; r2];
            end
            inHalf = all(ifelse(half == 1, pts(:, 1) <= midX - midGap - rr, pts(:, 1) >= midX + midGap + rr));
            inside = all(pts(:, 1) >= border & pts(:, 1) <= W - border & pts(:, 2) >= border & pts(:, 2) <= H - border);
            if ~inHalf || ~inside, continue; end
            ok = true;
            for q = 1:size(pts, 1)
                if ~isempty(blocked) && any(hypot(blocked(:, 1) - pts(q, 1), blocked(:, 2) - pts(q, 2)) < blocked(:, 3) + rr(q) + 8)
                    ok = false; break;
                end
            end
            if ~ok, continue; end
            if kind == 2, nextPair = nextPair + 1; pid = nextPair; else, pid = 0; end
            centers = [centers; pts]; radii = [radii; rr]; pairId = [pairId; pid * ones(numel(rr), 1)]; %#ok<AGROW>
            blocked = [blocked; pts, rr]; %#ok<AGROW>
            break;
        end
    end
end
nCell = size(centers, 1);
bright = 0.45 + 0.3 * rand(rs, nCell, 1);

% --- Marker-positive cells: 24 on day 1, 15 more on day 3 ---
ord = randperm(rs, nCell);
positive = false(nCell, 2);
positive(ord(1:24), 1) = true;
positive(ord(1:39), 2) = true;

% --- Debris (away from cells) and one fibre ---
debris = zeros(0, 2);
while size(debris, 1) < 20
    p = [border + rand(rs) * (W - 2 * border), border + rand(rs) * (H - 2 * border)];
    if all(hypot(centers(:, 1) - p(1), centers(:, 2) - p(2)) > radii + 12)
        debris(end + 1, :) = p; %#ok<AGROW>
    end
end
fibre = [];
for attempt = 1:5000
    a = [midX + 40 + rand(rs) * 100, border + 20 + rand(rs) * (H - 2 * border - 100)];
    b = a + 60 * [cos(1.2) sin(1.2)];
    tt = linspace(0, 1, 61)';
    seg = a + tt * (b - a);
    dmin = min(min(hypot(centers(:, 1) - seg(:, 1)', centers(:, 2) - seg(:, 2)') - radii));
    ddeb = min(min(hypot(debris(:, 1) - seg(:, 1)', debris(:, 2) - seg(:, 2)')));
    if dmin > 15 && ddeb > 10 && b(2) < H - border, fibre = [a; b]; break; end
end

% --- Microscope: illumination and shifts ---
illum = 0.10 + 0.20 * exp(-((X - 120).^2 + (Y - 300).^2) / (2 * 150^2)) + 0.08 * X / W;
shifts = [0 0; 6.4 -9.2];
chroma = [1.0 2.0];

images = zeros(H, W, 2, 2, 'single');
for k = 1:2
    for ch = 1:2
        sh = shifts(k, :) + (ch == 2) * chroma;
        Xs = X - sh(2); Ys = Y - sh(1);          % sample coordinates seen by each pixel
        sig = zeros(H, W);
        if ch == 1
            for i = 1:nCell
                sig = max(sig, bright(i) * softDisk(Xs, Ys, centers(i, :), radii(i)));
            end
            for i = 1:size(debris, 1)
                sig = sig + 1.2 * exp(-((Xs - debris(i, 1)).^2 + (Ys - debris(i, 2)).^2) / (2 * 0.8^2));
            end
            sig = max(sig, 0.55 * softSegment(Xs, Ys, fibre(1, :), fibre(2, :), 2.5));
            img = illum + sig + 0.025 * randn(rs, H, W);
        else
            for i = find(positive(:, k))'
                sig = max(sig, 0.5 * softDisk(Xs, Ys, centers(i, :), radii(i) + 3));
            end
            img = 0.5 * illum + sig + 0.025 * randn(rs, H, W);
        end
        images(:, :, ch, k) = single(img);
    end
end

% --- Regions and counts (day-1 coordinates) ---
regions = struct('name', {'Region A', 'Region B'}, ...
    'xy', {[0.5 0.5; midX 0.5; midX H + 0.5; 0.5 H + 0.5], [midX 0.5; W + 0.5 0.5; W + 0.5 H + 0.5; midX H + 0.5]});
counts = struct('name', {}, 'nCells', {}, 'nPositive', {}, 'areaMm2', {}, 'perMm2', {});
for r = 1:2
    in = inpolygon(centers(:, 1), centers(:, 2), regions(r).xy(:, 1), regions(r).xy(:, 2));
    areaMm2 = (W / 2) * H * (px / 1000)^2;
    counts(r) = struct('name', regions(r).name, 'nCells', nnz(in), ...
        'nPositive', [nnz(in & positive(:, 1)), nnz(in & positive(:, 2))], ...
        'areaMm2', areaMm2, 'perMm2', nnz(in) / areaMm2);
end

s.images = images;
s.channelNames = {'Nuclei (DAPI)', 'Marker (GFP)'};
s.imageNames = {'Culture, day 1', 'Culture, day 3'};
s.pixelSizeUm = px;
s.truth = struct('centers', centers, 'radii', radii, 'pairId', pairId, 'positive', positive, ...
    'shifts', shifts, 'chromaticShift', chroma, 'regions', regions, 'counts', counts, ...
    'nCells', nCell, 'nPositive', sum(positive, 1), 'debrisXY', debris, 'fibre', fibre);
end

%% softDisk - 1 inside a disk of radius r, smooth 0.7 px edge
function v = softDisk(X, Y, c, r)
    v = 1 ./ (1 + exp((hypot(X - c(1), Y - c(2)) - r) / 0.7));
end

%% softSegment - 1 within halfWidth of the segment a-b, smooth edge
function v = softSegment(X, Y, a, b, halfWidth)
    ab = b - a;
    t = ((X - a(1)) * ab(1) + (Y - a(2)) * ab(2)) / sum(ab.^2);
    t = min(max(t, 0), 1);
    d = hypot(X - (a(1) + t * ab(1)), Y - (a(2) + t * ab(2)));
    v = 1 ./ (1 + exp((d - halfWidth) / 0.7));
end

%% ifelse - One of two values
function v = ifelse(cond, a, b)
    if cond, v = a; else, v = b; end
end
