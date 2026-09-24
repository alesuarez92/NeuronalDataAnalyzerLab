%% LFPAnalysisApp.m
% =========================================================================
% PROCESS LFP DATA - ERP, CSD AND TIME-FREQUENCY ANALYSIS ON LOADED LFP
% =========================================================================
% Launched from Main. Built with UIKit.window: numbered step cards on the
% left (scrollable column), result tabs on the right, status bar below.
%   1 Load LFP file - .mat saved by ExtractEphysApp (Save LFP): lfp_data,
%                     stim_data, t_lfp, t_stim, lfp_fs, stim_fs (checked).
%   2 Channels      - LFP rows to analyse (multi-select).
%   3 ERP analysis  - ERPConfigApp (window, threshold, min ISI); onsets are
%                     upward threshold crossings of the mean-subtracted
%                     stimulus at time (k-1)/Fs; edge epochs are NaN-filled
%                     and excluded, the valid epoch count is reported.
%                     (Computed by core/ERPAnalysis: detectOnsets, average.)
%   4 CSD           - second spatial derivative of the ERP across a user
%                     channel order (>= 3 channels from the last ERP) and
%                     inter-electrode spacing (um); edge rows replicated.
%                     (ERPAnalysis.csd.)
%   5 Export        - ERP (mean, SD, t, y = channel average) and CSD to .mat.
%   6 Time-frequency- one channel (dropdown), frequency range (Hz), wavelet
%                     cycles, epoch and baseline windows (s), and editable
%                     band presets (delta 1-4, theta 4-8, alpha 8-13, beta
%                     13-30, gamma 30-80 Hz: conventions, not fixed
%                     physiology). Spectrum (Welch PSD), Spectrogram (STFT),
%                     ERSP / ITPC (Morlet wavelets, dB vs baseline) and Band
%                     power (% change vs baseline, mean ± SEM over trials),
%                     all computed by core/TimeFrequency. ERSP and band
%                     power use the stimulus onsets found with the ERP
%                     threshold / min ISI (defaults 0.5 and 0.5 s before
%                     the first ERP run).
% Tabs: Stimulus (with threshold and detected onsets), ERP overlay, ERP per
% channel (mean ± SD), CSD map, Spectrum, Spectrogram, ERSP / ITPC, Band
% power. Help button opens HelpApp on "LFP Analysis".
% "Try demo data" (loadDemo) opens DemoData's synthetic LFP, selects all
% channels and pre-fills CSD spacing 100 um / order 1..8. "Try oscillation
% demo" (loadOscillationDemo) opens core/demo/demoLFPOscillations (the same
% LFP plus 6 Hz theta on every channel and a phase-locked 40 Hz burst
% 50-250 ms after each stimulus on channels 3-5) with channel 4 chosen for
% the time-frequency step. Programmatic use (no dialogs): openFile(path),
% setChannels(idx), runERP(params), computeCSD(spacingUm, order),
% exportResults(path), loadOscillationDemo(), runSpectrum(ch),
% runSpectrogram(ch, fRange), runERSP(ch, fRange, baseline),
% runBandPower(ch, bands); the run* methods return true on success.
% =========================================================================

classdef LFPAnalysisApp < handle
    %% PROPERTIES: UI, loaded LFP/Stim/t/Fs, selected channels, ERP params and last results
    properties
        UIFig
        StatusLabel      % Status bar (UIKit.setStatus)
        LoadBtn
        DemoBtn          % Load DemoData's synthetic LFP file
        FileLabel        % File name, Fs, duration, channel count

        ChannelList      % Multi-select listbox (ItemsData = LFP row index)
        ChannelLabel     % "n of N selected"
        SelectAllBtn
        SelectNoneBtn
        ERBBtn           % Run ERP analysis (opens ERPConfigApp)
        ERPInfoLabel     % "Averaged n of m epochs"
        SpacingEdit      % CSD inter-electrode spacing (um)
        ChannelOrderEdit % CSD channel order, e.g. "5 4 3 2 1"
        CSDBtn
        ExportBtn

        LeftGrid         % Scrollable column holding the step cards
        TFChannelDrop    % Time-frequency channel (ItemsData = LFP row index)
        TFFminEdit       % Lowest frequency (Hz)
        TFFmaxEdit       % Highest frequency (Hz)
        TFCyclesEdit     % Morlet wavelet cycles
        TFEpochFromEdit  % Epoch start relative to onset (s)
        TFEpochToEdit    % Epoch end relative to onset (s)
        TFBaseFromEdit   % Baseline start (s)
        TFBaseToEdit     % Baseline end (s)
        BandTable        % uitable: Band | Low (Hz) | High (Hz) | Plot
        OscDemoBtn       % Load the oscillation demo (theta + evoked gamma)
        SpectrumBtn
        SpectrogramBtn
        ERSPBtn
        BandPowerBtn

        Tabs             % uitabgroup with the result views
        TabStim
        TabOverlay
        TabChannels
        TabCSD
        TabSpectrum
        TabSpectrogram
        TabERSP
        TabBandPower
        AxStim           % Stimulus (mean-subtracted) + threshold + onsets
        AxOverlay        % ERP overlay, all selected channels
        AxContainer      % Panel with the per-channel ERP tiles
        AxCSD            % CSD image
        AxSpectrum       % Welch PSD (log-log) with band shading
        AxSpectrogram    % STFT power (dB) with stimulus markers
        AxERSP           % ERSP (dB vs baseline)
        AxITPC           % Inter-trial phase coherence (0..1)
        BandContainer    % Panel with one band-power tile per band

        % Data
        LFP
        Stim
        t_lfp
        t_stim
        Fs_lfp
        Fs_stim
        FileName = ''
        LFPChannelIDs    % lfp_channels from the file (TDT numbers), if present

        % Analysis
        SelectedChannels
        ERPParams
        LastERP
        LastTime
        LastERPStd
        LastNValid       % Number of complete epochs averaged
        LastOnsetTimes   % Detected onset times (s)
        LastCSD
        LastCSDOrder
        LastCSDSpacing   % um
        Exported = false

        % Time-frequency results (step 6)
        LastSpectrum     % struct: channel, f, pxx, segSec
        LastSpectrogram  % struct: channel, f, t, powerDb, fRange, winSec, onsetTimes
        LastERSP         % struct: channel, freqs, t, erspDb, itpc, info, baseline, window
        LastBandPower    % TimeFrequency.eventBandPower result + channel, names
        TFDone = struct('spectrum', false, 'spectrogram', false, 'ersp', false, 'bandpower', false)
        TFFocus = false  % next-step hints follow step 6 (oscillation demo / after a TF run)
    end

    properties (Constant, Access = private)
        DefaultOnsetParams = struct('threshold', 0.5, 'minISI', 0.5)   % until an ERP was run
    end

    methods
        %% Constructor - Build UI; data loaded via Load LFP file
        function app = LFPAnalysisApp()
            app.buildUI();
        end

        %% buildUI - UIKit window: step cards (left) | result tabs (right)
        function buildUI(app)
            T = UITheme;
            W = UIKit.window('LFP / ERP Analysis', ...
                'Load LFP, average evoked responses (ERP), map current source density (CSD) and analyse oscillations', ...
                'LFP Analysis', [1200 820]);
            app.UIFig = W.Fig;
            app.StatusLabel = W.Status;
            W.Body.ColumnWidth = {300, '1x'};
            W.Body.RowHeight = {'1x'};
            bh = T.buttonHeight;
            ch = T.controlHeight;

            % Fixed row heights: the column scrolls, so a '1x' row could collapse
            tfRows = {22, bh, ch, ch, ch, ch, ch, 34, 134, bh, bh};
            tfH = sum([tfRows{:}]) + 6 * (numel(tfRows) - 1) + 18;
            left = uigridlayout(W.Body, [6 1], 'RowHeight', {124 + bh + 6, 170, 112, 142, 78, tfH}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            app.LeftGrid = left;

            % --- 1 Load LFP file ---
            g = cardGrid(left, {22, bh, bh, '1x'});
            UIKit.step(g, 1, 'Load LFP file');
            app.LoadBtn = UIKit.button(g, 'Load LFP file…', @(~,~)app.loadData(), 'primary', ...
                'Open a .mat saved by Extract Ephys (Save LFP)');
            app.DemoBtn = UIKit.button(g, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Load a synthetic 30 s LFP with known answers: 8 channels 100 µm apart, 15 stimuli ' ...
                '(every 2 s), an evoked potential (N1 at 15 ms, P2 at 40 ms) with its current sink at channel 4']);
            app.FileLabel = infoLabel(g, 'No file loaded');

            % --- 2 Channels ---
            g = cardGrid(left, {22, 26, '1x'});
            UIKit.step(g, 2, 'Channels');
            sg = uigridlayout(g, [1 3], 'ColumnWidth', {'1x', 48, 52}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.ChannelLabel = uilabel(sg, 'Text', 'No channels loaded', 'FontSize', T.fontSmall, ...
                'FontColor', T.bodyColor, 'Tooltip', 'Ctrl/Shift-click in the list to select several channels');
            app.SelectAllBtn = UIKit.button(sg, 'All', @(~,~)app.selectChannels(true), 'secondary', ...
                'Select every channel');
            app.SelectNoneBtn = UIKit.button(sg, 'None', @(~,~)app.selectChannels(false), 'secondary', ...
                'Clear the channel selection');
            app.ChannelList = uilistbox(g, 'Items', {}, 'Multiselect', 'on', ...
                'Tooltip', 'Channels for the ERP (and CSD). Ctrl/Shift-click to select several.', ...
                'ValueChangedFcn', @(~,~)app.onChannelsChanged());

            % --- 3 ERP analysis ---
            g = cardGrid(left, {22, bh, '1x'});
            UIKit.step(g, 3, 'ERP analysis');
            app.ERBBtn = UIKit.button(g, 'Run ERP…', @(~,~)app.openERPConfig(), 'secondary', ...
                'Set the epoch window and stimulus threshold, then average epochs per channel');
            app.ERPInfoLabel = infoLabel(g, 'Not run yet');

            % --- 4 CSD ---
            g = cardGrid(left, {22, ch, ch, bh}, 2);
            lbl = UIKit.step(g, 4, 'CSD');
            lbl.Layout.Column = [1 2];
            app.SpacingEdit = UIKit.field(g, 'Spacing (µm)', 'numeric', 100, ...
                'Distance between neighbouring electrode contacts in micrometres', [0 Inf]);
            app.SpacingEdit.LowerLimitInclusive = 'off';
            app.ChannelOrderEdit = UIKit.field(g, 'Channel order', 'text', '', ...
                ['Channels from the last ERP, top (superficial) to bottom (deep), ' ...
                'e.g. "5 4 3 2 1". At least 3.']);
            app.CSDBtn = UIKit.button(g, 'Compute CSD', @(~,~)app.computeCSD(), 'secondary', ...
                'Second spatial derivative of the ERP across the ordered channels (needs >= 3)');
            app.CSDBtn.Layout.Column = [1 2];

            % --- 5 Export ---
            g = cardGrid(left, {22, bh});
            UIKit.step(g, 5, 'Export');
            app.ExportBtn = UIKit.button(g, 'Export ERP / CSD…', @(~,~)app.exportResults(), 'secondary', ...
                'Save ERP mean/SD, time axis, epoch count and (if computed) CSD to .mat');

            % --- 6 Time-frequency ---
            g = cardGrid(left, tfRows, 2);
            lbl = UIKit.step(g, 6, 'Time–frequency');
            lbl.Layout.Column = [1 2];
            app.OscDemoBtn = UIKit.button(g, 'Try oscillation demo', @(~,~)app.loadOscillationDemo(), 'secondary', ...
                ['Load the demo LFP plus known oscillations: 6 Hz theta (40 µV, all channels, not phase-locked) ' ...
                'and a 40 Hz gamma burst (10 µV) 50–250 ms after each stimulus on channels 3–5']);
            app.OscDemoBtn.Layout.Column = [1 2];
            app.TFChannelDrop = UIKit.field(g, 'Channel', 'dropdown', {{'—'}, '—'}, ...
                'LFP channel for the spectrum, spectrogram, ERSP / ITPC and band power');
            [app.TFFminEdit, app.TFFmaxEdit] = rangeField(g, 'Frequencies (Hz)', 2, 80, ...
                'Lowest and highest frequency (Hz) for the spectrogram and ERSP / ITPC (below Fs/2)');
            app.TFFminEdit.Limits = [0 Inf]; app.TFFmaxEdit.Limits = [0 Inf];
            app.TFFmaxEdit.LowerLimitInclusive = 'off';
            app.TFCyclesEdit = UIKit.field(g, 'Wavelet cycles', 'numeric', 7, ...
                ['Cycles per Morlet wavelet (ERSP / ITPC). More cycles: finer frequency, coarser time ' ...
                '(time resolution ≈ cycles / (2π·f) s)'], [1 50]);
            [app.TFEpochFromEdit, app.TFEpochToEdit] = rangeField(g, 'Epoch (s)', -0.5, 1, ...
                'Epoch start and end relative to each stimulus onset (s) for ERSP / ITPC and band power');
            [app.TFBaseFromEdit, app.TFBaseToEdit] = rangeField(g, 'Baseline (s)', -0.4, -0.1, ...
                'Pre-stimulus reference window (s, inside the epoch): ERSP is dB and band power % change relative to it');
            hintLbl = uilabel(g, 'Text', ['Band limits (Hz) are conventions, not fixed physiology: edit ' ...
                'them as needed. Plot = show in Band power.'], 'FontSize', T.fontTiny, ...
                'FontColor', T.bodyColor, 'WordWrap', 'on', 'VerticalAlignment', 'top');
            hintLbl.Layout.Column = [1 2];
            b = TimeFrequency.defaultBands();
            app.BandTable = uitable(g, 'Data', [{b.name}', num2cell(vertcat(b.range)), num2cell(true(numel(b), 1))], ...
                'ColumnName', {'Band', 'Low (Hz)', 'High (Hz)', 'Plot'}, 'RowName', {}, ...
                'ColumnEditable', [true true true true], 'ColumnWidth', {'auto', 76, 76, 40}, ...
                'ColumnFormat', {'char', 'numeric', 'numeric', 'logical'}, 'FontSize', T.fontSmall, ...
                'CellEditCallback', @(src, evt)app.onBandEdited(src, evt));
            app.BandTable.Layout.Column = [1 2];
            app.SpectrumBtn = UIKit.button(g, 'Spectrum', @(~,~)app.runSpectrum(), 'secondary', ...
                'Welch power spectral density of the whole recording (2 s Hann segments, 50% overlap), log axes');
            app.SpectrogramBtn = UIKit.button(g, 'Spectrogram', @(~,~)app.runSpectrogram(), 'secondary', ...
                'Short-time Fourier power (0.5 s Hann windows, 90% overlap) over the recording, with stimulus markers');
            app.ERSPBtn = UIKit.button(g, 'ERSP / ITPC', @(~,~)app.runERSP(), 'secondary', ...
                ['Event-related power change (dB vs baseline) and inter-trial phase coherence (0–1) around ' ...
                'each stimulus, from Morlet wavelets']);
            app.BandPowerBtn = UIKit.button(g, 'Band power', @(~,~)app.runBandPower(), 'secondary', ...
                'Power of each ticked band around the stimulus: % change vs baseline, mean ± SEM over trials');

            % --- Result tabs ---
            app.Tabs = uitabgroup(W.Body);
            app.Tabs.Layout.Row = 1; app.Tabs.Layout.Column = 2;
            app.TabStim     = uitab(app.Tabs, 'Title', 'Stimulus', 'BackgroundColor', T.cardBg);
            app.TabOverlay  = uitab(app.Tabs, 'Title', 'ERP overlay', 'BackgroundColor', T.cardBg);
            app.TabChannels = uitab(app.Tabs, 'Title', 'ERP per channel', 'BackgroundColor', T.cardBg);
            app.TabCSD      = uitab(app.Tabs, 'Title', 'CSD', 'BackgroundColor', T.cardBg);
            app.TabSpectrum    = uitab(app.Tabs, 'Title', 'Spectrum', 'BackgroundColor', T.cardBg);
            app.TabSpectrogram = uitab(app.Tabs, 'Title', 'Spectrogram', 'BackgroundColor', T.cardBg);
            app.TabERSP        = uitab(app.Tabs, 'Title', 'ERSP / ITPC', 'BackgroundColor', T.cardBg);
            app.TabBandPower   = uitab(app.Tabs, 'Title', 'Band power', 'BackgroundColor', T.cardBg);
            app.AxStim    = uiaxes(tabGrid(app.TabStim));
            app.AxOverlay = uiaxes(tabGrid(app.TabOverlay));
            app.AxContainer = uipanel(tabGrid(app.TabChannels), 'BorderType', 'none', ...
                'BackgroundColor', T.cardBg);
            app.AxCSD     = uiaxes(tabGrid(app.TabCSD));
            app.AxSpectrum    = uiaxes(tabGrid(app.TabSpectrum));
            app.AxSpectrogram = uiaxes(tabGrid(app.TabSpectrogram));
            eg = tabGrid(app.TabERSP);
            eg.ColumnWidth = {'1x', '1x'}; eg.ColumnSpacing = 12;
            app.AxERSP = uiaxes(eg);
            app.AxITPC = uiaxes(eg);
            app.BandContainer = uipanel(tabGrid(app.TabBandPower), 'BorderType', 'none', ...
                'BackgroundColor', T.cardBg);
            UIKit.emptyAxes(app.AxStim, 'Load an LFP file (or Try demo data) to begin');
            UIKit.emptyAxes(app.AxOverlay, 'Run the ERP analysis (step 3) to see the overlay');
            app.channelPlaceholder('Run the ERP analysis (step 3) to see each channel');
            UIKit.emptyAxes(app.AxCSD, 'Run the ERP, then Compute CSD (step 4)');
            app.tfPlaceholders();

            app.updateControls();
        end

        %% updateControls - Enable state and primary (next) action from data state
        function updateControls(app)
            hasData = ~isempty(app.LFP);
            nSel = 0;
            if hasData, nSel = numel(app.ChannelList.Value); end
            hasERP = ~isempty(app.LastERP) && ~isempty(app.LastTime);
            hasCSD = ~isempty(app.LastCSD);
            nERP = numel(app.SelectedChannels);

            setEnable({app.ChannelList, app.SelectAllBtn, app.SelectNoneBtn}, hasData);
            app.ERBBtn.Enable = onOff(nSel > 0);
            setEnable({app.SpacingEdit, app.ChannelOrderEdit, app.CSDBtn}, hasERP);
            app.ExportBtn.Enable = onOff(hasERP);
            setEnable({app.TFChannelDrop, app.TFFminEdit, app.TFFmaxEdit, app.TFCyclesEdit, ...
                app.TFEpochFromEdit, app.TFEpochToEdit, app.TFBaseFromEdit, app.TFBaseToEdit, ...
                app.BandTable, app.SpectrumBtn, app.SpectrogramBtn, app.ERSPBtn, app.BandPowerBtn}, hasData);

            if hasData
                app.ChannelLabel.Text = sprintf('%d of %d selected', nSel, size(app.LFP, 1));
            end

            % Recommended next action: load -> ERP -> CSD (>= 3 ch) -> export;
            % when working in step 6: spectrum -> spectrogram -> ERSP -> band power
            tfBtns = [app.SpectrumBtn, app.SpectrogramBtn, app.ERSPBtn, app.BandPowerBtn];
            tfDone = [app.TFDone.spectrum, app.TFDone.spectrogram, app.TFDone.ersp, app.TFDone.bandpower];
            if ~hasData
                next = app.LoadBtn;
            elseif app.TFFocus && ~all(tfDone)
                next = tfBtns(find(~tfDone, 1));
            elseif ~hasERP
                next = app.ERBBtn;
            elseif nERP >= 3 && ~hasCSD
                next = app.CSDBtn;
            elseif ~app.Exported
                next = app.ExportBtn;
            else
                next = [];
            end
            for b = [app.LoadBtn, app.ERBBtn, app.CSDBtn, app.ExportBtn, tfBtns]
                setButtonStyle(b, isequal(b, next));
            end
        end

        %% loadData - Pick an LFP .mat, then openFile(path)
        function loadData(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir) || ~isfolder(startDir), startDir = pwd; end
            [file, path] = uigetfile('*.mat', 'Select LFP Data File', startDir);
            figure(app.UIFig);
            if isequal(file, 0)
                UIKit.setStatus(app.StatusLabel, 'Load cancelled.', 'info');
                return;
            end
            app.openFile(fullfile(path, file));
        end

        %% openFile - Load an LFP .mat by path (no dialog), validate, fill channel list
        % Returns true on success; on failure the previous data is kept.
        function ok = openFile(app, filePath)
            ok = false;
            [~, name, ext] = fileparts(filePath);
            file = [name ext];
            UIKit.setStatus(app.StatusLabel, sprintf('Loading %s…', file), 'busy');
            dlg = UIKit.busy(app.UIFig, sprintf('Loading %s…', file));
            try
                s = load(filePath);
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not read %s: %s', file, ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not read the file:\n%s', ME.message), 'Load Failed');
                return;
            end
            UIKit.done(dlg);

            % Validate that the file was saved by ExtractEphysApp (Save LFP Data)
            required = {'lfp_data', 'stim_data', 't_lfp', 't_stim', 'lfp_fs', 'stim_fs'};
            missing = required(~isfield(s, required));
            if ~isempty(missing)
                msg = sprintf('Invalid LFP file. Missing variable(s): %s', strjoin(missing, ', '));
                UIKit.setStatus(app.StatusLabel, msg, 'error');
                UIKit.alert(app.UIFig, [msg sprintf(['\n\nUse a file written by Extract Ephys ' ...
                    '(step 4, Save LFP).'])], 'Invalid File');
                return;
            end
            app.LFP = s.lfp_data;
            app.Stim = s.stim_data;
            app.t_lfp = s.t_lfp;
            app.t_stim = s.t_stim;
            app.Fs_lfp = s.lfp_fs;
            app.Fs_stim = s.stim_fs;
            app.FileName = file;

            % Drop results from a previously loaded file
            app.SelectedChannels = [];
            app.ERPParams = [];
            app.LastERP = []; app.LastTime = []; app.LastERPStd = [];
            app.LastNValid = []; app.LastOnsetTimes = [];
            app.LastCSD = []; app.LastCSDOrder = []; app.LastCSDSpacing = [];
            app.Exported = false;
            app.LastSpectrum = []; app.LastSpectrogram = []; app.LastERSP = []; app.LastBandPower = [];
            app.TFDone = struct('spectrum', false, 'spectrogram', false, 'ersp', false, 'bandpower', false);
            app.TFFocus = false;

            % Channel list: row index (used by ERP/CSD), plus TDT channel if saved
            nChan = size(app.LFP, 1);
            chanLabels = arrayfun(@(i) sprintf('Ch %d', i), 1:nChan, 'UniformOutput', false);
            app.LFPChannelIDs = [];
            if isfield(s, 'lfp_channels') && numel(s.lfp_channels) == nChan
                app.LFPChannelIDs = s.lfp_channels(:)';
                chanLabels = arrayfun(@(i) sprintf('Ch %d  (TDT %d)', i, app.LFPChannelIDs(i)), ...
                    1:nChan, 'UniformOutput', false);
            end
            app.ChannelList.ItemsData = [];
            app.ChannelList.Items = chanLabels;
            app.ChannelList.ItemsData = 1:nChan;
            app.ChannelList.Value = 1:min(4, nChan);
            app.ChannelOrderEdit.Value = '';
            app.TFChannelDrop.ItemsData = [];
            app.TFChannelDrop.Items = chanLabels;
            app.TFChannelDrop.ItemsData = 1:nChan;
            app.TFChannelDrop.Value = 1;

            durS = size(app.LFP, 2) / app.Fs_lfp;
            app.FileLabel.Text = sprintf('%s\nLFP %.2f Hz · %s · %d ch\nStim %.2f Hz', ...
                file, app.Fs_lfp, fmtDuration(durS), nChan, app.Fs_stim);
            app.FileLabel.Tooltip = filePath;
            app.ERPInfoLabel.Text = 'Not run yet';

            % Reset result views; show the stimulus so the threshold can be judged
            app.plotStimulus();
            resetAxes(app.AxOverlay);
            UIKit.emptyAxes(app.AxOverlay, 'Run the ERP analysis (step 3) to see the overlay');
            app.channelPlaceholder('Run the ERP analysis (step 3) to see each channel');
            resetAxes(app.AxCSD);
            UIKit.emptyAxes(app.AxCSD, 'Run the ERP, then Compute CSD (step 4)');
            app.tfPlaceholders();
            app.Tabs.SelectedTab = app.TabStim;

            app.updateControls();
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf('Loaded %s (%d channels, %.2f Hz, %s). Next: Run ERP.', ...
                file, nChan, app.Fs_lfp, fmtDuration(durS)), 'success');
        end

        %% loadDemo - Load DemoData's synthetic LFP; select all channels, pre-fill CSD
        % 30 s, 8 channels 100 um apart at 1017.25 Hz; stimulus pulses
        % (20 ms, amplitude 1) every 2 s from 1 s. Selects every channel and
        % pre-fills CSD spacing 100 um and order 1..8, so Run ERP (default
        % threshold 0.5) and Compute CSD just work; the sink is at ch 4.
        function loadDemo(app)
            dlg = UIKit.busy(app.UIFig, 'Preparing demo data (first time only takes a few seconds)…');
            try
                p = DemoData.file('lfp');
                UIKit.done(dlg);
                if ~app.openFile(p), return; end
                nChan = size(app.LFP, 1);
                app.setChannels(1:nChan);
                app.SpacingEdit.Value = 100;
                app.ChannelOrderEdit.Value = strjoin(arrayfun(@num2str, 1:nChan, 'UniformOutput', false), ' ');
                stim = app.Stim(:) - mean(app.Stim);
                nStim = sum(diff([false; stim > 0.5]) == 1);
                UIKit.setStatus(app.StatusLabel, sprintf(['Demo loaded: %s LFP, %d channels 100 µm apart, ' ...
                    '%d stimuli (20 ms, every 2 s). All channels selected, CSD spacing 100 µm. ' ...
                    'Next: Run ERP (threshold 0.5), then Compute CSD: the sink is at ch 4.'], ...
                    fmtDuration(size(app.LFP, 2) / app.Fs_lfp), nChan, nStim), 'success');
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load the demo data: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not load the demo data:\n%s', ME.message), 'Demo data');
            end
        end

        %% setChannels - Select LFP rows for the ERP programmatically
        % idx: row indices (values outside 1..nChannels are ignored).
        function setChannels(app, idx)
            if isempty(app.LFP), return; end
            idx = idx(ismember(idx, app.ChannelList.ItemsData));
            app.ChannelList.Value = idx(:)';
            app.onChannelsChanged();
        end

        %% onChannelsChanged - Selection changed: refresh enable state and status
        function onChannelsChanged(app)
            app.updateControls();
            if isempty(app.ChannelList.Value)
                UIKit.setStatus(app.StatusLabel, 'Select at least one channel for the ERP.', 'warning');
            end
        end

        %% selectChannels - All / None buttons
        function selectChannels(app, selectAll)
            if isempty(app.LFP), return; end
            if selectAll
                app.ChannelList.Value = app.ChannelList.ItemsData;
            else
                app.ChannelList.Value = [];
            end
            app.onChannelsChanged();
        end

        %% openERPConfig - ERPConfigApp dialog, then computeERP on OK
        function openERPConfig(app)
            app.runERP();
        end

        %% runERP - ERP on the selected channels; params skip the dialog
        % -------------------------------------------------------------
        % Without params the ERPConfigApp dialog asks for them (same as the
        % Run ERP button). params: preTime, postTime (s), threshold
        % (stimulus units, on the mean-subtracted stimulus), minISI (s);
        % missing fields default to 0.1, 0.3, 0.5, 0.5.
        % -------------------------------------------------------------
        function runERP(app, params)
            sel = app.ChannelList.Value;
            if isempty(sel)
                UIKit.alert(app.UIFig, 'Please select at least one channel for ERP analysis.', 'ERP Analysis');
                return;
            end

            if nargin < 2 || isempty(params)
                cfg = ERPConfigApp(app.Fs_lfp);
                uiwait(cfg.UIFig);
                if isempty(cfg.Params)
                    UIKit.setStatus(app.StatusLabel, 'ERP analysis cancelled.', 'info');
                    return;
                end
                params = cfg.Params;
            else
                defaults = struct('preTime', 0.1, 'postTime', 0.3, 'threshold', 0.5, 'minISI', 0.5);
                f = fieldnames(defaults);
                for k = 1:numel(f)
                    if ~isfield(params, f{k}), params.(f{k}) = defaults.(f{k}); end
                end
            end
            % Commit selection only once the dialog is confirmed, so a cancel
            % does not desync SelectedChannels from LastERP (used by CSD)
            app.SelectedChannels = sel(:)';
            app.ERPParams = params;

            % Next: computeERP()
            app.computeERP();
        end

        %% computeERP - Detect onsets, cut NaN-filled epochs, average, plot
        function computeERP(app)
            % Extract parameters
            fs = app.Fs_lfp;
            preS = app.ERPParams.preTime;
            postS = app.ERPParams.postTime;
            threshold = app.ERPParams.threshold;
            minISI = app.ERPParams.minISI;
            chIdx = app.SelectedChannels;

            % Detect stimulus onsets: upward threshold crossings of the
            % mean-subtracted stimulus, min ISI, sample k at (k-1)/Fs
            onsetTimes = ERPAnalysis.detectOnsets(app.Stim, app.Fs_stim, threshold, minISI);
            if isempty(onsetTimes)
                app.plotStimulus(threshold, []);
                app.Tabs.SelectedTab = app.TabStim;
                app.erpFailed(['No stimulus onsets detected. Check the threshold against the ' ...
                    'Stimulus tab (dashed line).']);
                return;
            end

            % NaN-filled epochs (edge epochs skipped), mean and SD over the complete ones
            [erpAvg, erpStd, t, nValid] = ERPAnalysis.average(app.LFP(chIdx, :), fs, onsetTimes, preS, postS);
            if nValid == 0
                app.plotStimulus(threshold, onsetTimes);
                app.erpFailed('No complete epochs: all onsets are too close to the recording edges.');
                return;
            end

            app.LastERP  = erpAvg;
            app.LastTime = t;
            app.LastERPStd = erpStd;
            app.LastNValid = nValid;
            app.LastOnsetTimes = onsetTimes;
            app.LastCSD = []; app.LastCSDOrder = []; app.LastCSDSpacing = [];   % CSD now stale
            app.Exported = false;
            app.ChannelOrderEdit.Value = num2str(chIdx);
            resetAxes(app.AxCSD);
            UIKit.emptyAxes(app.AxCSD, 'Compute CSD (step 4) for this ERP');

            dlg = UIKit.busy(app.UIFig, 'Plotting ERPs…');
            try
                app.plotStimulus(threshold, onsetTimes);
                app.plotOverlay(t, erpAvg, chIdx, nValid);
                app.plotPerChannel(t, erpAvg, erpStd, chIdx, nValid);
            catch ME
                UIKit.done(dlg);
                app.updateControls();
                UIKit.setStatus(app.StatusLabel, sprintf('ERP computed but plotting failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Plotting failed:\n%s', ME.message), 'ERP Analysis');
                return;
            end
            UIKit.done(dlg);
            app.Tabs.SelectedTab = app.TabOverlay;

            app.ERPInfoLabel.Text = sprintf('Averaged %d of %d epochs · %d ch · −%g to +%g s', ...
                nValid, numel(onsetTimes), numel(chIdx), preS, postS);
            app.updateControls();
            nextHint = 'Next: Export.';
            if numel(chIdx) >= 3, nextHint = 'Next: Compute CSD or Export.'; end
            UIKit.setStatus(app.StatusLabel, sprintf('ERP: averaged %d epochs (%d onsets detected, %d skipped at edges). %s', ...
                nValid, numel(onsetTimes), numel(onsetTimes) - nValid, nextHint), 'success');
        end

        %% computeCSD - Validate spacing / channel order, second spatial derivative
        % Optional spacingUm (um) and order (numeric vector or text) fill
        % the step-4 fields first (programmatic use); [] keeps a field.
        function computeCSD(app, spacingUm, order)
            if isempty(app.LastERP) || isempty(app.LastTime)
                UIKit.alert(app.UIFig, 'No ERP data available. Run ERP analysis first.', 'CSD');
                return;
            end
            if nargin >= 2 && ~isempty(spacingUm), app.SpacingEdit.Value = spacingUm; end
            if nargin >= 3 && ~isempty(order)
                if isnumeric(order), order = num2str(order(:)'); end
                app.ChannelOrderEdit.Value = char(order);
            end

            spacing_um = app.SpacingEdit.Value * 1e-6;  % meters
            if ~isfinite(spacing_um) || spacing_um <= 0
                app.csdInvalid('Inter-electrode spacing must be a positive number.');
                return;
            end
            chan_order = str2double(regexp(strtrim(app.ChannelOrderEdit.Value), '[\s,;]+', 'split'));
            if isempty(chan_order) || any(~isfinite(chan_order))
                app.csdInvalid('Channel order must be a list of channel numbers.');
                return;
            end
            [isMember, reorder] = ismember(chan_order, app.SelectedChannels);
            if ~all(isMember)
                app.csdInvalid(sprintf(['Channel order may only contain channels used in the last ERP ' ...
                    'analysis (%s).'], num2str(app.SelectedChannels)));
                return;
            end
            if numel(chan_order) < 3
                app.csdInvalid('CSD needs at least 3 channels.');
                return;
            end

            % Second spatial derivative (discrete Laplacian) of the ERP in the
            % user's channel order; edge rows replicated (ERPAnalysis.csd)
            csd = ERPAnalysis.csd(app.LastERP, app.SpacingEdit.Value, reorder);
            t   = app.LastTime;

            app.LastCSD = csd;
            app.LastCSDOrder = chan_order;
            app.LastCSDSpacing = app.SpacingEdit.Value;
            app.Exported = false;

            % Plot in the CSD tab
            T = UITheme;
            ax = app.AxCSD;
            resetAxes(ax);
            imagesc(ax, t, 1:length(chan_order), csd);
            colormap(ax, jet);
            cb = colorbar(ax);
            cb.Label.String = 'CSD (amplitude / m^2)';
            m = max(abs(csd(:)));
            if isfinite(m) && m > 0, ax.CLim = [-m m]; end   % symmetric: sinks vs sources
            hold(ax, 'on');
            xline(ax, 0, '--', 'Color', T.sectionTitleColor, 'LineWidth', 1);
            hold(ax, 'off');
            axis(ax, 'tight');
            UIKit.styleAxes(ax, 'Current Source Density (CSD)', 'Time (s)', 'Channel (ordered)');
            ax.XGrid = 'off'; ax.YGrid = 'off';
            ax.YDir = 'reverse';
            ax.YTick = 1:length(chan_order);
            ax.YTickLabel = arrayfun(@(c) sprintf('Ch %d', c), chan_order, 'UniformOutput', false);
            app.Tabs.SelectedTab = app.TabCSD;

            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf('CSD computed over %d channels (%g µm spacing). Next: Export.', ...
                numel(chan_order), app.LastCSDSpacing), 'success');
        end

        %% exportResults - Save ERP (and CSD if computed) to .mat
        % t / y (mean over the ERP channels) are readable by Signal Characterization.
        % With filePath given, no dialog is shown (programmatic use).
        function exportResults(app, filePath)
            if isempty(app.LastERP)
                UIKit.alert(app.UIFig, 'No ERP data available. Run ERP analysis first.', 'Export');
                return;
            end
            if nargin < 2 || isempty(filePath)
                d = ProjectManager.getExportDir();
                if isempty(d) || ~isfolder(d), d = pwd; end
                [~, base] = fileparts(app.FileName);
                if isempty(base), base = 'lfp'; end
                [file, path] = uiputfile('*.mat', 'Export ERP / CSD', fullfile(d, [base '_ERP.mat']));
                figure(app.UIFig);
                if isequal(file, 0)
                    UIKit.setStatus(app.StatusLabel, 'Export cancelled.', 'info');
                    return;
                end
                filePath = fullfile(path, file);
            else
                [~, name, ext] = fileparts(filePath);
                file = [name ext];
            end

            out = struct();
            out.t = app.LastTime;
            out.y = mean(app.LastERP, 1);
            out.erp_avg = app.LastERP;
            out.erp_std = app.LastERPStd;
            out.erp_channels = app.SelectedChannels;
            if ~isempty(app.LFPChannelIDs)
                out.erp_tdt_channels = app.LFPChannelIDs(app.SelectedChannels);
            end
            out.erp_params = app.ERPParams;
            out.n_epochs = app.LastNValid;
            out.onset_times = app.LastOnsetTimes;
            out.lfp_fs = app.Fs_lfp;
            out.source_file = app.FileName;
            if ~isempty(app.LastCSD)
                out.csd = app.LastCSD;
                out.csd_channel_order = app.LastCSDOrder;
                out.csd_spacing_um = app.LastCSDSpacing;
            end

            try
                save(filePath, '-struct', 'out');
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Export failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Export failed:\n%s', ME.message), 'Export');
                return;
            end
            app.Exported = true;
            app.updateControls();
            what = 'ERP';
            if ~isempty(app.LastCSD), what = 'ERP and CSD'; end
            UIKit.setStatus(app.StatusLabel, sprintf('Exported %s to %s.', what, file), 'success');
        end

        %% loadOscillationDemo - Demo LFP plus theta and evoked gamma; channel 4 for step 6
        % Writes core/demo/demoLFPOscillations to DemoData.folder() (always
        % regenerated, so it matches the code) and opens it like loadDemo:
        % all channels selected, CSD 100 um / order 1..8. Returns true on success.
        function ok = loadOscillationDemo(app)
            ok = false;
            dlg = UIKit.busy(app.UIFig, 'Preparing the oscillation demo (takes a few seconds)…');
            try
                ensureDemoPath();
                s = demoLFPOscillations();
                folder = DemoData.folder();
                if ~exist(folder, 'dir'), mkdir(folder); end
                p = fullfile(folder, 'demo_lfp_oscillations.mat');
                save(p, '-struct', 's');
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not create the oscillation demo: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not create the oscillation demo:\n%s', ME.message), 'Demo data');
                return;
            end
            if ~app.openFile(p), return; end
            nChan = size(app.LFP, 1);
            app.setChannels(1:nChan);
            app.SpacingEdit.Value = 100;
            app.ChannelOrderEdit.Value = strjoin(arrayfun(@num2str, 1:nChan, 'UniformOutput', false), ' ');
            app.TFChannelDrop.Value = min(4, nChan);
            app.TFFocus = true;
            app.updateControls();
            try, scroll(app.LeftGrid, 'bottom'); catch, end   % bring step 6 into view
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf(['Oscillation demo loaded: %d channels, %d stimuli; ' ...
                '6 Hz theta (40 µV, every channel, not phase-locked) and a 40 Hz burst (10 µV, 50–250 ms ' ...
                'after each stimulus, channels 3–5). Channel 4 chosen. Next: Spectrum, Spectrogram, ' ...
                'ERSP / ITPC, Band power.'], nChan, numel(s.truth.onsets)), 'success');
        end

        %% runSpectrum - Welch PSD of one channel (Spectrum tab); ch optional
        % ch: LFP row index (default: step-6 channel). Returns true on success.
        function ok = runSpectrum(app, ch)
            ok = false;
            if nargin < 2, ch = []; end
            if ~app.tfPrepare(ch), return; end
            ch = app.TFChannelDrop.Value;
            durS = size(app.LFP, 2) / app.Fs_lfp;
            segSec = min(2, durS / 4);
            dlg = UIKit.busy(app.UIFig, sprintf('Computing the power spectrum of Ch %d…', ch));
            try
                [pxx, f] = TimeFrequency.welchPSD(app.LFP(ch, :), app.Fs_lfp, segSec, 0.5);
                app.LastSpectrum = struct('channel', ch, 'f', f, 'pxx', pxx, 'segSec', segSec);
                app.plotSpectrum();
            catch ME
                UIKit.done(dlg);
                app.tfFailed(sprintf('Spectrum failed: %s', ME.message), 'Spectrum');
                return;
            end
            UIKit.done(dlg);
            app.TFDone.spectrum = true;
            app.TFFocus = true;
            app.Tabs.SelectedTab = app.TabSpectrum;
            app.updateControls();
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf(['Spectrum of Ch %d: Welch PSD, %.3g s Hann segments, ' ...
                '50%% overlap, %.2g Hz resolution. Next: Spectrogram.'], ch, segSec, f(2) - f(1)), 'success');
        end

        %% runSpectrogram - STFT power over the recording with stimulus markers
        % ch: LFP row; fRange: [fmin fmax] Hz (both optional: step-6 fields).
        function ok = runSpectrogram(app, ch, fRange)
            ok = false;
            if nargin < 2, ch = []; end
            if nargin < 3, fRange = []; end
            if ~app.tfPrepare(ch, fRange) || ~app.checkFRange('Spectrogram'), return; end
            ch = app.TFChannelDrop.Value;
            fRange = [app.TFFminEdit.Value, app.TFFmaxEdit.Value];
            winSec = min(0.5, size(app.LFP, 2) / app.Fs_lfp / 4);
            dlg = UIKit.busy(app.UIFig, sprintf('Computing the spectrogram of Ch %d…', ch));
            try
                [P, f, t] = TimeFrequency.stft(app.LFP(ch, :), app.Fs_lfp, winSec, 0.9, fRange);
                onsetTimes = app.stimulusOnsets();
                app.LastSpectrogram = struct('channel', ch, 'f', f, 't', t, 'powerDb', 10 * log10(P), ...
                    'fRange', fRange, 'winSec', winSec, 'onsetTimes', onsetTimes);
                app.plotSpectrogram();
            catch ME
                UIKit.done(dlg);
                app.tfFailed(sprintf('Spectrogram failed: %s', ME.message), 'Spectrogram');
                return;
            end
            UIKit.done(dlg);
            app.TFDone.spectrogram = true;
            app.TFFocus = true;
            app.Tabs.SelectedTab = app.TabSpectrogram;
            app.updateControls();
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf(['Spectrogram of Ch %d, %g–%g Hz (%.3g s Hann windows, ' ...
                '90%% overlap); %d stimulus onsets marked. Next: ERSP / ITPC.'], ch, fRange(1), fRange(2), ...
                winSec, numel(onsetTimes)), 'success');
        end

        %% runERSP - Event-related spectral perturbation (dB) and ITPC around stimuli
        % ch: LFP row; fRange: [fmin fmax] Hz; baseline: [t1 t2] s (all
        % optional: step-6 fields). Frequencies are 1 Hz apart (at most 80),
        % epochs from the step-6 Epoch fields, cycles from Wavelet cycles.
        function ok = runERSP(app, ch, fRange, baseline)
            ok = false;
            if nargin < 2, ch = []; end
            if nargin < 3, fRange = []; end
            if nargin < 4, baseline = []; end
            if ~app.tfPrepare(ch, fRange, baseline) || ~app.checkFRange('ERSP / ITPC'), return; end
            ch = app.TFChannelDrop.Value;
            fRange = [app.TFFminEdit.Value, app.TFFmaxEdit.Value];
            if fRange(1) <= 0
                app.tfFailed('ERSP needs a lowest frequency above 0 Hz (wavelets).', 'ERSP / ITPC');
                return;
            end
            [window, baseline] = app.tfWindows();
            onsetTimes = app.stimulusOnsets();
            if isempty(onsetTimes), app.noOnsets('ERSP / ITPC'); return; end
            nF = max(2, min(80, round(fRange(2) - fRange(1)) + 1));
            freqs = linspace(fRange(1), fRange(2), nF);
            nCycles = app.TFCyclesEdit.Value;
            dlg = UIKit.busy(app.UIFig, sprintf('Computing ERSP / ITPC for Ch %d (%d frequencies × %d stimuli)…', ...
                ch, nF, numel(onsetTimes)));
            try
                [erspDb, itpc, t, info] = TimeFrequency.ersp(app.LFP(ch, :), app.Fs_lfp, onsetTimes, ...
                    window, freqs, baseline, nCycles);
                app.LastERSP = struct('channel', ch, 'freqs', freqs, 't', t, 'erspDb', erspDb, ...
                    'itpc', itpc, 'info', info, 'baseline', baseline, 'window', window, 'nCycles', nCycles);
                app.plotERSP();
            catch ME
                UIKit.done(dlg);
                app.tfFailed(sprintf('ERSP / ITPC failed: %s', ME.message), 'ERSP / ITPC');
                return;
            end
            UIKit.done(dlg);
            app.TFDone.ersp = true;
            app.TFFocus = true;
            app.Tabs.SelectedTab = app.TabERSP;
            app.updateControls();
            ok = true;
            nMin = min(info.nTrialsPerFreq(info.nTrialsPerFreq > 0));
            edgeNote = '';
            if nMin < info.nTrials
                edgeNote = sprintf(' (%d at the lowest frequencies, whose wavelets reach past the recording edges)', nMin);
            end
            UIKit.setStatus(app.StatusLabel, sprintf(['ERSP / ITPC of Ch %d: %d of %d stimuli%s, %g–%g Hz, ' ...
                '%g cycles, baseline %g to %g s. ITPC above %.2f is unlikely by chance at a single point ' ...
                '(Rayleigh p < 0.05). Next: Band power.'], ch, info.nTrials, numel(onsetTimes), edgeNote, ...
                fRange(1), fRange(2), nCycles, baseline(1), baseline(2), sqrt(-log(0.05) / info.nTrials)), 'success');
        end

        %% runBandPower - Band power around stimuli: % change vs baseline, mean ± SEM
        % ch: LFP row (optional). bands (optional; default: ticked rows of
        % the band table): names of table rows, e.g. {'Theta', 'Gamma'};
        % an n x 2 matrix of [low high] Hz; or a struct array with fields
        % name and range. Epoch and baseline come from the step-6 fields.
        function ok = runBandPower(app, ch, bands)
            ok = false;
            if nargin < 2, ch = []; end
            if nargin < 3, bands = []; end
            if ~app.tfPrepare(ch), return; end
            ch = app.TFChannelDrop.Value;
            [names, ranges, msg] = app.resolveBands(bands);
            if ~isempty(msg), app.tfFailed(msg, 'Band power'); return; end
            [window, baseline] = app.tfWindows();
            onsetTimes = app.stimulusOnsets();
            if isempty(onsetTimes), app.noOnsets('Band power'); return; end
            dlg = UIKit.busy(app.UIFig, sprintf('Computing band power for Ch %d (%d bands)…', ch, numel(names)));
            try
                r = TimeFrequency.eventBandPower(app.LFP(ch, :), app.Fs_lfp, onsetTimes, window, ranges, baseline);
                r.channel = ch;
                r.names = names;
                r.baselineWindow = baseline;
                app.LastBandPower = r;
                app.plotBandPower();
            catch ME
                UIKit.done(dlg);
                app.tfFailed(sprintf('Band power failed: %s', ME.message), 'Band power');
                return;
            end
            UIKit.done(dlg);
            app.TFDone.bandpower = true;
            app.TFFocus = true;
            app.Tabs.SelectedTab = app.TabBandPower;
            app.updateControls();
            ok = true;
            % Largest average change from 50 ms after the onset: the evoked
            % potential itself gives a brief, very large broadband change in
            % the first tens of ms, which would otherwise always win
            post = r.t >= 0.05;
            if ~any(post), post = r.t > 0; end
            [pk, iPk] = max(abs(r.mean(:, post)), [], 2);
            [~, b] = max(pk);
            tPost = r.t(post);
            UIKit.setStatus(app.StatusLabel, sprintf(['Band power of Ch %d: %d bands, up to %d stimuli, ' ...
                '%% change vs baseline %g to %g s. Largest change after 50 ms: %s %+.0f%% at %.2f s.'], ch, numel(names), ...
                max(r.nTrials), baseline(1), baseline(2), names{b}, r.mean(b, find(post, 1) - 1 + iPk(b)), ...
                tPost(iPk(b))), 'success');
        end
    end

    methods (Access = private)
        %% tfPrepare - Data loaded? Apply optional channel / fRange / baseline to the step-6 fields
        function ok = tfPrepare(app, ch, fRange, baseline)
            ok = false;
            ttl = 'Time–frequency';
            if isempty(app.LFP)
                UIKit.alert(app.UIFig, 'Load an LFP file first (step 1).', ttl);
                return;
            end
            if nargin >= 2 && ~isempty(ch)
                if ~(isnumeric(ch) && isscalar(ch) && ismember(ch, app.TFChannelDrop.ItemsData))
                    app.tfFailed(sprintf('Channel must be one of 1–%d.', size(app.LFP, 1)), ttl);
                    return;
                end
                app.TFChannelDrop.Value = double(ch);
            end
            if nargin >= 3 && ~isempty(fRange)
                if numel(fRange) ~= 2 || any(~isfinite(fRange)) || fRange(1) < 0 || fRange(1) >= fRange(2)
                    app.tfFailed('The frequency range must be [low high] Hz with 0 <= low < high.', ttl);
                    return;
                end
                app.TFFminEdit.Value = fRange(1);
                app.TFFmaxEdit.Value = fRange(2);
            end
            if nargin >= 4 && ~isempty(baseline)
                if numel(baseline) ~= 2 || any(~isfinite(baseline)) || baseline(1) >= baseline(2)
                    app.tfFailed('The baseline must be [start end] s with start < end.', ttl);
                    return;
                end
                app.TFBaseFromEdit.Value = baseline(1);
                app.TFBaseToEdit.Value = baseline(2);
            end
            ok = true;
        end

        %% checkFRange - Step-6 frequency range: low < high < Nyquist
        function ok = checkFRange(app, ttl)
            ok = false;
            f1 = app.TFFminEdit.Value; f2 = app.TFFmaxEdit.Value; nyq = app.Fs_lfp / 2;
            if f1 >= f2
                app.tfFailed(sprintf('The lowest frequency (%g Hz) must be below the highest (%g Hz).', f1, f2), ttl);
            elseif f2 >= nyq
                app.tfFailed(sprintf(['The highest frequency must be below the Nyquist frequency ' ...
                    '(%g Hz, half the sampling rate).'], nyq), ttl);
            else
                ok = true;
            end
        end

        %% tfWindows - Epoch and baseline windows (s) from the step-6 fields
        function [window, baseline] = tfWindows(app)
            window = [app.TFEpochFromEdit.Value, app.TFEpochToEdit.Value];
            baseline = [app.TFBaseFromEdit.Value, app.TFBaseToEdit.Value];
        end

        %% onsetParams - Threshold / min ISI of the last ERP, else the defaults
        function p = onsetParams(app)
            p = app.DefaultOnsetParams;
            if ~isempty(app.ERPParams)
                p.threshold = app.ERPParams.threshold;
                p.minISI = app.ERPParams.minISI;
            end
        end

        %% stimulusOnsets - Onset times (s) with the ERP detection settings
        function onsetTimes = stimulusOnsets(app)
            p = app.onsetParams();
            try
                onsetTimes = ERPAnalysis.detectOnsets(app.Stim, app.Fs_stim, p.threshold, p.minISI);
            catch
                onsetTimes = zeros(1, 0);   % e.g. a multi-row stimulus: reported as "no onsets"
            end
        end

        %% noOnsets - No stimulus onsets for an event-related step: show the stimulus, explain
        function noOnsets(app, ttl)
            p = app.onsetParams();
            app.plotStimulus(p.threshold, []);
            app.Tabs.SelectedTab = app.TabStim;
            app.tfFailed(sprintf(['No stimulus onsets detected (threshold %g on the mean-subtracted ' ...
                'stimulus, min ISI %g s). %s uses the ERP settings: run the ERP (step 3) with a ' ...
                'threshold that suits the Stimulus tab first.'], p.threshold, p.minISI, ttl), ttl);
        end

        %% tfFailed - Time-frequency step failed: status + alert
        function tfFailed(app, msg, ttl)
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, msg, 'error');
            UIKit.alert(app.UIFig, msg, ttl);
        end

        %% tableBands - Names, [low high] rows and Plot ticks of the band table
        function [names, ranges, plotMask] = tableBands(app)
            d = app.BandTable.Data;
            if istable(d), d = table2cell(d); end
            names = cellfun(@(v) char(string(v)), d(:, 1)', 'UniformOutput', false);
            ranges = cell2mat(d(:, 2:3));
            plotMask = logical(cell2mat(d(:, 4)))';
        end

        %% resolveBands - bands argument of runBandPower -> names, n x 2 ranges, error text
        function [names, ranges, msg] = resolveBands(app, bands)
            msg = '';
            [tNames, tRanges, tPlot] = app.tableBands();
            fromTable = false;
            if isempty(bands)
                names = tNames(tPlot);
                ranges = tRanges(tPlot, :);
                if isempty(names)
                    msg = 'Tick Plot for at least one band in the band table (step 6).';
                    return;
                end
            elseif isstruct(bands) && all(isfield(bands, {'name', 'range'}))
                names = cellfun(@char, {bands.name}, 'UniformOutput', false);
                ranges = vertcat(bands.range);
            elseif isnumeric(bands)
                ranges = double(bands);
                if size(ranges, 2) ~= 2
                    msg = 'Numeric bands must be an n x 2 matrix of [low high] limits (Hz).';
                    return;
                end
                names = arrayfun(@(k) sprintf('%g–%g Hz', ranges(k, 1), ranges(k, 2)), ...
                    1:size(ranges, 1), 'UniformOutput', false);
                for k = 1:size(ranges, 1)   % reuse the table name when the limits match a row
                    m = find(all(abs(tRanges - ranges(k, :)) < 1e-9, 2), 1);
                    if ~isempty(m), names{k} = tNames{m}; end
                end
            else
                try
                    req = cellstr(bands);
                catch
                    msg = 'Bands must be band names, an n x 2 matrix of limits (Hz) or a struct with name / range.';
                    return;
                end
                names = cell(1, numel(req)); ranges = zeros(numel(req), 2);
                for k = 1:numel(req)
                    m = find(strcmpi(tNames, strtrim(req{k})), 1);
                    if isempty(m)
                        msg = sprintf('Unknown band "%s". Bands in the table: %s.', req{k}, strjoin(tNames, ', '));
                        return;
                    end
                    names{k} = tNames{m}; ranges(k, :) = tRanges(m, :);
                end
                fromTable = true;
            end
            if isempty(ranges) || any(~isfinite(ranges(:))) || any(ranges(:, 1) < 0) || any(ranges(:, 1) >= ranges(:, 2))
                msg = 'Each band needs limits 0 <= low < high (Hz).';
            elseif any(ranges(:, 1) >= app.Fs_lfp / 2)
                msg = sprintf('Bands must start below the Nyquist frequency (%g Hz).', app.Fs_lfp / 2);
            elseif fromTable
                % Show the requested bands as the ticked ones
                d = app.BandTable.Data;
                if ~istable(d)
                    d(:, 4) = num2cell(ismember(lower(tNames), lower(names)))';
                    app.BandTable.Data = d;
                end
            end
            names = names(:)';
        end

        %% onBandEdited - Validate a band-table edit; restore the old value if invalid
        function onBandEdited(app, src, evt)
            r = evt.Indices(1); c = evt.Indices(2);
            d = src.Data;
            if istable(d), return; end
            bad = '';
            if c == 1 && isempty(strtrim(char(string(evt.NewData))))
                bad = 'A band needs a name.';
            elseif c == 2 || c == 3
                v = evt.NewData;
                if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0)
                    bad = 'Band limits must be numbers >= 0 (Hz).';
                elseif d{r, 2} >= d{r, 3}
                    bad = sprintf('The low limit must be below the high limit (row %d).', r);
                end
            end
            if ~isempty(bad)
                d{r, c} = evt.PreviousData;
                src.Data = d;
                UIKit.setStatus(app.StatusLabel, [bad ' The previous value was restored.'], 'warning');
            elseif c <= 3
                UIKit.setStatus(app.StatusLabel, sprintf('Band %s set to %g–%g Hz.', ...
                    char(string(d{r, 1})), d{r, 2}, d{r, 3}), 'info');
            end
        end

        %% tfPlaceholders - Empty time-frequency views with a hint
        function tfPlaceholders(app)
            for ax = [app.AxSpectrum, app.AxSpectrogram, app.AxERSP, app.AxITPC]
                resetAxes(ax);
            end
            UIKit.emptyAxes(app.AxSpectrum, 'Time–frequency (step 6): click Spectrum');
            UIKit.emptyAxes(app.AxSpectrogram, 'Time–frequency (step 6): click Spectrogram');
            UIKit.emptyAxes(app.AxERSP, 'Step 6: click ERSP / ITPC');
            UIKit.emptyAxes(app.AxITPC, 'Step 6: click ERSP / ITPC');
            app.bandPlaceholder('Time–frequency (step 6): click Band power');
        end

        %% bandPlaceholder - Empty tile with a hint in the Band power tab
        function bandPlaceholder(app, msg)
            delete(app.BandContainer.Children);
            tl = tiledlayout(app.BandContainer, 1, 1, 'Padding', 'compact');
            UIKit.emptyAxes(nexttile(tl), msg);
        end

        %% plotSpectrum - Welch PSD on log-log axes, conventional bands shaded
        function plotSpectrum(app)
            T = UITheme;
            S = app.LastSpectrum;
            ax = app.AxSpectrum;
            resetAxes(ax);
            keep = S.f > 0 & S.pxx > 0;
            f = S.f(keep); p = S.pxx(keep);
            yl = [min(p) / 2, max(p) * 2];
            [names, ranges] = app.tableBands();
            nC = size(T.plotColors, 1);
            hold(ax, 'on');
            for b = 1:numel(names)
                lo = max(ranges(b, 1), f(1)); hi = min(ranges(b, 2), f(end));
                if ~(lo < hi), continue; end
                c = T.plotColors(mod(b - 1, nC) + 1, :);
                patch(ax, [lo hi hi lo], [yl(1) yl(1) yl(2) yl(2)], c, 'FaceAlpha', 0.08, 'EdgeColor', 'none');
                text(ax, sqrt(lo * hi), yl(2) / 1.8, names{b}, 'HorizontalAlignment', 'center', ...
                    'FontSize', T.fontTiny, 'Color', c, 'Interpreter', 'none');
            end
            plot(ax, f, p, 'Color', T.plotColors(1, :), 'LineWidth', 1);
            hold(ax, 'off');
            ax.XScale = 'log'; ax.YScale = 'log';
            ax.XLim = [f(1) f(end)]; ax.YLim = yl;
            UIKit.styleAxes(ax, sprintf('Power spectrum · Ch %d (Welch, %.3g s Hann segments, 50%% overlap)', ...
                S.channel, S.segSec), 'Frequency (Hz)', 'PSD (units^2/Hz)');
        end

        %% plotSpectrogram - STFT power (dB) image with dashed stimulus onsets
        function plotSpectrogram(app)
            T = UITheme;
            S = app.LastSpectrogram;
            ax = app.AxSpectrogram;
            resetAxes(ax);
            imagesc(ax, S.t, S.f, S.powerDb);
            ax.YDir = 'normal';
            colormap(ax, parula(256));
            cb = colorbar(ax);
            cb.Label.String = 'Power (dB: 10·log_{10} units^2/Hz)';
            v = sort(S.powerDb(isfinite(S.powerDb)));
            if numel(v) > 1
                lim = [v(max(1, round(0.01 * numel(v)))), v(max(1, round(0.995 * numel(v))))];
                if lim(2) > lim(1), ax.CLim = lim; end
            end
            if ~isempty(S.onsetTimes)
                hold(ax, 'on');
                n = numel(S.onsetTimes);
                x = [S.onsetTimes(:)'; S.onsetTimes(:)'; nan(1, n)];
                y = repmat([S.f(1); S.f(end); NaN], 1, n);
                plot(ax, x(:), y(:), '--', 'Color', T.stimColor, 'LineWidth', 1);
                hold(ax, 'off');
            end
            axis(ax, 'tight');
            UIKit.styleAxes(ax, sprintf('Spectrogram · Ch %d (%.3g s Hann windows, 90%% overlap; dashed: %d stimuli)', ...
                S.channel, S.winSec, numel(S.onsetTimes)), 'Time (s)', 'Frequency (Hz)');
            ax.XGrid = 'off'; ax.YGrid = 'off';
            ax.Layer = 'top';
        end

        %% plotERSP - ERSP (dB, diverging, centred at 0) and ITPC (0..1) side by side
        function plotERSP(app)
            T = UITheme;
            E = app.LastERSP;
            ax = app.AxERSP;
            resetAxes(ax);
            h = imagesc(ax, E.t, E.freqs, E.erspDb);
            h.AlphaData = double(isfinite(E.erspDb));   % frequencies without trials stay blank
            ax.YDir = 'normal';
            colormap(ax, divergingMap(256));
            cb = colorbar(ax);
            cb.Label.String = 'ERSP (dB vs baseline)';
            m = robustAbsMax(E.erspDb, 0.99);
            ax.CLim = [-m m];
            hold(ax, 'on');
            xline(ax, 0, '--', 'Color', T.stimColor, 'LineWidth', 1.2);
            xline(ax, E.baseline(1), ':', 'Color', T.sectionTitleColor, 'LineWidth', 1);
            xline(ax, E.baseline(2), ':', 'Color', T.sectionTitleColor, 'LineWidth', 1);
            hold(ax, 'off');
            axis(ax, 'tight');
            UIKit.styleAxes(ax, sprintf('ERSP · Ch %d (%d trials; dotted: baseline)', E.channel, E.info.nTrials), ...
                'Time from stimulus (s)', 'Frequency (Hz)');
            ax.XGrid = 'off'; ax.YGrid = 'off';
            ax.Layer = 'top';

            ax = app.AxITPC;
            resetAxes(ax);
            h = imagesc(ax, E.t, E.freqs, E.itpc);
            h.AlphaData = double(isfinite(E.itpc));
            ax.YDir = 'normal';
            colormap(ax, parula(256));
            cb = colorbar(ax);
            cb.Label.String = 'ITPC (0–1)';
            ax.CLim = [0 1];
            hold(ax, 'on');
            xline(ax, 0, '--', 'Color', T.stimColor, 'LineWidth', 1.2);
            hold(ax, 'off');
            axis(ax, 'tight');
            UIKit.styleAxes(ax, sprintf('Inter-trial phase coherence · Ch %d', E.channel), ...
                'Time from stimulus (s)', 'Frequency (Hz)');
            ax.XGrid = 'off'; ax.YGrid = 'off';
            ax.Layer = 'top';
        end

        %% plotBandPower - One tile per band: % change vs baseline, mean ± SEM
        function plotBandPower(app)
            T = UITheme;
            r = app.LastBandPower;
            delete(app.BandContainer.Children);
            tl = tiledlayout(app.BandContainer, 'flow', 'TileSpacing', 'compact', 'Padding', 'compact');
            nC = size(T.plotColors, 1);
            for b = 1:numel(r.names)
                ax = nexttile(tl);
                ttl = sprintf('%s %g–%g Hz (n = %d)', r.names{b}, r.bands(b, 1), r.bands(b, 2), r.nTrials(b));
                if r.nTrials(b) == 0
                    UIKit.emptyAxes(ax, 'No epochs far enough from the recording edges');
                    title(ax, ttl, 'Interpreter', 'none');
                    continue;
                end
                c = T.plotColors(mod(b - 1, nC) + 1, :);
                up = r.mean(b, :) + r.sem(b, :);
                lo = r.mean(b, :) - r.sem(b, :);
                hold(ax, 'on');
                fill(ax, [r.t fliplr(r.t)], [up fliplr(lo)], c, 'FaceAlpha', 0.2, 'EdgeColor', 'none');
                plot(ax, r.t, r.mean(b, :), 'Color', c, 'LineWidth', 1.2);
                xline(ax, 0, '--', 'Color', T.stimColor, 'LineWidth', 1);
                yline(ax, 0, ':', 'Color', T.bodyColor, 'LineWidth', 1);
                hold(ax, 'off');
                axis(ax, 'tight');
                UIKit.styleAxes(ax, ttl);
            end
            tl.Title.String = sprintf('Band power · Ch %d: %% change vs baseline (%g to %g s), mean ± SEM over trials', ...
                r.channel, r.baselineWindow(1), r.baselineWindow(2));
            tl.Title.FontWeight = 'bold';
            tl.Title.Color = T.sectionTitleColor;
            tl.XLabel.String = 'Time from stimulus (s)';
            tl.YLabel.String = 'Power change (%)';
        end

        %% plotStimulus - Mean-subtracted stimulus; optional threshold and onsets
        function plotStimulus(app, threshold, onsetTimes)
            T = UITheme;
            ax = app.AxStim;
            resetAxes(ax);
            stim = app.Stim - mean(app.Stim);
            plot(ax, app.t_stim, stim, 'Color', T.stimColor, 'DisplayName', 'Stimulus');
            ttl = 'Stimulus (mean-subtracted)';
            if nargin >= 2 && ~isempty(threshold)
                hold(ax, 'on');
                yline(ax, threshold, '--', 'Color', T.plotColors(2,:), 'LineWidth', 1, ...
                    'DisplayName', sprintf('Threshold (%g)', threshold));
                if nargin >= 3 && ~isempty(onsetTimes)
                    plot(ax, onsetTimes, repmat(threshold, size(onsetTimes)), 'v', ...
                        'Color', T.plotColors(1,:), 'MarkerFaceColor', T.plotColors(1,:), ...
                        'MarkerSize', 5, 'LineStyle', 'none', 'DisplayName', 'Detected onsets');
                    ttl = sprintf('Stimulus: %d onsets detected', numel(onsetTimes));
                else
                    ttl = 'Stimulus: no onsets above the threshold';
                end
                hold(ax, 'off');
                lg = legend(ax); lg.Location = 'northeast'; lg.Box = 'off';
            end
            axis(ax, 'tight');
            UIKit.styleAxes(ax, ttl, 'Time (s)', 'Stimulus (units)');
        end

        %% plotOverlay - All selected channels' ERPs in one axes
        function plotOverlay(app, t, erpAvg, chIdx, nValid)
            T = UITheme;
            ax = app.AxOverlay;
            resetAxes(ax);
            hold(ax, 'on');
            nC = size(T.plotColors, 1);
            styles = {'-', '--', ':'};
            for i = 1:length(chIdx)
                plot(ax, t, erpAvg(i,:), 'Color', T.plotColors(mod(i-1, nC) + 1, :), ...
                    'LineStyle', styles{mod(floor((i-1) / nC), numel(styles)) + 1}, ...
                    'LineWidth', 1, 'DisplayName', sprintf('Ch %d', chIdx(i)));
            end
            xline(ax, 0, '--', 'Color', T.stimColor, 'LineWidth', 1, 'DisplayName', 'Stimulus onset');
            hold(ax, 'off');
            axis(ax, 'tight');
            UIKit.styleAxes(ax, sprintf('ERP overlay (%d epochs)', nValid), 'Time (s)', 'Amplitude (V)');
            lg = legend(ax); lg.Location = 'eastoutside'; lg.Box = 'off';
        end

        %% plotPerChannel - One tile per channel: mean ± SD (shaded) and onset line
        function plotPerChannel(app, t, erpAvg, erpStd, chIdx, nValid)
            T = UITheme;
            delete(app.AxContainer.Children);
            tl = tiledlayout(app.AxContainer, 'flow', 'TileSpacing', 'compact', 'Padding', 'compact');
            for i = 1:length(chIdx)
                ax = nexttile(tl);
                hold(ax, 'on');
                upper = erpAvg(i,:) + erpStd(i,:);
                lower = erpAvg(i,:) - erpStd(i,:);
                fill(ax, [t fliplr(t)], [upper fliplr(lower)], T.shadeColor, ...
                    'FaceAlpha', 0.2, 'EdgeColor', 'none');
                plot(ax, t, erpAvg(i,:), 'Color', T.plotColors(1,:), 'LineWidth', 1);
                xline(ax, 0, '--', 'Color', T.stimColor, 'LineWidth', 1);
                hold(ax, 'off');
                axis(ax, 'tight');
                UIKit.styleAxes(ax, sprintf('Ch %d', chIdx(i)));
            end
            tl.Title.String = sprintf('ERP per channel: mean ± SD (%d epochs)', nValid);
            tl.Title.FontWeight = 'bold';
            tl.Title.Color = T.sectionTitleColor;
            tl.XLabel.String = 'Time (s)';
            tl.YLabel.String = 'Amplitude (V)';
        end

        %% channelPlaceholder - Empty tile with a hint in the per-channel tab
        function channelPlaceholder(app, msg)
            delete(app.AxContainer.Children);
            tl = tiledlayout(app.AxContainer, 1, 1, 'Padding', 'compact');
            UIKit.emptyAxes(nexttile(tl), msg);
        end

        %% erpFailed - ERP could not be computed: status + alert
        function erpFailed(app, msg)
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, msg, 'error');
            UIKit.alert(app.UIFig, msg, 'ERP Analysis');
        end

        %% csdInvalid - Invalid CSD input: status + alert
        function csdInvalid(app, msg)
            UIKit.setStatus(app.StatusLabel, msg, 'error');
            UIKit.alert(app.UIFig, msg, 'CSD Parameters');
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

%% Local helper: clear axes incl. legend/colorbar and reset tick modes
% (UIKit.emptyAxes fixes XTick/YTick to [], so plots must start from a reset)
function resetAxes(ax)
    legend(ax, 'off');
    colorbar(ax, 'off');
    cla(ax, 'reset');
end

%% Local helper: padded 1x1 grid inside a tab (room for titles and labels)
function g = tabGrid(tab)
    T = UITheme;
    g = uigridlayout(tab, [1 1], 'Padding', [8 8 8 8], 'BackgroundColor', T.cardBg);
end

%% Local helper: small wrapped info text inside a card
function lbl = infoLabel(parent, text)
    T = UITheme;
    lbl = uilabel(parent, 'Text', text, 'FontSize', T.fontSmall, 'FontColor', T.bodyColor, ...
        'WordWrap', 'on', 'VerticalAlignment', 'top', 'Interpreter', 'none');
end

%% Local helper: set Enable on a cell array of components
function setEnable(ctrls, tf)
    for k = 1:numel(ctrls)
        ctrls{k}.Enable = onOff(tf);
    end
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

%% Local helper: "Label | [from] – [to]" row of two numeric fields in a 2-column grid
function [f1, f2] = rangeField(grid, labelText, v1, v2, tooltip)
    T = UITheme;
    uilabel(grid, 'Text', labelText, 'FontSize', T.fontBody, ...
        'FontColor', T.sectionTitleColor, 'Tooltip', tooltip);
    rg = uigridlayout(grid, [1 3], 'ColumnWidth', {'1x', 10, '1x'}, 'Padding', [0 0 0 0], ...
        'ColumnSpacing', 2, 'BackgroundColor', T.cardBg);
    f1 = uieditfield(rg, 'numeric', 'Value', v1, 'Tooltip', tooltip);
    uilabel(rg, 'Text', '–', 'HorizontalAlignment', 'center', 'FontColor', T.bodyColor);
    f2 = uieditfield(rg, 'numeric', 'Value', v2, 'Tooltip', tooltip);
end

%% Local helper: diverging colormap theme blue -> white -> theme vermillion (white = 0)
function cmap = divergingMap(n)
    T = UITheme;
    h = floor(n / 2);
    a = linspace(0, 1, h + 1)';
    white = T.cardBg;
    neg = T.plotColors(1, :) + (white - T.plotColors(1, :)) .* a;
    pos = white + (T.plotColors(2, :) - white) .* a;
    cmap = [neg; pos(2:end, :)];
end

%% Local helper: q-quantile of |x| over finite values (colour limits robust to outliers)
function m = robustAbsMax(x, q)
    v = sort(abs(x(isfinite(x))));
    m = 1;
    if ~isempty(v)
        m = v(max(1, ceil(q * numel(v))));
    end
    if ~(isfinite(m) && m > 0), m = 1; end
end

%% Local helper: put core/demo on the path (demo generators live there)
function ensureDemoPath()
    if exist('demoLFPOscillations', 'file') ~= 2
        addpath(fullfile(fileparts(which('DemoData')), 'demo'));
    end
end

%% Local helper: 'on'/'off' from a logical
function s = onOff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end

%% Local helper: "612.0 s" / "10.2 min" duration text
function s = fmtDuration(sec)
    if sec >= 120
        s = sprintf('%.1f min', sec / 60);
    else
        s = sprintf('%.1f s', sec);
    end
end
