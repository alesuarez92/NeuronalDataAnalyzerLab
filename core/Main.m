%% Main.m
% =========================================================================
% NEURONAL DATA ANALYZER - MAIN LAUNCHER
% =========================================================================
% Entry point for the Neuronal Data Analyzer Lab application. On first run (or
% when no project dirs are set), prompts for Import/Export directories.
%
% Layout (top to bottom):
%   cover    logo, title, subtitle, the cover art (core/icons/cover.png,
%            cut to the free width whenever the window is resized) and
%            ? Help
%   folders  Import / Export folder and Set folders
%   body     (scrolls when the window is small)
%            LEARN: Course and Virtual lab (Coming soon, disabled), Try with demo data (choose a
%            window, it opens with synthetic data whose answers are known)
%            and Help, two per row
%            ANALYSES: one tile per technique, grouped by family: Blood
%            flow, Electrophysiology, EEG, Imaging, Across techniques. A
%            tile has a description, its steps as numbered buttons in order
%            (tooltips say which file goes in and out), the files in and out
%            and a ? that opens its Help topic.
%   status   toolbox availability and the last action;  footer
%
% Families, tiles and the Learn area come from Techniques.m, so a new
% technique is one new row there. The tiles wrap with the window width:
% 3 columns from about 1000 px, 2 from about 660 px, else 1 (Main.pack
% keeps each family together when it fits a row).
% =========================================================================

classdef Main < handle
    properties
        UIFig
        HeaderPanel
        HelpBtn            % ? Help in the cover (Welcome topic)
        CoverImage         % Cover art, cut to the width of its column (updateCover)
        ProjectPanel
        ImportLabel
        ExportLabel
        BodyGrid           % Scrolling body: Learn heading, Learn tiles, Analyses heading, tiles
        LearnGrid          % Learn tiles
        LearnTiles         % Panels of the Learn tiles (Techniques.learn order)
        LearnButtons       % struct with one button per Learn item id (course, lab, demo, help)
        DemoDrop           % Window that "Try with demo data" opens
        TileGrid           % Family headings and analysis tiles
        Tiles              % One per Techniques.list() row: id, family, panel, steps (buttons), help (? button)
        StatusLabel        % Status bar (toolbox availability, last action)
        Columns = 0        % Tile columns of the current layout
        LastOpened         % Last window opened from the launcher ([] if none or it failed)
        % Environment checks (set by checkSignalToolbox / checkTDTSDK)
        HasSignalToolbox = true
        HasTDTSDK = false
    end

    properties (Access = private)
        CoverArt           % Full cover image (rows x cols x 3 uint8)
        CoverWidth = 0     % Width the cover art was last cut to (px)
        Headings = {}      % Family heading grids of the current layout
    end

    properties (Constant)
        DefaultSize = [1120 1000]
        CoverHeight = 116
        TitleWidth = 430
        TileMinWidth = 300
        TileHeight = 144
        HeadingHeight = 32
        LearnHeight = 78
        Gap = 12
    end

    methods
        function app = Main()
            app.buildUI();
            app.checkSignalToolbox();
            app.checkTDTSDK();
            app.showEnvironmentStatus();
            % Prompt for project directories if not set (optional: only when no dirs)
            if ~ProjectManager.hasProject()
                ProjectManager.promptForProjectDirs();
                app.updateProjectLabels();
            end
        end

        function buildUI(app)
            T = UITheme;
            app.UIFig = uifigure('Name', 'Neuronal Data Analyzer Lab', ...
                'Position', UIKit.centeredPosition(Main.DefaultSize), 'Resize', 'on', ...
                'Color', T.bgGray, 'AutoResizeChildren', 'off');
            UIKit.setAppIcon(app.UIFig);

            % === MAIN GRID: Cover | Project bar | Body | Status | Footer ===
            mainGrid = uigridlayout(app.UIFig, [5, 1], ...
                'RowHeight', {Main.CoverHeight, 48, '1x', T.statusHeight, T.footerHeight}, ...
                'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0, ...
                'BackgroundColor', T.bgGray);
            app.buildCover(mainGrid);
            app.buildProjectBar(mainGrid);
            app.buildBody(mainGrid);
            app.StatusLabel = UIKit.statusBar(mainGrid);
            UIKit.footer(mainGrid);

            app.updateProjectLabels();
            app.UIFig.SizeChangedFcn = @(~, ~) app.onResize();
            app.onResize();
        end

        %% buildCover - Navy band: logo | title and subtitle | cover art | ? Help
        function buildCover(app, parent)
            T = UITheme;
            app.HeaderPanel = uipanel(parent, 'BackgroundColor', T.headerBg, 'BorderType', 'none');
            g = uigridlayout(app.HeaderPanel, [2 4], ...
                'ColumnWidth', {44, Main.TitleWidth, '1x', 96}, 'RowHeight', {'1x', '1x'}, ...
                'Padding', [T.headerPaddingH 0 16 0], 'RowSpacing', 4, 'ColumnSpacing', 12, ...
                'BackgroundColor', T.headerBg);
            icons = fullfile(fileparts(mfilename('fullpath')), 'icons');
            logo = fullfile(icons, 'logo_header.png');
            if exist(logo, 'file') == 2
                try
                    im = uiimage(g, 'ImageSource', logo, 'ScaleMethod', 'fit', 'Tooltip', 'Neuronal Data Analyzer Lab');
                    im.Layout.Row = [1 2]; im.Layout.Column = 1;
                catch
                end
            end
            t = uilabel(g, 'Text', 'Neuronal Data Analyzer Lab', 'FontSize', T.fontTitle + 2, ...
                'FontWeight', 'bold', 'FontColor', T.headerTitleColor, 'VerticalAlignment', 'bottom');
            t.Layout.Row = 1; t.Layout.Column = 2;
            s = uilabel(g, 'Text', 'Analysis of blood flow, electrophysiology, EEG and imaging, step by step', ...
                'FontSize', T.fontSubtitle, 'FontColor', T.headerSubtitleColor, 'VerticalAlignment', 'top');
            s.Layout.Row = 2; s.Layout.Column = 2;
            art = fullfile(icons, 'cover.png');
            if exist(art, 'file') == 2
                try
                    app.CoverArt = imread(art);
                    app.CoverImage = uiimage(g, 'ScaleMethod', 'fill');
                    app.CoverImage.Layout.Row = [1 2]; app.CoverImage.Layout.Column = 3;
                catch
                    app.CoverArt = [];
                    app.CoverImage = [];
                end
            end
            hg = uigridlayout(g, [3 1], 'RowHeight', {'1x', T.buttonHeight, '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 0, 'BackgroundColor', T.headerBg);
            hg.Layout.Row = [1 2]; hg.Layout.Column = 4;
            uilabel(hg, 'Text', '');
            app.HelpBtn = UIKit.button(hg, '? Help', @(~,~)app.openHelp('Welcome'), 'header', ...
                'Overview of the analyses, project folders and where to get help');
            app.HelpBtn.Layout.Row = 2;
        end

        %% buildProjectBar - Import / Export folders and Set folders
        function buildProjectBar(app, parent)
            T = UITheme;
            app.ProjectPanel = uipanel(parent, 'BackgroundColor', T.projectBarBg, ...
                'BorderType', 'line', 'HighlightColor', T.projectBarBorder);
            projGrid = uigridlayout(app.ProjectPanel, [1, 5], ...
                'ColumnWidth', {'fit', '1x', 'fit', '1x', 120}, 'RowHeight', {T.buttonHeight - 4}, ...
                'Padding', [16 8 16 8], 'ColumnSpacing', 8, 'BackgroundColor', T.projectBarBg);
            uilabel(projGrid, 'Text', 'Import folder:', 'FontWeight', 'bold', ...
                'FontSize', T.fontSmall, 'FontColor', T.sectionTitleColor, ...
                'Tooltip', 'Where file dialogs open when you load data');
            app.ImportLabel = uilabel(projGrid, 'Text', '(not set)', 'FontSize', T.fontSmall, ...
                'FontColor', T.bodyColor, 'Interpreter', 'none');
            uilabel(projGrid, 'Text', 'Export folder:', 'FontWeight', 'bold', ...
                'FontSize', T.fontSmall, 'FontColor', T.sectionTitleColor, ...
                'Tooltip', 'Default folder for exported results');
            app.ExportLabel = uilabel(projGrid, 'Text', '(not set)', 'FontSize', T.fontSmall, ...
                'FontColor', T.bodyColor, 'Interpreter', 'none');
            UIKit.button(projGrid, 'Set folders', @(~,~)app.onSetDirectories(), 'secondary', ...
                'Choose the Import (data) and Export (results) folders; remembered between sessions');
        end

        %% buildBody - Scrolling body: LEARN (tiles) and ANALYSES (family tiles)
        function buildBody(app, parent)
            T = UITheme;
            body = uipanel(parent, 'BackgroundColor', T.bgGray, 'BorderType', 'none');
            app.BodyGrid = uigridlayout(body, [4 1], 'RowHeight', {30, Main.LearnHeight, 30, 100}, ...
                'ColumnWidth', {'1x'}, 'Padding', [16 8 16 12], 'RowSpacing', 6, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            sectionHeading(app.BodyGrid, 'LEARN', ...
                'New here? Practise on simulated data with known answers before your own.');
            % Grids start with a cell for every tile; layoutTiles sets the real rows and columns
            nLearn = numel(Techniques.learn());
            app.LearnGrid = uigridlayout(app.BodyGrid, [nLearn 1], 'ColumnWidth', {'1x'}, ...
                'RowHeight', repmat({Main.LearnHeight}, 1, nLearn), 'Padding', [0 0 0 0], 'ColumnSpacing', Main.Gap, ...
                'RowSpacing', 10, 'BackgroundColor', T.bgGray);
            app.buildLearn();
            sectionHeading(app.BodyGrid, 'ANALYSES', ['Pick the tile for your data and click its ' ...
                'steps in order: each step saves a file that the next one opens. ? explains the tile.']);
            L = Techniques.list();
            app.TileGrid = uigridlayout(app.BodyGrid, [2 * numel(L), 1], 'Padding', [0 0 0 0], ...
                'ColumnSpacing', Main.Gap, 'RowSpacing', 0, 'BackgroundColor', T.bgGray);
            F = Techniques.families();
            app.Tiles = struct('id', {}, 'family', {}, 'panel', {}, 'steps', {}, 'help', {});
            for i = 1:numel(L)
                app.Tiles(i) = app.buildTile(L(i), F(strcmp({F.id}, L(i).family)).color);
            end
        end

        %% buildLearn - One tile per Techniques.learn() item
        function buildLearn(app)
            T = UITheme;
            L = Techniques.learn();
            app.LearnTiles = gobjects(1, numel(L));
            app.LearnButtons = struct();
            for i = 1:numel(L)
                id = L(i).id;
                isDemo = strcmp(id, 'demo');
                p = uipanel(app.LearnGrid, 'BackgroundColor', T.cardBg, 'BorderType', 'line', ...
                    'HighlightColor', T.cardBorder);
                app.LearnTiles(i) = p;
                if isDemo, cw = 176; else, cw = 84; end
                g = uigridlayout(p, [2 2], 'ColumnWidth', {'1x', cw}, 'RowHeight', {20, '1x'}, ...
                    'Padding', [12 8 12 8], 'RowSpacing', 2, 'ColumnSpacing', 10, 'BackgroundColor', T.cardBg);
                uilabel(g, 'Text', L(i).name, 'FontSize', T.fontButton + 1, 'FontWeight', 'bold', ...
                    'FontColor', T.sectionTitleColor);
                d = uilabel(g, 'Text', L(i).description, 'FontSize', T.fontSmall, 'FontColor', T.bodyColor, ...
                    'WordWrap', 'on', 'VerticalAlignment', 'top');
                d.Layout.Row = 2; d.Layout.Column = 1;
                if isDemo
                    c = uigridlayout(g, [2 1], 'RowHeight', {T.controlHeight - 2, T.buttonHeight - 4}, ...
                        'Padding', [0 0 0 0], 'RowSpacing', 4, 'BackgroundColor', T.cardBg);
                    [labels, classes] = Techniques.demoChoices();
                    app.DemoDrop = uidropdown(c, 'Items', labels, 'ItemsData', classes, ...
                        'FontSize', T.fontSmall, 'Tooltip', 'The window to open with demo data');
                    b = UIKit.button(c, [char(9654) ' Try'], @(~,~)app.tryDemo(), 'secondary', L(i).tooltip);
                else
                    c = uigridlayout(g, [3 1], 'RowHeight', {'1x', T.buttonHeight, '1x'}, ...
                        'Padding', [0 0 0 0], 'RowSpacing', 0, 'BackgroundColor', T.cardBg);
                    uilabel(c, 'Text', '');
                    b = UIKit.button(c, 'Open', @(~,~)app.openLearn(id), 'secondary', L(i).tooltip);
                    b.Layout.Row = 2;
                    if ~L(i).available
                        b.Text = 'Coming soon';
                        b.Enable = 'off';
                    end
                end
                c.Layout.Row = [1 2]; c.Layout.Column = 2;
                app.LearnButtons.(id) = b;
            end
        end

        %% buildTile - One analysis tile: colour stripe, title and ?, description, steps, in / out
        function tile = buildTile(app, t, color)
            T = UITheme;
            p = uipanel(app.TileGrid, 'BackgroundColor', T.cardBg, 'BorderType', 'line', ...
                'HighlightColor', T.cardBorder);
            outer = uigridlayout(p, [2 1], 'RowHeight', {4, '1x'}, 'ColumnWidth', {'1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 0, 'BackgroundColor', T.cardBg);
            uilabel(outer, 'Text', '', 'BackgroundColor', color);
            g = uigridlayout(outer, [5 2], 'RowHeight', {26, 32, '1x', T.buttonHeight, 14}, ...
                'ColumnWidth', {'1x', 30}, 'Padding', [12 6 12 8], 'RowSpacing', 4, ...
                'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
            uilabel(g, 'Text', t.name, 'FontSize', T.fontButton + 1, 'FontWeight', 'bold', ...
                'FontColor', T.sectionTitleColor);
            hb = UIKit.button(g, '?', @(~,~)app.openHelp(t.help), 'secondary', ...
                sprintf('Help: %s (quick start, file formats, troubleshooting)', t.help));
            d = uilabel(g, 'Text', t.description, 'FontSize', T.fontBody, 'WordWrap', 'on', ...
                'FontColor', T.sectionTitleColor, 'VerticalAlignment', 'top');
            d.Layout.Row = 2; d.Layout.Column = [1 2];
            n = numel(t.steps);
            cols = repmat({'1x'}, 1, 2 * n - 1);
            cols(2:2:end) = {16};
            sg = uigridlayout(g, [1, 2 * n - 1], 'ColumnWidth', cols, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            sg.Layout.Row = 4; sg.Layout.Column = [1 2];
            btns = gobjects(1, n);
            for k = 1:n
                if n > 1
                    txt = sprintf('%d   %s', k, t.steps(k).label);
                else
                    txt = t.steps(k).label;
                end
                id = t.id; step = k;
                btns(k) = UIKit.button(sg, txt, @(~,~)app.runStep(id, step), 'primary', t.steps(k).tooltip);
                btns(k).Layout.Row = 1; btns(k).Layout.Column = 2 * k - 1;
                if k < n
                    a = uilabel(sg, 'Text', char(8594), 'FontSize', T.fontSection, ...
                        'FontColor', T.mutedColor, 'HorizontalAlignment', 'center');
                    a.Layout.Row = 1; a.Layout.Column = 2 * k;
                end
            end
            io = uilabel(g, 'Text', t.io, 'FontSize', T.fontTiny, 'FontColor', T.mutedColor);
            io.Layout.Row = 5; io.Layout.Column = [1 2];
            tile = struct('id', t.id, 'family', t.family, 'panel', p, 'steps', btns, 'help', hb);
        end

        %% onResize - Cut the cover art to the new width; re-flow the tiles if the columns change
        function onResize(app)
            if isempty(app.UIFig) || ~isvalid(app.UIFig), return; end
            app.updateCover();
            n = Main.columnsFor(app.UIFig.Position(3));
            if n ~= app.Columns
                app.layoutTiles(n);
            end
        end

        %% layoutTiles - Place the tiles in n columns (families kept together, Main.pack)
        function layoutTiles(app, n)
            F = Techniques.families();
            fam = {app.Tiles.family};
            counts = cellfun(@(f) sum(strcmp(fam, f)), {F.id});
            B = Main.pack(counts, n);
            nRows = max([B.row]);
            % Park everything in cell (1, 1), valid in any grid, before resizing the grids
            for i = 1:numel(app.Tiles)
                app.Tiles(i).panel.Layout.Row = 1; app.Tiles(i).panel.Layout.Column = 1;
            end
            for i = 1:numel(app.LearnTiles)
                app.LearnTiles(i).Layout.Row = 1; app.LearnTiles(i).Layout.Column = 1;
            end
            cellfun(@delete, app.Headings);
            app.Headings = {};

            heights = repmat({Main.HeadingHeight, Main.TileHeight}, 1, nRows);
            for r = 1:nRows
                if ~any([B([B.row] == r).head])
                    heights{2 * r - 1} = Main.Gap;    % only the rest of a family: no heading
                end
            end
            app.TileGrid.ColumnWidth = repmat({'1x'}, 1, n);
            app.TileGrid.RowHeight = heights;
            for b = 1:numel(B)
                idx = find(strcmp(fam, F(B(b).family).id));
                idx = idx(B(b).first:B(b).first + B(b).count - 1);
                for j = 1:numel(idx)
                    app.Tiles(idx(j)).panel.Layout.Row = 2 * B(b).row;
                    app.Tiles(idx(j)).panel.Layout.Column = B(b).col + j - 1;
                end
                if B(b).head
                    app.Headings{end+1} = familyHeading(app.TileGrid, F(B(b).family), ...
                        2 * B(b).row - 1, [B(b).col, B(b).col + B(b).count - 1]);
                end
            end

            % Learn: two tiles per row, one in a narrow window
            nl = numel(app.LearnTiles);
            if n >= 2, lc = 2; else, lc = 1; end
            lr = ceil(nl / lc);
            app.LearnGrid.ColumnWidth = repmat({'1x'}, 1, lc);
            app.LearnGrid.RowHeight = repmat({Main.LearnHeight}, 1, lr);
            for i = 1:nl
                app.LearnTiles(i).Layout.Row = ceil(i / lc);
                app.LearnTiles(i).Layout.Column = mod(i - 1, lc) + 1;
            end
            learnH = lr * Main.LearnHeight + (lr - 1) * app.LearnGrid.RowSpacing;
            app.BodyGrid.RowHeight = {30, learnH, 30, sum([heights{:}])};
            app.Columns = n;
        end

        %% updateCover - Cut the cover art to the free width of the cover (hidden when too narrow)
        function updateCover(app)
            if isempty(app.CoverImage) || ~isvalid(app.CoverImage) || isempty(app.CoverArt), return; end
            T = UITheme;
            w = round(app.UIFig.Position(3) - (T.headerPaddingH + 16 + 44 + Main.TitleWidth + 96 + 3 * 12));
            if w < 120
                app.CoverImage.Visible = 'off';
                app.CoverWidth = 0;
                return;
            end
            app.CoverImage.Visible = 'on';
            if abs(w - app.CoverWidth) < 8, return; end
            app.CoverImage.ImageSource = Main.coverCrop(app.CoverArt, w, Main.CoverHeight, T.headerBg);
            app.CoverWidth = w;
        end

        %% runStep - Open the window of step k of a tile (or choose a session file)
        function win = runStep(app, id, k)
            L = Techniques.list();
            t = L(strcmp({L.id}, id));
            s = t.steps(k);
            if strcmp(s.action, 'session')
                win = app.openSessionFile();
                return;
            end
            name = s.label;
            if numel(t.steps) > 1 && ~contains(name, t.short)
                name = [name ' ' t.short];
            end
            win = app.launch(str2func(s.window), name);
        end

        %% launch - Open a window, reporting success or failure in the status bar
        function win = launch(app, ctor, name)
            win = [];
            app.LastOpened = [];
            UIKit.setStatus(app.StatusLabel, sprintf('Opening %s', name), 'busy');
            try
                win = ctor();
                app.LastOpened = win;
                UIKit.setStatus(app.StatusLabel, sprintf('Opened %s', name), 'success');
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Could not open %s', name), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not open %s:\n%s', name, ME.message), name);
            end
        end

        %% openLearn - Open a Learn item by id ('course', 'lab', 'demo', 'help')
        function win = openLearn(app, id)
            L = Techniques.learn();
            it = L(strcmp({L.id}, id));
            if ~it.available
                win = [];
                app.LastOpened = [];
                UIKit.setStatus(app.StatusLabel, sprintf('%s: coming soon', it.name), 'warning');
            elseif strcmp(it.window, 'HelpApp')
                win = app.openHelp(it.help);
            elseif isempty(it.window)
                win = app.tryDemo();
            else
                win = app.launch(str2func(it.window), it.name);
            end
        end

        %% openHelp - Help on a topic
        function win = openHelp(app, topic)
            win = [];
            app.LastOpened = [];
            try
                win = HelpApp(topic);
                app.LastOpened = win;
                if strcmpi(topic, 'Welcome')
                    UIKit.setStatus(app.StatusLabel, ['Help opened: pick a topic on the left; every ' ...
                        'window''s topic has a "Try it with demo data" button'], 'success');
                else
                    UIKit.setStatus(app.StatusLabel, sprintf('Help opened on %s', topic), 'success');
                end
            catch ME
                UIKit.setStatus(app.StatusLabel, 'Could not open Help', 'error');
                UIKit.alert(app.UIFig, sprintf('Could not open Help:\n%s', ME.message), 'Help');
            end
        end

        %% tryDemo - Open a window with its demo data (default: the one chosen in the Learn area)
        function win = tryDemo(app, cls)
            win = [];
            app.LastOpened = [];
            if nargin < 2 || isempty(cls), cls = app.DemoDrop.Value; end
            k = find(strcmp(app.DemoDrop.ItemsData, cls), 1);
            if isempty(k)
                UIKit.setStatus(app.StatusLabel, sprintf('%s has no demo data', cls), 'error');
                return;
            end
            app.DemoDrop.Value = cls;
            name = app.DemoDrop.Items{k};
            UIKit.setStatus(app.StatusLabel, sprintf('Opening %s with demo data', name), 'busy');
            try
                win = feval(cls);
                app.LastOpened = win;
                win.loadDemo();
                UIKit.setStatus(app.StatusLabel, sprintf(['Opened %s with demo data. The expected ' ...
                    'results are under "Demo data" in its Help (? Help in the window).'], name), 'success');
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Could not open %s with demo data', name), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not open %s with demo data:\n%s', name, ME.message), ...
                    'Try with demo data');
            end
        end

        %% openSessionFile - Open a saved session in the window that saved it
        % p omitted: choose the file (and missing input files) with dialogs.
        function win = openSessionFile(app, p)
            win = [];
            app.LastOpened = [];
            interactive = nargin < 2 || isempty(p);
            if interactive
                [f, d] = uigetfile({['*' Session.Extension], 'Neuronal Data Analyzer Lab sessions'}, ...
                    'Open a session', UIKit.sessionFolder(app));
                figure(app.UIFig);
                if isequal(f, 0), return; end
                p = fullfile(d, f);
            end
            try
                s = Session.load(p);
            catch ME
                UIKit.setStatus(app.StatusLabel, 'Could not read the session file', 'error');
                UIKit.alert(app.UIFig, sprintf('Could not read the session:\n%s', ME.message), 'Open a session');
                return;
            end
            if ~any(strcmp(Techniques.windows(), s.app)) || ~any(strcmp(methods(s.app), 'openSession'))
                UIKit.setStatus(app.StatusLabel, sprintf('No window opens sessions of %s', s.app), 'error');
                UIKit.alert(app.UIFig, sprintf(['This session was saved by "%s", which is not a window ' ...
                    'of this version of Neuronal Data Analyzer Lab.'], s.app), 'Open a session');
                return;
            end
            [~, n, e] = fileparts(p);
            name = Techniques.windowName(s.app);
            win = app.launch(str2func(s.app), name);
            if isempty(win), return; end
            if logical(win.openSession(p, interactive))
                UIKit.setStatus(app.StatusLabel, sprintf('Opened the session %s%s in %s', n, e, name), 'success');
            else
                UIKit.setStatus(app.StatusLabel, sprintf(['The session %s%s was not opened: the status bar ' ...
                    'of %s says why'], n, e, name), 'warning');
            end
        end

        %% checkSignalToolbox - Non-blocking warning if Signal Processing Toolbox is missing
        % Filtering, downsampling and spike detection (butter, filtfilt,
        % decimate, iirnotch, findpeaks) all depend on it.
        function checkSignalToolbox(app)
            hasSPT = license('test', 'Signal_Toolbox') && exist('butter', 'file') > 0;
            app.HasSignalToolbox = hasSPT;
            if ~hasSPT
                uialert(app.UIFig, ['Signal Processing Toolbox was not found or is not licensed. ' ...
                    'LDF/LFP/MUA filtering, downsampling and spike detection will fail.'], ...
                    'Missing Toolbox', 'Icon', 'warning');
            end
        end

        %% checkTDTSDK - Is the TDT MATLAB SDK installed (on the path or under Utilities/)?
        function checkTDTSDK(app)
            rootDir = fileparts(fileparts(mfilename('fullpath')));
            app.HasTDTSDK = exist('TDTbin2mat', 'file') > 0 || ...
                exist(fullfile(rootDir, 'Utilities', 'TDTMatlabSDK'), 'dir') > 0;
        end

        %% showEnvironmentStatus - Toolbox availability in the status bar
        function showEnvironmentStatus(app)
            yesNo = {'missing', 'found'};
            msg = sprintf('Signal Processing Toolbox: %s  ·  TDT SDK: %s', ...
                yesNo{app.HasSignalToolbox + 1}, yesNo{app.HasTDTSDK + 1});
            if ~app.HasSignalToolbox
                UIKit.setStatus(app.StatusLabel, [msg '  -  filtering and spike detection will fail'], 'warning');
            elseif ~app.HasTDTSDK
                UIKit.setStatus(app.StatusLabel, [msg ...
                    '  (only needed for Extract Ephys; see README "Install the TDT SDK")'], 'info');
            else
                UIKit.setStatus(app.StatusLabel, ['Ready  ·  ' msg], 'success');
            end
        end

        function onSetDirectories(app)
            ok = ProjectManager.promptForProjectDirs();
            figure(app.UIFig);
            app.updateProjectLabels();
            if ok
                UIKit.setStatus(app.StatusLabel, 'Project folders updated', 'success');
            end
        end

        function updateProjectLabels(app)
            imp = ProjectManager.getImportDir();
            exp = ProjectManager.getExportDir();
            app.ImportLabel.Tooltip = imp;
            app.ExportLabel.Tooltip = exp;
            if isempty(imp), imp = '(not set)'; else, imp = pathShorten(imp, 42); end
            if isempty(exp), exp = '(not set)'; else, exp = pathShorten(exp, 42); end
            app.ImportLabel.Text = imp;
            app.ExportLabel.Text = exp;
        end
    end

    methods (Static)
        %% columnsFor - Tile columns for a window width (1 to 3)
        function n = columnsFor(width)
            content = width - 32 - 18;           % body padding and room for a scroll bar
            n = floor((content + Main.Gap) / (Main.TileMinWidth + Main.Gap));
            n = max(1, min(3, n));
        end

        %% pack - Place families of tiles in rows of n columns
        % counts(f) = number of tiles of family f, in order. A family longer
        % than n is cut into chunks of n. Rows are filled in order; a later
        % family may fill a gap when it fits whole, but the chunks of one
        % family never change order. B: family, first (index of its first
        % tile in the family), count, head (first chunk of the family), row,
        % col (first column).
        function B = pack(counts, n)
            B = struct('family', {}, 'first', {}, 'count', {}, 'head', {}, 'row', {}, 'col', {});
            for f = 1:numel(counts)
                for s = 1:n:counts(f)
                    B(end+1) = struct('family', f, 'first', s, 'count', min(n, counts(f) - s + 1), ... %#ok<AGROW>
                        'head', s == 1, 'row', 0, 'col', 0);
                end
            end
            left = 1:numel(B);
            row = 0;
            while ~isempty(left)
                row = row + 1;
                free = n;
                i = 1;
                while i <= numel(left) && free > 0
                    b = left(i);
                    earlier = left(1:i-1);
                    waiting = any([B(earlier).family] == B(b).family);   % an earlier chunk of this family is not placed yet
                    if B(b).count <= free && ~waiting
                        B(b).row = row;
                        B(b).col = n - free + 1;
                        free = free - B(b).count;
                        left(i) = [];
                    else
                        i = i + 1;
                    end
                end
            end
        end

        %% coverCrop - Cover art for a w x h px cell: the left part of the
        % art (padded with its last column when the cell is wider), its right
        % edge faded into the header colour bg where it meets ? Help
        function img = coverCrop(art, w, h, bg)
            [H, W, ~] = size(art);
            n = max(2, round(w * H / h));
            if n <= W
                img = art(:, 1:n, :);
            else
                img = cat(2, art, repmat(art(:, end, :), 1, n - W, 1));
            end
            k = min(n, max(2, round(60 * H / h)));
            a = linspace(1, 0, k);                         % weight of the art
            bgImg = reshape(255 * bg(:)', 1, 1, 3);
            tail = double(img(:, end-k+1:end, :));
            img(:, end-k+1:end, :) = uint8(tail .* a + bgImg .* (1 - a));
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% sectionHeading - "LEARN" / "ANALYSES" with a one-line explanation
function g = sectionHeading(parent, titleText, hintText)
    T = UITheme;
    g = uigridlayout(parent, [1 2], 'ColumnWidth', {'fit', '1x'}, 'RowHeight', {'1x'}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 14, 'BackgroundColor', T.bgGray);
    uilabel(g, 'Text', titleText, 'FontSize', T.fontSection, 'FontWeight', 'bold', ...
        'FontColor', T.sectionTitleColor);
    uilabel(g, 'Text', hintText, 'FontSize', T.fontSmall, 'FontColor', T.mutedColor, 'WordWrap', 'on');
end

%% familyHeading - Colour mark, family name and a rule, over the family's tiles
function g = familyHeading(parent, fam, row, cols)
    T = UITheme;
    g = uigridlayout(parent, [3 3], 'RowHeight', {'1x', 1, '1x'}, 'ColumnWidth', {10, 'fit', '1x'}, ...
        'Padding', [0 6 0 10], 'RowSpacing', 0, 'ColumnSpacing', 8, 'BackgroundColor', T.bgGray);
    g.Layout.Row = row;
    if cols(1) == cols(2), cols = cols(1); end   % [c c] is not allowed: one column is a number
    g.Layout.Column = cols;
    m = uilabel(g, 'Text', '', 'BackgroundColor', fam.color);
    m.Layout.Row = [1 3]; m.Layout.Column = 1;
    n = uilabel(g, 'Text', upper(fam.name), 'FontSize', T.fontSmall + 1, 'FontWeight', 'bold', ...
        'FontColor', T.sectionTitleColor);
    n.Layout.Row = [1 3]; n.Layout.Column = 2;
    r = uilabel(g, 'Text', '', 'BackgroundColor', T.cardBorder);
    r.Layout.Row = 2; r.Layout.Column = 3;
end

function s = pathShorten(p, maxLen)
    if length(p) <= maxLen
        s = p;
        return;
    end
    s = ['...' p(end-maxLen+3:end)];
end
