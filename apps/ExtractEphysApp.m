%% ExtractEphysApp.m
% =========================================================================
% EXTRACT EPHYS DATA - LOAD TDT TANK, EXTRACT LFP AND MUA STREAMS
% =========================================================================
% Launched from Main. Built with UIKit.window: numbered step cards on the
% left, signal plots on the right, status bar below.
%   1 Load TDT tank  - TDTbin2mat on a tank folder (SDK path resolved from
%                      the toolbox root); requires Whis and xRAW streams.
%   2 Choose channels - stimulus (Whis) channel and one or more xRAW channels.
%   3 Process        - Plot RAW, Process LFP (anti-alias + integer-factor
%                      downsample at the ACTUAL rate fs/dsFactor, lowpass,
%                      60 Hz notch; LFPProcessingParamsApp) or Process MUA
%                      (zero-phase bandpass; MUAProcessingParamsApp). The MUA
%                      signal kept for saving is the unsmoothed bandpassed
%                      trace; smoothing only draws a rectified display envelope.
%   4 Save           - Save LFP / Save MUA write .mat files for
%                      LFPAnalysisApp and MUAAnalysisApp, using the channels
%                      and stim channel snapshotted when processing ran.
% Up to 4 channels are drawn one per tile; more are stacked with offsets in
% one axes. Help button opens HelpApp on the "Ephys Extract" tab.
% "Try demo data" (loadDemo) opens DemoData's synthetic tank
% (DemoData.loadTank instead of TDTbin2mat) and selects stim ch 1 + all RAW
% channels. Programmatic use (no dialogs): openTank(folder), setChannels(stim, raw),
% plotRAWData(), processLFPData(params), processMUAData(params),
% saveLFPTo(path, sel), saveMUATo(path, sel).
% =========================================================================

classdef ExtractEphysApp < handle
    %% PROPERTIES: UI, TDT data struct, selected channels, last processed LFP/MUA and params
    properties
        UIFig
        StatusLabel          % Status bar (UIKit.setStatus)
        LoadBtn
        DemoBtn              % Load the synthetic demo tank (DemoData)
        TankInfoLabel        % Tank name, Fs, duration, channel counts
        WhisChannelMenu      % Stimulus (Whis) channel dropdown (ItemsData = channel number)
        RAWList              % xRAW channels, multi-select (ItemsData = channel numbers)
        SelectAllBtn
        SelectNoneBtn
        PlotRAWBtn
        ProcessLFPBtn
        ProcessMUABtn
        SaveLFPBtn
        SaveMUABtn
        FsLabel              % Summary of processed LFP / MUA (rate, channels, saved)
        PlotCard             % Card around the plot area (title = what is shown)
        AxContainer          % Panel holding the tiledlayout of plots

        LastProcessedLFP
        LastLFPfs
        LastLFPChannels      % RAW channels used for LastProcessedLFP (snapshot)
        LastLFPStimChannel   % Whis channel selected when LFP was processed
        LastMUAFilterParams
        LastProcessedMUA
        LastMUAfs
        LastMUAChannels      % RAW channels used for LastProcessedMUA (snapshot)
        LastMUAStimChannel   % Whis channel selected when MUA was processed

        Data  % Struct loaded from TDTbin2mat
        StimChannel  % Selected Whis channel
        RAWChannels  % Selected xRAW channels
        TankName = ''        % Folder name of the loaded tank (default file names)
        LFPSaved = false     % LastProcessedLFP written to disk
        MUASaved = false     % LastProcessedMUA written to disk
    end

    methods
        %% Constructor - Build UI; data loaded via Load TDT tank
        function app = ExtractEphysApp()
            app.buildUI();
        end

        %% buildUI - UIKit window: step cards (left) | plot card (right)
        function buildUI(app)
            T = UITheme;
            W = UIKit.window('Extract Ephys Data', 'Load a TDT tank, extract LFP and MUA', ...
                'Ephys Extract', [1200 800]);
            app.UIFig = W.Fig;
            app.StatusLabel = W.Status;
            W.Body.ColumnWidth = {300, '1x'};
            W.Body.RowHeight = {'1x'};

            left = uigridlayout(W.Body, [4 1], 'RowHeight', {136 + T.buttonHeight + 6, '1x', 116, 124}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            bh = T.buttonHeight;

            % --- 1 Load TDT tank ---
            g = cardGrid(left, {22, bh, bh, '1x'});
            UIKit.step(g, 1, 'Load TDT tank');
            app.LoadBtn = UIKit.button(g, 'Load TDT tank…', @(~,~)app.loadTDT(), 'primary', ...
                'Choose a TDT tank/block folder (needs Whis and xRAW streams)');
            app.DemoBtn = UIKit.button(g, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Load a synthetic 30 s tank with known answers: 8 RAW channels 100 µm apart, ' ...
                '15 whisker stimuli (every 2 s), an evoked potential with its sink at channel 4 ' ...
                'and three units near channels 4-5']);
            app.TankInfoLabel = infoLabel(g, 'No tank loaded');

            % --- 2 Choose channels ---
            g = cardGrid(left, {22, T.controlHeight, 26, '1x'});
            UIKit.step(g, 2, 'Choose channels');
            sg = uigridlayout(g, [1 2], 'ColumnWidth', {'1x', 100}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
            app.WhisChannelMenu = UIKit.field(sg, 'Stimulus channel (Whis)', 'dropdown', ...
                {{'—'}, '—'}, 'Whis stream channel carrying the stimulus (saved with LFP/MUA)');
            app.WhisChannelMenu.ValueChangedFcn = @(~,~)app.updateControls();
            sg = uigridlayout(g, [1 3], 'ColumnWidth', {'1x', 48, 52}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            uilabel(sg, 'Text', 'RAW channels', 'FontSize', T.fontBody, ...
                'FontColor', T.sectionTitleColor, ...
                'Tooltip', 'Ctrl/Shift-click in the list to select several channels');
            app.SelectAllBtn = UIKit.button(sg, 'All', @(~,~)app.selectChannels(true), 'secondary', ...
                'Select every RAW channel');
            app.SelectNoneBtn = UIKit.button(sg, 'None', @(~,~)app.selectChannels(false), 'secondary', ...
                'Clear the RAW channel selection');
            app.RAWList = uilistbox(g, 'Items', {}, 'Multiselect', 'on', ...
                'Tooltip', 'xRAW channels to plot and process. Ctrl/Shift-click to select several.', ...
                'ValueChangedFcn', @(~,~)app.onChannelsChanged());

            % --- 3 Process ---
            g = cardGrid(left, {22, bh, bh}, 2);
            lbl = UIKit.step(g, 3, 'Process');
            lbl.Layout.Column = [1 2];
            app.ProcessLFPBtn = UIKit.button(g, 'Process LFP…', @(~,~)app.processLFPData(), 'secondary', ...
                'Lowpass / notch / downsample the selected channels into LFP');
            app.ProcessMUABtn = UIKit.button(g, 'Process MUA…', @(~,~)app.processMUAData(), 'secondary', ...
                'Bandpass the selected channels into multi-unit activity');
            app.PlotRAWBtn = UIKit.button(g, 'Plot RAW', @(~,~)app.plotRAWData(), 'secondary', ...
                'Plot the stimulus and the selected RAW channels (no filtering)');
            app.PlotRAWBtn.Layout.Column = [1 2];

            % --- 4 Save ---
            g = cardGrid(left, {22, bh, '1x'}, 2);
            lbl = UIKit.step(g, 4, 'Save');
            lbl.Layout.Column = [1 2];
            app.SaveLFPBtn = UIKit.button(g, 'Save LFP…', @(~,~)app.saveLFPData(), 'secondary', ...
                'Save the processed LFP (+ stimulus) as .mat for LFP Analysis');
            app.SaveMUABtn = UIKit.button(g, 'Save MUA…', @(~,~)app.saveMUAData(), 'secondary', ...
                'Save the processed MUA (+ stimulus, filter settings) as .mat for MUA Analysis');
            app.FsLabel = infoLabel(g, '');
            app.FsLabel.Layout.Column = [1 2];

            % --- Plots ---
            app.PlotCard = UIKit.card(W.Body, 'Signals');
            app.PlotCard.Layout.Row = 1; app.PlotCard.Layout.Column = 2;
            pg = uigridlayout(app.PlotCard, [1 1], 'Padding', [8 8 8 8], 'BackgroundColor', T.cardBg);
            app.AxContainer = uipanel(pg, 'BorderType', 'none', 'BackgroundColor', T.cardBg);
            app.showPlaceholder('Signals', 'Load a TDT tank (or Try demo data) to begin');

            app.updateControls();
        end

        %% updateControls - Enable state and primary (next) action from data state
        function updateControls(app)
            hasData = ~isempty(app.Data);
            hasSel = hasData && ~isempty(app.RAWList.Value);
            hasLFP = ~isempty(app.LastProcessedLFP);
            hasMUA = ~isempty(app.LastProcessedMUA);

            setEnable({app.WhisChannelMenu, app.RAWList, app.SelectAllBtn, app.SelectNoneBtn}, hasData);
            setEnable({app.PlotRAWBtn, app.ProcessLFPBtn, app.ProcessMUABtn}, hasSel);
            app.SaveLFPBtn.Enable = onOff(hasLFP);
            app.SaveMUABtn.Enable = onOff(hasMUA);

            % Recommended next action: load -> process LFP -> save LFP -> process MUA -> save MUA
            if ~hasData
                next = app.LoadBtn;
            elseif hasLFP && ~app.LFPSaved
                next = app.SaveLFPBtn;
            elseif hasMUA && ~app.MUASaved
                next = app.SaveMUABtn;
            elseif ~hasLFP
                next = app.ProcessLFPBtn;
            elseif ~hasMUA
                next = app.ProcessMUABtn;
            else
                next = [];
            end
            btns = [app.LoadBtn, app.PlotRAWBtn, app.ProcessLFPBtn, app.ProcessMUABtn, ...
                app.SaveLFPBtn, app.SaveMUABtn];
            for b = btns
                setButtonStyle(b, isequal(b, next));
            end

            % Processed-results summary under the Save buttons
            parts = {};
            if hasLFP
                parts{end+1} = sprintf('LFP: %d ch at %.2f Hz%s', numel(app.LastLFPChannels), ...
                    app.LastLFPfs, ifelse(app.LFPSaved, '  (saved)', ''));
            end
            if hasMUA
                parts{end+1} = sprintf('MUA: %d ch at %.2f Hz%s', numel(app.LastMUAChannels), ...
                    app.LastMUAfs, ifelse(app.MUASaved, '  (saved)', ''));
            end
            if isempty(parts), parts = {'Nothing processed yet'}; end
            app.FsLabel.Text = strjoin(parts, newline);
        end

%% ------------------------------------------------------------------------------------------
        %% loadTDT - Pick a tank folder, then openTank(folder)
        function loadTDT(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir) || ~isfolder(startDir), startDir = pwd; end
            folder = uigetdir(startDir, 'Select TDT Tank Folder');
            figure(app.UIFig);
            if isequal(folder, 0)
                UIKit.setStatus(app.StatusLabel, 'Load cancelled.', 'info');
                return;
            end
            app.openTank(folder);
        end

        %% openTank - Load a tank folder (no dialog), check streams, fill channel lists
        % A demo tank (DemoData.isDemoTank) is read with DemoData.loadTank,
        % anything else with TDTbin2mat. Returns true on success; on failure
        % the previously loaded tank is kept.
        function ok = openTank(app, folder)
            ok = false;
            [~, tankName] = fileparts(folder);

            UIKit.setStatus(app.StatusLabel, sprintf('Loading %s…', tankName), 'busy');
            dlg = UIKit.busy(app.UIFig, sprintf('Loading TDT tank %s… this can take a minute.', tankName));
            try
                if DemoData.isDemoTank(folder)
                    data = DemoData.loadTank(folder);   % TDTbin2mat stand-in
                else
                    % Resolve SDK relative to the toolbox root (apps/..), not pwd
                    rootDir = fileparts(fileparts(mfilename('fullpath')));
                    addpath(genpath(fullfile(rootDir, 'Utilities', 'TDTMatlabSDK')));
                    data = TDTbin2mat(folder);
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load %s: %s', tankName, ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf(['Could not load the TDT tank:\n%s\n\n' ...
                    'Check that you selected a tank/block folder.'], ME.message), 'Load Failed');
                return;
            end
            UIKit.done(dlg);

            % Require the Whis (stimulus) and xRAW streams used below
            if ~isfield(data, 'streams') || ~isfield(data.streams, 'Whis') || ~isfield(data.streams, 'xRAW')
                UIKit.setStatus(app.StatusLabel, 'Tank has no Whis and/or xRAW stream.', 'error');
                UIKit.alert(app.UIFig, ['The selected tank does not contain the required Whis and xRAW ' ...
                    'streams. Choose a block recorded with the stimulus (Whis) and raw (xRAW) stores.'], ...
                    'Invalid TDT Data');
                return;
            end
            app.Data = data;
            app.TankName = tankName;
            % Drop results from a previously loaded tank
            app.LastProcessedLFP = [];
            app.LastProcessedMUA = [];
            app.LFPSaved = false;
            app.MUASaved = false;

            % Populate channel lists from the actual number of channels
            nStim = size(data.streams.Whis.data, 1);
            nRaw  = size(data.streams.xRAW.data, 1);
            app.WhisChannelMenu.ItemsData = [];
            app.RAWList.ItemsData = [];
            app.WhisChannelMenu.Items = arrayfun(@(c) sprintf('Ch %d', c), 1:nStim, 'UniformOutput', false);
            app.WhisChannelMenu.ItemsData = 1:nStim;
            app.WhisChannelMenu.Value = 1;
            app.RAWList.Items = arrayfun(@(c) sprintf('Ch %d', c), 1:nRaw, 'UniformOutput', false);
            app.RAWList.ItemsData = 1:nRaw;
            app.RAWList.Value = 1:min(4, nRaw);

            rawFs = data.streams.xRAW.fs;
            durS = size(data.streams.xRAW.data, 2) / rawFs;
            app.TankInfoLabel.Text = sprintf('%s\nRAW %.2f Hz · stim %.2f Hz · %s\n%d RAW ch · %d stim ch', ...
                tankName, rawFs, data.streams.Whis.fs, fmtDuration(durS), nRaw, nStim);
            app.TankInfoLabel.Tooltip = folder;

            app.showPlaceholder('Signals', 'Tank loaded. Choose channels, then Plot RAW or Process LFP / MUA.');
            app.updateControls();
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf('Loaded %s (%d RAW channels, %.2f Hz, %s).', ...
                tankName, nRaw, rawFs, fmtDuration(durS)), 'success');
        end

        %% loadDemo - Load DemoData's synthetic tank and select every channel
        % 30 s; 8 RAW channels (100 um apart) at 24414 Hz; Whis ch 1 carries
        % 20 ms pulses every 2 s from 1 s. Selects stim channel 1 and RAW
        % channels 1-8 so Plot RAW / Process LFP / Process MUA just work.
        function loadDemo(app)
            dlg = UIKit.busy(app.UIFig, 'Preparing demo data (first time only takes a few seconds)…');
            try
                folder = DemoData.file('tdtTank');
                UIKit.done(dlg);
                if ~app.openTank(folder), return; end
                nRaw = size(app.Data.streams.xRAW.data, 1);
                app.setChannels(1, 1:nRaw);
                nStim = numel(app.Data.truth.onsets);
                UIKit.setStatus(app.StatusLabel, sprintf(['Demo loaded: %.0f s tank, %d RAW channels 100 µm apart, ' ...
                    '%d stimuli (20 ms, every 2 s) on Whis ch 1. All channels selected. ' ...
                    'Next: Process LFP (evoked sink at ch 4) or Process MUA (units near ch 4-5).'], ...
                    app.Data.truth.duration, nRaw, nStim), 'success');
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load the demo data: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not load the demo data:\n%s', ME.message), 'Demo data');
            end
        end

        %% setChannels - Select stimulus (Whis) and RAW channels programmatically
        % stimCh: Whis channel number ([] = keep); rawChs: xRAW channel
        % numbers (channels not in the tank are ignored).
        function setChannels(app, stimCh, rawChs)
            if isempty(app.Data), return; end
            if ~isempty(stimCh) && ismember(stimCh, app.WhisChannelMenu.ItemsData)
                app.WhisChannelMenu.Value = stimCh;
            end
            if nargin >= 3
                rawChs = rawChs(ismember(rawChs, app.RAWList.ItemsData));
                app.RAWList.Value = rawChs(:)';
            end
            app.onChannelsChanged();
        end

        %% onChannelsChanged - Selection changed: refresh enable state and status
        function onChannelsChanged(app)
            app.updateControls();
            n = numel(app.RAWList.Value);
            if n == 0
                UIKit.setStatus(app.StatusLabel, 'Select at least one RAW channel.', 'warning');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('%d RAW channel(s) selected.', n), 'info');
            end
        end

        %% selectChannels - All / None buttons
        function selectChannels(app, selectAll)
            if isempty(app.Data), return; end
            if selectAll
                app.RAWList.Value = app.RAWList.ItemsData;
            else
                app.RAWList.Value = [];
            end
            app.onChannelsChanged();
        end

        %% readSelection - Copy the UI selection into StimChannel / RAWChannels
        function ok = readSelection(app)
            ok = false;
            if isempty(app.Data)
                UIKit.alert(app.UIFig, 'Load a TDT tank first.', 'No Data');
                return;
            end
            app.StimChannel = app.WhisChannelMenu.Value;
            app.RAWChannels = app.RAWList.Value;
            if isempty(app.RAWChannels)
                UIKit.alert(app.UIFig, 'Select at least one RAW channel in step 2.', 'No Channels');
                return;
            end
            app.RAWChannels = app.RAWChannels(:)';
            ok = true;
        end

%% ------------------------------------------------------------------------------------------
        %% plotRAWData - Plot stimulus and the selected RAW channels
        function plotRAWData(app)
            if ~app.readSelection(), return; end
            T = UITheme;
            UIKit.setStatus(app.StatusLabel, 'Plotting RAW channels…', 'busy');
            dlg = UIKit.busy(app.UIFig, 'Plotting RAW channels…');
            try
                raw = double(app.Data.streams.xRAW.data(app.RAWChannels, :));
                raw_fs = app.Data.streams.xRAW.fs;
                t_raw = (0:size(raw,2)-1)/raw_fs;
                layer = struct('data', {num2cell(raw, 2)'}, 'color', T.plotColors(1,:), ...
                    'width', 0.5, 'name', 'RAW', 'center', true);
                app.drawChannels(sprintf('RAW signals (%.2f Hz)', raw_fs), t_raw, layer, ...
                    app.RAWChannels, 'RAW', app.StimChannel);
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Plotted %d RAW channel(s).', ...
                    numel(app.RAWChannels)), 'success');
            catch ME
                UIKit.done(dlg);
                app.fail('Plot RAW failed', ME);
            end
        end

%% ------------------------------------------------------------------------------------------
        %% processLFPData - Anti-alias + downsample, lowpass, notch; plot and keep for saving
        % Without params the LFPProcessingParamsApp dialog asks for them.
        % params (skips the dialog): lowCutoff (Hz, NaN = no lowpass),
        % notch60 (logical), downsample (logical), downsampleRate (Hz);
        % missing fields default to 300 Hz, false, true, 1000 Hz.
        function processLFPData(app, params)
            if ~app.readSelection(), return; end
            T = UITheme;

            if nargin < 2 || isempty(params)
                % Launch parameter window
                paramsApp = LFPProcessingParamsApp();
                uiwait(paramsApp.UIFig);  % Wait for user input
                params = paramsApp.Params;
                if isempty(params)
                    UIKit.setStatus(app.StatusLabel, 'LFP processing cancelled.', 'info');
                    return;  % User cancelled
                end
            else
                params = withDefaults(params, struct('lowCutoff', 300, 'notch60', false, ...
                    'downsample', true, 'downsampleRate', 1000));
            end

            raw_fs = app.Data.streams.xRAW.fs;
            fs = raw_fs;
            if params.downsample
                target_fs = params.downsampleRate;
                if target_fs >= fs
                    msg = sprintf('Downsample rate (%.1f Hz) must be below the raw rate (%.1f Hz).', ...
                        target_fs, fs);
                    UIKit.setStatus(app.StatusLabel, msg, 'error');
                    UIKit.alert(app.UIFig, msg, 'Invalid Downsample Rate');
                    return;
                end
            end

            nCh = length(app.RAWChannels);
            UIKit.setStatus(app.StatusLabel, sprintf('Processing LFP on %d channel(s)…', nCh), 'busy');
            dlg = UIKit.busy(app.UIFig, sprintf('Filtering %d channel(s) for LFP…', nCh));
            try
                raw = double(app.Data.streams.xRAW.data(app.RAWChannels,:));
                processed = cell(1, nCh);

                % === 1. Anti-aliasing + Downsample if requested ===
                if params.downsample
                    % Integer factor; the actual rate is fs/dsFactor (e.g. TDT's
                    % 24414.0625 Hz is not an integer multiple of the target)
                    dsFactor = max(1, round(fs / params.downsampleRate));
                    new_fs = fs / dsFactor;
                    aa_cutoff = 0.8 * new_fs / 2;  % anti-alias cutoff
                    [b_aa, a_aa] = butter(4, aa_cutoff / (fs / 2), 'low');
                    for i = 1:nCh
                        filtered = filtfilt(b_aa, a_aa, raw(i,:));
                        processed{i} = downsample(filtered, dsFactor);
                    end
                    fs = new_fs;  % update sampling rate (actual, not requested)
                else
                    for i = 1:nCh
                        processed{i} = raw(i,:);
                    end
                end

                % === 2. Apply lowpass filter ===
                if ~isnan(params.lowCutoff) && params.lowCutoff > 0 && params.lowCutoff < fs/2
                    [b_lp, a_lp] = butter(4, params.lowCutoff / (fs/2), 'low');
                    for i = 1:length(processed)
                        processed{i} = filtfilt(b_lp, a_lp, processed{i});
                    end
                end

                % === 3. Apply 60 Hz Notch filter if requested ===
                if params.notch60
                    wo = 60/(fs/2);
                    bw = wo/35;
                    [b_notch, a_notch] = iirnotch(wo, bw);
                    for i = 1:length(processed)
                        processed{i} = filtfilt(b_notch, a_notch, processed{i});
                    end
                end

                % === 4. Plot LFP data ===
                t = (0:length(processed{1})-1)/fs;
                layer = struct('data', {processed}, 'color', T.plotColors(1,:), ...
                    'width', 0.75, 'name', 'LFP', 'center', true);
                app.drawChannels(sprintf('Processed LFP (%.2f Hz)', fs), t, layer, ...
                    app.RAWChannels, 'LFP', app.StimChannel);
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                app.fail('LFP processing failed', ME);
                return;
            end

            app.LastProcessedLFP = processed;
            app.LastLFPfs = fs;
            app.LastLFPChannels = app.RAWChannels;
            app.LastLFPStimChannel = app.StimChannel;
            app.LFPSaved = false;
            app.updateControls();

            msg = sprintf('LFP processed: %d channel(s) at %.2f Hz (raw %.2f Hz).', nCh, fs, raw_fs);
            if ~isnan(params.lowCutoff) && params.lowCutoff >= fs/2
                UIKit.setStatus(app.StatusLabel, sprintf('%s Lowpass skipped: %.1f Hz is not below Nyquist (%.1f Hz).', ...
                    msg, params.lowCutoff, fs/2), 'warning');
            else
                UIKit.setStatus(app.StatusLabel, [msg ' Next: Save LFP.'], 'success');
            end
        end

%% ------------------------------------------------------------------------------------------
        %% saveLFPData - Pick channels to save and write the LFP .mat
        % processedLFP: cell array of processed data (1 x Nch); fsLFP: rate after
        % filtering/downsampling. Both default to the last processed LFP.
        function saveLFPData(app, processedLFP, fsLFP)
            if nargin < 2, processedLFP = app.LastProcessedLFP; end
            if nargin < 3, fsLFP = app.LastLFPfs; end
            if isempty(processedLFP)
                UIKit.alert(app.UIFig, 'No processed LFP data available. Run Process LFP first.', 'Save LFP');
                return;
            end

            % Use the channels snapshotted at process time (UI selection may have changed)
            lfpChannels = app.LastLFPChannels;
            chLabels = arrayfun(@(c) sprintf('Ch %d', c), lfpChannels, 'UniformOutput', false);
            selection = chooseChannels(chLabels, 'Save LFP', 'Select the LFP channels to save', 'Ephys Extract');
            figure(app.UIFig);
            if isempty(selection)
                UIKit.setStatus(app.StatusLabel, 'Save LFP cancelled.', 'info');
                return;  % User cancelled
            end

            % Save dialog
            [file, path] = uiputfile('*.mat', 'Save LFP Data As', app.defaultSavePath('LFP'));
            figure(app.UIFig);
            if isequal(file, 0)
                UIKit.setStatus(app.StatusLabel, 'Save LFP cancelled.', 'info');
                return;
            end
            app.writeLFP(processedLFP, fsLFP, selection, fullfile(path, file));
        end

        %% saveLFPTo - Save the last processed LFP to filePath without dialogs
        % selection: indices into the processed channels (default: all).
        % Returns true on success.
        function ok = saveLFPTo(app, filePath, selection)
            ok = false;
            if isempty(app.LastProcessedLFP)
                UIKit.alert(app.UIFig, 'No processed LFP data available. Run Process LFP first.', 'Save LFP');
                return;
            end
            if nargin < 3 || isempty(selection), selection = 1:numel(app.LastProcessedLFP); end
            ok = app.writeLFP(app.LastProcessedLFP, app.LastLFPfs, selection, filePath);
        end

%% ------------------------------------------------------------------------------------------
        %% processMUAData - Bandpass selected channels; smoothing for display envelope only
        % Without params the MUAProcessingParamsApp dialog asks for them.
        % params (skips the dialog): filterType ('Butterworth' |
        % 'Chebyshev I'), order, lowCutoff, highCutoff (Hz), smoothMs,
        % autoSmooth, overlayRaw; missing fields default to Butterworth,
        % 4, 300, 3000, 2, true, false.
        function processMUAData(app, params)
            if ~app.readSelection(), return; end
            T = UITheme;

            if nargin < 2 || isempty(params)
                paramApp = MUAProcessingParamsApp();
                uiwait(paramApp.UIFig);
                params = paramApp.Params;
                if isempty(params)
                    UIKit.setStatus(app.StatusLabel, 'MUA processing cancelled.', 'info');
                    return;
                end
            else
                params = withDefaults(params, struct('filterType', 'Butterworth', 'order', 4, ...
                    'lowCutoff', 300, 'highCutoff', 3000, 'smoothMs', 2, 'autoSmooth', true, ...
                    'overlayRaw', false));
            end

            fs = app.Data.streams.xRAW.fs;
            if params.highCutoff >= fs/2
                msg = sprintf('High cutoff (%.0f Hz) must be below half the raw rate (%.1f Hz).', ...
                    params.highCutoff, fs/2);
                UIKit.setStatus(app.StatusLabel, msg, 'error');
                UIKit.alert(app.UIFig, msg, 'Invalid MUA Filter');
                return;
            end

            Wn = [params.lowCutoff params.highCutoff] / (fs/2);
            switch params.filterType
                case 'Butterworth'
                    [b, a] = butter(params.order, Wn, 'bandpass');
                case 'Chebyshev I'
                    Rp = 0.5;
                    [b, a] = cheby1(params.order, Rp, Wn, 'bandpass');
                otherwise
                    UIKit.alert(app.UIFig, 'Unsupported filter type.', 'Invalid MUA Filter');
                    return;
            end

            smooth_ms = params.smoothMs;
            if params.autoSmooth
                smooth_ms = 2;
            end
            window = max(1, round((smooth_ms / 1000) * fs));
            kernel = ones(1, window) / window;

            nCh = length(app.RAWChannels);
            UIKit.setStatus(app.StatusLabel, sprintf('Processing MUA on %d channel(s)…', nCh), 'busy');
            dlg = UIKit.busy(app.UIFig, sprintf('Bandpass filtering %d channel(s) for MUA…', nCh));
            try
                processed = cell(1, nCh);
                envelope = cell(1, nCh);
                rawAll = cell(1, nCh);
                for i = 1:nCh
                    raw = double(app.Data.streams.xRAW.data(app.RAWChannels(i), :));
                    rawAll{i} = raw;
                    bandpassed = filtfilt(b, a, raw);
                    % Saved/processed signal stays bandpassed and UNSMOOTHED:
                    % MUAAnalysisApp thresholds and aligns spike waveforms on it.
                    % (A boxcar on the unrectified 300-3000 Hz band nearly nulls it.)
                    processed{i} = bandpassed;
                    % Smoothing is display-only: rectify first to get an MUA envelope
                    envelope{i} = conv(abs(bandpassed), kernel, 'same');
                end
                params.savedSignal = 'bandpassed (unsmoothed); smoothing used for display envelope only';

                % Plot layers: optional raw (gray), bandpassed MUA, rectified envelope
                t = (0:length(processed{1})-1)/fs;
                layers = struct('data', {}, 'color', {}, 'width', {}, 'name', {}, 'center', {});
                if params.overlayRaw
                    layers(end+1) = struct('data', {rawAll}, 'color', T.plotColors(7,:), ...
                        'width', 0.5, 'name', 'Raw', 'center', true);
                end
                layers(end+1) = struct('data', {processed}, 'color', T.plotColors(1,:), ...
                    'width', 0.75, 'name', 'MUA (bandpassed)', 'center', true);
                if window > 1
                    layers(end+1) = struct('data', {envelope}, 'color', T.plotColors(2,:), ...
                        'width', 1, 'name', sprintf('Envelope (%.3g ms)', smooth_ms), 'center', false);
                end
                app.drawChannels(sprintf('Processed MUA (%.0f–%.0f Hz, %s)', params.lowCutoff, ...
                    params.highCutoff, params.filterType), t, layers, app.RAWChannels, 'MUA', app.StimChannel);
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                app.fail('MUA processing failed', ME);
                return;
            end

            app.LastProcessedMUA = processed;
            app.LastMUAfs = fs;
            app.LastMUAFilterParams = params;
            app.LastMUAChannels = app.RAWChannels;
            app.LastMUAStimChannel = app.StimChannel;
            app.MUASaved = false;
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf(['MUA processed: %d channel(s), %.0f–%.0f Hz %s. ' ...
                'Next: Save MUA.'], nCh, params.lowCutoff, params.highCutoff, params.filterType), 'success');
        end

%% ------------------------------------------------------------------------------------------
        %% saveMUAData - Pick channels to save and write the MUA .mat (+ filterParams)
        function saveMUAData(app, processedMUA, fsMUA, filterParams)
            if nargin < 2, processedMUA = app.LastProcessedMUA; end
            if nargin < 3, fsMUA = app.LastMUAfs; end
            if nargin < 4, filterParams = app.LastMUAFilterParams; end %#ok<NASGU> saved below
            if isempty(processedMUA)
                UIKit.alert(app.UIFig, 'No processed MUA data available. Run Process MUA first.', 'Save MUA');
                return;
            end

            % Use the channels snapshotted at process time (UI selection may have changed)
            muaChannels = app.LastMUAChannels;
            chLabels = arrayfun(@(c) sprintf('Ch %d', c), muaChannels, 'UniformOutput', false);
            selection = chooseChannels(chLabels, 'Save MUA', 'Select the MUA channels to save', 'Ephys Extract');
            figure(app.UIFig);
            if isempty(selection)
                UIKit.setStatus(app.StatusLabel, 'Save MUA cancelled.', 'info');
                return;
            end

            [file, path] = uiputfile('*.mat', 'Save MUA Data As', app.defaultSavePath('MUA'));
            figure(app.UIFig);
            if isequal(file, 0)
                UIKit.setStatus(app.StatusLabel, 'Save MUA cancelled.', 'info');
                return;
            end
            app.writeMUA(processedMUA, fsMUA, filterParams, selection, fullfile(path, file));
        end

        %% saveMUATo - Save the last processed MUA to filePath without dialogs
        % selection: indices into the processed channels (default: all).
        % Returns true on success.
        function ok = saveMUATo(app, filePath, selection)
            ok = false;
            if isempty(app.LastProcessedMUA)
                UIKit.alert(app.UIFig, 'No processed MUA data available. Run Process MUA first.', 'Save MUA');
                return;
            end
            if nargin < 3 || isempty(selection), selection = 1:numel(app.LastProcessedMUA); end
            ok = app.writeMUA(app.LastProcessedMUA, app.LastMUAfs, app.LastMUAFilterParams, ...
                selection, filePath);
        end
    end

    methods (Access = private)
        %% writeLFP - Write the selected LFP channels (+ stimulus) to filePath
        function ok = writeLFP(app, processedLFP, fsLFP, selection, filePath)
            ok = false;
            lfp_data = cell2mat(processedLFP(selection)');
            lfp_channels = app.LastLFPChannels(selection);
            lfp_fs = fsLFP;
            t_lfp = (0:size(lfp_data,2)-1)/lfp_fs; %#ok<NASGU>

            stim_data = app.Data.streams.Whis.data(app.LastLFPStimChannel, :);
            stim_fs = app.Data.streams.Whis.fs;
            t_stim = (0:length(stim_data)-1)/stim_fs; %#ok<NASGU>

            [~, name, ext] = fileparts(filePath);
            file = [name ext];
            UIKit.setStatus(app.StatusLabel, sprintf('Saving %s…', file), 'busy');
            try
                save(filePath, ...
                    'lfp_data', 'lfp_channels', 'lfp_fs', 't_lfp', ...
                    'stim_data', 'stim_fs', 't_stim');
            catch ME
                app.fail('Save LFP failed', ME);
                return;
            end
            ok = true;
            app.LFPSaved = true;
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf('Saved LFP (%d channel(s), %.2f Hz) to %s.', ...
                numel(lfp_channels), lfp_fs, file), 'success');
        end

        %% writeMUA - Write the selected MUA channels (+ stimulus, filterParams) to filePath
        function ok = writeMUA(app, processedMUA, fsMUA, filterParams, selection, filePath) %#ok<INUSD> saved below
            ok = false;
            mua_data = cell2mat(processedMUA(selection)');
            mua_channels = app.LastMUAChannels(selection);
            mua_fs = fsMUA;
            t_mua = (0:size(mua_data,2)-1)/mua_fs; %#ok<NASGU>

            stim_data = app.Data.streams.Whis.data(app.LastMUAStimChannel, :);
            stim_fs = app.Data.streams.Whis.fs;
            t_stim = (0:length(stim_data)-1)/stim_fs; %#ok<NASGU>

            [~, name, ext] = fileparts(filePath);
            file = [name ext];
            UIKit.setStatus(app.StatusLabel, sprintf('Saving %s…', file), 'busy');
            try
                save(filePath, ...
                    'mua_data', 'mua_channels', 'mua_fs', 't_mua', ...
                    'stim_data', 'stim_fs', 't_stim', 'filterParams');
            catch ME
                app.fail('Save MUA failed', ME);
                return;
            end
            ok = true;
            app.MUASaved = true;
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf('Saved MUA data and filter settings (%d channel(s)) to %s.', ...
                numel(mua_channels), file), 'success');
        end

        %% drawChannels - Stimulus tile on top, then the channels
        % layers: struct array (data = 1xN cell of row vectors, color, width,
        % name, center). <= 4 channels: one tile each; more: stacked offset
        % traces in one axes with channel tick labels. X axes are linked.
        function drawChannels(app, cardTitle, t, layers, chans, prefix, stimCh)
            T = UITheme;
            delete(app.AxContainer.Children);
            app.PlotCard.Title = cardTitle;
            nCh = numel(chans);

            stim = app.Data.streams.Whis.data(stimCh, :);
            t_stim = (0:length(stim)-1) / app.Data.streams.Whis.fs;

            if nCh <= 4
                tl = tiledlayout(app.AxContainer, nCh + 1, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
            else
                tl = tiledlayout(app.AxContainer, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
            end
            axStim = nexttile(tl);
            plot(axStim, t_stim, stim, 'Color', T.stimColor);
            UIKit.styleAxes(axStim, sprintf('Stimulus (Whis Ch %d)', stimCh), '', 'Stim');
            axStim.XTickLabel = [];
            axList = axStim;

            if nCh <= 4
                for i = 1:nCh
                    ax = nexttile(tl);
                    hold(ax, 'on');
                    h = gobjects(1, numel(layers));
                    for L = 1:numel(layers)
                        y = layers(L).data{i};
                        if layers(L).center, y = y - mean(y); end
                        h(L) = plot(ax, t, y, 'Color', layers(L).color, ...
                            'LineWidth', layers(L).width, 'DisplayName', layers(L).name);
                    end
                    hold(ax, 'off');
                    if i == nCh
                        UIKit.styleAxes(ax, '', 'Time (s)', sprintf('%s Ch %d', prefix, chans(i)));
                    else
                        UIKit.styleAxes(ax, '', '', sprintf('%s Ch %d', prefix, chans(i)));
                        ax.XTickLabel = [];
                    end
                    if i == 1 && numel(layers) > 1
                        lg = legend(ax, h); lg.Location = 'northeast'; lg.Box = 'off';
                    end
                    axList(end+1) = ax; %#ok<AGROW>
                end
            else
                ax = nexttile(tl, [3 1]);
                % One spacing for all channels so relative amplitudes stay comparable
                sd = 0;
                for L = 1:numel(layers)
                    for i = 1:nCh
                        sd = max(sd, std(double(layers(L).data{i})));
                    end
                end
                spacing = 8 * sd;
                if ~(spacing > 0), spacing = 1; end
                offsets = (nCh-1:-1:0) * spacing;   % first channel on top
                hold(ax, 'on');
                h = gobjects(1, numel(layers));
                for i = 1:nCh
                    for L = 1:numel(layers)
                        y = layers(L).data{i};
                        if layers(L).center, y = y - mean(y); end
                        hl = plot(ax, t, y + offsets(i), 'Color', layers(L).color, ...
                            'LineWidth', layers(L).width, 'DisplayName', layers(L).name);
                        if i == 1, h(L) = hl; end
                    end
                end
                hold(ax, 'off');
                UIKit.styleAxes(ax, sprintf('%d channels, offset %.3g per channel', nCh, spacing), ...
                    'Time (s)', '');
                [ticks, order] = sort(offsets);
                ax.YTick = ticks;
                ax.YTickLabel = arrayfun(@(c) sprintf('%s Ch %d', prefix, c), chans(order), ...
                    'UniformOutput', false);
                ax.YLim = [-spacing, offsets(1) + spacing];
                if numel(layers) > 1
                    lg = legend(ax, h); lg.Location = 'northeast'; lg.Box = 'off';
                end
                axList(end+1) = ax;
            end
            linkaxes(axList, 'x');
            tMax = max([t(end), t_stim(end)]);
            if tMax > 0, xlim(axStim, [0 tMax]); end
        end

        %% showPlaceholder - Single empty axes with a hint message
        function showPlaceholder(app, cardTitle, msg)
            delete(app.AxContainer.Children);
            app.PlotCard.Title = cardTitle;
            tl = tiledlayout(app.AxContainer, 1, 1, 'Padding', 'compact');
            ax = nexttile(tl);
            UIKit.emptyAxes(ax, msg);
        end

        %% defaultSavePath - <export dir>/<tank>_<kind>.mat
        function p = defaultSavePath(app, kind)
            d = ProjectManager.getExportDir();
            if isempty(d) || ~isfolder(d), d = pwd; end
            name = app.TankName;
            if isempty(name), name = 'ephys'; end
            p = fullfile(d, sprintf('%s_%s.mat', name, kind));
        end

        %% fail - Report an error in the status bar and as an in-window alert
        function fail(app, what, ME)
            UIKit.setStatus(app.StatusLabel, sprintf('%s: %s', what, ME.message), 'error');
            UIKit.alert(app.UIFig, sprintf('%s:\n%s', what, ME.message), what);
        end
    end
end

%% Local helper: white card with a padded grid (one step per card)
function g = cardGrid(parent, rowHeights, nCols)
    T = UITheme;
    if nargin < 3, nCols = 1; end
    c = UIKit.card(parent, '');
    g = uigridlayout(c, [numel(rowHeights) nCols], 'RowHeight', rowHeights, ...
        'ColumnWidth', repmat({'1x'}, 1, nCols), 'Padding', [10 8 10 10], ...
        'RowSpacing', 6, 'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
end

%% Local helper: fill fields missing from params with defaults
function params = withDefaults(params, defaults)
    f = fieldnames(defaults);
    for k = 1:numel(f)
        if ~isfield(params, f{k}), params.(f{k}) = defaults.(f{k}); end
    end
end

%% Local helper: set Enable on a cell array of components
function setEnable(ctrls, tf)
    for k = 1:numel(ctrls)
        ctrls{k}.Enable = onOff(tf);
    end
end

%% Local helper: small wrapped info text inside a card
function lbl = infoLabel(parent, text)
    T = UITheme;
    lbl = uilabel(parent, 'Text', text, 'FontSize', T.fontSmall, 'FontColor', T.bodyColor, ...
        'WordWrap', 'on', 'VerticalAlignment', 'top', 'Interpreter', 'none');
end

%% Local helper: restyle an existing button as primary / secondary
% (UIKit.button only styles at creation; the "next step" moves as data changes)
function setButtonStyle(b, isPrimary)
    T = UITheme;
    if isPrimary
        b.BackgroundColor = T.accent;      b.FontColor = [1 1 1]; b.FontWeight = 'bold';
    else
        b.BackgroundColor = T.secondaryBg; b.FontColor = T.secondaryFg; b.FontWeight = 'normal';
    end
end

%% Local helper: modal channel picker (uifigure replacement for listdlg)
% Returns the selected indices into labels, or [] when cancelled.
function sel = chooseChannels(labels, titleText, subtitle, helpTopic)
    T = UITheme;
    D = UIKit.dialog(titleText, subtitle, helpTopic, [360 440]);
    D.Body.ColumnWidth = {'1x'};
    D.Body.RowHeight = {'1x'};
    lb = uilistbox(D.Body, 'Items', labels, 'ItemsData', 1:numel(labels), ...
        'Multiselect', 'on', 'Value', 1:numel(labels), 'FontSize', T.fontBody, ...
        'Tooltip', 'Ctrl/Shift-click to select several channels');
    D.Fig.UserData = [];
    D.Fig.CloseRequestFcn = @(~,~)uiresume(D.Fig);
    b = UIKit.button(D.Buttons, 'Cancel', @(~,~)uiresume(D.Fig), 'secondary', 'Do not save');
    b.Layout.Column = 2;
    b = UIKit.button(D.Buttons, 'OK', @(~,~)pickDone(D.Fig, lb), 'primary', 'Save the selected channels');
    b.Layout.Column = 3;
    uiwait(D.Fig);
    sel = [];
    if isvalid(D.Fig)
        sel = D.Fig.UserData;
        delete(D.Fig);
    end
end

%% Local helper: OK in chooseChannels - store selection, resume
function pickDone(fig, lb)
    if isempty(lb.Value)
        UIKit.alert(fig, 'Select at least one channel.', 'No Channels', 'warning');
        return;
    end
    fig.UserData = lb.Value;
    uiresume(fig);
end

%% Local helper: 'on'/'off' from a logical
function s = onOff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end

%% Local helper: return one of two values based on condition
function s = ifelse(cond, a, b)
    if cond, s = a; else, s = b; end
end

%% Local helper: "612.0 s" / "10.2 min" duration text
function s = fmtDuration(sec)
    if sec >= 120
        s = sprintf('%.1f min', sec / 60);
    else
        s = sprintf('%.1f s', sec);
    end
end
