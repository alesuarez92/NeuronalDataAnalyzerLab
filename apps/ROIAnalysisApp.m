%% ROIAnalysisApp.m
% =========================================================================
% ROI / COREGISTERED IMAGE ANALYSIS
% =========================================================================
% Load an image stack (time series of frames), optionally correct rigid
% motion, define one or more ROIs (drawn, detected automatically from the
% local correlation image, or from the file) or a line, then compute per
% ROI brightness, movement, ΔF/F or flow speed, or along the line a
% kymograph or the vessel diameter (optionally robust to red blood cells
% crossing the line). Plot and export.
%
% Layout (UIKit.window): numbered step cards on the left
%   1 Load stack  2 Preprocess  3 ROIs and line  4 Analysis + Run  5 Export
% and on the right the image (first frame, mean or correlation image) with
% the ROI / line overlay next to the ROI list, above the result tabs
% (Result | Motion correction). One updateControls() sets every enable state.
% Scriptable (CI walkthroughs, no dialogs): openFile(path), loadDemo(),
% loadAdvancedDemo(), setROIMask(mask), addROI(mask, name), removeROI(idx),
% renameROI(idx, name), setLine([x1 y1], [x2 y2]), setMotionCorrection(tf),
% runMotionCorrection(), detectCells(opts), setDisplay(mode),
% setRobustDiameter(tf), runAnalysis(methodName), exportResultsTo(path).
% =========================================================================

classdef ROIAnalysisApp < handle
    properties
        UIFig
        W                    % UIKit.window struct (Fig, Body, Status, HelpBtn)
        LoadBtn
        DemoBtn              % Try demo data (synthetic stack with known answers)
        AdvDemoBtn           % Try advanced demo (motion, 3 cells, RBC crossing the line)
        FileLabel
        MotionCb             % Motion correction (rigid), applied first
        MotionLabel          % Largest estimated shift
        ConvertBWCb          % Convert to B&W (256 levels)
        DrawROIBtn           % Add ROI (drag a rectangle)
        DetectBtn            % Detect cells (local correlation image)
        ComputeBtn
        MethodDropdown       % Brightness, Movement, Both, ΔF/F, Speed, Kymograph, Vessel diameter
        SmoothCb
        NormalizeCb
        DrawLineBtn
        ClearShapeBtn
        ShapeLabel           % Current ROIs / line description
        BaselineFramesEdit   % ΔF/F baseline: first N frames
        RobustCb             % Robust vessel diameter
        ROITable             % colour/# | Name (editable) | Area | Source
        RemoveROIBtn
        DisplayDropdown      % First frame | Mean image | Correlation image
        DetectThresholdEdit  % Detection threshold on the correlation image (0 = automatic)
        DetectThresholdLabel % Its label; shows the automatic threshold used by the last detection
        ExportBtn
        ExportLabel
        AxesImage
        AxesPlot
        AxesMotion           % Estimated shifts (Motion correction tab)
        ResultTabs
        ResultTab
        MotionTab
        FileName
        Stack                % H x W x N or H x W x 3 x N
        TimeVec
        TimeFromFile = false % true when TimeVec came from timeVec/t in a .mat (seconds)
        ROIs = struct('Id', {}, 'Name', {}, 'Mask', {}, 'Position', {}, 'Source', {}, 'Handle', {})
                             % Source: 'file' | 'mask' (setROIMask) | 'drawn' | 'detected' | 'added'
        SelectedROI = []     % Row selected in the ROI table
        ROIMask              % logical H x W: mask of ROI 1 (kept for scripts using the single-ROI API)
        MaskFromFile = false % true when ROIs came from the .mat (roiMask / roiMasks)
        CurrentROI           % Last drawn rectangle (drawrectangle handle, optional)
        LineStart            % [x1 y1] for kymograph / vessel
        LineEnd              % [x2 y2]
        CurrentLine          % drawline handle (optional)
        RegStack             % Motion-corrected grayscale stack (H x W x N double)
        Shifts               % N x 2 estimated [dy dx] per frame (px)
        RegValid             % H x W logical: pixels covered by every shifted frame
        CorrImage            % Cached local correlation image
        MeanImage            % Cached mean image
        DetectThreshold = [] % Threshold used by the last detection
        DemoTruth = []       % Ground truth of a demo stack ('truth' in the file), for scripts
        Intensity            % K x N, one row per ROI
        Movement
        T
        DFF
        Speed
        Kymo
        Diameter
        DiameterPlain        % Standard (min/max half level) diameter, shown with the robust one
        DiameterRaw          % Robust per-frame diameter before the temporal filter
        DiameterOutliers     % Frames replaced by the temporal filter
        ResultROINames = {}  % ROI names of the current ROI results
        ResultROIMasks = []  % H x W x K masks of the current ROI results
        LastMethod = ''      % Method of the current results ('' = none)
    end

    properties(Access = private)
        NextROIId = 1
    end

    properties(Constant, Access = private)
        LineMethods = {'Kymograph', 'Vessel diameter'}
        DisplayItems = {'First frame', 'Mean image', 'Correlation image'}
    end

    methods
        function app = ROIAnalysisApp()
            app.buildUI();
            app.updateControls();
        end

        %% buildUI - Header | step cards (left) + image, ROI list and result tabs (right) | status
        function buildUI(app)
            T = UITheme;
            app.W = UIKit.window('ROI / Image Analysis', ...
                'Motion correction, multiple ROIs and cell detection; ΔF/F, flow speed, kymograph and vessel diameter', ...
                'ROI Analysis', [1200 900]);
            app.UIFig = app.W.Fig;
            body = app.W.Body;
            body.RowHeight = {'1x'};
            body.ColumnWidth = {310, '1x'};

            % === LEFT: numbered step cards ===
            left = uigridlayout(body, [5 1], 'RowHeight', {168, 144, 154, 168, 88}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');

            % --- 1 Load stack ---
            g1 = uigridlayout(UIKit.card(left), [4 1], ...
                'RowHeight', {'fit', T.buttonHeight, T.buttonHeight, '1x'}, ...
                'Padding', [10 8 10 8], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g1, 1, 'Load stack');
            b1 = uigridlayout(g1, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.LoadBtn = UIKit.button(b1, 'Load stack', @(~,~)app.loadStack(), 'primary', ...
                ['.mat with stack or frames (H x W x N or H x W x 3 x N; optional timeVec or t, ' ...
                 'roiMask or roiMasks), or a multi-frame TIFF']);
            app.DemoBtn = UIKit.button(b1, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Load a synthetic stack with known answers: a cell with calcium transients at ' ...
                 '3, 7 and 11 s and a vessel whose diameter oscillates 9-15 px']);
            app.AdvDemoBtn = UIKit.button(g1, 'Try advanced demo (motion, 3 cells)', ...
                @(~,~)app.loadAdvancedDemo(), 'secondary', ...
                ['Synthetic stack with known answers for the advanced tools: rigid jitter up to 3 px, ' ...
                 'three cells with transients at different times, and a red blood cell that crosses ' ...
                 'the vessel-diameter line']);
            app.FileLabel = uilabel(g1, 'Text', 'No stack loaded', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on', 'Interpreter', 'none', ...
                'VerticalAlignment', 'top');

            % --- 2 Preprocess ---
            g2 = uigridlayout(UIKit.card(left), [6 1], ...
                'RowHeight', {'fit', 20, 20, 20, 20, '1x'}, 'Padding', [10 8 10 8], ...
                'RowSpacing', 4, 'BackgroundColor', T.cardBg);
            UIKit.step(g2, 2, 'Preprocess (optional)');
            mg = uigridlayout(g2, [1 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.MotionCb = uicheckbox(mg, 'Text', 'Motion correction (rigid)', 'Value', 0, ...
                'FontSize', T.fontBody, 'ValueChangedFcn', @(src,~)app.setMotionCorrection(src.Value), ...
                'Tooltip', ['Estimate each frame''s translation (px, sub-pixel) against the mean image ' ...
                 '(FFT phase correlation) and shift it back. Applied before everything else; the shifts ' ...
                 'are plotted in the Motion correction tab.']);
            app.MotionLabel = uilabel(mg, 'Text', '', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'HorizontalAlignment', 'right');
            app.ConvertBWCb = uicheckbox(g2, 'Text', 'B&W 256 levels', 'Value', 0, ...
                'FontSize', T.fontBody, ...
                'Tooltip', 'Convert every frame to 256-level grayscale (uint8), e.g. for fluorescence intensity');
            app.SmoothCb = uicheckbox(g2, 'Text', 'Smooth (Gaussian, sigma 2 px)', 'Value', 0, ...
                'FontSize', T.fontBody, 'Tooltip', 'Gaussian-smooth each frame (sigma = 2 pixels)');
            app.NormalizeCb = uicheckbox(g2, 'Text', 'Normalize each frame to 0-1', 'Value', 0, ...
                'FontSize', T.fontBody, 'Tooltip', 'Per-frame min/max normalization to the range 0-1');
            uilabel(g2, 'Text', 'Applied in this order when you click Run.', ...
                'FontSize', T.fontTiny, 'FontColor', T.mutedColor, 'VerticalAlignment', 'top');
            for cb = {app.ConvertBWCb, app.SmoothCb, app.NormalizeCb}
                cb{1}.ValueChangedFcn = @(~,~)app.onSettingsChanged();
            end

            % --- 3 ROIs and line ---
            g3 = uigridlayout(UIKit.card(left), [4 2], ...
                'RowHeight', {'fit', T.buttonHeight, T.buttonHeight, '1x'}, ...
                'ColumnWidth', {'1x', '1x'}, 'Padding', [10 8 10 8], 'RowSpacing', 6, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            s = UIKit.step(g3, 3, 'ROIs and line');
            s.Layout.Row = 1; s.Layout.Column = [1 2];
            app.DrawROIBtn = UIKit.button(g3, 'Add ROI', @(~,~)app.drawROI(), 'secondary', ...
                ['Drag a rectangle on the image to add a ROI (you can add several). Used by Brightness, ' ...
                 'Movement, ΔF/F and Speed: one trace per ROI.']);
            app.DrawROIBtn.Layout.Row = 2; app.DrawROIBtn.Layout.Column = 1;
            app.DetectBtn = UIKit.button(g3, 'Detect cells', @(~,~)app.detectCells(), 'secondary', ...
                ['Find active cells automatically: pixels whose time series correlate with their ' ...
                 'neighbours (correlation image), thresholded, 20-1000 px, compact. Adds one ROI per ' ...
                 'cell. Run Motion correction first.']);
            app.DetectBtn.Layout.Row = 2; app.DetectBtn.Layout.Column = 2;
            app.DrawLineBtn = UIKit.button(g3, 'Draw line', @(~,~)app.drawLine(), 'secondary', ...
                'Draw a line on the image (across the vessel for diameter). Used by Kymograph and Vessel diameter.');
            app.DrawLineBtn.Layout.Row = 3; app.DrawLineBtn.Layout.Column = 1;
            app.ClearShapeBtn = UIKit.button(g3, 'Clear ROIs and line', @(~,~)app.clearShapes(), ...
                'secondary', ['Remove drawn, added and detected ROIs and the line (ROIs from the ' ...
                 'file are kept; use Remove ROI for those)']);
            app.ClearShapeBtn.Layout.Row = 3; app.ClearShapeBtn.Layout.Column = 2;
            app.ShapeLabel = uilabel(g3, 'Text', '', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on', 'VerticalAlignment', 'top');
            app.ShapeLabel.Layout.Row = 4; app.ShapeLabel.Layout.Column = [1 2];

            % --- 4 Analysis + Run ---
            g4 = uigridlayout(UIKit.card(left), [5 1], ...
                'RowHeight', {'fit', T.controlHeight, T.controlHeight, 20, T.buttonHeight}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g4, 4, 'Analysis');
            f4a = uigridlayout(g4, [1 2], 'ColumnWidth', {70, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.MethodDropdown = UIKit.field(f4a, 'Method', 'dropdown', ...
                {{'Brightness', 'Movement', 'Both', 'ΔF/F (gCaMP)', 'Speed (flow)', 'Kymograph', 'Vessel diameter'}, 'Both'}, ...
                ['ROI methods (one trace per ROI): Brightness (mean intensity), Movement (mean |frame ' ...
                 'difference|), Both, ΔF/F, Speed (flow proxy). Line methods: Kymograph, Vessel diameter (FWHM)']);
            app.MethodDropdown.ValueChangedFcn = @(~,~)app.onSettingsChanged();
            f4b = uigridlayout(g4, [1 2], 'ColumnWidth', {'1x', 80}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.BaselineFramesEdit = UIKit.field(f4b, 'ΔF/F baseline (frames)', 'numeric', 30, ...
                'F0 = mean ROI intensity over the first N frames (ΔF/F only)', [1 Inf]);
            app.BaselineFramesEdit.RoundFractionalValues = 'on';
            app.BaselineFramesEdit.ValueChangedFcn = @(~,~)app.onSettingsChanged();
            app.RobustCb = uicheckbox(g4, 'Text', 'Robust diameter (ignore blood cells)', 'Value', 0, ...
                'FontSize', T.fontBody, 'ValueChangedFcn', @(~,~)app.onSettingsChanged(), ...
                'Tooltip', ['Vessel diameter only. Background from the line ends and vessel core from a ' ...
                 'low percentile (running medians over 7 frames), then frames that jump more than ' ...
                 '3 robust SD from their neighbours are replaced (Hampel filter). Use it when bright ' ...
                 'blood cells cross the line.']);
            app.ComputeBtn = UIKit.button(g4, 'Run', @(~,~)app.computeAndPlot(), 'primary', ...
                'Preprocess the stack and compute the selected method');

            % --- 5 Export ---
            g5 = uigridlayout(UIKit.card(left), [3 1], 'RowHeight', {'fit', T.buttonHeight, '1x'}, ...
                'Padding', [10 8 10 8], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g5, 5, 'Export');
            app.ExportBtn = UIKit.button(g5, 'Export results', @(~,~)app.exportResults(), ...
                'secondary', ['Save the result: .csv (time + one column per measure and ROI; ' ...
                 'kymograph as a matrix) or .mat (results plus all ROI masks, line, shifts and settings)']);
            app.ExportLabel = uilabel(g5, 'Text', 'Run an analysis first', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');

            % === RIGHT: image + ROI list above the result tabs ===
            right = uigridlayout(body, [2 1], 'RowHeight', {'1.2x', '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray);
            imgCard = UIKit.card(right, 'Image, ROIs and line');
            ig = uigridlayout(imgCard, [1 2], 'ColumnWidth', {'1x', 250}, 'Padding', [8 8 8 8], ...
                'ColumnSpacing', 10, 'BackgroundColor', T.cardBg);
            app.AxesImage = uiaxes(ig);
            UIKit.emptyAxes(app.AxesImage, 'Load a stack (or Try demo data) to begin');
            rg = uigridlayout(ig, [5 1], 'RowHeight', {'fit', '1x', T.buttonHeight, ...
                T.controlHeight, T.controlHeight}, 'Padding', [0 0 0 0], 'RowSpacing', 6, ...
                'BackgroundColor', T.cardBg);
            uilabel(rg, 'Text', 'ROIs (double-click a name to rename)', 'FontSize', T.fontSmall, ...
                'FontWeight', 'bold', 'FontColor', T.sectionTitleColor, ...
                'Tooltip', 'One row per ROI; # is shown in the colour of its outline and trace');
            app.ROITable = uitable(rg, 'ColumnName', {'#', 'Name', 'Area px', 'Source'}, ...
                'ColumnWidth', {26, 'auto', 70, 66}, 'ColumnEditable', [false true false false], ...
                'RowName', {}, 'FontSize', T.fontSmall, 'Data', cell(0, 4), ...
                'CellEditCallback', @(~, evt)app.onTableEdit(evt), ...
                'CellSelectionCallback', @(~, evt)app.onTableSelect(evt));
            app.RemoveROIBtn = UIKit.button(rg, 'Remove ROI', @(~,~)app.removeROI(), 'danger', ...
                'Remove the selected ROI (or the last one if none is selected)');
            f6 = uigridlayout(rg, [1 2], 'ColumnWidth', {44, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.DisplayDropdown = UIKit.field(f6, 'Show', 'dropdown', {app.DisplayItems, 'First frame'}, ...
                ['Background image: first frame, mean over all frames, or the local correlation image ' ...
                 '(bright = pixels that co-fluctuate with their neighbours, i.e. active cells). ' ...
                 'Motion-corrected when Motion correction is on.']);
            app.DisplayDropdown.ValueChangedFcn = @(src,~)app.setDisplay(src.Value);
            f7 = uigridlayout(rg, [1 2], 'ColumnWidth', {'1x', 64}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.DetectThresholdEdit = UIKit.field(f7, 'Detect: min correlation', 'numeric', 0, ...
                ['Correlation threshold (0-1) for Detect cells. 0 = automatic: median + 4 robust SD ' ...
                 'of the correlation image (at least 0.2); the label then shows the value used.'], [0 1]);
            app.DetectThresholdLabel = findobj(f7, 'Type', 'uilabel');

            plotCard = UIKit.card(right, 'Results');
            pg = uigridlayout(plotCard, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.ResultTabs = uitabgroup(pg);
            app.ResultTab = uitab(app.ResultTabs, 'Title', 'Result', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(app.ResultTab, [1 1], 'Padding', [6 4 6 4], 'BackgroundColor', T.cardBg);
            app.AxesPlot = uiaxes(tg);
            UIKit.emptyAxes(app.AxesPlot, 'Results appear here after Run (step 4)');
            app.MotionTab = uitab(app.ResultTabs, 'Title', 'Motion correction', 'BackgroundColor', T.cardBg);
            tg = uigridlayout(app.MotionTab, [1 1], 'Padding', [6 4 6 4], 'BackgroundColor', T.cardBg);
            app.AxesMotion = uiaxes(tg);
            UIKit.emptyAxes(app.AxesMotion, 'Tick Motion correction (step 2) to estimate the frame shifts');

            UIKit.setStatus(app.W.Status, 'Load an image stack (or Try demo data) to begin (step 1).', 'info');
        end

        %% updateControls - Enable state and hints from the current data state
        function updateControls(app)
            hasStack = ~isempty(app.Stack);
            method = app.MethodDropdown.Value;
            needLine = ismember(method, app.LineMethods);
            hasROI = app.hasROI();
            hasLine = app.hasLine();
            ready = hasStack && ((needLine && hasLine) || (~needLine && hasROI));
            hasRes = ~isempty(app.LastMethod);
            onOff = {'off', 'on'};
            for c = {app.MotionCb, app.ConvertBWCb, app.SmoothCb, app.NormalizeCb, app.DrawROIBtn, ...
                    app.DrawLineBtn, app.MethodDropdown, app.DisplayDropdown, app.DetectThresholdEdit}
                c{1}.Enable = onOff{hasStack + 1};
            end
            app.DetectBtn.Enable = onOff{(hasStack && app.nFrames() >= 3) + 1};
            clearable = hasLine || any(~ismember({app.ROIs.Source}, {'file', 'mask'}));
            app.ClearShapeBtn.Enable = onOff{(hasStack && clearable) + 1};
            app.RemoveROIBtn.Enable = onOff{hasROI + 1};
            app.BaselineFramesEdit.Enable = onOff{(hasStack && strcmp(method, 'ΔF/F (gCaMP)')) + 1};
            app.RobustCb.Enable = onOff{(hasStack && strcmp(method, 'Vessel diameter')) + 1};
            app.ComputeBtn.Enable = onOff{ready + 1};
            app.ExportBtn.Enable = onOff{hasRes + 1};
            % Recommended next action is primary
            styleBtn(app.DrawROIBtn, hasStack && ~needLine && ~hasROI);
            styleBtn(app.DrawLineBtn, hasStack && needLine && ~hasLine);
            styleBtn(app.ComputeBtn, ready && ~hasRes);
            styleBtn(app.ExportBtn, hasRes);

            % Motion indicator
            if ~hasStack || isempty(app.Shifts)
                app.MotionLabel.Text = '';
            elseif app.MotionCb.Value
                app.MotionLabel.Text = sprintf('max shift %.1f px', max(abs(app.Shifts(:))));
            else
                app.MotionLabel.Text = 'off';
            end

            % What is defined right now, and what the chosen method needs
            parts = {};
            nR = numel(app.ROIs);
            if nR == 1
                parts{end+1} = sprintf('ROI: %s (%d px).', app.ROIs(1).Name, nnz(app.ROIs(1).Mask));
            elseif nR > 1
                names = {app.ROIs.Name};
                etc = '';
                if nR > 3, etc = ', ...'; end
                parts{end+1} = sprintf('%d ROIs (%s%s).', nR, strjoin(names(1:min(3, nR)), ', '), etc);
            end
            lp = app.linePosition();
            if ~isempty(lp)
                parts{end+1} = sprintf('Line: %.0f px long.', hypot(lp(2,1) - lp(1,1), lp(2,2) - lp(1,2)));
            end
            if ~hasStack
                parts = {'Load a stack first.'};
            elseif needLine && ~hasLine
                parts{end+1} = sprintf('%s needs a line: click Draw line.', method);
            elseif ~needLine && ~hasROI
                parts{end+1} = sprintf('%s needs a ROI: click Add ROI or Detect cells.', method);
            end
            app.ShapeLabel.Text = strjoin(parts, ' ');
            if hasRes
                app.ExportLabel.Text = sprintf('Ready to export: %s', app.LastMethod);
            else
                app.ExportLabel.Text = 'Run an analysis first';
            end
        end

        function loadStack(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir), startDir = pwd; end
            [file, path] = uigetfile({'*.mat;*.tif;*.tiff', 'Stack or MAT'; '*.mat', 'MAT'; '*.tif;*.tiff', 'TIFF'}, ...
                'Load image stack', startDir);
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.openFile(fullfile(path, file));
        end

        %% openFile - Load a stack (.mat or TIFF) without dialogs and show it
        % A .mat may hold roiMask (H x W) or roiMasks (H x W x K, optional
        % roiNames); they become the ROIs. Returns true on success.
        function ok = openFile(app, fullPath)
            ok = false;
            [~, name, ext] = fileparts(fullPath);
            file = [name ext];
            dlg = UIKit.busy(app.UIFig, sprintf('Loading %s...', file));
            UIKit.setStatus(app.W.Status, sprintf('Loading %s', file), 'busy');
            masks = []; roiNames = {}; truth = [];
            try
                if strcmpi(ext, '.mat')
                    s = load(fullPath);
                    fn = fieldnames(s);
                    if isempty(fn)
                        error('The file contains no variables.');
                    end
                    if ismember('stack', fn)
                        stack = s.stack;
                    elseif ismember('frames', fn)
                        stack = s.frames;
                    else
                        stack = s.(fn{1});
                    end
                    if ~isnumeric(stack) && ~islogical(stack)
                        error(['No image stack found. Save the frames as a numeric variable ' ...
                            'named ''stack'' (H x W x N or H x W x 3 x N).']);
                    end
                    if ismember('timeVec', fn)
                        timeVec = s.timeVec;
                    elseif ismember('t', fn)
                        timeVec = s.t;
                    else
                        timeVec = [];
                    end
                    if ismember('roiMasks', fn) && ~isempty(s.roiMasks)
                        masks = logical(s.roiMasks);
                        if ismember('roiNames', fn), roiNames = cellstr(s.roiNames); end
                    elseif ismember('roiMask', fn)
                        masks = logical(s.roiMask);
                    end
                    if ismember('truth', fn) && isstruct(s.truth), truth = s.truth; end
                    timeFromFile = ~isempty(timeVec);
                else
                    info = imfinfo(fullPath);
                    n = numel(info);
                    first = imread(fullPath, 1);
                    % Preallocate double; RGB(A) frames are collapsed to the
                    % grayscale mean of the colour channels
                    stack = zeros(size(first, 1), size(first, 2), n);
                    for k = 1:n
                        fr = double(imread(fullPath, k));
                        if ndims(fr) == 3
                            fr = mean(fr(:, :, 1:min(3, size(fr, 3))), 3);
                        end
                        stack(:, :, k) = fr;
                    end
                    timeVec = 1:n;
                    timeFromFile = false;
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, 'Load failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Load failed: %s', ME.message), 'Load error');
                return;
            end
            UIKit.done(dlg);
            app.applyLoaded(stack, timeVec, timeFromFile, masks, roiNames, file);
            app.DemoTruth = truth;
            UIKit.setStatus(app.W.Status, sprintf('Loaded %s (%d frames). Next: add ROIs or draw a line (step 3).', ...
                file, app.nFrames()), 'success');
            ok = true;
        end

        %% loadDemo - Load the synthetic imaging stack and pre-fill a ΔF/F analysis
        % DemoData 'imaging': 96 x 96 x 150 frames at 10 Hz; a cell at
        % (24, 30) with calcium transients (ΔF/F ~1) at 3, 7 and 11 s (its
        % roiMask is in the file) and a vertical vessel at x = 60 whose
        % diameter oscillates 12 +/- 3 px at 0.2 Hz, with a bright RBC moving
        % down 2 px/frame. Sets method ΔF/F with the file roiMask and a line
        % across the vessel from (45, 70) to (75, 70). Returns true on success.
        function ok = loadDemo(app)
            ok = false;
            dlg = UIKit.busy(app.UIFig, sprintf('Preparing demo data (first time only takes a few seconds)%s', char(8230)));
            UIKit.setStatus(app.W.Status, 'Preparing demo data', 'busy');
            try
                p = DemoData.file('imaging');
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, sprintf('Demo data failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not create the demo data: %s', ME.message), 'Demo data');
                return;
            end
            UIKit.done(dlg);
            if ~app.openFile(p), return; end
            app.MethodDropdown.Value = 'ΔF/F (gCaMP)';
            app.BaselineFramesEdit.Value = 30;   % 0-2.9 s, before the first transient
            if ~isempty(app.ROIMask), app.setROIMask(app.ROIMask); end
            app.setLine([45 70], [75 70]);
            app.updateControls();
            UIKit.setStatus(app.W.Status, ['Demo loaded: 15 s at 10 Hz with a cell (outlined, roiMask) ' ...
                'and a vessel (line across it). Click Run for ΔF/F: peaks ~1 at 3, 7 and 11 s. Then try ' ...
                'Vessel diameter (9-15 px, period 5 s) or Kymograph.'], 'success');
            ok = true;
        end

        %% loadAdvancedDemo - Stack for motion correction, cell detection and robust diameter
        % core/demo/demoImagingAdvanced: 96 x 96 x 150 frames at 10 Hz with
        % rigid jitter (zero mean, up to 3 px), three cells with transients
        % at different times (cell 1 at (22, 24): 4, 8.5, 13 s; cell 2 at
        % (26, 78): 5.5, 10.5 s; cell 3 at (82, 30): 7, 12 s), a vessel at
        % x = 60 (diameter 12 +/- 3 px, period 5 s) and a red blood cell
        % that crosses the diameter line (35, 64)-(85, 64) about every 3 s.
        % No ROIs are loaded (use Detect cells). The ground truth is kept in
        % DemoTruth. Returns true on success.
        function ok = loadAdvancedDemo(app)
            ok = false;
            dlg = UIKit.busy(app.UIFig, sprintf('Generating the advanced demo stack%s', char(8230)));
            UIKit.setStatus(app.W.Status, 'Generating the advanced demo stack', 'busy');
            try
                if exist('demoImagingAdvanced', 'file') ~= 2
                    root = fileparts(fileparts(mfilename('fullpath')));
                    addpath(fullfile(root, 'core', 'demo'));
                end
                s = demoImagingAdvanced();
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, sprintf('Demo data failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not create the demo data: %s', ME.message), 'Demo data');
                return;
            end
            UIKit.done(dlg);
            app.applyLoaded(s.stack, s.timeVec, true, [], {}, 'demo_imaging_advanced');
            app.DemoTruth = s.truth;
            app.MethodDropdown.Value = 'ΔF/F (gCaMP)';
            app.BaselineFramesEdit.Value = 30;   % 0-2.9 s, before the first transient (4 s)
            app.setLine(s.truth.lineStart, s.truth.lineEnd);
            app.updateControls();
            UIKit.setStatus(app.W.Status, ['Advanced demo loaded: the frames jitter by up to 3 px. ' ...
                'Next: tick Motion correction (step 2), then Detect cells (step 3) and Run ΔF/F: ' ...
                'three cells with peaks at different times. Then compare Vessel diameter with and ' ...
                'without Robust diameter.'], 'success');
            ok = true;
        end

        %% setROIMask - Use a logical H x W mask as the only ROI (replaces all ROIs)
        function setROIMask(app, mask)
            if isempty(app.Stack)
                error('NeuroAnalyzer:ROI:noStack', 'Load a stack before setting a ROI mask.');
            end
            app.checkMaskSize(mask);
            app.deleteROIHandles();
            app.ROIs = app.ROIs([]);
            app.appendROI('ROI 1', logical(mask), [], 'mask');
            app.MaskFromFile = true;   % outlined, kept by Clear, used by Run
            app.showFrame();
            app.refreshROITable();
            app.onShapeMoved();
        end

        %% addROI - Add a logical H x W mask as a new ROI; returns its index
        % name is optional (default 'ROI <k>').
        function idx = addROI(app, mask, name)
            if isempty(app.Stack)
                error('NeuroAnalyzer:ROI:noStack', 'Load a stack before adding a ROI.');
            end
            app.checkMaskSize(mask);
            if ~any(mask(:))
                error('NeuroAnalyzer:ROI:emptyMask', 'The ROI mask is empty.');
            end
            if nargin < 3 || isempty(name), name = app.nextROIName('ROI'); end
            idx = app.appendROI(char(name), logical(mask), [], 'added');
            app.showFrame();
            app.refreshROITable();
            app.onShapeMoved();
        end

        %% removeROI - Remove ROI idx (default: the selected row, else the last ROI)
        function removeROI(app, idx)
            if isempty(app.ROIs), return; end
            if nargin < 2 || isempty(idx)
                idx = app.SelectedROI;
                if isempty(idx) || idx > numel(app.ROIs), idx = numel(app.ROIs); end
            end
            if idx < 1 || idx > numel(app.ROIs) || idx ~= round(idx)
                error('NeuroAnalyzer:ROI:index', 'ROI index must be between 1 and %d.', numel(app.ROIs));
            end
            name = app.ROIs(idx).Name;
            h = app.ROIs(idx).Handle;
            if hasDrawn(h), delete(h); end
            app.ROIs(idx) = [];
            app.SelectedROI = [];
            app.MaskFromFile = any(strcmp({app.ROIs.Source}, 'file'));
            app.syncLegacy();
            app.showFrame();
            app.refreshROITable();
            app.clearResults();
            app.updateControls();
            UIKit.setStatus(app.W.Status, sprintf('Removed %s (%d ROI(s) left).', name, numel(app.ROIs)), 'info');
        end

        %% renameROI - Rename ROI idx (names label the traces and export columns)
        function renameROI(app, idx, name)
            name = strtrim(char(name));
            if idx < 1 || idx > numel(app.ROIs)
                error('NeuroAnalyzer:ROI:index', 'ROI index must be between 1 and %d.', numel(app.ROIs));
            end
            if isempty(name)
                app.refreshROITable();
                return;
            end
            app.ROIs(idx).Name = name;
            h = app.ROIs(idx).Handle;
            if hasDrawn(h), h.Label = name; end
            app.refreshROITable();
            if ~isempty(app.LastMethod) && numel(app.ResultROINames) == numel(app.ROIs)
                app.ResultROINames{idx} = name;
                app.plotResults(app.LastMethod);
            end
            app.updateControls();
        end

        %% setLine - Set the kymograph / vessel line from p1 = [x1 y1] to p2 = [x2 y2] (px)
        % Shown as an editable line when drawline is available, else as a plain overlay.
        function setLine(app, p1, p2)
            if isempty(app.Stack)
                error('NeuroAnalyzer:ROI:noStack', 'Load a stack before setting a line.');
            end
            try delete(app.CurrentLine); catch, end
            app.CurrentLine = [];
            app.LineStart = double(p1(:)'); app.LineEnd = double(p2(:)');
            app.showFrame();                         % editable line if drawline exists, else overlay
            app.onShapeMoved();
        end

        %% setMotionCorrection - Turn rigid motion correction on or off (estimates it if needed)
        % Returns true on success.
        function ok = setMotionCorrection(app, tf)
            tf = logical(tf);
            app.MotionCb.Value = tf;
            if tf && ~isempty(app.Stack) && isempty(app.RegStack)
                ok = app.runMotionCorrection();
                return;
            end
            ok = true;
            app.CorrImage = []; app.MeanImage = [];
            if isempty(app.Stack), app.updateControls(); return; end
            app.showFrame();
            app.plotMotion();
            app.clearResults();
            app.updateControls();
            if tf
                UIKit.setStatus(app.W.Status, 'Motion correction on.', 'info');
            else
                UIKit.setStatus(app.W.Status, ['Motion correction off: the raw frames are used. ROIs and ' ...
                    'line stay where they are.'], 'info');
            end
        end

        %% runMotionCorrection - Estimate and apply rigid shifts (FFT phase correlation)
        % Registers every frame onto the mean image (two passes), ticks
        % Motion correction and plots the shifts. Returns true on success.
        function ok = runMotionCorrection(app)
            ok = false;
            if isempty(app.Stack)
                UIKit.alert(app.UIFig, 'Load a stack first (step 1).', 'Motion correction');
                return;
            end
            dlg = UIKit.busy(app.UIFig, sprintf('Motion correction: estimating frame shifts%s', char(8230)));
            UIKit.setStatus(app.W.Status, 'Estimating frame shifts', 'busy');
            try
                app.computeMotion();
            catch ME
                UIKit.done(dlg);
                app.MotionCb.Value = false;
                app.updateControls();
                UIKit.setStatus(app.W.Status, 'Motion correction failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Motion correction failed: %s', ME.message), 'Motion correction');
                return;
            end
            UIKit.done(dlg);
            app.MotionCb.Value = true;
            app.CorrImage = []; app.MeanImage = [];
            app.showFrame();
            app.plotMotion();
            app.clearResults();
            app.ResultTabs.SelectedTab = app.MotionTab;
            app.updateControls();
            UIKit.setStatus(app.W.Status, sprintf(['Motion corrected: shifts up to %.1f px (mean %.1f px). ' ...
                'Next: add ROIs or Detect cells (step 3).'], max(abs(app.Shifts(:))), ...
                mean(hypot(app.Shifts(:, 1), app.Shifts(:, 2)))), 'success');
            ok = true;
        end

        %% detectCells - Add one ROI per active cell found in the correlation image
        % opts (optional struct): options of detectCellsFromCorrelation
        % (Threshold, MinArea, MaxArea, MaxElongation, ...). Replaces the
        % ROIs of a previous detection. Returns the number of cells added.
        function n = detectCells(app, opts)
            n = 0;
            if nargin < 2 || isempty(opts), opts = struct(); end
            if isempty(app.Stack)
                UIKit.alert(app.UIFig, 'Load a stack first (step 1).', 'Detect cells');
                return;
            end
            dlg = UIKit.busy(app.UIFig, sprintf('Detecting cells (correlation image)%s', char(8230)));
            UIKit.setStatus(app.W.Status, 'Detecting cells', 'busy');
            try
                C = app.correlationImage();
                o = struct();
                if app.MotionCb.Value && ~isempty(app.Shifts)
                    o.BorderMargin = ceil(max(abs(app.Shifts(:))));   % edge copies after shifting
                end
                if app.DetectThresholdEdit.Value > 0, o.Threshold = app.DetectThresholdEdit.Value; end
                f = fieldnames(opts);
                for k = 1:numel(f), o.(f{k}) = opts.(f{k}); end
                [masks, ~, ~, thr] = detectCellsFromCorrelation(C, o);
                % Number the cells left to right (by centroid column), so the numbering is predictable
                if numel(masks) > 1
                    cx = cellfun(@(m) mean(find(any(m, 1))), masks);
                    [~, order] = sort(cx);
                    masks = masks(order);
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, 'Cell detection failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Cell detection failed: %s', ME.message), 'Detect cells');
                return;
            end
            UIKit.done(dlg);
            app.DetectThreshold = thr;
            if app.DetectThresholdEdit.Value == 0 && ~isempty(app.DetectThresholdLabel)
                app.DetectThresholdLabel.Text = sprintf('Detect: min corr. (auto %.2f)', thr);
            end
            % Replace the previous detection, keep drawn / file ROIs
            old = strcmp({app.ROIs.Source}, 'detected');
            for k = find(old)
                if hasDrawn(app.ROIs(k).Handle), delete(app.ROIs(k).Handle); end
            end
            app.ROIs(old) = [];
            for k = 1:numel(masks)
                app.appendROI(app.nextROIName('Cell'), masks{k}, [], 'detected');
            end
            n = numel(masks);
            app.SelectedROI = [];
            app.showFrame();
            app.refreshROITable();
            app.clearResults();
            app.updateControls();
            if n == 0
                hint = 'lower Detect: min correlation';
                if ~app.MotionCb.Value, hint = ['tick Motion correction first (motion makes every edge ' ...
                        'look correlated), or ' hint]; end
                UIKit.setStatus(app.W.Status, sprintf('No cells found (correlation >= %.2f): %s.', thr, hint), 'warning');
            else
                UIKit.setStatus(app.W.Status, sprintf(['Detected %d cell(s) (correlation >= %.2f). ' ...
                    'Next: choose a method and click Run (step 4).'], n, thr), 'success');
            end
        end

        %% setDisplay - Background image: 'first' | 'mean' | 'correlation' (or the Show item)
        function setDisplay(app, mode)
            items = app.DisplayItems;
            k = find(strcmpi(items, char(mode)), 1);
            if isempty(k), k = find(strncmpi(items, char(mode), numel(char(mode))), 1); end
            if isempty(k)
                error('NeuroAnalyzer:ROI:display', 'Unknown display ''%s''. Use one of: %s', ...
                    char(mode), strjoin(items, ', '));
            end
            app.DisplayDropdown.Value = items{k};
            if isempty(app.Stack), return; end
            if strcmp(items{k}, 'Correlation image') && isempty(app.CorrImage)
                dlg = UIKit.busy(app.UIFig, sprintf('Computing the correlation image%s', char(8230)));
                try
                    app.correlationImage();
                catch ME
                    UIKit.done(dlg);
                    UIKit.alert(app.UIFig, sprintf('Correlation image failed: %s', ME.message), 'Show');
                    app.DisplayDropdown.Value = 'First frame';
                    return;
                end
                UIKit.done(dlg);
            end
            app.showFrame();
        end

        %% setRobustDiameter - Robust vessel diameter on/off (clears current results)
        function setRobustDiameter(app, tf)
            app.RobustCb.Value = logical(tf);
            app.onSettingsChanged();
        end

        %% runAnalysis - Run a method with the current ROIs / line (scripts / CI)
        % methodName: a Method item ('Brightness', 'Movement', 'Both',
        % 'ΔF/F (gCaMP)', 'Speed (flow)', 'Kymograph', 'Vessel diameter'),
        % a case-insensitive prefix of one, or 'dF/F' / 'dff'. Omitted =
        % the selected method. Returns true when results were computed.
        function ok = runAnalysis(app, methodName)
            if nargin >= 2 && ~isempty(methodName)
                items = app.MethodDropdown.Items;
                name = char(methodName);
                if any(strcmpi(name, {'dff', 'df/f', 'deltaf/f'})), name = 'ΔF/F'; end
                k = find(strcmpi(items, name), 1);
                if isempty(k), k = find(strncmpi(items, name, numel(name)), 1); end
                if isempty(k)
                    error('NeuroAnalyzer:ROI:unknownMethod', 'Unknown method ''%s''. Use one of: %s', ...
                        name, strjoin(items, ', '));
                end
                app.MethodDropdown.Value = items{k};
                app.onSettingsChanged();
            end
            app.computeAndPlot();
            ok = ~isempty(app.LastMethod);
        end

        %% showFrame - Background image with every ROI outline and the line on top
        % Drawn rectangles and the line are re-created as editable shapes
        % (imshow deletes them); other ROIs are outlined with contours.
        function showFrame(app)
            T = UITheme;
            ax = app.AxesImage;
            if isempty(app.Stack)
                UIKit.emptyAxes(ax, 'Load a stack (or Try demo data) to begin');
                return;
            end
            linePos = app.linePosition();
            [img, what] = app.displayImage();
            imshow(img, [], 'Parent', ax);
            hold(ax, 'on');
            for k = 1:numel(app.ROIs)
                r = app.ROIs(k);
                col = roiColor(k);
                if ~isempty(r.Position)
                    h = [];
                    try
                        h = drawrectangle(ax, 'Position', r.Position, 'Label', r.Name, 'Color', col);
                        id = r.Id;
                        addlistener(h, 'ROIMoved', @(~,~)app.onRectMoved(id));
                    catch
                    end
                    app.ROIs(k).Handle = h;
                    if ~isempty(h), continue; end
                end
                if any(r.Mask(:))
                    contour(ax, double(r.Mask), [0.5 0.5], 'LineColor', col, 'LineWidth', 1.5);
                    [yy, xx] = find(r.Mask);
                    text(ax, mean(xx), min(yy) - 1, sprintf('%d', k), 'Color', col, 'FontWeight', 'bold', ...
                        'FontSize', T.fontSmall, 'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'bottom', 'Clipping', 'on');
                end
            end
            hold(ax, 'off');
            app.CurrentLine = [];
            if ~isempty(linePos)
                app.LineStart = linePos(1, :); app.LineEnd = linePos(2, :);
                try
                    app.CurrentLine = drawline(ax, 'Position', linePos, 'Label', 'Line', ...
                        'Color', T.plotColors(6, :));
                    addlistener(app.CurrentLine, 'ROIMoved', @(~,~)app.onShapeMoved());
                catch
                    app.CurrentLine = [];
                    hold(ax, 'on');
                    plot(ax, linePos(:, 1), linePos(:, 2), '-', 'Color', T.plotColors(6, :), ...
                        'LineWidth', 2, 'Tag', 'typedLine');
                    hold(ax, 'off');
                end
            end
            % Short title (the file name is in step 1): a long one ran under the axes toolbar
            what(1) = upper(what(1));
            title(ax, what, 'Interpreter', 'none', ...
                'FontWeight', 'bold', 'Color', T.sectionTitleColor, 'FontSize', T.fontSmall);
        end

        %% drawROI - Add a ROI by dragging a rectangle (Image Processing Toolbox)
        function drawROI(app)
            if isempty(app.Stack)
                UIKit.alert(app.UIFig, 'Load a stack first (step 1).', 'ROI');
                return;
            end
            UIKit.setStatus(app.W.Status, 'Drag a rectangle on the image to add a ROI', 'busy');
            name = app.nextROIName('ROI');
            col = roiColor(numel(app.ROIs) + 1);
            try
                h = drawrectangle(app.AxesImage, 'Label', name, 'Color', col);
            catch
                UIKit.setStatus(app.W.Status, 'Could not draw a ROI', 'error');
                UIKit.alert(app.UIFig, ['Could not draw a rectangle. drawrectangle needs the Image ' ...
                    'Processing Toolbox. Without it, use Detect cells, or save the stack in a .mat ' ...
                    'together with a logical roiMask (H x W) or roiMasks (H x W x K) and load that file.'], 'ROI');
                app.updateControls();
                return;
            end
            if ~hasDrawn(h) || isempty(h.Position) || any(h.Position(3:4) <= 0)
                try delete(h); catch, end
                app.updateControls();
                UIKit.setStatus(app.W.Status, 'No ROI drawn', 'info');
                return;
            end
            k = app.appendROI(name, rectMask(h.Position, size(app.Stack, 1), size(app.Stack, 2)), ...
                h.Position, 'drawn');
            app.ROIs(k).Handle = h;
            app.CurrentROI = h;
            id = app.ROIs(k).Id;
            addlistener(h, 'ROIMoved', @(~,~)app.onRectMoved(id));
            app.refreshROITable();
            app.onShapeMoved();
        end

        function drawLine(app)
            if isempty(app.Stack)
                UIKit.alert(app.UIFig, 'Load a stack first (step 1).', 'Line');
                return;
            end
            try delete(app.CurrentLine); catch, end
            app.CurrentLine = [];
            app.LineStart = []; app.LineEnd = [];
            app.showFrame();
            UIKit.setStatus(app.W.Status, 'Click and drag on the image to draw the line', 'busy');
            try
                app.CurrentLine = drawline(app.AxesImage, 'Label', 'Line', ...
                    'Color', UITheme.plotColors(6, :));
                delete(findobj(app.AxesImage, 'Tag', 'typedLine'));
                addlistener(app.CurrentLine, 'ROIMoved', @(~,~)app.onShapeMoved());
            catch
                UIKit.setStatus(app.W.Status, 'Could not draw a line', 'error');
                UIKit.alert(app.UIFig, ['Could not draw a line. drawline needs the Image ' ...
                    'Processing Toolbox; Kymograph and Vessel diameter are not available without it.'], 'Line');
                app.updateControls();
                return;
            end
            app.onShapeMoved();
        end

        %% onRectMoved - A drawn rectangle was moved / resized: update its mask
        function onRectMoved(app, id)
            k = find([app.ROIs.Id] == id, 1);
            if ~isempty(k) && hasDrawn(app.ROIs(k).Handle)
                pos = app.ROIs(k).Handle.Position;
                app.ROIs(k).Position = pos;
                app.ROIs(k).Mask = rectMask(pos, size(app.Stack, 1), size(app.Stack, 2));
                app.syncLegacy();
                app.refreshROITable();
            end
            app.onShapeMoved();
        end

        function onShapeMoved(app)
            app.clearResults();
            app.updateControls();
            UIKit.setStatus(app.W.Status, 'ROI / line set. Next: choose the method and click Run (step 4).', 'info');
        end

        function onSettingsChanged(app)
            if ~isempty(app.LastMethod)
                app.clearResults();
                UIKit.setStatus(app.W.Status, 'Settings changed: click Run again.', 'info');
            end
            app.updateControls();
        end

        %% onTableEdit - Rename from the Name column of the ROI table
        function onTableEdit(app, evt)
            if isempty(evt.Indices), return; end
            row = evt.Indices(1); col = evt.Indices(2);
            if col == 2 && row <= numel(app.ROIs)
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

        %% clearShapes - Remove drawn / added / detected ROIs and the line (file ROIs stay)
        function clearShapes(app)
            keep = ismember({app.ROIs.Source}, {'file', 'mask'});
            for k = find(~keep)
                if hasDrawn(app.ROIs(k).Handle), delete(app.ROIs(k).Handle); end
            end
            app.ROIs = app.ROIs(keep);
            app.CurrentROI = [];
            try delete(app.CurrentLine); catch, end
            app.CurrentLine = [];
            app.LineStart = []; app.LineEnd = [];
            app.SelectedROI = [];
            app.syncLegacy();
            if ~isempty(app.Stack), app.showFrame(); end
            app.refreshROITable();
            app.clearResults();
            app.updateControls();
            UIKit.setStatus(app.W.Status, 'ROIs and line cleared', 'info');
        end

        %% clearResults - Drop computed series (they no longer match the settings)
        function clearResults(app)
            app.Intensity = []; app.Movement = []; app.DFF = []; app.Speed = [];
            app.Kymo = []; app.Diameter = [];
            app.DiameterPlain = []; app.DiameterRaw = []; app.DiameterOutliers = [];
            app.ResultROINames = {}; app.ResultROIMasks = [];
            app.LastMethod = '';
            if ~isempty(app.AxesPlot) && isvalid(app.AxesPlot)
                colorbar(app.AxesPlot, 'off');
                cla(app.AxesPlot, 'reset');
                UIKit.emptyAxes(app.AxesPlot, 'Results appear here after Run (step 4)');
            end
        end

        function first = firstFrame(app)
            % First frame as a 2-D grayscale image (H x W x N or H x W x 3 x N stacks)
            if ndims(app.Stack) == 4
                first = mean(double(app.Stack(:, :, :, 1)), 3);
            else
                first = app.Stack(:, :, 1);
            end
        end

        function tf = hasROI(app)
            tf = ~isempty(app.ROIs) && ~isempty(app.Stack);
        end

        function tf = hasLine(app)
            tf = ~isempty(app.linePosition());
        end

        function computeAndPlot(app)
            if isempty(app.Stack)
                UIKit.alert(app.UIFig, 'Load a stack first (step 1).', 'Run');
                return;
            end
            method = app.MethodDropdown.Value;
            needLine = ismember(method, app.LineMethods);

            % ROI masks (drawn rectangles are read at their current position)
            masks = [];
            if ~needLine
                masks = app.roiMaskStack();
                if isempty(masks)
                    UIKit.alert(app.UIFig, 'Add a ROI first (Add ROI or Detect cells, step 3).', 'Run');
                    return;
                end
            end
            if needLine
                pos = app.linePosition();
                if isempty(pos)
                    UIKit.alert(app.UIFig, 'Draw a line first (Draw line, step 3) for Kymograph or Vessel diameter.', 'Run');
                    return;
                end
                app.LineStart = pos(1, :);
                app.LineEnd = pos(2, :);
            end

            dlg = UIKit.busy(app.UIFig, sprintf('%s: preprocessing and computing...', method));
            UIKit.setStatus(app.W.Status, sprintf('Computing %s', method), 'busy');
            nReplaced = 0;
            try
                stack = app.preprocessedStack();
                app.clearResults();
                N = size(stack, 3);
                app.T = 1:N;
                if ~isempty(app.TimeVec) && numel(app.TimeVec) == N
                    app.T = app.TimeVec(:)';
                end
                K = size(masks, 3);
                switch method
                    case 'Brightness'
                        app.Intensity = perROI(@(m) roiIntensityOverTime(stack, m, app.T), masks, N);
                    case 'Movement'
                        app.Movement = perROI(@(m) roiMovement(stack, m, app.T, 'diff'), masks, N);
                    case 'Both'
                        app.Intensity = perROI(@(m) roiIntensityOverTime(stack, m, app.T), masks, N);
                        app.Movement = perROI(@(m) roiMovement(stack, m, app.T, 'diff'), masks, N);
                    case 'ΔF/F (gCaMP)'
                        nBase = app.BaselineFramesEdit.Value;
                        app.DFF = perROI(@(m) deltaFOverF(stack, m, app.T, 'first', nBase), masks, N);
                    case 'Speed (flow)'
                        app.Speed = perROI(@(m) roiFlowSpeed(stack, m, app.T), masks, N);
                    case 'Kymograph'
                        [app.Kymo, ~, app.T] = kymograph(stack, app.LineStart, app.LineEnd, app.T);
                    case 'Vessel diameter'
                        robust = logical(app.RobustCb.Value);
                        [app.Diameter, app.T, ~, isOut, info] = vesselDiameterFromLine(stack, ...
                            app.LineStart, app.LineEnd, app.T, 'fwhm', 'Robust', robust);
                        if robust
                            app.DiameterOutliers = isOut;
                            app.DiameterRaw = info.rawDiameter;
                            app.DiameterPlain = vesselDiameterFromLine(stack, app.LineStart, app.LineEnd, app.T, 'fwhm');
                            nReplaced = nnz(isOut);
                        end
                end
                if ~needLine
                    app.ResultROINames = {app.ROIs(1:K).Name};
                    app.ResultROIMasks = masks;
                end
            catch ME
                UIKit.done(dlg);
                app.clearResults();
                app.updateControls();
                UIKit.setStatus(app.W.Status, sprintf('%s failed', method), 'error');
                UIKit.alert(app.UIFig, sprintf('%s failed: %s', method, ME.message), 'Run');
                return;
            end
            UIKit.done(dlg);
            app.LastMethod = method;
            app.plotResults(method);
            app.ResultTabs.SelectedTab = app.ResultTab;
            app.updateControls();
            extra = '';
            if ~needLine && size(masks, 3) > 1
                extra = sprintf(' for %d ROIs', size(masks, 3));
            elseif strcmp(method, 'Vessel diameter') && app.RobustCb.Value
                extra = sprintf(' (robust: %d frame(s) replaced)', nReplaced);
            end
            UIKit.setStatus(app.W.Status, sprintf('%s computed%s over %d frames. Next: Export (step 5).', ...
                method, extra, numel(app.T)), 'success');
        end

        %% plotResults - Plot the computed series (one per ROI) or kymograph image
        % cla 'reset' clears a previous yyaxis right side; colorbar removed explicitly.
        function plotResults(app, method)
            T = UITheme;
            ax = app.AxesPlot;
            colorbar(ax, 'off');
            cla(ax, 'reset');
            if app.TimeFromFile, xl = 'Time (s)'; else, xl = 'Frame'; end
            c = T.plotColors;
            if strcmp(method, 'Kymograph') && ~isempty(app.Kymo)
                imagesc(ax, app.T, 1:size(app.Kymo, 1), app.Kymo);
                ax.YDir = 'normal';
                axis(ax, 'tight');
                colorbar(ax);
                UIKit.styleAxes(ax, 'Kymograph along the line', xl, 'Position along line (px)');
                ax.XGrid = 'off'; ax.YGrid = 'off';
                return;
            end
            if strcmp(method, 'Vessel diameter')
                hold(ax, 'on');
                hs = gobjects(0); lab = {};
                if ~isempty(app.DiameterPlain)
                    hs(end+1) = plot(ax, app.T, app.DiameterPlain, '-', 'Color', T.stimColor, 'LineWidth', 0.8);
                    lab{end+1} = 'Standard (min/max half level)';
                end
                hs(end+1) = plot(ax, app.T, app.Diameter, '-', 'Color', c(3, :), 'LineWidth', 1.4);
                ttl = 'Vessel diameter';
                if app.RobustCb.Value && ~isempty(app.DiameterOutliers)
                    lab{end+1} = 'Robust';
                    ttl = 'Vessel diameter (robust)';
                    out = app.DiameterOutliers;
                    if any(out)
                        hs(end+1) = plot(ax, app.T(out), app.Diameter(out), 'o', 'Color', c(2, :), ...
                            'MarkerSize', 5, 'LineWidth', 1);
                        lab{end+1} = 'Replaced frames';
                    end
                else
                    lab{end+1} = 'Diameter';
                end
                hold(ax, 'off');
                UIKit.styleAxes(ax, ttl, xl, 'Diameter (px)');
                if numel(hs) > 1
                    legend(ax, hs, lab, 'Location', 'best', 'FontSize', T.fontTiny, 'Box', 'off');
                    % Keep the robust trace readable when the standard one spikes
                    d = app.Diameter(isfinite(app.Diameter));
                    if ~isempty(d)
                        span = max(d) - min(d);
                        ylim(ax, [min(d) - max(1, 0.5 * span), max(d) + max(1, 0.5 * span)]);
                    end
                end
                return;
            end

            names = app.ResultROINames;
            K = numel(names);
            if strcmp(method, 'Both')
                yyaxis(ax, 'left');
                hold(ax, 'on');
                hL = gobjects(1, K);
                for k = 1:K
                    col = roiColor(k);
                    if K == 1, col = c(1, :); end
                    hL(k) = plot(ax, app.T, app.Intensity(k, :), '-', 'Color', col, 'LineWidth', 1.2);
                end
                ylabel(ax, 'Mean intensity');
                yyaxis(ax, 'right');
                hold(ax, 'on');
                hR = gobjects(1, K);
                for k = 1:K
                    if K == 1
                        hR(k) = plot(ax, app.T, app.Movement(k, :), '-', 'Color', c(2, :), 'LineWidth', 1);
                    else
                        hR(k) = plot(ax, app.T, app.Movement(k, :), ':', 'Color', roiColor(k), 'LineWidth', 1);
                    end
                end
                ylabel(ax, 'Movement (mean |Δ|)');
                yyaxis(ax, 'left');
                if K == 1
                    UIKit.styleAxes(ax, method, xl, []);
                    ax.YAxis(1).Color = c(1, :);
                    ax.YAxis(2).Color = c(2, :);
                    legend(ax, [hL hR], {'Brightness', 'Movement'}, 'Location', 'best', ...
                        'FontSize', T.fontTiny, 'Box', 'off');
                else
                    UIKit.styleAxes(ax, 'Both: brightness (solid, left) and movement (dotted, right)', xl, []);
                    ax.YAxis(1).Color = T.bodyColor;
                    ax.YAxis(2).Color = T.bodyColor;
                    legend(ax, hL, names, 'Location', 'best', 'FontSize', T.fontTiny, 'Box', 'off', ...
                        'Interpreter', 'none');
                end
                return;
            end
            switch method
                case 'Brightness',    Y = app.Intensity; yl = 'Mean intensity';
                case 'Movement',      Y = app.Movement;  yl = 'Movement (mean |Δ|)';
                case 'ΔF/F (gCaMP)',  Y = app.DFF;       yl = 'ΔF/F';
                otherwise,            Y = app.Speed;     yl = 'Speed (flow proxy)';
            end
            hold(ax, 'on');
            h = gobjects(1, K);
            for k = 1:K
                h(k) = plot(ax, app.T, Y(k, :), '-', 'Color', roiColor(k), 'LineWidth', 1.2);
            end
            hold(ax, 'off');
            UIKit.styleAxes(ax, method, xl, yl);
            if K > 1
                legend(ax, h, names, 'Location', 'best', 'FontSize', T.fontTiny, 'Box', 'off', ...
                    'Interpreter', 'none');
            end
        end

        %% plotMotion - Estimated shifts per frame (and the true ones for the demo)
        function plotMotion(app)
            T = UITheme;
            ax = app.AxesMotion;
            cla(ax, 'reset');
            if isempty(app.Shifts) || isempty(app.Stack)
                UIKit.emptyAxes(ax, 'Tick Motion correction (step 2) to estimate the frame shifts');
                return;
            end
            N = size(app.Shifts, 1);
            t = 1:N; xl = 'Frame';
            if app.TimeFromFile && numel(app.TimeVec) == N
                t = app.TimeVec(:)'; xl = 'Time (s)';
            end
            c = T.plotColors;
            hold(ax, 'on');
            hs = [plot(ax, t, app.Shifts(:, 1), '-', 'Color', c(1, :), 'LineWidth', 1.2), ...
                  plot(ax, t, app.Shifts(:, 2), '-', 'Color', c(2, :), 'LineWidth', 1.2)];
            lab = {'dy (rows)', 'dx (columns)'};
            tr = app.DemoTruth;
            if isstruct(tr) && isfield(tr, 'shifts') && isequal(size(tr.shifts), [N 2])
                hs(end+1) = plot(ax, t, tr.shifts(:, 1), '--', 'Color', T.stimColor, 'LineWidth', 0.8);
                plot(ax, t, tr.shifts(:, 2), '--', 'Color', T.stimColor, 'LineWidth', 0.8);
                lab{end+1} = 'True shifts (demo)';
            end
            hold(ax, 'off');
            ttl = sprintf('Estimated rigid shifts (max %.1f px)', max(abs(app.Shifts(:))));
            if ~app.MotionCb.Value, ttl = [ttl ' - not applied']; end
            UIKit.styleAxes(ax, ttl, xl, 'Shift (px)');
            legend(ax, hs, lab, 'Location', 'best', 'FontSize', T.fontTiny, 'Box', 'off');
        end

        %% exportResults - Ask for a file name, then save the current result (.csv or .mat)
        function exportResults(app)
            if isempty(app.LastMethod)
                UIKit.alert(app.UIFig, 'Run an analysis first (step 4).', 'Export');
                return;
            end
            startDir = ProjectManager.getExportDir();
            if isempty(startDir), startDir = pwd; end
            [~, base] = fileparts(app.FileName);
            tag = lower(regexprep(app.LastMethod, '[^A-Za-z]+', '_'));
            tag = regexprep(tag, '^_+|_+$', '');
            [file, path] = uiputfile({'*.csv', 'CSV table (*.csv)'; '*.mat', 'MAT file (*.mat)'}, ...
                'Export ROI results', fullfile(startDir, sprintf('%s_%s.csv', base, tag)));
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.exportResultsTo(fullfile(path, file));
        end

        %% exportResultsTo - Save the current result without dialogs; true on success
        % .csv: Time + one column per measure and ROI (single ROI: Intensity,
        % Movement, DFF, Speed; several: <measure>_<ROI name>), or
        % Diameter_px (+ Diameter_standard_px, Replaced when robust); the
        % kymograph as a matrix (first row = time). .mat: struct results
        % with every series, all ROI masks and names, line, shifts and settings.
        function ok = exportResultsTo(app, fullPath)
            ok = false;
            if isempty(app.LastMethod)
                UIKit.alert(app.UIFig, 'Run an analysis first (step 4).', 'Export');
                return;
            end
            [~, fname, ext] = fileparts(fullPath);
            try
                t = app.T(:);
                if strcmpi(ext, '.csv')
                    if ~isempty(app.Kymo)
                        % Kymograph: first row = time, then one row per position along the line
                        writematrix([app.T(:)'; app.Kymo], fullPath);
                    else
                        tbl = table(t, 'VariableNames', {'Time'});
                        names = app.ResultROINames;
                        K = numel(names);
                        cols = {'Intensity', app.Intensity; 'Movement', app.Movement; ...
                            'DFF', app.DFF; 'Speed', app.Speed};
                        for m = 1:size(cols, 1)
                            v = cols{m, 2};
                            if isempty(v), continue; end
                            for k = 1:size(v, 1)
                                if K <= 1
                                    col = cols{m, 1};
                                else
                                    col = matlab.lang.makeValidName(sprintf('%s_%s', cols{m, 1}, names{k}));
                                    col = matlab.lang.makeUniqueStrings(col, tbl.Properties.VariableNames);
                                end
                                tbl.(col) = padTo(v(k, :), numel(t));
                            end
                        end
                        if ~isempty(app.Diameter)
                            tbl.Diameter_px = padTo(app.Diameter, numel(t));
                            if ~isempty(app.DiameterPlain)
                                tbl.Diameter_standard_px = padTo(app.DiameterPlain, numel(t));
                                tbl.Replaced = padTo(double(app.DiameterOutliers), numel(t));
                            end
                        end
                        writetable(tbl, fullPath);
                    end
                else
                    masks = app.ResultROIMasks;
                    first = [];
                    if ~isempty(masks), first = masks(:, :, 1); end
                    results = struct('method', app.LastMethod, 'sourceFile', app.FileName, ...
                        't', app.T, 'intensity', app.Intensity, 'movement', app.Movement, ...
                        'dff', app.DFF, 'speed', app.Speed, 'kymograph', app.Kymo, ...
                        'diameter', app.Diameter, 'roiMask', first, 'roiMasks', masks, ...
                        'roiNames', {app.ResultROINames}, ...
                        'lineStart', app.LineStart, 'lineEnd', app.LineEnd, ...
                        'motionCorrection', logical(app.MotionCb.Value), 'shifts', app.Shifts, ...
                        'bw256', logical(app.ConvertBWCb.Value), 'smooth', logical(app.SmoothCb.Value), ...
                        'normalize', logical(app.NormalizeCb.Value), ...
                        'dffBaselineFrames', app.BaselineFramesEdit.Value, ...
                        'robustDiameter', logical(app.RobustCb.Value), ...
                        'diameterStandard', app.DiameterPlain, 'diameterPerFrame', app.DiameterRaw, ...
                        'diameterReplaced', app.DiameterOutliers);
                    save(fullPath, 'results');
                end
                UIKit.setStatus(app.W.Status, sprintf('Exported %s to %s%s', app.LastMethod, fname, ext), 'success');
                ok = true;
            catch ME
                UIKit.setStatus(app.W.Status, 'Export failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Export failed: %s', ME.message), 'Export');
            end
        end
    end

    methods(Access = private)

        %% applyLoaded - Replace the data (new stack): reset ROIs, line, caches and results
        function applyLoaded(app, stack, timeVec, timeFromFile, masks, roiNames, fileName)
            app.deleteROIHandles();
            try delete(app.CurrentLine); catch, end
            app.Stack = stack;
            app.TimeVec = timeVec;
            app.TimeFromFile = timeFromFile;
            app.ROIs = app.ROIs([]);
            app.SelectedROI = [];
            app.CurrentROI = []; app.CurrentLine = [];
            app.LineStart = []; app.LineEnd = [];
            app.RegStack = []; app.Shifts = []; app.RegValid = [];
            app.CorrImage = []; app.MeanImage = []; app.DetectThreshold = [];
            app.MotionCb.Value = false;
            app.DemoTruth = [];
            app.FileName = fileName;
            sz = size(stack);
            maskInfo = '';
            if ~isempty(masks)
                if size(masks, 1) == sz(1) && size(masks, 2) == sz(2)
                    for k = 1:size(masks, 3)
                        if k <= numel(roiNames) && ~isempty(roiNames{k})
                            nm = roiNames{k};
                        else
                            nm = sprintf('ROI %d', k);
                        end
                        app.appendROI(nm, masks(:, :, k), [], 'file');
                    end
                    if size(masks, 3) == 1
                        maskInfo = sprintf(' · roiMask (%d px)', nnz(masks));
                    else
                        maskInfo = sprintf(' · %d ROIs (roiMasks)', size(masks, 3));
                    end
                else
                    maskInfo = ' · roiMask size does not match (ignored)';
                end
            end
            app.MaskFromFile = ~isempty(app.ROIs);
            app.syncLegacy();
            app.clearResults();

            % Describe what was loaded
            if ndims(stack) == 4
                nFr = sz(4); kind = 'RGB';
            else
                nFr = size(stack, 3); kind = 'grayscale';
            end
            if app.TimeFromFile && numel(app.TimeVec) == nFr
                tInfo = sprintf('time %.3g to %.3g', app.TimeVec(1), app.TimeVec(end));
            else
                tInfo = 'time = frame index';
            end
            app.FileLabel.Text = sprintf('%s\n%d x %d px · %d frames · %s\n%s%s', ...
                fileName, sz(2), sz(1), nFr, kind, tInfo, maskInfo);
            app.DisplayDropdown.Value = 'First frame';
            app.showFrame();
            app.refreshROITable();
            app.plotMotion();
            app.updateControls();
        end

        %% appendROI - Add a ROI record; returns its index
        function k = appendROI(app, name, mask, pos, source)
            r = struct('Id', app.NextROIId, 'Name', name, 'Mask', logical(mask), ...
                'Position', pos, 'Source', source, 'Handle', []);
            app.NextROIId = app.NextROIId + 1;
            if isempty(app.ROIs)
                app.ROIs = r;
            else
                app.ROIs(end + 1) = r;
            end
            k = numel(app.ROIs);
            app.syncLegacy();
        end

        %% nextROIName - First unused '<prefix> <n>'
        function name = nextROIName(app, prefix)
            used = {app.ROIs.Name};
            n = sum(strncmp(used, prefix, numel(prefix))) + 1;
            name = sprintf('%s %d', prefix, n);
            while any(strcmp(used, name))
                n = n + 1;
                name = sprintf('%s %d', prefix, n);
            end
        end

        %% deleteROIHandles - Delete every drawn rectangle object
        function deleteROIHandles(app)
            for k = 1:numel(app.ROIs)
                if hasDrawn(app.ROIs(k).Handle), delete(app.ROIs(k).Handle); end
            end
        end

        %% syncLegacy - Keep the single-ROI properties (ROIMask) in step with ROI 1
        function syncLegacy(app)
            if isempty(app.ROIs)
                app.ROIMask = [];
            else
                app.ROIMask = app.ROIs(1).Mask;
            end
        end

        function checkMaskSize(app, mask)
            if ~isequal(size(mask), [size(app.Stack, 1), size(app.Stack, 2)])
                error('NeuroAnalyzer:ROI:maskSize', 'The mask must be %d x %d (H x W).', ...
                    size(app.Stack, 1), size(app.Stack, 2));
            end
        end

        %% refreshROITable - One row per ROI, number cell in the ROI colour
        function refreshROITable(app)
            tbl = app.ROITable;
            K = numel(app.ROIs);
            data = cell(K, 4);
            for k = 1:K
                data(k, :) = {sprintf('%d', k), app.ROIs(k).Name, nnz(app.ROIs(k).Mask), app.ROIs(k).Source};
            end
            tbl.Data = data;
            try
                removeStyle(tbl);
                for k = 1:K
                    addStyle(tbl, uistyle('BackgroundColor', roiColor(k), 'FontColor', [1 1 1], ...
                        'FontWeight', 'bold'), 'cell', [k 1]);
                end
            catch
            end
        end

        %% roiMaskStack - H x W x K masks of all ROIs (drawn rectangles at their current position)
        function masks = roiMaskStack(app)
            H = size(app.Stack, 1); W = size(app.Stack, 2);
            K = numel(app.ROIs);
            masks = false(H, W, K);
            for k = 1:K
                h = app.ROIs(k).Handle;
                if hasDrawn(h)
                    app.ROIs(k).Position = h.Position;
                    app.ROIs(k).Mask = rectMask(h.Position, H, W);
                end
                masks(:, :, k) = app.ROIs(k).Mask;
            end
            app.syncLegacy();
        end

        %% linePosition - [x1 y1; x2 y2] of the drawn or typed line, [] if none
        function pos = linePosition(app)
            pos = [];
            if hasDrawn(app.CurrentLine)
                pos = app.CurrentLine.Position;
            elseif ~isempty(app.LineStart) && ~isempty(app.LineEnd)
                pos = [app.LineStart(:)'; app.LineEnd(:)'];
            end
        end

        function n = nFrames(app)
            if isempty(app.Stack)
                n = 0;
            elseif ndims(app.Stack) == 4
                n = size(app.Stack, 4);
            else
                n = size(app.Stack, 3);
            end
        end

        %% grayStack - The stack as double H x W x N (RGB collapsed to the channel mean)
        function stack = grayStack(app)
            stack = double(app.Stack);
            if ndims(stack) == 4
                stack = reshape(mean(stack, 3), size(stack, 1), size(stack, 2), size(stack, 4));
            end
        end

        %% computeMotion - Register the grayscale stack onto its mean (no UI)
        function computeMotion(app)
            [app.RegStack, app.Shifts, info] = registerStackRigid(app.grayStack(), 'mean');
            app.RegValid = info.validMask;
        end

        %% baseStack - Grayscale stack, motion-corrected when Motion correction is on
        function stack = baseStack(app)
            if app.MotionCb.Value
                if isempty(app.RegStack), app.computeMotion(); end
                stack = app.RegStack;
            else
                stack = app.grayStack();
            end
        end

        %% preprocessedStack - Motion correction, then B&W, smoothing, normalization
        function stack = preprocessedStack(app)
            stack = app.baseStack();
            if app.ConvertBWCb.Value
                stack = imageToGrayscale256(stack);
            end
            if app.SmoothCb.Value
                stack = imageStackSmooth(stack, 2, 'gaussian');
            end
            if app.NormalizeCb.Value
                stack = imageStackNormalize(stack, 'frame');
            end
        end

        %% correlationImage - Local correlation image of the (motion-corrected) stack, cached
        function C = correlationImage(app)
            if isempty(app.CorrImage)
                app.CorrImage = localCorrelationImage(app.baseStack());
            end
            C = app.CorrImage;
        end

        %% displayImage - Image for the Show setting and a short description
        function [img, what] = displayImage(app)
            mc = app.MotionCb.Value && ~isempty(app.RegStack);
            switch app.DisplayDropdown.Value
                case 'Mean image'
                    if isempty(app.MeanImage), app.MeanImage = mean(app.baseStack(), 3); end
                    img = app.MeanImage; what = 'mean image';
                case 'Correlation image'
                    img = app.correlationImage(); what = 'correlation image';
                otherwise
                    if mc
                        img = app.RegStack(:, :, 1);
                    else
                        img = app.firstFrame();
                    end
                    what = 'frame 1';
            end
            if mc, what = [what ', motion-corrected']; end
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% hasDrawn - True for a valid (not deleted) drawn ROI/line object
function tf = hasDrawn(h)
    tf = ~isempty(h) && isvalid(h);
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

%% roiColor - Colour of ROI k (UITheme.plotColors; sky blue is kept for the line)
function c = roiColor(k)
    P = UITheme.plotColors([1 2 3 4 5 7], :);
    c = P(mod(k - 1, size(P, 1)) + 1, :);
end

%% rectMask - Logical H x W mask of a drawrectangle Position [x y w h]
function m = rectMask(pos, H, W)
    pos = round(pos);
    x1 = max(1, pos(1)); y1 = max(1, pos(2));
    x2 = min(W, pos(1) + pos(3));
    y2 = min(H, pos(2) + pos(4));
    m = false(H, W);
    m(y1:y2, x1:x2) = true;
end

%% perROI - Apply fun(mask) to every ROI mask; one row per ROI
function Y = perROI(fun, masks, N)
    K = size(masks, 3);
    Y = NaN(K, N);
    for k = 1:K
        y = fun(masks(:, :, k));
        Y(k, 1:numel(y)) = y(:)';
    end
end

%% padTo - Column vector of length n (NaN-padded)
function v = padTo(v, n)
    v = double(v(:));
    if numel(v) < n, v(end+1:n) = NaN; end
    v = v(1:n);
end
