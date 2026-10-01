%% ScalpMap.m
% =========================================================================
% SCALP MAP - THE VOLTAGE OVER THE HEAD (OR SKULL) FROM ONE VALUE PER
% ELECTRODE
% =========================================================================
% Interpolates one value per electrode (for example the mean voltage of an
% ERP in a time window) over the head of an electrode layout
% (core/EEGLayout.m) and draws it:
%   scalp layouts  spherical spline on the head (Perrin F, Pernier J,
%                  Bertrand O, Echallier JF (1989), Electroencephalogr Clin
%                  Neurophysiol 72:184-187) with stiffness m = 4 and 50
%                  Legendre terms, without regularization, so the map
%                  passes through every electrode's value: the matrix of
%                  MNE-Python's spherical spline interpolation
%                  (_make_interpolation_matrix with alpha=None; for bad
%                  channels MNE adds 1e-5 to the diagonal, which moves the
%                  map 5-10% off the electrodes). EEGLAB uses 7 terms: up
%                  to 3% of the peak different, mostly beyond the outer
%                  electrodes. Drawn over the disk of EEGLayout.project out
%                  to the outermost electrode (at least the head line).
%   skull layouts  flat interpolation in mm from bregma: a thin-plate spline
%                  (Duchon J (1977), Lecture Notes in Mathematics 571:85-100;
%                  as scipy RBFInterpolator 'thin_plate_spline' with a linear
%                  term), drawn only inside the outline of the electrodes
%                  (their convex hull), since nothing is known outside it.
% Both pass exactly through the electrodes' values.
%
%   M = ScalpMap.make(L, values, Name, Value)
%       L: an EEGLayout (kind 'scalp' or 'skull'); values: one number per
%       channel of L (NaN = left out, e.g. a bad channel). Channels without
%       a position are left out too. Options:
%       'Labels'    channel names of values (default L.labels); matched to
%                   L.labels by name, case ignored; channels not in L are
%                   left out
%       'GridSize'  points across the map (default 101)
%   v = ScalpMap.sphericalSpline(from, values, to, Name, Value)
%       Values (n x k: k maps at once) at directions from (n x 3) carried
%       to directions to (m x 3); rows need not be unit length. Options
%       'Stiffness' (4), 'Terms' (50), 'Lambda' (0: added to the diagonal).
%   v = ScalpMap.thinPlate(from, values, to)
%       Values (n x k) at 2-D points from (n x 2) carried to points to (m x 2).
%   lim = ScalpMap.limits(maps)
%       Colour limits [-a a] shared by maps (a struct array of make): a =
%       the largest absolute value of their maps and electrodes.
%   h = ScalpMap.plot(ax, M, Name, Value)
%       The map with contour lines, the head (or skull) outline and the
%       electrodes used (dots; channels left out with a position: rings).
%       Options 'CLim' ([] = ScalpMap.limits(M)), 'Title' (''), 'Contours'
%       (true), 'Labels' (false: electrode names), 'FontSize' (8). h.map,
%       h.contours, h.outline, h.electrodes, h.left, h.labels.
%   h = ScalpMap.colorScale(ax, lim, label)
%       A vertical colour scale from lim(1) to lim(2) on axes ax.
%   c = ScalpMap.colormap(n)
%       Blue (negative) - white (0) - red (positive), n x 3 (default 256).
%   s = ScalpMap.describe(M)
%       The interpolation in one plain sentence (window and methods text).
%
% M fields:
%   kind       'scalp' | 'skull'
%   method     'spherical spline' | 'thin-plate spline'
%   x, y       grid vectors in drawing coordinates (EEGLayout.project:
%              scalp r = 1 at the head line, nose up; skull mm, right and
%              front +)
%   z          numel(y) x numel(x) values (NaN outside the map)
%   labels     1 x n channels used; xy n x 2 their drawing coordinates;
%              values n x 1 their values
%   left       channels left out (no value or bad, or no position);
%              leftXY: drawing coordinates of those that have a position
%   radius     scalp: radius of the map (drawing units); skull: NaN
%   hull       skull: k x 2 outline of the map (mm); scalp: []
%   range      [min max] of z and the values
% Errors: NeuroAnalyzer:eeg:invalid (no layout, too few electrodes, wrong
% number of values), NeuroAnalyzer:eeg:badOption.
% Toolboxes: none.
% =========================================================================

classdef ScalpMap
    methods(Static)

        %% make - Interpolate one value per channel of layout L over the head or skull
        function M = make(L, values, varargin)
            o = EEGLayout.options(struct('Labels', [], 'GridSize', 101), varargin);
            if ~isstruct(L) || ~isfield(L, 'kind') || ~any(strcmp(L.kind, {'scalp', 'skull'}))
                error('NeuroAnalyzer:eeg:invalid', ['A scalp map needs an electrode layout with positions ' ...
                    '(Electrode layout' char(8230) ').']);
            end
            n = numel(L.labels);
            values = double(values(:));
            if isempty(o.Labels)
                if numel(values) ~= n
                    error('NeuroAnalyzer:eeg:invalid', '%d values for %d channels of the layout.', numel(values), n);
                end
                v = values;
            else
                names = EEGLayout.cellRow(o.Labels);
                if numel(values) ~= numel(names)
                    error('NeuroAnalyzer:eeg:invalid', '%d values for %d channel names.', numel(values), numel(names));
                end
                v = NaN(n, 1);
                for k = 1:n
                    i = find(strcmpi(names, L.labels{k}), 1);
                    if ~isempty(i), v(k) = values(i); end
                end
            end
            xy = EEGLayout.project(L);
            hasPos = all(isfinite(xy), 2);
            use = hasPos & isfinite(v);
            N = max(11, round(o.GridSize));
            M = struct('kind', L.kind, 'method', '', 'x', [], 'y', [], 'z', [], ...
                'labels', {L.labels(use)}, 'xy', xy(use, :), 'values', v(use), ...
                'left', {L.labels(~use)}, 'leftXY', xy(~use & hasPos, :), 'radius', NaN, 'hull', [], ...
                'range', [NaN NaN]);
            if strcmp(L.kind, 'skull')
                P = xy(use, :);
                if sum(use) < 3 || rank(P - mean(P, 1), 1e-6 * max(1, max(abs(P(:))))) < 2
                    error('NeuroAnalyzer:eeg:invalid', ['A flat map needs at least 3 electrodes with a value ' ...
                        'that are not on one line (%d here).'], sum(use));
                end
                k = convhull(P(:, 1), P(:, 2));
                M.hull = P(k, :);
                lo = min(P, [], 1);
                hi = max(P, [], 1);
                step = max(hi - lo) / (N - 1);
                M.x = lo(1):step:hi(1) + step / 2;
                M.y = lo(2):step:hi(2) + step / 2;
                M.x = min(M.x, hi(1));
                M.y = min(M.y, hi(2));
                [X, Y] = meshgrid(M.x, M.y);
                inside = inpolygon(X, Y, M.hull(:, 1), M.hull(:, 2));
                Z = NaN(size(X));
                Z(inside) = ScalpMap.thinPlate(P, v(use), [X(inside), Y(inside)]);
                M.method = 'thin-plate spline';
            else
                if sum(use) < 3
                    error('NeuroAnalyzer:eeg:invalid', ['A scalp map needs at least 3 electrodes with a ' ...
                        'position and a value (%d here).'], sum(use));
                end
                r = sqrt(sum(xy(use, :) .^ 2, 2));
                R = max(1, max(r));
                M.radius = R;
                M.x = linspace(-R, R, N);
                M.y = M.x;
                [X, Y] = meshgrid(M.x, M.y);
                inside = X .^ 2 + Y .^ 2 <= R ^ 2 * (1 + 1e-9);
                rr = sqrt(X(inside) .^ 2 + Y(inside) .^ 2);
                polar = rr * pi / 2;                    % r = angle from the vertex / 90 deg
                az = atan2(X(inside), Y(inside));
                to = [sin(polar) .* sin(az), sin(polar) .* cos(az), cos(polar)];
                Z = NaN(size(X));
                Z(inside) = ScalpMap.sphericalSpline(L.pos(use, :), v(use), to);
                M.method = 'spherical spline';
            end
            M.z = Z;
            M.range = [min([Z(:); M.values]) max([Z(:); M.values])];
        end

        %% sphericalSpline - Spherical spline interpolation (Perrin et al. 1989)
        % V(r) = c0 + sum_i C_i g(cos(r, r_i)), g(x) = 1/(4 pi) sum_n (2n + 1) /
        % (n (n + 1))^m P_n(x); [G + lambda I, 1; 1', 0] [C; c0] = [V; 0].
        function out = sphericalSpline(from, values, to, varargin)
            o = EEGLayout.options(struct('Stiffness', 4, 'Terms', 50, 'Lambda', 0), varargin);
            from = ScalpMap.unitRows(from);
            to = ScalpMap.unitRows(to);
            n = size(from, 1);
            values = double(values);
            if size(values, 1) ~= n, values = values.'; end
            if size(values, 1) ~= n
                error('NeuroAnalyzer:eeg:invalid', '%d values for %d positions.', numel(values), n);
            end
            G = ScalpMap.gFunction(from * from', o.Stiffness, o.Terms);
            G(1:n + 1:end) = G(1:n + 1:end) + o.Lambda;
            A = [G, ones(n, 1); ones(1, n), 0];
            W = pinv(A) * [values; zeros(1, size(values, 2))];
            out = [ScalpMap.gFunction(to * from', o.Stiffness, o.Terms), ones(size(to, 1), 1)] * W;
        end

        %% thinPlate - Thin-plate spline in the plane, with a linear term
        % V(p) = a0 + a1 x + a2 y + sum_i w_i phi(|p - p_i|), phi(r) = r^2 log r.
        function out = thinPlate(from, values, to)
            n = size(from, 1);
            values = double(values);
            if size(values, 1) ~= n, values = values.'; end
            if size(values, 1) ~= n
                error('NeuroAnalyzer:eeg:invalid', '%d values for %d positions.', numel(values), n);
            end
            c = mean(from, 1);                       % centred for a well-conditioned system
            from = from - c;
            to = to - c;
            P = [ones(n, 1), from];
            A = [ScalpMap.phi(ScalpMap.distances(from, from)), P; P', zeros(3)];
            W = A \ [values; zeros(3, size(values, 2))];
            out = [ScalpMap.phi(ScalpMap.distances(to, from)), ones(size(to, 1), 1), to] * W;
        end

        %% limits - Shared, symmetric colour limits of several maps
        function lim = limits(maps)
            a = 0;
            for k = 1:numel(maps)
                a = max([a, abs(maps(k).range)]);
            end
            if ~(a > 0), a = 1; end
            lim = [-a a];
        end

        %% plot - The map, contours, outline and electrodes on axes or uiaxes
        function h = plot(ax, M, varargin)
            o = EEGLayout.options(struct('CLim', [], 'Title', '', 'Contours', true, 'Labels', false, ...
                'FontSize', 8), varargin);
            lim = o.CLim;
            if isempty(lim), lim = ScalpMap.limits(M); end
            wasHeld = ishold(ax);
            hold(ax, 'on');
            h = struct('map', [], 'contours', [], 'outline', [], 'electrodes', [], 'left', [], 'labels', []);
            h.map = imagesc(ax, M.x, M.y, M.z, 'AlphaData', double(isfinite(M.z)));
            if o.Contours && diff(M.range) > 0
                levels = linspace(lim(1), lim(2), 13);
                levels = levels(2:end - 1);
                levels = levels(levels > M.range(1) & levels < M.range(2));
                if ~isempty(levels)
                    [~, h.contours] = contour(ax, M.x, M.y, M.z, levels, 'LineColor', [0.25 0.25 0.3], ...
                        'LineWidth', 0.5);
                end
            end
            [h.outline, axLim] = EEGLayout.drawOutline(ax, M.kind, [M.xy; M.leftXY], o.FontSize);
            if ~isempty(M.leftXY)
                h.left = plot(ax, M.leftXY(:, 1), M.leftXY(:, 2), 'o', 'LineStyle', 'none', 'MarkerSize', 4, ...
                    'Color', [0.35 0.38 0.42], 'Tag', 'ScalpMap:left');
            end
            h.electrodes = plot(ax, M.xy(:, 1), M.xy(:, 2), '.', 'LineStyle', 'none', 'MarkerSize', 9, ...
                'Color', [0.1 0.1 0.12], 'Tag', 'ScalpMap:electrodes');
            if o.Labels && ~isempty(M.labels)
                h.labels = text(ax, M.xy(:, 1), M.xy(:, 2), M.labels, 'FontSize', o.FontSize, ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'Color', [0.1 0.1 0.12]);
            end
            colormap(ax, ScalpMap.colormap());
            set(ax, 'CLim', lim, 'YDir', 'normal', 'DataAspectRatio', [1 1 1], ...
                'XLim', axLim(:, 1)', 'YLim', axLim(:, 2)');
            if strcmp(M.kind, 'skull')
                axis(ax, 'on');
            else
                axis(ax, 'off');
            end
            if ~isempty(o.Title)
                title(ax, o.Title, 'Interpreter', 'none', 'FontWeight', 'normal');
            end
            if ~wasHeld, hold(ax, 'off'); end
        end

        %% colorScale - A vertical colour scale on its own axes
        function h = colorScale(ax, lim, label)
            if nargin < 3, label = ''; end
            c = ScalpMap.colormap();
            v = linspace(lim(1), lim(2), size(c, 1));
            h = image(ax, [0.25 0.75], v, repmat(reshape(c, [], 1, 3), 1, 2));
            set(ax, 'YDir', 'normal', 'XTick', [], 'YAxisLocation', 'right', 'XLim', [0 1], ...
                'YLim', lim, 'Box', 'on', 'Layer', 'top');
            ylabel(ax, label);
        end

        %% colormap - Blue (negative) - white (0) - red (positive)
        function c = colormap(n)
            if nargin < 1, n = 256; end
            anchors = [0.09 0.20 0.50; 0.35 0.55 0.82; 0.97 0.97 0.97; 0.90 0.45 0.35; 0.55 0.05 0.10];
            t = linspace(0, 1, size(anchors, 1));
            c = interp1(t, anchors, linspace(0, 1, n));
        end

        %% describe - The interpolation in one sentence
        function s = describe(M)
            if strcmp(M.kind, 'skull')
                s = sprintf(['Flat map (thin-plate spline in mm from bregma) from %d electrodes, drawn only ' ...
                    'inside their outline'], numel(M.labels));
            else
                s = sprintf('Spherical spline over the head (m = 4, 50 Legendre terms) from %d electrodes', ...
                    numel(M.labels));
            end
            if ~isempty(M.left)
                s = sprintf('%s; left out: %s', s, EEGLayout.listText(M.left));
            end
            s = [s '.'];
        end
    end

    methods(Static, Hidden)

        %% gFunction - g(x) = 1/(4 pi) sum_{n=1..N} (2n + 1) / (n (n + 1))^m P_n(x)
        function g = gFunction(x, m, N)
            x = max(-1, min(1, x));
            p0 = ones(size(x));
            p1 = x;
            g = (3 / 2 ^ m) * p1;
            for k = 2:N
                p2 = ((2 * k - 1) * x .* p1 - (k - 1) * p0) / k;
                g = g + (2 * k + 1) / (k * (k + 1)) ^ m * p2;
                p0 = p1;
                p1 = p2;
            end
            g = g / (4 * pi);
        end

        %% phi - Thin-plate kernel r^2 log r (0 at r = 0)
        function f = phi(r)
            f = zeros(size(r));
            k = r > 0;
            f(k) = r(k) .^ 2 .* log(r(k));
        end

        %% distances - Euclidean distances between the rows of a and b
        function d = distances(a, b)
            d = sqrt(max(0, sum(a .^ 2, 2) + sum(b .^ 2, 2)' - 2 * (a * b')));
        end

        %% unitRows - Rows scaled to unit length
        function p = unitRows(p)
            p = double(p);
            p = p ./ sqrt(sum(p .^ 2, 2));
        end
    end
end
