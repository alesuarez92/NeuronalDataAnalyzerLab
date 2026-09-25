%% VirtualLabApp.m
% =========================================================================
% VIRTUAL LAB - PLAN, RECORD AND ANALYSE A SIMULATED EXPERIMENT
% =========================================================================
% Launched from Main ("Virtual lab"). Built with UIKit.window: numbered
% step cards on the left (1 Learn, 2 Plan, 3 Record, 4 Report your
% results, 5 Instructor) and tabs on the right (Learn | Plan | Recording |
% Feedback). The student reads how the technique works, plans the
% experiment (probe position, stimulus, number of stimuli, time between
% them, baseline, sampling rate: the Plan tab previews the protocol as the
% values change), records it (core/VirtualLab.m simulates a LabChart
% export with a known answer, different for every student name), analyses
% the file in the normal windows (Open in Extract LDF), types the numbers
% into step 4, optionally attaches the session files saved in Process LDF
% / Average LDF, and gets feedback on the plan, the processing and the
% numbers (Check my results). The reference values stay hidden until
% "Show solution" (recorded in the submission). Save submission… writes a
% .navlab.mat for an instructor; Grade a folder… grades many (CSV).
% Programmatic use (no dialogs): loadDemo(), setStudent(id), setDesign(d), d =
% currentDesign(), recordTo(path), openInExtract(), setAnswers(a),
% attachSessions(paths), g = checkResults(), showSolution(),
% saveSubmissionTo(path), T = gradeFolderTo(folder, csvPath).
% =========================================================================

classdef VirtualLabApp < handle

    properties
        UIFig           % Main uifigure (UIKit.window)
        StatusLabel     % Status bar label (UIKit.setStatus)
        HelpBtn         % Opens HelpApp('Virtual lab')
        Tabs            % Right: Learn | Plan | Recording | Feedback
        LearnBtn        % Step 1: show the Learn tab
        StudentInput    % Step 2: student name or ID (seeds the data)
        ProbeDrop       % Step 2: probe position
        StimInput       % Step 2: stimulus duration (s)
        NStimInput      % Step 2: number of stimuli
        ISIInput        % Step 2: time between stimuli (s)
        BaselineInput   % Step 2: baseline before the first stimulus (s)
        RateDrop        % Step 2: sampling rate
        PlanInfo        % Step 2: duration, samples, file size or why not possible
        RecordBtn       % Step 3: record (save the simulated export)
        OpenExtractBtn  % Step 3: open Extract LDF with the recording
        RecordInfo      % Step 3: file written
        AnswerInputs    % Step 4: struct of numeric fields (baselinePU ...)
        AttachBtn       % Step 4: attach session files
        AttachInfo      % Step 4: attached sessions
        CheckBtn        % Step 4: grade
        SolutionBtn     % Step 4: reveal the reference values
        SubmitBtn       % Step 4: save submission
        GradeFolderBtn  % Step 5: grade a folder of submissions
        LearnText       % Learn tab text
        AxPlan          % Plan tab: protocol preview
        AxStim          % Recording tab: stimulus
        AxLDF           % Recording tab: LDF
        ScoreLabel      % Feedback tab: score line
        FeedbackTable   % Feedback tab: one row per item
        FeedbackText    % Feedback tab: explanations
        RecordingPath = ''      % last recording written
        RecordedDesign = []     % plan of that recording
        RecordedStudent = ''    % student of that recording
        Sessions = {}           % attached session structs
        SessionNames = {}       % their file names
        LastGrade = []          % last VirtualLab.grade result
        Attempts = 0            % Check my results clicks
        SolutionShown = false   % Show solution used
    end

    methods
        %% Constructor
        function app = VirtualLabApp()
            app.buildUI();
        end

        %% buildUI - Window, step cards (left), tabs (right)
        function buildUI(app)
            T = UITheme;
            sc = VirtualLab.scenario();
            W = UIKit.window('Virtual Lab', ...
                ['Plan and record a simulated experiment, analyse it yourself, and get feedback  ·  ' sc.title], ...
                'Virtual lab', [1250 820]);
            app.UIFig = W.Fig;
            app.StatusLabel = W.Status;
            app.HelpBtn = W.HelpBtn;
            W.Body.RowHeight = {'1x'};
            W.Body.ColumnWidth = {330, '1x'};

            left = uigridlayout(W.Body, [6 1], 'Padding', [0 0 0 0], 'RowSpacing', 10, ...
                'BackgroundColor', T.bgGray, 'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;
            heights = cell(1, 6);

            % --- 1 Learn ---
            [p, g, heights{1}] = stepCard(left, 1, 'Learn the technique', {48, T.buttonHeight});
            p.Layout.Row = 1;
            h = infoLabel(g, sc.question, 'The question this experiment answers');
            h.Layout.Row = 2; h.Layout.Column = [1 2];
            h.FontColor = T.sectionTitleColor;
            app.LearnBtn = UIKit.button(g, 'How LDF works', @(~,~)app.selectTab('Learn'), 'secondary', ...
                'How laser Doppler flowmetry measures blood flow, what the signal looks like and what you will do');
            app.LearnBtn.Layout.Row = 3; app.LearnBtn.Layout.Column = [1 2];

            % --- 2 Plan ---
            ch = T.controlHeight;
            [p, g, heights{2}] = stepCard(left, 2, 'Plan the experiment', {ch, ch, ch, ch, ch, ch, ch, 48});
            p.Layout.Row = 2;
            d = VirtualLab.defaultDesign();
            L = sc.limits;
            app.StudentInput = addField(g, 2, 'Your name or ID', 'text', '', ...
                'Your data are generated from this name: use the same name every time (your instructor may give you an ID)');
            app.ProbeDrop = addField(g, 3, 'Probe position', 'dropdown', {VirtualLab.Probes, d.probe}, ...
                'Where the LDF probe is placed on the skull / cortex');
            app.StimInput = addField(g, 4, 'Stimulus (s)', 'numeric', d.stimS, ...
                'How long the whiskers are stimulated each time, in seconds', L.stimS);
            app.NStimInput = addField(g, 5, 'Number of stimuli', 'numeric', d.nStim, ...
                'How many times the stimulus is repeated (one trial each)', L.nStim);
            app.ISIInput = addField(g, 6, 'Time between (s)', 'numeric', d.isiS, ...
                'Time from the start of one stimulus to the start of the next, in seconds', L.isiS);
            app.BaselineInput = addField(g, 7, 'Baseline first (s)', 'numeric', d.baselineS, ...
                'Recording time before the first stimulus, in seconds', L.baselineS);
            rates = arrayfun(@(r) sprintf('%g Hz', r), VirtualLab.Rates, 'UniformOutput', false);
            app.RateDrop = addField(g, 8, 'Sampling rate', 'dropdown', {rates, sprintf('%g Hz', d.fs)}, ...
                'Samples per second recorded on each channel');
            app.PlanInfo = infoLabel(g, '', 'Length and size of the recording, or why the plan is not possible');
            app.PlanInfo.Layout.Row = 9; app.PlanInfo.Layout.Column = [1 2];
            for c = {app.StudentInput, app.ProbeDrop, app.StimInput, app.NStimInput, app.ISIInput, ...
                    app.BaselineInput, app.RateDrop}
                c{1}.ValueChangedFcn = @(~,~)app.planChanged();
            end
            app.NStimInput.RoundFractionalValues = 'on';

            % --- 3 Record ---
            [p, g, heights{3}] = stepCard(left, 3, 'Record', {T.buttonHeight, T.buttonHeight, 48});
            p.Layout.Row = 3;
            app.RecordBtn = UIKit.button(g, 'Record…', @(~,~)app.recordDialog(), 'primary', ...
                'Run the experiment: saves the recording (LabChart export .mat: stimulus = channel 6, LDF = channel 8)');
            app.RecordBtn.Layout.Row = 2; app.RecordBtn.Layout.Column = [1 2];
            app.OpenExtractBtn = UIKit.button(g, 'Open in Extract LDF', @(~,~)app.openInExtract(), 'secondary', ...
                'Start the analysis: opens Extract LDF with your recording (then Process LDF and Average LDF)');
            app.OpenExtractBtn.Layout.Row = 3; app.OpenExtractBtn.Layout.Column = [1 2];
            app.RecordInfo = infoLabel(g, 'Not recorded yet', 'The recording file');
            app.RecordInfo.Layout.Row = 4; app.RecordInfo.Layout.Column = [1 2];

            % --- 4 Report your results ---
            [p, g, heights{4}] = stepCard(left, 4, 'Report your results', ...
                {ch, ch, ch, ch, ch, T.buttonHeight, 34, T.buttonHeight, T.buttonHeight});
            p.Layout.Row = 4;
            spec = { ...
                'baselinePU', 'Baseline (PU)', 'Mean LDF before the stimuli (Average LDF, step 3)'; ...
                'peakChangePU', 'Peak increase (PU)', 'Highest point of the mean trial minus the baseline'; ...
                'peakPercent', 'Peak increase (%)', '100 x peak increase / baseline'; ...
                'peakLatencyS', 'Time to peak (s)', 'Seconds from stimulus onset to the highest point of the mean trial'; ...
                'nTrials', 'Trials averaged', 'How many trials went into your average'};
            app.AnswerInputs = struct();
            for k = 1:size(spec, 1)
                f = addField(g, k + 1, spec{k, 2}, 'numeric', 0, spec{k, 3});
                f.AllowEmpty = 'on'; f.Value = [];
                f.ValueChangedFcn = @(~,~)app.updateControls();
                app.AnswerInputs.(spec{k, 1}) = f;
            end
            app.AttachBtn = UIKit.button(g, 'Attach sessions…', @(~,~)app.attachDialog(), 'secondary', ...
                'Optional: the session files you saved in Process LDF and Average LDF, so your settings can be checked too');
            app.AttachBtn.Layout.Row = 7; app.AttachBtn.Layout.Column = [1 2];
            app.AttachInfo = infoLabel(g, 'No sessions attached (optional)', 'Attached session files');
            app.AttachInfo.Layout.Row = 8; app.AttachInfo.Layout.Column = [1 2];
            app.CheckBtn = UIKit.button(g, 'Check my results', @(~,~)app.checkResults(), 'secondary', ...
                'Feedback on your plan, processing and numbers (the reference values stay hidden)');
            app.CheckBtn.Layout.Row = 9; app.CheckBtn.Layout.Column = [1 2];
            app.SolutionBtn = UIKit.button(g, 'Show solution', @(~,~)app.showSolution(), 'secondary', ...
                'Show the reference values and the true answer (noted in your submission)');
            app.SolutionBtn.Layout.Row = 10; app.SolutionBtn.Layout.Column = 1;
            app.SubmitBtn = UIKit.button(g, 'Save submission…', @(~,~)app.submitDialog(), 'secondary', ...
                'Save your plan, numbers and sessions as a .navlab.mat file for your instructor');
            app.SubmitBtn.Layout.Row = 10; app.SubmitBtn.Layout.Column = 2;

            % --- 5 Instructor ---
            [p, g, heights{5}] = stepCard(left, 5, 'Instructor', {34, T.buttonHeight});
            p.Layout.Row = 5;
            h = infoLabel(g, 'Grade every .navlab.mat submission in a folder into one table (CSV).', ...
                'Each submission is re-created from its student name and plan; nothing needs to be installed');
            h.Layout.Row = 2; h.Layout.Column = [1 2];
            app.GradeFolderBtn = UIKit.button(g, 'Grade a folder…', @(~,~)app.gradeFolderDialog(), 'secondary', ...
                'Choose a folder of submissions; writes virtual_lab_grades.csv in it');
            app.GradeFolderBtn.Layout.Row = 3; app.GradeFolderBtn.Layout.Column = [1 2];
            heights{6} = '1x';
            left.RowHeight = heights;

            % --- Tabs ---
            app.Tabs = uitabgroup(W.Body);
            app.Tabs.Layout.Row = 1; app.Tabs.Layout.Column = 2;
            tl = uitab(app.Tabs, 'Title', 'Learn', 'BackgroundColor', T.cardBg);
            gl = uigridlayout(tl, [1 1], 'Padding', [12 12 12 12], 'BackgroundColor', T.cardBg);
            app.LearnText = uitextarea(gl, 'Value', splitlines(VirtualLab.learnText()), 'Editable', 'off', ...
                'FontSize', T.fontBody + 1, 'FontColor', T.sectionTitleColor, 'BackgroundColor', T.cardBg);

            tp = uitab(app.Tabs, 'Title', 'Plan', 'BackgroundColor', T.cardBg);
            gp = uigridlayout(tp, [1 1], 'Padding', [8 8 14 8], 'BackgroundColor', T.cardBg);
            app.AxPlan = uiaxes(gp);

            tr = uitab(app.Tabs, 'Title', 'Recording', 'BackgroundColor', T.cardBg);
            gr = uigridlayout(tr, [2 1], 'RowHeight', {'1x', '2x'}, 'Padding', [8 8 14 8], ...
                'RowSpacing', 8, 'BackgroundColor', T.cardBg);
            app.AxStim = uiaxes(gr);
            app.AxLDF = uiaxes(gr);
            UIKit.styleAxes(app.AxStim, 'Stimulus (channel 6)');
            UIKit.styleAxes(app.AxLDF, 'LDF (channel 8)');
            UIKit.emptyAxes(app.AxStim, 'Record (step 3) to see the raw signals');
            UIKit.emptyAxes(app.AxLDF, 'LDF recording appears here');

            tf = uitab(app.Tabs, 'Title', 'Feedback', 'BackgroundColor', T.cardBg);
            gf = uigridlayout(tf, [3 1], 'RowHeight', {30, '1x', '1x'}, 'Padding', [10 10 10 10], ...
                'RowSpacing', 8, 'BackgroundColor', T.cardBg);
            app.ScoreLabel = uilabel(gf, 'Text', 'Report your results (step 4) and click "Check my results".', ...
                'FontSize', T.fontBody + 2, 'FontWeight', 'bold', 'FontColor', T.sectionTitleColor, ...
                'Interpreter', 'none');
            app.FeedbackTable = uitable(gf, 'ColumnName', {'Part', 'Item', 'Result', 'Yours', 'Target'}, ...
                'ColumnWidth', {100, 220, 70, 190, '1x'}, 'RowName', {}, 'FontSize', T.fontSmall + 1, ...
                'CellSelectionCallback', @(~, e)app.showItem(e));
            app.FeedbackText = uitextarea(gf, 'Value', {''}, 'Editable', 'off', 'FontSize', T.fontBody, ...
                'FontColor', T.sectionTitleColor);

            app.planChanged();
            UIKit.setStatus(app.StatusLabel, ['Step 1: read how LDF works (Learn tab), then type your name ' ...
                'and plan the experiment (step 2).'], 'info');
        end

        %% ----------------------------------------------------------------
        %% Plan
        %% currentDesign - The plan as typed (VirtualLab design struct)
        function d = currentDesign(app)
            d = struct('probe', app.ProbeDrop.Value, 'stimS', app.StimInput.Value, ...
                'nStim', app.NStimInput.Value, 'isiS', app.ISIInput.Value, ...
                'baselineS', app.BaselineInput.Value, 'fs', sscanf(app.RateDrop.Value, '%g'));
        end

        %% setDesign - Set the plan fields (missing fields keep their value)
        function setDesign(app, d)
            if isfield(d, 'probe'), app.ProbeDrop.Value = d.probe; end
            if isfield(d, 'stimS'), app.StimInput.Value = d.stimS; end
            if isfield(d, 'nStim'), app.NStimInput.Value = d.nStim; end
            if isfield(d, 'isiS'), app.ISIInput.Value = d.isiS; end
            if isfield(d, 'baselineS'), app.BaselineInput.Value = d.baselineS; end
            if isfield(d, 'fs'), app.RateDrop.Value = sprintf('%g Hz', d.fs); end
            app.planChanged();
        end

        %% setStudent - Name or ID that seeds the data
        function setStudent(app, id)
            app.StudentInput.Value = char(id);
            app.planChanged();
        end

        %% planChanged - Live preview: protocol plot, duration and size
        function planChanged(app)
            T = UITheme;
            d = app.currentDesign();
            msg = VirtualLab.validateDesign(d);
            ax = app.AxPlan;
            cla(ax);
            if isempty(msg)
                info = VirtualLab.describeDesign(d);
                app.PlanInfo.Text = info.text;
                app.PlanInfo.FontColor = T.sectionTitleColor;
                tt = [0, reshape([info.onsetsS; info.onsetsS; info.onsetsS + d.stimS; info.onsetsS + d.stimS], 1, []), info.durationS];
                yy = [0, repmat([0 1 1 0], 1, d.nStim), 0];
                area(ax, tt, yy, 'FaceColor', T.stimColor, 'EdgeColor', T.stimColor, 'FaceAlpha', 0.5);
                ax.YLim = [0 1.6]; ax.XLim = [0 info.durationS];
                ax.YTick = [];
                text(ax, 0, 1.35, sprintf(['  %d stimuli of %g s, one every %g s, after %g s of baseline  ·  ' ...
                    'recording %s at %g Hz'], d.nStim, d.stimS, d.isiS, d.baselineS, ...
                    durationText(info.durationS), d.fs), 'FontSize', T.fontSmall + 1, ...
                    'Color', T.sectionTitleColor, 'Interpreter', 'none');
                UIKit.styleAxes(ax, 'Your protocol (stimulus on = shaded)', 'Time (s)', '');
            else
                app.PlanInfo.Text = msg;
                app.PlanInfo.FontColor = T.danger;
                UIKit.styleAxes(ax, 'Your protocol', 'Time (s)', '');
                UIKit.emptyAxes(ax, msg);
            end
            app.updateControls();
        end

        %% loadDemo - Demo student with a good plan, recorded to the demo folder
        % Student 'Demo student', probe over the barrel, 5 s stimuli, 15
        % stimuli every 25 s after 30 s of baseline, 40 Hz. Used by Help →
        % Virtual lab → Try it.
        function ok = loadDemo(app)
            app.setStudent('Demo student');
            app.setDesign(struct('probe', VirtualLab.Probes{1}, 'stimS', 5, 'nStim', 15, ...
                'isiS', 25, 'baselineS', 30, 'fs', 40));
            folder = DemoData.folder();
            if ~exist(folder, 'dir'), mkdir(folder); end
            ok = app.recordTo(fullfile(folder, 'virtual_ldf_demo_student.mat'));
        end

        %% ----------------------------------------------------------------
        %% Record
        %% recordDialog - Ask where to save, then record
        function recordDialog(app)
            if ~app.checkStudent(), return; end
            start = ProjectManager.getExportDir();
            if isempty(start), start = pwd; end
            name = sprintf('virtual_ldf_%s.mat', fileTag(app.StudentInput.Value));
            [f, p] = uiputfile('*.mat', 'Save the recording as', fullfile(start, name));
            figure(app.UIFig);
            if isequal(f, 0), return; end
            app.recordTo(fullfile(p, f));
        end

        %% recordTo - Simulate the recording, save it and plot it (no dialog)
        function ok = recordTo(app, filePath)
            ok = false;
            if ~app.checkStudent(), return; end
            d = app.currentDesign();
            msg = VirtualLab.validateDesign(d);
            if ~isempty(msg)
                UIKit.setStatus(app.StatusLabel, msg, 'error');
                return;
            end
            dlg = UIKit.busy(app.UIFig, 'Recording…');
            try
                p = VirtualLab.recordTo(filePath, app.StudentInput.Value, d);
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not save the recording: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not save the recording:\n%s', ME.message), 'Record', 'error');
                return;
            end
            app.RecordingPath = p;
            app.RecordedDesign = d;
            app.RecordedStudent = app.StudentInput.Value;
            app.LastGrade = [];
            [~, n, e] = fileparts(p);
            app.RecordInfo.Text = sprintf('%s%s\n%s', n, e, VirtualLab.describeDesign(d).text);
            app.RecordInfo.FontColor = UITheme.sectionTitleColor;
            app.plotRecording();
            app.selectTab('Recording');
            app.updateControls();
            ok = true;
            UIKit.setStatus(app.StatusLabel, ['Recorded. Next: click "Open in Extract LDF" and analyse the ' ...
                'recording (Extract → Process → Average), then report your numbers in step 4.'], 'success');
        end

        %% plotRecording - Raw stimulus and LDF of the last recording
        function plotRecording(app)
            T = UITheme;
            rec = load(app.RecordingPath);
            stim = rec.data(rec.datastart(6):rec.dataend(6));
            ldf = rec.data(rec.datastart(8):rec.dataend(8));
            t = (0:numel(ldf) - 1) / rec.samplerate(8);
            cla(app.AxStim); cla(app.AxLDF);
            plot(app.AxStim, t, stim, 'Color', T.stimColor);
            plot(app.AxLDF, t, ldf, 'Color', T.plotColors(1, :));
            UIKit.styleAxes(app.AxStim, 'Stimulus (channel 6)', '', 'V');
            UIKit.styleAxes(app.AxLDF, 'LDF (channel 8): the raw recording, as the acquisition software saved it', ...
                'Time (s)', 'PU');
            linkaxes([app.AxStim, app.AxLDF], 'x');
            app.AxLDF.XLim = [0 t(end)];
        end

        %% openInExtract - Open Extract LDF with the recording (returns the window)
        function win = openInExtract(app)
            win = [];
            if isempty(app.RecordingPath) || exist(app.RecordingPath, 'file') ~= 2
                UIKit.setStatus(app.StatusLabel, 'Record first (step 3).', 'warning');
                return;
            end
            win = ExtractLDFApp();
            win.openFile(app.RecordingPath);
            UIKit.setStatus(app.StatusLabel, ['Extract LDF opened with your recording. Crop, save, then ' ...
                'continue in Process LDF and Average LDF (launcher, LDF card).'], 'success');
        end

        %% ----------------------------------------------------------------
        %% Report and feedback
        %% setAnswers - Fill step 4 (struct with VirtualLab.emptyAnswers fields)
        function setAnswers(app, a)
            f = fieldnames(app.AnswerInputs);
            for k = 1:numel(f)
                if isfield(a, f{k})
                    v = a.(f{k});
                    if isempty(v) || ~isfinite(v), v = []; end
                    app.AnswerInputs.(f{k}).Value = v;
                end
            end
            app.updateControls();
        end

        %% answers - The numbers typed in step 4 (NaN when empty)
        function a = answers(app)
            a = VirtualLab.emptyAnswers();
            f = fieldnames(a);
            for k = 1:numel(f)
                v = app.AnswerInputs.(f{k}).Value;
                if ~isempty(v), a.(f{k}) = v; end
            end
        end

        %% attachDialog - Choose session files (multi-select)
        function attachDialog(app)
            start = UIKit.sessionFolder(app);
            [f, p] = uigetfile({'*.nasession.mat', 'NeuroAnalyzer sessions'}, ...
                'Sessions saved in Process LDF / Average LDF', start, 'MultiSelect', 'on');
            figure(app.UIFig);
            if isequal(f, 0), return; end
            app.attachSessions(fullfile(p, cellstr(f)));
        end

        %% attachSessions - Load session files (replaces the attached list)
        function n = attachSessions(app, paths)
            paths = cellstr(paths);
            app.Sessions = {}; app.SessionNames = {};
            bad = {};
            for k = 1:numel(paths)
                try
                    app.Sessions{end + 1} = Session.load(paths{k});
                    [~, nm, e] = fileparts(paths{k});
                    app.SessionNames{end + 1} = [nm e];
                catch ME
                    bad{end + 1} = sprintf('%s (%s)', paths{k}, ME.message); %#ok<AGROW>
                end
            end
            n = numel(app.Sessions);
            if n == 0
                app.AttachInfo.Text = 'No sessions attached (optional)';
            else
                wins = cellfun(@(s) s.appTitle, app.Sessions, 'UniformOutput', false);
                app.AttachInfo.Text = sprintf('%d attached: %s', n, strjoin(wins, ', '));
            end
            if ~isempty(bad)
                UIKit.setStatus(app.StatusLabel, sprintf('Not a session file: %s', strjoin(bad, '; ')), 'error');
            end
        end

        %% checkResults - Grade and show the feedback (reference values hidden)
        function g = checkResults(app)
            g = [];
            if isempty(app.RecordingPath)
                UIKit.setStatus(app.StatusLabel, 'Record the experiment first (step 3).', 'warning');
                return;
            end
            dlg = UIKit.busy(app.UIFig, 'Checking…');
            try
                g = VirtualLab.grade(app.RecordedStudent, app.RecordedDesign, app.answers(), app.Sessions);
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not check the results: %s', ME.message), 'error');
                return;
            end
            app.Attempts = app.Attempts + 1;
            app.LastGrade = g;
            app.showFeedback();
            app.selectTab('Feedback');
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf(['Score %s. Click a row for the explanation; fix what is ' ...
                'orange or red and check again.'], g.summary), 'success');
        end

        %% showSolution - Reveal the reference values and the true answer
        function showSolution(app)
            if isempty(app.LastGrade)
                app.checkResults();
                if isempty(app.LastGrade), return; end
            end
            app.SolutionShown = true;
            app.showFeedback();
            app.selectTab('Feedback');
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, 'Solution shown (this is noted in your submission).', 'info');
        end

        %% showFeedback - Fill the Feedback tab from LastGrade
        function showFeedback(app)
            T = UITheme;
            g = app.LastGrade;
            items = g.items;
            hide = ~app.SolutionShown & (strcmp({items.section}, 'Your results') | strcmp({items.section}, 'What was true'));
            target = {items.reference};
            target(hide) = {'(hidden until "Show solution")'};
            label = struct('pass', 'OK', 'check', 'Check', 'fail', 'Fix', 'info', 'Info');
            res = cellfun(@(s) label.(s), {items.status}, 'UniformOutput', false);
            app.FeedbackTable.Data = [{items.section}', {items.item}', res', {items.yours}', target'];
            removeStyle(app.FeedbackTable);
            colors = struct('pass', T.success, 'check', T.warning, 'fail', T.danger, 'info', T.info);
            for s = fieldnames(colors)'
                rows = find(strcmp({items.status}, s{1}));
                if ~isempty(rows)
                    addStyle(app.FeedbackTable, uistyle('FontColor', colors.(s{1})), 'cell', ...
                        [rows(:), 3 * ones(numel(rows), 1)]);
                end
            end
            lines = {};
            for k = 1:numel(items)
                if hide(k) && strcmp(items(k).section, 'What was true'), continue; end
                lines{end + 1} = sprintf('[%s] %s: %s', res{k}, items(k).item, items(k).feedback); %#ok<AGROW>
            end
            app.FeedbackText.Value = lines;
            extra = '';
            if app.SolutionShown, extra = '  ·  solution shown'; end
            app.ScoreLabel.Text = sprintf('Score %s  ·  attempt %d%s', g.summary, app.Attempts, extra);
        end

        %% showItem - Explanation of the selected row
        function showItem(app, e)
            if isempty(app.LastGrade) || isempty(e.Indices), return; end
            k = e.Indices(1, 1);
            it = app.LastGrade.items(k);
            if ~app.SolutionShown && strcmp(it.section, 'What was true'), return; end
            app.FeedbackText.Value = {sprintf('%s: %s', it.item, it.feedback)};
        end

        %% submitDialog - Save the submission (.navlab.mat)
        function submitDialog(app)
            if ~app.checkStudent(), return; end
            start = UIKit.sessionFolder(app);
            name = sprintf('%s_virtual_lab%s', fileTag(app.RecordedStudent), VirtualLab.Extension);
            [f, p] = uiputfile(['*' VirtualLab.Extension], 'Save submission', fullfile(start, name));
            figure(app.UIFig);
            if isequal(f, 0), return; end
            app.saveSubmissionTo(fullfile(p, f));
        end

        %% saveSubmissionTo - Write the submission (no dialog); returns the path or ''
        function out = saveSubmissionTo(app, filePath)
            out = '';
            if isempty(app.RecordingPath)
                UIKit.setStatus(app.StatusLabel, 'Record the experiment first (step 3).', 'warning');
                return;
            end
            sub = VirtualLab.submission(app.RecordedStudent, app.RecordedDesign, app.answers(), ...
                app.Sessions, app.Attempts, app.SolutionShown);
            try
                out = VirtualLab.saveSubmission(filePath, sub);
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Could not save the submission: %s', ME.message), 'error');
                return;
            end
            [~, n, e] = fileparts(out);
            UIKit.setStatus(app.StatusLabel, sprintf('Submission saved: %s%s. Send it to your instructor.', n, e), 'success');
        end

        %% gradeFolderDialog - Instructor: choose a folder, grade, write CSV
        function gradeFolderDialog(app)
            folder = uigetdir(UIKit.sessionFolder(app), 'Folder with .navlab.mat submissions');
            figure(app.UIFig);
            if isequal(folder, 0), return; end
            app.gradeFolderTo(folder, fullfile(folder, 'virtual_lab_grades.csv'));
        end

        %% gradeFolderTo - Grade every submission in folder (no dialog)
        function T = gradeFolderTo(app, folder, csvPath)
            dlg = UIKit.busy(app.UIFig, 'Grading submissions…');
            try
                T = VirtualLab.gradeFolder(folder, csvPath);
                UIKit.done(dlg);
            catch ME
                UIKit.done(dlg);
                T = [];
                UIKit.setStatus(app.StatusLabel, sprintf('Could not grade the folder: %s', ME.message), 'error');
                return;
            end
            if height(T) == 0
                UIKit.setStatus(app.StatusLabel, 'No .navlab.mat submissions in that folder.', 'warning');
            else
                UIKit.setStatus(app.StatusLabel, sprintf('Graded %d submission(s) (mean score %.0f%%); table written to %s', ...
                    height(T), mean(T.Score, 'omitnan'), csvPath), 'success');
            end
        end

        %% ----------------------------------------------------------------
        %% Helpers
        %% selectTab - Show a tab by title
        function selectTab(app, titleText)
            tab = findobj(app.Tabs, 'Type', 'uitab', 'Title', titleText);
            if ~isempty(tab), app.Tabs.SelectedTab = tab(1); end
        end

        %% checkStudent - A name is needed (it seeds the data)
        function ok = checkStudent(app)
            ok = ~isempty(strtrim(app.StudentInput.Value));
            if ~ok
                UIKit.setStatus(app.StatusLabel, 'Type your name or ID in step 2 first: your data are made from it.', 'warning');
            end
        end

        %% updateControls - Enable steps from the state; next step is primary
        function updateControls(app)
            hasName = ~isempty(strtrim(app.StudentInput.Value));
            planOk = isempty(VirtualLab.validateDesign(app.currentDesign()));
            recorded = ~isempty(app.RecordingPath);
            a = app.answers();
            anyAnswer = any(cellfun(@(f) isfinite(a.(f)), fieldnames(a)));
            app.RecordBtn.Enable = onoff(hasName && planOk);
            app.OpenExtractBtn.Enable = onoff(recorded);
            app.AttachBtn.Enable = onoff(recorded);
            app.CheckBtn.Enable = onoff(recorded);
            app.SolutionBtn.Enable = onoff(recorded && ~isempty(app.LastGrade));
            app.SubmitBtn.Enable = onoff(recorded);
            setButtonStyle(app.RecordBtn, ifelse(~recorded, 'primary', 'secondary'));
            setButtonStyle(app.OpenExtractBtn, ifelse(recorded && ~anyAnswer, 'primary', 'secondary'));
            setButtonStyle(app.CheckBtn, ifelse(recorded && anyAnswer, 'primary', 'secondary'));
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

%% fileTag - Name usable in a file name
function s = fileTag(name)
    s = regexprep(strtrim(char(name)), '[^A-Za-z0-9_-]+', '_');
    if isempty(s), s = 'student'; end
end

%% durationText - "12 min 30 s" or "45 s"
function s = durationText(sec)
    if sec >= 60
        s = sprintf('%d min %d s', floor(sec / 60), round(mod(sec, 60)));
    else
        s = sprintf('%d s', round(sec));
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
