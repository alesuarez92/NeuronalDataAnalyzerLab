%% LDFGrandAverageApp.m
% =========================================================================
% AVERAGE LDF VIEWER - GRAND AVERAGE OF SEGMENTED LDF TRIALS
% =========================================================================
% Launched from Main. Built with UIKit.window: numbered step cards on the
% left (1 Load trial files, 2 Options, 3 Grand average) and two plots on
% the right (all trials; grand average mean ± SD). Loads one or more .mat
% files containing segmentedLDF and segmentedTime (from
% ProcessingLDFApp); files are appended to the current set when their
% time axes match, otherwise skipped and reported. Optional "Relative to
% baseline" subtracts each trial's pre-stimulus (t < 0) mean. Clear
% removes all trials. updateControls() enables actions from the data
% state and marks the next step primary.
% "Try demo data" (loadDemo) replaces the trials with DemoData's
% synthetic trials (relative to baseline on). Programmatic use (no dialogs):
% openFiles(paths), setRelative(tf), plotGrandAverage().
% =========================================================================

classdef LDFGrandAverageApp < handle
    %% PROPERTIES: UI, loaded segment matrix, time axis, plot handles
    properties
        UIFig          % Main uifigure (UIKit.window)
        StatusLabel    % Status bar label (UIKit.setStatus)
        HelpBtn        % Opens HelpApp('LDF Average')
        LoadBtn        % Step 1: add segmented files
        ClearBtn       % Step 1: remove all trials
        DemoBtn        % Step 1: load synthetic trials (DemoData)
        FileList       % Step 1: loaded files with trial counts
        InfoLabel      % Step 1: total trials, time window
        RelativeCheck  % Step 2: subtract pre-stimulus baseline
        PlotBtn        % Step 3: plot grand average
        Ax             % uiaxes: all trials
        GrandAxes      % uiaxes: grand average
        GrandPlot      % handle to the average line
        ShadedArea     % handle to the ± SD shading
        SegmentedData  % [nTrials x nSamples] trials from all files
        SegmentedTime  % time axis (s, 0 = onset)
        FileNames = {} % loaded file names (one per accepted file)
        FileCounts = [] % trials contributed by each file
    end

    methods
        %% Constructor - Init SegmentedData empty, build UI
        function app = LDFGrandAverageApp()
            app.SegmentedData = [];
            app.buildUI();
        end

        %% buildUI - Window, step cards (left), trial and average axes (right)
        function buildUI(app)
            T = UITheme;
            W = UIKit.window('Average LDF Viewer', ...
                'Pool segmented LDF trials from several files and plot the grand average', ...
                'LDF Average', [1150 740]);
            app.UIFig = W.Fig;
            app.StatusLabel = W.Status;
            app.HelpBtn = W.HelpBtn;
            W.Body.RowHeight = {'1x'};
            W.Body.ColumnWidth = {300, '1x'};

            left = uigridlayout(W.Body, [4 1], 'Padding', [0 0 0 0], 'RowSpacing', 10, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            heights = cell(1, 4);

            % --- 1 Load trial files ---
            [p, g, heights{1}] = stepCard(left, 1, 'Load trial files', {T.buttonHeight, T.buttonHeight, 120, 34});
            p.Layout.Row = 1;
            app.LoadBtn = UIKit.button(g, 'Add files...', @(~,~)app.loadFiles(), 'primary', ...
                'Add one or more .mat files with segmentedLDF and segmentedTime (saved by LDF Processing); trials are pooled');
            app.LoadBtn.Layout.Row = 2; app.LoadBtn.Layout.Column = 1;
            app.ClearBtn = UIKit.button(g, 'Clear all', @(~,~)app.clearSegments(), 'danger', ...
                'Remove all loaded trials and start again');
            app.ClearBtn.Layout.Row = 2; app.ClearBtn.Layout.Column = 2;
            app.DemoBtn = UIKit.button(g, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Replace the loaded trials with synthetic ones with known answers (-5 to +20 s at 10 Hz; ' ...
                'each has a +30 PU response peaking 4 s after onset on a ~120 PU baseline)']);
            app.DemoBtn.Layout.Row = 3; app.DemoBtn.Layout.Column = [1 2];
            app.FileList = uilistbox(g, 'Items', {'(no files loaded)'}, 'FontSize', T.fontSmall, ...
                'Tooltip', 'Files pooled so far, with the number of trials each contributed');
            app.FileList.Layout.Row = 4; app.FileList.Layout.Column = [1 2];
            app.InfoLabel = infoLabel(g, 'No trials loaded', 'Total number of trials and time window');
            app.InfoLabel.Layout.Row = 5; app.InfoLabel.Layout.Column = [1 2];

            % --- 2 Options ---
            [p, g, heights{2}] = stepCard(left, 2, 'Options', {T.controlHeight, 30});
            p.Layout.Row = 2;
            app.RelativeCheck = uicheckbox(g, 'Text', 'Relative to baseline', 'Value', false, ...
                'FontSize', T.fontBody, 'ValueChangedFcn', @(~,~)app.updateSegmentPlot(), ...
                'Tooltip', 'Subtract each trial''s mean over the pre-stimulus period (t < 0 s)');
            app.RelativeCheck.Layout.Row = 2; app.RelativeCheck.Layout.Column = [1 2];
            note = infoLabel(g, 'Subtracts each trial''s pre-stimulus (t < 0) mean.', ...
                'Baseline correction per trial');
            note.Layout.Row = 3; note.Layout.Column = [1 2];

            % --- 3 Grand average ---
            [p, g, heights{3}] = stepCard(left, 3, 'Grand average', {T.buttonHeight});
            p.Layout.Row = 3;
            app.PlotBtn = UIKit.button(g, 'Plot grand average', @(~,~)app.plotGrandAverage(), ...
                'secondary', 'Plot the mean ± SD across all loaded trials');
            app.PlotBtn.Layout.Row = 2; app.PlotBtn.Layout.Column = [1 2];

            heights{4} = '1x';
            left.RowHeight = heights;

            % --- Plots ---
            plotCard = UIKit.card(W.Body, '');
            plotCard.Layout.Row = 1; plotCard.Layout.Column = 2;
            axGrid = uigridlayout(plotCard, [2 1], 'RowHeight', {'1x', '1x'}, ...
                'Padding', [8 8 14 8], 'RowSpacing', 8, 'BackgroundColor', T.cardBg);
            app.Ax = uiaxes(axGrid);
            app.GrandAxes = uiaxes(axGrid);
            app.showPlaceholders();

            UIKit.setStatus(app.StatusLabel, 'Step 1: add segmented trial files (saved by LDF Processing).', 'info');
            app.updateControls();
        end

        %% updateControls - Enable controls from data state; next step is primary
        function updateControls(app)
            hasData = ~isempty(app.SegmentedData);
            hasAvg = ~isempty(app.GrandPlot) && isgraphics(app.GrandPlot);
            app.ClearBtn.Enable = onoff(hasData);
            app.RelativeCheck.Enable = onoff(hasData);
            app.PlotBtn.Enable = onoff(hasData);
            setButtonStyle(app.LoadBtn, ifelse(~hasData, 'primary', 'secondary'));
            setButtonStyle(app.PlotBtn, ifelse(hasData && ~hasAvg, 'primary', 'secondary'));
            if hasData
                app.FileList.Items = cellfun(@(f, n) sprintf('%s  (%d)', f, n), ...
                    app.FileNames, num2cell(app.FileCounts), 'UniformOutput', false);
                t = app.SegmentedTime;
                app.InfoLabel.Text = sprintf('%d trials from %d file(s)\nWindow %.2f to %.2f s', ...
                    size(app.SegmentedData, 1), numel(app.FileNames), t(1), t(end));
                app.InfoLabel.FontColor = UITheme.sectionTitleColor;
            else
                app.FileList.Items = {'(no files loaded)'};
                app.InfoLabel.Text = 'No trials loaded';
                app.InfoLabel.FontColor = UITheme.bodyColor;
            end
        end

        %% loadFiles - Add segmented files; skip files that do not match
        % -------------------------------------------------------------
        % Files without segmentedLDF/segmentedTime, or whose time axis
        % differs from the trials already loaded, are skipped and listed
        % in a warning. Picks the files, then openFiles(paths).
        % -------------------------------------------------------------
        function loadFiles(app)
            UIKit.setStatus(app.StatusLabel, 'Choose segmented trial files...', 'busy');
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = Exporter.getLastUsedPath(); end
            if isempty(startDir), startDir = pwd; end
            [files, path] = uigetfile(fullfile(startDir, '*.mat'), 'Select Segmented Files', 'MultiSelect', 'on');
            figure(app.UIFig);
            if isequal(files, 0)
                UIKit.setStatus(app.StatusLabel, 'No files added.', 'info');
                return;
            end
            if ischar(files), files = {files}; end
            app.openFiles(fullfile(path, files));
        end

        %% openFiles - Add segmented files by path (no dialog)
        % -------------------------------------------------------------
        % paths: cell array of .mat paths (or one char path). Same rules
        % as loadFiles; returns the number of trials added.
        % -------------------------------------------------------------
        function added = openFiles(app, paths)
            added = 0;
            if ischar(paths) || isstring(paths), paths = cellstr(paths); end
            if isempty(paths), return; end
            files = cell(size(paths));
            for i = 1:numel(paths)
                [~, name, ext] = fileparts(paths{i});
                files{i} = [name ext];
            end
            path = fileparts(paths{end});

            dlg = UIKit.busy(app.UIFig, sprintf('Loading %d file(s)...', numel(files)));
            skipped = {};
            nBefore = size(app.SegmentedData, 1);
            for i = 1:length(files)
                if isvalid(dlg), dlg.Message = sprintf('Loading %s (%d of %d)...', files{i}, i, numel(files)); end
                try
                    data = load(paths{i});
                catch ME
                    skipped{end+1} = sprintf('%s: could not be read (%s)', files{i}, ME.message); %#ok<AGROW>
                    continue;
                end
                if ~(isfield(data, 'segmentedLDF') && isfield(data, 'segmentedTime'))
                    skipped{end+1} = sprintf('%s: no segmentedLDF/segmentedTime', files{i}); %#ok<AGROW>
                    continue;
                end
                if isempty(app.SegmentedData)
                    app.SegmentedData = data.segmentedLDF;
                    app.SegmentedTime = data.segmentedTime;
                elseif isequal(app.SegmentedTime, data.segmentedTime)
                    app.SegmentedData = [app.SegmentedData; data.segmentedLDF];
                else
                    skipped{end+1} = sprintf('%s: time axis does not match', files{i}); %#ok<AGROW>
                    continue;
                end
                app.FileNames{end+1} = files{i};
                app.FileCounts(end+1) = size(data.segmentedLDF, 1);
            end
            UIKit.done(dlg);
            Exporter.setLastUsedPath(path);

            added = size(app.SegmentedData, 1) - nBefore;
            if ~isempty(app.SegmentedData)
                app.updateSegmentPlot();   % also refreshes a grand average already shown
            end
            app.updateControls();
            total = size(app.SegmentedData, 1);
            if isempty(skipped)
                UIKit.setStatus(app.StatusLabel, sprintf('Added %d trials (%d in total). Next: plot the grand average.', ...
                    added, total), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Added %d trials (%d in total); %d file(s) skipped.', ...
                    added, total, numel(skipped)), 'warning');
                UIKit.alert(app.UIFig, sprintf('These files were skipped:\n%s', strjoin(skipped, newline)), ...
                    'Some files skipped', 'warning');
            end
        end

        %% loadDemo - Replace the trials with DemoData's synthetic trials
        % -------------------------------------------------------------
        % -5 to +20 s at 10 Hz, one trial per stimulus; each has a +30 PU
        % hyperemia peaking 4 s after onset. Turns "Relative to baseline"
        % on so "Plot grand average" shows the response directly. The last
        % used folder is not changed by the demo.
        % -------------------------------------------------------------
        function loadDemo(app)
            prevLast = Exporter.getLastUsedPath();
            dlg = UIKit.busy(app.UIFig, 'Preparing demo data (first time only takes a few seconds)…');
            try
                p = DemoData.file('ldfTrials');
                UIKit.done(dlg);
                if ~isempty(app.SegmentedData)
                    app.clearSegments();
                end
                app.RelativeCheck.Value = true;
                added = app.openFiles({p});
                restoreLastPath(prevLast);
                if added == 0, return; end
                t = app.SegmentedTime;
                UIKit.setStatus(app.StatusLabel, sprintf(['Demo loaded: %d LDF trials (%g to %g s around onset), ' ...
                    'each with a ~30 PU response peaking 4 s after onset. "Relative to baseline" is on. ' ...
                    'Next: press "Plot grand average".'], added, t(1), t(end)), 'success');
            catch ME
                UIKit.done(dlg);
                restoreLastPath(prevLast);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load the demo data: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not load the demo data:\n%s', ME.message), 'Demo data', 'error');
            end
        end

        %% setRelative - Turn "Relative to baseline" on/off programmatically
        function setRelative(app, tf)
            app.RelativeCheck.Value = logical(tf);
            app.updateSegmentPlot();
        end

        %% updateSegmentPlot - Plot all trials (baseline-corrected if checked)
        function updateSegmentPlot(app)
            if isempty(app.SegmentedData)
                return;
            end
            [segments, ok] = app.correctedSegments();
            if ~ok, return; end
            T = UITheme;
            t = app.SegmentedTime(:)';
            ax = app.Ax;
            cla(ax);
            resetAxesModes(ax);
            ax.ColorOrder = T.plotColors;
            hold(ax, 'on');
            plot(ax, t, segments');
            xline(ax, 0, '-', 'Color', T.stimColor, 'LineWidth', 1.2);
            hold(ax, 'off');
            if app.RelativeCheck.Value
                label = 'All trials (relative to baseline)';
                yl = 'LDF change from baseline';
            else
                label = 'All trials';
                yl = 'LDF';
            end
            UIKit.styleAxes(ax, sprintf('%s (n = %d)', label, size(segments, 1)), 'Time from onset (s)', yl);
            if ~isempty(app.GrandPlot) && isgraphics(app.GrandPlot)
                app.plotGrandAverage();   % keep the average consistent with the option
            end
        end

        %% clearSegments - Remove all trials and reset the plots
        function clearSegments(app)
            app.SegmentedData = [];
            app.SegmentedTime = [];
            app.FileNames = {};
            app.FileCounts = [];
            app.GrandPlot = [];
            app.ShadedArea = [];
            app.showPlaceholders();
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, 'All trials cleared. Add files to start again.', 'info');
        end

        %% plotGrandAverage - Mean ± SD across all trials
        function plotGrandAverage(app)
            if isempty(app.SegmentedData)
                UIKit.alert(app.UIFig, 'No segmented data loaded.', 'No trials', 'warning');
                return;
            end
            [segments, ok] = app.correctedSegments();
            if ~ok, return; end
            T = UITheme;
            t = app.SegmentedTime(:)';
            avg = mean(segments, 1);
            stddev = std(segments, 0, 1);

            ax = app.GrandAxes;
            cla(ax);
            resetAxesModes(ax);
            hold(ax, 'on');
            % Shaded area for std
            app.ShadedArea = fill(ax, [t, fliplr(t)], [avg + stddev, fliplr(avg - stddev)], ...
                T.shadeColor, 'EdgeColor', 'none', 'FaceAlpha', 0.2, 'DisplayName', '± SD');
            % Average trace
            app.GrandPlot = plot(ax, t, avg, 'Color', T.plotColors(1, :), 'LineWidth', 2, ...
                'DisplayName', 'Mean');
            xline(ax, 0, '-', 'Color', T.stimColor, 'LineWidth', 1.2, 'HandleVisibility', 'off');
            hold(ax, 'off');
            legend(ax, 'Location', 'best', 'Box', 'off');
            if app.RelativeCheck.Value
                yl = 'LDF change from baseline';
            else
                yl = 'LDF';
            end
            UIKit.styleAxes(ax, sprintf('Grand average (n = %d)', size(segments, 1)), 'Time from onset (s)', yl);
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf('Grand average of %d trials plotted.', size(segments, 1)), 'success');
        end
    end

    methods (Access = private)
        %% correctedSegments - Trials, baseline-corrected when the option is on
        function [segments, ok] = correctedSegments(app)
            ok = true;
            segments = app.SegmentedData;
            if app.RelativeCheck.Value
                baselineMask = app.SegmentedTime < 0;
                if ~any(baselineMask)
                    ok = false;
                    app.RelativeCheck.Value = false;
                    UIKit.setStatus(app.StatusLabel, 'No pre-stimulus baseline: relative mode turned off.', 'error');
                    UIKit.alert(app.UIFig, ['No pre-stimulus baseline available for correction ' ...
                        '(the trials have no samples before t = 0).'], 'No baseline', 'error');
                    return;
                end
                baselineMeans = mean(segments(:, baselineMask), 2);
                segments = segments - baselineMeans;
            end
        end

        %% showPlaceholders - Empty-axes hints before data
        function showPlaceholders(app)
            legend(app.GrandAxes, 'off');
            % styleAxes first: it removes emptyAxes placeholders
            UIKit.styleAxes(app.Ax, 'All trials');
            UIKit.styleAxes(app.GrandAxes, 'Grand average');
            UIKit.emptyAxes(app.Ax, 'Add trial files (or Try demo data) to begin');
            UIKit.emptyAxes(app.GrandAxes, 'Grand average (mean ± SD) appears here');
        end
    end
end

%% Local helpers
% -------------------------------------------------------------------------

%% restoreLastPath - Put back the last used folder after loading demo data
function restoreLastPath(prev)
    if isempty(prev)
        if ispref('NeuroAnalyzer', 'LastUsedPath'), rmpref('NeuroAnalyzer', 'LastUsedPath'); end
    else
        Exporter.setLastUsedPath(prev);
    end
end

%% stepCard - Card with a numbered step label and a 2-column grid
% rowHeights: heights of the rows below the step label. Returns the
% panel, its grid and the pixel height the card needs.
function [p, g, h] = stepCard(parent, n, text, rowHeights)
    T = UITheme;
    p = UIKit.card(parent, '');
    rh = [{22}, rowHeights];
    g = uigridlayout(p, [numel(rh) 2], 'RowHeight', rh, 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [10 8 10 10], 'RowSpacing', 6, 'ColumnSpacing', 8, ...
        'BackgroundColor', T.cardBg);
    lbl = UIKit.step(g, n, text);
    lbl.Layout.Row = 1; lbl.Layout.Column = [1 2];
    h = sum([rh{:}]) + 6 * (numel(rh) - 1) + 18 + 4;
end

%% infoLabel - Small wrapped muted label for file/result summaries
function lbl = infoLabel(parent, text, tooltip)
    T = UITheme;
    lbl = uilabel(parent, 'Text', text, 'FontSize', T.fontSmall, 'FontColor', T.bodyColor, ...
        'WordWrap', 'on', 'VerticalAlignment', 'top', 'Tooltip', tooltip);
end

%% setButtonStyle - Restyle an existing UIKit button (primary/secondary)
function setButtonStyle(b, style)
    T = UITheme;
    if strcmp(style, 'primary')
        b.BackgroundColor = T.accent; b.FontColor = [1 1 1]; b.FontWeight = 'bold';
    else
        b.BackgroundColor = T.secondaryBg; b.FontColor = T.secondaryFg; b.FontWeight = 'normal';
    end
end

%% resetAxesModes - Undo emptyAxes tick removal / fixed limits
function resetAxesModes(ax)
    ax.XTickMode = 'auto'; ax.YTickMode = 'auto';
    ax.XLimMode = 'auto';  ax.YLimMode = 'auto';
end

%% onoff - 'on'/'off' from a logical
function s = onoff(cond)
    if cond, s = 'on'; else, s = 'off'; end
end

%% ifelse - Return one of two values based on condition
function s = ifelse(cond, a, b)
    if cond
        s = a;
    else
        s = b;
    end
end
