%% ExtractLDFApp.m
% =========================================================================
% EXTRACT LDF DATA - LOAD, CROP, AND SAVE LDF EXPORT FILES
% =========================================================================
% Sub-app launched from Main. Loads .mat files in LDF export format (via
% DataLoader), plots stimulus and LDF in two axes, lets user select a time
% range (interactively or by typing Start/End in seconds), crops with
% Processor.crop(), and saves cropped data via Exporter.saveCropped().
% Uses Validation.cropRange() before cropping. Button states (Select Range,
% Crop, Save Cropped) are disabled until the required data is available.
% Help button (?) opens HelpApp on the "LDF Extract" tab.
% =========================================================================

classdef ExtractLDFApp < handle

    %% PROPERTIES
    % ---------------------------------------------------------------------
    % UI: figure, toolbar buttons, edit fields, axes, status/sampling labels
    % ---------------------------------------------------------------------
    properties
        UIFig           % Main uifigure
        HeaderPanel     % Top bar (title, Help)
        LoadBtn         % Load LDF .mat (accent color)
        SelectRangeBtn  % Interactive range selection on stimulus plot
        ProcessBtn      % Crop & plot
        SaveCroppedBtn  % Save cropped to .mat
        AxStim          % uiaxes for stimulus
        AxLDF           % uiaxes for LDF
        StartInput      % uieditfield: start time (seconds)
        EndInput        % uieditfield: end time (seconds)
        SamplingRateText % Label showing Fs (e.g. "1000 Hz")
        StatusLabel     % "No file loaded" / "Loaded: name" / "... (cropped)"
        HelpBtn         % Opens HelpApp('LDF Extract')
        AppData         % Struct: RawStim, RawLDF, ProcessedStim, ProcessedLDF,
                        %         TimeVector, SamplingRate, FilePath, Metadata
    end

    methods
        %% Constructor - Initialize AppData and build UI
        % -------------------------------------------------------------
        function app = ExtractLDFApp()
            app.AppData = struct('RawStim', [], 'RawLDF', [], ...
                                 'ProcessedStim', [], 'ProcessedLDF', [], ...
                                 'TimeVector', [], 'SamplingRate', 1000, ...
                                 'FilePath', '', 'Metadata', struct());
            app.buildUI();
        end

        %% buildUI - Create figure, toolbar, status, and axes
        % -------------------------------------------------------------
        % Layout: (1) Toolbar row: Load, Select Range, Start/End fields,
        %         Crop & Plot, Save Cropped, Fs label, Help (?).
        %         (2) Status label. (3) Panel with two uiaxes (Stim, LDF).
        % Then updateButtonStates() to disable actions until data is loaded.
        % -------------------------------------------------------------
        function buildUI(app)
            T = UITheme;
            app.UIFig = uifigure('Name', 'Extract LDF Data', ...
                'Position', [100 80 1000 680], 'Resize', 'on', 'Color', T.bgGray);

            mainGrid = uigridlayout(app.UIFig, [5, 1], ...
                'RowHeight', {T.headerHeight, 44, 28, '1x', T.footerHeight}, ...
                'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 8);

            % --- Header: title + subtitle (left), Help button (right) ---
            app.HeaderPanel = uipanel(mainGrid, ...
                'BackgroundColor', T.headerBg, 'BorderType', 'none');
            headerGrid = uigridlayout(app.HeaderPanel, [2, 2], ...
                'ColumnWidth', {'1x', 80}, 'RowHeight', {38, 22}, ...
                'Padding', [T.headerPaddingH 8 20 8], ...
                'ColumnSpacing', 8, 'RowSpacing', 4);
            titleLbl = uilabel(headerGrid, 'Text', 'Extract LDF Data', ...
                'FontSize', T.fontTitle, 'FontWeight', 'bold', 'FontColor', T.headerTitleColor, ...
                'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;
            app.HelpBtn = uibutton(headerGrid, 'push', ...
                'Text', '? Help', ...
                'BackgroundColor', [1 1 1], 'FontColor', T.headerBg, 'FontWeight', 'bold', ...
                'Tooltip', 'Open help for this tool', ...
                'ButtonPushedFcn', @(~,~)HelpApp('LDF Extract'));
            app.HelpBtn.Layout.Row = [1 2]; app.HelpBtn.Layout.Column = 2;
            subLbl = uilabel(headerGrid, 'Text', 'Load, crop, and save LDF export', ...
                'FontSize', T.fontSubtitle, 'FontColor', T.headerSubtitleColor, ...
                'VerticalAlignment', 'center');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            % --- Toolbar: load, range, crop, save, Fs (fixed section) ---
            row1 = uigridlayout(mainGrid, [1, 10], ...
                'ColumnWidth', {100, 100, 60, 60, 60, 60, 100, 100, 90, 70}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 8);
            app.LoadBtn = uibutton(row1, 'push', ...
                'Text', 'Load File', 'BackgroundColor', T.accent, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~)app.loadFile(), ...
                'Tooltip', 'Load LDF export .mat file');
            app.SelectRangeBtn = uibutton(row1, 'push', ...
                'Text', 'Select Range', ...
                'ButtonPushedFcn', @(~,~)app.selectRangeInteractive(), ...
                'Tooltip', 'Click start and end on the stimulus plot');
            uilabel(row1, 'Text', 'Start (s):');
            app.StartInput = uieditfield(row1, 'text', 'Value', '', ...
                'Tooltip', 'Start time in seconds');
            uilabel(row1, 'Text', 'End (s):');
            app.EndInput = uieditfield(row1, 'text', 'Value', '', ...
                'Tooltip', 'End time in seconds');
            app.ProcessBtn = uibutton(row1, 'push', ...
                'Text', 'Crop & Plot', ...
                'ButtonPushedFcn', @(~,~)app.processData(), ...
                'Tooltip', 'Crop to the given range and plot');
            app.SaveCroppedBtn = uibutton(row1, 'push', ...
                'Text', 'Save Cropped', ...
                'ButtonPushedFcn', @(~,~)app.saveCroppedData(), ...
                'Tooltip', 'Save cropped stim and LDF to .mat');
            uilabel(row1, 'Text', 'Fs:');
            app.SamplingRateText = uilabel(row1, 'Text', '---');

            app.StatusLabel = uilabel(mainGrid, 'Text', 'No file loaded', ...
                'FontColor', T.bodyColor, 'FontSize', T.fontBody);

            % --- Axes panel: padding so graph titles are not clipped ---
            axPanel = uipanel(mainGrid, 'Title', 'Stimulus & LDF', ...
                'BorderType', 'line', 'HighlightColor', T.cardBorder, ...
                'BackgroundColor', T.cardBg, 'FontWeight', 'bold');
            axGrid = uigridlayout(axPanel, [2, 1], 'RowHeight', {'1x', '1x'}, ...
                'Padding', T.axesPanelPadding, 'RowSpacing', 12);
            app.AxStim = uiaxes(axGrid);
            app.AxLDF  = uiaxes(axGrid);
            title(app.AxStim, 'Stimulus (Channel 6)');
            title(app.AxLDF, 'LDF (Channel 8)');

            % --- Footer: fixed section for copyright ---
            footerPanel = uipanel(mainGrid, 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            footerGrid = uigridlayout(footerPanel, [1, 1], 'Padding', [14 4 14 4]);
            uihyperlink(footerGrid, 'Text', '© Copyrights by Alejandro Suarez, Ph.D.', ...
                'URL', 'https://github.com/alesuarez92', ...
                'FontSize', T.fontSmall, 'HorizontalAlignment', 'right', 'FontColor', T.mutedColor);

            app.updateButtonStates();
        end

        %% updateButtonStates - Enable/disable buttons based on data
        % -------------------------------------------------------------
        % Select Range and Crop & Plot enabled only when RawStim/RawLDF exist.
        % Save Cropped enabled only when ProcessedStim/ProcessedLDF exist.
        % -------------------------------------------------------------
        function updateButtonStates(app)
            hasRaw = ~isempty(app.AppData.RawStim) && ~isempty(app.AppData.RawLDF);
            hasCropped = ~isempty(app.AppData.ProcessedStim) && ~isempty(app.AppData.ProcessedLDF);
            app.SelectRangeBtn.Enable = ifelse(hasRaw, 'on', 'off');
            app.ProcessBtn.Enable = ifelse(hasRaw, 'on', 'off');
            app.SaveCroppedBtn.Enable = ifelse(hasCropped, 'on', 'off');
        end

        %% loadFile - Load .mat via DataLoader and update display
        % -------------------------------------------------------------
        % Calls DataLoader.load(app.AppData). On cancel or error, load returns
        % without filling RawStim so we return early. Otherwise: store last
        % path, update Fs label and status, plot Stim/LDF, refresh button states.
        % -------------------------------------------------------------
        function loadFile(app)
            % Send app window to back so file dialog opens on top
            uistack(app.UIFig, 'bottom');
            drawnow;
            app.AppData = DataLoader.load(app.AppData);
            figure(app.UIFig);  % Bring app back to front
            if isempty(app.AppData.RawStim)
                return;
            end
            [~, name, ~] = fileparts(app.AppData.FilePath);
            Exporter.setLastUsedPath(fileparts(app.AppData.FilePath));
            app.SamplingRateText.Text = sprintf('%d Hz', app.AppData.SamplingRate);
            app.StatusLabel.Text = sprintf('Loaded: %s', name);
            PlotManager.plotStimLDF(app.AppData, app.AxStim, app.AxLDF);
            app.updateButtonStates();
        end

        %% processData - Validate range, crop, plot in new figure, update status
        % -------------------------------------------------------------
        % Reads Start/End from edit fields (seconds). Validates with
        % Validation.cropRange(startTime, endTime, durationSec). Converts to
        % sample indices and calls Processor.crop(). Opens a new figure with
        % two subplots (cropped Stim, cropped LDF), updates status to "(cropped)"
        % and button states.
        % -------------------------------------------------------------
        function processData(app)
            startTime = str2double(app.StartInput.Value);
            endTime   = str2double(app.EndInput.Value);
            durationSec = length(app.AppData.RawStim) / app.AppData.SamplingRate;
            [ok, msg] = Validation.cropRange(startTime, endTime, durationSec);
            if ~ok
                errordlg(msg, 'Invalid Range');
                return;
            end
            Fs = app.AppData.SamplingRate;
            startIdx = round(startTime * Fs);
            endIdx   = round(endTime * Fs);
            app.AppData = Processor.crop(app.AppData, startIdx, endIdx);
            figure('Name', 'Cropped Signals');
            t = app.AppData.TimeVector;
            subplot(2,1,1);
            plot(t, app.AppData.ProcessedStim);
            title('Cropped Stimulus'); xlabel('Time (s)'); ylabel('Amplitude');
            subplot(2,1,2);
            plot(t, app.AppData.ProcessedLDF);
            title('Cropped LDF'); xlabel('Time (s)'); ylabel('Amplitude');
            [~, fname, ~] = fileparts(app.AppData.FilePath);
            app.StatusLabel.Text = sprintf('Loaded: %s (cropped)', fname);
            app.updateButtonStates();
        end

        %% selectRangeInteractive - Let user click two points on stimulus plot
        % -------------------------------------------------------------
        % Requires loaded data. Sets prompt title on stimulus axes, uses
        % ginput(2) to get two time points, sorts them, writes to Start/End
        % edit fields, and draws red/green vertical dashed lines at the range.
        % -------------------------------------------------------------
        function selectRangeInteractive(app)
            if isempty(app.AppData.RawStim)
                errordlg('Load data first.', 'No Data');
                return;
            end
            set(0, 'CurrentFigure', app.UIFig);
            title(app.AxStim, 'Click START then END on the plot');
            [x, ~] = ginput(2);
            x = sort(x);
            app.StartInput.Value = num2str(x(1));
            app.EndInput.Value   = num2str(x(2));
            title(app.AxStim, 'Stimulus (Channel 6)');
            hold(app.AxStim, 'on');
            yl = ylim(app.AxStim);
            plot(app.AxStim, [x(1) x(1)], yl, 'r--', 'LineWidth', 1.5);
            plot(app.AxStim, [x(2) x(2)], yl, 'g--', 'LineWidth', 1.5);
            hold(app.AxStim, 'off');
        end

        %% saveCroppedData - Save cropped data via Exporter and update last path
        % -------------------------------------------------------------
        % Calls Exporter.saveCropped() with ProcessedStim, ProcessedLDF,
        % TimeVector, SamplingRate, and last used path. If save succeeds,
        % stores the path used for next time.
        % -------------------------------------------------------------
        function saveCroppedData(app)
            defPath = ProjectManager.getExportDir();
            if isempty(defPath), defPath = Exporter.getLastUsedPath(); end
            [saved, pathUsed] = Exporter.saveCropped(...
                app.AppData.ProcessedStim, app.AppData.ProcessedLDF, ...
                app.AppData.TimeVector, app.AppData.SamplingRate, ...
                defPath);
            if saved && ~isempty(pathUsed)
                Exporter.setLastUsedPath(pathUsed);
            end
        end
    end
end

%% Local helper: return one of two strings based on condition
%  Used for 'on'/'off' Enable state without if/else in one line.
function s = ifelse(cond, a, b)
    if cond
        s = a;
    else
        s = b;
    end
end
