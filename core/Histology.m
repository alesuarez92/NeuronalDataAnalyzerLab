%% Histology.m
% =========================================================================
% HISTOLOGY AND CULTURE IMAGING - LOAD, ALIGN, COUNT CELLS, CO-LOCALISE
% =========================================================================
% The computations behind the Histology / culture window
% (apps/HistologyApp.m), usable from scripts. An "image" here is one
% field of view: H x W x C (C channels, e.g. nuclei and a marker). Several
% images (sections, time points, wells) can be aligned onto the first one.
%
% Loading
%   [img, info] = Histology.readImage(path)
%       .tif/.tiff (every page is a channel; one RGB page gives its colour
%       channels), .png/.jpg/.bmp, or .mat (variable 'image' H x W x C or
%       'images' H x W x C x N, optional 'channelNames', 'imageNames',
%       'pixelSizeUm', 'truth'). img: double H x W x C x N (N = 1 except for
%       a .mat with several images). info: pixelSizeUm ([] when the file
%       does not say), channelNames, imageNames, truth, source text.
%
% Alignment (coregistration)
%   [aligned, shifts] = Histology.alignChannels(img, refChannel)
%       shift every channel onto refChannel (chromatic shift of the optics)
%   [aligned, shifts] = Histology.alignImagesRigid(imgs, channel)
%       shift images 2..N onto image 1 (FFT phase correlation,
%       registerStackRigid); imgs: cell of H x W x C (same size)
%   [M, rms] = Histology.fitAffine(movingXY, fixedXY)
%       affine transform from >= 3 matching landmark pairs ([x y] rows):
%       [xm ym] = [xf yf 1] * M; rms = fit error at the landmarks (px)
%   out = Histology.warpAffine(img, M, [H W])   apply it (bilinear, 0 outside)
%   out = Histology.shiftImage(img, dy, dx)      move content by (dy, dx) px
%
% Cell counting (one channel)
%   bg  = Histology.background(ch, radiusPx)     rolling-ball-like background
%   thr = Histology.autoThreshold(v)             Otsu, at least 3 noise SD
%   [L, n] = Histology.labelComponents(mask)     8-connected labels
%   m   = Histology.fillHoles(mask)
%   R   = Histology.countCells(ch, opts)         the whole pipeline (below)
%   P   = Histology.positive(L, ch, opts)        per-cell co-localisation
%   S   = Histology.regionCounts(R, P, regions, pixelSizeUm)  counts per region
%
% countCells steps: (1) background = grey-level opening with a square of
% side 2 x BackgroundRadiusPx + 1 (minimum then maximum filter, like a
% rolling ball: removes uneven illumination, keeps objects smaller than
% the square); (2) Gaussian smoothing (SmoothSigmaPx) against pixel noise;
% (3) threshold (automatic: Otsu, but at least 3 robust noise SD above the
% background); (4) holes filled, 8-connected objects; (5) touching cells
% split (distance of each pixel to the object edge; its peaks are cell
% centres; two peaks stay separate only when the object narrows between
% them to less than SplitNeck x the smaller radius; pixels go to the
% nearest centre, weighted by its radius, so the cut runs through the
% neck like a watershed on the distance map); (6) size and shape filter
% (MinAreaPx, MaxAreaPx, MaxElongation = long / short axis).
%
% Base MATLAB only (R2021a); also runs in GNU Octave. No toolboxes.
% =========================================================================

classdef Histology
    properties(Constant)
        ImageExtensions = {'.tif', '.tiff', '.png', '.jpg', '.jpeg', '.bmp', '.mat'}
    end

    methods(Static)

        %% ----------------------------------------------------------------
        %% Loading
        %% readImage - Read one file into H x W x C x N double (see header)
        function [img, info] = readImage(p)
            [~, name, ext] = fileparts(p);
            info = struct('pixelSizeUm', [], 'channelNames', {{}}, 'imageNames', {{}}, ...
                'truth', [], 'source', [name ext]);
            colourPage = false;   % one RGB page: its channels are colours
            switch lower(ext)
                case '.mat'
                    s = load(p);
                    if isfield(s, 'images')
                        img = double(s.images);
                    elseif isfield(s, 'image')
                        img = double(s.image);
                    else
                        error('NeuroAnalyzer:Histology:noImage', ['%s holds no variable ''image'' ' ...
                            '(H x W x C) or ''images'' (H x W x C x N).'], [name ext]);
                    end
                    if isfield(s, 'channelNames'), info.channelNames = cellstr(s.channelNames); end
                    if isfield(s, 'imageNames'), info.imageNames = cellstr(s.imageNames); end
                    if isfield(s, 'pixelSizeUm') && ~isempty(s.pixelSizeUm), info.pixelSizeUm = double(s.pixelSizeUm); end
                    if isfield(s, 'truth'), info.truth = s.truth; end
                case {'.tif', '.tiff'}
                    fi = imfinfo(p);
                    first = imread(p, 1);
                    if numel(fi) == 1
                        img = double(first);
                        colourPage = size(img, 3) >= 3;
                    else
                        img = zeros(size(first, 1), size(first, 2), numel(fi));
                        for k = 1:numel(fi)
                            fr = double(imread(p, k));
                            if size(fr, 3) > 1, fr = mean(fr(:, :, 1:min(3, size(fr, 3))), 3); end
                            img(:, :, k) = fr;
                        end
                    end
                    info.pixelSizeUm = Histology.pixelSizeFromTiff(fi(1));
                otherwise
                    img = double(imread(p));
                    colourPage = size(img, 3) >= 3;
            end
            if ndims(img) == 3 && size(img, 3) == 4 && ~strcmpi(ext, '.mat')
                img = img(:, :, 1:3);                     % drop alpha
            end
            if ndims(img) == 3 && size(img, 3) == 3 && ~strcmpi(ext, '.mat')
                % Grey image stored as RGB: keep one channel
                if isequal(img(:, :, 1), img(:, :, 2), img(:, :, 3)), img = img(:, :, 1); end
            end
            C = size(img, 3);
            if numel(info.channelNames) ~= C
                if C == 3 && colourPage
                    info.channelNames = {'Red', 'Green', 'Blue'};
                else
                    info.channelNames = arrayfun(@(c) sprintf('Channel %d', c), 1:C, 'UniformOutput', false);
                end
            end
            N = size(img, 4);
            if numel(info.imageNames) ~= N
                if N == 1
                    info.imageNames = {name};
                else
                    info.imageNames = arrayfun(@(k) sprintf('%s #%d', name, k), 1:N, 'UniformOutput', false);
                end
            end
        end

        %% pixelSizeFromTiff - Micrometres per pixel from TIFF tags ([] if unknown)
        % ImageJ writes 'unit=micron' (or um / µm / mm / nm) in ImageDescription
        % and pixels per unit in XResolution; standard TIFFs give pixels per
        % centimetre or inch in XResolution / ResolutionUnit.
        function um = pixelSizeFromTiff(fi)
            um = [];
            if ~isfield(fi, 'XResolution') || isempty(fi.XResolution) || fi.XResolution <= 0
                return;
            end
            res = double(fi.XResolution);
            desc = '';
            if isfield(fi, 'ImageDescription') && ischar(fi.ImageDescription), desc = fi.ImageDescription; end
            tok = regexp(desc, 'unit=([^\s]+)', 'tokens', 'once');
            if ~isempty(tok)
                u = lower(strrep(tok{1}, '\', ''));
                scale = struct('micron', 1, 'um', 1, 'mm', 1000, 'nm', 1e-3, 'cm', 1e4);
                u = strrep(strrep(u, char(181), 'u'), 'microns', 'micron');
                if isfield(scale, u), um = scale.(u) / res; end
                return;
            end
            unit = '';
            if isfield(fi, 'ResolutionUnit'), unit = lower(char(fi.ResolutionUnit)); end
            switch unit
                case 'centimeter', um = 1e4 / res;
                case 'inch'
                    um = 25400 / res;
                    if res == 72 || res == 96 || res == 300, um = []; end   % screen / print defaults, not a scale
            end
        end

        %% ----------------------------------------------------------------
        %% Alignment
        %% shiftImage - Move the content of every channel by (dy, dx) px (0 outside)
        function out = shiftImage(img, dy, dx)
            [H, W, C] = size(img);
            [X, Y] = meshgrid(1:W, 1:H);
            out = zeros(size(img));
            for c = 1:C
                v = interp2(img(:, :, c), X - dx, Y - dy, 'linear', NaN);
                v(isnan(v)) = 0;
                out(:, :, c) = v;
            end
        end

        %% alignChannels - Shift each channel onto refChannel; shifts C x 2 [dy dx]
        % shifts(c, :) is how far channel c's content sat from the reference
        % channel before alignment (at most 20 px). Channels show different
        % things (nuclei, a marker), so plain cross-correlation of the
        % high-passed channels is used (phase correlation, which whitens the
        % spectrum, is thrown off when the shapes differ).
        function [aligned, shifts] = alignChannels(img, refChannel)
            if nargin < 2, refChannel = 1; end
            C = size(img, 3);
            shifts = zeros(C, 2);
            aligned = img;
            for c = 1:C
                if c == refChannel, continue; end
                sh = xcorrShift(normalise(img(:, :, refChannel)), normalise(img(:, :, c)), 20);
                shifts(c, :) = sh;
                aligned(:, :, c) = Histology.shiftImage(img(:, :, c), -sh(1), -sh(2));
            end
        end

        %% alignImagesRigid - Shift images 2..N onto image 1 using one channel
        % imgs: cell of H x W x C (same H, W). shifts: N x 2 [dy dx] of each
        % image's content relative to image 1 before alignment; peak: 1 x N
        % correlation peak height (low = unreliable).
        function [aligned, shifts, peak] = alignImagesRigid(imgs, channel)
            if nargin < 2, channel = 1; end
            N = numel(imgs);
            [H, W, ~] = size(imgs{1});
            for k = 2:N
                if size(imgs{k}, 1) ~= H || size(imgs{k}, 2) ~= W
                    error('NeuroAnalyzer:Histology:sizeMismatch', ...
                        'Image %d is %d x %d px, image 1 is %d x %d px: images must be the same size to align them automatically (use landmarks).', ...
                        k, size(imgs{k}, 2), size(imgs{k}, 1), W, H);
                end
            end
            stack = zeros(H, W, N);
            for k = 1:N, stack(:, :, k) = normalise(imgs{k}(:, :, channel)); end
            [~, shifts, info] = registerStackRigid(stack, 1, 'Iterations', 1);
            peak = info.peak;
            aligned = imgs;
            for k = 2:N
                aligned{k} = Histology.shiftImage(imgs{k}, -shifts(k, 1), -shifts(k, 2));
            end
        end

        %% fitAffine - Least-squares affine from landmark pairs
        % movingXY, fixedXY: K x 2 [x y] (K >= 3, not all on one line); the
        % point fixedXY(k, :) in the reference is movingXY(k, :) in the image
        % to align. M: 3 x 2 with [xm ym] = [xf yf 1] * M. rms: fit error (px).
        function [M, rms, resid] = fitAffine(movingXY, fixedXY)
            K = size(fixedXY, 1);
            if K < 3 || size(movingXY, 1) ~= K
                error('NeuroAnalyzer:Histology:landmarks', ...
                    'Landmarks: need at least 3 matching points in both images (have %d and %d).', ...
                    size(fixedXY, 1), size(movingXY, 1));
            end
            A = [fixedXY, ones(K, 1)];
            if rank(A) < 3
                error('NeuroAnalyzer:Histology:collinear', ...
                    'Landmarks: the points lie on one line; spread them over the image.');
            end
            M = A \ movingXY;
            resid = sqrt(sum((A * M - movingXY).^2, 2));
            rms = sqrt(mean(resid.^2));
        end

        %% warpAffine - Resample img onto the reference grid (outSize [H W])
        function out = warpAffine(img, M, outSize)
            if nargin < 3, outSize = [size(img, 1), size(img, 2)]; end
            [X, Y] = meshgrid(1:outSize(2), 1:outSize(1));
            P = [X(:), Y(:), ones(numel(X), 1)] * M;
            C = size(img, 3);
            out = zeros(outSize(1), outSize(2), C);
            for c = 1:C
                v = interp2(img(:, :, c), reshape(P(:, 1), outSize), reshape(P(:, 2), outSize), 'linear', NaN);
                v(isnan(v)) = 0;
                out(:, :, c) = v;
            end
        end

        %% ----------------------------------------------------------------
        %% Cell counting
        %% background - Grey-level opening with a (2r+1) square (min, then max filter)
        function bg = background(ch, radiusPx)
            w = 2 * round(radiusPx) + 1;
            bg = movmin(movmin(ch, w, 1), w, 2);
            bg = movmax(movmax(bg, w, 1), w, 2);
        end

        %% smooth - Gaussian smoothing (sigma px), normalised at the borders
        function out = smooth(ch, sigma)
            if sigma <= 0, out = ch; return; end
            r = ceil(3 * sigma);
            g = exp(-(-r:r).^2 / (2 * sigma^2));
            g = g / sum(g);
            num = conv2(g, g, ch, 'same');
            den = conv2(g, g, ones(size(ch)), 'same');
            out = num ./ den;
        end

        %% autoThreshold - Otsu's threshold, at least 3 robust noise SD above the median
        % v: background-subtracted, smoothed intensities. Also returns the
        % Otsu value and the noise floor (for the explanation shown).
        function [thr, otsuThr, floorThr] = autoThreshold(v)
            v = v(isfinite(v));
            otsuThr = Histology.otsu(v);
            med = median(v);
            noise = 1.4826 * median(abs(v - med));
            floorThr = med + 3 * noise;
            thr = max(otsuThr, floorThr);
        end

        %% otsu - Threshold that best separates two intensity classes (256 bins)
        function t = otsu(v)
            v = double(v(:));
            lo = min(v); hi = max(v);
            if hi <= lo, t = lo; return; end
            nb = 256;
            idx = min(nb, 1 + floor((v - lo) / (hi - lo) * nb));
            h = accumarray(idx, 1, [nb 1]) / numel(v);
            centres = lo + ((1:nb)' - 0.5) * (hi - lo) / nb;
            w0 = cumsum(h);
            m0 = cumsum(h .* centres);
            mT = m0(end);
            sb = (mT * w0 - m0).^2 ./ (w0 .* (1 - w0));
            sb(~isfinite(sb)) = 0;
            % Middle of the best bins (a gap between the classes gives a plateau)
            best = find(sb >= max(sb) * (1 - 1e-9));
            k = (best(1) + best(end)) / 2;
            t = lo + k * (hi - lo) / nb;
        end

        %% labelComponents - 8-connected components of a logical mask
        % Runs of foreground pixels in each column are joined with the runs
        % they touch in the previous column (union-find). L: double labels
        % 1..n in order of the first pixel (column-major), 0 = background.
        function [L, n] = labelComponents(mask)
            mask = logical(mask);
            [H, W] = size(mask);
            L = zeros(H, W);
            d = diff([false(1, W); mask; false(1, W)], 1, 1);
            [rs, cs] = find(d == 1);
            [re, ~] = find(d == -1);
            re = re - 1;
            nR = numel(rs);
            n = 0;
            if nR == 0, return; end
            parent = 1:nR;
            first = accumarray(cs, (1:nR)', [W 1], @min, 0);
            last = accumarray(cs, (1:nR)', [W 1], @max, 0);
            for c = 2:W
                if first(c) == 0 || first(c - 1) == 0, continue; end
                i = first(c - 1); j = first(c);
                while i <= last(c - 1) && j <= last(c)
                    if rs(j) <= re(i) + 1 && rs(i) <= re(j) + 1
                        a = i; while parent(a) ~= a, a = parent(a); end
                        b = j; while parent(b) ~= b, b = parent(b); end
                        if a ~= b, parent(max(a, b)) = min(a, b); end
                    end
                    if re(i) < re(j), i = i + 1; else, j = j + 1; end
                end
            end
            root = zeros(nR, 1);
            for k = 1:nR
                a = k; while parent(a) ~= a, a = parent(a); end
                root(k) = a;
            end
            % Every root is the smallest run index of its component, so
            % numbering the roots in order numbers components by first pixel
            labOfRoot = cumsum(root == (1:nR)');
            lab = labOfRoot(root);
            n = labOfRoot(end);
            for k = 1:nR
                L(rs(k):re(k), cs(k)) = lab(k);
            end
        end

        %% fillHoles - Fill background regions that do not touch the border
        function m = fillHoles(mask)
            m = logical(mask);
            [Lb, nb] = Histology.labelComponents(~m);
            if nb == 0, return; end
            border = unique([Lb(1, :), Lb(end, :), Lb(:, 1)', Lb(:, end)']);
            hole = Lb > 0 & ~ismember(Lb, border);
            m(hole) = true;
        end

        %% defaultCountOptions - Defaults of countCells (pixels)
        function o = defaultCountOptions()
            o = struct('BackgroundRadiusPx', 15, 'SmoothSigmaPx', 1, 'Threshold', [], ...
                'Split', true, 'SplitNeck', 0.85, 'MinAreaPx', 20, 'MaxAreaPx', 2000, ...
                'MaxElongation', 2.5);
        end

        %% countCells - Background, threshold, objects, split, filter (see header)
        % R: struct with
        %   L          H x W labels of the counted cells (1..n)
        %   rejected   H x W labels of rejected objects (1..m)
        %   n          number of cells
        %   centroid   n x 2 [x y] px;  areaPx  n x 1;  elongation  n x 1
        %   threshold  used; thresholdAuto (true when automatic), otsu, noiseFloor
        %   nObjects   objects after thresholding (before splitting)
        %   nSplit     extra cells gained by splitting touching cells
        %   nRejected  struct tooSmall, tooLarge, elongated
        %   corrected  background-subtracted, smoothed channel (for display)
        %   options    the options used
        function R = countCells(ch, opts)
            o = Histology.defaultCountOptions();
            if nargin >= 2 && ~isempty(opts)
                f = fieldnames(opts);
                for k = 1:numel(f), o.(f{k}) = opts.(f{k}); end
            end
            ch = double(ch);
            corr = ch - Histology.background(ch, o.BackgroundRadiusPx);
            corr = Histology.smooth(corr, o.SmoothSigmaPx);
            [autoThr, otsuThr, floorThr] = Histology.autoThreshold(corr);
            R.thresholdAuto = isempty(o.Threshold) || ~(o.Threshold > 0);
            if R.thresholdAuto, thr = autoThr; else, thr = o.Threshold; end
            R.threshold = thr; R.otsu = otsuThr; R.noiseFloor = floorThr;
            mask = Histology.fillHoles(corr > thr);
            [L0, n0] = Histology.labelComponents(mask);
            R.nObjects = n0;
            if o.Split && n0 > 0
                [L1, n1] = splitTouching(L0, n0, o);
            else
                L1 = L0; n1 = n0;
            end
            R.nSplit = n1 - n0;
            props = regionProps(L1, n1);
            tooSmall = props.area < o.MinAreaPx;
            tooLarge = props.area > o.MaxAreaPx;
            elong = ~tooSmall & ~tooLarge & props.elongation > o.MaxElongation;
            keep = ~(tooSmall | tooLarge | elong);
            R.nRejected = struct('tooSmall', nnz(tooSmall), 'tooLarge', nnz(tooLarge), 'elongated', nnz(elong));
            % Renumber kept cells left to right (by centroid x, then y)
            kept = find(keep);
            [~, ord] = sortrows(props.centroid(kept, :), [1 2]);
            kept = kept(ord);
            map = zeros(n1 + 1, 1);
            map(kept + 1) = 1:numel(kept);
            R.L = reshape(map(L1 + 1), size(L1));
            rej = find(~keep);
            mapR = zeros(n1 + 1, 1);
            mapR(rej + 1) = 1:numel(rej);
            R.rejected = reshape(mapR(L1 + 1), size(L1));
            R.n = numel(kept);
            R.centroid = props.centroid(kept, :);
            R.areaPx = props.area(kept);
            R.elongation = props.elongation(kept);
            R.corrected = corr;
            R.options = o;
        end

        %% positive - Is each cell positive in channel ch? (co-localisation)
        % A cell is positive when at least MinFraction (default 0.5) of its
        % pixels are above the channel's threshold (automatic as in
        % countCells, after the same background subtraction and smoothing).
        % P: struct threshold, thresholdAuto, fraction (n x 1), meanIntensity
        % (n x 1, background-subtracted), isPositive (n x 1 logical), nPositive.
        function P = positive(L, ch, opts)
            o = struct('BackgroundRadiusPx', 15, 'SmoothSigmaPx', 1, 'Threshold', [], 'MinFraction', 0.5);
            if nargin >= 3 && ~isempty(opts)
                f = fieldnames(opts);
                for k = 1:numel(f), o.(f{k}) = opts.(f{k}); end
            end
            corr = double(ch) - Histology.background(double(ch), o.BackgroundRadiusPx);
            corr = Histology.smooth(corr, o.SmoothSigmaPx);
            P.thresholdAuto = isempty(o.Threshold) || ~(o.Threshold > 0);
            if P.thresholdAuto, P.threshold = Histology.autoThreshold(corr); else, P.threshold = o.Threshold; end
            n = max([0; L(:)]);
            fg = L > 0;
            area = accumarray(L(fg), 1, [n 1]);
            above = accumarray(L(fg), double(corr(fg) > P.threshold), [n 1]);
            P.fraction = above ./ max(area, 1);
            P.meanIntensity = accumarray(L(fg), corr(fg), [n 1]) ./ max(area, 1);
            P.isPositive = P.fraction >= o.MinFraction;
            P.nPositive = nnz(P.isPositive);
            P.options = o;
        end

        %% regionCounts - Cells, area, density and positives per region
        % regions: struct array with name and xy (K x 2 polygon, px) — an
        % empty xy means the whole image. P: cell array of positive()
        % results (one per other channel, may be empty) with names
        % channelNames. S: struct array name, nCells, areaMm2, perMm2,
        % nPositive (1 x numel(P)), percentPositive, nAllPositive (positive
        % in every listed channel) and inRegion (n x 1 logical).
        function S = regionCounts(R, P, regions, pixelSizeUm, imageSize)
            if nargin < 5, imageSize = size(R.L); end
            if isempty(regions), regions = struct('name', 'Whole image', 'xy', zeros(0, 2)); end
            S = struct('name', {}, 'nCells', {}, 'areaMm2', {}, 'perMm2', {}, 'nPositive', {}, ...
                'percentPositive', {}, 'nAllPositive', {}, 'inRegion', {});
            pxMm2 = (pixelSizeUm / 1000)^2;
            for r = 1:numel(regions)
                xy = regions(r).xy;
                if isempty(xy)
                    in = true(R.n, 1);
                    areaPx = prod(imageSize(1:2));
                else
                    in = inpolygon(R.centroid(:, 1), R.centroid(:, 2), xy(:, 1), xy(:, 2));
                    areaPx = Histology.polygonAreaPx(xy, imageSize);
                end
                s.name = regions(r).name;
                s.nCells = nnz(in);
                s.areaMm2 = areaPx * pxMm2;
                s.perMm2 = s.nCells / max(s.areaMm2, eps);
                s.nPositive = zeros(1, numel(P));
                allPos = in;
                for c = 1:numel(P)
                    s.nPositive(c) = nnz(in & P{c}.isPositive);
                    allPos = allPos & P{c}.isPositive;
                end
                s.percentPositive = 100 * s.nPositive / max(s.nCells, 1);
                s.nAllPositive = nnz(allPos);
                if isempty(P), s.nAllPositive = 0; end
                s.inRegion = in;
                S(end + 1) = s; %#ok<AGROW>
            end
        end

        %% polygonAreaPx - Pixels of the image inside a polygon (clipped to the image)
        function a = polygonAreaPx(xy, imageSize)
            [X, Y] = meshgrid(1:imageSize(2), 1:imageSize(1));
            a = nnz(inpolygon(X, Y, xy(:, 1), xy(:, 2)));
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% normalise - High-pass (minus a 10 px Gaussian blur), zero mean, unit SD
% Registration then follows the cells, not uneven illumination.
function v = normalise(v)
    v = double(v);
    v = v - Histology.smooth(v, 10);
    s = std(v(:));
    if s > 0, v = (v - mean(v(:))) / s; end
end

%% regionProps - Area, centroid [x y] and elongation of labels 1..n
function p = regionProps(L, n)
    fg = find(L > 0);
    lab = L(fg);
    [y, x] = ind2sub(size(L), fg);
    a = accumarray(lab, 1, [n 1]);
    a1 = max(a, 1);
    cx = accumarray(lab, x, [n 1]) ./ a1;
    cy = accumarray(lab, y, [n 1]) ./ a1;
    sxx = accumarray(lab, x.^2, [n 1]) ./ a1 - cx.^2 + 1/12;
    syy = accumarray(lab, y.^2, [n 1]) ./ a1 - cy.^2 + 1/12;
    sxy = accumarray(lab, x .* y, [n 1]) ./ a1 - cx .* cy;
    tr = sxx + syy;
    dt = sqrt(max((sxx - syy).^2 / 4 + sxy.^2, 0));
    l1 = tr / 2 + dt; l2 = max(tr / 2 - dt, eps);
    p.area = a;
    p.centroid = [cx cy];
    p.elongation = sqrt(l1 ./ l2);
end

%% splitTouching - Split objects at necks (distance-map peaks, see header)
function [Lout, n] = splitTouching(L, n0, o)
    [H, W] = size(L);
    Lout = L;
    n = n0;
    fg = find(L > 0);
    [yy, xx] = ind2sub([H W], fg);
    lab = L(fg);
    area = accumarray(lab, 1, [n0 1]);
    r0 = accumarray(lab, yy, [n0 1], @min); r1 = accumarray(lab, yy, [n0 1], @max);
    c0 = accumarray(lab, xx, [n0 1], @min); c1 = accumarray(lab, xx, [n0 1], @max);
    minR = 2;
    for k = 1:n0
        if area(k) < 2 * max(o.MinAreaPx, 1), continue; end
        rr = max(r0(k) - 1, 1):min(r1(k) + 1, H);
        cc = max(c0(k) - 1, 1):min(c1(k) + 1, W);
        M = L(rr, cc) == k;
        D = distanceToEdge(M);
        mx = movmax(movmax(D, 3, 1), 3, 2);
        cand = find(M & D >= mx & D >= minR);
        if numel(cand) < 2, continue; end
        [vals, ord] = sort(D(cand), 'descend');
        cand = cand(ord);
        if numel(cand) > 300, cand = cand(1:300); vals = vals(1:300); end
        [cy, cx] = ind2sub(size(M), cand);
        % Peaks in order of height; a lower peak starts a new cell only when
        % every higher kept peak is unreachable from it without passing
        % through pixels closer to the edge than SplitNeck x its own height
        keep = 1;
        for j = 2:numel(cand)
            Lv = Histology.labelComponents(D >= o.SplitNeck * vals(j));
            if ~any(Lv(cand(keep)) == Lv(cand(j)))
                keep(end + 1) = j; %#ok<AGROW>
            end
        end
        if numel(keep) < 2, continue; end
        [py, px] = find(M);
        score = (px - cx(keep)').^2 + (py - cy(keep)').^2 - (vals(keep)').^2;
        [~, owner] = min(score, [], 2);
        sub = zeros(size(M));
        sub(sub2ind(size(M), py, px)) = owner;
        block = Lout(rr, cc);
        for q = 2:numel(keep)
            n = n + 1;
            block(sub == q) = n;
        end
        Lout(rr, cc) = block;
    end
end

%% distanceToEdge - Distance of each object pixel to the object edge
% (to the nearest background pixel centre, minus half a pixel)
function D = distanceToEdge(M)
    D = zeros(size(M));
    Mp = false(size(M) + 2);
    Mp(2:end-1, 2:end-1) = M;
    near = conv2(double(Mp), ones(3), 'same') > 0 & ~Mp;   % background touching the object
    [by, bx] = find(near);
    by = by - 1; bx = bx - 1;                               % back to M coordinates
    [fy, fx] = find(M);
    d = zeros(numel(fy), 1);
    step = 2000;
    for s = 1:step:numel(fy)
        e = min(s + step - 1, numel(fy));
        d(s:e) = sqrt(min((fy(s:e) - by').^2 + (fx(s:e) - bx').^2, [], 2)) - 0.5;
    end
    D(sub2ind(size(M), fy, fx)) = d;
end

%% xcorrShift - Displacement [dy dx] of b's content relative to a (|d| <= maxShift)
% Peak of the FFT cross-correlation (zero-padded, no wrap-around), refined
% with a 3-point parabola in y and in x.
function d = xcorrShift(a, b, maxShift)
    [H, W] = size(a);
    F = conj(fft2(a, 2 * H, 2 * W)) .* fft2(b, 2 * H, 2 * W);
    C = fftshift(real(ifft2(F)));
    cy = H + 1; cx = W + 1;                  % zero shift after fftshift
    ry = cy + (-maxShift:maxShift); rx = cx + (-maxShift:maxShift);
    sub = C(ry, rx);
    [~, k] = max(sub(:));
    [iy, ix] = ind2sub(size(sub), k);
    iy = min(max(iy, 2), size(sub, 1) - 1); ix = min(max(ix, 2), size(sub, 2) - 1);
    d = [iy - maxShift - 1 + parabolaPeak(sub(iy - 1:iy + 1, ix)), ...
         ix - maxShift - 1 + parabolaPeak(sub(iy, ix - 1:ix + 1))];
end

%% parabolaPeak - Offset (-0.5..0.5) of the vertex of a parabola through 3 values
function o = parabolaPeak(v)
    den = v(1) - 2 * v(2) + v(3);
    if den >= 0, o = 0; return; end
    o = max(-0.5, min(0.5, 0.5 * (v(1) - v(3)) / den));
end
