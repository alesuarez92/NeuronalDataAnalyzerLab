%% ROIAnalysisApp.m
% =========================================================================
% ROI / COREGISTERED IMAGE ANALYSIS
% =========================================================================
% Load an image stack (time series of coregistered frames), define a ROI,
% optionally convert to 256-level B&W for fluorescence, then compute
% brightness (mean intensity) and movement (frame-to-frame change) in the
% ROI over time. Plot and export.
% =========================================================================

classdef ROIAnalysisApp < handle
    properties
        UIFig
        HeaderPanel
        LoadBtn
        FileLabel
        ConvertBWCb          % Convert to B&W (256 levels)
        DrawROIBtn
        ComputeBtn
        MethodDropdown       % Brightness, Movement, Both, ΔF/F, Speed, Kymograph, Vessel diameter
        SmoothCb
        NormalizeCb
        DrawLineBtn
        AxesImage
        AxesPlot
        Stack                % H x W x N or H x W x 3 x N
        TimeVec
        ROIMask              % logical H x W
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
    end

    methods
        function app = ROIAnalysisApp()
            app.buildUI();
        end

        function buildUI(app)
            T = UITheme;
            app.UIFig = uifigure('Name', 'ROI / Coregistered Image Analysis', ...
                'Position', [60 40 1000 640], 'Resize', 'on', 'Color', T.bgGray);

            main = uigridlayout(app.UIFig, [5, 1], ...
                'RowHeight', {T.headerHeight, 48, '1x', 220, T.footerHeight}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 8);

            % --- Header: title + subtitle (left), Help button (right) ---
            app.HeaderPanel = uipanel(main, 'BackgroundColor', T.headerBg, 'BorderType', 'none');
            headerGrid = uigridlayout(app.HeaderPanel, [2, 2], ...
                'ColumnWidth', {'1x', 80}, 'RowHeight', {38, 22}, ...
                'Padding', [T.headerPaddingH 8 20 8], ...
                'ColumnSpacing', 8, 'RowSpacing', 4, ...
                'BackgroundColor', T.headerBg);
            titleLbl = uilabel(headerGrid, 'Text', 'ROI / Coregistered Image Analysis', ...
                'FontSize', T.fontTitle, 'FontWeight', 'bold', 'FontColor', T.headerTitleColor, ...
                'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;
            helpBtn = uibutton(headerGrid, 'push', 'Text', 'Help', ...
                'BackgroundColor', [1 1 1], 'FontColor', T.headerBg, 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~,~)HelpApp('ROI Analysis'));
            helpBtn.Layout.Row = [1 2]; helpBtn.Layout.Column = 2;
            subLbl = uilabel(headerGrid, 'Text', ...
                'ROI/line: brightness, movement, speed, ΔF/F, kymograph, vessel diameter.', ...
                'FontSize', T.fontSubtitle, 'FontColor', T.headerSubtitleColor, ...
                'VerticalAlignment', 'center');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            % --- Fixed controls: Load, preprocess, Draw ROI/Line, Compute ---
            row1 = uigridlayout(main, [1, 9], ...
                'ColumnWidth', {100, '1x', 78, 78, 78, 92, 92, 170, 130}, ...
                'Padding', [10 4 10 4], 'ColumnSpacing', 8);
            app.LoadBtn = uibutton(row1, 'push', 'Text', 'Load Stack', ...
                'BackgroundColor', T.accent, 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~)app.loadStack());
            app.FileLabel = uilabel(row1, 'Text', 'No stack loaded', 'FontColor', T.bodyColor, 'WordWrap', 'on');
            app.ConvertBWCb = uicheckbox(row1, 'Text', 'B&W 256', 'Value', 0, 'Tooltip', 'Fluorescence');
            app.SmoothCb = uicheckbox(row1, 'Text', 'Smooth', 'Value', 0, 'Tooltip', 'Gaussian smooth');
            app.NormalizeCb = uicheckbox(row1, 'Text', 'Norm', 'Value', 0, 'Tooltip', 'Normalize 0-1');
            app.DrawROIBtn = uibutton(row1, 'push', 'Text', 'Draw ROI', 'ButtonPushedFcn', @(~,~)app.drawROI());
            app.DrawLineBtn = uibutton(row1, 'push', 'Text', 'Draw Line', 'ButtonPushedFcn', @(~,~)app.drawLine());
            app.MethodDropdown = uidropdown(row1, 'Items', ...
                {'Brightness', 'Movement', 'Both', 'ΔF/F (gCaMP)', 'Speed (flow)', 'Kymograph', 'Vessel diameter'}, 'Value', 'Both', ...
                'Tooltip', 'ROI: Brightness/Movement/ΔF/F/Speed. Line: Kymograph/Vessel diameter');
            app.ComputeBtn = uibutton(row1, 'push', 'Text', 'Compute & Plot', ...
                'BackgroundColor', T.accent, 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~)app.computeAndPlot());

            % --- Image axes: padding so panel title and axis title not clipped ---
            panelImg = uipanel(main, 'Title', 'Frame (first), ROI or line', ...
                'BackgroundColor', T.cardBg, 'BorderType', 'line', 'HighlightColor', T.cardBorder);
            imgGrid = uigridlayout(panelImg, [1, 1], 'Padding', T.axesPanelPadding);
            app.AxesImage = uiaxes(imgGrid);

            % --- Plot axes: padding for titles ---
            panelPlot = uipanel(main, 'Title', 'Result: time series or kymograph', ...
                'BackgroundColor', T.cardBg, 'BorderType', 'line', 'HighlightColor', T.cardBorder);
            plotGrid = uigridlayout(panelPlot, [1, 1], 'Padding', T.axesPanelPadding);
            app.AxesPlot = uiaxes(plotGrid);

            % --- Fixed footer section for copyright ---
            footerPanel = uipanel(main, 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            footerGrid = uigridlayout(footerPanel, [1, 1], 'Padding', [14 4 14 4], ...
                'BackgroundColor', T.bgGray);
            uihyperlink(footerGrid, ...
                'Text', sprintf('© Copyrights by Alejandro Suarez, Ph.D.  ·  v%s', T.version), ...
                'URL', 'https://github.com/alesuarez92', 'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'HorizontalAlignment', 'right');
        end

        function loadStack(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir), startDir = pwd; end
            [file, path] = uigetfile({'*.mat;*.tif;*.tiff', 'Stack or MAT'; '*.mat', 'MAT'; '*.tif;*.tiff', 'TIFF'}, ...
                'Load image stack', startDir);
            if isequal(file, 0), return; end
            fullPath = fullfile(path, file);
            [~, ~, ext] = fileparts(file);
            try
                if strcmpi(ext, '.mat')
                    s = load(fullPath);
                    fn = fieldnames(s);
                    if ismember('stack', fn)
                        app.Stack = s.stack;
                    elseif ismember('frames', fn)
                        app.Stack = s.frames;
                    else
                        app.Stack = s.(fn{1});
                    end
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
                else
                    info = imfinfo(fullPath);
                    n = numel(info);
                    first = imread(fullPath, 1);
                    app.Stack = zeros([size(first, 1), size(first, 2), n], class(first));
                    app.Stack(:, :, 1) = first;
                    for k = 2:n
                        app.Stack(:, :, k) = imread(fullPath, k);
                    end
                    app.TimeVec = 1:n;
                end
                app.ROIMask = [];
                app.FileLabel.Text = file;
            catch ME
                errordlg(sprintf('Load failed: %s', ME.message), 'Load error');
            end
        end

        function drawROI(app)
            if isempty(app.Stack)
                errordlg('Load a stack first.', 'ROI');
                return;
            end
            first = app.Stack(:, :, 1);
            if ndims(first) == 3
                first = mean(first, 3);
            end
            imshow(first, [], 'Parent', app.AxesImage);
            try
                delete(app.CurrentROI);
            catch
            end
            try
                app.CurrentROI = drawrectangle(app.AxesImage, 'Label', 'ROI');
                app.ROIMask = [];
            catch
                errordlg('Draw a rectangle on the image. If drawrectangle is not available, load a .mat with ''stack'' and ''roiMask'' (logical).', 'ROI');
            end
        end

        function drawLine(app)
            if isempty(app.Stack)
                errordlg('Load a stack first.', 'Line');
                return;
            end
            first = app.Stack(:, :, 1);
            if ndims(first) == 3
                first = mean(first, 3);
            end
            imshow(first, [], 'Parent', app.AxesImage);
            try
                delete(app.CurrentLine);
            catch
            end
            try
                app.CurrentLine = drawline(app.AxesImage, 'Label', 'Line');
                app.LineStart = []; app.LineEnd = [];
            catch
                errordlg('Draw a line for kymograph or vessel diameter. If drawline is not available, set line in .mat as lineStart, lineEnd.', 'Line');
            end
        end

        function computeAndPlot(app)
            if isempty(app.Stack)
                errordlg('Load a stack first.', 'Compute');
                return;
            end
            % Build ROI mask from drawn rectangle or use stored mask
            if ~isempty(app.CurrentROI) && isvalid(app.CurrentROI)
                pos = round(app.CurrentROI.Position);
                H = size(app.Stack, 1); W = size(app.Stack, 2);
                x1 = max(1, pos(1)); y1 = max(1, pos(2));
                x2 = min(W, pos(1) + pos(3));
                y2 = min(H, pos(2) + pos(4));
                app.ROIMask = false(H, W);
                app.ROIMask(y1:y2, x1:x2) = true;
            end
            stack = double(app.Stack);
            if app.ConvertBWCb.Value
                stack = imageToGrayscale256(stack);
            end
            if app.SmoothCb.Value
                stack = imageStackSmooth(stack, 2, 'gaussian');
            end
            if app.NormalizeCb.Value
                stack = imageStackNormalize(stack, 'frame');
            end

            method = app.MethodDropdown.Value;
            needROI = ~ismember(method, {'Kymograph', 'Vessel diameter'});
            needLine = ismember(method, {'Kymograph', 'Vessel diameter'});

            if needROI
                if ~isempty(app.CurrentROI) && isvalid(app.CurrentROI)
                    pos = round(app.CurrentROI.Position);
                    H = size(stack, 1); W = size(stack, 2);
                    x1 = max(1, pos(1)); y1 = max(1, pos(2));
                    x2 = min(W, pos(1) + pos(3)); y2 = min(H, pos(2) + pos(4));
                    app.ROIMask = false(H, W);
                    app.ROIMask(y1:y2, x1:x2) = true;
                end
                if isempty(app.ROIMask) || ~isequal(size(app.ROIMask), [size(stack, 1), size(stack, 2)])
                    errordlg('Draw a ROI first for this analysis type.', 'Compute');
                    return;
                end
            end

            if needLine
                if ~isempty(app.CurrentLine) && isvalid(app.CurrentLine)
                    pos = app.CurrentLine.Position;
                    app.LineStart = pos(1, :);
                    app.LineEnd = pos(2, :);
                end
                if isempty(app.LineStart) || isempty(app.LineEnd)
                    errordlg('Draw a line first (Draw Line) for Kymograph or Vessel diameter.', 'Compute');
                    return;
                end
            end

            app.Intensity = []; app.Movement = []; app.DFF = []; app.Speed = []; app.Kymo = []; app.Diameter = [];
            app.T = 1:size(stack, 3);
            if ~isempty(app.TimeVec) && numel(app.TimeVec) == size(stack, 3)
                app.T = app.TimeVec(:)';
            end

            switch method
                case 'Brightness'
                    [app.Intensity, app.T] = roiIntensityOverTime(stack, app.ROIMask, app.TimeVec);
                case 'Movement'
                    [app.Movement, ~] = roiMovement(stack, app.ROIMask, app.TimeVec, 'diff');
                case 'Both'
                    [app.Intensity, app.T] = roiIntensityOverTime(stack, app.ROIMask, app.TimeVec);
                    [app.Movement, ~] = roiMovement(stack, app.ROIMask, app.TimeVec, 'diff');
                case 'ΔF/F (gCaMP)'
                    [app.DFF, app.T, ~] = deltaFOverF(stack, app.ROIMask, app.TimeVec, 'first', 30);
                case 'Speed (flow)'
                    [app.Speed, app.T] = roiFlowSpeed(stack, app.ROIMask, app.TimeVec);
                case 'Kymograph'
                    [app.Kymo, ~, app.T] = kymograph(stack, app.LineStart, app.LineEnd, app.TimeVec);
                case 'Vessel diameter'
                    [app.Diameter, app.T, ~] = vesselDiameterFromLine(stack, app.LineStart, app.LineEnd, app.TimeVec, 'fwhm');
            end

            % Plot
            cla(app.AxesPlot);
            if strcmp(method, 'Kymograph') && ~isempty(app.Kymo)
                imagesc(app.AxesPlot, app.T, 1:size(app.Kymo, 1), app.Kymo);
                app.AxesPlot.YDir = 'normal';
                xlabel(app.AxesPlot, 'Time (frame or s)');
                ylabel(app.AxesPlot, 'Position along line');
                colorbar(app.AxesPlot);
            else
                yyaxis(app.AxesPlot, 'left');
                if ~isempty(app.Intensity)
                    plot(app.AxesPlot, app.T, app.Intensity, 'Color', [0.2 0.55 0.6], 'LineWidth', 1.2);
                    ylabel(app.AxesPlot, 'Mean intensity');
                end
                if ~isempty(app.DFF)
                    plot(app.AxesPlot, app.T, app.DFF, 'Color', [0.5 0.2 0.5], 'LineWidth', 1.2);
                    ylabel(app.AxesPlot, 'ΔF/F');
                end
                if ~isempty(app.Diameter)
                    plot(app.AxesPlot, app.T, app.Diameter, 'Color', [0.2 0.5 0.3], 'LineWidth', 1.2);
                    ylabel(app.AxesPlot, 'Diameter (px)');
                end
                if ~isempty(app.Movement)
                    yyaxis(app.AxesPlot, 'right');
                    plot(app.AxesPlot, app.T, app.Movement, 'Color', [0.6 0.35 0.2], 'LineWidth', 1);
                    ylabel(app.AxesPlot, 'Movement');
                end
                if ~isempty(app.Speed)
                    yyaxis(app.AxesPlot, 'right');
                    plot(app.AxesPlot, app.T, app.Speed, 'Color', [0.8 0.3 0.2], 'LineWidth', 1);
                    ylabel(app.AxesPlot, 'Speed (flow)');
                end
                xlabel(app.AxesPlot, 'Time (frame or s)');
                grid(app.AxesPlot, 'on');
            end
        end
    end
end
