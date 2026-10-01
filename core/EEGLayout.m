%% EEGLayout.m
% =========================================================================
% EEG LAYOUT - WHERE EVERY ELECTRODE SITS, IN ONE ORIENTATION
% =========================================================================
% Electrode positions come in many orientations and units (EEGLAB: x =
% nose, y = left ear; FieldTrip, BrainVision, EGI, BIDS: mostly x = right
% ear, y = nose; mm, cm, m or a unit sphere). EEGLayout turns all of them
% into one frame, so the same electrode from different files lands in the
% same place:
%   x = towards the right ear, y = towards the nose, z = up
% Scalp layouts are directions (unit vectors from the centre of the
% head); rodent (skull) layouts are mm from bregma: x = medial-lateral
% (right +), y = anterior-posterior (front +), z = 0. Works on the EEG
% struct of core/io/EEGSource.m (eeg.labels, eeg.chanlocs, eeg.coordSystem).
%
% Channels without positions in the file are placed by name on the 10-5
% system, computed here with the idealized spherical construction of
% Oostenveld R, Praamstra P (2001), Clin Neurophysiol 112:713-719 (10-5
% system) and Jurcak V, Tsuzuki D, Dan I (2007), NeuroImage 34:1600-1611,
% with the equator through Nz, T9, Iz and T10 (345 positions). Next to
% positions from a file, a 10-5 position (by name or by hand) is put on
% that head: its angle from the vertex is scaled to fit the channels that
% have both (most files and real heads have Fpz, T7, Oz and T8 near the
% equator, the template 18 deg above it).
%
%   [labels, pos] = EEGLayout.template()
%       The 345 positions of the 10-5 system (labels 1 x 345, pos 345 x 3
%       unit vectors), rows from front to back, each row from left to right.
%   [name, how] = EEGLayout.cleanName(label)
%       The template name of a channel ('' if none) and how it was found:
%       'exact' | 'case' | 'alias' (T3 -> T7, T4 -> T8, T5 -> P7, T6 -> P8) |
%       'cleaned' (a leading 'EEG ' / 'EEG_' / 'EEG-' or a trailing
%       reference suffix -REF, -LE, -AR, -AVG, -A1, -A2, -M1, -M2 dropped) |
%       ''. A cell array of labels gives cell arrays.
%   [pos, kind, frame, notes] = EEGLayout.fromFile(eeg)
%       The file's positions (eeg.chanlocs, eeg.coordSystem) in the frame
%       above: pos channels x 3 (NaN rows = no position), kind 'scalp' |
%       'skull' | 'none', frame (plain words of the conversion done), notes.
%   L = EEGLayout.fromEEG(eeg, Name, Value)
%       The layout of a recording. Options:
%       'Source'    'auto' (default: the file's positions, the other
%                   channels by name on the 10-5 system) | 'template' (by
%                   name only, the file's positions are ignored) | 'file'
%                   (the file's positions only)
%       'Positions' a struct of electrode positions (as readElectrodes
%                   returns: labels, xyz in the frame above, unit, kind,
%                   format, frame, notes, fiducials), used instead of the
%                   file's positions; matched to the channels by name
%                   (cleaned, case ignored)
%       'Edits'     struct array label / as / ap / ml: placements made by
%                   hand. 'as' places a channel on the 10-5 position of that
%                   name (scalp); ap / ml in mm from bregma (skull). An edit
%                   with neither leaves the channel without a position.
%   xy = EEGLayout.project(L)
%       Drawing coordinates (channels x 2): scalp azimuthal equidistant
%       from the vertex, r = angle from the vertex / 90 deg (the head line
%       Nz-T9-Iz-T10 at r = 1; nose up, right ear right); skull [ml ap] mm.
%   h = EEGLayout.plot(ax, L, Name, Value)
%       Head (scalp) or skull outline, electrodes coloured by status and
%       their names, on axes or uiaxes. Options 'Labels' (true),
%       'MarkerSize' (7), 'FontSize' (8). h.outline, h.electrodes (one
%       line per status; UserData = channel indices), h.labels.
%   lines = EEGLayout.describe(L)
%       The layout in plain sentences (overview and check list).
%
% L (layout) fields:
%   kind       'scalp' | 'skull' | 'none'
%   labels     1 x n channel names
%   pos        n x 3 positions (scalp: unit vectors; skull: mm from bregma);
%              NaN rows = no position
%   source     1 x n 'file' | 'template' | 'positions file' | 'edited' | ''
%   as         1 x n template name a channel was placed on, or ''
%   status     1 x n 'ok' | 'renamed' | 'none' | 'duplicate' | 'outside'
%   frame      plain words: what the positions mean and how they were turned
%   notes      1 x n cell of plain sentences worth knowing
%   check      matched (channels with a position), renamed (n x 2 cell:
%              from, to), missing (no position), duplicated (two channels
%              with the same 10-5 name, scalp directions less than 2 deg
%              apart or skull positions less than 0.2 mm apart), outside
%              (scalp: more than 120 deg from the vertex; skull: more than
%              15 mm from bregma)
%   summary    one line, e.g. '33 of 34 channels placed: 32 from the file,
%              1 by name (10-5 system); no position: VEOG.'
%   confirmed  false until the user confirms the layout
%
% Orientation check: when at least 3 channels with file positions also
% have 10-5 names, the median angle between their file and template
% directions is computed; above 45 deg, the other common frame (x = right
% ear, y = nose <-> x = nose, y = left ear) is used when it fits much
% better (below 45 deg and at most half the angle; a note says so),
% otherwise a note reports the problem.
% Positions at one height (at least 3, or a frame that names bregma) are a
% rodent skull layout; all others are scalp layouts.
% Scalp centre: a least-squares sphere fit when at least 6 positions
% spread over the head and the fitted radius is between 0.5 and 2 times
% the median distance from the origin; otherwise the origin of the file.
% Errors: NeuroAnalyzer:eeg:badOption, NeuroAnalyzer:eeg:invalid.
% Toolboxes: none.
% =========================================================================

classdef EEGLayout
    methods(Static)

        %% template - The 345 positions of the 10-5 system (unit vectors)
        % Midline: sagittal angle s from Nz (0) over Cz (90) to Iz (180).
        % Short rows (N, NFp, Fp; O, OI, I) lie on the elevation contour of
        % their midline point, 18 and 9 deg of azimuth from the midline.
        % Full rows: position 7 on the 10 % contour (elevation 18 deg,
        % azimuth s), 9 on the equator, 9h half-way; 7h, 5, ..., 1h divide
        % the arc from 7 to the midline (on the circle through 7, the
        % midline point and 8) into eighths. Even numbers mirror the odd.
        function [labels, pos] = template()
            persistent L P
            if isempty(L)
                [L, P] = EEGLayout.buildTemplate();
            end
            labels = L;
            pos = P;
        end

        %% cleanName - Template name of a channel and how it was found
        function [name, how] = cleanName(label)
            if iscell(label)
                name = cell(size(label));
                how = cell(size(label));
                for k = 1:numel(label)
                    [name{k}, how{k}] = EEGLayout.cleanName(label{k});
                end
                return;
            end
            name = '';
            how = '';
            s = strtrim(EEGLayout.asText(label));
            if isempty(s), return; end
            [name, how] = EEGLayout.findName(s);
            if ~isempty(name), return; end
            c = EEGLayout.cleanText(s);
            if strcmp(c, s) || isempty(c) || any(c == '-'), return; end
            name = EEGLayout.findName(c);
            if ~isempty(name), how = 'cleaned'; end
        end

        %% fromFile - The file's positions turned to x = right ear, y = nose, z = up
        function [pos, kind, frame, notes] = fromFile(eeg)
            labels = EEGLayout.cellRow(eeg.labels);
            n = numel(labels);
            raw = NaN(n, 3);
            cl = eeg.chanlocs;
            if numel(cl) == n && n > 0
                raw = [EEGLayout.field(cl, 'x'), EEGLayout.field(cl, 'y'), EEGLayout.field(cl, 'z')];
            end
            cs = '';
            if isfield(eeg, 'coordSystem'), cs = EEGLayout.asText(eeg.coordSystem); end
            f = EEGLayout.readFrame(cs);
            pre = {};
            if ~any(all(isfinite(raw), 2)) && numel(cl) == n && n > 0
                % EEGLAB polar positions only (theta 0 = nose, +90 = right ear;
                % radius = angle from the vertex / 180 deg)
                th = EEGLayout.field(cl, 'theta');
                rd = EEGLayout.field(cl, 'radius');
                ok = isfinite(th) & isfinite(rd);
                if any(ok)
                    p = rd(ok) * 180;
                    raw(ok, :) = [sind(p) .* sind(th(ok)), sind(p) .* cosd(th(ok)), cosd(p)];
                    f = EEGLayout.frameStruct('EEGLAB polar positions', eye(3), '', true, false);
                    f.centre = false;
                    pre{end + 1} = 'The file gives polar positions only (theta, radius); they were used.';
                end
            end
            [pos, kind, frame, notes] = EEGLayout.finish(labels, raw, f);
            notes = [pre, notes];
        end

        %% fromEEG - The layout of a recording (file positions, names, edits)
        function L = fromEEG(eeg, varargin)
            o = EEGLayout.options(struct('Source', 'auto', 'Positions', [], 'Edits', []), varargin);
            src = lower(EEGLayout.asText(o.Source));
            if ~any(strcmp(src, {'auto', 'template', 'file'}))
                error('NeuroAnalyzer:eeg:badOption', ...
                    'Unknown source ''%s'' (use auto, template or file).', EEGLayout.asText(o.Source));
            end
            labels = EEGLayout.cellRow(eeg.labels);
            n = numel(labels);
            L = struct('kind', 'none', 'labels', {labels}, 'pos', NaN(n, 3), ...
                'source', {repmat({''}, 1, n)}, 'as', {repmat({''}, 1, n)}, ...
                'status', {repmat({'none'}, 1, n)}, 'frame', '', 'notes', {{}}, ...
                'check', struct(), 'summary', '', 'confirmed', false);
            renamed = false(1, n);
            renamedTo = repmat({''}, 1, n);

            % ---- Positions from the file (or a positions file) ----
            if ~strcmp(src, 'template')
                if ~isempty(o.Positions)
                    [p, kind, frame, notes, matchName] = EEGLayout.fromPositions(labels, o.Positions);
                    what = 'positions file';
                    renamed = ~cellfun(@isempty, matchName);
                    renamedTo = matchName;
                else
                    [p, kind, frame, notes] = EEGLayout.fromFile(eeg);
                    what = 'file';
                end
                has = all(isfinite(p), 2)';
                L.pos(has, :) = p(has, :);
                L.source(has) = {what};
                renamed = renamed & has;
                L.kind = kind;
                L.frame = frame;
                L.notes = notes;
            end

            % ---- The other channels by name on the 10-5 system ----
            % (on the head of the file's positions when there are some)
            scale = 1;
            if ~strcmp(L.kind, 'skull')
                scale = EEGLayout.templateScale(EEGLayout.cleanName(labels), L.pos);
            end
            if ~strcmp(src, 'file') && ~strcmp(L.kind, 'skull')
                [names, how] = EEGLayout.cleanName(labels);
                [tl, tp] = EEGLayout.template();
                todo = find(~all(isfinite(L.pos), 2)' & ~cellfun(@isempty, names));
                for k = todo
                    i = find(strcmp(tl, names{k}), 1);
                    L.pos(k, :) = EEGLayout.scaleTemplate(tp(i, :), scale);
                    L.source{k} = 'template';
                    L.as{k} = names{k};
                    if any(strcmp(how{k}, {'alias', 'cleaned'}))
                        renamed(k) = true;
                        renamedTo{k} = names{k};
                    end
                end
                if ~isempty(todo)
                    words = '10-5 positions by name (idealized spherical head; x = right ear, y = nose, z = up)';
                    if strcmp(L.kind, 'none')
                        L.kind = 'scalp';
                        L.frame = words;
                    else
                        L.frame = sprintf('%s; the other channels: %s', L.frame, words);
                    end
                end
            end

            % ---- Placements by hand ----
            if ~isempty(o.Edits)
                [L, renamed] = EEGLayout.applyEdits(L, o.Edits, renamed, scale);
            end
            if scale ~= 1 && any(strcmp(L.source, 'template') | (strcmp(L.source, 'edited') & ~cellfun(@isempty, L.as)))
                L.frame = sprintf(['%s; the 10-5 positions on this head: angles from the vertex x %.2f ' ...
                    '(fitted on the channels with both)'], L.frame, scale);
            end
            L = EEGLayout.review(L, renamed, renamedTo);
        end

        %% project - Drawing coordinates (scalp: from the vertex, r = 1 at the head line; skull: mm)
        function xy = project(L)
            n = size(L.pos, 1);
            xy = NaN(n, 2);
            has = all(isfinite(L.pos), 2);
            if ~any(has), return; end
            p = L.pos(has, :);
            switch L.kind
                case 'skull'
                    xy(has, :) = p(:, 1:2);
                otherwise
                    p = p ./ sqrt(sum(p .^ 2, 2));
                    polar = acos(max(-1, min(1, p(:, 3)))) * 180 / pi;
                    az = atan2(p(:, 1), p(:, 2));
                    r = polar / 90;
                    xy(has, :) = [r .* sin(az), r .* cos(az)];
            end
        end

        %% plot - Head or skull outline with the electrodes coloured by status
        function h = plot(ax, L, varargin)
            o = EEGLayout.options(struct('Labels', true, 'MarkerSize', 7, 'FontSize', 8), varargin);
            xy = EEGLayout.project(L);
            has = all(isfinite(xy), 2)';
            wasHeld = ishold(ax);
            hold(ax, 'on');
            grey = [0.35 0.38 0.42];
            outline = [];
            if strcmp(L.kind, 'skull')
                pts = [xy(has, :); 0 0];
                lo = min(pts, [], 1);
                hi = max(pts, [], 1);
                c = (lo + hi) / 2;
                ab = max(sqrt(2) * (hi - lo) / 2 + 1.5, [3 4]);
                t = linspace(0, 2 * pi, 181);
                outline = [outline, plot(ax, c(1) + ab(1) * cos(t), c(2) + ab(2) * sin(t), '-', ...
                    'Color', grey, 'LineWidth', 1.5)];
                dy = ab(2) * sqrt(max(0, 1 - (c(1) / ab(1)) ^ 2));
                outline = [outline, plot(ax, [0 0], c(2) + [-dy dy], '--', 'Color', grey)];
                outline = [outline, plot(ax, [-0.6 0.6], [0 0], '-', 'Color', grey, 'LineWidth', 1.5)];
                outline = [outline, plot(ax, [0 0], [-0.6 0.6], '-', 'Color', grey, 'LineWidth', 1.5)];
                outline = [outline, text(ax, 0.7, -0.5, 'bregma', 'Color', grey, 'FontSize', o.FontSize, ...
                    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top')];
                xlabel(ax, 'Medial-lateral (mm, right +)');
                ylabel(ax, 'Anterior-posterior (mm, front +)');
                axis(ax, 'on');
                lim = [c - ab - 1; c + ab + 1];
            else
                t = linspace(0, 2 * pi, 181);
                outline = [outline, plot(ax, cos(t), sin(t), '-', 'Color', grey, 'LineWidth', 1.5)];
                outline = [outline, plot(ax, [-0.09 0 0.09], [0.996 1.1 0.996], '-', 'Color', grey, 'LineWidth', 1.5)];
                e = linspace(-pi / 2, pi / 2, 31);
                outline = [outline, plot(ax, 1 + 0.05 * cos(e), 0.16 * sin(e), '-', 'Color', grey, 'LineWidth', 1.5)];
                outline = [outline, plot(ax, -1 - 0.05 * cos(e), 0.16 * sin(e), '-', 'Color', grey, 'LineWidth', 1.5)];
                r = 1.15;
                if any(has), r = max(r, max(sqrt(sum(xy(has, :) .^ 2, 2))) + 0.1); end
                lim = [-r -r; r r];
                axis(ax, 'off');
            end
            [statuses, colours] = EEGLayout.statusColours();
            electrodes = [];
            for s = 1:numel(statuses)
                i = find(has & strcmp(L.status, statuses{s}));
                if isempty(i), continue; end
                electrodes = [electrodes, plot(ax, xy(i, 1), xy(i, 2), 'o', 'LineStyle', 'none', ...
                    'MarkerSize', o.MarkerSize, 'MarkerFaceColor', colours(s, :), ...
                    'MarkerEdgeColor', 0.6 * colours(s, :), 'Tag', ['EEGLayout:' statuses{s}], ...
                    'UserData', i)]; %#ok<AGROW>
            end
            labels = [];
            if o.Labels && any(has)
                i = find(has);
                if strcmp(L.kind, 'skull')
                    at = [xy(i, 1), xy(i, 2) + 0.3];
                    align = repmat({'center', 'bottom'}, numel(i), 1);
                else
                    % Names above the dots; near or beyond the head line, outwards
                    % from the centre, so that the line, nose and ears do not cross them
                    at = [xy(i, 1), xy(i, 2) + 0.04];
                    align = repmat({'center', 'bottom'}, numel(i), 1);
                    r = sqrt(sum(xy(i, :) .^ 2, 2));
                    u = xy(i, :) ./ max(r, eps);
                    edge = r > 0.85;
                    rr = max(r + 0.06, 1.06);
                    rr(abs(u(:, 2)) < 0.3) = max(rr(abs(u(:, 2)) < 0.3), 1.11);                          % ears
                    rr(abs(u(:, 1)) < 0.15 & u(:, 2) > 0) = max(rr(abs(u(:, 1)) < 0.15 & u(:, 2) > 0), 1.13);  % nose
                    at(edge, :) = u(edge, :) .* rr(edge);
                    align(edge & u(:, 1) < -0.4, 1) = {'right'};
                    align(edge & u(:, 1) > 0.4, 1) = {'left'};
                    align(edge & abs(u(:, 2)) <= 0.4, 2) = {'middle'};
                    align(edge & u(:, 2) < -0.4, 2) = {'top'};
                    if any(edge), lim = lim + [-0.15 -0.15; 0.15 0.15]; end   % room for the names outside
                end
                labels = text(ax, at(:, 1), at(:, 2), L.labels(i), 'FontSize', o.FontSize, ...
                    'Color', [0.15 0.15 0.2]);
                set(labels, {'HorizontalAlignment', 'VerticalAlignment'}, align);
            end
            set(ax, 'DataAspectRatio', [1 1 1], 'XLim', lim(:, 1)', 'YLim', lim(:, 2)');
            if ~wasHeld, hold(ax, 'off'); end
            h = struct('outline', outline, 'electrodes', electrodes, 'labels', labels);
        end

        %% describe - The layout in plain sentences
        function lines = describe(L)
            lines = {L.summary};
            if ~isempty(L.frame)
                lines{end + 1} = sprintf('Positions: %s.', L.frame);
            end
            c = L.check;
            if ~isempty(c.renamed)
                % By name: the channel takes the 10-5 position of the name; positions
                % file: the channel takes the position the file gives under that name
                fromFile = cellfun(@(ch) any(strcmp(L.source(strcmp(L.labels, ch)), 'positions file')), ...
                    c.renamed(:, 1))';
                parts = cell(1, size(c.renamed, 1));
                for k = 1:numel(parts)
                    if fromFile(k)
                        parts{k} = sprintf('%s placed at %s of the positions file', c.renamed{k, 1}, c.renamed{k, 2});
                    else
                        parts{k} = sprintf('%s treated as %s', c.renamed{k, 1}, c.renamed{k, 2});
                    end
                end
                lines{end + 1} = sprintf('Names read as other names: %s.', EEGLayout.listText(parts));
            end
            if ~isempty(c.missing)
                parts = c.missing;
                for k = 1:numel(parts)
                    why = EEGLayout.nonScalpKind(parts{k});
                    if ~isempty(why), parts{k} = sprintf('%s (%s)', parts{k}, why); end
                end
                lines{end + 1} = sprintf('No position: %s.', EEGLayout.listText(parts));
            end
            pairs = EEGLayout.duplicatePairs(L);
            if ~isempty(pairs)
                parts = arrayfun(@(k) sprintf('%s and %s', L.labels{pairs(k, 1)}, L.labels{pairs(k, 2)}), ...
                    1:size(pairs, 1), 'UniformOutput', false);
                lines{end + 1} = sprintf('In the same place: %s.', EEGLayout.listText(parts, '; '));
            end
            if ~isempty(c.outside)
                if strcmp(L.kind, 'skull')
                    lines{end + 1} = sprintf('More than 15 mm from bregma: %s.', EEGLayout.listText(c.outside));
                else
                    lines{end + 1} = sprintf('Far below the head line (more than 120 deg from the vertex): %s.', ...
                        EEGLayout.listText(c.outside));
                end
            end
            lines = [lines, EEGLayout.cellRow(L.notes)];
            if ~L.confirmed && ~strcmp(L.kind, 'none')
                lines{end + 1} = 'Not confirmed yet: check that every electrode sits in the right place.';
            end
        end
    end

    methods(Static, Hidden)

        %% buildTemplate - Compute the 10-5 positions (see template)
        function [labels, pos] = buildTemplate()
            sph = @(az, el) [cosd(el) .* sind(az), cosd(el) .* cosd(az), sind(el)];
            mirror = @(p) [-p(:, 1), p(:, 2:3)];
            rows = {'N', 0; 'NFp', 9; 'Fp', 18; 'AFp', 27; 'AF', 36; 'AFF', 45; 'F', 54; 'FFC', 63; ...
                'FC', 72; 'FCC', 81; 'C', 90; 'CCP', 99; 'CP', 108; 'CPP', 117; 'P', 126; 'PPO', 135; ...
                'PO', 144; 'POO', 153; 'O', 162; 'OI', 171; 'I', 180};
            lateral = struct('FFC', 'FFT', 'FC', 'FT', 'FCC', 'FTT', 'C', 'T', 'CCP', 'TTP', 'CP', 'TP', 'CPP', 'TPP');
            labels = {};
            pos = zeros(0, 3);
            for r = 1:size(rows, 1)
                pre = rows{r, 1};
                s = rows{r, 2};
                mid = [0, cosd(s), sind(s)];
                if s < 27 || s > 153
                    % Short row on the elevation contour of its midline point
                    if s < 90
                        el = s; az = [-18 -9];
                    else
                        el = 180 - s; az = [-162 -171];
                    end
                    left = sph(az', [el; el]);
                    names = {'1', '1h', 'z', '2h', '2'};
                    P = [left; mid; mirror(left([2 1], :))];
                else
                    p7 = sph(-s, 18);
                    arc = EEGLayout.circleArc(p7, mid, mirror(p7), (1:7)' / 8);
                    % left, from the ear to the midline: 9, 9h, 7, 7h, 5, 5h, 3, 3h, 1, 1h
                    left = [sph(-s, 0); sph(-s, 9); p7; arc];
                    odd = {'9', '9h', '7', '7h', '5', '5h', '3', '3h', '1', '1h'};
                    even = {'10', '10h', '8', '8h', '6', '6h', '4', '4h', '2', '2h'};
                    names = [odd, {'z'}, fliplr(even)];
                    P = [left; mid; mirror(flipud(left))];
                end
                rowNames = strcat(pre, names);
                if isfield(lateral, pre)
                    side = ismember(names, {'7', '7h', '9', '9h', '8', '8h', '10', '10h'});
                    rowNames(side) = strcat(lateral.(pre), names(side));
                end
                labels = [labels, rowNames]; %#ok<AGROW>
                pos = [pos; P]; %#ok<AGROW>
            end
            pos = pos ./ sqrt(sum(pos .^ 2, 2));
            pos(abs(pos) < 1e-12) = 0;
        end

        %% circleArc - Points at fractions of the arc from a to b on the circle through a, b and c
        function p = circleArc(a, b, c, frac)
            nrm = cross(b - a, c - a);
            nrm = nrm / norm(nrm);
            centre = dot(nrm, a) * nrm;                  % the points lie on the unit sphere
            u = a - centre;
            v = b - centre;
            phi = acos(max(-1, min(1, dot(u, v) / (norm(u) * norm(v)))));
            p = zeros(numel(frac), 3);
            for k = 1:numel(frac)
                p(k, :) = centre + (sin((1 - frac(k)) * phi) * u + sin(frac(k) * phi) * v) / sin(phi);
            end
        end

        %% findName - Template name of a label as it is ('exact'), ignoring case ('case') or an old name ('alias')
        function [name, how] = findName(s)
            name = '';
            how = '';
            labels = EEGLayout.template();
            i = find(strcmp(labels, s), 1);
            if ~isempty(i), name = labels{i}; how = 'exact'; return; end
            i = find(strcmpi(labels, s), 1);
            if ~isempty(i), name = labels{i}; how = 'case'; return; end
            old = {'t3', 'T7'; 't4', 'T8'; 't5', 'P7'; 't6', 'P8'};
            i = find(strcmpi(old(:, 1), s), 1);
            if ~isempty(i), name = old{i, 2}; how = 'alias'; end
        end

        %% cleanText - Trim, drop a leading 'EEG ' / 'EEG_' / 'EEG-' and a trailing reference suffix
        function c = cleanText(s)
            c = strtrim(EEGLayout.asText(s));
            c = strtrim(regexprep(c, '^[Ee][Ee][Gg][ _-]', ''));
            c = strtrim(regexprep(c, '-([Rr][Ee][Ff]|[Ll][Ee]|[Aa][Rr]|[Aa][Vv][Gg]|[AaMm][12])$', ''));
        end

        %% matchKey - Lower-case name used to match channels with a positions file
        function k = matchKey(s)
            k = EEGLayout.cleanName(s);
            if isempty(k), k = EEGLayout.cleanText(s); end
            k = lower(k);
        end

        %% nonScalpKind - Why a channel has no scalp position ('' when no reason is known)
        function why = nonScalpKind(label)
            s = lower(EEGLayout.cleanText(label));
            why = '';
            if ~isempty(regexp(s, '^(a1|a2|m1|m2)$', 'once'))
                why = 'ear lobe or mastoid';
            elseif ~isempty(regexp(s, 'eog', 'once'))
                why = 'eye channel';
            elseif ~isempty(regexp(s, '^(ecg|ekg)', 'once'))
                why = 'heart channel';
            elseif ~isempty(regexp(s, '^emg', 'once'))
                why = 'muscle channel';
            elseif any(strcmp(s, {'nas', 'nasion', 'lpa', 'rpa', 'fidnz', 'fidt9', 'fidt10', 'leftear', 'rightear'}))
                why = 'landmark, not an electrode';
            end
        end

        %% readFrame - What a coordSystem text says: axes, unit, rodent (bregma)
        % f.M: 3 x 3, ras = raw * f.M' (x = right ear, y = nose, z = up).
        function f = readFrame(cs)
            cs = strtrim(cs);
            ALS = [0 -1 0; 1 0 0; 0 0 1];
            if isempty(cs)
                f = EEGLayout.frameStruct('positions', eye(3), '', false, false);
            elseif strncmpi(cs, 'EEGLAB', 6)
                rest = '';
                i = find(cs == ';', 1);
                if ~isempty(i), rest = cs(i + 1:end); end
                f = EEGLayout.frameStruct('EEGLAB', ALS, EEGLayout.unitWord(rest), true, ...
                    ~isempty(regexpi(rest, 'bregma|lambda|paxinos', 'once')));
            elseif strncmpi(cs, 'FieldTrip', 9)
                t = regexp(cs, '\((.*)\)', 'tokens', 'once');
                parts = {'', ''};
                if ~isempty(t)
                    q = strtrim(strsplit(t{1}, ','));
                    parts(1:min(2, numel(q))) = q(1:min(2, numel(q)));
                end
                sys = lower(parts{1});
                M = EEGLayout.axesCode(sys);
                stated = true;
                if isempty(M)
                    switch sys
                        case {'mni', 'tal', 'acpc', 'neuromag', 'elekta', 'scanras', 'spm', 'fsaverage', ...
                                'captrak', 'itab', 'bregma', 'paxinos'}
                            M = eye(3);
                        case {'ctf', '4d', 'bti', 'yokogawa', 'eeglab'}
                            M = ALS;
                        case {'scanlps', 'dicom'}
                            M = EEGLayout.axesCode('lps');
                        otherwise
                            M = eye(3);
                            stated = false;
                    end
                end
                name = 'FieldTrip';
                if stated, name = ['FieldTrip ' parts{1}]; end
                f = EEGLayout.frameStruct(name, M, EEGLayout.unitWord(parts{2}), stated, ...
                    any(strcmp(sys, {'bregma', 'paxinos'})));
            elseif strncmpi(cs, 'BrainVision', 11)
                f = EEGLayout.frameStruct('BrainVision', eye(3), '', true, false);
            elseif strncmpi(cs, 'EGI', 3)
                f = EEGLayout.frameStruct('EGI', eye(3), 'cm', true, false);
            elseif strncmpi(cs, 'BIDS', 4)
                t = regexp(cs, '^BIDS\s+(.*?)\s*\(([^()]*)\)\s*$', 'tokens', 'once');
                if isempty(t), t = {strtrim(cs(5:end)), ''}; end
                sys = t{1};
                if any(strcmpi(sys, {'CTF', '4DBti', 'KitYokogawa', 'EEGLAB', 'EEGLAB-HJ'}))
                    f = EEGLayout.frameStruct(['BIDS ' sys], ALS, EEGLayout.unitWord(t{2}), true, false);
                elseif isempty(sys) || any(strcmpi(sys, {'Other', 'unknown system', 'n/a'}))
                    f = EEGLayout.frameStruct(strtrim(['BIDS ' sys]), eye(3), EEGLayout.unitWord(t{2}), false, false);
                else
                    f = EEGLayout.frameStruct(['BIDS ' sys], eye(3), EEGLayout.unitWord(t{2}), true, false);
                end
            else
                f = EEGLayout.frameStruct(cs, eye(3), EEGLayout.unitWord(cs), false, false);
            end
        end

        %% frameStruct - The parts of a frame description
        function f = frameStruct(name, M, unit, stated, bregma)
            f = struct('name', name, 'M', M, 'unit', unit, 'stated', stated, 'bregma', bregma, ...
                'centre', true, 'words', '');
        end

        %% axesCode - Three-letter axes code (e.g. 'ras', 'als', 'lps') as a matrix, [] if it is none
        function M = axesCode(code)
            M = [];
            if numel(code) ~= 3, return; end
            letters = 'rlapsi';
            axis = [1 1 2 2 3 3];
            sgn = [1 -1 1 -1 1 -1];
            T = zeros(3);
            for j = 1:3
                i = find(letters == code(j), 1);
                if isempty(i), return; end
                T(axis(i), j) = sgn(i);
            end
            if all(sum(abs(T), 2) == 1), M = T; end
        end

        %% axesWords - The axes of a frame in words, e.g. 'x = nose, y = left ear, z = up'
        function s = axesWords(M, kind)
            if strcmp(kind, 'skull')
                words = {'right', 'left'; 'front', 'back'; 'up', 'down'};
            else
                words = {'right ear', 'left ear'; 'nose', 'back of the head'; 'up', 'down'};
            end
            xyz = 'xyz';
            parts = cell(1, 3);
            for j = 1:3
                i = find(M(:, j) ~= 0, 1);
                parts{j} = sprintf('%s = %s', xyz(j), words{i, 1 + (M(i, j) < 0)});
            end
            if strcmp(kind, 'skull'), parts = parts(1:2); end
            s = strjoin(parts, ', ');
        end

        %% unitWord - 'mm' | 'cm' | 'm' | '' from a piece of text
        function u = unitWord(s)
            u = '';
            s = lower(EEGLayout.asText(s));
            if ~isempty(regexp(s, '(^|[^a-z])(mm|millimet(er|re)s?)([^a-z]|$)', 'once'))
                u = 'mm';
            elseif ~isempty(regexp(s, '(^|[^a-z])(cm|centimet(er|re)s?)([^a-z]|$)', 'once'))
                u = 'cm';
            elseif ~isempty(regexp(s, '(^|[^a-z])(m|met(er|re)s?)([^a-z]|$)', 'once'))
                u = 'm';
            end
        end

        %% finish - Raw positions + frame -> skull mm or scalp directions, with the orientation check
        function [pos, kind, frame, notes] = finish(labels, raw, f)
            n = numel(labels);
            pos = NaN(n, 3);
            notes = {};
            frame = '';
            kind = 'none';
            has = all(isfinite(raw), 2);
            if ~any(has), return; end
            xyz = raw(has, :) * f.M';
            z = xyz(:, 3);
            % planar (rodent skull): at least 3 positions at one height; two can
            % share a height on the scalp too (e.g. T7 and T8)
            planar = sum(has) >= 3 && max(z) - min(z) <= 1e-9 * max(1, max(abs(xyz(:))));
            if planar || f.bregma
                kind = 'skull';
                scale = struct('mm', 1, 'cm', 10, 'm', 1000);
                unit = f.unit;
                if isempty(unit)
                    unit = 'mm';
                    notes{end + 1} = 'The file does not give the unit of the positions; they were read as mm.';
                end
                pos(has, :) = [xyz(:, 1:2) * scale.(unit), zeros(sum(has), 1)];
                if ~planar
                    notes{end + 1} = 'The positions differ in height; only medial-lateral and anterior-posterior are used.';
                end
                axesText = EEGLayout.axesWords(f.M, 'skull');
                inUnit = '';
                if ~strcmp(unit, 'mm'), inUnit = sprintf(' in %s', unit); end
                if ~f.stated
                    frame = sprintf('%s (axes not stated, read as %s)%s', f.name, axesText, inUnit);
                    notes{end + 1} = 'Orientation not stated in the file: x was read as right and y as front.';
                else
                    frame = sprintf('%s (%s)%s', f.name, axesText, inUnit);
                end
                if isequal(f.M, eye(3)) && isempty(inUnit)
                    frame = [frame, ', mm from bregma'];
                else
                    frame = [frame, ', turned to mm from bregma (x = right, y = front)'];
                end
                return;
            end

            % ---- Scalp: directions from the centre of the head ----
            kind = 'scalp';
            idx = find(has);
            zero = all(raw(idx, :) == 0, 2);
            if any(zero)
                notes{end + 1} = sprintf('%d channel(s) at 0, 0, 0 were taken as without position.', sum(zero));
                has(idx(zero)) = false;
                if ~any(has), kind = 'none'; return; end
            end
            M = f.M;
            [d, fitted] = EEGLayout.directions(raw(has, :) * M', f.centre);
            names = EEGLayout.cleanName(labels(has));
            a = EEGLayout.medianAngle(names, d);
            if isfinite(a) && a > 45
                ALS = [0 -1 0; 1 0 0; 0 0 1];
                if isequal(M, eye(3)), alt = ALS; else, alt = eye(3); end
                [d2, fitted2] = EEGLayout.directions(raw(has, :) * alt', f.centre);
                a2 = EEGLayout.medianAngle(names, d2);
                if a2 < 45 && a2 < 0.5 * a
                    notes{end + 1} = sprintf(['The positions looked rotated by 90 deg; they were read as ' ...
                        '%s (median %.0f deg from the 10-5 positions of the same names instead of %.0f deg).'], ...
                        EEGLayout.axesWords(alt, 'scalp'), a2, a);
                    M = alt; d = d2; fitted = fitted2; a = a2;
                end
                if a > 45
                    notes{end + 1} = sprintf(['The positions are far from the 10-5 positions of the same ' ...
                        'names (median %.0f deg apart); check the layout.'], a);
                end
            end
            pos(has, :) = d;
            axesText = EEGLayout.axesWords(M, 'scalp');
            guessed = ~isequal(M, f.M);
            if ~isempty(f.words) && ~guessed
                frame = f.words;
            else
                if guessed
                    how = sprintf('read as %s, guessed from the channel names', axesText);
                elseif ~f.stated
                    how = sprintf('axes not stated, read as %s', axesText);
                    notes{end + 1} = 'Orientation not stated in the file: x was read as the right ear and y as the nose.';
                else
                    how = axesText;
                end
                frame = sprintf('%s (%s)', f.name, how);
                if ~isequal(M, eye(3)), frame = [frame, ', turned to x = right ear, y = nose, z = up']; end
            end
            if fitted
                frame = [frame, '; directions from the centre of a sphere fitted to the positions'];
            else
                frame = [frame, '; directions from the origin of the positions'];
            end
        end

        %% directions - Unit vectors from the fitted sphere centre (or the origin)
        function [d, fitted] = directions(xyz, tryFit)
            c = [0 0 0];
            fitted = false;
            n = size(xyz, 1);
            if tryFit && n >= 6
                sv = svd(xyz - mean(xyz, 1));
                if sv(1) > 0 && sv(3) >= 0.1 * sv(1)
                    sol = [2 * xyz, ones(n, 1)] \ sum(xyz .^ 2, 2);
                    cc = sol(1:3)';
                    r2 = sol(4) + cc * cc';
                    med = median(sqrt(sum(xyz .^ 2, 2)));
                    if r2 > 0 && sqrt(r2) >= 0.5 * med && sqrt(r2) <= 2 * med
                        c = cc;
                        fitted = true;
                    end
                end
            end
            d = xyz - c;
            len = sqrt(sum(d .^ 2, 2));
            d = d ./ len;
            d(len == 0, :) = NaN;
        end

        %% medianAngle - Median angle (deg) between directions and the 10-5 positions of the same names; NaN below 3 names
        function a = medianAngle(names, d)
            a = NaN;
            [tl, tp] = EEGLayout.template();
            [ok, i] = ismember(names, tl);
            ok = ok(:) & all(isfinite(d), 2);
            if sum(ok) < 3, return; end
            c = sum(d(ok, :) .* tp(i(ok), :), 2);
            a = median(acos(max(-1, min(1, c))) * 180 / pi);
        end

        %% templateScale - Factor on the 10-5 angles from the vertex that fits the positions given
        % Least squares of the angle of each position on the angle of its
        % 10-5 name, over the channels with both that are more than 20 deg
        % from the vertex (at least 3). 1 when there are fewer, when the
        % factor is within 1 % of 1, or outside 0.75-1.5 (no common head).
        % names: the 10-5 name of each channel ('' when none).
        function s = templateScale(names, pos)
            s = 1;
            [tl, tp] = EEGLayout.template();
            [ok, i] = ismember(EEGLayout.cellRow(names), tl);
            ok = ok & all(isfinite(pos), 2)';
            if sum(ok) < 3, return; end
            d = pos(ok, :) ./ sqrt(sum(pos(ok, :) .^ 2, 2));
            af = acos(max(-1, min(1, d(:, 3))));
            at = acos(max(-1, min(1, tp(i(ok), 3))));
            use = at > 20 * pi / 180;
            if sum(use) < 3, return; end
            k = sum(af(use) .* at(use)) / sum(at(use) .^ 2);
            if abs(k - 1) >= 0.01 && k >= 0.75 && k <= 1.5, s = k; end
        end

        %% scaleTemplate - 10-5 directions with the angle from the vertex times s (same azimuth)
        function p = scaleTemplate(p, s)
            if s == 1 || isempty(p), return; end
            a = min(pi, s * acos(max(-1, min(1, p(:, 3)))));
            az = atan2(p(:, 1), p(:, 2));
            p = [sin(a) .* sin(az), sin(a) .* cos(az), cos(a)];
        end

        %% fromPositions - Positions of a positions file, matched to the channels by name
        function [pos, kind, frame, notes, matchName] = fromPositions(labels, P)
            if ~isstruct(P) || ~isscalar(P) || ~all(isfield(P, {'labels', 'xyz'}))
                error('NeuroAnalyzer:eeg:invalid', ['The positions must be a struct with labels and ' ...
                    'xyz (as readElectrodes returns).']);
            end
            pl = EEGLayout.cellRow(P.labels);
            xyz = double(P.xyz);
            if size(xyz, 1) ~= numel(pl) || size(xyz, 2) ~= 3
                error('NeuroAnalyzer:eeg:invalid', 'The positions file has %d names for %d x %d positions.', ...
                    numel(pl), size(xyz, 1), size(xyz, 2));
            end
            unit = '';
            if isfield(P, 'unit'), unit = EEGLayout.unitWord(P.unit); end
            skull = isfield(P, 'kind') && strcmpi(EEGLayout.asText(P.kind), 'skull');
            name = 'positions file';
            if isfield(P, 'format') && ~isempty(P.format)
                name = sprintf('positions file (%s)', EEGLayout.asText(P.format));
            end
            f = EEGLayout.frameStruct(name, eye(3), unit, true, skull);
            if isfield(P, 'frame') && ~isempty(P.frame)
                f.words = sprintf('%s: %s', name, EEGLayout.asText(P.frame));
            end
            [pp, kind, frame, notes] = EEGLayout.finish(pl, xyz, f);
            if isfield(P, 'notes'), notes = [EEGLayout.cellRow(P.notes), notes]; end
            if strcmp(kind, 'skull') && ~isempty(f.words)
                frame = f.words;
                if ~isempty(unit) && ~strcmp(unit, 'mm'), frame = sprintf('%s, %s turned to mm', frame, unit); end
            end

            % ---- Match by name: as written (case ignored), then cleaned ----
            n = numel(labels);
            pos = NaN(n, 3);
            matchName = repmat({''}, 1, n);
            keys = cellfun(@EEGLayout.matchKey, pl, 'UniformOutput', false);
            used = 0;
            for k = 1:n
                i = find(strcmpi(pl, strtrim(labels{k})), 1);
                if isempty(i)
                    i = find(strcmp(keys, EEGLayout.matchKey(labels{k})), 1);
                    if ~isempty(i) && ~isempty(keys{i}), matchName{k} = pl{i}; else, i = []; end
                end
                if ~isempty(i) && all(isfinite(pp(i, :)))
                    pos(k, :) = pp(i, :);
                    used = used + 1;
                else
                    matchName{k} = '';
                end
            end
            unusedN = sum(all(isfinite(pp), 2)) - used;
            if used == 0
                kind = 'none';
                notes{end + 1} = 'No channel name was found in the positions file.';
            elseif unusedN > 0
                notes{end + 1} = sprintf('%d position(s) of the positions file belong to no channel.', unusedN);
            end
        end

        %% applyEdits - Placements by hand: 'as' a 10-5 position (scalp) or ap / ml mm (skull)
        function [L, renamed] = applyEdits(L, E, renamed, scale)
            if nargin < 4, scale = 1; end
            if ~isstruct(E) || ~isfield(E, 'label')
                error('NeuroAnalyzer:eeg:badOption', 'Edits must be a struct array with label and as, or ap and ml.');
            end
            [tl, tp] = EEGLayout.template();
            for k = 1:numel(E)
                lbl = EEGLayout.asText(E(k).label);
                c = find(strcmp(L.labels, lbl));
                if isempty(c), c = find(strcmpi(L.labels, strtrim(lbl))); end
                if isempty(c)
                    L.notes{end + 1} = sprintf('The placement of %s was not used: there is no channel of that name.', lbl);
                    continue;
                end
                as = '';
                if isfield(E, 'as'), as = strtrim(EEGLayout.asText(E(k).as)); end
                ap = NaN; ml = NaN;
                if isfield(E, 'ap') && isnumeric(E(k).ap) && isscalar(E(k).ap), ap = double(E(k).ap); end
                if isfield(E, 'ml') && isnumeric(E(k).ml) && isscalar(E(k).ml), ml = double(E(k).ml); end
                skull = isfinite(ap) && isfinite(ml);
                if ~isempty(as) && skull
                    error('NeuroAnalyzer:eeg:badOption', ...
                        'Place %s either on a 10-5 position (as) or in mm from bregma (ap, ml), not both.', lbl);
                end
                if ~isempty(as)
                    name = EEGLayout.cleanName(as);
                    if isempty(name)
                        error('NeuroAnalyzer:eeg:badOption', '''%s'' is not a position of the 10-5 system.', as);
                    end
                    if strcmp(L.kind, 'skull')
                        error('NeuroAnalyzer:eeg:badOption', ['%s cannot go on the 10-5 position %s: the ' ...
                            'layout is in mm from bregma (give ap and ml).'], lbl, name);
                    end
                    L.kind = 'scalp';
                    p = EEGLayout.scaleTemplate(tp(strcmp(tl, name), :), scale);
                elseif skull
                    if strcmp(L.kind, 'scalp')
                        error('NeuroAnalyzer:eeg:badOption', ['%s cannot go at ap %g, ml %g mm: the ' ...
                            'layout is on the head (give a 10-5 name in as).'], lbl, ap, ml);
                    end
                    if strcmp(L.kind, 'none')
                        L.kind = 'skull';
                        L.frame = 'mm from bregma (x = right, y = front)';
                    end
                    name = '';
                    p = [ml, ap, 0];
                else
                    name = '';
                    p = NaN(1, 3);
                end
                for i = c(:)'
                    L.pos(i, :) = p;
                    L.as{i} = name;
                    renamed(i) = false;
                    if all(isfinite(p)), L.source{i} = 'edited'; else, L.source{i} = ''; end
                end
            end
            if ~any(all(isfinite(L.pos), 2)), L.kind = 'none'; end
            if isempty(L.frame) && strcmp(L.kind, 'scalp')
                L.frame = '10-5 positions placed by hand (x = right ear, y = nose, z = up)';
            end
        end

        %% review - Status of every channel, the check lists and the summary line
        function L = review(L, renamed, renamedTo)
            n = numel(L.labels);
            has = all(isfinite(L.pos), 2)';
            status = repmat({'ok'}, 1, n);
            status(~has) = {'none'};
            status(has & renamed) = {'renamed'};
            out = false(1, n);
            if strcmp(L.kind, 'skull')
                out(has) = sqrt(sum(L.pos(has, 1:2) .^ 2, 2))' > 15;
            elseif strcmp(L.kind, 'scalp')
                out(has) = acos(max(-1, min(1, L.pos(has, 3))))' * 180 / pi > 120;
            end
            status(out) = {'outside'};
            pairs = EEGLayout.duplicatePairs(L);
            dup = false(1, n);
            dup(pairs(:)) = true;
            status(dup) = {'duplicate'};
            L.status = status;
            from = L.labels(has & renamed);
            to = renamedTo(has & renamed);
            L.check = struct('matched', {L.labels(has)}, 'renamed', {[from(:), to(:)]}, ...
                'missing', {L.labels(~has)}, 'duplicated', {L.labels(dup)}, 'outside', {L.labels(out)});
            if isempty(from), L.check.renamed = cell(0, 2); end

            % ---- Summary line ----
            counts = {'file', 'from the file'; 'template', 'by name (10-5 system)'; ...
                'positions file', 'from the positions file'; 'edited', 'placed by hand'};
            parts = {};
            for k = 1:size(counts, 1)
                m = sum(strcmp(L.source, counts{k, 1}) & has);
                if m > 0, parts{end + 1} = sprintf('%d %s', m, counts{k, 2}); end %#ok<AGROW>
            end
            if any(has)
                s = sprintf('%d of %d channels placed: %s', sum(has), n, strjoin(parts, ', '));
            else
                s = sprintf('0 of %d channels placed', n);
            end
            if any(~has)
                miss = L.labels(~has);
                if numel(miss) > 8
                    miss = [miss(1:6), {sprintf('%d more', numel(miss) - 6)}];
                end
                s = sprintf('%s; no position: %s', s, strjoin(miss, ', '));
            end
            L.summary = [s '.'];
        end

        %% duplicatePairs - Channel pairs with the same 10-5 name or (almost) the same place
        function pairs = duplicatePairs(L)
            pairs = zeros(0, 2);
            has = find(all(isfinite(L.pos), 2))';
            if numel(has) < 2, return; end
            names = L.as(has);
            for k = find(cellfun(@isempty, names))
                names{k} = EEGLayout.cleanName(L.labels{has(k)});
            end
            [~, ~, g] = unique(lower(names));
            g = g(:);
            same = g == g' & ~cellfun(@isempty, names(:));
            P = L.pos(has, :);
            if strcmp(L.kind, 'skull')
                near = sqrt((P(:, 1) - P(:, 1)') .^ 2 + (P(:, 2) - P(:, 2)') .^ 2) < 0.2;
            else
                near = acos(max(-1, min(1, P * P'))) * 180 / pi < 2;
            end
            [a, b] = find(triu(same | near, 1));
            pairs = sortrows([has(a(:))', has(b(:))']);
        end

        %% statusColours - Electrode colour per status
        function [statuses, colours] = statusColours()
            statuses = {'ok', 'renamed', 'outside', 'duplicate'};
            colours = [0.00 0.45 0.70; 0.34 0.71 0.91; 0.90 0.62 0.00; 0.84 0.37 0.00];
        end

        %% field - Numbers of one chanlocs field as a column (NaN where missing)
        function v = field(cl, name)
            v = NaN(numel(cl), 1);
            if ~isfield(cl, name), return; end
            for k = 1:numel(cl)
                x = cl(k).(name);
                if isnumeric(x) && isscalar(x), v(k) = double(x); end
            end
        end

        %% options - Name/Value pairs into a defaults struct (case-insensitive names)
        function o = options(o, args)
            if mod(numel(args), 2) ~= 0
                error('NeuroAnalyzer:eeg:badOption', 'Options must come in Name, Value pairs.');
            end
            f = fieldnames(o);
            for k = 1:2:numel(args)
                i = find(strcmpi(f, args{k}), 1);
                if isempty(i)
                    error('NeuroAnalyzer:eeg:badOption', 'Unknown option ''%s''.', EEGLayout.asText(args{k}));
                end
                o.(f{i}) = args{k + 1};
            end
        end

        %% asText - A char row from char / string / number
        function s = asText(v)
            if ischar(v)
                s = v(:)';
            elseif isstring(v) || iscellstr(v)
                s = char(v);
                if size(s, 1) > 1, s = strjoin(cellstr(s)', ' '); end
            elseif isnumeric(v) && ~isempty(v)
                s = num2str(v);
            else
                s = '';
            end
        end

        %% cellRow - 1 x n cell of char from a cell / string array / char
        function c = cellRow(v)
            if ischar(v)
                c = {v};
            elseif isstring(v)
                c = cellstr(v);
            elseif iscell(v)
                c = v;
            else
                c = {};
            end
            c = c(:)';
        end

        %% listText - {'a', 'b', 'c'} -> 'a, b and c' (or joined by sep)
        function s = listText(c, sep)
            if nargin > 1
                s = strjoin(c, sep);
            elseif numel(c) <= 1
                s = strjoin(c, '');
            else
                s = [strjoin(c(1:end - 1), ', ') ' and ' c{end}];
            end
        end
    end
end
