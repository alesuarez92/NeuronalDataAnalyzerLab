%% MUAAnalysisApp.m
% =========================================================================
% MUA ANALYSIS - LOAD MUA, SEGMENT BY STIMULUS, SPIKE SORTING, SPIKE RATE
% =========================================================================
% Launched from Main. Loads .mat saved from ExtractEphysApp (mua_data,
% mua_fs, t_mua, mua_channels; optional stim_data, stim_fs, t_stim).
% Window built with UIKit.window; left column of numbered step cards:
%   1 Load MUA file      - file name, Fs, duration, channels, stimulus yes/no
%   2 Channel & segments - channel dropdown; optional segmentation by
%                          stimulation onsets (parameters in a UIKit.dialog)
%   3 Spike sorting      - Configure... (UIKit.dialog: detection threshold
%                          and polarity, features, clustering, drift
%                          correction) and Run
%   4 Clusters           - cluster listbox (multi-select), Select all /
%                          Clear, quality summary
%   5 Export             - save spike times, cluster IDs and QC to .mat
% Right side: tabs 'Signal & spikes', 'Waveforms', 'Clusters',
% 'Spike rate' and 'Quality' (QC table, ISI histograms, alignment check).
% One updateControls() enables controls from the data state and marks the
% next recommended action as primary. Help button opens HelpApp on the
% "MUA Analysis" tab. Analysis: runSpikeSorting (wrapper with busy dialog)
% -> doSpikeSorting (detection, alignment, features, clustering, QC);
% cluster merging helpers for drift correction are unchanged.
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
        BusyDlg             % uiprogressdlg while sorting
    end

    methods
        %% Constructor - Build UI; data loaded via Load MUA file
        % -------------------------------------------------------------
        % Must not open dialogs or block (CI smoke test screenshots UIFig).
        % -------------------------------------------------------------
        function app = MUAAnalysisApp()
            app.SpikeSortParams = defaultSortParams();
            app.buildUI();
        end

        %% buildUI - Step cards on the left, result tabs on the right
        % -------------------------------------------------------------
        function buildUI(app)
            T = UITheme;
            W = UIKit.window('MUA Analysis', ...
                'Detect and sort spikes from multi-unit activity, then check quality and firing rate', ...
                'MUA Analysis', [1280 880]);
            app.UIFig = W.Fig;
            app.StatusLabel = W.Status;
            W.Body.RowHeight = {'1x'};
            W.Body.ColumnWidth = {310, '1x'};

            left = uigridlayout(W.Body, [5 1], ...
                'RowHeight', {136, 160, 124, '1x', 84}, 'ColumnWidth', {'1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 8, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;

            % --- 1 Load MUA file ---
            g = stepCard(left, 1, 'Load MUA file', {T.buttonHeight, 'fit', 'fit'});
            app.LoadBtn = UIKit.button(g, 'Load MUA file...', @(~,~)app.loadData(), 'primary', ...
                'Open a .mat file saved by Extract Ephys (MUA channels, optional stimulus)');
            app.FileLabel = uilabel(g, 'Text', 'No file loaded', 'FontSize', T.fontBody, ...
                'FontColor', T.sectionTitleColor, 'FontWeight', 'bold', 'Interpreter', 'none');
            app.FileInfoLabel = uilabel(g, 'Text', 'Sampling rate, duration and channels appear here', ...
                'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'WordWrap', 'on');

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
            g = stepCard(left, 4, 'Clusters', {'1x', T.buttonHeight, 'fit'}, {'1x', '1x'});
            app.ClusterSelectMenu = uilistbox(g, 'Items', {}, 'Multiselect', 'on', ...
                'FontSize', T.fontBody, 'Tooltip', ...
                'Clusters shown in the plots. Ctrl/Shift-click to select several. Cluster 0 is noise (unclustered spikes).', ...
                'ValueChangedFcn', @(~,~)app.updateClusterScatter());
            app.ClusterSelectMenu.Layout.Row = 2; app.ClusterSelectMenu.Layout.Column = [1 2];
            app.SelectAllBtn = UIKit.button(g, 'Select all', @(~,~)app.selectAllClusters(), ...
                'secondary', 'Select every unit (noise cluster 0 excluded)');
            app.SelectAllBtn.Layout.Row = 3; app.SelectAllBtn.Layout.Column = 1;
            app.ClearBtn = UIKit.button(g, 'Clear', @(~,~)app.clearClusterSelection(), ...
                'secondary', 'Deselect all clusters');
            app.ClearBtn.Layout.Row = 3; app.ClearBtn.Layout.Column = 2;
            app.QualityLabel = uilabel(g, 'Text', 'Run spike sorting to see clusters', ...
                'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'WordWrap', 'on');
            app.QualityLabel.Layout.Row = 4; app.QualityLabel.Layout.Column = [1 2];

            % --- 5 Export ---
            g = stepCard(left, 5, 'Export', {T.buttonHeight});
            app.SaveBtn = UIKit.button(g, 'Save results...', @(~,~)app.saveResults(), 'secondary', ...
                'Save spike times, cluster IDs, waveforms, quality metrics and settings to a .mat file');

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
            app.RateBinField.Enable = onOff(hasRes);
            app.RateRelativeCheck.Enable = onOff(hasRes);

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
        % Requires mua_data, mua_fs, t_mua, mua_channels; stim_data,
        % stim_fs and t_stim are optional. Resets segmentation and any
        % previous sorting results.
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

            UIKit.setStatus(app.StatusLabel, sprintf('Loading %s...', file), 'busy');
            dlg = UIKit.busy(app.UIFig, sprintf('Loading %s...', file));
            try
                data = load(fullfile(path, file));
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
                app.FilePath = fullfile(path, file);

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
                Exporter.setLastUsedPath(path);

                app.plotSignal();
                app.refreshResultPlots();
                UIKit.done(dlg);
                app.updateControls();
                UIKit.setStatus(app.StatusLabel, sprintf('Loaded %s (%s Hz, %s, %d channels) - next: Run spike sorting (step 3)', ...
                    file, num2str(fs), formatDuration(durSec), numel(app.MUAData.channels)), 'success');
            catch ME
                UIKit.done(dlg);
                app.updateControls();
                UIKit.alert(app.UIFig, sprintf('Could not load %s:\n%s', file, ME.message), ...
                    'Cannot load file', 'error');
                UIKit.setStatus(app.StatusLabel, sprintf('Error loading %s: %s', file, ME.message), 'error');
            end
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
                stim = app.StimData.signal;
                t = app.StimData.time;
                aboveThresh = stim > threshold;
                onsetIdx = find(diff([0; aboveThresh(:)]) == 1);
                onsetTimes = t(onsetIdx(:));
                onsetTimes = onsetTimes(:);
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
                prev = struct('minISI', 1, 'threshold', 0.5, 'preTime', 0.5, 'postTime', 1.0);
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
                UIKit.emptyAxes(app.AxStim, 'Load a file to begin');
                UIKit.styleAxes(app.AxStim, 'Stimulus');
                UIKit.emptyAxes(app.AxMUA, 'Load a MUA file (step 1) to see the signal');
                UIKit.styleAxes(app.AxMUA, 'MUA signal');
                return;
            end
            [chIdx, segIdx] = app.currentSelection();
            chNum = app.MUAData.channels(chIdx);

            % Always plot full stimulus trace (if the file has one)
            ax = app.AxStim;
            if isempty(app.StimData)
                UIKit.emptyAxes(ax, 'No stimulus channel in this file');
                UIKit.styleAxes(ax, 'Stimulus');
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
                UIKit.emptyAxes(ax, 'This segment lies outside the recording');
                UIKit.styleAxes(ax, sprintf('Segment %d - Channel %d', segIdx, chNum));
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
            UIKit.styleAxes(ax, ttl, xl, 'Amplitude (a.u.)');
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
            p = app.SpikeSortParams;
            D = UIKit.dialog('Spike sorting settings', 'Detection, features, clustering and drift', ...
                'MUA Analysis', [520 800]);
            nRows = 21;
            D.Body.RowHeight = repmat({T.controlHeight}, 1, nRows);
            D.Body.RowHeight([1 10 17]) = {22};
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

            % --- Drift correction ---
            sectionLabel(D.Body, 17, 'Drift correction');
            driftCheck = placeField(D.Body, 18, 'Correct for drift', 'checkbox', ...
                logical(p.enableDriftCorrection), ...
                'Compensate for slow changes in spike shape over long recordings');
            driftOpts = {'Time Binning', 'Dynamic Clustering'};
            driftMethodPopup = placeField(D.Body, 19, 'Drift method', 'dropdown', ...
                {driftOpts, pickItem(driftOpts, p.driftMethod)}, ...
                ['Time Binning: cluster each time bin separately, then join matching units ' ...
                 'across bins. Dynamic Clustering: add time as an extra feature.']);
            driftBinBox = placeField(D.Body, 20, 'Bin width (s)', 'numeric', p.driftBinWidth, ...
                'Length of each time bin for Time Binning (s)', [0 Inf]);
            driftBinBox.LowerLimitInclusive = 'off';
            GridSearchCheck = placeField(D.Body, 21, 'Optimize merge thresholds (grid search)', 'checkbox', ...
                logical(p.enableGridSearchCheck), ...
                'Try several merge thresholds and keep the one with the best silhouette (slower)');

            filterCheckbox.ValueChangedFcn = @(~,~)updateDialogEnable();
            clusterPopup.ValueChangedFcn = @(~,~)updateDialogEnable();
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
                disp(params);
                delete(D.Fig);
                app.SpikeSortParams = params;
                app.updateParamsLabel();
                app.runSpikeSorting(params);
            end
        end

        %% updateParamsLabel - One-line summary of the sorting settings
        function updateParamsLabel(app)
            p = app.SpikeSortParams;
            s = sprintf('%s, k = %g, %s polarity  ·  %s + %s', p.detectMethod, p.threshold, ...
                p.polarity, p.featureMethod, p.clusterMethod);
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
                UIKit.setStatus(app.StatusLabel, sprintf(['Sorted %d spikes into %d unit%s (%d rejected) on %s ' ...
                    'in %.1f s - review the tabs, then Save results (step 5)'], ...
                    numel(app.SpikeResults.spikeTimes), nUnits, plural(nUnits), nRej, ...
                    app.SortContext.label, toc(tStart)), 'success');
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
            app.ClusterSelectMenu.Items = {};
            app.ClusterSelectMenu.ItemsData = [];
            app.QualityLabel.Text = 'Run spike sorting to see clusters';
        end

        %% doSpikeSorting - Detection, alignment, features, clustering, QC
        % -------------------------------------------------------------
        % Returns true on success. Failures call failSort and return false.
        % -------------------------------------------------------------
        function ok = doSpikeSorting(app, params)
            ok = false;
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
                app.SpikeResults.segmentedMUA = x;
                app.SpikeResults.segmentedTime = t;
            else
                t = app.MUAData.time;
                x = app.MUAData.data(chIdx, :);
                tAll = t; %#ok<NASGU>
                xAll = x; %#ok<NASGU>
                app.SpikeResults.segmentedMUA = x;
                app.SpikeResults.segmentedTime = t;
            end

            fs = app.MUAData.fs;

            % --- Optional bandpass filter before detection (zero-phase) ---
            if params.filter
                nyq = fs / 2;
                if ~(isfinite(params.bpLow) && isfinite(params.bpHigh) && params.bpLow > 0 && ...
                        params.bpHigh > params.bpLow && params.bpHigh < nyq)
                    app.failSort(sprintf('Invalid bandpass range. Require 0 < low < high < %.0f Hz (Nyquist).', nyq), ...
                        'Filter Error');
                    return;
                end
                app.setStage(sprintf('Filtering %g-%g Hz...', params.bpLow, params.bpHigh));
                [bFilt, aFilt] = butter(3, [params.bpLow params.bpHigh] / nyq, 'bandpass');
                x = filtfilt(bFilt, aFilt, double(x));
                app.SpikeResults.segmentedMUA = x;
            end

            % --- Spike detection based on method and polarity ---
            % Detection uses a short dead time (~0.3 ms) so that sub-refractory
            % ISIs stay visible to the ISI quality check; the refractory period
            % is used for QC only. Double detections of the same spike are
            % removed after alignment (same extremum).
            deadSamples = max(1, round(0.3e-3 * fs));

            %% Spike detection
            app.setStage(sprintf('Detecting spikes (%s)...', params.detectMethod));
            isNEO = strcmpi(params.detectMethod, 'neo');
            if isNEO
                % Nonlinear Energy Operator: psi[n] = x[n]^2 - x[n-1]*x[n+1].
                % Spikes of either sign give large positive psi, so the NEO
                % output is searched directly irrespective of polarity.
                xd = double(x);
                psi = zeros(size(xd));
                psi(2:end-1) = xd(2:end-1).^2 - xd(1:end-2) .* xd(3:end);
                searchSigns = 1;
            else
                switch lower(params.polarity)
                    case 'negative', searchSigns = -1;
                    case 'positive', searchSigns = 1;
                    otherwise,       searchSigns = [1 -1];  % 'both'
                end
            end

            locs = [];
            threshLines = [];  % thresholds on the MUA amplitude scale (for plotting)
            for sgn = searchSigns
                if isNEO
                    dataToSearch = psi;
                    % Threshold on the NEO scale
                    thr = mean(psi) + params.threshold * std(psi);
                else
                    % Search the sign-flipped signal; threshold computed on it
                    dataToSearch = sgn * double(x);
                    switch lower(params.detectMethod)
                        case {'mad', 'rolling mad'}
                            med = median(dataToSearch);
                            madVal = 1.4826 * median(abs(dataToSearch - med));
                            thr = med + params.threshold * madVal;
                        case 'percentile'
                            thr = prctile(abs(dataToSearch), 99.9);  % 99.9th percentile
                        otherwise  % 'standard'
                            thr = mean(dataToSearch) + params.threshold * std(dataToSearch);
                    end
                    threshLines(end+1) = sgn * thr; %#ok<AGROW>
                end

                if strcmpi(params.detectMethod, 'rolling mad')
                    initialIdx = find(dataToSearch > thr);
                    sgnLocs = [];
                    last = -Inf;
                    searchWindow = round(0.5 * fs / 1000 * params.alignWinMs);  % 0.5 ms in samples
                    for i = 1:length(initialIdx)
                        if initialIdx(i) - last > deadSamples
                            winStart = max(1, initialIdx(i) - searchWindow);
                            winEnd = min(length(dataToSearch), initialIdx(i) + searchWindow);
                            [~, peakRel] = max(dataToSearch(winStart:winEnd));
                            sgnLocs(end+1,1) = winStart + peakRel - 1; %#ok<AGROW>
                            last = sgnLocs(end);
                        end
                    end
                else
                    % Global threshold
                    [~, sgnLocs] = findpeaks(dataToSearch, 'MinPeakHeight', thr, ...
                        'MinPeakDistance', deadSamples);
                end
                locs = [locs; sgnLocs(:)]; %#ok<AGROW>
            end
            locs = unique(locs);  % sorted; merges coincident detections

            spikeTimes = t(locs);
            spikeTimes = spikeTimes(:);

            fprintf('[Detection] Method: %s | Polarity: %s | Spikes: %d\n', ...
                lower(params.detectMethod), lower(params.polarity), numel(locs));

            % Exit if no spikes or too few
            if isempty(locs)
                app.failSort('No spikes detected with the current threshold. Try a lower threshold multiplier or another polarity.', ...
                    'Detection Error');
                return;
            end
            if numel(spikeTimes) < params.minSpikesPerCluster * 2
                app.failSort(sprintf(['Too few spikes for clustering (%d detected; need at least 2 x %d). ' ...
                    'Lower the threshold or the minimum spikes per cluster.'], numel(spikeTimes), ...
                    params.minSpikesPerCluster), 'Clustering Error');
                return;
            end

            %% Align waveforms around spike locations
            app.setStage(sprintf('Aligning %d waveforms...', numel(locs)));

            win = round(params.alignWinMs / 1000 * fs);  % half window for output (symmetric)
            preAlignMs = 0.5 * params.alignWinMs;
            postAlignMs = 1.0 * params.alignWinMs;

            preSearch = round(preAlignMs / 1000 * fs);
            postSearch = round(postAlignMs / 1000 * fs);

            alignedWaves = nan(length(locs), 2*win + 1);
            validIdx = false(size(locs));
            peakLocs = nan(size(locs));

            for i = 1:length(locs)
                center = locs(i);
                searchLeft = center - preSearch;
                searchRight = center + postSearch;
                if searchLeft > 0 && searchRight <= length(x)
                    snip = x(searchLeft:searchRight);
                    switch lower(params.polarity)
                        case 'negative', [~, peakIdx] = min(snip);
                        case 'positive', [~, peakIdx] = max(snip);
                        case 'both',     [~, peakIdx] = max(abs(snip));
                    end
                    peakLoc = searchLeft + peakIdx - 1;
                    leftFinal = peakLoc - win;
                    rightFinal = peakLoc + win;
                    if leftFinal > 0 && rightFinal <= length(x)
                        alignedWaves(i,:) = x(leftFinal:rightFinal);
                        validIdx(i) = true;
                        peakLocs(i) = peakLoc;
                    end
                end

            end

            % Drop double detections of the same spike (snapped to the same extremum)
            validPos = find(validIdx);
            [~, keepPos] = unique(peakLocs(validPos), 'stable');
            validIdx(:) = false;
            validIdx(validPos(keepPos)) = true;

            % Filter only valid waveform rows
            alignedWaves = alignedWaves(validIdx, :);
            locs = locs(validIdx);  % spike indices
            spikeTimes = spikeTimes(validIdx);  % spike times aligned with waveforms
            if numel(locs) < params.minSpikesPerCluster * 2
                app.failSort('Too few spikes with complete waveforms for clustering.', 'Clustering Error');
                return;
            end

            % Store original waveforms (centered at detection locs)
            preAlignedWaves = nan(length(locs), 2*win + 1);
            for i = 1:length(locs)
                if locs(i)-win > 0 && locs(i)+win <= length(x)
                    preAlignedWaves(i,:) = x(locs(i)-win : locs(i)+win);
                end
            end

            % Save both raw and aligned waveforms for diagnostics
            app.SpikeResults.waveformsAligned = alignedWaves;
            app.SpikeResults.waveformsRaw = preAlignedWaves;

            %% Feature extraction for clustering
            app.setStage(sprintf('Extracting features (%s)...', params.featureMethod));

            switch lower(params.featureMethod)
                case 'pca'
                    maxComp = min(params.numComponents, size(alignedWaves,2));
                    coeff = pca(alignedWaves);
                    features = alignedWaves * coeff(:, 1:maxComp);
                case 'ica'
                    try
                        [icasig, ~, ~] = fastica(alignedWaves', 'numOfIC', params.numComponents);
                        features = icasig(1:params.numComponents, :)';
                    catch
                        warning('ICA failed, using zeros.');
                        features = zeros(size(alignedWaves,1), params.numComponents);
                    end
                case 'waveform'
                    maxComp = min(params.numComponents, size(alignedWaves,2));
                    features = alignedWaves(:, 1:maxComp);
                case 'wavelet'
                    wv = cell(size(alignedWaves,1), 1);  % preallocate
                    for i = 1:size(alignedWaves,1)
                        [c,~] = wavedec(alignedWaves(i,:), 3, 'haar');
                        nComp = min(params.numComponents, length(c));
                        wv{i} = c(1:nComp);  % truncate to fixed length
                    end

                    try
                        features = cell2mat(wv);  % results in N x numComponents
                    catch
                        warning('Wavelet features inconsistent in size. Falling back to zeros.');
                        features = zeros(size(alignedWaves,1), params.numComponents);
                    end
                case 't-sne'
                    try
                        maxComp = min(params.numComponents, 3);
                        features = tsne(alignedWaves, 'NumDimensions', maxComp);
                    catch
                        warning('t-SNE failed, using zeros.');
                        features = zeros(size(alignedWaves,1), maxComp);
                    end
                otherwise
                    app.failSort('Unknown feature method.', 'Spike sorting');
                    return;
            end
            % Enforce feature matrix shape [N x numComponents]
            [N, ~] = size(alignedWaves);
            if size(features, 1) ~= N
                warning('Feature shape mismatch. Forcing consistent rows.');
                features = reshape(features, N, []);
            end
            % Optional z-score normalization of features (helps clustering)
            if isfield(params, 'normalize') && params.normalize
                mu = mean(features, 1);
                sig = std(features, 0, 1);
                sig(sig < 1e-8) = 1;
                features = (features - mu) ./ sig;
            end

            %% Running clustering
            app.setStage(sprintf('Clustering (%s)...', params.clusterMethod));

            % DRIFT CORRECTION: time binning strategy
            if params.enableDriftCorrection && strcmpi(params.driftMethod, 'Time Binning')
                % Compute bin IDs for filtered spikeTimes (aligned to features)
                fullStart = t(1);
                fullEnd = t(end);
                % Add one extra bin edge to guarantee coverage of fullEnd
                nBins = ceil((fullEnd - fullStart) / params.driftBinWidth);
                binEdges = linspace(fullStart, fullStart + nBins * params.driftBinWidth, nBins + 1);
                % Use right-edge inclusion for final bin coverage
                binIDs = discretize(spikeTimes, binEdges, 'IncludedEdge', 'right');
                uniqueBins = unique(binIDs(~isnan(binIDs)));
                numBins = numel(uniqueBins);
                minSpikesPerBin = max(2, ceil(params.minSpikesPerCluster / numBins));  % minimum 2 to allow 1 cluster
                fprintf('[Auto] Using minSpikesPerBin = %d (from global %d across %d bins)\n', ...
                            minSpikesPerBin, params.minSpikesPerCluster, numBins);

                % Initialize
                waveformBins = {};
                labelBins = {};
                timeBins = {};

                for b = uniqueBins(:)'  % loop over bins
                    binIdx = (binIDs == b);
                    fprintf('[DEBUG] Bin %d: %d spikes\n', b, sum(binIdx));
                    if sum(binIdx) < minSpikesPerBin
                        continue;  % skip small bins
                    end

                    binFeatures = features(binIdx, :);
                    binWaveforms = alignedWaves(binIdx, :);
                    binTimes = spikeTimes(binIdx);

                    switch lower(params.clusterMethod)
                        case 'k-means', [labels, valid] = tryKMeans(binFeatures, minSpikesPerBin);
                        case 'gmm',    [labels, valid] = tryGMM(binFeatures, minSpikesPerBin);
                        case 'dbscan', [labels, valid] = tryDBSCAN(binFeatures, minSpikesPerBin, params.dbscanEpsilon);
                    end

                    if valid
                        waveformBins{end+1} = binWaveforms; %#ok<AGROW>
                        labelBins{end+1} = labels; %#ok<AGROW>
                        timeBins{end+1} = binTimes; %#ok<AGROW>
                    end
                    fprintf('[DEBUG] Bin %d → valid: %d | #clusters: %d\n', ...
                        b, valid, numel(unique(labels)));
                end

                if isempty(waveformBins)
                    app.failSort('Time-binning drift correction: no time bin produced a valid clustering.', ...
                        'Clustering Error');
                    return;
                end

                % Flatten all bins into one array
                spikeTimesFlat = []; waveformsFlat = []; labelsFlat = []; binIDsFlat = [];
                for i = 1:numel(waveformBins)
                    waveformsFlat = [waveformsFlat; waveformBins{i}]; %#ok<AGROW>
                    labelsFlat = [labelsFlat; labelBins{i}(:)]; %#ok<AGROW>
                    spikeTimesFlat = [spikeTimesFlat; timeBins{i}(:)]; %#ok<AGROW>
                    binIDsFlat = [binIDsFlat; i * ones(size(labelBins{i}(:)))]; %#ok<AGROW>
                end

                % Grid search over thresholds to merge clusters
                if params.enableGridSearchCheck
                    app.setStage('Merging clusters across time bins (grid search)...');
                else
                    app.setStage('Merging clusters across time bins...');
                end
                clusterLabels = app.optimizeClusterMerging(spikeTimesFlat, waveformsFlat, labelsFlat, binIDsFlat,params);
                % Enforce global minSpikesPerCluster after merging
                uniqueLabels = unique(clusterLabels);
                for i = 1:numel(uniqueLabels)
                    k = uniqueLabels(i);
                    if k == 0, continue; end  % skip unclustered
                    if sum(clusterLabels == k) < params.minSpikesPerCluster
                        clusterLabels(clusterLabels == k) = 0;  % reassign to noise
                    end
                end
                % Replace spike times, indices and waveforms with the kept bins
                % so they stay in sync with clusterLabels
                spikeTimes = spikeTimesFlat;
                alignedWaves = waveformsFlat;
                locs = round((spikeTimes - t(1)) * fs) + 1;  % aligned to segment trace
                locs = min(max(locs, 1), numel(t));

            % DRIFT CORRECTION: dynamic clustering
            elseif params.enableDriftCorrection && strcmpi(params.driftMethod, 'Dynamic Clustering')

                tSpan = max(spikeTimes) - min(spikeTimes);
                if tSpan <= 0, tSpan = 1; end
                tnorm = (spikeTimes(:) - min(spikeTimes)) / tSpan;
                dynFeatures = [features, tnorm];
                switch lower(params.clusterMethod)
                    case 'k-means', [clusterLabels, valid] = tryKMeans(dynFeatures, params.minSpikesPerCluster);
                    case 'gmm',    [clusterLabels, valid] = tryGMM(dynFeatures, params.minSpikesPerCluster);
                    case 'dbscan', [clusterLabels, valid] = tryDBSCAN(dynFeatures, params.minSpikesPerCluster, params.dbscanEpsilon);
                end
                if ~valid
                    app.failSort(['Dynamic clustering failed: no clustering had enough spikes in every ' ...
                        'cluster. Lower the minimum spikes per cluster or try another method.'], 'Clustering Error');
                    return;
                end
                clusterLabels = app.mergeWithinClusters(alignedWaves, clusterLabels, 0.8, 0.5);  % adjust as needed
            % NO drift correction
            else
                switch lower(params.clusterMethod)
                    case 'k-means', [clusterLabels, valid] = tryKMeans(features, params.minSpikesPerCluster);
                    case 'gmm',    [clusterLabels, valid] = tryGMM(features, params.minSpikesPerCluster);
                    case 'dbscan', [clusterLabels, valid] = tryDBSCAN(features, params.minSpikesPerCluster, params.dbscanEpsilon);
                end
                if ~valid
                    app.failSort(['Clustering failed: no clustering had enough spikes in every cluster. ' ...
                        'Lower the minimum spikes per cluster or try another method.'], 'Clustering Error');
                    return;
                end
            end

            app.setStage('Spike sorting complete. Computing quality metrics...');

            %% Save results and quality metrics
            clusterLabels(~isfinite(clusterLabels)) = 0;
            clusterLabels = round(clusterLabels);
            app.SpikeResults.spikeTimes = spikeTimes;
            app.SpikeResults.clusterIdx = clusterLabels;
            app.SpikeResults.waveforms = {};

            clusterIDs = unique(clusterLabels);

            % Per-cluster SNR and ISI quality checks
            app.SpikeResults.isiViolationRate = containers.Map('KeyType', 'double', 'ValueType', 'double');
            refracMs = params.refractoryMs;  % ← e.g., 1.5
            isiThresh = 2.0;  % max % spikes with ISIs < 1.5 ms allowed
            SNRThresh = 2.0;  % min SNR allowed
            preSpikeBasleine = 0.5; % pre-spike baseline (e.g., first 0.5 ms)
            qc = struct('id', {}, 'n', {}, 'snr', {}, 'isiPct', {}, 'isiMs', {}, ...
                'rejected', {}, 'reason', {});
            for i = 1:numel(clusterIDs)
                k = clusterIDs(i);
                si = locs(clusterLabels == k);
                clusterWaves = alignedWaves(clusterLabels == k, :);

                % Default rejection flag
                isRejected = false;
                rejectionReason = "";

                % --- SNR Calculation ---
                meanWave = mean(clusterWaves, 1);
                ampP2P = max(meanWave) - min(meanWave);

                % Estimate noise from pre-spike baseline (e.g., first 0.5 ms)
                % (at least 2 samples so std is defined at low fs)
                baselineEnd = min(size(clusterWaves, 2), max(2, round(preSpikeBasleine / 1000 * fs)));
                baselineRegion = clusterWaves(:, 1:baselineEnd);
                noiseSD = std(baselineRegion(:));

                snr = ampP2P / (2 * noiseSD);
                if k == 0
                    app.SpikeResults.noiseSNR = snr;
                else
                    app.SpikeResults.snr(k) = snr;
                end

                % Report to console
                fprintf('[SNR] Cluster %d: %.2f (P2P=%.3f, noise=%.3f)\n', ...
                    k, snr, ampP2P, noiseSD);
                % Optional rejection
                if snr < SNRThresh && k ~= 0
                    isRejected = true;
                    rejectionReason = "Low SNR";
                end


                % --- ISI analysis ---
                isi = diff(t(si));
                isiViolations = sum(isi < (refracMs / 1000));  % convert ms to seconds
                violationRate = 100 * isiViolations / max(1, length(isi));


                % Optional rejection
                if violationRate > isiThresh && k ~= 0
                    isRejected = true;
                    if rejectionReason == ""
                        rejectionReason = "ISI Violation";
                    else
                        rejectionReason = rejectionReason + " + ISI Violation";
                    end
                else
                    fprintf('[ISI] Cluster %d: %.2f%% ISIs < %.1f ms\n',k, violationRate, refracMs);
                end

                clusterWaves = alignedWaves(clusterLabels == k, :);
                app.SpikeResults.waveforms{i} = clusterWaves;

                if isRejected
                    fprintf('[REJECTED] Cluster %d: %s\n', k, rejectionReason);
                else
                    if k > 0
                        app.SpikeResults.rejectedClusters(k) = false;
                    end
                end

                % Display-only copy of the QC outcome (table, titles, markers)
                qc(i).id = k;
                qc(i).n = size(clusterWaves, 1);
                qc(i).snr = snr;
                qc(i).isiPct = violationRate;
                qc(i).isiMs = isi(:) * 1000;
                qc(i).rejected = isRejected;
                qc(i).reason = char(rejectionReason);
            end

            % Display state for the plots and the cluster list
            app.ClusterQC = qc;
            app.SpikeLocs = locs(:);
            app.ThreshLines = threshLines;
            chNum = app.MUAData.channels(chIdx);
            label = sprintf('Ch %d', chNum);
            if ~isempty(segIdx), label = sprintf('%s, segment %d', label, segIdx); end
            app.SortContext = struct('chIdx', chIdx, 'channel', chNum, 'segIdx', segIdx, ...
                'segWin', segWin, 'label', label);

            clusterStr = arrayfun(@(q) clusterListText(q), qc, 'UniformOutput', false);
            app.ClusterSelectMenu.Items = clusterStr;
            app.ClusterSelectMenu.ItemsData = 1:numel(clusterIDs);
            app.ClusterSelectMenu.Value = 1:numel(clusterIDs);  % Select all by default
            app.updateQualityLabel();
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

        %% refreshResultPlots - Redraw every result tab from the selection
        function refreshResultPlots(app)
            app.plotWaveforms();
            app.plotFeatureSpace();
            app.plotSpikeRateOverTime();
            app.updateQualityTable();
            app.plotISI();
            app.plotAlignmentDiagnostics();
        end

        %% plotWaveforms - One tile per selected cluster: spikes + mean
        function plotWaveforms(app)
            T = UITheme;
            delete(app.WaveformPanel.Children);
            tl = tiledlayout(app.WaveformPanel, 'flow', 'TileSpacing', 'compact', 'Padding', 'compact');
            sel = app.selectedClusterPos();
            if ~app.hasResults() || isempty(sel)
                ax = nexttile(tl);
                if app.hasResults()
                    UIKit.emptyAxes(ax, 'Select clusters in step 4 to see their waveforms');
                else
                    UIKit.emptyAxes(ax, 'Run spike sorting (step 3) to see spike waveforms');
                end
                UIKit.styleAxes(ax, 'Waveforms');
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
                UIKit.styleAxes(ax, ttl, 'Time (ms)', 'Amplitude (a.u.)');
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
                if ~app.hasResults()
                    UIKit.emptyAxes(ax, 'Run spike sorting (step 3) to see the clusters');
                elseif isempty(sel)
                    UIKit.emptyAxes(ax, 'Select clusters in step 4');
                else
                    UIKit.emptyAxes(ax, 'Waveform PCA not available for these spikes');
                end
                UIKit.styleAxes(ax, 'Clusters in waveform PCA space');
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
                if ~app.hasResults()
                    UIKit.emptyAxes(ax, 'Run spike sorting (step 3) to see the spike rate');
                else
                    UIKit.emptyAxes(ax, 'Select at least one cluster in step 4');
                end
                UIKit.styleAxes(ax, 'Spike rate over time');
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
                if ~app.hasResults()
                    UIKit.emptyAxes(ax, 'Run spike sorting first');
                else
                    UIKit.emptyAxes(ax, 'Select clusters in step 4');
                end
                UIKit.styleAxes(ax, 'Inter-spike intervals');
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
            showLegend(ax, 'northeast');
            UIKit.styleAxes(ax, sprintf('ISI (dashed = %g ms refractory)', app.SpikeSortParams.refractoryMs), ...
                'ISI (ms)', 'Count');
        end

        %% plotAlignmentDiagnostics - Up to 50 spikes before / after alignment
        function plotAlignmentDiagnostics(app)
            T = UITheme;
            if ~isstruct(app.SpikeResults) || ~isfield(app.SpikeResults, 'waveformsRaw') || ...
                    isempty(app.SpikeResults.waveformsRaw) || ~app.hasResults()
                UIKit.emptyAxes(app.AxAlignBefore, 'Run spike sorting first');
                UIKit.styleAxes(app.AxAlignBefore, 'Before alignment');
                UIKit.emptyAxes(app.AxAlignAfter, 'Run spike sorting first');
                UIKit.styleAxes(app.AxAlignAfter, 'After alignment');
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
            UIKit.styleAxes(ax, sprintf('Before alignment (%d spikes)', N), 'Time (ms)', 'Amplitude (a.u.)');

            ax = app.AxAlignAfter;
            resetAxes(ax);
            hold(ax, 'on');
            plot(ax, tAxis, alignedWaves(1:N,:)', 'Color', [T.plotColors(1,:) 0.3]);
            plot(ax, tAxis, mean(alignedWaves(1:N,:), 1), 'Color', T.plotColors(1,:), 'LineWidth', 2);
            hold(ax, 'off');
            UIKit.styleAxes(ax, 'After alignment (on peak)', 'Time (ms)', 'Amplitude (a.u.)');
            linkaxes([app.AxAlignBefore, app.AxAlignAfter], 'y');
        end

        %% updateClusterScatter - Cluster selection changed: redraw plots
        function updateClusterScatter(app)
            % Nothing to show until spike sorting has produced results
            if ~app.hasResults(), return; end
            app.plotSignal();
            app.refreshResultPlots();
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
                'segmentParams', app.SegmentParams, 'fs', app.MUAData.fs); %#ok<NASGU>
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
        % ---------------------------------------------------------------------------------------------
        %% Cluster merging (drift correction) - unchanged analysis code
        function bestLabels = optimizeClusterMerging(app, spikeTimes, alignedWaves, clusterLabels, binIDs,params)
            
            fixedLabels = app.mergeClustersAcrossBins(spikeTimes, alignedWaves, clusterLabels, binIDs, 0.85, 0.5);
            if params.enableGridSearchCheck
                corrVals = 0.8:0.05:0.95;
                distVals = 0.4:0.05:0.6;
                bestScore = -Inf;
                bestLabels = zeros(size(clusterLabels));
                bestCorr = NaN;
                bestDist = NaN;
                
                fprintf('Running grid search over correlation × distance thresholds...\n');
                
                for c = 1:numel(corrVals)
                    for d = 1:numel(distVals)
                        try
                            labels = app.mergeSimilarClusters(alignedWaves, fixedLabels, corrVals(c), distVals(d));
                            u = unique(labels);
                            numClusters = numel(u(u > 0));  % exclude 0
    
                            if numClusters < 2, continue;  end
                            %if numel(unique(labels(labels > 0))) < 2, continue; end  % skip trivial results
                            sil = silhouette(alignedWaves, labels);
                            avgSil = mean(sil(~isnan(sil)));
            
                            if avgSil > bestScore
                                bestScore = avgSil;
                                bestLabels = labels;
                                bestCorr = corrVals(c);
                                bestDist = distVals(d);
                            end
                        catch
                            continue;
                        end
                        u = unique(labels);
                        fprintf('[GridSearch] Corr %.2f Dist %.2f → %d nonzero clusters\n', ...
                            corrVals(c), distVals(d), numel(u(u > 0)));
                    end
                end
                fprintf('Best thresholds → Corr: %.2f, Dist: %.2f | Mean silhouette: %.3f\n', bestCorr, bestDist, bestScore);
            else
                bestLabels = app.mergeSimilarClusters(alignedWaves, fixedLabels, 0.85, 0.5);
            end
        
            
        end

        function finalLabels = mergeClustersAcrossBins(app,spikeTimes, waveforms, labels, binIDs, corrThresh, distThresh)
            % mergeClustersAcrossBins - merges cluster labels across time bins
            % for 2D waveforms [nSpikes x nSamples]
            
            % Inputs:
            %   - spikeTimes: [nSpikes x 1] spike time vector
            %   - waveforms:  [nSpikes x nSamples] (2D array)
            %   - labels:     [nSpikes x 1] initial cluster labels
            %   - binIDs:     [nSpikes x 1] bin index each spike belongs to
            %   - corrThresh: scalar threshold for centroid correlation
            %   - distThresh: scalar threshold for centroid distance
            %
            % Outputs:
            %   - finalLabels: updated label assignments across bins
            %   - labelBank: cell array of cluster info per bin
            
            uniqueBins = unique(binIDs);
            labelOffset = 0;
            finalLabels = zeros(size(labels));
            
            % Store cluster centroids (and their global labels) from previous bin
            prevCentroids = [];
            prevIDs = [];
            
            for b = 1:length(uniqueBins)
                bin = uniqueBins(b);
                idx = (binIDs == bin);
                
                waveBin = waveforms(idx, :);
                labelBin = labels(idx);
                uniqueClusts = unique(labelBin(labelBin > 0));  % label 0 = noise, stays 0
                
                % Compute centroids for each cluster in this bin
                centroids = zeros(length(uniqueClusts), size(waveBin, 2));
                for c = 1:length(uniqueClusts)
                    clusterIdx = labelBin == uniqueClusts(c);
                    centroids(c, :) = mean(waveBin(clusterIdx, :), 1);
                end
                
                % Match clusters to previous bin centroids
                newLabels = zeros(size(labelBin));
                curIDs = zeros(length(uniqueClusts), 1);
                
                for c = 1:length(uniqueClusts)
                    thisCentroid = centroids(c, :);
                    bestMatch = 0;
                    bestScore = -Inf;
                    
                    for p = 1:size(prevCentroids,1)
                        corrVal = pearsonR(thisCentroid, prevCentroids(p,:));
                        distVal = norm(thisCentroid - prevCentroids(p,:));
                        
                        if corrVal >= corrThresh && distVal <= distThresh
                            score = corrVal - 0.01 * distVal;
                            if score > bestScore
                                bestScore = score;
                                bestMatch = p;
                            end
                        end
                    end
                    
                    if bestMatch > 0
                        % Inherit the global label of the matched previous cluster
                        curIDs(c) = prevIDs(bestMatch);
                    else
                        labelOffset = labelOffset + 1;
                        curIDs(c) = labelOffset;
                    end
                    newLabels(labelBin == uniqueClusts(c)) = curIDs(c);
                end
                
                finalLabels(idx) = newLabels;
                if ~isempty(uniqueClusts)  % an all-noise bin keeps the previous reference
                    prevCentroids = centroids;
                    prevIDs = curIDs;
                end
            end
        end

        function mergedLabels = mergeWithinClusters(app, waveforms, labels, corrThresh, distThresh)
            mergedLabels = labels;
            uniqueClusts = unique(labels(labels > 0));  % exclude noise
            centroids = [];
        
            for k = uniqueClusts(:)'
                centroids(k,:) = mean(waveforms(labels == k,:), 1);
            end
        
            % Compare all pairs
            for i = 1:length(uniqueClusts)
                for j = i+1:length(uniqueClusts)
                    c1 = centroids(uniqueClusts(i),:);
                    c2 = centroids(uniqueClusts(j),:);
                    r = pearsonR(c1, c2);
                    d = norm(c1 - c2);
                    if r > corrThresh && d < distThresh
                        mergedLabels(mergedLabels == uniqueClusts(j)) = uniqueClusts(i);
                    end
                end
            end
        
            % Reassign cluster labels to be sequential (keep 0 = noise as 0)
            pos = mergedLabels > 0;
            [~, ~, seqLabels] = unique(mergedLabels(pos), 'sorted');
            mergedLabels(pos) = seqLabels;
        end

        function mergedLabels = mergeSimilarClusters(app, waveforms, labels, corrThresh, distThresh)
            mergedLabels = labels;
            uClust = unique(labels(labels > 0));  % ignore 0/noise
            K = numel(uClust);
            centroids = zeros(K, size(waveforms,2));
        
            % Compute centroid of each cluster
            for i = 1:K
                centroids(i,:) = mean(waveforms(labels == uClust(i), :), 1);
            end
        
            % Pairwise comparison
            map = containers.Map('KeyType', 'double', 'ValueType', 'double');
            for i = 1:K
                map(uClust(i)) = uClust(i);  % initialize
            end
        
            for i = 1:K
                for j = i+1:K
                    r = pearsonR(centroids(i,:), centroids(j,:));
                    d = norm(centroids(i,:) - centroids(j,:));
                    if r > corrThresh && d < distThresh
                        % Merge cluster j into i
                        map(uClust(j)) = map(uClust(i));
                    end
                end
            end
        
            % Apply mapping
            for k = 1:length(labels)
                if labels(k) > 0 && isKey(map, labels(k))
                    mergedLabels(k) = map(labels(k));
                end
            end
        
            % Reassign cluster labels to be sequential (keep 0 = noise as 0)
            pos = mergedLabels > 0;
            [~, ~, seqLabels] = unique(mergedLabels(pos), 'sorted');
            mergedLabels(pos) = seqLabels;
        end
    end
end


function [idx, valid] = tryKMeans(features, minSpikes)
    valid = false;
    maxK = 10;
    bestScore = -Inf;
    bestK = 2;
    idx = [];

    for k = 2:maxK
        tempIdx = kmeans(features, k, 'Replicates', 5, 'MaxIter', 500);
        counts = histcounts(tempIdx, 1:(k+1));

        if all(counts >= minSpikes)
            silScore = mean(silhouette(features, tempIdx));
            if silScore > bestScore
                bestScore = silScore;
                bestK = k;
                idx = tempIdx;
                valid = true;
            end
        end

        
    end
end

function [idx, valid] = tryGMM(features, minSpikes)
    valid = false;
    maxK = 10;
    bestScore = -Inf;
    bestK = 2;
    idx = [];

    for k = 2:maxK
        try
            gmOptions = statset('MaxIter', 500);
            GM = fitgmdist(features, k, 'Options', gmOptions, ...
                'RegularizationValue', 1e-5, 'Replicates', 3);
            tempIdx = cluster(GM, features);
        catch
            continue;
        end

        counts = histcounts(tempIdx, 1:(k+1));
        if all(counts >= minSpikes)
            silScore = mean(silhouette(features, tempIdx));
            if silScore > bestScore
                bestScore = silScore;
                bestK = k;
                idx = tempIdx;
                valid = true;
            end
        end
        
    end
end

function [idx, valid] = tryDBSCAN(features, minSpikes, epsilon)
    if isnan(epsilon) || epsilon <= 0
        % Auto-tune epsilon using k-distance heuristic
        N = size(features, 1);
        if N < 2
            idx = zeros(N, 1);
            valid = false;
            return;
        end
        k = min(10, N - 1); % e.g., 10th nearest neighbor
        % knnsearch avoids the N x N distance matrix; column 1 is self
        [~, D] = knnsearch(features, features, 'K', k + 1);
        kDistances = D(:, k + 1);
        epsilon = prctile(kDistances, 95);  % choose 95th percentile
    end

    idx = dbscan(features, epsilon, minSpikes);

    if all(idx == -1)
        valid = false;
        return;
    end

    idx(idx == -1) = 0; % unclustered
    valid = true;
end

function r = pearsonR(a, b)
    % Pearson correlation of two vectors (base MATLAB, no toolbox)
    R = corrcoef(a(:), b(:));
    r = R(1, 2);
end

%% ------------------------------------------------------------------------
% UI helpers (local to this app)
% -------------------------------------------------------------------------

%% defaultSortParams - Spike sorting defaults (same as the original dialog)
function p = defaultSortParams()
    p = struct();
    p.detectMethod = 'Standard';
    p.clusterMethod = 'K-means';
    p.threshold = 3.5;
    p.refractoryMs = 1.0;
    p.alignWinMs = 1.5;
    p.polarity = 'positive';
    p.filter = 0;
    p.bpLow = 300;
    p.bpHigh = 3000;
    p.featureMethod = 'PCA';
    p.numComponents = 3;
    p.normalize = 1;
    p.minSpikesPerCluster = 20;
    p.enableDriftCorrection = 0;
    p.driftMethod = 'Time Binning';
    p.driftBinWidth = 30;
    p.enableGridSearchCheck = 0;
    p.dbscanEpsilon = NaN;  % auto-tune
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
