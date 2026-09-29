%% HistologyApp.m
% =========================================================================
% HISTOLOGY / CULTURE - ALIGN IMAGES, COUNT CELLS, CO-LOCALISE MARKERS
% =========================================================================
% Opened from the launcher (Imaging card, "Histology / culture"). For still
% images of fixed sections or cultures: one or more images (sections, time
% points, wells), each with one or more channels (e.g. nuclei and markers).
%
% Layout (UIKit.window): numbered step cards on the left
%   1 Load images   (TIFF / PNG / JPG / .mat; pixel size from the file or typed)
%   2 Align         (optional: channels onto channel 1; images onto image 1
%                    by an automatic shift or by landmark points, affine)
%   3 Count cells   (channel, background radius, threshold, split touching
%                    cells, size and shape limits; all sizes in um / um2)
%   4 Regions and markers (regions clicked on the image; a cell is positive
%                    for a marker when enough of it is bright in that channel)
%   5 Export        (cells and counts as .csv, everything as .mat; sessions)
% and on the right the image (composite, one channel, or what was
% thresholded) with the counted cells, rejected objects, regions and
% landmarks, above the result tabs Counts | Cells | Checks (plain-language
% checks of the pixel size, alignment, threshold and filters).
% The computations are in core/Histology.m.
%
% Scriptable (CI walkthroughs, no dialogs): openFiles(paths), loadDemo(),
% setPixelSize(um), setAlignment(method, channel, alignChannels),
% setLandmarks(k, movingXY, fixedXY), align(), setCountOptions(o),
% countCells(), addRegion(name, xy), removeRegion(k), setView(k, mode),
% exportResultsTo(path). Sessions: saveSessionTo(path, notes),
% openSession(path), makeReport(pdfPath), sessionState(), restoreSession(s).
% =========================================================================

classdef HistologyApp < handle

    properties
        UIFig
        W                   % UIKit.window struct (Fig, Body, Status, HelpBtn)
        StatusLabel
        % Step 1
        LoadBtn
        DemoBtn
        FileInfo            % what was loaded
        PixelSizeEdit       % um per pixel
        PixelSizeNote       % "from the file" / "type it"
        % Step 2
        AlignChannelsCb
        AlignMethodDrop     % Do not align | Shift (automatic) | Landmarks (click points)
        AlignChannelDrop
        PickLandmarksBtn
        ClearLandmarksBtn
        AlignBtn
        AlignInfo
        % Step 3
        CountChannelDrop
        BackgroundEdit      % um
        ThresholdEdit       % 0 = automatic
        SplitCb
        MinAreaEdit         % um2
        MaxAreaEdit         % um2
        ElongationEdit
        CountBtn
        CountInfo
        % Step 4
        MinFractionEdit     % % of the cell above the marker threshold
        MarkerThresholdEdit % 0 = automatic
        AddRegionBtn
        FinishRegionBtn
        RemoveRegionBtn
        RegionInfo
        % Step 5
        ExportBtn
        SessionBtns
        % Right side
        ImageDrop           % which image is shown
        ViewDrop            % Composite | Channel k | What was thresholded
        MarksCb             % show cells, regions, landmarks
        AxImage
        Tabs
        CountsTable
        CellsTable
        ChecksTable
        ChecksText
        % Data
        Files = {}          % loaded file paths ('' = demo)
        Raw = {}            % images as loaded, 1 x N cell of H x W x C
        Images = {}         % after alignment (what is counted)
        ChannelNames = {}
        ImageNames = {}
        PixelSizeFromFile = false
        Generator = ''      % 'demoHistology' when the demo was loaded
        DemoTruth = []
        ChannelShifts = []  % C x 2 per image (cell), from alignChannels
        Shifts = []         % N x 2 automatic image shifts
        Peaks = []          % 1 x N reliability of the shifts
        Landmarks = {}      % 1 x N struct fixed / moving (K x 2 [x y])
        LandmarkRms = []    % 1 x N px
        AlignedMethod = 'none'   % method of the current Images
        Regions = struct('name', {}, 'xy', {})
        Results = {}        % 1 x N countCells results
        Positives = {}      % 1 x N cell of positive() results per marker channel
        RegionStats = {}    % 1 x N regionCounts results
        CountSettings = []  % options of the last count (um units)
    end

    properties(Access = private)
        ClickMode = ''      % '' | 'region' | 'landmarkFixed' | 'landmarkMoving'
        PendingXY = zeros(0, 2)
        LandmarkImage = 2
    end

    properties(Constant)
        AlignMethods = {'Do not align', 'Shift (automatic)', 'Landmarks (click points)'}
        ViewThresholded = 'What was thresholded'
    end

    methods
        %% Constructor
        function app = HistologyApp()
            app.buildUI();
            app.updateControls();
        end

        %% buildUI - Step cards (left), image and result tabs (right)
        function buildUI(app)
            T = UITheme;
            app.W = UIKit.window('Histology / culture', ...
                'Count cells in still images, compare regions and markers, align sections or time points', ...
                'Histology', [1320 900]);
            app.UIFig = app.W.Fig;
            app.StatusLabel = app.W.Status;
            app.W.Body.RowHeight = {'1x'};
            app.W.Body.ColumnWidth = {360, '1x'};

            left = uigridlayout(app.W.Body, [6 1], 'Padding', [0 0 0 0], 'RowSpacing', 10, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            heights = cell(1, 6);
            ch = T.controlHeight; bh = T.buttonHeight;

            % --- 1 Load images ---
            [p, g, heights{1}] = stepCard(left, 1, 'Load images', {bh, 34, ch, 30});
            p.Layout.Row = 1;
            app.LoadBtn = UIKit.button(g, ['Load images' char(8230)], @(~,~)app.loadDialog(), 'primary', ...
                ['One or more files: TIFF (every page is a channel), PNG / JPG (colours become channels) or .mat ' ...
                 '(variable images, H x W x channels x images). Several files = several sections, time points or wells ' ...
                 '(same channels in each).']);
            app.LoadBtn.Layout.Row = 2; app.LoadBtn.Layout.Column = 1;
            app.DemoBtn = UIKit.button(g, 'Try demo data', @(~,~)app.loadDemo(), 'secondary', ...
                ['Two images of one culture (day 1, day 3) with nuclei and a marker: 60 nuclei, 24 then 39 marker-positive, ' ...
                 'touching pairs, debris and a fibre; see Help for the answers']);
            app.DemoBtn.Layout.Row = 2; app.DemoBtn.Layout.Column = 2;
            app.FileInfo = infoLabel(g, 'Nothing loaded', 'Images, channels and size');
            app.FileInfo.Layout.Row = 3; app.FileInfo.Layout.Column = [1 2];
            app.PixelSizeEdit = addField(g, 4, 'Pixel size (um)', 'numeric', 1, ...
                ['Micrometres per pixel of your images (microscope + objective + camera binning). Needed for sizes in um2 ' ...
                 'and densities per mm2. Read from the file when it says (ImageJ TIFF).'], [1e-4 1e4]);
            app.PixelSizeEdit.ValueChangedFcn = @(~,~)app.onPixelSize();
            app.PixelSizeNote = infoLabel(g, '', 'Where the pixel size comes from');
            app.PixelSizeNote.Layout.Row = 5; app.PixelSizeNote.Layout.Column = [1 2];

            % --- 2 Align ---
            [p, g, heights{2}] = stepCard(left, 2, 'Align (optional)', {ch, ch, ch, bh, bh, 48});
            p.Layout.Row = 2;
            app.AlignChannelsCb = addField(g, 2, 'Align channels', 'checkbox', false, ...
                ['Shift every channel onto channel 1 (corrects the small colour shift of many microscopes, about ' ...
                 'half-pixel accuracy). Leave off if the composite already looks right.']);
            app.AlignMethodDrop = addField(g, 3, 'Align images', 'dropdown', {app.AlignMethods, app.AlignMethods{1}}, ...
                ['Put images 2, 3 ... on top of image 1, so a region covers the same place in every image. Shift: automatic, ' ...
                 'for the same field re-imaged (time points). Landmarks: click the same 3 or more features in both images; ' ...
                 'corrects shift, rotation, scaling and shear (serial sections).']);
            app.AlignMethodDrop.ValueChangedFcn = @(~,~)app.updateControls();
            app.AlignChannelDrop = addField(g, 4, 'Align using channel', 'dropdown', {{'Channel 1'}, 'Channel 1'}, ...
                'The channel with the clearest shared structure (usually nuclei)');
            app.PickLandmarksBtn = UIKit.button(g, ['Pick landmarks' char(8230)], @(~,~)app.startLandmarks(), 'secondary', ...
                ['Click a feature in image 1, then the same feature in the image shown; repeat (3 or more pairs, spread out). ' ...
                 'Press Finish when done.']);
            app.PickLandmarksBtn.Layout.Row = 5; app.PickLandmarksBtn.Layout.Column = 1;
            app.ClearLandmarksBtn = UIKit.button(g, 'Clear landmarks', @(~,~)app.clearLandmarks(), 'secondary', ...
                'Remove the landmarks of the image shown');
            app.ClearLandmarksBtn.Layout.Row = 5; app.ClearLandmarksBtn.Layout.Column = 2;
            app.AlignBtn = UIKit.button(g, 'Align', @(~,~)app.align(), 'secondary', ...
                'Apply the channel and image alignment (the counts are then made on the aligned images)');
            app.AlignBtn.Layout.Row = 6; app.AlignBtn.Layout.Column = [1 2];
            app.AlignInfo = infoLabel(g, 'Not aligned', 'What the alignment did');
            app.AlignInfo.Layout.Row = 7; app.AlignInfo.Layout.Column = [1 2];

            % --- 3 Count cells ---
            [p, g, heights{3}] = stepCard(left, 3, 'Count cells', {ch, ch, ch, ch, ch, ch, ch, bh, 48});
            p.Layout.Row = 3;
            o = HistologyApp.defaultSettings();
            app.CountChannelDrop = addField(g, 2, 'Count in channel', 'dropdown', {{'Channel 1'}, 'Channel 1'}, ...
                'The channel in which every cell is visible, usually nuclei (DAPI, Hoechst)');
            app.BackgroundEdit = addField(g, 3, 'Background radius (um)', 'numeric', o.backgroundRadiusUm, ...
                ['Uneven illumination and haze are removed by subtracting a background that follows everything larger than ' ...
                 'this radius. Use about 2-3 x the radius of a cell.'], [0.1 1e4]);
            app.ThresholdEdit = addField(g, 4, 'Threshold (0 = auto)', 'numeric', 0, ...
                ['Brightness above the background that counts as cell. 0 = automatic (Otsu, but at least 3 noise SD). ' ...
                 'Check it with Show: What was thresholded.'], [0 Inf]);
            app.SplitCb = addField(g, 5, 'Split touching cells', 'checkbox', true, ...
                'Cut objects at their narrow waist, so two touching nuclei count as two (strongly overlapping ones stay one)');
            app.MinAreaEdit = addField(g, 6, 'Min size (um2)', 'numeric', o.minAreaUm2, ...
                'Smaller objects are not counted (debris, noise). A nucleus of 8 um diameter is about 50 um2.', [0 Inf]);
            app.MaxAreaEdit = addField(g, 7, 'Max size (um2)', 'numeric', o.maxAreaUm2, ...
                'Larger objects are not counted (clumps that could not be split, tissue folds)', [0 Inf]);
            app.ElongationEdit = addField(g, 8, 'Max elongation', 'numeric', o.maxElongation, ...
                ['Length / width. Longer objects are not counted (fibres, vessels, processes). Round nuclei are 1-1.5, ' ...
                 'dividing or oval ones up to about 2.'], [1 Inf]);
            app.CountBtn = UIKit.button(g, 'Count cells', @(~,~)app.countCells(), 'primary', ...
                'Count the cells in every image, decide which are positive for each other channel, and fill the tables');
            app.CountBtn.Layout.Row = 9; app.CountBtn.Layout.Column = [1 2];
            app.CountInfo = infoLabel(g, 'Not counted yet', 'Result of the last count');
            app.CountInfo.Layout.Row = 10; app.CountInfo.Layout.Column = [1 2];

            % --- 4 Regions and markers ---
            [p, g, heights{4}] = stepCard(left, 4, 'Regions and markers', {ch, ch, bh, bh, 48});
            p.Layout.Row = 4;
            app.MinFractionEdit = addField(g, 2, 'Positive if (% of cell)', 'numeric', o.minFractionPct, ...
                ['A cell is positive for a marker when at least this part of it is above the marker threshold in that ' ...
                 'channel (50% = most of the cell)'], [1 100]);
            app.MarkerThresholdEdit = addField(g, 3, 'Marker threshold (0 = auto)', 'numeric', 0, ...
                'Brightness above background that counts as marker; 0 = automatic, per channel', [0 Inf]);
            app.AddRegionBtn = UIKit.button(g, 'Add region', @(~,~)app.startRegion(), 'secondary', ...
                ['Click the corners of a region on the image (e.g. a cortical layer, a well area), then Finish region. ' ...
                 'Counts and densities are given per region; without regions, for the whole image.']);
            app.AddRegionBtn.Layout.Row = 4; app.AddRegionBtn.Layout.Column = 1;
            app.FinishRegionBtn = UIKit.button(g, 'Finish', @(~,~)app.finishClicks(), 'secondary', ...
                'Close the region (3 or more corners) or end landmark picking');
            app.FinishRegionBtn.Layout.Row = 4; app.FinishRegionBtn.Layout.Column = 2;
            app.RemoveRegionBtn = UIKit.button(g, 'Remove last region', @(~,~)app.removeRegion(numel(app.Regions)), 'secondary', ...
                'Delete the most recently added region');
            app.RemoveRegionBtn.Layout.Row = 5; app.RemoveRegionBtn.Layout.Column = [1 2];
            app.RegionInfo = infoLabel(g, 'No regions: counts are for the whole image', 'Regions');
            app.RegionInfo.Layout.Row = 6; app.RegionInfo.Layout.Column = [1 2];

            % --- 5 Export ---
            [p, g, heights{5}] = stepCard(left, 5, 'Export', {bh, UIKit.sessionButtonsHeight()});
            p.Layout.Row = 5;
            app.ExportBtn = UIKit.button(g, ['Export results' char(8230)], @(~,~)app.exportDialog(), 'secondary', ...
                ['.csv: one row per cell (image, position, size, region, markers) plus <name>_counts.csv with the counts per ' ...
                 'image and region; .mat: everything, including the label images']);
            app.ExportBtn.Layout.Row = 2; app.ExportBtn.Layout.Column = [1 2];
            app.SessionBtns = UIKit.sessionButtons(g, app);
            app.SessionBtns.Grid.Layout.Row = 3; app.SessionBtns.Grid.Layout.Column = [1 2];
            heights{6} = '1x';
            left.RowHeight = heights;

            % --- Right: image and tabs ---
            right = uigridlayout(app.W.Body, [3 1], 'RowHeight', {ch, '3x', '2x'}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 6, 'BackgroundColor', T.bgGray);
            right.Layout.Row = 1; right.Layout.Column = 2;
            bar = uigridlayout(right, [1 6], 'ColumnWidth', {'fit', 200, 'fit', 230, 'fit', '1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 8, 'BackgroundColor', T.bgGray);
            uilabel(bar, 'Text', 'Image', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            app.ImageDrop = uidropdown(bar, 'Items', {'(none)'}, 'Value', '(none)', ...
                'ValueChangedFcn', @(~,~)app.showImage(), 'Tooltip', 'Which image to show');
            uilabel(bar, 'Text', 'Show', 'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);
            app.ViewDrop = uidropdown(bar, 'Items', {'Composite'}, 'Value', 'Composite', ...
                'ValueChangedFcn', @(~,~)app.showImage(), 'Tooltip', ...
                ['Composite: channel 1 blue, 2 green, 3 red. One channel in grey. What was thresholded: the counting ' ...
                 'channel after background subtraction, with the threshold outline']);
            app.MarksCb = uicheckbox(bar, 'Text', 'Cells and regions', 'Value', true, ...
                'ValueChangedFcn', @(~,~)app.showImage(), 'Tooltip', ...
                'Circles: counted cells (filled yellow = positive for every marker); x: objects not counted; lines: regions');
            uilabel(bar, 'Text', '');
            imgPanel = uipanel(right, 'BackgroundColor', T.cardBg, 'BorderType', 'line', 'HighlightColor', T.cardBorder);
            gi = uigridlayout(imgPanel, [1 1], 'Padding', [4 4 4 4], 'BackgroundColor', T.cardBg);
            app.AxImage = uiaxes(gi);
            app.AxImage.Toolbar.Visible = 'on';
            UIKit.emptyAxes(app.AxImage, 'Load images (or Try demo data) to begin');

            app.Tabs = uitabgroup(right);
            tc = uitab(app.Tabs, 'Title', 'Counts', 'BackgroundColor', T.cardBg);
            g1 = uigridlayout(tc, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.CountsTable = uitable(g1, 'RowName', {}, 'FontSize', T.fontSmall + 1);
            tcl = uitab(app.Tabs, 'Title', 'Cells', 'BackgroundColor', T.cardBg);
            g2 = uigridlayout(tcl, [1 1], 'Padding', [6 6 6 6], 'BackgroundColor', T.cardBg);
            app.CellsTable = uitable(g2, 'RowName', {}, 'FontSize', T.fontSmall + 1);
            tk = uitab(app.Tabs, 'Title', 'Checks', 'BackgroundColor', T.cardBg);
            g3 = uigridlayout(tk, [2 1], 'RowHeight', {'1x', 60}, 'Padding', [6 6 6 6], 'RowSpacing', 6, ...
                'BackgroundColor', T.cardBg);
            app.ChecksTable = uitable(g3, 'RowName', {}, 'ColumnName', {'Result', 'Topic', 'What it means'}, ...
                'ColumnWidth', {70, 110, 'auto'}, 'FontSize', T.fontSmall + 1, ...
                'CellSelectionCallback', @(~, e)app.showCheck(e));
            app.ChecksText = uitextarea(g3, 'Value', {'Count cells (step 3) to see the checks.'}, 'Editable', 'off', ...
                'FontSize', T.fontBody, 'FontColor', T.sectionTitleColor);

            UIKit.setStatus(app.StatusLabel, ['Step 1: load your images (or Try demo data). Type the pixel size if ' ...
                'the file does not give it.'], 'info');
        end

        %% ----------------------------------------------------------------
        %% Step 1: load
        %% loadDialog - Choose one or more image files
        function loadDialog(app)
            start = ProjectManager.getImportDir();
            if isempty(start), start = pwd; end
            [f, p] = uigetfile({'*.tif;*.tiff;*.png;*.jpg;*.jpeg;*.bmp;*.mat', 'Images (TIFF, PNG, JPG, BMP, MAT)'}, ...
                'Load images (select several for sections / time points)', start, 'MultiSelect', 'on');
            figure(app.UIFig);
            if isequal(f, 0), return; end
            app.openFiles(fullfile(p, cellstr(f)));
        end

        %% openFiles - Load files (no dialog); every file adds its image(s)
        % All images must have the same number of channels. Returns true on success.
        function ok = openFiles(app, paths)
            ok = false;
            paths = cellstr(paths);
            dlg = UIKit.busy(app.UIFig, 'Loading images…');
            raw = {}; names = {}; chNames = {}; px = []; truth = [];
            try
                for k = 1:numel(paths)
                    [img, info] = Histology.readImage(paths{k});
                    if isempty(chNames), chNames = info.channelNames; end
                    for n = 1:size(img, 4)
                        if ~isempty(raw) && size(img, 3) ~= size(raw{1}, 3)
                            error('NeuroAnalyzer:Histology:channels', ...
                                '%s has %d channel(s), the first image %d: load images with the same channels together.', ...
                                info.source, size(img, 3), size(raw{1}, 3));
                        end
                        raw{end + 1} = img(:, :, :, n); %#ok<AGROW>
                        names{end + 1} = info.imageNames{n}; %#ok<AGROW>
                    end
                    if isempty(px), px = info.pixelSizeUm; end
                    if isempty(truth), truth = info.truth; end
                end
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not load: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not load the images:\n%s', ME.message), 'Load images', 'error');
                return;
            end
            UIKit.done(dlg);
            app.Files = paths;
            app.Generator = '';
            app.setData(raw, names, chNames, px, truth);
            ok = true;
        end

        %% loadDemo - The histology demo (core/demo/demoHistology), in memory
        function ok = loadDemo(app)
            DemoData.ensureDemoPath();
            dlg = UIKit.busy(app.UIFig, 'Making the demo images…');
            s = demoHistology();
            UIKit.done(dlg);
            raw = {double(s.images(:, :, :, 1)), double(s.images(:, :, :, 2))};
            app.Files = {};
            app.Generator = 'demoHistology';
            app.setData(raw, s.imageNames, s.channelNames, s.pixelSizeUm, s.truth);
            ok = true;
        end

        %% setPixelSize - Micrometres per pixel (typed; replaces the file's value)
        function setPixelSize(app, um)
            app.PixelSizeEdit.Value = um;
            app.onPixelSize();
        end

        %% ----------------------------------------------------------------
        %% Step 2: align
        %% setAlignment - method: 'none' | 'shift' | 'landmarks' (or the dropdown text)
        function setAlignment(app, method, channel, alignChannels)
            app.AlignMethodDrop.Value = app.AlignMethods{methodIndex(method)};
            if nargin >= 3 && ~isempty(channel), app.AlignChannelDrop.Value = app.AlignChannelDrop.Items{channel}; end
            if nargin >= 4 && ~isempty(alignChannels), app.AlignChannelsCb.Value = logical(alignChannels); end
            app.updateControls();
        end

        %% setLandmarks - Landmarks of image k: movingXY in image k, fixedXY in image 1 (K x 2 [x y])
        function setLandmarks(app, k, movingXY, fixedXY)
            app.Landmarks{k} = struct('moving', movingXY, 'fixed', fixedXY);
            app.showImage();
            app.updateControls();
        end

        %% align - Apply channel and image alignment to the loaded images
        function ok = align(app)
            ok = false;
            if isempty(app.Raw), return; end
            N = numel(app.Raw);
            imgs = app.Raw;
            dlg = UIKit.busy(app.UIFig, 'Aligning…');
            try
                app.ChannelShifts = [];
                if app.AlignChannelsCb.Value && size(imgs{1}, 3) > 1
                    app.ChannelShifts = cell(1, N);
                    for k = 1:N
                        [imgs{k}, app.ChannelShifts{k}] = Histology.alignChannels(imgs{k}, 1);
                    end
                end
                method = methodKey(app.AlignMethodDrop.Value);
                app.Shifts = zeros(N, 2); app.Peaks = ones(1, N); app.LandmarkRms = nan(1, N);
                chIdx = find(strcmp(app.AlignChannelDrop.Items, app.AlignChannelDrop.Value), 1);
                if N > 1
                    switch method
                        case 'shift'
                            [imgs, app.Shifts, app.Peaks] = Histology.alignImagesRigid(imgs, chIdx);
                        case 'landmarks'
                            sz = [size(imgs{1}, 1), size(imgs{1}, 2)];
                            for k = 2:N
                                if k <= numel(app.Landmarks) && ~isempty(app.Landmarks{k}) && size(app.Landmarks{k}.fixed, 1) >= 3
                                    [M, app.LandmarkRms(k)] = Histology.fitAffine(app.Landmarks{k}.moving, app.Landmarks{k}.fixed);
                                    imgs{k} = Histology.warpAffine(imgs{k}, M, sz);
                                end
                            end
                    end
                end
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not align: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not align:\n%s', ME.message), 'Align', 'error');
                return;
            end
            app.Images = imgs;
            app.AlignedMethod = method;
            app.clearResults();
            app.AlignInfo.Text = app.alignSummary();
            app.showImage();
            app.updateControls();
            ok = true;
            UIKit.setStatus(app.StatusLabel, ['Aligned. Check the overlay (switch images), then count cells ' ...
                '(step 3).'], 'success');
        end

        %% ----------------------------------------------------------------
        %% Step 3: count
        %% setCountOptions - Any of the fields of defaultSettings (um units)
        function setCountOptions(app, o)
            map = {'backgroundRadiusUm', 'BackgroundEdit'; 'threshold', 'ThresholdEdit'; ...
                'split', 'SplitCb'; 'minAreaUm2', 'MinAreaEdit'; 'maxAreaUm2', 'MaxAreaEdit'; ...
                'maxElongation', 'ElongationEdit'; 'minFractionPct', 'MinFractionEdit'; ...
                'markerThreshold', 'MarkerThresholdEdit'};
            for k = 1:size(map, 1)
                if isfield(o, map{k, 1}), app.(map{k, 2}).Value = o.(map{k, 1}); end
            end
            if isfield(o, 'channel'), app.CountChannelDrop.Value = app.CountChannelDrop.Items{o.channel}; end
        end

        %% currentSettings - The count and marker settings as typed (um units)
        function o = currentSettings(app)
            o = HistologyApp.defaultSettings();
            o.channel = max(1, find(strcmp(app.CountChannelDrop.Items, app.CountChannelDrop.Value), 1));
            o.backgroundRadiusUm = app.BackgroundEdit.Value;
            o.threshold = app.ThresholdEdit.Value;
            o.split = logical(app.SplitCb.Value);
            o.minAreaUm2 = app.MinAreaEdit.Value;
            o.maxAreaUm2 = app.MaxAreaEdit.Value;
            o.maxElongation = app.ElongationEdit.Value;
            o.minFractionPct = app.MinFractionEdit.Value;
            o.markerThreshold = app.MarkerThresholdEdit.Value;
            o.pixelSizeUm = app.PixelSizeEdit.Value;
        end

        %% countCells - Count every image; markers = the other channels
        function ok = countCells(app)
            ok = false;
            if isempty(app.Images)
                UIKit.setStatus(app.StatusLabel, 'Load images first (step 1).', 'warning');
                return;
            end
            o = app.currentSettings();
            px = o.pixelSizeUm;
            copt = struct('BackgroundRadiusPx', max(1, o.backgroundRadiusUm / px), 'Threshold', o.threshold, ...
                'Split', o.split, 'MinAreaPx', o.minAreaUm2 / px^2, 'MaxAreaPx', o.maxAreaUm2 / px^2, ...
                'MaxElongation', o.maxElongation);
            popt = struct('BackgroundRadiusPx', copt.BackgroundRadiusPx, 'Threshold', o.markerThreshold, ...
                'MinFraction', o.minFractionPct / 100);
            N = numel(app.Images);
            markers = setdiff(1:size(app.Images{1}, 3), o.channel);
            dlg = UIKit.busy(app.UIFig, 'Counting cells…');
            try
                app.Results = cell(1, N); app.Positives = cell(1, N); app.RegionStats = cell(1, N);
                for k = 1:N
                    R = Histology.countCells(app.Images{k}(:, :, o.channel), copt);
                    P = cell(1, numel(markers));
                    for m = 1:numel(markers)
                        P{m} = Histology.positive(R.L, app.Images{k}(:, :, markers(m)), popt);
                        P{m}.channel = markers(m);
                    end
                    app.Results{k} = R;
                    app.Positives{k} = P;
                end
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                app.clearResults();
                UIKit.setStatus(app.StatusLabel, sprintf('Could not count: %s', ME.message), 'error');
                return;
            end
            app.CountSettings = o;
            app.updateRegionStats();
            ok = true;
            n = cellfun(@(r) r.n, app.Results);
            app.CountInfo.Text = sprintf('%s cells (%s)', strjoin(arrayfun(@num2str, n, 'UniformOutput', false), ' / '), ...
                strjoin(app.ImageNames, ' / '));
            app.CountInfo.FontColor = UITheme.sectionTitleColor;
            app.showImage();
            app.selectTab('Counts');
            app.updateControls();
            nWarn = nnz(strcmp(app.ChecksTable.Data(:, 1), 'Warning'));
            if nWarn > 0
                UIKit.setStatus(app.StatusLabel, sprintf(['Counted. %d warning(s) in the Checks tab: read them before ' ...
                    'using the numbers.'], nWarn), 'warning');
            else
                UIKit.setStatus(app.StatusLabel, ['Counted. Check the circles on the image and the Checks tab; add ' ...
                    'regions (step 4) for counts per region.'], 'success');
            end
        end

        %% ----------------------------------------------------------------
        %% Step 4: regions
        %% addRegion - Add a region (xy: K x 2 polygon [x y] in image-1 pixels)
        function k = addRegion(app, name, xy)
            if nargin < 2 || isempty(name), name = sprintf('Region %d', numel(app.Regions) + 1); end
            app.Regions(end + 1) = struct('name', char(name), 'xy', xy);
            k = numel(app.Regions);
            app.updateRegionStats();
            app.showImage();
            app.updateControls();
        end

        %% removeRegion - Delete region k
        function removeRegion(app, k)
            if k < 1 || k > numel(app.Regions), return; end
            app.Regions(k) = [];
            app.updateRegionStats();
            app.showImage();
            app.updateControls();
        end

        %% ----------------------------------------------------------------
        %% Display
        %% setView - Image index and view ('Composite', a channel name or ViewThresholded)
        function setView(app, k, mode)
            if ~isempty(k), app.ImageDrop.Value = app.ImageDrop.Items{k}; end
            if nargin >= 3 && ~isempty(mode), app.ViewDrop.Value = mode; end
            app.showImage();
        end

        %% showImage - Draw the current image with the marks
        function showImage(app)
            T = UITheme;
            ax = app.AxImage;
            cla(ax);
            if isempty(app.Images)
                UIKit.emptyAxes(ax, 'Load images (or Try demo data) to begin');
                return;
            end
            k = app.currentImage();
            img = app.Images{k};
            view = app.ViewDrop.Value;
            R = [];
            if k <= numel(app.Results), R = app.Results{k}; end
            if strcmp(view, 'Composite')
                rgb = composite(img);
            elseif strcmp(view, app.ViewThresholded) && ~isempty(R)
                g = stretch(R.corrected);
                rgb = repmat(g, 1, 1, 3);
                above = R.corrected > R.threshold;
                rgb(:, :, 1) = min(1, rgb(:, :, 1) + 0.45 * above);
            else
                c = find(strcmp(app.ChannelNames, view), 1);
                if isempty(c), c = 1; end
                rgb = repmat(stretch(img(:, :, c)), 1, 1, 3);
            end
            h = image(ax, 'CData', rgb);
            h.ButtonDownFcn = @(~, e)app.onImageClick(e);
            ax.YDir = 'reverse';
            axis(ax, 'image');
            ax.XLim = [0.5 size(img, 2) + 0.5]; ax.YLim = [0.5 size(img, 1) + 0.5];
            ax.XTick = []; ax.YTick = [];
            hold(ax, 'on');
            if app.MarksCb.Value
                if ~isempty(R) && R.n > 0
                    r = sqrt(R.areaPx / pi);
                    pos = true(R.n, 1);
                    P = app.Positives{k};
                    for m = 1:numel(P), pos = pos & P{m}.isPositive; end
                    if isempty(P), pos = false(R.n, 1); end
                    th = linspace(0, 2 * pi, 25);
                    xs = R.centroid(:, 1) + r .* cos(th); ys = R.centroid(:, 2) + r .* sin(th);
                    xs(:, end + 1) = NaN; ys(:, end + 1) = NaN;
                    xn = xs(~pos, :)'; yn = ys(~pos, :)';
                    xp = xs(pos, :)'; yp = ys(pos, :)';
                    plot(ax, xn(:), yn(:), '-', 'Color', [0 0.9 1], 'LineWidth', 1, 'HitTest', 'off', 'PickableParts', 'none');
                    plot(ax, xp(:), yp(:), '-', 'Color', [1 0.9 0], 'LineWidth', 1.8, 'HitTest', 'off', 'PickableParts', 'none');
                end
                if ~isempty(R) && any(R.rejected(:))
                    nr = max(R.rejected(:));
                    [yy, xx] = find(R.rejected > 0);
                    lab = R.rejected(R.rejected > 0);
                    cx = accumarray(lab, xx, [nr 1], @mean); cy = accumarray(lab, yy, [nr 1], @mean);
                    plot(ax, cx, cy, 'x', 'Color', [0.75 0.75 0.75], 'MarkerSize', 7, 'LineWidth', 1.2, ...
                        'HitTest', 'off', 'PickableParts', 'none');
                end
                for q = 1:numel(app.Regions)
                    xy = app.Regions(q).xy;
                    col = T.plotColors(mod(q - 1, size(T.plotColors, 1)) + 1, :);
                    plot(ax, xy([1:end 1], 1), xy([1:end 1], 2), '-', 'Color', col, 'LineWidth', 2, ...
                        'HitTest', 'off', 'PickableParts', 'none');
                    text(ax, mean(xy(:, 1)), min(xy(:, 2)) + 8, app.Regions(q).name, 'Color', col, ...
                        'FontWeight', 'bold', 'FontSize', T.fontSmall + 1, 'HorizontalAlignment', 'center', ...
                        'Interpreter', 'none', 'HitTest', 'off', 'PickableParts', 'none', 'Clipping', 'on');
                end
                app.drawLandmarks(k);
                if ~isempty(app.PendingXY) && strcmp(app.ClickMode, 'region')
                    plot(ax, app.PendingXY(:, 1), app.PendingXY(:, 2), 'o-', 'Color', [1 0.4 0.8], ...
                        'LineWidth', 1.5, 'HitTest', 'off', 'PickableParts', 'none');
                end
            end
            hold(ax, 'off');
            ttl = sprintf('%s  ·  %s', app.ImageNames{k}, view);
            if ~isempty(R), ttl = sprintf('%s  ·  %d cells', ttl, R.n); end
            title(ax, ttl, 'Interpreter', 'none', 'FontWeight', 'bold', 'Color', T.sectionTitleColor, ...
                'FontSize', T.fontSmall + 1);
        end

        %% ----------------------------------------------------------------
        %% Export
        %% exportDialog - Choose .csv or .mat
        function exportDialog(app)
            start = ProjectManager.getExportDir();
            if isempty(start), start = pwd; end
            [f, p] = uiputfile({'*.csv', 'CSV (cells + counts)'; '*.mat', 'MAT (everything)'}, ...
                'Export results', fullfile(start, 'histology_cells.csv'));
            figure(app.UIFig);
            if isequal(f, 0), return; end
            app.exportResultsTo(fullfile(p, f));
        end

        %% exportResultsTo - Write the results (no dialog); .csv or .mat by extension
        % .csv: one row per cell; next to it <name>_counts.csv (per image and region).
        function ok = exportResultsTo(app, filePath)
            ok = false;
            if isempty(app.Results)
                UIKit.setStatus(app.StatusLabel, 'Count cells first (step 3).', 'warning');
                return;
            end
            [folder, name, ext] = fileparts(filePath);
            try
                if strcmpi(ext, '.mat')
                    results = app.resultsStruct(); %#ok<NASGU>
                    save(filePath, 'results');
                    written = [name ext];
                else
                    writeCsv(filePath, app.cellsHeader(), app.cellsRows());
                    countsPath = fullfile(folder, [name '_counts.csv']);
                    writeCsv(countsPath, app.countsHeader(), app.countsRows());
                    written = sprintf('%s%s and %s_counts.csv', name, ext, name);
                end
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Export failed: %s', ME.message), 'error');
                return;
            end
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf('Exported %s', written), 'success');
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

        %% sessionState - Inputs, settings (alignment, landmarks, count, regions) and results
        function st = sessionState(app)
            st.inputs = [];
            st.settings = struct();
            st.results = struct();
            st.summary = {};
            if isempty(app.Raw), return; end
            if strcmp(app.Generator, 'demoHistology')
                st.inputs = Session.fileInfo('', 'Histology demo (demoHistology)');
            else
                for k = 1:numel(app.Files)
                    info = Session.fileInfo(app.Files{k}, sprintf('Image file %d', k));
                    if isempty(st.inputs), st.inputs = info; else, st.inputs(end + 1) = info; end
                end
            end
            st.settings.generator = app.Generator;
            st.settings.pixelSizeUm = app.PixelSizeEdit.Value;
            st.settings.pixelSizeFromFile = app.PixelSizeFromFile;
            st.settings.channelNames = app.ChannelNames;
            st.settings.imageNames = app.ImageNames;
            st.settings.alignChannels = logical(app.AlignChannelsCb.Value);
            st.settings.alignMethod = methodKey(app.AlignMethodDrop.Value);
            st.settings.alignChannel = find(strcmp(app.AlignChannelDrop.Items, app.AlignChannelDrop.Value), 1);
            st.settings.alignedMethod = app.AlignedMethod;
            st.settings.channelsAligned = ~isempty(app.ChannelShifts);
            st.settings.landmarks = app.Landmarks;
            st.settings.count = app.currentSettings();
            st.settings.regions = app.Regions;
            [H, W, C] = size(app.Raw{1});
            st.summary{end + 1} = sprintf('%d image(s), %d x %d px, %d channel(s) (%s); pixel size %.4g um (%s)', ...
                numel(app.Raw), W, H, C, strjoin(app.ChannelNames, ', '), app.PixelSizeEdit.Value, ...
                ifelse(app.PixelSizeFromFile, 'from the file', 'typed'));
            if ~strcmp(app.AlignedMethod, 'none') || ~isempty(app.ChannelShifts)
                st.results.shifts = app.Shifts;
                st.results.landmarkRms = app.LandmarkRms;
                st.results.channelShifts = app.ChannelShifts;
                st.summary{end + 1} = app.alignSummary();
            end
            if isempty(app.Results), return; end
            st.results.counts = app.countsRows();
            st.results.countsHeader = app.countsHeader();
            o = app.CountSettings;
            st.summary{end + 1} = sprintf(['Count in %s: background radius %g um, threshold %s, split touching %s, ' ...
                'size %g-%g um2, elongation <= %g; positive when >= %g%% of the cell is above the marker threshold (%s)'], ...
                app.ChannelNames{o.channel}, o.backgroundRadiusUm, ifelse(o.threshold > 0, sprintf('%g', o.threshold), 'automatic'), ...
                ifelse(o.split, 'on', 'off'), o.minAreaUm2, o.maxAreaUm2, o.maxElongation, o.minFractionPct, ...
                ifelse(o.markerThreshold > 0, sprintf('%g', o.markerThreshold), 'automatic'));
            rows = app.countsRows();
            hdr = app.countsHeader();
            for r = 1:size(rows, 1)
                parts = {sprintf('%s, %s: %d cells, %.1f per mm2', rows{r, 1}, rows{r, 2}, rows{r, 3}, rows{r, 5})};
                for c = 6:numel(hdr)
                    if startsWith(hdr{c}, 'Positive') || startsWith(hdr{c}, 'All')
                        parts{end + 1} = sprintf('%s %d', hdr{c}, rows{r, c}); %#ok<AGROW>
                    end
                end
                st.summary{end + 1} = ['  ' strjoin(parts, '; ')];
            end
        end

        %% restoreSession - Reload images, re-apply settings, re-align, re-count
        function ok = restoreSession(app, s)
            ok = false;
            cfg = s.settings;
            if isfield(cfg, 'generator') && strcmp(cfg.generator, 'demoHistology')
                if ~app.loadDemo(), return; end
            elseif isempty(s.inputs)
                ok = true; return;
            elseif ~app.openFiles({s.inputs.path})
                return;
            end
            % A pixel size from the file is read again; only a typed one is re-typed
            if ~cfg.pixelSizeFromFile, app.setPixelSize(cfg.pixelSizeUm); end
            app.Landmarks = cfg.landmarks;
            % Re-apply the alignment that was applied (the controls may show a newer choice)
            if ~strcmp(cfg.alignedMethod, 'none') || cfg.channelsAligned
                app.setAlignment(cfg.alignedMethod, cfg.alignChannel, cfg.channelsAligned);
                if ~app.align(), return; end
            end
            app.setAlignment(cfg.alignMethod, cfg.alignChannel, cfg.alignChannels);
            app.setCountOptions(cfg.count);
            app.Regions = cfg.regions;
            if isfield(s.results, 'counts')
                if ~app.countCells(), return; end
            end
            app.updateRegionStats();
            app.showImage();
            app.updateControls();
            ok = true;
        end
    end

    methods(Static)
        %% defaultSettings - Count and marker settings (um units)
        function o = defaultSettings()
            o = struct('channel', 1, 'backgroundRadiusUm', 15, 'threshold', 0, 'split', true, ...
                'minAreaUm2', 20, 'maxAreaUm2', 2000, 'maxElongation', 2.5, 'minFractionPct', 50, ...
                'markerThreshold', 0, 'pixelSizeUm', 1);
        end
    end

    methods(Access = private)

        %% setData - New images: reset alignment, results, regions; fill controls
        function setData(app, raw, names, chNames, px, truth)
            app.Raw = raw;
            app.Images = raw;
            app.ImageNames = names;
            app.ChannelNames = chNames;
            app.DemoTruth = truth;
            app.Landmarks = cell(1, numel(raw));
            app.LandmarkRms = nan(1, numel(raw));
            app.Shifts = zeros(numel(raw), 2); app.Peaks = ones(1, numel(raw));
            app.ChannelShifts = [];
            app.AlignedMethod = 'none';
            app.Regions = app.Regions([]);
            app.ClickMode = ''; app.PendingXY = zeros(0, 2);
            app.clearResults();
            app.PixelSizeFromFile = ~isempty(px);
            if isempty(px)
                app.PixelSizeNote.Text = 'Not in the file: type the pixel size of your microscope.';
                app.PixelSizeNote.FontColor = UITheme.warning;
            else
                app.PixelSizeEdit.Value = px;
                app.PixelSizeNote.Text = 'Read from the file.';
                app.PixelSizeNote.FontColor = UITheme.success;
            end
            app.ImageDrop.Items = names; app.ImageDrop.Value = names{1};
            app.ViewDrop.Items = [{'Composite'}, chNames, {app.ViewThresholded}];
            app.ViewDrop.Value = 'Composite';
            app.CountChannelDrop.Items = chNames; app.CountChannelDrop.Value = chNames{1};
            app.AlignChannelDrop.Items = chNames; app.AlignChannelDrop.Value = chNames{1};
            [H, W, C] = size(raw{1});
            app.FileInfo.Text = sprintf('%d image(s)  ·  %d channel(s): %s  ·  %d x %d px', numel(raw), C, ...
                strjoin(chNames, ', '), W, H);
            app.FileInfo.FontColor = UITheme.sectionTitleColor;
            app.AlignInfo.Text = 'Not aligned';
            app.RegionInfo.Text = 'No regions: counts are for the whole image';
            app.CountInfo.Text = 'Not counted yet';
            app.showImage();
            app.updateControls();
            next = 'count cells (step 3)';
            if numel(raw) > 1, next = 'align the images (step 2) or count cells (step 3)'; end
            if isempty(px)
                UIKit.setStatus(app.StatusLabel, sprintf(['Loaded %d image(s). The file does not give the pixel size: ' ...
                    'type it in step 1, then %s.'], numel(raw), next), 'warning');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Loaded %d image(s). Next: %s.', numel(raw), next), 'success');
            end
        end

        %% clearResults - Forget the counts (after new data, alignment or pixel size)
        function clearResults(app)
            app.Results = {}; app.Positives = {}; app.RegionStats = {};
            app.CountSettings = [];
            if ~isempty(app.CountsTable) && isvalid(app.CountsTable)
                app.CountsTable.Data = {}; app.CellsTable.Data = {}; app.ChecksTable.Data = cell(0, 3);
                app.ChecksText.Value = {'Count cells (step 3) to see the checks.'};
            end
            if ~isempty(app.CountInfo) && isvalid(app.CountInfo), app.CountInfo.Text = 'Not counted yet'; end
        end

        %% onPixelSize - Typed pixel size: results in um must be recomputed
        function onPixelSize(app)
            if ~isempty(app.Raw)
                app.PixelSizeFromFile = false;
                app.PixelSizeNote.Text = 'Typed by you.';
                app.PixelSizeNote.FontColor = UITheme.bodyColor;
            end
            if ~isempty(app.Results)
                app.clearResults();
                app.showImage();
                UIKit.setStatus(app.StatusLabel, 'Pixel size changed: count again (step 3) so sizes and densities use it.', 'info');
            end
            app.updateControls();
        end

        %% updateRegionStats - Counts per region, tables and checks
        function updateRegionStats(app)
            n = numel(app.Regions);
            if n == 0
                app.RegionInfo.Text = 'No regions: counts are for the whole image';
            else
                app.RegionInfo.Text = sprintf('%d region(s): %s', n, strjoin({app.Regions.name}, ', '));
            end
            if isempty(app.Results), return; end
            px = app.CountSettings.pixelSizeUm;
            for k = 1:numel(app.Results)
                app.RegionStats{k} = Histology.regionCounts(app.Results{k}, app.Positives{k}, app.Regions, px, ...
                    size(app.Images{k}));
            end
            app.CountsTable.ColumnName = app.countsHeader();
            app.CountsTable.Data = app.countsRows();
            app.CellsTable.ColumnName = app.cellsHeader();
            app.CellsTable.Data = app.cellsRows();
            app.fillChecks();
        end

        %% fillChecks - Checks tab from Histology.checks
        function fillChecks(app)
            T = UITheme;
            ctx = struct('pixelSizeUm', app.CountSettings.pixelSizeUm, 'pixelSizeFromFile', app.PixelSizeFromFile, ...
                'nImages', numel(app.Images), 'alignMethod', app.AlignedMethod, 'shifts', app.Shifts, ...
                'peak', app.Peaks, 'landmarkRms', app.LandmarkRms, 'channelShifts', [], ...
                'hasRegions', ~isempty(app.Regions));
            if ~isempty(app.ChannelShifts), ctx.channelShifts = app.ChannelShifts{1}; end
            C = Histology.checks(app.Results, app.Positives, ctx);
            label = struct('ok', 'OK', 'check', 'Check', 'warning', 'Warning');
            res = cellfun(@(s) label.(s), C(:, 1), 'UniformOutput', false);
            app.ChecksTable.Data = [res, C(:, 2), C(:, 3)];
            removeStyle(app.ChecksTable);
            colors = struct('ok', T.success, 'check', T.warning, 'warning', T.danger);
            for f = fieldnames(colors)'
                rows = find(strcmp(C(:, 1), f{1}));
                if ~isempty(rows)
                    addStyle(app.ChecksTable, uistyle('FontColor', colors.(f{1})), 'cell', [rows(:), ones(numel(rows), 1)]);
                end
            end
            app.ChecksText.Value = {sprintf('%d OK, %d to check, %d warning(s). Click a row to read it in full.', ...
                nnz(strcmp(C(:, 1), 'ok')), nnz(strcmp(C(:, 1), 'check')), nnz(strcmp(C(:, 1), 'warning')))};
        end

        %% showCheck - Full text of the selected check
        function showCheck(app, e)
            if isempty(e.Indices) || isempty(app.ChecksTable.Data), return; end
            r = e.Indices(1, 1);
            app.ChecksText.Value = {sprintf('%s: %s', app.ChecksTable.Data{r, 2}, app.ChecksTable.Data{r, 3})};
        end

        %% countsHeader / countsRows - One row per image and region
        function h = countsHeader(app)
            h = {'Image', 'Region', 'Cells', 'Area (mm2)', 'Cells per mm2'};
            for m = app.markerChannels()
                h = [h, {sprintf('Positive %s', app.ChannelNames{m}), sprintf('%% %s', app.ChannelNames{m})}]; %#ok<AGROW>
            end
            if numel(app.markerChannels()) > 1, h{end + 1} = 'All markers positive'; end
        end

        function rows = countsRows(app)
            rows = cell(0, numel(app.countsHeader()));
            nm = numel(app.markerChannels());
            for k = 1:numel(app.RegionStats)
                for s = app.RegionStats{k}
                    row = {app.ImageNames{k}, s.name, s.nCells, round(s.areaMm2, 5), round(s.perMm2, 1)};
                    for m = 1:nm
                        row = [row, {s.nPositive(m), round(s.percentPositive(m), 1)}]; %#ok<AGROW>
                    end
                    if nm > 1, row{end + 1} = s.nAllPositive; end %#ok<AGROW>
                    rows(end + 1, :) = row; %#ok<AGROW>
                end
            end
        end

        %% cellsHeader / cellsRows - One row per counted cell
        function h = cellsHeader(app)
            h = {'Image', 'Cell', 'x (um)', 'y (um)', 'Area (um2)', 'Elongation', 'Region'};
            for m = app.markerChannels()
                h = [h, {sprintf('%s positive', app.ChannelNames{m}), sprintf('%s part of cell (%%)', app.ChannelNames{m})}]; %#ok<AGROW>
            end
        end

        function rows = cellsRows(app)
            px = app.CountSettings.pixelSizeUm;
            rows = cell(0, numel(app.cellsHeader()));
            for k = 1:numel(app.Results)
                R = app.Results{k};
                S = app.RegionStats{k};
                P = app.Positives{k};
                for i = 1:R.n
                    reg = '';
                    for s = S
                        if s.inRegion(i), reg = s.name; break; end
                    end
                    row = {app.ImageNames{k}, i, round(R.centroid(i, 1) * px, 2), round(R.centroid(i, 2) * px, 2), ...
                        round(R.areaPx(i) * px^2, 1), round(R.elongation(i), 2), reg};
                    for m = 1:numel(P)
                        row = [row, {ifelse(P{m}.isPositive(i), 'yes', 'no'), round(100 * P{m}.fraction(i))}]; %#ok<AGROW>
                    end
                    rows(end + 1, :) = row; %#ok<AGROW>
                end
            end
        end

        %% resultsStruct - Everything for the .mat export
        function r = resultsStruct(app)
            r.imageNames = app.ImageNames;
            r.channelNames = app.ChannelNames;
            r.pixelSizeUm = app.CountSettings.pixelSizeUm;
            r.settings = app.CountSettings;
            r.regions = app.Regions;
            r.alignMethod = app.AlignedMethod;
            r.shifts = app.Shifts;
            r.landmarks = app.Landmarks;
            r.landmarkRms = app.LandmarkRms;
            r.channelShifts = app.ChannelShifts;
            r.countsHeader = app.countsHeader();
            r.counts = app.countsRows();
            r.cellsHeader = app.cellsHeader();
            r.cells = app.cellsRows();
            r.labels = cellfun(@(x) uint32(x.L), app.Results, 'UniformOutput', false);
            r.count = cellfun(@(x) rmfield(x, {'L', 'rejected', 'corrected'}), app.Results, 'UniformOutput', false);
            r.markers = app.Positives;
        end

        %% markerChannels - Channels other than the counting channel
        function m = markerChannels(app)
            if isempty(app.Images), m = []; return; end
            c = 1;
            if ~isempty(app.CountSettings), c = app.CountSettings.channel; end
            m = setdiff(1:size(app.Images{1}, 3), c);
        end

        %% alignSummary - One line on what the alignment did
        function s = alignSummary(app)
            parts = {};
            if ~isempty(app.ChannelShifts)
                sh = app.ChannelShifts{1};
                parts{end + 1} = sprintf('channels shifted by up to %.1f px', max(hypot(sh(:, 1), sh(:, 2))));
            end
            switch app.AlignedMethod
                case 'shift'
                    parts{end + 1} = sprintf('images shifted by up to %.1f px', max(hypot(app.Shifts(:, 1), app.Shifts(:, 2))));
                case 'landmarks'
                    e = app.LandmarkRms(isfinite(app.LandmarkRms));
                    if isempty(e)
                        parts{end + 1} = 'no landmarks set';
                    else
                        parts{end + 1} = sprintf('landmarks fit to %.1f px (worst image)', max(e));
                    end
            end
            if isempty(parts), s = 'Not aligned'; else, s = ['Aligned: ' strjoin(parts, '; ')]; end
        end

        %% ----------------------------------------------------------------
        %% Clicks on the image: region corners and landmarks
        function startRegion(app)
            if isempty(app.Images), return; end
            app.ClickMode = 'region';
            app.PendingXY = zeros(0, 2);
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, 'Click the corners of the region on the image, then Finish (step 4).', 'info');
        end

        function startLandmarks(app)
            if numel(app.Images) < 2, return; end
            k = app.currentImage();
            if k == 1, k = 2; end
            app.LandmarkImage = k;
            app.Landmarks{k} = struct('moving', zeros(0, 2), 'fixed', zeros(0, 2));
            app.ClickMode = 'landmarkFixed';
            app.ViewDrop.Value = 'Composite';
            app.showRaw(1);
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf(['Landmark 1: click a clear feature in image 1 (%s). Then click the ' ...
                'same feature in image %d. Repeat 3 or more times, spread over the image; then Finish.'], ...
                app.ImageNames{1}, k), 'info');
        end

        function clearLandmarks(app)
            k = app.currentImage();
            if k <= numel(app.Landmarks), app.Landmarks{k} = []; end
            app.showImage();
            app.updateControls();
        end

        %% onImageClick - Add a region corner or a landmark
        function onImageClick(app, e)
            if isempty(app.ClickMode), return; end
            xy = e.IntersectionPoint(1:2);
            k = app.LandmarkImage;
            switch app.ClickMode
                case 'region'
                    app.PendingXY(end + 1, :) = xy;
                    app.showImage();
                case 'landmarkFixed'
                    app.Landmarks{k}.fixed(end + 1, :) = xy;
                    app.ClickMode = 'landmarkMoving';
                    app.showRaw(k);
                    UIKit.setStatus(app.StatusLabel, sprintf('Now click the same feature in image %d (%s).', ...
                        k, app.ImageNames{k}), 'info');
                case 'landmarkMoving'
                    app.Landmarks{k}.moving(end + 1, :) = xy;
                    n = size(app.Landmarks{k}.moving, 1);
                    app.ClickMode = 'landmarkFixed';
                    app.showRaw(1);
                    UIKit.setStatus(app.StatusLabel, sprintf(['%d landmark pair(s). Click the next feature in image 1, ' ...
                        'or Finish (at least 3 pairs).'], n), 'info');
            end
            app.updateControls();
        end

        %% finishClicks - Close the region, or end landmark picking
        function finishClicks(app)
            switch app.ClickMode
                case 'region'
                    if size(app.PendingXY, 1) >= 3
                        xy = app.PendingXY;
                        app.ClickMode = ''; app.PendingXY = zeros(0, 2);
                        k = app.addRegion('', xy);
                        UIKit.setStatus(app.StatusLabel, sprintf('%s added.', app.Regions(k).name), 'success');
                    else
                        UIKit.setStatus(app.StatusLabel, 'A region needs at least 3 corners.', 'warning');
                        return;
                    end
                case {'landmarkFixed', 'landmarkMoving'}
                    k = app.LandmarkImage;
                    lm = app.Landmarks{k};
                    n = min(size(lm.fixed, 1), size(lm.moving, 1));
                    app.Landmarks{k} = struct('moving', lm.moving(1:n, :), 'fixed', lm.fixed(1:n, :));
                    app.ClickMode = '';
                    app.showImage();
                    if n < 3
                        UIKit.setStatus(app.StatusLabel, sprintf('Only %d landmark pair(s): at least 3 are needed.', n), 'warning');
                    else
                        UIKit.setStatus(app.StatusLabel, sprintf('%d landmark pairs for image %d. Click Align.', n, k), 'success');
                    end
            end
            app.updateControls();
        end

        %% showRaw - Show image k before alignment (landmarks are clicked there)
        function showRaw(app, k)
            app.ImageDrop.Value = app.ImageDrop.Items{k};
            saved = app.Images;
            app.Images = app.Raw;
            app.showImage();
            app.Images = saved;
        end

        %% drawLandmarks - Numbered landmark points of the image shown
        function drawLandmarks(app, k)
            ax = app.AxImage;
            if isempty(app.ClickMode) || ~startsWith(app.ClickMode, 'landmark'), return; end
            lm = app.Landmarks{app.LandmarkImage};
            if isempty(lm), return; end
            if k == 1, pts = lm.fixed; else, pts = lm.moving; end
            for i = 1:size(pts, 1)
                plot(ax, pts(i, 1), pts(i, 2), '+', 'Color', [1 0.3 0.3], 'MarkerSize', 12, 'LineWidth', 2, ...
                    'HitTest', 'off', 'PickableParts', 'none');
                text(ax, pts(i, 1) + 4, pts(i, 2) - 4, sprintf('%d', i), 'Color', [1 0.3 0.3], 'FontWeight', 'bold', ...
                    'HitTest', 'off', 'PickableParts', 'none');
            end
        end

        %% currentImage - Index of the image shown
        function k = currentImage(app)
            k = find(strcmp(app.ImageDrop.Items, app.ImageDrop.Value), 1);
            if isempty(k), k = 1; end
        end

        %% selectTab - Show a result tab by title
        function selectTab(app, titleText)
            tab = findobj(app.Tabs, 'Type', 'uitab', 'Title', titleText);
            if ~isempty(tab), app.Tabs.SelectedTab = tab(1); end
        end

        %% updateControls - Enable states from the data; next step is primary
        function updateControls(app)
            has = ~isempty(app.Raw);
            multi = numel(app.Raw) > 1;
            counted = ~isempty(app.Results);
            method = methodKey(app.AlignMethodDrop.Value);
            clicking = ~isempty(app.ClickMode);
            app.AlignChannelsCb.Enable = onoff(has && size(app.Raw{max(1, end)}, 3) > 1);
            app.AlignMethodDrop.Enable = onoff(multi);
            app.AlignChannelDrop.Enable = onoff(multi && ~strcmp(method, 'landmarks'));
            app.PickLandmarksBtn.Enable = onoff(multi && strcmp(method, 'landmarks') && ~clicking);
            app.ClearLandmarksBtn.Enable = onoff(multi && strcmp(method, 'landmarks'));
            app.AlignBtn.Enable = onoff(has && ~clicking);
            app.CountBtn.Enable = onoff(has && ~clicking);
            app.AddRegionBtn.Enable = onoff(has && ~clicking);
            app.FinishRegionBtn.Enable = onoff(clicking);
            app.RemoveRegionBtn.Enable = onoff(~isempty(app.Regions) && ~clicking);
            app.ExportBtn.Enable = onoff(counted);
            app.ImageDrop.Enable = onoff(has);
            app.ViewDrop.Enable = onoff(has);
            UIKit.setSessionEnable(app.SessionBtns, has);
            setButtonStyle(app.LoadBtn, ifelse(~has, 'primary', 'secondary'));
            setButtonStyle(app.CountBtn, ifelse(has && ~counted, 'primary', 'secondary'));
            setButtonStyle(app.FinishRegionBtn, ifelse(clicking, 'primary', 'secondary'));
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% stepCard - Card with a numbered step title and a 2-column grid
function [p, g, h] = stepCard(parent, n, text, rowHeights)
    T = UITheme;
    p = UIKit.card(parent, '');
    rh = [{22}, rowHeights];
    g = uigridlayout(p, [numel(rh) 2], 'RowHeight', rh, 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [10 8 10 10], 'RowSpacing', 6, 'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
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

%% infoLabel - Small wrapped muted label
function lbl = infoLabel(parent, text, tooltip)
    T = UITheme;
    lbl = uilabel(parent, 'Text', text, 'FontSize', T.fontSmall, 'FontColor', T.bodyColor, ...
        'WordWrap', 'on', 'VerticalAlignment', 'top', 'Tooltip', tooltip, 'Interpreter', 'none');
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

%% methodKey / methodIndex - Alignment method: dropdown text <-> 'none' | 'shift' | 'landmarks'
function k = methodKey(label)
    keys = {'none', 'shift', 'landmarks'};
    k = keys{methodIndex(label)};
end

function i = methodIndex(m)
    m = lower(char(m));
    if startsWith(m, 'shift'), i = 2;
    elseif startsWith(m, 'landmark'), i = 3;
    else, i = 1;
    end
end

%% stretch - Scale to 0-1 between the 0.5th and 99.5th percentile
function g = stretch(v)
    v = double(v);
    s = sort(v(isfinite(v)));
    if isempty(s), g = zeros(size(v)); return; end
    lo = s(max(1, round(0.005 * numel(s)))); hi = s(max(1, round(0.995 * numel(s))));
    if hi <= lo, hi = lo + 1; end
    g = min(1, max(0, (v - lo) / (hi - lo)));
end

%% composite - Channel 1 blue, 2 green, 3 red, further channels magenta
function rgb = composite(img)
    C = size(img, 3);
    if C == 1, rgb = repmat(stretch(img), 1, 1, 3); return; end
    colors = [0 0.35 1; 0 1 0; 1 0 0; 1 0 1];
    rgb = zeros(size(img, 1), size(img, 2), 3);
    for c = 1:C
        col = colors(min(c, size(colors, 1)), :);
        g = stretch(img(:, :, c));
        for q = 1:3, rgb(:, :, q) = rgb(:, :, q) + col(q) * g; end
    end
    rgb = min(1, rgb);
end

%% writeCsv - Header + rows (cell) as CSV, text quoted
function writeCsv(p, header, rows)
    fid = fopen(p, 'w');
    if fid < 0, error('NeuroAnalyzer:Histology:write', 'Cannot write %s', p); end
    c = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', strjoin(cellfun(@(h) ['"' strrep(h, '"', '""') '"'], header, 'UniformOutput', false), ','));
    for r = 1:size(rows, 1)
        parts = cell(1, size(rows, 2));
        for c2 = 1:size(rows, 2)
            v = rows{r, c2};
            if ischar(v), parts{c2} = ['"' strrep(v, '"', '""') '"'];
            elseif isempty(v), parts{c2} = '';
            else, parts{c2} = sprintf('%.10g', v);
            end
        end
        fprintf(fid, '%s\n', strjoin(parts, ','));
    end
end

%% onoff - 'on'/'off' from a logical
function s = onoff(cond)
    if cond, s = 'on'; else, s = 'off'; end
end

%% ifelse - One of two values
function s = ifelse(cond, a, b)
    if cond, s = a; else, s = b; end
end
