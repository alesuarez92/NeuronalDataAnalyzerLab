%% EEGAnalysisApp.m
% =========================================================================
% EEG ANALYSIS - ERPs PER CONDITION, AMPLITUDE MEASURES AND STATISTICS
% =========================================================================
% Opened from the launcher (EEG card). For EEG that was already cleaned in
% EEGLAB, FieldTrip, BrainVision Analyzer or MATLAB, or recorded with
% BrainVision Recorder: one file per participant (EEGLAB .set, FieldTrip
% .mat, BrainVision .vhdr or a plain .mat array), scalp or rodent.
%
% Layout (UIKit.window): numbered step cards on the left
%   1 Load EEG      (one or several files; a plain .mat file gets a short
%                    form saying what its variables are; a continuous
%                    recording is cut into trials around its events)
%   2 ERPs          (baseline, channels to look at)
%   3 Measure       (mean or peak amplitude in a time window, per
%                    participant and condition; warns about edge peaks)
%   4 Statistics    (conditions compared within participants: paired
%                    t-test / Wilcoxon for two, repeated-measures ANOVA /
%                    Friedman for more; core/GroupStats.m)
%   5 Save          (measures as .csv, everything as .mat; sessions)
% and on the right the ERP plot (conditions, all channels, or a
% difference wave; one participant or the grand average) above the tabs
% Overview (what each file holds and what was already done to it) |
% Measures | Statistics. The computations are in core/EEGAnalysis.m.
%
% Scriptable (CI walkthroughs, no dialogs): openFiles(paths, maps),
% loadDemo(), setTrialWindow([from to] s), cutIntoTrials(),
% setBaseline(on, [from to] s), setChannels(names), showERPs(),
% setView(participant, view, condA, condB), setMeasure(kind, polarity,
% [from to] s, channels), measure(), setStatsMethod(m),
% compareConditions(), exportResultsTo(path). Sessions:
% saveSessionTo(path, notes), openSession(path), makeReport(pdfPath),
% sessionState(), restoreSession(s).
% =========================================================================

classdef EEGAnalysisApp < handle

    properties
        UIFig
        W                   % UIKit.window struct (Fig, Body, Status, HelpBtn)
        StatusLabel
        % Step 1
        LoadBtn
        DemoBtn
        FileInfo
        TrialFromEdit       % ms
        TrialToEdit         % ms
        CutBtn
        CutInfo
        % Step 2
        BaselineCb
        BaselineFromEdit    % ms
        BaselineToEdit      % ms
        ChannelsEdit        % text: 'Pz' or 'Cz, FCz'
        ShowBtn
        ErpInfo
        % Step 3
        MeasureDrop
        PolarityDrop
        WindowFromEdit      % ms
        WindowToEdit        % ms
        MeasureChannelsEdit
        MeasureBtn
        MeasureInfo
        % Step 4
        MethodDrop
        StatsBtn
        StatsInfo
        % Step 5
        ExportBtn
        SessionBtns
        % Right side
        ParticipantDrop
        ViewDrop
        CondADrop
        CondBDrop
        AxERP
        Tabs
        OverviewText
        MeasuresTable
        StatsText
        StatsTable
        % Data
        Files = {}          % loaded file paths
        Maps = {}           % plain .mat: the map used for each file ([] otherwise)
        Names = {}          % participant names (file names)
        Loaded = {}         % EEG structs as read (core/io/EEGSource.m)
        EEGs = {}           % the same cut into trials (what is analysed)
        Generator = ''      % 'demoEEG' when the demo was loaded
        TrialWindow = []    % [from to] s used to cut continuous recordings
        ERPs = {}           % conditionERPs per participant (all channels)
        Grand = []          % grandAverage of ERPs (several participants)
        ERPSettings = []    % baseline and channels of the ERPs shown
        Measures = {}       % 1 x P measure() results
        MeasureSettings = []
        StatsResult = []    % GroupStats.compare result
    end

    properties(Constant)
        GrandLabel = 'All participants (grand average)'
        Views = {'Conditions', 'All channels (butterfly)', 'Difference wave'}
        MeasureKinds = {'Mean amplitude', 'Peak amplitude'}
    end

    methods
        %% Constructor
        function app = EEGAnalysisApp()
            EEGAnalysisApp.ensurePath();
            app.buildUI();
            app.updateControls();
        end

        %% buildUI - Step cards (left), ERP plot and result tabs (right)
        function buildUI(app)
            T = UITheme;
            app.W = UIKit.window('EEG Analysis', ...
                'ERPs per condition, amplitude measures and statistics for cleaned EEG (scalp or rodent)', ...
                'EEG Analysis', [1320 900]);
            app.UIFig = app.W.Fig;
            app.StatusLabel = app.W.Status;
            app.W.Body.RowHeight = {'1x'};
            app.W.Body.ColumnWidth = {360, '1x'};

            left = uigridlayout(app.W.Body, [6 1], 'Padding', [0 0 0 0], 'RowSpacing', 10, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            heights = cell(1, 6);
            ch = T.controlHeight; bh = T.buttonHeight;

            % --- 1 Load EEG ---
            [p, g, heights{1}] = stepCard(left, 1, 'Load EEG', {bh, 48, ch, ch, bh, 34});
            p.Layout.Row = 1;
            app.LoadBtn = UIKit.button(g, ['Load EEG files' char(8230)], @(~,~)app.loadDialog(), 'primary', ...
                ['One file per participant: EEGLAB .set, FieldTrip .mat, BrainVision .vhdr (Brain Products Recorder or ' ...
                 'Analyzer; keep its .vmrk and .eeg files next to it) or a plain .mat with the numbers (you will be ' ...
                 'asked what its variables are). Select several files at once for a group.']);
            app.LoadBtn.Layout.Row = 2; app.LoadBtn.Layout.Column = 1;
            app.DemoBtn = UIKit.button(g, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['An oddball study: 8 participants, 32 channels, Standard / Target / Novel trials with a P300 at Pz ' ...
                 '(Target 10 > Novel 6 > Standard 2 uV); see Help for every answer']);
            app.DemoBtn.Layout.Row = 2; app.DemoBtn.Layout.Column = 2;
            app.FileInfo = infoLabel(g, 'Nothing loaded', 'Participants, channels and trials');
            app.FileInfo.Layout.Row = 3; app.FileInfo.Layout.Column = [1 2];
            app.TrialFromEdit = addField(g, 4, 'Trial from (ms)', 'numeric', -200, ...
                ['Only for continuous recordings: where each trial starts, relative to its event (negative = before ' ...
                 'the event, so there is a baseline)'], [-60000 60000]);
            app.TrialToEdit = addField(g, 5, 'Trial to (ms)', 'numeric', 800, ...
                'Only for continuous recordings: where each trial ends, relative to its event', [-60000 60000]);
            app.CutBtn = UIKit.button(g, 'Cut into trials', @(~,~)app.cutIntoTrials(), 'secondary', ...
                ['Cut every continuous recording into trials around its events. The condition of a trial is the name ' ...
                 'of its event. Events too close to the start or end are left out (the Overview says how many).']);
            app.CutBtn.Layout.Row = 6; app.CutBtn.Layout.Column = [1 2];
            app.CutInfo = infoLabel(g, '', 'What cutting into trials did');
            app.CutInfo.Layout.Row = 7; app.CutInfo.Layout.Column = [1 2];

            % --- 2 ERPs ---
            [p, g, heights{2}] = stepCard(left, 2, 'ERPs', {ch, ch, ch, ch, bh, 34});
            p.Layout.Row = 2;
            app.BaselineCb = addField(g, 2, 'Subtract a baseline', 'checkbox', true, ...
                ['Subtract, in every trial and channel, the mean of the baseline window, so the ERP starts at 0 uV. ' ...
                 'Untick when the data were already baseline-corrected and you want them unchanged.']);
            app.BaselineCb.ValueChangedFcn = @(~,~)app.updateControls();
            app.BaselineFromEdit = addField(g, 3, 'Baseline from (ms)', 'numeric', -200, ...
                'Start of the baseline window (usually the start of the trial)', [-60000 60000]);
            app.BaselineToEdit = addField(g, 4, 'Baseline to (ms)', 'numeric', 0, ...
                'End of the baseline window (usually the event, 0 ms)', [-60000 60000]);
            app.ChannelsEdit = addField(g, 5, 'Channels to plot', 'text', '', ...
                ['Channel names separated by commas, e.g. Pz or Cz, FCz (any case). Several channels are averaged. ' ...
                 'Empty = the average of all channels.']);
            app.ShowBtn = UIKit.button(g, 'Show ERPs', @(~,~)app.showERPs(), 'secondary', ...
                ['Average the trials of each condition for every participant (and across participants) and plot them. ' ...
                 'Use the bar above the plot to switch participant, view and conditions.']);
            app.ShowBtn.Layout.Row = 6; app.ShowBtn.Layout.Column = [1 2];
            app.ErpInfo = infoLabel(g, '', 'What the ERPs are made of');
            app.ErpInfo.Layout.Row = 7; app.ErpInfo.Layout.Column = [1 2];

            % --- 3 Measure ---
            [p, g, heights{3}] = stepCard(left, 3, 'Measure', {ch, ch, ch, ch, ch, bh, 48});
            p.Layout.Row = 3;
            app.MeasureDrop = addField(g, 2, 'Measure', 'dropdown', {app.MeasureKinds, app.MeasureKinds{1}}, ...
                ['Mean amplitude: the average voltage in the window (robust to noise; recommended for most components). ' ...
                 'Peak amplitude: the largest value in the window, with its latency (sensitive to noise).']);
            app.MeasureDrop.ValueChangedFcn = @(~,~)app.updateControls();
            app.PolarityDrop = addField(g, 3, 'Peak direction', 'dropdown', {{'Positive', 'Negative'}, 'Positive'}, ...
                'Positive for components such as P1 or P300, negative for N1 or N400 (peak amplitude only)');
            app.WindowFromEdit = addField(g, 4, 'Window from (ms)', 'numeric', 300, ...
                'Start of the time window to measure in (choose it from the grand average or the literature, not per condition)', ...
                [-60000 60000]);
            app.WindowToEdit = addField(g, 5, 'Window to (ms)', 'numeric', 400, 'End of the time window to measure in', ...
                [-60000 60000]);
            app.MeasureChannelsEdit = addField(g, 6, 'Channels', 'text', '', ...
                'Channels to measure at, separated by commas (averaged). Empty = the channels of step 2.');
            app.MeasureBtn = UIKit.button(g, 'Measure', @(~,~)app.measure(), 'secondary', ...
                'One number per participant and condition, in the Measures tab; the window is shaded on the plot');
            app.MeasureBtn.Layout.Row = 7; app.MeasureBtn.Layout.Column = [1 2];
            app.MeasureInfo = infoLabel(g, '', 'Result of the measure and its checks');
            app.MeasureInfo.Layout.Row = 8; app.MeasureInfo.Layout.Column = [1 2];

            % --- 4 Statistics ---
            [p, g, heights{4}] = stepCard(left, 4, 'Statistics', {ch, bh, 48});
            p.Layout.Row = 4;
            app.MethodDrop = addField(g, 2, 'Method', 'dropdown', {{'Parametric', 'Nonparametric'}, 'Parametric'}, ...
                ['Parametric: paired t-test (2 conditions) or repeated-measures ANOVA (3 or more). Nonparametric: ' ...
                 'Wilcoxon signed-rank or Friedman test (fewer assumptions, less power). The other is run as a check.']);
            app.StatsBtn = UIKit.button(g, 'Compare conditions', @(~,~)app.compareConditions(), 'secondary', ...
                ['Compare the measured values between conditions, within participants (each participant is matched ' ...
                 'with themself across conditions). Needs 2 or more participants.']);
            app.StatsBtn.Layout.Row = 3; app.StatsBtn.Layout.Column = [1 2];
            app.StatsInfo = infoLabel(g, '', 'Result of the test');
            app.StatsInfo.Layout.Row = 4; app.StatsInfo.Layout.Column = [1 2];

            % --- 5 Save ---
            [p, g, heights{5}] = stepCard(left, 5, 'Save', {bh, UIKit.sessionButtonsHeight()});
            p.Layout.Row = 5;
            app.ExportBtn = UIKit.button(g, ['Export results' char(8230)], @(~,~)app.exportDialog(), 'secondary', ...
                ['.csv: one row per participant and condition (value in uV, latency in s, trials, edge warning), ' ...
                 'ready for a spreadsheet or statistics program; .mat: everything (ERPs, measures, statistics)']);
            app.ExportBtn.Layout.Row = 2; app.ExportBtn.Layout.Column = [1 2];
            app.SessionBtns = UIKit.sessionButtons(g, app);
            app.SessionBtns.Grid.Layout.Row = 3; app.SessionBtns.Grid.Layout.Column = [1 2];
            heights{6} = '1x';
            left.RowHeight = heights;

            % --- Right: plot bar, ERP plot and tabs ---
            right = uigridlayout(app.W.Body, [3 1], 'RowHeight', {ch, '3x', '2x'}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 6, 'BackgroundColor', T.bgGray);
            right.Layout.Row = 1; right.Layout.Column = 2;
            bar = uigridlayout(right, [1 8], 'ColumnWidth', {'fit', 230, 'fit', 180, 'fit', 120, 'fit', 120}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 8, 'BackgroundColor', T.bgGray);
            barLabel(bar, 'Participant');
            app.ParticipantDrop = uidropdown(bar, 'Items', {'(none)'}, 'Value', '(none)', ...
                'ValueChangedFcn', @(~,~)app.plotERP(), 'Tooltip', ...
                'One participant, or the grand average (every participant counts once)');
            barLabel(bar, 'Show');
            app.ViewDrop = uidropdown(bar, 'Items', app.Views, 'Value', app.Views{1}, ...
                'ValueChangedFcn', @(~,~)app.onView(), 'Tooltip', ...
                ['Conditions: one line per condition at the chosen channels (shade = SEM). All channels: every ' ...
                 'channel of one condition (chosen channels in colour). Difference wave: condition A minus B.']);
            barLabel(bar, 'Condition');
            app.CondADrop = uidropdown(bar, 'Items', {'(none)'}, 'Value', '(none)', ...
                'ValueChangedFcn', @(~,~)app.plotERP(), 'Tooltip', 'Condition shown (All channels) or A (Difference wave)');
            barLabel(bar, 'minus');
            app.CondBDrop = uidropdown(bar, 'Items', {'(none)'}, 'Value', '(none)', ...
                'ValueChangedFcn', @(~,~)app.plotERP(), 'Tooltip', 'Condition B, subtracted from A (Difference wave)');
            plotPanel = uipanel(right, 'BackgroundColor', T.cardBg, 'BorderType', 'line', 'HighlightColor', T.cardBorder);
            gp = uigridlayout(plotPanel, [1 1], 'Padding', [4 4 4 4], 'BackgroundColor', T.cardBg);
            app.AxERP = uiaxes(gp);
            app.AxERP.Toolbar.Visible = 'on';
            UIKit.emptyAxes(app.AxERP, 'Load EEG files (or Try demo data) to begin');

            app.Tabs = uitabgroup(right);
            to = uitab(app.Tabs, 'Title', 'Overview', 'BackgroundColor', T.cardBg);
            g1 = uigridlayout(to, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.OverviewText = uitextarea(g1, 'Value', {'Load EEG files to see what they hold and what was done to them.'}, ...
                'Editable', 'off', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            tm = uitab(app.Tabs, 'Title', 'Measures', 'BackgroundColor', T.cardBg);
            g2 = uigridlayout(tm, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.MeasuresTable = uitable(g2, 'RowName', {}, 'FontSize', T.fontSmall + 1, 'ColumnName', ...
                {'Participant', 'Condition', 'Value (uV)', 'Latency (ms)', 'Trials', 'Check'});
            ts = uitab(app.Tabs, 'Title', 'Statistics', 'BackgroundColor', T.cardBg);
            g3 = uigridlayout(ts, [2 1], 'RowHeight', {'1x', '1x'}, 'Padding', [6 6 6 6], 'RowSpacing', 6, ...
                'BackgroundColor', T.cardBg);
            app.StatsText = uitextarea(g3, 'Value', {'Measure (step 3), then Compare conditions (step 4).'}, ...
                'Editable', 'off', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            app.StatsTable = uitable(g3, 'RowName', {}, 'FontSize', T.fontSmall + 1, 'ColumnName', ...
                {'Comparison', 'Difference (uV)', '95% CI', 'p (Holm)', 'Test'});

            UIKit.setStatus(app.StatusLabel, ['Step 1: load one EEG file per participant (or Try demo data).'], 'info');
        end

        %% ----------------------------------------------------------------
        %% Step 1: load
        %% loadDialog - Choose one or more EEG files
        function loadDialog(app)
            start = ProjectManager.getImportDir();
            if isempty(start), start = pwd; end
            [f, p] = uigetfile({'*.set;*.mat;*.vhdr', 'EEG (EEGLAB .set, FieldTrip or plain .mat, BrainVision .vhdr)'}, ...
                'Load EEG (select one file per participant)', start, 'MultiSelect', 'on');
            figure(app.UIFig);
            if isequal(f, 0), return; end
            app.openFiles(fullfile(p, cellstr(f)), {}, true);
        end

        %% openFiles - Read files (no dialog unless interactive); one per participant
        % maps: optional cell (one per file) of readEEGMatrix maps for plain
        % .mat files ([] = detect / guess). interactive: ask with a form when
        % a plain .mat file is unclear. Returns true on success.
        function ok = openFiles(app, paths, maps, interactive)
            if nargin < 3, maps = {}; end
            if nargin < 4, interactive = false; end
            ok = false;
            paths = cellstr(paths);
            if isempty(maps), maps = cell(1, numel(paths)); end
            dlg = UIKit.busy(app.UIFig, 'Reading the EEG files…');
            eegs = cell(1, numel(paths));
            used = cell(1, numel(paths));
            for k = 1:numel(paths)
                try
                    [eegs{k}, used{k}] = app.readOne(paths{k}, maps{k}, interactive, dlg);
                catch ME
                    UIKit.done(dlg);
                    [~, n, e] = fileparts(paths{k});
                    UIKit.setStatus(app.StatusLabel, sprintf('Could not load %s%s: %s', n, e, ME.message), 'error');
                    if interactive
                        UIKit.alert(app.UIFig, sprintf('Could not load %s%s:\n%s', n, e, ME.message), 'Load EEG', 'error');
                    end
                    return;
                end
                if isempty(eegs{k})
                    UIKit.done(dlg);
                    UIKit.setStatus(app.StatusLabel, 'Loading cancelled.', 'info');
                    return;
                end
            end
            UIKit.done(dlg);
            names = cell(1, numel(paths));
            for k = 1:numel(paths)
                [~, names{k}] = fileparts(paths{k});
            end
            app.Files = paths;
            app.Maps = used;
            app.Generator = '';
            ok = app.setData(eegs, names);
        end

        %% loadDemo - The demo oddball study (core/demo/demoEEG): 8 EEGLAB files
        function ok = loadDemo(app)
            DemoData.ensureDemoPath();
            dlg = UIKit.busy(app.UIFig, 'Making the demo EEG (the first time takes a few seconds)…');
            try
                f = demoEEG();
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Demo not made: %s', ME.message), 'error');
                ok = false;
                return;
            end
            UIKit.done(dlg);
            ok = app.openFiles({f.scalp.eeglab});
            if ~ok, return; end
            app.Generator = 'demoEEG';
            app.setChannels({'Pz'});
            app.setMeasure('mean', 'positive', [0.3 0.4], {'Pz'});
            UIKit.setStatus(app.StatusLabel, ['Demo loaded: 8 participants, already cut into trials. Next: Show ERPs ' ...
                '(step 2), then Measure the P300 at Pz from 300 to 400 ms (step 3).'], 'success');
        end

        %% setTrialWindow - [from to] in s around each event (continuous recordings)
        function setTrialWindow(app, w)
            app.TrialFromEdit.Value = w(1) * 1000;
            app.TrialToEdit.Value = w(2) * 1000;
        end

        %% cutIntoTrials - Cut every continuous recording around its events
        function ok = cutIntoTrials(app)
            ok = false;
            if isempty(app.Loaded), return; end
            w = [app.TrialFromEdit.Value app.TrialToEdit.Value] / 1000;
            eegs = app.Loaded;
            try
                for k = 1:numel(eegs)
                    if ~eegs{k}.isEpoched
                        eegs{k} = EEGAnalysis.epoch(eegs{k}, 'Window', w);
                    end
                end
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Not cut into trials (%s): %s', app.Names{k}, ME.message), 'error');
                return;
            end
            app.EEGs = eegs;
            app.TrialWindow = w;
            app.clearResults();
            if w(1) < 0, app.BaselineFromEdit.Value = w(1) * 1000; end
            n = cellfun(@(e) size(e.data, 3), eegs);
            app.CutInfo.Text = sprintf('Cut from %g to %g ms: %s trials.', w(1) * 1000, w(2) * 1000, ...
                strjoin(arrayfun(@num2str, n, 'UniformOutput', false), ', '));
            app.CutInfo.FontColor = UITheme.success;
            app.fillOverview();
            app.fillConditionDrops();
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, 'Cut into trials. Next: Show ERPs (step 2).', 'success');
            ok = true;
        end

        %% ----------------------------------------------------------------
        %% Step 2: ERPs
        %% setBaseline - Baseline on / off and [from to] in s
        function setBaseline(app, on, w)
            app.BaselineCb.Value = logical(on);
            if nargin >= 3 && ~isempty(w)
                app.BaselineFromEdit.Value = w(1) * 1000;
                app.BaselineToEdit.Value = w(2) * 1000;
            end
            app.updateControls();
        end

        %% setChannels - Channels to plot (cell of names or 'Cz, FCz'; {} = all)
        function setChannels(app, names)
            app.ChannelsEdit.Value = channelText(names);
        end

        %% showERPs - Condition averages of every participant (and the grand average)
        function ok = showERPs(app)
            ok = false;
            if ~app.isReady(), return; end
            base = [];
            if app.BaselineCb.Value
                base = [app.BaselineFromEdit.Value app.BaselineToEdit.Value] / 1000;
            end
            try
                chans = channelList(app.ChannelsEdit.Value);
                if ~isempty(chans), EEGAnalysis.channelIndex(app.EEGs{1}.labels, chans); end
                erps = cellfun(@(e) EEGAnalysis.conditionERPs(e, 'Baseline', base), app.EEGs, 'UniformOutput', false);
                grand = [];
                if numel(erps) > 1, grand = EEGAnalysis.grandAverage(erps); end
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('ERPs not made: %s', ME.message), 'error');
                return;
            end
            app.ERPs = erps;
            app.Grand = grand;
            app.ERPSettings = struct('baseline', base, 'channels', {chans});
            app.Measures = {};
            app.StatsResult = [];
            app.fillMeasures();
            app.fillStats();
            app.fillConditionDrops();
            if isempty(base), bt = 'no baseline subtracted'; else, bt = sprintf('baseline %g to %g ms', base * 1000); end
            e = app.analysisERP(1);
            if numel(erps) > 1
                app.ErpInfo.Text = sprintf('%d participants, %s; %s.', numel(erps), ...
                    EEGSource.listText(arrayfun(@(c) sprintf('%s (%d trials)', e.conditions{c}, e.trials(c)), ...
                    1:numel(e.conditions), 'UniformOutput', false)), bt);
            else
                app.ErpInfo.Text = sprintf('%s; %s.', EEGSource.listText(arrayfun(@(c) sprintf('%s (%d trials)', ...
                    e.conditions{c}, e.n(c)), 1:numel(e.conditions), 'UniformOutput', false)), bt);
            end
            app.ErpInfo.FontColor = UITheme.sectionTitleColor;
            if ~isempty(grand) && ~isempty(grand.notes)
                app.ErpInfo.Text = [app.ErpInfo.Text ' ' grand.notes{1}];
                app.ErpInfo.FontColor = UITheme.warning;
            end
            if isempty(app.MeasureChannelsEdit.Value), app.MeasureChannelsEdit.Value = channelText(chans); end
            app.plotERP();
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, ['ERPs ready. Look at the grand average to choose the time window, ' ...
                'then Measure (step 3).'], 'success');
            ok = true;
        end

        %% setView - participant: name, index or 'grand'; view: text of the Show list
        function setView(app, participant, viewName, a, b)
            if nargin >= 2 && ~isempty(participant)
                if isnumeric(participant), participant = app.Names{participant}; end
                if strcmpi(participant, 'grand'), participant = app.GrandLabel; end
                app.ParticipantDrop.Value = participant;
            end
            if nargin >= 3 && ~isempty(viewName)
                k = find(strncmpi(app.Views, viewName, 3), 1);
                app.ViewDrop.Value = app.Views{k};
            end
            if nargin >= 4 && ~isempty(a), app.CondADrop.Value = a; end
            if nargin >= 5 && ~isempty(b), app.CondBDrop.Value = b; end
            app.onView();
        end

        %% ----------------------------------------------------------------
        %% Step 3: measure
        %% setMeasure - kind 'mean' | 'peak', polarity, [from to] s, channels
        function setMeasure(app, kind, polarity, w, chans)
            app.MeasureDrop.Value = app.MeasureKinds{1 + strcmpi(kind, 'peak')};
            if nargin >= 3 && ~isempty(polarity)
                app.PolarityDrop.Value = [upper(polarity(1)) lower(polarity(2:end))];
            end
            if nargin >= 4 && ~isempty(w)
                app.WindowFromEdit.Value = w(1) * 1000;
                app.WindowToEdit.Value = w(2) * 1000;
            end
            if nargin >= 5, app.MeasureChannelsEdit.Value = channelText(chans); end
            app.updateControls();
        end

        %% measure - One value per participant and condition
        function ok = measure(app)
            ok = false;
            if isempty(app.ERPs)
                UIKit.setStatus(app.StatusLabel, 'Show the ERPs first (step 2).', 'warning');
                return;
            end
            o = app.currentMeasure();
            try
                r = cellfun(@(e) EEGAnalysis.measure(e, 'Channels', o.Channels, 'Window', o.Window, ...
                    'Measure', o.Measure, 'Polarity', o.Polarity), app.ERPs, 'UniformOutput', false);
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Not measured: %s', ME.message), 'error');
                return;
            end
            app.Measures = r;
            app.MeasureSettings = o;
            app.StatsResult = [];
            app.fillMeasures();
            app.fillStats();
            nEdge = sum(cellfun(@(x) sum([x.atEdge]), r));
            if nEdge > 0
                app.MeasureInfo.Text = sprintf(['%s Check: %d peak(s) lie on the edge of the window, so they may ' ...
                    'not be real peaks (the signal was still rising or falling). Widen the window or use the mean ' ...
                    'amplitude.'], EEGAnalysis.describeMeasure(o), nEdge);
                app.MeasureInfo.FontColor = UITheme.warning;
            else
                app.MeasureInfo.Text = EEGAnalysis.describeMeasure(o);
                app.MeasureInfo.FontColor = UITheme.sectionTitleColor;
            end
            app.selectTab('Measures');
            app.plotERP();
            app.updateControls();
            if numel(app.ERPs) > 1
                next = 'Next: Compare conditions (step 4).';
            else
                next = 'Statistics need two or more participants; export the values (step 5).';
            end
            UIKit.setStatus(app.StatusLabel, sprintf('Measured %d participant(s). %s', numel(r), next), ...
                ifelse(nEdge > 0, 'warning', 'success'));
            ok = true;
        end

        %% ----------------------------------------------------------------
        %% Step 4: statistics
        %% setStatsMethod - 'parametric' | 'nonparametric'
        function setStatsMethod(app, m)
            app.MethodDrop.Value = ifelse(strncmpi(m, 'non', 3), 'Nonparametric', 'Parametric');
        end

        %% compareConditions - Within-participant test of the measured values
        function ok = compareConditions(app)
            ok = false;
            if isempty(app.Measures)
                UIKit.setStatus(app.StatusLabel, 'Measure first (step 3).', 'warning');
                return;
            end
            [Y, conds] = app.valueMatrix();
            if size(Y, 1) < 2 || numel(conds) < 2
                UIKit.setStatus(app.StatusLabel, ['Statistics need two or more participants and two or more ' ...
                    'conditions they all have.'], 'warning');
                return;
            end
            design = ifelse(numel(conds) == 2, 'paired', 'rm');
            method = lower(app.MethodDrop.Value);
            try
                res = GroupStats.compare(num2cell(Y, 1), conds, design, method);
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Test not run: %s', ME.message), 'error');
                return;
            end
            app.StatsResult = res;
            app.fillStats();
            app.selectTab('Statistics');
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, [res.summary ' Next: Save (step 5).'], 'success');
            ok = true;
        end

        %% ----------------------------------------------------------------
        %% Step 5: save
        %% exportDialog - Choose .csv or .mat
        function exportDialog(app)
            start = ProjectManager.getExportDir();
            if isempty(start), start = pwd; end
            [f, p] = uiputfile({'*.csv', 'CSV (one row per participant and condition)'; '*.mat', 'MAT (everything)'}, ...
                'Export results', fullfile(start, 'eeg_measures.csv'));
            figure(app.UIFig);
            if isequal(f, 0), return; end
            app.exportResultsTo(fullfile(p, f));
        end

        %% exportResultsTo - Write the measures (.csv) or everything (.mat), by extension
        function ok = exportResultsTo(app, filePath)
            ok = false;
            if isempty(app.Measures)
                UIKit.setStatus(app.StatusLabel, 'Measure first (step 3).', 'warning');
                return;
            end
            [~, name, ext] = fileparts(filePath);
            try
                if strcmpi(ext, '.mat')
                    results = app.resultsStruct(); %#ok<NASGU>
                    save(filePath, 'results');
                else
                    writeCsv(filePath, {'Participant', 'Condition', 'Value_uV', 'Latency_s', 'Trials', 'PeakAtEdge'}, ...
                        app.measureRows(false));
                end
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Export failed: %s', ME.message), 'error');
                return;
            end
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf('Exported %s%s', name, ext), 'success');
        end

        %% ----------------------------------------------------------------
        %% Sessions and reports (core/Session.m, core/Report.m)
        function ok = saveSessionTo(app, filePath, notes)
            if nargin < 3, notes = []; end
            ok = Session.saveApp(app, filePath, notes);
        end

        function ok = openSession(app, filePath, interactive)
            if nargin < 3, interactive = false; end
            ok = Session.openInApp(app, filePath, interactive);
        end

        function ok = makeReport(app, pdfPath)
            ok = Report.forApp(app, pdfPath);
        end

        %% sessionState - Files, settings (trials, baseline, measure, test) and results
        function st = sessionState(app)
            st.inputs = [];
            st.settings = struct();
            st.results = struct();
            st.summary = {};
            if isempty(app.Loaded), return; end
            if strcmp(app.Generator, 'demoEEG')
                st.inputs = Session.fileInfo('', 'EEG demo (demoEEG), 8 participants');
            else
                for k = 1:numel(app.Files)
                    info = Session.fileInfo(app.Files{k}, sprintf('EEG, participant %s', app.Names{k}));
                    if isempty(st.inputs), st.inputs = info; else, st.inputs(end + 1) = info; end
                end
            end
            e1 = app.Loaded{1};
            st.settings.generator = app.Generator;
            st.settings.participants = app.Names;
            st.settings.maps = app.Maps;
            st.settings.sources = cellfun(@(e) e.source, app.Loaded, 'UniformOutput', false);
            st.settings.continuous = ~e1.isEpoched;
            st.settings.trialWindow = app.TrialWindow;
            st.settings.fs = e1.fs;
            st.settings.nChannels = numel(e1.labels);
            st.settings.reference = e1.reference;
            st.settings.history = e1.history;
            st.settings.baselineOn = logical(app.BaselineCb.Value);
            st.settings.baseline = [app.BaselineFromEdit.Value app.BaselineToEdit.Value] / 1000;
            st.settings.channels = channelList(app.ChannelsEdit.Value);
            st.settings.erpsShown = ~isempty(app.ERPs);
            st.settings.measure = app.currentMeasure();
            st.settings.measured = ~isempty(app.Measures);
            st.settings.statsMethod = lower(app.MethodDrop.Value);
            st.settings.tested = ~isempty(app.StatsResult);
            st.summary{end + 1} = sprintf('%d participant(s): %s; %d channels at %g Hz (%s)', numel(app.Names), ...
                strjoin(app.Names, ', '), numel(e1.labels), e1.fs, strjoin(EEGSource.stableUnique(st.settings.sources), ', '));
            if ~isempty(app.TrialWindow)
                st.summary{end + 1} = sprintf('Continuous recordings cut into trials from %g to %g ms around the events', ...
                    app.TrialWindow * 1000);
            end
            if ~isempty(app.ERPs)
                e = app.analysisERP(1);
                st.results.conditions = e.conditions;
                st.results.trials = e.trials;
                st.summary{end + 1} = sprintf('ERPs: %s; %s', EEGSource.listText(arrayfun(@(c) sprintf('%s (%d trials)', ...
                    e.conditions{c}, e.trials(c)), 1:numel(e.conditions), 'UniformOutput', false)), ...
                    ifelse(isempty(app.ERPSettings.baseline), 'no baseline subtracted', ...
                    sprintf('baseline %g to %g ms', app.ERPSettings.baseline * 1000)));
            end
            if isempty(app.Measures), return; end
            st.results.measureHeader = {'Participant', 'Condition', 'Value_uV', 'Latency_s', 'Trials', 'PeakAtEdge'};
            st.results.measures = app.measureRows(false);
            st.summary{end + 1} = EEGAnalysis.describeMeasure(app.MeasureSettings);
            [Y, conds] = app.valueMatrix();
            for c = 1:numel(conds)
                st.summary{end + 1} = sprintf('  %s: mean %.3g uV, SD %.3g (n = %d)', conds{c}, mean(Y(:, c)), ...
                    std(Y(:, c)), size(Y, 1));
            end
            if ~isempty(app.StatsResult)
                st.results.groupTest = app.StatsResult;
                st.summary{end + 1} = sprintf('Test: %s', app.StatsResult.summary);
            end
        end

        %% restoreSession - Reload the files, re-apply the settings, re-run each step
        function ok = restoreSession(app, s)
            ok = false;
            cfg = s.settings;
            if isfield(cfg, 'generator') && strcmp(cfg.generator, 'demoEEG')
                if ~app.loadDemo(), return; end
            elseif isempty(s.inputs)
                ok = true; return;
            else
                maps = {};
                if isfield(cfg, 'maps'), maps = cfg.maps; end
                if ~app.openFiles({s.inputs.path}, maps), return; end
            end
            if ~isempty(cfg.trialWindow)
                app.setTrialWindow(cfg.trialWindow);
                if ~app.cutIntoTrials(), return; end
            end
            app.setBaseline(cfg.baselineOn, cfg.baseline);
            app.setChannels(cfg.channels);
            m = cfg.measure;
            app.setMeasure(m.Measure, m.Polarity, m.Window, m.Channels);
            app.setStatsMethod(cfg.statsMethod);
            if cfg.erpsShown && ~app.showERPs(), return; end
            if cfg.measured && ~app.measure(), return; end
            if cfg.tested && ~app.compareConditions(), return; end
            app.updateControls();
            ok = true;
        end
    end

    methods(Static)
        %% ensurePath - core/io (EEGSource and the readers) on the path
        function ensurePath()
            if exist('EEGSource', 'file') ~= 2
                addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'core', 'io'));
            end
        end
    end

    methods(Access = private)

        %% readOne - One file as an EEG struct ([] when the form was cancelled)
        function [eeg, map] = readOne(app, p, map, interactive, dlg)
            eeg = [];
            if ~isempty(map)
                eeg = EEGSource.open(p, 'matrix', map);
                return;
            end
            try
                eeg = EEGSource.open(p);
            catch ME
                if ~strcmp(ME.identifier, 'NeuroAnalyzer:eeg:needsMap') || ~interactive
                    rethrow(ME);
                end
                UIKit.done(dlg);
                map = matrixMapDialog(p, EEGSource.guessMatrixMap(p));
                if isempty(map), return; end
                eeg = EEGSource.open(p, 'matrix', map);
                return;
            end
            if strcmp(eeg.format, 'matrix')
                g = EEGSource.guessMatrixMap(p);
                map = g.map;
            end
        end

        %% setData - New participants: reset every result, fill the controls
        function ok = setData(app, eegs, names)
            ok = false;
            kinds = cellfun(@(e) e.isEpoched, eegs);
            if any(kinds) && ~all(kinds)
                UIKit.setStatus(app.StatusLabel, ['Some files are cut into trials and others are continuous: ' ...
                    'load them separately.'], 'error');
                return;
            end
            app.Loaded = eegs;
            app.Names = names;
            app.TrialWindow = [];
            if all(kinds), app.EEGs = eegs; else, app.EEGs = {}; end
            app.clearResults();
            e1 = eegs{1};
            if e1.isEpoched
                n = cellfun(@(e) size(e.data, 3), eegs);
                app.FileInfo.Text = sprintf('%d participant(s)  ·  %d channels at %g Hz  ·  trials %g to %g ms  ·  %s trials', ...
                    numel(eegs), numel(e1.labels), e1.fs, e1.times(1) * 1000, e1.times(end) * 1000, rangeText(n));
                app.CutInfo.Text = 'Already cut into trials.';
                app.CutInfo.FontColor = UITheme.bodyColor;
                app.BaselineFromEdit.Value = e1.times(1) * 1000;
            else
                nEv = cellfun(@(e) numel(e.events), eegs);
                app.FileInfo.Text = sprintf('%d participant(s)  ·  %d channels at %g Hz  ·  continuous, %s events', ...
                    numel(eegs), numel(e1.labels), e1.fs, rangeText(nEv));
                app.CutInfo.Text = 'Continuous: choose the trial window and Cut into trials.';
                app.CutInfo.FontColor = UITheme.warning;
            end
            app.FileInfo.FontColor = UITheme.sectionTitleColor;
            % Channels typed for earlier files: keep only those the new files have
            app.ChannelsEdit.Value = channelText(keepChannels(app.ChannelsEdit.Value, e1.labels));
            app.MeasureChannelsEdit.Value = channelText(keepChannels(app.MeasureChannelsEdit.Value, e1.labels));
            items = names;
            if numel(names) > 1, items = [{app.GrandLabel}, names]; end
            app.ParticipantDrop.Items = items;
            app.ParticipantDrop.Value = items{1};
            app.fillOverview();
            app.fillConditionDrops();
            UIKit.emptyAxes(app.AxERP, 'Click Show ERPs (step 2)');
            app.updateControls();
            if e1.isEpoched
                UIKit.setStatus(app.StatusLabel, sprintf(['Loaded %d participant(s). Read the Overview tab (what ' ...
                    'was already done to the data), then Show ERPs (step 2).'], numel(eegs)), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf(['Loaded %d continuous recording(s). Next: choose the ' ...
                    'trial window and Cut into trials (step 1).'], numel(eegs)), 'success');
            end
            ok = true;
        end

        %% clearResults - Forget ERPs, measures and tests (after new data)
        function clearResults(app)
            app.ERPs = {}; app.Grand = []; app.ERPSettings = [];
            app.Measures = {}; app.MeasureSettings = []; app.StatsResult = [];
            if ~isempty(app.MeasuresTable) && isvalid(app.MeasuresTable)
                app.fillMeasures();
                app.fillStats();
                app.ErpInfo.Text = '';
                app.MeasureInfo.Text = '';
            end
        end

        %% isReady - Data cut into trials (message otherwise)
        function tf = isReady(app)
            tf = ~isempty(app.EEGs);
            if tf, return; end
            if isempty(app.Loaded)
                UIKit.setStatus(app.StatusLabel, 'Load EEG files first (step 1).', 'warning');
            else
                UIKit.setStatus(app.StatusLabel, 'Cut the recordings into trials first (step 1).', 'warning');
            end
        end

        %% currentMeasure - Measure settings from the controls (s, names)
        function o = currentMeasure(app)
            chans = channelList(app.MeasureChannelsEdit.Value);
            if isempty(chans) && ~isempty(app.ERPSettings), chans = app.ERPSettings.channels; end
            o = struct('Measure', ifelse(strcmp(app.MeasureDrop.Value, app.MeasureKinds{2}), 'peak', 'mean'), ...
                'Polarity', lower(app.PolarityDrop.Value), ...
                'Window', [app.WindowFromEdit.Value app.WindowToEdit.Value] / 1000, 'Channels', {chans});
        end

        %% analysisERP - ERP of a participant (index) or the grand average (0 / 1 with several)
        % With trials: e.trials (total trials per condition) is always set.
        function e = analysisERP(app, k)
            if k == 1 && ~isempty(app.Grand)
                e = app.Grand;
            else
                if ~isempty(app.Grand), k = k - 1; end
                e = app.ERPs{max(1, k)};
                e.trials = e.n;
            end
        end

        %% shownIndex - Position in the participant list (1 = grand with several)
        function k = shownIndex(app)
            k = find(strcmp(app.ParticipantDrop.Items, app.ParticipantDrop.Value), 1);
            if isempty(k), k = 1; end
        end

        %% channelWaves - ERP of the chosen channels' average for the shown participant(s)
        % SEM across trials (one participant) or across participants (grand).
        function e = channelWaves(app, chans)
            k = app.shownIndex();
            grand = ~isempty(app.Grand) && k == 1;
            if grand, idx = 1:numel(app.EEGs); elseif isempty(app.Grand), idx = k; else, idx = k - 1; end
            erps = cell(1, numel(idx));
            for i = 1:numel(idx)
                eeg = app.EEGs{idx(i)};
                ch = 1:numel(eeg.labels);
                if ~isempty(chans), ch = EEGAnalysis.channelIndex(eeg.labels, chans); end
                eeg.data = mean(eeg.data(ch, :, :), 1);
                eeg.labels = {'mean'};
                erps{i} = EEGAnalysis.conditionERPs(eeg, 'Baseline', app.ERPSettings.baseline);
            end
            e = EEGAnalysis.grandAverage(erps);
        end

        %% onView - Enable the condition lists that the view uses, then plot
        function onView(app)
            app.updateControls();
            app.plotERP();
        end

        %% plotERP - Conditions, butterfly or difference wave of the shown participant(s)
        function plotERP(app)
            ax = app.AxERP;
            % cla keeps objects with hidden handles (butterfly lines, SEM shades): delete them all
            delete(allchild(ax));
            ax.YLimMode = 'auto';   % the measure window fixes the limits; each view starts free
            if isempty(app.ERPs)
                if isempty(app.Loaded)
                    UIKit.emptyAxes(ax, 'Load EEG files (or Try demo data) to begin');
                else
                    UIKit.emptyAxes(ax, 'Click Show ERPs (step 2)');
                end
                return;
            end
            T = UITheme;
            hold(ax, 'on');
            chans = app.ERPSettings.channels;
            where = ifelse(isempty(chans), 'all channels (average)', strjoin(chans, ', '));
            whoText = app.ParticipantDrop.Value;
            shownView = app.ViewDrop.Value;
            try
                switch shownView
                    case app.Views{2}
                        e = app.analysisERP(app.shownIndex());
                        c = find(strcmp(e.conditions, app.CondADrop.Value), 1);
                        if isempty(c), c = 1; end
                        t = e.times * 1000;
                        y = e.mean(:, :, c);
                        plot(ax, t, y', 'Color', lighten(T.bodyColor, 0.6), 'LineWidth', 0.5, 'HandleVisibility', 'off');
                        if ~isempty(chans)
                            ch = EEGAnalysis.channelIndex(e.labels, chans);
                            for i = 1:numel(ch)
                                col = T.plotColors(1 + mod(i - 1, size(T.plotColors, 1)), :);
                                plot(ax, t, y(ch(i), :), 'Color', col, 'LineWidth', 1.8, 'DisplayName', e.labels{ch(i)});
                            end
                        end
                        ttl = sprintf('%s: %s, every channel', whoText, e.conditions{c});
                    case app.Views{3}
                        w = app.channelWaves(chans);
                        a = app.CondADrop.Value; b = app.CondBDrop.Value;
                        d = EEGAnalysis.difference(w, a, b);
                        t = w.times * 1000;
                        ia = strcmp(w.conditions, a); ib = strcmp(w.conditions, b);
                        plot(ax, t, w.mean(1, :, ia), '--', 'Color', lighten(T.plotColors(1, :), 0.4), 'DisplayName', a);
                        plot(ax, t, w.mean(1, :, ib), '--', 'Color', lighten(T.plotColors(2, :), 0.4), 'DisplayName', b);
                        plot(ax, t, d.mean, 'Color', T.sectionTitleColor, 'LineWidth', 2, 'DisplayName', d.label);
                        ttl = sprintf('%s: %s at %s', whoText, d.label, where);
                    otherwise
                        w = app.channelWaves(chans);
                        t = w.times * 1000;
                        grand = ~isempty(app.Grand) && app.shownIndex() == 1;
                        for c = 1:numel(w.conditions)
                            col = T.plotColors(1 + mod(c - 1, size(T.plotColors, 1)), :);
                            m = w.mean(1, :, c);
                            s = w.sem(1, :, c);
                            if all(isfinite(s))
                                fill(ax, [t fliplr(t)], [m + s, fliplr(m - s)], col, 'FaceAlpha', 0.15, ...
                                    'EdgeColor', 'none', 'HandleVisibility', 'off');
                            end
                            if grand, nTxt = sprintf('%d participants', w.n(c)); else, nTxt = sprintf('%d trials', w.n(c)); end
                            plot(ax, t, m, 'Color', col, 'LineWidth', 1.6, 'DisplayName', ...
                                sprintf('%s (%s)', w.conditions{c}, nTxt));
                        end
                        ttl = sprintf('%s: conditions at %s', whoText, where);
                end
            catch ME
                hold(ax, 'off');
                UIKit.emptyAxes(ax, sprintf('Cannot plot: %s', ME.message));
                return;
            end
            if ~isempty(app.MeasureSettings)
                wm = app.MeasureSettings.Window * 1000;
                yl = dataRange(ax);   % not ylim(ax): before the first draw it can still be [0 1]
                patch(ax, [wm(1) wm(2) wm(2) wm(1)], [yl(1) yl(1) yl(2) yl(2)], T.accent, 'FaceAlpha', 0.1, ...
                    'EdgeColor', 'none', 'HandleVisibility', 'off');
                ylim(ax, yl);
            end
            xline(ax, 0, ':', 'Color', T.stimColor, 'HandleVisibility', 'off');
            yline(ax, 0, '-', 'Color', T.axesGrid, 'HandleVisibility', 'off');
            hold(ax, 'off');
            UIKit.styleAxes(ax, ttl, 'Time from the event (ms)', 'Voltage (uV, positive up)');
            xlim(ax, [t(1) t(end)]);
            if ~isempty(findobj(ax, 'Type', 'line'))
                legend(ax, 'Location', 'northwest', 'Box', 'off', 'Interpreter', 'none');
            else
                legend(ax, 'off');
            end
        end

        %% fillOverview - What every file holds and what was done to it before
        function fillOverview(app)
            lines = {};
            for k = 1:numel(app.Loaded)
                e = app.Loaded{k};
                if ~isempty(app.EEGs), e = app.EEGs{k}; end
                lines{end + 1} = sprintf('%s  (%s, %s)', app.Names{k}, e.source, fileName(e.file)); %#ok<AGROW>
                lines = [lines, strcat({'   '}, EEGSource.describe(e))]; %#ok<AGROW>
                lines{end + 1} = '   Already done to the data (read from the file, nothing was run):'; %#ok<AGROW>
                lines = [lines, strcat({'     - '}, EEGSource.describeHistory(e))]; %#ok<AGROW>
                lines{end + 1} = ''; %#ok<AGROW>
            end
            if isempty(lines), lines = {'Load EEG files to see what they hold and what was done to them.'}; end
            app.OverviewText.Value = lines';
        end

        %% fillConditionDrops - Condition lists of the plot bar
        function fillConditionDrops(app)
            conds = {};
            if ~isempty(app.ERPs)
                conds = app.analysisERP(1).conditions;
            elseif ~isempty(app.EEGs)
                conds = app.EEGs{1}.conditions;
            end
            if isempty(conds), conds = {'(none)'}; end
            a = app.CondADrop.Value; b = app.CondBDrop.Value;
            app.CondADrop.Items = conds;
            app.CondBDrop.Items = conds;
            % Default difference: the second condition minus the first (e.g. Target minus Standard)
            if ~any(strcmp(conds, a)), a = conds{min(2, numel(conds))}; end
            if ~any(strcmp(conds, b)) || strcmp(a, b), b = conds{1}; end
            app.CondADrop.Value = a;
            app.CondBDrop.Value = b;
        end

        %% fillMeasures - Measures table
        function fillMeasures(app)
            if isempty(app.Measures)
                app.MeasuresTable.Data = cell(0, 6);
                return;
            end
            app.MeasuresTable.Data = app.measureRows(true);
        end

        %% measureRows - Participant, condition, value, latency, trials, check
        % forTable: latency in ms and a text check; otherwise s and a flag.
        function rows = measureRows(app, forTable)
            rows = cell(0, 6);
            order = {};
            if ~isempty(app.ERPs), order = app.analysisERP(1).conditions; end
            for p = 1:numel(app.Measures)
                r = app.Measures{p};
                % Same condition order for every participant (that of the ERPs; others after)
                [~, pos] = ismember({r.condition}, order);
                pos(pos == 0) = numel(order) + find(pos == 0);
                [~, k] = sort(pos);
                r = r(k);
                for c = 1:numel(r)
                    if forTable
                        lat = round(r(c).latency * 1000, 1);
                        if isnan(lat), lat = []; end
                        if r(c).atEdge, chk = 'Peak on the window edge'; else, chk = ''; end
                        rows(end + 1, :) = {app.Names{p}, r(c).condition, round(r(c).value, 3), lat, ...
                            r(c).n, chk}; %#ok<AGROW>
                    else
                        rows(end + 1, :) = {app.Names{p}, r(c).condition, r(c).value, r(c).latency, r(c).n, ...
                            double(r(c).atEdge)}; %#ok<AGROW>
                    end
                end
            end
        end

        %% valueMatrix - Participants x conditions (conditions every participant has)
        function [Y, conds] = valueMatrix(app)
            conds = app.analysisERP(1).conditions;
            Y = nan(numel(app.Measures), numel(conds));
            for p = 1:numel(app.Measures)
                r = app.Measures{p};
                [tf, j] = ismember(conds, {r.condition});
                Y(p, tf) = [r(j(tf)).value];
            end
        end

        %% fillStats - Statistics text and pairwise table
        function fillStats(app)
            r = app.StatsResult;
            if isempty(r)
                app.StatsText.Value = {'Measure (step 3), then Compare conditions (step 4).'};
                app.StatsTable.Data = cell(0, 5);
                app.StatsInfo.Text = '';
                return;
            end
            if r.checkAgrees, agree = 'agrees with the main test'; else, agree = 'disagrees with the main test'; end
            o = app.MeasureSettings;
            lines = {r.summary; ''; ['Assumptions: ' r.assumptions]; ''; ...
                sprintf('Robustness check: %s, %s (%s).', r.check.test, GroupStats.formatP(r.check.p), agree); ''; ...
                ['Values compared: ' EEGAnalysis.describeMeasure(o)]; ...
                sprintf('Participants (matched across conditions): %s.', strjoin(app.Names, ', '))};
            app.StatsText.Value = lines;
            ph = r.comparisons;
            rows = cell(numel(ph), 5);
            for i = 1:numel(ph)
                if all(isfinite(ph(i).ci)), ci = sprintf('%.3g to %.3g', ph(i).ci); else, ci = ''; end
                rows(i, :) = {ph(i).label, round(ph(i).diff, 3), ci, GroupStats.formatP(ph(i).p), ph(i).method};
            end
            app.StatsTable.Data = rows;
            app.StatsInfo.Text = sprintf('%s: %s, %s', r.main.test, GroupStats.statText(r.main), GroupStats.formatP(r.main.p));
            app.StatsInfo.FontColor = UITheme.sectionTitleColor;
        end

        %% resultsStruct - Everything for the .mat export
        function r = resultsStruct(app)
            r = struct('participants', {app.Names}, 'files', {app.Files}, 'erps', {app.ERPs}, ...
                'grandAverage', app.Grand, 'erpSettings', app.ERPSettings, 'measureSettings', app.MeasureSettings, ...
                'measureHeader', {{'Participant', 'Condition', 'Value_uV', 'Latency_s', 'Trials', 'PeakAtEdge'}}, ...
                'measures', {app.measureRows(false)}, 'measureText', EEGAnalysis.describeMeasure(app.MeasureSettings), ...
                'stats', app.StatsResult, 'trialWindow', app.TrialWindow);
        end

        %% selectTab - Show a result tab by title
        function selectTab(app, titleText)
            tab = findobj(app.Tabs, 'Type', 'uitab', 'Title', titleText);
            if ~isempty(tab), app.Tabs.SelectedTab = tab(1); end
        end

        %% updateControls - Enable states from the data; next step is primary
        function updateControls(app)
            has = ~isempty(app.Loaded);
            continuous = has && ~app.Loaded{1}.isEpoched;
            ready = ~isempty(app.EEGs);
            shown = ~isempty(app.ERPs);
            measured = ~isempty(app.Measures);
            tested = ~isempty(app.StatsResult);
            peak = strcmp(app.MeasureDrop.Value, app.MeasureKinds{2});
            shownView = app.ViewDrop.Value;
            app.TrialFromEdit.Enable = onoff(continuous);
            app.TrialToEdit.Enable = onoff(continuous);
            app.CutBtn.Enable = onoff(continuous);
            app.BaselineFromEdit.Enable = onoff(ready && app.BaselineCb.Value);
            app.BaselineToEdit.Enable = onoff(ready && app.BaselineCb.Value);
            app.ShowBtn.Enable = onoff(ready);
            app.MeasureBtn.Enable = onoff(shown);
            app.PolarityDrop.Enable = onoff(peak);
            app.StatsBtn.Enable = onoff(measured && numel(app.Measures) > 1);
            app.ExportBtn.Enable = onoff(measured);
            app.ParticipantDrop.Enable = onoff(shown);
            app.ViewDrop.Enable = onoff(shown);
            app.CondADrop.Enable = onoff(shown && ~strcmp(shownView, app.Views{1}));
            app.CondBDrop.Enable = onoff(shown && strcmp(shownView, app.Views{3}));
            UIKit.setSessionEnable(app.SessionBtns, has);
            setButtonStyle(app.LoadBtn, ifelse(~has, 'primary', 'secondary'));
            setButtonStyle(app.CutBtn, ifelse(continuous && ~ready, 'primary', 'secondary'));
            setButtonStyle(app.ShowBtn, ifelse(ready && ~shown, 'primary', 'secondary'));
            setButtonStyle(app.MeasureBtn, ifelse(shown && ~measured, 'primary', 'secondary'));
            setButtonStyle(app.StatsBtn, ifelse(measured && ~tested && numel(app.Measures) > 1, 'primary', 'secondary'));
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% matrixMapDialog - Form: what the variables of a plain .mat file are
% Returns a readEEGMatrix map, or [] when cancelled.
function map = matrixMapDialog(p, g)
    [~, n, e] = fileparts(p);
    D = UIKit.dialog('What is in this file?', sprintf('%s%s: say which variable is what', n, e), ...
        'EEG Analysis', [560 560]);
    none = '(none)';
    vars = {g.variables.name};
    isNum = cellfun(@(c) any(strcmp(c, {'double', 'single', 'int16', 'int32', 'uint16', 'int8', 'uint8'})), ...
        {g.variables.class});
    sizes = {g.variables.size};
    big = vars(isNum & cellfun(@(s) sum(s > 1) >= 2, sizes));
    scalars = vars(isNum & cellfun(@(s) prod(s) == 1, sizes));
    vectors = vars(cellfun(@(s) sum(s > 1) == 1, sizes));
    m = g.map;
    rows = {50, 26, 26, 26, 26, 26, 26, 26, 26, 26, '1x'};
    D.Body.RowHeight = rows;
    msg = strjoin([g.problems, g.notes], ' ');
    if isempty(msg), msg = 'Check the suggestion and click OK.'; end
    h = UIKit.hint(D.Body, msg);
    h.Parent.Parent.Layout.Row = 1; h.Parent.Parent.Layout.Column = [1 2];
    c = struct();
    c.data = formField(D.Body, 2, 'EEG numbers', pick(big, m.data), ...
        'The variable holding the EEG (a table of numbers)');
    c.fsVar = formField(D.Body, 3, 'Sampling rate from', pick([{'(type it below)'}, scalars], m.fs), ...
        'A variable holding the sampling rate in Hz, or type it below');
    c.fs = uieditfield(D.Body, 'numeric', 'Value', 1000, 'Limits', [1e-3 1e7], ...
        'Tooltip', 'Sampling rate in Hz (used when no variable holds it)');
    c.fs.Layout.Row = 4; c.fs.Layout.Column = 2;
    lbl = uilabel(D.Body, 'Text', 'Sampling rate (Hz)'); lbl.Layout.Row = 4; lbl.Layout.Column = 1;
    orders = dimOrders(numel(dataSize(g, c.data.Value)));
    c.dims = formField(D.Body, 5, 'Order of the numbers', {orders, pickOrder(orders, m.dims)}, ...
        'What each dimension of the numbers is, from the first to the last');
    c.data.ValueChangedFcn = @(~,~)refreshOrders(c, g);
    c.labels = formField(D.Body, 6, 'Channel names', pick([{none}, vectors], m.labels), ...
        'A list of channel names (none: Ch 1, Ch 2, ...)');
    c.times = formField(D.Body, 7, 'Time of each sample (s)', pick([{none}, vectors], m.times), ...
        'A vector of times in s (none: from the start time below)');
    c.tStart = uieditfield(D.Body, 'numeric', 'Value', 0, 'Tooltip', ...
        'Time of the first sample in s, e.g. -0.2 for trials that start 200 ms before the event');
    c.tStart.Layout.Row = 8; c.tStart.Layout.Column = 2;
    lbl = uilabel(D.Body, 'Text', 'Start time (s)'); lbl.Layout.Row = 8; lbl.Layout.Column = 1;
    c.conditions = formField(D.Body, 9, 'Condition of each trial', pick([{none}, vectors], m.conditions), ...
        'Trials only: a list with the condition (name or number) of every trial');
    c.events = formField(D.Body, 10, 'Event times (s)', pick([{none}, vectors], m.events), ...
        'Continuous recordings only: the times of the events (s), to cut trials around them');
    c.unit = formField(D.Body, 11, 'Unit', {{'auto', 'uV', 'mV', 'V'}, m.unit}, ...
        'auto: values smaller than 0.01 are taken as volts and converted to microvolts');
    map = [];
    fig = D.Fig;
    fig.UserData = [];
    UIKit.button(D.Buttons, 'Cancel', @(~,~)uiresume(fig), 'secondary');
    UIKit.button(D.Buttons, 'OK', @(~,~)mapFinish(fig, c), 'primary');
    uiwait(fig);
    if isvalid(fig)
        map = fig.UserData;
        delete(fig);
    end
end

%% mapFinish - OK of the form: the map into the dialog's UserData
function mapFinish(fig, c)
    map = struct('data', c.data.Value, 'dims', {orderDims(c.dims.Value)}, 'unit', c.unit.Value, ...
        'tStart', c.tStart.Value);
    if strcmp(c.fsVar.Value, '(type it below)'), map.fs = c.fs.Value; else, map.fs = c.fsVar.Value; end
    for f = {'labels', 'times', 'conditions', 'events'}
        v = c.(f{1}).Value;
        if strcmp(v, '(none)'), v = ''; end
        map.(f{1}) = v;
    end
    fig.UserData = map;
    uiresume(fig);
end

%% formField - Dropdown field on a given row of a dialog form
function c = formField(grid, row, labelText, value, tooltip)
    c = addField(grid, row, labelText, 'dropdown', value, tooltip);
end

%% pick - {items, value}: value when it is one of the items, else the first item
function v = pick(items, value)
    if isempty(items), items = {'(none)'}; end
    if ischar(value) && any(strcmp(items, value)), sel = value; else, sel = items{1}; end
    v = {items, sel};
end

%% dataSize - Size of the chosen data variable
function sz = dataSize(g, name)
    k = find(strcmp({g.variables.name}, name), 1);
    if isempty(k), sz = [1 1]; else, sz = g.variables(k).size; end
end

%% dimOrders - Texts for every order of channels / samples (/ trials)
function t = dimOrders(nd)
    if nd >= 3
        P = perms(1:3);
        P = P(end:-1:1, :);
    else
        P = [1 2; 2 1];
    end
    words = {'channels', 'samples', 'trials'};
    t = arrayfun(@(i) strjoin(words(P(i, :)), ' x '), 1:size(P, 1), 'UniformOutput', false);
end

%% pickOrder - The order text that matches a dims cell
function s = pickOrder(orders, dims)
    s = orders{1};
    if isempty(dims), return; end
    txt = strjoin(strrep(strrep(strrep(dims, 'channel', 'channels'), 'time', 'samples'), 'trial', 'trials'), ' x ');
    if any(strcmp(orders, txt)), s = txt; end
end

%% orderDims - Order text -> dims cell ('channels x samples' -> {'channel', 'time'})
function d = orderDims(txt)
    d = strtrim(strsplit(txt, 'x'));
    d = strrep(strrep(strrep(d, 'channels', 'channel'), 'samples', 'time'), 'trials', 'trial');
end

%% refreshOrders - New data variable: the order list for its number of dimensions
function refreshOrders(c, g)
    orders = dimOrders(numel(dataSize(g, c.data.Value)));
    c.dims.Items = orders;
    c.dims.Value = orders{1};
end

%% stepCard - Card with a numbered step title and a 2-column grid
function [p, g, h] = stepCard(parent, n, text, rowHeights)
    T = UITheme;
    p = UIKit.card(parent, '');
    rh = [{22}, rowHeights];
    g = uigridlayout(p, [numel(rh) 2], 'RowHeight', rh, 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [10 8 10 10], 'RowSpacing', 6, 'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
    lbl = UIKit.step(g, n, text);
    lbl.Layout.Row = 1; lbl.Layout.Column = [1 2];
    h = sum([rh{:}]) + 6 * (numel(rh) - 1) + 18 + 4;
end

%% addField - UIKit.field placed on grid row 'row' (label col 1, control col 2)
function c = addField(g, row, labelText, varargin)
    c = UIKit.field(g, labelText, varargin{:});
    lbl = findobj(g, '-depth', 1, 'Type', 'uilabel', 'Text', labelText);
    if ~isempty(lbl), lbl(end).Layout.Row = row; lbl(end).Layout.Column = 1; end
    c.Layout.Row = row; c.Layout.Column = 2;
end

%% infoLabel - Small wrapped muted label
function lbl = infoLabel(parent, text, tooltip)
    T = UITheme;
    lbl = uilabel(parent, 'Text', text, 'FontSize', T.fontSmall, 'FontColor', T.bodyColor, ...
        'WordWrap', 'on', 'VerticalAlignment', 'top', 'Tooltip', tooltip, 'Interpreter', 'none');
end

%% barLabel - Label of the plot bar
function barLabel(parent, text)
    T = UITheme;
    uilabel(parent, 'Text', text, 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
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

%% dataRange - [low high] of the lines and shades drawn in ax, with a 5% margin
function yl = dataRange(ax)
    h = findall(ax, 'Type', 'line', '-or', 'Type', 'patch');
    y = get(h, 'YData');
    if iscell(y), y = cellfun(@(v) v(:)', y, 'UniformOutput', false); y = [y{:}]; else, y = y(:)'; end
    y = y(isfinite(y));
    if isempty(y), yl = [-1 1]; return; end
    lo = min(y); hi = max(y);
    pad = 0.05 * max(hi - lo, eps);
    yl = [lo - pad, hi + pad];
end

%% lighten - Colour mixed with white (f = 0: unchanged, 1: white)
function c = lighten(c, f)
    c = c + (1 - c) * f;
end

%% channelList - 'Cz, FCz' (or a cell) -> {'Cz', 'FCz'}; '' -> {} (names may hold spaces: 'Ch 1')
function c = channelList(x)
    if iscell(x), c = EEGSource.cellRow(x); return; end
    x = strtrim(char(x));
    if isempty(x), c = {}; return; end
    c = strtrim(strsplit(x, {',', ';'}));
    c = c(~cellfun(@isempty, c));
end

%% keepChannels - The names in x (text or cell) that are among labels (any case)
function c = keepChannels(x, labels)
    c = channelList(x);
    c = c(ismember(lower(c), lower(labels)));
end

%% channelText - {'Cz', 'FCz'} (or text) -> 'Cz, FCz'
function t = channelText(x)
    t = strjoin(channelList(x), ', ');
end

%% rangeText - '65' or '60-65' for a list of counts
function t = rangeText(n)
    if min(n) == max(n), t = sprintf('%d', n(1)); else, t = sprintf('%d-%d', min(n), max(n)); end
end

%% fileName - Name and extension of a path
function s = fileName(p)
    [~, n, e] = fileparts(p);
    s = [n e];
end

%% writeCsv - Header + rows (cell) as CSV, text quoted
function writeCsv(p, header, rows)
    fid = fopen(p, 'w');
    if fid < 0, error('NeuroAnalyzer:eeg:write', 'Cannot write %s', p); end
    c = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', strjoin(cellfun(@(h) ['"' strrep(h, '"', '""') '"'], header, 'UniformOutput', false), ','));
    for r = 1:size(rows, 1)
        parts = cell(1, size(rows, 2));
        for c2 = 1:size(rows, 2)
            v = rows{r, c2};
            if ischar(v), parts{c2} = ['"' strrep(v, '"', '""') '"'];
            elseif isempty(v) || (isnumeric(v) && isnan(v)), parts{c2} = '';
            else, parts{c2} = sprintf('%.10g', v);
            end
        end
        fprintf(fid, '%s\n', strjoin(parts, ','));
    end
end

%% onoff - 'on'/'off' from a logical
function s = onoff(cond)
    if cond, s = 'on'; else, s = 'off'; end
end

%% ifelse - One of two values
function s = ifelse(cond, a, b)
    if cond, s = a; else, s = b; end
end
