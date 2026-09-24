%% SignalCharacterizationApp.m
% =========================================================================
% SIGNAL CHARACTERIZATION - EXTRACT RESPONSE FEATURES FROM PROCESSED DATA
% =========================================================================
% Load processed/imported data (LDF segments, ERP, or generic t/y), set
% stimulus onset and baseline, select features to compute (peak latency,
% onset delay, FWHM, AUC+, AUC-, rise/decay time, peak amplitude,
% stimulation-response integration). Results in a table; export to CSV or .mat.
%
% Layout (UIKit.window): numbered step cards on the left
%   1 Load data   2 Parameters   3 Features + Extract   4 Export
% and on the right the selected series (with t0, baseline and extracted
% peak / half-maximum marked) above the results table. One updateControls()
% sets every enable state from the current data.
% Scriptable (CI walkthroughs, no dialogs): openFile(path), loadDemo(),
% extract() (= extractFeatures()).
% =========================================================================

classdef SignalCharacterizationApp < handle
    properties
        UIFig
        W                  % UIKit.window struct (Fig, Body, Status, HelpBtn)
        LoadBtn
        DemoBtn            % Try demo data (synthetic LDF trials with known answers)
        DataTypeMenu       % 'LDF segments', 'ERP (channel average)', 'Time series (t, y)'
        FileLabel          % What was detected in the loaded file
        T0Edit             % Stimulus onset (s)
        BaselineStartEdit  % Baseline window start (s)
        BaselineEndEdit    % Baseline window end (s)
        DirectionMenu      % 'Auto', 'Positive', 'Negative' response direction
        FeatureList        % Multi-select list of features to compute
        ExtractBtn
        ExportBtn
        ResultsLabel       % "n series · k features" under Export
        SeriesMenu         % Which series to plot
        Axes               % Selected series with features marked
        ResultsTable       % uitable
        Data               % Loaded: t, y or segments, etc.
        FileName
        Fs
        T0
        Baseline
        SeriesT            % Cell of time vectors, one per parsed series
        SeriesY            % Cell of signals, one per parsed series
        SeriesNames        % Cell of names ('Trial k'), same order
        HasResults = false % True once features were extracted for SeriesT/Y
        NFeatures = 0      % Number of features in the current results
    end

    properties(Constant, Access = private)
        FeatureItems = {'Peak latency', 'Onset delay (50%)', 'FWHM', ...
            'AUC positive', 'AUC negative', 'Rise time', 'Decay time', ...
            'Peak amplitude', 'Stim–response integral'}
        DataTypes = {'LDF segments (segmentedLDF, segmentedTime)', ...
            'ERP / average response (t, y or lfp_data)', ...
            'Time series (t, y)'}
    end

    methods
        function app = SignalCharacterizationApp()
            app.buildUI();
            app.updateControls();
        end

        %% buildUI - Header | step cards (left) + plot and table (right) | status
        function buildUI(app)
            T = UITheme;
            app.W = UIKit.window('Signal Characterization', ...
                'Extract response features (latency, FWHM, AUC, rise/decay) from processed data', ...
                'Signal Characterization', [1200 860]);
            app.UIFig = app.W.Fig;
            body = app.W.Body;
            body.RowHeight = {'1x'};
            body.ColumnWidth = {320, '1x'};

            % === LEFT: numbered step cards ===
            left = uigridlayout(body, [4 1], 'RowHeight', {150, 172, '1x', 100}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');

            % --- 1 Load data ---
            g1 = uigridlayout(UIKit.card(left), [4 1], ...
                'RowHeight', {'fit', T.buttonHeight, T.controlHeight, '1x'}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g1, 1, 'Load data');
            b1 = uigridlayout(g1, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.LoadBtn = UIKit.button(b1, 'Load .mat file', @(~,~)app.loadData(), 'primary', ...
                ['Segmented LDF (segmentedLDF, segmentedTime) from Process LDF, an LFP file ' ...
                 'from Extract Ephys (lfp_data, t_lfp), the ERP export of LFP analysis, ' ...
                 'or any .mat with t and y']);
            app.DemoBtn = UIKit.button(b1, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Load synthetic LDF trials with known answers: hyperemia of about +30 PU ' ...
                 'peaking about 4 s after stimulus onset']);
            f1 = uigridlayout(g1, [1 2], 'ColumnWidth', {70, '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.DataTypeMenu = UIKit.field(f1, 'Data type', 'dropdown', ...
                {app.DataTypes, app.DataTypes{3}}, ...
                'Detected automatically on load; change it if the file holds several formats');
            app.DataTypeMenu.ValueChangedFcn = @(~,~)app.onDataTypeChanged();
            app.FileLabel = uilabel(g1, 'Text', 'No file loaded', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on', 'Interpreter', 'none');

            % --- 2 Parameters ---
            g2 = uigridlayout(UIKit.card(left), [2 1], ...
                'RowHeight', {'fit', 4 * T.controlHeight + 3 * 6}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g2, 2, 'Parameters');
            f2 = uigridlayout(g2, [4 2], 'RowHeight', repmat({T.controlHeight}, 1, 4), ...
                'ColumnWidth', {'1x', 110}, 'Padding', [0 0 0 0], 'RowSpacing', 6, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.T0Edit = UIKit.field(f2, 'Stimulus onset t0 (s)', 'numeric', 0, ...
                'Time of stimulus onset in the trace. Features are measured after t0 (0 for segmented LDF).', ...
                [-1e6 1e6]);
            app.BaselineStartEdit = UIKit.field(f2, 'Baseline start (s)', 'numeric', 0, ...
                ['Start of the baseline window: its mean is the reference level for every feature. ' ...
                 'If the window holds no samples, the pre-onset mean is used.'], [-1e6 1e6]);
            app.BaselineEndEdit = UIKit.field(f2, 'Baseline end (s)', 'numeric', 0.05, ...
                ['End of the baseline window. Set end <= start to use the first 0.05 s ' ...
                 'of each trace instead.'], [-1e6 1e6]);
            app.DirectionMenu = UIKit.field(f2, 'Direction', 'dropdown', ...
                {{'Auto', 'Positive', 'Negative'}, 'Auto'}, ...
                ['Response polarity. Positive: peaks; Negative: troughs; Auto: negative if the ' ...
                 'post-onset deflection below baseline is larger than above']);
            for c = {app.T0Edit, app.BaselineStartEdit, app.BaselineEndEdit, app.DirectionMenu}
                c{1}.ValueChangedFcn = @(~,~)app.onParamsChanged();
            end

            % --- 3 Features + Extract ---
            g3 = uigridlayout(UIKit.card(left), [3 1], ...
                'RowHeight', {'fit', '1x', T.buttonHeight}, 'Padding', [10 8 10 10], ...
                'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g3, 3, 'Features');
            app.FeatureList = uilistbox(g3, 'Items', app.FeatureItems, 'Multiselect', 'on', ...
                'Value', {'Peak latency', 'FWHM', 'AUC positive', 'AUC negative'}, ...
                'FontSize', T.fontBody, ...
                'Tooltip', 'Ctrl/Cmd-click to select several features; Shift-click for a range', ...
                'ValueChangedFcn', @(~,~)app.updateControls());
            app.ExtractBtn = UIKit.button(g3, 'Extract features', @(~,~)app.extractFeatures(), ...
                'primary', 'Compute the selected features for every series in the file');

            % --- 4 Export ---
            g4 = uigridlayout(UIKit.card(left), [3 1], ...
                'RowHeight', {'fit', T.buttonHeight, '1x'}, 'Padding', [10 8 10 10], ...
                'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g4, 4, 'Export results');
            app.ExportBtn = UIKit.button(g4, 'Export to CSV / MAT', @(~,~)app.exportResults(), ...
                'secondary', 'Save the results table as .csv (one row per series) or .mat (data, colNames)');
            app.ResultsLabel = uilabel(g4, 'Text', 'No results yet', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');

            % === RIGHT: plot (with series selector) above results table ===
            right = uigridlayout(body, [2 1], 'RowHeight', {'1.3x', '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray);
            plotCard = UIKit.card(right, 'Selected series');
            pg = uigridlayout(plotCard, [2 3], 'RowHeight', {T.controlHeight, '1x'}, ...
                'ColumnWidth', {'fit', 200, '1x'}, 'Padding', [10 6 10 6], ...
                'BackgroundColor', T.cardBg);
            uilabel(pg, 'Text', 'Show:', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            app.SeriesMenu = uidropdown(pg, 'Items', {'-'}, 'Value', '-', ...
                'Tooltip', 'Series to plot. Clicking a row in the results table also selects it.', ...
                'ValueChangedFcn', @(~,~)app.plotSelected());
            uilabel(pg, 'Text', 'Dashed: t0 · shaded: baseline window · o: peak · bar: FWHM', ...
                'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'HorizontalAlignment', 'right');
            app.Axes = uiaxes(pg);
            app.Axes.Layout.Row = 2; app.Axes.Layout.Column = [1 3];
            UIKit.emptyAxes(app.Axes, 'Load a file (or Try demo data) to begin');

            tableCard = UIKit.card(right, 'Results (one row per series; NaN = not computed or not found)');
            tg = uigridlayout(tableCard, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.ResultsTable = uitable(tg, ...
                'ColumnName', {'Trial_Channel', 'PeakLatency_s', 'OnsetDelay_s', 'FWHM_s', 'AUCpos', 'AUCneg', 'RiseTime_s', 'DecayTime_s', 'PeakAmp', 'Integral'}, ...
                'RowName', {}, 'FontSize', T.fontBody, ...
                'Tooltip', 'Click a row to plot that series', ...
                'CellSelectionCallback', @(~,evt)app.onTableSelect(evt));

            UIKit.setStatus(app.W.Status, 'Load a .mat file (or Try demo data) to begin (step 1).', 'info');
        end

        %% updateControls - Enable state of every control from the current data
        function updateControls(app)
            hasData = ~isempty(app.Data);
            hasSeries = ~isempty(app.SeriesT);
            hasFeat = ~isempty(app.FeatureList.Value);
            hasRes = ~isempty(app.ResultsTable.Data);
            onOff = {'off', 'on'};
            app.DataTypeMenu.Enable = onOff{hasData + 1};
            for c = {app.T0Edit, app.BaselineStartEdit, app.BaselineEndEdit, app.DirectionMenu}
                c{1}.Enable = onOff{hasData + 1};
            end
            app.FeatureList.Enable = onOff{hasData + 1};
            app.ExtractBtn.Enable = onOff{(hasSeries && hasFeat) + 1};
            app.ExportBtn.Enable = onOff{hasRes + 1};
            app.SeriesMenu.Enable = onOff{hasSeries + 1};
            % Primary style follows the recommended next action
            styleBtn(app.ExtractBtn, hasSeries && ~hasRes);
            styleBtn(app.ExportBtn, hasRes);
            if hasRes
                app.ResultsLabel.Text = sprintf('%d series · %d feature(s) computed', ...
                    size(app.ResultsTable.Data, 1), app.NFeatures);
            else
                app.ResultsLabel.Text = 'No results yet';
            end
        end

        %% loadData - Pick a .mat, detect its format, parse series and plot the first
        function loadData(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir), startDir = ProjectManager.getExportDir(); end
            if isempty(startDir), startDir = pwd; end
            [file, path] = uigetfile(fullfile(startDir, '*.mat'), 'Select processed data');
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.openFile(fullfile(path, file));
        end

        %% openFile - Load a .mat without dialogs: detect format, parse series, plot
        % Returns true on success.
        function ok = openFile(app, fullPath)
            ok = false;
            [~, name, ext] = fileparts(fullPath);
            file = [name ext];
            UIKit.setStatus(app.W.Status, sprintf('Loading %s', file), 'busy');
            try
                s = load(fullPath);
            catch ME
                UIKit.setStatus(app.W.Status, 'Load failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Load failed: %s', ME.message), 'Load error');
                return;
            end
            dt = detectDataType(s);
            if isempty(dt)
                UIKit.setStatus(app.W.Status, sprintf('%s: no usable variables', file), 'error');
                UIKit.alert(app.UIFig, sprintf(['%s does not contain a supported format.\n\n' ...
                    'Expected one of:\n  segmentedLDF + segmentedTime (Process LDF)\n' ...
                    '  lfp_data + t_lfp (Extract Ephys, LFP)\n  t + y, or t + LDF\n\n' ...
                    'Variables found: %s'], file, strjoin(fieldnames(s), ', ')), 'Unsupported file');
                return;
            end
            app.Data = s;
            app.FileName = file;
            app.DataTypeMenu.Value = dt;
            % Infer Fs from segmentedTime, lfp_fs, t or t_lfp if present
            if isfield(s, 'segmentedTime') && ~isempty(s.segmentedTime)
                tt = s.segmentedTime(:);
                if numel(tt) > 1
                    app.Fs = 1 / (tt(2) - tt(1));
                else
                    app.Fs = 1000;
                end
            elseif isfield(s, 'lfp_fs') && ~isempty(s.lfp_fs)
                app.Fs = s.lfp_fs;
            elseif isfield(s, 't') || isfield(s, 't_lfp')
                if isfield(s, 't'), t = s.t(:); else, t = s.t_lfp(:); end
                if numel(t) > 1, app.Fs = 1/(t(2)-t(1)); else, app.Fs = 1000; end
            else
                app.Fs = 1000;
            end
            try
                app.parseSeries();
            catch ME
                app.Data = []; app.SeriesT = {}; app.SeriesY = {}; app.SeriesNames = {};
                app.SeriesMenu.Items = {'-'}; app.SeriesMenu.Value = '-';
                app.FileLabel.Text = 'No file loaded';
                UIKit.emptyAxes(app.Axes, 'Load a file to begin');
                app.updateControls();
                UIKit.setStatus(app.W.Status, sprintf('Could not read the series in %s', file), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not read the series in %s: %s', file, ME.message), ...
                    'Load error');
                return;
            end
            % Segmented traces start before onset: default the baseline to
            % the pre-stimulus part instead of the first 50 ms after onset
            msg = '';
            if ~isempty(app.SeriesT)
                tFirst = app.SeriesT{1}(1);
                if tFirst < app.T0Edit.Value
                    app.BaselineStartEdit.Value = tFirst;
                    app.BaselineEndEdit.Value = app.T0Edit.Value;
                    msg = sprintf(' Baseline set to the pre-stimulus window %.3g to %.3g s.', ...
                        tFirst, app.T0Edit.Value);
                    app.plotSelected();
                end
            end
            UIKit.setStatus(app.W.Status, sprintf('Loaded %s: %d series.%s Choose features and click Extract.', ...
                file, numel(app.SeriesT), msg), 'success');
            ok = true;
        end

        %% loadDemo - Load synthetic LDF trials and pre-fill the settings
        % DemoData 'ldfTrials': trials -5..20 s around each stimulus (10 Hz)
        % with a hyperemia of ~+30 PU over ~120 PU peaking ~4 s after
        % onset. Sets t0 = 0, direction Auto, every feature selected (the
        % baseline becomes -5..0 s on load). Returns true on success.
        function ok = loadDemo(app)
            ok = false;
            dlg = UIKit.busy(app.UIFig, sprintf('Preparing demo data (first time only takes a few seconds)%s', char(8230)));
            UIKit.setStatus(app.W.Status, 'Preparing demo data', 'busy');
            try
                p = DemoData.file('ldfTrials');
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, sprintf('Demo data failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not create the demo data: %s', ME.message), 'Demo data');
                return;
            end
            UIKit.done(dlg);
            app.T0Edit.Value = 0;
            app.DirectionMenu.Value = 'Auto';
            if ~app.openFile(p), return; end
            app.FeatureList.Value = app.FeatureItems;
            app.plotSelected();
            app.updateControls();
            UIKit.setStatus(app.W.Status, sprintf(['Demo loaded: %d synthetic LDF trials (-5 to 20 s, stimulus at 0 s), ' ...
                'all features selected. Click Extract features: expect peak latency ~4 s and ' ...
                'peak amplitude ~30 PU.'], numel(app.SeriesT)), 'success');
            ok = true;
        end

        %% extract - Extract the selected features with the current fields (scripts / CI)
        % Same as the Extract features button. Returns true when results exist.
        function ok = extract(app)
            app.extractFeatures();
            ok = app.HasResults;
        end

        %% parseSeries - (Re)build series from Data for the selected data type
        % Clears previous results and refreshes the info label, series menu and plot.
        function parseSeries(app)
            [tCell, yCell] = app.getTimeSeriesFromData(app.DataTypeMenu.Value);
            app.SeriesT = tCell;
            app.SeriesY = yCell;
            app.SeriesNames = arrayfun(@(k) sprintf('Trial %d', k), 1:numel(tCell), ...
                'UniformOutput', false);
            app.ResultsTable.Data = {};
            app.HasResults = false;
            if isempty(tCell)
                app.SeriesMenu.Items = {'-'}; app.SeriesMenu.Value = '-';
                app.FileLabel.Text = sprintf('%s: no series of this type', app.FileName);
                UIKit.emptyAxes(app.Axes, 'No series for this data type: pick another type in step 1');
            else
                app.SeriesMenu.Items = app.SeriesNames;
                app.SeriesMenu.Value = app.SeriesNames{1};
                t1 = tCell{1};
                typeShort = strtok(app.DataTypeMenu.Value, '(');
                app.FileLabel.Text = sprintf('%s\n%s· %d series · Fs %.4g Hz · %.3g to %.3g s', ...
                    app.FileName, typeShort, numel(tCell), app.Fs, t1(1), t1(end));
                app.plotSelected();
            end
            app.updateControls();
        end

        function onDataTypeChanged(app)
            if isempty(app.Data), return; end
            app.parseSeries();
            if isempty(app.SeriesT)
                UIKit.setStatus(app.W.Status, 'The file has no series for this data type', 'warning');
            else
                UIKit.setStatus(app.W.Status, sprintf('%d series for "%s"', numel(app.SeriesT), ...
                    app.DataTypeMenu.Value), 'info');
            end
        end

        %% onParamsChanged - t0/baseline/direction changed: results are stale
        function onParamsChanged(app)
            if app.HasResults
                app.ResultsTable.Data = {};
                app.HasResults = false;
                UIKit.setStatus(app.W.Status, 'Parameters changed: click Extract features again.', 'info');
            end
            app.plotSelected();
            app.updateControls();
        end

        function onTableSelect(app, evt)
            if isempty(evt.Indices), return; end
            r = evt.Indices(1, 1);
            data = app.ResultsTable.Data;
            if r <= size(data, 1) && ismember(data{r, 1}, app.SeriesMenu.Items)
                app.SeriesMenu.Value = data{r, 1};
                app.plotSelected();
            end
        end

        %% baselineWindow - [start end] from the fields, or [] when end <= start
        function bl = baselineWindow(app)
            bl = [app.BaselineStartEdit.Value, app.BaselineEndEdit.Value];
            if bl(2) <= bl(1), bl = []; end
        end

        function extractFeatures(app)
            if isempty(app.Data)
                UIKit.alert(app.UIFig, 'Load data first (step 1).', 'No data'); return;
            end
            app.T0 = app.T0Edit.Value;
            baseline = app.baselineWindow();
            app.Baseline = baseline;
            selected = app.FeatureList.Value;
            if ischar(selected), selected = {selected}; end

            tCell = app.SeriesT;
            yCell = app.SeriesY;
            if isempty(tCell)
                UIKit.alert(app.UIFig, 'Could not parse data for the selected data type.', 'No series');
                return;
            end
            dlg = UIKit.busy(app.UIFig, sprintf('Extracting features from %d series...', numel(tCell)));
            UIKit.setStatus(app.W.Status, 'Extracting features', 'busy');

            % Compute features for each series
            nSkipped = 0;
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

            try
                for k = 1:numel(tCell)
                    t = tCell{k}(:);
                    y = yCell{k}(:);
                    % Skip empty or malformed series (t and y must match)
                    if isempty(t) || numel(t) ~= numel(y)
                        nSkipped = nSkipped + 1;
                        continue;
                    end
                    baseVal = seriesBaseline(t, y, baseline, app.T0);
                    dirn = seriesDirection(t, y, baseVal, app.T0, app.DirectionMenu.Value);
                    names{end+1} = app.SeriesNames{k}; %#ok<AGROW>

                    if ismember('Peak latency', selected)
                        [lat, ~] = SignalFeatures.peakLatency(t, y, app.T0, dirn);
                        peakLat(end+1) = lat; %#ok<AGROW>
                    else, peakLat(end+1) = NaN; end %#ok<AGROW>
                    if ismember('Onset delay (50%)', selected)
                        onsetD(end+1) = SignalFeatures.onsetDelay(t, y, app.T0, 0.5, dirn, baseVal); %#ok<AGROW>
                    else, onsetD(end+1) = NaN; end %#ok<AGROW>
                    if ismember('FWHM', selected)
                        fwhm_(end+1) = SignalFeatures.fwhm(t, y, app.T0, dirn, baseVal); %#ok<AGROW>
                    else, fwhm_(end+1) = NaN; end %#ok<AGROW>
                    if ismember('AUC positive', selected)
                        aucP(end+1) = SignalFeatures.aucPositive(t, y, baseVal); %#ok<AGROW>
                    else, aucP(end+1) = NaN; end %#ok<AGROW>
                    if ismember('AUC negative', selected)
                        aucN(end+1) = SignalFeatures.aucNegative(t, y, baseVal); %#ok<AGROW>
                    else, aucN(end+1) = NaN; end %#ok<AGROW>
                    if ismember('Rise time', selected)
                        riseT(end+1) = SignalFeatures.riseTime(t, y, app.T0, dirn, baseVal); %#ok<AGROW>
                    else, riseT(end+1) = NaN; end %#ok<AGROW>
                    if ismember('Decay time', selected)
                        decT(end+1) = SignalFeatures.decayTime(t, y, app.T0, dirn, baseVal); %#ok<AGROW>
                    else, decT(end+1) = NaN; end %#ok<AGROW>
                    if ismember('Peak amplitude', selected)
                        [amp, ~] = SignalFeatures.peakAmplitude(t, y, app.T0, dirn, baseVal);
                        peakA(end+1) = amp; %#ok<AGROW>
                    else, peakA(end+1) = NaN; end %#ok<AGROW>
                    if ismember('Stim–response integral', selected)
                        stim = zeros(size(y)); stim(t >= app.T0) = 1;
                        integral_(end+1) = SignalFeatures.stimResponseIntegration(t, stim, y, app.T0); %#ok<AGROW>
                    else, integral_(end+1) = NaN; end %#ok<AGROW>
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, 'Feature extraction failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Feature extraction failed: %s', ME.message), 'Extract');
                return;
            end
            UIKit.done(dlg);

            app.ResultsTable.Data = [names(:), num2cell(peakLat(:)), num2cell(onsetD(:)), ...
                num2cell(fwhm_(:)), num2cell(aucP(:)), num2cell(aucN(:)), ...
                num2cell(riseT(:)), num2cell(decT(:)), num2cell(peakA(:)), num2cell(integral_(:))];
            app.HasResults = ~isempty(names);
            app.NFeatures = numel(selected);
            app.plotSelected();
            app.updateControls();
            if isempty(names)
                UIKit.setStatus(app.W.Status, 'No valid series: nothing extracted', 'error');
            elseif nSkipped > 0
                UIKit.setStatus(app.W.Status, sprintf('Extracted features for %d series; %d skipped', ...
                    numel(names), nSkipped), 'warning');
            else
                UIKit.setStatus(app.W.Status, sprintf('Extracted %d feature(s) for %d series. Next: Export (step 4).', ...
                    numel(selected), numel(names)), 'success');
            end
            if nSkipped > 0
                UIKit.alert(app.UIFig, sprintf('%d series skipped (empty, or t and y lengths differ).', nSkipped), ...
                    'Skipped series', 'warning');
            end
        end

        %% plotSelected - Plot the chosen series with t0, baseline and features
        % Peak and FWHM are always marked (from the same SignalFeatures calls
        % used for the table) so users can check the numbers visually.
        function plotSelected(app)
            T = UITheme;
            ax = app.Axes;
            k = find(strcmp(app.SeriesNames, app.SeriesMenu.Value), 1);
            if isempty(k)
                if isempty(app.Data), UIKit.emptyAxes(ax, 'Load a file to begin'); end
                return;
            end
            t = app.SeriesT{k}(:);
            y = app.SeriesY{k}(:);
            cla(ax, 'reset');
            if isempty(t) || numel(t) ~= numel(y)
                UIKit.emptyAxes(ax, sprintf('%s is skipped: t and y lengths differ', app.SeriesNames{k}));
                return;
            end
            t0 = app.T0Edit.Value;
            bl = app.baselineWindow();
            baseVal = seriesBaseline(t, y, bl, t0);
            dirn = seriesDirection(t, y, baseVal, t0, app.DirectionMenu.Value);
            hold(ax, 'on');
            % Baseline window (shaded) drawn first so the trace stays on top
            yr = [min(y) max(y)];
            if yr(1) == yr(2), yr = yr + [-1 1]; end
            hs = [];
            if ~isempty(bl)
                hs = patch(ax, [bl(1) bl(2) bl(2) bl(1)], yr([1 1 2 2]), T.shadeColor, ...
                    'FaceAlpha', 0.10, 'EdgeColor', 'none', 'DisplayName', 'Baseline window');
            end
            hy = plot(ax, t, y, 'Color', T.plotColors(1, :), 'LineWidth', 1.2, ...
                'DisplayName', app.SeriesNames{k});
            hb = plot(ax, t([1 end]), [baseVal baseVal], ':', 'Color', T.bodyColor, ...
                'LineWidth', 1, 'DisplayName', sprintf('Baseline %.3g', baseVal));
            ht = xline(ax, t0, '--', 'Color', T.stimColor, 'LineWidth', 1.2, 'DisplayName', 't0');
            handles = [hs, hy, hb, ht];
            % Peak and half-maximum width (same definitions as SignalFeatures)
            [amp, tPk] = SignalFeatures.peakAmplitude(t, y, t0, dirn, baseVal);
            if isfinite(amp)
                hp = plot(ax, tPk, baseVal + amp, 'o', 'MarkerSize', 8, 'LineWidth', 1.5, ...
                    'Color', T.plotColors(2, :), 'DisplayName', ...
                    sprintf('Peak %.3g at %.3g s', amp, tPk - t0));
                handles(end+1) = hp;
                [tA, tB, half] = fwhmSpan(t, y, t0, dirn, baseVal);
                if ~isempty(tA)
                    hw = plot(ax, [tA tB], [half half], '-', 'LineWidth', 2.5, ...
                        'Color', T.plotColors(3, :), 'DisplayName', sprintf('FWHM %.3g s', tB - tA));
                    handles(end+1) = hw;
                end
            end
            hold(ax, 'off');
            xlim(ax, [t(1) t(end)]);
            ttl = sprintf('%s  (%s response)', app.SeriesNames{k}, ...
                strrep(strrep(dirn, 'max', 'positive'), 'min', 'negative'));
            UIKit.styleAxes(ax, ttl, 'Time (s)', 'Signal');
            legend(ax, handles, 'Location', 'best', 'FontSize', T.fontTiny, 'Box', 'off');
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
                % ExtractEphysApp saves the LFP time vector as 't_lfp'
                if isfield(s, 't'), tv = s.t; elseif isfield(s, 't_lfp'), tv = s.t_lfp; else, tv = []; end
                if ~isempty(tv) && isfield(s, 'lfp_data')
                    y = mean(s.lfp_data, 1);
                    tCell = {tv(:)'};
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
                UIKit.alert(app.UIFig, 'No results to export. Run Extract features first (step 3).', 'Export');
                return;
            end
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = pwd; end
            [file, path] = uiputfile({'*.csv', 'CSV table (*.csv)'; '*.mat', 'MAT file (*.mat)'}, ...
                'Export features', fullfile(startDir, 'signal_features.csv'));
            figure(app.UIFig);
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
                UIKit.setStatus(app.W.Status, sprintf('Exported %d rows to %s', size(data, 1), file), 'success');
            catch ME
                UIKit.setStatus(app.W.Status, 'Export failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Export failed: %s', ME.message), 'Export');
            end
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% detectDataType - Data type menu item matching the variables in s ('' if none)
function dt = detectDataType(s)
    types = {'LDF segments (segmentedLDF, segmentedTime)', ...
        'ERP / average response (t, y or lfp_data)', 'Time series (t, y)'};
    if isfield(s, 'segmentedLDF') && isfield(s, 'segmentedTime')
        dt = types{1};
    elseif (isfield(s, 'lfp_data') && (isfield(s, 't') || isfield(s, 't_lfp'))) || ...
            (isfield(s, 'erp_avg') && isfield(s, 't') && isfield(s, 'y'))
        % LFP from Extract Ephys, or the ERP export of LFP analysis (t, y = channel mean)
        dt = types{2};
    elseif isfield(s, 't') && (isfield(s, 'y') || isfield(s, 'LDF'))
        dt = types{3};
    else
        dt = '';
    end
end

%% seriesBaseline - Reference level: mean in the baseline window, else fallbacks
% bl = [start end] or [] (first 0.05 s of the trace). Empty/NaN window:
% pre-onset mean, else y(1).
function baseVal = seriesBaseline(t, y, bl, t0)
    if isempty(bl)
        baseVal = mean(y(t >= t(1) & t < min(t(1)+0.05, t(end))));
    else
        idx = t >= bl(1) & t <= bl(2);
        baseVal = mean(y(idx));
    end
    if ~isfinite(baseVal)
        pre = y(t < t0);
        baseVal = mean(pre(isfinite(pre)));
        if ~isfinite(baseVal), baseVal = y(1); end
    end
end

%% seriesDirection - 'max' or 'min' from the menu value ('Auto' = larger deflection)
function dirn = seriesDirection(t, y, baseVal, t0, choice)
    switch choice
        case 'Positive', dirn = 'max';
        case 'Negative', dirn = 'min';
        otherwise
            post = y(t >= t0);
            if ~isempty(post) && (baseVal - min(post)) > (max(post) - baseVal)
                dirn = 'min';
            else
                dirn = 'max';
            end
    end
end

%% fwhmSpan - Start/end time of the half-maximum lobe around the peak (for plotting)
% Mirrors SignalFeatures.fwhm: contiguous samples after t0 past the half level.
function [tA, tB, half] = fwhmSpan(t, y, t0, dirn, baseVal)
    tA = []; tB = []; half = NaN;
    idx = t >= t0;
    t_ = t(idx); y_ = y(idx);
    if isempty(t_), return; end
    if strcmpi(dirn, 'min'), [pk, iPk] = min(y_); else, [pk, iPk] = max(y_); end
    if pk == baseVal, return; end
    half = baseVal + 0.5 * (pk - baseVal);
    if strcmpi(dirn, 'min'), past = y_ <= half; else, past = y_ >= half; end
    i1 = iPk; while i1 > 1 && past(i1 - 1), i1 = i1 - 1; end
    i2 = iPk; while i2 < numel(y_) && past(i2 + 1), i2 = i2 + 1; end
    tA = t_(i1); tB = t_(i2);
end

%% styleBtn - Switch a UIKit button between primary and secondary look
function styleBtn(b, isPrimary)
    T = UITheme;
    if isPrimary
        b.BackgroundColor = T.accent; b.FontColor = [1 1 1]; b.FontWeight = 'bold';
    else
        b.BackgroundColor = T.secondaryBg; b.FontColor = T.secondaryFg; b.FontWeight = 'normal';
    end
end
