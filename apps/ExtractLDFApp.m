%% ExtractLDFApp.m
% =========================================================================
% EXTRACT LDF DATA - LOAD, CROP, AND SAVE LDF EXPORT FILES
% =========================================================================
% Sub-app launched from Main. Built with UIKit.window: numbered step cards
% on the left (1 Load, 2 Time range, 3 Crop, 4 Save), stimulus and LDF
% plots on the right. Loads .mat files in LDF export format (via
% DataLoader), lets the user choose a time range (typed Start/End in
% seconds, or two clicks on either plot via "Pick on plot"), shows the
% range as a shaded region, crops with Processor.crop() after
% Validation.cropRange(), shows the cropped signals in the same axes and
% saves them via Exporter.saveCropped(). updateButtonStates() enables
% each action from the data state and makes the next step the primary
% button. Header "? Help" opens HelpApp on the "LDF Extract" tab.
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
        LoadBtn         % Step 1: load LDF export .mat
        FileInfoLabel   % Step 1: file name, Fs, duration, samples
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
    end

    methods
        %% Constructor - Initialize AppData and build UI
        % -------------------------------------------------------------
        function app = ExtractLDFApp()
            app.AppData = struct('RawStim', [], 'RawLDF', [], ...
                                 'ProcessedStim', [], 'ProcessedLDF', [], ...
                                 'TimeVector', [], 'SamplingRate', 1000, ...
                                 'FilePath', '', 'Metadata', struct());
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
                'Load an LDF export, choose a time window, crop it and save it', ...
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
            [p, g, heights{1}] = stepCard(left, 1, 'Load LDF export', {T.buttonHeight, 56});
            p.Layout.Row = 1;
            app.LoadBtn = UIKit.button(g, 'Load file...', @(~,~)app.loadFile(), 'primary', ...
                'Load a .mat file in LDF export format (data, datastart, dataend); stimulus = channel 6, LDF = channel 8');
            app.LoadBtn.Layout.Row = 2; app.LoadBtn.Layout.Column = [1 2];
            app.FileInfoLabel = infoLabel(g, 'No file loaded', ...
                'File name, sampling rate, duration and number of samples');
            app.FileInfoLabel.Layout.Row = 3; app.FileInfoLabel.Layout.Column = [1 2];

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
            [p, g, heights{4}] = stepCard(left, 4, 'Save', {T.buttonHeight, 34});
            p.Layout.Row = 4;
            app.SaveCroppedBtn = UIKit.button(g, 'Save cropped data...', @(~,~)app.saveCroppedData(), ...
                'secondary', 'Save cropped stim, LDF, time vector (t) and sampling rate (Fs) to a .mat file');
            app.SaveCroppedBtn.Layout.Row = 2; app.SaveCroppedBtn.Layout.Column = [1 2];
            note = infoLabel(g, 'Output (stim, LDF, t, Fs) opens in LDF Processing.', ...
                'The saved file is the input of the LDF Processing window');
            note.Layout.Row = 3; note.Layout.Column = [1 2];

            heights{5} = '1x';
            left.RowHeight = heights;

            % --- Plots ---
            plotCard = UIKit.card(W.Body, '');
            plotCard.Layout.Row = 1; plotCard.Layout.Column = 2;
            axGrid = uigridlayout(plotCard, [2 1], 'RowHeight', {'1x', '1x'}, ...
                'Padding', [8 8 14 8], 'RowSpacing', 8, 'BackgroundColor', T.cardBg);
            app.AxStim = uiaxes(axGrid);
            app.AxLDF  = uiaxes(axGrid);
            UIKit.emptyAxes(app.AxStim, 'Load a file to begin');
            UIKit.emptyAxes(app.AxLDF, 'LDF signal appears here');
            UIKit.styleAxes(app.AxStim, 'Stimulus (channel 6)');
            UIKit.styleAxes(app.AxLDF, 'LDF (channel 8)');

            UIKit.setStatus(app.StatusLabel, 'Step 1: load an LDF export file.', 'info');
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

        %% loadFile - Load .mat via DataLoader and update display
        % -------------------------------------------------------------
        % DataLoader.load(app.AppData) opens the file dialog; on cancel or
        % error it returns AppData unchanged, so an unchanged FilePath +
        % RawStim means nothing new was loaded (previous data and crop are
        % kept). For a new file: drop the previous crop so Save cannot
        % write stale data, reset Start/End to the full recording, store
        % the folder as last used path, show file info and plot.
        % -------------------------------------------------------------
        function loadFile(app)
            app.cancelPick('');
            UIKit.setStatus(app.StatusLabel, 'Choose an LDF export file...', 'busy');
            prevPath = app.AppData.FilePath;
            prevStim = app.AppData.RawStim;
            app.AppData = DataLoader.load(app.AppData);
            figure(app.UIFig);  % Bring app back to front
            if isempty(app.AppData.RawStim) || ...
                    (isequal(app.AppData.FilePath, prevPath) && isequal(app.AppData.RawStim, prevStim))
                % Cancelled or failed: previous data (and crop) unchanged
                if isempty(app.AppData.RawStim)
                    UIKit.setStatus(app.StatusLabel, 'No file loaded. Click "Load file..." to choose an LDF export.', 'info');
                else
                    UIKit.setStatus(app.StatusLabel, 'No new file loaded; previous data kept.', 'info');
                end
                return;
            end
            % New file: drop the previous crop so Save cannot write stale data
            app.AppData.ProcessedStim = [];
            app.AppData.ProcessedLDF  = [];
            app.AppData.TimeVector    = [];
            app.CropRange = [];
            Exporter.setLastUsedPath(fileparts(app.AppData.FilePath));

            Fs = app.AppData.SamplingRate;
            N = length(app.AppData.RawStim);
            dur = N / Fs;
            % Reset the range to the whole recording (limits follow the file)
            app.StartInput.Value = 0;
            app.EndInput.Value = 0;
            lim = [0 max(dur, 1 / Fs)];
            app.StartInput.Limits = lim;
            app.EndInput.Limits = lim;
            app.EndInput.Value = dur;
            app.ViewDropDown.Value = 'Full recording';

            [~, name, ext] = fileparts(app.AppData.FilePath);
            app.FileInfoLabel.Text = sprintf('%s%s\n%g Hz  ·  %s  ·  %d samples\nStimulus = ch 6, LDF = ch 8', ...
                name, ext, Fs, formatDuration(dur), N);
            app.FileInfoLabel.FontColor = UITheme.sectionTitleColor;
            app.plotSignals();
            app.updateButtonStates();
            if isfield(app.AppData.Metadata, 'SampleRateRaw')
                UIKit.setStatus(app.StatusLabel, sprintf('Loaded %s%s (%g Hz, %s). Next: choose the time range and click "Crop to range".', ...
                    name, ext, Fs, formatDuration(dur)), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Loaded %s%s, but the file has no sampling rate: assumed %g Hz.', ...
                    name, ext, Fs), 'warning');
            end
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
            for ax = axs
                cla(ax);
                ax.YLimMode = 'auto'; ax.XLimMode = 'auto';
                ax.XTickMode = 'auto'; ax.YTickMode = 'auto';
            end
            if isempty(app.AppData.RawStim)
                UIKit.emptyAxes(app.AxStim, 'Load a file to begin');
                UIKit.emptyAxes(app.AxLDF, 'LDF signal appears here');
                return;
            end
            Fs = app.AppData.SamplingRate;
            if showCrop
                t = app.AppData.TimeVector;
                stim = app.AppData.ProcessedStim; ldf = app.AppData.ProcessedLDF;
                tStim = t; tLDF = t;
                ttl = {'Cropped stimulus', 'Cropped LDF'};
                xl = 'Time from crop start (s)';
            else
                stim = app.AppData.RawStim; ldf = app.AppData.RawLDF;
                tStim = (0:length(stim)-1) / Fs;
                tLDF  = (0:length(ldf)-1) / Fs;
                ttl = {'Stimulus (channel 6)', 'LDF (channel 8)'};
                xl = 'Time (s)';
            end
            plot(app.AxStim, tStim, stim, 'Color', T.stimColor, 'HitTest', 'off');
            plot(app.AxLDF, tLDF, ldf, 'Color', T.plotColors(1, :), 'HitTest', 'off');
            UIKit.styleAxes(app.AxStim, ttl{1}, xl, 'Amplitude');
            UIKit.styleAxes(app.AxLDF, ttl{2}, xl, 'Amplitude');
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
                defPath);
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
