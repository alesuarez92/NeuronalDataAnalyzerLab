%% VirtualLab.m
% =========================================================================
% VIRTUAL LAB - SIMULATED EXPERIMENTS, RECORDINGS AND AUTOMATIC FEEDBACK
% =========================================================================
% A virtual experiment lets a student plan a recording, "record" it (the
% simulator writes a file in the same format as the lab's acquisition
% software), process it from scratch in the normal windows, and get
% feedback on the plan, the processing and the numbers they report.
% Every student gets different data (drawn from their name / ID), so
% answers cannot be copied, but the same student always gets the same
% data for the same plan.
%
% The true answer is never stored in the recording: the grader re-creates
% the experiment from the student ID and the plan. A student's numbers are
% compared with a careful reference analysis of THEIR recording (so noise
% is not held against them); the true, noise-free response is shown next
% to it to explain how close any analysis of that recording could get.
%
% Scenario 'ldfWhisker' (Laser Doppler flowmetry, whisker stimulation):
% a probe over barrel cortex records blood flow (perfusion units, PU)
% while the whiskers are stimulated. Simulated signal: baseline (90-150
% PU), slow drift, vasomotion (0.08-0.14 Hz), heartbeat (5-7 Hz), noise,
% and a hyperemic response per stimulus: a gamma-shaped impulse response
% (peak 2-3 s) convolved with the stimulus (responses add up linearly),
% 20-40 PU for a 5 s stimulus over the activated barrel, weaker at the
% edge (x0.45) and far away (x0.08), with 15% trial-to-trial variation.
% The simulation is a teaching model, not a physiological model.
%
% API (base MATLAB, no toolboxes)
%   sc  = VirtualLab.scenario('ldfWhisker')   title, question, limits, defaults
%   d   = VirtualLab.defaultDesign()          plan: probe, stimS, nStim,
%                                             isiS, baselineS, fs
%   msg = VirtualLab.validateDesign(d)        '' or why the plan is not possible
%   info = VirtualLab.describeDesign(d)       durationS, nSamples, megabytes, text
%   tr  = VirtualLab.truth(studentId, d)      hidden answers (noise-free response)
%   rec = VirtualLab.record(studentId, d)     LabChart-style export struct
%                                             (data/datastart/dataend, ch 6 =
%                                             stimulus, ch 8 = LDF) + virtualLab
%   p   = VirtualLab.recordTo(path, studentId, d)   writes rec to a .mat
%   ref = VirtualLab.referenceAnalysis(studentId, d)
%         careful analysis of the recording: baselinePU, peakChangePU,
%         peakPercent, peakLatencyS, nTrials, peakSE (PU), pre/post windows
%   a   = VirtualLab.emptyAnswers()           baselinePU, peakChangePU,
%                                             peakPercent, peakLatencyS, nTrials
%   g   = VirtualLab.grade(studentId, d, answers, sessions)
%         items (section, item, status 'pass'|'check'|'fail'|'info', yours,
%         reference, feedback), score (0-100), truth, reference.
%         sessions: optional cell of session structs (Session.load) from
%         Process LDF / Average LDF; their settings are checked too.
%   sub = VirtualLab.submission(studentId, d, answers, sessions, attempts, solutionShown)
%   out = VirtualLab.saveSubmission(path, sub)  '<name>.navlab.mat'
%   sub = VirtualLab.loadSubmission(path)
%   T   = VirtualLab.gradeFolder(folder, csvPath)   one row per submission
%   txt = VirtualLab.learnText('ldfWhisker')  plain-language explainer
%   lines = VirtualLab.protocolText(studentId, d)   lab-notebook lines
% =========================================================================

classdef VirtualLab
    properties(Constant)
        Format = 'NeuroAnalyzer virtual lab submission'
        FormatVersion = 1
        Extension = '.navlab.mat'
        Seed = 20260925
        Probes = {'Over the activated barrel', 'At the edge of the barrel', 'Far from the barrel'}
        ProbeGain = [1 0.45 0.08]
        Rates = [10 40 100 1000]         % Hz offered in the plan
        MaxSamples = 4e6                 % per channel (file size limit)
        DtModel = 0.01                   % s, grid of the response model
    end

    methods(Static)

        %% scenario - Title, question and limits of a scenario
        function sc = scenario(name)
            if nargin < 1 || isempty(name), name = 'ldfWhisker'; end
            if ~strcmp(name, 'ldfWhisker')
                error('NeuroAnalyzer:VirtualLab:unknownScenario', 'Unknown virtual experiment ''%s''.', name);
            end
            sc = struct('name', name, ...
                'title', 'Blood flow response to whisker stimulation (LDF)', ...
                'question', ['How much does blood flow in barrel cortex increase after a whisker ' ...
                    'stimulus, and when does it peak?'], ...
                'limits', struct('stimS', [1 10], 'nStim', [3 40], 'isiS', [10 120], 'baselineS', [10 120]), ...
                'defaults', VirtualLab.defaultDesign());
        end

        %% defaultDesign - A reasonable starting plan (not the best one)
        function d = defaultDesign()
            d = struct('probe', VirtualLab.Probes{1}, 'stimS', 5, 'nStim', 5, ...
                'isiS', 15, 'baselineS', 30, 'fs', 40);
        end

        %% validateDesign - '' when the plan can be recorded, else the reason
        function msg = validateDesign(d)
            msg = '';
            sc = VirtualLab.scenario();
            L = sc.limits;
            f = {'stimS', 'nStim', 'isiS', 'baselineS'};
            names = {'Stimulus duration', 'Number of stimuli', 'Time between stimuli', 'Baseline before the first stimulus'};
            for k = 1:numel(f)
                v = d.(f{k});
                lim = L.(f{k});
                if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || v < lim(1) || v > lim(2)
                    msg = sprintf('%s must be between %g and %g.', names{k}, lim(1), lim(2));
                    return;
                end
            end
            if d.nStim ~= round(d.nStim)
                msg = 'Number of stimuli must be a whole number.';
            elseif ~any(strcmp(d.probe, VirtualLab.Probes))
                msg = 'Choose where the probe goes.';
            elseif ~any(d.fs == VirtualLab.Rates)
                msg = sprintf('Sampling rate must be one of %s Hz.', strjoin(arrayfun(@num2str, VirtualLab.Rates, 'UniformOutput', false), ', '));
            elseif d.isiS <= d.stimS
                msg = 'The time between stimuli must be longer than the stimulus.';
            else
                info = VirtualLab.describeDesign(d);
                if info.nSamples > VirtualLab.MaxSamples
                    msg = sprintf(['This recording would have %d samples per channel (about %.0f MB). ' ...
                        'Choose a lower sampling rate or fewer / shorter trials.'], info.nSamples, info.megabytes);
                end
            end
        end

        %% describeDesign - Duration, samples and file size of a plan
        function info = describeDesign(d)
            info.onsetsS = d.baselineS + (0:d.nStim - 1) * d.isiS;
            info.durationS = info.onsetsS(end) + max(d.isiS, 40);
            info.nSamples = round(info.durationS * d.fs);
            info.megabytes = 2 * 8 * info.nSamples / 1e6;   % two channels of doubles
            info.text = sprintf('Recording: %s  ·  %d samples per channel  ·  about %s', ...
                durationText(info.durationS), info.nSamples, sizeText(info.megabytes));
        end

        %% truth - The hidden answer for this student and plan (noise-free)
        % peakChangePU / peakLatencyS / returnS of the mean response at
        % the chosen probe position, baselinePU, peakPercent, and the
        % physiology drawn for this student (for the grader and tests).
        function tr = truth(studentId, d)
            P = VirtualLab.physiology(studentId);
            [r, tr_] = VirtualLab.responseShape(P, d.stimS);
            gain = VirtualLab.ProbeGain(strcmp(d.probe, VirtualLab.Probes));
            [pk, i] = max(r);
            tr = struct('baselinePU', P.baseline, 'peakChangePU', gain * pk, ...
                'peakPercent', 100 * gain * pk / P.baseline, 'peakLatencyS', tr_(i), ...
                'returnS', VirtualLab.returnTime(r, tr_), 'gain', gain, 'physiology', P);
        end

        %% record - Simulate the recording of one plan (LabChart export struct)
        function rec = record(studentId, d)
            msg = VirtualLab.validateDesign(d);
            if ~isempty(msg)
                error('NeuroAnalyzer:VirtualLab:invalidDesign', '%s', msg);
            end
            P = VirtualLab.physiology(studentId);
            info = VirtualLab.describeDesign(d);
            rs = RandStream('mt19937ar', 'Seed', VirtualLab.seedFor(studentId, VirtualLab.designKey(d)));
            fs = d.fs;
            t = (0:info.nSamples - 1) / fs;
            gain = VirtualLab.ProbeGain(strcmp(d.probe, VirtualLab.Probes));

            % Background: baseline, drift, vasomotion (slowly changing size),
            % heartbeat (sampled as is: aliases below 2x its frequency), noise
            ldf = P.baseline + P.driftPU * sin(2 * pi * t / P.driftPeriodS + P.phase(1)) ...
                + P.vasoPU * (1 + 0.3 * sin(2 * pi * t / 170 + P.phase(2))) .* sin(2 * pi * P.vasoHz * t + P.phase(3)) ...
                + P.cardiacPU * sin(2 * pi * P.cardiacHz * t + P.phase(4)) ...
                + P.noisePU * randn(rs, 1, numel(t));

            % Responses: one scaled copy of the response shape per stimulus
            [r, tr_] = VirtualLab.responseShape(P, d.stimS);
            amps = gain * (1 + P.trialCV * randn(rs, 1, d.nStim));
            stim = zeros(1, numel(t));
            for k = 1:d.nStim
                on = info.onsetsS(k);
                i1 = floor(on * fs) + 1;
                i2 = min(numel(t), ceil((on + tr_(end)) * fs) + 1);
                idx = i1:i2;
                x = t(idx) - on;
                ok = x >= 0;
                ldf(idx(ok)) = ldf(idx(ok)) + amps(k) * interp1(tr_, r, x(ok), 'linear', 0);
                stim(t >= on & t < on + d.stimS) = 5;
            end
            stim = stim + 0.01 * randn(rs, 1, numel(t));

            % LabChart-style export: channels 1-5 and 7 empty (-1), 6 = stimulus, 8 = LDF
            n = numel(t);
            rec.data = [stim, ldf];
            rec.datastart = [-1 -1 -1 -1 -1 1 -1 n + 1];
            rec.dataend = [-1 -1 -1 -1 -1 n -1 2 * n];
            rec.samplerate = repmat(fs, 1, 8);
            rec.titles = char('Ch1', 'Ch2', 'Ch3', 'Ch4', 'Ch5', 'Stimulus', 'Ch7', 'LDF');
            rec.unittext = char('V', 'PU');
            rec.comtext = char(sprintf('Virtual lab: %s', VirtualLab.scenario().title));
            rec.virtualLab = struct('scenario', 'ldfWhisker', 'studentId', char(studentId), ...
                'design', d, 'toolboxVersion', UITheme.version, 'created', isoNow());
        end

        %% recordTo - Record and save the export .mat (returns the path)
        function p = recordTo(p, studentId, d)
            rec = VirtualLab.record(studentId, d); %#ok<NASGU>
            [folder, ~, ext] = fileparts(p);
            if isempty(ext), p = [p '.mat']; end
            if ~isempty(folder) && ~exist(folder, 'dir'), mkdir(folder); end
            save(p, '-struct', 'rec');
        end

        %% referenceAnalysis - A careful analysis of the student's recording
        % 10 Hz block averages (removes the heartbeat), one trial per
        % stimulus from -pre to +post (pre = 5 s, shorter if the stimuli
        % are closer; post up to 30 s, ending before the next stimulus),
        % each trial minus its own pre-stimulus mean, then the mean trial.
        function ref = referenceAnalysis(studentId, d)
            rec = VirtualLab.record(studentId, d);
            info = VirtualLab.describeDesign(d);
            ldf = rec.data(rec.datastart(8):rec.dataend(8));
            fsOut = 10;
            k = round(d.fs / fsOut);
            n = floor(numel(ldf) / k) * k;
            y = mean(reshape(ldf(1:n), k, []), 1);
            pre = min(5, d.isiS - d.stimS);
            post = min(30, d.isiS - pre);
            np = round(pre * fsOut); nq = round(post * fsOut);
            tSeg = (-np:nq) / fsOut;
            trials = zeros(0, numel(tSeg));
            base = zeros(0, 1);
            for s = info.onsetsS
                i0 = round(s * fsOut) + 1;
                if i0 - np < 1 || i0 + nq > numel(y), continue; end
                seg = y(i0 - np:i0 + nq);
                b = mean(seg(1:np));
                base(end + 1, 1) = b; %#ok<AGROW>
                trials(end + 1, :) = seg - b; %#ok<AGROW>
            end
            m = mean(trials, 1);
            post_ = tSeg > 0;
            tp = tSeg(post_);
            [pk, i] = max(m(post_));
            iAll = find(post_, 1) + i - 1;
            ref = struct('baselinePU', mean(base), 'peakChangePU', pk, ...
                'peakPercent', 100 * pk / mean(base), 'peakLatencyS', tp(i), ...
                'nTrials', size(trials, 1), 'peakSE', std(trials(:, iAll)) / sqrt(size(trials, 1)), ...
                'preS', pre, 'postS', post, 'fsAnalysis', fsOut, 'meanTrial', m, 'time', tSeg);
        end

        %% emptyAnswers - The numbers a student reports (NaN = not given)
        function a = emptyAnswers()
            a = struct('baselinePU', NaN, 'peakChangePU', NaN, 'peakPercent', NaN, ...
                'peakLatencyS', NaN, 'nTrials', NaN);
        end

        %% grade - Feedback on the plan, the processing and the answers
        function g = grade(studentId, d, answers, sessions)
            if nargin < 3 || isempty(answers), answers = VirtualLab.emptyAnswers(); end
            if nargin < 4, sessions = {}; end
            if isstruct(sessions), sessions = num2cell(sessions); end
            tr = VirtualLab.truth(studentId, d);
            ref = VirtualLab.referenceAnalysis(studentId, d);
            items = VirtualLab.designItems(d, tr, ref);
            items = [items, VirtualLab.processItems(sessions, d, tr)];
            items = [items, VirtualLab.answerItems(answers, ref, tr, d)];

            scored = ~strcmp({items.status}, 'info');
            pts = zeros(1, numel(items));
            pts(strcmp({items.status}, 'pass')) = 1;
            pts(strcmp({items.status}, 'check')) = 0.5;
            if any(scored)
                score = round(100 * sum(pts(scored)) / sum(scored));
            else
                score = 0;
            end
            g = struct('items', items, 'score', score, 'truth', tr, 'reference', ...
                rmfield(ref, {'meanTrial', 'time'}), 'studentId', char(studentId), 'design', d);
            g.summary = sprintf('%d%%  ·  %d passed, %d to check, %d to fix (of %d)', score, ...
                sum(strcmp({items.status}, 'pass')), sum(strcmp({items.status}, 'check')), ...
                sum(strcmp({items.status}, 'fail')), sum(scored));
        end

        %% submission - What a student hands in (no answers key inside)
        function sub = submission(studentId, d, answers, sessions, attempts, solutionShown)
            if nargin < 4, sessions = {}; end
            if nargin < 5, attempts = 0; end
            if nargin < 6, solutionShown = false; end
            sub = struct('format', VirtualLab.Format, 'formatVersion', VirtualLab.FormatVersion, ...
                'scenario', 'ldfWhisker', 'studentId', char(studentId), 'design', d, ...
                'answers', answers, 'sessions', {sessions}, 'attempts', attempts, ...
                'solutionShown', logical(solutionShown), 'toolboxVersion', UITheme.version, ...
                'created', isoNow());
        end

        %% saveSubmission - Write '<name>.navlab.mat' (variable 'submission')
        function p = saveSubmission(p, sub)
            if ~endsWith(p, VirtualLab.Extension)
                p = regexprep(p, '\.mat$', '');
                p = [p VirtualLab.Extension];
            end
            submission = sub; %#ok<NASGU>
            save(p, 'submission');
        end

        %% loadSubmission - Read and check a submission file
        function sub = loadSubmission(p)
            s = load(p);
            if ~isfield(s, 'submission') || ~isfield(s.submission, 'format') || ...
                    ~strcmp(s.submission.format, VirtualLab.Format)
                error('NeuroAnalyzer:VirtualLab:notSubmission', '%s is not a virtual lab submission.', p);
            end
            sub = s.submission;
        end

        %% gradeFolder - Grade every submission in a folder (instructor)
        % One row per file: Student, Score, the answers, the reference
        % values, attempts, SolutionShown, Status ('ok' or the error). Writes
        % csvPath when given.
        function T = gradeFolder(folder, csvPath)
            files = dir(fullfile(folder, ['*' VirtualLab.Extension]));
            n = numel(files);
            File = cell(n, 1); Student = cell(n, 1); Score = nan(n, 1); Status = cell(n, 1);
            Attempts = nan(n, 1); SolutionShown = false(n, 1);
            f = fieldnames(VirtualLab.emptyAnswers());
            ans_ = nan(n, numel(f)); ref_ = nan(n, numel(f));
            for k = 1:n
                File{k} = files(k).name;
                Student{k} = '';
                try
                    sub = VirtualLab.loadSubmission(fullfile(folder, files(k).name));
                    Student{k} = sub.studentId;
                    g = VirtualLab.grade(sub.studentId, sub.design, sub.answers, sub.sessions);
                    Score(k) = g.score;
                    Attempts(k) = sub.attempts;
                    SolutionShown(k) = sub.solutionShown;
                    for j = 1:numel(f)
                        ans_(k, j) = sub.answers.(f{j});
                        ref_(k, j) = g.reference.(f{j});
                    end
                    Status{k} = 'ok';
                catch ME
                    Status{k} = ME.message;
                end
            end
            T = table(File, Student, Score, Attempts, SolutionShown, Status);
            for j = 1:numel(f)
                T.(['Your_' f{j}]) = ans_(:, j);
                T.(['Ref_' f{j}]) = ref_(:, j);
            end
            if nargin >= 2 && ~isempty(csvPath)
                writetable(T, csvPath);
            end
        end

        %% learnText - Plain-language explainer shown in step 1
        function txt = learnText(name)
            if nargin < 1, name = 'ldfWhisker'; end
            VirtualLab.scenario(name);
            txt = { ...
                'THE QUESTION', ...
                ['When the whiskers of a rat or mouse are touched, neurons in one small patch of the ' ...
                 'somatosensory cortex (the "barrel" of that whisker) become active. Within seconds the ' ...
                 'nearby blood vessels widen and blood flow rises: this is neurovascular coupling. ' ...
                 'You will measure how big that increase is and when it peaks.'], ...
                '', ...
                'HOW LASER DOPPLER FLOWMETRY (LDF) WORKS', ...
                ['A thin probe shines laser light into the tissue. Light that hits moving red blood cells ' ...
                 'comes back with a tiny change in frequency (the Doppler shift); light that hits still ' ...
                 'tissue does not. The instrument turns this into "perfusion": roughly how many red cells ' ...
                 'move and how fast, in a small volume under the probe (about a millimetre).'], ...
                ['The unit is the perfusion unit (PU). PU are relative: they depend on the probe and the ' ...
                 'tissue, so results are usually given as a change from the baseline (PU or %), not as ' ...
                 'absolute flow.'], ...
                '', ...
                'WHAT THE RAW SIGNAL LOOKS LIKE', ...
                ['- A baseline level that drifts slowly.' newline ...
                 '- Vasomotion: slow waves of about 0.1 Hz (one every ~10 s) from vessels contracting and relaxing.' newline ...
                 '- The heartbeat: a fast ripple (5-7 Hz in rats).' newline ...
                 '- Noise.' newline ...
                 '- After each stimulus: a rise of blood flow over a few seconds and a slower return.'], ...
                '', ...
                'HOW THE EXPERIMENT IS RECORDED', ...
                ['The acquisition system records two channels at the same time: the stimulus (a 5 V pulse ' ...
                 'while the whiskers are stimulated, channel 6) and the LDF signal (channel 8). You choose ' ...
                 'where the probe goes, the stimulus, how many stimuli, the time between them, the ' ...
                 'baseline before the first one and the sampling rate. Each choice has consequences - ' ...
                 'that is the point of the exercise.'], ...
                '', ...
                'WHAT YOU WILL DO', ...
                ['1. Plan the experiment (step 2) and record it (step 3).' newline ...
                 '2. Process the recording from scratch in the normal windows: Extract LDF (crop), ' ...
                 'Process LDF (cut trials around each stimulus), Average LDF (mean trial relative to baseline).' newline ...
                 '3. Report your numbers (step 4) and, if you like, attach the session files you saved in ' ...
                 'those windows so your processing settings can be checked too.' newline ...
                 '4. Read the feedback: what was right, what to change and why.'], ...
                '', ...
                'ABOUT THE DATA', ...
                ['The recording is simulated with a known answer. The model is simplified (for example, ' ...
                 'responses add up linearly and there are no movement artefacts); it teaches the method, ' ...
                 'not the physiology of a particular animal.']};
            txt = strjoin(txt, newline);
        end

        %% protocolText - Lab-notebook lines describing the recorded plan
        function lines = protocolText(studentId, d)
            info = VirtualLab.describeDesign(d);
            lines = { ...
                sprintf('Virtual experiment: %s', VirtualLab.scenario().title), ...
                sprintf('Student: %s', char(studentId)), ...
                sprintf('Probe: %s', d.probe), ...
                sprintf('Stimulus: %g s whisker stimulation, %d times, every %g s (first after %g s of baseline)', ...
                    d.stimS, d.nStim, d.isiS, d.baselineS), ...
                sprintf('Sampling rate: %g Hz  ·  %s', d.fs, info.text), ...
                'Channels: 6 = stimulus (5 V while stimulating), 8 = LDF (PU)'};
        end
    end

    methods(Static, Access = private)

        %% physiology - This student's animal (drawn from the student ID)
        % Uses a Park-Miller generator (exact in double precision), so the
        % true answers are the same on every MATLAB release and machine.
        function P = physiology(studentId)
            x = mod(VirtualLab.seedFor(studentId, 'physiology'), 2147483646) + 1;
            u = zeros(1, 12);
            for k = 1:12
                x = mod(16807 * x, 2147483647);
                u(k) = x / 2147483647;
            end
            P = struct('baseline', 90 + 60 * u(1), 'amplitude5s', 20 + 20 * u(2), ...
                'kernelPeakS', 2 + u(3), 'vasoHz', 0.08 + 0.06 * u(4), 'vasoPU', 2 + 2 * u(5), ...
                'cardiacHz', 5 + 2 * u(6), 'cardiacPU', 1.5, 'noisePU', 1.5, ...
                'driftPU', 3 + 3 * u(7), 'driftPeriodS', 300 + 300 * u(8), ...
                'trialCV', 0.15, 'phase', 2 * pi * u(9:12));
        end

        %% responseShape - Mean response (PU at gain 1) to a stimS-long stimulus
        % Gamma impulse response x^3 exp(3 (1 - x)), x = t / kernelPeakS,
        % convolved with the stimulus; scaled so a 5 s stimulus peaks at
        % amplitude5s. Returns r and its time axis (s from onset, 0-60 s).
        function [r, t] = responseShape(P, stimS)
            dt = VirtualLab.DtModel;
            t = 0:dt:60;
            x = t / P.kernelPeakS;
            h = x.^3 .* exp(3 * (1 - x));
            conv5 = conv(double(t < 5), h) * dt;
            r = conv(double(t < stimS), h) * dt;
            r = P.amplitude5s * r(1:numel(t)) / max(conv5(1:numel(t)));
        end

        %% returnTime - Time after onset when the response is back below 10% of its peak
        function s = returnTime(r, t)
            [pk, i] = max(r);
            j = find(r(i:end) < 0.1 * pk, 1);
            if isempty(j), s = t(end); else, s = t(i + j - 1); end
        end

        %% seedFor - Reproducible seed from the student ID and a purpose
        function s = seedFor(studentId, purpose)
            key = [lower(strtrim(char(studentId))) '|' char(purpose)];
            h = 0;
            for c = double(key)
                h = mod(h * 131 + c, 2147483647);
            end
            s = mod(VirtualLab.Seed + h, 2^32 - 1);
        end

        %% designKey - Text key of a plan (same plan -> same recording)
        function k = designKey(d)
            k = sprintf('%s|%g|%g|%g|%g|%g', d.probe, d.stimS, d.nStim, d.isiS, d.baselineS, d.fs);
        end

        %% designItems - Feedback on the plan
        function items = designItems(d, tr, ref)
            items = emptyItems();
            sec = 'Plan';
            switch find(strcmp(d.probe, VirtualLab.Probes))
                case 1
                    items(end + 1) = item(sec, 'Probe position', 'pass', d.probe, VirtualLab.Probes{1}, ...
                        'Right place: the probe sits over the barrel activated by the stimulated whiskers.');
                case 2
                    items(end + 1) = item(sec, 'Probe position', 'check', d.probe, VirtualLab.Probes{1}, ...
                        ['At the edge of the barrel the response is about half as large. Find the most ' ...
                         'responsive spot first (e.g. a quick test stimulus at a few positions), then record.']);
                otherwise
                    items(end + 1) = item(sec, 'Probe position', 'fail', d.probe, VirtualLab.Probes{1}, ...
                        ['Far from the barrel there is almost no response. That is a useful control site, ' ...
                         'but it cannot answer the question: record over the activated barrel.']);
            end
            need = ceil(tr.returnS);
            if d.isiS >= need + 5
                items(end + 1) = item(sec, 'Time between stimuli', 'pass', sprintf('%g s', d.isiS), ...
                    sprintf('>= %d s', need + 5), sprintf(['Blood flow is back to baseline (about %d s after ' ...
                    'onset) before the next stimulus, so each trial starts from a clean baseline.'], need));
            elseif d.isiS >= need
                items(end + 1) = item(sec, 'Time between stimuli', 'check', sprintf('%g s', d.isiS), ...
                    sprintf('>= %d s', need + 5), sprintf(['Flow is only just back to baseline (about %d s ' ...
                    'after onset). Leave a few seconds more so vasomotion and slow tails do not raise the next baseline.'], need));
            else
                items(end + 1) = item(sec, 'Time between stimuli', 'fail', sprintf('%g s', d.isiS), ...
                    sprintf('>= %d s', need + 5), sprintf(['Flow needs about %d s to return to baseline, so ' ...
                    'responses overlap: each "baseline" still contains the previous response and the ' ...
                    'measured increase is too small. Use at least %d s between stimuli.'], need, need + 5));
            end
            spread = 2 * ref.peakSE;
            if d.nStim >= 10
                st = 'pass'; fb = sprintf('Enough trials: with %d, the peak is known to about ±%.1f PU.', d.nStim, spread);
            elseif d.nStim >= 6
                st = 'check'; fb = sprintf(['With %d trials the peak is known only to about ±%.1f PU. ' ...
                    'Averaging more trials (10-20) shrinks the noise by the square root of the number of trials.'], d.nStim, spread);
            else
                st = 'fail'; fb = sprintf(['%d trials are too few: vasomotion alone moves single trials by several PU ' ...
                    '(your peak is known only to about ±%.1f PU). Record 10-20.'], d.nStim, spread);
            end
            items(end + 1) = item(sec, 'Number of stimuli', st, sprintf('%d', d.nStim), '>= 10', fb);
            if d.fs == 10
                items(end + 1) = item(sec, 'Sampling rate', 'check', '10 Hz', '40-100 Hz', ...
                    ['10 Hz is enough for the slow response, but the heartbeat (5-7 Hz) is faster than half ' ...
                     'the sampling rate, so it folds into a slower, false ripple (aliasing) that no filter can ' ...
                     'remove afterwards. Sample at 40 Hz or more, or low-pass before sampling.']);
            elseif d.fs == 1000
                items(end + 1) = item(sec, 'Sampling rate', 'pass', '1000 Hz', '40-100 Hz', ...
                    ['Works, but far more than LDF needs: the file is 10-25 times larger than at 40-100 Hz ' ...
                     'for the same information.']);
            else
                items(end + 1) = item(sec, 'Sampling rate', 'pass', sprintf('%g Hz', d.fs), '40-100 Hz', ...
                    'Fast enough for the heartbeat and the response, and small files.');
            end
            if d.baselineS >= 30
                items(end + 1) = item(sec, 'Baseline before the first stimulus', 'pass', sprintf('%g s', d.baselineS), ...
                    '>= 30 s', 'A stable stretch before the first stimulus shows the resting level and its fluctuations.');
            else
                items(end + 1) = item(sec, 'Baseline before the first stimulus', 'check', sprintf('%g s', d.baselineS), ...
                    '>= 30 s', 'Record at least 30 s of baseline first: it shows whether the signal is stable before you start.');
            end
        end

        %% processItems - Checks on the settings saved in session files
        function items = processItems(sessions, d, tr)
            items = emptyItems();
            sec = 'Processing';
            apps = cellfun(@(s) getField(s, 'app', ''), sessions, 'UniformOutput', false);
            k = find(strcmp(apps, 'ProcessingLDFApp'), 1, 'last');
            if isempty(k)
                items(end + 1) = item(sec, 'Trial cutting (Process LDF session)', 'info', 'not attached', '', ...
                    ['Attach the session saved in Process LDF (step 4, Save session…) to get feedback on ' ...
                     'your filter and trial window.']);
            else
                st = sessions{k}.settings;
                needPost = min(ceil(tr.returnS), d.isiS - 2);
                if st.postS >= needPost
                    items(end + 1) = item(sec, 'Window after the stimulus', 'pass', sprintf('%g s', st.postS), ...
                        sprintf('>= %d s', needPost), 'The window covers the whole response, including its return to baseline.');
                elseif st.postS > tr.peakLatencyS + 1
                    items(end + 1) = item(sec, 'Window after the stimulus', 'check', sprintf('%g s', st.postS), ...
                        sprintf('>= %d s', needPost), sprintf(['The peak is inside the window, but the return to ' ...
                        'baseline (about %d s) is cut off.'], ceil(tr.returnS)));
                else
                    items(end + 1) = item(sec, 'Window after the stimulus', 'fail', sprintf('%g s', st.postS), ...
                        sprintf('>= %d s', needPost), sprintf(['The window ends before the response peaks ' ...
                        '(about %.1f s), so the peak and its timing cannot be measured. Use a longer "Post" window.'], tr.peakLatencyS));
                end
                if st.preS >= 2 && st.preS <= d.isiS - ceil(tr.returnS) + 5
                    items(end + 1) = item(sec, 'Baseline window before the stimulus', 'pass', sprintf('%g s', st.preS), ...
                        '2-5 s', 'Long enough to average out the heartbeat, short enough to stay clear of the previous response.');
                elseif st.preS < 2
                    items(end + 1) = item(sec, 'Baseline window before the stimulus', 'check', sprintf('%g s', st.preS), ...
                        '2-5 s', 'A baseline shorter than 2 s is dominated by vasomotion and heartbeat; use 2-5 s.');
                else
                    items(end + 1) = item(sec, 'Baseline window before the stimulus', 'check', sprintf('%g s', st.preS), ...
                        '2-5 s', 'This baseline reaches back into the previous response; use a shorter one (2-5 s).');
                end
                items(end + 1) = VirtualLab.filterItem(st.processing);
            end
            k = find(strcmp(apps, 'LDFGrandAverageApp'), 1, 'last');
            if isempty(k)
                items(end + 1) = item(sec, 'Averaging (Average LDF session)', 'info', 'not attached', '', ...
                    'Attach the session saved in Average LDF to get feedback on the averaging.');
            elseif getField(sessions{k}.settings, 'relativeToBaseline', false)
                items(end + 1) = item(sec, 'Relative to baseline', 'pass', 'on', 'on', ...
                    'Each trial is measured from its own pre-stimulus level, which removes slow drift between trials.');
            else
                items(end + 1) = item(sec, 'Relative to baseline', 'check', 'off', 'on', ...
                    ['Without "Relative to baseline" the average mixes the response with slow drift between ' ...
                     'trials. Turn it on to read the increase directly in PU.']);
            end
        end

        %% filterItem - Feedback on the Process LDF filter settings
        function it = filterItem(p)
            sec = 'Processing';
            name = 'Filter';
            ft = getField(p, 'filterType', 1);
            lo = getField(p, 'cutoffLow', NaN); hi = getField(p, 'cutoffHigh', NaN);
            if ft == 1
                it = item(sec, name, 'pass', 'none', 'none or low-pass >= 1 Hz', ...
                    'No filter is fine: averaging trials already removes most of the heartbeat and noise.');
            elseif ft == 2 && hi >= 0.5
                it = item(sec, name, 'pass', sprintf('low-pass %g Hz', hi), 'none or low-pass >= 1 Hz', ...
                    'A low-pass above the response speed removes the heartbeat without changing the response.');
            elseif ft == 2
                it = item(sec, name, 'check', sprintf('low-pass %g Hz', hi), 'none or low-pass >= 1 Hz', ...
                    'A low-pass below 0.5 Hz starts to flatten and widen the response peak. Use about 1 Hz or none.');
            elseif ft == 3 || ft == 4
                it = item(sec, name, 'fail', sprintf('high-pass from %g Hz', lo), 'none or low-pass >= 1 Hz', ...
                    ['A high-pass filter removes slow changes - and the blood flow response IS a slow change. ' ...
                     'It shrinks the peak and creates a dip after it. Use trial baselines instead.']);
            else
                it = item(sec, name, 'check', sprintf('band-stop %g-%g Hz', lo, hi), 'none or low-pass >= 1 Hz', ...
                    'A notch is not needed for LDF here; check that it does not touch frequencies below 1 Hz.');
            end
        end

        %% answerItems - The reported numbers vs a careful analysis of the same recording
        function items = answerItems(a, ref, tr, d)
            items = emptyItems();
            sec = 'Your results';
            spec = { ...
                'nTrials', 'Trials averaged', ref.nTrials, 0, '%d', ...
                    sprintf(['Every stimulus gives one complete trial (%d). Fewer means some onsets were missed ' ...
                    '(threshold) or trials did not fit the window; more means the recording was cut into ' ...
                    'extra pieces.'], ref.nTrials); ...
                'baselinePU', 'Baseline (PU)', ref.baselinePU, max(3, 0.05 * ref.baselinePU), '%.1f', ...
                    'The baseline is the mean flow just before the stimuli, in PU.'; ...
                'peakChangePU', 'Peak increase (PU)', ref.peakChangePU, max(2, 0.15 * ref.peakChangePU), '%.1f', ...
                    ['The peak increase is the highest point of the mean trial minus its baseline. Check the ' ...
                     'window after the stimulus, "Relative to baseline", and that no high-pass filter shrank it.']; ...
                'peakPercent', 'Peak increase (%)', ref.peakPercent, max(2, 0.15 * ref.peakPercent), '%.1f', ...
                    'The percent increase is 100 x peak increase / baseline.'; ...
                'peakLatencyS', 'Time to peak (s)', ref.peakLatencyS, max(0.75, 2 / d.fs), '%.1f', ...
                    ['The time to peak is measured from stimulus onset (t = 0) to the highest point of the ' ...
                     'mean trial; a window that ends too early puts it at the window''s end.']};
            for k = 1:size(spec, 1)
                [f, name, refV, tol, fmt, why] = spec{k, :};
                v = a.(f);
                refText = sprintf(fmt, refV);
                if ~isnumeric(v) || isempty(v) || ~isfinite(v)
                    items(end + 1) = item(sec, name, 'fail', 'not given', refText, 'Enter this value.'); %#ok<AGROW>
                    continue;
                end
                err = abs(v - refV);
                if err <= tol
                    items(end + 1) = item(sec, name, 'pass', sprintf(fmt, v), refText, 'Matches a careful analysis of your recording.'); %#ok<AGROW>
                elseif err <= 2 * tol
                    items(end + 1) = item(sec, name, 'check', sprintf(fmt, v), refText, ['Close, but a little off. ' why]); %#ok<AGROW>
                else
                    items(end + 1) = item(sec, name, 'fail', sprintf(fmt, v), refText, why); %#ok<AGROW>
                end
            end
            items(end + 1) = item('What was true', 'Noise-free answer', 'info', '', ...
                sprintf('%.1f PU (%.1f%%) at %.1f s', tr.peakChangePU, tr.peakPercent, tr.peakLatencyS), ...
                sprintf(['The simulator knows the true response. A careful analysis of your recording found ' ...
                'a peak of %.1f PU at %.1f s; the difference to the true value comes from noise, which ' ...
                'is about ±%.1f PU with %d trials.'], ref.peakChangePU, ref.peakLatencyS, 2 * ref.peakSE, ref.nTrials));
        end
    end
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% item - One feedback row
function it = item(section, name, status, yours, reference, feedback)
    it = struct('section', section, 'item', name, 'status', status, 'yours', yours, ...
        'reference', reference, 'feedback', feedback);
end

%% emptyItems - 1x0 struct array with the feedback fields
function items = emptyItems()
    items = struct('section', {}, 'item', {}, 'status', {}, 'yours', {}, 'reference', {}, 'feedback', {});
end

%% getField - s.(name) or a default
function v = getField(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end

%% durationText - "12 min 30 s" or "45 s"
function s = durationText(sec)
    if sec >= 60
        s = sprintf('%d min %d s', floor(sec / 60), round(mod(sec, 60)));
    else
        s = sprintf('%d s', round(sec));
    end
end

%% sizeText - "0.4 MB" / "12 MB"
function s = sizeText(mb)
    if mb < 10
        s = sprintf('%.1f MB', mb);
    else
        s = sprintf('%.0f MB', mb);
    end
end

%% isoNow - Local time as ISO 8601
function t = isoNow()
    t = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
end
