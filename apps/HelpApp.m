%% HelpApp.m
% =========================================================================
% HELP APP - TOPIC NAVIGATION WITH QUICK STARTS, FILE FORMATS AND FIGURES
% =========================================================================
% Opened from the launcher (Help button and the '?' on each workflow card)
% and from the "? Help" button in every window header (UIKit.header).
% Optional constructor argument topic (e.g. 'LDF Extract', 'Filtering')
% opens the window on that topic (case-insensitive). Topic titles are the
% keys other windows use and must not change:
%   Welcome | LDF Extract | LDF Process | Filtering | LDF Average |
%   Ephys Extract | LFP Analysis | MUA Analysis | ROI Analysis |
%   Signal Characterization
%
% Layout (UIKit.window): topic list on the left (ordered by workflow,
% Previous / Next, link to GitHub issues), topic page on the right. Each
% page: Quick start (numbered steps matching the step cards of the
% window), Inputs and outputs, How it works (detailed text),
% Troubleshooting, then the explanatory figures from docs/ (resolved by
% getDocsPath, embedded as data URIs). Pages are rendered with uihtml;
% if uihtml is unavailable a plain uitextarea is used instead. An open
% Help window is reused (switched to the requested topic) rather than
% opening a second one.
%
% Demo data: every page has a "Demo data" section (what the synthetic
% dataset from DemoData contains and the results to expect), and the
% "Try it with demo data" button under the topic list opens the matching
% window and calls its loadDemo() (tryDemo). On Welcome the button writes
% every demo file to a folder instead (generateDemoFiles).
% =========================================================================

classdef HelpApp < handle
    %% PROPERTIES
    properties
        UIFig       % Main uifigure
        W           % UIKit.window struct (Fig, Body, Status, HelpBtn)
        TopicList   % uilistbox of topic titles (left navigation)
        Content     % uihtml (or uitextarea fallback) showing the topic page
        PrevBtn
        NextBtn
        DemoBtn     % "Try it with demo data" (Welcome: "Generate all demo files...")
        Tabs        % Cell of topic titles (kept name: other code may index topics by it)
        Topics      % Struct array of topic content (see HelpApp.topicData)
        UseHtml = true
        ImageCache  % containers.Map: file name -> data URI
    end

    properties(Constant)
        IssuesURL = 'https://github.com/alesuarez92/NeuronalDataAnalyzerLab/issues'
    end

    methods
        %% Constructor - Build UI and optionally select a topic by title
        % -------------------------------------------------------------
        % If topic is given and matches a topic title (case-insensitive),
        % that page is shown; otherwise Welcome.
        % -------------------------------------------------------------
        function app = HelpApp(topic)
            if nargin < 1, topic = ''; end
            % Reuse an open Help window instead of stacking a new one per click
            openFigs = findall(groot, 'Type', 'figure', 'Tag', 'NeuroAnalyzerHelp');
            if ~isempty(openFigs) && isa(openFigs(1).UserData, 'HelpApp') && isvalid(openFigs(1).UserData)
                prev = openFigs(1).UserData;
                for p = {'UIFig', 'W', 'TopicList', 'Content', 'PrevBtn', 'NextBtn', 'DemoBtn', ...
                        'Tabs', 'Topics', 'UseHtml', 'ImageCache'}
                    app.(p{1}) = prev.(p{1});
                end
                prev.selectTopic(topic);
                figure(app.UIFig);
                return;
            end
            app.ImageCache = containers.Map('KeyType', 'char', 'ValueType', 'char');
            app.Topics = HelpApp.topicData();
            app.Tabs = {app.Topics.title};
            app.buildUI();
            app.selectTopic(topic);
        end

        %% getDocsPath - Resolve path to docs/filename relative to toolbox root
        % -------------------------------------------------------------
        % Uses preference NeuroAnalyzer.RootDir (set by NeuroAnalyzer.m), or
        % folder containing Main.m, or parent of that if docs live at project root.
        % -------------------------------------------------------------
        function p = getDocsPath(app, filename) %#ok<INUSL>
            base = getpref('NeuroAnalyzer', 'RootDir', '');
            if isempty(base)
                base = fileparts(which('Main'));
                if ~isempty(base) && ~exist(fullfile(base, 'docs'), 'dir')
                    parent = fileparts(base);
                    if exist(fullfile(parent, 'docs'), 'dir')
                        base = parent;
                    end
                end
            end
            if isempty(base)
                base = pwd;
            end
            p = fullfile(base, 'docs', filename);
        end

        %% buildUI - Window with topic list (left) and page (right)
        function buildUI(app)
            T = UITheme;
            app.W = UIKit.window('NeuroAnalyzer Help', ...
                'Quick starts, file formats and troubleshooting for every window', '', [1120 780]);
            app.UIFig = app.W.Fig;
            app.UIFig.Tag = 'NeuroAnalyzerHelp';
            app.UIFig.UserData = app;
            body = app.W.Body;
            body.RowHeight = {'1x'};
            body.ColumnWidth = {230, '1x'};

            % --- Left: navigation ---
            nav = UIKit.card(body);
            ng = uigridlayout(nav, [6 2], ...
                'RowHeight', {'fit', '1x', T.buttonHeight + 6, 'fit', T.buttonHeight, T.buttonHeight}, ...
                'ColumnWidth', {'1x', '1x'}, 'Padding', [10 10 10 10], 'RowSpacing', 8, ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            lbl = uilabel(ng, 'Text', 'Topics', 'FontSize', T.fontBody, 'FontWeight', 'bold', ...
                'FontColor', T.sectionTitleColor);
            lbl.Layout.Row = 1; lbl.Layout.Column = [1 2];
            items = cellfun(@(t, g) navLabel(t, g), app.Tabs, {app.Topics.group}, ...
                'UniformOutput', false);
            app.TopicList = uilistbox(ng, 'Items', items, 'ItemsData', app.Tabs, ...
                'Value', app.Tabs{1}, 'FontSize', T.fontBody, ...
                'Tooltip', 'Topics in workflow order: LDF, electrophysiology, imaging, response features', ...
                'ValueChangedFcn', @(~,~)app.showTopic(app.TopicList.Value));
            app.TopicList.Layout.Row = 2; app.TopicList.Layout.Column = [1 2];
            app.DemoBtn = UIKit.button(ng, [char(9654) ' Try it with demo data'], ...
                @(~,~)app.tryDemo(app.TopicList.Value), 'primary', ...
                'Open this window with synthetic data whose answers are known');
            app.DemoBtn.Layout.Row = 3; app.DemoBtn.Layout.Column = [1 2];
            note = uilabel(ng, 'Text', ['Same order as the launcher cards. Each window''s ' ...
                '"? Help" button opens its topic here.'], 'FontSize', T.fontTiny, ...
                'FontColor', T.mutedColor, 'WordWrap', 'on');
            note.Layout.Row = 4; note.Layout.Column = [1 2];
            app.PrevBtn = UIKit.button(ng, [char(8249) ' Previous'], @(~,~)app.step(-1), ...
                'secondary', 'Previous topic');
            app.PrevBtn.Layout.Row = 5; app.PrevBtn.Layout.Column = 1;
            app.NextBtn = UIKit.button(ng, ['Next ' char(8250)], @(~,~)app.step(1), ...
                'secondary', 'Next topic');
            app.NextBtn.Layout.Row = 5; app.NextBtn.Layout.Column = 2;
            issues = UIKit.button(ng, 'Report a problem', @(~,~)web(HelpApp.IssuesURL, '-browser'), ...
                'secondary', ['Open GitHub issues in your browser: ' HelpApp.IssuesURL]);
            issues.Layout.Row = 6; issues.Layout.Column = [1 2];

            % --- Right: topic page ---
            page = UIKit.card(body);
            pg = uigridlayout(page, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', T.cardBg);
            try
                app.Content = uihtml(pg);
                app.UseHtml = true;
            catch
                app.Content = uitextarea(pg, 'Editable', 'off', 'WordWrap', 'on', ...
                    'FontSize', T.fontBody);
                app.UseHtml = false;
            end
        end

        %% selectTopic - Show a topic by title (case-insensitive); Welcome if unknown
        function selectTopic(app, topic)
            idx = [];
            if ~isempty(topic)
                idx = find(strcmpi(app.Tabs, strtrim(char(topic))), 1);
            end
            if isempty(idx), idx = 1; end
            app.TopicList.Value = app.Tabs{idx};
            app.showTopic(app.Tabs{idx});
        end

        %% step - Previous (-1) / next (+1) topic
        function step(app, d)
            idx = find(strcmp(app.Tabs, app.TopicList.Value), 1);
            idx = min(max(1, idx + d), numel(app.Tabs));
            app.selectTopic(app.Tabs{idx});
        end

        %% showTopic - Render one topic page
        function showTopic(app, title)
            idx = find(strcmp(app.Tabs, title), 1);
            if isempty(idx), return; end
            tp = app.Topics(idx);
            onOff = {'off', 'on'};
            app.PrevBtn.Enable = onOff{(idx > 1) + 1};
            app.NextBtn.Enable = onOff{(idx < numel(app.Tabs)) + 1};
            win = HelpApp.demoWindow(tp.title);
            if isempty(win)
                app.DemoBtn.Text = ['Generate all demo files' char(8230)];
                app.DemoBtn.Tooltip = ['Write every synthetic demo file (LDF, TDT tank, LFP, MUA, imaging) ' ...
                    'to a folder of your choice, e.g. to use it as the Import folder'];
            else
                app.DemoBtn.Text = [char(9654) ' Try it with demo data'];
                app.DemoBtn.Tooltip = sprintf(['Open %s with synthetic data whose answers are known ' ...
                    '(see "Demo data" on this page)'], tp.title);
            end
            if app.UseHtml
                app.Content.HTMLSource = app.topicHtml(tp);
            else
                app.Content.Value = HelpApp.topicPlain(tp);
            end
            UIKit.setStatus(app.W.Status, sprintf('%s  ·  %s', tp.title, tp.summary), 'info');
        end

        %% tryDemo - Open the window of a topic and load its demo data
        % Returns the opened app ([] for Welcome, which generates the demo
        % files instead, or on error). Windows without loadDemo are just opened.
        function win = tryDemo(app, topic)
            win = [];
            if nargin < 2 || isempty(topic), topic = app.TopicList.Value; end
            cls = HelpApp.demoWindow(topic);
            if isempty(cls)
                app.generateDemoFiles();
                return;
            end
            UIKit.setStatus(app.W.Status, sprintf('Opening %s with demo data', topic), 'busy');
            try
                win = feval(cls);
                if ismethod(win, 'loadDemo')
                    win.loadDemo();
                    UIKit.setStatus(app.W.Status, sprintf(['Opened %s with demo data. Compare your ' ...
                        'results with "Demo data" on this page.'], topic), 'success');
                else
                    UIKit.setStatus(app.W.Status, sprintf(['Opened %s. Its demo is not available yet: ' ...
                        'use Welcome → Generate all demo files and load the file by hand.'], topic), 'warning');
                end
            catch ME
                UIKit.setStatus(app.W.Status, sprintf('Could not open %s with demo data', topic), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not open %s with demo data: %s', topic, ME.message), ...
                    'Demo data');
            end
        end

        %% generateDemoFiles - Write every demo file to a folder (DemoData.writeAll)
        % folder omitted/empty: ask with uigetdir (default DemoData.folder()).
        % offerImport (default true): afterwards offer to make the folder the
        % project Import folder. Returns the DemoData.writeAll file struct ([] if cancelled / failed).
        function files = generateDemoFiles(app, folder, offerImport)
            files = [];
            if nargin < 3, offerImport = true; end
            if nargin < 2 || isempty(folder)
                start = DemoData.folder();
                if ~exist(start, 'dir')
                    try mkdir(start); catch, start = pwd; end
                end
                folder = uigetdir(start, 'Choose a folder for the demo files');
                figure(app.UIFig);
                if isequal(folder, 0)
                    UIKit.setStatus(app.W.Status, 'Demo files: cancelled', 'info');
                    return;
                end
            end
            dlg = UIKit.busy(app.UIFig, sprintf('Writing the demo files to %s%s', folder, char(8230)));
            UIKit.setStatus(app.W.Status, 'Writing the demo files', 'busy');
            try
                files = DemoData.writeAll(folder);
            catch ME
                UIKit.done(dlg);
                files = [];
                UIKit.setStatus(app.W.Status, 'Could not write the demo files', 'error');
                UIKit.alert(app.UIFig, sprintf('Could not write the demo files: %s', ME.message), 'Demo data');
                return;
            end
            UIKit.done(dlg);
            UIKit.setStatus(app.W.Status, sprintf(['Demo files written to %s (LDF export, cropped LDF, ' ...
                'LDF trials, TDT tank, LFP, MUA, imaging stack).'], folder), 'success');
            if offerImport
                uiconfirm(app.UIFig, sprintf(['The demo files are in\n%s\n\nUse this folder as the ' ...
                    'project Import folder, so every Load dialog starts there?'], folder), 'Demo files written', ...
                    'Options', {'Use as Import folder', 'Not now'}, 'DefaultOption', 1, 'CancelOption', 2, ...
                    'Icon', 'success', 'CloseFcn', @(~, evt)app.onImportChoice(evt, folder));
            end
        end

        %% onImportChoice - uiconfirm answer of generateDemoFiles
        function onImportChoice(app, evt, folder)
            if strcmp(evt.SelectedOption, 'Use as Import folder')
                ProjectManager.setImportDir(folder);
                UIKit.setStatus(app.W.Status, sprintf('Import folder set to %s', folder), 'success');
            end
        end

        %% topicHtml - Full HTML page for one topic
        function html = topicHtml(app, tp)
            T = UITheme;
            css = sprintf([ ...
                'body{font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;font-size:13px;' ...
                'color:%s;margin:0;padding:18px 26px 30px 26px;line-height:1.45;background:#fff}' ...
                '.crumb{font-size:11px;color:%s;text-transform:uppercase;letter-spacing:.04em}' ...
                'h1{font-size:21px;color:%s;margin:2px 0 4px 0}' ...
                '.lead{font-size:13.5px;color:%s;margin:0 0 14px 0}' ...
                'h2{font-size:15px;color:%s;border-bottom:1px solid %s;padding-bottom:3px;margin:22px 0 8px 0}' ...
                'h3{font-size:13px;color:%s;margin:14px 0 4px 0}' ...
                'ol.steps{list-style:none;padding:0;margin:0}' ...
                'ol.steps li{display:flex;align-items:flex-start;padding:6px 10px;margin:0 0 6px 0;' ...
                'background:%s;border:1px solid %s;border-radius:6px}' ...
                'ol.steps span.num{flex:0 0 22px;display:inline-block;width:22px;height:22px;margin:0 10px 0 0;' ...
                'border-radius:11px;background-color:%s;color:#ffffff;font-weight:bold;text-align:center;' ...
                'line-height:22px;font-size:12px}' ...
                'ol.steps span.txt{flex:1 1 auto}' ...
                '.demo{background:%s;border:1px solid %s;border-radius:6px;padding:2px 14px 6px 14px}' ...
                '.demo p.try{font-weight:bold;color:%s}' ...
                '.io{display:flex;gap:12px;flex-wrap:wrap}' ...
                '.io div{flex:1 1 260px;border:1px solid %s;border-radius:6px;padding:6px 12px}' ...
                '.io h3{margin-top:4px}' ...
                'ul{margin:4px 0 8px 0;padding-left:20px}li{margin:2px 0}' ...
                'code{background:%s;padding:0 3px;border-radius:3px;font-size:12px}' ...
                'table.tr{border-collapse:collapse;width:100%%}' ...
                'table.tr td{border-top:1px solid %s;padding:6px 8px;vertical-align:top}' ...
                'table.tr td:first-child{width:38%%;font-weight:bold;color:%s}' ...
                'table.pl{border-collapse:collapse;width:100%%;margin:4px 0}' ...
                'table.pl th{text-align:left;background:%s;padding:5px 8px}' ...
                'table.pl td{border-top:1px solid %s;padding:5px 8px;vertical-align:top}' ...
                'figure{margin:12px 0 18px 0;text-align:center}' ...
                'figure img{max-width:100%%;border:1px solid %s;border-radius:4px}' ...
                'figcaption{font-size:11px;color:%s}' ...
                '.missing{color:%s;font-style:italic}a{color:%s}'], ...
                hex(T.sectionTitleColor), hex(T.mutedColor), hex(T.headerBg), hex(T.bodyColor), ...
                hex(T.headerBg), hex(T.cardBorder), hex(T.sectionTitleColor), ...
                hex(T.hintBg), hex(T.hintBorder), hex(T.accent), ...
                hex(T.hintBg), hex(T.hintBorder), hex(T.info), hex(T.cardBorder), ...
                hex(T.secondaryBg), hex(T.cardBorder), hex(T.danger), hex(T.secondaryBg), ...
                hex(T.cardBorder), hex(T.cardBorder), hex(T.mutedColor), hex(T.mutedColor), hex(T.info));

            parts = {};
            parts{end+1} = sprintf('<div class="crumb">%s</div><h1>%s</h1><p class="lead">%s</p>', ...
                esc(tp.group), esc(tp.title), esc(tp.summary));
            if ~isempty(tp.quick)
                % Step numbers as literal text (CSS counters / ::before did not render in uihtml)
                items = arrayfun(@(k) sprintf('<li><span class="num">%d</span><span class="txt">%s</span></li>', ...
                    k, fmt(dropStepNo(tp.quick{k}))), 1:numel(tp.quick), 'UniformOutput', false);
                parts{end+1} = ['<h2>Quick start</h2><ol class="steps">' strjoin(items, '') '</ol>'];
            end
            if ~isempty(tp.demo)
                if isempty(HelpApp.demoWindow(tp.title))
                    try_ = ['Click <b>Generate all demo files' char(8230) '</b> (left) to write them to a folder.'];
                else
                    try_ = sprintf(['Click <b>%s Try it with demo data</b> (left) to open this window with the ' ...
                        'synthetic dataset, then check your results against the expected values.'], char(9654));
                end
                parts{end+1} = ['<h2>Demo data</h2><div class="demo"><p class="try">' try_ '</p>' ...
                    markup(tp.demo) '</div>'];
            end
            if ~isempty(tp.inputs) || ~isempty(tp.outputs)
                parts{end+1} = ['<h2>Inputs and outputs</h2><div class="io">' ...
                    '<div><h3>In</h3>' bullets(tp.inputs) '</div>' ...
                    '<div><h3>Out</h3>' bullets(tp.outputs) '</div></div>'];
            end
            if ~isempty(tp.details)
                parts{end+1} = ['<h2>' esc(tp.detailsTitle) '</h2>' markup(tp.details)];
            end
            if ~isempty(tp.trouble)
                rows = cellfun(@(p, f) ['<tr><td>' fmt(p) '</td><td>' fmt(f) '</td></tr>'], ...
                    tp.trouble(:, 1), tp.trouble(:, 2), 'UniformOutput', false);
                parts{end+1} = ['<h2>Troubleshooting / common errors</h2><table class="tr">' ...
                    strjoin(rows', '') '</table>'];
            end
            if ~isempty(tp.images)
                figs = {'<h2>Figures</h2>'};
                for k = 1:numel(tp.images)
                    figs{end+1} = app.figureHtml(tp.images{k}); %#ok<AGROW>
                end
                parts{end+1} = strjoin(figs, '');
            end
            html = ['<!DOCTYPE html><html><head><meta charset="utf-8"><style>' css ...
                '</style></head><body>' strjoin(parts, newline) '</body></html>'];
        end

        %% figureHtml - <figure> with the docs/ image embedded as a data URI
        function s = figureHtml(app, filename)
            if ~isKey(app.ImageCache, filename)
                uri = '';
                p = app.getDocsPath(filename);
                if exist(p, 'file')
                    try
                        fid = fopen(p, 'r');
                        bytes = fread(fid, Inf, '*uint8');
                        fclose(fid);
                        uri = ['data:image/png;base64,' matlab.net.base64encode(bytes')];
                    catch
                        uri = '';
                    end
                end
                app.ImageCache(filename) = uri;
            end
            uri = app.ImageCache(filename);
            if isempty(uri)
                s = sprintf('<p class="missing">(Figure docs/%s not found)</p>', esc(filename));
            else
                s = sprintf('<figure><img src="%s" alt="%s"><figcaption>docs/%s</figcaption></figure>', ...
                    uri, esc(filename), esc(filename));
            end
        end
    end

    %% TOPIC CONTENT
    methods(Static)
        %% topicPlain - Plain-text version of a topic (uitextarea fallback)
        function s = topicPlain(tp)
            strip = @(c) regexprep(c, '\*\*|`', '');
            s = {upper(tp.title); tp.summary; ''};
            if ~isempty(tp.quick)
                s{end+1} = 'QUICK START';
                for k = 1:numel(tp.quick)
                    s{end+1} = sprintf('  %d. %s', k, strip(dropStepNo(tp.quick{k}))); %#ok<AGROW>
                end
                s{end+1} = '';
            end
            if ~isempty(tp.demo)
                s{end+1} = 'DEMO DATA';
                for k = 1:numel(tp.demo)
                    s{end+1} = ['  ' strip(regexprep(tp.demo{k}, '^## |^\* |\|', ' '))]; %#ok<AGROW>
                end
                s{end+1} = '';
            end
            s = [s; {'INPUTS'}; strcat({'  - '}, strip(tp.inputs(:))); ...
                {'OUTPUTS'}; strcat({'  - '}, strip(tp.outputs(:))); {''}; {upper(tp.detailsTitle)}];
            for k = 1:numel(tp.details)
                s{end+1} = strip(regexprep(tp.details{k}, '^## |^\* |\|', ' ')); %#ok<AGROW>
            end
            s{end+1} = '';
            s{end+1} = 'TROUBLESHOOTING';
            for k = 1:size(tp.trouble, 1)
                s{end+1} = sprintf('  - %s: %s', strip(tp.trouble{k, 1}), strip(tp.trouble{k, 2})); %#ok<AGROW>
            end
        end

        %% demoWindow - Class of the window a topic's "Try it" opens ('' = Welcome)
        function cls = demoWindow(topic)
            map = {'LDF Extract', 'ExtractLDFApp'; 'LDF Process', 'ProcessingLDFApp'; ...
                'Filtering', 'ProcessingLDFApp'; 'LDF Average', 'LDFGrandAverageApp'; ...
                'Ephys Extract', 'ExtractEphysApp'; 'LFP Analysis', 'LFPAnalysisApp'; ...
                'MUA Analysis', 'MUAAnalysisApp'; 'ROI Analysis', 'ROIAnalysisApp'; ...
                'Signal Characterization', 'SignalCharacterizationApp'};
            k = find(strcmpi(map(:, 1), strtrim(char(topic))), 1);
            if isempty(k), cls = ''; else, cls = map{k, 2}; end
        end

        %% topicData - Content of every topic, in navigation order
        % Text markup: **bold**, `code`; in details, lines starting with
        % '## ' are sub-headings, '* ' bullets, '| a | b |' table rows
        % (first row = header); other lines are paragraphs.
        function tp = topicData()
            tp = [ ...
                HelpApp.topicWelcome(), HelpApp.topicLDFExtract(), HelpApp.topicLDFProcess(), ...
                HelpApp.topicFiltering(), HelpApp.topicLDFAverage(), HelpApp.topicEphysExtract(), ...
                HelpApp.topicLFPAnalysis(), HelpApp.topicMUAAnalysis(), HelpApp.topicROIAnalysis(), ...
                HelpApp.topicSignalCharacterization()];
        end

        %% topicWelcome - Overview of the four pipelines, project folders, help
        function t = topicWelcome()
            t = mkTopic('Welcome', 'Getting started', ...
                'NeuroAnalyzer (NMD Lab): analysis toolbox for LDF, electrophysiology, imaging and response features.');
            t.quick = {
                'In the launcher, click **Set folders** and choose your **Import** folder (raw data) and **Export** folder (results). You can use one folder for both.'
                'Find the card for your data (LDF, Electrophysiology, Imaging, Response features) and click its numbered steps **in order**.'
                'In every window, work down the numbered step cards on the left: **Load** → **Settings** → **Run** → **Save**. The teal button is the recommended next action; greyed-out buttons are not possible yet.'
                'Read the **status bar** at the bottom of each window: it says what happened and what to do next.'
                'Stuck? Click **? Help** in the window header for its quick start and troubleshooting.'};
            t.demo = {
                'Every window can load **synthetic data with known answers** (made by `DemoData`, always the same), so you can learn the workflow and check that you get the right numbers before using your own recordings.'
                '| File | Open it in | What it contains |'
                '| demo_ldf_export.mat | LDF Extract | LabChart-style export, 300 s at 1000 Hz: stimulus on channel 6 (5 s pulses every 30 s from 30 s), LDF on channel 8 (~120 PU) with a +30 PU response peaking ~4 s after each onset |'
                '| demo_ldf_cropped.mat | LDF Process | The same recording cropped to 20–280 s (`stim`, `LDF`, `t`, `Fs`) |'
                '| demo_ldf_trials.mat | LDF Average, Signal Characterization | 8 trials from −5 to 20 s at 10 Hz (`segmentedLDF`, `segmentedTime`) |'
                '| demo_tank/ | Ephys Extract | 30 s TDT-like block: 8 raw channels at 24414 Hz and a whisker stimulus (20 ms pulses every 2 s from 1 s) |'
                '| demo_lfp.mat | LFP Analysis, Signal Characterization | 8-channel LFP at 1017 Hz, 100 µm spacing: ERP with N1 at 15 ms and P2 at 40 ms, largest at channel 4 |'
                '| demo_mua.mat | MUA Analysis | Channels 3–5 at 24414 Hz with three units that fire more for 50 ms after each stimulus |'
                '| demo_imaging.mat | ROI Analysis | 96 × 96 × 150 frames at 10 Hz: a pulsing vessel, a moving red blood cell and a cell with calcium transients (`roiMask` included) |'
                'Each file also stores the ground truth in a `truth` variable. Use **Generate all demo files…** to write them to a folder (and optionally make it your Import folder), or the **Try it with demo data** button on any topic to open that window with its demo already loaded.'};
            t.inputs = {
                'LabChart .mat export (LDF)'
                'TDT tank / block folder (electrophysiology; needs the TDT MATLAB SDK)'
                'Image stack .mat or multi-frame TIFF (imaging)'
                'Any saved result with a time vector and signal (response features)'};
            t.outputs = {
                'Intermediate .mat files that the next step loads (cropped LDF, LDF trials, LFP, MUA)'
                'Final results: grand averages, ERP/CSD, spike sorting, ROI time series, feature tables (.csv / .mat)'};
            t.detailsTitle = 'Overview';
            t.details = {
                '## The four pipelines'
                '| Pipeline | Windows, in order | Starts from | Ends with |'
                '| LDF (Laser Doppler Flowmetry) | 1 Extract → 2 Process → 3 Average | LabChart .mat export | Trials .mat; grand average (mean ± SD) |'
                '| Electrophysiology | 1 Extract (TDT) → 2 LFP analysis or 2 MUA analysis | TDT tank folder | ERP and CSD; spike times, clusters, rates |'
                '| Imaging | ROI analysis | Image stack (.mat or TIFF) | Brightness, movement, ΔF/F, speed, kymograph, vessel diameter |'
                '| Response features | Signal Characterization | LDF trials, LFP / ERP .mat, or any t and y | Feature table: latency, FWHM, AUC, rise/decay |'
                '## Typical order'
                'Each step saves a .mat file that the next step loads, so run the steps of a card from left to right. Signal Characterization comes last: use it on the trials saved by **LDF Process**, on the ERP exported by **LFP analysis**, or on the LFP saved by **Extract Ephys**, to turn responses into numbers.'
                '## Project folders'
                '* **Import folder**: where Load dialogs start (your raw data).'
                '* **Export folder**: where Save / Export dialogs start (your results).'
                '* Both are stored as MATLAB preferences (`NeuroAnalyzer.ImportDir`, `NeuroAnalyzer.ExportDir`), so they are remembered between sessions. The launcher asks for them the first time; change them with **Set folders**.'
                '## Requirements'
                '* MATLAB R2021a or later.'
                '* **Signal Processing Toolbox**: filtering, downsampling and spike detection (LDF Process, Extract Ephys, MUA analysis).'
                '* **Image Processing Toolbox**: drawing a ROI or line in ROI analysis.'
                '* **TDT MATLAB SDK**: only for Extract Ephys. See README, section "Install the TDT SDK".'
                'The launcher status bar shows whether the Signal Processing Toolbox and the TDT SDK were found.'
                '## Where to get help'
                'Every window has a **? Help** button that opens its topic here. To report a bug or ask for a feature, click **Report a problem** or open https://github.com/alesuarez92/NeuronalDataAnalyzerLab/issues. Include your MATLAB version, the window, what you clicked and the exact message from the status bar or error dialog.'};
            t.trouble = {
                'Undefined function ''Main'', ''UIKit'' or ''HelpApp''', 'The toolbox is not on the MATLAB path. Run `addpath(genpath(''<toolbox folder>''))`, optionally `savepath`, then launch with `NeuroAnalyzer`.'
                'Launcher warns "Signal Processing Toolbox was not found"', 'Filtering, downsampling and spike detection will fail. Install it from Home → Add-Ons, or check your license with `ver`.'
                'Extract Ephys: "TDTbin2mat" undefined', 'The TDT MATLAB SDK is missing. Follow README → "Install the TDT SDK" (place `TDTMatlabSDK/` under `Utilities/`).'
                'A file dialog does not appear', 'It may have opened behind the app window; check the taskbar / Dock.'
                'Figures in this help say "not found"', 'Launch with `NeuroAnalyzer` from the toolbox folder so the `docs/` folder can be found.'};
            t.images = {};
        end

        %% topicLDFExtract - Extract LDF Data
        function t = topicLDFExtract()
            t = mkTopic('LDF Extract', 'LDF pipeline · step 1 of 3', ...
                'Load a LabChart LDF export, keep the time range of the experiment and save it.');
            t.quick = {
                '**1 Load LDF export**: click **Load file...** and choose the LabChart .mat export. Stimulus (channel 6) and LDF (channel 8) are plotted; file name, sampling rate and duration are shown.'
                '**2 Choose time range**: type **Start** and **End** (s), click **Pick on plot** and click twice (start, end) on either plot, or click **Full range**.'
                '**3 Crop**: click **Crop to range**. The cropped signals replace the full recording in the plots.'
                '**4 Save**: click **Save cropped data...** and choose a file name. Open this file next in **LDF Process**.'};
            t.demo = {
                '* **Data**: LabChart-style export, 8 channels, 300 s at 1000 Hz. Channel 6 = stimulus: 9 pulses of 5 s every 30 s from t = 30 s. Channel 8 = LDF: ~120 PU baseline with slow drift, vasomotion (0.1 Hz), a cardiac ripple (6 Hz) and noise.'
                '* **What you should see**: after each stimulus pulse the LDF rises by about **+30 PU**, peaking about **4 s after the onset**, and returns to baseline within ~12 s.'
                '* **Try**: crop **20 to 280 s** (this is exactly what the LDF Process demo file contains) and save; the cropped plots start at t = 0 with the first pulse at 10 s.'};
            t.inputs = {
                'LabChart export `.mat` with `data` (all channels, concatenated), `datastart` and `dataend` (start / end index of each channel)'
                'Optional: `samplerate` (Hz; 1000 Hz is assumed when missing), `titles`, `unittext`, comments'
                'Stimulus = channel 6, LDF = channel 8'};
            t.outputs = {
                'Cropped `.mat` with `stim` (stimulus), `LDF` (flow), `t` (time in s, 0 at the crop start) and `Fs` (Hz)'};
            t.details = {
                'The stimulus and LDF channels are cut out of `data` using `datastart` / `dataend`. Sample k is at time (k − 1) / Fs.'
                'The range must satisfy 0 ≤ Start < End ≤ duration. Cropping keeps samples round(Start·Fs)+1 to round(End·Fs)+1.'
                'Loading a new file discards the previous crop, so a stale crop can never be saved by mistake.'};
            t.trouble = {
                '"Not a valid LDF export: file must contain data, datastart, and dataend"', 'The file is not a LabChart export. Export the recording from LabChart as a MATLAB .mat file.'
                '"Channel indices out of range"', 'The file has fewer than 8 channels. The stimulus must be on channel 6 and the LDF on channel 8.'
                'Sampling rate shows 1000 Hz but the recording used another rate', '`samplerate` is missing from the export; re-export with it, otherwise every time axis is wrong.'
                '"Start time must be less than End time" / "Range must be within …"', 'Check the Start and End values (seconds, inside the recording).'};
            t.images = {'LDFExtractWorkflow.png', 'LDFExtractPrinciple.png'};
        end

        %% topicLDFProcess - Process LDF Data (filter, segment)
        function t = topicLDFProcess()
            t = mkTopic('LDF Process', 'LDF pipeline · step 2 of 3', ...
                'Downsample and filter the cropped LDF, cut trials around each stimulus and save them.');
            t.quick = {
                '**1 Load cropped LDF**: click **Load file...** and choose the file saved by LDF Extract.'
                '**2 Filter / downsample (optional)**: click **Settings...**, choose downsampling and filter, click **Apply**. The Filter response tab shows the filter; **Undo** returns to the loaded data. See the **Filtering** topic.'
                '**3 Segment trials**: set **Stim threshold** (shown as a dashed line on the stimulus), **Pre-onset** and **Post-onset** (s) and **Min interval** (s), then click **Segment trials**. All trials and the mean ± SD appear in the Trials tab.'
                '**4 Save trials**: click **Save trials...**. Choosing an existing trials file appends the new trials to it (time axes must match). Open the file(s) next in **LDF Average**.'};
            t.demo = {
                '* **Data**: the cropped demo recording (20–280 s of the LDF export, 1000 Hz): 9 stimulus pulses of 5 s, the first at 10 s, then every 30 s.'
                '* **Try**: downsample 10x, low-pass ~1 Hz (removes the 6 Hz cardiac ripple), then segment with pre = 5 s and post = 20 s.'
                '* **What you should get**: 8 complete trials (the last pulse is too close to the end for a 20 s window). The mean response rises after 0 s and **peaks ~4 s after onset at ~+30 PU** above a ~120 PU baseline.'};
            t.inputs = {
                '`.mat` from LDF Extract with `stim`, `LDF`, `t`, `Fs` (all four are required)'};
            t.outputs = {
                '`.mat` with `segmentedLDF` (trials × samples), `segmentedTime` (s, 0 = stimulus onset, negative = before) and `Fs`'};
            t.details = {
                '## Filter / downsample'
                '* Downsample: 1x, 2x, 5x or 10x. The LDF is decimated with an anti-aliasing filter; the stimulus is subsampled.'
                '* Filter type: None, Low-pass, High-pass, Band-pass or Notch; design Butterworth, Chebyshev I or FIR; cutoff(s) in Hz and order.'
                '* Processing always starts from the loaded data, so applying new settings never filters an already filtered signal.'
                '## Segment trials'
                '* Onsets are the samples where the stimulus rises above the threshold; onsets closer than the minimum ISI to the previous one are ignored.'
                '* Each trial runs from onset − pre to onset + post. Trials that would run past the start or end of the recording are skipped.'};
            t.trouble = {
                '"Invalid LDF file. Missing variable(s): …"', 'Load the file saved by LDF Extract (it contains stim, LDF, t, Fs), not the raw LabChart export.'
                'No trials found', 'The threshold is above the stimulus amplitude or the minimum ISI is too long. Look at the stimulus plot and lower the threshold.'
                'Filter error / cutoff must be below Nyquist', 'Cutoffs must be below half the sampling rate after downsampling (e.g. 1000 Hz with 10x → Nyquist 50 Hz).'
                'Filtering fails with an undefined function (butter, filtfilt, decimate)', 'The Signal Processing Toolbox is missing (see Welcome → Requirements).'
                '"Time axes do not match" when saving', 'You are appending to a file made with different pre/post times or sampling rate. Save to a new file instead.'};
            t.images = {'LDFProcessWorkflow.png', 'LDFProcessPrinciple.png'};
        end

        %% topicFiltering - How low-pass, high-pass, band-pass, notch work; order; Nyquist
        function t = topicFiltering()
            t = mkTopic('Filtering', 'LDF pipeline · reference', ...
                'How the digital filters in LDF Process (and Extract Ephys) change a signal.');
            t.quick = {
                'In LDF Process, click **Settings** (step 2).'
                'Choose **Downsample** first: it sets the new sampling rate and therefore the highest usable cutoff (Nyquist = half the rate).'
                'Pick the **filter type** and enter the **cutoff(s)** in Hz; start with order 4.'
                'Click **Apply** and compare the filtered trace with the original in the plots; use **Undo** to try other settings.'};
            t.demo = {
                '* **Data**: the cropped demo LDF (1000 Hz). Besides the ~+30 PU responses it contains a slow drift (period 400 s), vasomotion at **0.1 Hz** (±3 PU), a cardiac ripple at **6 Hz** (±1.5 PU) and white noise.'
                '* **Low-pass 1 Hz** (after 10x downsampling): the 6 Hz ripple and most noise disappear, the responses keep their shape and timing (zero-phase filtering: the peak stays ~4 s after onset).'
                '* **High-pass 0.2 Hz**: removes drift and vasomotion but also shrinks and distorts the slow (~5 s wide) responses, a good example of a cutoff that is too high for LDF.'};
            t.inputs = {'A signal and its sampling rate (after downsampling)'};
            t.outputs = {'The filtered signal (zero-phase filtering: no time shift)'};
            t.details = {
                'Filters remove or keep certain frequencies in a signal:'
                '* **Low-pass**: keeps low frequencies, removes high ones (e.g. smooths noise). One cutoff: frequencies above it are attenuated.'
                '* **High-pass**: removes low frequencies, keeps high ones (e.g. removes slow drift). One cutoff: frequencies below it are attenuated.'
                '* **Band-pass**: keeps the band between a low and a high cutoff, e.g. 0.5–5 Hz for LDF.'
                '* **Notch**: removes a narrow band, e.g. 50 / 60 Hz line noise.'
                '**Order**: a higher order gives a steeper roll-off (sharper cutoff) but can ring or become unstable; 2–4 is usually enough.'
                '**Nyquist**: cutoffs must be below half the sampling rate. With downsampling, use the new rate: 1000 Hz / 10 = 100 Hz → cutoffs < 50 Hz.'
                '**Design**: Butterworth has a flat pass-band; Chebyshev I is steeper but has pass-band ripple; FIR is always stable but needs a high order for a sharp cutoff.'};
            t.trouble = {
                'Cutoff rejected / filter unstable', 'Keep cutoffs between 0 and Nyquist, low < high for band-pass, and lower the order.'
                'The filtered signal looks shifted or distorted at the edges', 'Edge transients are normal for strong filters; crop a little extra in LDF Extract so trials are away from the edges.'
                'Undefined function butter / cheby1 / fir1', 'Install the Signal Processing Toolbox.'};
            t.images = {'FilterWorkflow.png', 'FilterHowItWorks.png', 'FilterPrinciple.png'};
        end

        %% topicLDFAverage - Average LDF Viewer
        function t = topicLDFAverage()
            t = mkTopic('LDF Average', 'LDF pipeline · step 3 of 3', ...
                'Pool the trials of one or more trial files and plot the grand average (mean ± SD).');
            t.quick = {
                '**1 Load trial files**: click **Add files...** and select one or more files saved by LDF Process (multi-select). You can add more files later; **Clear all** starts over.'
                '**2 Options**: tick **Relative to baseline** to subtract each trial''s pre-stimulus mean.'
                '**3 Grand average**: click **Plot grand average** to see the mean ± SD across all trials.'};
            t.demo = {
                '* **Data**: `demo_ldf_trials.mat`, 8 trials from −5 to 20 s at 10 Hz (0 = stimulus onset).'
                '* **What you should get**: the grand average is flat before 0 s (~120 PU), rises after onset and **peaks ~4 s after onset at ~+30 PU**, then returns to baseline by ~12–15 s. The SD band shows the trial-to-trial vasomotion (a few PU).'
                '* With **Relative to baseline** the curve starts at ~0 PU and peaks at ~+30 PU.'};
            t.inputs = {'One or more `.mat` files with `segmentedLDF` and `segmentedTime` (from LDF Process)'};
            t.outputs = {'Plots of all trials and of the grand average (mean ± SD); the file list shows how many trials came from each file'};
            t.details = {
                'Files are pooled only when their `segmentedTime` is identical (same pre/post window and sampling rate). Files with a different time axis are skipped and reported.'
                '**Relative to baseline** subtracts from each trial the mean of its samples with t < 0 (before the stimulus). It needs a pre-stimulus window (pre > 0 in LDF Process).'};
            t.trouble = {
                'A file was skipped: time axes do not match', 'Re-segment it in LDF Process with the same pre/post times and downsampling as the other files.'
                'A file adds no trials', 'It does not contain segmentedLDF / segmentedTime; load the file saved by **Save trials**.'
                '"No pre-stimulus baseline available"', 'The trials start at t = 0. Segment again with pre > 0 s.'};
            t.images = {'LDFAverageWorkflow.png', 'LDFAveragePrinciple.png'};
        end

        %% topicEphysExtract - Extract Ephys (TDT, LFP, MUA)
        function t = topicEphysExtract()
            t = mkTopic('Ephys Extract', 'Electrophysiology · step 1', ...
                'Load a TDT recording and extract the LFP and MUA signals for analysis.');
            t.quick = {
                '**1 Load TDT tank**: click **Load TDT tank…** and select the tank / block folder. The channel lists are filled from the recording.'
                '**2 Choose channels**: pick the stimulus (Whis) channel and one or more raw (xRAW) channels (**All** / **None** help).'
                '**3 Process**: optionally **Plot RAW**; then **Process LFP…** (low-pass, 60 Hz notch, downsample) and/or **Process MUA…** (band-pass, default 300–3000 Hz).'
                '**4 Save**: **Save LFP…** / **Save MUA…**, choose which channels to keep and a file name (default `<tank>_LFP.mat` / `<tank>_MUA.mat`). Open these files in **LFP analysis** / **MUA analysis**.'};
            t.demo = {
                '* **Data**: a TDT-like demo block (30 s): 8 raw channels (`xRAW`, 24414 Hz, electrodes 100 µm apart) and the whisker stimulus (`Whis`: 20 ms pulses every 2 s from 1 s, 15 stimuli). The demo tank is read by a built-in stand-in, so the TDT SDK is not needed for it.'
                '* **Process LFP** (low-pass, downsample to ~1017 Hz): each stimulus evokes a negative deflection at **15 ms** and a positive one at **40 ms**, largest on **channel 4** and weaker with distance from it.'
                '* **Process MUA** (300–3000 Hz): spikes on **channels 3–5** (two units on channel 4, one on channel 5), denser in the 50 ms after each stimulus. Save both to try LFP and MUA Analysis.'};
            t.inputs = {
                'TDT tank / block folder containing the `Whis` (stimulus) and `xRAW` (raw neural) streams'
                'Requires the TDT MATLAB SDK (`TDTbin2mat`) under `Utilities/TDTMatlabSDK/`'};
            t.outputs = {
                'LFP `.mat`: `lfp_data` (channels × samples), `lfp_channels`, `lfp_fs`, `t_lfp`, `stim_data`, `stim_fs`, `t_stim`'
                'MUA `.mat`: `mua_data`, `mua_channels`, `mua_fs`, `t_mua`, `stim_data`, `stim_fs`, `t_stim`, `filterParams`'};
            t.details = {
                '## LFP'
                '* Optional downsampling by an integer factor after an anti-aliasing low-pass. The saved `lfp_fs` is the **actual** rate: TDT''s 24414.0625 Hz / 24 = 1017.25 Hz, not the requested 1000 Hz.'
                '* Then a 4th-order Butterworth low-pass at the chosen cutoff and an optional 60 Hz notch (zero-phase).'
                '## MUA'
                '* Zero-phase band-pass (preset: 300–3000 Hz, Butterworth, order 4, or custom). The saved signal is the band-passed trace used for spike detection; the smoothed, rectified envelope is only for display.'
                'The channels and stimulus channel saved are the ones used when you clicked Process, even if the selection changed afterwards.'};
            t.trouble = {
                '"Undefined function TDTbin2mat" or tank does not load', 'Install the TDT MATLAB SDK: README → "Install the TDT SDK". The folder must be `Utilities/TDTMatlabSDK/`.'
                '"The selected tank does not contain the required Whis and xRAW streams"', 'Select the block folder of a recording that stored both streams (stimulus as Whis, raw data as xRAW).'
                '"Downsample rate must be below the raw rate"', 'Enter a target rate (Hz) lower than the raw sampling rate shown after loading.'
                'Filtering fails (butter, filtfilt, iirnotch undefined)', 'The Signal Processing Toolbox is missing.'
                'Save is disabled', 'Run Process LFP / Process MUA first; Save stores the last processed result.'};
            t.images = {'EphysExtractWorkflow.png', 'EphysExtractPrinciple.png'};
        end

        %% topicLFPAnalysis - Process LFP (ERP, CSD)
        function t = topicLFPAnalysis()
            t = mkTopic('LFP Analysis', 'Electrophysiology · step 2 (LFP)', ...
                'Average the LFP around each stimulus (ERP) and compute current source density (CSD).');
            t.quick = {
                '**1 Load LFP file**: click **Load LFP file…** and choose the LFP file saved by Extract Ephys.'
                '**2 Channels**: select the channels to analyse (**All** / **None**).'
                '**3 ERP analysis**: click **Run ERP…**, set pre- and post-stimulus time (s), stimulus threshold and minimum ISI (s), click OK. The number of averaged epochs is reported.'
                '**4 CSD**: enter **Spacing (µm)** and the **Channel order** from top to bottom (at least 3 channels of the last ERP), then click **Compute CSD**.'
                '**5 Export**: click **Export ERP / CSD…** to save a .mat that Signal Characterization can read.'};
            t.demo = {
                '* **Data**: `demo_lfp.mat`, 8 channels at 1017.25 Hz, 30 s, 100 µm spacing; 15 stimuli every 2 s from 1 s.'
                '* **ERP** (e.g. pre 0.05 s, post 0.2 s): 15 epochs; **N1 (negative) at ~15 ms** (about −120 µV at channel 4) and **P2 (positive) at ~40 ms**; both are **largest at channel 4** and fall off over ~150 µm (channels 2–6).'
                '* **CSD** (spacing 100 µm, order 1–8): a **current sink at channel 4** at ~15 ms, flanked by sources above and below (channels 2–3 and 5–6).'};
            t.inputs = {'LFP `.mat` from Extract Ephys: `lfp_data`, `stim_data`, `t_lfp`, `t_stim`, `lfp_fs`, `stim_fs` (all required)'};
            t.outputs = {
                'Tabs: Stimulus (threshold and detected onsets), ERP overlay, ERP per channel (mean ± SD), CSD map'
                'Export `.mat`: `t`, `y` (ERP averaged over channels), `erp_avg`, `erp_std`, `erp_channels`, `n_epochs`, `onset_times`, `erp_params`, and `csd` when computed'};
            t.details = {
                '## ERP'
                '* Stimulus onsets are upward crossings of the threshold by the mean-subtracted stimulus; onsets closer than the minimum ISI to the previous one are dropped.'
                '* Each epoch runs from onset − pre to onset + post. Epochs that would run past the recording edges are excluded (not zero-filled); the ERP is the mean and SD of the valid epochs.'
                '## CSD'
                '* CSD is the negative second spatial derivative of the ERP across the ordered channels divided by spacing²; the first and last rows are copied from their neighbours.'
                '* Sinks (current flowing into cells) and sources appear as opposite colours across depth; use it with a linear probe and the true channel order.'};
            t.trouble = {
                '"Missing variable(s)" when loading', 'Load the file written by Extract Ephys → Save LFP, not the MUA file or a raw tank.'
                '"No stimulus onsets detected. Check the threshold."', 'Look at the stimulus tab and set the threshold between baseline and stimulus amplitude (the stimulus is mean-subtracted first).'
                '"No complete epochs"', 'All onsets are too close to the recording start / end for the pre/post window. Shorten pre/post.'
                '"CSD needs at least 3 channels" / order error', 'Run the ERP with ≥ 3 channels and list only those channels in the CSD order.'};
            t.images = {'LFPAnalysisWorkflow.png', 'LFPAnalysisCSD.png', 'LFPAnalysisPrinciple.png'};
        end

        %% topicMUAAnalysis - Process MUA (spike sort, rate)
        function t = topicMUAAnalysis()
            t = mkTopic('MUA Analysis', 'Electrophysiology · step 2 (MUA)', ...
                'Detect and sort spikes in the MUA signal, check their quality and plot firing rates.');
            t.quick = {
                '**1 Load MUA file**: click **Load MUA file...** and choose the MUA file saved by Extract Ephys. Channels and whether a stimulus is present are shown.'
                '**2 Channel & segments**: choose the channel; optionally tick **Segment by stimulation onsets** (minimum ISI, threshold, pre / post-stimulus times) and pick a segment.'
                '**3 Spike sorting**: click **Configure...** (detection method, threshold, polarity, filtering, features, clustering, drift correction) and then **Run**.'
                '**4 Clusters**: select the clusters to show (**Select all** / **Clear**) and read the quality summary. Result tabs: Signal & spikes, Waveforms, Clusters (feature space), Spike rate, Quality.'
                '**5 Export**: click **Save results...** to write spike times, cluster IDs, the sorting parameters and quality measures to .mat.'};
            t.demo = {
                '* **Data**: `demo_mua.mat`, channels 3–5 at 24414 Hz, 30 s, stimulus every 2 s from 1 s. Three units with negative spikes: **unit 1 (~90 µV) and unit 2 (~50 µV) on channel 4**, **unit 3 (~110 µV) on channel 5** (seen weaker on channel 4). Noise ~10 µV.'
                '* The demo selects **channel 4** and detection **MAD, k = 4, negative polarity**; click **Run**.'
                '* **What you should get**: **2 units on channel 4** with clearly different amplitudes (and 1 on channel 5). In the Spike rate tab (bin ~0.05 s), rates jump **5–55 ms after each stimulus** (baseline ~6–10 Hz, evoked 40–80 Hz); ISI violations should be ~0% (2 ms refractory).'};
            t.inputs = {
                'MUA `.mat` from Extract Ephys: `mua_data`, `mua_fs`, `t_mua`, `mua_channels`'
                'Optional `stim_data`, `stim_fs`, `t_stim` (needed to segment by stimulus)'};
            t.outputs = {'Plots: signal with detected spikes, waveforms, clusters in feature space, spike rate, quality (ISI histograms, alignment check)'
                'Saved `.mat`: `SpikeResults` (spike times, cluster IDs, waveforms), `SpikeSortParams`, `clusterQuality`, `info`'};
            t.details = {
                '## Detection'
                'Spikes are detected where the (optionally band-pass filtered) signal crosses a threshold. The threshold is a multiplier (e.g. 3.5×) of the noise level. Polarity: positive, negative or both.'
                '* **Standard**: mean + k·SD.'
                '* **MAD**: median + k·MAD (robust to large spikes).'
                '* **NEO**: nonlinear energy operator ψ[n] = x[n]² − x[n−1]·x[n+1], thresholded on that scale; picks up either polarity.'
                '* **Rolling MAD**: MAD in a moving window (for drifting noise).'
                '* **Percentile**: the 99.9th percentile.'
                'A short dead time (~0.3 ms) avoids counting a spike twice; the refractory period (ms) is used for the per-cluster ISI quality check.'
                '## Sorting'
                'For each spike a waveform snippet is aligned and features are computed (PCA, ICA*, waveform, wavelet* or t-SNE; *only offered when FastICA / the Wavelet Toolbox is available). K-means and GMM try 2–10 clusters and keep the number with the best mean silhouette; DBSCAN is density based (epsilon auto-tuned if left empty) and labels unclustered spikes 0 = noise. Optional drift correction matches clusters across time bins.'};
            t.trouble = {
                '"No stimulation data in the loaded file; cannot segment"', 'The MUA file has no stim_data; save it again from Extract Ephys (it stores the stimulus channel).'
                'Very few or no spikes', 'Lower the threshold multiplier, check the polarity, or enable filtering before detection.'
                'Many ISI violations in one cluster', 'It probably mixes units or noise: try another feature method, more clusters, or a higher threshold.'
                'ICA / Wavelet not in the list', 'They need FastICA or the Wavelet Toolbox; use PCA instead.'
                'Detection fails (findpeaks / butter undefined)', 'Install the Signal Processing Toolbox.'};
            t.images = {'MUAAnalysisWorkflow.png', 'MUAAnalysisPrinciple.png'};
        end

        %% topicROIAnalysis - ROI / Coregistered Image Analysis
        function t = topicROIAnalysis()
            t = mkTopic('ROI Analysis', 'Imaging', ...
                'Measure a ROI or a line over time in a stack of coregistered frames (2-photon, gCaMP, blood-flow imaging).');
            t.quick = {
                '**1 Load stack**: click **Load stack** and choose a .mat or multi-frame TIFF. The first frame is shown with the size, frame count and time source.'
                '**2 Preprocess (optional)**: tick **B&W 256 levels**, **Smooth** and/or **Normalize each frame**. They are applied, in that order, when you click Run.'
                '**3 Draw ROI or line**: click **Draw ROI** and drag a rectangle, or **Draw line** and drag a line (across the vessel for diameter). You can move / resize them afterwards.'
                '**4 Analysis**: choose the **Method** (for ΔF/F also the baseline frames) and click **Run**. The result is plotted below the frame.'
                '**5 Export**: click **Export results** to save a .csv (time + values) or a .mat (results, ROI / line and settings).'};
            t.demo = {
                '* **Data**: `demo_imaging.mat`, 96 × 96 px, 150 frames at 10 Hz (15 s). A dark vertical **vessel at x = 60** whose **diameter oscillates 12 ± 3 px (9–15 px) every 5 s**; a bright **red blood cell moving down 2 px/frame** (20 px/s); a **cell at (24, 30), radius 6 px** with calcium transients (ΔF/F ≈ 1) at **3, 7 and 11 s**. The cell''s `roiMask` is in the file.'
                '* The demo selects **ΔF/F** with that mask (baseline = first 30 frames) and a line across the vessel from (45, 70) to (75, 70).'
                '* **ΔF/F**: flat ~0 until 3 s, then **three peaks of ~1 at 3, 7 and 11 s**, each decaying in ~1–2 s.'
                '* **Vessel diameter** (same line): a sine between **~9 and ~15 px with a 5 s period**. **Kymograph** along the vessel (e.g. from (60, 5) to (60, 90)): slanted streaks with a slope of **2 px per frame**.'};
            t.inputs = {
                '`.mat` with `stack` or `frames` (H × W × N grayscale or H × W × 3 × N RGB; otherwise the first variable is used)'
                'Optional in the .mat: `timeVec` or `t` (one time per frame), `roiMask` (logical H × W, used when no ROI is drawn)'
                'Multi-frame TIFF: RGB frames are converted to grayscale (mean of the colour channels); time = frame index'};
            t.outputs = {
                '.csv: `Time` plus one column per measure (Intensity, Movement, DFF, Speed, Diameter_px); for a kymograph, a matrix (first row = time)'
                '.mat: struct `results` with the series, `kymograph`, `roiMask`, `lineStart` / `lineEnd` and the preprocessing settings'};
            t.details = {
                '## Methods using the ROI'
                '* **Brightness**: mean intensity in the ROI per frame.'
                '* **Movement**: mean absolute frame-to-frame difference in the ROI.'
                '* **Both**: brightness (left axis) and movement (right axis).'
                '* **ΔF/F (gCaMP)**: (F − F0) / F0 of the ROI intensity, F0 = mean of the first N frames (default 30).'
                '* **Speed (flow)**: frame-to-frame motion magnitude in the ROI, a flow / speed proxy (first frame NaN).'
                '## Methods using the line'
                '* **Kymograph**: intensity sampled along the line in every frame → a space × time image; slanted streaks show propagation or flow direction.'
                '* **Vessel diameter**: width (FWHM, pixels) of the intensity profile along the line in every frame. Draw the line across the vessel.'
                '## Preprocessing'
                '* **B&W 256**: rescale to 256 grey levels (uint8), e.g. for fluorescence intensity.'
                '* **Smooth**: Gaussian filter, sigma 2 px, on every frame.'
                '* **Normalize**: every frame scaled to 0–1 by its own min / max (removes global brightness changes, so do not use it for Brightness or ΔF/F).'};
            t.trouble = {
                '"Could not draw a rectangle / line"', 'drawrectangle / drawline need the Image Processing Toolbox. Without it, save a logical `roiMask` in the .mat for ROI methods.'
                'Run is disabled', 'The chosen method needs a ROI (Brightness, Movement, Both, ΔF/F, Speed) or a line (Kymograph, Vessel diameter); the step 3 card says which is missing.'
                '"roiMask size does not match"', 'The mask must be H × W, the same size as one frame.'
                'Time axis shows frames, not seconds', 'Add a `timeVec` (or `t`) with one value per frame to the .mat.'
                'Load is slow / out of memory', 'Large TIFFs are read frame by frame into memory as double; crop or bin the stack first.'};
            t.images = {'ROIAnalysisWorkflow.png', 'ROIAnalysisPrinciple.png'};
        end

        %% topicSignalCharacterization - Signal Characterization
        function t = topicSignalCharacterization()
            t = mkTopic('Signal Characterization', 'Response features', ...
                'Turn each response into numbers: latency, onset delay, FWHM, AUC, rise / decay time, amplitude.');
            t.quick = {
                '**1 Load data**: click **Load .mat file**. The data type is detected (LDF segments, ERP / average, time series) and the number of series, Fs and time range are shown; the first series is plotted.'
                '**2 Parameters**: set the stimulus onset **t0** (s), the **baseline** window (s) and the response **direction**. The plot shows t0 (dashed), the baseline window (shaded) and the detected peak and FWHM, so you can check them before extracting.'
                '**3 Features**: select the features (Ctrl/Cmd-click for several) and click **Extract features**.'
                '**4 Export**: check the table (click a row to plot that series) and click **Export to CSV / MAT**.'};
            t.demo = {
                '* **Data**: `demo_ldf_trials.mat`, 8 LDF trials from −5 to 20 s at 10 Hz (0 = stimulus onset). The demo sets t0 = 0, direction Auto, the baseline to −5–0 s and selects every feature.'
                '* **Expected per trial** (true response: ~120 PU baseline + 30 PU gamma-shaped hyperemia): **peak latency ≈ 4 s**, **peak amplitude ≈ 30 PU**, onset delay (50%) ≈ 1.9 s, FWHM ≈ 5.5 s, rise time (10–90%) ≈ 2.2 s, decay to 50% ≈ 3.4 s; positive direction.'
                '* Trials differ by a few PU / tenths of a second because of vasomotion and noise, which is why the mean over trials is the number to report.'};
            t.inputs = {
                'LDF trials from LDF Process: `segmentedLDF`, `segmentedTime` (one series per trial)'
                'LFP from Extract Ephys: `lfp_data`, `t_lfp` (mean over channels = one series)'
                'ERP export from LFP analysis, or any `.mat` with `t` and `y` (or `t` and `LDF`)'};
            t.outputs = {
                '.csv: one row per series, columns Trial_Channel, PeakLatency_s, OnsetDelay_s, FWHM_s, AUCpos, AUCneg, RiseTime_s, DecayTime_s, PeakAmp, Integral'
                '.mat: `data` (the table as a cell array) and `colNames`'};
            t.details = {
                '## Reference level and direction'
                '* **Baseline**: the mean of the signal inside the baseline window is the reference for every feature. If the window holds no samples, the pre-onset mean is used; if end ≤ start, the first 0.05 s of the trace. For trials that start before t0 the window is set to the pre-stimulus part when the file is loaded.'
                '* **Direction**: Positive (peaks), Negative (troughs) or Auto (negative when the post-onset deflection below baseline is larger than above).'
                '## Features (measured after t0)'
                '* **Peak latency**: time from t0 to the peak.'
                '* **Onset delay (50%)**: time from t0 until the response first reaches 50% of the baseline-to-peak amplitude.'
                '* **FWHM**: width of the part of the response around the peak that stays beyond half of the baseline-to-peak amplitude.'
                '* **AUC positive / negative**: area above / below the baseline over the whole trace.'
                '* **Rise time**: 10% → 90% of the baseline-to-peak amplitude, before the peak.'
                '* **Decay time**: from the peak until the signal returns past 50%.'
                '* **Peak amplitude**: peak minus baseline.'
                '* **Stim–response integral**: integral of the signal from t0 to the end.'
                'A feature that cannot be measured (e.g. the signal never returns to 50%) is NaN.'};
            t.trouble = {
                '"… does not contain a supported format"', 'The file needs segmentedLDF + segmentedTime, lfp_data + t_lfp, or t + y (or t + LDF). The alert lists the variables it found.'
                'Series skipped (t and y lengths differ)', 'Each y must have one value per time point; check the saved variables.'
                'Features are NaN', 'Check t0 (inside the time range?) and the direction; the plot shows where the peak was found.'
                'Peak found on the wrong deflection', 'Set Direction to Positive or Negative instead of Auto.'};
            t.images = {'SignalCharacterizationWorkflow.png', 'SignalCharacterizationPrinciple.png'};
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% mkTopic - Empty topic struct with title, group (breadcrumb) and summary
function t = mkTopic(title, group, summary)
    t = struct('title', title, 'group', group, 'summary', summary, ...
        'quick', {{}}, 'demo', {{}}, 'inputs', {{}}, 'outputs', {{}}, 'details', {{}}, ...
        'detailsTitle', 'How it works', ...
        'trouble', {cell(0, 2)}, 'images', {{}});
end

%% navLabel - Topic label in the navigation list (reference topics indented)
function s = navLabel(title, group)
    if contains(group, 'reference')
        s = ['      ' title];
    else
        s = title;
    end
end

%% dropStepNo - '**1 Load data**: ...' -> '**Load data**: ...' (the list numbers the steps)
function s = dropStepNo(s)
    s = regexprep(s, '^\*\*\d+ ', '**');
end

%% esc - Escape HTML special characters
function s = esc(s)
    s = strrep(s, '&', '&amp;');
    s = strrep(s, '<', '&lt;');
    s = strrep(s, '>', '&gt;');
end

%% fmt - Escape, then **bold**, `code` and https:// links
function s = fmt(s)
    s = esc(s);
    s = regexprep(s, '\*\*(.+?)\*\*', '<b>$1</b>');
    s = regexprep(s, '`(.+?)`', '<code>$1</code>');
    s = regexprep(s, '(https://[^\s<]+[^\s<.,)])', '<a href="$1" target="_blank">$1</a>');
end

%% bullets - <ul> from a cell of strings
function s = bullets(c)
    if isempty(c), s = '<p>-</p>'; return; end
    s = ['<ul>' strjoin(cellfun(@(x) ['<li>' fmt(x) '</li>'], c(:)', 'UniformOutput', false), '') '</ul>'];
end

%% markup - Details lines to HTML (## heading, * bullet, | table |, paragraph)
function html = markup(lines)
    out = {};
    inList = false; inTable = false; firstRow = false;
    for k = 1:numel(lines)
        ln = lines{k};
        isBullet = startsWith(ln, '* ');
        isRow = startsWith(ln, '|');
        if inList && ~isBullet, out{end+1} = '</ul>'; inList = false; end %#ok<AGROW>
        if inTable && ~isRow, out{end+1} = '</table>'; inTable = false; end %#ok<AGROW>
        if startsWith(ln, '## ')
            out{end+1} = ['<h3>' fmt(ln(4:end)) '</h3>']; %#ok<AGROW>
        elseif isBullet
            if ~inList, out{end+1} = '<ul>'; inList = true; end %#ok<AGROW>
            out{end+1} = ['<li>' fmt(ln(3:end)) '</li>']; %#ok<AGROW>
        elseif isRow
            if ~inTable, out{end+1} = '<table class="pl">'; inTable = true; firstRow = true; end %#ok<AGROW>
            cells = strtrim(strsplit(strtrim(ln(2:end-1)), '|'));
            if firstRow, tag = 'th'; else, tag = 'td'; end
            out{end+1} = ['<tr>' strjoin(cellfun(@(c) sprintf('<%s>%s</%s>', tag, fmt(c), tag), ...
                cells, 'UniformOutput', false), '') '</tr>']; %#ok<AGROW>
            firstRow = false;
        elseif ~isempty(strtrim(ln))
            out{end+1} = ['<p>' fmt(ln) '</p>']; %#ok<AGROW>
        end
    end
    if inList, out{end+1} = '</ul>'; end
    if inTable, out{end+1} = '</table>'; end
    html = strjoin(out, newline);
end

%% hex - UITheme RGB triplet (0-1) to #rrggbb
function s = hex(rgb)
    s = sprintf('#%02x%02x%02x', round(rgb * 255));
end
