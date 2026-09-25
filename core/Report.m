%% Report.m
% =========================================================================
% REPORT - ONE-PAGE PDF OF A WINDOW: ITS IMAGE PLUS A PROVENANCE SUMMARY
% =========================================================================
% [ok, msg] = Report.make(app, pdfPath, s)
%   Writes an A4 portrait PDF with, on one page:
%     top    - an image of the window as it is now (plots included);
%     bottom - a text summary in two columns: window, NeuroAnalyzer and
%              MATLAB versions, OS, date, notes, every input file with its
%              size, modification date and MD5; the settings and the key
%              results of the session s (default: Session.capture(app)).
%   ok is false (and msg says why) when the PDF could not be written; it
%   never throws, so an analysis never fails because of its report.
% ok = Report.forApp(app, pdfPath)
%   Same, with status-bar messages (used by every window's makeReport).
%
% Approach (base MATLAB, no Report Generator): merging two PDF pages
% needs a toolbox or an external tool, so the report is ONE page. The
% window image is taken with exportapp (R2020b+); if that fails, the
% largest visible axes with exportgraphics, then getframe of the window;
% if all fail, the page says so. The image and the text are laid out in
% one invisible figure (A4, centimetres) and printed with
% print('-dpdf'); if print fails, exportgraphics(fig, pdf) is tried.
% Long lists are cut to what fits on the page, with a note; the session
% file keeps everything.
% =========================================================================

classdef Report
    properties(Constant)
        LinesPerColumn = 44
        CharsPerLine = 66
    end

    methods(Static)

        %% forApp - Report with status messages (never throws)
        function ok = forApp(app, pdfPath)
            lbl = Session.statusLabel(app);
            [ok, msg] = Report.make(app, pdfPath);
            [~, n, e] = fileparts(pdfPath);
            if ok
                UIKit.setStatus(lbl, sprintf('Report written to %s%s.', n, e), 'success');
            else
                UIKit.setStatus(lbl, sprintf('Report not written: %s', msg), 'error');
                try
                    UIKit.alert(app.UIFig, sprintf('The report could not be written:\n%s', msg), ...
                        'Report (PDF)', 'warning');
                catch
                end
            end
        end

        %% make - One-page A4 PDF: window image + provenance summary
        function [ok, msg] = make(app, pdfPath, s)
            ok = false; msg = '';
            fig = [];
            try
                % Image first, so status messages below do not show in it
                [img, how] = Report.windowImage(app.UIFig);
                if nargin < 3 || isempty(s)
                    s = Session.capture(app);
                end
                pdfPath = char(pdfPath);
                if numel(pdfPath) < 4 || ~strcmpi(pdfPath(end-3:end), '.pdf')
                    pdfPath = [pdfPath '.pdf'];
                end
                fig = Report.buildPage(s, img, how);
                Report.printPage(fig, pdfPath);
                ok = exist(pdfPath, 'file') == 2;
                if ~ok, msg = 'the PDF file was not created'; end
            catch ME
                msg = ME.message;
            end
            if ~isempty(fig) && isvalid(fig), delete(fig); end
        end

        %% windowImage - RGB image of a uifigure and how it was taken
        function [img, how] = windowImage(fig)
            img = []; how = 'not available';
            tmp = [tempname '.png'];
            c = onCleanup(@() Report.deleteIfExists(tmp));
            try
                drawnow;
                exportapp(fig, tmp);
                img = imread(tmp); how = 'exportapp';
                return;
            catch
            end
            try
                ax = findobj(fig, 'Type', 'axes', 'Visible', 'on');
                if ~isempty(ax)
                    area = zeros(numel(ax), 1);
                    for k = 1:numel(ax)
                        p = getpixelposition(ax(k), true);
                        area(k) = p(3) * p(4);
                    end
                    [~, k] = max(area);
                    exportgraphics(ax(k), tmp, 'Resolution', 150);
                    img = imread(tmp); how = 'exportgraphics (largest plot only)';
                    return;
                end
            catch
            end
            try
                fr = getframe(fig);
                img = fr.cdata; how = 'getframe';
            catch
            end
        end

        %% lines - The two text columns of the summary (cellstr each)
        function [left, right] = lines(s)
            W = Report.CharsPerLine;
            left = {sprintf('Window: %s (%s)', s.appTitle, s.app), ...
                sprintf('NeuroAnalyzer v%s', s.toolboxVersion), ...
                sprintf('MATLAB %s', s.matlabVersion), ...
                sprintf('OS: %s', s.os), ...
                sprintf('Session created: %s', s.created)};
            if isfield(s, 'reportCreated')
                left{end+1} = sprintf('Report created: %s', s.reportCreated);
            end
            if ~isempty(s.notes)
                left{end+1} = '';
                left{end+1} = 'NOTES';
                left = [left, Report.wrap(strsplit(s.notes, newline), W)];
            end
            left{end+1} = '';
            left{end+1} = sprintf('INPUTS (%d)', numel(s.inputs));
            for k = 1:numel(s.inputs)
                in = s.inputs(k);
                left{end+1} = sprintf('%d. %s: %s', k, in.role, in.name); %#ok<AGROW>
                if isempty(in.path)
                    left{end+1} = '   generated in memory (no file)'; %#ok<AGROW>
                    continue;
                end
                left = [left, Report.wrap({['   path: ' in.path]}, W)]; %#ok<AGROW>
                left{end+1} = sprintf('   %s bytes, modified %s', Report.thousands(in.bytes), in.modified); %#ok<AGROW>
                left{end+1} = sprintf('   MD5 %s', in.md5); %#ok<AGROW>
            end
            right = {'SETTINGS'};
            right = [right, Report.wrap(Session.describe(s.settings, ''), W)];
            right{end+1} = '';
            right{end+1} = 'KEY RESULTS';
            if isempty(s.summary)
                right{end+1} = '(no results yet)';
            else
                right = [right, Report.wrap(s.summary(:)', W)];
            end
        end
    end

    methods(Static, Hidden)
        %% deleteIfExists - Delete a temporary file if it is there
        function deleteIfExists(p)
            if exist(p, 'file') == 2
                try, delete(p); catch, end
            end
        end
    end

    methods(Static, Access = private)

        %% buildPage - Invisible A4 figure: title, window image, two text columns
        function fig = buildPage(s, img, how)
            T = UITheme;
            s.reportCreated = Session.isoNow();
            fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'centimeters', ...
                'Position', [1 1 21 29.7], 'PaperUnits', 'centimeters', 'PaperType', 'a4', ...
                'PaperOrientation', 'portrait', 'PaperPosition', [0 0 21 29.7], ...
                'PaperPositionMode', 'manual', 'InvertHardcopy', 'off', 'MenuBar', 'none', ...
                'ToolBar', 'none', 'NumberTitle', 'off', 'Name', 'NeuroAnalyzer report');
            page = axes(fig, 'Position', [0 0 1 1], 'Visible', 'off', 'XLim', [0 1], 'YLim', [0 1]);
            hold(page, 'on');
            ttl = s.appTitle;
            if isempty(ttl), ttl = s.app; end
            text(page, 0.05, 0.975, sprintf('NeuroAnalyzer report: %s', ttl), 'FontSize', 13, ...
                'FontWeight', 'bold', 'Color', T.headerBg, 'Interpreter', 'none', ...
                'VerticalAlignment', 'top');
            text(page, 0.05, 0.952, sprintf('NeuroAnalyzer v%s  ·  MATLAB %s  ·  %s  ·  window image: %s', ...
                s.toolboxVersion, s.matlabRelease, s.reportCreated, how), 'FontSize', 7.5, ...
                'Color', T.bodyColor, 'Interpreter', 'none', 'VerticalAlignment', 'top');
            plot(page, [0.05 0.95], [0.938 0.938], '-', 'Color', T.cardBorder);

            imAx = axes(fig, 'Position', [0.03 0.44 0.94 0.51]);   % larger image: it was hard to read
            if isempty(img)
                axis(imAx, 'off');
                text(imAx, 0.5, 0.5, 'Window image not available on this system', ...
                    'HorizontalAlignment', 'center', 'Color', T.mutedColor, 'Units', 'normalized');
            else
                image(imAx, img);
                axis(imAx, 'image');
                axis(imAx, 'off');
            end

            [left, right] = Report.lines(s);
            left = Report.fit(left);
            right = Report.fit(right);
            plot(page, [0.05 0.95], [0.432 0.432], '-', 'Color', T.cardBorder);
            text(page, 0.05, 0.423, left, 'FontName', 'FixedWidth', 'FontSize', 6.2, ...
                'Interpreter', 'none', 'VerticalAlignment', 'top', 'Color', [0.1 0.1 0.1]);
            text(page, 0.515, 0.423, right, 'FontName', 'FixedWidth', 'FontSize', 6.2, ...
                'Interpreter', 'none', 'VerticalAlignment', 'top', 'Color', [0.1 0.1 0.1]);
            text(page, 0.95, 0.012, sprintf('© Alejandro Suarez, Ph.D. · NeuroAnalyzer v%s', s.toolboxVersion), ...
                'FontSize', 6, 'Color', T.mutedColor, 'HorizontalAlignment', 'right', 'Interpreter', 'none');
        end

        %% printPage - print('-dpdf'); exportgraphics as a fallback
        function printPage(fig, pdfPath)
            Report.deleteIfExists(pdfPath);
            try
                print(fig, pdfPath, '-dpdf', '-r300');   % >= the window's pixel density: no blurring
            catch ME
                try
                    exportgraphics(fig, pdfPath, 'ContentType', 'image', 'Resolution', 300);
                catch
                    rethrow(ME);
                end
            end
        end

        %% fit - Cut a column to LinesPerColumn lines, with a note
        function c = fit(c)
            n = Report.LinesPerColumn;
            if numel(c) > n
                more = numel(c) - (n - 1);
                c = [c(1:n - 1), {sprintf('... %d more line(s): see the session file', more)}];
            end
        end

        %% wrap - Wrap each line at width characters (continuation indented)
        % Breaks at the last space before width when there is one in the
        % second half of the line, else mid-word (paths, long numbers).
        function out = wrap(lines, width)
            out = {};
            for k = 1:numel(lines)
                t = char(lines{k});
                first = true;
                while numel(t) > width
                    cut = find(t(1:width + 1) == ' ', 1, 'last');
                    if isempty(cut) || cut <= width / 2
                        out{end+1} = t(1:width); %#ok<AGROW>
                        rest = t(width + 1:end);
                    else
                        out{end+1} = t(1:cut - 1); %#ok<AGROW>
                        rest = t(cut + 1:end);
                    end
                    t = ['     ' rest];
                    first = false;
                end
                if first || ~isempty(strtrim(t)), out{end+1} = t; end %#ok<AGROW>
            end
        end

        function t = thousands(n)
            t = sprintf('%d', round(n));
            k = numel(t) - 3;
            while k > 0
                t = [t(1:k) ',' t(k + 1:end)];
                k = k - 3;
            end
        end
    end
end
