%% ExtractEphysApp.m
% =========================================================================
% EXTRACT EPHYS DATA - LOAD A RECORDING, EXTRACT LFP AND MUA STREAMS
% =========================================================================
% Launched from Main. Built with UIKit.window: numbered step cards on the
% left, signal plots on the right, status bar below.
%   1 Load recording - Source dropdown (TDT tank, Intan .rhd, Open Ephys
%                      folder, NWB file) + Load recording… (folder or file
%                      picker for that source). Every source is read by
%                      EphysSource (core/io) into the TDTbin2mat struct
%                      shape used below: streams.xRAW (neural channels, V)
%                      and streams.Whis (candidate stimulus channels: TDT
%                      Whis, Intan digital/analog inputs, Open Ephys TTL
%                      lines/ADC, NWB stimulus TimeSeries/trials). TDT
%                      tanks: TDTbin2mat (SDK path resolved from the toolbox
%                      root); requires Whis and xRAW streams.
%   2 Choose channels - stimulus channel and one or more RAW channels.
%   3 Process        - Plot RAW, Process LFP (anti-alias + integer-factor
%                      downsample at the ACTUAL rate fs/dsFactor, lowpass,
%                      60 Hz notch; LFPProcessingParamsApp) or Process MUA
%                      (zero-phase bandpass; MUAProcessingParamsApp). The MUA
%                      signal kept for saving is the unsmoothed bandpassed
%                      trace; smoothing only draws a rectified display envelope.
%   4 Save           - Save LFP / Save MUA write .mat files for
%                      LFPAnalysisApp and MUAAnalysisApp, using the channels
%                      and stim channel snapshotted when processing ran.
%                      Export NWB… writes the processed LFP + stimulus as an
%                      NWB 2.x file (writeNWB: matnwb when installed,
%                      otherwise an "NWB-style export (not validated)").
% Up to 4 channels are drawn one per tile; more are stacked with offsets in
% one axes. Help button opens HelpApp on the "Ephys Extract" tab.
% "Try demo data" (loadDemo) opens DemoData's synthetic tank
% (DemoData.loadTank instead of TDTbin2mat) and selects stim ch 1 + all RAW
% channels; with another Source selected (or loadDemo(format)) it opens the
% same demo written in that format by core/demo/demoFormats.m.
% Programmatic use (no dialogs): openTank(folder), openRecording(path, format),
% loadDemo(format), setChannels(stim, raw), plotRAWData(),
% processLFPData(params), processMUAData(params), saveLFPTo(path, sel),
% saveMUATo(path, sel), exportNWB(path).
% =========================================================================

classdef ExtractEphysApp < handle
    %% PROPERTIES: UI, TDT data struct, selected channels, last processed LFP/MUA and params
    properties
        UIFig
        StatusLabel          % Status bar (UIKit.setStatus)
        SourceMenu           % Recording format dropdown (ItemsData = EphysSource format key)
        LoadBtn
        DemoBtn              % Load the synthetic demo tank (DemoData) / demo in the chosen format
        TankInfoLabel        % Recording name, Fs, duration, channel counts
        WhisChannelMenu      % Stimulus channel dropdown (ItemsData = channel number)
        RAWList              % xRAW channels, multi-select (ItemsData = channel numbers)
        SelectAllBtn
        SelectNoneBtn
        PlotRAWBtn
        ProcessLFPBtn
        ProcessMUABtn
        SaveLFPBtn
        SaveMUABtn
        ExportNWBBtn         % Export the processed LFP (+ stimulus) as NWB
        FsLabel              % Summary of processed LFP / MUA (rate, channels, saved)
        PlotCard             % Card around the plot area (title = what is shown)
        AxContainer          % Panel holding the tiledlayout of plots

        LastProcessedLFP
        LastLFPfs
        LastLFPChannels      % RAW channels used for LastProcessedLFP (snapshot)
        LastLFPStimChannel   % Whis channel selected when LFP was processed
        LastLFPParams        % LFP processing parameters (for the NWB 'filtering' text)
        LastMUAFilterParams
        LastProcessedMUA
        LastMUAfs
        LastMUAChannels      % RAW channels used for LastProcessedMUA (snapshot)
        LastMUAStimChannel   % Whis channel selected when MUA was processed

        Data  % Struct loaded from TDTbin2mat / EphysSource (streams.xRAW, streams.Whis, info)
        StimChannel  % Selected Whis channel
        RAWChannels  % Selected xRAW channels
        TankName = ''        % Name of the loaded tank / recording (default file names)
        SourceFormat = ''    % Format key of the loaded recording ('tdt', 'intan', 'openephys', 'nwb')
        LFPSaved = false     % LastProcessedLFP written to disk
        MUASaved = false     % LastProcessedMUA written to disk
        LastNWBExport = ''   % Path of the last NWB export
    end

    methods
        %% Constructor - Build UI; data loaded via Load recording
        function app = ExtractEphysApp()
            ensureIOPath();
            app.buildUI();
        end

        %% buildUI - UIKit window: step cards (left) | plot card (right)
        function buildUI(app)
            T = UITheme;
            W = UIKit.window('Extract Ephys Data', ...
                'Load a recording (TDT, Intan, Open Ephys, NWB), extract LFP and MUA', ...
                'Ephys Extract', [1200 840]);
            app.UIFig = W.Fig;
            app.StatusLabel = W.Status;
            W.Body.ColumnWidth = {300, '1x'};
            W.Body.RowHeight = {'1x'};

            left = uigridlayout(W.Body, [4 1], 'RowHeight', ...
                {136 + T.controlHeight + 14, '1x', 116, 124 + T.buttonHeight + 6}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            bh = T.buttonHeight;

            % --- 1 Load recording ---
            g = cardGrid(left, {22, T.controlHeight, bh, '1x'});
            UIKit.step(g, 1, 'Load recording');
            src = EphysSource.formats();
            sg = uigridlayout(g, [1 2], 'ColumnWidth', {56, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
            app.SourceMenu = UIKit.field(sg, 'Source', 'dropdown', {{src.label}, src(1).label}, ...
                ['Acquisition system / file format of the recording: TDT tank folder, Intan .rhd file, ' ...
                'Open Ephys binary folder or NWB 2.x file']);
            app.SourceMenu.ItemsData = {src.key};
            app.SourceMenu.Value = 'tdt';
            app.SourceMenu.ValueChangedFcn = @(~,~)app.onSourceChanged();
            sg = uigridlayout(g, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
            app.LoadBtn = UIKit.button(sg, 'Load recording…', @(~,~)app.loadRecording(), 'primary', ...
                src(1).hint);
            app.DemoBtn = UIKit.button(sg, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                demoTooltip('tdt'));
            app.TankInfoLabel = infoLabel(g, 'No recording loaded');

            % --- 2 Choose channels ---
            g = cardGrid(left, {22, T.controlHeight, 26, '1x'});
            UIKit.step(g, 2, 'Choose channels');
            sg = uigridlayout(g, [1 2], 'ColumnWidth', {'1x', 130}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
            app.WhisChannelMenu = UIKit.field(sg, 'Stimulus channel', 'dropdown', ...
                {{'—'}, '—'}, ['Channel carrying the stimulus, saved with LFP/MUA: Whis (TDT), ' ...
                'digital or analog input (Intan), TTL line or ADC (Open Ephys), stimulus ' ...
                'TimeSeries or trials (NWB)']);
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
            g = cardGrid(left, {22, bh, bh, '1x'}, 2);
            lbl = UIKit.step(g, 4, 'Save');
            lbl.Layout.Column = [1 2];
            app.SaveLFPBtn = UIKit.button(g, 'Save LFP…', @(~,~)app.saveLFPData(), 'secondary', ...
                'Save the processed LFP (+ stimulus) as .mat for LFP Analysis');
            app.SaveMUABtn = UIKit.button(g, 'Save MUA…', @(~,~)app.saveMUAData(), 'secondary', ...
                'Save the processed MUA (+ stimulus, filter settings) as .mat for MUA Analysis');
            app.ExportNWBBtn = UIKit.button(g, 'Export NWB…', @(~,~)app.saveNWBData(), 'secondary', ...
                ['Export the processed LFP (volts, at the LFP rate) and the stimulus channel as an ' ...
                'NWB 2.x file. Uses matnwb when installed; otherwise an NWB-style export ' ...
                '(not validated) by the built-in writer']);
            app.ExportNWBBtn.Layout.Column = [1 2];
            app.FsLabel = infoLabel(g, '');
            app.FsLabel.Layout.Column = [1 2];

            % --- Plots ---
            app.PlotCard = UIKit.card(W.Body, 'Signals');
            app.PlotCard.Layout.Row = 1; app.PlotCard.Layout.Column = 2;
            pg = uigridlayout(app.PlotCard, [1 1], 'Padding', [8 8 8 8], 'BackgroundColor', T.cardBg);
            app.AxContainer = uipanel(pg, 'BorderType', 'none', 'BackgroundColor', T.cardBg);
            app.showPlaceholder('Signals', 'Load a recording (or Try demo data) to begin');

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
            app.ExportNWBBtn.Enable = onOff(hasLFP);

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
        %% loadRecording - Load button: folder / file picker for the selected Source
        function loadRecording(app)
            fmt = app.SourceMenu.Value;
            if strcmp(fmt, 'tdt')
                app.loadTDT();
                return;
            end
            src = EphysSource.formats();
            src = src(strcmp({src.key}, fmt));
            startDir = ProjectManager.getImportDir();
            if isempty(startDir) || ~isfolder(startDir), startDir = pwd; end
            if strcmp(src.pick, 'folder')
                p = uigetdir(startDir, src.prompt);
                figure(app.UIFig);
                if isequal(p, 0)
                    UIKit.setStatus(app.StatusLabel, 'Load cancelled.', 'info');
                    return;
                end
            else
                [file, folder] = uigetfile(src.filter, src.prompt, startDir);
                figure(app.UIFig);
                if isequal(file, 0)
                    UIKit.setStatus(app.StatusLabel, 'Load cancelled.', 'info');
                    return;
                end
                p = fullfile(folder, file);
            end
            app.openRecording(p, fmt);
        end

        %% onSourceChanged - Source dropdown: update the Load / demo tooltips and hint
        function onSourceChanged(app)
            fmt = app.SourceMenu.Value;
            src = EphysSource.formats();
            src = src(strcmp({src.key}, fmt));
            app.LoadBtn.Tooltip = src.hint;
            app.DemoBtn.Tooltip = demoTooltip(fmt);
            if isempty(app.Data)
                app.showPlaceholder('Signals', sprintf('Load a recording (%s) or Try demo data to begin', ...
                    src.label));
            end
            UIKit.setStatus(app.StatusLabel, sprintf('Source: %s. Click Load recording… to choose the %s, or Try demo data.', ...
                src.label, src.pick), 'info');
        end

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
            ok = app.openRecording(folder, 'tdt');
        end

        %% openRecording - Load a recording (no dialog), check streams, fill channel lists
        % p: tank folder ('tdt'), .rhd file ('intan'), Open Ephys recording
        % or parent folder ('openephys'), .nwb file ('nwb'). format: one of
        % those keys, or omitted / 'auto' to detect it. Returns true on
        % success; on failure the previously loaded recording is kept.
        function ok = openRecording(app, p, format)
            ok = false;
            if nargin < 3 || isempty(format) || strcmpi(format, 'auto')
                try
                    format = EphysSource.detect(p);
                catch ME
                    UIKit.setStatus(app.StatusLabel, ME.message, 'error');
                    UIKit.alert(app.UIFig, ME.message, 'Load Failed');
                    return;
                end
            end
            format = lower(format);
            isTDT = strcmp(format, 'tdt');
            label = EphysSource.label(format);
            [~, name, ext] = fileparts(regexprep(p, '[\\/]+$', ''));
            if ~isTDT, name = [name ext]; end

            UIKit.setStatus(app.StatusLabel, sprintf('Loading %s…', name), 'busy');
            if isTDT
                dlg = UIKit.busy(app.UIFig, sprintf('Loading TDT tank %s… this can take a minute.', name));
            else
                dlg = UIKit.busy(app.UIFig, sprintf('Loading %s recording %s…', label, name));
            end
            try
                data = EphysSource.open(p, format);
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load %s: %s', name, ME.message), 'error');
                if isTDT
                    UIKit.alert(app.UIFig, sprintf(['Could not load the TDT tank:\n%s\n\n' ...
                        'Check that you selected a tank/block folder.'], ME.message), 'Load Failed');
                else
                    UIKit.alert(app.UIFig, sprintf('Could not load the %s recording:\n%s\n\n%s', ...
                        label, ME.message, loadHint(format)), 'Load Failed');
                end
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
            if isempty(data.streams.xRAW.data)
                UIKit.setStatus(app.StatusLabel, 'The recording has no neural channels.', 'error');
                UIKit.alert(app.UIFig, 'The recording has no neural (amplifier) channels.', 'Invalid Recording');
                return;
            end
            app.Data = data;
            if isTDT || ~isfield(data.info, 'blockname') || isempty(data.info.blockname)
                app.TankName = name;
            else
                app.TankName = data.info.blockname;
            end
            app.SourceFormat = format;
            app.SourceMenu.Value = format;
            app.LoadBtn.Tooltip = sourceHint(format);
            app.DemoBtn.Tooltip = demoTooltip(format);
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
            app.WhisChannelMenu.Items = app.stimItems(nStim);
            app.WhisChannelMenu.ItemsData = 1:nStim;
            app.WhisChannelMenu.Value = 1;
            app.RAWList.Items = app.rawItems(nRaw);
            app.RAWList.ItemsData = 1:nRaw;
            app.RAWList.Value = 1:min(4, nRaw);

            rawFs = data.streams.xRAW.fs;
            durS = size(data.streams.xRAW.data, 2) / rawFs;
            if isTDT
                app.TankInfoLabel.Text = sprintf('%s\nRAW %.2f Hz · stim %.2f Hz · %s\n%d RAW ch · %d stim ch', ...
                    name, rawFs, data.streams.Whis.fs, fmtDuration(durS), nRaw, nStim);
                app.showPlaceholder('Signals', 'Tank loaded. Choose channels, then Plot RAW or Process LFP / MUA.');
            else
                app.TankInfoLabel.Text = sprintf('%s · %s\nRAW %.2f Hz · stim %.2f Hz · %s\n%d RAW ch · %d stim ch', ...
                    name, label, rawFs, data.streams.Whis.fs, fmtDuration(durS), nRaw, nStim);
                app.showPlaceholder('Signals', 'Recording loaded. Choose channels, then Plot RAW or Process LFP / MUA.');
            end
            app.TankInfoLabel.Tooltip = p;
            app.updateControls();
            ok = true;
            if isTDT
                UIKit.setStatus(app.StatusLabel, sprintf('Loaded %s (%d RAW channels, %.2f Hz, %s).', ...
                    name, nRaw, rawFs, fmtDuration(durS)), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf(['Loaded %s recording %s (%d channels, %.2f Hz, %s; ' ...
                    '%d stimulus channel(s): %s).'], label, name, nRaw, rawFs, fmtDuration(durS), nStim, ...
                    strjoin(app.stimItems(nStim), ', ')), 'success');
            end
        end

        %% loadDemo - Load the demo recording and select every channel
        % format (default: the Source dropdown, initially 'tdt'):
        %   'tdt'  DemoData's synthetic tank: 30 s; 8 RAW channels (100 um
        %          apart) at 24414 Hz; Whis ch 1 carries 20 ms pulses every
        %          2 s from 1 s. Selects stim channel 1 and RAW channels 1-8
        %          so Plot RAW / Process LFP / Process MUA just work.
        %   'intan' | 'openephys' | 'nwb'  the first 6 s of tank channels
        %          3-6 written in that format by demoFormats (cached).
        function loadDemo(app, format)
            if nargin < 2 || isempty(format), format = app.SourceMenu.Value; end
            if ~strcmp(format, 'tdt')
                app.loadDemoFormat(format);
                return;
            end
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
                UIKit.alert(app.UIFig, 'Load a recording (or Try demo data) first.', 'No Data');
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
        %% recordedKind - 'LFP' when the loaded NWB series is an LFP (e.g. our own export), else 'RAW'
        function k = recordedKind(app)
            k = 'RAW';
            try
                p = app.Data.info.seriesPath;
                if strcmp(app.SourceFormat, 'nwb') && ~isempty(regexpi(p, 'lfp', 'once')), k = 'LFP'; end
            catch
            end
        end

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
                kind = app.recordedKind();   % 'RAW', or 'LFP' for an LFP series read from NWB
                layer = struct('data', {num2cell(raw, 2)'}, 'color', T.plotColors(1,:), ...
                    'width', 0.5, 'name', kind, 'center', true);
                app.drawChannels(sprintf('%s signals (%.2f Hz)', kind, raw_fs), t_raw, layer, ...
                    app.RAWChannels, kind, app.StimChannel);
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
            app.LastLFPParams = params;
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

%% ------------------------------------------------------------------------------------------
        %% saveNWBData - Export NWB… button: choose a .nwb file, then exportNWB(path)
        function saveNWBData(app)
            if isempty(app.LastProcessedLFP)
                UIKit.alert(app.UIFig, 'No processed LFP data available. Run Process LFP first.', 'Export NWB');
                return;
            end
            [file, path] = uiputfile({'*.nwb', 'NWB file (*.nwb)'}, 'Export NWB (processed LFP + stimulus)', ...
                app.defaultSavePath('LFP', '.nwb'));
            figure(app.UIFig);
            if isequal(file, 0)
                UIKit.setStatus(app.StatusLabel, 'Export NWB cancelled.', 'info');
                return;
            end
            app.exportNWB(fullfile(path, file));
        end

        %% exportNWB - Write the last processed LFP (+ its stimulus channel) as NWB, no dialogs
        % Uses writeNWB: matnwb when it is on the path, otherwise the
        % built-in minimal writer ("NWB-style export (not validated)").
        % LFP in volts at the LFP rate in /processing/ecephys/LFP, the
        % stimulus channel snapshotted at Process LFP in
        % /stimulus/presentation/stimulus, electrodes named after the
        % source channels. Returns true on success.
        function ok = exportNWB(app, filePath)
            ok = false;
            if isempty(app.LastProcessedLFP)
                UIKit.alert(app.UIFig, 'No processed LFP data available. Run Process LFP first.', 'Export NWB');
                return;
            end
            info = struct();
            if isfield(app.Data, 'info') && isstruct(app.Data.info), info = app.Data.info; end
            fmt = app.SourceFormat;
            if isempty(fmt), fmt = 'tdt'; end
            label = EphysSource.label(fmt);
            src = '';
            if isfield(info, 'file') && ischar(info.file), src = info.file; end

            r = struct();
            r.lfp = struct('data', cell2mat(app.LastProcessedLFP(:)), 'fs', app.LastLFPfs, ...
                'channels', app.LastLFPChannels, 'description', ...
                sprintf('LFP extracted with NeuroAnalyzer Extract Ephys from %s channels %s', label, ...
                mat2str(app.LastLFPChannels)), 'filtering', app.lfpFilteringText());
            stimName = app.stimLabel(app.LastLFPStimChannel);
            r.stim = struct('data', double(app.Data.streams.Whis.data(app.LastLFPStimChannel, :)), ...
                'fs', app.Data.streams.Whis.fs, 'name', 'stimulus', 'unit', 'a.u.', ...
                'description', sprintf('Stimulus channel %s of the source recording', stimName));
            names = arrayfun(@(c) sprintf('Ch %d', c), app.LastLFPChannels, 'UniformOutput', false);
            if isfield(info, 'channelNames') && numel(info.channelNames) >= max(app.LastLFPChannels)
                names = info.channelNames(app.LastLFPChannels);
            end
            r.electrodes = struct('names', {names(:)'}, 'device', sprintf('%s_system', fmt), ...
                'deviceDescription', sprintf('%s acquisition system', label));
            r.sessionDescription = sprintf('%s recording %s: LFP extracted with NeuroAnalyzer', label, app.TankName);
            r.source = strtrim(sprintf('%s %s', label, src));
            if isfield(info, 'sessionStartTime') && ischar(info.sessionStartTime) && ~isempty(info.sessionStartTime)
                r.sessionStartTime = info.sessionStartTime;
            else
                r.notes = 'Session start time unknown in the source recording; set to the export time.';
            end

            [~, fname, fext] = fileparts(filePath);
            UIKit.setStatus(app.StatusLabel, sprintf('Exporting %s%s…', fname, fext), 'busy');
            dlg = UIKit.busy(app.UIFig, 'Writing the NWB file…');
            try
                out = writeNWB(filePath, r);
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                app.fail('Export NWB failed', ME);
                return;
            end
            ok = true;
            app.LastNWBExport = filePath;
            if strcmp(out.engine, 'matnwb')
                kind = 'NWB file (written with matnwb)';
            else
                kind = 'NWB-style file (not validated)';
            end
            UIKit.setStatus(app.StatusLabel, sprintf('Exported %s: LFP (%d channel(s), %.2f Hz) + stimulus to %s%s.', ...
                kind, numel(app.LastLFPChannels), app.LastLFPfs, fname, fext), 'success');
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
            UIKit.styleAxes(axStim, sprintf('Stimulus (%s)', app.stimLabel(stimCh)), '', 'Stim');
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
                        UIKit.styleAxes(ax, '', 'Time (s)', sprintf('%s Ch %d (V)', prefix, chans(i)));
                    else
                        UIKit.styleAxes(ax, '', '', sprintf('%s Ch %d (V)', prefix, chans(i)));
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
                UIKit.styleAxes(ax, sprintf('%d channels (V), offset %.3g V per channel', nCh, spacing), ...
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

        %% defaultSavePath - <export dir>/<tank>_<kind><ext> (ext default '.mat')
        function p = defaultSavePath(app, kind, ext)
            if nargin < 3, ext = '.mat'; end
            d = ProjectManager.getExportDir();
            if isempty(d) || ~isfolder(d), d = pwd; end
            name = app.TankName;
            if isempty(name), name = 'ephys'; end
            p = fullfile(d, sprintf('%s_%s%s', name, kind, ext));
        end

        %% stimItems - Stimulus dropdown labels ('Ch k' for TDT, else the source's names)
        function items = stimItems(app, n)
            items = arrayfun(@(c) sprintf('Ch %d', c), 1:n, 'UniformOutput', false);
            if ~strcmp(app.SourceFormat, 'tdt') && isfield(app.Data, 'info') ...
                    && isfield(app.Data.info, 'stimNames') && numel(app.Data.info.stimNames) == n
                items = app.Data.info.stimNames(:)';
            end
        end

        %% rawItems - RAW list labels ('Ch k', plus the source's channel name)
        function items = rawItems(app, n)
            items = arrayfun(@(c) sprintf('Ch %d', c), 1:n, 'UniformOutput', false);
            if ~strcmp(app.SourceFormat, 'tdt') && isfield(app.Data, 'info') ...
                    && isfield(app.Data.info, 'channelNames') && numel(app.Data.info.channelNames) == n
                names = app.Data.info.channelNames;
                for c = 1:n
                    if ~strcmp(names{c}, items{c}), items{c} = sprintf('Ch %d  %s', c, names{c}); end
                end
            end
        end

        %% stimLabel - Name of a stimulus channel for plot titles
        function s = stimLabel(app, stimCh)
            s = sprintf('Whis Ch %d', stimCh);
            if ~strcmp(app.SourceFormat, 'tdt')
                items = app.stimItems(size(app.Data.streams.Whis.data, 1));
                if stimCh <= numel(items), s = items{stimCh}; end
            end
        end

        %% lfpFilteringText - What Process LFP did, for the NWB 'filtering' attribute
        function s = lfpFilteringText(app)
            p = app.LastLFPParams;
            rawFs = app.Data.streams.xRAW.fs;
            parts = {};
            if isstruct(p) && isfield(p, 'downsample') && p.downsample
                parts{end+1} = sprintf(['zero-phase 4th-order Butterworth anti-alias low-pass at %.4g Hz, ' ...
                    'downsampled by %d from %.6g Hz'], 0.8 * app.LastLFPfs / 2, round(rawFs / app.LastLFPfs), rawFs);
            end
            if isstruct(p) && isfield(p, 'lowCutoff') && ~isnan(p.lowCutoff) && p.lowCutoff > 0 ...
                    && p.lowCutoff < app.LastLFPfs / 2
                parts{end+1} = sprintf('zero-phase 4th-order Butterworth low-pass at %g Hz', p.lowCutoff);
            end
            if isstruct(p) && isfield(p, 'notch60') && p.notch60
                parts{end+1} = 'zero-phase 60 Hz notch (Q = 35)';
            end
            if isempty(parts), parts = {'none'}; end
            s = strjoin(parts, '; ');
        end

        %% loadDemoFormat - Open the demo written in an acquisition format (demoFormats)
        function ok = loadDemoFormat(app, format)
            ok = false;
            label = EphysSource.label(format);
            dlg = UIKit.busy(app.UIFig, sprintf('Preparing the %s demo (first time only takes a few seconds)…', label));
            try
                files = demoFormats([], 'Formats', {format});
                UIKit.done(dlg);
                if ~isfield(files, format)
                    error('NeuroAnalyzer:ExtractEphys:demo', 'No demo recording for format ''%s''.', format);
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load the demo data: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not load the demo data:\n%s', ME.message), 'Demo data');
                return;
            end
            if ~app.openRecording(files.(format), format), return; end
            app.Data.truth = files.truth;
            nRaw = size(app.Data.streams.xRAW.data, 1);
            app.setChannels(1, 1:nRaw);
            items = app.stimItems(size(app.Data.streams.Whis.data, 1));
            UIKit.setStatus(app.StatusLabel, sprintf(['Demo loaded (%s): the first %.0f s of the demo tank, ' ...
                'channels 3-6 as RAW Ch 1-%d at %.0f Hz; stimulus %s: %d pulses of 20 ms, every 2 s from 1 s. ' ...
                'Next: Process LFP (evoked sink at RAW Ch %d = tank channel 4).'], label, files.truth.duration, ...
                nRaw, app.Data.streams.xRAW.fs, items{1}, numel(files.truth.onsets), files.truth.sinkIndex), 'success');
            ok = true;
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

%% Local helper: put core/io (EphysSource, readers, writeNWB) and core/demo on the path
function ensureIOPath()
    rootDir = fileparts(fileparts(mfilename('fullpath')));
    if isempty(which('EphysSource')), addpath(fullfile(rootDir, 'core', 'io')); end
    if isempty(which('demoFormats')), addpath(fullfile(rootDir, 'core', 'demo')); end
end

%% Local helper: Load button tooltip for a source format
function s = sourceHint(fmt)
    src = EphysSource.formats();
    k = find(strcmp({src.key}, fmt), 1);
    if isempty(k), k = 1; end
    s = src(k).hint;
end

%% Local helper: what to check when a recording does not load
function s = loadHint(fmt)
    switch fmt
        case 'intan'
            s = 'Choose an Intan RHD2000 .rhd file saved in the traditional single-file format.';
        case 'openephys'
            s = ['Choose the Open Ephys recording folder (…/Record Node */experiment*/recording*, ' ...
                'with structure.oebin) or a folder above it; the recording must be in binary format.'];
        case 'nwb'
            s = 'Choose an NWB 2.x (.nwb) file with an ElectricalSeries in /acquisition or /processing.';
        otherwise
            s = 'Check that you selected the right file or folder for this source.';
    end
end

%% Local helper: Try demo data tooltip for a source format
function s = demoTooltip(fmt)
    if strcmp(fmt, 'tdt')
        s = ['Load a synthetic 30 s tank with known answers: 8 RAW channels 100 µm apart, ' ...
            '15 whisker stimuli (every 2 s), an evoked potential with its sink at channel 4 ' ...
            'and three units near channels 4-5'];
    else
        s = sprintf(['Load the demo tank''s first 6 s (channels 3-6: evoked sink at the 2nd, units ' ...
            'near the 2nd-3rd) written as %s, with 3 stimuli (20 ms, every 2 s from 1 s)'], ...
            EphysSource.label(fmt));
    end
end

%% Local helper: "612.0 s" / "10.2 min" duration text
function s = fmtDuration(sec)
    if sec >= 120
        s = sprintf('%.1f min', sec / 60);
    else
        s = sprintf('%.1f s', sec);
    end
end
