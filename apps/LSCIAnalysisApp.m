%% LSCIAnalysisApp.m
% =========================================================================
% LASER SPECKLE FLOWMETRY (LSCI) - BLOOD-FLOW MAPS AND RESPONSES
% =========================================================================
% Load laser speckle images (raw speckle, speckle contrast K, or the
% perfusion / flux images a commercial system exports), compute the
% speckle contrast and a flow index in every pixel, measure the flow in
% ROIs over time, cut trials around each stimulus and map where the flow
% changed. The computations are in core/LaserSpeckle.m (the same numbers
% in scripts and tests).
%
% Layout (UIKit.window): numbered step cards on the left
%   1 Load images  2 Contrast and flow  3 ROIs  4 Stimulus and trials + Run
%   5 Export
% and on the right the image (mean image, contrast, flow index or
% response map) with the ROI outlines next to the ROI list, above the
% result tabs (Flow over time | Average response | Checks). One
% updateControls() sets every enable state.
%
% Scriptable (CI walkthroughs, no dialogs): openFile(path), loadDemo(),
% setInputType(key), setParams(struct with LaserSpeckle.defaults fields),
% addROI(mask, name), removeROI(idx), renameROI(idx, name), clearROIs(),
% setStimulus('file' | 'none'), setStimulus('regular', first, interval,
% count), setTrialWindow(pre, post, respFrom, respTo), run(),
% setDisplay(item), exportResultsTo(path), saveTrialsTo(path, roiIdx).
% Sessions (step 5; core/Session.m, core/Report.m, core/MethodsWriter.m):
% saveSessionTo(path, notes), openSession(path), makeReport(pdfPath),
% sessionState(), restoreSession(s).
% =========================================================================

classdef LSCIAnalysisApp < handle
    properties
        UIFig
        W                    % UIKit.window struct (Fig, Body, Status, HelpBtn)
        LoadBtn
        DemoBtn
        FileLabel
        InputDropdown        % Images are: raw speckle | contrast K | perfusion / flux
        FpsEdit              % Frame rate (Hz)
        ExposureEdit         % Exposure (ms)
        ContrastDropdown     % Spatial | Temporal
        WindowEdit           % Window (px)
        FramesEdit           % Frames per value
        DarkEdit             % Dark level (counts)
        ModelDropdown        % 1/K^2 | 1/tau_c
        BetaEdit             % beta of the model
        AddROIBtn
        RemoveROIBtn
        ClearROIBtn
        ROILabel
        ROITable
        ShowDropdown
        OnsetDropdown        % Stimulus in the file | Regular | None
        FirstOnsetEdit
        IntervalEdit
        CountEdit
        PreEdit
        PostEdit
        RespFromEdit
        RespToEdit
        RunBtn
        ExportBtn
        TrialsBtn
        ExportLabel
        SessionBtns
        AxesImage
        AxesTrace
        AxesAvg
        ResultTabs
        TraceTab
        AvgTab
        ChecksTab           % = ChecksUI.Tab
        ChecksUI            % UIKit.checksTab struct (Tab, Table, Text)
        ChecksTable         % = ChecksUI.Table (Result | Topic | Finding)
        ChecksText          % = ChecksUI.Text (the clicked row in full)
        Data = []            % readImageStack struct (stack, t, fps, stim, ...)
        MeanImage = []       % mean over all frames (H x W double), for Show: Mean image
        KindGuessed = false  % Images are was guessed from the content (the file did not say)
        FileName = ''
        FilePath = ''
        ROIs = struct('Name', {}, 'Mask', {}, 'Position', {}, 'Source', {})
        SelectedROI = []
        Result = []          % LaserSpeckle.analyze struct of the last Run
        ResultROINames = {}
        ResultROIMasks = []
        DemoTruth = []
    end

    properties(Constant)
        InputItems = {'Raw speckle images', 'Speckle contrast (K)', 'Perfusion / flux images'}
        InputKeys = {'raw', 'contrast', 'flow'}
        ContrastItems = {'Spatial (window in each frame)', 'Temporal (each pixel over frames)'}
        ContrastKeys = {'spatial', 'temporal'}
        ModelItems = {[char([49 47 75]) char(178) ' (speckle flow index)'], ['1/' char(964) 'c (exposure model)']}
        ModelKeys = {'invK2', 'tauc'}
        OnsetItems = {'Stimulus in the file', 'Regular (first + interval)', 'None'}
        OnsetKeys = {'file', 'regular', 'none'}
        ShowItems = {'Mean image', 'Speckle contrast K', 'Flow index', 'Response map (%)'}
    end

    methods
        function app = LSCIAnalysisApp()
            app.buildUI();
            app.updateControls();
        end

        %% buildUI - Header | step cards (left) + image and result tabs (right) | status
        function buildUI(app)
            T = UITheme;
            app.W = UIKit.window('Laser Speckle Flowmetry', ...
                'Speckle contrast, blood-flow maps, responses to stimuli and where the flow changed', ...
                'Laser Speckle', [1240 900]);
            app.UIFig = app.W.Fig;
            body = app.W.Body;
            body.RowHeight = {'1x'};
            body.ColumnWidth = {320, '1x'};

            left = uigridlayout(body, [5 1], 'RowHeight', {206, 226, 120, 236, 110 + UIKit.sessionButtonsHeight()}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray, 'Scrollable', 'on');

            % --- 1 Load images ---
            g1 = uigridlayout(UIKit.card(left), [6 2], ...
                'RowHeight', {'fit', T.buttonHeight, '1x', T.controlHeight, T.controlHeight, T.controlHeight}, ...
                'ColumnWidth', {'1x', 96}, 'Padding', [10 8 10 8], 'RowSpacing', 5, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            s = UIKit.step(g1, 1, 'Load images'); s.Layout.Column = [1 2];
            b1 = uigridlayout(g1, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            b1.Layout.Row = 2; b1.Layout.Column = [1 2];
            app.LoadBtn = UIKit.button(b1, ['Load images' char(8230)], @(~,~)app.loadImages(), 'primary', ...
                ['Image stack over time: .mat (frames or stack, H x W x N; optional t or fps, exposureMs, dark, ' ...
                 'stim, roiMasks), multi-frame TIFF (raw camera frames, or the perfusion images a commercial ' ...
                 'system exports) or a video']);
            app.DemoBtn = UIKit.button(b1, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Synthetic raw speckle recording with known answers: 90 s at 10 Hz, exposure 5 ms, four ' ...
                 'stimuli; the flow of an activated area rises by 25%, the rest does not change']);
            app.FileLabel = uilabel(g1, 'Text', 'No images loaded', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on', 'Interpreter', 'none', 'VerticalAlignment', 'top');
            app.FileLabel.Layout.Row = 3; app.FileLabel.Layout.Column = [1 2];
            app.InputDropdown = rowField(g1, 4, 'Images are', 'dropdown', {app.InputItems, app.InputItems{1}}, ...
                ['Raw speckle images from the camera (contrast is computed here), speckle contrast images ' ...
                 '(K, 0-1), or perfusion / flux images already computed by the acquisition software ' ...
                 '(e.g. PeriCam PSI, moorFLPI): these are used as they are']);
            app.InputDropdown.ItemsData = app.InputKeys;
            app.InputDropdown.Value = 'raw';
            app.InputDropdown.ValueChangedFcn = @(~,~)app.onInputChanged();
            app.FpsEdit = rowField(g1, 5, 'Frame rate (Hz)', 'numeric', 10, ...
                'Frames per second of the images (read from the file when it says; otherwise type it)', [0 Inf]);
            app.ExposureEdit = rowField(g1, 6, 'Exposure (ms)', 'numeric', 0, ...
                ['Camera exposure time per frame (ms); needed by the 1/tau_c model. 0 = unknown. ' ...
                 'Typical: 1-20 ms'], [0 Inf]);
            app.FpsEdit.ValueChangedFcn = @(~,~)app.onSettingsChanged();
            app.ExposureEdit.ValueChangedFcn = @(~,~)app.onSettingsChanged();

            % --- 2 Contrast and flow ---
            g2 = uigridlayout(UIKit.card(left), [7 2], ...
                'RowHeight', [{'fit'}, repmat({T.controlHeight}, 1, 6)], ...
                'ColumnWidth', {'1x', 128}, 'Padding', [10 8 10 8], 'RowSpacing', 5, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            s = UIKit.step(g2, 2, 'Contrast and flow'); s.Layout.Column = [1 2];
            app.ContrastDropdown = rowField(g2, 2, 'Contrast', 'dropdown', {app.ContrastItems, app.ContrastItems{1}}, ...
                ['Spatial: sigma / mean of the intensity in a window around each pixel, in every frame ' ...
                 '(keeps the time resolution, blurs the image by the window size). Temporal: sigma / mean ' ...
                 'of each pixel over several frames (keeps the image sharp, lowers the time resolution).']);
            app.ContrastDropdown.ItemsData = app.ContrastKeys;
            app.ContrastDropdown.Value = 'spatial';
            app.WindowEdit = rowField(g2, 3, 'Window (px)', 'numeric', 7, ...
                ['Spatial contrast: size of the square window (odd, 3-31). 5 x 5 or 7 x 7 is usual; smaller ' ...
                 'windows bias the contrast low, larger ones blur vessels.'], [3 31]);
            app.WindowEdit.RoundFractionalValues = 'on';
            app.FramesEdit = rowField(g2, 4, 'Frames per value', 'numeric', 1, ...
                ['Spatial: average the contrast of this many frames (lower noise, lower frame rate). ' ...
                 'Temporal: number of frames in each contrast image (at least 3; 15-25 is usual).'], [1 Inf]);
            app.FramesEdit.RoundFractionalValues = 'on';
            app.DarkEdit = rowField(g2, 5, 'Dark level (counts)', 'numeric', 0, ...
                ['Camera offset subtracted from raw images (image with the laser off). Without it the ' ...
                 'contrast is underestimated.'], [0 Inf]);
            app.ModelDropdown = rowField(g2, 6, 'Flow index', 'dropdown', {app.ModelItems, app.ModelItems{1}}, ...
                ['1/K^2: the speckle flow index, proportional to flow for most tissue. 1/tau_c: inverse ' ...
                 'correlation time from the exposure model K^2 = beta (exp(-2x) - 1 + 2x) / (2x^2), x = T / tau_c ' ...
                 '(needs the exposure; closer to the true flow change for large changes)']);
            app.ModelDropdown.ItemsData = app.ModelKeys;
            app.ModelDropdown.Value = 'invK2';
            app.BetaEdit = rowField(g2, 7, [char(946) ' (coherence, 0-1)'], 'numeric', 1, ...
                ['Coherence factor of the 1/tau_c model: the contrast of a still speckle pattern (1 for ideal ' ...
                 'polarised speckle, often 0.3-0.8). Relative changes do not depend on it.'], [0.01 1]);
            app.ContrastDropdown.ValueChangedFcn = @(~,~)app.onInputChanged();
            for c = {app.WindowEdit, app.FramesEdit, app.DarkEdit, app.ModelDropdown, app.BetaEdit}
                c{1}.ValueChangedFcn = @(~,~)app.onSettingsChanged();
            end

            % --- 3 ROIs ---
            g3 = uigridlayout(UIKit.card(left), [3 3], 'RowHeight', {'fit', T.buttonHeight, '1x'}, ...
                'ColumnWidth', {'1x', '1x', '1x'}, 'Padding', [10 8 10 8], 'RowSpacing', 6, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            s = UIKit.step(g3, 3, 'ROIs'); s.Layout.Column = [1 3];
            app.AddROIBtn = UIKit.button(g3, 'Add ROI', @(~,~)app.drawROI(), 'secondary', ...
                ['Drag a rectangle on the image to add a ROI (several allowed): one flow trace per ROI. ' ...
                 'Without ROIs the whole image is used.']);
            app.AddROIBtn.Layout.Row = 2; app.AddROIBtn.Layout.Column = 1;
            app.RemoveROIBtn = UIKit.button(g3, 'Remove', @(~,~)app.removeROI(), 'danger', ...
                'Remove the ROI selected in the list (or the last one)');
            app.RemoveROIBtn.Layout.Row = 2; app.RemoveROIBtn.Layout.Column = 2;
            app.ClearROIBtn = UIKit.button(g3, 'Clear all', @(~,~)app.clearROIs(), 'secondary', 'Remove every ROI');
            app.ClearROIBtn.Layout.Row = 2; app.ClearROIBtn.Layout.Column = 3;
            app.ROILabel = uilabel(g3, 'Text', '', 'FontSize', T.fontSmall, 'FontColor', T.mutedColor, ...
                'WordWrap', 'on', 'VerticalAlignment', 'top');
            app.ROILabel.Layout.Row = 3; app.ROILabel.Layout.Column = [1 3];

            % --- 4 Stimulus and trials + Run ---
            g4 = uigridlayout(UIKit.card(left), [7 4], ...
                'RowHeight', [{'fit'}, repmat({T.controlHeight}, 1, 5), {T.buttonHeight}], ...
                'ColumnWidth', {'1x', 58, '1x', 58}, 'Padding', [10 8 10 10], 'RowSpacing', 5, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            s = UIKit.step(g4, 4, 'Stimulus, trials and Run'); s.Layout.Column = [1 4];
            lbl = uilabel(g4, 'Text', 'Onsets', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            lbl.Layout.Row = 2; lbl.Layout.Column = 1;
            app.OnsetDropdown = uidropdown(g4, 'Items', app.OnsetItems, 'ItemsData', app.OnsetKeys, ...
                'Value', 'none', 'Tooltip', ['Where the stimulus onsets come from: the stimulus trace in the ' ...
                'file (rising edges; pulses of one train closer than 1 s count once), a regular protocol ' ...
                '(first onset, interval, count), or none (flow over time only)'], ...
                'ValueChangedFcn', @(~,~)app.onSettingsChanged());
            app.OnsetDropdown.Layout.Row = 2; app.OnsetDropdown.Layout.Column = [2 4];
            app.FirstOnsetEdit = pairField(g4, 3, 1, 'First (s)', 10, 'Time of the first stimulus (s)', [0 Inf]);
            app.IntervalEdit = pairField(g4, 3, 3, 'Every (s)', 20, 'Time between stimuli (s)', [0 Inf]);
            app.CountEdit = pairField(g4, 4, 1, 'Count', 4, 'Number of stimuli', [1 Inf]);
            app.CountEdit.RoundFractionalValues = 'on';
            app.PreEdit = pairField(g4, 4, 3, 'Before (s)', 5, ...
                'Trial start before each onset (s); this part is the baseline of the trial', [0.1 Inf]);
            app.PostEdit = pairField(g4, 5, 1, 'After (s)', 15, 'Trial end after each onset (s)', [0.1 Inf]);
            app.RespFromEdit = pairField(g4, 5, 3, 'Resp. from', 2, ...
                'Start of the response window (s after onset): the response map and the mean response', [-Inf Inf]);
            app.RespToEdit = pairField(g4, 6, 3, 'Resp. to', 6, 'End of the response window (s after onset)', [-Inf Inf]);
            for c = {app.FirstOnsetEdit, app.IntervalEdit, app.CountEdit, app.PreEdit, app.PostEdit, ...
                    app.RespFromEdit, app.RespToEdit}
                c{1}.ValueChangedFcn = @(~,~)app.onSettingsChanged();
            end
            app.RunBtn = UIKit.button(g4, 'Run', @(~,~)app.run(), 'primary', ...
                ['Compute the contrast and flow index, the flow in every ROI over time, the trials around each ' ...
                 'stimulus and the response map']);
            app.RunBtn.Layout.Row = 7; app.RunBtn.Layout.Column = [1 4];

            % --- 5 Export ---
            g5 = uigridlayout(UIKit.card(left), [4 2], 'RowHeight', {'fit', T.buttonHeight, '1x', UIKit.sessionButtonsHeight()}, ...
                'ColumnWidth', {'1x', '1x'}, 'Padding', [10 8 10 8], 'RowSpacing', 6, 'ColumnSpacing', 8, ...
                'BackgroundColor', T.cardBg);
            s = UIKit.step(g5, 5, 'Export'); s.Layout.Column = [1 2];
            app.ExportBtn = UIKit.button(g5, ['Export results' char(8230)], @(~,~)app.exportResults(), 'secondary', ...
                ['.csv: time and the flow change (%) of every ROI; .mat: everything (maps, traces, trials, ' ...
                 'ROI masks, settings)']);
            app.ExportBtn.Layout.Row = 2; app.ExportBtn.Layout.Column = 1;
            app.TrialsBtn = UIKit.button(g5, ['Save trials' char(8230)], @(~,~)app.saveTrials(), 'secondary', ...
                ['Save the trials of the selected ROI (% change) as segmentedLDF / segmentedTime / Fs: ' ...
                 'LDF Average and Response features open this file']);
            app.TrialsBtn.Layout.Row = 2; app.TrialsBtn.Layout.Column = 2;
            app.ExportLabel = uilabel(g5, 'Text', 'Run first (step 4)', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');
            app.ExportLabel.Layout.Row = 3; app.ExportLabel.Layout.Column = [1 2];
            app.SessionBtns = UIKit.sessionButtons(g5, app);
            app.SessionBtns.Grid.Layout.Row = 4; app.SessionBtns.Grid.Layout.Column = [1 2];

            % === RIGHT: image + ROI list, then the result tabs ===
            right = uigridlayout(body, [2 1], 'RowHeight', {'1.15x', '1x'}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 10, 'BackgroundColor', T.bgGray);
            imgCard = UIKit.card(right, 'Image and ROIs');
            ig = uigridlayout(imgCard, [1 2], 'ColumnWidth', {'1x', 240}, 'Padding', [8 8 8 8], ...
                'ColumnSpacing', 10, 'BackgroundColor', T.cardBg);
            app.AxesImage = uiaxes(ig);
            UIKit.emptyAxes(app.AxesImage, 'Load images (or Try demo data) to begin');
            rg = uigridlayout(ig, [3 1], 'RowHeight', {'fit', '1x', T.controlHeight}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            uilabel(rg, 'Text', 'ROIs (double-click a name to rename)', 'FontSize', T.fontSmall, ...
                'FontWeight', 'bold', 'FontColor', T.sectionTitleColor, ...
                'Tooltip', 'One row per ROI; # is shown in the colour of its outline and traces');
            app.ROITable = uitable(rg, 'ColumnName', {'#', 'Name', 'Area px'}, ...
                'ColumnWidth', {26, 'auto', 64}, 'ColumnEditable', [false true false], 'RowName', {}, ...
                'FontSize', T.fontSmall, 'Data', cell(0, 3), ...
                'CellEditCallback', @(~, evt)app.onTableEdit(evt), ...
                'CellSelectionCallback', @(~, evt)app.onTableSelect(evt));
            f = uigridlayout(rg, [1 2], 'ColumnWidth', {44, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.ShowDropdown = UIKit.field(f, 'Show', 'dropdown', {app.ShowItems, app.ShowItems{1}}, ...
                ['Mean image of the file; mean speckle contrast K; mean flow index; response map: % change of ' ...
                 'the flow in the response window from the pre-stimulus baseline (after Run)']);
            app.ShowDropdown.ValueChangedFcn = @(src,~)app.setDisplay(src.Value);

            resCard = UIKit.card(right, 'Results');
            pg = uigridlayout(resCard, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.ResultTabs = uitabgroup(pg);
            app.TraceTab = uitab(app.ResultTabs, 'Title', 'Flow over time', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(app.TraceTab, [1 1], 'Padding', [6 4 6 4], 'BackgroundColor', T.cardBg);
            app.AxesTrace = uiaxes(tg);
            UIKit.emptyAxes(app.AxesTrace, 'The flow of each ROI over time appears here after Run (step 4)');
            app.AvgTab = uitab(app.ResultTabs, 'Title', 'Average response', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(app.AvgTab, [1 1], 'Padding', [6 4 6 4], 'BackgroundColor', T.cardBg);
            app.AxesAvg = uiaxes(tg);
            UIKit.emptyAxes(app.AxesAvg, 'The average response to the stimuli appears here after Run');
            app.ChecksUI = UIKit.checksTab(app.ResultTabs, ...
                'Plain-language checks of the images and settings appear here after Run.');
            app.ChecksTab = app.ChecksUI.Tab;
            app.ChecksTable = app.ChecksUI.Table;
            app.ChecksText = app.ChecksUI.Text;

            UIKit.setStatus(app.W.Status, 'Load laser speckle images (or Try demo data) to begin (step 1).', 'info');
        end

        %% updateControls - Enable state and hints from the current data state
        function updateControls(app)
            hasData = ~isempty(app.Data);
            hasRes = ~isempty(app.Result);
            onOff = {'off', 'on'};
            inType = app.InputDropdown.Value;
            isRaw = strcmp(inType, 'raw');
            isK = ~strcmp(inType, 'flow');
            isSpatial = strcmp(app.ContrastDropdown.Value, 'spatial');
            isModel = strcmp(app.ModelDropdown.Value, 'tauc');
            for c = {app.InputDropdown, app.FpsEdit, app.ExposureEdit, app.FramesEdit, app.AddROIBtn, ...
                    app.ShowDropdown, app.OnsetDropdown, app.PreEdit, app.PostEdit, app.RespFromEdit, app.RespToEdit}
                c{1}.Enable = onOff{hasData + 1};
            end
            app.ContrastDropdown.Enable = onOff{(hasData && isRaw) + 1};
            app.WindowEdit.Enable = onOff{(hasData && isRaw && isSpatial) + 1};
            app.DarkEdit.Enable = onOff{(hasData && isRaw) + 1};
            app.ModelDropdown.Enable = onOff{(hasData && isK) + 1};
            app.BetaEdit.Enable = onOff{(hasData && isK && isModel) + 1};
            regular = strcmp(app.OnsetDropdown.Value, 'regular');
            for c = {app.FirstOnsetEdit, app.IntervalEdit, app.CountEdit}
                c{1}.Enable = onOff{(hasData && regular) + 1};
            end
            hasROI = ~isempty(app.ROIs);
            app.RemoveROIBtn.Enable = onOff{hasROI + 1};
            app.ClearROIBtn.Enable = onOff{hasROI + 1};
            app.RunBtn.Enable = onOff{hasData + 1};
            app.ExportBtn.Enable = onOff{hasRes + 1};
            app.TrialsBtn.Enable = onOff{(hasRes && ~isempty(app.Result.onsets)) + 1};
            UIKit.setSessionEnable(app.SessionBtns, hasData);
            styleBtn(app.LoadBtn, ~hasData);
            styleBtn(app.RunBtn, hasData && ~hasRes);
            styleBtn(app.ExportBtn, hasRes);
            if ~hasData
                app.ROILabel.Text = 'Load images first.';
            elseif ~hasROI
                app.ROILabel.Text = 'No ROI: Run uses the whole image. Click Add ROI to measure regions.';
            else
                app.ROILabel.Text = sprintf('%d ROI(s): %s.', numel(app.ROIs), strjoin({app.ROIs.Name}, ', '));
            end
            if hasRes
                if isempty(app.Result.onsets)
                    app.ExportLabel.Text = 'Ready to export the flow over time (no trials: no onsets).';
                else
                    app.ExportLabel.Text = sprintf('Ready: %d trials, %d ROI(s). Save trials exports the selected ROI.', ...
                        numel(app.Result.onsets), numel(app.ResultROINames));
                end
            else
                app.ExportLabel.Text = 'Run first (step 4)';
            end
        end

        %% loadImages - Ask for a file, then openFile
        function loadImages(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir), startDir = pwd; end
            [file, path] = uigetfile({'*.mat;*.tif;*.tiff;*.avi;*.mp4;*.dat', 'Images (.mat, TIFF, video, PIMSoft .dat)'; ...
                '*.mat', 'MAT (*.mat)'; '*.tif;*.tiff', 'TIFF (*.tif, *.tiff)'; '*.avi;*.mp4', 'Video'; ...
                '*.dat', 'Perimed PIMSoft (*.dat)'}, ...
                'Load laser speckle images', startDir);
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.openFile(fullfile(path, file));
        end

        %% openFile - Load images (readImageStack) without dialogs; true on success
        function ok = openFile(app, fullPath)
            ok = false;
            [~, name, ext] = fileparts(fullPath);
            dlg = UIKit.busy(app.UIFig, sprintf('Loading %s%s%s', name, ext, char(8230)));
            UIKit.setStatus(app.W.Status, sprintf('Loading %s%s', name, ext), 'busy');
            try
                S = readImageStack(fullPath);
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, 'Load failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Load failed: %s', ME.message), 'Load error');
                return;
            end
            UIKit.done(dlg);
            app.applyLoaded(S, [name ext]);
            app.FilePath = fullPath;
            kind = app.InputItems{strcmp(app.InputKeys, app.InputDropdown.Value)};
            if app.KindGuessed
                kind = sprintf('%s (judged from the images: change Images are if wrong)', kind);
            end
            UIKit.setStatus(app.W.Status, sprintf(['Loaded %s%s (%d frames): %s. Next: check the settings in ' ...
                'step 2, add ROIs (step 3) and Run (step 4).'], name, ext, size(S.stack, 3), kind), 'success');
            ok = true;
        end

        %% loadDemo - Synthetic raw speckle recording (core/demo/demoLSCI) with its ROIs
        function ok = loadDemo(app)
            ok = false;
            dlg = UIKit.busy(app.UIFig, sprintf('Preparing demo data (first time only takes a few seconds)%s', char(8230)));
            UIKit.setStatus(app.W.Status, 'Preparing demo data', 'busy');
            try
                p = DemoData.file('lsci');
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, sprintf('Demo data failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not create the demo data: %s', ME.message), 'Demo data');
                return;
            end
            UIKit.done(dlg);
            if ~app.openFile(p), return; end
            app.FramesEdit.Value = 5;                      % 10 Hz averaged by 5: flow at 2 Hz
            app.clearResults();
            app.updateControls();
            UIKit.setStatus(app.W.Status, ['Demo loaded: raw speckle, 90 s at 10 Hz, exposure 5 ms, dark level ' ...
                '100, four stimuli (10, 30, 50, 70 s) and three ROIs. Click Run: the activated area rises by ' ...
                'about 21% 2-6 s after each onset, the control cortex and the vessel do not change.'], 'success');
            ok = true;
        end

        %% setInputType - 'raw' | 'contrast' | 'flow' (as choosing it in Images are)
        function setInputType(app, key)
            app.InputDropdown.Value = validKey(key, app.InputKeys);
            app.onInputChanged();
        end

        %% setParams - Set any LaserSpeckle.defaults field (Contrast, Window, Frames, Dark, FlowModel, Beta, ExposureMs, Fps)
        function setParams(app, s)
            f = fieldnames(s);
            for k = 1:numel(f)
                v = s.(f{k});
                switch f{k}
                    case 'InputType',  app.InputDropdown.Value = validKey(v, app.InputKeys);
                    case 'Contrast',   app.ContrastDropdown.Value = validKey(v, app.ContrastKeys);
                    case 'Window',     app.WindowEdit.Value = v;
                    case 'Frames',     app.FramesEdit.Value = v;
                    case 'Dark',       app.DarkEdit.Value = v;
                    case 'FlowModel',  app.ModelDropdown.Value = validKey(v, app.ModelKeys);
                    case 'Beta',       app.BetaEdit.Value = v;
                    case 'ExposureMs', app.ExposureEdit.Value = zeroIfNaN(v);
                    case 'Fps',        app.FpsEdit.Value = zeroIfNaN(v);
                    otherwise
                        error('NeuroAnalyzer:LSCI:param', 'Unknown setting %s.', f{k});
                end
            end
            app.onSettingsChanged();
        end

        %% setStimulus - 'file' | 'none' | 'regular' (first, interval, count)
        function setStimulus(app, mode, first, interval, count)
            app.OnsetDropdown.Value = validKey(mode, app.OnsetKeys);
            if strcmp(app.OnsetDropdown.Value, 'regular')
                app.FirstOnsetEdit.Value = first;
                app.IntervalEdit.Value = interval;
                app.CountEdit.Value = count;
            end
            app.onSettingsChanged();
        end

        %% setTrialWindow - Trial from -pre to +post s; response window respFrom-respTo s after onset
        function setTrialWindow(app, pre, post, respFrom, respTo)
            app.PreEdit.Value = pre;
            app.PostEdit.Value = post;
            if nargin >= 5
                app.RespFromEdit.Value = respFrom;
                app.RespToEdit.Value = respTo;
            end
            app.onSettingsChanged();
        end

        %% addROI - Add a logical H x W mask as a ROI; returns its index
        function idx = addROI(app, mask, name)
            if isempty(app.Data)
                error('NeuroAnalyzer:LSCI:noData', 'Load images before adding a ROI.');
            end
            [H, W] = app.frameSize();
            if ~isequal(size(mask), [H W]) || ~any(mask(:))
                error('NeuroAnalyzer:LSCI:mask', 'The ROI mask must be a non-empty %d x %d logical image.', H, W);
            end
            if nargin < 3 || isempty(name), name = app.nextROIName(); end
            idx = app.appendROI(char(name), logical(mask), [], 'added');
            app.afterROIChange();
        end

        %% removeROI - Remove ROI idx (default: the selected row, else the last ROI)
        function removeROI(app, idx)
            if isempty(app.ROIs), return; end
            if nargin < 2 || isempty(idx)
                idx = app.SelectedROI;
                if isempty(idx) || idx > numel(app.ROIs), idx = numel(app.ROIs); end
            end
            if idx < 1 || idx > numel(app.ROIs)
                error('NeuroAnalyzer:LSCI:index', 'ROI index must be between 1 and %d.', numel(app.ROIs));
            end
            name = app.ROIs(idx).Name;
            app.ROIs(idx) = [];
            app.SelectedROI = [];
            app.afterROIChange();
            UIKit.setStatus(app.W.Status, sprintf('Removed %s (%d ROI(s) left).', name, numel(app.ROIs)), 'info');
        end

        %% renameROI - Rename ROI idx (names label traces and export columns)
        function renameROI(app, idx, name)
            name = strtrim(char(name));
            if idx < 1 || idx > numel(app.ROIs)
                error('NeuroAnalyzer:LSCI:index', 'ROI index must be between 1 and %d.', numel(app.ROIs));
            end
            if ~isempty(name)
                app.ROIs(idx).Name = name;
                if ~isempty(app.Result) && idx <= numel(app.ResultROINames)
                    app.ResultROINames{idx} = name;
                    app.plotResults();
                end
            end
            app.refreshROITable();
            app.showImage();
            app.updateControls();
        end

        %% clearROIs - Remove every ROI
        function clearROIs(app)
            app.ROIs = app.ROIs([]);
            app.SelectedROI = [];
            app.afterROIChange();
            UIKit.setStatus(app.W.Status, 'ROIs cleared: Run uses the whole image.', 'info');
        end

        %% drawROI - Drag a rectangle on the image (Image Processing Toolbox)
        function drawROI(app)
            if isempty(app.Data)
                UIKit.alert(app.UIFig, 'Load images first (step 1).', 'ROI');
                return;
            end
            UIKit.setStatus(app.W.Status, 'Drag a rectangle on the image to add a ROI', 'busy');
            name = app.nextROIName();
            try
                h = drawrectangle(app.AxesImage, 'Label', name, 'Color', roiColor(numel(app.ROIs) + 1));
            catch
                UIKit.setStatus(app.W.Status, 'Could not draw a ROI', 'error');
                UIKit.alert(app.UIFig, ['Could not draw a rectangle: drawrectangle needs the Image Processing ' ...
                    'Toolbox. Without it, save the images in a .mat with a logical roiMasks (H x W x K) and ' ...
                    'load that file.'], 'ROI');
                return;
            end
            pos = [];
            try pos = h.Position; delete(h); catch, end
            if isempty(pos) || any(pos(3:4) <= 0)
                UIKit.setStatus(app.W.Status, 'No ROI drawn', 'info');
                return;
            end
            [H, W] = app.frameSize();
            app.appendROI(name, rectMask(pos, H, W), pos, 'drawn');
            app.afterROIChange();
            UIKit.setStatus(app.W.Status, sprintf('%s added. Add more ROIs or click Run (step 4).', name), 'success');
        end

        %% run - Contrast, flow, ROI traces, trials and response map (LaserSpeckle.analyze)
        function ok = run(app)
            ok = false;
            if isempty(app.Data)
                UIKit.alert(app.UIFig, 'Load images first (step 1).', 'Run');
                return;
            end
            p = app.params();
            [masks, names] = app.roiMasks();
            dlg = UIKit.busy(app.UIFig, sprintf('Computing speckle contrast and flow%s', char(8230)));
            UIKit.setStatus(app.W.Status, 'Computing speckle contrast and flow', 'busy');
            try
                [t, p.Onsets] = app.timeAndOnsets(p);
                R = LaserSpeckle.analyze(app.Data.stack, t, masks, p);
            catch ME
                UIKit.done(dlg);
                app.clearResults();
                app.updateControls();
                UIKit.setStatus(app.W.Status, sprintf('Run failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Run failed: %s', ME.message), 'Run');
                return;
            end
            UIKit.done(dlg);
            app.Result = R;
            app.ResultROINames = names;
            app.ResultROIMasks = masks;
            app.plotResults();
            if ~isempty(R.responseMap)
                app.ShowDropdown.Value = 'Response map (%)';
            else
                app.ShowDropdown.Value = 'Flow index';
            end
            app.showImage();
            if isempty(R.onsets)
                app.ResultTabs.SelectedTab = app.TraceTab;
            else
                app.ResultTabs.SelectedTab = app.AvgTab;
            end
            app.updateControls();
            nWarn = QualityChecks.count(R.checkRows, 'warning');
            if nWarn > 0
                UIKit.setStatus(app.W.Status, sprintf(['Flow computed, but %s in the Checks tab: read them ' ...
                    'before using the numbers.'], QualityChecks.plural(nWarn, 'warning')), 'warning');
            elseif isempty(R.onsets)
                UIKit.setStatus(app.W.Status, sprintf(['Flow computed for %d ROI(s) at %.3g Hz (%d values). ' ...
                    'No stimulus onsets, so no trials. Next: Export (step 5).'], numel(names), R.fps, numel(R.t)), 'success');
            else
                UIKit.setStatus(app.W.Status, sprintf(['%d trials: %s %+.1f%% (%g-%g s after onset). See the ' ...
                    'Checks tab, then Export (step 5).'], numel(R.onsets), names{1}, R.response(1), ...
                    p.ResponseSec(1), p.ResponseSec(2)), 'success');
            end
            ok = true;
        end

        %% setDisplay - Background image: an item of Show, or 'mean' | 'contrast' | 'flow' | 'response'
        function setDisplay(app, item)
            keys = {'mean', 'contrast', 'flow', 'response'};
            k = find(strcmpi(app.ShowItems, item) | strcmpi(keys, item), 1);
            if isempty(k)
                error('NeuroAnalyzer:LSCI:display', 'Unknown display ''%s''.', item);
            end
            app.ShowDropdown.Value = app.ShowItems{k};
            app.showImage();
        end

        %% exportResults - Ask for a .csv / .mat, then exportResultsTo
        function exportResults(app)
            if isempty(app.Result), return; end
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = pwd; end
            [~, base] = fileparts(app.FileName);
            [file, path] = uiputfile({'*.csv', 'CSV table (*.csv)'; '*.mat', 'MAT file (*.mat)'}, ...
                'Export laser speckle results', fullfile(startDir, [base '_lsci.csv']));
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.exportResultsTo(fullfile(path, file));
        end

        %% exportResultsTo - .csv (Time + flow change % per ROI) or .mat (results struct); true on success
        function ok = exportResultsTo(app, fullPath)
            ok = false;
            if isempty(app.Result)
                UIKit.alert(app.UIFig, 'Run first (step 4).', 'Export');
                return;
            end
            R = app.Result;
            [~, fname, ext] = fileparts(fullPath);
            try
                if strcmpi(ext, '.csv')
                    tbl = table(R.t(:), 'VariableNames', {'Time_s'});
                    for k = 1:numel(app.ResultROINames)
                        col = matlab.lang.makeValidName(['FlowChange_pct_' app.ResultROINames{k}]);
                        col = matlab.lang.makeUniqueStrings(col, tbl.Properties.VariableNames);
                        tbl.(col) = 100 * (R.roiRel(k, :)' - 1);
                    end
                    for k = 1:numel(app.ResultROINames)
                        col = matlab.lang.makeValidName(['FlowIndex_' app.ResultROINames{k}]);
                        col = matlab.lang.makeUniqueStrings(col, tbl.Properties.VariableNames);
                        tbl.(col) = R.roiFlow(k, :)';
                    end
                    writetable(tbl, fullPath);
                else
                    results = R;
                    results.roiNames = app.ResultROINames;
                    results.roiMasks = app.ResultROIMasks;
                    results.sourceFile = app.FileName;
                    results.flowUnits = R.units;
                    save(fullPath, 'results');
                end
                UIKit.setStatus(app.W.Status, sprintf('Exported to %s%s', fname, ext), 'success');
                ok = true;
            catch ME
                UIKit.setStatus(app.W.Status, 'Export failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Export failed: %s', ME.message), 'Export');
            end
        end

        %% saveTrials - Ask for a .mat, then saveTrialsTo (selected ROI)
        function saveTrials(app)
            if isempty(app.Result) || isempty(app.Result.onsets), return; end
            k = app.SelectedROI;
            if isempty(k) || k > numel(app.ResultROINames), k = 1; end
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = pwd; end
            [~, base] = fileparts(app.FileName);
            nm = regexprep(app.ResultROINames{k}, '[^A-Za-z0-9]+', '_');
            [file, path] = uiputfile({'*.mat', 'Trials (*.mat)'}, 'Save trials', ...
                fullfile(startDir, sprintf('%s_%s_trials.mat', base, nm)));
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.saveTrialsTo(fullfile(path, file), k);
        end

        %% saveTrialsTo - Trials of ROI k as segmentedLDF (trials x samples, %), segmentedTime, Fs
        % The format of LDF Process, so LDF Average and Response features open it.
        function ok = saveTrialsTo(app, fullPath, k)
            ok = false;
            if nargin < 3 || isempty(k), k = 1; end
            R = app.Result;
            if isempty(R) || isempty(R.onsets)
                UIKit.alert(app.UIFig, 'Run with stimulus onsets first (step 4).', 'Save trials');
                return;
            end
            try
                segmentedLDF = reshape(R.trials(k, :, :), numel(R.onsets), []); %#ok<NASGU>
                segmentedTime = R.trialTime; %#ok<NASGU>
                Fs = R.fps; %#ok<NASGU>
                onsetTimes = R.onsets; %#ok<NASGU>
                roiName = app.ResultROINames{k}; %#ok<NASGU>
                units = sprintf('%% change of %s from the pre-stimulus mean', R.units); %#ok<NASGU>
                source = 'Laser speckle (LSCIAnalysisApp)'; %#ok<NASGU>
                save(fullPath, 'segmentedLDF', 'segmentedTime', 'Fs', 'onsetTimes', 'roiName', 'units', 'source');
                [~, n, e] = fileparts(fullPath);
                UIKit.setStatus(app.W.Status, sprintf(['Saved %d trials of %s to %s%s: open it in LDF Average ' ...
                    'or Response features.'], numel(R.onsets), app.ResultROINames{k}, n, e), 'success');
                ok = true;
            catch ME
                UIKit.setStatus(app.W.Status, 'Saving the trials failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Saving the trials failed: %s', ME.message), 'Save trials');
            end
        end

        %% ----------------------------------------------------------------
        %% Sessions and reports (core/Session.m, core/Report.m)
        function ok = saveSessionTo(app, filePath, notes)
            if nargin < 3, notes = []; end
            ok = Session.saveApp(app, filePath, notes);
        end

        function ok = openSession(app, filePath, interactive)
            if nargin < 3, interactive = false; end
            ok = Session.openInApp(app, filePath, interactive);
        end

        function ok = makeReport(app, pdfPath)
            ok = Report.forApp(app, pdfPath);
        end

        %% sessionState - Images (with MD5), settings, ROIs and results for Session.capture
        function st = sessionState(app)
            st.inputs = [];
            st.settings = struct();
            st.results = struct();
            st.summary = {};
            if isempty(app.Data), return; end
            st.inputs = Session.fileInfo(app.FilePath, 'Laser speckle images');
            p = app.params();
            st.settings.params = p;
            st.settings.onsetSource = app.OnsetDropdown.Value;
            st.settings.regular = [app.FirstOnsetEdit.Value, app.IntervalEdit.Value, app.CountEdit.Value];
            st.settings.roiNames = {app.ROIs.Name};
            st.settings.roiSources = {app.ROIs.Source};
            st.settings.roiPositions = {app.ROIs.Position};
            st.settings.roiMasks = app.roiMaskStack();
            st.settings.display = app.ShowDropdown.Value;
            [H, W] = app.frameSize();
            st.summary{end+1} = sprintf('Images: %d x %d px, %d frames (%s); %d ROI(s)', W, H, ...
                size(app.Data.stack, 3), p.InputType, numel(app.ROIs));
            if isempty(app.Result), return; end
            R = app.Result;
            st.checks = R.checkRows;
            st.results = struct('t', R.t, 'fps', R.fps, 'roiNames', {app.ResultROINames}, ...
                'roiFlow', R.roiFlow, 'roiRel', R.roiRel, 'onsets', R.onsets, 'trialTime', R.trialTime, ...
                'trialMean', R.trialMean, 'trialSD', R.trialSD, 'response', R.response, 'peak', R.peak, ...
                'peakTime', R.peakTime, 'units', R.units, 'checks', {R.checks}, 'baselineSec', R.baselineSec);
            st.summary{end+1} = sprintf('Flow index: %s at %.3g Hz; %d trial(s)', R.units, R.fps, numel(R.onsets));
            for k = 1:numel(app.ResultROINames)
                if isempty(R.onsets)
                    st.summary{end+1} = sprintf('  %s: mean flow index %.4g', app.ResultROINames{k}, ...
                        mean(R.roiFlow(k, :), 'omitnan')); %#ok<AGROW>
                else
                    st.summary{end+1} = sprintf('  %s: response %+.2f%% (%g-%g s), peak %+.2f%% at %.3g s', ...
                        app.ResultROINames{k}, R.response(k), p.ResponseSec(1), p.ResponseSec(2), ...
                        R.peak(k), R.peakTime(k)); %#ok<AGROW>
                end
            end
        end

        %% restoreSession - Reload the images, ROIs and settings; re-run
        function ok = restoreSession(app, s)
            ok = false;
            if isempty(s.inputs), ok = true; return; end
            if ~app.openFile(s.inputs(1).path), return; end
            cfg = s.settings;
            app.ROIs = app.ROIs([]);
            for k = 1:numel(cfg.roiNames)
                app.appendROI(cfg.roiNames{k}, cfg.roiMasks(:, :, k), cfg.roiPositions{k}, cfg.roiSources{k});
            end
            p = cfg.params;
            app.setParams(rmfield(p, intersect(fieldnames(p), {'Onsets', 'PreSec', 'PostSec', 'ResponseSec', 'BaselineSec'})));
            app.OnsetDropdown.Value = cfg.onsetSource;
            app.FirstOnsetEdit.Value = cfg.regular(1);
            app.IntervalEdit.Value = cfg.regular(2);
            app.CountEdit.Value = cfg.regular(3);
            app.setTrialWindow(p.PreSec, p.PostSec, p.ResponseSec(1), p.ResponseSec(2));
            app.refreshROITable();
            app.clearResults();
            if isfield(s.results, 'response')
                if ~app.run(), return; end
            end
            app.setDisplay(cfg.display);
            app.updateControls();
            ok = true;
        end
    end

    methods(Access = private)

        %% applyLoaded - New images: settings from the file, ROIs from the file, reset results
        function applyLoaded(app, S, fileName)
            app.Data = S;
            app.MeanImage = zeros(size(S.stack, 1), size(S.stack, 2));
            for n = 1:size(S.stack, 3)            % frame by frame: no double copy of the whole stack
                app.MeanImage = app.MeanImage + double(S.stack(:, :, n));
            end
            app.MeanImage = app.MeanImage / size(S.stack, 3);
            app.FileName = fileName;
            app.DemoTruth = S.truth;
            app.ROIs = app.ROIs([]);
            app.SelectedROI = [];
            if ~isempty(S.roiMasks)
                for k = 1:size(S.roiMasks, 3)
                    app.appendROI(S.roiNames{k}, S.roiMasks(:, :, k), [], 'file');
                end
            end
            % Settings the file knows (the image type from its content when it does not say)
            key = kindKey(S.kind);
            app.KindGuessed = isempty(key);
            if isempty(key), key = guessKind(S.stack); end
            app.InputDropdown.Value = key;
            if isfinite(S.fps) && S.fps > 0, app.FpsEdit.Value = S.fps; end
            app.ExposureEdit.Value = zeroIfNaN(S.exposureMs);
            if isscalar(S.dark) && isfinite(S.dark), app.DarkEdit.Value = S.dark; else, app.DarkEdit.Value = 0; end
            app.FramesEdit.Value = app.defaultFrames();
            if ~isempty(S.stim)
                app.OnsetDropdown.Value = 'file';
            else
                app.OnsetDropdown.Value = 'none';
            end
            % Describe what was loaded
            [H, W] = app.frameSize();
            N = size(S.stack, 3);
            if isfinite(S.fps)
                tInfo = sprintf('%g Hz (%.4g s)', S.fps, N / S.fps);
            else
                tInfo = 'frame rate unknown: type it below';
            end
            extra = '';
            if ~isempty(S.stim), extra = ' · stimulus trace'; end
            if ~isempty(S.roiMasks), extra = sprintf('%s · %d ROI(s)', extra, size(S.roiMasks, 3)); end
            app.FileLabel.Text = sprintf('%s\n%d x %d px · %d frames · %s · %s%s', fileName, W, H, N, ...
                class(S.stack), tInfo, extra);
            app.ShowDropdown.Value = 'Mean image';
            app.clearResults();
            app.refreshROITable();
            app.showImage();
            app.updateControls();
        end

        %% params - LaserSpeckle settings from the controls
        function p = params(app)
            p = LaserSpeckle.defaults();
            p.InputType = app.InputDropdown.Value;
            p.Contrast = app.ContrastDropdown.Value;
            p.Window = app.WindowEdit.Value;
            p.Frames = app.FramesEdit.Value;
            p.Dark = app.DarkEdit.Value;
            p.FlowModel = app.ModelDropdown.Value;
            p.Beta = app.BetaEdit.Value;
            p.ExposureMs = nanIfZero(app.ExposureEdit.Value);
            p.Fps = nanIfZero(app.FpsEdit.Value);
            p.PreSec = app.PreEdit.Value;
            p.PostSec = app.PostEdit.Value;
            p.ResponseSec = [app.RespFromEdit.Value, app.RespToEdit.Value];
        end

        %% timeAndOnsets - Frame times (from the file or the frame rate) and the stimulus onsets (s)
        function [t, onsets] = timeAndOnsets(app, p)
            N = size(app.Data.stack, 3);
            t = app.Data.t;
            if isempty(t)
                if ~(isfinite(p.Fps) && p.Fps > 0)
                    error('NeuroAnalyzer:LSCI:fps', 'Type the frame rate (step 1): the file does not say it.');
                end
                t = (0:N-1) / p.Fps;
            end
            switch app.OnsetDropdown.Value
                case 'file'
                    if isempty(app.Data.stim)
                        error('NeuroAnalyzer:LSCI:stim', 'The file has no stimulus trace: choose Regular or None.');
                    end
                    stim = app.Data.stim;
                    ts = t;
                    if numel(stim) ~= N
                        ts = linspace(t(1), t(end), numel(stim));   % stimulus sampled faster than the frames
                    end
                    onsets = LaserSpeckle.onsetsFromStimulus(stim, ts, 1);
                case 'regular'
                    onsets = app.FirstOnsetEdit.Value + (0:app.CountEdit.Value - 1) * app.IntervalEdit.Value;
                otherwise
                    onsets = [];
            end
        end

        %% showImage - The Show image with the ROI outlines on top
        function showImage(app)
            T = UITheme;
            ax = app.AxesImage;
            if isempty(app.Data)
                UIKit.emptyAxes(ax, 'Load images (or Try demo data) to begin');
                return;
            end
            R = app.Result;
            item = app.ShowDropdown.Value;
            cmap = gray(256); cl = []; cbLabel = '';
            switch item
                case 'Speckle contrast K'
                    if isempty(R) || isempty(R.K2Mean)
                        img = []; msg = 'Run first (step 4): the contrast is computed by Run';
                        if ~isempty(R), msg = 'These images are not speckle images: no contrast'; end
                    else
                        img = sqrt(R.K2Mean); cmap = flipud(hot(256)); cbLabel = 'K';
                        cl = [0 max(0.05, min(1, pctl(img(:), 99.5)))];
                    end
                case 'Flow index'
                    if isempty(R)
                        img = []; msg = 'Run first (step 4)';
                    else
                        img = R.flowMean; cmap = hot(256); cbLabel = R.units;
                        cl = [pctl(img(:), 1), pctl(img(:), 99)];
                    end
                case 'Response map (%)'
                    if isempty(R) || isempty(R.responseMap)
                        img = []; msg = 'Run with stimulus onsets first (step 4)';
                    else
                        img = R.responseMap; cmap = divergingMap(); cbLabel = 'Flow change (%)';
                        a = max(5, pctl(abs(img(:)), 99));
                        cl = [-a a];
                    end
                otherwise
                    img = app.MeanImage; cbLabel = 'Mean intensity';
            end
            colorbar(ax, 'off');
            cla(ax, 'reset');
            if isempty(img)
                UIKit.emptyAxes(ax, msg);
                return;
            end
            imagesc(ax, img);
            axis(ax, 'image');
            colormap(ax, cmap);
            if ~isempty(cl) && all(isfinite(cl)) && cl(2) > cl(1), ax.CLim = cl; end
            cb = colorbar(ax);
            cb.Label.String = cbLabel;
            ax.XTick = []; ax.YTick = [];
            hold(ax, 'on');
            for k = 1:numel(app.ROIs)
                m = app.ROIs(k).Mask;
                if ~any(m(:)), continue; end
                col = roiColor(k);
                contour(ax, double(m), [0.5 0.5], 'LineColor', col, 'LineWidth', 1.5);
                [yy, xx] = find(m);
                text(ax, mean(xx), min(yy) - 0.5, sprintf('%d', k), 'Color', col, 'FontWeight', 'bold', ...
                    'FontSize', T.fontSmall, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                    'Clipping', 'on');
            end
            hold(ax, 'off');
            title(ax, item, 'Interpreter', 'none', 'FontWeight', 'bold', 'Color', T.sectionTitleColor, ...
                'FontSize', T.fontSmall);
        end

        %% plotResults - Flow over time, average response and checks
        function plotResults(app)
            T = UITheme;
            R = app.Result;
            if isempty(R), return; end
            names = app.ResultROINames;
            % Flow over time (% change from the baseline window)
            ax = app.AxesTrace;
            cla(ax, 'reset');
            hold(ax, 'on');
            for k = 1:numel(names)
                plot(ax, R.t, 100 * (R.roiRel(k, :) - 1), '-', 'Color', roiColor(k), 'LineWidth', 1.2, ...
                    'DisplayName', names{k});
            end
            for o = R.params.Onsets(:)'
                xline(ax, o, ':', 'Color', T.stimColor, 'HandleVisibility', 'off');   % full height at any zoom
            end
            hold(ax, 'off');
            UIKit.styleAxes(ax, sprintf('Flow change from %.3g-%.3g s (%s)', R.baselineSec(1), R.baselineSec(2), ...
                R.units), 'Time (s)', 'Flow change (%)');
            legend(ax, 'Location', 'best', 'Interpreter', 'none', 'Box', 'off');
            % Average response
            ax = app.AxesAvg;
            cla(ax, 'reset');
            if isempty(R.onsets)
                UIKit.emptyAxes(ax, 'No stimulus onsets (step 4): no trials to average');
            else
                hold(ax, 'on');
                rw = R.params.ResponseSec;
                yAll = [R.trialMean(:) - R.trialSD(:); R.trialMean(:) + R.trialSD(:)];
                yAll = yAll(isfinite(yAll));
                if isempty(yAll), yAll = [-1; 1]; end
                yr = [min(yAll), max(yAll)];
                if yr(2) <= yr(1), yr = yr + [-1 1]; end
                patch(ax, rw([1 2 2 1]), yr([1 1 2 2]), T.hintBg, 'EdgeColor', 'none', ...
                    'HandleVisibility', 'off');
                tt = R.trialTime;
                for k = 1:numel(names)
                    m = R.trialMean(k, :); sd = R.trialSD(k, :);
                    patch(ax, [tt, fliplr(tt)], [m - sd, fliplr(m + sd)], roiColor(k), 'FaceAlpha', 0.15, ...
                        'EdgeColor', 'none', 'HandleVisibility', 'off');
                    plot(ax, tt, m, '-', 'Color', roiColor(k), 'LineWidth', 1.6, 'DisplayName', ...
                        sprintf('%s: %+.1f%%', names{k}, R.response(k)));
                end
                plot(ax, [0 0], yr, '-', 'Color', T.stimColor, 'LineWidth', 1, 'HandleVisibility', 'off');
                hold(ax, 'off');
                ylim(ax, yr);
                UIKit.styleAxes(ax, sprintf('Average of %d trials (mean %s SD); shaded: response window', ...
                    numel(R.onsets), char(177)), 'Time from onset (s)', 'Flow change (%)');
                legend(ax, 'Location', 'best', 'Interpreter', 'none', 'Box', 'off');
            end
            UIKit.showChecks(app.ChecksUI, R.checkRows);
        end

        function clearResults(app)
            app.Result = [];
            app.ResultROINames = {};
            app.ResultROIMasks = [];
            if isempty(app.AxesTrace) || ~isvalid(app.AxesTrace), return; end
            cla(app.AxesTrace, 'reset');
            UIKit.emptyAxes(app.AxesTrace, 'The flow of each ROI over time appears here after Run (step 4)');
            cla(app.AxesAvg, 'reset');
            UIKit.emptyAxes(app.AxesAvg, 'The average response to the stimuli appears here after Run');
            UIKit.showChecks(app.ChecksUI, QualityChecks.none());
            if ~any(strcmp(app.ShowDropdown.Value, {'Mean image'}))
                app.ShowDropdown.Value = 'Mean image';
                if ~isempty(app.Data), app.showImage(); end
            end
        end

        %% onInputChanged - Images are changed: frames per value back to the default for that type
        function onInputChanged(app)
            if ~isempty(app.Data), app.FramesEdit.Value = app.defaultFrames(); end
            app.onSettingsChanged();
        end

        %% defaultFrames - About 2 flow values per second for raw speckle; 1 otherwise
        function n = defaultFrames(app)
            fps = app.FpsEdit.Value;
            n = 1;
            if strcmp(app.InputDropdown.Value, 'raw') && fps > 4
                if strcmp(app.ContrastDropdown.Value, 'temporal')
                    n = max(3, round(fps / 2));
                else
                    n = max(1, round(fps / 2));
                end
            elseif strcmp(app.InputDropdown.Value, 'raw') && strcmp(app.ContrastDropdown.Value, 'temporal')
                n = 3;
            end
        end

        function onSettingsChanged(app)
            if ~isempty(app.Result)
                app.clearResults();
                UIKit.setStatus(app.W.Status, 'Settings changed: click Run again (step 4).', 'info');
            end
            app.updateControls();
        end

        function afterROIChange(app)
            app.clearResults();
            app.refreshROITable();
            app.showImage();
            app.updateControls();
        end

        function onTableEdit(app, evt)
            if isempty(evt.Indices), return; end
            row = evt.Indices(1);
            if evt.Indices(2) == 2 && row <= numel(app.ROIs)
                app.renameROI(row, evt.NewData);
            end
        end

        function onTableSelect(app, evt)
            if isempty(evt.Indices)
                app.SelectedROI = [];
            else
                app.SelectedROI = evt.Indices(1, 1);
            end
        end

        function k = appendROI(app, name, mask, pos, source)
            r = struct('Name', name, 'Mask', logical(mask), 'Position', pos, 'Source', source);
            if isempty(app.ROIs), app.ROIs = r; else, app.ROIs(end + 1) = r; end
            k = numel(app.ROIs);
        end

        function name = nextROIName(app)
            used = {app.ROIs.Name};
            n = numel(used) + 1;
            name = sprintf('ROI %d', n);
            while any(strcmp(used, name))
                n = n + 1;
                name = sprintf('ROI %d', n);
            end
        end

        function refreshROITable(app)
            K = numel(app.ROIs);
            data = cell(K, 3);
            for k = 1:K
                data(k, :) = {sprintf('%d', k), app.ROIs(k).Name, nnz(app.ROIs(k).Mask)};
            end
            app.ROITable.Data = data;
            try
                removeStyle(app.ROITable);
                for k = 1:K
                    addStyle(app.ROITable, uistyle('BackgroundColor', roiColor(k), 'FontColor', [1 1 1], ...
                        'FontWeight', 'bold'), 'cell', [k 1]);
                end
            catch
            end
        end

        function masks = roiMaskStack(app)
            [H, W] = app.frameSize();
            K = numel(app.ROIs);
            masks = false(H, W, K);
            for k = 1:K, masks(:, :, k) = app.ROIs(k).Mask; end
        end

        %% roiMasks - Masks and names for Run (the whole image when there is no ROI)
        function [masks, names] = roiMasks(app)
            if isempty(app.ROIs)
                [H, W] = app.frameSize();
                masks = true(H, W);
                names = {'Whole image'};
            else
                masks = app.roiMaskStack();
                names = {app.ROIs.Name};
            end
        end

        function [H, W] = frameSize(app)
            H = size(app.Data.stack, 1);
            W = size(app.Data.stack, 2);
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% rowField - UIKit.field placed in row r (label column 1, control column 2)
function c = rowField(g, r, label, kind, value, tooltip, limits)
    if nargin < 7, limits = []; end
    [c, lbl] = UIKit.field(g, label, kind, value, tooltip, limits);
    lbl.Layout.Row = r; lbl.Layout.Column = 1;
    c.Layout.Row = r; c.Layout.Column = 2;
end

%% pairField - Label + numeric field in columns col and col + 1 of row r
function c = pairField(g, r, col, label, value, tooltip, limits)
    T = UITheme;
    lbl = uilabel(g, 'Text', label, 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor, 'Tooltip', tooltip);
    lbl.Layout.Row = r; lbl.Layout.Column = col;
    c = uieditfield(g, 'numeric', 'Value', value, 'Limits', limits, 'Tooltip', tooltip);
    c.Layout.Row = r; c.Layout.Column = col + 1;
end

function k = validKey(v, keys)
    i = find(strcmpi(keys, v), 1);
    if isempty(i)
        error('NeuroAnalyzer:LSCI:param', 'Unknown value ''%s'' (use %s).', char(v), strjoin(keys, ', '));
    end
    k = keys{i};
end

%% kindKey - InputType key of a file's 'kind' ('' when unknown)
function key = kindKey(kind)
    kind = lower(char(kind));
    key = '';
    if isempty(kind), return; end
    if ~isempty(strfind(kind, 'raw')) || ~isempty(strfind(kind, 'speckle')) %#ok<STREMP>
        key = 'raw';
    end
    if ~isempty(strfind(kind, 'contrast')) %#ok<STREMP>
        key = 'contrast';
    elseif any(~cellfun(@isempty, regexp(kind, {'flow', 'flux', 'perfusion'}, 'once')))
        key = 'flow';
    end
end

%% guessKind - Image type from the content: contrast images hold values in 0-1; raw
% speckle has a grainy pattern (local contrast K >= 0.03); smooth images are
% perfusion / flux images already computed by the acquisition software
function key = guessKind(stack)
    f = double(stack(:, :, 1));
    v = f(isfinite(f));
    if isfloat(stack) && ~isempty(v) && min(v) >= 0 && max(v) <= 1.5 && any(v ~= round(v))
        key = 'contrast';
        return;
    end
    key = 'raw';
    if size(f, 1) >= 7 && size(f, 2) >= 7
        K = LaserSpeckle.spatialContrast(f, 7);
        K = K(4:end-3, 4:end-3);
        k = median(K(isfinite(K)));
        if isempty(k) || ~(k >= 0.03), key = 'flow'; end
    end
end

function v = zeroIfNaN(v)
    if isempty(v) || ~isfinite(v), v = 0; end
end

function v = nanIfZero(v)
    if v == 0, v = NaN; end
end

function styleBtn(b, isPrimary)
    T = UITheme;
    if isPrimary
        b.BackgroundColor = T.accent; b.FontColor = [1 1 1]; b.FontWeight = 'bold';
    else
        b.BackgroundColor = T.secondaryBg; b.FontColor = T.secondaryFg; b.FontWeight = 'normal';
    end
end

function c = roiColor(k)
    P = UITheme.plotColors([1 2 3 4 5 7], :);
    c = P(mod(k - 1, size(P, 1)) + 1, :);
end

function m = rectMask(pos, H, W)
    pos = round(pos);
    x1 = max(1, pos(1)); y1 = max(1, pos(2));
    x2 = min(W, pos(1) + pos(3)); y2 = min(H, pos(2) + pos(4));
    m = false(H, W);
    m(y1:y2, x1:x2) = true;
end

%% pctl - Percentile (linear interpolation) without the Statistics Toolbox
function v = pctl(x, p)
    x = sort(x(isfinite(x)));
    if isempty(x), v = NaN; return; end
    pos = 1 + (numel(x) - 1) * p / 100;
    lo = floor(pos); hi = min(lo + 1, numel(x));
    v = x(lo) + (pos - lo) * (x(hi) - x(lo));
end

%% divergingMap - Blue - white - vermillion colour map (flow down / up)
function c = divergingMap()
    n = 128;
    blue = [0.00 0.45 0.70]; red = [0.84 0.37 0.00];
    a = linspace(0, 1, n)';
    c = [blue + (1 - blue) .* a; 1 - (1 - red) .* a];
end
