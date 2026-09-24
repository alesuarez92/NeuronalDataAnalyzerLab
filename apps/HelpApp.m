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
                'LDF trials, TDT tank, LFP, MUA, imaging stack, oscillation LFP, advanced imaging, groups, ' ...
                'Intan / Open Ephys / NWB).'], folder), 'success');
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
                'Signal Characterization', 'SignalCharacterizationApp'; 'Batch processing', 'BatchApp'};
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
                HelpApp.topicSignalCharacterization(), HelpApp.topicBatch(), HelpApp.topicSessions()];
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
                '| demo_lfp_oscillations.mat | LFP Analysis (step 6) | demo_lfp.mat plus 6 Hz theta (40 µV, all channels) and a phase-locked 40 Hz burst (10 µV, 50–250 ms after each stimulus, channels 3–5) |'
                '| demo_imaging_advanced.mat | ROI Analysis | Jittered stack (±3 px), three cells with distinct event times, a pulsing vessel and a red blood cell crossing the diameter line |'
                '| groups/ | Signal Characterization (Groups & statistics) | 24 LDF trial files: the same 8 animals in Control, Stimulated and Drug (true peaks 18, 30 and 24 PU) |'
                '| formats/ | Ephys Extract | The first 6 s of demo channels 3–6 as an Intan .rhd, an Open Ephys binary folder and an NWB file |'
                'Each file also stores the ground truth in a `truth` variable. Use **Generate all demo files…** to write them to a folder (and optionally make it your Import folder), or the **Try it with demo data** button on any topic to open that window with its demo already loaded.'};
            t.inputs = {
                'LabChart .mat export (LDF)'
                'TDT tank / block folder, Intan .rhd, Open Ephys binary folder or NWB 2.x file (electrophysiology; TDT needs the TDT MATLAB SDK)'
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
                '**4 Save**: click **Save cropped data...** and choose a file name. Open this file next in **LDF Process**.'
                '**Session / report (optional)**: in step 4, **Save session…** stores the export file (with checksum), the range and the crop; **Open session…** redoes them; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'};
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
                '**4 Save trials**: click **Save trials...**. Choosing an existing trials file appends the new trials to it (time axes must match). Open the file(s) next in **LDF Average**.'
                '**Session / report (optional)**: in step 4, **Save session…** stores the file (with checksum), filter and segmentation settings; **Open session…** re-runs them; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'};
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
                '**3 Grand average**: click **Plot grand average** to see the mean ± SD across all trials.'
                '**Session / report (optional)**: in step 3, **Save session…** stores every trial file (with checksum) and the option; **Open session…** reloads them and redraws the average; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'};
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
                'Load a TDT, Intan, Open Ephys or NWB recording and extract the LFP and MUA signals for analysis.');
            t.quick = {
                '**1 Load recording**: choose the **Source** (TDT tank, Intan .rhd, Open Ephys folder or NWB file), click **Load recording…** and select the tank / block folder, the .rhd file, the Open Ephys recording folder (or any folder above it) or the .nwb file. The channel lists are filled from the recording.'
                '**2 Choose channels**: pick the **Stimulus channel** (TDT: Whis; Intan: DIGITAL-IN / ANALOG-IN; Open Ephys: TTL line / ADC; NWB: stimulus TimeSeries or trials) and one or more raw channels (**All** / **None** help).'
                '**3 Process**: optionally **Plot RAW**; then **Process LFP…** (low-pass, 60 Hz notch, downsample) and/or **Process MUA…** (band-pass, default 300–3000 Hz).'
                '**4 Save**: **Save LFP…** / **Save MUA…**, choose which channels to keep and a file name (default `<recording>_LFP.mat` / `<recording>_MUA.mat`). Open these files in **LFP analysis** / **MUA analysis**. **Export NWB…** writes the processed LFP and its stimulus channel as an NWB 2.x file (default `<recording>_LFP.nwb`).'
                '**Session / report (optional)**: in step 4, **Save session…** stores the recording (with checksum), channels and LFP / MUA settings; **Open session…** re-processes them; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'};
            t.demo = {
                '* **Data**: a TDT-like demo block (30 s): 8 raw channels (`xRAW`, 24414 Hz, electrodes 100 µm apart) and the whisker stimulus (`Whis`: 20 ms pulses every 2 s from 1 s, 15 stimuli). The demo tank is read by a built-in stand-in, so the TDT SDK is not needed for it.'
                '* **Process LFP** (low-pass, downsample to ~1017 Hz): each stimulus evokes a negative deflection at **15 ms** and a positive one at **40 ms**, largest on **channel 4** and weaker with distance from it.'
                '* **Process MUA** (300–3000 Hz): spikes on **channels 3–5** (two units on channel 4, one on channel 5), denser in the 50 ms after each stimulus. Save both to try LFP and MUA Analysis.'
                '* **Other formats**: choose a **Source** before **Try demo data** to open the first 6 s of demo channels 3–6 written as an Intan .rhd (20 kHz; stimulus on DIGITAL-IN-01 and a 1 V copy on ANALOG-IN-1), an Open Ephys folder (30 kHz; TTL line 1 and ADC1) or an NWB file (24414 Hz; the whisker stimulus TimeSeries and a trials table). There are 3 stimuli (1, 3 and 5 s). **Process LFP** gives 1000 Hz (Intan, Open Ephys) or 1017.25 Hz (NWB), with the evoked negative deflection at **15 ms**, largest on **RAW Ch 2** (= demo channel 4).'
                '* **Export NWB…** after Process LFP, then choose Source **NWB file** and **Load recording…** with the exported file: the LFP opens at its LFP rate with the same channel names and stimulus.'};
            t.inputs = {
                'TDT tank / block folder containing the `Whis` (stimulus) and `xRAW` (raw neural) streams (needs the TDT MATLAB SDK, `TDTbin2mat`, under `Utilities/TDTMatlabSDK/`)'
                'Intan RHD2000 `.rhd` file (file format 1.0–3.x, traditional single-file format)'
                'Open Ephys binary recording folder (GUI 0.5 or later: `structure.oebin`, `continuous.dat`, TTL events)'
                'NWB 2.x `.nwb` file with an ElectricalSeries in /acquisition or /processing'};
            t.outputs = {
                'LFP `.mat`: `lfp_data` (channels × samples), `lfp_channels`, `lfp_fs`, `t_lfp`, `stim_data`, `stim_fs`, `t_stim`'
                'MUA `.mat`: `mua_data`, `mua_channels`, `mua_fs`, `t_mua`, `stim_data`, `stim_fs`, `t_stim`, `filterParams`'
                'NWB `.nwb` (Export NWB…): LFP in volts in /processing/ecephys/LFP, the stimulus in /stimulus/presentation, electrodes with source channel names. Written with matnwb when installed, otherwise an NWB-style export (not validated).'};
            t.details = {
                '## LFP'
                '* Optional downsampling by an integer factor after an anti-aliasing low-pass. The saved `lfp_fs` is the **actual** rate: TDT''s 24414.0625 Hz / 24 = 1017.25 Hz, not the requested 1000 Hz.'
                '* Then a 4th-order Butterworth low-pass at the chosen cutoff and an optional 60 Hz notch (zero-phase).'
                '## MUA'
                '* Zero-phase band-pass (preset: 300–3000 Hz, Butterworth, order 4, or custom). The saved signal is the band-passed trace used for spike detection; the smoothed, rectified envelope is only for display.'
                'The channels and stimulus channel saved are the ones used when you clicked Process, even if the selection changed afterwards.'
                '## Recording formats'
                '* All sources are read into the same form: raw channels in volts plus a list of candidate stimulus channels, so processing and saving are identical for every format.'
                '* **Intan .rhd**: amplifier channels (0.195 µV per bit); stimulus candidates are the board digital inputs (0/1) and board ADC inputs (volts). The notch-filter setting is shown in the header but not applied.'
                '* **Open Ephys**: headstage channels (value × bit_volts); ADC channels become stimulus candidates; each TTL line becomes a 0/1 stimulus trace at the recording rate. AUX (accelerometer) channels are skipped.'
                '* **NWB**: the first ElectricalSeries (data × conversion); stimulus candidates are stimulus TimeSeries and trial / interval tables, aligned to the series start.'
                '## NWB export'
                '* Without matnwb the file is written by a built-in minimal writer that follows the NWB 2.7 layout but is **not validated** at run time and does not embed the schema. To check a file, run `nwbinspector` or `pynwb.validate` in Python. Subject metadata is not written by the app.'};
            t.trouble = {
                '"Undefined function TDTbin2mat" or tank does not load', 'Install the TDT MATLAB SDK: README → "Install the TDT SDK". The folder must be `Utilities/TDTMatlabSDK/`.'
                '"The selected tank does not contain the required Whis and xRAW streams"', 'Select the block folder of a recording that stored both streams (stimulus as Whis, raw data as xRAW).'
                '"Downsample rate must be below the raw rate"', 'Enter a target rate (Hz) lower than the raw sampling rate shown after loading.'
                'Filtering fails (butter, filtfilt, iirnotch undefined)', 'The Signal Processing Toolbox is missing.'
                'Save is disabled', 'Run Process LFP / Process MUA first; Save stores the last processed result.'
                '"not an Intan RHD2000 file: magic number …"', 'The file is not an Intan .rhd data file. Intan stimulation files (.rhs) are not supported.'
                '"holds only a header (no data blocks)"', 'The recording was saved as "one file per signal type" or "one file per channel" (info.rhd + .dat files). Save it in the traditional single-file .rhd format.'
                '"… is not a whole number of … data blocks"', 'The .rhd file is truncated (for example the recording was interrupted). Re-export it from the Intan software.'
                '"No structure.oebin found"', 'Choose the Open Ephys recording folder (…/Record Node */experiment*/recording*) or a folder above it. Only the binary format is supported; for the older "Open Ephys format" (.continuous files), re-save as binary.'
                '"not an HDF5 file" / "without the NWB root attribute nwb_version" / "No ElectricalSeries"', 'The file is not an NWB 2.x file with extracellular data. NWB 1.x files are not supported.'
                'The stimulus channel list shows "(no stimulus channel)"', 'The recording has no digital / analog input, TTL events or stimulus series. LFP / MUA files are still saved, with an all-zero stimulus.'
                'Export NWB says "NWB-style file (not validated)"', 'matnwb is not installed. The file follows the NWB 2.7 layout; install matnwb (https://github.com/NeurodataWithoutBorders/matnwb) to write it with the official schema classes, or validate it with nwbinspector.'
                'Loading a long recording runs out of memory', 'The whole recording is loaded (as for TDT tanks). Split long recordings, or export a shorter segment from the acquisition software.'};
            t.images = {'EphysExtractWorkflow.png', 'EphysExtractPrinciple.png'};
        end

        %% topicLFPAnalysis - Process LFP (ERP, CSD)
        function t = topicLFPAnalysis()
            t = mkTopic('LFP Analysis', 'Electrophysiology · step 2 (LFP)', ...
                'Average the LFP around each stimulus (ERP), compute current source density (CSD) and analyse oscillations (spectrum, spectrogram, ERSP / ITPC, band power).');
            t.quick = {
                '**1 Load LFP file**: click **Load LFP file…** and choose the LFP file saved by Extract Ephys.'
                '**2 Channels**: select the channels to analyse (**All** / **None**).'
                '**3 ERP analysis**: click **Run ERP…**, set pre- and post-stimulus time (s), stimulus threshold and minimum ISI (s), click OK. The number of averaged epochs is reported.'
                '**4 CSD**: enter **Spacing (µm)** and the **Channel order** from top to bottom (at least 3 channels of the last ERP), then click **Compute CSD**.'
                '**5 Export**: click **Export ERP / CSD…** to save a .mat that Signal Characterization can read.'
                '**6 Time–frequency**: choose the **Channel**, **Frequencies (Hz)** (lowest – highest), **Wavelet cycles**, **Epoch (s)** and **Baseline (s)**. The band table (delta 1–4, theta 4–8, alpha 8–13, beta 13–30, gamma 30–80 Hz) holds common conventions: edit the limits for your preparation and tick **Plot** for the bands to show. **Try oscillation demo** loads a demo with known theta and gamma oscillations and selects channel 4.'
                '**7 Time–frequency plots**: click **Spectrum** (power spectrum of the whole recording), **Spectrogram** (power over time with the stimuli marked), **ERSP / ITPC** (power change in dB and phase locking around each stimulus) and **Band power** (% change of each ticked band around the stimulus, mean ± SEM). Each opens its tab. ERSP and Band power use the stimulus onsets found with the ERP threshold (0.5 until you run the ERP).'
                '**Session / report (optional)**: in step 5, **Save session…** stores the file (with checksum) and the ERP, CSD and time–frequency settings and results; **Open session…** re-runs them; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'};
            t.demo = {
                '* **Data**: `demo_lfp.mat`, 8 channels at 1017.25 Hz, 30 s, 100 µm spacing; 15 stimuli every 2 s from 1 s.'
                '* **ERP** (e.g. pre 0.05 s, post 0.2 s): 15 epochs; **N1 (negative) at ~15 ms** (about −120 µV at channel 4) and **P2 (positive) at ~40 ms**; both are **largest at channel 4** and fall off over ~150 µm (channels 2–6).'
                '* **CSD** (spacing 100 µm, order 1–8): a **current sink at channel 4** at ~15 ms, flanked by sources above and below (channels 2–3 and 5–6).'
                '* **Oscillation demo** (**Try oscillation demo**): the same LFP plus **6 Hz theta** (40 µV, on every channel, not phase-locked to the stimuli) and a **40 Hz gamma burst** (10 µV, **50–250 ms after each stimulus**, **channels 3–5**, phase-locked). Channel 4 is chosen.'
                '* **Spectrum**: 1/f background with a clear **peak at ~6 Hz** (theta) and a small bump near **40 Hz**.'
                '* **Spectrogram** (2–80 Hz): a steady band at 6 Hz, and short 40 Hz patches just after each dashed stimulus line.'
                '* **ERSP / ITPC** (2–80 Hz, 7 cycles, baseline −0.4 to −0.1 s): about **+10 to +12 dB at 36–44 Hz between 50 and 250 ms**, ITPC ≈ **0.97** there, and ≈ 0 dB before the stimulus and after ~0.3 s. The ERP itself (N1 / P2) adds a brief broadband increase with high ITPC in the first ~50 ms. On channel 8 (no gamma) there is no 40 Hz increase. 14 of the 15 stimuli are used (the last epoch would run past the end of the recording), and 13 at the lowest frequencies.'
                '* **Band power** (channel 4): the ERP itself (N1 / P2) gives a very large, brief increase in the first ~50 ms in every band, so the y-axis is scaled to it (the status bar''s "largest change" therefore looks from 50 ms on); the **gamma burst** (roughly **+350 to +600 %**) is the plateau at 0.05–0.25 s. Theta also swings around the ERP. On **channel 8** (far from the ERP, no gamma) **theta stays flat** (~0 %): theta is not modulated by the stimuli.'};
            t.inputs = {'LFP `.mat` from Extract Ephys: `lfp_data`, `stim_data`, `t_lfp`, `t_stim`, `lfp_fs`, `stim_fs` (all required)'};
            t.outputs = {
                'Tabs: Stimulus (threshold and detected onsets), ERP overlay, ERP per channel (mean ± SD), CSD map'
                'Export `.mat`: `t`, `y` (ERP averaged over channels), `erp_avg`, `erp_std`, `erp_channels`, `n_epochs`, `onset_times`, `erp_params`, and `csd` when computed'
                'Time–frequency tabs: Spectrum (Welch PSD, log–log, bands shaded), Spectrogram (STFT power in dB, dashed stimulus onsets), ERSP / ITPC (dB vs baseline on a blue–white–red scale centred at 0; ITPC 0–1), Band power (% change vs baseline, mean ± SEM per band)'};
            t.details = {
                '## ERP'
                '* Stimulus onsets are upward crossings of the threshold by the mean-subtracted stimulus; onsets closer than the minimum ISI to the previous one are dropped.'
                '* Each epoch runs from onset − pre to onset + post. Epochs that would run past the recording edges are excluded (not zero-filled); the ERP is the mean and SD of the valid epochs.'
                '## CSD'
                '* CSD is the negative second spatial derivative of the ERP across the ordered channels divided by spacing²; the first and last rows are copied from their neighbours.'
                '* Sinks (current flowing into cells) and sources appear as opposite colours across depth; use it with a linear probe and the true channel order.'
                '## Time–frequency'
                '* **Spectrum**: Welch''s method, 2 s Hann segments with 50% overlap, each segment''s mean removed; density in units²/Hz, so the area under the spectrum equals the signal variance.'
                '* **Spectrogram**: short-time Fourier transform, 0.5 s Hann windows, 90% overlap; power in dB.'
                '* **ERSP / ITPC**: complex Morlet wavelets (unit energy; time resolution ≈ cycles / (2π·f) s). ERSP is 10·log10 of the trial-averaged power divided by the mean power in the baseline window; ITPC is the length of the mean unit phase vector across trials (0 = random phase, 1 = identical phase). At each frequency, trials whose wavelet would reach past the start or end of the recording are left out.'
                '* **Band power**: band-pass filter plus Hilbert envelope (done with the FFT), power = envelope², then % change from the trial-averaged baseline. Trials closer to the recording edges than the filter''s settling time (about 1 s for delta / theta) are left out for that band.'
                '* Band limits are conventions and vary between species, brain areas and labs; there is no single correct definition.'};
            t.trouble = {
                '"Missing variable(s)" when loading', 'Load the file written by Extract Ephys → Save LFP, not the MUA file or a raw tank.'
                '"No stimulus onsets detected. Check the threshold."', 'Look at the stimulus tab and set the threshold between baseline and stimulus amplitude (the stimulus is mean-subtracted first).'
                '"No complete epochs"', 'All onsets are too close to the recording start / end for the pre/post window. Shorten pre/post.'
                '"CSD needs at least 3 channels" / order error', 'Run the ERP with ≥ 3 channels and list only those channels in the CSD order.'
                '"No stimulus onsets detected" in ERSP / ITPC or Band power', 'These use the ERP stimulus threshold and minimum ISI (0.5 and 0.5 s until the ERP has been run). Run the ERP (step 3) with a threshold that suits the Stimulus tab, then try again.'
                '"The highest frequency must be below the Nyquist frequency"', 'Enter a highest frequency below half the LFP sampling rate (e.g. < 508 Hz for 1017 Hz data).'
                '"The baseline window … lies outside the epoch window"', 'Keep Baseline (s) inside Epoch (s), e.g. epoch −0.5 to 1 s and baseline −0.4 to −0.1 s.'
                'ERSP uses fewer trials at low frequencies, or low rows are blank', 'Low-frequency wavelets are long (3·cycles / (2π·f) s each side); trials whose wavelet would run past the recording start or end are left out at those frequencies. Raise the lowest frequency or use fewer cycles.'
                'Band power says n is smaller for delta / theta, or "No epochs far enough from the recording edges"', 'The band filter needs about 1 s of data on each side of an epoch; trials near the start or end of the recording are left out for that band.'
                'A band-table edit is undone', 'Limits must be numbers ≥ 0 with Low < High; the previous value is restored and the status bar says why.'};
            t.images = {'LFPAnalysisWorkflow.png', 'LFPAnalysisCSD.png', 'LFPAnalysisPrinciple.png'};
        end

        %% topicMUAAnalysis - Process MUA (spike sort, rate)
        function t = topicMUAAnalysis()
            t = mkTopic('MUA Analysis', 'Electrophysiology · step 2 (MUA)', ...
                'Detect and sort spikes in the MUA signal, check their quality and plot firing rates.');
            t.quick = {
                '**1 Load MUA file**: click **Load MUA file...** and choose the MUA file saved by Extract Ephys. Channels and whether a stimulus is present are shown.'
                '**2 Channel & segments**: choose the channel; optionally tick **Segment by stimulation onsets** (minimum ISI, threshold, pre / post-stimulus times) and pick a segment.'
                '**3 Spike sorting**: click **Configure...** (detection method, threshold, polarity, filtering, features, clustering, **Auto-merge similar clusters** with its **Merge threshold (correlation)**, drift correction) and then **Run**. With auto-merge on (default), clusters whose mean waveforms have the same shape (correlation ≥ 0.95) and size (amplitude ratio ≥ 0.85) are joined; the status bar says what was merged.'
                '**4 Clusters**: select the clusters to show (**Select all** / **Clear**) and read the quality summary. Select two or more units and click **Merge selected** when they are the same neuron; select one unit and click **Split selected** to cut it in two; **Undo** reverses the last merge, split or auto-merge.'
                '**5 Raster & PSTH** tab: spikes of each selected unit (up to 4) around every stimulus onset (raster) and the mean firing rate ± SEM (PSTH). Set **From (s)**, **To (s)** and **Bin (ms)**; onsets use the threshold and minimum ISI of **Segment by stimulation onsets** (default 0.5, 1 s).'
                '**6 Correlograms** tab: autocorrelograms (diagonal) and cross-correlograms of up to 4 selected units; set **Max lag (ms)** and **Bin (ms)**. The shaded band is ± the refractory period: a clean unit has (almost) no spikes there.'
                '**7 Export**: click **Save results...** to write spike times, cluster IDs, the sorting parameters, quality measures and the list of merges / splits (`info.clusterEdits`) to .mat.'
                '**Session / report (optional)**: in step 5, **Save session…** stores the file (with checksum), all settings and the sorted clusters with your edits; **Open session…** restores them as saved (Undo still works); **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'};
            t.demo = {
                '* **Data**: `demo_mua.mat`, channels 3–5 at 24414 Hz, 30 s, stimulus every 2 s from 1 s. Three units with negative spikes: **unit 1 (~90 µV) and unit 2 (~50 µV) on channel 4**, **unit 3 (~110 µV) on channel 5** (seen weaker on channel 4). Noise ~10 µV.'
                '* The demo selects **channel 4** and detection **MAD, k = 4, negative polarity**; click **Run**.'
                '* **What you should get**: K-means alone tends to split one unit in two (e.g. 4 clusters, two with the same waveform); with **Auto-merge similar clusters** on (default) the status bar reports e.g. "Auto-merged cluster 3 into 1 (r = 0.98, amplitude ratio 0.99)" and **2–3 units** remain on channel 4: unit 1 (~90 µV), unit 2 (~50 µV) and possibly unit 3 seen weaker from channel 5.'
                '* **Raster & PSTH** (−0.1 to 0.3 s, 5–10 ms bins): 15 trials; every unit fires more **5–55 ms after each stimulus** (unit 1: ~80 vs ~6 spikes/s). **Correlograms**: the autocorrelograms are empty within ±1 ms (2 ms refractory period); ISI violations ~0%.'};
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
                'Detection fails (findpeaks / butter undefined)', 'Install the Signal Processing Toolbox.'
                'Two clusters have the same waveform', 'One neuron was split: select both and click Merge selected, or turn on Auto-merge similar clusters (Configure...). Lower the Merge threshold (e.g. 0.9) to merge more.'
                'Auto-merge joined two different neurons', 'Click Undo (step 4) to restore the clusters, then raise the Merge threshold (e.g. 0.98) or turn Auto-merge off in Configure....'
                'One cluster mixes two waveforms or has many ISI violations', 'Select that unit alone and click Split selected; Undo if the result is worse.'
                'Raster & PSTH says "No stimulus channel in this file"', 'The MUA file has no stim_data; save it again from Extract Ephys with the stimulus channel. Correlograms do not need a stimulus.'
                'Raster & PSTH says "No stimulus onsets"', 'The stimulus never rises above the onset threshold: tick Segment by stimulation onsets (step 2) and set a lower threshold, then untick it if you want to sort the full recording.'
                'Autocorrelogram has spikes inside the shaded band', 'The unit has refractory violations: it probably contains a second neuron or noise; try Split selected or a higher detection threshold.'};
            t.images = {'MUAAnalysisWorkflow.png', 'MUAAnalysisPrinciple.png'};
        end

        %% topicROIAnalysis - ROI / Coregistered Image Analysis
        function t = topicROIAnalysis()
            t = mkTopic('ROI Analysis', 'Imaging', ...
                'Measure a ROI or a line over time in a stack of coregistered frames (2-photon, gCaMP, blood-flow imaging).');
            t.quick = {
                '**1 Load stack**: click **Load stack** and choose a .mat or multi-frame TIFF (or **Try demo data** / **Try advanced demo (motion, 3 cells)**). The first frame is shown with the size, frame count and time source; a `roiMask` / `roiMasks` in the file becomes the first ROI(s).'
                '**2 Preprocess (optional)**: tick **Motion correction (rigid)** if the frames jitter: the shifts are estimated once (max shift shown next to the box, per-frame plot in the **Motion correction** tab) and applied before everything else. Then optionally **B&W 256 levels**, **Smooth** and/or **Normalize each frame**, applied in that order when you click Run.'
                '**3 ROIs and line**: click **Add ROI** and drag a rectangle (repeat for more ROIs), or **Detect cells** to add one ROI per active cell automatically. ROIs are listed next to the image (double-click a name to rename, **Remove ROI** to delete). For line methods click **Draw line** (across the vessel for diameter). **Clear ROIs and line** starts over.'
                '**4 Analysis**: choose the **Method** (for ΔF/F also the baseline frames; for Vessel diameter optionally **Robust diameter (ignore blood cells)**) and click **Run**. ROI methods give one trace per ROI, in the ROI''s colour.'
                '**5 Export**: click **Export results** to save a .csv (time + one column per measure and ROI) or a .mat (all series, ROI masks and names, line, shifts and settings).'
                '**Session / report (optional)**: in step 5, **Save session…** stores the stack (with checksum), ROIs, line and settings; **Open session…** re-runs motion correction and the analysis; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'};
            t.demo = {
                '* **Data**: `demo_imaging.mat`, 96 × 96 px, 150 frames at 10 Hz (15 s). A dark vertical **vessel at x = 60** whose **diameter oscillates 12 ± 3 px (9–15 px) every 5 s**; a bright **red blood cell moving down 2 px/frame** (20 px/s); a **cell at (24, 30), radius 6 px** with calcium transients (ΔF/F ≈ 1) at **3, 7 and 11 s**. The cell''s `roiMask` is in the file.'
                '* The demo selects **ΔF/F** with that mask (baseline = first 30 frames) and a line across the vessel from (45, 70) to (75, 70).'
                '* **ΔF/F**: flat ~0 until 3 s, then **three peaks of ~0.2–0.3 at 3, 7 and 11 s**, each decaying in ~1–2 s. (The simulated calcium signal has ΔF/F ≈ 1, but it is added on top of the tissue background inside the ROI, so the measured ΔF/F of the ROI is smaller.)'
                '* **Vessel diameter** (same line): a sine between **~9 and ~15 px with a 5 s period**. **Kymograph** along the vessel (e.g. from (60, 5) to (60, 90)): slanted streaks with a slope of **2 px per frame**.'
                '* **Advanced demo** (**Try advanced demo (motion, 3 cells)**): 96 × 96 px, 150 frames at 10 Hz. Every frame is shifted by up to **±3 px** (smooth random walk); **three cells**: cell 1 at (22, 24) with events at **4, 8.5, 13 s**, cell 2 at (26, 78) at **5.5, 10.5 s**, cell 3 at (82, 30) at **7, 12 s**; the vessel at x = 60 (12 ± 3 px, period 5 s) and a bright **red blood cell that crosses the diameter line** (35, 64)–(85, 64) about every 3 s.'
                '* **Motion correction**: the Motion correction tab shows dy and dx following the dashed true shifts (error < 0.3 px), max shift ≈ 3 px.'
                '* **Show → Correlation image**: the three cells are bright disks (correlation ≈ 0.9), the vessel a bright band; **Detect cells** adds exactly **Cell 1–3** (the vessel is rejected as too elongated).'
                '* **ΔF/F** (Run): three traces, each peaking only at its own cell''s event times.'
                '* **Vessel diameter**: without Robust diameter the trace jumps to ~50 px whenever the blood cell crosses the line; with **Robust diameter** it follows the 9–15 px sine (error < 2.5 px) and the replaced frames are circled.'};
            t.inputs = {
                '`.mat` with `stack` or `frames` (H × W × N grayscale or H × W × 3 × N RGB; otherwise the first variable is used)'
                'Optional in the .mat: `timeVec` or `t` (one time per frame), `roiMask` (logical H × W) or `roiMasks` (H × W × K, optional `roiNames`), used as the first ROIs'
                'Multi-frame TIFF: RGB frames are converted to grayscale (mean of the colour channels); time = frame index'};
            t.outputs = {
                '.csv: `Time` plus one column per measure (Intensity, Movement, DFF, Speed; with several ROIs `<measure>_<ROI name>`), or `Diameter_px` (+ `Diameter_standard_px`, `Replaced` when robust); for a kymograph, a matrix (first row = time)'
                '.mat: struct `results` with the series (one row per ROI), `roiMasks` / `roiNames`, `roiMask` (ROI 1), `lineStart` / `lineEnd`, `motionCorrection` and `shifts`, and the preprocessing and diameter settings'};
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
                '* **Normalize**: every frame scaled to 0–1 by its own min / max (removes global brightness changes, so do not use it for Brightness or ΔF/F).'
                '## Advanced'
                '* **Motion correction (rigid)**: every frame is aligned to the mean image by FFT phase correlation with a sub-pixel peak fit (two passes), then shifted back (bilinear). Translation only.'
                '* **Multiple ROIs**: every ROI method gives one trace per ROI; the ROI table shows number (in the trace colour), name, area and source (file, drawn, detected, added).'
                '* **Detect cells**: local correlation image (mean correlation of each pixel with its 8 neighbours), threshold (automatic: median + 4 robust SD, at least 0.2; the field''s label then shows the value used), connected components of 20–1000 px that are not elongated, holes filled. Detected cells are numbered from left to right.'
                '* **Robust diameter**: background from the line ends and vessel core from a low percentile (both as running medians over 7 frames), outermost half-level crossings, then a Hampel filter (7 frames, 3 robust SD) replaces remaining spikes. Walls are located to sub-pixel precision in all modes.'};
            t.trouble = {
                '"Could not draw a rectangle / line"', 'drawrectangle / drawline need the Image Processing Toolbox. Without it, save a logical `roiMask` in the .mat for ROI methods.'
                'Run is disabled', 'The chosen method needs a ROI (Brightness, Movement, Both, ΔF/F, Speed) or a line (Kymograph, Vessel diameter); the step 3 card says which is missing.'
                '"roiMask size does not match"', 'The mask must be H × W, the same size as one frame.'
                'Time axis shows frames, not seconds', 'Add a `timeVec` (or `t`) with one value per frame to the .mat.'
                'Load is slow / out of memory', 'Large TIFFs are read frame by frame into memory as double; crop or bin the stack first.'
                'Detect cells finds nothing', 'Tick **Motion correction** first: residual motion makes every edge look correlated and raises the automatic threshold. Otherwise lower **Detect: min correlation** (e.g. 0.3; 0 = automatic).'
                'Detect cells also picks up vessels or blobs at the border', 'Elongated structures (ratio > 3) and components outside 20–1000 px are rejected; after motion correction the border within the largest shift is ignored. Remove unwanted ROIs with **Remove ROI**.'
                'Two touching cells become one ROI', 'Raise **Detect: min correlation** so they separate, or draw them with **Add ROI**.'
                'Vessel diameter jumps for single frames', 'A bright blood cell crossing the line moves the half level. Tick **Robust diameter (ignore blood cells)**; make the line extend at least one vessel radius beyond each wall so its ends sample the background.'
                'Motion correction shifts look noisy / wrong', 'It corrects translation only (not rotation or warping) and needs structure in the image; very dim or uniform stacks give unreliable shifts. Untick it to go back to the raw frames.'
                'ROIs are slightly off after turning motion correction on or off', 'ROIs and the line keep their pixel positions; re-run **Detect cells** or redraw them on the image you analyse.'};
            t.images = {'ROIAnalysisWorkflow.png', 'ROIAnalysisPrinciple.png'};
        end

        %% topicSignalCharacterization - Signal Characterization
        function t = topicSignalCharacterization()
            t = mkTopic('Signal Characterization', 'Response features', ...
                'Turn each response into numbers (latency, onset delay, FWHM, AUC, rise / decay time, amplitude), compare groups of animals statistically and export publication figures.');
            t.quick = {
                '**1 Load data**: click **Load .mat file**. The data type is detected (LDF segments, ERP / average, time series) and the number of series, Fs and time range are shown; the first series is plotted.'
                '**2 Parameters**: set the stimulus onset **t0** (s), the **baseline** window (s) and the response **direction**. The plot shows t0 (dashed), the baseline window (shaded) and the detected peak and FWHM, so you can check them before extracting.'
                '**3 Features**: select the features (Ctrl/Cmd-click for several) and click **Extract features**.'
                '**4 Export**: check the table (click a row to plot that series) and click **Export to CSV / MAT**. **Export figure…** above the plot saves the selected trace as a publication figure.'
                '**5 Groups & statistics** tab (or **Try group demo**): in **1 Files and groups** type a **Group** name and click **Add files…** (one .mat per animal); repeat for each group. The **#** column is the subject number: paired designs match #1 with #1, #2 with #2 (fix with **▲ Move up** / **▼ Move down**).'
                '**6 Feature and test**: choose the **Feature**, **Value per** (File (mean trace) recommended: one animal = one file), **Onset t0 (s)**, **Baseline (s)** and **Direction**; then the **Design** (Paired, Unpaired or ANOVA for 2+ groups), the **Method** (Parametric or Nonparametric) and, for two groups, **Compare** A vs B (difference = B − A). Click **Run test**: the **Plot** tab shows every animal, pair lines, mean ± SEM (or **Box plot**) and the significance bracket; the **Results** tab lists test, statistic, df, p, effect size, 95% CI, n, a robustness check with the other test family, assumptions and a copy-ready report.'
                '**7 Export**: choose a format and click **Export figure…** (PDF / SVG / EPS vector, or PNG / TIFF at 300 or 600 dpi; 8.5 cm wide, 8 pt Helvetica, the window is not changed). **Export values & report…** saves the per-animal values (.csv plus a _report.txt) or the full result (.mat).'
                '**Session / report (optional)**: in step 4 of either tab, **Save session…** stores the single file and every group file (with checksums), all settings and results; **Open session…** re-extracts the features and re-runs the test; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'};
            t.demo = {
                '* **Data**: `demo_ldf_trials.mat`, 8 LDF trials from −5 to 20 s at 10 Hz (0 = stimulus onset). The demo sets t0 = 0, direction Auto, the baseline to −5–0 s and selects every feature.'
                '* **Expected per trial** (true response: ~120 PU baseline + 30 PU gamma-shaped hyperemia): **peak latency ≈ 4 s**, **peak amplitude ≈ 30 PU**, onset delay (50%) ≈ 1.9 s, FWHM ≈ 5.5 s, rise time (10–90%) ≈ 2.2 s, decay to 50% ≈ 3.4 s; positive direction.'
                '* Trials differ by a few PU / tenths of a second because of vasomotion and noise, which is why the mean over trials is the number to report.'
                '* **Group demo** (**Try group demo**): 24 files, `control_animal01.mat` … `drug_animal08.mat`: the same 8 animals in Control, Stimulated and Drug, each with 8 LDF trials (−5 to 20 s at 10 Hz). True peak hyperemia 18, 30 and 24 PU; animals differ by ~3 PU, plus ~2.5 PU per animal and condition.'
                '* **Paired t-test, Peak amplitude, Control vs Stimulated**: Stimulated − Control ≈ **+12 PU** (95% CI roughly +9 to +15), **p < 0.001**, d_z ≈ 3 (simulated 3.3). Wilcoxon signed-rank: p ≈ 0.008 (all 8 animals increase; the smallest exact p possible with 8 pairs). Unpaired (Welch): also significant, with a smaller t.'
                '* **ANOVA**: F(2, 21) large, p < 0.001; Tukey–Kramer Stimulated − Control ≈ +12 PU (p < 0.001); Drug lies ~6 PU from each of the others (usually, not always, significant). **Peak latency** ≈ 4 s in every group: no difference expected.'};
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
                'Peak found on the wrong deflection', 'Set Direction to Positive or Negative instead of Auto.'
                '"The paired design needs the same number of subjects in both groups"', 'Every animal needs one file in each group. Add the missing file or remove the extra one; the **#** column shows the pairing.'
                'Wrong animals paired', 'The Results report lists every pair (`1: fileA ↔ fileB`). Files are added in alphabetical order; fix the order with **▲ Move up** / **▼ Move down**.'
                '**Run test** is disabled', 'Add files to at least two groups. For a two-group design, choose two different groups in **Compare**.'
                '"… value(s) excluded because the feature could not be computed"', 'The feature was NaN for those files (peak not found or never crossing 50%). Check **Onset t0**, **Baseline** and **Direction**, or choose another feature.'
                '"The parametric and rank-based tests disagree"', 'Usually few animals or an outlier. Look at the Plot tab, and report the rank-based result or add animals.'
                'Same animals in 3 or more conditions', 'The one-way ANOVA assumes independent groups; repeated-measures ANOVA is not available. Compare the conditions of interest with paired tests (corrected for multiple comparisons), or use a statistics package.'
                '**Export figure…** is disabled', 'Run a test first (Groups & statistics), or load a file (Single file).'
                'The journal wants Arial or another size', 'Export as PDF or SVG (vector) and change the font or size in Illustrator or Inkscape; the text stays editable.'};
            t.images = {'SignalCharacterizationWorkflow.png', 'SignalCharacterizationPrinciple.png'};
        end


        %% topicBatch - Batch processing: one pipeline on many files
        function t = topicBatch()
            t = mkTopic('Batch processing', 'All pipelines · many files', ...
                'Run one analysis with the same settings on a whole folder and get one summary table.');
            t.quick = {
                '**1 Pipeline**: choose what to run on every file: **LDF: trials + response features**, **LFP: ERP (+ CSD) per channel**, **MUA: spike sorting per channel**, **Imaging: ROI dF/F and vessel diameter** or **Response features (any trace file)**. The line below says which files it reads. **Try demo batch** adds a few synthetic files with known answers and fills the settings.'
                '**2 Input files**: click **Add folder...** (every file of the folder that this pipeline reads) or **Add files...** (multi-select). Select files and click **Remove** to drop them; **Clear** empties the list. Files are processed in list order.'
                '**3 Settings**: one set of settings for every file (hover a field for its unit and meaning). They are the settings of the matching window: e.g. downsampling, filter and trial window for LDF; epoch, N1 window and electrode spacing for LFP; detection, clustering and random seed for MUA.'
                '**4 Run**: choose the **Output folder...** and click **Run batch**. The table and the status bar show which file is being processed; **Cancel** stops before the next file. A file that fails does not stop the batch: it gets a red row with the reason.'
                '**5 Results**: one row per file (LFP and MUA: per channel; imaging: per ROI). Green = ok, orange = warning (some channels failed), red = error, gray = skipped. **Open folder** shows the summary (.csv and .mat), the log (.txt) and, for LDF, the trial files; **Export...** saves a copy of the table (.csv, .xlsx or .mat).'};
            t.demo = {
                '* **Data**: **Try demo batch** writes synthetic files for the chosen pipeline, each with slightly different known answers, and fills the settings.'
                '* **LDF**: 4 cropped recordings (200 s, 7 stimuli of 5 s). **What you should get**: 7 onsets and **6 trials** per file (the last stimulus is too close to the end); peak latency **~3, 3.5, 4 and 4.5 s** and peak amplitude **~20, 25, 30 and 35 PU** (within ~2 PU); one trial file per recording in the trials folder.'
                '* **LFP**: 3 recordings, 8 channels 100 µm apart. **What you should get**: 8 rows per file; the N1 is largest and the CSD sink (SinkChannel) is on **channel 3, 4 and 5**, with the N1 at **~12, 15 and 18 ms** (about −90, −115 and −135 µV).'
                '* **MUA**: the demo MUA recording and a copy recorded at twice the gain, channel 4. **What you should get**: **2–3 units** and the **same spike count in both files** (sorting does not depend on the gain); the evoked rate (5–55 ms after each stimulus) is several times the baseline rate.'
                '* **Imaging**: 3 stacks with a cell (roiMask) and a vessel crossed by the line 25 50 63 50. **What you should get**: peak ΔF/F **~0.5, 1.0 and 1.5** at ~3.2 s and mean vessel diameter **~10, 12 and 14 px**.'
                '* **Response features**: 4 trial files. **What you should get**: peak latency ~3, 3.5, 4, 4.5 s and peak amplitude ~20, 25, 30, 35 PU (one row per file); Series = Each series gives one row per trial (32 rows).'};
            t.inputs = {
                'LDF: cropped `.mat` files from LDF Extract (`stim`, `LDF`, `t`, `Fs`)'
                'LFP: `.mat` files from Extract Ephys (`lfp_data`, `stim_data`, `lfp_fs`, `stim_fs`; `t_lfp`, `lfp_channels` optional)'
                'MUA: `.mat` files from Extract Ephys (`mua_data`, `mua_fs`; `t_mua`, `mua_channels`, `stim_data` + `t_stim` optional)'
                'Imaging: `.mat` with `stack` (or `frames`), optional `timeVec` / `t` and `roiMask` / `roiMasks`, or a multi-frame TIFF'
                'Response features: any file Signal Characterization reads (`segmentedLDF` + `segmentedTime`, `lfp_data` + `t_lfp`, `t` + `y`, `t` + `LDF`)'};
            t.outputs = {
                '`<name>_summary.csv` and `<name>_summary.mat` (table `summary` + struct `batch` with the settings, files, statuses and log): columns File, Status, Message, then the pipeline''s results'
                '`<name>_log.txt`: date, settings and one line per file (result or error)'
                'LDF: `trials/<file>_segments.mat` per recording (`segmentedLDF`, `segmentedTime`, `Fs`), ready for LDF Average'};
            t.details = {
                '## What each pipeline measures'
                '* **LDF**: the LDF Process steps (decimate, filter, cut trials around each onset), then the response features of the **mean trial** (onset 0 s, baseline = the pre-onset part): peak latency and amplitude, onset delay, FWHM, AUC, rise and decay time, integral.'
                '* **LFP**: ERP per channel as in LFP Analysis (onsets on the mean-subtracted stimulus). **N1** = minimum in the N1 window, **P2** = maximum in the P2 window; latency in ms after the stimulus, amplitude relative to the pre-stimulus mean, multiplied by Amplitude scale (1e6: V to µV). With **Compute CSD** (≥ 3 channels, in the listed order, top to bottom): the CSD minimum in the N1 window per channel (AmpUnit / mm²) and the sink channel of the file.'
                '* **MUA**: spike sorting per channel as in MUA Analysis. The random generator is set to **Random seed** before every channel, so the same file always gives the same clusters, whatever its position in the list. Per channel: spikes in units, units (good / rejected by the quality check: SNR < 2 or > 2% ISIs below the refractory period), mean rate and rate per unit, mean SNR, worst ISI violation and, with a stimulus, the rate in the response window vs the baseline window.'
                '* **Imaging**: per ROI the mean brightness and ΔF/F (F0 = mean of the first baseline frames) with its peak and peak time; with a line, the vessel diameter (FWHM; **Robust diameter** ignores red blood cells) as mean, min and max. No smoothing or normalisation is applied; **Motion correction** registers every frame onto the mean image first.'
                '* **Response features**: the nine features of Signal Characterization, for the mean of the series in each file or for every series.'
                '## Good to know'
                '* Channels are the numbers saved in the file (`lfp_channels` / `mua_channels`), otherwise the row numbers. Empty = all channels.'
                '* Vector fields take numbers separated by spaces, e.g. `5 50` for a window or `45 70 75 70` for a line.'
                '* The same pipelines run from scripts: `R = Batch.run(''ldf'', folder, params, outFolder)`; `Batch.defaults(''ldf'')` lists the settings.'};
            t.trouble = {
                'A row is red with "Missing variable(s)"', 'The file was not saved by the step this pipeline expects (e.g. a raw LabChart export in the LDF pipeline). Use the files named under Inputs, or choose the matching pipeline.'
                'A row is red with "Unable to read" / "not a binary MAT-file"', 'The file is damaged or not a MAT file. Remove it (select it, **Remove**) or re-export it; the other files are not affected.'
                'LDF: "No stimulus onsets found above threshold"', 'The stimulus never crosses **Stim threshold**: lower it (e.g. 0.5 for a 1 V trigger, 2.5 for 5 V TTL).'
                'LDF: "no complete trial fits"', 'Pre-onset + Post-onset is longer than the recording around the stimuli: shorten the windows.'
                'LFP: "Channel(s) … not in the file"', 'The Channels field lists numbers the file does not have: clear it (all channels) or use the numbers shown in LFP Analysis.'
                'MUA: a red channel row (file orange) with "Too few spikes for clustering"', 'That channel has almost no spikes at this threshold: lower Threshold (k) or Min spikes / cluster, or leave the channel out; the other channels of the file are kept.'
                'Imaging: "needs a line" or no diameter columns', 'Type the line across the vessel in **Line x1 y1 x2 y2 (px)** (read the coordinates in ROI Analysis).'
                'Imaging: "No ROI"', 'The stacks have no `roiMask`: draw and export ROIs in ROI Analysis, or measure Vessel diameter only.'
                'The batch takes long', 'MUA sorting is the slowest part (seconds per channel): select only the channels you need. **Cancel** stops after the current file and still writes the summary of the files done.'};
            t.images = {};
        end

        %% topicSessions - Save / reopen an analysis and write a PDF report
        function t = topicSessions()
            t = mkTopic('Sessions and reports', 'All windows', ...
                'Save everything needed to repeat an analysis, reopen it later, and write a one-page PDF report.');
            t.quick = {
                '**Save session…** (last step card of every analysis window): choose a file name, type optional notes (animal, condition, why these settings) and click **Save session**. The `.nasession.mat` file stores the input file paths with their size, date and MD5 checksum, every setting, the results and your notes.'
                '**Open session…**: choose a `.nasession.mat` saved by the **same window**. The input files are reloaded and checked; the settings are applied and the analysis is re-run, so the window looks as it did when you saved.'
                'If an input file has moved, put it next to the session file (it is found automatically) or choose it when asked. If a file has **changed** since the session was saved, the session still opens and the status bar warns you.'
                '**Report (PDF)…**: writes one A4 page with a picture of the window and, below it, the NeuroAnalyzer and MATLAB versions, the date, every input file with its MD5, the settings and the key results. Attach it to your lab notebook or use it for the methods section.'};
            t.demo = {
                '* **Try**: in any window click **Try demo data**, run the analysis, then **Save session…**. Close the window, open it again from the launcher and click **Open session…**: the same plots and numbers come back.'
                '* **What you should get**: the status bar says "Session … opened (saved … with NeuroAnalyzer v…)" and shows your notes. **Report (PDF)…** writes a one-page PDF of about 0.2–1 MB.'};
            t.inputs = {
                'A `.nasession.mat` file saved by the same window (Open session)'
                'The input files the session refers to, at their saved location, next to the session file, or chosen when asked'};
            t.outputs = {
                '`<name>.nasession.mat`: variable `session` with `app`, `toolboxVersion`, `matlabVersion`, `os`, `created` (ISO 8601), `inputs` (role, path, name, bytes, modified, md5), `settings`, `results`, `summary`, `notes`'
                '`<name>_report.pdf`: one A4 page (window image + versions, inputs with MD5, settings, key results)'};
            t.details = {
                '## What is stored'
                '* **Inputs**: the full path, size in bytes, modification date and MD5 checksum of every input file (for folders such as TDT tanks: one checksum over all files in the folder).'
                '* **Settings**: every parameter of the window (filters, ERP window and threshold, CSD order, time–frequency settings, spike-sorting settings, ROIs and line, features, statistical design, …).'
                '* **Results**: the result structs of the window. Large signals (e.g. filtered LFP / MUA, cropped LDF) are not stored: they are re-computed from the checked input when the session is opened. Arrays larger than 100 MB are replaced by a note.'
                '## Opening a session'
                '* The input files are checked first. **ok**: unchanged; **moved**: found next to the session file with the same checksum; **changed**: the checksum differs (the session opens with a warning, results may differ); **missing**: you are asked to locate it (the session does not open without it).'
                '* The analysis is re-run with the saved settings. MUA Analysis is the exception: the sorted clusters, your merges and splits and the Undo history are restored as saved, because K-means and manual edits cannot be repeated exactly.'
                '* A session saved by one window cannot be opened in another window.'
                '## The PDF report'
                '* One page: base MATLAB cannot join several PDF pages without a toolbox, so the window picture and the summary share one A4 page. Long lists are shortened on the page; the session file keeps everything.'
                '* The window picture is taken with `exportapp` (MATLAB R2020b or later); if that fails, the largest plot is used instead.'};
            t.trouble = {
                '"This session was saved by …, not by this window"', 'Open the session in the window named in the message (each window saves its own kind of session).'
                '"Session not opened: … not found at …"', 'The input file was moved or renamed. Copy it next to the session file, or use Open session… again and locate it when asked.'
                '"… has CHANGED since the session was saved (MD5 differs)"', 'The input file is not the one used when the session was saved (edited, re-exported or overwritten). The results may differ; use the original file if you still have it.'
                'Report not written', 'Check that the folder is writable and that the PDF is not open in another program. The analysis itself is not affected.'
                'The window picture in the PDF shows only one plot', '`exportapp` is not available (MATLAB older than R2020b or no display); the largest plot was used instead.'};
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
