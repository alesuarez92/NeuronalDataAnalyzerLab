%% SignalCharacterizationApp.m
% =========================================================================
% SIGNAL CHARACTERIZATION - EXTRACT RESPONSE FEATURES FROM PROCESSED DATA
% =========================================================================
% Load processed/imported data (LDF segments, ERP, or generic t/y), set
% stimulus onset and baseline, select features to compute (peak latency,
% onset delay, FWHM, AUC+, AUC-, rise/decay time, peak amplitude,
% stimulation-response integration). Results in a table; export to CSV or .mat.
% =========================================================================

classdef SignalCharacterizationApp < handle
    properties
        UIFig
        HeaderPanel
        LoadBtn
        DataTypeMenu       % 'LDF segments', 'ERP (channel average)', 'Time series (t, y)'
        FileLabel
        T0Edit             % Stimulus onset (s)
        BaselineEdit       % e.g. "0 0.1" for 0 to 0.1 s
        FeatureList        % Checkboxes or list for which features to compute
        ExtractBtn
        TablePanel
        ResultsTable       % uitable
        ExportBtn
        Data               % Loaded: t, y or segments, etc.
        Fs
        T0
        Baseline
    end

    methods
        function app = SignalCharacterizationApp()
            app.buildUI();
        end

        function buildUI(app)
            T = UITheme;
            app.UIFig = uifigure('Name', 'Signal Characterization', ...
                'Position', [80 60 900 640], 'Resize', 'on', 'Color', T.bgGray);

            main = uigridlayout(app.UIFig, [7, 1], ...
                'RowHeight', {T.headerHeight, 48, 215, 44, '1x', 44, T.footerHeight}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 16);

            % --- Header: title + subtitle (left), Help button (right) ---
            app.HeaderPanel = uipanel(main, ...
                'BackgroundColor', T.headerBg, 'BorderType', 'none');
            headerGrid = uigridlayout(app.HeaderPanel, [2, 2], ...
                'ColumnWidth', {'1x', 80}, 'RowHeight', {38, 22}, ...
                'Padding', [T.headerPaddingH 8 20 8], ...
                'ColumnSpacing', 8, 'RowSpacing', 4, ...
                'BackgroundColor', T.headerBg);
            titleLbl = uilabel(headerGrid, 'Text', 'Signal Characterization', ...
                'FontSize', T.fontTitle, 'FontWeight', 'bold', 'FontColor', T.headerTitleColor, ...
                'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;
            helpBtn = uibutton(headerGrid, 'push', 'Text', 'Help', ...
                'BackgroundColor', [1 1 1], 'FontColor', T.headerBg, 'FontWeight', 'bold', ...
                'Tooltip', 'Open help for this tool', ...
                'ButtonPushedFcn', @(~,~)HelpApp('Signal Characterization'));
            helpBtn.Layout.Row = [1 2]; helpBtn.Layout.Column = 2;
            subLbl = uilabel(headerGrid, 'Text', 'Extract response features from processed data', ...
                'FontSize', T.fontSubtitle, 'FontColor', T.headerSubtitleColor, ...
                'VerticalAlignment', 'center');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            % --- Row 1: Load and data type (taller row so Load Data button has height) ---
            row1 = uigridlayout(main, [1, 6], ...
                'ColumnWidth', {100, 220, 140, 100, 140, '1x'}, ...
                'ColumnSpacing', 10);
            app.LoadBtn = uibutton(row1, 'push', 'Text', 'Load Data', ...
                'BackgroundColor', T.accent, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~)app.loadData());
            uilabel(row1, 'Text', 'Data type:');
            app.DataTypeMenu = uidropdown(row1, 'Items', ...
                {'LDF segments (segmentedLDF, segmentedTime)', ...
                 'ERP / average response (t, y or lfp_data)', ...
                 'Time series (t, y)'}, ...
                'Value', 'Time series (t, y)', ...
                'Tooltip', 'Format of the loaded .mat file');
            app.FileLabel = uilabel(row1, 'Text', 'No file loaded', ...
                'FontColor', T.bodyColor, 'WordWrap', 'on');

            % --- Row 2: Parameters – one row for t0/baseline (label next to input), then features list ---
            row2 = uipanel(main, 'Title', 'Parameters', ...
                'BackgroundColor', T.cardBg, 'BorderType', 'line', ...
                'HighlightColor', T.cardBorder);
            inner = uigridlayout(row2, [2, 1], 'RowHeight', {36, 115}, ...
                'Padding', [12 10 12 18], 'RowSpacing', 10);
            % Top row: Stimulus onset and Baseline window (label immediately left of each input)
            topRow = uigridlayout(inner, [1, 4], 'ColumnWidth', {130, 85, 130, 95}, 'ColumnSpacing', 8);
            uilabel(topRow, 'Text', 'Stimulus onset t0 (s):');
            app.T0Edit = uieditfield(topRow, 'numeric', 'Value', 0, ...
                'Tooltip', 'Time of stimulus onset in the signal');
            uilabel(topRow, 'Text', 'Baseline window (s):');
            app.BaselineEdit = uieditfield(topRow, 'text', 'Value', '0 0.05', ...
                'Tooltip', 'e.g. 0 0.05 for 0 to 0.05 s');
            % Bottom row: Features label and listbox (full width so it does not get cut off)
            botRow = uigridlayout(inner, [1, 2], 'ColumnWidth', {160, '1x'}, 'ColumnSpacing', 8);
            uilabel(botRow, 'Text', 'Features (multi-select):');
            app.FeatureList = uilistbox(botRow, ...
                'Items', {'Peak latency', 'Onset delay (50%)', 'FWHM', ...
                    'AUC positive', 'AUC negative', 'Rise time', 'Decay time', ...
                    'Peak amplitude', 'Stim–response integral'}, ...
                'Multiselect', 'on', 'Value', {'Peak latency', 'FWHM', 'AUC positive', 'AUC negative'}, ...
                'FontSize', 11);

            % --- Row 3: Extract button ---
            app.ExtractBtn = uibutton(main, 'push', ...
                'Text', 'Extract Features', ...
                'FontSize', T.fontButton, 'BackgroundColor', T.accent, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~)app.extractFeatures(), ...
                'Enable', 'off');

            % --- Row 4: Results table ---
            app.TablePanel = uipanel(main, 'Title', 'Results', ...
                'BackgroundColor', T.cardBg, 'BorderType', 'line', 'HighlightColor', T.cardBorder);
            tGrid = uigridlayout(app.TablePanel, [1, 1], 'Padding', [6 6 6 6]);
            app.ResultsTable = uitable(tGrid, ...
                'ColumnName', {'Trial_Channel', 'PeakLatency_s', 'OnsetDelay_s', 'FWHM_s', 'AUCpos', 'AUCneg', 'RiseTime_s', 'DecayTime_s', 'PeakAmp', 'Integral'}, ...
                'RowName', {}, 'Enable', 'on', 'FontSize', 11);

            % --- Row 5: Export ---
            app.ExportBtn = uibutton(main, 'push', ...
                'Text', 'Export to CSV / MAT', ...
                'FontSize', T.fontButton, ...
                'ButtonPushedFcn', @(~,~)app.exportResults(), ...
                'Enable', 'off');
            % --- Fixed footer section for copyright ---
            footerPanel = uipanel(main, 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            footerGrid = uigridlayout(footerPanel, [1, 1], 'Padding', [14 4 14 4], ...
                'BackgroundColor', T.bgGray);
            uihyperlink(footerGrid, 'Text', '© Copyrights by Alejandro Suarez, Ph.D.', ...
                'URL', 'https://github.com/alesuarez92', ...
                'FontSize', T.fontSmall, 'HorizontalAlignment', 'right', 'FontColor', T.mutedColor);
        end

        function loadData(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir), startDir = ProjectManager.getExportDir(); end
            if isempty(startDir), startDir = pwd; end
            uistack(app.UIFig, 'bottom');
            drawnow;
            [file, path] = uigetfile(fullfile(startDir, '*.mat'), 'Select processed data');
            figure(app.UIFig);
            if isequal(file, 0), return; end
            fullPath = fullfile(path, file);
            try
                s = load(fullPath);
            catch ME
                errordlg(sprintf('Load failed: %s', ME.message), 'Load Error');
                return;
            end
            app.Data = s;
            app.FileLabel.Text = file;
            % Infer Fs from segmentedTime or t if present
            if isfield(s, 'segmentedTime') && ~isempty(s.segmentedTime)
                tt = s.segmentedTime(:);
                if numel(tt) > 1
                    app.Fs = 1 / (tt(2) - tt(1));
                else
                    app.Fs = 1000;
                end
            elseif isfield(s, 't')
                t = s.t(:);
                if numel(t) > 1, app.Fs = 1/(t(2)-t(1)); else app.Fs = 1000; end
            else
                app.Fs = 1000;
            end
            app.ExtractBtn.Enable = 'on';
        end

        function extractFeatures(app)
            if isempty(app.Data)
                errordlg('Load data first.'); return;
            end
            app.T0 = app.T0Edit.Value;
            bl = str2num(app.BaselineEdit.Value); %#ok<ST2NM>
            if isempty(bl) || numel(bl) < 2
                baseline = [];
            else
                baseline = [bl(1), bl(2)];
            end
            selected = app.FeatureList.Value;
            dt = app.DataTypeMenu.Value;

            % Build (t, y) per trial/channel
            [tCell, yCell] = app.getTimeSeriesFromData(dt);
            if isempty(tCell)
                errordlg('Could not parse data for selected type.'); return;
            end

            % Compute features for each series
            names = {};
            peakLat = [];
            onsetD = [];
            fwhm_ = [];
            aucP = [];
            aucN = [];
            riseT = [];
            decT = [];
            peakA = [];
            integral_ = [];

            for k = 1:numel(tCell)
                t = tCell{k}(:);
                y = yCell{k}(:);
                if isempty(baseline)
                    baseVal = mean(y(t >= t(1) & t < min(t(1)+0.05, t(end))));
                else
                    idx = t >= baseline(1) & t <= baseline(2);
                    baseVal = mean(y(idx));
                end
                names{end+1} = sprintf('Trial %d', k); %#ok<AGROW>

                if ismember('Peak latency', selected)
                    [lat, ~] = SignalFeatures.peakLatency(t, y, app.T0, 'max');
                    peakLat(end+1) = lat; %#ok<AGROW>
                else, peakLat(end+1) = NaN; end %#ok<AGROW>
                if ismember('Onset delay (50%)', selected)
                    onsetD(end+1) = SignalFeatures.onsetDelay(t, y, app.T0, 0.5, 'max'); %#ok<AGROW>
                else, onsetD(end+1) = NaN; end %#ok<AGROW>
                if ismember('FWHM', selected)
                    fwhm_(end+1) = SignalFeatures.fwhm(t, y, app.T0, 'max'); %#ok<AGROW>
                else, fwhm_(end+1) = NaN; end %#ok<AGROW>
                if ismember('AUC positive', selected)
                    aucP(end+1) = SignalFeatures.aucPositive(t, y, baseVal); %#ok<AGROW>
                else, aucP(end+1) = NaN; end %#ok<AGROW>
                if ismember('AUC negative', selected)
                    aucN(end+1) = SignalFeatures.aucNegative(t, y, baseVal); %#ok<AGROW>
                else, aucN(end+1) = NaN; end %#ok<AGROW>
                if ismember('Rise time', selected)
                    riseT(end+1) = SignalFeatures.riseTime(t, y, app.T0, 'max'); %#ok<AGROW>
                else, riseT(end+1) = NaN; end %#ok<AGROW>
                if ismember('Decay time', selected)
                    decT(end+1) = SignalFeatures.decayTime(t, y, app.T0, 'max'); %#ok<AGROW>
                else, decT(end+1) = NaN; end %#ok<AGROW>
                if ismember('Peak amplitude', selected)
                    [amp, ~] = SignalFeatures.peakAmplitude(t, y, app.T0, 'max', baseVal);
                    peakA(end+1) = amp; %#ok<AGROW>
                else, peakA(end+1) = NaN; end %#ok<AGROW>
                if ismember('Stim–response integral', selected)
                    stim = zeros(size(y)); stim(t >= app.T0) = 1;
                    integral_(end+1) = SignalFeatures.stimResponseIntegration(t, stim, y, app.T0); %#ok<AGROW>
                else, integral_(end+1) = NaN; end %#ok<AGROW>
            end

            app.ResultsTable.Data = [names(:), num2cell(peakLat(:)), num2cell(onsetD(:)), ...
                num2cell(fwhm_(:)), num2cell(aucP(:)), num2cell(aucN(:)), ...
                num2cell(riseT(:)), num2cell(decT(:)), num2cell(peakA(:)), num2cell(integral_(:))];
            app.ExportBtn.Enable = 'on';
        end

        function [tCell, yCell] = getTimeSeriesFromData(app, dt)
            tCell = {};
            yCell = {};
            s = app.Data;
            if contains(dt, 'LDF segments')
                if ~isfield(s, 'segmentedLDF') || ~isfield(s, 'segmentedTime')
                    return;
                end
                seg = s.segmentedLDF;
                t = s.segmentedTime(1,:);
                for i = 1:size(seg, 1)
                    tCell{end+1} = t; %#ok<AGROW>
                    yCell{end+1} = seg(i,:); %#ok<AGROW>
                end
            elseif contains(dt, 'ERP') || contains(dt, 'average')
                if isfield(s, 't') && isfield(s, 'lfp_data')
                    y = mean(s.lfp_data, 1);
                    tCell = {s.t(:)'};
                    yCell = {y(:)'};
                elseif isfield(s, 't') && isfield(s, 'y')
                    tCell = {s.t(:)'};
                    yCell = {s.y(:)'};
                else
                    return;
                end
            else
                if isfield(s, 't') && isfield(s, 'y')
                    tCell = {s.t(:)'};
                    yCell = {s.y(:)'};
                elseif isfield(s, 't') && isfield(s, 'LDF')
                    tCell = {s.t(:)'};
                    yCell = {s.LDF(:)'};
                else
                    return;
                end
            end
        end

        function exportResults(app)
            data = app.ResultsTable.Data;
            if isempty(data)
                errordlg('No results to export.'); return;
            end
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = pwd; end
            [file, path] = uiputfile({'*.csv'; '*.mat'}, 'Export features', fullfile(startDir, 'signal_features.csv'));
            if isequal(file, 0), return; end
            fullPath = fullfile(path, file);
            colNames = app.ResultsTable.ColumnName;
            if iscell(colNames), colNames = colNames(:)'; end
            try
                if endsWith(lower(fullPath), '.csv')
                    T = cell2table(data, 'VariableNames', colNames);
                    writetable(T, fullPath);
                else
                    save(fullPath, 'data', 'colNames');
                end
                msgbox('Export complete.');
            catch ME
                errordlg(sprintf('Export failed: %s', ME.message));
            end
        end
    end
end
