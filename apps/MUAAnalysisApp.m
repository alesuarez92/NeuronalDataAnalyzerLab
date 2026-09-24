%% MUAAnalysisApp.m
% =========================================================================
% MUA ANALYSIS - LOAD MUA, SEGMENT BY STIMULUS, SPIKE SORTING, SPIKE RATE
% =========================================================================
% Launched from Main. Loads .mat saved from ExtractEphysApp (mua_data,
% mua_fs, t_mua, mua_channels; optional stim_data, stim_fs, t_stim).
% Window built with UIKit.window; left column of numbered step cards:
%   1 Load MUA file      - file name, Fs, duration, channels, stimulus yes/no
%                          (or Try demo data: synthetic MUA with known units)
%   2 Channel & segments - channel dropdown; optional segmentation by
%                          stimulation onsets (parameters in a UIKit.dialog)
%   3 Spike sorting      - Configure... (UIKit.dialog: detection threshold
%                          and polarity, features, clustering, auto-merge
%                          of over-split clusters, drift correction) and Run
%   4 Clusters           - cluster listbox (multi-select), Select all /
%                          Clear / Undo, Merge selected / Split selected,
%                          quality summary
%   5 Export             - save spike times, cluster IDs and QC to .mat
% Right side: tabs 'Signal & spikes', 'Waveforms', 'Clusters',
% 'Spike rate', 'Raster & PSTH' (per unit, locked to stimulus onsets),
% 'Correlograms' (auto / cross, up to 4 units) and 'Quality' (QC table,
% ISI histograms, alignment check). Raster and correlogram tabs are
% redrawn when shown (refreshLazyTabs).
% One updateControls() enables controls from the data state and marks the
% next recommended action as primary. Help button opens HelpApp on the
% "MUA Analysis" tab. Analysis: runSpikeSorting (wrapper with busy dialog)
% -> doSpikeSorting -> MUAPipeline.sort (headless detection, alignment,
% features, clustering, auto-merge, QC). Cluster edits use ClusterTools and
% are undoable (EditHistory); rasters / PSTHs / correlograms use
% SpikeTrains. The drift-correction merging helpers live in MUAPipeline
% (the app methods of the same name delegate to it).
% Scriptable (CI walkthroughs, no dialogs): openFile(path), loadDemo(),
% runSorting(params), autoMergeClusters(opts), mergeClusters(ids),
% splitCluster(id), undoClusterEdit(), showRasterPSTH(unitIds, window,
% bin), showCorrelograms(unitIds, maxLagMs, binMs).
% Sessions (step 5 buttons; core/Session.m, core/Report.m):
% saveSessionTo(path, notes), openSession(path), makeReport(pdfPath),
% sessionState(), restoreSession(s). A session stores the MUA file (with
% MD5), channel, segmentation, sorting and display settings, and the
% sorting results including cluster edits and their Undo history; these
% are restored as saved (K-means and manual edits are not re-run).
% =========================================================================

classdef MUAAnalysisApp < handle

    %% PROPERTIES
    % ---------------------------------------------------------------------
    % UI handles (by step card and plot tab), loaded data, sorting params
    % and results, plus display-only state derived from the last sort.
    % ---------------------------------------------------------------------
    properties
        UIFig               % Main uifigure (UIKit.window)
        StatusLabel         % Status bar label (UIKit.setStatus)
        % Step 1 - Load
        LoadBtn             % Load MUA .mat
        DemoBtn             % Try demo data (synthetic MUA with known units)
        FileLabel           % Loaded file name
        FileInfoLabel       % Fs, duration, channels, stimulus yes/no
        % Step 2 - Channel & segments
        ChannelMenu         % uidropdown; Value = channel row index
        SegmentCheckbox     % Segment by stimulation onsets
        SegmentMenu         % uidropdown; Value = segment index
        SegmentInfoLabel    % Number of segments / onset parameters
        % Step 3 - Spike sorting
        ConfigureBtn        % Opens the spike sorting configuration dialog
        RunBtn              % Runs spike sorting with SpikeSortParams
        ParamsLabel         % One-line summary of the current settings
        % Step 4 - Clusters
        ClusterSelectMenu   % uilistbox (multi-select); ItemsData = position
                            % in unique(SpikeResults.clusterIdx)
        SelectAllBtn        % Select every unit (noise excluded)
        ClearBtn            % Clear the cluster selection
        UndoBtn             % Undo the last merge / split / auto-merge
        MergeBtn            % Merge the selected units into one
        SplitBtn            % Split the selected unit in two
        QualityLabel        % Units / rejected / noise summary
        % Step 5 - Export
        SaveBtn             % Save results to .mat
        % Plots
        TabGroup            % uitabgroup with the result tabs
        AxStim              % Stimulus trace (+ segment shading)
        AxMUA               % MUA trace, thresholds and sorted spikes
        WaveformPanel       % uipanel holding the per-cluster tiledlayout
        AxFeatures          % Clusters in waveform PCA space
        AxRate              % Spike rate over time
        RateBinField        % Rate bin width (s)
        RateRelativeCheck   % Plot rate as fraction of spikes per bin
        RasterTab           % 'Raster & PSTH' tab
        RasterPanel         % uipanel holding the raster / PSTH tiledlayout
        RasterFromField     % Window start relative to onset (s)
        RasterToField       % Window end relative to onset (s)
        RasterBinField      % PSTH bin width (ms)
        RasterInfoLabel     % Trials / onset detection summary
        CorrTab             % 'Correlograms' tab
        CorrPanel           % uipanel holding the correlogram grid
        CorrLagField        % Maximum lag (ms)
        CorrBinField        % Correlogram bin width (ms)
        CorrInfoLabel       % How to read the grid
        QualityTable        % uitable: per-cluster QC metrics
        AxISI               % ISI histograms of the selected clusters
        AxAlignBefore       % Waveforms before peak alignment
        AxAlignAfter        % Waveforms after peak alignment
        % Data
        FilePath            % Full path of the loaded file
        MUAData             % Struct: data (ch x samples), fs, time, channels
        StimData            % Struct: signal, fs, time ([] if no stimulus)
        Segments            % [nSeg x 2] segment windows (s), [] when off
        SegmentParams       % Struct: minISI, threshold, preTime, postTime
        SpikeSortParams     % Spike sorting parameters (see defaultSortParams)
        SpikeResults        % Spike times, cluster IDs, waveforms, SNR, ...
        % Display-only state from the last successful sort
        SortContext         % Struct: chIdx, channel, segIdx, segWin
        SpikeLocs           % Sample index of each spike in the sorted trace
        ThreshLines         % Detection thresholds on the MUA scale
        ClusterQC           % Struct array: id, n, snr, isiPct, isiMs, rejected, reason
        DisplayPCs          % [nSpikes x 2] waveform PCA scores (for plotting)
        SpikeWaves          % [nSpikes x samples] aligned waveform per spike
                            % (same order as SpikeResults.clusterIdx)
        EditHistory         % Struct array (labels, description, edits): the
                            % cluster labels before each merge / split / auto-merge
        ClusterEdits        % Cellstr: edits applied since the sort (saved in info)
        RasterDirty = true  % Raster & PSTH tab needs a redraw when shown
        CorrDirty = true    % Correlograms tab needs a redraw when shown
        RasterOutcome = struct('ok', false, 'msg', '')  % Result of the last raster draw
        CorrOutcome = struct('ok', false, 'msg', '')    % Result of the last correlogram draw
        BusyDlg             % uiprogressdlg while sorting
        SessionBtns         % Step 5: Save session / Open session / Report (UIKit.sessionButtons)
    end

    methods
        %% Constructor - Build UI; data loaded via Load MUA file or loadDemo
        % -------------------------------------------------------------
        % Must not open dialogs or block (CI smoke test screenshots UIFig).
        % -------------------------------------------------------------
        function app = MUAAnalysisApp()
            app.SpikeSortParams = defaultSortParams();
            app.EditHistory = emptyHistory();
            app.ClusterEdits = {};
            app.buildUI();
        end

        %% buildUI - Step cards on the left, result tabs on the right
        % -------------------------------------------------------------
        function buildUI(app)
            T = UITheme;
            W = UIKit.window('MUA Analysis', ...
                'Detect and sort spikes from multi-unit activity, then check quality and firing rate', ...
                'MUA Analysis', [1280 920]);
            app.UIFig = W.Fig;
            app.StatusLabel = W.Status;
            W.Body.RowHeight = {'1x'};
            W.Body.ColumnWidth = {310, '1x'};

            left = uigridlayout(W.Body, [5 1], ...
                'RowHeight', {136, 160, 124, '1x', 84 + UIKit.sessionButtonsHeight() + 6}, 'ColumnWidth', {'1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 8, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;

            % --- 1 Load MUA file ---
            g = stepCard(left, 1, 'Load MUA file', {T.buttonHeight, 'fit', 'fit'}, {'1x', '1x'});
            app.LoadBtn = UIKit.button(g, 'Load MUA file...', @(~,~)app.loadData(), 'primary', ...
                'Open a .mat file saved by Extract Ephys (MUA channels, optional stimulus)');
            app.LoadBtn.Layout.Row = 2; app.LoadBtn.Layout.Column = 1;
            app.DemoBtn = UIKit.button(g, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Load synthetic data with known answers: 3 units on channels 4-5 that fire more ' ...
                 'after each stimulus (every 2 s)']);
            app.DemoBtn.Layout.Row = 2; app.DemoBtn.Layout.Column = 2;
            app.FileLabel = uilabel(g, 'Text', 'No file loaded', 'FontSize', T.fontBody, ...
                'FontColor', T.sectionTitleColor, 'FontWeight', 'bold', 'Interpreter', 'none');
            app.FileLabel.Layout.Row = 3; app.FileLabel.Layout.Column = [1 2];
            app.FileInfoLabel = uilabel(g, 'Text', 'Sampling rate, duration and channels appear here', ...
                'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'WordWrap', 'on');
            app.FileInfoLabel.Layout.Row = 4; app.FileInfoLabel.Layout.Column = [1 2];

            % --- 2 Channel & segments ---
            g = stepCard(left, 2, 'Channel & segments', ...
                {T.controlHeight, T.controlHeight, T.controlHeight, 'fit'}, {80, '1x'});
            lbl = uilabel(g, 'Text', 'Channel', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            lbl.Layout.Row = 2; lbl.Layout.Column = 1;
            app.ChannelMenu = uidropdown(g, 'Items', {'-'}, 'ItemsData', 0, ...
                'Tooltip', 'Recording channel to analyse', ...
                'ValueChangedFcn', @(~,~)app.updateMUAPlot());
            app.ChannelMenu.Layout.Row = 2; app.ChannelMenu.Layout.Column = 2;
            app.SegmentCheckbox = uicheckbox(g, 'Text', 'Segment by stimulation onsets', ...
                'FontSize', T.fontBody, 'Tooltip', ...
                ['Split the recording into trials around each stimulus onset and analyse ' ...
                 'one trial at a time. Needs a stimulus channel in the file.'], ...
                'ValueChangedFcn', @(~,~)app.handleSegmentationToggle());
            app.SegmentCheckbox.Layout.Row = 3; app.SegmentCheckbox.Layout.Column = [1 2];
            lbl = uilabel(g, 'Text', 'Segment', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            lbl.Layout.Row = 4; lbl.Layout.Column = 1;
            app.SegmentMenu = uidropdown(g, 'Items', {'-'}, 'ItemsData', 0, ...
                'Tooltip', 'Trial (stimulus onset) to show and sort; time is relative to the segment start', ...
                'ValueChangedFcn', @(~,~)app.updateMUAPlot());
            app.SegmentMenu.Layout.Row = 4; app.SegmentMenu.Layout.Column = 2;
            app.SegmentInfoLabel = uilabel(g, 'Text', 'Full recording', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');
            app.SegmentInfoLabel.Layout.Row = 5; app.SegmentInfoLabel.Layout.Column = [1 2];

            % --- 3 Spike sorting ---
            g = stepCard(left, 3, 'Spike sorting', {'fit', T.buttonHeight}, {'1x', '1x'});
            app.ParamsLabel = uilabel(g, 'Text', '', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');
            app.ParamsLabel.Layout.Row = 2; app.ParamsLabel.Layout.Column = [1 2];
            app.ConfigureBtn = UIKit.button(g, 'Configure...', @(~,~)app.configureSpikeSorting(), ...
                'secondary', 'Choose detection method, threshold, polarity, features and clustering');
            app.ConfigureBtn.Layout.Row = 3; app.ConfigureBtn.Layout.Column = 1;
            app.RunBtn = UIKit.button(g, 'Run', @(~,~)app.runSpikeSorting(app.SpikeSortParams), ...
                'secondary', 'Detect and cluster spikes on the selected channel (and segment) with the current settings');
            app.RunBtn.Layout.Row = 3; app.RunBtn.Layout.Column = 2;

            % --- 4 Clusters ---
            g = stepCard(left, 4, 'Clusters', {96, T.buttonHeight, T.buttonHeight, 'fit'}, {'1x', '1x'});   % list: ~5 rows
            app.ClusterSelectMenu = uilistbox(g, 'Items', {}, 'Multiselect', 'on', ...
                'FontSize', T.fontBody, 'Tooltip', ...
                'Clusters shown in the plots. Ctrl/Shift-click to select several. Cluster 0 is noise (unclustered spikes).', ...
                'ValueChangedFcn', @(~,~)app.updateClusterScatter());
            app.ClusterSelectMenu.Layout.Row = 2; app.ClusterSelectMenu.Layout.Column = [1 2];
            selRow = uigridlayout(g, [1 3], 'ColumnWidth', {'1x', '1x', '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            selRow.Layout.Row = 3; selRow.Layout.Column = [1 2];
            app.SelectAllBtn = UIKit.button(selRow, 'Select all', @(~,~)app.selectAllClusters(), ...
                'secondary', 'Select every unit (noise cluster 0 excluded)');
            app.ClearBtn = UIKit.button(selRow, 'Clear', @(~,~)app.clearClusterSelection(), ...
                'secondary', 'Deselect all clusters');
            app.UndoBtn = UIKit.button(selRow, 'Undo', @(~,~)app.undoClusterEdit(), 'secondary', ...
                ['Undo last change: restore the clusters as they were before the last merge, ' ...
                 'split or auto-merge (repeat to go further back)']);
            app.MergeBtn = UIKit.button(g, 'Merge selected', @(~,~)app.mergeClusters(), 'secondary', ...
                ['Merge the selected units into one (the lowest cluster number is kept). Use it when ' ...
                 'two clusters have the same waveform: one neuron split in two.']);
            app.MergeBtn.Layout.Row = 4; app.MergeBtn.Layout.Column = 1;
            app.SplitBtn = UIKit.button(g, 'Split selected', @(~,~)app.splitCluster(), 'secondary', ...
                ['Split the selected unit in two (k-means on its waveform PCA). Use it when a cluster ' ...
                 'mixes two waveforms or has many ISI violations.']);
            app.SplitBtn.Layout.Row = 4; app.SplitBtn.Layout.Column = 2;
            app.QualityLabel = uilabel(g, 'Text', 'Run spike sorting to see clusters', ...
                'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'WordWrap', 'on');
            app.QualityLabel.Layout.Row = 5; app.QualityLabel.Layout.Column = [1 2];

            % --- 5 Export ---
            g = stepCard(left, 5, 'Export', {T.buttonHeight, UIKit.sessionButtonsHeight()});
            app.SaveBtn = UIKit.button(g, 'Save results...', @(~,~)app.saveResults(), 'secondary', ...
                'Save spike times, cluster IDs, waveforms, quality metrics and settings to a .mat file');
            app.SaveBtn.Layout.Row = 2;
            app.SessionBtns = UIKit.sessionButtons(g, app);
            app.SessionBtns.Grid.Layout.Row = 3;

            % --- Plots: one tab per view ---
            app.TabGroup = uitabgroup(W.Body);
            app.TabGroup.Layout.Row = 1; app.TabGroup.Layout.Column = 2;

            tab = uitab(app.TabGroup, 'Title', 'Signal & spikes', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(tab, [2 1], 'RowHeight', {'1x', '3x'}, 'ColumnWidth', {'1x'}, ...
                'Padding', [8 8 8 8], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            app.AxStim = uiaxes(tg);
            app.AxMUA = uiaxes(tg);

            tab = uitab(app.TabGroup, 'Title', 'Waveforms', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(tab, [1 1], 'Padding', [8 8 8 8], 'BackgroundColor', T.cardBg);
            app.WaveformPanel = uipanel(tg, 'BorderType', 'none', 'BackgroundColor', T.cardBg);

            tab = uitab(app.TabGroup, 'Title', 'Clusters (feature space)', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(tab, [1 1], 'Padding', [8 8 8 8], 'BackgroundColor', T.cardBg);
            app.AxFeatures = uiaxes(tg);

            tab = uitab(app.TabGroup, 'Title', 'Spike rate', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(tab, [2 1], 'RowHeight', {T.controlHeight, '1x'}, ...
                'ColumnWidth', {'1x'}, 'Padding', [8 8 8 8], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            bar = uigridlayout(tg, [1 4], 'ColumnWidth', {70, 80, 320, '1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
            uilabel(bar, 'Text', 'Bin (s)', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor, ...
                'HorizontalAlignment', 'right');
            app.RateBinField = uieditfield(bar, 'numeric', 'Value', 1, 'Limits', [0 Inf], ...
                'LowerLimitInclusive', 'off', 'Tooltip', 'Width of each time bin for counting spikes (s)', ...
                'ValueChangedFcn', @(~,~)app.plotSpikeRateOverTime());
            app.RateRelativeCheck = uicheckbox(bar, 'Text', 'Relative rate (fraction of spikes per bin)', ...
                'Value', false, 'FontSize', T.fontBody, ...
                'Tooltip', 'Off: firing rate in Hz. On: each bin as a fraction of that cluster''s spikes.', ...
                'ValueChangedFcn', @(~,~)app.plotSpikeRateOverTime());
            app.AxRate = uiaxes(tg);

            % Raster & PSTH: window / bin controls, then one column per unit
            app.RasterTab = uitab(app.TabGroup, 'Title', 'Raster & PSTH', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(app.RasterTab, [2 1], 'RowHeight', {T.controlHeight, '1x'}, ...
                'ColumnWidth', {'1x'}, 'Padding', [8 8 8 8], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            bar = uigridlayout(tg, [1 7], 'ColumnWidth', {70, 64, 50, 64, 64, 56, '1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            barLabel(bar, 'From (s)');
            app.RasterFromField = uieditfield(bar, 'numeric', 'Value', -0.1, 'Limits', [-60 60], ...
                'Tooltip', 'Start of the window around each stimulus onset (s); negative = before the stimulus', ...
                'ValueChangedFcn', @(~,~)app.plotRasterPSTH());
            barLabel(bar, 'To (s)');
            app.RasterToField = uieditfield(bar, 'numeric', 'Value', 0.3, 'Limits', [-60 60], ...
                'Tooltip', 'End of the window around each stimulus onset (s after the onset)', ...
                'ValueChangedFcn', @(~,~)app.plotRasterPSTH());
            barLabel(bar, 'Bin (ms)');
            app.RasterBinField = uieditfield(bar, 'numeric', 'Value', 5, 'Limits', [0.1 10000], ...
                'Tooltip', 'Width of each PSTH bin (ms)', 'ValueChangedFcn', @(~,~)app.plotRasterPSTH());
            app.RasterInfoLabel = uilabel(bar, 'Text', '', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');
            app.RasterPanel = uipanel(tg, 'BorderType', 'none', 'BackgroundColor', T.cardBg);

            % Correlograms: lag / bin controls, then an n x n grid
            app.CorrTab = uitab(app.TabGroup, 'Title', 'Correlograms', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(app.CorrTab, [2 1], 'RowHeight', {T.controlHeight, '1x'}, ...
                'ColumnWidth', {'1x'}, 'Padding', [8 8 8 8], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            bar = uigridlayout(tg, [1 5], 'ColumnWidth', {86, 64, 56, 64, '1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            barLabel(bar, 'Max lag (ms)');
            app.CorrLagField = uieditfield(bar, 'numeric', 'Value', 50, 'Limits', [0.5 10000], ...
                'Tooltip', 'Largest time difference between two spikes shown (ms), both directions', ...
                'ValueChangedFcn', @(~,~)app.plotCorrelograms());
            barLabel(bar, 'Bin (ms)');
            app.CorrBinField = uieditfield(bar, 'numeric', 'Value', 1, 'Limits', [0.05 1000], ...
                'Tooltip', 'Width of each correlogram bin (ms)', 'ValueChangedFcn', @(~,~)app.plotCorrelograms());
            app.CorrInfoLabel = uilabel(bar, 'Text', '', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');
            app.CorrPanel = uipanel(tg, 'BorderType', 'none', 'BackgroundColor', T.cardBg);
            app.TabGroup.SelectionChangedFcn = @(~,~)app.refreshLazyTabs();

            tab = uitab(app.TabGroup, 'Title', 'Quality', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(tab, [3 1], 'RowHeight', {36, '1x', '1.4x'}, 'ColumnWidth', {'1x'}, ...
                'Padding', [8 8 8 8], 'RowSpacing', 8, 'BackgroundColor', T.cardBg);
            UIKit.hint(tg, ['SNR = peak-to-peak / (2 x baseline SD); a unit with SNR < 2 is rejected. ' ...
                'ISI < refractory = % of inter-spike intervals shorter than the refractory period; ' ...
                'more than 2% is rejected. Rejected clusters show as x markers on the signal.']);
            app.QualityTable = uitable(tg, 'ColumnName', ...
                {'Cluster', 'Spikes', 'Rate (Hz)', 'SNR', 'ISI < refractory (%)', 'Status'}, ...
                'RowName', {}, 'FontSize', T.fontSmall);
            bottom = uigridlayout(tg, [1 3], 'ColumnWidth', {'1x', '1x', '1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
            app.AxISI = uiaxes(bottom);
            app.AxAlignBefore = uiaxes(bottom);
            app.AxAlignAfter = uiaxes(bottom);

            app.plotSignal();
            app.refreshResultPlots();
            app.updateParamsLabel();
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, 'Ready - load a MUA file to begin (step 1)', 'info');
        end

        %% updateControls - Enable/disable controls from the data state
        % -------------------------------------------------------------
        % Next recommended action is primary: Load -> Run -> Save.
        % -------------------------------------------------------------
        function updateControls(app)
            hasData = ~isempty(app.MUAData);
            hasStim = ~isempty(app.StimData);
            hasSeg = hasData && app.SegmentCheckbox.Value && ~isempty(app.Segments);
            hasRes = app.hasResults();
            isCurrent = app.resultsCurrent();

            app.ChannelMenu.Enable = onOff(hasData);
            app.SegmentCheckbox.Enable = onOff(hasData && hasStim);
            app.SegmentMenu.Enable = onOff(hasSeg);
            app.ConfigureBtn.Enable = onOff(hasData);
            app.RunBtn.Enable = onOff(hasData);
            app.ClusterSelectMenu.Enable = onOff(hasRes);
            app.SelectAllBtn.Enable = onOff(hasRes);
            app.ClearBtn.Enable = onOff(hasRes);
            app.SaveBtn.Enable = onOff(hasRes);
            UIKit.setSessionEnable(app.SessionBtns, hasData);
            app.RateBinField.Enable = onOff(hasRes);
            app.RateRelativeCheck.Enable = onOff(hasRes);
            selIds = app.selectedClusterIds();
            nSelUnits = sum(selIds > 0);
            app.MergeBtn.Enable = onOff(hasRes && nSelUnits >= 2);
            app.SplitBtn.Enable = onOff(hasRes && nSelUnits == 1);
            app.UndoBtn.Enable = onOff(hasRes && ~isempty(app.EditHistory));
            set([app.RasterFromField, app.RasterToField, app.RasterBinField, ...
                app.CorrLagField, app.CorrBinField], 'Enable', onOff(hasRes));

            setButtonStyle(app.LoadBtn, ~hasData);
            setButtonStyle(app.RunBtn, hasData && ~isCurrent);
            setButtonStyle(app.SaveBtn, hasRes && isCurrent);
        end

        %% hasResults - True when a spike sort finished successfully
        function tf = hasResults(app)
            tf = isstruct(app.SpikeResults) && isfield(app.SpikeResults, 'clusterIdx') && ...
                ~isempty(app.SpikeResults.clusterIdx) && isfield(app.SpikeResults, 'spikeTimes') && ...
                ~isempty(app.SortContext);
        end

        %% resultsCurrent - True when results match the selected channel/segment
        function tf = resultsCurrent(app)
            tf = false;
            if ~app.hasResults() || isempty(app.SortContext) || isempty(app.MUAData), return; end
            [chIdx, segIdx, segWin] = app.currentSelection();
            tf = isequal(app.SortContext.chIdx, chIdx) && isequal(app.SortContext.segIdx, segIdx) && ...
                isequal(app.SortContext.segWin, segWin);
        end

        %% currentSelection - Selected channel row, segment index and window
        % segIdx / segWin are [] when the full recording is used.
        function [chIdx, segIdx, segWin] = currentSelection(app)
            chIdx = app.ChannelMenu.Value;
            segIdx = []; segWin = [];
            if app.SegmentCheckbox.Value && ~isempty(app.Segments)
                segIdx = app.SegmentMenu.Value;
                segWin = app.Segments(segIdx, :);
            end
        end

        %% loadData - Pick a .mat from Extract Ephys and show it
        % -------------------------------------------------------------
        % Interactive: asks for the file, then openFile does the rest.
        % -------------------------------------------------------------
        function loadData(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir), startDir = Exporter.getLastUsedPath(); end
            if isempty(startDir) || ~exist(startDir, 'dir'), startDir = pwd; end
            [file, path] = uigetfile('*.mat', 'Select MUA data file', startDir);
            figure(app.UIFig);
            if isequal(file, 0)
                UIKit.setStatus(app.StatusLabel, 'Loading cancelled', 'info');
                return;
            end
            app.openFile(fullfile(path, file));
        end

        %% openFile - Load a MUA .mat (no dialogs) and show it
        % -------------------------------------------------------------
        % Requires mua_data, mua_fs, t_mua, mua_channels; stim_data,
        % stim_fs and t_stim are optional. Resets segmentation and any
        % previous sorting results. rememberFolder (default true) stores
        % the folder as the last used path. Returns true on success.
        % -------------------------------------------------------------
        function ok = openFile(app, fullPath, rememberFolder)
            if nargin < 3, rememberFolder = true; end
            ok = false;
            [path, name, ext] = fileparts(fullPath);
            file = [name ext];
            UIKit.setStatus(app.StatusLabel, sprintf('Loading %s...', file), 'busy');
            dlg = UIKit.busy(app.UIFig, sprintf('Loading %s...', file));
            try
                data = load(fullPath);
                needed = {'mua_data', 'mua_fs', 't_mua', 'mua_channels'};
                missing = needed(~isfield(data, needed));
                if ~isempty(missing)
                    UIKit.done(dlg);
                    UIKit.alert(app.UIFig, sprintf(['%s is not a MUA file: missing %s. ' ...
                        'Save MUA data with Extract Ephys first.'], file, strjoin(missing, ', ')), ...
                        'Cannot load file', 'error');
                    UIKit.setStatus(app.StatusLabel, sprintf('Could not load %s (not a MUA file)', file), 'error');
                    return;
                end

                app.MUAData = struct();
                app.MUAData.data = data.mua_data;
                app.MUAData.fs = data.mua_fs;
                app.MUAData.time = data.t_mua;
                app.MUAData.channels = data.mua_channels;
                app.FilePath = fullPath;

                % Reset segmentation and sorting state from any previous file
                app.Segments = [];
                app.SegmentCheckbox.Value = 0;
                app.SegmentMenu.Items = {'-'};
                app.SegmentMenu.ItemsData = 0;
                app.SegmentInfoLabel.Text = 'Full recording';
                app.clearResults();

                if isfield(data, 'stim_data') && isfield(data, 'stim_fs') && isfield(data, 't_stim')
                    app.StimData = struct();
                    app.StimData.signal = data.stim_data;
                    app.StimData.fs = data.stim_fs;
                    app.StimData.time = data.t_stim;
                else
                    % No stimulus in this file: clear any stale stimulus
                    app.StimData = [];
                end

                chNames = compose('Ch %d', app.MUAData.channels);
                app.ChannelMenu.Items = cellstr(chNames);
                app.ChannelMenu.ItemsData = 1:numel(chNames);
                app.ChannelMenu.Value = 1;

                fs = app.MUAData.fs;
                durSec = size(app.MUAData.data, 2) / fs;
                app.FileLabel.Text = file;
                app.FileLabel.Tooltip = app.FilePath;
                app.FileInfoLabel.Text = sprintf('%s Hz  ·  %s  ·  %d channel%s  ·  stimulus: %s', ...
                    num2str(fs), formatDuration(durSec), numel(app.MUAData.channels), ...
                    plural(numel(app.MUAData.channels)), yesNo(~isempty(app.StimData)));
                if rememberFolder, Exporter.setLastUsedPath(path); end

                app.plotSignal();
                app.refreshResultPlots();
                UIKit.done(dlg);
                app.updateControls();
                UIKit.setStatus(app.StatusLabel, sprintf('Loaded %s (%s Hz, %s, %d channels) - next: Run spike sorting (step 3)', ...
                    file, num2str(fs), formatDuration(durSec), numel(app.MUAData.channels)), 'success');
                ok = true;
            catch ME
                UIKit.done(dlg);
                app.updateControls();
                UIKit.alert(app.UIFig, sprintf('Could not load %s:\n%s', file, ME.message), ...
                    'Cannot load file', 'error');
                UIKit.setStatus(app.StatusLabel, sprintf('Error loading %s: %s', file, ME.message), 'error');
            end
        end

        %% loadDemo - Load the synthetic MUA file (known units) and pre-fill settings
        % -------------------------------------------------------------
        % DemoData 'mua': channels 3-5 at 24414 Hz; units 1 (~90 uV) and 2
        % (~50 uV) on ch 4, unit 3 (~110 uV) on ch 5; firing rises for
        % 50 ms after each stimulus (every 2 s from 1 s). Selects ch 4 and
        % sets detection to MAD, k = 4, negative spikes. Returns true on success.
        % -------------------------------------------------------------
        function ok = loadDemo(app)
            ok = false;
            dlg = UIKit.busy(app.UIFig, sprintf('Preparing demo data (first time only takes a few seconds)%s', char(8230)));
            UIKit.setStatus(app.StatusLabel, 'Preparing demo data', 'busy');
            try
                p = DemoData.file('mua');
            catch ME
                UIKit.done(dlg);
                UIKit.alert(app.UIFig, sprintf('Could not create the demo data:\n%s', ME.message), ...
                    'Demo data', 'error');
                UIKit.setStatus(app.StatusLabel, sprintf('Demo data failed: %s', ME.message), 'error');
                return;
            end
            UIKit.done(dlg);
            if ~app.openFile(p, false), return; end
            ch4 = find(app.MUAData.channels == 4, 1);
            if ~isempty(ch4), app.ChannelMenu.Value = ch4; end
            params = defaultSortParams();
            params.detectMethod = 'MAD';
            params.threshold = 4;
            params.polarity = 'negative';
            app.SpikeSortParams = params;
            app.updateParamsLabel();
            app.plotSignal();
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, ['Demo loaded (ch 4: units of ~90 and ~50 µV). ' ...
                'Click Run: expect 2-3 units firing 5-55 ms after each stimulus.'], 'success');
            ok = true;
        end

        %% runSorting - Spike sorting without the Configure dialog (scripts / CI)
        % -------------------------------------------------------------
        % params: full or partial struct of sorting settings (missing
        % fields come from defaultSortParams); omitted or [] = the current
        % settings. Returns true when sorting produced results.
        % -------------------------------------------------------------
        function ok = runSorting(app, params)
            if nargin < 2 || isempty(params)
                params = app.SpikeSortParams;
            else
                merged = defaultSortParams();
                fn = fieldnames(params);
                for i = 1:numel(fn), merged.(fn{i}) = params.(fn{i}); end
                params = merged;
            end
            app.SpikeSortParams = params;
            app.updateParamsLabel();
            app.runSpikeSorting(params);
            ok = app.hasResults();
        end

        %% handleSegmentationToggle - Detect stimulus onsets and build segments
        % -------------------------------------------------------------
        % Onsets: rising crossings of the stimulus threshold, keeping only
        % onsets more than minISI after the previous one. Each segment is
        % [onset - preTime, onset + postTime] (s).
        % -------------------------------------------------------------
        function handleSegmentationToggle(app)
            if app.SegmentCheckbox.Value
                if isempty(app.StimData)
                    app.SegmentCheckbox.Value = 0;
                    app.updateControls();
                    UIKit.alert(app.UIFig, 'No stimulation data in the loaded file; cannot segment.', ...
                        'Segmentation', 'warning');
                    UIKit.setStatus(app.StatusLabel, 'Cannot segment: this file has no stimulus channel', 'warning');
                    return;
                end
                answer = app.askSegmentParams();
                if isempty(answer)
                    app.SegmentCheckbox.Value = 0;
                    app.updateControls();
                    UIKit.setStatus(app.StatusLabel, 'Segmentation cancelled - using the full recording', 'info');
                    return;
                end
                minISI = answer.minISI;
                threshold = answer.threshold;
                preTime = answer.preTime;
                postTime = answer.postTime;
                % All rising crossings of the threshold (minISI applied below)
                onsetTimes = SpikeTrains.stimulusOnsets(app.StimData.signal, app.StimData.time, ...
                    threshold, -Inf);
                if isempty(onsetTimes)
                    app.Segments = [];
                    app.SegmentCheckbox.Value = 0;
                    app.SegmentMenu.Items = {'-'};
                    app.SegmentMenu.ItemsData = 0;
                    app.updateMUAPlot();
                    UIKit.alert(app.UIFig, sprintf(['No stimulus onsets found: the stimulus never rises ' ...
                        'above %g. Try a lower threshold.'], threshold), 'Segmentation', 'warning');
                    UIKit.setStatus(app.StatusLabel, 'No stimulus onsets found - lower the threshold', 'warning');
                    return;
                end
                isi = [Inf; diff(onsetTimes(:))];
                onsetTimes = onsetTimes(isi > minISI);
                segs = [onsetTimes(:) - preTime, onsetTimes(:) + postTime];
                app.Segments = segs;
                app.SegmentParams = struct('minISI', minISI, 'threshold', threshold, 'preTime', preTime, 'postTime', postTime);
                segNames = arrayfun(@(i) sprintf('Segment %d  (onset %.2f s)', i, onsetTimes(i)), ...
                    1:size(segs,1), 'UniformOutput', false);
                app.SegmentMenu.Items = segNames;
                app.SegmentMenu.ItemsData = 1:size(segs,1);
                app.SegmentMenu.Value = 1;
                app.SegmentInfoLabel.Text = sprintf('%d segment%s: %.2f s before to %.2f s after each onset', ...
                    size(segs,1), plural(size(segs,1)), preTime, postTime);
                app.updateMUAPlot();
                % The Raster & PSTH tab uses the same onset threshold / minimum ISI
                app.RasterDirty = true;
                app.refreshLazyTabs();
                UIKit.setStatus(app.StatusLabel, sprintf('Found %d stimulus onset%s - pick a segment, then Run spike sorting', ...
                    size(segs,1), plural(size(segs,1))), 'success');
            else
                app.Segments = [];
                app.SegmentMenu.Items = {'-'};
                app.SegmentMenu.ItemsData = 0;
                app.SegmentInfoLabel.Text = 'Full recording';
                app.updateMUAPlot();
                UIKit.setStatus(app.StatusLabel, 'Segmentation off - using the full recording', 'info');
            end
        end

        %% askSegmentParams - Modal dialog for onset detection parameters
        % Returns struct (minISI, threshold, preTime, postTime) or [] if cancelled.
        function answer = askSegmentParams(app)
            answer = [];
            prev = app.SegmentParams;
            if isempty(prev)
                prev = defaultSegmentParams();
            end
            D = UIKit.dialog('Stimulation onsets', 'Split the recording into trials', 'MUA Analysis', [420 330]);
            D.Body.RowHeight = repmat({UITheme.controlHeight}, 1, 4);
            D.Body.ColumnWidth = {'1.3x', '1x'};
            isiField = placeField(D.Body, 1, 'Minimum ISI (s)', 'numeric', prev.minISI, ...
                'Onsets closer than this to the previous onset are ignored (s)', [0 Inf]);
            thrField = placeField(D.Body, 2, 'Threshold (stimulus units)', 'numeric', prev.threshold, ...
                'An onset is where the stimulus signal rises above this value', [-Inf Inf]);
            preField = placeField(D.Body, 3, 'Pre-stimulus (s)', 'numeric', prev.preTime, ...
                'Time kept before each onset (s)', [0 Inf]);
            postField = placeField(D.Body, 4, 'Post-stimulus (s)', 'numeric', prev.postTime, ...
                'Time kept after each onset (s)', [0 Inf]);
            postField.LowerLimitInclusive = 'off';
            cancelBtn = UIKit.button(D.Buttons, 'Cancel', @(~,~)delete(D.Fig), 'secondary', 'Keep the full recording');
            cancelBtn.Layout.Column = 2;
            okBtn = UIKit.button(D.Buttons, 'OK', @(~,~)onOK(), 'primary', 'Detect onsets and build segments');
            okBtn.Layout.Column = 3;
            uiwait(D.Fig);

            function onOK()
                answer = struct('minISI', isiField.Value, 'threshold', thrField.Value, ...
                    'preTime', preField.Value, 'postTime', postField.Value);
                delete(D.Fig);
            end
        end

        %% updateMUAPlot - Channel / segment changed: redraw and report
        function updateMUAPlot(app)
            if isempty(app.MUAData), return; end
            app.plotSignal();
            app.updateControls();
            [chIdx, segIdx] = app.currentSelection();
            where = sprintf('Ch %d', app.MUAData.channels(chIdx));
            if ~isempty(segIdx), where = sprintf('%s, segment %d', where, segIdx); end
            if app.hasResults() && ~app.resultsCurrent()
                UIKit.setStatus(app.StatusLabel, sprintf(['Showing %s. Cluster results are for %s - ' ...
                    'Run spike sorting again for this selection.'], where, app.SortContext.label), 'warning');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Showing %s', where), 'info');
            end
        end

        %% plotSignal - Stimulus (with segment shading) and MUA trace
        % -------------------------------------------------------------
        % When sorting results match the selection, the MUA axes show the
        % trace the spikes were detected on (filtered if enabled), the
        % detection thresholds and the selected clusters' spikes
        % (x markers = rejected cluster). Segment view: time from segment start.
        % -------------------------------------------------------------
        function plotSignal(app)
            T = UITheme;
            if isempty(app.MUAData)
                UIKit.styleAxes(app.AxStim, 'Stimulus');
                UIKit.emptyAxes(app.AxStim, 'Load a MUA file (or Try demo data) to begin');
                UIKit.styleAxes(app.AxMUA, 'MUA signal');
                UIKit.emptyAxes(app.AxMUA, 'Load a MUA file (or Try demo data, step 1) to see the signal');
                return;
            end
            [chIdx, segIdx] = app.currentSelection();
            chNum = app.MUAData.channels(chIdx);

            % Always plot full stimulus trace (if the file has one)
            ax = app.AxStim;
            if isempty(app.StimData)
                UIKit.styleAxes(ax, 'Stimulus');
                UIKit.emptyAxes(ax, 'No stimulus channel in this file');
            else
                resetAxes(ax);
                plot(ax, app.StimData.time, app.StimData.signal, 'Color', T.stimColor);
                if ~isempty(segIdx)
                    hold(ax, 'on');
                    yLims = ylim(ax);
                    for i = 1:size(app.Segments,1)
                        segX = app.Segments(i,:);
                        alpha = 0.10;
                        if i == segIdx, alpha = 0.35; end
                        fill(ax, [segX(1) segX(2) segX(2) segX(1)], ...
                            [yLims(1) yLims(1) yLims(2) yLims(2)], T.shadeColor, ...
                            'FaceAlpha', alpha, 'EdgeColor', 'none');
                    end
                    ylim(ax, yLims);
                    hold(ax, 'off');
                end
                ttl = 'Stimulus';
                if ~isempty(segIdx), ttl = sprintf('Stimulus (segment %d highlighted)', segIdx); end
                UIKit.styleAxes(ax, ttl, 'Time (s)', 'Amplitude (a.u.)');
            end

            % MUA trace: sorted trace + spikes when results match, else raw
            ax = app.AxMUA;
            resetAxes(ax);
            relTime = ~isempty(segIdx);
            if app.resultsCurrent()
                t = app.SpikeResults.segmentedTime;
                x = app.SpikeResults.segmentedMUA;
            elseif relTime
                seg = app.Segments(segIdx, :);
                idxRange = app.MUAData.time >= seg(1) & app.MUAData.time <= seg(2);
                t = app.MUAData.time(idxRange);
                x = app.MUAData.data(chIdx, idxRange);
            else
                t = app.MUAData.time;
                x = app.MUAData.data(chIdx, :);
            end
            if isempty(t)
                UIKit.styleAxes(ax, sprintf('Segment %d - Channel %d', segIdx, chNum));
                UIKit.emptyAxes(ax, 'This segment lies outside the recording');
                return;
            end
            tx = t;
            if relTime, tx = t - t(1); end
            plot(ax, tx, x, 'Color', T.sectionTitleColor, 'LineWidth', 0.5, 'HandleVisibility', 'off');

            ttl = sprintf('MUA - Channel %d', chNum);
            if relTime, ttl = sprintf('Segment %d - Channel %d', segIdx, chNum); end
            if app.resultsCurrent()
                hold(ax, 'on');
                % Threshold lines (none for NEO: its threshold is on the NEO scale)
                for thrLine = app.ThreshLines
                    yline(ax, thrLine, '--', 'Color', T.danger, 'LineWidth', 1.2, 'HandleVisibility', 'off');
                end
                ids = unique(app.SpikeResults.clusterIdx);
                sel = app.selectedClusterPos();
                for p = sel
                    k = ids(p);
                    si = app.SpikeLocs(app.SpikeResults.clusterIdx == k);
                    col = clusterColor(k);
                    if app.ClusterQC(p).rejected
                        scatter(ax, tx(si), x(si), 24, 'x', 'MarkerEdgeColor', col, ...
                            'DisplayName', sprintf('%s (rejected)', clusterName(k)));
                    else
                        scatter(ax, tx(si), x(si), 16, col, 'filled', 'DisplayName', clusterName(k));
                    end
                end
                hold(ax, 'off');
                if ~isempty(sel) && numel(sel) <= 12
                    showLegend(ax, 'northeast');
                end
                if app.SpikeSortParams.filter
                    ttl = sprintf('%s  (band-pass %g-%g Hz, as sorted)', ttl, ...
                        app.SpikeSortParams.bpLow, app.SpikeSortParams.bpHigh);
                end
            end
            xl = 'Time (s)';
            if relTime, xl = 'Time from segment start (s)'; end
            UIKit.styleAxes(ax, ttl, xl, 'Amplitude (V)');
        end

        %% configureSpikeSorting - Settings dialog; Run saves and sorts
        % -------------------------------------------------------------
        % UIKit.dialog with detection, feature/clustering and drift
        % correction settings, pre-filled from SpikeSortParams. "Run"
        % builds the params struct (same fields as before), stores it and
        % calls runSpikeSorting; Cancel keeps the previous settings.
        % -------------------------------------------------------------
        function configureSpikeSorting(app)
            if isempty(app.MUAData)
                UIKit.alert(app.UIFig, 'Load MUA data before configuring spike sorting.', 'No Data', 'warning');
                return;
            end
            T = UITheme;
            p = MUAPipeline.completeParams(app.SpikeSortParams);
            D = UIKit.dialog('Spike sorting settings', 'Detection, features, clustering and drift', ...
                'MUA Analysis', [520 860]);
            nRows = 23;
            D.Body.RowHeight = repmat({T.controlHeight}, 1, nRows);
            D.Body.RowHeight([1 10 19]) = {22};
            D.Body.RowSpacing = 6;
            D.Body.ColumnWidth = {'1.25x', '1x'};

            % --- Detection ---
            sectionLabel(D.Body, 1, 'Detection');
            detectOpts = {'Standard', 'MAD', 'NEO', 'Rolling MAD', 'Percentile'};
            detectMethodPopup = placeField(D.Body, 2, 'Detection method', 'dropdown', ...
                {detectOpts, pickItem(detectOpts, p.detectMethod)}, ...
                ['How the spike threshold is set. Standard: mean + k x SD. MAD: median + k x MAD ' ...
                 '(robust when there are many spikes). NEO: energy operator that highlights sharp ' ...
                 'spikes of either sign. Rolling MAD: MAD threshold, peak picked in a short window. ' ...
                 'Percentile: 99.9th percentile of |signal| (ignores k).']);
            thresholdBox = placeField(D.Body, 3, 'Threshold multiplier k', 'numeric', p.threshold, ...
                ['How many SDs (or MADs) above the baseline a peak must reach. Higher = fewer, ' ...
                 'larger spikes. Typical 3-5.'], [0 100]);
            thresholdBox.LowerLimitInclusive = 'off';
            polOpts = {'positive', 'negative', 'both'};
            polarityPopup = placeField(D.Body, 4, 'Polarity', 'dropdown', ...
                {polOpts, pickItem(polOpts, p.polarity)}, ...
                ['Direction of the spikes: negative = downward peaks (typical extracellular), ' ...
                 'positive = upward, both = either. Also sets which peak waveforms are aligned on.']);
            refractoryBox = placeField(D.Body, 5, 'Refractory period (ms)', 'numeric', p.refractoryMs, ...
                ['Used only for quality control: a unit with more than 2% of inter-spike ' ...
                 'intervals shorter than this is flagged as rejected.'], [0 100]);
            alignBox = placeField(D.Body, 6, 'Alignment window (ms)', 'numeric', p.alignWinMs, ...
                ['Half-width of each waveform snippet (ms). Spikes are re-centred on their ' ...
                 'peak within this window.'], [0 50]);
            alignBox.LowerLimitInclusive = 'off';
            filterCheckbox = placeField(D.Body, 7, 'Band-pass filter before detection', 'checkbox', ...
                logical(p.filter), 'Apply a zero-phase Butterworth band-pass filter before detecting spikes');
            bandpassLow = placeField(D.Body, 8, 'Band-pass low (Hz)', 'numeric', p.bpLow, ...
                'Lower cutoff (Hz); must be above 0 and below the high cutoff', [0 Inf]);
            bandpassHigh = placeField(D.Body, 9, 'Band-pass high (Hz)', 'numeric', p.bpHigh, ...
                'Upper cutoff (Hz); must be below half the sampling rate (Nyquist)', [0 Inf]);

            % --- Features & clustering ---
            sectionLabel(D.Body, 10, 'Features & clustering');
            % ICA needs the external FastICA package and Wavelet needs the
            % Wavelet Toolbox; only offer them when available.
            featureOpts = {'PCA', 'ICA', 'Waveform', 'Wavelet', 't-SNE'};
            if ~exist('fastica', 'file'), featureOpts(strcmp(featureOpts, 'ICA')) = []; end
            if ~exist('wavedec', 'file'), featureOpts(strcmp(featureOpts, 'Wavelet')) = []; end
            featurePopup = placeField(D.Body, 11, 'Feature extraction', 'dropdown', ...
                {featureOpts, pickItem(featureOpts, p.featureMethod)}, ...
                ['What describes each spike for clustering. PCA: main waveform shapes. ' ...
                 'ICA: independent components (FastICA). Waveform: raw samples. ' ...
                 'Wavelet: Haar wavelet coefficients. t-SNE: non-linear 2-3-D map (slow).']);
            compBox = placeField(D.Body, 12, 'Number of components', 'numeric', p.numComponents, ...
                'Number of features per spike given to the clustering (t-SNE uses at most 3)', [1 100]);
            compBox.RoundFractionalValues = 'on';
            normCheckbox = placeField(D.Body, 13, 'Normalize features (z-score)', 'checkbox', ...
                logical(p.normalize), 'Give every feature the same weight before clustering');
            clusterOpts = {'K-means', 'GMM', 'DBSCAN'};
            clusterPopup = placeField(D.Body, 14, 'Clustering method', 'dropdown', ...
                {clusterOpts, pickItem(clusterOpts, p.clusterMethod)}, ...
                ['K-means / GMM: try 2-10 clusters and keep the number with the best silhouette. ' ...
                 'DBSCAN: finds dense groups; spikes outside them become noise (cluster 0).']);
            epsVal = p.dbscanEpsilon;
            if ~isfinite(epsVal), epsVal = 0; end
            dbscanEpsBox = placeField(D.Body, 15, 'DBSCAN epsilon (0 = auto)', 'numeric', epsVal, ...
                'Neighbourhood radius in feature units. 0 = choose automatically (k-distance heuristic).', [0 Inf]);
            minSpikesBox = placeField(D.Body, 16, 'Minimum spikes per cluster', 'numeric', p.minSpikesPerCluster, ...
                'Clusters with fewer spikes are not accepted (or become noise after drift merging)', [1 Inf]);
            minSpikesBox.RoundFractionalValues = 'on';
            autoMergeCheck = placeField(D.Body, 17, 'Auto-merge similar clusters', 'checkbox', ...
                logical(p.autoMerge), ...
                sprintf(['After clustering, merge clusters that are one neuron split in two: mean waveforms ' ...
                 'with the same shape (correlation at or above the threshold, allowing a 0.2 ms shift) and ' ...
                 'similar size (amplitude ratio at least %g). Undo in step 4 restores the clusters.'], ...
                 p.mergeMinAmpRatio));
            mergeThrBox = placeField(D.Body, 18, 'Merge threshold (correlation)', 'numeric', p.mergeThreshold, ...
                ['Minimum correlation (0.5-1, no unit) between two clusters'' mean waveforms for them to be ' ...
                 'merged. Higher = merge less. Default 0.95.'], [0.5 1]);

            % --- Drift correction ---
            sectionLabel(D.Body, 19, 'Drift correction');
            driftCheck = placeField(D.Body, 20, 'Correct for drift', 'checkbox', ...
                logical(p.enableDriftCorrection), ...
                'Compensate for slow changes in spike shape over long recordings');
            driftOpts = {'Time Binning', 'Dynamic Clustering'};
            driftMethodPopup = placeField(D.Body, 21, 'Drift method', 'dropdown', ...
                {driftOpts, pickItem(driftOpts, p.driftMethod)}, ...
                ['Time Binning: cluster each time bin separately, then join matching units ' ...
                 'across bins. Dynamic Clustering: add time as an extra feature.']);
            driftBinBox = placeField(D.Body, 22, 'Bin width (s)', 'numeric', p.driftBinWidth, ...
                'Length of each time bin for Time Binning (s)', [0 Inf]);
            driftBinBox.LowerLimitInclusive = 'off';
            GridSearchCheck = placeField(D.Body, 23, 'Optimize merge thresholds (grid search)', 'checkbox', ...
                logical(p.enableGridSearchCheck), ...
                'Try several merge thresholds and keep the one with the best silhouette (slower)');

            filterCheckbox.ValueChangedFcn = @(~,~)updateDialogEnable();
            clusterPopup.ValueChangedFcn = @(~,~)updateDialogEnable();
            autoMergeCheck.ValueChangedFcn = @(~,~)updateDialogEnable();
            driftCheck.ValueChangedFcn = @(~,~)updateDialogEnable();
            driftMethodPopup.ValueChangedFcn = @(~,~)updateDialogEnable();
            updateDialogEnable();

            cancelBtn = UIKit.button(D.Buttons, 'Cancel', @(~,~)delete(D.Fig), 'secondary', ...
                'Close without changing the settings');
            cancelBtn.Layout.Column = 2;
            runBtn = UIKit.button(D.Buttons, 'Run', @(~,~)submitAndClose(), 'primary', ...
                'Save these settings and run spike sorting now');
            runBtn.Layout.Column = 3;

            function updateDialogEnable()
                set([bandpassLow, bandpassHigh], 'Enable', onOff(filterCheckbox.Value));
                dbscanEpsBox.Enable = onOff(strcmp(clusterPopup.Value, 'DBSCAN'));
                mergeThrBox.Enable = onOff(autoMergeCheck.Value);
                driftMethodPopup.Enable = onOff(driftCheck.Value);
                isBinning = driftCheck.Value && strcmp(driftMethodPopup.Value, 'Time Binning');
                driftBinBox.Enable = onOff(isBinning);
                GridSearchCheck.Enable = onOff(isBinning);
            end

            function submitAndClose()
                params = struct();
                params.detectMethod = detectMethodPopup.Value;
                params.clusterMethod = clusterPopup.Value;
                params.threshold = thresholdBox.Value;
                params.refractoryMs = refractoryBox.Value;
                params.alignWinMs = alignBox.Value;
                params.polarity = polarityPopup.Value;
                params.filter = double(filterCheckbox.Value);
                params.bpLow = bandpassLow.Value;
                params.bpHigh = bandpassHigh.Value;
                params.featureMethod = featurePopup.Value;
                params.numComponents = compBox.Value;
                params.normalize = double(normCheckbox.Value);
                params.minSpikesPerCluster = minSpikesBox.Value;
                params.enableDriftCorrection = double(driftCheck.Value);
                params.driftMethod = driftMethodPopup.Value;
                params.driftBinWidth = driftBinBox.Value;
                params.enableGridSearchCheck = double(GridSearchCheck.Value);
                if dbscanEpsBox.Value <= 0
                    params.dbscanEpsilon = NaN;  % auto-tune
                else
                    params.dbscanEpsilon = dbscanEpsBox.Value;
                end
                params.autoMerge = double(autoMergeCheck.Value);
                params.mergeThreshold = mergeThrBox.Value;
                params.mergeMinAmpRatio = p.mergeMinAmpRatio;  % not in the dialog; kept
                disp(params);
                delete(D.Fig);
                app.SpikeSortParams = params;
                app.updateParamsLabel();
                app.runSpikeSorting(params);
            end
        end

        %% updateParamsLabel - One-line summary of the sorting settings
        function updateParamsLabel(app)
            p = MUAPipeline.completeParams(app.SpikeSortParams);
            s = sprintf('%s, k = %g, %s polarity  ·  %s + %s', p.detectMethod, p.threshold, ...
                p.polarity, p.featureMethod, p.clusterMethod);
            if p.autoMerge, s = sprintf('%s  ·  auto-merge r %s %g', s, char(8805), p.mergeThreshold); end
            if p.filter, s = sprintf('%s  ·  %g-%g Hz', s, p.bpLow, p.bpHigh); end
            if p.enableDriftCorrection, s = sprintf('%s  ·  drift: %s', s, p.driftMethod); end
            app.ParamsLabel.Text = s;
        end

        %% runSpikeSorting - Checks, busy dialog, sorting, then plots
        % -------------------------------------------------------------
        % Wraps doSpikeSorting (the analysis) with toolbox checks, a busy
        % dialog updated per stage, error reporting and plot refresh.
        % -------------------------------------------------------------
        function runSpikeSorting(app, params)
            if isempty(app.MUAData)
                UIKit.alert(app.UIFig, 'Load MUA data before running spike sorting.', 'No Data', 'warning');
                return;
            end
            % Required toolboxes: Signal Processing (findpeaks, butter,
            % filtfilt) and Statistics and Machine Learning (pca, kmeans,
            % fitgmdist, dbscan, silhouette, prctile).
            hasSignal = license('test', 'Signal_Toolbox') && exist('findpeaks', 'file') == 2;
            hasStats = license('test', 'Statistics_Toolbox') && exist('kmeans', 'file') == 2;
            if ~hasSignal || ~hasStats
                missing = {};
                if ~hasSignal, missing{end+1} = 'Signal Processing Toolbox'; end
                if ~hasStats, missing{end+1} = 'Statistics and Machine Learning Toolbox'; end
                UIKit.alert(app.UIFig, sprintf('Spike sorting requires: %s.', strjoin(missing, ', ')), ...
                    'Missing Toolbox', 'error');
                UIKit.setStatus(app.StatusLabel, 'Spike sorting unavailable: missing toolbox', 'error');
                return;
            end

            tStart = tic;
            app.BusyDlg = UIKit.busy(app.UIFig, 'Starting spike detection...');
            ok = false;
            try
                ok = app.doSpikeSorting(params);
                if ok
                    app.setStage('Plotting results...');
                    app.computeDisplayPCs();
                    app.refreshResultPlots();
                    app.plotSignal();
                end
            catch ME
                ok = false;
                app.clearResults();
                app.failSort(sprintf('Spike sorting failed: %s', ME.message), 'Spike sorting');
            end
            UIKit.done(app.BusyDlg);
            app.BusyDlg = [];
            app.updateControls();
            if ok
                qc = app.ClusterQC;
                nUnits = sum([qc.id] > 0);
                nRej = sum([qc.rejected]);
                mergeNote = '';
                if ~isempty(app.ClusterEdits)
                    mergeNote = sprintf('  ·  %s (Undo in step 4 keeps them apart)', app.ClusterEdits{end});
                end
                UIKit.setStatus(app.StatusLabel, sprintf(['Sorted %d spikes into %d unit%s (%d rejected) on %s ' ...
                    'in %.1f s%s - review the tabs, then Save results (step 5)'], ...
                    numel(app.SpikeResults.spikeTimes), nUnits, plural(nUnits), nRej, ...
                    app.SortContext.label, toc(tStart), mergeNote), 'success');
            end
        end

        %% setStage - Report the current sorting stage (status + busy dialog)
        function setStage(app, msg)
            UIKit.setStatus(app.StatusLabel, msg, 'busy');
            if ~isempty(app.BusyDlg) && isvalid(app.BusyDlg)
                app.BusyDlg.Message = msg;
            end
            drawnow;
        end

        %% failSort - Close the busy dialog, alert and report an error
        function failSort(app, msg, titleText)
            if nargin < 3, titleText = 'Spike sorting'; end
            UIKit.done(app.BusyDlg);
            app.BusyDlg = [];
            app.refreshResultPlots();
            app.plotSignal();
            app.updateControls();
            UIKit.alert(app.UIFig, msg, titleText, 'error');
            UIKit.setStatus(app.StatusLabel, msg, 'error');
        end

        %% clearResults - Drop sorting results and display state
        function clearResults(app)
            app.SpikeResults = [];
            app.SortContext = [];
            app.SpikeLocs = [];
            app.ThreshLines = [];
            app.ClusterQC = [];
            app.DisplayPCs = [];
            app.SpikeWaves = [];
            app.EditHistory = emptyHistory();
            app.ClusterEdits = {};
            app.ClusterSelectMenu.Items = {};
            app.ClusterSelectMenu.ItemsData = [];
            app.QualityLabel.Text = 'Run spike sorting to see clusters';
        end

        %% doSpikeSorting - Detection, alignment, features, clustering, QC
        % -------------------------------------------------------------
        % Cuts the selected channel (and segment) and runs MUAPipeline.sort
        % (the headless sorting shared with scripts / batch runs), then
        % stores the results and display state. Auto-merges become the
        % first undoable edit. Returns true on success; pipeline failures
        % call failSort and return false.
        % -------------------------------------------------------------
        function ok = doSpikeSorting(app, params)
            ok = false;
            params = MUAPipeline.completeParams(params);
            app.SpikeSortParams = params;
            [chIdx, segIdx, segWin] = app.currentSelection();
            % Drop results of any previous run so partial failures leave no stale state
            app.clearResults();

            % Extract data (either full trace or segmented portion)
            if app.SegmentCheckbox.Value && ~isempty(app.Segments)
                tAll = app.MUAData.time;
                xAll = app.MUAData.data(chIdx, :);
                seg = app.Segments(segIdx, :);
                idxRange = tAll >= seg(1) & tAll <= seg(2);
                t = tAll(idxRange);
                x = xAll(idxRange);
            else
                t = app.MUAData.time;
                x = app.MUAData.data(chIdx, :);
            end

            try
                [res, info] = MUAPipeline.sort(x, t, app.MUAData.fs, params, @(msg) app.setStage(msg));
            catch ME
                if strncmp(ME.identifier, 'NeuroAnalyzer:MUAPipeline:', 26)
                    app.failSort(ME.message, MUAPipeline.errorTitle(ME.identifier));
                    return;
                end
                rethrow(ME);
            end

            % Results and display state for the plots and the cluster list
            app.SpikeResults = res;
            app.ClusterQC = info.qc;
            app.SpikeLocs = info.locs;
            app.ThreshLines = info.threshLines;
            app.SpikeWaves = info.waves;
            chNum = app.MUAData.channels(chIdx);
            label = sprintf('Ch %d', chNum);
            if ~isempty(segIdx), label = sprintf('%s, segment %d', label, segIdx); end
            app.SortContext = struct('chIdx', chIdx, 'channel', chNum, 'segIdx', segIdx, ...
                'segWin', segWin, 'label', label);
            if ~isempty(info.mergeLog)
                desc = ['Auto-merged ' ClusterTools.describeLog(info.mergeLog)];
                app.EditHistory = struct('labels', info.labelsBeforeMerge, 'description', desc, ...
                    'edits', {{}});
                app.ClusterEdits = {desc};
            end
            app.refreshClusterList([info.qc.id]);  % Select all by default
            ok = true;
        end

        %% updateQualityLabel - Units / rejected / noise summary in step 4
        function updateQualityLabel(app)
            qc = app.ClusterQC;
            if isempty(qc)
                app.QualityLabel.Text = 'Run spike sorting to see clusters';
                return;
            end
            isUnit = [qc.id] > 0;
            nUnits = sum(isUnit);
            nRej = sum([qc.rejected]);
            nNoise = sum([qc(~isUnit).n]);
            app.QualityLabel.Text = sprintf(['%s: %d unit%s, %d accepted, %d rejected ' ...
                '(SNR < 2 or > 2%% ISI < %g ms)  ·  %d noise spike%s'], ...
                app.SortContext.label, nUnits, plural(nUnits), nUnits - nRej, nRej, ...
                app.SpikeSortParams.refractoryMs, nNoise, plural(nNoise));
        end

        %% computeDisplayPCs - 2-D waveform PCA used only for the cluster plot
        % Independent of the chosen feature method so it is always in sync
        % with the final spikes (also after drift correction).
        function computeDisplayPCs(app)
            app.DisplayPCs = [];
            % Rebuild from the per-cluster waveforms: these always match
            % clusterIdx (drift time binning keeps only some bins)
            ids = unique(app.SpikeResults.clusterIdx);
            waves = nan(numel(app.SpikeResults.clusterIdx), size(app.SpikeResults.waveforms{1}, 2));
            for i = 1:numel(ids)
                waves(app.SpikeResults.clusterIdx == ids(i), :) = app.SpikeResults.waveforms{i};
            end
            try
                [~, score] = pca(waves);
                if size(score, 2) < 2, score(:, end+1:2) = 0; end
                app.DisplayPCs = score(:, 1:2);
            catch
                app.DisplayPCs = [];
            end
        end

        %% selectedClusterPos - Selected positions in unique(clusterIdx)
        function pos = selectedClusterPos(app)
            pos = [];
            if ~app.hasResults(), return; end
            v = app.ClusterSelectMenu.Value;
            if iscell(v), v = cell2mat(v); end
            nIDs = numel(unique(app.SpikeResults.clusterIdx));
            pos = v(:)';
            pos = pos(isnumeric(pos) & pos >= 1 & pos <= nIDs);
        end

        %% selectedClusterIds - Cluster IDs selected in step 4 (0 = noise)
        function ids = selectedClusterIds(app)
            ids = [];
            if ~app.hasResults(), return; end
            allIds = unique(app.SpikeResults.clusterIdx);
            ids = reshape(allIds(app.selectedClusterPos()), 1, []);
        end

        %% setSelectedIds - Select exactly these cluster IDs in step 4
        function setSelectedIds(app, ids)
            if ~app.hasResults(), return; end
            allIds = unique(app.SpikeResults.clusterIdx);
            pos = find(ismember(allIds, ids));
            if isempty(pos)
                try
                    app.ClusterSelectMenu.Value = [];
                catch
                    app.ClusterSelectMenu.Value = {};
                end
            else
                app.ClusterSelectMenu.Value = pos(:)';
            end
        end

        %% refreshClusterList - List items from ClusterQC; select selIds (all if none exist)
        function refreshClusterList(app, selIds)
            qc = app.ClusterQC;
            ids = [qc.id];
            % Empty the list first (as clearResults does) so a stale Value never
            % points past the new items
            app.ClusterSelectMenu.Items = {};
            app.ClusterSelectMenu.ItemsData = [];
            app.ClusterSelectMenu.Items = arrayfun(@(q) clusterListText(q), qc, 'UniformOutput', false);
            app.ClusterSelectMenu.ItemsData = 1:numel(ids);
            pos = find(ismember(ids, selIds));
            if isempty(pos), pos = 1:numel(ids); end
            app.ClusterSelectMenu.Value = pos;
            app.updateQualityLabel();
        end

        %% requireResults - Warn in the status bar when there is nothing sorted yet
        function tf = requireResults(app, what)
            tf = app.hasResults();
            if ~tf
                UIKit.setStatus(app.StatusLabel, sprintf('Run spike sorting (step 3) before %s', what), 'warning');
            end
        end

        %% autoMergeClusters - Merge over-split clusters now (no dialog)
        % -------------------------------------------------------------
        % Same rule as the Configure option: mean waveforms with the same
        % shape and size (ClusterTools.autoMerge). opts (optional struct):
        % threshold (min correlation; default the Configure setting, 0.95),
        % minAmpRatio (default 0.85), maxLag (samples; default 0.2 ms).
        % Undoable. ok is true when the step ran (also when nothing needed
        % merging); mergeLog lists the merges.
        % -------------------------------------------------------------
        function [ok, mergeLog] = autoMergeClusters(app, opts)
            ok = false; mergeLog = [];
            if ~app.requireResults('merging clusters'), return; end
            o = MUAPipeline.mergeOptions(app.SpikeSortParams, app.MUAData.fs);
            if nargin >= 2 && isstruct(opts)
                fn = fieldnames(opts);
                for i = 1:numel(fn), o.(fn{i}) = opts.(fn{i}); end
            end
            [labels, mergeLog] = ClusterTools.autoMerge(app.SpikeResults.clusterIdx, app.SpikeWaves, o);
            ok = true;
            if isempty(mergeLog)
                UIKit.setStatus(app.StatusLabel, sprintf(['Auto-merge: no two clusters have a waveform ' ...
                    'correlation %s %g and amplitude ratio %s %g - nothing merged'], ...
                    char(8805), o.threshold, char(8805), o.minAmpRatio), 'info');
                return;
            end
            desc = ['Auto-merged ' ClusterTools.describeLog(mergeLog)];
            app.applyClusterEdit(labels, desc, [mergeLog.keep]);
            nUnits = sum([app.ClusterQC.id] > 0);
            UIKit.setStatus(app.StatusLabel, sprintf('%s - now %d unit%s (Undo in step 4 restores them)', ...
                desc, nUnits, plural(nUnits)), 'success');
        end

        %% mergeClusters - Merge units into the lowest ID (no dialog)
        % ids: cluster IDs (default: the units selected in step 4); noise
        % (0) is ignored. Undoable. Returns true when clusters were merged.
        function ok = mergeClusters(app, ids)
            ok = false;
            if ~app.requireResults('merging clusters'), return; end
            if nargin < 2 || isempty(ids), ids = app.selectedClusterIds(); end
            labels = app.SpikeResults.clusterIdx;
            ids = reshape(ids, 1, []);
            units = unique(ids(ids > 0 & ismember(ids, labels)));
            if numel(units) < 2
                UIKit.setStatus(app.StatusLabel, ['Merge: select at least two units in step 4 ' ...
                    '(noise cluster 0 cannot be merged)'], 'warning');
                return;
            end
            keep = min(units);
            newLabels = ClusterTools.merge(labels, units);
            gone = units(units ~= keep);
            desc = sprintf('Merged cluster%s %s into cluster %d', plural(numel(gone)), ...
                strjoin(arrayfun(@num2str, gone, 'UniformOutput', false), ', '), keep);
            app.applyClusterEdit(newLabels, desc, keep);
            UIKit.setStatus(app.StatusLabel, sprintf('%s (%d spikes) - Undo in step 4 restores them', ...
                desc, sum(newLabels == keep)), 'success');
            ok = true;
        end

        %% splitCluster - Split one unit in two (no dialog)
        % id: cluster ID (default: the single unit selected in step 4).
        % k-means on the unit's waveform PCA (ClusterTools.split); the
        % larger part keeps id. Undoable. Returns true when split.
        function ok = splitCluster(app, id)
            ok = false;
            if ~app.requireResults('splitting a cluster'), return; end
            if nargin < 2 || isempty(id)
                sel = app.selectedClusterIds();
                sel = sel(sel > 0);
                if numel(sel) ~= 1
                    UIKit.setStatus(app.StatusLabel, 'Split: select exactly one unit in step 4', 'warning');
                    return;
                end
                id = sel;
            end
            try
                [newLabels, newIds] = ClusterTools.split(app.SpikeResults.clusterIdx, app.SpikeWaves, id, 2);
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Split: %s', ME.message), 'warning');
                return;
            end
            counts = arrayfun(@(k) sum(newLabels == k), newIds);
            desc = sprintf('Split cluster %d into clusters %s', id, ...
                strjoin(arrayfun(@num2str, newIds, 'UniformOutput', false), ' and '));
            app.applyClusterEdit(newLabels, desc, newIds);
            UIKit.setStatus(app.StatusLabel, sprintf('%s (%s spikes) - Undo in step 4 restores it', desc, ...
                strjoin(arrayfun(@num2str, counts, 'UniformOutput', false), ' / ')), 'success');
            ok = true;
        end

        %% undoClusterEdit - Restore the clusters before the last edit (no dialog)
        % Undoes merges, splits and auto-merges (also the one done while
        % sorting), most recent first. Returns true when something was undone.
        function ok = undoClusterEdit(app)
            ok = false;
            if ~app.hasResults() || isempty(app.EditHistory)
                UIKit.setStatus(app.StatusLabel, 'Nothing to undo', 'info');
                app.updateControls();
                return;
            end
            h = app.EditHistory(end);
            app.EditHistory(end) = [];
            app.ClusterEdits = h.edits;
            back = setdiff(unique(h.labels), unique(app.SpikeResults.clusterIdx));
            app.setClusterLabels(h.labels, back);
            nUnits = sum([app.ClusterQC.id] > 0);
            UIKit.setStatus(app.StatusLabel, sprintf('Undone: %s - back to %d unit%s', h.description, ...
                nUnits, plural(nUnits)), 'success');
            ok = true;
        end

        %% applyClusterEdit - Remember the current labels (for Undo), then apply new ones
        function applyClusterEdit(app, labels, description, focusIds)
            app.EditHistory(end + 1) = struct('labels', app.SpikeResults.clusterIdx, ...
                'description', description, 'edits', {app.ClusterEdits});
            app.ClusterEdits{end + 1} = description;
            app.setClusterLabels(labels, focusIds);
        end

        %% setClusterLabels - New cluster ID per spike: recompute QC, list and plots
        % Keeps the selection of clusters that still exist and adds focusIds.
        function setClusterLabels(app, labels, focusIds)
            oldSel = app.selectedClusterIds();
            [res, qc] = MUAPipeline.qualityMetrics(app.SpikeResults, labels, app.SpikeWaves, ...
                app.SpikeLocs, app.SpikeResults.segmentedTime, app.MUAData.fs, app.SpikeSortParams);
            app.SpikeResults = res;
            app.ClusterQC = qc;
            ids = [qc.id];
            app.refreshClusterList([oldSel(ismember(oldSel, ids)), reshape(focusIds, 1, [])]);
            app.computeDisplayPCs();
            app.refreshResultPlots();
            app.plotSignal();
            app.updateControls();
        end

        %% showRasterPSTH - Raster & PSTH tab for units (no dialog)
        % -------------------------------------------------------------
        % unitIds: cluster IDs (default: the current selection; the first
        % 4 units are shown). window: [from to] s around each stimulus
        % onset (default the tab's fields, -0.1 to 0.3). bin: PSTH bin
        % width in s (default 0.005). Onsets use step 2's threshold and
        % minimum ISI (default 0.5 and 1 s). Returns true when drawn.
        % -------------------------------------------------------------
        function ok = showRasterPSTH(app, unitIds, window, bin)
            if nargin >= 3 && ~isempty(window)
                app.RasterFromField.Value = window(1);
                app.RasterToField.Value = window(2);
            end
            if nargin >= 4 && ~isempty(bin), app.RasterBinField.Value = bin * 1000; end
            % Show the tab first so a selection change draws it only once
            app.TabGroup.SelectedTab = app.RasterTab;
            if nargin >= 2 && ~isempty(unitIds) && app.hasResults()
                app.setSelectedIds(unitIds);
                app.updateClusterScatter();   % redraws the tabs, this one included
            else
                app.plotRasterPSTH();
            end
            if app.RasterDirty, app.plotRasterPSTH(); end
            ok = app.RasterOutcome.ok;
            msg = app.RasterOutcome.msg;
            if ok
                UIKit.setStatus(app.StatusLabel, sprintf('Raster & PSTH: %s', app.RasterInfoLabel.Text), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Raster & PSTH: %s', msg), 'warning');
            end
        end

        %% showCorrelograms - Correlograms tab for up to 4 units (no dialog)
        % unitIds: cluster IDs (default: the current selection); maxLagMs
        % and binMs in ms (defaults 50 and 1). Returns true when drawn.
        function ok = showCorrelograms(app, unitIds, maxLagMs, binMs)
            if nargin >= 3 && ~isempty(maxLagMs), app.CorrLagField.Value = maxLagMs; end
            if nargin >= 4 && ~isempty(binMs), app.CorrBinField.Value = binMs; end
            % Show the tab first so a selection change draws it only once
            app.TabGroup.SelectedTab = app.CorrTab;
            if nargin >= 2 && ~isempty(unitIds) && app.hasResults()
                app.setSelectedIds(unitIds);
                app.updateClusterScatter();   % redraws the tabs, this one included
            else
                app.plotCorrelograms();
            end
            if app.CorrDirty, app.plotCorrelograms(); end
            ok = app.CorrOutcome.ok;
            msg = app.CorrOutcome.msg;
            if ok
                nU = numel(app.unitsToShow());
                UIKit.setStatus(app.StatusLabel, sprintf(['Correlograms: %d unit%s, %s%g ms lag, %g ms bins ' ...
                    '(shaded = refractory period)'], nU, plural(nU), char(177), app.CorrLagField.Value, ...
                    app.CorrBinField.Value), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Correlograms: %s', msg), 'warning');
            end
        end

        %% unitsToShow - Selected unit IDs (> 0, first 4) or why none can be shown
        function [ids, msg, nSel] = unitsToShow(app)
            ids = []; msg = ''; nSel = 0;
            if ~app.hasResults()
                msg = 'Run spike sorting (step 3) first';
                return;
            end
            sel = app.selectedClusterIds();
            ids = sel(sel > 0);
            nSel = numel(ids);
            if isempty(ids)
                msg = 'Select one or more units in step 4 (noise cluster 0 is not shown)';
            end
            ids = ids(1:min(4, end));
        end

        %% stimOnsets - Stimulus onsets with step 2's onset settings
        % Threshold and minimum ISI from "Segment by stimulation onsets"
        % (defaults until that dialog is used). [] when there is no stimulus.
        function [onsets, sp] = stimOnsets(app)
            sp = app.SegmentParams;
            if isempty(sp), sp = defaultSegmentParams(); end
            onsets = [];
            if isempty(app.StimData), return; end
            onsets = SpikeTrains.stimulusOnsets(app.StimData.signal, app.StimData.time, ...
                sp.threshold, sp.minISI);
        end

        %% plotRasterPSTH - Per selected unit: raster (top) and PSTH (bottom)
        % -------------------------------------------------------------
        % Spikes of each unit around every stimulus onset whose window lies
        % inside the sorted trace; stimulus at 0 (gray line). PSTH bars =
        % mean rate over trials (spikes/s), lines = +/- SEM. Returns
        % [ok, msg]; msg says why nothing could be drawn.
        % -------------------------------------------------------------
        function [ok, msg] = plotRasterPSTH(app)
            T = UITheme;
            ok = false;
            app.RasterDirty = false;
            delete(app.RasterPanel.Children);
            app.RasterInfoLabel.Text = '';
            win = [app.RasterFromField.Value, app.RasterToField.Value];
            binS = app.RasterBinField.Value / 1000;
            [ids, msg, nSel] = app.unitsToShow();
            if isempty(msg) && isempty(app.StimData)
                msg = 'No stimulus channel in this file: rasters and PSTHs need stimulus onsets (stim_data)';
            end
            if isempty(msg) && win(2) <= win(1)
                msg = 'Set "To" later than "From" (window around each stimulus onset, s)';
            end
            if isempty(msg)
                [onsets, sp] = app.stimOnsets();
                st = app.SpikeResults.segmentedTime;
                span = [st(1) st(end)];
                nIn = sum(onsets + win(1) >= span(1) & onsets + win(2) <= span(2));
                if isempty(onsets)
                    msg = sprintf(['No stimulus onsets: the stimulus never rises above %g. Set the threshold ' ...
                        'with Segment by stimulation onsets (step 2).'], sp.threshold);
                elseif nIn == 0
                    msg = 'No stimulus onset has its whole window inside the sorted recording (or segment)';
                else
                    shown = '';
                    if nSel > numel(ids), shown = sprintf('  ·  first %d of %d selected units', numel(ids), nSel); end
                    app.RasterInfoLabel.Text = sprintf(['%d trial%s, %g ms bins (bars: mean rate, lines: ' ...
                        '%s SEM)  ·  onsets: stimulus above %g, %g s apart (step 2)%s'], nIn, plural(nIn), ...
                        binS * 1000, char(177), sp.threshold, sp.minISI, shown);
                end
            end
            if ~isempty(msg)
                tl = tiledlayout(app.RasterPanel, 1, 1, 'Padding', 'compact');
                ax = nexttile(tl);
                UIKit.styleAxes(ax, 'Raster & PSTH');
                UIKit.emptyAxes(ax, msg);
                app.RasterOutcome = struct('ok', false, 'msg', msg);
                return;
            end
            nU = numel(ids);
            tl = tiledlayout(app.RasterPanel, 2, nU, 'TileSpacing', 'compact', 'Padding', 'compact');
            for u = 1:nU
                k = ids(u);
                col = clusterColor(k);
                tk = app.SpikeResults.spikeTimes(app.SpikeResults.clusterIdx == k);
                [r, p] = SpikeTrains.rasterPSTH(tk, onsets, win, binS, span);

                % Raster: one tick per spike, trial 1 at the top
                ax = nexttile(tl, u);
                resetAxes(ax);
                hold(ax, 'on');
                if ~isempty(r.time)
                    n = numel(r.time);
                    xs = [r.time'; r.time'; nan(1, n)] * 1000;
                    ys = [r.trial' - 0.4; r.trial' + 0.4; nan(1, n)];
                    plot(ax, xs(:), ys(:), 'Color', col, 'LineWidth', 1);
                end
                xline(ax, 0, '-', 'Color', T.stimColor, 'LineWidth', 1.5);
                hold(ax, 'off');
                xlim(ax, win * 1000);
                ylim(ax, [0.5, r.nTrials + 0.5]);
                ax.YDir = 'reverse';
                UIKit.styleAxes(ax, sprintf('%s  ·  %d spikes', clusterName(k), numel(r.time)), '', 'Trial');

                % PSTH: trial-averaged rate +/- SEM
                ax2 = nexttile(tl, nU + u);
                resetAxes(ax2);
                hold(ax2, 'on');
                bar(ax2, p.centers * 1000, p.rate, 1, 'FaceColor', col, 'EdgeColor', 'none', 'FaceAlpha', 0.75);
                errorbar(ax2, p.centers * 1000, p.rate, p.sem, 'LineStyle', 'none', ...
                    'Color', T.sectionTitleColor, 'CapSize', 0);
                xline(ax2, 0, '-', 'Color', T.stimColor, 'LineWidth', 1.5);
                hold(ax2, 'off');
                xlim(ax2, win * 1000);
                yl = ylim(ax2);
                ylim(ax2, [0, max(yl(2), 1)]);   % rates are >= 0; SEM bars must not push the axis below 0
                [~, iPk] = max(p.rate);
                UIKit.styleAxes(ax2, sprintf('PSTH  ·  peak at %.0f ms', p.centers(iPk) * 1000), ...
                    'Time from stimulus (ms)', 'Rate (spikes/s)');
                linkaxes([ax ax2], 'x');
            end
            ok = true;
            app.RasterOutcome = struct('ok', true, 'msg', '');
        end

        %% plotCorrelograms - Auto (diagonal) and cross-correlograms of up to 4 units
        % -------------------------------------------------------------
        % Row i, column j: spikes of unit j around spikes of unit i
        % (positive lag = j after i). Shaded band: +/- refractory period
        % (Configure, default 1 ms); a clean unit's autocorrelogram is
        % empty there. Returns [ok, msg].
        % -------------------------------------------------------------
        function [ok, msg] = plotCorrelograms(app)
            T = UITheme;
            ok = false;
            app.CorrDirty = false;
            delete(app.CorrPanel.Children);
            app.CorrInfoLabel.Text = '';
            maxLag = app.CorrLagField.Value;
            binMs = app.CorrBinField.Value;
            [ids, msg, nSel] = app.unitsToShow();
            if isempty(msg) && binMs >= maxLag
                msg = 'Set the bin (ms) smaller than the maximum lag (ms)';
            end
            if ~isempty(msg)
                tl = tiledlayout(app.CorrPanel, 1, 1, 'Padding', 'compact');
                ax = nexttile(tl);
                UIKit.styleAxes(ax, 'Correlograms');
                UIKit.emptyAxes(ax, msg);
                app.CorrOutcome = struct('ok', false, 'msg', msg);
                return;
            end
            ref = app.SpikeSortParams.refractoryMs;
            shown = '';
            if nSel > numel(ids), shown = sprintf('  ·  first %d of %d selected units', numel(ids), nSel); end
            app.CorrInfoLabel.Text = sprintf(['Diagonal: autocorrelograms. Row i, column j: unit j around ' ...
                'unit i (lag > 0 = j after i). Shaded: %s%g ms refractory period.%s'], char(177), ref, shown);
            n = numel(ids);
            tl = tiledlayout(app.CorrPanel, n, n, 'TileSpacing', 'compact', 'Padding', 'compact');
            for i = 1:n
                ti = app.SpikeResults.spikeTimes(app.SpikeResults.clusterIdx == ids(i));
                for j = 1:n
                    if i == j
                        [c, cen] = SpikeTrains.correlogram(ti, [], maxLag / 1000, binMs / 1000);
                        col = clusterColor(ids(i));
                        nRef = sum(c(abs(cen) * 1000 < ref));
                        ttl = sprintf('Cluster %d  ·  %d within %s%g ms', ids(i), nRef, char(177), ref);
                    else
                        tj = app.SpikeResults.spikeTimes(app.SpikeResults.clusterIdx == ids(j));
                        [c, cen] = SpikeTrains.correlogram(ti, tj, maxLag / 1000, binMs / 1000);
                        col = T.accentDark;
                        ttl = sprintf('%d %s %d', ids(i), char(8594), ids(j));
                    end
                    ax = nexttile(tl, (i - 1) * n + j);
                    resetAxes(ax);
                    yTop = max([c(:); 1]) * 1.1;
                    hold(ax, 'on');
                    fill(ax, [-ref ref ref -ref], [0 0 yTop yTop], T.danger, 'FaceAlpha', 0.12, ...
                        'EdgeColor', 'none');
                    bar(ax, cen * 1000, c, 1, 'FaceColor', col, 'EdgeColor', 'none');
                    hold(ax, 'off');
                    xlim(ax, [-maxLag maxLag]);
                    ylim(ax, [0 yTop]);
                    xl = ''; yl = '';
                    if i == n, xl = 'Lag (ms)'; end
                    if j == 1, yl = 'Count'; end
                    UIKit.styleAxes(ax, ttl, xl, yl);
                end
            end
            ok = true;
            app.CorrOutcome = struct('ok', true, 'msg', '');
        end

        %% refreshResultPlots - Redraw every result tab from the selection
        function refreshResultPlots(app)
            app.plotWaveforms();
            app.plotFeatureSpace();
            app.plotSpikeRateOverTime();
            app.updateQualityTable();
            app.plotISI();
            app.plotAlignmentDiagnostics();
            % Raster / correlogram grids hold many axes: draw them when shown
            app.RasterDirty = true;
            app.CorrDirty = true;
            app.refreshLazyTabs();
        end

        %% refreshLazyTabs - Redraw the Raster & PSTH / Correlograms tab if shown and stale
        function refreshLazyTabs(app)
            if isempty(app.TabGroup) || ~isvalid(app.TabGroup), return; end
            sel = app.TabGroup.SelectedTab;
            if app.RasterDirty && isequal(sel, app.RasterTab)
                app.plotRasterPSTH();
            elseif app.CorrDirty && isequal(sel, app.CorrTab)
                app.plotCorrelograms();
            end
        end

        %% plotWaveforms - One tile per selected cluster: spikes + mean
        function plotWaveforms(app)
            T = UITheme;
            delete(app.WaveformPanel.Children);
            tl = tiledlayout(app.WaveformPanel, 'flow', 'TileSpacing', 'compact', 'Padding', 'compact');
            sel = app.selectedClusterPos();
            if ~app.hasResults() || isempty(sel)
                ax = nexttile(tl);
                UIKit.styleAxes(ax, 'Waveforms');
                if app.hasResults()
                    UIKit.emptyAxes(ax, 'Select clusters in step 4 to see their waveforms');
                else
                    UIKit.emptyAxes(ax, 'Run spike sorting (step 3) to see spike waveforms');
                end
                return;
            end
            maxTiles = 16;
            if numel(sel) > maxTiles, sel = sel(1:maxTiles); end
            fs = app.MUAData.fs;
            maxTraces = 300;  % faint traces drawn per cluster (mean uses all)
            for p = sel
                q = app.ClusterQC(p);
                waves = app.SpikeResults.waveforms{p};
                win = (size(waves, 2) - 1) / 2;
                tMs = (-win:win) / fs * 1000;
                col = clusterColor(q.id);
                ax = nexttile(tl);
                hold(ax, 'on');
                show = unique(round(linspace(1, size(waves, 1), min(maxTraces, size(waves, 1)))));
                if ~isempty(show)
                    plot(ax, tMs, waves(show, :)', 'Color', [col 0.15]);
                end
                plot(ax, tMs, mean(waves, 1), 'Color', col, 'LineWidth', 2.5);
                hold(ax, 'off');
                xlim(ax, [tMs(1) tMs(end)]);
                ttl = sprintf('%s  ·  n = %d  ·  SNR %.1f', clusterName(q.id), q.n, q.snr);
                if q.rejected, ttl = sprintf('%s  ·  rejected', ttl); end
                UIKit.styleAxes(ax, ttl, 'Time (ms)', 'Amplitude (V)');
                if q.rejected, ax.Title.Color = T.danger; end
            end
            if numel(app.selectedClusterPos()) > maxTiles
                UIKit.setStatus(app.StatusLabel, sprintf('Waveforms: showing the first %d selected clusters', maxTiles), 'info');
            end
        end

        %% plotFeatureSpace - Selected clusters in waveform PCA space
        function plotFeatureSpace(app)
            ax = app.AxFeatures;
            sel = app.selectedClusterPos();
            if ~app.hasResults() || isempty(app.DisplayPCs) || isempty(sel)
                UIKit.styleAxes(ax, 'Clusters in waveform PCA space');
                if ~app.hasResults()
                    UIKit.emptyAxes(ax, 'Run spike sorting (step 3) to see the clusters');
                elseif isempty(sel)
                    UIKit.emptyAxes(ax, 'Select clusters in step 4');
                else
                    UIKit.emptyAxes(ax, 'Waveform PCA not available for these spikes');
                end
                return;
            end
            resetAxes(ax);
            hold(ax, 'on');
            ids = unique(app.SpikeResults.clusterIdx);
            for p = sel
                k = ids(p);
                m = app.SpikeResults.clusterIdx == k;
                scatter(ax, app.DisplayPCs(m, 1), app.DisplayPCs(m, 2), 10, clusterColor(k), 'filled', ...
                    'MarkerFaceAlpha', 0.6, 'DisplayName', clusterName(k));
            end
            hold(ax, 'off');
            showLegend(ax, 'bestoutside');
            UIKit.styleAxes(ax, sprintf('Clusters in waveform PCA space (%s)', app.SortContext.label), ...
                'PC 1 (a.u.)', 'PC 2 (a.u.)');
        end

        %% plotSpikeRateOverTime - Firing rate per selected cluster
        % -------------------------------------------------------------
        % Bin width (s) and relative/absolute from the Spike rate tab.
        % Absolute: counts / bin (Hz); relative: counts / total per cluster.
        % -------------------------------------------------------------
        function plotSpikeRateOverTime(app)
            ax = app.AxRate;
            sel = app.selectedClusterPos();
            if ~app.hasResults() || isempty(sel)
                UIKit.styleAxes(ax, 'Spike rate over time');
                if ~app.hasResults()
                    UIKit.emptyAxes(ax, 'Run spike sorting (step 3) to see the spike rate');
                else
                    UIKit.emptyAxes(ax, 'Select at least one cluster in step 4');
                end
                return;
            end

            binSize = app.RateBinField.Value;
            isRelative = logical(app.RateRelativeCheck.Value);

            % Listbox items are built from unique(clusterIdx), in that order
            allClusterIDs = unique(app.SpikeResults.clusterIdx);
            clusterIDs = allClusterIDs(sel);
            t = app.SpikeResults.spikeTimes;
            c = app.SpikeResults.clusterIdx;

            tStart = min(t);
            tEnd = max(t);
            edges = tStart:binSize:tEnd;
            if numel(edges) < 2 || edges(end) < tEnd
                edges(end+1) = edges(end) + binSize;  % cover the last spikes
            end
            centers = edges(1:end-1) + binSize/2;

            resetAxes(ax);
            hold(ax, 'on');
            for i = 1:numel(clusterIDs)
                k = clusterIDs(i);
                spikes = t(c == k);
                counts = histcounts(spikes, edges);

                if isRelative
                    rate = counts / sum(counts);  % normalize
                else
                    rate = counts / binSize;  % absolute rate (Hz)
                end

                plot(ax, centers, rate, 'LineWidth', 2, 'Color', clusterColor(k), ...
                    'DisplayName', clusterName(k));
            end
            hold(ax, 'off');
            showLegend(ax, 'northeast');
            if isRelative
                yl = 'Relative rate (fraction of spikes)';
            else
                yl = 'Firing rate (Hz)';
            end
            UIKit.styleAxes(ax, sprintf('Spike rate over time (%s, %g s bins)', app.SortContext.label, binSize), ...
                'Time (s)', yl);
        end

        %% updateQualityTable - Per-cluster QC metrics
        function updateQualityTable(app)
            T = UITheme;
            tbl = app.QualityTable;
            try removeStyle(tbl); catch, end
            if ~app.hasResults() || isempty(app.ClusterQC)
                tbl.Data = cell(0, 6);
                return;
            end
            qc = app.ClusterQC;
            t = app.SpikeResults.segmentedTime;
            durSec = max(t(end) - t(1), eps);
            rows = cell(numel(qc), 6);
            for i = 1:numel(qc)
                if qc(i).id == 0
                    status = 'Noise';
                elseif qc(i).rejected
                    status = ['Rejected: ' qc(i).reason];
                else
                    status = 'Accepted';
                end
                rows(i, :) = {clusterName(qc(i).id), qc(i).n, round(qc(i).n / durSec, 2), ...
                    round(qc(i).snr, 2), round(qc(i).isiPct, 2), status};
            end
            tbl.Data = rows;
            rejRows = find([qc.rejected]);
            if ~isempty(rejRows)
                try
                    addStyle(tbl, uistyle('FontColor', T.danger), 'row', rejRows);
                catch
                end
            end
        end

        %% plotISI - Inter-spike interval histograms (0-50 ms), selected clusters
        function plotISI(app)
            T = UITheme;
            ax = app.AxISI;
            sel = app.selectedClusterPos();
            if ~app.hasResults() || isempty(sel)
                UIKit.styleAxes(ax, 'Inter-spike intervals');
                if ~app.hasResults()
                    UIKit.emptyAxes(ax, 'Run spike sorting first');
                else
                    UIKit.emptyAxes(ax, 'Select clusters in step 4');
                end
                return;
            end
            resetAxes(ax);
            hold(ax, 'on');
            edges = 0:0.5:50;
            for p = sel
                q = app.ClusterQC(p);
                if isempty(q.isiMs), continue; end
                histogram(ax, q.isiMs, edges, 'FaceColor', clusterColor(q.id), 'FaceAlpha', 0.45, ...
                    'EdgeColor', 'none', 'DisplayName', sprintf('%s (%.1f%%)', clusterName(q.id), q.isiPct));
            end
            xline(ax, app.SpikeSortParams.refractoryMs, '--', 'Color', T.danger, 'LineWidth', 1.2, ...
                'HandleVisibility', 'off');
            hold(ax, 'off');
            xlim(ax, [0 50]);
            showLegend(ax, 'best');
            UIKit.styleAxes(ax, sprintf('ISI (dashed = %g ms refractory)', app.SpikeSortParams.refractoryMs), ...
                'ISI (ms)', 'Count');
        end

        %% plotAlignmentDiagnostics - Up to 50 spikes before / after alignment
        function plotAlignmentDiagnostics(app)
            T = UITheme;
            if ~isstruct(app.SpikeResults) || ~isfield(app.SpikeResults, 'waveformsRaw') || ...
                    isempty(app.SpikeResults.waveformsRaw) || ~app.hasResults()
                UIKit.styleAxes(app.AxAlignBefore, 'Before alignment');
                UIKit.emptyAxes(app.AxAlignBefore, 'Run spike sorting first');
                UIKit.styleAxes(app.AxAlignAfter, 'After alignment');
                UIKit.emptyAxes(app.AxAlignAfter, 'Run spike sorting first');
                return;
            end

            rawWaves = app.SpikeResults.waveformsRaw;
            alignedWaves = app.SpikeResults.waveformsAligned;

            N = min(50, size(rawWaves,1));  % visualize up to 50 spikes
            fs = app.MUAData.fs;
            tAxis = (-floor(size(rawWaves,2)/2):floor(size(rawWaves,2)/2)) / fs * 1000;

            ax = app.AxAlignBefore;
            resetAxes(ax);
            hold(ax, 'on');
            plot(ax, tAxis, rawWaves(1:N,:)', 'Color', [T.stimColor 0.3]);
            plot(ax, tAxis, mean(rawWaves(1:N,:), 1, 'omitnan'), 'Color', T.sectionTitleColor, 'LineWidth', 2);
            hold(ax, 'off');
            UIKit.styleAxes(ax, sprintf('Before alignment (%d spikes)', N), 'Time (ms)', 'Amplitude (V)');

            ax = app.AxAlignAfter;
            resetAxes(ax);
            hold(ax, 'on');
            plot(ax, tAxis, alignedWaves(1:N,:)', 'Color', [T.plotColors(1,:) 0.3]);
            plot(ax, tAxis, mean(alignedWaves(1:N,:), 1), 'Color', T.plotColors(1,:), 'LineWidth', 2);
            hold(ax, 'off');
            UIKit.styleAxes(ax, 'After alignment (on peak)', 'Time (ms)', 'Amplitude (V)');
            linkaxes([app.AxAlignBefore, app.AxAlignAfter], 'y');
        end

        %% updateClusterScatter - Cluster selection changed: redraw plots
        function updateClusterScatter(app)
            % Nothing to show until spike sorting has produced results
            if ~app.hasResults(), return; end
            app.plotSignal();
            app.refreshResultPlots();
            app.updateControls();
            n = numel(app.selectedClusterPos());
            UIKit.setStatus(app.StatusLabel, sprintf('%d cluster%s selected', n, plural(n)), 'info');
        end

        %% selectAllClusters - Select every unit (cluster IDs >= 1)
        function selectAllClusters(app)
            if ~app.hasResults(), return; end
            allClusterIDs = unique(app.SpikeResults.clusterIdx);

            % Only include cluster IDs ≥ 1
            validIdx = find(allClusterIDs > 0);

            if ~isempty(validIdx)
                app.ClusterSelectMenu.Value = validIdx(:)';
                app.updateClusterScatter();
            else
                UIKit.setStatus(app.StatusLabel, 'No units to select: every spike is noise (cluster 0)', 'warning');
            end
        end

        %% clearClusterSelection - Deselect all clusters
        function clearClusterSelection(app)
            if isempty(app.ClusterSelectMenu.Items), return; end
            try
                app.ClusterSelectMenu.Value = [];
            catch
                app.ClusterSelectMenu.Value = {};
            end
            app.updateClusterScatter();
        end

        %% saveResults - Save results, QC and settings to a .mat file
        % -------------------------------------------------------------
        % Variables: SpikeResults (as computed), SpikeSortParams,
        % clusterQuality (struct array), info (source file, channel,
        % segment window, segment params, fs).
        % -------------------------------------------------------------
        function saveResults(app)
            if ~app.hasResults()
                UIKit.alert(app.UIFig, 'Run spike sorting before saving results.', 'Nothing to save', 'warning');
                return;
            end
            if ~app.resultsCurrent()
                UIKit.setStatus(app.StatusLabel, sprintf('Saving the results for %s (not the current selection)', ...
                    app.SortContext.label), 'warning');
            end
            defDir = ProjectManager.getExportDir();
            if isempty(defDir), defDir = Exporter.getLastUsedPath(); end
            if isempty(defDir) || ~exist(defDir, 'dir'), defDir = pwd; end
            [~, base] = fileparts(app.FilePath);
            defName = sprintf('%s_ch%d_spikes.mat', base, app.SortContext.channel);
            if ~isempty(app.SortContext.segIdx)
                defName = sprintf('%s_ch%d_seg%d_spikes.mat', base, app.SortContext.channel, app.SortContext.segIdx);
            end
            [file, path] = uiputfile('*.mat', 'Save spike sorting results', fullfile(defDir, defName));
            figure(app.UIFig);
            if isequal(file, 0)
                UIKit.setStatus(app.StatusLabel, 'Save cancelled', 'info');
                return;
            end

            SpikeResults = app.SpikeResults;
            SpikeSortParams = app.SpikeSortParams; %#ok<NASGU>
            clusterQuality = rmfield(app.ClusterQC, 'isiMs');
            info = struct('sourceFile', app.FilePath, 'channel', app.SortContext.channel, ...
                'segmentIndex', app.SortContext.segIdx, 'segmentWindow', app.SortContext.segWin, ...
                'segmentParams', app.SegmentParams, 'fs', app.MUAData.fs);
            % Merges / splits applied after sorting (saved with info below)
            info.clusterEdits = app.ClusterEdits; %#ok<STRNU>
            outFile = fullfile(path, file);
            UIKit.setStatus(app.StatusLabel, sprintf('Saving %s...', file), 'busy');
            try
                try
                    save(outFile, 'SpikeResults', 'SpikeSortParams', 'clusterQuality', 'info');
                catch
                    save(outFile, 'SpikeResults', 'SpikeSortParams', 'clusterQuality', 'info', '-v7.3');
                end
                Exporter.setLastUsedPath(path);
                UIKit.setStatus(app.StatusLabel, sprintf('Saved %s (%d spikes, %d clusters)', file, ...
                    numel(SpikeResults.spikeTimes), numel(clusterQuality)), 'success');
            catch ME
                UIKit.alert(app.UIFig, sprintf('Could not save %s:\n%s', file, ME.message), 'Save failed', 'error');
                UIKit.setStatus(app.StatusLabel, sprintf('Save failed: %s', ME.message), 'error');
            end
        end

        %% ----------------------------------------------------------------
        %% Sessions and reports (core/Session.m, core/Report.m)
        %% saveSessionTo - Save inputs (path, size, date, MD5), settings, results and notes (no dialog)
        function ok = saveSessionTo(app, filePath, notes)
            if nargin < 3, notes = []; end
            ok = Session.saveApp(app, filePath, notes);
        end

        %% openSession - Reopen a .nasession.mat saved by this window
        % interactive (default false, no dialogs): ask for missing inputs
        % and show warnings as alerts. Returns true when restored.
        function ok = openSession(app, filePath, interactive)
            if nargin < 3, interactive = false; end
            ok = Session.openInApp(app, filePath, interactive);
        end

        %% makeReport - One-page PDF: window image + versions, inputs (MD5), settings, results
        function ok = makeReport(app, pdfPath)
            ok = Report.forApp(app, pdfPath);
        end

        %% sessionState - Settings, results and inputs for Session.capture
        % settings: channel, segmentation (parameters, windows, segment),
        % sorting parameters, raster / correlogram / rate fields, selected
        % clusters and tab. results: SpikeResults with the display state,
        % cluster QC, edit history (Undo) and the list of edits.
        function st = sessionState(app)
            st.inputs = [];
            st.settings = struct();
            st.results = struct();
            st.summary = {};
            if isempty(app.MUAData), return; end
            st.inputs = Session.fileInfo(app.FilePath, 'MUA file');
            chIdx = app.ChannelMenu.Value;
            st.settings.channelIndex = chIdx;
            st.settings.channel = app.MUAData.channels(chIdx);
            st.settings.segmentation = struct('on', logical(app.SegmentCheckbox.Value), ...
                'params', app.SegmentParams, 'segments', app.Segments, 'segment', app.SegmentMenu.Value);
            st.settings.sortParams = app.SpikeSortParams;
            st.settings.raster = struct('from', app.RasterFromField.Value, 'to', app.RasterToField.Value, ...
                'binMs', app.RasterBinField.Value);
            st.settings.correlogram = struct('maxLagMs', app.CorrLagField.Value, 'binMs', app.CorrBinField.Value);
            st.settings.rate = struct('binS', app.RateBinField.Value, 'relative', logical(app.RateRelativeCheck.Value));
            st.settings.selectedClusters = app.selectedClusterIds();
            st.settings.tab = app.TabGroup.SelectedTab.Title;
            st.summary{end+1} = sprintf('MUA: %d channel(s) at %s Hz, analysed Ch %d', numel(app.MUAData.channels), ...
                num2str(app.MUAData.fs), st.settings.channel);
            if ~app.hasResults(), return; end
            r = struct();
            r.spikeResults = app.SpikeResults;
            r.sortContext = app.SortContext;
            r.clusterQC = app.ClusterQC;
            r.spikeLocs = app.SpikeLocs;
            r.threshLines = app.ThreshLines;
            r.spikeWaves = app.SpikeWaves;
            r.displayPCs = app.DisplayPCs;
            r.editHistory = app.EditHistory;
            r.clusterEdits = app.ClusterEdits;
            st.results = r;
            qc = app.ClusterQC;
            st.summary{end+1} = sprintf('Sorted %d spikes on %s: %d unit(s), %d rejected', ...
                numel(app.SpikeResults.spikeTimes), app.SortContext.label, sum([qc.id] > 0), sum([qc.rejected]));
            for k = 1:numel(qc)
                if qc(k).id == 0
                    st.summary{end+1} = sprintf('  noise (0): %d spikes', qc(k).n); %#ok<AGROW>
                else
                    st.summary{end+1} = sprintf('  unit %d: %d spikes, SNR %.2f, ISI < refractory %.2f%%%s', ...
                        qc(k).id, qc(k).n, qc(k).snr, qc(k).isiPct, ifelseText(qc(k).rejected, ' (rejected)', '')); %#ok<AGROW>
                end
            end
            for k = 1:numel(app.ClusterEdits)
                st.summary{end+1} = sprintf('  edit %d: %s', k, app.ClusterEdits{k}); %#ok<AGROW>
            end
        end

        %% restoreSession - Reload the MUA file, re-apply settings, restore the sorting as saved
        function ok = restoreSession(app, s)
            ok = false;
            if isempty(s.inputs), ok = true; return; end
            if ~app.openFile(s.inputs(1).path, false), return; end
            cfg = s.settings;
            if isfield(cfg, 'channelIndex') && ismember(cfg.channelIndex, app.ChannelMenu.ItemsData)
                app.ChannelMenu.Value = cfg.channelIndex;
            end
            if isfield(cfg, 'segmentation')
                seg = cfg.segmentation;
                if ~isempty(seg.params), app.SegmentParams = seg.params; end
                if seg.on && ~isempty(seg.segments) && ~isempty(app.StimData)
                    n = size(seg.segments, 1);
                    app.Segments = seg.segments;
                    app.SegmentCheckbox.Value = true;
                    app.SegmentMenu.Items = arrayfun(@(i) sprintf('Segment %d  (onset %.2f s)', i, ...
                        seg.segments(i, 1) + seg.params.preTime), 1:n, 'UniformOutput', false);
                    app.SegmentMenu.ItemsData = 1:n;
                    app.SegmentMenu.Value = min(max(1, seg.segment), n);
                    app.SegmentInfoLabel.Text = sprintf('%d segment%s: %.2f s before to %.2f s after each onset', ...
                        n, plural(n), seg.params.preTime, seg.params.postTime);
                end
            end
            if isfield(cfg, 'sortParams'), app.SpikeSortParams = cfg.sortParams; end
            app.updateParamsLabel();
            if isfield(cfg, 'raster')
                app.RasterFromField.Value = cfg.raster.from;
                app.RasterToField.Value = cfg.raster.to;
                app.RasterBinField.Value = cfg.raster.binMs;
            end
            if isfield(cfg, 'correlogram')
                app.CorrLagField.Value = cfg.correlogram.maxLagMs;
                app.CorrBinField.Value = cfg.correlogram.binMs;
            end
            if isfield(cfg, 'rate')
                app.RateBinField.Value = cfg.rate.binS;
                app.RateRelativeCheck.Value = cfg.rate.relative;
            end
            r = s.results;
            if isfield(r, 'spikeResults') && isstruct(r.spikeResults) && isstruct(r.clusterQC)
                app.SpikeResults = r.spikeResults;
                app.SortContext = r.sortContext;
                app.ClusterQC = r.clusterQC;
                app.SpikeLocs = r.spikeLocs;
                app.ThreshLines = r.threshLines;
                app.SpikeWaves = r.spikeWaves;
                app.DisplayPCs = r.displayPCs;
                app.EditHistory = r.editHistory;
                if isempty(app.EditHistory), app.EditHistory = emptyHistory(); end
                app.ClusterEdits = r.clusterEdits;
                if isempty(app.ClusterEdits), app.ClusterEdits = {}; end
                if ischar(app.SpikeWaves) || ischar(app.DisplayPCs)
                    app.SpikeWaves = []; app.computeDisplayPCs();   % too large to have been stored
                end
                app.refreshClusterList(cfg.selectedClusters);
                app.refreshResultPlots();
            end
            app.plotSignal();
            if isfield(cfg, 'tab')
                tab = findobj(app.TabGroup, 'Type', 'uitab', 'Title', cfg.tab);
                if ~isempty(tab)
                    app.TabGroup.SelectedTab = tab(1);
                    app.refreshLazyTabs();
                end
            end
            app.updateControls();
            ok = true;
        end

        % ---------------------------------------------------------------------------------------------
        %% Cluster merging for drift correction - implemented in MUAPipeline
        % Kept as app methods (same signatures) for existing callers.
        function bestLabels = optimizeClusterMerging(app, spikeTimes, alignedWaves, clusterLabels, binIDs, params) %#ok<INUSL>
            bestLabels = MUAPipeline.optimizeClusterMerging(spikeTimes, alignedWaves, clusterLabels, binIDs, params);
        end

        function finalLabels = mergeClustersAcrossBins(app, spikeTimes, waveforms, labels, binIDs, corrThresh, distThresh) %#ok<INUSL>
            finalLabels = MUAPipeline.mergeClustersAcrossBins(spikeTimes, waveforms, labels, binIDs, corrThresh, distThresh);
        end

        function mergedLabels = mergeWithinClusters(app, waveforms, labels, corrThresh, distThresh) %#ok<INUSL>
            mergedLabels = MUAPipeline.mergeWithinClusters(waveforms, labels, corrThresh, distThresh);
        end

        function mergedLabels = mergeSimilarClusters(app, waveforms, labels, corrThresh, distThresh) %#ok<INUSL>
            mergedLabels = MUAPipeline.mergeSimilarClusters(waveforms, labels, corrThresh, distThresh);
        end
    end
end

%% ------------------------------------------------------------------------
% UI helpers (local to this app)
% -------------------------------------------------------------------------

%% defaultSortParams - Spike sorting defaults (MUAPipeline.defaultParams)
function p = defaultSortParams()
    p = MUAPipeline.defaultParams();
end

%% defaultSegmentParams - Onset detection / segment defaults (askSegmentParams)
function p = defaultSegmentParams()
    p = struct('minISI', 1, 'threshold', 0.5, 'preTime', 0.5, 'postTime', 1.0);
end

%% ifelseText - a if cond, else b
function s = ifelseText(cond, a, b)
    if cond, s = a; else, s = b; end
end

%% emptyHistory - No cluster edits to undo
function h = emptyHistory()
    h = struct('labels', {}, 'description', {}, 'edits', {});
end

%% barLabel - Right-aligned label in a tab's control bar
function barLabel(parent, text)
    T = UITheme;
    uilabel(parent, 'Text', text, 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor, ...
        'HorizontalAlignment', 'right');
end

%% stepCard - UIKit.card with a numbered step label on the first row
% Returns the card's grid; rowHeights/colWidths are for the rows below
% the step label (which spans all columns).
function g = stepCard(parent, n, text, rowHeights, colWidths)
    T = UITheme;
    if nargin < 5, colWidths = {'1x'}; end
    card = UIKit.card(parent, '');
    g = uigridlayout(card, [1 + numel(rowHeights), numel(colWidths)], ...
        'RowHeight', [{22}, rowHeights], 'ColumnWidth', colWidths, ...
        'Padding', [10 8 10 8], 'RowSpacing', 6, 'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
    lbl = UIKit.step(g, n, text);
    lbl.Layout.Row = 1;
    if numel(colWidths) > 1, lbl.Layout.Column = [1 numel(colWidths)]; end
end

%% placeField - UIKit.field placed explicitly on one row (label | control)
function c = placeField(grid, row, labelText, kind, value, tooltip, limits)
    if nargin < 7, limits = []; end
    c = UIKit.field(grid, labelText, kind, value, tooltip, limits);
    lbl = grid.Children(2);  % UIKit.field creates the label just before the control
    lbl.Layout.Row = row; lbl.Layout.Column = 1;
    c.Layout.Row = row; c.Layout.Column = 2;
end

%% sectionLabel - Bold section heading spanning both dialog columns
function sectionLabel(grid, row, text)
    T = UITheme;
    lbl = uilabel(grid, 'Text', text, 'FontSize', T.fontBody, 'FontWeight', 'bold', ...
        'FontColor', T.accent, 'VerticalAlignment', 'bottom');
    lbl.Layout.Row = row; lbl.Layout.Column = [1 2];
end

%% showLegend - Compact, borderless legend of the named series
function showLegend(ax, location)
    T = UITheme;
    lg = legend(ax);
    lg.Location = location;
    lg.Box = 'off';
    lg.FontSize = T.fontTiny;
end

%% setButtonStyle - Restyle a UIKit button as primary or secondary
% (UIKit.button only styles at creation; callers pass isPrimary only
% for enabled buttons.)
function setButtonStyle(b, isPrimary)
    T = UITheme;
    if isPrimary
        b.BackgroundColor = T.accent; b.FontColor = [1 1 1]; b.FontWeight = 'bold';
    else
        b.BackgroundColor = T.secondaryBg; b.FontColor = T.secondaryFg; b.FontWeight = 'normal';
    end
end

%% resetAxes - Clear axes and undo UIKit.emptyAxes (ticks, legend)
function resetAxes(ax)
    cla(ax);
    legend(ax, 'off');
    ax.XTickMode = 'auto'; ax.YTickMode = 'auto';
    ax.XTickLabelMode = 'auto'; ax.YTickLabelMode = 'auto';
    ax.XLimMode = 'auto'; ax.YLimMode = 'auto';
end

%% clusterColor - UITheme.plotColors cycle for units; noise (0) in gray
% The palette's last row is gray, so units cycle through the other rows.
function c = clusterColor(k)
    T = UITheme;
    if k == 0
        c = T.mutedColor;
        return;
    end
    P = T.plotColors(1:end-1, :);
    c = P(mod(k - 1, size(P, 1)) + 1, :);
end

%% clusterName - 'Cluster k', or 'Noise (0)' for unclustered spikes
function s = clusterName(k)
    if k == 0
        s = 'Noise (0)';
    else
        s = sprintf('Cluster %d', k);
    end
end

%% clusterListText - Listbox entry: name, spike count, rejected flag
function s = clusterListText(q)
    s = sprintf('%s  ·  %d spikes', clusterName(q.id), q.n);
    if q.rejected, s = [s '  ·  rejected']; end
end

%% pickItem - value if it is one of items, else the first item
function v = pickItem(items, value)
    if any(strcmp(items, value))
        v = value;
    else
        v = items{1};
    end
end

%% formatDuration - '45.2 s' or '12.3 min'
function s = formatDuration(sec)
    if sec < 120
        s = sprintf('%.1f s', sec);
    else
        s = sprintf('%.1f min', sec / 60);
    end
end

%% onOff / yesNo / plural - Small text helpers
function s = onOff(cond)
    if cond, s = 'on'; else, s = 'off'; end
end

function s = yesNo(cond)
    if cond, s = 'yes'; else, s = 'no'; end
end

function s = plural(n)
    if n == 1, s = ''; else, s = 's'; end
end
