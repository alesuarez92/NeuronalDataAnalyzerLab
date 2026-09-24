%% BatchApp.m
% =========================================================================
% BATCH PROCESSING - ONE PIPELINE, ONE SET OF SETTINGS, MANY FILES
% =========================================================================
% Launched from Main (Batch card). Built with UIKit.window in three
% columns: steps 1-2 | steps 3-4 | step 5 (summary table) above the log.
%   1 Pipeline      dropdown (LDF trials + features, LFP ERP (+ CSD), MUA
%                   spike sorting, imaging ROI dF/F + vessel diameter,
%                   response features of any trace file); "Try demo batch"
%   2 Input files   Add folder... / Add files... / Remove / Clear, list with
%                   the file count
%   3 Settings      the chosen pipeline's main settings (Batch.paramSpec;
%                   tooltips give the units)
%   4 Run           output folder (Choose...), Run batch, Cancel (stops
%                   before the next file); progress per file in the status
%                   bar, the step label and the table
%   5 Results       Open output folder, Export summary...
% The table lists the queued files while running and the summary after
% (one row per file, channel, ROI or series; rows coloured by Status:
% ok / warning / error / skipped). The log shows Batch.run's log. All the
% computing is done by core/Batch.m (Batch.run), which also writes the
% summary CSV / MAT and the log to the output folder.
%
% Scriptable (CI walkthroughs, no dialogs): setPipeline(name),
% addFiles(paths), removeFiles(idx), clearFiles(), setParams(struct),
% getParams(), setOutputFolder(folder), runBatch(outFolder),
% cancelBatch(), exportSummary(path), loadDemo(pipeline) (demo files from
% core/demo/demoBatch.m with settings that suit them).
% =========================================================================

classdef BatchApp < handle
    properties
        UIFig
        W                  % UIKit.window struct (Fig, Body, Status, HelpBtn)
        StatusLabel
        HelpBtn
        % Step 1
        PipelineDrop       % Pipeline dropdown (labels; ItemsData = keys)
        PipelineInfo       % Input / output of the chosen pipeline
        DemoBtn
        % Step 2
        AddFolderBtn
        AddFilesBtn
        RemoveBtn
        ClearBtn
        FileList           % uilistbox (multi-select) of the input files
        FileCountLabel
        % Step 3
        LeftGrid           % Middle column grid (steps 3-4; card heights change with the settings)
        SettingsCard
        SettingsGrid
        ParamControls      % struct: parameter name -> control
        ParamSpec          % Batch.paramSpec of the current pipeline
        ExtraParams        % settings not shown as fields (e.g. roiMask), kept from setParams
        % Step 4
        OutFolderLabel
        OutFolderBtn
        RunBtn
        CancelBtn
        ProgressLabel
        % Step 5
        OpenFolderBtn
        ExportBtn
        ResultsInfoLabel
        % Right
        Table              % uitable: queued files, then the summary
        LogArea            % uitextarea: batch log
        % State
        Pipeline = 'ldf'
        Files = {}         % input files (cellstr, row)
        OutFolder = ''
        Result = []        % struct returned by Batch.run
        Running = false
        CancelRequested = false
        CardHeights = {}
    end

    methods
        %% Constructor - Build the window (no data)
        function app = BatchApp()
            app.buildUI();
        end

        %% buildUI - Window, step cards (left), summary table and log (right)
        function buildUI(app)
            T = UITheme;
            app.W = UIKit.window('Batch Processing', ...
                'Run one pipeline with the same settings on many files and collect one summary table', ...
                'Batch processing', [1440 860]);
            app.UIFig = app.W.Fig;
            app.StatusLabel = app.W.Status;
            app.HelpBtn = app.W.HelpBtn;
            app.W.Body.RowHeight = {'1x'};
            app.W.Body.ColumnWidth = {300, 330, '1x'};
            bh = T.buttonHeight; ch = T.controlHeight;

            % === Column 1: steps 1 and 2 ===
            col1 = uigridlayout(app.W.Body, [2 1], 'Padding', [0 0 0 0], 'RowSpacing', 10, ...
                'BackgroundColor', T.bgGray);
            col1.Layout.Row = 1; col1.Layout.Column = 1;

            % --- 1 Pipeline ---
            [p, g, h1] = stepCard(col1, 1, 'Pipeline', {ch, 46, bh});
            p.Layout.Row = 1;
            keys = Batch.pipelines();
            labels = cellfun(@(k) batchLabel(k), keys, 'UniformOutput', false);
            app.PipelineDrop = uidropdown(g, 'Items', labels, 'ItemsData', keys, 'Value', 'ldf', ...
                'Tooltip', 'Analysis applied to every file; the settings in step 3 change with it', ...
                'ValueChangedFcn', @(src, ~)app.setPipeline(src.Value));
            app.PipelineDrop.Layout.Row = 2; app.PipelineDrop.Layout.Column = [1 2];
            app.PipelineInfo = infoLabel(g, '', 'Input files this pipeline reads and what it writes');
            app.PipelineInfo.Layout.Row = 3; app.PipelineInfo.Layout.Column = [1 2];
            app.DemoBtn = UIKit.button(g, 'Try demo batch', @(~,~)app.loadDemo(), 'secondary', ...
                ['Write a few synthetic files for this pipeline (known, slightly different answers), ' ...
                 'add them and fill the settings']);
            app.DemoBtn.Layout.Row = 4; app.DemoBtn.Layout.Column = [1 2];

            % --- 2 Input files (the list takes the rest of the column) ---
            [p, g] = stepCard(col1, 2, 'Input files', {bh, bh, '1x', 18});
            p.Layout.Row = 2;
            col1.RowHeight = {h1, '1x'};
            app.AddFolderBtn = UIKit.button(g, 'Add folder...', @(~,~)app.addFolderDialog(), 'secondary', ...
                'Add every file of a folder that this pipeline reads (.mat; imaging also .tif)');
            app.AddFolderBtn.Layout.Row = 2; app.AddFolderBtn.Layout.Column = 1;
            app.AddFilesBtn = UIKit.button(g, 'Add files...', @(~,~)app.addFilesDialog(), 'secondary', ...
                'Add one or more files (multi-select)');
            app.AddFilesBtn.Layout.Row = 2; app.AddFilesBtn.Layout.Column = 2;
            app.RemoveBtn = UIKit.button(g, 'Remove', @(~,~)app.removeFiles(), 'secondary', ...
                'Remove the selected files from the list');
            app.RemoveBtn.Layout.Row = 3; app.RemoveBtn.Layout.Column = 1;
            app.ClearBtn = UIKit.button(g, 'Clear', @(~,~)app.clearFiles(), 'danger', ...
                'Remove every file from the list');
            app.ClearBtn.Layout.Row = 3; app.ClearBtn.Layout.Column = 2;
            app.FileList = uilistbox(g, 'Items', {}, 'Multiselect', 'on', 'FontSize', T.fontSmall, ...
                'Tooltip', 'Files to process, in this order (select to Remove)');
            app.FileList.Layout.Row = 4; app.FileList.Layout.Column = [1 2];
            app.FileCountLabel = uilabel(g, 'Text', 'No files', 'FontSize', T.fontSmall, ...
                'FontColor', T.bodyColor);
            app.FileCountLabel.Layout.Row = 5; app.FileCountLabel.Layout.Column = [1 2];

            % === Column 2: steps 3 and 4 (scrolls if the settings are long) ===
            col2 = uigridlayout(app.W.Body, [3 1], 'Padding', [0 0 0 0], 'RowSpacing', 10, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            col2.Layout.Row = 1; col2.Layout.Column = 2;
            app.LeftGrid = col2;

            % --- 3 Settings (rebuilt for each pipeline) ---
            app.SettingsCard = UIKit.card(col2, '');
            app.SettingsCard.Layout.Row = 1;

            % --- 4 Run ---
            [p, g, h4] = stepCard(col2, 4, 'Run', {30, bh, bh, 30});
            p.Layout.Row = 2;
            app.OutFolderLabel = infoLabel(g, '', 'Where the summary (.csv, .mat), the log and trial files are written');
            app.OutFolderLabel.Layout.Row = 2; app.OutFolderLabel.Layout.Column = [1 2];
            app.OutFolderBtn = UIKit.button(g, 'Output folder...', @(~,~)app.chooseOutputFolder(), 'secondary', ...
                'Choose the folder for the summary table and the log');
            app.OutFolderBtn.Layout.Row = 3; app.OutFolderBtn.Layout.Column = 1;
            app.CancelBtn = UIKit.button(g, 'Cancel', @(~,~)app.cancelBatch(), 'danger', ...
                'Stop after the file being processed (the rest is marked skipped)');
            app.CancelBtn.Layout.Row = 3; app.CancelBtn.Layout.Column = 2;
            app.RunBtn = UIKit.button(g, 'Run batch', @(~,~)app.runBatch(), 'secondary', ...
                'Process every file with the settings of step 3; a file that fails is logged and the batch goes on');
            app.RunBtn.Layout.Row = 4; app.RunBtn.Layout.Column = [1 2];
            app.ProgressLabel = infoLabel(g, 'Not run yet', 'Progress of the batch');
            app.ProgressLabel.Layout.Row = 5; app.ProgressLabel.Layout.Column = [1 2];
            app.CardHeights = {[], h4, '1x'};

            % === Column 3: step 5 results (summary table) and the log ===
            right = uigridlayout(app.W.Body, [2 1], 'RowHeight', {'1x', 160}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 10, 'BackgroundColor', T.bgGray);
            right.Layout.Row = 1; right.Layout.Column = 3;
            rc = UIKit.card(right, '');
            rg = uigridlayout(rc, [3 3], 'RowHeight', {bh, 18, '1x'}, 'ColumnWidth', {'1x', 120, 120}, ...
                'Padding', [10 8 10 10], 'RowSpacing', 6, 'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
            lbl = UIKit.step(rg, 5, 'Results (one row per file, channel, ROI or series)');
            lbl.Layout.Row = 1; lbl.Layout.Column = 1;
            app.OpenFolderBtn = UIKit.button(rg, 'Open folder', @(~,~)app.openOutputFolder(), 'secondary', ...
                'Open the output folder (summary .csv / .mat, log, trial files)');
            app.OpenFolderBtn.Layout.Row = 1; app.OpenFolderBtn.Layout.Column = 2;
            app.ExportBtn = UIKit.button(rg, 'Export...', @(~,~)app.exportDialog(), 'secondary', ...
                'Save a copy of the summary table as .csv, .xlsx or .mat');
            app.ExportBtn.Layout.Row = 1; app.ExportBtn.Layout.Column = 3;
            app.ResultsInfoLabel = uilabel(rg, 'Text', 'No results yet', 'FontSize', T.fontSmall, ...
                'FontColor', T.bodyColor, 'Interpreter', 'none', ...
                'Tooltip', 'Outcome of the last batch. Rows: green ok, orange warning, red error, gray skipped');
            app.ResultsInfoLabel.Layout.Row = 2; app.ResultsInfoLabel.Layout.Column = [1 3];
            % Queued files while running; the summary afterwards (rows coloured by Status)
            app.Table = uitable(rg, 'Data', emptyQueue(), 'RowName', {}, 'FontSize', T.fontSmall);
            app.Table.Layout.Row = 3; app.Table.Layout.Column = [1 3];
            lc = UIKit.card(right, 'Log');
            lg = uigridlayout(lc, [1 1], 'Padding', [8 8 8 8], 'BackgroundColor', T.cardBg);
            app.LogArea = uitextarea(lg, 'Value', {''}, 'Editable', 'off', 'FontSize', T.fontSmall, ...
                'FontName', 'Monospaced', 'Tooltip', 'Settings and one line per file (also saved as <name>_log.txt)');

            app.setOutputFolder(defaultOutFolder());
            app.setPipeline('ldf');
            UIKit.setStatus(app.StatusLabel, ['Step 1: choose a pipeline, then add files (step 2) or ' ...
                'click Try demo batch.'], 'info');
        end

        %% updateControls - Enable controls from the state; next action is primary
        function updateControls(app)
            idle = ~app.Running;
            hasFiles = ~isempty(app.Files);
            hasResult = ~isempty(app.Result);
            setEnable({app.PipelineDrop, app.DemoBtn, app.AddFolderBtn, app.AddFilesBtn, ...
                app.OutFolderBtn}, idle);
            setEnable({app.RemoveBtn, app.ClearBtn}, idle && hasFiles);
            setEnable({app.RunBtn}, idle && hasFiles);
            setEnable({app.CancelBtn}, app.Running);
            setEnable({app.OpenFolderBtn, app.ExportBtn}, idle && hasResult);
            fn = fieldnames(app.ParamControls);
            for i = 1:numel(fn)
                app.ParamControls.(fn{i}).Enable = onOff(idle);
            end
            styleBtn(app.AddFilesBtn, idle && ~hasFiles);
            styleBtn(app.RunBtn, idle && hasFiles && ~hasResult);
            styleBtn(app.OpenFolderBtn, idle && hasResult);
            n = numel(app.Files);
            if n == 0
                app.FileCountLabel.Text = 'No files';
            elseif n == 1
                app.FileCountLabel.Text = '1 file';
            else
                app.FileCountLabel.Text = sprintf('%d files', n);
            end
        end

        %% setPipeline - Choose the pipeline (key or label); rebuilds the settings
        function ok = setPipeline(app, name)
            ok = false;
            keys = Batch.pipelines();
            k = find(strcmpi(char(name), keys), 1);
            if isempty(k)
                labels = cellfun(@(x) batchLabel(x), keys, 'UniformOutput', false);
                k = find(strcmpi(char(name), labels), 1);
            end
            if isempty(k)
                UIKit.setStatus(app.StatusLabel, sprintf('Unknown pipeline "%s".', char(name)), 'warning');
                return;
            end
            changed = ~strcmp(app.Pipeline, keys{k}) || isempty(app.ParamSpec);
            app.Pipeline = keys{k};
            app.PipelineDrop.Value = keys{k};
            d = Batch.describe(app.Pipeline);
            app.PipelineInfo.Text = sprintf('In: %s', d.input);
            app.PipelineInfo.Tooltip = sprintf('In: %s\nOut: %s', d.input, d.output);
            if changed
                app.ExtraParams = struct();
                app.buildSettings();
                app.Result = [];
                app.showQueue();
                app.ResultsInfoLabel.Text = 'No results yet';
                app.ProgressLabel.Text = 'Not run yet';
            end
            app.updateControls();
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf('Pipeline: %s. %s', d.label, d.output), 'info');
        end

        %% addFiles - Add files and/or folders (folders: files this pipeline reads)
        function n = addFiles(app, paths)
            if ischar(paths), paths = {paths}; end
            new = Batch.listInputs(paths, app.Pipeline);
            new = new(~ismember(new, app.Files));
            app.Files = [app.Files, new];
            n = numel(new);
            app.refreshFileList();
            app.Result = [];
            app.showQueue();
            app.updateControls();
            if n == 0
                UIKit.setStatus(app.StatusLabel, 'No new files added (already in the list or none found).', 'warning');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Added %d file(s); %d in the list. Next: check the settings (step 3) and Run batch.', ...
                    n, numel(app.Files)), 'success');
            end
        end

        %% removeFiles - Remove files by index (default: the selected ones)
        function removeFiles(app, idx)
            if nargin < 2
                sel = app.FileList.Value;
                if ischar(sel), sel = {sel}; end
                idx = find(ismember(app.FileList.ItemsData, sel));
            end
            idx = idx(idx >= 1 & idx <= numel(app.Files));
            if isempty(idx)
                UIKit.setStatus(app.StatusLabel, 'Select the files to remove first.', 'warning');
                return;
            end
            app.Files(idx) = [];
            app.refreshFileList();
            app.Result = [];
            app.showQueue();
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf('Removed %d file(s); %d left.', numel(idx), numel(app.Files)), 'info');
        end

        %% clearFiles - Empty the file list
        function clearFiles(app)
            app.Files = {};
            app.refreshFileList();
            app.Result = [];
            app.showQueue();
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, 'File list cleared. Add files (step 2).', 'info');
        end

        %% setParams - Fill the settings fields from a struct (other fields are kept too)
        function setParams(app, params)
            if isempty(params), return; end
            fn = fieldnames(params);
            for i = 1:numel(fn)
                name = fn{i};
                v = params.(name);
                if isfield(app.ParamControls, name)
                    c = app.ParamControls.(name);
                    kind = app.ParamSpec(strcmp({app.ParamSpec.name}, name)).kind;
                    switch kind
                        case 'vector',   c.Value = vectorText(v);
                        case 'checkbox', c.Value = logical(v);
                        case 'dropdown'
                            if ismember(char(v), c.Items), c.Value = char(v); end
                        case 'text',     c.Value = char(v);
                        otherwise,       c.Value = double(v);
                    end
                else
                    app.ExtraParams.(name) = v;
                end
            end
        end

        %% getParams - Settings from the fields (+ kept extras), complete
        function p = getParams(app)
            p = app.ExtraParams;
            for k = 1:numel(app.ParamSpec)
                s = app.ParamSpec(k);
                c = app.ParamControls.(s.name);
                switch s.kind
                    case 'vector'
                        txt = strtrim(regexprep(c.Value, '[,;]', ' '));
                        if isempty(txt)
                            v = [];
                        else
                            v = str2double(regexp(txt, '\s+', 'split'));
                        end
                    case 'checkbox', v = logical(c.Value);
                    otherwise,       v = c.Value;
                end
                p.(s.name) = v;
            end
            p = Batch.completeParams(app.Pipeline, p);
        end

        %% setOutputFolder - Where Batch.run writes the summary and the log
        function setOutputFolder(app, folder)
            app.OutFolder = char(folder);
            app.OutFolderLabel.Text = sprintf('Output: %s', shortPath(app.OutFolder, 44));
            app.OutFolderLabel.Tooltip = app.OutFolder;
        end

        %% runBatch - Run the batch (no dialogs); [ok, R] with R from Batch.run
        % outFolder optional (default: the step-4 output folder). ok is true
        % when the batch ran, even if some files failed (see the table).
        function [ok, R] = runBatch(app, outFolder)
            ok = false; R = [];
            if app.Running, return; end
            if nargin >= 2 && ~isempty(outFolder), app.setOutputFolder(outFolder); end
            if isempty(app.Files)
                UIKit.alert(app.UIFig, 'Add input files first (step 2).', 'Batch', 'warning');
                UIKit.setStatus(app.StatusLabel, 'No files to process: add files (step 2).', 'warning');
                return;
            end
            params = app.getParams();
            app.Running = true;
            app.CancelRequested = false;
            app.Result = [];
            app.showQueue();
            app.LogArea.Value = {''};
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf('Running the batch on %d file(s)...', numel(app.Files)), 'busy');
            try
                R = Batch.run(app.Pipeline, app.Files, params, app.OutFolder, ...
                    'Progress', @(k, n, f, st, msg) app.onProgress(k, n, f, st, msg), ...
                    'Cancel', @() app.cancelRequested());
            catch ME
                app.Running = false;
                app.updateControls();
                UIKit.setStatus(app.StatusLabel, sprintf('Batch failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('The batch could not run:\n%s', ME.message), 'Batch', 'error');
                return;
            end
            app.Running = false;
            app.Result = R;
            app.showSummary();
            app.LogArea.Value = R.log;
            ok = true;
            summaryText = sprintf('%d OK, %d with warnings, %d failed, %d skipped', R.nOK, R.nWarning, ...
                R.nError, R.nSkipped);
            app.ResultsInfoLabel.Text = sprintf('%s  ·  %d rows  ·  %.1f s  ·  %s', summaryText, ...
                height(R.summary), R.elapsed, R.paths.csv);
            app.ProgressLabel.Text = sprintf('Done: %d of %d file(s) processed', ...
                numel(R.files) - R.nSkipped, numel(R.files));
            app.updateControls();
            [~, nm, ex] = fileparts(R.paths.csv);
            if R.cancelled
                UIKit.setStatus(app.StatusLabel, sprintf('Batch cancelled: %s. Summary so far in %s%s.', ...
                    summaryText, nm, ex), 'warning');
            elseif R.nError > 0 || R.nWarning > 0
                UIKit.setStatus(app.StatusLabel, sprintf(['Batch done: %s (see the red / orange rows and the log). ' ...
                    'Summary: %s%s.'], summaryText, nm, ex), 'warning');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Batch done: %s. Summary: %s%s (Open folder, step 5).', ...
                    summaryText, nm, ex), 'success');
            end
        end

        %% cancelBatch - Stop before the next file
        function cancelBatch(app)
            if ~app.Running, return; end
            app.CancelRequested = true;
            UIKit.setStatus(app.StatusLabel, 'Cancelling after the current file...', 'warning');
        end

        %% loadDemo - Demo files for a pipeline (default: the current one) + settings
        function ok = loadDemo(app, pipeline)
            ok = false;
            if nargin < 2 || isempty(pipeline), pipeline = app.Pipeline; end
            if ~app.setPipeline(pipeline), return; end
            dlg = UIKit.busy(app.UIFig, sprintf('Writing demo files (first time only takes a few seconds)%s', char(8230)));
            UIKit.setStatus(app.StatusLabel, 'Preparing demo data', 'busy');
            try
                DemoData.ensureDemoPath();
                demo = demoBatch(app.Pipeline, fullfile(DemoData.folder(), 'batch', app.Pipeline));
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Demo data failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not create the demo data:\n%s', ME.message), 'Demo data');
                return;
            end
            UIKit.done(dlg);
            app.Files = {};
            app.addFiles(demo.files);
            app.setParams(demo.params);
            app.setOutputFolder(fullfile(DemoData.folder(), 'batch', 'results', app.Pipeline));
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, demoMessage(app.Pipeline, numel(demo.files)), 'success');
            ok = true;
        end

        %% exportSummary - Save the summary table (.csv / .xlsx: table; .mat: summary + batch)
        function ok = exportSummary(app, filePath)
            ok = false;
            if isempty(app.Result)
                UIKit.setStatus(app.StatusLabel, 'Nothing to export: run the batch first (step 4).', 'warning');
                return;
            end
            [~, nm, ext] = fileparts(filePath);
            try
                summary = app.Result.summary;
                if strcmpi(ext, '.mat')
                    batch = rmfield(app.Result, 'summary'); %#ok<NASGU>
                    save(filePath, 'summary', 'batch');
                else
                    writetable(summary, filePath);
                end
            catch ME
                UIKit.setStatus(app.StatusLabel, 'Export failed', 'error');
                UIKit.alert(app.UIFig, sprintf('Export failed:\n%s', ME.message), 'Export');
                return;
            end
            ok = true;
            UIKit.setStatus(app.StatusLabel, sprintf('Exported %d rows to %s%s.', height(app.Result.summary), nm, ext), 'success');
        end

        %% openOutputFolder - Show the output folder in the system file browser
        function openOutputFolder(app)
            folder = app.OutFolder;
            if ~isempty(app.Result), folder = app.Result.paths.folder; end
            if exist(folder, 'dir') ~= 7
                UIKit.setStatus(app.StatusLabel, 'The output folder does not exist yet: run the batch first.', 'warning');
                return;
            end
            try
                if ispc
                    winopen(folder);
                elseif ismac
                    system(sprintf('open "%s" &', folder));
                else
                    system(sprintf('xdg-open "%s" > /dev/null 2>&1 &', folder));
                end
                UIKit.setStatus(app.StatusLabel, sprintf('Opened %s', folder), 'info');
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Could not open the folder: %s', ME.message), 'error');
            end
        end

        %% ---------------- Dialog wrappers (buttons) ----------------

        function addFolderDialog(app)
            folder = uigetdir(startFolder(), 'Add every file of a folder');
            figure(app.UIFig);
            if isequal(folder, 0), UIKit.setStatus(app.StatusLabel, 'Add folder cancelled.', 'info'); return; end
            app.addFiles(folder);
        end

        function addFilesDialog(app)
            d = Batch.describe(app.Pipeline);
            pattern = strjoin(cellfun(@(e) ['*' e], d.extensions, 'UniformOutput', false), ';');
            [file, path] = uigetfile({pattern, sprintf('Input files (%s)', pattern)}, ...
                'Add input files', startFolder(), 'MultiSelect', 'on');
            figure(app.UIFig);
            if isequal(file, 0), UIKit.setStatus(app.StatusLabel, 'Add files cancelled.', 'info'); return; end
            if ischar(file), file = {file}; end
            app.addFiles(fullfile(path, file));
        end

        function chooseOutputFolder(app)
            folder = uigetdir(app.OutFolder, 'Output folder for the summary and the log');
            figure(app.UIFig);
            if isequal(folder, 0), return; end
            app.setOutputFolder(folder);
            UIKit.setStatus(app.StatusLabel, sprintf('Output folder: %s', folder), 'info');
        end

        function exportDialog(app)
            if isempty(app.Result), return; end
            [file, path] = uiputfile({'*.csv', 'CSV table (*.csv)'; '*.xlsx', 'Excel (*.xlsx)'; ...
                '*.mat', 'MAT file (*.mat)'}, 'Export summary', ...
                fullfile(app.Result.paths.folder, sprintf('batch_%s_summary.csv', app.Pipeline)));
            figure(app.UIFig);
            if isequal(file, 0), return; end
            app.exportSummary(fullfile(path, file));
        end
    end

    methods(Access = private)

        %% buildSettings - Settings card (step 3) for the current pipeline
        function buildSettings(app)
            T = UITheme;
            delete(app.SettingsCard.Children);
            app.ParamSpec = Batch.paramSpec(app.Pipeline);
            n = numel(app.ParamSpec);
            rh = [{22}, repmat({T.controlHeight}, 1, n)];
            g = uigridlayout(app.SettingsCard, [n + 1, 2], 'RowHeight', rh, ...
                'ColumnWidth', {'1.2x', '1x'}, 'Padding', [10 8 10 10], 'RowSpacing', 6, ...
                'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
            lbl = UIKit.step(g, 3, 'Settings (same for every file)');
            lbl.Layout.Row = 1; lbl.Layout.Column = [1 2];
            app.SettingsGrid = g;
            app.ParamControls = struct();
            for k = 1:n
                s = app.ParamSpec(k);
                switch s.kind
                    case 'vector',   c = UIKit.field(g, s.label, 'text', vectorText(s.value), s.tooltip);
                    case 'dropdown', c = UIKit.field(g, s.label, 'dropdown', {s.items, s.value}, s.tooltip);
                    case 'checkbox', c = UIKit.field(g, s.label, 'checkbox', logical(s.value), s.tooltip);
                    case 'text',     c = UIKit.field(g, s.label, 'text', s.value, s.tooltip);
                    otherwise,       c = UIKit.field(g, s.label, 'numeric', s.value, s.tooltip, s.limits);
                end
                app.ParamControls.(s.name) = c;
            end
            h = sum([rh{:}]) + 6 * (numel(rh) - 1) + 18 + 4;
            app.CardHeights{1} = h;
            app.LeftGrid.RowHeight = app.CardHeights;
        end

        %% refreshFileList - List box items (names) with full paths as data
        function refreshFileList(app)
            names = cell(size(app.Files));
            for i = 1:numel(app.Files)
                [~, nm, ex] = fileparts(app.Files{i});
                names{i} = sprintf('%d. %s%s', i, nm, ex);
            end
            app.FileList.Items = names;
            app.FileList.ItemsData = app.Files;
            app.FileList.Value = {};
        end

        %% showQueue - Table of the input files with their status
        function showQueue(app, status, messages)
            n = numel(app.Files);
            if nargin < 2, status = repmat({'queued'}, n, 1); end
            if nargin < 3, messages = repmat({''}, n, 1); end
            names = cell(n, 1);
            for i = 1:n
                [~, nm, ex] = fileparts(app.Files{i});
                names{i} = [nm ex];
            end
            app.Table.Data = table(names, status(:), messages(:), 'VariableNames', {'File', 'Status', 'Message'});
            app.colourRows();
        end

        %% showSummary - The summary table of the last batch
        function showSummary(app)
            app.Table.Data = app.Result.summary;
            app.colourRows();
        end

        %% colourRows - Row colours from the Status column
        function colourRows(app)
            T = UITheme;
            tbl = app.Table;
            try removeStyle(tbl); catch, end
            d = tbl.Data;
            if ~istable(d) || height(d) == 0 || ~ismember('Status', d.Properties.VariableNames), return; end
            kinds = {'ok', T.success; 'warning', T.warning; 'error', T.danger; ...
                'skipped', T.mutedColor; 'running', T.info};
            for i = 1:size(kinds, 1)
                rows = find(strcmp(d.Status, kinds{i, 1}));
                if isempty(rows), continue; end
                c = kinds{i, 2};
                tint = 0.82 * T.cardBg + 0.18 * c;
                addStyle(tbl, uistyle('BackgroundColor', tint, 'FontColor', T.sectionTitleColor), 'row', rows);
                col = find(strcmp(d.Properties.VariableNames, 'Status'), 1);
                addStyle(tbl, uistyle('FontColor', c, 'FontWeight', 'bold'), 'cell', ...
                    [rows(:), repmat(col, numel(rows), 1)]);
            end
        end

        %% onProgress - Batch.run callback: status bar, step label, table row
        function onProgress(app, k, n, fileName, status, msg)
            d = app.Table.Data;
            if istable(d) && height(d) >= k && ismember('Status', d.Properties.VariableNames)
                d.Status{k} = status;
                d.Message{k} = msg;
                app.Table.Data = d;
                app.colourRows();
            end
            if strcmp(status, 'running')
                app.ProgressLabel.Text = sprintf('File %d of %d: %s', k, n, fileName);
                UIKit.setStatus(app.StatusLabel, sprintf('Processing file %d of %d: %s', k, n, fileName), 'busy');
            else
                app.ProgressLabel.Text = sprintf('File %d of %d: %s (%s)', k, n, fileName, status);
            end
            drawnow;
        end

        %% cancelRequested - Batch.run's Cancel callback (processes the Cancel click)
        function tf = cancelRequested(app)
            drawnow;
            tf = app.CancelRequested;
        end
    end
end

%% Local helpers
% -------------------------------------------------------------------------

%% batchLabel - Menu label of a pipeline key
function s = batchLabel(key)
    d = Batch.describe(key);
    s = d.label;
end

%% demoMessage - Status text after loadDemo: what the demo contains and what to expect
function s = demoMessage(pipeline, n)
    switch pipeline
        case 'ldf'
            s = sprintf(['Demo loaded: %d cropped LDF recordings (7 stimuli each) with responses of 20, 25, 30 ' ...
                'and 35 PU peaking 3, 3.5, 4 and 4.5 s after onset. Next: Run batch: expect 6 trials per file.'], n);
        case 'erp'
            s = sprintf(['Demo loaded: %d LFP recordings (8 channels, 10 stimuli) with N1 at 12, 15 and 18 ms and ' ...
                'the CSD sink on channels 3, 4 and 5. Next: Run batch.'], n);
        case 'mua'
            s = sprintf(['Demo loaded: %d MUA recordings (the demo recording and a copy at twice the gain), ' ...
                'channel 4. Next: Run batch: expect 2-3 units and the same spike count in both files.'], n);
        case 'roi'
            s = sprintf(['Demo loaded: %d image stacks with a cell (peak dF/F 0.5, 1.0, 1.5) and a vessel ' ...
                '(mean diameter 10, 12, 14 px) crossed by the line 25 50 63 50. Next: Run batch.'], n);
        otherwise
            s = sprintf(['Demo loaded: %d trial files (8 trials each) with responses of 20, 25, 30 and 35 PU ' ...
                'peaking 3, 3.5, 4 and 4.5 s after onset. Next: Run batch.'], n);
    end
end

%% emptyQueue - Empty File / Status / Message table
function t = emptyQueue()
    t = table(cell(0, 1), cell(0, 1), cell(0, 1), 'VariableNames', {'File', 'Status', 'Message'});
end

%% defaultOutFolder - Export folder of the project (else tempdir) / batch
function f = defaultOutFolder()
    base = '';
    try base = ProjectManager.getExportDir(); catch, end
    if isempty(base), base = tempdir; end
    f = fullfile(base, 'batch');
end

%% startFolder - Where the file dialogs open
function f = startFolder()
    f = '';
    try f = ProjectManager.getImportDir(); catch, end
    if isempty(f), f = pwd; end
end

%% vectorText - Numbers as "a b c" (empty -> '')
function s = vectorText(v)
    if isempty(v)
        s = '';
    elseif ischar(v)
        s = v;
    else
        s = strtrim(sprintf('%g ', v));
    end
end

%% shortPath - '...' + the end of a long path
function s = shortPath(p, maxLen)
    if length(p) <= maxLen
        s = p;
    else
        s = ['...' p(end - maxLen + 4:end)];
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
    h = [];
    if nargout > 2, h = sum([rh{:}]) + 6 * (numel(rh) - 1) + 18 + 4; end
end

%% infoLabel - Small wrapped muted label for file/result summaries
function lbl = infoLabel(parent, text, tooltip)
    T = UITheme;
    lbl = uilabel(parent, 'Text', text, 'FontSize', T.fontSmall, 'FontColor', T.bodyColor, ...
        'WordWrap', 'on', 'VerticalAlignment', 'top', 'Tooltip', tooltip, 'Interpreter', 'none');
end

%% styleBtn - Switch a button between primary and secondary look (danger buttons untouched)
function styleBtn(b, isPrimary)
    T = UITheme;
    if isPrimary
        b.BackgroundColor = T.accent; b.FontColor = [1 1 1]; b.FontWeight = 'bold';
    else
        b.BackgroundColor = T.secondaryBg; b.FontColor = T.secondaryFg; b.FontWeight = 'normal';
    end
end

%% setEnable - Enable / disable a list of controls
function setEnable(ctrls, tf)
    for i = 1:numel(ctrls)
        ctrls{i}.Enable = onOff(tf);
    end
end

%% onOff - 'on' / 'off' from a logical
function s = onOff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end
