%% SignalCharacterizationApp.m
% =========================================================================
% SIGNAL CHARACTERIZATION - EXTRACT RESPONSE FEATURES FROM PROCESSED DATA
% =========================================================================
% Load processed/imported data (LDF segments, ERP, or generic t/y), set
% stimulus onset and baseline, select features to compute (peak latency,
% onset delay, FWHM, AUC+, AUC-, rise/decay time, peak amplitude,
% stimulation-response integration). Results in a table; export to CSV or .mat.
%
% Layout (UIKit.window): two tabs that act as a mode switch.
%  "Single file": numbered step cards on the left
%   1 Load data   2 Parameters   3 Features + Extract   4 Export
%  and on the right the selected series (with t0, baseline and extracted
%  peak / half-maximum marked; "Export figure…" above it) and the results table.
%  "Groups & statistics": compare one feature between groups/conditions
%   1 Files and groups (several files per group, e.g. one per animal)
%   2 Feature (one value per subject: feature of each file's mean trace,
%     mean of its per-series values, or every series as a subject)
%   3 Statistical test (paired / unpaired / one-way ANOVA; parametric or
%     rank-based; GroupStats) -> Results tab (statistic, df, p, effect
%     size, CI, n, assumptions) and Plot tab (subjects, pairs, mean ± SEM
%     or box, significance brackets)
%   4 Export (publication figure via FigureExport; values + report)
% One updateControls() sets every enable state from the current data.
% Scriptable (CI walkthroughs, no dialogs): openFile(path), loadDemo(),
% extract() (= extractFeatures()), addGroupFiles(paths, groupName),
% removeGroupFile(idx), moveGroupFile(idx, delta), clearGroups(),
% loadGroupDemo(), runGroupStats(feature, design, method, pair),
% setGroupPlotStyle(style), exportFigure(path, format, target),
% exportGroupResults(path).
% =========================================================================

classdef SignalCharacterizationApp < handle
    properties
        UIFig
        W                  % UIKit.window struct (Fig, Body, Status, HelpBtn)
        LoadBtn
        DemoBtn            % Try demo data (synthetic LDF trials with known answers)
        DataTypeMenu       % 'LDF segments', 'ERP (channel average)', 'Time series (t, y)'
        FileLabel          % What was detected in the loaded file
        T0Edit             % Stimulus onset (s)
        BaselineStartEdit  % Baseline window start (s)
        BaselineEndEdit    % Baseline window end (s)
        DirectionMenu      % 'Auto', 'Positive', 'Negative' response direction
        FeatureList        % Multi-select list of features to compute
        ExtractBtn
        ExportBtn
        ResultsLabel       % "n series · k features" under Export
        SeriesMenu         % Which series to plot
        Axes               % Selected series with features marked
        ResultsTable       % uitable
        Data               % Loaded: t, y or segments, etc.
        FileName
        Fs
        T0
        Baseline
        SeriesT            % Cell of time vectors, one per parsed series
        SeriesY            % Cell of signals, one per parsed series
        SeriesNames        % Cell of names ('Trial k'), same order
        HasResults = false % True once features were extracted for SeriesT/Y
        NFeatures = 0      % Number of features in the current results
        SeriesFigFormatMenu % Format for the single-series figure export
        SeriesExportFigBtn  % "Export figure…" above the series plot

        % --- Mode tabs ---
        ModeTabs           % uitabgroup: Single file | Groups & statistics
        SingleTab
        GroupsTab
        % --- Groups & statistics: controls ---
        GroupNameMenu      % Editable dropdown: group the next files go to
        AddGroupFilesBtn
        GroupDemoBtn
        GroupInfoLabel     % "24 files · 3 groups: ..."
        GroupFeatureMenu   % Feature compared between groups
        SubjectMenu        % What one subject (one value) is
        GroupT0Edit
        GroupBaseStartEdit
        GroupBaseEndEdit
        GroupDirectionMenu
        DesignMenu         % Paired / Unpaired / ANOVA
        MethodMenu         % Parametric / Nonparametric
        GroupAMenu         % Reference group (two-group designs)
        GroupBMenu         % Compared group (two-group designs)
        DesignHint         % How the design pairs / compares subjects
        RunStatsBtn
        FigFormatMenu      % Format for the group figure export
        ExportFigBtn
        ExportValuesBtn
        % --- Groups & statistics: views ---
        GroupTabs          % uitabgroup: Files | Results | Plot
        FilesTab
        ResultsTab
        PlotTab
        GroupTable         % #, File, Group, Series, Value
        MoveUpBtn
        MoveDownBtn
        RemoveGroupFileBtn
        ClearGroupsBtn
        StatsTable         % Quantity | Value
        PostHocTable       % Pairwise comparisons
        ReportText         % Copy-ready summary + assumptions
        PlotStyleMenu      % Mean ± SEM | Box plot
        StatsAxes
        StatsSummaryLabel
        % --- Groups & statistics: data ---
        GroupFiles = struct('path', {}, 'name', {}, 'group', {}, 'dataType', {}, ...
            'T', {}, 'Y', {}, 'nSeries', {}, 'value', {})   % one entry per file (column)
        GroupOrder = {}    % Group names in the order they were created (plot / table order)
        GroupResult = []   % GroupStats.compare output + feature, labels, ...
        GroupStale = false % Settings changed since the last test
        GroupSelectedRow = []   % Row selected in the Files table
        GroupBaselineAuto = true % Baseline window follows the data until edited
        GroupDemo = []     % demoGroups() output (with .truth) after loadGroupDemo
        LastExportPath = '' % File written by the last exportFigure
    end

    properties(Constant, Access = private)
        FeatureItems = {'Peak latency', 'Onset delay (50%)', 'FWHM', ...
            'AUC positive', 'AUC negative', 'Rise time', 'Decay time', ...
            'Peak amplitude', 'Stim–response integral'}
        DataTypes = {'LDF segments (segmentedLDF, segmentedTime)', ...
            'ERP / average response (t, y or lfp_data)', ...
            'Time series (t, y)'}
        SubjectModes = {'File (mean trace)', 'File (mean of series)', 'Each series'}
        SubjectKeys = {'meantrace', 'meanvalues', 'series'}
        Designs = {'Paired (same animals)', 'Unpaired (independent)', 'ANOVA (2+ groups)'}
        DesignKeys = {'paired', 'unpaired', 'anova'}
        Methods = {'Parametric', 'Nonparametric (ranks)'}
        MethodKeys = {'parametric', 'nonparametric'}
        PlotStyles = {'Mean ± SEM', 'Box plot (median, IQR)'}
    end

    methods
        function app = SignalCharacterizationApp()
            app.buildUI();
            app.updateControls();
        end

        %% buildUI - Header | step cards (left) + plot and table (right) | status
        function buildUI(app)
            T = UITheme;
            app.W = UIKit.window('Signal Characterization', ...
                'Extract response features (latency, FWHM, AUC, rise/decay) and compare groups with statistics', ...
                'Signal Characterization', [1240 900]);
            app.UIFig = app.W.Fig;
            body = app.W.Body;
            body.RowHeight = {'1x'};
            body.ColumnWidth = {'1x'};

            % Mode switch: one file (per-series features) or groups + statistics
            app.ModeTabs = uitabgroup(body, 'SelectionChangedFcn', @(~,~)app.onModeChanged());
            app.SingleTab = uitab(app.ModeTabs, 'Title', 'Single file', 'BackgroundColor', T.bgGray);
            app.GroupsTab = uitab(app.ModeTabs, 'Title', 'Groups & statistics', 'BackgroundColor', T.bgGray);
            singleGrid = uigridlayout(app.SingleTab, [1 2], 'ColumnWidth', {320, '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [8 8 8 8], 'ColumnSpacing', 10, 'BackgroundColor', T.bgGray);

            % === LEFT: numbered step cards ===
            left = uigridlayout(singleGrid, [4 1], 'RowHeight', {150, 172, '1x', 100}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');

            % --- 1 Load data ---
            g1 = uigridlayout(UIKit.card(left), [4 1], ...
                'RowHeight', {'fit', T.buttonHeight, T.controlHeight, '1x'}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g1, 1, 'Load data');
            b1 = uigridlayout(g1, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.LoadBtn = UIKit.button(b1, 'Load .mat file', @(~,~)app.loadData(), 'primary', ...
                ['Segmented LDF (segmentedLDF, segmentedTime) from Process LDF, an LFP file ' ...
                 'from Extract Ephys (lfp_data, t_lfp), the ERP export of LFP analysis, ' ...
                 'or any .mat with t and y']);
            app.DemoBtn = UIKit.button(b1, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Load synthetic LDF trials with known answers: hyperemia of about +30 PU ' ...
                 'peaking about 4 s after stimulus onset']);
            f1 = uigridlayout(g1, [1 2], 'ColumnWidth', {70, '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.DataTypeMenu = UIKit.field(f1, 'Data type', 'dropdown', ...
                {app.DataTypes, app.DataTypes{3}}, ...
                'Detected automatically on load; change it if the file holds several formats');
            app.DataTypeMenu.ValueChangedFcn = @(~,~)app.onDataTypeChanged();
            app.FileLabel = uilabel(g1, 'Text', 'No file loaded', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on', 'Interpreter', 'none');

            % --- 2 Parameters ---
            g2 = uigridlayout(UIKit.card(left), [2 1], ...
                'RowHeight', {'fit', 4 * T.controlHeight + 3 * 6}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g2, 2, 'Parameters');
            f2 = uigridlayout(g2, [4 2], 'RowHeight', repmat({T.controlHeight}, 1, 4), ...
                'ColumnWidth', {'1x', 110}, 'Padding', [0 0 0 0], 'RowSpacing', 6, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.T0Edit = UIKit.field(f2, 'Stimulus onset t0 (s)', 'numeric', 0, ...
                'Time of stimulus onset in the trace. Features are measured after t0 (0 for segmented LDF).', ...
                [-1e6 1e6]);
            app.BaselineStartEdit = UIKit.field(f2, 'Baseline start (s)', 'numeric', 0, ...
                ['Start of the baseline window: its mean is the reference level for every feature. ' ...
                 'If the window holds no samples, the pre-onset mean is used.'], [-1e6 1e6]);
            app.BaselineEndEdit = UIKit.field(f2, 'Baseline end (s)', 'numeric', 0.05, ...
                ['End of the baseline window. Set end <= start to use the first 0.05 s ' ...
                 'of each trace instead.'], [-1e6 1e6]);
            app.DirectionMenu = UIKit.field(f2, 'Direction', 'dropdown', ...
                {{'Auto', 'Positive', 'Negative'}, 'Auto'}, ...
                ['Response polarity. Positive: peaks; Negative: troughs; Auto: negative if the ' ...
                 'post-onset deflection below baseline is larger than above']);
            for c = {app.T0Edit, app.BaselineStartEdit, app.BaselineEndEdit, app.DirectionMenu}
                c{1}.ValueChangedFcn = @(~,~)app.onParamsChanged();
            end

            % --- 3 Features + Extract ---
            g3 = uigridlayout(UIKit.card(left), [3 1], ...
                'RowHeight', {'fit', '1x', T.buttonHeight}, 'Padding', [10 8 10 10], ...
                'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g3, 3, 'Features');
            app.FeatureList = uilistbox(g3, 'Items', app.FeatureItems, 'Multiselect', 'on', ...
                'Value', {'Peak latency', 'FWHM', 'AUC positive', 'AUC negative'}, ...
                'FontSize', T.fontBody, ...
                'Tooltip', 'Ctrl/Cmd-click to select several features; Shift-click for a range', ...
                'ValueChangedFcn', @(~,~)app.updateControls());
            app.ExtractBtn = UIKit.button(g3, 'Extract features', @(~,~)app.extractFeatures(), ...
                'primary', 'Compute the selected features for every series in the file');

            % --- 4 Export ---
            g4 = uigridlayout(UIKit.card(left), [3 1], ...
                'RowHeight', {'fit', T.buttonHeight, '1x'}, 'Padding', [10 8 10 10], ...
                'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g4, 4, 'Export results');
            app.ExportBtn = UIKit.button(g4, 'Export to CSV / MAT', @(~,~)app.exportResults(), ...
                'secondary', 'Save the results table as .csv (one row per series) or .mat (data, colNames)');
            app.ResultsLabel = uilabel(g4, 'Text', 'No results yet', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');

            % === RIGHT: plot (with series selector) above results table ===
            right = uigridlayout(singleGrid, [2 1], 'RowHeight', {'1.3x', '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray);
            plotCard = UIKit.card(right, 'Selected series');
            pg = uigridlayout(plotCard, [2 5], 'RowHeight', {T.controlHeight, '1x'}, ...
                'ColumnWidth', {'fit', 200, '1x', 120, 120}, 'Padding', [10 6 10 6], ...
                'BackgroundColor', T.cardBg);
            uilabel(pg, 'Text', 'Show:', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            app.SeriesMenu = uidropdown(pg, 'Items', {'-'}, 'Value', '-', ...
                'Tooltip', 'Series to plot. Clicking a row in the results table also selects it.', ...
                'ValueChangedFcn', @(~,~)app.plotSelected());
            uilabel(pg, 'Text', 'Dashed: t0 · shaded: baseline window · o: peak · bar: FWHM', ...
                'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'HorizontalAlignment', 'right');
            fmts = FigureExport.formats();
            app.SeriesFigFormatMenu = uidropdown(pg, 'Items', fmts, 'Value', fmts{1}, ...
                'Tooltip', ['File format for Export figure: PDF / SVG / EPS are vector (editable in ' ...
                'Illustrator or Inkscape); PNG / TIFF are images at 300 or 600 dpi']);
            app.SeriesExportFigBtn = UIKit.button(pg, ['Export figure' char(8230)], ...
                @(~,~)app.exportFigureDialog('series'), 'secondary', ...
                ['Save this plot as a publication figure (8.5 cm wide, 8 pt Helvetica, white ' ...
                 'background, no grid). The window itself is not changed.']);
            app.Axes = uiaxes(pg);
            app.Axes.Layout.Row = 2; app.Axes.Layout.Column = [1 5];
            UIKit.emptyAxes(app.Axes, 'Load a file (or Try demo data) to begin');

            tableCard = UIKit.card(right, 'Results (one row per series; NaN = not computed or not found)');
            tg = uigridlayout(tableCard, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.ResultsTable = uitable(tg, ...
                'ColumnName', {'Trial_Channel', 'PeakLatency_s', 'OnsetDelay_s', 'FWHM_s', 'AUCpos', 'AUCneg', 'RiseTime_s', 'DecayTime_s', 'PeakAmp', 'Integral'}, ...
                'RowName', {}, 'FontSize', T.fontBody, ...
                'Tooltip', 'Click a row to plot that series', ...
                'CellSelectionCallback', @(~,evt)app.onTableSelect(evt));

            app.buildGroupsUI();
            UIKit.setStatus(app.W.Status, ['Load a .mat file (or Try demo data) to begin (step 1). ' ...
                'To compare animals or conditions, open the Groups & statistics tab.'], 'info');
        end

        %% buildGroupsUI - "Groups & statistics" tab: step cards | Files, Results, Plot
        function buildGroupsUI(app)
            T = UITheme;
            g = uigridlayout(app.GroupsTab, [1 2], 'ColumnWidth', {320, '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [8 8 8 8], 'ColumnSpacing', 10, 'BackgroundColor', T.bgGray);
            left = uigridlayout(g, [4 1], 'RowHeight', {146, 198, 206, 112}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 8, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');

            % --- 1 Files and groups ---
            c1 = uigridlayout(UIKit.card(left), [4 1], ...
                'RowHeight', {'fit', T.controlHeight, T.buttonHeight, '1x'}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(c1, 1, 'Files and groups');
            f1 = uigridlayout(c1, [1 2], 'ColumnWidth', {85, '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.GroupNameMenu = UIKit.field(f1, 'Group', 'dropdown', ...
                {{'Control', 'Stimulated'}, 'Control'}, ...
                ['Group / condition for the next files you add. Pick one or type a new name ' ...
                 '(e.g. Drug). You can also change a file''s group in the Files table.']);
            app.GroupNameMenu.Editable = 'on';
            b1 = uigridlayout(c1, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.AddGroupFilesBtn = UIKit.button(b1, ['Add files' char(8230)], ...
                @(~,~)app.addGroupFilesDialog(), 'primary', ...
                ['Pick one or more .mat files (typically one per animal) for the group above. ' ...
                 'Same formats as the Single file tab (LDF segments, LFP / ERP, t + y).']);
            app.GroupDemoBtn = UIKit.button(b1, 'Try group demo', @(~,~)app.loadGroupDemo(), 'secondary', ...
                ['Synthetic LDF trials, 3 conditions x 8 animals (the same animals in each): ' ...
                 'peak hyperemia Control ~18, Stimulated ~30, Drug ~24 PU']);
            app.GroupInfoLabel = uilabel(c1, 'Text', 'No files yet: add files to at least two groups.', ...
                'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'WordWrap', 'on', 'Interpreter', 'none');

            % --- 2 Feature ---
            c2 = uigridlayout(UIKit.card(left), [2 1], ...
                'RowHeight', {'fit', 5 * T.controlHeight + 4 * 6}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(c2, 2, 'Feature (one value per subject)');
            f2 = uigridlayout(c2, [5 2], 'RowHeight', repmat({T.controlHeight}, 1, 5), ...
                'ColumnWidth', {85, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 6, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.GroupFeatureMenu = UIKit.field(f2, 'Feature', 'dropdown', ...
                {app.FeatureItems, 'Peak amplitude'}, ...
                ['Response feature compared between groups (same definitions as the Single file tab; ' ...
                 'latency, FWHM, rise and decay in s; amplitude in signal units; AUC in signal x s)']);
            app.SubjectMenu = UIKit.field(f2, 'Value per', 'dropdown', ...
                {app.SubjectModes, app.SubjectModes{1}}, ...
                ['What one subject is. File (mean trace): the feature of the average of the file''s ' ...
                 'trials (recommended: one animal = one file, less noise). File (mean of series): the ' ...
                 'mean of the per-trial features. Each series: every trial/channel is a subject.']);
            app.GroupT0Edit = UIKit.field(f2, 'Onset t0 (s)', 'numeric', 0, ...
                'Stimulus onset in each trace (s). Features are measured after t0 (0 for segmented LDF).', ...
                [-1e6 1e6]);
            uilabel(f2, 'Text', 'Baseline (s)', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor, ...
                'Tooltip', 'Baseline window start and end (s); its mean is the reference level');
            bl = uigridlayout(f2, [1 2], 'ColumnWidth', {'1x', '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.GroupBaseStartEdit = uieditfield(bl, 'numeric', 'Value', 0, 'Limits', [-1e6 1e6], ...
                'Tooltip', ['Baseline window start (s). Set automatically to the pre-stimulus part ' ...
                'when the traces start before t0, until you edit it.']);
            app.GroupBaseEndEdit = uieditfield(bl, 'numeric', 'Value', 0.05, 'Limits', [-1e6 1e6], ...
                'Tooltip', 'Baseline window end (s). End <= start: first 0.05 s of each trace.');
            app.GroupDirectionMenu = UIKit.field(f2, 'Direction', 'dropdown', ...
                {{'Auto', 'Positive', 'Negative'}, 'Auto'}, ...
                'Response polarity: Positive (peaks), Negative (troughs) or Auto (larger deflection)');
            for c = {app.GroupFeatureMenu, app.SubjectMenu, app.GroupDirectionMenu}
                c{1}.ValueChangedFcn = @(~,~)app.onGroupSettingsChanged();
            end
            app.GroupT0Edit.ValueChangedFcn = @(~,~)app.onGroupT0Changed();
            app.GroupBaseStartEdit.ValueChangedFcn = @(~,~)app.onGroupBaselineEdited();
            app.GroupBaseEndEdit.ValueChangedFcn = @(~,~)app.onGroupBaselineEdited();

            % --- 3 Statistical test ---
            c3 = uigridlayout(UIKit.card(left), [4 1], ...
                'RowHeight', {'fit', 3 * T.controlHeight + 2 * 6, '1x', T.buttonHeight}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(c3, 3, 'Statistical test');
            f3 = uigridlayout(c3, [3 2], 'RowHeight', repmat({T.controlHeight}, 1, 3), ...
                'ColumnWidth', {60, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 6, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.DesignMenu = UIKit.field(f3, 'Design', 'dropdown', {app.Designs, app.Designs{1}}, ...
                ['Paired: the same animals measured in two conditions (paired t-test / Wilcoxon ' ...
                 'signed-rank). Unpaired: two independent groups (Welch t-test / Mann-Whitney U). ' ...
                 'ANOVA: all groups at once (one-way ANOVA + Tukey-Kramer / Kruskal-Wallis).']);
            app.MethodMenu = UIKit.field(f3, 'Method', 'dropdown', {app.Methods, app.Methods{1}}, ...
                ['Parametric: t-tests / ANOVA on the values (compare means; assume roughly normal data). ' ...
                 'Nonparametric: rank-based tests (no normality assumption). The other family is ' ...
                 'always run too, as a robustness check.']);
            uilabel(f3, 'Text', 'Compare', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor, ...
                'Tooltip', 'Two-group designs: reference group (A) and compared group (B); difference = B - A');
            ab = uigridlayout(f3, [1 3], 'ColumnWidth', {'1x', 'fit', '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 4, 'BackgroundColor', T.cardBg);
            app.GroupAMenu = uidropdown(ab, 'Items', {'-'}, 'Value', '-', ...
                'Tooltip', 'Reference group A (e.g. Control); differences are B - A');
            uilabel(ab, 'Text', 'vs', 'FontSize', T.fontSmall, 'FontColor', T.mutedColor);
            app.GroupBMenu = uidropdown(ab, 'Items', {'-'}, 'Value', '-', ...
                'Tooltip', 'Compared group B (e.g. Stimulated)');
            for c = {app.DesignMenu, app.MethodMenu, app.GroupAMenu, app.GroupBMenu}
                c{1}.ValueChangedFcn = @(~,~)app.onGroupSettingsChanged();
            end
            app.DesignHint = uilabel(c3, 'Text', '', 'FontSize', T.fontSmall, 'FontColor', T.info, ...
                'WordWrap', 'on', 'VerticalAlignment', 'top');
            app.RunStatsBtn = UIKit.button(c3, 'Run test', @(~,~)app.runGroupStats(), 'primary', ...
                ['Compute the feature for every file, run the test and show the Results and Plot tabs ' ...
                 '(statistic, df, p, effect size, 95% CI, n per group, assumptions)']);

            % --- 4 Export ---
            c4 = uigridlayout(UIKit.card(left), [3 1], ...
                'RowHeight', {'fit', T.buttonHeight, T.buttonHeight}, 'Padding', [10 8 10 10], ...
                'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(c4, 4, 'Export');
            e4 = uigridlayout(c4, [1 2], 'ColumnWidth', {'1x', '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            fmts = FigureExport.formats();
            app.FigFormatMenu = uidropdown(e4, 'Items', fmts, 'Value', fmts{1}, ...
                'Tooltip', ['PDF / SVG / EPS: vector (journals, Illustrator, Inkscape). ' ...
                'PNG / TIFF: images at 300 or 600 dpi']);
            app.ExportFigBtn = UIKit.button(e4, ['Export figure' char(8230)], ...
                @(~,~)app.exportFigureDialog('groups'), 'secondary', ...
                ['Save the statistics plot as a publication figure (8.5 cm wide, 8 pt Helvetica, ' ...
                 'white background, no grid). The window itself is not changed.']);
            app.ExportValuesBtn = UIKit.button(c4, ['Export values & report' char(8230)], ...
                @(~,~)app.exportGroupResultsDialog(), 'secondary', ...
                ['.csv: one row per subject (group, subject, value) plus a _report.txt with the ' ...
                 'test results; .mat: the full result struct']);

            % === RIGHT: Files | Results | Plot ===
            app.GroupTabs = uitabgroup(g);
            app.FilesTab = uitab(app.GroupTabs, 'Title', 'Files', 'BackgroundColor', T.cardBg);
            ft = uigridlayout(app.FilesTab, [2 1], 'RowHeight', {T.buttonHeight, '1x'}, ...
                'Padding', [8 8 8 8], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            tb = uigridlayout(ft, [1 5], 'ColumnWidth', {110, 110, 90, '1x', 90}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.MoveUpBtn = UIKit.button(tb, [char(9650) ' Move up'], ...
                @(~,~)app.moveGroupFile(app.GroupSelectedRow, -1), 'secondary', ...
                ['Move the selected file one place up within its group. In paired designs the ' ...
                 'k-th file of each group is the same animal, so the order sets the pairing.']);
            app.MoveDownBtn = UIKit.button(tb, [char(9660) ' Move down'], ...
                @(~,~)app.moveGroupFile(app.GroupSelectedRow, 1), 'secondary', ...
                'Move the selected file one place down within its group (changes the pairing)');
            app.RemoveGroupFileBtn = UIKit.button(tb, 'Remove', ...
                @(~,~)app.removeGroupFile(app.GroupSelectedRow), 'secondary', ...
                'Remove the selected file from its group');
            uilabel(tb, 'Text', ['# = subject number within the group. Paired designs match ' ...
                'subjects by this number (1st with 1st, 2nd with 2nd, ...).'], ...
                'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'WordWrap', 'on');
            app.ClearGroupsBtn = UIKit.button(tb, 'Clear all', @(~,~)app.clearGroups(), 'danger', ...
                'Remove every file from every group');
            app.GroupTable = uitable(ft, 'ColumnName', {'#', 'File', 'Group', 'Series', 'Value'}, ...
                'RowName', {}, 'ColumnEditable', [false false true false false], ...
                'ColumnWidth', {40, 'auto', 140, 60, 110}, 'FontSize', T.fontBody, ...
                'Tooltip', ['Click a row to select it (Move / Remove). Double-click a Group cell to ' ...
                'move the file to another group. Value: the subject value from the last test.'], ...
                'CellEditCallback', @(~,evt)app.onGroupTableEdit(evt), ...
                'CellSelectionCallback', @(~,evt)app.onGroupTableSelect(evt));

            app.ResultsTab = uitab(app.GroupTabs, 'Title', 'Results', 'BackgroundColor', T.cardBg);
            rt = uigridlayout(app.ResultsTab, [4 1], 'RowHeight', {'1x', 'fit', 110, 96}, ...
                'Padding', [8 8 8 8], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            app.StatsTable = uitable(rt, 'ColumnName', {'Quantity', 'Value'}, 'RowName', {}, ...
                'ColumnWidth', {170, 'auto'}, 'FontSize', T.fontBody, ...
                'Tooltip', 'Result of the last test (two-sided p-values; differences are B - A)');
            uilabel(rt, 'Text', 'Pairwise comparisons', 'FontSize', T.fontBody, 'FontWeight', 'bold', ...
                'FontColor', T.sectionTitleColor);
            app.PostHocTable = uitable(rt, 'ColumnName', {'Comparison', 'Difference', '95% CI', 'p', 'Method'}, ...
                'RowName', {}, 'ColumnWidth', {180, 90, 150, 110, 'auto'}, 'FontSize', T.fontBody, ...
                'Tooltip', ['Two groups: the tested difference. ANOVA: every pair (Tukey-Kramer p and ' ...
                'family-wise 95% CI); Kruskal-Wallis: Holm-corrected Mann-Whitney p (median differences)']);
            app.ReportText = uitextarea(rt, 'Editable', 'off', 'FontSize', T.fontSmall, ...
                'Value', {'Run a test (step 3) to see a copy-ready summary and the assumptions here.'}, ...
                'Tooltip', 'Copy-ready summary, assumptions and (paired designs) the list of pairs');

            app.PlotTab = uitab(app.GroupTabs, 'Title', 'Plot', 'BackgroundColor', T.cardBg);
            pt = uigridlayout(app.PlotTab, [3 3], 'RowHeight', {T.controlHeight, '1x', 'fit'}, ...
                'ColumnWidth', {'fit', 190, '1x'}, 'Padding', [8 8 8 8], 'RowSpacing', 6, ...
                'BackgroundColor', T.cardBg);
            uilabel(pt, 'Text', 'Style:', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            app.PlotStyleMenu = uidropdown(pt, 'Items', app.PlotStyles, 'Value', app.PlotStyles{1}, ...
                'Tooltip', ['Mean ± SEM (bar and whiskers) or box plot (median, quartiles, whiskers to ' ...
                'the most extreme value within 1.5 IQR); every subject is always shown'], ...
                'ValueChangedFcn', @(~,~)app.plotGroupStats());
            uilabel(pt, 'Text', ['Dots: subjects · grey lines: pairs · brackets: tested differences ' ...
                '(* p<0.05, ** p<0.01, *** p<0.001)'], 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'HorizontalAlignment', 'right');
            app.StatsAxes = uiaxes(pt);
            app.StatsAxes.Layout.Row = 2; app.StatsAxes.Layout.Column = [1 3];
            UIKit.emptyAxes(app.StatsAxes, 'Add files to two or more groups (or Try group demo), then Run test');
            app.StatsSummaryLabel = uilabel(pt, 'Text', '', 'FontSize', T.fontSmall, ...
                'FontColor', T.sectionTitleColor, 'WordWrap', 'on', 'Interpreter', 'none');
            app.StatsSummaryLabel.Layout.Row = 3; app.StatsSummaryLabel.Layout.Column = [1 3];

            app.refreshGroups();
        end

        %% updateControls - Enable state of every control from the current data
        function updateControls(app)
            hasData = ~isempty(app.Data);
            hasSeries = ~isempty(app.SeriesT);
            hasFeat = ~isempty(app.FeatureList.Value);
            hasRes = ~isempty(app.ResultsTable.Data);
            onOff = {'off', 'on'};
            app.DataTypeMenu.Enable = onOff{hasData + 1};
            for c = {app.T0Edit, app.BaselineStartEdit, app.BaselineEndEdit, app.DirectionMenu}
                c{1}.Enable = onOff{hasData + 1};
            end
            app.FeatureList.Enable = onOff{hasData + 1};
            app.ExtractBtn.Enable = onOff{(hasSeries && hasFeat) + 1};
            app.ExportBtn.Enable = onOff{hasRes + 1};
            app.SeriesMenu.Enable = onOff{hasSeries + 1};
            % Primary style follows the recommended next action
            styleBtn(app.ExtractBtn, hasSeries && ~hasRes);
            styleBtn(app.ExportBtn, hasRes);
            if hasRes
                app.ResultsLabel.Text = sprintf('%d series · %d feature(s) computed', ...
                    size(app.ResultsTable.Data, 1), app.NFeatures);
            else
                app.ResultsLabel.Text = 'No results yet';
            end
            app.SeriesFigFormatMenu.Enable = onOff{hasSeries + 1};
            app.SeriesExportFigBtn.Enable = onOff{hasSeries + 1};

            % --- Groups & statistics ---
            names = app.groupNames();
            hasGF = ~isempty(app.GroupFiles);
            isAnova = strcmp(app.designKey(), 'anova');
            twoOk = numel(names) >= 2 && ~strcmp(app.GroupAMenu.Value, app.GroupBMenu.Value);
            canRun = numel(names) >= 2 && (isAnova || twoOk);
            hasGR = ~isempty(app.GroupResult);
            row = app.GroupSelectedRow;
            hasSel = hasGF && ~isempty(row) && row >= 1 && row <= numel(app.GroupFiles);
            for c = {app.GroupFeatureMenu, app.SubjectMenu, app.GroupT0Edit, app.GroupBaseStartEdit, ...
                    app.GroupBaseEndEdit, app.GroupDirectionMenu, app.DesignMenu, app.MethodMenu}
                c{1}.Enable = onOff{hasGF + 1};
            end
            app.GroupAMenu.Enable = onOff{(~isAnova && numel(names) >= 2) + 1};
            app.GroupBMenu.Enable = app.GroupAMenu.Enable;
            app.RunStatsBtn.Enable = onOff{canRun + 1};
            app.ClearGroupsBtn.Enable = onOff{hasGF + 1};
            app.RemoveGroupFileBtn.Enable = onOff{hasSel + 1};
            app.MoveUpBtn.Enable = onOff{(hasSel && ~isempty(app.neighbourInGroup(row, -1))) + 1};
            app.MoveDownBtn.Enable = onOff{(hasSel && ~isempty(app.neighbourInGroup(row, 1))) + 1};
            app.FigFormatMenu.Enable = onOff{hasGR + 1};
            app.ExportFigBtn.Enable = onOff{hasGR + 1};
            app.ExportValuesBtn.Enable = onOff{hasGR + 1};
            % Primary style follows the recommended next action
            styleBtn(app.AddGroupFilesBtn, numel(names) < 2);
            styleBtn(app.RunStatsBtn, canRun && (~hasGR || app.GroupStale));
            styleBtn(app.ExportFigBtn, hasGR && ~app.GroupStale);
            if ~hasGF
                app.GroupInfoLabel.Text = 'No files yet: add files to at least two groups.';
            else
                counts = cellfun(@(nm) sum(strcmp({app.GroupFiles.group}, nm)), names);
                parts = arrayfun(@(i) sprintf('%s %d', names{i}, counts(i)), 1:numel(names), ...
                    'UniformOutput', false);
                app.GroupInfoLabel.Text = sprintf('%d file(s) in %d group(s): %s', ...
                    numel(app.GroupFiles), numel(names), strjoin(parts, ', '));
            end
            app.DesignHint.Text = app.designHintText();
        end

        %% loadData - Pick a .mat, detect its format, parse series and plot the first
        function loadData(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir), startDir = ProjectManager.getExportDir(); end
            if isempty(startDir), startDir = pwd; end
            [file, path] = uigetfile(fullfile(startDir, '*.mat'), 'Select processed data');
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.openFile(fullfile(path, file));
        end

        %% openFile - Load a .mat without dialogs: detect format, parse series, plot
        % Returns true on success.
        function ok = openFile(app, fullPath)
            ok = false;
            [~, name, ext] = fileparts(fullPath);
            file = [name ext];
            UIKit.setStatus(app.W.Status, sprintf('Loading %s', file), 'busy');
            try
                s = load(fullPath);
            catch ME
                UIKit.setStatus(app.W.Status, 'Load failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Load failed: %s', ME.message), 'Load error');
                return;
            end
            dt = detectDataType(s);
            if isempty(dt)
                UIKit.setStatus(app.W.Status, sprintf('%s: no usable variables', file), 'error');
                UIKit.alert(app.UIFig, sprintf(['%s does not contain a supported format.\n\n' ...
                    'Expected one of:\n  segmentedLDF + segmentedTime (Process LDF)\n' ...
                    '  lfp_data + t_lfp (Extract Ephys, LFP)\n  t + y, or t + LDF\n\n' ...
                    'Variables found: %s'], file, strjoin(fieldnames(s), ', ')), 'Unsupported file');
                return;
            end
            app.Data = s;
            app.FileName = file;
            app.DataTypeMenu.Value = dt;
            % Infer Fs from segmentedTime, lfp_fs, t or t_lfp if present
            if isfield(s, 'segmentedTime') && ~isempty(s.segmentedTime)
                tt = s.segmentedTime(:);
                if numel(tt) > 1
                    app.Fs = 1 / (tt(2) - tt(1));
                else
                    app.Fs = 1000;
                end
            elseif isfield(s, 'lfp_fs') && ~isempty(s.lfp_fs)
                app.Fs = s.lfp_fs;
            elseif isfield(s, 't') || isfield(s, 't_lfp')
                if isfield(s, 't'), t = s.t(:); else, t = s.t_lfp(:); end
                if numel(t) > 1, app.Fs = 1/(t(2)-t(1)); else, app.Fs = 1000; end
            else
                app.Fs = 1000;
            end
            try
                app.parseSeries();
            catch ME
                app.Data = []; app.SeriesT = {}; app.SeriesY = {}; app.SeriesNames = {};
                app.SeriesMenu.Items = {'-'}; app.SeriesMenu.Value = '-';
                app.FileLabel.Text = 'No file loaded';
                UIKit.emptyAxes(app.Axes, 'Load a file to begin');
                app.updateControls();
                UIKit.setStatus(app.W.Status, sprintf('Could not read the series in %s', file), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not read the series in %s: %s', file, ME.message), ...
                    'Load error');
                return;
            end
            % Segmented traces start before onset: default the baseline to
            % the pre-stimulus part instead of the first 50 ms after onset
            msg = '';
            if ~isempty(app.SeriesT)
                tFirst = app.SeriesT{1}(1);
                if tFirst < app.T0Edit.Value
                    app.BaselineStartEdit.Value = tFirst;
                    app.BaselineEndEdit.Value = app.T0Edit.Value;
                    msg = sprintf(' Baseline set to the pre-stimulus window %.3g to %.3g s.', ...
                        tFirst, app.T0Edit.Value);
                    app.plotSelected();
                end
            end
            UIKit.setStatus(app.W.Status, sprintf('Loaded %s: %d series.%s Choose features and click Extract.', ...
                file, numel(app.SeriesT), msg), 'success');
            ok = true;
        end

        %% loadDemo - Load synthetic LDF trials and pre-fill the settings
        % DemoData 'ldfTrials': trials -5..20 s around each stimulus (10 Hz)
        % with a hyperemia of ~+30 PU over ~120 PU peaking ~4 s after
        % onset. Sets t0 = 0, direction Auto, every feature selected (the
        % baseline becomes -5..0 s on load). Returns true on success.
        function ok = loadDemo(app)
            ok = false;
            dlg = UIKit.busy(app.UIFig, sprintf('Preparing demo data (first time only takes a few seconds)%s', char(8230)));
            UIKit.setStatus(app.W.Status, 'Preparing demo data', 'busy');
            try
                p = DemoData.file('ldfTrials');
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, sprintf('Demo data failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not create the demo data: %s', ME.message), 'Demo data');
                return;
            end
            UIKit.done(dlg);
            app.T0Edit.Value = 0;
            app.DirectionMenu.Value = 'Auto';
            if ~app.openFile(p), return; end
            app.FeatureList.Value = app.FeatureItems;
            app.plotSelected();
            app.updateControls();
            UIKit.setStatus(app.W.Status, sprintf(['Demo loaded: %d synthetic LDF trials (-5 to 20 s, stimulus at 0 s), ' ...
                'all features selected. Click Extract features: expect peak latency ~4 s and ' ...
                'peak amplitude ~30 PU.'], numel(app.SeriesT)), 'success');
            ok = true;
        end

        %% extract - Extract the selected features with the current fields (scripts / CI)
        % Same as the Extract features button. Returns true when results exist.
        function ok = extract(app)
            app.extractFeatures();
            ok = app.HasResults;
        end

        %% parseSeries - (Re)build series from Data for the selected data type
        % Clears previous results and refreshes the info label, series menu and plot.
        function parseSeries(app)
            [tCell, yCell] = app.getTimeSeriesFromData(app.DataTypeMenu.Value);
            app.SeriesT = tCell;
            app.SeriesY = yCell;
            app.SeriesNames = arrayfun(@(k) sprintf('Trial %d', k), 1:numel(tCell), ...
                'UniformOutput', false);
            app.ResultsTable.Data = {};
            app.HasResults = false;
            if isempty(tCell)
                app.SeriesMenu.Items = {'-'}; app.SeriesMenu.Value = '-';
                app.FileLabel.Text = sprintf('%s: no series of this type', app.FileName);
                UIKit.emptyAxes(app.Axes, 'No series for this data type: pick another type in step 1');
            else
                app.SeriesMenu.Items = app.SeriesNames;
                app.SeriesMenu.Value = app.SeriesNames{1};
                t1 = tCell{1};
                typeShort = strtok(app.DataTypeMenu.Value, '(');
                app.FileLabel.Text = sprintf('%s\n%s· %d series · Fs %.4g Hz · %.3g to %.3g s', ...
                    app.FileName, typeShort, numel(tCell), app.Fs, t1(1), t1(end));
                app.plotSelected();
            end
            app.updateControls();
        end

        function onDataTypeChanged(app)
            if isempty(app.Data), return; end
            app.parseSeries();
            if isempty(app.SeriesT)
                UIKit.setStatus(app.W.Status, 'The file has no series for this data type', 'warning');
            else
                UIKit.setStatus(app.W.Status, sprintf('%d series for "%s"', numel(app.SeriesT), ...
                    app.DataTypeMenu.Value), 'info');
            end
        end

        %% onParamsChanged - t0/baseline/direction changed: results are stale
        function onParamsChanged(app)
            if app.HasResults
                app.ResultsTable.Data = {};
                app.HasResults = false;
                UIKit.setStatus(app.W.Status, 'Parameters changed: click Extract features again.', 'info');
            end
            app.plotSelected();
            app.updateControls();
        end

        function onTableSelect(app, evt)
            if isempty(evt.Indices), return; end
            r = evt.Indices(1, 1);
            data = app.ResultsTable.Data;
            if r <= size(data, 1) && ismember(data{r, 1}, app.SeriesMenu.Items)
                app.SeriesMenu.Value = data{r, 1};
                app.plotSelected();
            end
        end

        %% baselineWindow - [start end] from the fields, or [] when end <= start
        function bl = baselineWindow(app)
            bl = [app.BaselineStartEdit.Value, app.BaselineEndEdit.Value];
            if bl(2) <= bl(1), bl = []; end
        end

        function extractFeatures(app)
            if isempty(app.Data)
                UIKit.alert(app.UIFig, 'Load data first (step 1).', 'No data'); return;
            end
            app.T0 = app.T0Edit.Value;
            baseline = app.baselineWindow();
            app.Baseline = baseline;
            selected = app.FeatureList.Value;
            if ischar(selected), selected = {selected}; end

            tCell = app.SeriesT;
            yCell = app.SeriesY;
            if isempty(tCell)
                UIKit.alert(app.UIFig, 'Could not parse data for the selected data type.', 'No series');
                return;
            end
            dlg = UIKit.busy(app.UIFig, sprintf('Extracting features from %d series...', numel(tCell)));
            UIKit.setStatus(app.W.Status, 'Extracting features', 'busy');

            % Compute the selected features for each series (NaN = not selected)
            nSkipped = 0;
            names = {};
            rows = zeros(0, numel(app.FeatureItems));

            try
                for k = 1:numel(tCell)
                    t = tCell{k}(:);
                    y = yCell{k}(:);
                    % Skip empty or malformed series (t and y must match)
                    if isempty(t) || numel(t) ~= numel(y)
                        nSkipped = nSkipped + 1;
                        continue;
                    end
                    baseVal = seriesBaseline(t, y, baseline, app.T0);
                    dirn = seriesDirection(t, y, baseVal, app.T0, app.DirectionMenu.Value);
                    names{end+1} = app.SeriesNames{k}; %#ok<AGROW>
                    vals = NaN(1, numel(app.FeatureItems));
                    for f = 1:numel(app.FeatureItems)
                        if ismember(app.FeatureItems{f}, selected)
                            vals(f) = computeFeature(app.FeatureItems{f}, t, y, app.T0, baseVal, dirn);
                        end
                    end
                    rows(end+1, :) = vals; %#ok<AGROW>
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, 'Feature extraction failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Feature extraction failed: %s', ME.message), 'Extract');
                return;
            end
            UIKit.done(dlg);

            % Columns in FeatureItems order: Trial_Channel, PeakLatency_s, ..., Integral
            app.ResultsTable.Data = [names(:), num2cell(rows)];
            app.HasResults = ~isempty(names);
            app.NFeatures = numel(selected);
            app.plotSelected();
            app.updateControls();
            if isempty(names)
                UIKit.setStatus(app.W.Status, 'No valid series: nothing extracted', 'error');
            elseif nSkipped > 0
                UIKit.setStatus(app.W.Status, sprintf('Extracted features for %d series; %d skipped', ...
                    numel(names), nSkipped), 'warning');
            else
                UIKit.setStatus(app.W.Status, sprintf('Extracted %d feature(s) for %d series. Next: Export (step 4).', ...
                    numel(selected), numel(names)), 'success');
            end
            if nSkipped > 0
                UIKit.alert(app.UIFig, sprintf('%d series skipped (empty, or t and y lengths differ).', nSkipped), ...
                    'Skipped series', 'warning');
            end
        end

        %% plotSelected - Plot the chosen series with t0, baseline and features
        % Peak and FWHM are always marked (from the same SignalFeatures calls
        % used for the table) so users can check the numbers visually.
        function plotSelected(app)
            T = UITheme;
            ax = app.Axes;
            k = find(strcmp(app.SeriesNames, app.SeriesMenu.Value), 1);
            if isempty(k)
                if isempty(app.Data), UIKit.emptyAxes(ax, 'Load a file to begin'); end
                return;
            end
            t = app.SeriesT{k}(:);
            y = app.SeriesY{k}(:);
            cla(ax, 'reset');
            if isempty(t) || numel(t) ~= numel(y)
                UIKit.emptyAxes(ax, sprintf('%s is skipped: t and y lengths differ', app.SeriesNames{k}));
                return;
            end
            t0 = app.T0Edit.Value;
            bl = app.baselineWindow();
            baseVal = seriesBaseline(t, y, bl, t0);
            dirn = seriesDirection(t, y, baseVal, t0, app.DirectionMenu.Value);
            hold(ax, 'on');
            % Baseline window (shaded) drawn first so the trace stays on top
            yr = [min(y) max(y)];
            if yr(1) == yr(2), yr = yr + [-1 1]; end
            hs = [];
            if ~isempty(bl)
                hs = patch(ax, [bl(1) bl(2) bl(2) bl(1)], yr([1 1 2 2]), T.shadeColor, ...
                    'FaceAlpha', 0.10, 'EdgeColor', 'none', 'DisplayName', 'Baseline window');
            end
            hy = plot(ax, t, y, 'Color', T.plotColors(1, :), 'LineWidth', 1.2, ...
                'DisplayName', app.SeriesNames{k});
            hb = plot(ax, t([1 end]), [baseVal baseVal], ':', 'Color', T.bodyColor, ...
                'LineWidth', 1, 'DisplayName', sprintf('Baseline %.3g', baseVal));
            ht = xline(ax, t0, '--', 'Color', T.stimColor, 'LineWidth', 1.2, 'DisplayName', 't0');
            handles = [hs, hy, hb, ht];
            % Peak and half-maximum width (same definitions as SignalFeatures)
            [amp, tPk] = SignalFeatures.peakAmplitude(t, y, t0, dirn, baseVal);
            if isfinite(amp)
                hp = plot(ax, tPk, baseVal + amp, 'o', 'MarkerSize', 8, 'LineWidth', 1.5, ...
                    'Color', T.plotColors(2, :), 'DisplayName', ...
                    sprintf('Peak %.3g at %.3g s', amp, tPk - t0));
                handles(end+1) = hp;
                [tA, tB, half] = fwhmSpan(t, y, t0, dirn, baseVal);
                if ~isempty(tA)
                    hw = plot(ax, [tA tB], [half half], '-', 'LineWidth', 2.5, ...
                        'Color', T.plotColors(3, :), 'DisplayName', sprintf('FWHM %.3g s', tB - tA));
                    handles(end+1) = hw;
                end
            end
            hold(ax, 'off');
            xlim(ax, [t(1) t(end)]);
            ttl = sprintf('%s  (%s response)', app.SeriesNames{k}, ...
                strrep(strrep(dirn, 'max', 'positive'), 'min', 'negative'));
            UIKit.styleAxes(ax, ttl, 'Time (s)', 'Signal');
            legend(ax, handles, 'Location', 'best', 'FontSize', T.fontTiny, 'Box', 'off');
        end

        function [tCell, yCell] = getTimeSeriesFromData(app, dt)
            [tCell, yCell] = parseSeriesStruct(app.Data, dt);
        end

        function exportResults(app)
            data = app.ResultsTable.Data;
            if isempty(data)
                UIKit.alert(app.UIFig, 'No results to export. Run Extract features first (step 3).', 'Export');
                return;
            end
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = pwd; end
            [file, path] = uiputfile({'*.csv', 'CSV table (*.csv)'; '*.mat', 'MAT file (*.mat)'}, ...
                'Export features', fullfile(startDir, 'signal_features.csv'));
            figure(app.UIFig);
            if isequal(file, 0), return; end
            fullPath = fullfile(path, file);
            colNames = app.ResultsTable.ColumnName;
            if iscell(colNames), colNames = colNames(:)'; end
            try
                if endsWith(lower(fullPath), '.csv')
                    T = cell2table(data, 'VariableNames', colNames);
                    writetable(T, fullPath);
                else
                    save(fullPath, 'data', 'colNames');
                end
                UIKit.setStatus(app.W.Status, sprintf('Exported %d rows to %s', size(data, 1), file), 'success');
            catch ME
                UIKit.setStatus(app.W.Status, 'Export failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Export failed: %s', ME.message), 'Export');
            end
        end

        %% ================= Groups & statistics ==========================

        %% onModeChanged - Tab switched: say what to do next in that mode
        function onModeChanged(app)
            if app.ModeTabs.SelectedTab == app.GroupsTab
                if isempty(app.GroupFiles)
                    UIKit.setStatus(app.W.Status, ['Groups & statistics: choose a group name and click ' ...
                        'Add files (step 1), or click Try group demo.'], 'info');
                elseif numel(app.groupNames()) < 2
                    UIKit.setStatus(app.W.Status, 'Add files to a second group (type its name in step 1).', 'info');
                elseif isempty(app.GroupResult) || app.GroupStale
                    UIKit.setStatus(app.W.Status, 'Choose the feature and the design, then click Run test (step 3).', 'info');
                end
            end
            app.updateControls();
        end

        %% addGroupFilesDialog - Pick .mat files for the group named in step 1
        function addGroupFilesDialog(app)
            groupName = strtrim(char(app.GroupNameMenu.Value));
            if isempty(groupName)
                UIKit.alert(app.UIFig, 'Type or choose a group name first (step 1).', 'Group name', 'warning');
                return;
            end
            startDir = ProjectManager.getImportDir();
            if isempty(startDir), startDir = ProjectManager.getExportDir(); end
            if isempty(startDir), startDir = pwd; end
            [file, path] = uigetfile(fullfile(startDir, '*.mat'), ...
                sprintf('Files for group "%s" (e.g. one per animal)', groupName), 'MultiSelect', 'on');
            figure(app.UIFig);
            if isequal(file, 0), return; end
            % Alphabetical order (animal01, animal02, ...) sets the subject numbers
            file = sort(cellstr(file));
            app.addGroupFiles(fullfile(path, file), groupName);
        end

        %% addGroupFiles - Add .mat files to a group without dialogs; true if any was added
        % paths: char, string or cell array of paths; groupName: text (default:
        % the Group field). Files are read as in the Single file tab (same
        % formats); files that cannot be read are listed and skipped. The
        % order of paths sets the subject numbers used to pair files.
        function ok = addGroupFiles(app, paths, groupName)
            ok = false;
            if nargin < 3 || isempty(groupName), groupName = app.GroupNameMenu.Value; end
            groupName = strtrim(char(groupName));
            if isempty(groupName)
                UIKit.alert(app.UIFig, 'Type or choose a group name first (step 1).', 'Group name', 'warning');
                return;
            end
            paths = cellstr(paths);
            nAdded = 0;
            failed = {};
            UIKit.setStatus(app.W.Status, sprintf('Reading %d file(s) for %s', numel(paths), groupName), 'busy');
            dlg = UIKit.busy(app.UIFig, sprintf('Reading %d file(s) for %s%s', numel(paths), groupName, char(8230)));
            for i = 1:numel(paths)
                [~, nm, ext] = fileparts(paths{i});
                try
                    s = load(paths{i});
                    dt = detectDataType(s);
                    if isempty(dt)
                        error('NeuroAnalyzer:SignalCharacterization:format', ...
                            'no supported variables (found: %s)', strjoin(fieldnames(s), ', '));
                    end
                    [tc, yc] = parseSeriesStruct(s, dt);
                    if isempty(tc)
                        error('NeuroAnalyzer:SignalCharacterization:format', 'no series found');
                    end
                catch ME
                    failed{end + 1} = sprintf('%s: %s', [nm ext], ME.message); %#ok<AGROW>
                    continue;
                end
                entry = struct('path', paths{i}, 'name', [nm ext], 'group', groupName, ...
                    'dataType', dt, 'T', {tc}, 'Y', {yc}, 'nSeries', numel(tc), 'value', NaN);
                app.GroupFiles(end + 1, 1) = entry;
                nAdded = nAdded + 1;
            end
            UIKit.done(dlg);
            if nAdded > 0 && ~any(strcmp(app.GroupOrder, groupName))
                app.GroupOrder{end + 1} = groupName;
            end
            if nAdded > 0
                app.markGroupStale();
                app.applyGroupBaselineDefault();
                app.refreshGroups();
                app.GroupNameMenu.Value = groupName;
                app.ModeTabs.SelectedTab = app.GroupsTab;
                app.GroupTabs.SelectedTab = app.FilesTab;
                if numel(app.groupNames()) < 2
                    msg = sprintf(['Added %d file(s) to %s. Add files to a second group ' ...
                        '(type its name in step 1).'], nAdded, groupName);
                else
                    msg = sprintf(['Added %d file(s) to %s. Choose the feature and the design, ' ...
                        'then click Run test (step 3).'], nAdded, groupName);
                end
                if isempty(failed)
                    UIKit.setStatus(app.W.Status, msg, 'success');
                else
                    UIKit.setStatus(app.W.Status, sprintf('%s %d file(s) skipped.', msg, numel(failed)), 'warning');
                end
                ok = true;
            else
                UIKit.setStatus(app.W.Status, 'No file added: none could be read', 'error');
            end
            if ~isempty(failed)
                UIKit.alert(app.UIFig, sprintf(['These files were skipped (expected segmentedLDF + ' ...
                    'segmentedTime, lfp_data + t_lfp, or t + y):\n%s'], strjoin(failed, newline)), ...
                    'Add files', 'warning');
            end
        end

        %% removeGroupFile - Remove file idx (row of the Files table); true on success
        function ok = removeGroupFile(app, idx)
            ok = false;
            if isempty(idx) || idx < 1 || idx > numel(app.GroupFiles), return; end
            name = app.GroupFiles(idx).name;
            app.GroupFiles(idx) = [];
            app.GroupSelectedRow = [];
            app.markGroupStale();
            app.refreshGroups();
            UIKit.setStatus(app.W.Status, sprintf('Removed %s.', name), 'info');
            ok = true;
        end

        %% moveGroupFile - Swap file idx with the previous (-1) or next (+1) file of its group
        % Changes the subject numbers, i.e. the pairing in paired designs.
        function ok = moveGroupFile(app, idx, delta)
            ok = false;
            j = app.neighbourInGroup(idx, delta);
            if isempty(j), return; end
            moved = app.GroupFiles(idx);
            app.GroupFiles(idx) = app.GroupFiles(j);
            app.GroupFiles(j) = moved;
            app.GroupSelectedRow = j;
            app.markGroupStale();
            app.refreshGroups();
            k = sum(strcmp({app.GroupFiles(1:j).group}, moved.group));
            UIKit.setStatus(app.W.Status, sprintf('%s is now subject %d of %s.', moved.name, k, moved.group), 'info');
            ok = true;
        end

        %% neighbourInGroup - Index of the previous/next file of the same group ([] if none)
        function j = neighbourInGroup(app, idx, delta)
            j = [];
            if isempty(idx) || idx < 1 || idx > numel(app.GroupFiles), return; end
            same = find(strcmp({app.GroupFiles.group}, app.GroupFiles(idx).group));
            k = find(same == idx, 1) + delta;
            if k >= 1 && k <= numel(same), j = same(k); end
        end

        %% clearGroups - Remove every group file and the last result
        function clearGroups(app)
            app.GroupFiles = app.GroupFiles([]);
            app.GroupOrder = {};
            app.GroupResult = [];
            app.GroupStale = false;
            app.GroupSelectedRow = [];
            app.GroupBaselineAuto = true;
            app.GroupDemo = [];
            app.refreshGroups();
            app.showGroupResults();
            app.plotGroupStats();
            UIKit.setStatus(app.W.Status, 'Groups cleared. Add files (step 1) or click Try group demo.', 'info');
        end

        %% loadGroupDemo - Demo files for 3 conditions x 8 animals; paired test preselected
        % core/demo/demoGroups: the same 8 animals in Control, Stimulated and
        % Drug (true peak hyperemia 18, 30 and 24 PU). Sets feature Peak
        % amplitude (file mean trace), t0 = 0, baseline -5..0 s, design
        % Paired, Control vs Stimulated. Returns true on success.
        function ok = loadGroupDemo(app)
            ok = false;
            dlg = UIKit.busy(app.UIFig, sprintf('Writing demo group files (3 conditions x 8 animals)%s', char(8230)));
            UIKit.setStatus(app.W.Status, 'Preparing group demo data', 'busy');
            try
                ensureDemoPath();
                demo = demoGroups();
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, sprintf('Group demo failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not create the group demo data: %s', ME.message), 'Group demo');
                return;
            end
            UIKit.done(dlg);
            app.clearGroups();
            app.GroupFeatureMenu.Value = 'Peak amplitude';
            app.SubjectMenu.Value = app.SubjectModes{1};
            app.GroupT0Edit.Value = 0;
            app.GroupDirectionMenu.Value = 'Auto';
            app.DesignMenu.Value = app.Designs{1};
            app.MethodMenu.Value = app.Methods{1};
            for c = 1:numel(demo.conditions)
                if ~app.addGroupFiles(demo.paths{c}, demo.conditions{c}), return; end
            end
            app.GroupDemo = demo;
            app.GroupAMenu.Value = demo.conditions{1};
            app.GroupBMenu.Value = demo.conditions{2};
            app.updateControls();
            app.ModeTabs.SelectedTab = app.GroupsTab;
            app.GroupTabs.SelectedTab = app.FilesTab;
            UIKit.setStatus(app.W.Status, sprintf(['Group demo loaded: %d animals x 3 conditions, the same ' ...
                'animals in each (true peak hyperemia Control 18, Stimulated 30, Drug 24 PU). Click Run test: ' ...
                'paired Stimulated vs Control should give about +12 PU with p < 0.001.'], ...
                demo.truth.nAnimals), 'success');
            ok = true;
        end

        %% runGroupStats - Compute the feature per subject and run the test (no dialogs)
        % All arguments optional (default: the current fields):
        %   feature  one of the feature names, e.g. 'Peak amplitude'
        %   design   'paired' | 'unpaired' | 'anova' (or a Design menu item)
        %   method   'parametric' | 'nonparametric' (or a Method menu item)
        %   pair     {groupA, groupB} for two-group designs (difference B - A)
        % Result in app.GroupResult (GroupStats.compare output plus feature,
        % labels, settings). Returns true when the test ran.
        function ok = runGroupStats(app, feature, design, method, pair)
            ok = false;
            try
                if nargin >= 2 && ~isempty(feature)
                    app.GroupFeatureMenu.Value = pickItem(feature, app.FeatureItems, app.FeatureItems, 'feature');
                end
                if nargin >= 3 && ~isempty(design)
                    app.DesignMenu.Value = pickItem(design, app.Designs, app.DesignKeys, 'design');
                end
                if nargin >= 4 && ~isempty(method)
                    app.MethodMenu.Value = pickItem(method, app.Methods, app.MethodKeys, 'method');
                end
                names = app.groupNames();
                if nargin >= 5 && ~isempty(pair)
                    pair = cellstr(pair);
                    app.GroupAMenu.Value = pickItem(pair{1}, names, names, 'group');
                    app.GroupBMenu.Value = pickItem(pair{2}, names, names, 'group');
                end
            catch ME
                UIKit.setStatus(app.W.Status, ME.message, 'error');
                UIKit.alert(app.UIFig, ME.message, 'Group statistics');
                return;
            end
            app.updateControls();
            names = app.groupNames();
            if numel(names) < 2
                UIKit.setStatus(app.W.Status, 'Add files to at least two groups first (step 1).', 'error');
                UIKit.alert(app.UIFig, 'Add files to at least two groups first (step 1), or click Try group demo.', ...
                    'Group statistics');
                return;
            end
            dkey = app.designKey();
            if strcmp(dkey, 'anova')
                use = names;
            else
                use = {app.GroupAMenu.Value, app.GroupBMenu.Value};
                if strcmp(use{1}, use{2})
                    UIKit.alert(app.UIFig, 'Choose two different groups to compare (step 3).', 'Group statistics');
                    return;
                end
            end
            feature = app.GroupFeatureMenu.Value;
            dlg = UIKit.busy(app.UIFig, sprintf('Computing %s for %d file(s) and running the test%s', ...
                lower(feature), numel(app.GroupFiles), char(8230)));
            UIKit.setStatus(app.W.Status, 'Running group statistics', 'busy');
            try
                [vals, labels] = app.computeGroupValues(feature, use);
                res = GroupStats.compare(vals, use, dkey, app.methodKey());
            catch ME
                UIKit.done(dlg);
                app.refreshGroups();
                UIKit.setStatus(app.W.Status, sprintf('Test not run: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, ME.message, 'Group statistics');
                return;
            end
            UIKit.done(dlg);
            % Labels of the subjects actually analysed (same exclusions as compare)
            if strcmp(dkey, 'paired')
                keep = isfinite(vals{1}) & isfinite(vals{2});
                labels = {labels{1}(keep), labels{2}(keep)};
            else
                labels = cellfun(@(l, v) l(isfinite(v)), labels, vals, 'UniformOutput', false);
            end
            res.labels = labels;
            res.feature = feature;
            res.subjectMode = app.SubjectMenu.Value;
            res.designLabel = app.DesignMenu.Value;
            res.unit = app.groupUnit();
            res.settings = struct('t0', app.GroupT0Edit.Value, ...
                'baseline', [app.GroupBaseStartEdit.Value, app.GroupBaseEndEdit.Value], ...
                'direction', app.GroupDirectionMenu.Value);
            app.GroupResult = res;
            app.GroupStale = false;
            app.refreshGroups();
            app.showGroupResults();
            app.plotGroupStats();
            app.ModeTabs.SelectedTab = app.GroupsTab;
            app.GroupTabs.SelectedTab = app.PlotTab;
            app.updateControls();
            UIKit.setStatus(app.W.Status, [res.summary ' Next: Export figure (step 4).'], 'success');
            ok = true;
        end

        %% computeGroupValues - One value per subject for the groups in groupList
        % vals / labels: cell per group (column vectors / cellstr). Also stores
        % each file's value (file modes) for the Files table.
        function [vals, labels] = computeGroupValues(app, feature, groupList)
            t0 = app.GroupT0Edit.Value;
            bl = [app.GroupBaseStartEdit.Value, app.GroupBaseEndEdit.Value];
            if bl(2) <= bl(1), bl = []; end
            dirChoice = app.GroupDirectionMenu.Value;
            subjMode = app.subjectModeKey();
            nF = numel(app.GroupFiles);
            perFile = cell(nF, 1);
            perLbl = cell(nF, 1);
            for i = 1:nF
                gf = app.GroupFiles(i);
                fileVal = NaN;
                handled = false;
                if strcmp(subjMode, 'meantrace')
                    [tm, ym, same] = meanTrace(gf.T, gf.Y);
                    if same
                        fileVal = seriesFeature(feature, tm, ym, t0, bl, dirChoice);
                        handled = true;
                    end
                end
                if ~handled
                    v = NaN(gf.nSeries, 1);
                    for k = 1:gf.nSeries
                        v(k) = seriesFeature(feature, gf.T{k}, gf.Y{k}, t0, bl, dirChoice);
                    end
                    if strcmp(subjMode, 'series')
                        perFile{i} = v;
                        perLbl{i} = arrayfun(@(k) sprintf('%s #%d', gf.name, k), (1:gf.nSeries)', ...
                            'UniformOutput', false);
                        app.GroupFiles(i).value = NaN;
                        continue;
                    end
                    fin = v(isfinite(v));
                    if ~isempty(fin), fileVal = mean(fin); end
                end
                perFile{i} = fileVal;
                perLbl{i} = {gf.name};
                app.GroupFiles(i).value = fileVal;
            end
            groups = {app.GroupFiles.group};
            vals = cell(1, numel(groupList));
            labels = cell(1, numel(groupList));
            for g = 1:numel(groupList)
                idx = find(strcmp(groups, groupList{g}));
                vals{g} = vertcat(perFile{idx});
                labels{g} = vertcat(perLbl{idx});
            end
        end

        %% showGroupResults - Fill the Results tab from GroupResult
        function showGroupResults(app)
            r = app.GroupResult;
            if isempty(r)
                app.StatsTable.Data = {};
                app.PostHocTable.Data = {};
                app.ReportText.Value = {'Run a test (step 3) to see a copy-ready summary and the assumptions here.'};
                return;
            end
            m = r.main;
            names = r.groupNames;
            per = @(f) strjoin(arrayfun(@(i) f(i), 1:numel(names), 'UniformOutput', false), '  ·  ');
            nTxt = per(@(i) sprintf('%s %d', names{i}, r.desc(i).n));
            if strcmp(r.design, 'paired'), nTxt = sprintf('%s  (%d pairs)', nTxt, r.desc(1).n); end
            if numel(m.df) == 2
                dfTxt = sprintf('%g, %g', m.df(1), m.df(2));
            elseif isnan(m.df)
                dfTxt = char(8212);
            else
                dfTxt = sprintf('%.4g', m.df);
            end
            effTxt = sprintf('%s = %.3g', m.effectName, m.effect);
            if ~isempty(m.effect2Name), effTxt = sprintf('%s;  %s = %.3g', effTxt, m.effect2Name, m.effect2); end
            if r.checkAgrees, agree = 'consistent'; else, agree = 'DISAGREES: interpret with care'; end
            rows = {
                'Test', sprintf('%s (%s)', m.test, m.method)
                'Design', r.designLabel
                'Feature', sprintf('%s (%s), value per %s', r.feature, r.unit, lower(r.subjectMode))
                'n per group', nTxt
                'Mean ± SD', per(@(i) sprintf('%s %.4g ± %.3g', names{i}, r.desc(i).mean, r.desc(i).sd))
                'Mean ± SEM', per(@(i) sprintf('%s %.4g ± %.3g', names{i}, r.desc(i).mean, r.desc(i).sem))
                'Median [IQR]', per(@(i) sprintf('%s %.4g [%.4g, %.4g]', names{i}, r.desc(i).median, r.desc(i).q1, r.desc(i).q3))
                'Statistic', GroupStats.statText(m)
                'df', dfTxt
                'p (two-sided)', sprintf('%.4g   %s', m.p, GroupStats.stars(m.p))
                'Effect size', effTxt};
            if ~strcmp(r.design, 'anova')
                c = r.comparisons(1);
                if all(isfinite(c.ci))
                    rows(end + 1, :) = {'Difference [95% CI]', sprintf('%s = %.4g [%.4g, %.4g]', c.label, c.diff, c.ci(1), c.ci(2))};
                else
                    rows(end + 1, :) = {'Median difference', sprintf('%s = %.4g', c.label, c.diff)};
                end
            end
            rows(end + 1, :) = {'Robustness check', sprintf('%s: %s, %s = %.3g (%s)', r.check.test, ...
                GroupStats.formatP(r.check.p), r.check.effectName, r.check.effect, agree)};
            % Table cells do not wrap: one sentence per row, so nothing is cut off
            parts = strtrim(regexp(r.assumptions, '(?<=\.)\s+', 'split'));
            parts = parts(~cellfun(@isempty, parts));
            for i = 1:numel(parts)
                if i == 1, q = 'Assumptions'; else, q = ''; end
                rows(end + 1, :) = {q, parts{i}}; %#ok<AGROW>
            end
            app.StatsTable.Data = rows;
            ph = r.comparisons;
            data = cell(numel(ph), 5);
            for i = 1:numel(ph)
                if all(isfinite(ph(i).ci))
                    ciTxt = sprintf('[%.4g, %.4g]', ph(i).ci(1), ph(i).ci(2));
                else
                    ciTxt = char(8212);
                end
                data(i, :) = {ph(i).label, sprintf('%.4g', ph(i).diff), ciTxt, ...
                    sprintf('%.4g  %s', ph(i).p, GroupStats.stars(ph(i).p)), ph(i).method};
            end
            app.PostHocTable.Data = data;
            app.ReportText.Value = app.reportLines();
        end

        %% reportLines - Copy-ready summary, assumptions, settings and pairs
        function lines = reportLines(app)
            r = app.GroupResult;
            if isempty(r), lines = {}; return; end
            s = r.settings;
            if r.checkAgrees, agree = 'consistent with the main test'; else, agree = 'disagrees with the main test'; end
            lines = {r.summary; ''; ['Assumptions: ' r.assumptions]; ''; ...
                sprintf('Robustness check: %s, %s (%s).', r.check.test, GroupStats.formatP(r.check.p), agree); ''; ...
                sprintf('Feature: %s (%s), value per %s; t0 = %g s; baseline %g to %g s; direction %s.', ...
                r.feature, r.unit, lower(r.subjectMode), s.t0, s.baseline(1), s.baseline(2), s.direction)};
            if strcmp(r.design, 'paired')
                lines{end + 1, 1} = '';
                lines{end + 1, 1} = sprintf('Pairs (matched by subject number): %s  %s  %s', ...
                    r.groupNames{1}, char(8596), r.groupNames{2});
                for j = 1:numel(r.labels{1})
                    lines{end + 1, 1} = sprintf('  %d: %s  %s  %s', j, r.labels{1}{j}, char(8596), r.labels{2}{j}); %#ok<AGROW>
                end
            end
        end

        %% plotGroupStats - Subjects, pairs, mean ± SEM or box, significance brackets
        function plotGroupStats(app)
            T = UITheme;
            ax = app.StatsAxes;
            r = app.GroupResult;
            if isempty(r)
                UIKit.emptyAxes(ax, 'Add files to two or more groups (or Try group demo), then Run test');
                app.StatsSummaryLabel.Text = '';
                return;
            end
            cla(ax, 'reset');
            hold(ax, 'on');
            k = numel(r.groupNames);
            isBox = strncmpi(app.PlotStyleMenu.Value, 'Box', 3);
            allv = vertcat(r.values{:});
            lo = min(allv); hi = max(allv);
            span = hi - lo;
            if ~(span > 0), span = max(abs(hi), 1); end
            dark = T.sectionTitleColor;
            offs = cellfun(@(v) jitterOffsets(numel(v)), r.values, 'UniformOutput', false);
            % Paired lines under the points (subject j of A with subject j of B)
            if strcmp(r.design, 'paired')
                a = r.values{1}; b = r.values{2};
                for j = 1:numel(a)
                    plot(ax, [1 2] + offs{1}(j), [a(j) b(j)], '-', 'Color', [0.74 0.76 0.80], 'LineWidth', 0.8);
                end
            end
            for i = 1:k
                v = r.values{i};
                d = r.desc(i);
                c = T.plotColors(mod(i - 1, size(T.plotColors, 1)) + 1, :);
                if isBox && d.n >= 1
                    patch(ax, i + [-0.22 0.22 0.22 -0.22], [d.q1 d.q1 d.q3 d.q3], 0.25 * c + 0.75, ...
                        'EdgeColor', c, 'LineWidth', 1);
                    plot(ax, i + [-0.22 0.22], [d.median d.median], '-', 'Color', 0.7 * c, 'LineWidth', 2);
                    wLo = min(v(v >= d.q1 - 1.5 * d.iqr));
                    wHi = max(v(v <= d.q3 + 1.5 * d.iqr));
                    plot(ax, [i i NaN i i], [d.q3 wHi NaN d.q1 wLo], '-', 'Color', c, 'LineWidth', 1);
                    plot(ax, [i - 0.08, i + 0.08, NaN, i - 0.08, i + 0.08], [wHi wHi NaN wLo wLo], '-', ...
                        'Color', c, 'LineWidth', 1);
                end
                if ~isempty(v)
                    scatter(ax, i + offs{i}, v, 40, c, 'filled', 'MarkerEdgeColor', [1 1 1], 'LineWidth', 0.5);
                end
                if ~isBox && isfinite(d.mean)
                    plot(ax, i + [-0.26 0.26], [d.mean d.mean], '-', 'Color', dark, 'LineWidth', 2);
                    if isfinite(d.sem)
                        errorbar(ax, i, d.mean, d.sem, 'Color', dark, 'LineWidth', 1.5, 'CapSize', 10);
                    end
                end
            end
            % Significance brackets: the tested difference, or significant post-hoc pairs
            comps = r.comparisons;
            if strcmp(r.design, 'anova'), comps = comps([comps.p] < 0.05); end
            base = hi + 0.08 * span;
            gap = 0.11 * span;
            for m = 1:numel(comps)
                ia = find(strcmp(r.groupNames, comps(m).a), 1);
                ib = find(strcmp(r.groupNames, comps(m).b), 1);
                y = base + (m - 1) * gap;
                plot(ax, [ia ia ib ib], y + [-0.025 0 0 -0.025] * span, '-', 'Color', dark, 'LineWidth', 1);
                text(ax, (ia + ib) / 2, y + 0.01 * span, sprintf('%s   %s', GroupStats.stars(comps(m).p), ...
                    GroupStats.formatP(comps(m).p)), 'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'bottom', 'FontSize', T.fontSmall, 'Color', dark, 'Interpreter', 'none');
            end
            hold(ax, 'off');
            top = base + max(numel(comps), 0.2) * gap + 0.03 * span;
            ylim(ax, [lo - 0.08 * span, top]);
            UIKit.styleAxes(ax, sprintf('%s: %s, %s', r.main.test, GroupStats.statText(r.main), ...
                GroupStats.formatP(r.main.p)), '', featureAxisLabel(r.feature, r.unit));
            ax.XTick = 1:k;
            ax.XTickLabel = r.groupNames;
            ax.TickLabelInterpreter = 'none';
            ax.XLim = [0.4, k + 0.6];
            ax.XGrid = 'off';
            app.StatsSummaryLabel.Text = r.summary;
        end

        %% setGroupPlotStyle - 'mean' (mean ± SEM) or 'box' (box plot); redraws
        function setGroupPlotStyle(app, style)
            if strncmpi(style, 'box', 3)
                app.PlotStyleMenu.Value = app.PlotStyles{2};
            else
                app.PlotStyleMenu.Value = app.PlotStyles{1};
            end
            app.plotGroupStats();
        end

        %% exportFigure - Save a plot as a publication figure (no dialogs)
        % format: 'pdf' | 'svg' | 'eps' | 'png300' | 'png600' | 'tif' or a
        % dropdown label (default: the format dropdown). target: 'groups'
        % (statistics plot), 'series' (Single file plot) or 'auto' (the
        % visible mode). The window is unchanged (FigureExport styles a
        % temporary copy). Returns true on success; the written file is in
        % app.LastExportPath.
        function ok = exportFigure(app, filePath, format, target)
            ok = false;
            if nargin < 4 || isempty(target), target = 'auto'; end
            if strcmpi(target, 'auto')
                onGroups = app.ModeTabs.SelectedTab == app.GroupsTab;
                if ~isempty(app.GroupResult) && (onGroups || isempty(app.SeriesT))
                    target = 'groups';
                else
                    target = 'series';
                end
            end
            isGroups = strcmpi(target, 'groups');
            if isGroups, menu = app.FigFormatMenu; else, menu = app.SeriesFigFormatMenu; end
            if nargin < 3 || isempty(format)
                format = menu.Value;
            else
                % Show the format actually written in the dropdown (scripts / CI pass it explicitly)
                keys = cellfun(@FigureExport.formatKey, menu.Items, 'UniformOutput', false);
                i = find(strcmpi(keys, FigureExport.formatKey(format)), 1);
                if ~isempty(i), menu.Value = menu.Items{i}; end
            end
            if isGroups
                if isempty(app.GroupResult)
                    UIKit.alert(app.UIFig, 'Run a test first (Groups & statistics, step 3).', 'Export figure');
                    return;
                end
                src = app.StatsAxes;
            else
                if isempty(app.SeriesT)
                    UIKit.alert(app.UIFig, 'Load a file first (Single file, step 1).', 'Export figure');
                    return;
                end
                src = app.Axes;
            end
            UIKit.setStatus(app.W.Status, 'Exporting figure', 'busy');
            dlg = UIKit.busy(app.UIFig, sprintf('Writing the publication figure%s', char(8230)));
            try
                out = FigureExport.export(src, filePath, FigureExport.formatKey(format));
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, 'Figure export failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Figure export failed: %s', ME.message), 'Export figure');
                return;
            end
            app.LastExportPath = out;
            [~, nm, ext] = fileparts(out);
            UIKit.setStatus(app.W.Status, sprintf(['Figure saved: %s (publication style: 8 pt ' ...
                'Helvetica, white background; the window is unchanged).'], [nm ext]), 'success');
            ok = true;
        end

        %% exportFigureDialog - Ask for a file name, then exportFigure
        function exportFigureDialog(app, target)
            if strcmp(target, 'groups')
                if isempty(app.GroupResult)
                    UIKit.alert(app.UIFig, 'Run a test first (step 3).', 'Export figure'); return;
                end
                fmtLabel = app.FigFormatMenu.Value;
                base = ['group_' matlab.lang.makeValidName(app.GroupResult.feature)];
            else
                fmtLabel = app.SeriesFigFormatMenu.Value;
                base = ['series_' matlab.lang.makeValidName(app.SeriesMenu.Value)];
            end
            [~, ext] = FigureExport.parseFormat(fmtLabel);
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = pwd; end
            [file, path] = uiputfile({['*' ext], fmtLabel}, 'Export figure', fullfile(startDir, [base ext]));
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.exportFigure(fullfile(path, file), FigureExport.formatKey(fmtLabel), target);
        end

        %% exportGroupResults - Values and report (.csv + _report.txt) or result struct (.mat)
        function ok = exportGroupResults(app, filePath)
            ok = false;
            r = app.GroupResult;
            if isempty(r)
                UIKit.alert(app.UIFig, 'Run a test first (step 3).', 'Export'); return;
            end
            [folder, name, ext] = fileparts(filePath);
            try
                if strcmpi(ext, '.mat')
                    result = r; %#ok<NASGU>
                    save(filePath, 'result');
                    written = [name ext];
                else
                    csvPath = fullfile(folder, [name '.csv']);
                    G = {}; S = {}; V = [];
                    for g = 1:numel(r.groupNames)
                        n = numel(r.values{g});
                        G = [G; repmat(r.groupNames(g), n, 1)]; %#ok<AGROW>
                        S = [S; r.labels{g}(:)]; %#ok<AGROW>
                        V = [V; r.values{g}(:)]; %#ok<AGROW>
                    end
                    tbl = table(G, S, V, 'VariableNames', ...
                        {'Group', 'Subject', matlab.lang.makeValidName(r.feature)});
                    writetable(tbl, csvPath);
                    rep = fullfile(folder, [name '_report.txt']);
                    fid = fopen(rep, 'w', 'n', 'UTF-8');
                    if fid < 0
                        error('NeuroAnalyzer:SignalCharacterization:write', 'Cannot write %s', rep);
                    end
                    lines = app.reportLines();
                    fprintf(fid, '%s\n', lines{:});
                    fclose(fid);
                    written = sprintf('%s.csv and %s_report.txt', name, name);
                end
            catch ME
                UIKit.setStatus(app.W.Status, 'Export failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Export failed: %s', ME.message), 'Export');
                return;
            end
            UIKit.setStatus(app.W.Status, sprintf('Exported %s', written), 'success');
            ok = true;
        end

        %% exportGroupResultsDialog - Ask for a file name, then exportGroupResults
        function exportGroupResultsDialog(app)
            if isempty(app.GroupResult)
                UIKit.alert(app.UIFig, 'Run a test first (step 3).', 'Export'); return;
            end
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = pwd; end
            [file, path] = uiputfile({'*.csv', 'Values + report (*.csv, *_report.txt)'; ...
                '*.mat', 'Result struct (*.mat)'}, 'Export values & report', ...
                fullfile(startDir, ['group_' matlab.lang.makeValidName(app.GroupResult.feature) '.csv']));
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.exportGroupResults(fullfile(path, file));
        end

        %% refreshGroups - Files table, group dropdowns and enable states
        function refreshGroups(app)
            names = app.groupNames();
            gf = app.GroupFiles;
            groups = {gf.group};
            data = cell(numel(gf), 5);
            for i = 1:numel(gf)
                if isfinite(gf(i).value), v = sprintf('%.4g', gf(i).value); else, v = ''; end
                data(i, :) = {sum(strcmp(groups(1:i), groups{i})), gf(i).name, gf(i).group, gf(i).nSeries, v};
            end
            app.GroupTable.Data = data;
            items = names;
            if isempty(items), items = {'-'}; end
            oldA = app.GroupAMenu.Value;
            oldB = app.GroupBMenu.Value;
            app.GroupAMenu.Items = items;
            app.GroupBMenu.Items = items;
            if ismember(oldA, items), app.GroupAMenu.Value = oldA; else, app.GroupAMenu.Value = items{1}; end
            if ismember(oldB, items) && ~strcmp(oldB, app.GroupAMenu.Value)
                app.GroupBMenu.Value = oldB;
            else
                others = items(~strcmp(items, app.GroupAMenu.Value));
                if isempty(others), app.GroupBMenu.Value = items{1}; else, app.GroupBMenu.Value = others{1}; end
            end
            % Group field: the usual names plus every existing group
            val = app.GroupNameMenu.Value;
            known = {'Control', 'Stimulated'};
            app.GroupNameMenu.Items = [known, names(~ismember(names, known))];
            app.GroupNameMenu.Value = val;
            app.updateControls();
        end

        %% groupNames - Groups that have files, in the order they were created
        function names = groupNames(app)
            groups = {app.GroupFiles.group};
            names = app.GroupOrder(ismember(app.GroupOrder, groups));
            for i = 1:numel(groups)
                if ~any(strcmp(names, groups{i}))
                    names{end + 1} = groups{i}; %#ok<AGROW>
                end
            end
        end

        %% groupUnit - 'PU' when every file is LDF, else 'signal units'
        function u = groupUnit(app)
            if ~isempty(app.GroupFiles) && all(strncmp({app.GroupFiles.dataType}, 'LDF', 3))
                u = 'PU';
            else
                u = 'signal units';
            end
        end

        function k = designKey(app)
            k = app.DesignKeys{find(strcmp(app.Designs, app.DesignMenu.Value), 1)};
        end

        function k = methodKey(app)
            k = app.MethodKeys{find(strcmp(app.Methods, app.MethodMenu.Value), 1)};
        end

        function k = subjectModeKey(app)
            k = app.SubjectKeys{find(strcmp(app.SubjectModes, app.SubjectMenu.Value), 1)};
        end

        %% designHintText - One line on how the chosen design compares subjects
        function s = designHintText(app)
            switch app.designKey()
                case 'paired'
                    s = 'Pairs by subject number: #1 of A with #1 of B, and so on (see the Files tab).';
                case 'unpaired'
                    s = 'Independent animals; group sizes may differ. Welch test: unequal SDs allowed.';
                otherwise
                    s = 'All groups at once (independent animals), then every pair (Tukey-Kramer).';
            end
        end

        %% markGroupStale - Files or settings changed after a test
        function markGroupStale(app)
            if ~isempty(app.GroupResult) && ~app.GroupStale
                app.GroupStale = true;
                UIKit.setStatus(app.W.Status, 'Files or settings changed: click Run test again (step 3).', 'info');
            end
        end

        function onGroupSettingsChanged(app)
            app.markGroupStale();
            app.updateControls();
        end

        function onGroupT0Changed(app)
            app.applyGroupBaselineDefault();
            app.markGroupStale();
            app.updateControls();
        end

        function onGroupBaselineEdited(app)
            app.GroupBaselineAuto = false;
            app.markGroupStale();
            app.updateControls();
        end

        %% applyGroupBaselineDefault - Pre-stimulus baseline while the user has not edited it
        function applyGroupBaselineDefault(app)
            if ~app.GroupBaselineAuto || isempty(app.GroupFiles), return; end
            t0 = app.GroupT0Edit.Value;
            tFirst = Inf;
            for i = 1:numel(app.GroupFiles)
                t = app.GroupFiles(i).T{1};
                if ~isempty(t), tFirst = min(tFirst, t(1)); end
            end
            if tFirst < t0
                app.GroupBaseStartEdit.Value = tFirst;
                app.GroupBaseEndEdit.Value = t0;
            end
        end

        function onGroupTableSelect(app, evt)
            if isempty(evt.Indices), return; end
            app.GroupSelectedRow = evt.Indices(1, 1);
            app.updateControls();
        end

        %% onGroupTableEdit - Group cell edited: move the file to that group
        function onGroupTableEdit(app, evt)
            r = evt.Indices(1);
            if evt.Indices(2) ~= 3 || r > numel(app.GroupFiles)
                app.refreshGroups();
                return;
            end
            newName = strtrim(char(evt.NewData));
            if isempty(newName)
                app.refreshGroups();
                UIKit.setStatus(app.W.Status, 'A group name cannot be empty.', 'warning');
                return;
            end
            old = app.GroupFiles(r).group;
            app.GroupFiles(r).group = newName;
            if ~any(strcmp(app.GroupOrder, newName)), app.GroupOrder{end + 1} = newName; end
            app.markGroupStale();
            app.refreshGroups();
            UIKit.setStatus(app.W.Status, sprintf('%s moved from %s to %s.', app.GroupFiles(r).name, ...
                old, newName), 'info');
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% detectDataType - Data type menu item matching the variables in s ('' if none)
function dt = detectDataType(s)
    types = {'LDF segments (segmentedLDF, segmentedTime)', ...
        'ERP / average response (t, y or lfp_data)', 'Time series (t, y)'};
    if isfield(s, 'segmentedLDF') && isfield(s, 'segmentedTime')
        dt = types{1};
    elseif (isfield(s, 'lfp_data') && (isfield(s, 't') || isfield(s, 't_lfp'))) || ...
            (isfield(s, 'erp_avg') && isfield(s, 't') && isfield(s, 'y'))
        % LFP from Extract Ephys, or the ERP export of LFP analysis (t, y = channel mean)
        dt = types{2};
    elseif isfield(s, 't') && (isfield(s, 'y') || isfield(s, 'LDF'))
        dt = types{3};
    else
        dt = '';
    end
end

%% seriesBaseline - Reference level: mean in the baseline window, else fallbacks
% bl = [start end] or [] (first 0.05 s of the trace). Empty/NaN window:
% pre-onset mean, else y(1).
function baseVal = seriesBaseline(t, y, bl, t0)
    if isempty(bl)
        baseVal = mean(y(t >= t(1) & t < min(t(1)+0.05, t(end))));
    else
        idx = t >= bl(1) & t <= bl(2);
        baseVal = mean(y(idx));
    end
    if ~isfinite(baseVal)
        pre = y(t < t0);
        baseVal = mean(pre(isfinite(pre)));
        if ~isfinite(baseVal), baseVal = y(1); end
    end
end

%% seriesDirection - 'max' or 'min' from the menu value ('Auto' = larger deflection)
function dirn = seriesDirection(t, y, baseVal, t0, choice)
    switch choice
        case 'Positive', dirn = 'max';
        case 'Negative', dirn = 'min';
        otherwise
            post = y(t >= t0);
            if ~isempty(post) && (baseVal - min(post)) > (max(post) - baseVal)
                dirn = 'min';
            else
                dirn = 'max';
            end
    end
end

%% fwhmSpan - Start/end time of the half-maximum lobe around the peak (for plotting)
% Mirrors SignalFeatures.fwhm: contiguous samples after t0 past the half level.
function [tA, tB, half] = fwhmSpan(t, y, t0, dirn, baseVal)
    tA = []; tB = []; half = NaN;
    idx = t >= t0;
    t_ = t(idx); y_ = y(idx);
    if isempty(t_), return; end
    if strcmpi(dirn, 'min'), [pk, iPk] = min(y_); else, [pk, iPk] = max(y_); end
    if pk == baseVal, return; end
    half = baseVal + 0.5 * (pk - baseVal);
    if strcmpi(dirn, 'min'), past = y_ <= half; else, past = y_ >= half; end
    i1 = iPk; while i1 > 1 && past(i1 - 1), i1 = i1 - 1; end
    i2 = iPk; while i2 < numel(y_) && past(i2 + 1), i2 = i2 + 1; end
    tA = t_(i1); tB = t_(i2);
end

%% styleBtn - Switch a UIKit button between primary and secondary look
function styleBtn(b, isPrimary)
    T = UITheme;
    if isPrimary
        b.BackgroundColor = T.accent; b.FontColor = [1 1 1]; b.FontWeight = 'bold';
    else
        b.BackgroundColor = T.secondaryBg; b.FontColor = T.secondaryFg; b.FontWeight = 'normal';
    end
end

%% parseSeriesStruct - Time vectors and signals (row vectors) for data type dt
% LDF segments: one series per trial; ERP / average: the mean over LFP
% channels (or t, y); time series: t + y, or t + LDF. Empty if absent.
function [tCell, yCell] = parseSeriesStruct(s, dt)
    tCell = {};
    yCell = {};
    if contains(dt, 'LDF segments')
        if ~isfield(s, 'segmentedLDF') || ~isfield(s, 'segmentedTime')
            return;
        end
        seg = s.segmentedLDF;
        t = s.segmentedTime(1,:);
        for i = 1:size(seg, 1)
            tCell{end+1} = t; %#ok<AGROW>
            yCell{end+1} = seg(i,:); %#ok<AGROW>
        end
    elseif contains(dt, 'ERP') || contains(dt, 'average')
        % ExtractEphysApp saves the LFP time vector as 't_lfp'
        if isfield(s, 't'), tv = s.t; elseif isfield(s, 't_lfp'), tv = s.t_lfp; else, tv = []; end
        if ~isempty(tv) && isfield(s, 'lfp_data')
            y = mean(s.lfp_data, 1);
            tCell = {tv(:)'};
            yCell = {y(:)'};
        elseif isfield(s, 't') && isfield(s, 'y')
            tCell = {s.t(:)'};
            yCell = {s.y(:)'};
        else
            return;
        end
    else
        if isfield(s, 't') && isfield(s, 'y')
            tCell = {s.t(:)'};
            yCell = {s.y(:)'};
        elseif isfield(s, 't') && isfield(s, 'LDF')
            tCell = {s.t(:)'};
            yCell = {s.LDF(:)'};
        else
            return;
        end
    end
end

%% computeFeature - One feature of one series (the SignalFeatures call behind each column)
function v = computeFeature(name, t, y, t0, baseVal, dirn)
    switch name
        case 'Peak latency'
            v = SignalFeatures.peakLatency(t, y, t0, dirn);
        case 'Onset delay (50%)'
            v = SignalFeatures.onsetDelay(t, y, t0, 0.5, dirn, baseVal);
        case 'FWHM'
            v = SignalFeatures.fwhm(t, y, t0, dirn, baseVal);
        case 'AUC positive'
            v = SignalFeatures.aucPositive(t, y, baseVal);
        case 'AUC negative'
            v = SignalFeatures.aucNegative(t, y, baseVal);
        case 'Rise time'
            v = SignalFeatures.riseTime(t, y, t0, dirn, baseVal);
        case 'Decay time'
            v = SignalFeatures.decayTime(t, y, t0, dirn, baseVal);
        case 'Peak amplitude'
            v = SignalFeatures.peakAmplitude(t, y, t0, dirn, baseVal);
        case 'Stim–response integral'
            stim = zeros(size(y)); stim(t >= t0) = 1;
            v = SignalFeatures.stimResponseIntegration(t, stim, y, t0);
        otherwise
            v = NaN;
    end
end

%% seriesFeature - Feature of one series with baseline / direction resolved as in the table
function v = seriesFeature(name, t, y, t0, bl, dirChoice)
    t = t(:); y = y(:);
    if isempty(t) || numel(t) ~= numel(y), v = NaN; return; end
    baseVal = seriesBaseline(t, y, bl, t0);
    dirn = seriesDirection(t, y, baseVal, t0, dirChoice);
    v = computeFeature(name, t, y, t0, baseVal, dirn);
end

%% meanTrace - Average of series that share one time base (same = false otherwise)
function [t, y, same] = meanTrace(T, Y)
    t = T{1}(:)';
    y = [];
    same = ~isempty(t);
    tol = 1e-9 * max(1, max(abs(t)));
    for i = 1:numel(T)
        if numel(T{i}) ~= numel(t) || numel(Y{i}) ~= numel(t) || any(abs(T{i}(:)' - t) > tol)
            same = false;
            return;
        end
    end
    rows = cellfun(@(v) v(:)', Y(:), 'UniformOutput', false);
    y = mean(vertcat(rows{:}), 1, 'omitnan');
end

%% jitterOffsets - Deterministic horizontal spread of n points (column)
function o = jitterOffsets(n)
    if n <= 1
        o = zeros(n, 1);
    else
        o = ((1:n)' - (n + 1) / 2) / (n - 1) * 0.24;
    end
end

%% featureAxisLabel - y label with the feature's unit
function s = featureAxisLabel(name, unit)
    switch name
        case {'Peak latency', 'Onset delay (50%)', 'FWHM', 'Rise time', 'Decay time'}
            s = [name ' (s)'];
        case {'AUC positive', 'AUC negative', 'Stim–response integral'}
            s = sprintf('%s (%s × s)', name, unit);
        otherwise
            s = sprintf('%s (%s)', name, unit);
    end
end

%% pickItem - Menu item for a key or item text (case-insensitive); error if unknown
function item = pickItem(value, items, keys, what)
    value = char(value);
    i = find(strcmpi(keys, value) | strcmpi(items, value), 1);
    if isempty(i)
        error('NeuroAnalyzer:SignalCharacterization:option', 'Unknown %s ''%s'' (use: %s).', ...
            what, value, strjoin(keys, ', '));
    end
    item = items{i};
end

%% ensureDemoPath - Put core/demo (demo generators) on the path if needed
function ensureDemoPath()
    if exist('demoGroups', 'file') ~= 2
        addpath(fullfile(fileparts(which('DemoData')), 'demo'));
    end
end
