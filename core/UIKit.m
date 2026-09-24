%% UIKit.m
% =========================================================================
% UI KIT - SHARED BUILDING BLOCKS FOR EVERY NEUROANALYZER WINDOW
% =========================================================================
% Static helpers so every window has the same structure and behaviour:
%
%   W = UIKit.window(title, subtitle, helpTopic, [w h])
%       uifigure with header (title, subtitle, Help button), a body grid,
%       a status bar and the copyright footer. Returns struct W with
%       fields Fig, Body (uigridlayout to fill), Status (uilabel), HelpBtn.
%   D = UIKit.dialog(title, subtitle, helpTopic, [w h])
%       Same for small parameter dialogs (compact header, no status bar);
%       D.Body is the form grid, D.Buttons a 1x3 grid for Cancel / OK.
%   UIKit.button(parent, text, callback, style, tooltip)
%       style: 'primary' (teal), 'secondary', 'danger', 'header' (white).
%   UIKit.card(parent, title) / UIKit.step(parent, n, text)
%   UIKit.field(grid, label, kind, value, tooltip, limits)
%       Label + numeric/text/dropdown/checkbox in two adjacent grid cells.
%   UIKit.hint(parent, text)        Light-blue "how to" strip.
%   UIKit.setStatus(lbl, msg, kind) kind: info | success | warning | error | busy
%   UIKit.busy(fig, msg) / UIKit.done(dlg)   Indeterminate progress dialog.
%   UIKit.alert(fig, msg, title, kind)       uialert with the right icon.
%   UIKit.styleAxes(ax, ttl, xl, yl)         Consistent axes look.
%   UIKit.emptyAxes(ax, msg)                 Placeholder text on empty axes.
%   UIKit.footer(parent)
%
% All colors and sizes come from UITheme. Requires R2021a (uifigure,
% uigridlayout, uihyperlink, uiprogressdlg).
% =========================================================================

classdef UIKit
    methods(Static)

        %% window - Standard sub-app window: header | body | status | footer
        function W = window(titleText, subtitleText, helpTopic, sz)
            T = UITheme;
            if nargin < 3, helpTopic = ''; end
            if nargin < 4 || isempty(sz), sz = [1100 720]; end
            W.Fig = uifigure('Name', titleText, 'Color', T.bgGray, 'Resize', 'on', ...
                'Position', UIKit.centeredPosition(sz), 'Visible', 'off');
            main = uigridlayout(W.Fig, [4 1], ...
                'RowHeight', {T.headerHeight, '1x', T.statusHeight, T.footerHeight}, ...
                'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0, ...
                'BackgroundColor', T.bgGray);
            [W.Header, W.HelpBtn] = UIKit.header(main, titleText, subtitleText, helpTopic);
            bodyPanel = uipanel(main, 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            W.Body = uigridlayout(bodyPanel, [1 1], 'Padding', [14 12 14 8], ...
                'RowSpacing', 10, 'ColumnSpacing', 10, 'BackgroundColor', T.bgGray);
            W.Status = UIKit.statusBar(main);
            UIKit.footer(main);
            W.Fig.Visible = 'on';
        end

        %% dialog - Compact modal parameter dialog: header | form | buttons
        % D.Body: form grid (fill with UIKit.field rows); D.Buttons: 1x3 grid
        % whose columns 2 and 3 are for Cancel / OK (column 1 is a spacer).
        function D = dialog(titleText, subtitleText, helpTopic, sz)
            T = UITheme;
            if nargin < 3, helpTopic = ''; end
            if nargin < 4 || isempty(sz), sz = [420 360]; end
            D.Fig = uifigure('Name', titleText, 'Color', T.bgGray, 'Resize', 'off', ...
                'Position', UIKit.centeredPosition(sz), 'WindowStyle', 'modal');
            main = uigridlayout(D.Fig, [3 1], ...
                'RowHeight', {64, '1x', 52}, 'ColumnWidth', {'1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 0, 'BackgroundColor', T.bgGray);
            [D.Header, D.HelpBtn] = UIKit.header(main, titleText, subtitleText, helpTopic, 16);
            bodyPanel = uipanel(main, 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            D.Body = uigridlayout(bodyPanel, [1 2], 'ColumnWidth', {'1x', '1x'}, ...
                'Padding', [18 14 18 6], 'RowSpacing', 8, 'ColumnSpacing', 10, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            btnPanel = uipanel(main, 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            D.Buttons = uigridlayout(btnPanel, [1 3], 'ColumnWidth', {'1x', 100, 100}, ...
                'RowHeight', {T.buttonHeight}, 'Padding', [18 10 18 10], ...
                'ColumnSpacing', 10, 'BackgroundColor', T.bgGray);
            uilabel(D.Buttons, 'Text', '');
        end

        %% header - Dark title bar with optional subtitle and Help button
        function [panel, helpBtn] = header(parent, titleText, subtitleText, helpTopic, titleSize)
            T = UITheme;
            if nargin < 5, titleSize = T.fontTitle; end
            panel = uipanel(parent, 'BackgroundColor', T.headerBg, 'BorderType', 'none');
            g = uigridlayout(panel, [2 2], 'ColumnWidth', {'1x', 96}, ...
                'RowHeight', {'1x', 'fit'}, 'Padding', [T.headerPaddingH 8 16 8], ...
                'RowSpacing', 2, 'ColumnSpacing', 8, 'BackgroundColor', T.headerBg);
            t = uilabel(g, 'Text', titleText, 'FontSize', titleSize, 'FontWeight', 'bold', ...
                'FontColor', T.headerTitleColor, 'VerticalAlignment', 'bottom');
            t.Layout.Row = 1; t.Layout.Column = 1;
            s = uilabel(g, 'Text', subtitleText, 'FontSize', T.fontSubtitle, ...
                'FontColor', T.headerSubtitleColor, 'VerticalAlignment', 'top');
            s.Layout.Row = 2; s.Layout.Column = 1;
            helpBtn = [];
            if ~isempty(helpTopic)
                helpBtn = UIKit.button(g, '? Help', @(~,~)HelpApp(helpTopic), 'header', ...
                    'Step-by-step guide for this window');
                helpBtn.Layout.Row = [1 2]; helpBtn.Layout.Column = 2;
            end
        end

        %% button - Themed push button
        function b = button(parent, text, callback, style, tooltip)
            T = UITheme;
            if nargin < 4 || isempty(style), style = 'secondary'; end
            if nargin < 5, tooltip = ''; end
            b = uibutton(parent, 'push', 'Text', text, 'FontSize', T.fontButton, ...
                'Tooltip', tooltip);
            if ~isempty(callback), b.ButtonPushedFcn = callback; end
            switch style
                case 'primary'
                    b.BackgroundColor = T.accent;      b.FontColor = [1 1 1]; b.FontWeight = 'bold';
                case 'danger'
                    b.BackgroundColor = T.danger;      b.FontColor = [1 1 1];
                case 'header'
                    b.BackgroundColor = [1 1 1];       b.FontColor = T.headerBg; b.FontWeight = 'bold';
                otherwise
                    b.BackgroundColor = T.secondaryBg; b.FontColor = T.secondaryFg;
            end
        end

        %% card - White bordered panel with a bold title
        function p = card(parent, titleText)
            T = UITheme;
            if nargin < 2, titleText = ''; end
            p = uipanel(parent, 'Title', titleText, 'BackgroundColor', T.cardBg, ...
                'HighlightColor', T.cardBorder, 'BorderType', 'line', ...
                'FontWeight', 'bold', 'FontSize', T.fontBody, 'ForegroundColor', T.sectionTitleColor);
        end

        %% step - Numbered workflow step label, e.g. "1  Load data"
        function lbl = step(parent, n, text)
            T = UITheme;
            lbl = uilabel(parent, 'Text', sprintf('%d   %s', n, text), ...
                'FontSize', T.fontBody, 'FontWeight', 'bold', 'FontColor', T.sectionTitleColor);
        end

        %% field - Label in one grid cell, control in the next
        % kind: 'numeric' | 'text' | 'dropdown' | 'checkbox'. For dropdown,
        % value = {items, selected}. limits (numeric only): [min max].
        function c = field(grid, labelText, kind, value, tooltip, limits)
            T = UITheme;
            if nargin < 5, tooltip = ''; end
            if nargin < 6, limits = []; end
            uilabel(grid, 'Text', labelText, 'FontSize', T.fontBody, ...
                'FontColor', T.sectionTitleColor, 'Tooltip', tooltip);
            switch kind
                case 'numeric'
                    c = uieditfield(grid, 'numeric', 'Value', value, 'Tooltip', tooltip);
                    if ~isempty(limits), c.Limits = limits; end
                case 'dropdown'
                    c = uidropdown(grid, 'Items', value{1}, 'Value', value{2}, 'Tooltip', tooltip);
                case 'checkbox'
                    c = uicheckbox(grid, 'Text', '', 'Value', value, 'Tooltip', tooltip);
                otherwise
                    c = uieditfield(grid, 'text', 'Value', value, 'Tooltip', tooltip);
            end
        end

        %% hint - Light-blue explanatory strip ("Tip: ...")
        function lbl = hint(parent, text)
            T = UITheme;
            p = uipanel(parent, 'BackgroundColor', T.hintBg, 'HighlightColor', T.hintBorder, ...
                'BorderType', 'line');
            g = uigridlayout(p, [1 1], 'Padding', [10 4 10 4], 'BackgroundColor', T.hintBg);
            lbl = uilabel(g, 'Text', text, 'FontSize', T.fontSmall, 'FontColor', T.info, ...
                'WordWrap', 'on');
        end

        %% statusBar - Single-line status label on a light strip
        function lbl = statusBar(parent)
            T = UITheme;
            p = uipanel(parent, 'BackgroundColor', T.projectBarBg, ...
                'HighlightColor', T.projectBarBorder, 'BorderType', 'line');
            g = uigridlayout(p, [1 1], 'Padding', [14 2 14 2], 'BackgroundColor', T.projectBarBg);
            lbl = uilabel(g, 'Text', '', 'FontSize', T.fontSmall, 'Interpreter', 'none');
            UIKit.setStatus(lbl, 'Ready', 'info');
        end

        %% setStatus - Colored status message; kind: info|success|warning|error|busy
        function setStatus(lbl, msg, kind)
            T = UITheme;
            if nargin < 3, kind = 'info'; end
            if isempty(lbl) || ~isvalid(lbl), return; end
            switch kind
                case 'success', c = T.success; prefix = [char(10003) ' '];
                case 'warning', c = T.warning; prefix = '! ';
                case 'error',   c = T.danger;  prefix = [char(10007) ' '];
                case 'busy',    c = T.info;    prefix = [char(8230) ' '];
                otherwise,      c = T.bodyColor; prefix = '';
            end
            lbl.Text = [prefix msg];
            lbl.FontColor = c;
            drawnow limitrate;
        end

        %% busy - Indeterminate progress dialog for long operations
        % Usage: dlg = UIKit.busy(app.UIFig, 'Filtering...'); ...; UIKit.done(dlg);
        function dlg = busy(fig, msg)
            dlg = uiprogressdlg(fig, 'Title', 'Please wait', 'Message', msg, ...
                'Indeterminate', 'on');
            drawnow;
        end

        %% done - Close a busy dialog if it is still open
        function done(dlg)
            if ~isempty(dlg) && isvalid(dlg), close(dlg); end
        end

        %% alert - uialert with the icon matching kind (error|warning|success|info)
        function alert(fig, msg, titleText, kind)
            if nargin < 3, titleText = 'NeuroAnalyzer'; end
            if nargin < 4, kind = 'error'; end
            uialert(fig, msg, titleText, 'Icon', kind);
        end

        %% styleAxes - Consistent axes look: grid, fonts, labels
        function styleAxes(ax, ttl, xl, yl)
            T = UITheme;
            if nargin >= 2 && ~isempty(ttl), title(ax, ttl, 'FontWeight', 'bold', 'Color', T.sectionTitleColor); end
            if nargin >= 3 && ~isempty(xl), xlabel(ax, xl); end
            if nargin >= 4 && ~isempty(yl), ylabel(ax, yl); end
            ax.FontSize = T.fontSmall;
            ax.Box = 'off';
            ax.TickDir = 'out';
            ax.XGrid = 'on'; ax.YGrid = 'on';
            ax.GridColor = T.axesGrid; ax.GridAlpha = 1;
            ax.XColor = T.bodyColor; ax.YColor = T.bodyColor;
            ax.ColorOrder = T.plotColors;
        end

        %% emptyAxes - Centered placeholder message on empty axes
        function emptyAxes(ax, msg)
            T = UITheme;
            cla(ax);
            text(ax, 0.5, 0.5, msg, 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'Color', T.mutedColor, 'FontSize', T.fontBody, 'Tag', 'emptyHint');
            ax.XTick = []; ax.YTick = [];
        end

        %% footer - Copyright + version, right-aligned
        function footer(parent)
            T = UITheme;
            p = uipanel(parent, 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            g = uigridlayout(p, [1 1], 'Padding', [14 4 14 4], 'BackgroundColor', T.bgGray);
            uihyperlink(g, 'Text', sprintf('© Copyrights by Alejandro Suarez, Ph.D.  ·  v%s', T.version), ...
                'URL', 'https://github.com/alesuarez92', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'HorizontalAlignment', 'right');
        end

        %% centeredPosition - [x y w h] centered on the primary screen
        function pos = centeredPosition(sz)
            scr = get(groot, 'ScreenSize');
            if numel(scr) < 4 || scr(3) < 100, scr = [1 1 1440 900]; end
            w = min(sz(1), scr(3) - 40);
            h = min(sz(2), scr(4) - 80);
            pos = [max(1, (scr(3) - w) / 2), max(1, (scr(4) - h) / 2), w, h];
        end
    end
end
