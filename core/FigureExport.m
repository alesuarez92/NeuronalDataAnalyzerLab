%% FigureExport.m
% =========================================================================
% FIGURE EXPORT - PUBLICATION-READY VECTOR AND HIGH-RESOLUTION FIGURES
% =========================================================================
% Exports what an app shows in its axes (uiaxes or axes, a tiled layout,
% or any container holding axes) to a file for papers and posters. The
% plot content is copied into a temporary invisible figure, the
% publication style is applied there, and the copy is written and
% deleted, so the app's own view never changes.
%
%   out = FigureExport.export(src, filePath, format, opts)
%     src       axes / uiaxes handle, array of axes, TiledChartLayout, or a
%               container (figure, uifigure, panel, tab, grid layout)
%     filePath  output file; its extension is replaced by the format's
%     format    'pdf' | 'svg' | 'eps' (vector), 'png' / 'png300' (300 dpi),
%               'png600', 'tif' (600 dpi) or a label from formats().
%               Default: from the extension of filePath, else 'pdf'.
%     opts      struct, all fields optional:
%                 Width, Height   size in cm (default 8.5 x 6.5 for one
%                                 axes = one journal column; 17.5 x 6.5
%                                 per row of tiles for several)
%                 FontName        'Helvetica'
%                 FontSize        8 (tick labels, text; labels and title +1)
%                 LineWidth       0.75 (axes lines)
%                 MinDataLineWidth 1 (thinner data lines are thickened)
%                 KeepTitle       true
%                 Grid            false
%     out       path of the written file
%   items = FigureExport.formats()     {label; ...} for a dropdown
%   key   = FigureExport.formatKey(labelOrKey)   e.g. 'PDF (vector)' -> 'pdf'
%
% Publication style: white figure and axes, black axes, ticks and text, no
% grid, no box, ticks out, one font, fixed physical size. Semi-transparent
% patches and markers are flattened to the equivalent opaque color on
% white so every vector format (EPS in particular) renders them the same.
% Vector files use exportgraphics(..., 'ContentType', 'vector'); PNG/TIFF
% use exportgraphics(..., 'Resolution', dpi). When exportgraphics is not
% available or does not support a format (e.g. SVG in some releases),
% print is used instead (-dsvg / -dpdf / -depsc / -dpng / -dtiff).
% Limitations: yyaxis (two y axes) keeps only the active side; objects
% that cannot be copied are skipped.
% Requires base MATLAB (exportgraphics: R2020a+; print fallback before).
% =========================================================================

classdef FigureExport
    properties(Constant)
        Labels = {'PDF (vector)', 'SVG (vector)', 'EPS (vector)', 'PNG 300 dpi', ...
            'PNG 600 dpi', 'TIFF 600 dpi'}
        Keys = {'pdf', 'svg', 'eps', 'png300', 'png600', 'tif'}
    end

    methods(Static)

        %% export - Copy src into an invisible figure, style it and write it
        function out = export(src, filePath, format, opts)
            filePath = char(filePath);
            if nargin < 3 || isempty(format)
                [~, ~, ext0] = fileparts(filePath);
                format = strrep(lower(ext0), '.', '');
                if isempty(format), format = 'pdf'; end
            end
            if nargin < 4 || isempty(opts), opts = struct(); end
            [fmt, ext, dpi, isVector] = FigureExport.parseFormat(format);
            [folder, name] = fileparts(filePath);
            if isempty(name)
                error('NeuroAnalyzer:FigureExport:path', 'No file name given (%s).', filePath);
            end
            if ~isempty(folder) && ~exist(folder, 'dir'), mkdir(folder); end
            out = fullfile(folder, [name ext]);

            axList = FigureExport.findAxes(src);
            if isempty(axList)
                error('NeuroAnalyzer:FigureExport:noAxes', 'Nothing to export: no axes found.');
            end
            opts = FigureExport.defaults(opts, src, axList);

            fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'centimeters', ...
                'Position', [1 1 opts.Width opts.Height], 'PaperUnits', 'centimeters', ...
                'PaperSize', [opts.Width opts.Height], 'PaperPosition', [0 0 opts.Width opts.Height], ...
                'InvertHardcopy', 'off', 'NumberTitle', 'off', 'Name', 'FigureExport', ...
                'MenuBar', 'none', 'ToolBar', 'none');
            cleaner = onCleanup(@() delete(fig));
            FigureExport.rebuild(src, axList, fig);
            FigureExport.applyStyle(fig, opts);
            drawnow;
            FigureExport.write(fig, out, fmt, dpi, isVector);
            clear cleaner
            d = dir(out);
            if isempty(d) || d(1).bytes == 0
                error('NeuroAnalyzer:FigureExport:empty', 'Export produced no file: %s', out);
            end
        end

        %% formats - Dropdown labels (same order as FigureExport.Keys)
        function items = formats()
            items = FigureExport.Labels;
        end

        %% formatKey - Key for a dropdown label or key ('PNG 600 dpi' -> 'png600')
        function key = formatKey(label)
            label = char(label);
            i = find(strcmpi(FigureExport.Labels, label), 1);
            if ~isempty(i)
                key = FigureExport.Keys{i};
            else
                key = lower(strrep(strtrim(label), '.', ''));
            end
        end

        %% parseFormat - file type, extension, resolution and vector flag
        function [fmt, ext, dpi, isVector] = parseFormat(format)
            key = FigureExport.formatKey(format);
            dpi = 300;
            switch key
                case 'pdf',            fmt = 'pdf'; isVector = true;
                case 'svg',            fmt = 'svg'; isVector = true;
                case 'eps',            fmt = 'eps'; isVector = true;
                case {'png', 'png300'}, fmt = 'png'; isVector = false;
                case 'png600',         fmt = 'png'; isVector = false; dpi = 600;
                case {'tif', 'tiff'},  fmt = 'tif'; isVector = false; dpi = 600;
                otherwise
                    error('NeuroAnalyzer:FigureExport:format', ...
                        'Unknown format ''%s'' (use pdf, svg, eps, png300, png600 or tif).', key);
            end
            ext = ['.' fmt];
        end

        %% findAxes - Axes to export from src, in reading order
        function axList = findAxes(src)
            if isempty(src) || ~all(isgraphics(src(:)))
                error('NeuroAnalyzer:FigureExport:src', 'The source to export is not a valid graphics object.');
            end
            allAxes = true;
            for i = 1:numel(src), allAxes = allAxes && FigureExport.isAxes(src(i)); end
            if allAxes
                axList = src(:);
            else
                axList = findobj(src, 'Type', 'axes');
            end
            if numel(axList) <= 1, return; end
            % Tiles in tile order; otherwise top-to-bottom, left-to-right
            try
                tiles = arrayfun(@(a) a.Layout.Tile, axList);
                [~, order] = sort(tiles);
            catch
                pos = zeros(numel(axList), 4);
                for i = 1:numel(axList), pos(i, :) = getpixelposition(axList(i), true); end
                [~, order] = sortrows([-round(pos(:, 2) + pos(:, 4)), round(pos(:, 1))]);
            end
            axList = axList(order);
        end
    end

    methods(Static, Access = private)

        %% isAxes - Cartesian axes or UIAxes
        function tf = isAxes(h)
            tf = isa(h, 'matlab.graphics.axis.Axes') || isa(h, 'matlab.ui.control.UIAxes');
        end

        %% defaults - Fill in missing options; size depends on the number of axes
        function opts = defaults(opts, src, axList)
            n = numel(axList);
            rows = 1;
            if n > 1
                if isa(src, 'matlab.graphics.layout.TiledChartLayout')
                    try, rows = src.GridSize(1); catch, rows = ceil(n / 2); end
                else
                    rows = ceil(n / 2);
                end
            end
            def = struct('Width', FigureExport.ifElse(n > 1, 17.5, 8.5), 'Height', 6.5 * rows, ...
                'FontName', 'Helvetica', 'FontSize', 8, 'LineWidth', 0.75, ...
                'MinDataLineWidth', 1, 'KeepTitle', true, 'Grid', false);
            f = fieldnames(def);
            for i = 1:numel(f)
                if ~isfield(opts, f{i}) || isempty(opts.(f{i})), opts.(f{i}) = def.(f{i}); end
            end
        end

        %% rebuild - Recreate the axes layout of src in fig and copy each axes
        function rebuild(src, axList, fig)
            if numel(axList) == 1
                FigureExport.copyAxes(axList, axes('Parent', fig));
                return;
            end
            if isa(src, 'matlab.graphics.layout.TiledChartLayout')
                gs = src.GridSize;
                tl = tiledlayout(fig, gs(1), gs(2), 'TileSpacing', 'compact', 'Padding', 'compact');
                for i = 1:numel(axList)
                    try
                        dst = nexttile(tl, axList(i).Layout.Tile, axList(i).Layout.TileSpan);
                    catch
                        dst = nexttile(tl);
                    end
                    FigureExport.copyAxes(axList(i), dst);
                end
            else
                tl = tiledlayout(fig, 'flow', 'TileSpacing', 'compact', 'Padding', 'compact');
                for i = 1:numel(axList)
                    FigureExport.copyAxes(axList(i), nexttile(tl));
                end
            end
        end

        %% copyAxes - Copy plotted objects, limits, ticks, labels, legend
        function copyAxes(s, d)
            kids = s.Children;
            if ~isempty(kids)
                tags = arrayfun(@(h) h.Tag, kids, 'UniformOutput', false);
                kids = kids(~strcmp(tags, 'emptyHint'));
            end
            % Copy bottom-most first so the stacking order is preserved
            copies = gobjects(numel(kids), 1);
            for i = numel(kids):-1:1
                try
                    copies(i) = copyobj(kids(i), d);
                catch
                    % object type not copyable into a regular axes: skipped
                end
            end
            d.XLim = s.XLim; d.YLim = s.YLim;
            props = {'XScale', 'YScale', 'XDir', 'YDir', 'Layer', 'XAxisLocation', ...
                'YAxisLocation', 'TickLabelInterpreter', 'View'};
            for i = 1:numel(props)
                try, d.(props{i}) = s.(props{i}); catch, end
            end
            try, d.CLim = s.CLim; colormap(d, s.Colormap); catch, end
            try
                if strcmp(s.DataAspectRatioMode, 'manual'), d.DataAspectRatio = s.DataAspectRatio; end
            catch
            end
            for ax = 'XY'
                if strcmp(s.([ax 'TickMode']), 'manual'), d.([ax 'Tick']) = s.([ax 'Tick']); end
                if strcmp(s.([ax 'TickLabelMode']), 'manual'), d.([ax 'TickLabel']) = s.([ax 'TickLabel']); end
                try, d.([ax 'TickLabelRotation']) = s.([ax 'TickLabelRotation']); catch, end
            end
            for lbl = {'XLabel', 'YLabel', 'Title'}
                d.(lbl{1}).String = s.(lbl{1}).String;
                d.(lbl{1}).Interpreter = s.(lbl{1}).Interpreter;
            end
            % Legend: same entries, pointing at the copies
            try
                lg = s.Legend;
                if ~isempty(lg) && isvalid(lg) && strcmp(lg.Visible, 'on')
                    pc = lg.PlotChildren;
                    h = gobjects(0); str = {};
                    for i = 1:numel(pc)
                        j = find(kids == pc(i), 1);
                        if ~isempty(j) && isgraphics(copies(j))
                            h(end + 1) = copies(j); %#ok<AGROW>
                            str{end + 1} = lg.String{i}; %#ok<AGROW>
                        end
                    end
                    if ~isempty(h)
                        legend(d, h, str, 'Location', lg.Location, 'Interpreter', lg.Interpreter);
                    end
                end
            catch
            end
            % Colorbar
            try
                if ~isempty(s.Colorbar) && isvalid(s.Colorbar)
                    cb = colorbar(d);
                    cb.Label.String = s.Colorbar.Label.String;
                end
            catch
            end
        end

        %% applyStyle - Publication look on every object of the export figure
        function applyStyle(fig, opts)
            fs = opts.FontSize;
            black = [0 0 0];
            grid = FigureExport.ifElse(opts.Grid, 'on', 'off');
            % User text first (titles and labels follow the axes font size)
            for h = findobj(fig, 'Type', 'text')'
                h.FontName = opts.FontName;
                h.FontSize = fs;
                if isnumeric(h.Color), h.Color = FigureExport.darken(h.Color); end
            end
            for ax = findobj(fig, 'Type', 'axes')'
                ax.Color = 'w';
                ax.Box = 'off';
                ax.TickDir = 'out';
                ax.TickLength = [0.015 0.015];
                ax.LineWidth = opts.LineWidth;
                ax.XColor = black; ax.YColor = black;
                ax.XGrid = grid; ax.YGrid = grid;
                ax.XMinorGrid = 'off'; ax.YMinorGrid = 'off';
                ax.FontName = opts.FontName;
                ax.FontSize = fs;
                ax.LabelFontSizeMultiplier = (fs + 1) / fs;
                ax.TitleFontSizeMultiplier = (fs + 1) / fs;
                ax.TitleFontWeight = 'bold';
                ax.Title.Color = black;
                ax.XLabel.Color = black; ax.YLabel.Color = black;
                if ~opts.KeepTitle, ax.Title.String = ''; end
            end
            for h = findobj(fig, 'Type', 'line')'
                if h.LineWidth < opts.MinDataLineWidth, h.LineWidth = opts.MinDataLineWidth; end
            end
            for h = findobj(fig, 'Type', 'errorbar')'
                h.LineWidth = max(h.LineWidth, opts.MinDataLineWidth);
            end
            for h = findobj(fig, 'Type', 'constantline')'
                h.LineWidth = max(h.LineWidth, opts.MinDataLineWidth);
            end
            for h = findobj(fig, 'Type', 'patch')'
                if isnumeric(h.FaceColor) && isnumeric(h.FaceAlpha) && h.FaceAlpha < 1
                    h.FaceColor = h.FaceAlpha * h.FaceColor + (1 - h.FaceAlpha);
                    h.FaceAlpha = 1;
                end
                if isnumeric(h.EdgeAlpha) && h.EdgeAlpha < 1, h.EdgeAlpha = 1; end
            end
            for h = findobj(fig, 'Type', 'scatter')'
                if isnumeric(h.MarkerFaceAlpha) && h.MarkerFaceAlpha < 1 && isnumeric(h.MarkerFaceColor)
                    h.MarkerFaceColor = h.MarkerFaceAlpha * h.MarkerFaceColor + (1 - h.MarkerFaceAlpha);
                    h.MarkerFaceAlpha = 1;
                end
            end
            for h = findobj(fig, 'Type', 'legend')'
                h.FontName = opts.FontName;
                h.FontSize = max(fs - 1, 6);
                h.Box = 'off';
                h.TextColor = black;
                h.Color = 'none';
            end
            for h = findobj(fig, 'Type', 'colorbar')'
                h.FontName = opts.FontName;
                h.FontSize = fs;
                h.Color = black;
                h.LineWidth = opts.LineWidth;
            end
        end

        %% write - exportgraphics, falling back to print
        function write(fig, out, fmt, dpi, isVector)
            if exist(out, 'file'), delete(out); end
            try
                if isVector
                    exportgraphics(fig, out, 'ContentType', 'vector', 'BackgroundColor', 'white');
                else
                    exportgraphics(fig, out, 'Resolution', dpi, 'BackgroundColor', 'white');
                end
                if exist(out, 'file'), return; end
            catch ME
                firstError = ME;
            end
            devices = struct('pdf', '-dpdf', 'svg', '-dsvg', 'eps', '-depsc', 'png', '-dpng', 'tif', '-dtiff');
            if isVector
                extra = {{'-vector'}, {'-painters'}, {}};
            else
                extra = {{sprintf('-r%d', dpi), '-opengl'}, {sprintf('-r%d', dpi)}};
            end
            for i = 1:numel(extra)
                try
                    print(fig, out, devices.(fmt), extra{i}{:});
                    if exist(out, 'file'), return; end
                catch ME
                    lastError = ME;
                end
            end
            if exist('lastError', 'var')
                rethrow(lastError);
            elseif exist('firstError', 'var')
                rethrow(firstError);
            end
            error('NeuroAnalyzer:FigureExport:write', 'Could not write %s.', out);
        end

        %% darken - Light UI text colors become black; saturated colors stay
        function c = darken(c)
            if max(c) - min(c) < 0.2, c = [0 0 0]; end
        end

        %% ifElse - Inline conditional
        function out = ifElse(cond, a, b)
            if cond, out = a; else, out = b; end
        end
    end
end
