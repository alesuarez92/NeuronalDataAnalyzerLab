%% ExtractLDFApp.m
% =========================================================================
% EXTRACT LDF DATA - LOAD, CROP, AND SAVE LDF EXPORT FILES
% =========================================================================
% Sub-app launched from Main. Built with UIKit.window: numbered step cards
% on the left (1 Load, 2 Time range, 3 Crop, 4 Save), stimulus and LDF
% plots on the right. Loads any recording SignalSource reads (LabChart
% .mat / text export, AcqKnowledge .acq / .mat / text, Spike2 .mat,
% delimited text, a cropped LDF .mat); step 1 then offers the flow
% channel, the stimulus (a channel, the comments / markers, or none) and
% the block, guessed from the channel names (SignalSource.guessChannels).
% Lets the user choose a time range (typed Start/End in
% seconds, or two clicks on either plot via "Pick on plot"), shows the
% range as a shaded region, crops with Processor.crop() after
% Validation.cropRange(), shows the cropped signals in the same axes and
% saves them via Exporter.saveCropped(). updateButtonStates() enables
% each action from the data state and makes the next step the primary
% button. Header "? Help" opens HelpApp on the "LDF Extract" tab.
% "Try demo data" (loadDemo) opens DemoData's synthetic export and
% pre-fills the range 20-280 s. Programmatic use (no dialogs): openFile(path)
% (openFile(path, fs) for a text file without a time column),
% selectSignals(flow, stim, block), setRange(start, end), processData(),
% saveCroppedTo(path).
% Sessions (step 4 buttons; core/Session.m, core/Report.m):
% saveSessionTo(path, notes), openSession(path), makeReport(pdfPath),
% sessionState(), restoreSession(s). A session stores the recording
% (with MD5), its format, the flow channel, the stimulus, the block, the
% Start/End range, the crop and the view.
% =========================================================================

classdef ExtractLDFApp < handle

    %% PROPERTIES
    % ---------------------------------------------------------------------
    % UI handles, data (AppData) and range-picking state
    % ---------------------------------------------------------------------
    properties
        UIFig           % Main uifigure (UIKit.window)
        HeaderPanel     % Header bar (title, subtitle, Help)
        HelpBtn         % Opens HelpApp('LDF Extract')
        StatusLabel     % Status bar label (UIKit.setStatus)
        LoadBtn         % Step 1: load a recording (SignalSource formats)
        DemoBtn         % Step 1: load synthetic demo export (DemoData)
        FileInfoLabel   % Step 1: file name, format, rate, duration, channels
        FlowDropDown    % Step 1: flow (LDF) channel (ItemsData = channel number)
        StimDropDown    % Step 1: stimulus (ItemsData = index into StimValues)
        BlockDropDown   % Step 1: block / recording period (ItemsData = block)
        StartInput      % Step 2: numeric start time (s)
        EndInput        % Step 2: numeric end time (s)
        SelectRangeBtn  % Step 2: pick start/end by clicking a plot
        FullRangeBtn    % Step 2: reset range to the whole recording
        ProcessBtn      % Step 3: crop to the range
        ViewDropDown    % Step 3: show full recording or cropped segment
        CropInfoLabel   % Step 3: summary of the current crop
        SaveCroppedBtn  % Step 4: save cropped data to .mat
        AxStim          % uiaxes for stimulus
        AxLDF           % uiaxes for LDF
        AppData         % Struct: RawStim, RawLDF, ProcessedStim, ProcessedLDF,
                        %         TimeVector, SamplingRate, FilePath, Metadata
        CropRange = []  % [start end] (s) used for the current ProcessedStim/LDF
        PickState = 0   % 0 = idle, 1 = waiting for START click, 2 = waiting for END
        PickStart = NaN % Time (s) of the first click while picking
        RangeGfx        % Shaded range patches on both axes
        PickGfx         % Start marker lines shown while picking
        SessionBtns     % Step 4: Save session / Open session / Report (UIKit.sessionButtons)
        Rec = []        % SignalSource recording of the loaded file
        StimValues = {} % SignalSource.stimItems values (channel number, 'events...', 0)
        Selection = struct('flow', [], 'stim', [], 'block', 1)  % signals shown now
    end

    methods
        %% Constructor - Initialize AppData and build UI
        % -------------------------------------------------------------
        function app = ExtractLDFApp()
            app.AppData = struct('RawStim', [], 'RawLDF', [], ...
                                 'ProcessedStim', [], 'ProcessedLDF', [], ...
                                 'TimeVector', [], 'SamplingRate', 1000, ...
                                 'FilePath', '', 'Metadata', struct(), ...
                                 'FlowName', '', 'FlowUnits', '', 'StimName', '', 'Format', '');
            app.RangeGfx = gobjects(0);
            app.PickGfx  = gobjects(0);
            app.buildUI();
        end

        %% buildUI - Window, step cards (left) and stimulus/LDF axes (right)
        % -------------------------------------------------------------
        % Cards: 1 Load file | 2 Time range (Start/End, Pick on plot, Full
        % range) | 3 Crop (Crop, View) | 4 Save. Axes show placeholders
        % until a file is loaded. Ends with updateButtonStates().
        % -------------------------------------------------------------
        function buildUI(app)
            T = UITheme;
            W = UIKit.window('Extract LDF Data', ...
                'Load a recording, choose the LDF and stimulus, a time window, crop it and save it', ...
                'LDF Extract', [1150 740]);
            app.UIFig = W.Fig;
            app.HeaderPanel = W.Header;
            app.HelpBtn = W.HelpBtn;
            app.StatusLabel = W.Status;
            W.Body.RowHeight = {'1x'};
            W.Body.ColumnWidth = {300, '1x'};

            left = uigridlayout(W.Body, [5 1], 'Padding', [0 0 0 0], 'RowSpacing', 10, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            heights = cell(1, 5);

            % --- 1 Load file ---
            [p, g, heights{1}] = stepCard(left, 1, 'Load recording', {T.buttonHeight, T.buttonHeight, 60, ...
                T.controlHeight, T.controlHeight, T.controlHeight});
            p.Layout.Row = 1;
            app.LoadBtn = UIKit.button(g, 'Load file...', @(~,~)app.loadFile(), 'primary', ...
                ['Load a recording: LabChart .mat or text export, AcqKnowledge .acq / .mat / text, Spike2 .mat ' ...
                'export, a .txt / .csv table or a cropped LDF .mat']);
            app.LoadBtn.Layout.Row = 2; app.LoadBtn.Layout.Column = [1 2];
            app.DemoBtn = UIKit.button(g, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Load a synthetic 300 s LabChart export with known answers (9 stimuli of 5 s every 30 s ' ...
                'on channel 6, LDF with a +30 PU response peaking 4 s after each onset on channel 8)']);
            app.DemoBtn.Layout.Row = 3; app.DemoBtn.Layout.Column = [1 2];
            app.FileInfoLabel = infoLabel(g, 'No file loaded', ...
                'File name, format, sampling rate, duration and channels');
            app.FileInfoLabel.Layout.Row = 4; app.FileInfoLabel.Layout.Column = [1 2];
            app.FlowDropDown = addField(g, 5, 'LDF', 'dropdown', {{'(load a file)'}, '(load a file)'}, ...
                'Channel with the laser Doppler flow (perfusion) signal; guessed from the channel names');
            app.StimDropDown = addField(g, 6, 'Stimulus', 'dropdown', {{'(load a file)'}, '(load a file)'}, ...
                ['Stimulus trigger: a channel, the comments / event markers of the file (each one becomes ' ...
                'a 0.5 s pulse), or None']);
            app.BlockDropDown = addField(g, 7, 'Block', 'dropdown', {{'(load a file)'}, '(load a file)'}, ...
                'Recording period (LabChart block) to use when the file has several');
            app.FlowDropDown.ValueChangedFcn = @(~,~)app.signalsChanged();
            app.StimDropDown.ValueChangedFcn = @(~,~)app.signalsChanged();
            app.BlockDropDown.ValueChangedFcn = @(~,~)app.signalsChanged();

            % --- 2 Time range ---
            [p, g, heights{2}] = stepCard(left, 2, 'Choose time range', ...
                {52, T.controlHeight, T.controlHeight, T.buttonHeight});
            p.Layout.Row = 2;
            h = UIKit.hint(g, 'Type Start/End, or click "Pick on plot" and then click the start and end on either plot.');
            h.Parent.Parent.Layout.Row = 2; h.Parent.Parent.Layout.Column = [1 2];
            app.StartInput = addField(g, 3, 'Start (s)', 'numeric', 0, ...
                'Start of the window to keep, in seconds from the start of the recording', [0 Inf]);
            app.EndInput = addField(g, 4, 'End (s)', 'numeric', 0, ...
                'End of the window to keep, in seconds from the start of the recording', [0 Inf]);
            app.StartInput.ValueDisplayFormat = '%.3f';
            app.EndInput.ValueDisplayFormat = '%.3f';
            app.StartInput.ValueChangedFcn = @(~,~)app.rangeChanged();
            app.EndInput.ValueChangedFcn = @(~,~)app.rangeChanged();
            app.SelectRangeBtn = UIKit.button(g, 'Pick on plot', @(~,~)app.selectRangeInteractive(), ...
                'secondary', 'Click the start and then the end of the window on the stimulus or LDF plot (click again to cancel)');
            app.SelectRangeBtn.Layout.Row = 5; app.SelectRangeBtn.Layout.Column = 1;
            app.FullRangeBtn = UIKit.button(g, 'Full range', @(~,~)app.resetRange(), ...
                'secondary', 'Set Start/End to the whole recording');
            app.FullRangeBtn.Layout.Row = 5; app.FullRangeBtn.Layout.Column = 2;

            % --- 3 Crop ---
            [p, g, heights{3}] = stepCard(left, 3, 'Crop', {T.buttonHeight, T.controlHeight, 34});
            p.Layout.Row = 3;
            app.ProcessBtn = UIKit.button(g, 'Crop to range', @(~,~)app.processData(), ...
                'secondary', 'Keep only the samples between Start and End and show them on the plots');
            app.ProcessBtn.Layout.Row = 2; app.ProcessBtn.Layout.Column = [1 2];
            app.ViewDropDown = addField(g, 3, 'Show', 'dropdown', ...
                {{'Full recording', 'Cropped segment'}, 'Full recording'}, ...
                'Choose whether the plots show the whole recording or the cropped segment');
            app.ViewDropDown.ValueChangedFcn = @(~,~)app.viewChanged();
            app.CropInfoLabel = infoLabel(g, 'Not cropped yet', 'Summary of the current crop');
            app.CropInfoLabel.Layout.Row = 4; app.CropInfoLabel.Layout.Column = [1 2];

            % --- 4 Save ---
            [p, g, heights{4}] = stepCard(left, 4, 'Save', {T.buttonHeight, 34, UIKit.sessionButtonsHeight()});
            p.Layout.Row = 4;
            app.SaveCroppedBtn = UIKit.button(g, 'Save cropped data...', @(~,~)app.saveCroppedData(), ...
                'secondary', 'Save cropped stim, LDF, time vector (t) and sampling rate (Fs) to a .mat file');
            app.SaveCroppedBtn.Layout.Row = 2; app.SaveCroppedBtn.Layout.Column = [1 2];
            note = infoLabel(g, 'Output (stim, LDF, t, Fs) opens in LDF Processing.', ...
                'The saved file is the input of the LDF Processing window');
            note.Layout.Row = 3; note.Layout.Column = [1 2];
            app.SessionBtns = UIKit.sessionButtons(g, app);
            app.SessionBtns.Grid.Layout.Row = 4; app.SessionBtns.Grid.Layout.Column = [1 2];

            heights{5} = '1x';
            left.RowHeight = heights;

            % --- Plots ---
            plotCard = UIKit.card(W.Body, '');
            plotCard.Layout.Row = 1; plotCard.Layout.Column = 2;
            axGrid = uigridlayout(plotCard, [2 1], 'RowHeight', {'1x', '1x'}, ...
                'Padding', [8 8 14 8], 'RowSpacing', 8, 'BackgroundColor', T.cardBg);
            app.AxStim = uiaxes(axGrid);
            app.AxLDF  = uiaxes(axGrid);
            % styleAxes first: it removes emptyAxes placeholders
            UIKit.styleAxes(app.AxStim, 'Stimulus');
            UIKit.styleAxes(app.AxLDF, 'LDF');
            UIKit.emptyAxes(app.AxStim, 'Load a file (or Try demo data) to begin');
            UIKit.emptyAxes(app.AxLDF, 'LDF signal appears here');

            UIKit.setStatus(app.StatusLabel, 'Step 1: load a recording (LabChart, AcqKnowledge, Spike2 or a table).', 'info');
            app.updateButtonStates();
        end

        %% updateButtonStates - Enable controls and pick the primary button
        % -------------------------------------------------------------
        % Range controls and Crop need raw data. Save needs a crop that
        % matches the current Start/End (a changed range must be cropped
        % again). Primary: Load -> Crop -> Save.
        % -------------------------------------------------------------
        function updateButtonStates(app)
            hasRaw = ~isempty(app.AppData.RawStim) && ~isempty(app.AppData.RawLDF);
            hasCropped = ~isempty(app.AppData.ProcessedStim) && ~isempty(app.AppData.ProcessedLDF);
            cropCurrent = hasCropped && isequal(app.CropRange, app.currentRange());
            picking = app.PickState > 0;

            app.StartInput.Enable     = onoff(hasRaw && ~picking);
            app.EndInput.Enable       = onoff(hasRaw && ~picking);
            app.SelectRangeBtn.Enable = onoff(hasRaw);
            app.FullRangeBtn.Enable   = onoff(hasRaw && ~picking);
            app.ProcessBtn.Enable     = onoff(hasRaw && ~picking);
            app.ViewDropDown.Enable   = onoff(hasCropped && ~picking);
            app.SaveCroppedBtn.Enable = onoff(cropCurrent && ~picking);
            app.LoadBtn.Enable        = onoff(~picking);
            hasRec = ~isempty(app.Rec);
            app.FlowDropDown.Enable   = onoff(hasRec && ~picking);
            app.StimDropDown.Enable   = onoff(hasRec && ~picking);
            app.BlockDropDown.Enable  = onoff(hasRec && ~picking && app.Rec.nBlocks > 1);
            app.DemoBtn.Enable        = onoff(~picking);
            UIKit.setSessionEnable(app.SessionBtns, hasRaw && ~picking);

            if picking
                app.SelectRangeBtn.Text = 'Cancel picking';
            else
                app.SelectRangeBtn.Text = 'Pick on plot';
            end

            setButtonStyle(app.LoadBtn, ifelse(~hasRaw, 'primary', 'secondary'));
            setButtonStyle(app.ProcessBtn, ifelse(hasRaw && ~cropCurrent, 'primary', 'secondary'));
            setButtonStyle(app.SaveCroppedBtn, ifelse(cropCurrent, 'primary', 'secondary'));

            if hasCropped && ~cropCurrent
                app.CropInfoLabel.Text = sprintf('Range changed since the last crop (%.3f-%.3f s). Crop again to save.', ...
                    app.CropRange(1), app.CropRange(2));
                app.CropInfoLabel.FontColor = UITheme.warning;
            elseif hasCropped
                n = numel(app.AppData.ProcessedStim);
                app.CropInfoLabel.Text = sprintf('Cropped %.3f-%.3f s\n%s, %d samples', ...
                    app.CropRange(1), app.CropRange(2), ...
                    formatDuration(n / app.AppData.SamplingRate), n);
                app.CropInfoLabel.FontColor = UITheme.success;
            else
                app.CropInfoLabel.Text = 'Not cropped yet';
                app.CropInfoLabel.FontColor = UITheme.bodyColor;
            end
        end

        %% loadFile - Pick a recording, then openFile(path, 'ask')
        % -------------------------------------------------------------
        % On cancel nothing changes (previous data and crop are kept).
        % A text file without a time column asks for its sampling rate.
        % -------------------------------------------------------------
        function loadFile(app)
            app.cancelPick('');
            UIKit.setStatus(app.StatusLabel, 'Choose a recording...', 'busy');
            initPath = ProjectManager.getImportDir();
            if isempty(initPath), initPath = pwd; end
            filter = {'*.mat;*.acq;*.txt;*.csv;*.tsv', 'Recordings (.mat, .acq, .txt, .csv, .tsv)'; ...
                      '*.mat', 'LabChart / AcqKnowledge / Spike2 .mat export, cropped LDF (.mat)'; ...
                      '*.acq', 'AcqKnowledge (.acq)'; ...
                      '*.txt;*.csv;*.tsv', 'Text export or table (.txt, .csv, .tsv)'; ...
                      '*.*', 'All files'};
            [file, path] = uigetfile(filter, 'Load a recording', [initPath filesep]);
            figure(app.UIFig);  % Bring app back to front
            if isequal(file, 0)
                if isempty(app.AppData.RawStim)
                    UIKit.setStatus(app.StatusLabel, 'No file loaded. Click "Load file..." to choose a recording.', 'info');
                else
                    UIKit.setStatus(app.StatusLabel, 'No new file loaded; previous data kept.', 'info');
                end
                return;
            end
            app.openFile(fullfile(path, file), 'ask');
        end

        %% openFile - Load a recording by path (no dialog) and display it
        % -------------------------------------------------------------
        % SignalSource.open reads any supported format; the flow channel
        % and the stimulus are guessed from the channel names. fs (Hz,
        % optional): the rate of a text file without a time column;
        % 'ask' asks for it (loadFile). If the file cannot be read,
        % previous data and crop are kept and ok = false. For a new file:
        % drop the previous crop so Save cannot write stale data, reset
        % Start/End to the full recording, store the folder as last used
        % path, show file info and plot.
        % -------------------------------------------------------------
        function ok = openFile(app, filePath, fs)
            if nargin < 3, fs = []; end
            ask = ischar(fs) && strcmp(fs, 'ask');
            if ask, fs = []; end
            ok = false;
            app.cancelPick('');
            [~, name, ext] = fileparts(filePath);
            try
                rec = SignalSource.open(filePath, '', struct('Fs', fs));
            catch ME
                if strcmp(ME.identifier, 'NeuroAnalyzer:io:noRate') && ask
                    fs = app.askRate([name ext]);
                    if isempty(fs)
                        UIKit.setStatus(app.StatusLabel, sprintf('%s%s not opened (no sampling rate given); previous data kept.', ...
                            name, ext), 'info');
                        return;
                    end
                    ok = app.openFile(filePath, fs);
                    return;
                end
                UIKit.setStatus(app.StatusLabel, sprintf('Could not read %s%s; previous data kept.', name, ext), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not read %s%s:\n%s', name, ext, ME.message), 'Load error', 'error');
                return;
            end
            [iFlow, iStim] = SignalSource.guessChannels(rec);
            [~, stimValues] = SignalSource.stimItems(rec);
            if iStim == 0 && ~isempty(rec.events)
                stim = 'events';                  % no trigger channel: the comments / markers
            else
                stim = iStim;
            end
            if ~any(cellfun(@(v) isequal(v, stim), stimValues)), stim = 0; end
            % First block where the flow channel has data; drop a stimulus channel empty there
            block = 1;
            for bk = 1:rec.nBlocks
                if ~isempty(SignalSource.channel(rec, iFlow, bk)), block = bk; break; end
            end
            if isnumeric(stim) && stim > 0 && isempty(SignalSource.channel(rec, stim, block)), stim = 0; end
            if ~app.useSignals(rec, filePath, iFlow, stim, block, true), return; end
            ok = true;
            Exporter.setLastUsedPath(fileparts(filePath));
            Fs = app.AppData.SamplingRate;
            dur = numel(app.AppData.RawLDF) / Fs;
            if rec.info.rateAssumed
                UIKit.setStatus(app.StatusLabel, sprintf('Loaded %s%s, but the file has no sampling rate: assumed %g Hz.', ...
                    name, ext, Fs), 'warning');
            else
                UIKit.setStatus(app.StatusLabel, sprintf(['Loaded %s%s (%g Hz, %s; LDF = %s, stimulus = %s). ' ...
                    'Check the channels, then choose the time range and click "Crop to range".'], ...
                    name, ext, Fs, formatDuration(dur), app.AppData.FlowName, app.AppData.StimName), 'success');
            end
        end

        %% selectSignals - Choose the flow channel, stimulus and block (as in the dropdowns)
        % flow: channel number; stim: channel number, 'events',
        % 'events:<text>' or 0 (none); block (default 1). Keeps the
        % Start/End range when it still fits. Returns true when shown.
        function ok = selectSignals(app, flow, stim, block)
            ok = false;
            if isempty(app.Rec), return; end
            if nargin < 4 || isempty(block), block = app.Selection.block; end
            ok = app.useSignals(app.Rec, app.AppData.FilePath, flow, stim, block, false);
        end

        %% signalsChanged - A step 1 dropdown changed
        function signalsChanged(app)
            if isempty(app.Rec), return; end
            flow = app.FlowDropDown.Value;
            stim = app.StimValues{app.StimDropDown.Value};
            block = app.BlockDropDown.Value;
            if app.selectSignals(flow, stim, block)
                UIKit.setStatus(app.StatusLabel, sprintf('LDF = %s, stimulus = %s. Next: choose the time range and click "Crop to range".', ...
                    app.AppData.FlowName, app.AppData.StimName), 'info');
            end
        end

        %% useSignals - Put the chosen flow channel and stimulus of rec in the window
        % -------------------------------------------------------------
        % SignalSource.toLDF puts the stimulus on the flow channel's time
        % base. On an error nothing changes (ok = false). The previous
        % crop is dropped (it was of other signals); a new file resets
        % Start/End to the whole recording, a new choice keeps them when
        % they still fit.
        % -------------------------------------------------------------
        function ok = useSignals(app, rec, filePath, flow, stim, block, isNew)
            ok = false;
            [~, name, ext] = fileparts(filePath);
            try
                L = SignalSource.toLDF(rec, flow, stim, block);
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Could not use these signals of %s%s: %s', name, ext, ...
                    ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not use these signals of %s%s:\n%s', name, ext, ME.message), ...
                    'Signals', 'error');
                app.fillSignalLists();          % dropdowns back to what is shown
                return;
            end
            oldRange = app.currentRange();
            app.Rec = rec;
            app.Selection = struct('flow', flow, 'stim', stim, 'block', block);
            app.fillSignalLists();
            d = app.AppData;
            d.RawStim = L.stim;
            d.RawLDF = L.LDF;
            d.SamplingRate = L.Fs;
            d.FilePath = filePath;
            d.FlowName = L.flowName;
            d.FlowUnits = L.flowUnits;
            d.StimName = L.stimName;
            d.Format = rec.info.format;
            d.Metadata = struct('Format', rec.info.format, 'FormatLabel', rec.info.label, ...
                'ChannelTitles', {rec.names}, 'Units', {rec.units}, 'Notes', {rec.info.notes}, ...
                'Onsets', L.onsets, 'Block', block);
            % Drop the previous crop so Save cannot write stale data
            d.ProcessedStim = [];
            d.ProcessedLDF  = [];
            d.TimeVector    = [];
            app.AppData = d;
            app.CropRange = [];

            dur = numel(L.LDF) / L.Fs;
            lim = [0 max(dur, 1 / L.Fs)];
            keep = ~isNew && oldRange(2) > oldRange(1) && oldRange(2) <= lim(2);
            app.StartInput.Value = 0;
            app.EndInput.Value = 0;
            app.StartInput.Limits = lim;
            app.EndInput.Limits = lim;
            if keep
                app.StartInput.Value = oldRange(1);
                app.EndInput.Value = oldRange(2);
            else
                app.EndInput.Value = dur;
            end
            app.ViewDropDown.Value = 'Full recording';
            app.FileInfoLabel.Text = app.fileInfoText([name ext]);
            app.FileInfoLabel.FontColor = UITheme.sectionTitleColor;
            app.plotSignals();
            app.updateButtonStates();
            ok = true;
        end

        %% fillSignalLists - Step 1 dropdowns from Rec, showing Selection
        function fillSignalLists(app)
            rec = app.Rec;
            if isempty(rec), return; end
            sel = app.Selection;
            setItems(app.FlowDropDown, SignalSource.channelItems(rec), sel.flow);
            [items, values] = SignalSource.stimItems(rec);
            app.StimValues = values;
            k = find(cellfun(@(v) isequal(v, sel.stim), values), 1);
            if isempty(k), k = numel(items); end            % None
            setItems(app.StimDropDown, items, k);
            b = cell(1, rec.nBlocks);
            for i = 1:rec.nBlocks
                b{i} = sprintf('Block %d', i);
                if i <= numel(rec.info.blockStart) && ~isempty(rec.info.blockStart{i})
                    b{i} = sprintf('Block %d (%s)', i, strrep(rec.info.blockStart{i}, 'T', ' '));
                end
            end
            setItems(app.BlockDropDown, b, min(max(1, sel.block), rec.nBlocks));
        end

        %% fileInfoText - File name, format, rate, duration, channels
        function txt = fileInfoText(app, fileName)
            rec = app.Rec;
            Fs = app.AppData.SamplingRate;
            N = numel(app.AppData.RawLDF);
            blocks = '';
            if rec.nBlocks > 1, blocks = sprintf(', %d blocks', rec.nBlocks); end
            txt = sprintf('%s\n%s\n%g Hz  ·  %s  ·  %d channels%s', fileName, rec.info.label, Fs, ...
                formatDuration(N / Fs), rec.nChannels, blocks);
        end

        %% askRate - Ask for the sampling rate of a file without a time column ([] if cancelled)
        function fs = askRate(app, fileName)
            fs = [];
            txt = UIKit.askText('Sampling rate', sprintf(['%s has no time column. Type the sampling rate ' ...
                'of its rows in Hz (samples per second):'], fileName), 'LDF Extract', '1000', 'Open');
            figure(app.UIFig);
            if isnumeric(txt) && isempty(txt), return; end
            v = str2double(strrep(strtrim(char(txt)), ',', '.'));
            if isfinite(v) && v > 0
                fs = v;
            else
                UIKit.alert(app.UIFig, sprintf('"%s" is not a sampling rate. Load the file again and type a positive number, e.g. 1000.', ...
                    strtrim(char(txt))), 'Sampling rate', 'warning');
            end
        end

        %% loadDemo - Load the synthetic LDF export (DemoData) and pre-fill the range
        % -------------------------------------------------------------
        % 300 s at 1000 Hz; 5 s stimuli every 30 s from 30 s (ch 6, 5 V);
        % LDF on ch 8. Pre-fills Start/End = 20-280 s (as DemoData's
        % ldfCropped), so "Crop to range" is the next click. The last used
        % folder is not changed by the demo.
        % -------------------------------------------------------------
        function loadDemo(app)
            app.cancelPick('');
            prevLast = Exporter.getLastUsedPath();
            dlg = UIKit.busy(app.UIFig, 'Preparing demo data (first time only takes a few seconds)…');
            try
                p = DemoData.file('ldfExport');
                UIKit.done(dlg);
                ok = app.openFile(p);
                restoreLastPath(prevLast);
                if ~ok, return; end
                app.setRange(20, 280);
                nStim = countOnsets(app.AppData.RawStim, 2.5);
                UIKit.setStatus(app.StatusLabel, sprintf(['Demo loaded: 300 s LDF export with %d stimuli ' ...
                    '(5 s each, every 30 s). Range 20-280 s pre-filled. Next: press "Crop to range".'], nStim), 'success');
            catch ME
                UIKit.done(dlg);
                restoreLastPath(prevLast);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load the demo data: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not load the demo data:\n%s', ME.message), 'Demo data', 'error');
            end
        end

        %% setRange - Set Start/End (s) programmatically (as if typed)
        % Values are clamped to the recording; shades the range on the plots.
        function setRange(app, startS, endS)
            if isempty(app.AppData.RawStim), return; end
            lim = app.StartInput.Limits;
            app.StartInput.Value = min(max(startS, lim(1)), lim(2));
            app.EndInput.Value = min(max(endS, lim(1)), lim(2));
            app.rangeChanged();
        end

        %% processData - Validate range, crop, show cropped signals
        % -------------------------------------------------------------
        % Reads Start/End (s). Validates with Validation.cropRange(start,
        % end, N/Fs). Sample k (1-based) is at time (k-1)/Fs, so indices
        % are round(t*Fs)+1, end clamped to the common length. Calls
        % Processor.crop(), remembers the range and switches the plots
        % to the cropped segment.
        % -------------------------------------------------------------
        function processData(app)
            if isempty(app.AppData.RawStim)
                UIKit.alert(app.UIFig, 'Load a file first.', 'No data', 'warning');
                return;
            end
            app.cancelPick('');
            startTime = app.StartInput.Value;
            endTime   = app.EndInput.Value;
            durationSec = length(app.AppData.RawStim) / app.AppData.SamplingRate;
            [ok, msg] = Validation.cropRange(startTime, endTime, durationSec);
            if ~ok
                UIKit.setStatus(app.StatusLabel, ['Invalid range: ' msg], 'error');
                UIKit.alert(app.UIFig, msg, 'Invalid range', 'error');
                return;
            end
            Fs = app.AppData.SamplingRate;
            % Sample k (1-based) is at time (k-1)/Fs
            N = min(length(app.AppData.RawStim), length(app.AppData.RawLDF));
            startIdx = round(startTime * Fs) + 1;
            endIdx   = min(round(endTime * Fs) + 1, N);
            app.AppData = Processor.crop(app.AppData, startIdx, endIdx);
            app.CropRange = [startTime endTime];
            app.ViewDropDown.Value = 'Cropped segment';
            app.plotSignals();
            app.updateButtonStates();
            UIKit.setStatus(app.StatusLabel, sprintf('Cropped %.3f-%.3f s (%d samples). Next: save the cropped data.', ...
                startTime, endTime, numel(app.AppData.ProcessedStim)), 'success');
        end

        %% selectRangeInteractive - Start (or cancel) picking the range by clicks
        % -------------------------------------------------------------
        % Replaces ginput (unreliable in uifigure): while picking, clicks
        % on either axes go to onAxesClick via ButtonDownFcn. First click
        % = start (marker line), second click = end; the fields are then
        % filled and the range is shaded. Clicking the button again cancels.
        % -------------------------------------------------------------
        function selectRangeInteractive(app)
            if isempty(app.AppData.RawStim)
                UIKit.alert(app.UIFig, 'Load a file first.', 'No data', 'warning');
                return;
            end
            if app.PickState > 0
                app.cancelPick('Range picking cancelled.');
                return;
            end
            if ~strcmp(app.ViewDropDown.Value, 'Full recording')
                app.ViewDropDown.Value = 'Full recording';
                app.plotSignals();
            end
            app.PickState = 1;
            for ax = [app.AxStim app.AxLDF]
                try disableDefaultInteractivity(ax); catch, end
                ax.ButtonDownFcn = @(src, evt)app.onAxesClick(src, evt);
            end
            app.updateButtonStates();
            UIKit.setStatus(app.StatusLabel, 'Click the START of the window on the stimulus or LDF plot.', 'busy');
        end

        %% onAxesClick - Handle a click while picking the range
        function onAxesClick(app, ax, evt)
            if app.PickState == 0, return; end
            x = clickTime(ax, evt);
            dur = length(app.AppData.RawStim) / app.AppData.SamplingRate;
            x = min(max(x, 0), dur);
            if app.PickState == 1
                app.PickStart = x;
                app.PickState = 2;
                app.clearGfx('PickGfx');
                for a = [app.AxStim app.AxLDF]
                    hl = xline(a, x, '--', 'Color', UITheme.plotColors(2, :), 'LineWidth', 1.5);
                    try hl.PickableParts = 'none'; catch, end
                    app.PickGfx(end+1) = hl;
                end
                UIKit.setStatus(app.StatusLabel, sprintf('Start = %.3f s. Now click the END of the window.', x), 'busy');
                return;
            end
            r = sort([app.PickStart x]);
            if r(2) - r(1) < 1 / app.AppData.SamplingRate
                UIKit.setStatus(app.StatusLabel, 'End must differ from start. Click the END of the window again.', 'warning');
                return;
            end
            app.cancelPick('');
            app.StartInput.Value = r(1);
            app.EndInput.Value = r(2);
            app.rangeChanged();
        end

        %% cancelPick - Leave picking mode (msg shown in status if not empty)
        function cancelPick(app, msg)
            wasPicking = app.PickState > 0;
            app.PickState = 0;
            app.PickStart = NaN;
            app.clearGfx('PickGfx');
            for ax = [app.AxStim app.AxLDF]
                ax.ButtonDownFcn = '';
                try enableDefaultInteractivity(ax); catch, end
            end
            if wasPicking
                app.updateButtonStates();
                if ~isempty(msg)
                    UIKit.setStatus(app.StatusLabel, msg, 'info');
                end
            end
        end

        %% resetRange - Start/End = whole recording
        function resetRange(app)
            if isempty(app.AppData.RawStim), return; end
            app.StartInput.Value = 0;
            app.EndInput.Value = length(app.AppData.RawStim) / app.AppData.SamplingRate;
            app.rangeChanged();
        end

        %% rangeChanged - Start/End edited or picked: shade range, update state
        function rangeChanged(app)
            r = app.currentRange();
            if strcmp(app.ViewDropDown.Value, 'Full recording')
                app.drawRange();
            end
            app.updateButtonStates();
            if r(2) <= r(1)
                UIKit.setStatus(app.StatusLabel, 'End must be after Start.', 'warning');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Range %.3f-%.3f s selected (%s). Next: click "Crop to range".', ...
                    r(1), r(2), formatDuration(r(2) - r(1))), 'info');
            end
        end

        %% viewChanged - Switch plots between full recording and cropped segment
        function viewChanged(app)
            app.plotSignals();
            UIKit.setStatus(app.StatusLabel, sprintf('Showing: %s.', lower(app.ViewDropDown.Value)), 'info');
        end

        %% plotSignals - Plot full recording (with range) or cropped segment
        function plotSignals(app)
            T = UITheme;
            app.clearGfx('RangeGfx');
            showCrop = strcmp(app.ViewDropDown.Value, 'Cropped segment') && ...
                ~isempty(app.AppData.ProcessedStim);
            axs = [app.AxStim app.AxLDF];
            try linkaxes(axs, 'off'); catch, end   % re-linked below; stale links kept old limits
            for ax = axs
                cla(ax);
                ax.YLimMode = 'auto'; ax.XLimMode = 'auto';
                ax.XTickMode = 'auto'; ax.YTickMode = 'auto';
            end
            if isempty(app.AppData.RawStim)
                UIKit.emptyAxes(app.AxStim, 'Load a file (or Try demo data) to begin');
                UIKit.emptyAxes(app.AxLDF, 'LDF signal appears here');
                return;
            end
            Fs = app.AppData.SamplingRate;
            if showCrop
                t = app.AppData.TimeVector;
                stim = app.AppData.ProcessedStim; ldf = app.AppData.ProcessedLDF;
                tStim = t; tLDF = t;
                ttl = {plotTitle('Cropped stimulus', app.AppData.StimName), plotTitle('Cropped LDF', app.AppData.FlowName)};
                xl = 'Time from crop start (s)';
            else
                stim = app.AppData.RawStim; ldf = app.AppData.RawLDF;
                tStim = (0:length(stim)-1) / Fs;
                tLDF  = (0:length(ldf)-1) / Fs;
                ttl = {plotTitle('Stimulus', app.AppData.StimName), plotTitle('LDF', app.AppData.FlowName)};
                xl = 'Time (s)';
            end
            plot(app.AxStim, tStim, stim, 'Color', T.stimColor, 'HitTest', 'off');
            plot(app.AxLDF, tLDF, ldf, 'Color', T.plotColors(1, :), 'HitTest', 'off');
            ldfUnits = 'Amplitude';
            if ~isempty(app.AppData.FlowUnits), ldfUnits = app.AppData.FlowUnits; end
            UIKit.styleAxes(app.AxStim, ttl{1}, xl, 'Amplitude');
            UIKit.styleAxes(app.AxLDF, ttl{2}, xl, ldfUnits);
            tEnd = max([tStim(end), tLDF(end)]);
            if tEnd > 0, xlim(app.AxStim, [0 tEnd]); xlim(app.AxLDF, [0 tEnd]); end
            try linkaxes(axs, 'x'); catch, end
            if ~showCrop
                app.drawRange();
            end
        end

        %% drawRange - Shade the Start/End range on both axes
        function drawRange(app)
            T = UITheme;
            app.clearGfx('RangeGfx');
            r = app.currentRange();
            if isempty(app.AppData.RawStim) || r(2) <= r(1), return; end
            for ax = [app.AxStim app.AxLDF]
                yl = ylim(ax);
                hold(ax, 'on');
                hp = patch(ax, [r(1) r(2) r(2) r(1)], [yl(1) yl(1) yl(2) yl(2)], T.shadeColor, ...
                    'FaceAlpha', 0.12, 'EdgeColor', T.shadeColor, 'EdgeAlpha', 0.6, ...
                    'HitTest', 'off', 'PickableParts', 'none');
                hold(ax, 'off');
                uistack(hp, 'bottom');
                ylim(ax, yl);
                app.RangeGfx(end+1) = hp;
            end
        end

        %% clearGfx - Delete graphics stored in property name ('RangeGfx'/'PickGfx')
        function clearGfx(app, prop)
            h = app.(prop);
            delete(h(isgraphics(h)));
            app.(prop) = gobjects(0);
        end

        %% currentRange - [Start End] from the edit fields (s)
        function r = currentRange(app)
            r = [app.StartInput.Value app.EndInput.Value];
        end

        %% saveCroppedData - Save cropped data via Exporter and update last path
        % -------------------------------------------------------------
        % Calls Exporter.saveCropped() with ProcessedStim, ProcessedLDF,
        % TimeVector, SamplingRate and the project export folder (or last
        % used path). If save succeeds, stores the path used for next time.
        % -------------------------------------------------------------
        function saveCroppedData(app)
            if isempty(app.AppData.ProcessedStim)
                UIKit.alert(app.UIFig, 'Crop the data first (step 3).', 'Nothing to save', 'warning');
                return;
            end
            UIKit.setStatus(app.StatusLabel, 'Choose where to save the cropped data...', 'busy');
            defPath = ProjectManager.getExportDir();
            if isempty(defPath), defPath = Exporter.getLastUsedPath(); end
            [saved, pathUsed] = Exporter.saveCropped(...
                app.AppData.ProcessedStim, app.AppData.ProcessedLDF, ...
                app.AppData.TimeVector, app.AppData.SamplingRate, ...
                defPath, app.signalNames());
            figure(app.UIFig);
            if saved && ~isempty(pathUsed)
                Exporter.setLastUsedPath(pathUsed);
                UIKit.setStatus(app.StatusLabel, sprintf('Saved cropped data in %s. Open it in LDF Processing.', pathUsed), 'success');
            elseif saved
                UIKit.setStatus(app.StatusLabel, 'Saved cropped data.', 'success');
            else
                UIKit.setStatus(app.StatusLabel, 'Cropped data not saved.', 'info');
            end
        end

        %% signalNames - flowName, flowUnits, stimName saved next to the crop
        function S = signalNames(app)
            S = struct('flowName', app.AppData.FlowName, 'flowUnits', app.AppData.FlowUnits, ...
                'stimName', app.AppData.StimName);
        end

        %% saveCroppedTo - Save the crop to filePath without a dialog
        % Same variables as Exporter.saveCropped (stim, LDF, t, Fs, and
        % flowName, flowUnits, stimName); the file opens in LDF
        % Processing. Returns true on success.
        function ok = saveCroppedTo(app, filePath)
            ok = false;
            if isempty(app.AppData.ProcessedStim)
                UIKit.alert(app.UIFig, 'Crop the data first (step 3).', 'Nothing to save', 'warning');
                return;
            end
            S = app.signalNames();
            S.stim = app.AppData.ProcessedStim;
            S.LDF = app.AppData.ProcessedLDF;
            S.t = app.AppData.TimeVector;
            S.Fs = app.AppData.SamplingRate;
            try
                save(filePath, '-struct', 'S');
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Save failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Save failed:\n%s', ME.message), 'Save error', 'error');
                return;
            end
            ok = true;
            [~, name, ext] = fileparts(filePath);
            UIKit.setStatus(app.StatusLabel, sprintf('Saved cropped data to %s%s. Open it in LDF Processing.', ...
                name, ext), 'success');
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
        % inputs: the LDF export. settings: Start/End, view, channels.
        % results: crop range, rate, samples and LDF mean / SD of the crop
        % (the cropped signals are re-cut from the export on open).
        function st = sessionState(app)
            st.inputs = [];
            if ~isempty(app.AppData.FilePath)
                st.inputs = Session.fileInfo(app.AppData.FilePath, 'Recording');
            end
            sel = app.Selection;
            stimCh = 0;
            if isnumeric(sel.stim) && ~isempty(sel.stim), stimCh = sel.stim; end
            st.settings = struct('range', app.currentRange(), 'view', app.ViewDropDown.Value, ...
                'format', app.AppData.Format, 'formatLabel', '', 'flowChannel', sel.flow, ...
                'flowName', app.AppData.FlowName, 'flowUnits', app.AppData.FlowUnits, ...
                'stimulus', sel.stim, 'stimName', app.AppData.StimName, 'block', sel.block, ...
                'stimulusChannel', stimCh, 'ldfChannel', sel.flow, 'rate', app.AppData.SamplingRate);
            if ~isempty(app.Rec), st.settings.formatLabel = app.Rec.info.label; end
            st.results = struct();
            st.summary = {};
            if ~isempty(app.AppData.RawStim)
                st.summary{end+1} = sprintf('Recording: %d samples at %g Hz (%s)', numel(app.AppData.RawStim), ...
                    app.AppData.SamplingRate, formatDuration(numel(app.AppData.RawStim) / app.AppData.SamplingRate));
            end
            if ~isempty(app.AppData.ProcessedLDF)
                ldf = double(app.AppData.ProcessedLDF(:));
                st.results = struct('cropRange', app.CropRange, 'fs', app.AppData.SamplingRate, ...
                    'nSamples', numel(ldf), 'ldfMean', mean(ldf), 'ldfSD', std(ldf));
                st.summary{end+1} = sprintf('Crop: %.3f-%.3f s, %d samples', app.CropRange(1), ...
                    app.CropRange(2), numel(ldf));
                st.summary{end+1} = sprintf('Cropped LDF: mean %.4g, SD %.4g', mean(ldf), std(ldf));
            end
        end

        %% restoreSession - Reload the export, crop to the saved range, restore the fields
        function ok = restoreSession(app, s)
            ok = false;
            if isempty(s.inputs), ok = true; return; end
            cfg = s.settings;
            fs = [];
            if strcmp(getOr(cfg, 'format', ''), 'text'), fs = getOr(cfg, 'rate', []); end
            if ~app.openFile(s.inputs(1).path, fs), return; end
            % Signals: the saved choice (older sessions: stimulusChannel / ldfChannel)
            flow = getOr(cfg, 'flowChannel', getOr(cfg, 'ldfChannel', []));
            stim = getOr(cfg, 'stimulus', getOr(cfg, 'stimulusChannel', []));
            block = getOr(cfg, 'block', 1);
            if ~isempty(flow) && ~isempty(stim) && ~isequal(app.Selection, struct('flow', flow, 'stim', stim, 'block', block))
                if flow > app.Rec.nChannels || block > app.Rec.nBlocks || ...
                        (isnumeric(stim) && stim > app.Rec.nChannels) || ~app.selectSignals(flow, stim, block)
                    return;
                end
            end
            if isfield(s.results, 'cropRange') && numel(s.results.cropRange) == 2
                app.setRange(s.results.cropRange(1), s.results.cropRange(2));
                app.processData();
            end
            if isfield(cfg, 'range') && numel(cfg.range) == 2
                app.setRange(cfg.range(1), cfg.range(2));
            end
            if isfield(cfg, 'view') && ~isempty(app.AppData.ProcessedStim) && ...
                    ismember(cfg.view, app.ViewDropDown.Items)
                app.ViewDropDown.Value = cfg.view;
                app.plotSignals();
            end
            app.updateButtonStates();
            ok = true;
        end
    end
end

%% Local helpers
% -------------------------------------------------------------------------

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

%% addField - UIKit.field placed on grid row 'row' (label col 1, control col 2)
function c = addField(g, row, labelText, varargin)
    c = UIKit.field(g, labelText, varargin{:});
    lbl = findobj(g, '-depth', 1, 'Type', 'uilabel', 'Text', labelText);
    if ~isempty(lbl), lbl(end).Layout.Row = row; lbl(end).Layout.Column = 1; end
    c.Layout.Row = row; c.Layout.Column = 2;
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

%% clickTime - x (s) of a mouse click on axes
function x = clickTime(ax, evt)
    try
        x = evt.IntersectionPoint(1);
    catch
        x = ax.CurrentPoint(1, 1);
    end
end

%% formatDuration - "612.0 s" or "10 min 12.0 s"
function s = formatDuration(sec)
    if sec >= 120
        s = sprintf('%d min %.1f s', floor(sec / 60), mod(sec, 60));
    else
        s = sprintf('%.1f s', sec);
    end
end

%% countOnsets - Number of rising edges of x above threshold
function n = countOnsets(x, threshold)
    above = x(:) > threshold;
    n = sum(diff([false; above]) == 1);
end

%% restoreLastPath - Put back the last used folder after loading demo data
function restoreLastPath(prev)
    if isempty(prev)
        if ispref('NeuroAnalyzer', 'LastUsedPath'), rmpref('NeuroAnalyzer', 'LastUsedPath'); end
    else
        Exporter.setLastUsedPath(prev);
    end
end

%% plotTitle - 'LDF: Flux (ch 3)' style title; the bare prefix when the name adds nothing
function t = plotTitle(prefix, name)
    last = regexp(prefix, '\w+$', 'match', 'once');
    if isempty(name) || strcmpi(name, last) || strcmpi(name, prefix)
        t = prefix;
    else
        t = [prefix ': ' name];
    end
end

%% setItems - Dropdown items with ItemsData 1..n and the selected index
function setItems(dd, items, value)
    dd.ItemsData = [];
    dd.Items = items;
    dd.ItemsData = 1:numel(items);
    dd.Value = value;
end

%% getOr - s.(name) when present, else default
function v = getOr(s, name, default)
    if isstruct(s) && isfield(s, name), v = s.(name); else, v = default; end
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
