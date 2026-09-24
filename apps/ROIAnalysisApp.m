%% ROIAnalysisApp.m
% =========================================================================
% ROI / COREGISTERED IMAGE ANALYSIS
% =========================================================================
% Load an image stack (time series of coregistered frames), define a ROI,
% optionally convert to 256-level B&W for fluorescence, then compute
% brightness (mean intensity) and movement (frame-to-frame change) in the
% ROI over time. Plot and export.
%
% Layout (UIKit.window): numbered step cards on the left
%   1 Load stack  2 Preprocess  3 Draw ROI or line  4 Analysis + Run  5 Export
% and on the right the first frame with the ROI / line overlay above the
% result plot. One updateControls() sets every enable state.
% =========================================================================

classdef ROIAnalysisApp < handle
    properties
        UIFig
        W                    % UIKit.window struct (Fig, Body, Status, HelpBtn)
        LoadBtn
        FileLabel
        ConvertBWCb          % Convert to B&W (256 levels)
        DrawROIBtn
        ComputeBtn
        MethodDropdown       % Brightness, Movement, Both, ΔF/F, Speed, Kymograph, Vessel diameter
        SmoothCb
        NormalizeCb
        DrawLineBtn
        ClearShapeBtn
        ShapeLabel           % Current ROI / line description
        BaselineFramesEdit   % ΔF/F baseline: first N frames
        ExportBtn
        ExportLabel
        AxesImage
        AxesPlot
        FileName
        Stack                % H x W x N or H x W x 3 x N
        TimeVec
        TimeFromFile = false % true when TimeVec came from timeVec/t in a .mat (seconds)
        ROIMask              % logical H x W
        MaskFromFile = false % true when ROIMask is the roiMask stored in the .mat
        CurrentROI           % drawrectangle handle (optional)
        LineStart            % [x1 y1] for kymograph / vessel
        LineEnd              % [x2 y2]
        CurrentLine          % drawline handle (optional)
        Intensity
        Movement
        T
        DFF
        Speed
        Kymo
        Diameter
        LastMethod = ''      % Method of the current results ('' = none)
    end

    properties(Constant, Access = private)
        LineMethods = {'Kymograph', 'Vessel diameter'}
    end

    methods
        function app = ROIAnalysisApp()
            app.buildUI();
            app.updateControls();
        end

        %% buildUI - Header | step cards (left) + frame and result plots (right) | status
        function buildUI(app)
            T = UITheme;
            app.W = UIKit.window('ROI / Image Analysis', ...
                'Brightness, movement, ΔF/F, flow speed, kymograph and vessel diameter from image stacks', ...
                'ROI Analysis', [1200 840]);
            app.UIFig = app.W.Fig;
            body = app.W.Body;
            body.RowHeight = {'1x'};
            body.ColumnWidth = {310, '1x'};

            % === LEFT: numbered step cards ===
            left = uigridlayout(body, [5 1], 'RowHeight', {122, 122, 140, 150, 96}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');

            % --- 1 Load stack ---
            g1 = uigridlayout(UIKit.card(left), [3 1], 'RowHeight', {'fit', T.buttonHeight, '1x'}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g1, 1, 'Load stack');
            app.LoadBtn = UIKit.button(g1, 'Load stack', @(~,~)app.loadStack(), 'primary', ...
                ['.mat with stack or frames (H x W x N or H x W x 3 x N; optional timeVec or t, ' ...
                 'roiMask), or a multi-frame TIFF']);
            app.FileLabel = uilabel(g1, 'Text', 'No stack loaded', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on', 'Interpreter', 'none', ...
                'VerticalAlignment', 'top');

            % --- 2 Preprocess ---
            g2 = uigridlayout(UIKit.card(left), [5 1], ...
                'RowHeight', {'fit', 20, 20, 20, '1x'}, 'Padding', [10 8 10 8], ...
                'RowSpacing', 4, 'BackgroundColor', T.cardBg);
            UIKit.step(g2, 2, 'Preprocess (optional)');
            app.ConvertBWCb = uicheckbox(g2, 'Text', 'B&W 256 levels', 'Value', 0, ...
                'FontSize', T.fontBody, ...
                'Tooltip', 'Convert every frame to 256-level grayscale (uint8), e.g. for fluorescence intensity');
            app.SmoothCb = uicheckbox(g2, 'Text', 'Smooth (Gaussian, sigma 2 px)', 'Value', 0, ...
                'FontSize', T.fontBody, 'Tooltip', 'Gaussian-smooth each frame (sigma = 2 pixels)');
            app.NormalizeCb = uicheckbox(g2, 'Text', 'Normalize each frame to 0-1', 'Value', 0, ...
                'FontSize', T.fontBody, 'Tooltip', 'Per-frame min/max normalization to the range 0-1');
            uilabel(g2, 'Text', 'Applied in this order when you click Run.', ...
                'FontSize', T.fontTiny, 'FontColor', T.mutedColor);
            for cb = {app.ConvertBWCb, app.SmoothCb, app.NormalizeCb}
                cb{1}.ValueChangedFcn = @(~,~)app.onSettingsChanged();
            end

            % --- 3 Draw ROI or line ---
            g3 = uigridlayout(UIKit.card(left), [4 2], ...
                'RowHeight', {'fit', T.buttonHeight, T.buttonHeight, '1x'}, ...
                'ColumnWidth', {'1x', '1x'}, 'Padding', [10 8 10 8], 'RowSpacing', 6, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            s = UIKit.step(g3, 3, 'Draw ROI or line');
            s.Layout.Row = 1; s.Layout.Column = [1 2];
            app.DrawROIBtn = UIKit.button(g3, 'Draw ROI', @(~,~)app.drawROI(), 'secondary', ...
                'Drag a rectangle on the frame. Used by Brightness, Movement, ΔF/F and Speed.');
            app.DrawROIBtn.Layout.Row = 2; app.DrawROIBtn.Layout.Column = 1;
            app.DrawLineBtn = UIKit.button(g3, 'Draw line', @(~,~)app.drawLine(), 'secondary', ...
                'Draw a line on the frame (across the vessel for diameter). Used by Kymograph and Vessel diameter.');
            app.DrawLineBtn.Layout.Row = 2; app.DrawLineBtn.Layout.Column = 2;
            app.ClearShapeBtn = UIKit.button(g3, 'Clear ROI and line', @(~,~)app.clearShapes(), ...
                'secondary', 'Remove the drawn ROI and line');
            app.ClearShapeBtn.Layout.Row = 3; app.ClearShapeBtn.Layout.Column = [1 2];
            app.ShapeLabel = uilabel(g3, 'Text', '', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on', 'VerticalAlignment', 'top');
            app.ShapeLabel.Layout.Row = 4; app.ShapeLabel.Layout.Column = [1 2];

            % --- 4 Analysis + Run ---
            g4 = uigridlayout(UIKit.card(left), [4 1], ...
                'RowHeight', {'fit', T.controlHeight, T.controlHeight, T.buttonHeight}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g4, 4, 'Analysis');
            f4a = uigridlayout(g4, [1 2], 'ColumnWidth', {70, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.MethodDropdown = UIKit.field(f4a, 'Method', 'dropdown', ...
                {{'Brightness', 'Movement', 'Both', 'ΔF/F (gCaMP)', 'Speed (flow)', 'Kymograph', 'Vessel diameter'}, 'Both'}, ...
                ['ROI methods: Brightness (mean intensity), Movement (mean |frame difference|), Both, ' ...
                 'ΔF/F, Speed (flow proxy). Line methods: Kymograph, Vessel diameter (FWHM)']);
            app.MethodDropdown.ValueChangedFcn = @(~,~)app.onSettingsChanged();
            f4b = uigridlayout(g4, [1 2], 'ColumnWidth', {'1x', 80}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.BaselineFramesEdit = UIKit.field(f4b, 'ΔF/F baseline (frames)', 'numeric', 30, ...
                'F0 = mean ROI intensity over the first N frames (ΔF/F only)', [1 Inf]);
            app.BaselineFramesEdit.RoundFractionalValues = 'on';
            app.BaselineFramesEdit.ValueChangedFcn = @(~,~)app.onSettingsChanged();
            app.ComputeBtn = UIKit.button(g4, 'Run', @(~,~)app.computeAndPlot(), 'primary', ...
                'Preprocess the stack and compute the selected method');

            % --- 5 Export ---
            g5 = uigridlayout(UIKit.card(left), [3 1], 'RowHeight', {'fit', T.buttonHeight, '1x'}, ...
                'Padding', [10 8 10 8], 'RowSpacing', 6, 'BackgroundColor', T.cardBg);
            UIKit.step(g5, 5, 'Export');
            app.ExportBtn = UIKit.button(g5, 'Export results', @(~,~)app.exportResults(), ...
                'secondary', ['Save the result: .csv (time + one column per measure; kymograph as ' ...
                 'a matrix) or .mat (results plus ROI/line and settings)']);
            app.ExportLabel = uilabel(g5, 'Text', 'Run an analysis first', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');

            % === RIGHT: first frame with overlay above the result plot ===
            right = uigridlayout(body, [2 1], 'RowHeight', {'1.2x', '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray);
            imgCard = UIKit.card(right, 'First frame with ROI / line');
            ig = uigridlayout(imgCard, [1 1], 'Padding', [8 8 8 8], 'BackgroundColor', T.cardBg);
            app.AxesImage = uiaxes(ig);
            UIKit.emptyAxes(app.AxesImage, 'Load a stack to begin');
            plotCard = UIKit.card(right, 'Result: time series or kymograph');
            pg = uigridlayout(plotCard, [1 1], 'Padding', [8 6 8 6], 'BackgroundColor', T.cardBg);
            app.AxesPlot = uiaxes(pg);
            UIKit.emptyAxes(app.AxesPlot, 'Results appear here after Run (step 4)');

            UIKit.setStatus(app.W.Status, 'Load an image stack to begin (step 1).', 'info');
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
            for c = {app.ConvertBWCb, app.SmoothCb, app.NormalizeCb, app.DrawROIBtn, ...
                    app.DrawLineBtn, app.MethodDropdown}
                c{1}.Enable = onOff{hasStack + 1};
            end
            app.ClearShapeBtn.Enable = onOff{(hasStack && (hasDrawn(app.CurrentROI) || hasLine)) + 1};
            app.BaselineFramesEdit.Enable = onOff{(hasStack && strcmp(method, 'ΔF/F (gCaMP)')) + 1};
            app.ComputeBtn.Enable = onOff{ready + 1};
            app.ExportBtn.Enable = onOff{hasRes + 1};
            % Recommended next action is primary
            styleBtn(app.DrawROIBtn, hasStack && ~needLine && ~hasROI);
            styleBtn(app.DrawLineBtn, hasStack && needLine && ~hasLine);
            styleBtn(app.ComputeBtn, ready && ~hasRes);
            styleBtn(app.ExportBtn, hasRes);

            % What is defined right now, and what the chosen method needs
            parts = {};
            if hasDrawn(app.CurrentROI)
                p = round(app.CurrentROI.Position);
                parts{end+1} = sprintf('ROI: %d x %d px at (%d, %d).', p(3), p(4), p(1), p(2));
            elseif app.MaskFromFile && ~isempty(app.ROIMask)
                parts{end+1} = sprintf('ROI: roiMask from file (%d px).', nnz(app.ROIMask));
            end
            if hasDrawn(app.CurrentLine)
                p = app.CurrentLine.Position;
                parts{end+1} = sprintf('Line: %.0f px long.', hypot(p(2,1) - p(1,1), p(2,2) - p(1,2)));
            end
            if ~hasStack
                parts = {'Load a stack first.'};
            elseif needLine && ~hasLine
                parts{end+1} = sprintf('%s needs a line: click Draw line.', method);
            elseif ~needLine && ~hasROI
                parts{end+1} = sprintf('%s needs a ROI: click Draw ROI.', method);
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
            fullPath = fullfile(path, file);
            [~, ~, ext] = fileparts(file);
            dlg = UIKit.busy(app.UIFig, sprintf('Loading %s...', file));
            UIKit.setStatus(app.W.Status, sprintf('Loading %s', file), 'busy');
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
                    app.Stack = stack;
                    if ismember('timeVec', fn)
                        app.TimeVec = s.timeVec;
                    elseif ismember('t', fn)
                        app.TimeVec = s.t;
                    else
                        app.TimeVec = [];
                    end
                    if ismember('roiMask', fn)
                        app.ROIMask = logical(s.roiMask);
                    else
                        app.ROIMask = [];
                    end
                    app.TimeFromFile = ~isempty(app.TimeVec);
                else
                    info = imfinfo(fullPath);
                    n = numel(info);
                    first = imread(fullPath, 1);
                    % Preallocate double; RGB(A) frames are collapsed to the
                    % grayscale mean of the colour channels
                    app.Stack = zeros(size(first, 1), size(first, 2), n);
                    for k = 1:n
                        fr = double(imread(fullPath, k));
                        if ndims(fr) == 3
                            fr = mean(fr(:, :, 1:min(3, size(fr, 3))), 3);
                        end
                        app.Stack(:, :, k) = fr;
                    end
                    app.TimeVec = 1:n;
                    app.ROIMask = [];
                    app.TimeFromFile = false;
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.W.Status, 'Load failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Load failed: %s', ME.message), 'Load error');
                return;
            end
            UIKit.done(dlg);
            % Drawn ROI/line belong to the previous stack; drop them so a
            % roiMask loaded from .mat is actually used
            try delete(app.CurrentROI); catch, end
            try delete(app.CurrentLine); catch, end
            app.CurrentROI = []; app.CurrentLine = [];
            app.LineStart = []; app.LineEnd = [];
            app.MaskFromFile = ~isempty(app.ROIMask);
            app.FileName = file;
            app.clearResults();

            % Describe what was loaded
            sz = size(app.Stack);
            if ndims(app.Stack) == 4
                nFr = sz(4); kind = 'RGB';
            else
                nFr = sz(3); kind = 'grayscale';
            end
            if app.TimeFromFile && numel(app.TimeVec) == nFr
                tInfo = sprintf('time %.3g to %.3g', app.TimeVec(1), app.TimeVec(end));
            else
                tInfo = 'time = frame index';
            end
            maskInfo = '';
            if app.MaskFromFile
                if isequal(size(app.ROIMask), sz(1:2))
                    maskInfo = sprintf(' · roiMask (%d px)', nnz(app.ROIMask));
                else
                    maskInfo = ' · roiMask size does not match (ignored)';
                end
            end
            app.FileLabel.Text = sprintf('%s\n%d x %d px · %d frames · %s · %s%s', ...
                file, sz(2), sz(1), nFr, kind, tInfo, maskInfo);
            app.showFrame();
            app.updateControls();
            UIKit.setStatus(app.W.Status, sprintf('Loaded %s (%d frames). Next: draw a ROI or line (step 3).', ...
                file, nFr), 'success');
        end

        %% showFrame - First frame with the file roiMask outline (drawn shapes stay on top)
        function showFrame(app)
            T = UITheme;
            ax = app.AxesImage;
            imshow(app.firstFrame(), [], 'Parent', ax);
            if app.MaskFromFile && ~isempty(app.ROIMask) && ...
                    isequal(size(app.ROIMask), [size(app.Stack, 1), size(app.Stack, 2)]) && ...
                    ~hasDrawn(app.CurrentROI)
                hold(ax, 'on');
                contour(ax, double(app.ROIMask), [0.5 0.5], 'LineColor', T.plotColors(5, :), ...
                    'LineWidth', 1.5);
                hold(ax, 'off');
            end
            title(ax, sprintf('%s (frame 1)', app.FileName), 'Interpreter', 'none', ...
                'FontWeight', 'bold', 'Color', T.sectionTitleColor, 'FontSize', T.fontSmall);
        end

        function drawROI(app)
            if isempty(app.Stack)
                UIKit.alert(app.UIFig, 'Load a stack first (step 1).', 'ROI');
                return;
            end
            try
                delete(app.CurrentROI);
            catch
            end
            app.CurrentROI = [];
            linePos = shapePosition(app.CurrentLine);
            app.showFrame();
            app.restoreShape('line', linePos);
            UIKit.setStatus(app.W.Status, 'Drag a rectangle on the frame to define the ROI', 'busy');
            try
                app.CurrentROI = drawrectangle(app.AxesImage, 'Label', 'ROI', ...
                    'Color', UITheme.plotColors(5, :));
                app.ROIMask = [];
                app.MaskFromFile = false;
                delete(findobj(app.AxesImage, 'Type', 'contour'));  % file mask no longer used
                addlistener(app.CurrentROI, 'ROIMoved', @(~,~)app.onShapeMoved());
            catch
                UIKit.setStatus(app.W.Status, 'Could not draw a ROI', 'error');
                UIKit.alert(app.UIFig, ['Could not draw a rectangle. drawrectangle needs the Image ' ...
                    'Processing Toolbox. Without it, save the stack in a .mat together with a ' ...
                    'logical roiMask (H x W) and load that file.'], 'ROI');
                app.updateControls();
                return;
            end
            app.onShapeMoved();
        end

        function drawLine(app)
            if isempty(app.Stack)
                UIKit.alert(app.UIFig, 'Load a stack first (step 1).', 'Line');
                return;
            end
            try
                delete(app.CurrentLine);
            catch
            end
            app.CurrentLine = [];
            roiPos = shapePosition(app.CurrentROI);
            app.showFrame();
            app.restoreShape('roi', roiPos);
            UIKit.setStatus(app.W.Status, 'Click and drag on the frame to draw the line', 'busy');
            try
                app.CurrentLine = drawline(app.AxesImage, 'Label', 'Line', ...
                    'Color', UITheme.plotColors(6, :));
                app.LineStart = []; app.LineEnd = [];
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

        %% restoreShape - Re-create a ROI or line after the frame was redrawn
        % imshow replaces the axes content, which deletes existing ROI
        % objects, so the other shape is rebuilt at its previous position.
        function restoreShape(app, kind, pos)
            if isempty(pos), return; end
            try
                if strcmp(kind, 'roi')
                    app.CurrentROI = drawrectangle(app.AxesImage, 'Position', pos, ...
                        'Label', 'ROI', 'Color', UITheme.plotColors(5, :));
                    addlistener(app.CurrentROI, 'ROIMoved', @(~,~)app.onShapeMoved());
                else
                    app.CurrentLine = drawline(app.AxesImage, 'Position', pos, ...
                        'Label', 'Line', 'Color', UITheme.plotColors(6, :));
                    addlistener(app.CurrentLine, 'ROIMoved', @(~,~)app.onShapeMoved());
                end
            catch
            end
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

        function clearShapes(app)
            try delete(app.CurrentROI); catch, end
            try delete(app.CurrentLine); catch, end
            app.CurrentROI = []; app.CurrentLine = [];
            app.LineStart = []; app.LineEnd = [];
            if ~app.MaskFromFile, app.ROIMask = []; end
            if ~isempty(app.Stack), app.showFrame(); end
            app.clearResults();
            app.updateControls();
            UIKit.setStatus(app.W.Status, 'ROI and line cleared', 'info');
        end

        %% clearResults - Drop computed series (they no longer match the settings)
        function clearResults(app)
            app.Intensity = []; app.Movement = []; app.DFF = []; app.Speed = [];
            app.Kymo = []; app.Diameter = [];
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
            tf = hasDrawn(app.CurrentROI) || (~isempty(app.ROIMask) && ~isempty(app.Stack) && ...
                isequal(size(app.ROIMask), [size(app.Stack, 1), size(app.Stack, 2)]));
        end

        function tf = hasLine(app)
            tf = hasDrawn(app.CurrentLine) || (~isempty(app.LineStart) && ~isempty(app.LineEnd));
        end

        function computeAndPlot(app)
            if isempty(app.Stack)
                UIKit.alert(app.UIFig, 'Load a stack first (step 1).', 'Run');
                return;
            end
            method = app.MethodDropdown.Value;
            needROI = ~ismember(method, app.LineMethods);
            needLine = ismember(method, app.LineMethods);

            % Build ROI mask from drawn rectangle or use stored mask
            if needROI
                if hasDrawn(app.CurrentROI)
                    pos = round(app.CurrentROI.Position);
                    H = size(app.Stack, 1); W = size(app.Stack, 2);
                    x1 = max(1, pos(1)); y1 = max(1, pos(2));
                    x2 = min(W, pos(1) + pos(3));
                    y2 = min(H, pos(2) + pos(4));
                    app.ROIMask = false(H, W);
                    app.ROIMask(y1:y2, x1:x2) = true;
                end
                if isempty(app.ROIMask) || ~isequal(size(app.ROIMask), [size(app.Stack, 1), size(app.Stack, 2)])
                    UIKit.alert(app.UIFig, 'Draw a ROI first for this analysis type (step 3).', 'Run');
                    return;
                end
            end

            if needLine
                if hasDrawn(app.CurrentLine)
                    pos = app.CurrentLine.Position;
                    app.LineStart = pos(1, :);
                    app.LineEnd = pos(2, :);
                end
                if isempty(app.LineStart) || isempty(app.LineEnd)
                    UIKit.alert(app.UIFig, 'Draw a line first (Draw line, step 3) for Kymograph or Vessel diameter.', 'Run');
                    return;
                end
            end

            dlg = UIKit.busy(app.UIFig, sprintf('%s: preprocessing and computing...', method));
            UIKit.setStatus(app.W.Status, sprintf('Computing %s', method), 'busy');
            try
                stack = double(app.Stack);
                if ndims(stack) == 4
                    % H x W x 3 x N (RGB stack): collapse to grayscale mean per frame
                    stack = reshape(mean(stack, 3), size(stack, 1), size(stack, 2), size(stack, 4));
                end
                if app.ConvertBWCb.Value
                    stack = imageToGrayscale256(stack);
                end
                if app.SmoothCb.Value
                    stack = imageStackSmooth(stack, 2, 'gaussian');
                end
                if app.NormalizeCb.Value
                    stack = imageStackNormalize(stack, 'frame');
                end

                app.Intensity = []; app.Movement = []; app.DFF = []; app.Speed = []; app.Kymo = []; app.Diameter = [];
                app.T = 1:size(stack, 3);
                if ~isempty(app.TimeVec) && numel(app.TimeVec) == size(stack, 3)
                    app.T = app.TimeVec(:)';
                end

                switch method
                    case 'Brightness'
                        [app.Intensity, app.T] = roiIntensityOverTime(stack, app.ROIMask, app.T);
                    case 'Movement'
                        [app.Movement, ~] = roiMovement(stack, app.ROIMask, app.T, 'diff');
                    case 'Both'
                        [app.Intensity, app.T] = roiIntensityOverTime(stack, app.ROIMask, app.T);
                        [app.Movement, ~] = roiMovement(stack, app.ROIMask, app.T, 'diff');
                    case 'ΔF/F (gCaMP)'
                        [app.DFF, app.T, ~] = deltaFOverF(stack, app.ROIMask, app.T, 'first', ...
                            app.BaselineFramesEdit.Value);
                    case 'Speed (flow)'
                        [app.Speed, app.T] = roiFlowSpeed(stack, app.ROIMask, app.T);
                    case 'Kymograph'
                        [app.Kymo, ~, app.T] = kymograph(stack, app.LineStart, app.LineEnd, app.T);
                    case 'Vessel diameter'
                        [app.Diameter, app.T, ~] = vesselDiameterFromLine(stack, app.LineStart, app.LineEnd, app.T, 'fwhm');
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
            app.updateControls();
            UIKit.setStatus(app.W.Status, sprintf('%s computed over %d frames. Next: Export (step 5).', ...
                method, numel(app.T)), 'success');
        end

        %% plotResults - Plot the computed series (or kymograph image)
        % cla 'reset' clears a previous yyaxis right side; colorbar removed explicitly.
        function plotResults(app, method)
            T = UITheme;
            ax = app.AxesPlot;
            colorbar(ax, 'off');
            cla(ax, 'reset');
            if app.TimeFromFile, xl = 'Time (s)'; else, xl = 'Frame'; end
            if strcmp(method, 'Kymograph') && ~isempty(app.Kymo)
                imagesc(ax, app.T, 1:size(app.Kymo, 1), app.Kymo);
                ax.YDir = 'normal';
                axis(ax, 'tight');
                colorbar(ax);
                UIKit.styleAxes(ax, 'Kymograph along the line', xl, 'Position along line (px)');
                ax.XGrid = 'off'; ax.YGrid = 'off';
                return;
            end
            c = T.plotColors;
            yyaxis(ax, 'left');
            leftCol = c(1, :); rightCol = c(2, :);
            if ~isempty(app.Intensity)
                plot(ax, app.T, app.Intensity, '-', 'Color', c(1, :), 'LineWidth', 1.2);
                ylabel(ax, 'Mean intensity');
            end
            if ~isempty(app.DFF)
                plot(ax, app.T, app.DFF, '-', 'Color', c(4, :), 'LineWidth', 1.2);
                ylabel(ax, 'ΔF/F');
                leftCol = c(4, :);
            end
            if ~isempty(app.Diameter)
                plot(ax, app.T, app.Diameter, '-', 'Color', c(3, :), 'LineWidth', 1.2);
                ylabel(ax, 'Diameter (px)');
                leftCol = c(3, :);
            end
            if ~isempty(app.Movement)
                yyaxis(ax, 'right');
                plot(ax, app.T, app.Movement, '-', 'Color', c(2, :), 'LineWidth', 1);
                ylabel(ax, 'Movement (mean |Δ|)');
            end
            if ~isempty(app.Speed)
                yyaxis(ax, 'right');
                plot(ax, app.T, app.Speed, '-', 'Color', c(2, :), 'LineWidth', 1);
                ylabel(ax, 'Speed (flow proxy)');
            end
            yyaxis(ax, 'left');
            UIKit.styleAxes(ax, method, xl, []);
            % styleAxes colors the active y axis only; match each side to its trace
            ax.YAxis(1).Color = leftCol;
            if isempty(app.Movement) && isempty(app.Speed)
                ax.YAxis(2).Visible = 'off';
            else
                ax.YAxis(2).Color = rightCol;
            end
            if strcmp(method, 'Both')
                legend(ax, {'Brightness', 'Movement'}, 'Location', 'best', ...
                    'FontSize', T.fontTiny, 'Box', 'off');
            end
        end

        %% exportResults - Save the current result to .csv or .mat
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
            fullPath = fullfile(path, file);
            try
                t = app.T(:);
                if endsWith(lower(fullPath), '.csv')
                    if ~isempty(app.Kymo)
                        % Kymograph: first row = time, then one row per position along the line
                        writematrix([app.T(:)'; app.Kymo], fullPath);
                    else
                        tbl = table(t, 'VariableNames', {'Time'});
                        cols = {'Intensity', app.Intensity; 'Movement', app.Movement; ...
                            'DFF', app.DFF; 'Speed', app.Speed; 'Diameter_px', app.Diameter};
                        for k = 1:size(cols, 1)
                            v = cols{k, 2};
                            if isempty(v), continue; end
                            v = v(:);
                            if numel(v) < numel(t), v(end+1:numel(t)) = NaN; end %#ok<AGROW>
                            tbl.(cols{k, 1}) = v(1:numel(t));
                        end
                        writetable(tbl, fullPath);
                    end
                else
                    results = struct('method', app.LastMethod, 'sourceFile', app.FileName, ...
                        't', app.T, 'intensity', app.Intensity, 'movement', app.Movement, ...
                        'dff', app.DFF, 'speed', app.Speed, 'kymograph', app.Kymo, ...
                        'diameter', app.Diameter, 'roiMask', app.ROIMask, ...
                        'lineStart', app.LineStart, 'lineEnd', app.LineEnd, ...
                        'bw256', logical(app.ConvertBWCb.Value), 'smooth', logical(app.SmoothCb.Value), ...
                        'normalize', logical(app.NormalizeCb.Value), ...
                        'dffBaselineFrames', app.BaselineFramesEdit.Value);
                    save(fullPath, 'results');
                end
                UIKit.setStatus(app.W.Status, sprintf('Exported %s to %s', app.LastMethod, file), 'success');
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

%% shapePosition - Position of a drawn ROI/line, [] if none
function pos = shapePosition(h)
    pos = [];
    if hasDrawn(h), pos = h.Position; end
end

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
