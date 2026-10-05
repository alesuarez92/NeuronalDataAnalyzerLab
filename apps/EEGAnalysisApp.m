%% EEGAnalysisApp.m
% =========================================================================
% EEG ANALYSIS - ERPs PER CONDITION, AMPLITUDE MEASURES AND STATISTICS
% =========================================================================
% Opened from the launcher (EEG card). For raw recordings (BrainVision
% Recorder, EDF / BDF, XDF, EEG-BIDS), cleaned here with basic
% steps, and for EEG already cleaned in EEGLAB, FieldTrip, BrainVision
% Analyzer or MATLAB: one file per participant (EEGLAB .set, FieldTrip
% .mat, BrainVision .vhdr, EDF / BDF, .xdf or a plain .mat array),
% scalp or rodent.
%
% Layout (UIKit.window): numbered step cards on the left
%   1 Load EEG      (one or several files; a plain .mat file gets a short
%                    form saying what its variables are; two demos: the
%                    cleaned study and 3 raw continuous recordings; the
%                    Electrode layout... dialog shows where every electrode
%                    sits, core/EEGLayout.m, and lets the user change and
%                    confirm it)
%   2 Clean recordings (bad channels per participant, with a suggestion;
%                    high-pass, low-pass and notch filters; re-reference to
%                    the average, linked mastoids or chosen channels)
%   3 Trials        (events and condition names, trial window; a
%                    continuous recording is cut into trials around its
%                    events; trials with too large amplitudes left out)
%   4 ERPs          (baseline, channels to look at)
%   5 Measure       (mean or peak amplitude in a time window, per
%                    participant and condition; warns about edge peaks;
%                    Scalp maps of the same window)
%   6 Statistics    (conditions compared within participants: paired
%                    t-test / Wilcoxon for two, repeated-measures ANOVA /
%                    Friedman for more; core/GroupStats.m)
%   7 Time-frequency (Morlet wavelet power of every trial at chosen
%                    channels, per participant and condition: ERSP, ITPC
%                    and the power of one band; EEGAnalysis.timeFrequency;
%                    values only where the whole wavelet lies inside the
%                    trial)
%   8 Save          (measures as .csv, everything as .mat; sessions)
% and on the right the ERP plot (conditions, all channels, a difference
% wave, or scalp maps of the window of step 5: one per condition and A
% minus B, core/ScalpMap.m; or the time-frequency of step 7: ERSP per
% condition and A minus B, ITPC per condition, band power; one
% participant or the grand average) above the tabs
% Overview (what each file holds and what was done to it) |
% Measures | Statistics | Checks. The computations are in core/EEGAnalysis.m.
% Checks tab (UIKit.checksTab): after Cut into trials / Apply rejection
% (step 3), Show ERPs (step 4) and Measure (step 5), EEGAnalysis.checks
% looks at the trials analysed (trials per condition, the share of each
% condition rejected, trial counts against the measure, bad channels,
% channels interpolated before loading against the measured channels);
% Compare conditions (step 6) adds the checks of the test
% (GroupStats.checks: sample size, normality, sphericity, robustness
% check, missing values; worded for participants);
% CheckRows holds the rows, sessions store them, new results clear them.
% Step 2 always starts again from the files as read and step 3 from the
% result of step 2 (or the files when step 2 was not applied), in the
% order bad channels -> filters -> reference -> trials -> rejection, so a
% session replays them exactly.
%
% Scriptable (CI walkthroughs, no dialogs): openFiles(paths, maps),
% loadDemo(), loadRawDemo(), loadFaultsDemo() (DemoData 'eegFaults': one
% participant with the faults of the checks), setLayout('Source', s, 'PositionsFile', f,
% 'Edits', E, 'Confirm', tf), openLayout() (the layout dialog, not modal;
% returns its figure), setBadChannels(participant, names),
% suggestBadChannels(participant), setFilters(highPass, lowPass, notch),
% setReference(mode, channels), applyCleaning(), setEvents(text),
% setTrialWindow([from to] s), setRejection(on, peakToPeak, absolute),
% cutIntoTrials(), setBaseline(on, [from to] s), setChannels(names),
% showERPs(), setView(participant, view, condA, condB), showScalpMaps([from
% to] s), setMeasure(kind, polarity, [from to] s, channels), measure(),
% setStatsMethod(m),
% compareConditions(), setTimeFrequency([from to] Hz, cycles, [from to] s,
% channels, band; [] = unchanged), showTimeFrequency(), exportResultsTo(path). Sessions:
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
        RawDemoBtn
        FileInfo
        LayoutBtn           % Electrode layout... (opens the layout dialog)
        LayoutInfo          % summary of the layout, confirmed or not
        % Step 2
        CleanParticipantDrop    % whose bad channels the field shows
        BadEdit             % text: 'T7' or 'T7, FT9'
        SuggestBtn
        HighPassEdit        % Hz, 0 = off
        LowPassEdit         % Hz, 0 = off
        NotchDrop
        ReferenceDrop
        ReferenceChannelsEdit
        ApplyCleanBtn
        CleanInfo
        % Step 3
        EventsEdit          % text: 'S 1 = Standard, S 2 = Target'
        TrialFromEdit       % ms
        TrialToEdit         % ms
        RejectCb
        PeakToPeakEdit      % uV, 0 = off
        AbsoluteEdit        % uV, 0 = off
        CutBtn
        CutInfo
        % Step 4
        BaselineCb
        BaselineFromEdit    % ms
        BaselineToEdit      % ms
        ChannelsEdit        % text: 'Pz' or 'Cz, FCz'
        ShowBtn
        ErpInfo
        % Step 5
        MeasureDrop
        PolarityDrop
        WindowFromEdit      % ms
        WindowToEdit        % ms
        MeasureChannelsEdit
        MeasureBtn
        MapsBtn             % Scalp maps (of the window above, in the plot area)
        MeasureInfo
        % Step 6
        MethodDrop
        StatsBtn
        StatsInfo
        % Step 7
        TFFromEdit          % Hz
        TFToEdit            % Hz
        TFCyclesEdit        % Morlet wavelet cycles
        TFBaseFromEdit      % ms
        TFBaseToEdit        % ms
        TFChannelsEdit      % text: 'Oz' or 'O1, Oz, O2' ('' = the channels of step 4)
        TFBandDrop          % band of Band power (TimeFrequency.defaultBands)
        TFBtn
        TFInfo
        % Step 8
        ExportBtn
        SessionBtns
        % Right side
        ParticipantDrop
        ViewDrop
        CondADrop
        CondBDrop
        AxERP
        PlotGrid            % holds ErpPanel (row 1) and MapPanel (row 2); the row shown has height '1x'
        ErpPanel            % holds AxERP; hidden while the maps show (a 0-height row still drew its top)
        MapPanel            % the scalp maps (view Scalp maps)
        Tabs
        OverviewText
        MeasuresTable
        StatsText
        StatsTable
        ChecksUI            % UIKit.checksTab struct (Tab, Table, Text)
        ChecksTab           % = ChecksUI.Tab
        ChecksTable         % = ChecksUI.Table (Result | Topic | Finding)
        ChecksText          % = ChecksUI.Text (the clicked row in full)
        CheckRows           % QualityChecks rows of the trials analysed (EEGAnalysis.checks) and of the test (GroupStats.checks)
        % Data
        Files = {}          % loaded file paths
        Maps = {}           % plain .mat: the map used for each file ([] otherwise)
        Names = {}          % participant names (file names)
        Loaded = {}         % EEG structs as read (core/io/EEGSource.m)
        BadChannels = {}    % 1 x P cell of channel names marked bad (step 2)
        Cleaned = {}        % Loaded after step 2 ({} = step 2 not applied)
        EEGs = {}           % the same cut into trials (what is analysed)
        Generator = ''      % 'demoEEG' / 'demoEEGraw' when a demo was loaded
        CleanSettings = []  % step 2 settings used for Cleaned
        SuggestRule = ''    % how the last bad channel suggestion was made
        TrialSettings = []  % step 3 settings used for EEGs
        TrialWindow = []    % [from to] s used to cut continuous recordings
        Rejections = []     % 1 x P rejectTrials info ([] when no rejection ran)
        ERPs = {}           % conditionERPs per participant (all channels)
        Grand = []          % grandAverage of ERPs (several participants)
        ERPSettings = []    % baseline and channels of the ERPs shown
        Measures = {}       % 1 x P measure() results
        MeasureSettings = []
        StatsResult = []    % GroupStats.compare result
        ScalpMaps = []      % maps last drawn (ScalpMap.make results plus name), [] = none
        MapSettings = []    % window [from to] s, participant, condA, condB of ScalpMaps
        TFs = {}            % EEGAnalysis.timeFrequency per participant (step 7)
        GrandTF = []        % grandTimeFrequency of TFs (several participants)
        TFSettings = []     % currentTF() used for TFs
        % Electrode layout (step 1)
        Layout = []         % EEGLayout of participant 1 (core/EEGLayout.m: kind, labels, pos, ...)
        LayoutSettings = [] % source 'auto' | 'template' | 'file', positionsFile, edits, confirmed
        LayoutPositions = []    % readElectrodes struct of the positions file ([] = none)
        LayoutFig = []      % the Electrode layout dialog while it is open
        LayoutDlg = []      % its controls and the layout shown in it (draft, not yet used)
    end

    properties(Constant)
        GrandLabel = 'All participants (grand average)'
        Views = {'Conditions', 'All channels (butterfly)', 'Difference wave', 'Scalp maps', ...
            ['Time' char(8211) 'frequency (ERSP)'], 'Phase locking (ITPC)', 'Band power'}
        MeasureKinds = {'Mean amplitude', 'Peak amplitude'}
        NotchItems = {'Off', '50 Hz (+ harmonics)', '60 Hz (+ harmonics)'}
        ReferenceModes = {'As recorded', 'Average', 'Linked mastoids', 'Channels'}
        LayoutSources = {'From the files, others by name', 'By name (10-5 system)', 'From a positions file'}
        PositionsRole = 'Electrode positions'   % role of the positions file in a session's inputs
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
                'Cleaning, ERPs per condition, amplitude measures and statistics for scalp or rodent EEG', ...
                'EEG Analysis', [1320 900]);
            app.UIFig = app.W.Fig;
            app.UIFig.DeleteFcn = @(~,~)app.closeLayout();     % the layout dialog closes with the window
            app.StatusLabel = app.W.Status;
            app.W.Body.RowHeight = {'1x'};
            app.W.Body.ColumnWidth = {360, '1x'};

            left = uigridlayout(app.W.Body, [9 1], 'Padding', [0 0 0 0], 'RowSpacing', 10, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            heights = cell(1, 9);
            ch = T.controlHeight; bh = T.buttonHeight;

            % --- 1 Load EEG ---
            [p, g, heights{1}] = stepCard(left, 1, 'Load EEG', {bh, bh, 48, bh, 60});
            p.Layout.Row = 1;
            app.LoadBtn = UIKit.button(g, ['Load EEG files' char(8230)], @(~,~)app.loadDialog(), 'primary', ...
                ['One file per participant: EEGLAB .set, FieldTrip .mat, BrainVision .vhdr (Brain Products Recorder or ' ...
                 'Analyzer; keep its .vmrk and .eeg files next to it), EDF / BDF, XDF (LabRecorder), the sub-*_eeg ' ...
                 'file of an EEG-BIDS dataset, ' ...
                 'or a plain .mat with the numbers (you will be ' ...
                 'asked what its variables are). Select several files at once for a group.']);
            app.LoadBtn.Layout.Row = 2; app.LoadBtn.Layout.Column = 1;
            app.DemoBtn = UIKit.button(g, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['An oddball study: 8 participants, 32 channels, Standard / Target / Novel trials with a P300 at Pz ' ...
                 '(Target 10 > Novel 6 > Standard 2 uV), already cleaned and cut into trials; see Help for every answer']);
            app.DemoBtn.Layout.Row = 2; app.DemoBtn.Layout.Column = 2;
            app.RawDemoBtn = UIKit.button(g, 'Try raw demo (continuous, not cleaned)', @(~,~)app.loadRawDemo(), ...
                'secondary', ['The same oddball design as 3 raw BrainVision Recorder recordings (500 Hz, 32 channels ' ...
                 'against FCz) with drift, 50 Hz line noise, a noisy T7 and blinks in 8 trials per participant: ' ...
                 'practise steps 2 and 3. The suggested settings are filled in; nothing is applied yet.']);
            app.RawDemoBtn.Layout.Row = 3; app.RawDemoBtn.Layout.Column = [1 2];
            app.FileInfo = infoLabel(g, 'Nothing loaded', 'Participants, channels and trials');
            app.FileInfo.Layout.Row = 4; app.FileInfo.Layout.Column = [1 2];
            app.LayoutBtn = UIKit.button(g, ['Electrode layout' char(8230)], @(~,~)app.openLayout(), 'secondary', ...
                ['Where every electrode sits, drawn on a head (scalp) or a skull (rodent, mm from bregma): from the ' ...
                 'positions in the files, from the channel names on the 10-5 system, or from a positions file ' ...
                 '(.elc, .sfp, .loc, .ced, .xyz, .elp, .bvef, .csv, .tsv, .txt). Check it, change it if needed and ' ...
                 'confirm it.']);
            app.LayoutBtn.Layout.Row = 5; app.LayoutBtn.Layout.Column = [1 2];
            app.LayoutInfo = infoLabel(g, '', ['Electrode layout of the first participant: how many channels have a ' ...
                'position and where it comes from']);
            app.LayoutInfo.Layout.Row = 6; app.LayoutInfo.Layout.Column = [1 2];

            % --- 2 Clean recordings ---
            [p, g, heights{2}] = stepCard(left, 2, 'Clean recordings', {ch, ch, bh, ch, ch, ch, ch, ch, bh, 48});
            p.Layout.Row = 2;
            app.CleanParticipantDrop = addField(g, 2, 'Participant', 'dropdown', {{'(none)'}, '(none)'}, ...
                'Whose bad channels the field below shows (each participant has their own)');
            app.CleanParticipantDrop.ValueChangedFcn = @(~,~)app.showBadChannels();
            app.BadEdit = addField(g, 3, 'Bad channels', 'text', '', ...
                ['Channels of this participant to leave out (flat, very noisy or detached), separated by commas, ' ...
                 'e.g. T7 or T7, FT9 (any case). They are left out of the average reference, the trial rejection, ' ...
                 'the ERPs and the measures. Empty = none.']);
            app.BadEdit.ValueChangedFcn = @(~,~)app.onBadEdited();
            app.SuggestBtn = UIKit.button(g, 'Suggest', @(~,~)app.suggestBadChannels(), 'secondary', ...
                ['Fill in the flat or very noisy channels of this participant (their spread lies far from that of ' ...
                 'the other channels). Only a suggestion: look at the data and change the list if needed.']);
            app.SuggestBtn.Layout.Row = 4; app.SuggestBtn.Layout.Column = 2;
            app.HighPassEdit = addField(g, 5, 'High-pass (Hz)', 'numeric', 0.1, ...
                ['Removes slow drifts and electrode offsets below this frequency (0 = off). 0.1 Hz is usual for ERPs; ' ...
                 'higher values can distort slow components such as the P300.'], [0 10000]);
            app.HighPassEdit.ValueChangedFcn = @(~,~)app.updateControls();
            app.LowPassEdit = addField(g, 6, 'Low-pass (Hz)', 'numeric', 30, ...
                'Removes fast activity and line noise above this frequency (0 = off). 30 or 40 Hz is usual for ERPs.', ...
                [0 10000]);
            app.LowPassEdit.ValueChangedFcn = @(~,~)app.updateControls();
            app.NotchDrop = addField(g, 7, 'Notch', 'dropdown', {app.NotchItems, app.NotchItems{1}}, ...
                ['Removes the mains line noise (50 Hz in Europe, 60 Hz in the Americas) and those of its multiples ' ...
                 'that lie below half the sampling rate and below the low-pass. Usually not needed when the ' ...
                 'low-pass is well below it.']);
            app.NotchDrop.ValueChangedFcn = @(~,~)app.updateControls();
            app.ReferenceDrop = addField(g, 8, 'Reference', 'dropdown', {app.ReferenceModes, app.ReferenceModes{1}}, ...
                ['As recorded: keep the reference of the file. Average: the mean of the good channels (needs many ' ...
                 'channels over the whole head). Linked mastoids: the mean of TP9 and TP10 (or M1 and M2, A1 and A2). ' ...
                 'Channels: the mean of the channels typed below.']);
            app.ReferenceDrop.ValueChangedFcn = @(~,~)app.updateControls();
            app.ReferenceChannelsEdit = addField(g, 9, 'Reference channels', 'text', '', ...
                'Only for Reference = Channels: channel names separated by commas, e.g. Cz or TP9, TP10 (their mean)');
            app.ReferenceChannelsEdit.ValueChangedFcn = @(~,~)app.updateControls();
            app.ApplyCleanBtn = UIKit.button(g, 'Apply', @(~,~)app.applyCleaning(), 'secondary', ...
                ['Mark the bad channels, filter and re-reference every participant, always starting again from the ' ...
                 'files as read. The trials (step 3) and every later result are made again afterwards.']);
            app.ApplyCleanBtn.Layout.Row = 10; app.ApplyCleanBtn.Layout.Column = [1 2];
            app.CleanInfo = infoLabel(g, '', 'What cleaning did');
            app.CleanInfo.Layout.Row = 11; app.CleanInfo.Layout.Column = [1 2];

            % --- 3 Trials ---
            [p, g, heights{3}] = stepCard(left, 3, 'Trials', {ch, ch, ch, ch, ch, ch, bh, 48});
            p.Layout.Row = 3;
            app.EventsEdit = addField(g, 2, 'Events and names', 'text', '', ...
                ['Only for continuous recordings: the events to cut trials around, separated by commas, each with ' ...
                 'its condition name, e.g. S 1 = Standard, S 2 = Target (any case and spacing). An event without ' ...
                 '"= name" keeps its type as the condition. Empty = every event, named by its type.']);
            app.EventsEdit.ValueChangedFcn = @(~,~)app.updateControls();
            app.TrialFromEdit = addField(g, 3, 'Trial from (ms)', 'numeric', -200, ...
                ['Only for continuous recordings: where each trial starts, relative to its event (negative = before ' ...
                 'the event, so there is a baseline)'], [-60000 60000]);
            app.TrialToEdit = addField(g, 4, 'Trial to (ms)', 'numeric', 800, ...
                'Only for continuous recordings: where each trial ends, relative to its event', [-60000 60000]);
            app.RejectCb = addField(g, 5, 'Reject trials', 'checkbox', false, ...
                ['Leave out the trials whose amplitude is too large on any good channel (blinks, movements, ' ...
                 'electrode pops). Mark noisy channels bad first (step 2), or they reject every trial.']);
            app.RejectCb.ValueChangedFcn = @(~,~)app.updateControls();
            app.PeakToPeakEdit = addField(g, 6, ['Peak-to-peak (' char(181) 'V)'], 'numeric', 100, ...
                ['Reject a trial when the largest minus the smallest value of a good channel exceeds this (0 = off). ' ...
                 '100 uV is usual for scalp EEG after filtering.'], [0 1e6]);
            app.AbsoluteEdit = addField(g, 7, ['Absolute (' char(181) 'V)'], 'numeric', 0, ...
                'Reject a trial when any value of a good channel lies further than this from 0 uV (0 = off)', [0 1e6]);
            app.CutBtn = UIKit.button(g, 'Cut into trials', @(~,~)app.cutIntoTrials(), 'secondary', ...
                ['Cut every continuous recording into trials around its events (after step 2 when it was applied), ' ...
                 'then reject trials when ticked. The condition of a trial is the name of its event. Events too ' ...
                 'close to the start or end are left out (the Overview says how many).']);
            app.CutBtn.Layout.Row = 8; app.CutBtn.Layout.Column = [1 2];
            app.CutInfo = infoLabel(g, '', 'Trials per participant and what the rejection left out');
            app.CutInfo.Layout.Row = 9; app.CutInfo.Layout.Column = [1 2];

            % --- 4 ERPs ---
            [p, g, heights{4}] = stepCard(left, 4, 'ERPs', {ch, ch, ch, ch, bh, 34});
            p.Layout.Row = 4;
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
                 'Empty = the average of all channels (flat after an average reference); new files fill in ' ...
                 'Pz, Cz, Fz or Oz when they have one.']);
            app.ShowBtn = UIKit.button(g, 'Show ERPs', @(~,~)app.showERPs(), 'secondary', ...
                ['Average the trials of each condition for every participant (and across participants) and plot them. ' ...
                 'Use the bar above the plot to switch participant, view and conditions.']);
            app.ShowBtn.Layout.Row = 6; app.ShowBtn.Layout.Column = [1 2];
            app.ErpInfo = infoLabel(g, '', 'What the ERPs are made of');
            app.ErpInfo.Layout.Row = 7; app.ErpInfo.Layout.Column = [1 2];

            % --- 5 Measure ---
            [p, g, heights{5}] = stepCard(left, 5, 'Measure', {ch, ch, ch, ch, ch, bh, 48});
            p.Layout.Row = 5;
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
                'Channels to measure at, separated by commas (averaged). Empty = the channels of step 4.');
            app.MeasureBtn = UIKit.button(g, 'Measure', @(~,~)app.measure(), 'secondary', ...
                'One number per participant and condition, in the Measures tab; the window is shaded on the plot');
            app.MeasureBtn.Layout.Row = 7; app.MeasureBtn.Layout.Column = 1;
            app.MapsBtn = UIKit.button(g, 'Scalp maps', @(~,~)app.showScalpMaps(), 'secondary', ...
                ['The mean voltage of every electrode in this window, drawn on the head (or skull) for each ' ...
                 'condition and for A minus B, in the plot above (Show: Scalp maps). Uses the electrode layout ' ...
                 'of step 1; bad channels are left out.']);
            app.MapsBtn.Layout.Row = 7; app.MapsBtn.Layout.Column = 2;
            app.MeasureInfo = infoLabel(g, '', 'Result of the measure and its checks');
            app.MeasureInfo.Layout.Row = 8; app.MeasureInfo.Layout.Column = [1 2];

            % --- 6 Statistics ---
            [p, g, heights{6}] = stepCard(left, 6, 'Statistics', {ch, bh, 48});
            p.Layout.Row = 6;
            app.MethodDrop = addField(g, 2, 'Method', 'dropdown', {{'Parametric', 'Nonparametric'}, 'Parametric'}, ...
                ['Parametric: paired t-test (2 conditions) or repeated-measures ANOVA (3 or more). Nonparametric: ' ...
                 'Wilcoxon signed-rank or Friedman test (fewer assumptions, less power). The other is run as a check.']);
            app.StatsBtn = UIKit.button(g, 'Compare conditions', @(~,~)app.compareConditions(), 'secondary', ...
                ['Compare the measured values between conditions, within participants (each participant is matched ' ...
                 'with themself across conditions). Needs 2 or more participants.']);
            app.StatsBtn.Layout.Row = 3; app.StatsBtn.Layout.Column = [1 2];
            app.StatsInfo = infoLabel(g, '', 'Result of the test');
            app.StatsInfo.Layout.Row = 4; app.StatsInfo.Layout.Column = [1 2];

            % --- 7 Time-frequency ---
            [p, g, heights{7}] = stepCard(left, 7, ['Time' char(8211) 'frequency'], {ch, ch, ch, ch, ch, bh, 120});
            p.Layout.Row = 7;
            [app.TFFromEdit, app.TFToEdit] = rangeRow(g, 2, 'Frequencies (Hz)', 4, 40, ...
                ['Lowest and highest frequency, in 1 Hz steps (below half the sampling rate). Low frequencies ' ...
                 'need long trials: their wavelets are long.'], [0 100000]);
            app.TFCyclesEdit = addField(g, 3, 'Wavelet cycles', 'numeric', 3, ...
                ['Cycles of each Morlet wavelet. Fewer cycles: shorter wavelets, so values nearer the trial ' ...
                 'edges and finer timing, but coarser frequencies. 3 suits trials of about 1 s; 5 to 7 longer ' ...
                 'trials.'], [0.5 50]);
            [app.TFBaseFromEdit, app.TFBaseToEdit] = rangeRow(g, 4, 'Baseline (ms)', -200, 0, ...
                ['Reference window before the event: ERSP is the power in dB against its mean power there, ' ...
                 'band power the % change from it (each condition against its own baseline)'], [-60000 60000]);
            app.TFChannelsEdit = addField(g, 5, 'Channels', 'text', '', ...
                ['Channels separated by commas, e.g. Oz or O1, Oz, O2 (any case; their power is averaged). ' ...
                 'Empty = the channels of step 4.']);
            bands = TimeFrequency.defaultBands();
            bandItems = arrayfun(@(b) sprintf('%s (%g%s%g Hz)', b.name, b.range(1), char(8211), b.range(2)), ...
                bands, 'UniformOutput', false);
            app.TFBandDrop = addField(g, 6, 'Band', 'dropdown', {bandItems, bandItems{3}}, ...
                ['Frequency band of Band power (Show: Band power): the mean power over its frequencies, as % ' ...
                 'change from the baseline. Band limits are conventions; they differ between labs and species.']);
            app.TFBtn = UIKit.button(g, ['Time' char(8211) 'frequency'], @(~,~)app.showTimeFrequency(), 'secondary', ...
                ['Wavelet power of every trial at these channels, per participant and condition (and across ' ...
                 'participants): ERSP, phase locking (ITPC) and band power, in the plot above (Show). A value is ' ...
                 'shown only where the whole wavelet lies inside the trial.']);
            app.TFBtn.Layout.Row = 7; app.TFBtn.Layout.Column = [1 2];
            app.TFInfo = infoLabel(g, '', ['What the time' char(8211) 'frequency is made of, and what the trial ' ...
                'length leaves blank']);
            app.TFInfo.Layout.Row = 8; app.TFInfo.Layout.Column = [1 2];

            % --- 8 Save ---
            [p, g, heights{8}] = stepCard(left, 8, 'Save', {bh, UIKit.sessionButtonsHeight()});
            p.Layout.Row = 8;
            app.ExportBtn = UIKit.button(g, ['Export results' char(8230)], @(~,~)app.exportDialog(), 'secondary', ...
                ['.csv: one row per participant and condition (value in uV, latency in s, trials, edge warning), ' ...
                 'ready for a spreadsheet or statistics program; .mat: everything (ERPs, measures, statistics)']);
            app.ExportBtn.Layout.Row = 2; app.ExportBtn.Layout.Column = [1 2];
            app.SessionBtns = UIKit.sessionButtons(g, app);
            app.SessionBtns.Grid.Layout.Row = 3; app.SessionBtns.Grid.Layout.Column = [1 2];
            heights{9} = '1x';
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
                 'channel of one condition (chosen channels in colour). Difference wave: condition A minus B. ' ...
                 'Scalp maps: the mean voltage in the window of step 5 over the head, per condition and A minus B. ' ...
                 'Time' char(8211) 'frequency (ERSP), Phase locking (ITPC), Band power: the results of step 7.']);
            barLabel(bar, 'Condition');
            app.CondADrop = uidropdown(bar, 'Items', {'(none)'}, 'Value', '(none)', ...
                'ValueChangedFcn', @(~,~)app.plotERP(), 'Tooltip', ...
                'Condition shown (All channels) or A (Difference wave; the A minus B map of Scalp maps and ERSP)');
            barLabel(bar, 'minus');
            app.CondBDrop = uidropdown(bar, 'Items', {'(none)'}, 'Value', '(none)', ...
                'ValueChangedFcn', @(~,~)app.plotERP(), 'Tooltip', ...
                'Condition B, subtracted from A (Difference wave; the A minus B map of Scalp maps and ERSP)');
            plotPanel = uipanel(right, 'BackgroundColor', T.cardBg, 'BorderType', 'line', 'HighlightColor', T.cardBorder);
            gp = uigridlayout(plotPanel, [2 1], 'RowHeight', {'1x', 0}, 'Padding', [4 4 4 4], 'RowSpacing', 0, ...
                'BackgroundColor', T.cardBg);
            app.PlotGrid = gp;
            app.ErpPanel = uipanel(gp, 'BorderType', 'none', 'BackgroundColor', T.cardBg);
            app.ErpPanel.Layout.Row = 1;
            app.AxERP = uiaxes(uigridlayout(app.ErpPanel, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', T.cardBg));
            app.AxERP.Toolbar.Visible = 'on';
            app.MapPanel = uipanel(gp, 'BorderType', 'none', 'BackgroundColor', T.cardBg, 'Visible', 'off');
            app.MapPanel.Layout.Row = 2;
            UIKit.emptyAxes(app.AxERP, 'Load EEG files (or Try demo data) to begin');

            app.Tabs = uitabgroup(right);
            to = uitab(app.Tabs, 'Title', 'Overview', 'BackgroundColor', T.cardBg);
            g1 = uigridlayout(to, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.OverviewText = uitextarea(g1, 'Value', {'Load EEG files to see what they hold and what was done to them.'}, ...
                'Editable', 'off', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            tm = uitab(app.Tabs, 'Title', 'Measures', 'BackgroundColor', T.cardBg);
            g2 = uigridlayout(tm, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.MeasuresTable = uitable(g2, 'RowName', {}, 'FontSize', T.fontSmall + 1, 'ColumnName', ...
                {'Participant', 'Condition', ['Value (' char(181) 'V)'], 'Latency (ms)', 'Trials', 'Check'});
            ts = uitab(app.Tabs, 'Title', 'Statistics', 'BackgroundColor', T.cardBg);
            g3 = uigridlayout(ts, [2 1], 'RowHeight', {'1x', '1x'}, 'Padding', [6 6 6 6], 'RowSpacing', 6, ...
                'BackgroundColor', T.cardBg);
            app.StatsText = uitextarea(g3, 'Value', {'Measure (step 5), then Compare conditions (step 6).'}, ...
                'Editable', 'off', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            app.StatsTable = uitable(g3, 'RowName', {}, 'FontSize', T.fontSmall + 1, 'ColumnName', ...
                {'Comparison', ['Difference (' char(181) 'V)'], '95% CI', 'p (Holm)', 'Test'});
            app.ChecksUI = UIKit.checksTab(app.Tabs, ['Quality checks of the trials appear here after Cut into ' ...
                'trials / Apply rejection (step 3), Show ERPs (step 4) or Measure (step 5); those of the test after ' ...
                'Compare conditions (step 6).']);
            app.ChecksTab = app.ChecksUI.Tab;
            app.ChecksTable = app.ChecksUI.Table;
            app.ChecksText = app.ChecksUI.Text;
            app.CheckRows = QualityChecks.none();

            UIKit.setStatus(app.StatusLabel, ['Step 1: load one EEG file per participant (or Try demo data).'], 'info');
        end

        %% ----------------------------------------------------------------
        %% Step 1: load
        %% loadDialog - Choose one or more EEG files
        function loadDialog(app)
            start = ProjectManager.getImportDir();
            if isempty(start), start = pwd; end
            [f, p] = uigetfile({'*.set;*.mat;*.vhdr;*.edf;*.bdf;*.xdf', ...
                'EEG (EEGLAB .set, FieldTrip or plain .mat, BrainVision .vhdr, EDF / BDF, XDF)'}, ...
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
            UIKit.setStatus(app.StatusLabel, ['Demo loaded: 8 participants, already cleaned and cut into trials. ' ...
                'Next: Show ERPs (step 4), then Measure the P300 at Pz from 300 to 400 ms (step 5).'], 'success');
        end

        %% loadRawDemo - 3 raw continuous BrainVision recordings (core/demo/demoEEG)
        % Fills in the suggested cleaning and trial settings without applying them.
        function ok = loadRawDemo(app)
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
            ok = app.openFiles({f.raw.brainvision});
            if ~ok, return; end
            app.Generator = 'demoEEGraw';
            for k = 1:numel(app.Loaded)
                app.suggestBadChannels(k);
            end
            app.CleanParticipantDrop.Value = app.Names{1};
            app.showBadChannels();
            app.setFilters(0.1, 30, 'off');
            app.setReference('average');
            app.setEvents('S 1 = Standard, S 2 = Target, S 3 = Novel');
            app.setTrialWindow([-0.2 0.8]);
            app.setRejection(true, 100, 0);
            app.setChannels({'Pz'});
            app.setMeasure('mean', 'positive', [0.3 0.4], {'Pz'});
            bad = unique([app.BadChannels{:}]);
            if isempty(bad), badText = 'no channel'; else, badText = EEGSource.listText(bad); end
            UIKit.setStatus(app.StatusLabel, sprintf(['Raw demo loaded: %d continuous recordings; %s suggested as ' ...
                'bad. Next: check the settings and Apply (step 2), then Cut into trials (step 3).'], ...
                numel(app.Loaded), badText), 'success');
        end

        %% loadFaultsDemo - One participant with the faults of the quality checks (DemoData 'eegFaults')
        % An EEGLAB dataset cut into trials (core/demo/demoEEG faults):
        % blinks in most Target trials, 8 noisy or flat channels, Pz
        % interpolated. Fills in the suggested bad channels, the 100 uV
        % rejection and the P300 measure at Pz without applying them.
        function ok = loadFaultsDemo(app)
            DemoData.ensureDemoPath();
            dlg = UIKit.busy(app.UIFig, 'Making the demo EEG (the first time takes a few seconds)…');
            try
                p = DemoData.file('eegFaults');
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Demo not made: %s', ME.message), 'error');
                ok = false;
                return;
            end
            UIKit.done(dlg);
            ok = app.openFiles({p});
            if ~ok, return; end
            bad = app.suggestBadChannels(1);
            app.setRejection(true, 100, 0);
            app.setChannels({'Pz'});
            app.setMeasure('mean', 'positive', [0.3 0.4], {'Pz'});
            UIKit.setStatus(app.StatusLabel, sprintf(['Faults demo loaded: one participant with blinks in most ' ...
                'Target trials; %d channels suggested as bad. Next: Apply rejection (step 3), then read the ' ...
                'Checks tab.'], numel(bad)), 'success');
        end

        %% setLayout - Electrode layout of the recordings (made from participant 1)
        % Name, Value: 'Source' 'auto' (the files' positions, the other
        % channels by name on the 10-5 system) | 'template' (by name only) |
        % 'file' (positions only); 'PositionsFile' a file of electrode
        % positions (core/io/readElectrodes.m) used instead of the files'
        % positions ('' = none; dropped with Source 'template'; given without
        % Source it turns 'template' into 'auto'); 'Edits' struct array
        % label / as / ap / ml of placements by hand (as: a 10-5 name; ap, ml:
        % mm from bregma; [] = none); 'Confirm' true / false. Options left out
        % keep their value; a change without 'Confirm' leaves the layout not
        % confirmed. Returns false, with the reason in the status bar and the
        % layout unchanged, when the file or the placements cannot be used.
        function ok = setLayout(app, varargin)
            ok = false;
            if isempty(app.Loaded)
                UIKit.setStatus(app.StatusLabel, 'Load EEG files first (step 1).', 'warning');
                return;
            end
            ls = app.LayoutSettings;
            confirm = [];
            try
                if mod(numel(varargin), 2) ~= 0
                    error('NeuroAnalyzer:eeg:badOption', 'Layout options must come in Name, Value pairs.');
                end
                given = {};
                for k = 1:2:numel(varargin)
                    name = lower(char(varargin{k}));
                    v = varargin{k + 1};
                    given{end + 1} = name; %#ok<AGROW>
                    switch name
                        case 'source'
                            v = lower(strtrim(char(v)));
                            if ~any(strcmp(v, {'auto', 'template', 'file'}))
                                error('NeuroAnalyzer:eeg:badOption', ...
                                    'Unknown layout source ''%s'' (use auto, template or file).', v);
                            end
                            ls.source = v;
                        case 'positionsfile'
                            ls.positionsFile = strtrim(char(v));
                        case 'edits'
                            ls.edits = layoutEdits(v);
                        case 'confirm'
                            confirm = logical(v);
                        otherwise
                            error('NeuroAnalyzer:eeg:badOption', ['Unknown layout option ''%s'' (use Source, ' ...
                                'PositionsFile, Edits or Confirm).'], char(varargin{k}));
                    end
                end
                if isempty(ls.positionsFile), ls.positionsFile = ''; end
                if ~isempty(ls.positionsFile) && strcmp(ls.source, 'template')
                    if any(strcmp(given, 'source')), ls.positionsFile = ''; else, ls.source = 'auto'; end
                end
                changed = ~isequaln(rmfield(ls, 'confirmed'), rmfield(app.LayoutSettings, 'confirmed'));
                if changed || isempty(app.Layout)
                    [L, P] = buildLayout(app.Loaded{1}, ls);
                else
                    L = app.Layout;
                    P = app.LayoutPositions;
                end
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Electrode layout not changed: %s', ME.message), 'error');
                return;
            end
            if isempty(confirm), confirm = ls.confirmed && ~changed; end
            ls.confirmed = logical(confirm(1));
            L.confirmed = ls.confirmed;
            app.Layout = L;
            app.LayoutSettings = ls;
            app.LayoutPositions = P;
            if ~isempty(app.LayoutDlg)              % an open layout dialog shows the layout now in use
                app.LayoutDlg.draft = ls;
                app.LayoutDlg.positions = P;
                app.LayoutDlg.L = L;
                app.showLayoutDraft();
            end
            app.showLayoutInfo();
            app.fillOverview();
            if strcmp(app.ViewDrop.Value, app.Views{4}) && ~isempty(app.ERPs)
                app.plotMaps(true);             % the maps shown, on the new layout
            end
            if L.confirmed
                UIKit.setStatus(app.StatusLabel, ['Electrode layout confirmed: ' L.summary], 'success');
            else
                UIKit.setStatus(app.StatusLabel, ['Electrode layout: ' L.summary ' Not confirmed yet.'], 'info');
            end
            ok = true;
        end

        %% openLayout - The Electrode layout dialog (not modal); returns its figure
        % Left: the drawing (EEGLayout.plot); right: the Source list,
        % Positions file..., the table (scalp: Channel | Placed from | As |
        % Status, As editable; skull: Channel | AP (mm) | ML (mm) | Status, AP
        % and ML editable), the summary and notes, then Cancel and Use this
        % layout. Changes are drawn at once but used only after Use this
        % layout, which also confirms the layout.
        function fig = openLayout(app)
            fig = [];
            if isempty(app.Loaded)
                UIKit.setStatus(app.StatusLabel, 'Load EEG files first (step 1).', 'warning');
                return;
            end
            if ~isempty(app.LayoutFig) && isvalid(app.LayoutFig)
                fig = app.LayoutFig;
                figure(fig);
                return;
            end
            T = UITheme;
            D = UIKit.dialog('Electrode layout', ['Where every electrode sits: check it, change it if needed, ' ...
                'then Use this layout'], 'EEG Analysis', [1000 660]);
            fig = D.Fig;
            fig.WindowStyle = 'normal';         % not modal: the window stays usable
            fig.Resize = 'on';
            fig.CloseRequestFcn = @(~,~)app.closeLayout();
            D.Body.Scrollable = 'off';
            D.Body.ColumnWidth = {'1x', 420};
            D.Body.RowHeight = {'1x'};
            plotPanel = uipanel(D.Body, 'BackgroundColor', T.cardBg, 'BorderType', 'line', ...
                'HighlightColor', T.cardBorder);
            plotPanel.Layout.Row = 1; plotPanel.Layout.Column = 1;
            gp = uigridlayout(plotPanel, [1 1], 'Padding', [4 4 4 4], 'BackgroundColor', T.cardBg);
            ax = uiaxes(gp);
            right = uigridlayout(D.Body, [5 2], 'ColumnWidth', {64, '1x'}, ...
                'RowHeight', {T.controlHeight, T.buttonHeight, '1x', 130, 34}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 8, 'ColumnSpacing', 8, 'BackgroundColor', T.bgGray);
            right.Layout.Row = 1; right.Layout.Column = 2;
            drop = addField(right, 1, 'Source', 'dropdown', {app.LayoutSources, app.LayoutSources{1}}, ...
                ['From the files: the positions stored in the recording, the other channels by their names on ' ...
                 'the 10-5 system. By name: every channel on the 10-5 position of its name (idealized head). ' ...
                 'From a positions file: the positions of a cap or digitizer file.']);
            drop.ValueChangedFcn = @(~,~)app.onLayoutSource();
            fileBtn = UIKit.button(right, ['Positions file' char(8230)], @(~,~)app.choosePositionsFile(), ...
                'secondary', ['A file of electrode positions: .elc, .sfp, .loc / .locs, .ced, .xyz, .elp (BESA), ' ...
                '.bvef (BrainVision), .csv, .tsv or .txt (name with x, y, z; theta and phi; or ap and ml for a ' ...
                'rodent). Channels are matched by name (any case; T3 is read as T7).']);
            fileBtn.Layout.Row = 2; fileBtn.Layout.Column = [1 2];
            tbl = uitable(right, 'RowName', {}, 'FontSize', T.fontSmall + 1, ...
                'CellEditCallback', @(~, evt)app.onLayoutEdit(evt), 'Tooltip', ...
                ['As: type a 10-5 name to place a channel there (empty = no position). AP / ML: mm from ' ...
                 'bregma (anterior +, right +).']);
            tbl.Layout.Row = 3; tbl.Layout.Column = [1 2];
            txt = uitextarea(right, 'Value', {''}, 'Editable', 'off', 'FontSize', T.fontSmall, ...
                'FontColor', T.sectionTitleColor);
            txt.Layout.Row = 4; txt.Layout.Column = [1 2];
            msg = uilabel(right, 'Text', '', 'FontSize', T.fontSmall, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', 'Interpreter', 'none');
            msg.Layout.Row = 5; msg.Layout.Column = [1 2];
            cancelBtn = UIKit.button(D.Buttons, 'Cancel', @(~,~)app.closeLayout(), 'secondary', ...
                'Close without changing the layout');
            useBtn = UIKit.button(D.Buttons, 'Use this layout', @(~,~)app.useLayout(), 'primary', ...
                'Use the layout shown and mark it as checked');
            D.Buttons.ColumnWidth = {'1x', 100, 150};
            d = struct();
            d.Axes = ax;
            d.SourceDrop = drop;
            d.FileBtn = fileBtn;
            d.Table = tbl;
            d.Text = txt;
            d.Message = msg;
            d.CancelBtn = cancelBtn;
            d.UseBtn = useBtn;
            d.draft = app.LayoutSettings;       % what the dialog shows (used after Use this layout)
            d.positions = app.LayoutPositions;
            d.L = app.Layout;
            app.LayoutFig = fig;
            app.LayoutDlg = d;
            app.showLayoutDraft();
        end

        %% ----------------------------------------------------------------
        %% Step 2: clean recordings
        %% setBadChannels - Bad channels of one participant (index or name; names cell or 'T7, FT9')
        function setBadChannels(app, participant, names)
            k = app.participantIndex(participant);
            app.BadChannels{k} = channelList(names);
            if app.cleanIndex() == k, app.BadEdit.Value = channelText(app.BadChannels{k}); end
            app.updateControls();
        end

        %% suggestBadChannels - Fill in the flat or noisy channels of one participant (default: the shown one)
        function names = suggestBadChannels(app, participant)
            names = {};
            if isempty(app.Loaded), return; end
            if nargin < 2 || isempty(participant), k = app.cleanIndex(); else, k = app.participantIndex(participant); end
            try
                [names, info] = EEGAnalysis.suggestBadChannels(app.Loaded{k});
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('No suggestion (%s): %s', app.Names{k}, ME.message), 'error');
                return;
            end
            names = channelList(names);
            app.SuggestRule = info.rule;
            app.CleanParticipantDrop.Value = app.Names{k};
            app.setBadChannels(k, names);
            if isempty(names), found = 'none'; else, found = EEGSource.listText(names); end
            UIKit.setStatus(app.StatusLabel, sprintf('Suggested for %s: %s. %s', app.Names{k}, found, info.rule), 'info');
        end

        %% setFilters - High-pass and low-pass (Hz, 0 or [] = off); notch 'off' | 50 | 60
        function setFilters(app, highPass, lowPass, notch)
            if isempty(highPass), highPass = 0; end
            if isempty(lowPass), lowPass = 0; end
            app.HighPassEdit.Value = highPass;
            app.LowPassEdit.Value = lowPass;
            if nargin >= 4
                if isstring(notch), notch = char(notch); end
                if ischar(notch) && strcmpi(strtrim(notch), 'off'), notch = 0;
                elseif ischar(notch), notch = str2double(notch);
                elseif isempty(notch), notch = 0;
                end
                k = find(isequal(notch, 0), 1);
                if isempty(k), k = 1 + find([50 60] == notch, 1); end
                if isempty(k)
                    error('NeuroAnalyzer:eeg:badOption', 'Unknown notch: use ''off'', 50 or 60 (Hz).');
                end
                app.NotchDrop.Value = app.NotchItems{k};
            end
            app.updateControls();
        end

        %% setReference - 'as recorded' | 'average' | 'linked mastoids' | 'channels' (+ names)
        function setReference(app, mode, channels)
            k = find(strcmpi(app.ReferenceModes, strtrim(mode)), 1);
            if isempty(k)
                error('NeuroAnalyzer:eeg:badOption', 'Unknown reference "%s": use %s.', mode, ...
                    EEGSource.listText(lower(app.ReferenceModes)));
            end
            app.ReferenceDrop.Value = app.ReferenceModes{k};
            if nargin >= 3, app.ReferenceChannelsEdit.Value = channelText(channels); end
            app.updateControls();
        end

        %% applyCleaning - Bad channels, filters and reference, from the files as read
        function ok = applyCleaning(app)
            ok = false;
            if isempty(app.Loaded)
                UIKit.setStatus(app.StatusLabel, 'Load EEG files first (step 1).', 'warning');
                return;
            end
            cs = app.currentCleaning();
            cs.notchFreqs = [];
            cs.filterText = {};
            cs.suggestRule = app.SuggestRule;
            cs.applied = true;
            eegs = app.Loaded;
            dlg = UIKit.busy(app.UIFig, 'Cleaning the recordings (filtering takes a few seconds)…');
            try
                for k = 1:numel(eegs)
                    e = EEGAnalysis.markBad(eegs{k}, cs.bad{k});
                    nf = EEGAnalysis.notchFrequencies(cs.notch, e.fs, cs.lowPass);
                    if cs.highPass > 0 || cs.lowPass > 0 || ~isempty(nf)
                        [e, info] = EEGAnalysis.filter(e, 'HighPass', positiveOrEmpty(cs.highPass), ...
                            'LowPass', positiveOrEmpty(cs.lowPass), 'Notch', nf);
                        if k == 1
                            cs.notchFreqs = nf;
                            d = [info.band, info.notch];
                            cs.filterText = arrayfun(@(x) EEGAnalysis.describeFilter(x), d, 'UniformOutput', false);
                        end
                    end
                    switch cs.referenceMode
                        case 'average'
                            e = EEGAnalysis.rereference(e, 'average');
                        case 'linked mastoids'
                            e = EEGAnalysis.rereference(e, EEGAnalysis.mastoidChannels(e.labels));
                        case 'channels'
                            if isempty(cs.referenceChannels)
                                error('NeuroAnalyzer:eeg:badOption', 'Type the reference channels (e.g. Cz or TP9, TP10).');
                            end
                            e = EEGAnalysis.rereference(e, cs.referenceChannels);
                    end
                    eegs{k} = e;
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Not cleaned (%s): %s', app.Names{k}, ME.message), 'error');
                return;
            end
            UIKit.done(dlg);
            app.Cleaned = eegs;
            app.CleanSettings = cs;
            % Trials and every later result are made again from the cleaned data
            epoched = eegs{1}.isEpoched;
            if epoched, app.EEGs = eegs; else, app.EEGs = {}; end
            app.TrialSettings = [];
            app.TrialWindow = [];
            app.Rejections = [];
            app.clearResults();
            app.CleanInfo.Text = cleaningText(cs, numel(eegs));
            app.CleanInfo.FontColor = UITheme.success;
            if epoched && ~isempty(cs.filterText)
                app.CleanInfo.Text = [app.CleanInfo.Text ' Filtered trial by trial: filtering the continuous ' ...
                    'recording before cutting it is better (the Overview says when a filter is longer than a trial).'];
                app.CleanInfo.FontColor = UITheme.warning;
            end
            if epoched
                app.CutInfo.Text = ['Cleaned trials in use. Tick Reject trials and Apply rejection to leave out ' ...
                    'noisy trials.'];
            else
                app.CutInfo.Text = 'Cleaned: cut the recordings into trials again.';
            end
            app.CutInfo.FontColor = UITheme.warning;
            app.fillOverview();
            app.fillConditionDrops();
            app.plotERP();
            app.updateControls();
            if epoched
                UIKit.setStatus(app.StatusLabel, ['Trials cleaned. Next: reject trials (step 3, optional) or ' ...
                    'Show ERPs (step 4).'], 'success');
            else
                UIKit.setStatus(app.StatusLabel, 'Recordings cleaned. Next: Cut into trials (step 3).', 'success');
            end
            ok = true;
        end

        %% ----------------------------------------------------------------
        %% Step 3: trials
        %% setEvents - 'S 1 = Standard, S 2 = Target' ('' = every event, named by its type)
        function setEvents(app, txt)
            app.EventsEdit.Value = char(txt);
            app.updateControls();
        end

        %% setTrialWindow - [from to] in s around each event (continuous recordings)
        function setTrialWindow(app, w)
            app.TrialFromEdit.Value = w(1) * 1000;
            app.TrialToEdit.Value = w(2) * 1000;
        end

        %% setRejection - Reject trials on / off; thresholds in uV (0 or [] = off)
        function setRejection(app, on, peakToPeak, absolute)
            app.RejectCb.Value = logical(on);
            if nargin >= 3
                if isempty(peakToPeak), peakToPeak = 0; end
                app.PeakToPeakEdit.Value = peakToPeak;
            end
            if nargin >= 4
                if isempty(absolute), absolute = 0; end
                app.AbsoluteEdit.Value = absolute;
            end
            app.updateControls();
        end

        %% cutIntoTrials - Cut every continuous recording around its events, then reject trials
        % Starts from the cleaned data (step 2) when it was applied, else from the files as read
        % with the bad channels of step 2 marked.
        function ok = cutIntoTrials(app)
            ok = false;
            if isempty(app.Loaded), return; end
            ts = app.currentTrials();
            if ~isempty(ts.problems)
                UIKit.setStatus(app.StatusLabel, sprintf(['Write each event as "type = name" (e.g. S 1 = ' ...
                    'Standard): %s.'], EEGSource.listText(strcat('"', ts.problems, '"'))), 'error');
                return;
            end
            ts = rmfield(ts, 'problems');
            if ts.reject && ts.peakToPeak <= 0 && ts.absolute <= 0
                UIKit.setStatus(app.StatusLabel, ['Give a peak-to-peak or an absolute threshold, or untick ' ...
                    'Reject trials.'], 'warning');
                return;
            end
            cleaned = ~isempty(app.Cleaned);
            if cleaned, eegs = app.Cleaned; else, eegs = app.Loaded; end
            continuous = ~eegs{1}.isEpoched;
            rej = [];
            dlg = UIKit.busy(app.UIFig, 'Making the trials…');
            try
                for k = 1:numel(eegs)
                    % Step 2 not applied: its bad channels still count
                    if ~cleaned, eegs{k} = EEGAnalysis.markBad(eegs{k}, app.BadChannels{k}); end
                    if ~eegs{k}.isEpoched
                        eegs{k} = EEGAnalysis.epoch(eegs{k}, 'Window', ts.window, 'Events', ts.events, ...
                            'Rename', ts.rename);
                    end
                    if ts.reject
                        [eegs{k}, info] = EEGAnalysis.rejectTrials(eegs{k}, 'PeakToPeak', positiveOrEmpty(ts.peakToPeak), ...
                            'Absolute', positiveOrEmpty(ts.absolute));
                        if k == 1, rej = info; else, rej(k) = info; end
                    end
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Not cut into trials (%s): %s', app.Names{k}, ME.message), 'error');
                return;
            end
            UIKit.done(dlg);
            ts.cut = true;
            app.EEGs = eegs;
            app.TrialSettings = ts;
            app.Rejections = rej;
            if continuous, app.TrialWindow = ts.window; else, app.TrialWindow = []; end
            app.clearResults();
            if continuous && ts.window(1) < 0
                app.BaselineFromEdit.Value = ts.window(1) * 1000;
                app.TFBaseFromEdit.Value = ts.window(1) * 1000;
            end
            app.CutInfo.Text = trialsText(eegs, rej, ifelse(continuous, ts.window, []));
            app.CutInfo.FontColor = UITheme.success;
            app.fillOverview();
            app.fillConditionDrops();
            app.plotERP();
            app.updateControls();
            app.updateChecks();
            if isempty(rej)
                what = ifelse(continuous, 'Cut into trials.', 'Every trial kept.');
            else
                what = sprintf('%s; %d of %d trials rejected.', ifelse(continuous, 'Cut into trials', ...
                    'Rejection applied'), sum([rej.total]) - sum([rej.kept]), sum([rej.total]));
            end
            [extra, level] = app.checksStatus('success');
            UIKit.setStatus(app.StatusLabel, [what ' Next: Show ERPs (step 4).' extra], level);
            ok = true;
        end

        %% ----------------------------------------------------------------
        %% Step 4: ERPs
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
            app.ScalpMaps = [];
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
            app.updateChecks();
            plotted = app.plotERP();
            app.updateControls();
            ok = true;
            if ~plotted, return; end    % the status says why the plot is empty
            [extra, level] = app.checksStatus('success');
            UIKit.setStatus(app.StatusLabel, ['ERPs ready. Look at the grand average to choose the time window, ' ...
                'then Measure (step 5).' extra], level);
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

        %% showScalpMaps - Scalp maps of a window: [from to] s (default: the window of step 5)
        % A window given here is also put in step 5. One map per condition and
        % one of A minus B (the conditions of the plot bar), for the participant
        % shown or the grand average, in the plot area (Show: Scalp maps).
        function ok = showScalpMaps(app, w)
            ok = false;
            if isempty(app.ERPs)
                UIKit.setStatus(app.StatusLabel, 'Show the ERPs first (step 4).', 'warning');
                return;
            end
            if nargin >= 2 && ~isempty(w)
                app.WindowFromEdit.Value = w(1) * 1000;
                app.WindowToEdit.Value = w(2) * 1000;
            end
            app.MapSettings = struct('window', [app.WindowFromEdit.Value app.WindowToEdit.Value] / 1000);
            app.ViewDrop.Value = app.Views{4};
            app.updateControls();
            ok = app.plotERP();
        end

        %% ----------------------------------------------------------------
        %% Step 5: measure
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
                UIKit.setStatus(app.StatusLabel, 'Show the ERPs first (step 4).', 'warning');
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
            if strcmp(app.ViewDrop.Value, app.Views{4})     % maps shown: they follow the window measured
                app.MapSettings = struct('window', o.Window);
            end
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
            app.updateChecks();
            app.selectTab('Measures');
            app.plotERP();
            app.updateControls();
            if numel(app.ERPs) > 1
                next = 'Next: Compare conditions (step 6).';
            else
                next = 'Statistics need two or more participants; export the values (step 8).';
            end
            [extra, level] = app.checksStatus(ifelse(nEdge > 0, 'warning', 'success'));
            UIKit.setStatus(app.StatusLabel, [sprintf('Measured %d participant(s). %s', numel(r), next) extra], level);
            ok = true;
        end

        %% ----------------------------------------------------------------
        %% Step 6: statistics
        %% setStatsMethod - 'parametric' | 'nonparametric'
        function setStatsMethod(app, m)
            app.MethodDrop.Value = ifelse(strncmpi(m, 'non', 3), 'Nonparametric', 'Parametric');
        end

        %% compareConditions - Within-participant test of the measured values
        function ok = compareConditions(app)
            ok = false;
            if isempty(app.Measures)
                UIKit.setStatus(app.StatusLabel, 'Measure first (step 5).', 'warning');
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
            o = GroupStats.checkOptions();
            o.labels = repmat({app.Names(all(isfinite(Y), 2))}, 1, numel(conds));
            o.subject = 'participant';
            o.valuesTab = 'the Measures tab';
            o.missingAction = ['A condition with no trials left (all rejected, or none of its events) has no ' ...
                'value: see Trials per condition above and the Overview tab.'];
            res.checkRows = GroupStats.checks(res, o);
            app.StatsResult = res;
            app.fillStats();
            app.updateChecks();
            app.selectTab('Statistics');
            app.updateControls();
            [extra, level] = app.checksStatus('success');
            UIKit.setStatus(app.StatusLabel, [res.summary ' Next: Save (step 8), or the time' char(8211) ...
                'frequency of the trials (step 7).' extra], level);
            ok = true;
        end

        %% ----------------------------------------------------------------
        %% Step 7: time-frequency
        %% setTimeFrequency - [from to] Hz, cycles, baseline [from to] s, channels ({} = those of step 4), band name
        % [] leaves a setting as it is.
        function setTimeFrequency(app, freqs, cycles, baseline, chans, band)
            if nargin >= 2 && ~isempty(freqs)
                app.TFFromEdit.Value = freqs(1);
                app.TFToEdit.Value = freqs(end);
            end
            if nargin >= 3 && ~isempty(cycles), app.TFCyclesEdit.Value = cycles; end
            if nargin >= 4 && ~isempty(baseline)
                app.TFBaseFromEdit.Value = baseline(1) * 1000;
                app.TFBaseToEdit.Value = baseline(2) * 1000;
            end
            if nargin >= 5 && ~(isnumeric(chans) && isempty(chans)), app.TFChannelsEdit.Value = channelText(chans); end
            if nargin >= 6 && ~isempty(band)
                k = find(strncmpi(app.TFBandDrop.Items, band, numel(band)), 1);
                if ~isempty(k), app.TFBandDrop.Value = app.TFBandDrop.Items{k}; end
            end
            app.updateControls();
        end

        %% showTimeFrequency - Wavelet power, ERSP, ITPC and band power of every participant (step 7)
        % Shows the ERSP (Show: Time-frequency) unless another view of step 7 is shown.
        function ok = showTimeFrequency(app)
            ok = false;
            if isempty(app.EEGs)
                UIKit.setStatus(app.StatusLabel, 'Cut the recordings into trials first (step 3).', 'warning');
                return;
            end
            o = app.currentTF();
            f = o.frequencies;
            nyq = app.EEGs{1}.fs / 2;
            if ~(f(1) > 0 && f(2) > f(1) && f(2) < nyq)
                UIKit.setStatus(app.StatusLabel, sprintf(['The frequencies must run from above 0 Hz to a higher ' ...
                    'frequency below half the sampling rate (%g Hz).'], nyq), 'warning');
                return;
            end
            if o.band(1) < f(1) - 1e-9 || o.band(2) > f(2) + 1e-9
                UIKit.setStatus(app.StatusLabel, sprintf(['The %s band (%g to %g Hz) goes beyond the frequencies ' ...
                    '(%g to %g Hz): widen them or choose another band.'], o.bandName, o.band, f), 'warning');
                return;
            end
            freqs = f(1):1:f(2);
            if freqs(end) < f(2) - 1e-9, freqs(end + 1) = f(2); end
            dlg = UIKit.busy(app.UIFig, ['Computing the time' char(8211) 'frequency' char(8230)]);
            try
                tfs = cellfun(@(e) EEGAnalysis.timeFrequency(e, 'Channels', o.channels, 'Frequencies', freqs, ...
                    'Cycles', o.cycles, 'Baseline', o.baseline, 'Bands', o.band, 'BandNames', {o.bandName}), ...
                    app.EEGs, 'UniformOutput', false);
                grand = [];
                if numel(tfs) > 1, grand = EEGAnalysis.grandTimeFrequency(tfs); end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Time%sfrequency not computed: %s', char(8211), ME.message), ...
                    'error');
                return;
            end
            UIKit.done(dlg);
            app.TFs = tfs;
            app.GrandTF = grand;
            app.TFSettings = o;
            e = tfs{1};
            app.TFInfo.Text = EEGAnalysis.describeTimeFrequency(e);
            blank = ~all(any(e.valid, 2)) || any(any(e.valid, 2)' & e.baselineSamples == 0);
            if ~isempty(grand) && ~isempty(grand.notes)
                app.TFInfo.Text = [app.TFInfo.Text ' ' strjoin(grand.notes, ' ')];
            end
            app.TFInfo.FontColor = ifelse(blank, UITheme.warning, UITheme.sectionTitleColor);
            app.fillConditionDrops();
            if ~any(strcmp(app.ViewDrop.Value, app.Views(5:7))), app.ViewDrop.Value = app.Views{5}; end
            app.updateControls();
            plotted = app.plotERP();
            ok = true;
            if ~plotted, return; end
            if ~any(any(e.valid))
                UIKit.setStatus(app.StatusLabel, app.TFInfo.Text, 'warning');
                return;
            end
            UIKit.setStatus(app.StatusLabel, sprintf(['Time%sfrequency of %d participant(s) %s. Show: ' ...
                'Time%sfrequency (ERSP), Phase locking (ITPC) or Band power.%s'], char(8211), numel(tfs), ...
                tfWhere(e.channels), char(8211), ifelse(blank, ' Grey: no value (see step 7).', '')), ...
                ifelse(blank, 'warning', 'success'));
        end

        %% ----------------------------------------------------------------
        %% Step 8: save
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
            [~, name, ext] = fileparts(filePath);
            if isempty(app.Measures) && (isempty(app.TFs) || ~strcmpi(ext, '.mat'))
                UIKit.setStatus(app.StatusLabel, ['Measure first (step 5); a .mat file also takes the ' ...
                    'time' char(8211) 'frequency alone.'], 'warning');
                return;
            end
            try
                if strcmpi(ext, '.mat')
                    results = app.resultsStruct(); %#ok<NASGU>
                    save(filePath, 'results');
                else
                    writeCsv(filePath, {'Participant', 'Condition', 'Value_uV', 'Latency_ms', 'Trials', 'PeakAtEdge'}, ...
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

        %% sessionState - Files, settings (cleaning, trials, baseline, measure, test) and results
        % checks: the Checks tab rows (none before trials).
        function st = sessionState(app)
            st.inputs = [];
            st.settings = struct();
            st.results = struct();
            st.summary = {};
            st.checks = QualityChecks.ensure(app.CheckRows);
            if isempty(app.Loaded), return; end
            if strcmp(app.Generator, 'demoEEG')
                st.inputs = Session.fileInfo('', 'EEG demo (demoEEG), 8 participants');
            elseif strcmp(app.Generator, 'demoEEGraw')
                st.inputs = Session.fileInfo('', sprintf('EEG demo (demoEEG), %d raw continuous recordings', ...
                    numel(app.Loaded)));
            else
                for k = 1:numel(app.Files)
                    info = Session.fileInfo(app.Files{k}, sprintf('EEG, participant %s', app.Names{k}));
                    if isempty(st.inputs), st.inputs = info; else, st.inputs(end + 1) = info; end
                end
            end
            e1 = app.Loaded{1};
            ea = app.analysedData(1);
            st.settings.generator = app.Generator;
            st.settings.participants = app.Names;
            st.settings.maps = app.Maps;
            st.settings.sources = cellfun(@(e) e.source, app.Loaded, 'UniformOutput', false);
            st.settings.continuous = ~e1.isEpoched;
            % Electrode layout (step 1); its positions file is an input too
            if ~isempty(app.Layout)
                st.settings.layout = layoutSession(app.Layout, app.LayoutSettings, app.LayoutPositions);
                if ~isempty(app.LayoutSettings.positionsFile)
                    info = Session.fileInfo(app.LayoutSettings.positionsFile, app.PositionsRole);
                    if isempty(st.inputs), st.inputs = info; else, st.inputs(end + 1) = info; end
                end
            end
            % Step 2: the settings applied (or those in the window when not applied)
            if isempty(app.CleanSettings)
                cl = app.currentCleaning();
                cl.notchFreqs = [];
                cl.filterText = {};
                cl.suggestRule = app.SuggestRule;
                cl.applied = false;
            else
                cl = app.CleanSettings;
            end
            st.settings.cleaning = cl;
            % Step 3: the settings used (or those in the window when not run)
            if isempty(app.TrialSettings)
                tr = rmfield(app.currentTrials(), 'problems');
            else
                tr = app.TrialSettings;
            end
            st.settings.trials = tr;
            st.settings.trialWindow = app.TrialWindow;    % also in trials.window (kept for older readers)
            st.settings.fs = e1.fs;
            st.settings.nChannels = numel(e1.labels);
            st.settings.reference = ea.reference;          % of the analysed data
            st.settings.recordedReference = e1.reference;  % of the files as read
            st.settings.history = e1.history;              % what was done before the window
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
            if ~isempty(app.Layout)
                st.summary{end + 1} = sprintf('Electrode layout: %s%s', app.Layout.summary, ...
                    ifelse(app.Layout.confirmed, ' Confirmed.', ' Not confirmed.'));
            end
            if cl.applied
                st.summary{end + 1} = ['Cleaning: ' cleaningText(cl, numel(app.Names))];
                for i = 1:numel(cl.filterText)
                    st.summary{end + 1} = ['  ' cl.filterText{i}];
                end
                st.summary{end + 1} = sprintf('Reference of the analysed data: %s', ea.reference);
            end
            if ~isempty(app.TrialWindow)
                st.summary{end + 1} = sprintf('Continuous recordings cut into trials from %g to %g ms around the events', ...
                    app.TrialWindow * 1000);
            end
            if ~isempty(app.Rejections)
                r = app.Rejections;
                rj = struct('participant', app.Names, 'total', {r.total}, 'kept', {r.kept}, ...
                    'conditions', {r.conditions}, 'before', {r.before}, 'after', {r.after}, 'sentence', {r.sentence});
                st.results.rejection = rj;
                st.summary{end + 1} = sprintf('Trial rejection: %d of %d trials rejected (%s per participant)', ...
                    sum([r.total]) - sum([r.kept]), sum([r.total]), rangeText([r.total] - [r.kept]));
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
            st.settings.scalpMaps = [];
            if ~isempty(app.ScalpMaps)
                M = app.ScalpMaps;
                st.settings.scalpMaps = app.MapSettings;
                st.results.scalpMaps = struct('names', {{M.name}}, 'kind', M(1).kind, 'method', M(1).method, ...
                    'electrodes', {M(1).labels}, 'left', {M(1).left});
                st.summary{end + 1} = sprintf('Scalp maps (%s): %s. %s', app.MapSettings.participant, ...
                    mapWindowText(app.MapSettings.window), ScalpMap.describe(M(1)));
            end
            % Step 7: the settings used (or those in the window when not computed) and the view shown
            st.settings.tfShown = ~isempty(app.TFs);
            if st.settings.tfShown, st.settings.timeFrequency = app.TFSettings;
            else, st.settings.timeFrequency = app.currentTF(); end
            st.settings.tfPlot = [];
            if any(strcmp(app.ViewDrop.Value, app.Views(5:7)))
                st.settings.tfPlot = struct('view', app.ViewDrop.Value, 'participant', app.ParticipantDrop.Value, ...
                    'condA', app.CondADrop.Value, 'condB', app.CondBDrop.Value);
            end
            if st.settings.tfShown
                e = app.analysisTF(1);
                has = any(e.valid, 2)';
                withBase = has & e.baselineSamples > 0;
                st.results.timeFrequency = struct('conditions', {e.conditions}, 'trials', e.trials, ...
                    'participants', numel(app.TFs), 'freqs', e.freqs, 'cycles', e.cycles, 'baseline', e.baseline, ...
                    'channels', {e.channels}, 'band', e.bands(1, :), 'bandName', e.bandNames{1}, ...
                    'lowestWithValues', firstOr(e.freqs(has), NaN), 'lowestWithBaseline', ...
                    firstOr(e.freqs(withBase), NaN), 'text', EEGAnalysis.describeTimeFrequency(app.TFs{1}));
                st.summary{end + 1} = ['Time' char(8211) 'frequency: ' st.results.timeFrequency.text];
            end
            if isempty(app.Measures), return; end
            st.results.measureHeader = {'Participant', 'Condition', 'Value_uV', 'Latency_ms', 'Trials', 'PeakAtEdge'};
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
        % Sessions saved before steps 2 and 3 existed have no cleaning / trials
        % settings: their continuous recordings are cut with trialWindow only.
        % Sessions without a layout keep the layout made from the files (not
        % confirmed). The positions file is the input of role PositionsRole;
        % every other input is an EEG file.
        function ok = restoreSession(app, s)
            ok = false;
            cfg = s.settings;
            ins = s.inputs;
            isPos = false(1, numel(ins));
            if isstruct(ins) && ~isempty(ins) && isfield(ins, 'role')
                isPos = strcmp({ins.role}, app.PositionsRole);
            end
            eegIn = ins(~isPos);
            gen = '';
            if isfield(cfg, 'generator'), gen = cfg.generator; end
            if strcmp(gen, 'demoEEG')
                if ~app.loadDemo(), return; end
            elseif strcmp(gen, 'demoEEGraw')
                if ~app.loadRawDemo(), return; end
            elseif isempty(eegIn)
                ok = true; return;
            else
                maps = {};
                if isfield(cfg, 'maps'), maps = cfg.maps; end
                if ~app.openFiles({eegIn.path}, maps), return; end
            end
            if isfield(cfg, 'layout') && isstruct(cfg.layout)
                ly = cfg.layout;
                f = ly.positionsFile;
                if any(isPos), f = ins(find(isPos, 1)).path; end      % where the session check found it
                if ~app.setLayout('Source', ly.source, 'PositionsFile', f, 'Edits', ly.edits, ...
                        'Confirm', ly.confirmed)
                    return;
                end
            end
            if isfield(cfg, 'cleaning') && isstruct(cfg.cleaning)
                cl = cfg.cleaning;
                for k = 1:min(numel(cl.bad), numel(app.Names))
                    app.setBadChannels(k, cl.bad{k});
                end
                app.SuggestRule = cl.suggestRule;
                app.setFilters(cl.highPass, cl.lowPass, cl.notch);
                app.setReference(cl.referenceMode, cl.referenceChannels);
                if cl.applied && ~app.applyCleaning(), return; end
            end
            if isfield(cfg, 'trials') && isstruct(cfg.trials)
                tr = cfg.trials;
                app.setEvents(tr.eventsText);
                app.setTrialWindow(tr.window);
                app.setRejection(tr.reject, tr.peakToPeak, tr.absolute);
                if tr.cut && ~app.cutIntoTrials(), return; end
            elseif ~isempty(cfg.trialWindow)
                app.setEvents('');
                app.setRejection(false);
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
            if isfield(cfg, 'scalpMaps') && isstruct(cfg.scalpMaps) && ~isempty(cfg.scalpMaps) && ~isempty(app.ERPs)
                ms = cfg.scalpMaps;
                if any(strcmp(app.ParticipantDrop.Items, ms.participant)), app.ParticipantDrop.Value = ms.participant; end
                if any(strcmp(app.CondADrop.Items, ms.condA)), app.CondADrop.Value = ms.condA; end
                if any(strcmp(app.CondBDrop.Items, ms.condB)), app.CondBDrop.Value = ms.condB; end
                app.MapSettings = struct('window', ms.window);
                app.ViewDrop.Value = app.Views{4};
                app.updateControls();
                if ~app.plotERP(), return; end
            end
            if isfield(cfg, 'timeFrequency') && isstruct(cfg.timeFrequency)
                tq = cfg.timeFrequency;
                app.setTimeFrequency(tq.frequencies, tq.cycles, tq.baseline, tq.channelsTyped, tq.bandName);
                if cfg.tfShown && ~app.showTimeFrequency(), return; end
                tp = cfg.tfPlot;
                if isstruct(tp) && ~isempty(tp) && any(strcmp(app.Views, tp.view))
                    if any(strcmp(app.ParticipantDrop.Items, tp.participant)), app.ParticipantDrop.Value = tp.participant; end
                    if any(strcmp(app.CondADrop.Items, tp.condA)), app.CondADrop.Value = tp.condA; end
                    if any(strcmp(app.CondBDrop.Items, tp.condB)), app.CondBDrop.Value = tp.condB; end
                    app.ViewDrop.Value = tp.view;
                    app.updateControls();
                    app.plotERP();
                end
            end
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
            % Step 2 starts from the bad channels the files already mark
            app.BadChannels = cellfun(@(e) channelList(e.labels(EEGAnalysis.badChannels(e))), eegs, ...
                'UniformOutput', false);
            app.Cleaned = {};
            app.CleanSettings = [];
            app.SuggestRule = '';
            app.TrialSettings = [];
            app.Rejections = [];
            app.clearResults();
            app.resetLayout();
            app.CleanParticipantDrop.Items = names;
            app.CleanParticipantDrop.Value = names{1};
            app.showBadChannels();
            % Steps 2 and 3 start from their defaults (no filter for trials already cut)
            if all(kinds), app.setFilters(0, 0, 'off'); else, app.setFilters(0.1, 30, 'off'); end
            app.setReference('as recorded', {});
            app.setEvents('');
            app.setTrialWindow([-0.2 0.8]);
            app.setRejection(false, 100, 0);
            e1 = eegs{1};
            if e1.isEpoched
                n = cellfun(@(e) size(e.data, 3), eegs);
                app.FileInfo.Text = sprintf('%d participant(s)  ·  %d channels at %g Hz  ·  trials %g to %g ms  ·  %s trials', ...
                    numel(eegs), numel(e1.labels), e1.fs, e1.times(1) * 1000, e1.times(end) * 1000, rangeText(n));
                app.CleanInfo.Text = ['Already cut into trials: filters run on each trial, which is less accurate ' ...
                    'than filtering the continuous recording (the edges of short trials). Often nothing to do here.'];
                app.CleanInfo.FontColor = UITheme.bodyColor;
                app.CutInfo.Text = ['Already cut into trials. Tick Reject trials and Apply rejection to leave out ' ...
                    'noisy trials.'];
                app.CutInfo.FontColor = UITheme.bodyColor;
                app.CutBtn.Text = 'Apply rejection';
                app.BaselineFromEdit.Value = e1.times(1) * 1000;
                if e1.times(1) < 0, app.TFBaseFromEdit.Value = e1.times(1) * 1000; end
            else
                nEv = cellfun(@(e) numel(e.events), eegs);
                app.FileInfo.Text = sprintf('%d participant(s)  ·  %d channels at %g Hz  ·  continuous, %s events', ...
                    numel(eegs), numel(e1.labels), e1.fs, rangeText(nEv));
                app.CleanInfo.Text = 'Mark bad channels, choose the filters and the reference, then Apply (optional).';
                app.CleanInfo.FontColor = UITheme.bodyColor;
                app.CutInfo.Text = 'Continuous: say the events and the trial window, then Cut into trials.';
                app.CutInfo.FontColor = UITheme.warning;
                app.CutBtn.Text = 'Cut into trials';
            end
            app.FileInfo.FontColor = UITheme.sectionTitleColor;
            % Channels typed for earlier files: keep only those the new files have
            app.ChannelsEdit.Value = channelText(keepChannels(app.ChannelsEdit.Value, e1.labels));
            app.MeasureChannelsEdit.Value = channelText(keepChannels(app.MeasureChannelsEdit.Value, e1.labels));
            % None left: a midline channel when the files have one (the average
            % of all channels is flat after an average reference)
            if isempty(app.ChannelsEdit.Value)
                mid = keepChannels({'Pz', 'Cz', 'Fz', 'Oz'}, e1.labels);
                if ~isempty(mid), app.ChannelsEdit.Value = mid{1}; end
            end
            items = names;
            if numel(names) > 1, items = [{app.GrandLabel}, names]; end
            app.ParticipantDrop.Items = items;
            app.ParticipantDrop.Value = items{1};
            app.fillOverview();
            app.fillConditionDrops();
            app.plotERP();
            app.updateControls();
            if e1.isEpoched
                UIKit.setStatus(app.StatusLabel, sprintf(['Loaded %d participant(s). Read the Overview tab (what ' ...
                    'was already done to the data), then Show ERPs (step 4).'], numel(eegs)), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf(['Loaded %d continuous recording(s). Next: clean them ' ...
                    '(step 2, optional), then Cut into trials (step 3).'], numel(eegs)), 'success');
            end
            ok = true;
        end

        %% clearResults - Forget ERPs, measures and tests (after new data)
        function clearResults(app)
            app.ERPs = {}; app.Grand = []; app.ERPSettings = [];
            app.Measures = {}; app.MeasureSettings = []; app.StatsResult = [];
            app.ScalpMaps = []; app.MapSettings = [];
            app.TFs = {}; app.GrandTF = []; app.TFSettings = [];
            app.CheckRows = QualityChecks.none();      % checks belong to the trials analysed
            if ~isempty(app.MeasuresTable) && isvalid(app.MeasuresTable)
                app.fillMeasures();
                app.fillStats();
                app.ErpInfo.Text = '';
                app.MeasureInfo.Text = '';
                app.TFInfo.Text = '';
            end
            if ~isempty(app.ChecksUI), UIKit.showChecks(app.ChecksUI, app.CheckRows); end
        end

        %% updateChecks - Quality checks of the trials analysed (EEGAnalysis.checks) into the Checks tab
        % After Compare conditions the rows of the test (GroupStats.checks,
        % res.checkRows) follow them.
        % Measure kind and channels: those measured (step 5), else those in
        % the window; ERP channels: those shown (step 4), else those typed.
        function updateChecks(app)
            app.CheckRows = QualityChecks.none();
            if ~isempty(app.EEGs)
                if isempty(app.Measures) || isempty(app.MeasureSettings)
                    m = app.currentMeasure();
                else
                    m = app.MeasureSettings;
                end
                if isempty(app.ERPSettings)
                    erpChans = channelList(app.ChannelsEdit.Value);
                else
                    erpChans = app.ERPSettings.channels;
                end
                app.CheckRows = EEGAnalysis.checks(app.EEGs, app.Names, struct('rejections', app.Rejections, ...
                    'measure', m.Measure, 'channels', {m.Channels}, 'erpChannels', {erpChans}));
                if ~isempty(app.StatsResult) && isfield(app.StatsResult, 'checkRows')
                    app.CheckRows = [app.CheckRows; QualityChecks.ensure(app.StatsResult.checkRows)];
                end
            end
            if ~isempty(app.ChecksUI), UIKit.showChecks(app.ChecksUI, app.CheckRows); end
        end

        %% checksStatus - ' 2 warnings in the Checks tab: ...' and level 'warning' when the checks warn
        function [extra, level] = checksStatus(app, level)
            extra = '';
            n = QualityChecks.count(app.CheckRows, 'warning');
            if n == 0, return; end
            extra = sprintf(' %s in the Checks tab: read them before using the results.', QualityChecks.plural(n, 'warning'));
            level = 'warning';
        end

        %% resetLayout - New files: the layout of participant 1 from its positions (others by name), not confirmed
        % Never stops the loading: an error gives a layout without positions and a note.
        function resetLayout(app)
            app.closeLayout();
            ls = struct();
            ls.source = 'auto';
            ls.positionsFile = '';
            ls.edits = layoutEdits([]);
            ls.confirmed = false;
            app.LayoutSettings = ls;
            app.LayoutPositions = [];
            try
                app.Layout = EEGLayout.fromEEG(app.Loaded{1});
            catch ME
                app.Layout = noLayout(app.Loaded{1}.labels, ME.message);
            end
            app.showLayoutInfo();
        end

        %% showLayoutInfo - Step 1: the layout's summary, confirmed or not
        function showLayoutInfo(app)
            L = app.Layout;
            if isempty(L)
                app.LayoutInfo.Text = '';
                return;
            end
            if L.confirmed
                app.LayoutInfo.Text = [L.summary ' Confirmed.'];
                app.LayoutInfo.FontColor = UITheme.success;
            else
                app.LayoutInfo.Text = [L.summary ' Not checked yet: open Electrode layout' char(8230) ' to look at it.'];
                app.LayoutInfo.FontColor = UITheme.warning;
            end
        end

        %% showLayoutDraft - The layout dialog: Source list, table, summary and drawing of the layout shown
        function showLayoutDraft(app)
            d = app.LayoutDlg;
            if isempty(d) || isempty(app.LayoutFig) || ~isvalid(app.LayoutFig), return; end
            L = d.L;
            items = app.LayoutSources;
            if ~isempty(d.draft.positionsFile)
                d.SourceDrop.Value = items{3};
            elseif strcmp(d.draft.source, 'template')
                d.SourceDrop.Value = items{2};
            else
                d.SourceDrop.Value = items{1};
            end
            tbl = d.Table;
            tbl.Data = cell(0, 4);                  % no old rows under the new column formats
            if strcmp(L.kind, 'skull')
                tbl.ColumnName = {'Channel', 'AP (mm)', 'ML (mm)', 'Status'};
                tbl.ColumnEditable = [false true true false];
                tbl.ColumnFormat = {'char', 'numeric', 'numeric', 'char'};
            else
                tbl.ColumnName = {'Channel', 'Placed from', 'As', 'Status'};
                tbl.ColumnEditable = [false false true false];
                tbl.ColumnFormat = {'char', 'char', 'char', 'char'};
            end
            tbl.Data = layoutRows(L);
            lines = EEGLayout.describe(L);
            if ~isempty(d.draft.positionsFile)
                lines = [{sprintf('Positions file: %s', fileName(d.draft.positionsFile))}, lines];
            end
            d.Text.Value = lines(:);
            ax = d.Axes;
            delete(allchild(ax));
            EEGLayout.plot(ax, L);
        end

        %% layoutMessage - One line under the summary of the layout dialog (kind: info | warning | error)
        function layoutMessage(app, msg, kind)
            d = app.LayoutDlg;
            if isempty(d) || ~isvalid(d.Message), return; end
            d.Message.Text = msg;
            switch kind
                case 'error', d.Message.FontColor = UITheme.danger;
                case 'warning', d.Message.FontColor = UITheme.warning;
                otherwise, d.Message.FontColor = UITheme.bodyColor;
            end
        end

        %% previewLayout - Show the layout of new dialog settings (not used until Use this layout)
        % dropEdits: when the placements by hand do not fit the new layout
        % (e.g. 10-5 names on a skull), drop them instead of refusing the change.
        function previewLayout(app, dr, P, dropEdits, note)
            if nargin < 5, note = ''; end
            eeg = app.Loaded{1};
            L = [];
            try
                L = buildLayout(eeg, dr, P);
            catch ME
                why = ME.message;
                if dropEdits && ~isempty(dr.edits)
                    dr.edits = layoutEdits([]);
                    try
                        L = buildLayout(eeg, dr, P);
                        note = sprintf('Your placements by hand were dropped: %s', why);
                    catch ME2
                        why = ME2.message;
                    end
                end
                if isempty(L)
                    app.showLayoutDraft();          % back to the layout shown before
                    app.layoutMessage(sprintf('Not changed: %s', why), 'error');
                    return;
                end
            end
            app.LayoutDlg.draft = dr;
            app.LayoutDlg.positions = P;
            app.LayoutDlg.L = L;
            app.showLayoutDraft();
            app.layoutMessage(note, 'warning');
        end

        %% onLayoutSource - Source list of the layout dialog
        function onLayoutSource(app)
            d = app.LayoutDlg;
            if isempty(d), return; end
            dr = d.draft;
            k = find(strcmp(app.LayoutSources, d.SourceDrop.Value), 1);
            if k == 3
                if isempty(dr.positionsFile), app.choosePositionsFile(); end
                return;
            end
            dr.source = ifelse(k == 2, 'template', 'auto');
            dr.positionsFile = '';
            app.previewLayout(dr, [], true);
        end

        %% choosePositionsFile - Positions file... of the layout dialog
        function choosePositionsFile(app)
            start = ProjectManager.getImportDir();
            if isempty(start), start = pwd; end
            [f, p] = uigetfile({'*.elc;*.sfp;*.loc;*.locs;*.ced;*.xyz;*.elp;*.bvef;*.csv;*.tsv;*.txt', ...
                'Electrode positions (.elc, .sfp, .loc, .locs, .ced, .xyz, .elp, .bvef, .csv, .tsv, .txt)'}, ...
                'Electrode positions', start);
            if isempty(app.LayoutDlg) || isempty(app.LayoutFig) || ~isvalid(app.LayoutFig), return; end
            figure(app.LayoutFig);
            if isequal(f, 0)
                app.showLayoutDraft();              % the Source list shows the layout in use again
                return;
            end
            app.usePositionsFile(fullfile(p, f));
        end

        %% usePositionsFile - Read a positions file and show the layout it gives (layout dialog)
        function usePositionsFile(app, f)
            try
                P = readElectrodes(f);
            catch ME
                app.showLayoutDraft();
                app.layoutMessage(sprintf('Positions file not read: %s', ME.message), 'error');
                return;
            end
            dr = app.LayoutDlg.draft;
            if strcmp(dr.source, 'template'), dr.source = 'auto'; end
            dr.positionsFile = f;
            app.previewLayout(dr, P, true);
        end

        %% onLayoutEdit - A cell of the layout table: As (scalp) or AP / ML (skull) typed
        % Empty = no position. A skull channel without a position gets 0 mm
        % for the coordinate not typed yet.
        function onLayoutEdit(app, evt)
            d = app.LayoutDlg;
            if isempty(d), return; end
            L = d.L;
            r = evt.Indices(1);
            c = evt.Indices(2);
            if r < 1 || r > numel(L.labels), return; end
            E = struct('label', L.labels{r}, 'as', '', 'ap', NaN, 'ml', NaN);
            note = '';
            if strcmp(L.kind, 'skull')
                if c ~= 2 && c ~= 3, return; end
                v = evt.NewData;
                if ischar(v) || isstring(v), v = str2double(v); end
                if isempty(v) || ~isnumeric(v) || ~isscalar(v), v = NaN; end
                v = double(v);
                ml = L.pos(r, 1);
                ap = L.pos(r, 2);
                if c == 2, ap = v; else, ml = v; end
                if isfinite(v)
                    if ~isfinite(ap), ap = 0; note = sprintf('%s placed at AP 0 mm: type its AP too.', E.label); end
                    if ~isfinite(ml), ml = 0; note = sprintf('%s placed at ML 0 mm: type its ML too.', E.label); end
                    E.ap = ap;
                    E.ml = ml;
                end
            else
                if c ~= 3, return; end
                E.as = strtrim(char(evt.NewData));
            end
            dr = d.draft;
            dr.edits = setEdit(dr.edits, E);
            app.previewLayout(dr, d.positions, false, note);
        end

        %% useLayout - Use this layout: apply the dialog's layout, confirmed, and close the dialog
        function useLayout(app)
            d = app.LayoutDlg;
            if isempty(d), return; end
            dr = d.draft;
            if app.setLayout('Source', dr.source, 'PositionsFile', dr.positionsFile, 'Edits', dr.edits, ...
                    'Confirm', true)
                app.closeLayout();
            else
                app.layoutMessage(app.StatusLabel.Text, 'error');
            end
        end

        %% closeLayout - Close the layout dialog (Cancel, its close box, new files, the window closing)
        function closeLayout(app)
            fig = app.LayoutFig;
            app.LayoutFig = [];
            app.LayoutDlg = [];
            if ~isempty(fig) && isvalid(fig), delete(fig); end
        end

        %% isReady - Data cut into trials (message otherwise)
        function tf = isReady(app)
            tf = ~isempty(app.EEGs);
            if tf, return; end
            if isempty(app.Loaded)
                UIKit.setStatus(app.StatusLabel, 'Load EEG files first (step 1).', 'warning');
            else
                UIKit.setStatus(app.StatusLabel, 'Cut the recordings into trials first (step 3).', 'warning');
            end
        end

        %% analysedData - What is analysed for participant k: trials, else cleaned, else as read
        function e = analysedData(app, k)
            if ~isempty(app.EEGs)
                e = app.EEGs{k};
            elseif ~isempty(app.Cleaned)
                e = app.Cleaned{k};
            else
                e = app.Loaded{k};
            end
        end

        %% participantIndex - Index of a participant given as index or name
        function k = participantIndex(app, participant)
            if isnumeric(participant)
                k = participant;
            else
                k = find(strcmpi(app.Names, participant), 1);
            end
            if isempty(k) || k < 1 || k > numel(app.Names)
                error('NeuroAnalyzer:eeg:badOption', 'No participant %s. Participants: %s.', ...
                    num2str(participant), EEGSource.listText(app.Names));
            end
        end

        %% cleanIndex - Participant shown in step 2
        function k = cleanIndex(app)
            k = find(strcmp(app.CleanParticipantDrop.Items, app.CleanParticipantDrop.Value), 1);
            if isempty(k), k = 1; end
        end

        %% showBadChannels - The bad channels of the participant shown in step 2
        function showBadChannels(app)
            k = app.cleanIndex();
            if k <= numel(app.BadChannels)
                app.BadEdit.Value = channelText(app.BadChannels{k});
            else
                app.BadEdit.Value = '';
            end
        end

        %% onBadEdited - Bad channels typed for the participant shown in step 2
        function onBadEdited(app)
            if isempty(app.Loaded), return; end
            k = app.cleanIndex();
            app.BadChannels{k} = channelList(app.BadEdit.Value);
            app.BadEdit.Value = channelText(app.BadChannels{k});
            app.updateControls();
        end

        %% currentCleaning - Step 2 settings from the controls
        % highPass / lowPass in Hz (0 = off), notch 'off' | 50 | 60, referenceMode lower case.
        function cs = currentCleaning(app)
            notch = 'off';
            if strcmp(app.NotchDrop.Value, app.NotchItems{2}), notch = 50; end
            if strcmp(app.NotchDrop.Value, app.NotchItems{3}), notch = 60; end
            cs = struct('bad', {app.BadChannels}, 'highPass', app.HighPassEdit.Value, ...
                'lowPass', app.LowPassEdit.Value, 'notch', notch, 'referenceMode', lower(app.ReferenceDrop.Value), ...
                'referenceChannels', {channelList(app.ReferenceChannelsEdit.Value)});
        end

        %% cleaningChanged - Step 2 controls differ from the settings applied
        function tf = cleaningChanged(app)
            tf = false;
            if isempty(app.CleanSettings), return; end
            cur = app.currentCleaning();
            for f = fieldnames(cur)'
                if ~isequal(cur.(f{1}), app.CleanSettings.(f{1})), tf = true; return; end
            end
        end

        %% currentTrials - Step 3 settings from the controls (window in s, thresholds in uV, 0 = off)
        % problems: entries of the events text that are not 'type' or 'type = name'.
        function ts = currentTrials(app)
            [events, rename, problems] = EEGAnalysis.parseEvents(app.EventsEdit.Value);
            ts = struct('eventsText', strtrim(app.EventsEdit.Value), 'events', {events}, 'rename', {rename}, ...
                'window', [app.TrialFromEdit.Value app.TrialToEdit.Value] / 1000, ...
                'reject', logical(app.RejectCb.Value), 'peakToPeak', app.PeakToPeakEdit.Value, ...
                'absolute', app.AbsoluteEdit.Value, 'cut', false, 'problems', {problems});
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
                bad = EEGAnalysis.badChannels(eeg);
                ch = ch(~bad(ch));      % bad channels are left out of the average
                if isempty(ch), continue; end
                eeg.data = mean(eeg.data(ch, :, :), 1);
                eeg.labels = {'mean'};
                eeg.bad = false;
                erps{i} = EEGAnalysis.conditionERPs(eeg, 'Baseline', app.ERPSettings.baseline);
            end
            erps = erps(~cellfun(@isempty, erps));
            if isempty(erps)
                error('NeuroAnalyzer:eeg:badOption', ['Every chosen channel (%s) is marked bad, so there is ' ...
                    'nothing to plot. Choose other channels (step 4).'], EEGSource.listText(chans));
            end
            e = EEGAnalysis.grandAverage(erps);
        end

        %% onView - Enable the condition lists that the view uses, then plot
        function onView(app)
            app.updateControls();
            app.plotERP();
        end

        %% plotERP - Conditions, butterfly, difference wave or scalp maps of the shown participant(s)
        % ok: false when the plot could not be made (the axes and the status say why)
        function ok = plotERP(app)
            tfView = find(strcmp(app.Views(5:7), app.ViewDrop.Value), 1);
            if ~isempty(tfView)
                app.showMapPanel(tfView < 3);
                if tfView == 3
                    ok = app.plotBandPower();
                else
                    ok = app.plotTF(ifelse(tfView == 1, 'ersp', 'itpc'));
                end
                return;
            end
            mapsView = strcmp(app.ViewDrop.Value, app.Views{4}) && ~isempty(app.ERPs);
            app.showMapPanel(mapsView);
            if mapsView
                ok = app.plotMaps();
                return;
            end
            ok = true;
            ax = app.AxERP;
            % cla keeps objects with hidden handles (butterfly lines, SEM shades): delete them all
            delete(allchild(ax));
            ax.YLimMode = 'auto';   % the measure window fixes the limits; each view starts free
            if isempty(app.ERPs)
                if isempty(app.Loaded)
                    UIKit.emptyAxes(ax, 'Load EEG files (or Try demo data) to begin');
                elseif isempty(app.EEGs)
                    UIKit.emptyAxes(ax, 'Cut the recordings into trials (step 3)');
                else
                    UIKit.emptyAxes(ax, 'Click Show ERPs (step 4)');
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
                        good = any(isfinite(y), 2);     % bad channels are NaN: no line for them
                        plot(ax, t, y(good, :)', 'Color', lighten(T.bodyColor, 0.6), 'LineWidth', 0.5, ...
                            'HandleVisibility', 'off');
                        if ~isempty(chans)
                            ch = EEGAnalysis.channelIndex(e.labels, chans);
                            ch = ch(good(ch));
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
                UIKit.setStatus(app.StatusLabel, sprintf('Cannot plot: %s', ME.message), 'warning');
                ok = false;
                return;
            end
            if ~isempty(app.MeasureSettings)
                wm = app.MeasureSettings.Window * 1000;
                yl = UIKit.dataLimits(ax, 'y');   % not ylim(ax): before the first draw it can still be [0 1]
                patch(ax, [wm(1) wm(2) wm(2) wm(1)], [yl(1) yl(1) yl(2) yl(2)], T.accent, 'FaceAlpha', 0.1, ...
                    'EdgeColor', 'none', 'HandleVisibility', 'off');
                ylim(ax, yl);
            end
            xline(ax, 0, ':', 'Color', T.stimColor, 'HandleVisibility', 'off');
            yline(ax, 0, '-', 'Color', T.axesGrid, 'HandleVisibility', 'off');
            hold(ax, 'off');
            UIKit.styleAxes(ax, ttl, 'Time from the event (ms)', ['Voltage (' char(181) 'V, positive up)']);
            xlim(ax, [t(1) t(end)]);
            if ~isempty(findobj(ax, 'Type', 'line'))
                legend(ax, 'Location', 'northwest', 'Box', 'off', 'Interpreter', 'none');
            else
                legend(ax, 'off');
            end
        end

        %% showMapPanel - The plot area shows the scalp maps (true) or the ERP axes (false)
        function showMapPanel(app, on)
            if on
                app.PlotGrid.RowHeight = {0, '1x'};
            else
                app.PlotGrid.RowHeight = {'1x', 0};
            end
            app.MapPanel.Visible = onoff(on);
            app.ErpPanel.Visible = onoff(~on);
        end

        %% plotMaps - Scalp maps of the shown participant, one colour scale for all
        % The window is MapSettings.window (set by showScalpMaps and measure).
        % quiet: leave the status bar as it is.
        function ok = plotMaps(app, quiet)
            if nargin < 2, quiet = false; end
            ok = false;
            T = UITheme;
            delete(app.MapPanel.Children);
            g = uigridlayout(app.MapPanel, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [4 2 4 2], ...
                'RowSpacing', 4, 'BackgroundColor', T.cardBg);
            info = uilabel(g, 'Text', '', 'WordWrap', 'on', 'FontSize', T.fontSmall + 1, ...
                'FontColor', T.sectionTitleColor);
            if isempty(app.MapSettings)
                app.MapSettings = struct('window', [app.WindowFromEdit.Value app.WindowToEdit.Value] / 1000);
            end
            w = app.MapSettings.window;
            try
                maps = app.makeMaps(w);
            catch ME
                app.ScalpMaps = [];
                info.Text = sprintf('No scalp maps: %s', ME.message);
                info.FontColor = T.warning;
                if ~quiet, UIKit.setStatus(app.StatusLabel, info.Text, 'warning'); end
                return;
            end
            n = numel(maps);
            mg = uigridlayout(g, [1 n + 1], 'ColumnWidth', [repmat({'1x'}, 1, n), {70}], 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 2, 'BackgroundColor', T.cardBg);
            lim = ScalpMap.limits(maps);
            for k = 1:n
                ax = uiaxes(mg);
                ax.Toolbar.Visible = 'off';
                disableDefaultInteractivity(ax);
                ScalpMap.plot(ax, maps(k), 'CLim', lim, 'Title', maps(k).name, 'FontSize', T.fontSmall);
            end
            ax = uiaxes(mg);
            ax.Toolbar.Visible = 'off';
            disableDefaultInteractivity(ax);
            ScalpMap.colorScale(ax, lim, [char(181) 'V']);
            app.ScalpMaps = maps;
            app.MapSettings.participant = app.ParticipantDrop.Value;
            app.MapSettings.condA = app.CondADrop.Value;
            app.MapSettings.condB = app.CondBDrop.Value;
            info.Text = sprintf('%s: %s. %s Every map has the same colour scale (red positive, blue negative).', ...
                app.ParticipantDrop.Value, mapWindowText(w), ScalpMap.describe(maps(1)));
            confirmed = app.Layout.confirmed;
            if ~confirmed
                info.Text = sprintf(['%s The electrode layout is not confirmed yet: check it (step 1, ' ...
                    'Electrode layout%s).'], info.Text, char(8230));
                info.FontColor = T.warning;
            end
            ok = true;
            if quiet, return; end
            if confirmed
                UIKit.setStatus(app.StatusLabel, sprintf('Scalp maps of %s.', mapWindowText(w)), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf(['Scalp maps of %s, on an electrode layout that is not ' ...
                    'confirmed yet: check it in Electrode layout%s (step 1).'], mapWindowText(w), char(8230)), 'warning');
            end
        end

        %% makeMaps - Maps of every condition and of A minus B for the shown participant (window w in s)
        function maps = makeMaps(app, w)
            L = app.Layout;
            if isempty(L) || ~any(strcmp(L.kind, {'scalp', 'skull'}))
                error('NeuroAnalyzer:eeg:invalid', ['the channels have no positions (none in the files and no ' ...
                    '10-5 names). Give them a layout in step 1 (Electrode layout%s).'], char(8230));
            end
            e = app.analysisERP(app.shownIndex());
            names = e.conditions;
            a = app.CondADrop.Value;
            b = app.CondBDrop.Value;
            pairs = [names(:), repmat({''}, numel(names), 1)];
            if numel(names) > 1 && ~strcmp(a, b) && all(ismember({a, b}, names))
                pairs(end + 1, :) = {a, b};
            end
            maps = [];
            for k = 1:size(pairs, 1)
                v = EEGAnalysis.windowMean(e, w, pairs{k, 1}, pairs{k, 2});
                m = ScalpMap.make(L, v, 'Labels', e.labels);
                if isempty(pairs{k, 2})
                    m.name = pairs{k, 1};
                else
                    m.name = sprintf('%s minus %s', pairs{k, 1}, pairs{k, 2});
                end
                maps = [maps, m]; %#ok<AGROW>
            end
        end

        %% currentTF - Step 7 settings: frequencies [from to] Hz, cycles, baseline [from to] s, channels, band
        % channels: those typed, else those of step 4 ({} = all); channelsTyped: the field as typed.
        function o = currentTF(app)
            bands = TimeFrequency.defaultBands();
            k = find(strcmp(app.TFBandDrop.Items, app.TFBandDrop.Value), 1);
            chans = channelList(app.TFChannelsEdit.Value);
            if isempty(chans), chans = channelList(app.ChannelsEdit.Value); end
            o = struct('frequencies', [app.TFFromEdit.Value app.TFToEdit.Value], 'cycles', app.TFCyclesEdit.Value, ...
                'baseline', [app.TFBaseFromEdit.Value app.TFBaseToEdit.Value] / 1000, 'channels', {chans}, ...
                'channelsTyped', {channelList(app.TFChannelsEdit.Value)}, 'band', bands(k).range, ...
                'bandName', bands(k).name);
        end

        %% analysisTF - Time-frequency of the shown participant (1 = grand average with several)
        function e = analysisTF(app, k)
            if k == 1 && ~isempty(app.GrandTF)
                e = app.GrandTF;
            else
                if ~isempty(app.GrandTF), k = k - 1; end
                e = app.TFs{max(1, min(k, numel(app.TFs)))};
                e.trials = e.n;
            end
        end

        %% plotTF - ERSP (per condition and A minus B, one colour scale) or ITPC (per condition) images
        % which: 'ersp' | 'itpc'. Grey: no value (the wavelet would leave the trial).
        function ok = plotTF(app, which)
            ok = false;
            T = UITheme;
            delete(app.MapPanel.Children);
            g = uigridlayout(app.MapPanel, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [4 2 4 2], ...
                'RowSpacing', 4, 'BackgroundColor', T.cardBg);
            info = uilabel(g, 'Text', '', 'WordWrap', 'on', 'FontSize', T.fontSmall + 1, ...
                'FontColor', T.sectionTitleColor);
            if isempty(app.TFs)
                info.Text = ifelse(isempty(app.EEGs), 'Cut the recordings into trials (step 3), then compute the ', ...
                    'Click the button of step 7 to compute the ');
                info.Text = [info.Text 'time' char(8211) 'frequency.'];
                return;
            end
            e = app.analysisTF(app.shownIndex());
            isErsp = strcmp(which, 'ersp');
            grand = ~isempty(app.GrandTF) && app.shownIndex() == 1;
            C = numel(e.conditions);
            Z = cell(1, C);
            names = cell(1, C);
            for c = 1:C
                if isErsp, Z{c} = e.ersp(:, :, c); else, Z{c} = e.itpc(:, :, c); end
                if grand, nTxt = sprintf('%d participants', e.n(c)); else, nTxt = sprintf('%d trials', e.n(c)); end
                names{c} = sprintf('%s (%s)', e.conditions{c}, nTxt);
            end
            a = app.CondADrop.Value; b = app.CondBDrop.Value;
            ia = find(strcmp(e.conditions, a), 1); ib = find(strcmp(e.conditions, b), 1);
            if isErsp && C > 1 && ~isempty(ia) && ~isempty(ib) && ia ~= ib
                Z{end + 1} = e.ersp(:, :, ia) - e.ersp(:, :, ib);
                names{end + 1} = sprintf('%s minus %s', a, b);
            end
            n = numel(Z);
            vals = cell2mat(cellfun(@(z) z(isfinite(z))', Z, 'UniformOutput', false));
            if isErsp
                m = max([abs(vals), 0]);
                if m == 0, m = 1; end
                lim = [-m m];
                cmap = ScalpMap.colormap();
                unit = 'dB';
            else
                lim = [0 1];
                cmap = parula(256);
                unit = 'ITPC';
            end
            mg = uigridlayout(g, [1 n + 1], 'ColumnWidth', [repmat({'1x'}, 1, n), {70}], 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            t = e.times * 1000;
            df = 0.5 * min([diff(e.freqs), 1]);
            for k = 1:n
                ax = uiaxes(mg);
                ax.Toolbar.Visible = 'off';
                disableDefaultInteractivity(ax);
                im = imagesc(ax, t, e.freqs, Z{k});
                im.AlphaData = double(isfinite(Z{k}));
                ax.YDir = 'normal';
                ax.Color = noValueColor();
                colormap(ax, cmap);
                ax.CLim = lim;
                hold(ax, 'on');
                xline(ax, 0, ':', 'Color', T.stimColor, 'LineWidth', 1.2);
                hold(ax, 'off');
                xlim(ax, [t(1) t(end)]);
                ylim(ax, [e.freqs(1) - df, e.freqs(end) + df]);
                UIKit.styleAxes(ax, names{k}, 'Time (ms)', ifelse(k == 1, 'Frequency (Hz)', ''));
                ax.XGrid = 'off'; ax.YGrid = 'off';
                ax.Layer = 'top';
            end
            ax = uiaxes(mg);
            ax.Toolbar.Visible = 'off';
            disableDefaultInteractivity(ax);
            ScalpMap.colorScale(ax, lim, unit, cmap);
            where = tfWhere(e.channels);
            if isErsp
                info.Text = sprintf(['%s: ERSP %s, power in dB against its mean from %g to %g ms in each condition ' ...
                    '(red: more power than in the baseline, blue: less). Grey: no value (the wavelet would ' ...
                    'leave the trial).'], app.ParticipantDrop.Value, where, e.baseline * 1000);
            else
                nTr = e.n;                                   % trials (one participant) ...
                if grand, nTr = e.trials ./ e.n; end         % ... or trials per participant
                per = arrayfun(@(c) sprintf('%.2f for %s', sqrt(pi / (4 * max(1, nTr(c)))), e.conditions{c}), ...
                    1:C, 'UniformOutput', false);
                info.Text = sprintf(['%s: phase locking across trials (ITPC, 0 to 1) %s: 1 when every trial ' ...
                    'has the same phase. By chance about %s (fewer trials, higher chance level). Grey: no value.'], ...
                    app.ParticipantDrop.Value, where, EEGSource.listText(per));
            end
            ok = true;
        end

        %% plotBandPower - Band power per condition (% change from the baseline; shade = SEM)
        function ok = plotBandPower(app)
            ok = false;
            ax = app.AxERP;
            delete(allchild(ax));
            legend(ax, 'off');
            ax.YLimMode = 'auto';
            if isempty(app.TFs)
                UIKit.emptyAxes(ax, ifelse(isempty(app.EEGs), 'Cut the recordings into trials (step 3)', ...
                    ['Click the button of step 7 (Time' char(8211) 'frequency)']));
                return;
            end
            T = UITheme;
            e = app.analysisTF(app.shownIndex());
            grand = ~isempty(app.GrandTF) && app.shownIndex() == 1;
            t = e.times * 1000;
            hold(ax, 'on');
            bw = e.baseline * 1000;
            yl = [-1 1];
            for c = 1:numel(e.conditions)
                col = T.plotColors(1 + mod(c - 1, size(T.plotColors, 1)), :);
                m = e.bandPct(1, :, c);
                s = e.bandSem(1, :, c);
                v = isfinite(m);
                if ~any(v), continue; end
                tt = t(v); mm = m(v); ss = s(v);
                if all(isfinite(ss)) && numel(tt) > 1
                    fill(ax, [tt fliplr(tt)], [mm + ss, fliplr(mm - ss)], col, 'FaceAlpha', 0.15, ...
                        'EdgeColor', 'none', 'HandleVisibility', 'off');
                    yl = [min(yl(1), min(mm - ss)), max(yl(2), max(mm + ss))];
                end
                yl = [min(yl(1), min(mm)), max(yl(2), max(mm))];
                if grand, nTxt = sprintf('%d participants', e.n(c)); else, nTxt = sprintf('%d trials', e.n(c)); end
                plot(ax, tt, mm, 'Color', col, 'LineWidth', 1.6, 'DisplayName', sprintf('%s (%s)', e.conditions{c}, nTxt));
            end
            yl = yl + [-0.08 0.08] * diff(yl);
            patch(ax, [bw(1) bw(2) bw(2) bw(1)], [yl(1) yl(1) yl(2) yl(2)], T.axesGrid, 'FaceAlpha', 0.35, ...
                'EdgeColor', 'none', 'HandleVisibility', 'off');
            xline(ax, 0, ':', 'Color', T.stimColor, 'HandleVisibility', 'off');
            yline(ax, 0, '-', 'Color', T.axesGrid, 'HandleVisibility', 'off');
            hold(ax, 'off');
            UIKit.styleAxes(ax, sprintf('%s: %s power (%g%s%g Hz) %s; shaded: baseline', ...
                app.ParticipantDrop.Value, e.bandNames{1}, e.bands(1, 1), char(8211), e.bands(1, 2), ...
                tfWhere(e.channels)), 'Time from the event (ms)', '% change from the baseline');
            xlim(ax, [t(1) t(end)]);
            ylim(ax, yl);
            if ~isempty(findobj(ax, 'Type', 'line'))
                legend(ax, 'Location', 'northwest', 'Box', 'off', 'Interpreter', 'none');
            else
                UIKit.emptyAxes(ax, sprintf(['No band power: the wavelets of the %s band are longer than the ' ...
                    'trials allow (see step 7).'], e.bandNames{1}));
                return;
            end
            ok = true;
        end

        %% fillOverview - What every file holds and what was done to it before
        % The electrode layout (of participant 1) comes first, in place of the
        % position sentence of each file.
        function fillOverview(app)
            lines = {};
            if ~isempty(app.Loaded) && ~isempty(app.Layout)
                if numel(app.Loaded) > 1
                    lines{end + 1} = sprintf('Electrode layout (from the first participant, %s):', app.Names{1});
                else
                    lines{end + 1} = 'Electrode layout:';
                end
                lines = [lines, strcat({'   '}, EEGLayout.describe(app.Layout)), {''}];
            end
            for k = 1:numel(app.Loaded)
                e = app.analysedData(k);
                lines{end + 1} = sprintf('%s  (%s, %s)', app.Names{k}, e.source, fileName(e.file)); %#ok<AGROW>
                d = EEGSource.describe(e);
                d = d(cellfun(@isempty, regexp(d, '^(Electrode positions for |The file has no electrode positions)', ...
                    'once')));
                lines = [lines, strcat({'   '}, d)]; %#ok<AGROW>
                bad = EEGAnalysis.badChannels(e);
                if any(bad)
                    lines{end + 1} = sprintf(['   Bad channels: %s (left out of the reference, rejection, ERPs ' ...
                        'and measures).'], EEGSource.listText(e.labels(bad))); %#ok<AGROW>
                else
                    lines{end + 1} = '   Bad channels: none marked.'; %#ok<AGROW>
                end
                if numel(e.history) > numel(app.Loaded{k}.history)
                    lines{end + 1} = '   Already done to the data (read from the file, then the steps run here):'; %#ok<AGROW>
                else
                    lines{end + 1} = '   Already done to the data (read from the file, nothing was run):'; %#ok<AGROW>
                end
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
                        rows(end + 1, :) = {app.Names{p}, r(c).condition, r(c).value, r(c).latency * 1000, r(c).n, ...
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
                app.StatsText.Value = {'Measure (step 5), then Compare conditions (step 6).'};
                app.StatsTable.Data = cell(0, 5);
                app.StatsInfo.Text = '';
                return;
            end
            if r.checkAgrees, agree = 'agrees with the main test'; else, agree = 'disagrees with the main test'; end
            o = app.MeasureSettings;
            Q = QualityChecks.none();
            if isfield(r, 'checkRows'), Q = r.checkRows; end
            lines = {r.summary; ''; ['Assumptions: ' r.assumptions]; ''; ...
                sprintf('Robustness check: %s, %s (%s).', r.check.test, GroupStats.formatP(r.check.p), agree); ''; ...
                sprintf('Checks of the test: %s (Checks tab).', QualityChecks.summary(Q)); ''; ...
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
                'measureHeader', {{'Participant', 'Condition', 'Value_uV', 'Latency_ms', 'Trials', 'PeakAtEdge'}}, ...
                'measures', {app.measureRows(false)}, 'measureText', EEGAnalysis.describeMeasure(app.MeasureSettings), ...
                'stats', app.StatsResult, 'trialWindow', app.TrialWindow, 'cleaning', app.CleanSettings, ...
                'trials', app.TrialSettings, 'rejection', {app.Rejections}, 'timeFrequency', {app.TFs}, ...
                'grandTimeFrequency', app.GrandTF, 'timeFrequencySettings', app.TFSettings);
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
            tfDone = ~isempty(app.TFs);
            peak = strcmp(app.MeasureDrop.Value, app.MeasureKinds{2});
            shownView = app.ViewDrop.Value;
            reject = logical(app.RejectCb.Value);
            % Step 2: next while a continuous recording is not cleaned, or after its settings changed
            changed = app.cleaningChanged();
            cleanNext = has && ((continuous && isempty(app.Cleaned) && ~ready) || changed);
            for c = {app.CleanParticipantDrop, app.BadEdit, app.SuggestBtn, app.HighPassEdit, app.LowPassEdit, ...
                    app.NotchDrop, app.ReferenceDrop, app.ApplyCleanBtn}
                c{1}.Enable = onoff(has);
            end
            app.ReferenceChannelsEdit.Enable = onoff(has && strcmp(app.ReferenceDrop.Value, app.ReferenceModes{4}));
            changedText = 'Settings changed: click Apply to use them.';
            if changed
                app.CleanInfo.Text = changedText;
                app.CleanInfo.FontColor = UITheme.warning;
            elseif ~isempty(app.CleanSettings) && strcmp(app.CleanInfo.Text, changedText)
                app.CleanInfo.Text = cleaningText(app.CleanSettings, numel(app.Names));
                app.CleanInfo.FontColor = UITheme.success;
            end
            % Step 3: events and window only for continuous recordings
            app.EventsEdit.Enable = onoff(continuous);
            app.TrialFromEdit.Enable = onoff(continuous);
            app.TrialToEdit.Enable = onoff(continuous);
            app.RejectCb.Enable = onoff(has);
            app.PeakToPeakEdit.Enable = onoff(has && reject);
            app.AbsoluteEdit.Enable = onoff(has && reject);
            app.CutBtn.Enable = onoff(has);
            app.LayoutBtn.Enable = onoff(has);
            app.BaselineFromEdit.Enable = onoff(ready && app.BaselineCb.Value);
            app.BaselineToEdit.Enable = onoff(ready && app.BaselineCb.Value);
            app.ShowBtn.Enable = onoff(ready);
            app.MeasureBtn.Enable = onoff(shown);
            app.MapsBtn.Enable = onoff(shown);
            app.PolarityDrop.Enable = onoff(peak);
            app.StatsBtn.Enable = onoff(measured && numel(app.Measures) > 1);
            for c = {app.TFFromEdit, app.TFToEdit, app.TFCyclesEdit, app.TFBaseFromEdit, app.TFBaseToEdit, ...
                    app.TFChannelsEdit, app.TFBandDrop, app.TFBtn}
                c{1}.Enable = onoff(ready);
            end
            app.ExportBtn.Enable = onoff(measured || tfDone);
            app.ParticipantDrop.Enable = onoff(shown || tfDone);
            app.ViewDrop.Enable = onoff(shown || tfDone);
            app.CondADrop.Enable = onoff((shown || tfDone) && ~any(strcmp(shownView, app.Views([1 6 7]))));
            app.CondBDrop.Enable = onoff((shown || tfDone) && any(strcmp(shownView, app.Views([3 4 5]))));
            UIKit.setSessionEnable(app.SessionBtns, has);
            setButtonStyle(app.LoadBtn, ifelse(~has, 'primary', 'secondary'));
            setButtonStyle(app.ApplyCleanBtn, ifelse(cleanNext, 'primary', 'secondary'));
            setButtonStyle(app.CutBtn, ifelse(continuous && ~ready && ~cleanNext, 'primary', 'secondary'));
            setButtonStyle(app.ShowBtn, ifelse(ready && ~shown && ~changed, 'primary', 'secondary'));
            setButtonStyle(app.MeasureBtn, ifelse(shown && ~measured, 'primary', 'secondary'));
            setButtonStyle(app.StatsBtn, ifelse(measured && ~tested && numel(app.Measures) > 1, 'primary', 'secondary'));
            setButtonStyle(app.TFBtn, ifelse(ready && ~tfDone && (tested || (measured && numel(app.Measures) < 2)), ...
                'primary', 'secondary'));
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


%% positiveOrEmpty - x when above 0, else [] (0 = off in the number fields)
function x = positiveOrEmpty(x)
    if isempty(x) || x <= 0, x = []; end
end


%% cleaningText - Step 2 settings in one short sentence
function t = cleaningText(cs, nP)
    hp = cs.highPass; lp = cs.lowPass;
    if hp > 0 && lp > 0
        parts = {sprintf('band-pass %g-%g Hz', hp, lp)};
    elseif hp > 0
        parts = {sprintf('high-pass %g Hz', hp)};
    elseif lp > 0
        parts = {sprintf('low-pass %g Hz', lp)};
    else
        parts = {'no band filter'};
    end
    if isfield(cs, 'notchFreqs') && ~isempty(cs.notchFreqs)
        parts{end + 1} = sprintf('notch at %s Hz', strjoin(arrayfun(@(v) sprintf('%g', v), cs.notchFreqs, ...
            'UniformOutput', false), ', '));
    elseif isnumeric(cs.notch)
        parts{end + 1} = sprintf('notch at %g Hz', cs.notch);
    end
    switch cs.referenceMode
        case 'average', parts{end + 1} = 'average reference';
        case 'linked mastoids', parts{end + 1} = 'linked mastoids reference';
        case 'channels', parts{end + 1} = sprintf('reference %s', strjoin(cs.referenceChannels, ', '));
        otherwise, parts{end + 1} = 'reference as recorded';
    end
    nBad = cellfun(@numel, cs.bad);
    if any(nBad > 0)
        every = [cs.bad{:}];
        [~, i] = unique(lower(every), 'first');
        parts{end + 1} = sprintf('bad channels %s (%d of %d participants)', strjoin(every(sort(i)), ', '), ...
            sum(nBad > 0), nP);
    else
        parts{end + 1} = 'no bad channels';
    end
    t = [upper(parts{1}(1)) parts{1}(2:end) '; ' strjoin(parts(2:end), '; ') '.'];
end

%% trialsText - Trials per participant and, after a rejection, what it left out
function t = trialsText(eegs, rej, w)
    n = cellfun(@(e) size(e.data, 3), eegs);
    if ~isempty(rej), n = [rej.total]; end          % before the rejection
    nText = strjoin(arrayfun(@num2str, n, 'UniformOutput', false), ', ');
    if isempty(w)
        t = sprintf('Trials per participant: %s.', nText);
    else
        t = sprintf('Cut from %g to %g ms: %s trials.', w(1) * 1000, w(2) * 1000, nText);
    end
    if isempty(rej), return; end
    % Rejected trials per condition and channels, over the participants
    conds = {};
    for k = 1:numel(rej), conds = [conds, rej(k).conditions]; end %#ok<AGROW>
    conds = EEGSource.stableUnique(conds);
    out = zeros(1, numel(conds));
    names = {};
    counts = [];
    for k = 1:numel(rej)
        [~, j] = ismember(rej(k).conditions, conds);
        out(j) = out(j) + rej(k).before - rej(k).after;
        for i = 1:numel(rej(k).channels)
            c = find(strcmp(names, rej(k).channels{i}), 1);
            if isempty(c), names{end + 1} = rej(k).channels{i}; counts(end + 1) = 0; c = numel(names); end %#ok<AGROW>
            counts(c) = counts(c) + rej(k).channelCounts(i); %#ok<AGROW>
        end
    end
    per = arrayfun(@(c) sprintf('%s %d', conds{c}, out(c)), 1:numel(conds), 'UniformOutput', false);
    t = sprintf('%s Rejected %d of %d (%s)', t, sum([rej.total]) - sum([rej.kept]), sum([rej.total]), strjoin(per, ', '));
    if ~isempty(names)
        [~, order] = sort(counts, 'descend');
        t = sprintf('%s, most often on %s', t, strjoin(names(order(1:min(3, end))), ', '));
    end
    t = sprintf('%s; %s kept.', t, strjoin(arrayfun(@num2str, [rej.kept], 'UniformOutput', false), ', '));
end


%% buildLayout - EEGLayout of a recording with layout settings (source, positionsFile, edits)
% P: the positions file already read ([] = read it here when there is one).
function [L, P] = buildLayout(eeg, ls, P)
    if nargin < 3, P = []; end
    if isempty(ls.positionsFile) || strcmp(ls.source, 'template')
        P = [];
    elseif isempty(P)
        P = readElectrodes(ls.positionsFile);
    end
    L = EEGLayout.fromEEG(eeg, 'Source', ls.source, 'Positions', P, 'Edits', ls.edits);
end

%% layoutEdits - Placements by hand as a struct array label / as / ap / ml (0 x 0 when none)
% as: a 10-5 name ('' = none); ap, ml: mm from bregma (NaN = none).
function out = layoutEdits(E)
    out = struct('label', {}, 'as', {}, 'ap', {}, 'ml', {});
    if isempty(E), return; end
    if ~isstruct(E) || ~isfield(E, 'label')
        error('NeuroAnalyzer:eeg:badOption', ['Placements by hand must be a struct array with label and as ' ...
            '(a 10-5 name), or label, ap and ml (mm from bregma).']);
    end
    for k = 1:numel(E)
        e = struct('label', strtrim(char(E(k).label)), 'as', '', 'ap', NaN, 'ml', NaN);
        if isfield(E, 'as') && (ischar(E(k).as) || isstring(E(k).as)), e.as = strtrim(char(E(k).as)); end
        if isfield(E, 'ap') && isnumeric(E(k).ap) && isscalar(E(k).ap), e.ap = double(E(k).ap); end
        if isfield(E, 'ml') && isnumeric(E(k).ml) && isscalar(E(k).ml), e.ml = double(E(k).ml); end
        if isempty(e.as), e.as = ''; end
        out(end + 1) = e; %#ok<AGROW>
    end
end

%% setEdit - The placements with e for its channel (replaced, else added)
function E = setEdit(E, e)
    E = layoutEdits(E);
    e = layoutEdits(e);
    k = find(strcmpi({E.label}, e.label), 1);
    if isempty(k), k = numel(E) + 1; end
    E(k) = e;
end

%% noLayout - A layout without positions (when making the layout failed)
function L = noLayout(labels, why)
    labels = EEGSource.cellRow(labels);
    n = numel(labels);
    L = struct('kind', 'none', 'labels', {labels}, 'pos', NaN(n, 3), 'source', {repmat({''}, 1, n)}, ...
        'as', {repmat({''}, 1, n)}, 'status', {repmat({'none'}, 1, n)}, 'frame', '', ...
        'notes', {{sprintf('The electrode layout could not be made: %s', why)}}, ...
        'check', struct('matched', {{}}, 'renamed', {cell(0, 2)}, 'missing', {labels}, 'duplicated', {{}}, ...
        'outside', {{}}), 'summary', sprintf('0 of %d channels placed.', n), 'confirmed', false);
end

%% layoutRows - Rows of the layout table
% Scalp: Channel | Placed from | As (the 10-5 name) | Status;
% skull: Channel | AP (mm) | ML (mm) | Status ([] = no position).
function rows = layoutRows(L)
    n = numel(L.labels);
    rows = cell(n, 4);
    skull = strcmp(L.kind, 'skull');
    pairs = EEGLayout.duplicatePairs(L);
    for k = 1:n
        has = all(isfinite(L.pos(k, :)));
        switch L.status{k}
            case 'ok'
                st = 'placed';
            case 'renamed'
                i = find(strcmp(L.check.renamed(:, 1), L.labels{k}), 1);
                if isempty(i)
                    st = 'renamed';
                else
                    st = sprintf('renamed (%s %s %s)', L.check.renamed{i, 1}, char(8594), L.check.renamed{i, 2});
                end
            case 'duplicate'
                other = pairs(any(pairs == k, 2), :);
                other = unique(other(other ~= k))';
                st = sprintf('same place as %s', strjoin(L.labels(other), ', '));
            case 'outside'
                st = 'outside the head';
            otherwise
                st = 'no position';
        end
        if skull
            ap = []; ml = [];
            if has, ap = L.pos(k, 2); ml = L.pos(k, 1); end
            rows(k, :) = {L.labels{k}, ap, ml, st};
        else
            as = L.as{k};
            if isempty(as) && has, as = EEGLayout.cleanName(L.labels{k}); end
            switch L.source{k}
                case 'file', from = 'file';
                case 'template', from = 'name (10-5)';
                case 'positions file', from = 'positions file';
                case 'edited', from = 'by hand';
                otherwise, from = '';
            end
            rows(k, :) = {L.labels{k}, from, as, st};
        end
    end
end

%% layoutSession - The layout settings and what they gave, for the session (settings.layout)
% source, positionsFile, edits, confirmed; kind, counts (channels per
% source: file, template, positionsFile, edited; none; total), renamed
% (n x 2: channel, name used), frame, format (of the positions file),
% summary.
function ly = layoutSession(L, ls, P)
    has = all(isfinite(L.pos), 2)';
    count = @(what) sum(strcmp(L.source, what) & has);
    ly = struct();
    ly.source = ls.source;
    ly.positionsFile = ls.positionsFile;
    ly.edits = layoutEdits(ls.edits);
    ly.confirmed = logical(ls.confirmed);
    ly.kind = L.kind;
    ly.counts = struct('file', count('file'), 'template', count('template'), ...
        'positionsFile', count('positions file'), 'edited', count('edited'), 'none', sum(~has), ...
        'total', numel(L.labels));
    ly.renamed = L.check.renamed;
    ly.frame = L.frame;
    ly.format = '';
    if isstruct(P) && isfield(P, 'format'), ly.format = char(P.format); end
    ly.summary = L.summary;
end

%% rangeRow - Label (column 1) and two numeric fields side by side (column 2) on grid row 'row'
function [a, b] = rangeRow(g, row, labelText, va, vb, tooltip, limits)
    T = UITheme;
    lbl = uilabel(g, 'Text', labelText, 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor, ...
        'Tooltip', tooltip);
    lbl.Layout.Row = row; lbl.Layout.Column = 1;
    rg = uigridlayout(g, [1 3], 'ColumnWidth', {'1x', 10, '1x'}, 'Padding', [0 0 0 0], 'ColumnSpacing', 2, ...
        'BackgroundColor', T.cardBg);
    rg.Layout.Row = row; rg.Layout.Column = 2;
    a = uieditfield(rg, 'numeric', 'Value', va, 'Limits', limits, 'Tooltip', tooltip);
    uilabel(rg, 'Text', char(8211), 'HorizontalAlignment', 'center', 'FontColor', T.bodyColor);
    b = uieditfield(rg, 'numeric', 'Value', vb, 'Limits', limits, 'Tooltip', tooltip);
end

%% tfWhere - 'at Oz' or 'over O1, Oz and O2' (time-frequency titles)
function t = tfWhere(chans)
    if isscalar(chans)
        t = sprintf('at %s', chans{1});
    elseif numel(chans) <= 4
        t = sprintf('over %s', EEGSource.listText(chans));
    else
        t = sprintf('over %d channels', numel(chans));
    end
end

%% noValueColor - Background where a time-frequency image has no value
function c = noValueColor()
    c = [0.86 0.86 0.86];
end

%% mapWindowText - 'mean voltage from 300 to 400 ms' or 'voltage at 100 ms'
function t = mapWindowText(w)
    if abs(w(2) - w(1)) < 1e-9
        t = sprintf('voltage at %g ms', w(1) * 1000);
    else
        t = sprintf('mean voltage from %g to %g ms', w * 1000);
    end
end

%% firstOr - First element of x, or v when x is empty
function y = firstOr(x, v)
    if isempty(x), y = v; else, y = x(1); end
end

%% onoff - 'on'/'off' from a logical
function s = onoff(cond)
    if cond, s = 'on'; else, s = 'off'; end
end

%% ifelse - One of two values
function s = ifelse(cond, a, b)
    if cond, s = a; else, s = b; end
end
