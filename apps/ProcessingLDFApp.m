%% ProcessingLDFApp.m
% =========================================================================
% PROCESS LDF DATA - FILTER, DOWNSAMPLE, AND SEGMENT LDF BY STIMULUS ONSETS
% =========================================================================
% Launched from Main. Built with UIKit.window: numbered step cards on the
% left (1 Load, 2 Filter / downsample, 3 Segment trials, 4 Save) and a
% tab group on the right (Signals | Filter response | Trials). Loads a
% cropped LDF + stimulus .mat (stim, LDF, t, Fs from ExtractLDFApp),
% opens LDFProcessingParamsApp for downsample/filter settings (always
% applied to the loaded raw copy, LDF decimated with anti-aliasing),
% segments trials around stimulus onsets (threshold, pre, post, min ISI),
% plots all trials and the mean ± SD, and saves (or appends) segmented
% data for LDFGrandAverageApp. Key methods: loadData,
% receiveProcessingParams, applyFilter, segmentByOnsetsConfig,
% segmentLDFByOnsets, plotAverageSegment, saveData. updateControls()
% enables actions from the data state and marks the next step primary.
% "Try demo data" (loadDemo) opens DemoData's cropped LDF and pre-fills
% threshold 2.5, pre 5 s, post 20 s, min interval 10 s. Programmatic use (no
% dialogs): openFile(path), applyProcessingParams(params),
% setSegmentParams(thr, pre, post, isi), segmentByOnsetsConfig(), saveData(path).
% =========================================================================

classdef ProcessingLDFApp < handle
    %% PROPERTIES: UI handles, processing params, signals and segmented data
    properties
        UIFig            % Main uifigure (UIKit.window)
        StatusLabel      % Status bar label (UIKit.setStatus)
        HelpBtn          % Opens HelpApp('LDF Process')
        LoadBtn          % Step 1: load stim/LDF .mat
        DemoBtn          % Step 1: load synthetic cropped LDF (DemoData)
        FsLabel          % Step 1: file name, sampling rate, duration
        FilterBtn        % Step 2: open LDFProcessingParamsApp
        ResetBtn         % Step 2: discard processing, back to loaded data
        ProcessInfoLabel % Step 2: summary of the applied processing
        ThresholdInput   % Step 3: stimulus threshold
        PreInput         % Step 3: pre-onset window (s)
        PostInput        % Step 3: post-onset window (s)
        ISIInput         % Step 3: minimum inter-stimulus interval (s)
        SegmentBtn       % Step 3: segment trials
        SegmentInfoLabel % Step 3: number of trials / window
        SaveBtn          % Step 4: save or append segmented data
        Tabs             % uitabgroup on the right
        SignalsTab       % Tab: stimulus + LDF
        FilterTab        % Tab: filter frequency response
        TrialsTab        % Tab: segments + average
        AxStim           % uiaxes: stimulus
        AxLDF            % uiaxes: LDF (loaded vs processed)
        AxFreq           % uiaxes: filter magnitude response
        AxSeg            % uiaxes: all segments
        AxAvg            % uiaxes: average ± SD
        ThreshLine       % Threshold line on AxStim
        ProcessingParams % params struct from LDFProcessingParamsApp (applied)
        Stim             % stimulus after processing (downsampled if requested)
        LDF              % LDF after processing
        RawLDF           % LDF as loaded (processing always starts from Raw*)
        RawStim          % stimulus as loaded
        t                % time vector after processing
        tRaw             % time vector as loaded
        Fs               % sampling rate after processing
        RawFs            % sampling rate as loaded
        FilePath = ''    % loaded file
        SegmentedLDF     % segmented LDF trials [nTrials x nSamples]
        SegmentedTime    % time axis for each segment (s, 0 = onset)
    end

    methods
        %% Constructor - Build UI only; data loaded via Load File
        function app = ProcessingLDFApp()
            app.buildUI();
        end

        %% buildUI - Window, step cards (left), tabbed plots (right)
        function buildUI(app)
            T = UITheme;
            W = UIKit.window('LDF Processing', ...
                'Filter and downsample LDF, then cut trials around stimulus onsets', ...
                'LDF Process', [1200 760]);
            app.UIFig = W.Fig;
            app.StatusLabel = W.Status;
            app.HelpBtn = W.HelpBtn;
            W.Body.RowHeight = {'1x'};
            W.Body.ColumnWidth = {310, '1x'};

            left = uigridlayout(W.Body, [5 1], 'Padding', [0 0 0 0], 'RowSpacing', 10, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            heights = cell(1, 5);

            % --- 1 Load ---
            [p, g, heights{1}] = stepCard(left, 1, 'Load cropped LDF', {T.buttonHeight, T.buttonHeight, 48});
            p.Layout.Row = 1;
            app.LoadBtn = UIKit.button(g, 'Load file...', @(~,~)app.loadData(), 'primary', ...
                'Load a .mat file with stim, LDF, t and Fs (as saved by Extract LDF Data)');
            app.LoadBtn.Layout.Row = 2; app.LoadBtn.Layout.Column = [1 2];
            app.DemoBtn = UIKit.button(g, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Load a synthetic 260 s cropped LDF with known answers (9 stimuli of 5 s, 5 V TTL; ' ...
                'each followed by a +30 PU response peaking 4 s after onset) and pre-fill the segmentation']);
            app.DemoBtn.Layout.Row = 3; app.DemoBtn.Layout.Column = [1 2];
            app.FsLabel = infoLabel(g, 'No file loaded', 'File name, sampling rate and duration');
            app.FsLabel.Layout.Row = 4; app.FsLabel.Layout.Column = [1 2];

            % --- 2 Filter / downsample ---
            [p, g, heights{2}] = stepCard(left, 2, 'Filter / downsample (optional)', {T.buttonHeight, 48});
            p.Layout.Row = 2;
            app.FilterBtn = UIKit.button(g, 'Settings...', @(~,~)app.openProcessingSettings(), ...
                'secondary', 'Choose downsampling, filter type, design, cutoffs and order, then apply them to the loaded LDF');
            app.FilterBtn.Layout.Row = 2; app.FilterBtn.Layout.Column = 1;
            app.ResetBtn = UIKit.button(g, 'Undo', @(~,~)app.resetProcessing(), ...
                'secondary', 'Discard filtering/downsampling and go back to the loaded signal');
            app.ResetBtn.Layout.Row = 2; app.ResetBtn.Layout.Column = 2;
            app.ProcessInfoLabel = infoLabel(g, 'Not processed (using loaded signal)', ...
                'Processing currently applied to the LDF signal');
            app.ProcessInfoLabel.Layout.Row = 3; app.ProcessInfoLabel.Layout.Column = [1 2];

            % --- 3 Segment ---
            ch = T.controlHeight;
            [p, g, heights{3}] = stepCard(left, 3, 'Segment trials', {ch, ch, ch, ch, T.buttonHeight, 34});
            p.Layout.Row = 3;
            app.ThresholdInput = addField(g, 2, 'Stim threshold', 'numeric', 0.5, ...
                'Stimulus level that marks an onset (rising edge crossing). Shown as a dashed line on the stimulus plot', [-Inf Inf]);
            app.PreInput = addField(g, 3, 'Pre-onset (s)', 'numeric', 2, ...
                'Seconds kept before each onset (baseline)', [0 Inf]);
            app.PostInput = addField(g, 4, 'Post-onset (s)', 'numeric', 4, ...
                'Seconds kept after each onset (must be > 0)', [0 Inf]);
            app.PostInput.LowerLimitInclusive = 'off';
            app.ISIInput = addField(g, 5, 'Min interval (s)', 'numeric', 1, ...
                'Minimum time between two onsets; extra edges within this interval (e.g. pulse trains) are ignored', [0 Inf]);
            app.ThresholdInput.ValueChangedFcn = @(~,~)app.drawThreshold();
            app.SegmentBtn = UIKit.button(g, 'Segment trials', @(~,~)app.segmentByOnsetsConfig(), ...
                'secondary', 'Detect stimulus onsets and cut the LDF into trials of [-pre, +post] seconds');
            app.SegmentBtn.Layout.Row = 6; app.SegmentBtn.Layout.Column = [1 2];
            app.SegmentInfoLabel = infoLabel(g, 'No trials yet', 'Result of the last segmentation');
            app.SegmentInfoLabel.Layout.Row = 7; app.SegmentInfoLabel.Layout.Column = [1 2];

            % --- 4 Save ---
            [p, g, heights{4}] = stepCard(left, 4, 'Save trials', {T.buttonHeight, 34});
            p.Layout.Row = 4;
            app.SaveBtn = UIKit.button(g, 'Save trials...', @(~,~)app.saveData(), 'secondary', ...
                'Save segmentedLDF, segmentedTime and Fs to .mat; choosing an existing file appends the trials to it');
            app.SaveBtn.Layout.Row = 2; app.SaveBtn.Layout.Column = [1 2];
            note = infoLabel(g, 'Choosing an existing file appends to it. Open the files in LDF Average.', ...
                'Trials are appended when the time axes match');
            note.Layout.Row = 3; note.Layout.Column = [1 2];

            heights{5} = '1x';
            left.RowHeight = heights;

            % --- Plots: tabs ---
            app.Tabs = uitabgroup(W.Body);
            app.Tabs.Layout.Row = 1; app.Tabs.Layout.Column = 2;
            app.SignalsTab = uitab(app.Tabs, 'Title', 'Signals', 'BackgroundColor', T.cardBg);
            app.FilterTab  = uitab(app.Tabs, 'Title', 'Filter response', 'BackgroundColor', T.cardBg);
            app.TrialsTab  = uitab(app.Tabs, 'Title', 'Trials', 'BackgroundColor', T.cardBg);

            gs = uigridlayout(app.SignalsTab, [2 1], 'RowHeight', {'1x', '1x'}, ...
                'Padding', [8 8 14 8], 'RowSpacing', 8, 'BackgroundColor', T.cardBg);
            app.AxStim = uiaxes(gs);
            app.AxLDF  = uiaxes(gs);
            gf = uigridlayout(app.FilterTab, [1 1], 'Padding', [8 8 14 8], 'BackgroundColor', T.cardBg);
            app.AxFreq = uiaxes(gf);
            gt = uigridlayout(app.TrialsTab, [2 1], 'RowHeight', {'1x', '1x'}, ...
                'Padding', [8 8 14 8], 'RowSpacing', 8, 'BackgroundColor', T.cardBg);
            app.AxSeg = uiaxes(gt);
            app.AxAvg = uiaxes(gt);

            % styleAxes first: it removes emptyAxes placeholders
            UIKit.styleAxes(app.AxStim, 'Stimulus');
            UIKit.styleAxes(app.AxLDF, 'LDF');
            UIKit.styleAxes(app.AxFreq, 'Filter frequency response');
            UIKit.styleAxes(app.AxSeg, 'Trials');
            UIKit.styleAxes(app.AxAvg, 'Average LDF');
            UIKit.emptyAxes(app.AxStim, 'Load a cropped LDF file (or Try demo data) to begin');
            UIKit.emptyAxes(app.AxLDF, 'LDF signal appears here');
            UIKit.emptyAxes(app.AxFreq, 'Apply a filter (step 2) to see its frequency response');
            UIKit.emptyAxes(app.AxSeg, 'Segment trials (step 3) to see them here');
            UIKit.emptyAxes(app.AxAvg, 'Average ± SD appears after segmentation');

            UIKit.setStatus(app.StatusLabel, 'Step 1: load a cropped LDF file (from Extract LDF Data).', 'info');
            app.updateControls();
        end

        %% updateControls - Enable controls from data state; next step is primary
        % -------------------------------------------------------------
        % Load -> (Filter optional) -> Segment -> Save. Everything after
        % Load needs data; Save needs segmented trials; Undo needs an
        % applied processing step.
        % -------------------------------------------------------------
        function updateControls(app)
            hasData = ~isempty(app.RawLDF) && ~isempty(app.RawFs) && app.RawFs > 0;
            hasProc = hasData && ~isempty(app.ProcessingParams);
            hasSeg = ~isempty(app.SegmentedLDF) && ~isempty(app.SegmentedTime);

            app.FilterBtn.Enable = onoff(hasData);
            app.ResetBtn.Enable  = onoff(hasProc);
            for c = {app.ThresholdInput, app.PreInput, app.PostInput, app.ISIInput}
                c{1}.Enable = onoff(hasData);
            end
            app.SegmentBtn.Enable = onoff(hasData);
            app.SaveBtn.Enable = onoff(hasSeg);

            setButtonStyle(app.LoadBtn, ifelse(~hasData, 'primary', 'secondary'));
            setButtonStyle(app.SegmentBtn, ifelse(hasData && ~hasSeg, 'primary', 'secondary'));
            setButtonStyle(app.SaveBtn, ifelse(hasSeg, 'primary', 'secondary'));

            if hasProc
                app.ProcessInfoLabel.Text = describeParams(app.ProcessingParams, app.Fs);
                app.ProcessInfoLabel.FontColor = UITheme.success;
            else
                app.ProcessInfoLabel.Text = 'Not processed (using loaded signal)';
                app.ProcessInfoLabel.FontColor = UITheme.bodyColor;
            end
            if hasSeg
                app.SegmentInfoLabel.Text = sprintf('%d trials, %.2f to %.2f s around onset', ...
                    size(app.SegmentedLDF, 1), app.SegmentedTime(1), app.SegmentedTime(end));
                app.SegmentInfoLabel.FontColor = UITheme.success;
            else
                app.SegmentInfoLabel.Text = 'No trials yet';
                app.SegmentInfoLabel.FontColor = UITheme.bodyColor;
            end
        end

        %% loadData - Pick a .mat with stim, LDF, t, Fs, then openFile(path)
        function loadData(app)
            UIKit.setStatus(app.StatusLabel, 'Choose a cropped LDF file...', 'busy');
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = Exporter.getLastUsedPath(); end
            if isempty(startDir), startDir = pwd; end
            [file, path] = uigetfile(fullfile(startDir, '*.mat'), 'Load cropped LDF data');
            figure(app.UIFig);
            if isequal(file, 0)
                UIKit.setStatus(app.StatusLabel, 'Load cancelled.', 'info');
                return;
            end
            app.openFile(fullfile(path, file));
        end

        %% openFile - Load a cropped LDF .mat by path (no dialog) and plot it
        % -------------------------------------------------------------
        % Validates required variables (as saved by Exporter.saveCropped).
        % Keeps untouched Raw* copies so re-running processing never
        % compounds, and clears results from a previous file. Returns
        % true on success; on failure the previous data is kept.
        % -------------------------------------------------------------
        function ok = openFile(app, filePath)
            ok = false;
            [path, name, ext] = fileparts(filePath);
            file = [name ext];
            dlg = UIKit.busy(app.UIFig, sprintf('Loading %s...', file));
            try
                data = load(filePath);
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load %s.', file), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not load %s:\n%s', file, ME.message), 'Load error', 'error');
                return;
            end
            UIKit.done(dlg);

            % Validate required variables (as saved by Exporter.saveCropped)
            required = {'stim', 'LDF', 't', 'Fs'};
            missing = required(~isfield(data, required));
            if ~isempty(missing)
                msg = sprintf(['Invalid LDF file. Missing variable(s): %s.\n' ...
                    'Use a file saved by Extract LDF Data (stim, LDF, t, Fs).'], strjoin(missing, ', '));
                UIKit.setStatus(app.StatusLabel, sprintf('%s is not a cropped LDF file.', file), 'error');
                UIKit.alert(app.UIFig, msg, 'Invalid file', 'error');
                return;
            end

            app.Stim = data.stim;
            app.LDF  = data.LDF;
            app.t    = data.t;
            app.Fs   = data.Fs;
            % Keep untouched copies so re-running processing never compounds
            app.RawLDF  = app.LDF;
            app.RawStim = app.Stim;
            app.tRaw    = data.t;
            app.RawFs   = data.Fs;
            app.FilePath = filePath;
            Exporter.setLastUsedPath(path);
            % Results from a previous file no longer apply
            app.ProcessingParams = [];
            app.SegmentedLDF = [];
            app.SegmentedTime = [];
            app.updateSamplingRateLabel();

            app.plotSignals(false);
            UIKit.styleAxes(app.AxFreq, 'Filter frequency response');
            UIKit.emptyAxes(app.AxFreq, 'Apply a filter (step 2) to see its frequency response');
            app.clearTrialPlots();
            app.Tabs.SelectedTab = app.SignalsTab;
            app.updateControls();
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf(['Loaded %s (%g Hz, %s). Next: optionally filter (step 2), ' ...
                'then check the threshold line and segment trials (step 3).'], ...
                file, app.Fs, formatDuration(numel(app.LDF) / app.Fs)), 'success');
        end

        %% loadDemo - Load the synthetic cropped LDF (DemoData) and pre-fill step 3
        % -------------------------------------------------------------
        % 260 s at 1000 Hz, 9 stimuli (5 s, 5 V TTL) at 10, 40, ..., 250 s.
        % Pre-fills threshold 2.5, pre 5 s, post 20 s, min interval 10 s so
        % "Segment trials" is the next click. The last used folder is not
        % changed by the demo.
        % -------------------------------------------------------------
        function loadDemo(app)
            prevLast = Exporter.getLastUsedPath();
            dlg = UIKit.busy(app.UIFig, 'Preparing demo data (first time only takes a few seconds)…');
            try
                p = DemoData.file('ldfCropped');
                UIKit.done(dlg);
                ok = app.openFile(p);
                restoreLastPath(prevLast);
                if ~ok, return; end
                app.setSegmentParams(2.5, 5, 20, 10);
                nStim = sum(diff([false; app.RawStim(:) > 2.5]) == 1);
                UIKit.setStatus(app.StatusLabel, sprintf(['Demo loaded: %s cropped LDF with %d stimuli (5 s each). ' ...
                    'Threshold 2.5, window -5 to +20 s pre-filled. Next: optionally filter (step 2), ' ...
                    'then press "Segment trials".'], formatDuration(numel(app.LDF) / app.Fs), nStim), 'success');
            catch ME
                UIKit.done(dlg);
                restoreLastPath(prevLast);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load the demo data: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not load the demo data:\n%s', ME.message), 'Demo data', 'error');
            end
        end

        %% setSegmentParams - Fill the step-3 fields programmatically
        % Any argument may be [] to keep the current value. Redraws the
        % threshold line; call segmentByOnsetsConfig() to segment.
        function setSegmentParams(app, threshold, preSec, postSec, minISI)
            if nargin >= 2 && ~isempty(threshold), app.ThresholdInput.Value = threshold; end
            if nargin >= 3 && ~isempty(preSec),    app.PreInput.Value = preSec; end
            if nargin >= 4 && ~isempty(postSec),   app.PostInput.Value = postSec; end
            if nargin >= 5 && ~isempty(minISI),    app.ISIInput.Value = minISI; end
            app.drawThreshold();
        end

        %% openProcessingSettings - Open LDFProcessingParamsApp for the raw Fs
        function openProcessingSettings(app)
            if isempty(app.RawFs) || app.RawFs <= 0
                UIKit.alert(app.UIFig, 'Please load a dataset first.', 'No data', 'warning');
                return;
            end
            UIKit.setStatus(app.StatusLabel, 'Choose processing settings in the dialog, then click Apply.', 'info');
            % Raw Fs: processing is always applied to the loaded (raw) signal
            dlg = LDFProcessingParamsApp(@(params)app.receiveProcessingParams(params), app.RawFs);
            uiwait(dlg.UIFig);
            if isvalid(app.UIFig) && isempty(dlg.Params)
                UIKit.setStatus(app.StatusLabel, 'Processing settings cancelled; nothing changed.', 'info');
            end
        end

        %% receiveProcessingParams - Callback from LDFProcessingParamsApp
        function receiveProcessingParams(app, params)
            app.applyProcessingParams(params);
        end

        %% applyProcessingParams - Apply processing params without the dialog
        % -------------------------------------------------------------
        % params (as LDFProcessingParamsApp returns): downsample (integer
        % factor, 1 = none), filterType (1 none, 2 low-pass, 3 high-pass,
        % 4 band-pass, 5 notch), designType (1 Butterworth, 2 Chebyshev I,
        % 3 FIR), filterOrder, cutoffLow, cutoffHigh (Hz; NaN if unused).
        % If they fail validation the previous processing (if any) stays in
        % place and ok = false.
        % -------------------------------------------------------------
        function ok = applyProcessingParams(app, params)
            prev = app.ProcessingParams;
            app.ProcessingParams = params;
            ok = app.applyFilter();
            if ~ok
                app.ProcessingParams = prev;
                app.updateControls();
            end
        end

        %% applyFilter - Downsample (decimate) and filter the loaded LDF
        % -------------------------------------------------------------
        % Always starts from Raw* (never from a previous result). LDF is
        % decimated (anti-alias low-pass + downsample); the TTL stimulus
        % and time vector are sample-picked, then all trimmed to a common
        % length. Filter is designed at the post-downsample Fs and applied
        % zero-phase (filtfilt). Returns true on success.
        % -------------------------------------------------------------
        function ok = applyFilter(app)
            ok = false;
            if isempty(app.RawLDF) || isempty(app.ProcessingParams)
                UIKit.alert(app.UIFig, 'Missing data or parameters.', 'Cannot process', 'error');
                return;
            end

            % Always start from the loaded (raw) data, not a previous result
            LDF = app.RawLDF;
            t = app.tRaw;
            stim = app.RawStim;
            Fs = app.RawFs;
            p = app.ProcessingParams;
            FsNew = Fs;
            if p.downsample > 1, FsNew = Fs / p.downsample; end

            % Validate filter settings against the post-downsample Nyquist
            if p.filterType ~= 1
                msg = '';
                if any([p.cutoffLow, p.cutoffHigh] >= FsNew/2)
                    msg = sprintf('Cutoff frequency must be below Nyquist (Fs/2 = %g Hz).', FsNew/2);
                elseif p.cutoffLow >= p.cutoffHigh && ismember(p.filterType, [4, 5])
                    msg = 'For band-pass and notch filters, Low cutoff must be < High cutoff.';
                elseif p.filterOrder <= 0 || isnan(p.filterOrder)
                    msg = 'Filter order must be a positive number.';
                end
                if ~isempty(msg)
                    UIKit.setStatus(app.StatusLabel, ['Processing not applied: ' msg], 'error');
                    UIKit.alert(app.UIFig, msg, 'Invalid filter settings', 'error');
                    return;
                end
            end

            UIKit.setStatus(app.StatusLabel, 'Processing LDF...', 'busy');
            dlg = UIKit.busy(app.UIFig, 'Downsampling and filtering LDF...');
            try
                % Downsample
                if p.downsample > 1
                    % decimate = anti-alias lowpass + downsample (length ceil(N/r))
                    LDFdec = decimate(double(LDF(:)), p.downsample);
                    if isrow(LDF), LDFdec = LDFdec.'; end  % keep original orientation
                    LDF = LDFdec;
                    % Stim is a TTL: plain sample picking keeps edges sharp
                    stim = downsample(stim, p.downsample);
                    t = downsample(t, p.downsample);
                    n = min([numel(LDF), numel(stim), numel(t)]);
                    LDF = LDF(1:n); stim = stim(1:n); t = t(1:n);
                    Fs = Fs / p.downsample;
                end

                % Filter (skip if no filtering)
                b = []; a = [];
                if p.filterType == 1
                    filteredLDF = LDF;
                else
                    Wn = [];  % Normalized cutoff
                    filterOrder = p.filterOrder;
                    switch p.filterType
                        case 2  % Low-pass
                            Wn = p.cutoffHigh / (Fs/2);
                        case 3  % High-pass
                            Wn = p.cutoffLow / (Fs/2);
                        case 4  % Band-pass
                            Wn = [p.cutoffLow p.cutoffHigh] / (Fs/2);
                        case 5  % Notch
                            Wn = [p.cutoffLow p.cutoffHigh] / (Fs/2);
                    end
                    % Design filter
                    mode = app.getFilterMode(p.filterType);
                    switch p.designType
                        case 1  % Butterworth
                            [b, a] = butter(filterOrder, Wn, mode);
                        case 2  % Chebyshev I
                            [b, a] = cheby1(filterOrder, 0.5, Wn, mode);
                        case 3  % FIR
                            b = fir1(filterOrder, Wn, mode);
                            a = 1;
                    end
                    % Apply filter (zero-phase)
                    filteredLDF = filtfilt(b, a, LDF);
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, 'Processing failed.', 'error');
                UIKit.alert(app.UIFig, sprintf(['Processing failed:\n%s\n\nCheck the settings ' ...
                    '(e.g. a lower filter order for short recordings) and that the Signal ' ...
                    'Processing Toolbox is installed.'], ME.message), 'Processing error', 'error');
                return;
            end
            UIKit.done(dlg);

            % Update
            app.LDF = filteredLDF;
            app.Stim = stim;
            app.t = t;
            app.Fs = Fs;
            % Trials cut from the previous signal no longer match
            app.SegmentedLDF = [];
            app.SegmentedTime = [];
            app.updateSamplingRateLabel();

            app.plotSignals(true);
            app.plotFilterResponse(b, a, Fs);
            app.clearTrialPlots();
            app.Tabs.SelectedTab = app.SignalsTab;
            ok = true;
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf('Processed LDF: %s. Next: segment trials (step 3).', ...
                describeParams(p, Fs)), 'success');
        end

        %% resetProcessing - Back to the loaded (raw) signals
        function resetProcessing(app)
            if isempty(app.RawLDF), return; end
            app.LDF = app.RawLDF;
            app.Stim = app.RawStim;
            app.t = app.tRaw;
            app.Fs = app.RawFs;
            app.ProcessingParams = [];
            app.SegmentedLDF = [];
            app.SegmentedTime = [];
            app.updateSamplingRateLabel();
            app.plotSignals(false);
            UIKit.styleAxes(app.AxFreq, 'Filter frequency response');
            UIKit.emptyAxes(app.AxFreq, 'Apply a filter (step 2) to see its frequency response');
            app.clearTrialPlots();
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, 'Processing removed; using the loaded signal.', 'info');
        end

        %% getFilterMode - filterType index -> butter/cheby1/fir1 mode string
        function mode = getFilterMode(~, filterType)
            switch filterType
                case 2
                    mode = 'low';
                case 3
                    mode = 'high';
                case 4
                    mode = 'bandpass';
                case 5
                    mode = 'stop';
                otherwise
                    mode = 'low';
            end
        end

        %% segmentByOnsetsConfig - Read and validate step-3 fields, segment
        function segmentByOnsetsConfig(app)
            if isempty(app.Fs) || app.Fs <= 0
                UIKit.alert(app.UIFig, 'Please load a dataset first.', 'No data', 'warning');
                return;
            end
            threshold = app.ThresholdInput.Value;
            preSec    = app.PreInput.Value;
            postSec   = app.PostInput.Value;
            minISI    = app.ISIInput.Value;

            if any(isnan([threshold preSec postSec minISI]))
                UIKit.alert(app.UIFig, 'All fields must be numeric.', 'Invalid segmentation settings', 'error');
                return;
            end
            if preSec < 0 || postSec <= 0 || minISI < 0
                UIKit.alert(app.UIFig, 'Pre must be >= 0, Post > 0 and Min interval >= 0 (seconds).', ...
                    'Invalid segmentation settings', 'error');
                return;
            end
            app.segmentLDFByOnsets(threshold, preSec, postSec, minISI);
        end

        %% segmentLDFByOnsets - Detect debounced onsets and cut LDF trials
        % -------------------------------------------------------------
        % Rising edges of Stim > threshold; an edge is kept only if at
        % least minISI_sec after the last accepted one. Trials that do not
        % fit completely ([onset-pre, onset+post]) are skipped.
        % -------------------------------------------------------------
        function segmentLDFByOnsets(app, threshold, preSec, postSec, minISI_sec)
            if isempty(app.Stim) || isempty(app.LDF)
                UIKit.alert(app.UIFig, 'Stimulus or LDF data missing.', 'No data', 'error');
                return;
            end
            UIKit.setStatus(app.StatusLabel, 'Detecting onsets and cutting trials...', 'busy');

            ldf = app.LDF;
            Fs = app.Fs;

            % 1. Threshold and detect rising edges
            stimLogic = app.Stim > threshold;
            stimLogic = stimLogic(:);  % ensure column vector
            rawOnsets = find(diff([0; stimLogic]) == 1);  % all rising edges

            % 2. Debounce: only keep one onset per pulse
            minISI_samp = round(minISI_sec * app.Fs);
            onsets = [];
            lastAccepted = -inf;
            for i = 1:length(rawOnsets)
                if rawOnsets(i) - lastAccepted >= minISI_samp
                    onsets(end+1) = rawOnsets(i); %#ok<AGROW>
                    lastAccepted = rawOnsets(i);
                end
            end

            preSamp = round(preSec * Fs);
            postSamp = round(postSec * Fs);
            segLength = preSamp + postSamp + 1;

            validSegments = zeros(0, 2);
            for i = 1:length(onsets)
                idx = onsets(i);
                startIdx = idx - preSamp;
                endIdx = idx + postSamp;
                if startIdx > 0 && endIdx <= length(ldf)
                    validSegments = [validSegments; startIdx endIdx]; %#ok<AGROW>
                end
            end

            app.drawOnsets(onsets);
            if isempty(validSegments)
                if isempty(onsets)
                    msg = sprintf(['No stimulus onsets found above threshold %g. ' ...
                        'Check the dashed threshold line on the stimulus plot.'], threshold);
                else
                    msg = sprintf(['%d onsets found, but no complete trial fits in the recording ' ...
                        'with Pre = %g s and Post = %g s. Try shorter windows.'], numel(onsets), preSec, postSec);
                end
                UIKit.setStatus(app.StatusLabel, 'No complete trials found.', 'error');
                UIKit.alert(app.UIFig, msg, 'No complete trials', 'error');
                return;
            end

            % 3. Create LDF segment matrix
            nTrials = size(validSegments, 1);
            ldfSegments = zeros(nTrials, segLength);
            for i = 1:nTrials
                ldfSegments(i,:) = ldf(validSegments(i,1):validSegments(i,2));
            end
            t_seg = (-preSamp:postSamp) / Fs;

            % 4. Store for further analysis and plot
            app.SegmentedLDF = ldfSegments;
            app.SegmentedTime = t_seg;
            app.plotSegments();
            app.plotAverageSegment();
            app.Tabs.SelectedTab = app.TrialsTab;
            app.updateControls();
            skipped = numel(onsets) - nTrials;
            if skipped > 0
                UIKit.setStatus(app.StatusLabel, sprintf(['%d trials cut (%d onsets found, %d too close to the ' ...
                    'recording edges). Next: save the trials.'], nTrials, numel(onsets), skipped), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('%d trials cut from %d onsets. Next: save the trials.', ...
                    nTrials, numel(onsets)), 'success');
            end
        end

        %% updateSamplingRateLabel - File name, Fs (loaded -> current), duration
        function updateSamplingRateLabel(app)
            if isempty(app.Fs)
                app.FsLabel.Text = 'No file loaded';
                app.FsLabel.FontColor = UITheme.bodyColor;
                return;
            end
            [~, name, ext] = fileparts(app.FilePath);
            if ~isempty(app.RawFs) && app.Fs ~= app.RawFs
                fsText = sprintf('%g Hz (loaded %g Hz)', app.Fs, app.RawFs);
            else
                fsText = sprintf('%g Hz', app.Fs);
            end
            app.FsLabel.Text = sprintf('%s%s\n%s  ·  %s  ·  %d samples', name, ext, fsText, ...
                formatDuration(numel(app.LDF) / app.Fs), numel(app.LDF));
            app.FsLabel.FontColor = UITheme.sectionTitleColor;
        end

        %% plotSignals - Stimulus + LDF (loaded vs processed when processed)
        function plotSignals(app, processed)
            T = UITheme;
            cla(app.AxStim); cla(app.AxLDF);
            for ax = [app.AxStim app.AxLDF]
                ax.XTickMode = 'auto'; ax.YTickMode = 'auto';
                ax.XLimMode = 'auto'; ax.YLimMode = 'auto';
            end
            plot(app.AxStim, app.t, app.Stim, 'Color', T.stimColor);
            UIKit.styleAxes(app.AxStim, 'Stimulus', 'Time (s)', 'Amplitude');
            if processed
                hold(app.AxLDF, 'on');
                plot(app.AxLDF, app.tRaw(:), app.RawLDF(:), 'Color', T.plotColors(7, :), ...
                    'LineStyle', '--', 'DisplayName', 'Loaded LDF');
                plot(app.AxLDF, app.t(:), app.LDF(:), 'Color', T.plotColors(1, :), ...
                    'LineWidth', 1.2, 'DisplayName', 'Processed LDF');
                hold(app.AxLDF, 'off');
                legend(app.AxLDF, 'Location', 'best', 'Box', 'off');
                UIKit.styleAxes(app.AxLDF, 'Processed vs. loaded LDF', 'Time (s)', 'LDF');
            else
                legend(app.AxLDF, 'off');
                plot(app.AxLDF, app.t, app.LDF, 'Color', T.plotColors(1, :));
                UIKit.styleAxes(app.AxLDF, 'Loaded LDF', 'Time (s)', 'LDF');
            end
            try linkaxes([app.AxStim app.AxLDF], 'x'); catch, end
            app.ThreshLine = [];
            app.drawThreshold();
        end

        %% drawThreshold - Dashed threshold line on the stimulus axes
        function drawThreshold(app)
            if ~isempty(app.ThreshLine) && isgraphics(app.ThreshLine)
                delete(app.ThreshLine);
            end
            app.ThreshLine = [];
            if isempty(app.Stim), return; end
            app.ThreshLine = yline(app.AxStim, app.ThresholdInput.Value, '--', 'Threshold', ...
                'Color', UITheme.plotColors(2, :), 'LabelHorizontalAlignment', 'left');
        end

        %% drawOnsets - Mark accepted onsets on the stimulus axes
        function drawOnsets(app, onsets)
            delete(findobj(app.AxStim, 'Tag', 'onsetMarks'));
            onsets = onsets(onsets <= numel(app.t));
            if isempty(onsets), return; end
            hold(app.AxStim, 'on');
            plot(app.AxStim, app.t(onsets), repmat(app.ThresholdInput.Value, 1, numel(onsets)), 'v', ...
                'Color', UITheme.plotColors(2, :), 'MarkerFaceColor', UITheme.plotColors(2, :), ...
                'MarkerSize', 5, 'Tag', 'onsetMarks');
            hold(app.AxStim, 'off');
        end

        %% plotFilterResponse - Magnitude response of the designed filter
        function plotFilterResponse(app, b, a, Fs)
            T = UITheme;
            cla(app.AxFreq);
            app.AxFreq.XTickMode = 'auto'; app.AxFreq.YTickMode = 'auto';
            app.AxFreq.XLimMode = 'auto'; app.AxFreq.YLimMode = 'auto';
            if isempty(b)
                UIKit.styleAxes(app.AxFreq, 'Filter frequency response');
                UIKit.emptyAxes(app.AxFreq, 'No filter applied (downsampling only)');
                return;
            end
            [h, f] = freqz(b, a, 1024, Fs);
            plot(app.AxFreq, f, 20*log10(abs(h) + eps), 'Color', T.plotColors(1, :), 'LineWidth', 1.5);
            UIKit.styleAxes(app.AxFreq, 'Filter frequency response (single pass; filtfilt doubles dB)', ...
                'Frequency (Hz)', 'Magnitude (dB)');
            ylim(app.AxFreq, [max(-100, min(20*log10(abs(h) + eps))) 5]);
        end

        %% plotSegments - All trials overlaid, onset at 0
        function plotSegments(app)
            T = UITheme;
            ax = app.AxSeg;
            cla(ax);
            ax.XTickMode = 'auto'; ax.YTickMode = 'auto';
            ax.XLimMode = 'auto'; ax.YLimMode = 'auto';
            ax.ColorOrder = T.plotColors;
            hold(ax, 'on');
            plot(ax, app.SegmentedTime, app.SegmentedLDF');
            xline(ax, 0, '-', 'Color', T.stimColor, 'LineWidth', 1.2);
            hold(ax, 'off');
            UIKit.styleAxes(ax, sprintf('LDF trials (n = %d)', size(app.SegmentedLDF, 1)), ...
                'Time from onset (s)', 'LDF');
        end

        %% plotAverageSegment - Mean ± SD of the segmented trials
        function plotAverageSegment(app)
            if isempty(app.SegmentedLDF) || isempty(app.SegmentedTime)
                UIKit.alert(app.UIFig, 'No segmented LDF data available.', 'No trials', 'warning');
                return;
            end
            T = UITheme;
            segments = app.SegmentedLDF;
            t_seg = app.SegmentedTime(:)';
            avgLDF = mean(segments, 1);
            stdLDF = std(segments, 0, 1);

            ax = app.AxAvg;
            cla(ax);
            ax.XTickMode = 'auto'; ax.YTickMode = 'auto';
            ax.XLimMode = 'auto'; ax.YLimMode = 'auto';
            hold(ax, 'on');
            % Shaded area: mean ± std
            fill(ax, [t_seg, fliplr(t_seg)], [avgLDF + stdLDF, fliplr(avgLDF - stdLDF)], ...
                T.shadeColor, 'EdgeColor', 'none', 'FaceAlpha', 0.2, 'DisplayName', '± SD');
            plot(ax, t_seg, avgLDF, 'Color', T.plotColors(1, :), 'LineWidth', 2, 'DisplayName', 'Mean');
            xline(ax, 0, '-', 'Color', T.stimColor, 'LineWidth', 1.2, 'HandleVisibility', 'off');
            hold(ax, 'off');
            legend(ax, 'Location', 'best', 'Box', 'off');
            UIKit.styleAxes(ax, sprintf('Average LDF (n = %d trials)', size(segments, 1)), ...
                'Time from onset (s)', 'LDF');
        end

        %% clearTrialPlots - Placeholders on the Trials tab
        function clearTrialPlots(app)
            legend(app.AxAvg, 'off');
            UIKit.styleAxes(app.AxSeg, 'Trials');
            UIKit.styleAxes(app.AxAvg, 'Average LDF');
            UIKit.emptyAxes(app.AxSeg, 'Segment trials (step 3) to see them here');
            UIKit.emptyAxes(app.AxAvg, 'Average ± SD appears after segmentation');
        end

        %% saveData - Save (or append to) segmented data .mat
        % -------------------------------------------------------------
        % Saves segmentedLDF, segmentedTime, Fs. If the chosen file already
        % holds segmentedLDF/segmentedTime, trials are appended when the
        % time axes match (otherwise refused). With fullpath given, no
        % dialog is shown (programmatic use).
        % -------------------------------------------------------------
        function saveData(app, fullpath)
            if isempty(app.SegmentedLDF)
                UIKit.alert(app.UIFig, 'No segmented data to save. Segment trials first (step 3).', ...
                    'Nothing to save', 'warning');
                return;
            end
            if nargin < 2 || isempty(fullpath)
                UIKit.setStatus(app.StatusLabel, 'Choose where to save the trials...', 'busy');
                startDir = ProjectManager.getExportDir();
                if isempty(startDir), startDir = Exporter.getLastUsedPath(); end
                [~, base] = fileparts(app.FilePath);
                defName = '*.mat';
                if ~isempty(base), defName = [base '_segments.mat']; end
                [file, path] = uiputfile(fullfile(startDir, defName), 'Save or Append Segmented Data As');
                figure(app.UIFig);
                if isequal(file, 0)
                    UIKit.setStatus(app.StatusLabel, 'Save cancelled.', 'info');
                    return;
                end
                fullpath = fullfile(path, file);
            else
                [path, name, ext] = fileparts(fullpath);
                file = [name ext];
            end

            segmentedLDF = app.SegmentedLDF;
            segmentedTime = app.SegmentedTime;
            Fs = app.Fs;
            appended = false;
            try
                if isfile(fullpath)
                    % Append to existing file
                    existing = load(fullpath);
                    if isfield(existing, 'segmentedLDF') && isfield(existing, 'segmentedTime')
                        if ~isequal(existing.segmentedTime, segmentedTime)
                            UIKit.setStatus(app.StatusLabel, 'Not saved: time axes do not match.', 'error');
                            UIKit.alert(app.UIFig, ['Time axes do not match. Cannot append segments. ' ...
                                'Use the same Pre/Post windows and sampling rate, or choose a new file.'], ...
                                'Cannot append', 'error');
                            return;
                        end
                        segmentedLDF = [existing.segmentedLDF; segmentedLDF];
                        appended = true;
                    end
                end
                save(fullpath, 'segmentedLDF', 'segmentedTime', 'Fs');
            catch ME
                UIKit.setStatus(app.StatusLabel, 'Save failed.', 'error');
                UIKit.alert(app.UIFig, sprintf('Save failed:\n%s', ME.message), 'Save error', 'error');
                return;
            end
            Exporter.setLastUsedPath(path);
            if appended
                UIKit.setStatus(app.StatusLabel, sprintf('Appended %d trials to %s (%d trials in file).', ...
                    size(app.SegmentedLDF, 1), file, size(segmentedLDF, 1)), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Saved %d trials to %s. Open it in LDF Average.', ...
                    size(segmentedLDF, 1), file), 'success');
            end
        end
    end
end

%% Local helpers
% -------------------------------------------------------------------------

%% describeParams - One-line summary of a processing params struct
function s = describeParams(p, Fs)
    parts = {};
    if p.downsample > 1
        parts{end+1} = sprintf('decimated %dx to %g Hz', p.downsample, Fs);
    end
    designs = {'Butterworth', 'Chebyshev I', 'FIR'};
    d = designs{min(max(p.designType, 1), 3)};
    switch p.filterType
        case 2, parts{end+1} = sprintf('%s low-pass %g Hz, order %g', d, p.cutoffHigh, p.filterOrder);
        case 3, parts{end+1} = sprintf('%s high-pass %g Hz, order %g', d, p.cutoffLow, p.filterOrder);
        case 4, parts{end+1} = sprintf('%s band-pass %g-%g Hz, order %g', d, p.cutoffLow, p.cutoffHigh, p.filterOrder);
        case 5, parts{end+1} = sprintf('%s notch %g-%g Hz, order %g', d, p.cutoffLow, p.cutoffHigh, p.filterOrder);
    end
    if isempty(parts)
        s = 'No downsampling or filtering selected';
    else
        s = strjoin(parts, '; ');
        s(1) = upper(s(1));
    end
end

%% restoreLastPath - Put back the last used folder after loading demo data
function restoreLastPath(prev)
    if isempty(prev)
        if ispref('NeuroAnalyzer', 'LastUsedPath'), rmpref('NeuroAnalyzer', 'LastUsedPath'); end
    else
        Exporter.setLastUsedPath(prev);
    end
end

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
