%% MethodsWriter.m
% =========================================================================
% METHODS WRITER - DRAFT METHODS TEXT FROM SAVED SESSIONS
% =========================================================================
% Turns what a window did (a session, see core/Session.m) into a draft
% methods section in past tense, with the actual parameter values and
% units, the software versions and a reference list. The text is a draft
% for the scientist to check and edit: nothing is invented. Values that
% the session does not hold (animals, surgery, hardware) are left as
% bracketed "[please add: ...]" placeholders.
%
%   [txt, refs] = MethodsWriter.fromSession(s)
%       s: session struct (Session.load / Session.capture) or the path of
%       a .nasession.mat. txt: char, paragraphs separated by a blank line;
%       refs: cellstr, one full reference per cell (alphabetical).
%   [txt, refs] = MethodsWriter.fromSessions(list)
%       Several sessions of a pipeline (cellstr of paths, struct array or
%       cell of structs) in pipeline order (Extract LDF -> Process LDF ->
%       LDF Average -> Laser speckle -> Extract Ephys -> LFP Analysis -> MUA Analysis ->
%       ROI Analysis -> Histology / culture -> EEG Analysis -> Signal
%       Characterization), one placeholder paragraph
%       at the start, one software paragraph at the end and one reference
%       list. Identical paragraphs (the same session twice) appear once.
%   full = MethodsWriter.compose(txt, refs)
%       txt followed by a "References" section (the text of the dialog).
%   out = MethodsWriter.write(path, txt, refs)
%       Writes compose(txt, refs) as UTF-8 text (with a byte-order mark so
%       Word and Notepad detect the encoding); '.txt' added if missing.
%       refs optional (omit when txt already holds the references).
%   fig = MethodsWriter.dialog(app, sessions)
%       Methods text window (UIKit look): the text in an editable box,
%       Copy, Save .txt..., and "Add saved sessions..." (several
%       .nasession.mat, combined in pipeline order). app: the window the
%       button belongs to ([] when not opened from a window); sessions:
%       optional cell of session structs (default {Session.capture(app)}).
%   MethodsWriter.forApp(app)
%       The "Methods text..." session button (UIKit.sessionButtons): opens
%       the dialog for the window's current analysis, with a status-bar
%       message; never throws.
%
% Citations appear in the text as {{key}} markers while it is built and
% are replaced by "Author, year" (MethodsWriter.references lists them);
% only references whose details are certain are listed. Error
% identifiers: NeuroAnalyzer:MethodsWriter:invalidSession, noSessions,
% write.
%
% Base MATLAB only (R2021a); the text functions also run in GNU Octave.
% =========================================================================

classdef MethodsWriter
    properties(Constant)
        % Window classes in pipeline order (unknown windows go before the last)
        PipelineOrder = {'ExtractLDFApp', 'ProcessingLDFApp', 'LDFGrandAverageApp', 'LSCIAnalysisApp', ...
            'ExtractEphysApp', 'LFPAnalysisApp', 'MUAAnalysisApp', 'ROIAnalysisApp', ...
            'HistologyApp', 'EEGAnalysisApp', 'SignalCharacterizationApp'}
        Placeholder = ['[Describe the animals (species, strain, sex, age and number), anaesthesia ' ...
            'and surgery, and the recording or imaging hardware (probe or electrode type, amplifier, ' ...
            'microscope, acquisition system) here.]']
        CheckNote = 'Check every sentence against what you did; add animal, surgery and hardware details.'
        RepoURL = 'https://github.com/alesuarez92/NeuronalDataAnalyzerLab'
    end

    methods(Static)

        %% fromSession - Methods text and references of one session
        function [txt, refs] = fromSession(s)
            [txt, refs] = MethodsWriter.fromSessions({s});
        end

        %% fromSessions - Combined methods text of several sessions, in pipeline order
        function [txt, refs] = fromSessions(list)
            list = MethodsWriter.sessionList(list);
            if isempty(list)
                error('NeuroAnalyzer:MethodsWriter:noSessions', 'No sessions to describe.');
            end
            rk = zeros(1, numel(list));
            for k = 1:numel(list)
                rk(k) = MethodsWriter.pipelineRank(list{k}.app);
            end
            [~, order] = sort(rk);            % sort is stable: same window keeps its order
            list = list(order);
            paras = {MethodsWriter.Placeholder};
            tbx = {};
            for k = 1:numel(list)
                [p, tb] = MethodsWriter.describe(list{k});
                for j = 1:numel(p)
                    if ~any(strcmp(paras, p{j})), paras{end+1} = p{j}; end %#ok<AGROW>
                end
                tbx = [tbx, tb]; %#ok<AGROW>
            end
            paras{end+1} = MethodsWriter.softwareParagraph(list, MethodsWriter.uniqueStable(tbx));
            raw = strjoin(paras, [newline newline]);
            [txt, keys] = MethodsWriter.resolveCitations(raw, list);
            txt = MethodsWriter.entities(txt);
            refs = MethodsWriter.referenceList(keys, list);
            for k = 1:numel(refs)
                refs{k} = MethodsWriter.entities(regexprep(refs{k}, '(\d)-(\d)', '$1&ndash;$2'));
            end
        end

        %% compose - Text plus a "References" section
        function full = compose(txt, refs)
            if nargin < 2, refs = {}; end
            full = char(txt);
            refs = cellstr(refs);
            refs = refs(~cellfun(@isempty, refs));
            if ~isempty(refs)
                full = sprintf('%s%s%sReferences%s%s', full, newline, newline, newline, strjoin(refs(:)', newline));
            end
        end

        %% write - Save the text (and references) as a UTF-8 .txt file
        function out = write(p, txt, refs)
            if nargin < 3, refs = {}; end
            out = char(p);
            if numel(out) < 4 || ~strcmpi(out(end-3:end), '.txt')
                out = [out '.txt'];
            end
            full = MethodsWriter.compose(txt, refs);
            if ispc
                full = strrep(strrep(full, sprintf('\r\n'), newline), newline, sprintf('\r\n'));
            end
            fid = fopen(out, 'w');
            if fid < 0
                error('NeuroAnalyzer:MethodsWriter:write', 'Could not write %s (check that the folder is writable).', out);
            end
            c = onCleanup(@() fclose(fid));
            fwrite(fid, uint8([239 187 191]), 'uint8');          % UTF-8 byte-order mark
            fwrite(fid, unicode2native(full, 'UTF-8'), 'uint8');
        end

        %% references - Every citation key: {key, short cite, full reference}
        function R = references()
            R = {
                'mitzdorf1985', 'Mitzdorf, 1985', ['Mitzdorf U (1985). Current source-density method and application ' ...
                    'in cat cerebral cortex: investigation of evoked potentials and EEG phenomena. Physiol Rev 65(1):37-100.']
                'nicholson1975', 'Nicholson & Freeman, 1975', ['Nicholson C, Freeman JA (1975). Theory of current ' ...
                    'source-density analysis and determination of conductivity tensor for anuran cerebellum. ' ...
                    'J Neurophysiol 38(2):356-368.']
                'pettersen2006', 'Pettersen et al., 2006', ['Pettersen KH, Devor A, Ulbert I, Dale AM, Einevoll GT ' ...
                    '(2006). Current-source density estimation based on inversion of electrostatic forward solution: ' ...
                    'effects of finite extent of neuronal activity and conductivity discontinuities. ' ...
                    'J Neurosci Methods 154(1-2):116-133.']
                'potworowski2012', 'Potworowski et al., 2012', ['Potworowski J, Jakuczun W, Leski S, Wojcik D (2012). ' ...
                    'Kernel current source density method. Neural Comput 24(2):541-575.']
                'welch1967', 'Welch, 1967', ['Welch PD (1967). The use of fast Fourier transform for the estimation ' ...
                    'of power spectra: a method based on time averaging over short, modified periodograms. ' ...
                    'IEEE Trans Audio Electroacoust 15(2):70-73.']
                'makeig1993', 'Makeig, 1993', ['Makeig S (1993). Auditory event-related dynamics of the EEG spectrum ' ...
                    'and effects of exposure to tones. Electroencephalogr Clin Neurophysiol 86(4):283-293.']
                'tallonbaudry1996', 'Tallon-Baudry et al., 1996', ['Tallon-Baudry C, Bertrand O, Delpuech C, ' ...
                    'Pernier J (1996). Stimulus specificity of phase-locked and non-phase-locked 40 Hz visual ' ...
                    'responses in human. J Neurosci 16(13):4240-4249.']
                'pfurtscheller1999', 'Pfurtscheller & Lopes da Silva, 1999', ['Pfurtscheller G, Lopes da Silva FH ' ...
                    '(1999). Event-related EEG/MEG synchronization and desynchronization: basic principles. ' ...
                    'Clin Neurophysiol 110(11):1842-1857.']
                'rousseeuw1987', 'Rousseeuw, 1987', ['Rousseeuw PJ (1987). Silhouettes: a graphical aid to the ' ...
                    'interpretation and validation of cluster analysis. J Comput Appl Math 20:53-65.']
                'ester1996', 'Ester et al., 1996', ['Ester M, Kriegel HP, Sander J, Xu X (1996). A density-based ' ...
                    'algorithm for discovering clusters in large spatial databases with noise. In: Proceedings of ' ...
                    'the Second International Conference on Knowledge Discovery and Data Mining (KDD-96), pp. 226-231.']
                'otsu1979', 'Otsu, 1979', ['Otsu N (1979). A threshold selection method from gray-level ' ...
                    'histograms. IEEE Trans Syst Man Cybern 9(1):62-66.']
                'briers1996', 'Briers & Webster, 1996', ['Briers JD, Webster S (1996). Laser speckle contrast ' ...
                    'analysis (LASCA): a nonscanning, full-field technique for monitoring capillary blood flow. ' ...
                    'J Biomed Opt 1(2):174-179.']
                'boas2010', 'Boas & Dunn, 2010', ['Boas DA, Dunn AK (2010). Laser speckle contrast imaging in ' ...
                    'biomedical optics. J Biomed Opt 15(1):011109.']
                'bandyopadhyay2005', 'Bandyopadhyay et al., 2005', ['Bandyopadhyay R, Gittings AS, Suh SS, ' ...
                    'Dixon PK, Durian DJ (2005). Speckle-visibility spectroscopy: a tool to study time-varying ' ...
                    'dynamics. Rev Sci Instrum 76(9):093110.']
                'cheng2003', 'Cheng et al., 2003', ['Cheng H, Luo Q, Zeng S, Chen S, Cen J, Gong H (2003). ' ...
                    'Modified laser speckle imaging method with improved spatial resolution. J Biomed Opt ' ...
                    '8(3):559-564.']
                'delorme2004', 'Delorme & Makeig, 2004', ['Delorme A, Makeig S (2004). EEGLAB: an open source ' ...
                    'toolbox for analysis of single-trial EEG dynamics including independent component analysis. ' ...
                    'J Neurosci Methods 134(1):9-21.']
                'oostenveld2011', 'Oostenveld et al., 2011', ['Oostenveld R, Fries P, Maris E, Schoffelen JM (2011). ' ...
                    'FieldTrip: open source software for advanced analysis of MEG, EEG, and invasive ' ...
                    'electrophysiological data. Comput Intell Neurosci 2011:156869.']
                'widmann2015', 'Widmann et al., 2015', ['Widmann A, Schr' char(246) 'ger E, Maess B (2015). Digital ' ...
                    'filter design for electrophysiological data - a practical approach. J Neurosci Methods 250:34-46.']
                'oostenveld2001', 'Oostenveld & Praamstra, 2001', ['Oostenveld R, Praamstra P (2001). The five ' ...
                    'percent electrode system for high-resolution EEG and ERP measurements. Clin Neurophysiol ' ...
                    '112(4):713-719.']
                'perrin1989', 'Perrin et al., 1989', ['Perrin F, Pernier J, Bertrand O, Echallier JF (1989). ' ...
                    'Spherical splines for scalp potential and current density mapping. Electroencephalogr Clin ' ...
                    'Neurophysiol 72(2):184-187.']
                'duchon1977', 'Duchon, 1977', ['Duchon J (1977). Splines minimizing rotation-invariant ' ...
                    'semi-norms in Sobolev spaces. In: Schempp W, Zeller K (eds) Constructive Theory of Functions of ' ...
                    'Several Variables. Lecture Notes in Mathematics 571. Springer, Berlin, pp 85-100.']
                'jurcak2007', 'Jurcak et al., 2007', ['Jurcak V, Tsuzuki D, Dan I (2007). 10/20, 10/10, and 10/5 ' ...
                    'systems revisited: their validity as relative head-surface-based positioning systems. ' ...
                    'NeuroImage 34(4):1600-1611.']
                'student1908', 'Student, 1908', 'Student (1908). The probable error of a mean. Biometrika 6(1):1-25.'
                'welch1947', 'Welch, 1947', ['Welch BL (1947). The generalization of ''Student''s'' problem when ' ...
                    'several different population variances are involved. Biometrika 34(1-2):28-35.']
                'wilcoxon1945', 'Wilcoxon, 1945', ['Wilcoxon F (1945). Individual comparisons by ranking methods. ' ...
                    'Biometrics Bulletin 1(6):80-83.']
                'mannwhitney1947', 'Mann & Whitney, 1947', ['Mann HB, Whitney DR (1947). On a test of whether one ' ...
                    'of two random variables is stochastically larger than the other. Ann Math Stat 18(1):50-60.']
                'kruskal1952', 'Kruskal & Wallis, 1952', ['Kruskal WH, Wallis WA (1952). Use of ranks in ' ...
                    'one-criterion variance analysis. J Am Stat Assoc 47(260):583-621.']
                'kramer1956', 'Kramer, 1956', ['Kramer CY (1956). Extension of multiple range tests to group ' ...
                    'means with unequal numbers of replications. Biometrics 12(3):307-310.']
                'hedges1981', 'Hedges, 1981', ['Hedges LV (1981). Distribution theory for Glass''s estimator of ' ...
                    'effect size and related estimators. J Educ Stat 6(2):107-128.']
                'holm1979', 'Holm, 1979', ['Holm S (1979). A simple sequentially rejective multiple test ' ...
                    'procedure. Scand J Stat 6(2):65-70.']
                'friedman1937', 'Friedman, 1937', ['Friedman M (1937). The use of ranks to avoid the assumption ' ...
                    'of normality implicit in the analysis of variance. J Am Stat Assoc 32(200):675-701.']
                'mauchly1940', 'Mauchly, 1940', ['Mauchly JW (1940). Significance test for sphericity of a normal ' ...
                    'n-variate distribution. Ann Math Stat 11(2):204-209.']
                'greenhouse1959', 'Greenhouse & Geisser, 1959', ['Greenhouse SW, Geisser S (1959). On methods in ' ...
                    'the analysis of profile data. Psychometrika 24(2):95-112.']
                'huynh1976', 'Huynh & Feldt, 1976', ['Huynh H, Feldt LS (1976). Estimation of the Box correction ' ...
                    'for degrees of freedom from sample data in randomized block and split-plot designs. ' ...
                    'J Educ Stat 1(1):69-82.']
                'olejnik2003', 'Olejnik & Algina, 2003', ['Olejnik S, Algina J (2003). Generalized eta and omega ' ...
                    'squared statistics: measures of effect size for some common research designs. ' ...
                    'Psychol Methods 8(4):434-447.']
                'bakeman2005', 'Bakeman, 2005', ['Bakeman R (2005). Recommended effect size statistics for ' ...
                    'repeated measures designs. Behav Res Methods 37(3):379-384.']
                };
        end

        %% forApp - "Methods text..." button: open the dialog for the window (never throws)
        function fig = forApp(app)
            fig = [];
            lbl = Session.statusLabel(app);
            try
                s = Session.capture(app);
                fig = MethodsWriter.dialog(app, {s});
                UIKit.setStatus(lbl, ['Methods text drafted from this analysis: check it, then copy or ' ...
                    'save it.'], 'success');
            catch ME
                UIKit.setStatus(lbl, sprintf('Methods text not created: %s', ME.message), 'error');
                try
                    UIKit.alert(app.UIFig, sprintf('The methods text could not be created:\n%s', ME.message), ...
                        'Methods text', 'error');
                catch
                end
            end
        end

        %% dialog - Methods text window: editable text, Copy, Save .txt, Add saved sessions
        function fig = dialog(app, sessions)
            if nargin < 1, app = []; end
            if nargin < 2 || isempty(sessions)
                sessions = {Session.capture(app)};
            end
            sessions = MethodsWriter.sessionList(sessions);
            T = UITheme;
            D = UIKit.dialog('Methods text', ['Draft methods section from the saved settings: edit it ' ...
                'here, then copy it or save it as .txt'], 'Sessions and reports', [780 620]);
            fig = D.Fig;
            fig.WindowStyle = 'normal';
            fig.Resize = 'on';
            D.Body.Scrollable = 'off';
            D.Body.ColumnWidth = {'1x'};
            D.Body.RowHeight = {40, '1x', 'fit'};
            note = UIKit.hint(D.Body, MethodsWriter.CheckNote);
            note.Interpreter = 'none';
            note.Parent.Parent.Layout.Row = 1;
            ta = uitextarea(D.Body, 'Value', {''}, 'FontSize', T.fontBody, 'Editable', 'on', ...
                'Tooltip', 'Edit freely: the text is only a draft. Square brackets mark what you must add.');
            ta.Layout.Row = 2;
            status = uilabel(D.Body, 'Text', '', 'FontSize', T.fontSmall, 'FontColor', T.mutedColor, ...
                'Interpreter', 'none', 'WordWrap', 'on');
            status.Layout.Row = 3;

            % Buttons: Add saved sessions | (spacer) | Copy | Save .txt | Close
            D.Buttons.ColumnWidth = {170, '1x', 90, 110, 90};
            spacer = findobj(D.Buttons.Children, 'flat', 'Type', 'uilabel');
            if ~isempty(spacer), spacer(1).Layout.Column = 2; end
            b = UIKit.button(D.Buttons, ['Add saved sessions' char(8230)], ...
                @(~,~)MethodsWriter.addSessions(fig), 'secondary', ...
                ['Add .nasession.mat files of the other steps of this pipeline (e.g. Extract LDF, ' ...
                 'Process LDF, Average): one combined text, steps in pipeline order']);
            b.Layout.Column = 1;
            b = UIKit.button(D.Buttons, 'Copy', @(~,~)MethodsWriter.copyText(fig), 'secondary', ...
                'Copy the text (as edited) to the clipboard, to paste into Word');
            b.Layout.Column = 3;
            b = UIKit.button(D.Buttons, ['Save .txt' char(8230)], @(~,~)MethodsWriter.saveText(fig), ...
                'primary', 'Save the text (as edited) as a UTF-8 .txt file that Word opens');
            b.Layout.Column = 4;
            b = UIKit.button(D.Buttons, 'Close', @(~,~)delete(fig), 'secondary', 'Close this window');
            b.Layout.Column = 5;

            fig.UserData = struct('app', {app}, 'sessions', {sessions}, 'ta', ta, 'status', status, ...
                'generated', '');
            MethodsWriter.refreshDialog(fig);
        end
    end

    methods(Static, Hidden)

        %% describe - Paragraphs and needed toolboxes of one session
        function [paras, tbx] = describe(s)
            tbx = {};
            switch s.app
                case 'ExtractLDFApp',             paras = MethodsWriter.extractLDF(s);
                case 'ProcessingLDFApp',          [paras, tbx] = MethodsWriter.processingLDF(s);
                case 'LDFGrandAverageApp',        paras = MethodsWriter.ldfAverage(s);
                case 'LSCIAnalysisApp',           paras = MethodsWriter.lsciAnalysis(s);
                case 'ExtractEphysApp',           [paras, tbx] = MethodsWriter.extractEphys(s);
                case 'LFPAnalysisApp',            paras = MethodsWriter.lfpAnalysis(s);
                case 'MUAAnalysisApp',            [paras, tbx] = MethodsWriter.muaAnalysis(s);
                case 'ROIAnalysisApp',            paras = MethodsWriter.roiAnalysis(s);
                case 'HistologyApp',              paras = MethodsWriter.histology(s);
                case 'EEGAnalysisApp',            paras = MethodsWriter.eegAnalysis(s);
                case 'SignalCharacterizationApp', paras = MethodsWriter.signalCharacterization(s);
                otherwise
                    ttl = MethodsWriter.getf(s, 'appTitle', '');
                    if isempty(ttl), ttl = s.app; end
                    paras = {sprintf('[please add: describe the analysis done in %s.]', ttl)};
            end
            paras = paras(~cellfun(@isempty, paras));
            q = MethodsWriter.checksSentence(s);
            if ~isempty(paras) && ~isempty(q), paras{end} = [paras{end} ' ' q]; end
            if isempty(paras)
                ttl = MethodsWriter.getf(s, 'appTitle', '');
                if isempty(ttl), ttl = s.app; end
                paras = {sprintf(['[please add: the %s session holds no analysis yet (run the analysis ' ...
                    'before saving the session).]'], ttl)};
            end
        end

        %% checksSentence - What the window's quality checks reported ('' when none)
        function t = checksSentence(s)
            t = '';
            Q = QualityChecks.ensure(MethodsWriter.getf(s, 'checks', []));
            if isempty(Q), return; end
            parts = {sprintf('%d OK', QualityChecks.count(Q, 'ok'))};
            for lv = {'check', 'warning'}
                k = find(strcmp({Q.level}, lv{1}));
                topics = MethodsWriter.uniqueStable({Q(k).topic});
                if strcmp(lv{1}, 'check')
                    if isempty(k), w = 'none to check'; else, w = sprintf('%d to check', numel(k)); end
                else
                    w = QualityChecks.plural(numel(k), 'warning');
                end
                if ~isempty(k), w = sprintf('%s (%s)', w, strjoin(topics, ', ')); end
                parts{end+1} = w; %#ok<AGROW>
            end
            t = sprintf('The built-in quality checks reported %s, %s and %s.', parts{:});
        end

        %% extractLDF - Recording format, channels, sampling rate and crop
        % Sessions before the format / channel names were stored keep the
        % LabChart wording.
        function paras = extractLDF(s)
            fs = MethodsWriter.getf(s, 'results.fs', []);
            if ~MethodsWriter.isNum(fs)
                fs = MethodsWriter.fromSummary(s, 'Recording: \d+ samples at ([\d.eE+-]+) Hz');
            end
            ldfCh = MethodsWriter.getf(s, 'settings.ldfChannel', []);
            stimCh = MethodsWriter.getf(s, 'settings.stimulusChannel', []);
            fmt = MethodsWriter.getf(s, 'settings.format', '');
            if isempty(fmt)
                txt = ['Laser Doppler flowmetry (LDF) and the stimulus trigger were recorded [please add: LDF ' ...
                    'monitor, probe and acquisition system] and exported as a LabChart-format .mat file'];
                det = {};
                if MethodsWriter.isNum(ldfCh), det{end+1} = sprintf('LDF on channel %s', MethodsWriter.num(ldfCh)); end
                if MethodsWriter.isNum(stimCh), det{end+1} = sprintf('stimulus trigger on channel %s', MethodsWriter.num(stimCh)); end
                twoChannels = true;
            else
                switch fmt
                    case 'labchart',   how = ' with LabChart (ADInstruments) and exported as a .mat file';
                    case 'acqmat',     how = ' with AcqKnowledge (BIOPAC) and exported as a .mat file';
                    case 'spike2',     how = ' with Spike2 (CED) and exported as a .mat file';
                    case 'edf',        how = ' [please add: acquisition system] and stored as an EDF / BDF file';
                    case 'text'
                        lbl = MethodsWriter.getf(s, 'settings.formatLabel', '');
                        if strncmp(lbl, 'LabChart', 8)
                            how = ' with LabChart (ADInstruments) and exported as a text file';
                        elseif strncmp(lbl, 'AcqKnowledge', 12)
                            how = ' with AcqKnowledge (BIOPAC) and exported as a text file';
                        else
                            how = ' [please add: acquisition system] and exported as a text table';
                        end
                    case 'ldfcropped', how = ' [please add: acquisition system] and saved as a cropped LDF .mat file';
                    otherwise,         how = sprintf(' [please add: acquisition system] and read from a %s file', fmt);
                end
                txt = ['Laser Doppler flowmetry (LDF) and the stimulus were recorded [please add: LDF monitor ' ...
                    'and probe]' how];
                det = {};
                flowName = MethodsWriter.getf(s, 'settings.flowName', '');
                flowUnits = MethodsWriter.getf(s, 'settings.flowUnits', '');
                stimName = MethodsWriter.getf(s, 'settings.stimName', '');
                stim = MethodsWriter.getf(s, 'settings.stimulus', stimCh);
                twoChannels = MethodsWriter.isNum(stim) && stim > 0;
                if MethodsWriter.isNum(ldfCh)
                    nm = '';
                    if ~isempty(flowName) && ~isempty(flowUnits)
                        nm = sprintf(' ("%s", %s)', flowName, flowUnits);
                    elseif ~isempty(flowName)
                        nm = sprintf(' ("%s")', flowName);
                    end
                    det{end+1} = sprintf('LDF on channel %s%s', MethodsWriter.num(ldfCh), nm);
                end
                if ischar(stim) && strncmp(stim, 'events:', 7)
                    det{end+1} = sprintf('stimulus onsets from the comments "%s"', stim(8:end));
                elseif ischar(stim)
                    det{end+1} = 'stimulus onsets from the comments / event markers of the recording';
                elseif MethodsWriter.isNum(stim) && stim > 0
                    nm = '';
                    if ~isempty(stimName), nm = sprintf(' ("%s")', stimName); end
                    det{end+1} = sprintf('stimulus trigger on channel %s%s', MethodsWriter.num(stim), nm);
                elseif MethodsWriter.isNum(stim)
                    det{end+1} = 'no stimulus channel';
                end
                block = MethodsWriter.getf(s, 'settings.block', 1);
                if MethodsWriter.isNum(block) && block > 1
                    det{end+1} = sprintf('block %s of the recording', MethodsWriter.num(block));
                end
            end
            det = MethodsWriter.listText(det);
            if MethodsWriter.isNum(fs)
                if isempty(det)
                    det = sprintf('sampled at %s Hz', MethodsWriter.num(fs));
                elseif twoChannels
                    det = sprintf('%s, both sampled at %s Hz', det, MethodsWriter.num(fs));
                else
                    det = sprintf('%s, LDF sampled at %s Hz', det, MethodsWriter.num(fs));
                end
            end
            if ~isempty(det), txt = sprintf('%s (%s)', txt, det); end
            txt = [txt '.'];
            crop = MethodsWriter.getf(s, 'results.cropRange', []);
            n = MethodsWriter.getf(s, 'results.nSamples', []);
            if isnumeric(crop) && numel(crop) == 2 && all(isfinite(crop))
                txt = sprintf('%s The recording was cropped to %s&ndash;%s s (%s s', txt, MethodsWriter.num(crop(1)), ...
                    MethodsWriter.num(crop(2)), MethodsWriter.num(crop(2) - crop(1)));
                if MethodsWriter.isNum(n), txt = sprintf('%s, %s samples', txt, MethodsWriter.num(n)); end
                txt = [txt ') for further analysis.'];
            end
            paras = {txt};
        end

        %% processingLDF - Decimation, filter, onset detection and trials
        function [paras, tbx] = processingLDF(s)
            tbx = {};
            p = MethodsWriter.getf(s, 'settings.processing', []);
            tok = MethodsWriter.summaryTokens(s, 'Loaded \d+ samples at ([\d.eE+-]+) Hz; processed rate ([\d.eE+-]+) Hz');
            rawFs = NaN; newFs = MethodsWriter.getf(s, 'results.fs', NaN);
            if numel(tok) == 2
                rawFs = str2double(tok{1});
                if ~MethodsWriter.isNum(newFs), newFs = str2double(tok{2}); end
            end
            parts = {};
            if isstruct(p)
                ds = MethodsWriter.getf(p, 'downsample', 1);
                ft = MethodsWriter.getf(p, 'filterType', 1);
                if ~MethodsWriter.isNum(rawFs) && MethodsWriter.isNum(newFs) && MethodsWriter.isNum(ds)
                    rawFs = newFs * ds;
                end
                if MethodsWriter.isNum(ds) && ds > 1
                    tbx{end+1} = 'Signal Processing Toolbox';
                    t = sprintf('LDF signals were decimated by a factor of %s', MethodsWriter.num(ds));
                    if MethodsWriter.isNum(rawFs)
                        t = sprintf('%s (from %s to %s Hz)', t, MethodsWriter.num(rawFs), MethodsWriter.num(rawFs / ds));
                    end
                    t = sprintf(['%s with the MATLAB decimate function (8th-order Chebyshev type I ' ...
                        'anti-aliasing low-pass filter applied forward and backward), and the stimulus trigger was ' ...
                        'downsampled by keeping every %s sample.'], t, MethodsWriter.ordinal(ds));
                    parts{end+1} = t;
                end
                ftxt = MethodsWriter.ldfFilterText(p);
                if ~isempty(ftxt)
                    tbx{end+1} = 'Signal Processing Toolbox';
                    if MethodsWriter.isNum(ds) && ds > 1
                        parts{end+1} = sprintf('The decimated LDF was then %s.', ftxt);
                    elseif MethodsWriter.isNum(rawFs)
                        parts{end+1} = sprintf('LDF signals (sampled at %s Hz) were %s.', MethodsWriter.num(rawFs), ftxt);
                    else
                        parts{end+1} = sprintf('LDF signals were %s.', ftxt);
                    end
                elseif ~(MethodsWriter.isNum(ds) && ds > 1) && ft == 1
                    if MethodsWriter.isNum(rawFs)
                        parts{end+1} = sprintf(['LDF signals were analysed at their original sampling rate ' ...
                            '(%s Hz) without additional filtering.'], MethodsWriter.num(rawFs));
                    else
                        parts{end+1} = 'LDF signals were analysed without downsampling or additional filtering.';
                    end
                end
            end
            nTr = MethodsWriter.getf(s, 'results.nTrials', []);
            seg = logical(MethodsWriter.getf(s, 'settings.segmented', false)) || MethodsWriter.isNum(nTr);
            if seg
                thr = MethodsWriter.getf(s, 'settings.threshold', []);
                isi = MethodsWriter.getf(s, 'settings.minISI', []);
                pre = MethodsWriter.getf(s, 'settings.preS', []);
                post = MethodsWriter.getf(s, 'settings.postS', []);
                win = MethodsWriter.getf(s, 'results.window', []);
                if ~MethodsWriter.isNum(pre) && numel(win) == 2, pre = -win(1); end
                if ~MethodsWriter.isNum(post) && numel(win) == 2, post = win(2); end
                t = 'Stimulus onsets were detected as rising edges of the trigger signal';
                if MethodsWriter.isNum(thr), t = sprintf('%s above %s (trigger signal units)', t, MethodsWriter.num(thr)); end
                if MethodsWriter.isNum(isi)
                    t = sprintf('%s, keeping only onsets at least %s after the previous accepted onset', t, MethodsWriter.dur(isi));
                end
                parts{end+1} = [t '.'];
                if MethodsWriter.isNum(pre) && MethodsWriter.isNum(post)
                    t = sprintf('Trials were cut from %s before to %s after each onset', ...
                        MethodsWriter.dur(pre), MethodsWriter.dur(post));
                else
                    t = 'Trials were cut around each onset';
                end
                if MethodsWriter.isNum(nTr), t = sprintf('%s (n = %s trials)', t, MethodsWriter.num(nTr)); end
                parts{end+1} = [t '; trials that did not fit completely within the recording were discarded.'];
            end
            paras = {strjoin(parts, ' ')};
        end

        %% ldfFilterText - "low-pass filtered at 1 Hz (4th-order Butterworth filter, ...)" ('' = none)
        function t = ldfFilterText(p)
            t = '';
            ft = MethodsWriter.getf(p, 'filterType', 1);
            if ~MethodsWriter.isNum(ft) || ft == 1, return; end
            lo = MethodsWriter.getf(p, 'cutoffLow', NaN);
            hi = MethodsWriter.getf(p, 'cutoffHigh', NaN);
            n = MethodsWriter.getf(p, 'filterOrder', NaN);
            dt = MethodsWriter.getf(p, 'designType', 1);
            switch ft
                case 2
                    if ~MethodsWriter.isNum(hi), return; end
                    what = sprintf('low-pass filtered at %s Hz', MethodsWriter.num(hi));
                case 3
                    if ~MethodsWriter.isNum(lo), return; end
                    what = sprintf('high-pass filtered at %s Hz', MethodsWriter.num(lo));
                case 4
                    if ~MethodsWriter.isNum(lo) || ~MethodsWriter.isNum(hi), return; end
                    what = sprintf('band-pass filtered between %s and %s Hz', MethodsWriter.num(lo), MethodsWriter.num(hi));
                case 5
                    if ~MethodsWriter.isNum(lo) || ~MethodsWriter.isNum(hi), return; end
                    what = sprintf('band-stop (notch) filtered between %s and %s Hz', MethodsWriter.num(lo), MethodsWriter.num(hi));
                otherwise
                    return;
            end
            twoBand = any(ft == [4 5]);
            if ~MethodsWriter.isNum(n)
                design = '';
            elseif dt == 3
                design = sprintf('FIR filter of order %s, window method with a Hamming window', MethodsWriter.num(n));
            else
                nEff = n;
                if twoBand, nEff = 2 * n; end
                if dt == 2
                    design = sprintf('%s-order Chebyshev type I filter with 0.5 dB passband ripple', MethodsWriter.ordinal(nEff));
                else
                    design = sprintf('%s-order Butterworth filter', MethodsWriter.ordinal(nEff));
                end
                if twoBand, design = sprintf('%s, design order %s', design, MethodsWriter.num(n)); end
            end
            zp = 'applied forward and backward for zero phase shift';
            if isempty(design)
                t = sprintf('%s (%s)', what, zp);
            else
                t = sprintf('%s (%s, %s)', what, design, zp);
            end
        end

        %% ldfAverage - Pooled trials, baseline, grand average
        function paras = ldfAverage(s)
            nTr = MethodsWriter.getf(s, 'results.nTrials', []);
            if ~MethodsWriter.isNum(nTr), paras = {}; return; end
            counts = MethodsWriter.getf(s, 'results.fileCounts', []);
            nFiles = max(numel(s.inputs), numel(counts));
            win = MethodsWriter.getf(s, 'results.window', []);
            t = sprintf('Trials from %s', MethodsWriter.plural(nFiles, 'recording file'));
            if numel(counts) > 1 && all(isfinite(counts))
                t = sprintf('%s (%s trials per file; n = %s trials in total)', t, ...
                    MethodsWriter.listText(arrayfun(@(x) MethodsWriter.num(x), counts(:)', 'UniformOutput', false)), ...
                    MethodsWriter.num(nTr));
            else
                t = sprintf('%s (n = %s trials)', t, MethodsWriter.num(nTr));
            end
            if isnumeric(win) && numel(win) == 2 && all(isfinite(win))
                t = sprintf('%s, spanning %s around stimulus onset,', t, MethodsWriter.secRange(win(1), win(2)));
            end
            t = [t ' were pooled.'];
            if logical(MethodsWriter.getf(s, 'settings.relativeToBaseline', false))
                t = [t ' Each trial was expressed relative to its pre-stimulus baseline by subtracting the ' ...
                    'mean of its samples before onset.'];
            end
            if logical(MethodsWriter.getf(s, 'settings.grandAverageShown', false))
                t = [t ' The grand average was computed as the mean &plusmn; SD across all trials.'];
            end
            if MethodsWriter.isNum(MethodsWriter.getf(s, 'results.peakChange', []))
                t = [t ' The response was quantified as the maximum of the mean trial after onset minus ' ...
                    'the mean pre-stimulus baseline (in the units of the LDF signal and as a percentage of ' ...
                    'the baseline), and its time after onset.'];
            end
            paras = {t};
        end

        %% lsciAnalysis - Speckle contrast, flow index, ROIs, trials and the response map
        function paras = lsciAnalysis(s)
            p = MethodsWriter.getf(s, 'settings.params', struct());
            if ~isstruct(p) || ~isfield(p, 'InputType'), paras = {}; return; end
            parts = {};
            tok = MethodsWriter.summaryTokens(s, 'Images: (\d+) x (\d+) px, (\d+) frames');
            dims = '';
            if numel(tok) == 3
                dims = sprintf(' (%s &times; %s pixels, %s frames)', tok{1}, tok{2}, tok{3});
            end
            fps = MethodsWriter.getf(s, 'results.fps', NaN);
            expo = MethodsWriter.getf(p, 'ExposureMs', NaN);
            switch p.InputType
                case 'raw'
                    if MethodsWriter.isNum(expo)
                        t = sprintf(['Laser speckle images%s were acquired with an exposure time of %s ms [please ' ...
                            'add: laser wavelength and power, camera, magnification and frame rate].'], dims, ...
                            MethodsWriter.num(expo));
                    else
                        t = sprintf(['Laser speckle images%s were acquired [please add: laser wavelength and power, ' ...
                            'camera, magnification, frame rate and exposure time].'], dims);
                    end
                    parts{end+1} = t;
                    dark = MethodsWriter.getf(p, 'Dark', 0);
                    if MethodsWriter.isNum(dark) && dark > 0
                        parts{end+1} = sprintf('A camera dark level of %s counts was subtracted from every image.', ...
                            MethodsWriter.num(dark));
                    end
                    n = MethodsWriter.getf(p, 'Frames', 1);
                    if strcmp(MethodsWriter.getf(p, 'Contrast', 'spatial'), 'temporal')
                        t = sprintf(['Temporal speckle contrast K = &sigma;/mean(I) was computed for every ' ...
                            'pixel over non-overlapping blocks of %s consecutive frames ({{cheng2003}}).'], MethodsWriter.num(n));
                    else
                        w = MethodsWriter.num(MethodsWriter.getf(p, 'Window', 7));
                        t = sprintf(['Spatial speckle contrast K = &sigma;/mean(I) of the intensity was computed in a sliding ' ...
                            '%s &times; %s pixel window in every frame ({{briers1996}}; {{boas2010}})'], w, w);
                        if MethodsWriter.isNum(n) && n > 1
                            t = sprintf('%s, and K&sup2; was averaged over non-overlapping blocks of %s frames', t, ...
                                MethodsWriter.num(n));
                        end
                        t = [t '.'];
                    end
                    parts{end+1} = t;
                case 'contrast'
                    parts{end+1} = sprintf(['Speckle contrast images%s [please add: how the contrast was ' ...
                        'computed and by which system] were analysed.'], dims);
                otherwise
                    parts{end+1} = sprintf(['Perfusion images%s were exported from [please add: the laser speckle ' ...
                        'system and software, with its settings] and analysed in the units of that system.'], dims);
            end
            if ~strcmp(p.InputType, 'flow')
                if strcmp(MethodsWriter.getf(p, 'FlowModel', 'invK2'), 'tauc')
                    parts{end+1} = sprintf(['Blood flow was indexed by the inverse decorrelation time 1/&tau;c, ' ...
                        'obtained by solving K&sup2; = &beta;[exp(&minus;2x) &minus; 1 + 2x]/(2x&sup2;), x = T/&tau;c, ' ...
                        'for each value ({{bandyopadhyay2005}}; {{boas2010}}), with T = %s ms and &beta; = %s.'], ...
                        MethodsWriter.num(expo), MethodsWriter.num(MethodsWriter.getf(p, 'Beta', 1)));
                else
                    parts{end+1} = ['Blood flow was indexed by the speckle flow index 1/K&sup2;, which is ' ...
                        'proportional to the inverse decorrelation time for exposures much longer than it ({{boas2010}}).'];
                end
            end
            names = cellstr(MethodsWriter.getf(s, 'results.roiNames', {}));
            if ~isempty(names)
                if numel(names) == 1 && strcmp(names{1}, 'Whole image')
                    t = 'The flow index was averaged over the whole image';
                else
                    if numel(names) == 1, roiW = 'one region of interest'; else, roiW = sprintf('%d regions of interest', numel(names)); end
                    t = sprintf('The flow index was measured in %s (%s)', roiW, MethodsWriter.listText(names));
                end
                if MethodsWriter.isNum(fps)
                    t = sprintf('%s at %s values per second', t, MethodsWriter.num(fps));
                end
                if ~strcmp(p.InputType, 'flow')
                    t = [t ', averaging K&sup2; over the pixels of each region before conversion'];
                end
                parts{end+1} = [t '.'];
            end
            on = MethodsWriter.getf(s, 'results.onsets', []);
            if isnumeric(on) && ~isempty(on)
                rw = MethodsWriter.getf(p, 'ResponseSec', [NaN NaN]);
                if numel(on) == 1, stimW = 'For the stimulus'; else, stimW = sprintf('For each of %d stimuli', numel(on)); end
                parts{end+1} = sprintf(['%s, a trial from %s s before to %s s after onset was expressed ' ...
                    'as the percentage change from its mean before onset; trials were averaged (mean &plusmn; SD), ' ...
                    'and the response was taken as the mean change %s after onset. A response map was computed ' ...
                    'as the percentage change, in every pixel, of the flow index averaged over that window and ' ...
                    'over trials, relative to the pre-stimulus period.'], stimW, ...
                    MethodsWriter.num(MethodsWriter.getf(p, 'PreSec', NaN)), MethodsWriter.num(MethodsWriter.getf(p, 'PostSec', NaN)), ...
                    MethodsWriter.secRange(rw(1), rw(2)));
            end
            paras = {strjoin(parts, ' ')};
        end

        %% extractEphys - Wideband source, LFP and MUA extraction
        function [paras, tbx] = extractEphys(s)
            tbx = {};
            fmt = MethodsWriter.getf(s, 'settings.format', '');
            src = MethodsWriter.formatLabel(fmt);
            rawFs = MethodsWriter.fromSummary(s, 'RAW channels at ([\d.eE+-]+) Hz');
            parts = {};
            t = 'Wideband extracellular signals were recorded [please add: probe or electrode, amplifier and acquisition system]';
            if ~isempty(src), t = sprintf('%s and read from the %s', t, src); end
            if MethodsWriter.isNum(rawFs), t = sprintf('%s (sampled at %s Hz)', t, MethodsWriter.num(rawFs)); end
            parts{end+1} = [t '.'];
            lfp = MethodsWriter.getf(s, 'settings.lfp', []);
            if isstruct(lfp)
                tbx{end+1} = 'Signal Processing Toolbox';
                p = MethodsWriter.getf(lfp, 'params', struct());
                ch = MethodsWriter.getf(lfp, 'channels', []);
                fsL = MethodsWriter.getf(s, 'results.lfp.fs', NaN);
                steps = {};
                if logical(MethodsWriter.getf(p, 'downsample', false)) && MethodsWriter.isNum(fsL)
                    st = sprintf(['anti-alias low-pass filtered (4th-order Butterworth filter at %s Hz, 0.8 ' ...
                        'times the new Nyquist frequency)'], MethodsWriter.num(0.8 * fsL / 2));
                    if MethodsWriter.isNum(rawFs)
                        st = sprintf('%s and downsampled by a factor of %s to %s Hz', st, ...
                            MethodsWriter.num(round(rawFs / fsL)), MethodsWriter.num(fsL));
                    else
                        st = sprintf('%s and downsampled to %s Hz', st, MethodsWriter.num(fsL));
                    end
                    steps{end+1} = st;
                end
                lc = MethodsWriter.getf(p, 'lowCutoff', NaN);
                if MethodsWriter.isNum(lc) && lc > 0 && (~MethodsWriter.isNum(fsL) || lc < fsL / 2)
                    steps{end+1} = sprintf('low-pass filtered at %s Hz (4th-order Butterworth filter)', MethodsWriter.num(lc));
                end
                if logical(MethodsWriter.getf(p, 'notch60', false))
                    steps{end+1} = 'notch filtered at 60 Hz (second-order IIR notch filter, Q = 35)';
                end
                t = 'To obtain local field potentials (LFP)';
                if ~isempty(ch), t = sprintf('%s, %s', t, MethodsWriter.chanText(ch)); end
                if isempty(steps)
                    if MethodsWriter.isNum(fsL)
                        t = sprintf('%s were kept at %s Hz without filtering.', t, MethodsWriter.num(fsL));
                    else
                        t = sprintf('%s were used without filtering.', t);
                    end
                else
                    if isempty(ch), t = [t ', the signals']; end
                    t = sprintf('%s were %s; all filters were applied forward and backward (zero phase shift).', ...
                        t, MethodsWriter.listText(steps));
                end
                parts{end+1} = t;
            end
            mua = MethodsWriter.getf(s, 'settings.mua', []);
            if isstruct(mua)
                tbx{end+1} = 'Signal Processing Toolbox';
                p = MethodsWriter.getf(mua, 'params', struct());
                ch = MethodsWriter.getf(mua, 'channels', []);
                lo = MethodsWriter.getf(p, 'lowCutoff', NaN);
                hi = MethodsWriter.getf(p, 'highCutoff', NaN);
                n = MethodsWriter.getf(p, 'order', NaN);
                typ = MethodsWriter.getf(p, 'filterType', '');
                t = 'For multi-unit activity (MUA)';
                if ~isempty(ch), t = sprintf('%s, %s', t, MethodsWriter.chanText(ch)); else, t = [t ', the signals']; end
                if MethodsWriter.isNum(lo) && MethodsWriter.isNum(hi)
                    t = sprintf('%s were band-pass filtered between %s and %s Hz', t, MethodsWriter.num(lo), MethodsWriter.num(hi));
                    if MethodsWriter.isNum(n)
                        if strcmpi(typ, 'Chebyshev I')
                            kind = 'Chebyshev type I band-pass filter with 0.5 dB passband ripple';
                        else
                            kind = 'Butterworth band-pass filter';
                        end
                        t = sprintf('%s (%s-order %s, design order %s, applied forward and backward)', t, ...
                            MethodsWriter.ordinal(2 * n), kind, MethodsWriter.num(n));
                    end
                    t = [t '; the unsmoothed band-passed signal was used for further analysis.'];
                else
                    t = [t ' were band-pass filtered [please add: pass band].'];
                end
                parts{end+1} = t;
            end
            stimCh = MethodsWriter.getf(s, 'settings.stimChannel', []);
            if MethodsWriter.isNum(stimCh)
                parts{end+1} = sprintf('The stimulus was read from stimulus channel %s.', MethodsWriter.num(stimCh));
            end
            paras = {strjoin(parts, ' ')};
        end

        %% lfpAnalysis - ERP, CSD and time-frequency steps
        function paras = lfpAnalysis(s)
            tok = MethodsWriter.summaryTokens(s, 'LFP: (\d+) channels at ([\d.eE+-]+) Hz');
            fs = NaN;
            if numel(tok) == 2, fs = str2double(tok{2}); end
            erp = MethodsWriter.getf(s, 'settings.erp', []);
            rErp = MethodsWriter.getf(s, 'results.erp', []);
            parts = {};
            hasOnsets = false;
            if isstruct(erp) && isstruct(rErp)
                p = MethodsWriter.getf(erp, 'params', struct());
                thr = MethodsWriter.getf(p, 'threshold', NaN);
                isi = MethodsWriter.getf(p, 'minISI', NaN);
                nOn = numel(MethodsWriter.getf(rErp, 'onsetTimes', []));
                t = 'Stimulus onsets were detected as upward crossings of';
                if MethodsWriter.isNum(thr)
                    t = sprintf('%s a threshold of %s (stimulus units) by the mean-subtracted stimulus signal', t, MethodsWriter.num(thr));
                else
                    t = sprintf('%s a threshold by the mean-subtracted stimulus signal', t);
                end
                if MethodsWriter.isNum(isi)
                    t = sprintf('%s; crossings less than %s after the previous accepted onset were ignored', t, MethodsWriter.dur(isi));
                end
                if nOn > 0, t = sprintf('%s (n = %d onsets)', t, nOn); end
                parts{end+1} = [t '.'];
                hasOnsets = true;
                pre = MethodsWriter.getf(p, 'preTime', NaN);
                post = MethodsWriter.getf(p, 'postTime', NaN);
                ch = MethodsWriter.getf(erp, 'channels', []);
                nV = MethodsWriter.getf(rErp, 'nValid', NaN);
                t = 'Event-related potentials (ERPs) were computed';
                if ~isempty(ch), t = sprintf('%s for %s', t, MethodsWriter.chanText(ch)); end
                if MethodsWriter.isNum(fs), t = sprintf('%s (LFP sampled at %s Hz)', t, MethodsWriter.num(fs)); end
                if MethodsWriter.isNum(pre) && MethodsWriter.isNum(post)
                    t = sprintf('%s by averaging epochs from %s before to %s after each onset', t, ...
                        MethodsWriter.dur(pre), MethodsWriter.dur(post));
                else
                    t = sprintf('%s by averaging epochs around each onset', t);
                end
                if MethodsWriter.isNum(nV) && nOn > 0
                    t = sprintf('%s (n = %s of %d epochs; epochs extending beyond the recording were excluded)', ...
                        t, MethodsWriter.num(nV), nOn);
                end
                parts{end+1} = [t '.'];
            end
            csdTxt = MethodsWriter.csdText(s);
            if ~isempty(csdTxt), parts{end+1} = csdTxt; end
            tf = MethodsWriter.tfText(s, hasOnsets);
            parts = [parts, tf];
            paras = {};
            if ~isempty(parts), paras = {strjoin(parts, ' ')}; end
        end

        %% csdText - Standard / iCSD / kCSD description ('' when no CSD)
        function t = csdText(s)
            t = '';
            c = MethodsWriter.getf(s, 'settings.csd', []);
            if ~isstruct(c) || ~logical(MethodsWriter.getf(c, 'computed', false)), return; end
            method = MethodsWriter.getf(c, 'usedMethod', '');
            if isempty(method), method = MethodsWriter.getf(c, 'method', 'standard'); end
            sp = MethodsWriter.getf(c, 'usedSpacingUm', MethodsWriter.getf(c, 'spacingUm', NaN));
            order = MethodsWriter.getf(c, 'usedOrder', []);
            p = MethodsWriter.getf(c, 'usedParams', []);
            if ~isstruct(p), p = MethodsWriter.getf(c, 'params', struct()); end
            info = MethodsWriter.getf(s, 'results.csd.info', struct());
            if ~isstruct(info), info = struct(); end
            nCh = numel(order);
            from = 'from the ERPs';
            if nCh > 0
                from = sprintf('from the ERPs of %d contacts (%s, ordered from superficial to deep', nCh, ...
                    MethodsWriter.orderText(order));
                if MethodsWriter.isNum(sp), from = sprintf('%s; inter-contact spacing %s &mu;m', from, MethodsWriter.num(sp)); end
                from = [from ')'];
            elseif MethodsWriter.isNum(sp)
                from = sprintf('%s (inter-contact spacing %s &mu;m)', from, MethodsWriter.num(sp));
            end
            sigma = MethodsWriter.getf(p, 'sigma', NaN);
            diam = MethodsWriter.getf(p, 'diameterUm', NaN);
            medium = '';
            if MethodsWriter.isNum(diam) && MethodsWriter.isNum(sigma)
                medium = sprintf(['discs of %s &mu;m diameter in a homogeneous medium of conductivity ' ...
                    '%s S/m'], MethodsWriter.num(diam), MethodsWriter.num(sigma));
            end
            switch lower(method)
                case 'standard'
                    t = sprintf(['Current source density (CSD) was estimated %s as the negative second spatial ' ...
                        'derivative of the potential (three-point finite difference; {{nicholson1975}}; ' ...
                        '{{mitzdorf1985}}). Values at the first and last contacts were copied from their neighbours, ' ...
                        'and the conductivity was not included (CSD in V/m&sup2;).'], from);
                case {'delta', 'step', 'spline'}
                    names = struct('delta', 'delta-source', 'step', 'step', 'spline', 'cubic-spline');
                    t = sprintf('Current source density (CSD) was estimated %s with the %s inverse CSD method (iCSD; {{pettersen2006}})', ...
                        from, names.(lower(method)));
                    if ~isempty(medium), t = sprintf('%s, modelling the sources as %s', t, medium); end
                    t = [t ' (CSD in A/m&sup3;).'];
                    sm = MethodsWriter.getf(p, 'smoothUm', 0);
                    if MethodsWriter.isNum(sm) && sm > 0
                        t = sprintf('%s The estimate was then smoothed across depth with a Gaussian filter (SD %s &mu;m).', ...
                            t, MethodsWriter.num(sm));
                    end
                case 'kcsd'
                    t = sprintf('Current source density (CSD) was estimated %s with one-dimensional kernel CSD (kCSD; {{potworowski2012}})', from);
                    nSrc = MethodsWriter.getf(info, 'nSources', NaN);
                    if MethodsWriter.isNum(nSrc)
                        t = sprintf('%s, using %s Gaussian basis sources', t, MethodsWriter.num(nSrc));
                    else
                        t = sprintf('%s, using Gaussian basis sources', t);
                    end
                    if ~isempty(medium), t = sprintf('%s and a forward model of %s', t, medium); end
                    t = [t ' (CSD in A/m&sup3;).'];
                    R = MethodsWriter.getf(info, 'R', NaN);
                    lamRel = MethodsWriter.getf(info, 'lambdaRel', NaN);
                    rCV = ~(MethodsWriter.isNum(MethodsWriter.getf(p, 'RUm', 0)) && MethodsWriter.getf(p, 'RUm', 0) > 0);
                    lCV = ~(MethodsWriter.isNum(MethodsWriter.getf(p, 'lambda', 0)) && MethodsWriter.getf(p, 'lambda', 0) > 0);
                    rTxt = 'the basis width R';
                    if MethodsWriter.isNum(R), rTxt = sprintf('the basis width R (%s &mu;m)', MethodsWriter.num(R)); end
                    lTxt = 'the regularisation parameter &lambda;';
                    if MethodsWriter.isNum(lamRel)
                        lTxt = sprintf('the regularisation parameter &lambda; (%s relative to the mean diagonal of the kernel matrix)', ...
                            MethodsWriter.num(lamRel));
                    end
                    if rCV && lCV
                        t = sprintf('%s Both %s and %s were chosen by leave-one-out cross-validation of the potentials.', t, rTxt, lTxt);
                    elseif rCV
                        t = sprintf('%s %s was chosen by leave-one-out cross-validation of the potentials; %s was set by the user.', ...
                            t, MethodsWriter.capital(rTxt), lTxt);
                    elseif lCV
                        t = sprintf('%s %s was chosen by leave-one-out cross-validation of the potentials; %s was set by the user.', ...
                            t, MethodsWriter.capital(lTxt), rTxt);
                    else
                        t = sprintf('%s %s and %s were set by the user.', t, MethodsWriter.capital(rTxt), lTxt);
                    end
                otherwise
                    t = sprintf('Current source density (CSD) was estimated %s ([please add: CSD method]).', from);
            end
        end

        %% tfText - Spectrum, spectrogram, ERSP / ITPC and band power sentences
        function parts = tfText(s, hasOnsets)
            parts = {};
            runs = MethodsWriter.getf(s, 'settings.tfRuns', struct());
            if ~isstruct(runs), return; end
            sp = MethodsWriter.getf(runs, 'spectrum', []);
            if isstruct(sp)
                seg = MethodsWriter.getf(s, 'results.spectrum.segSec', NaN);
                t = sprintf('The power spectral density of channel %s was estimated with Welch''s method ({{welch1967}}', ...
                    MethodsWriter.num(sp.channel));
                if MethodsWriter.isNum(seg)
                    t = sprintf('%s; Hann-windowed segments of %s with 50%% overlap, segment means removed', t, MethodsWriter.dur(seg));
                end
                parts{end+1} = [t ').'];
            end
            sg = MethodsWriter.getf(runs, 'spectrogram', []);
            if isstruct(sg)
                fr = MethodsWriter.getf(sg, 'fRange', []);
                win = MethodsWriter.getf(s, 'results.spectrogram.winSec', NaN);
                t = sprintf('A spectrogram of channel %s', MethodsWriter.num(sg.channel));
                if numel(fr) == 2, t = sprintf('%s (%s&ndash;%s Hz)', t, MethodsWriter.num(fr(1)), MethodsWriter.num(fr(2))); end
                t = [t ' was computed with a short-time Fourier transform'];
                if MethodsWriter.isNum(win), t = sprintf('%s (Hann windows of %s, 90%% overlap)', t, MethodsWriter.dur(win)); end
                parts{end+1} = [t '.'];
            end
            er = MethodsWriter.getf(runs, 'ersp', []);
            bp = MethodsWriter.getf(runs, 'bandpower', []);
            if (isstruct(er) || isstruct(bp)) && ~hasOnsets
                parts{end+1} = 'Stimulus onsets were detected as upward threshold crossings of the mean-subtracted stimulus signal.';
            end
            if isstruct(er)
                fr = MethodsWriter.getf(er, 'fRange', []);
                w = MethodsWriter.getf(er, 'window', []);
                b = MethodsWriter.getf(er, 'baseline', []);
                nc = MethodsWriter.getf(er, 'nCycles', NaN);
                nF = numel(MethodsWriter.getf(s, 'results.ersp.freqs', []));
                nT = MethodsWriter.getf(s, 'results.ersp.info.nTrials', NaN);
                t = sprintf(['Event-related spectral perturbation (ERSP; {{makeig1993}}) and inter-trial phase ' ...
                    'coherence (ITPC; {{tallonbaudry1996}}) of channel %s were computed from complex Morlet wavelet ' ...
                    'transforms'], MethodsWriter.num(er.channel));
                det = {};
                if MethodsWriter.isNum(nc), det{end+1} = sprintf('%s cycles', MethodsWriter.num(nc)); end
                if numel(fr) == 2
                    if nF > 0
                        det{end+1} = sprintf('%d frequencies from %s to %s Hz', nF, MethodsWriter.num(fr(1)), MethodsWriter.num(fr(2)));
                    else
                        det{end+1} = sprintf('%s&ndash;%s Hz', MethodsWriter.num(fr(1)), MethodsWriter.num(fr(2)));
                    end
                end
                det{end+1} = 'wavelets normalised to unit energy';
                t = sprintf('%s (%s)', t, strjoin(det, '; '));
                if numel(w) == 2, t = sprintf('%s of epochs from %s around each stimulus onset', t, MethodsWriter.secRange(w(1), w(2))); end
                if MethodsWriter.isNum(nT), t = sprintf('%s (up to %s trials', t, MethodsWriter.num(nT)); else, t = [t ' (']; end
                if MethodsWriter.isNum(nT), t = [t '; ']; end
                t = [t 'at each frequency, only epochs whose wavelet support lay within the recording were used).'];
                if numel(b) == 2
                    t = sprintf(['%s ERSP was expressed in dB relative to the trial-averaged power in the ' ...
                        'baseline window (%s), and ITPC as the length of the mean unit phase vector across trials.'], ...
                        t, MethodsWriter.secRange(b(1), b(2)));
                end
                parts{end+1} = t;
            end
            if isstruct(bp)
                names = cellstr(MethodsWriter.getf(bp, 'names', {}));
                rg = MethodsWriter.getf(bp, 'ranges', []);
                w = MethodsWriter.getf(bp, 'window', []);
                b = MethodsWriter.getf(bp, 'baseline', []);
                bands = {};
                if size(rg, 1) == numel(names) && size(rg, 2) == 2
                    for k = 1:numel(names)
                        bands{end+1} = sprintf('%s %s&ndash;%s Hz', names{k}, MethodsWriter.num(rg(k, 1)), MethodsWriter.num(rg(k, 2))); %#ok<AGROW>
                    end
                end
                t = sprintf('Band-limited power of channel %s', MethodsWriter.num(bp.channel));
                if ~isempty(bands), t = sprintf('%s (%s)', t, MethodsWriter.listText(bands)); end
                t = [t ' was computed as the squared magnitude of the analytic signal of the band-pass filtered LFP ' ...
                    '(FFT-based band-pass filter with raised-cosine edges, equivalent to band-pass filtering followed ' ...
                    'by the Hilbert transform)'];
                if numel(w) == 2, t = sprintf('%s in epochs from %s around each onset', t, MethodsWriter.secRange(w(1), w(2))); end
                t = [t ', and expressed as percent change from the trial-averaged power in the baseline window'];
                if numel(b) == 2
                    t = sprintf('%s (%s; {{pfurtscheller1999}}).', t, MethodsWriter.secRange(b(1), b(2)));
                else
                    t = [t ' ({{pfurtscheller1999}}).'];
                end
                parts{end+1} = t;
            end
        end

        %% muaAnalysis - Detection, alignment, features, clustering, QC
        function [paras, tbx] = muaAnalysis(s)
            tbx = {};
            fsTok = MethodsWriter.summaryTokens(s, 'MUA: \d+ channel\(s\) at ([\d.eE+-]+) Hz');
            fs = NaN;
            if ~isempty(fsTok), fs = str2double(fsTok{1}); end
            ch = MethodsWriter.getf(s, 'settings.channel', NaN);
            res = MethodsWriter.getf(s, 'results.spikeResults', []);
            if ~isstruct(res)
                t = 'Multi-unit activity';
                if MethodsWriter.isNum(ch), t = sprintf('%s of channel %s', t, MethodsWriter.num(ch)); end
                if MethodsWriter.isNum(fs), t = sprintf('%s (sampled at %s Hz)', t, MethodsWriter.num(fs)); end
                paras = {[t ' was loaded [please add: spike sorting was not run in this session].']};
                return;
            end
            tbx = {'Signal Processing Toolbox', 'Statistics and Machine Learning Toolbox'};
            p = MethodsWriter.getf(s, 'settings.sortParams', struct());
            if ~isstruct(p), p = struct(); end
            try, p = MUAPipeline.completeParams(p); catch, end
            parts = {};
            t = 'Spikes were detected';
            if MethodsWriter.isNum(ch), t = sprintf('%s on channel %s', t, MethodsWriter.num(ch)); end
            if MethodsWriter.isNum(fs), t = sprintf('%s (MUA sampled at %s Hz)', t, MethodsWriter.num(fs)); end
            segWin = MethodsWriter.getf(s, 'results.sortContext.segWin', []);
            if isnumeric(segWin) && numel(segWin) == 2 && all(isfinite(segWin))
                t = sprintf('%s within the time window %s of the recording', t, MethodsWriter.secRange(segWin(1), segWin(2)));
            end
            if logical(MethodsWriter.getf(p, 'filter', 0))
                t = sprintf('%s after band-pass filtering between %s and %s Hz (6th-order Butterworth filter, design order 3, applied forward and backward)', ...
                    t, MethodsWriter.num(p.bpLow), MethodsWriter.num(p.bpHigh));
            end
            k = MethodsWriter.num(MethodsWriter.getf(p, 'threshold', NaN));
            switch lower(MethodsWriter.getf(p, 'detectMethod', 'standard'))
                case 'mad'
                    thr = sprintf(['with an amplitude threshold of the median plus %s times the robust standard ' ...
                        'deviation (1.4826 times the median absolute deviation) of the signal'], k);
                case 'rolling mad'
                    thr = sprintf(['with an amplitude threshold of the median plus %s times the robust standard ' ...
                        'deviation (1.4826 times the median absolute deviation) of the signal, taking the local ' ...
                        'maximum within %s ms of each crossing'], k, MethodsWriter.num(0.5 * p.alignWinMs));
                case 'neo'
                    thr = sprintf(['with the nonlinear energy operator, &psi;[n] = x[n]&sup2; &minus; x[n&minus;1]x[n+1], and a threshold ' ...
                        'of the mean plus %s times the standard deviation of &psi;'], k);
                case 'percentile'
                    thr = 'with a threshold at the 99.9th percentile of the absolute signal amplitude';
                otherwise
                    thr = sprintf('with an amplitude threshold of the mean plus %s times the standard deviation of the signal', k);
            end
            switch lower(MethodsWriter.getf(p, 'polarity', 'positive'))
                case 'negative', pol = 'negative-going';
                case 'both',     pol = 'positive- and negative-going';
                otherwise,       pol = 'positive-going';
            end
            parts{end+1} = sprintf('%s %s (%s peaks; at least 0.3 ms between detections).', t, thr, pol);
            a = MethodsWriter.getf(p, 'alignWinMs', NaN);
            if MethodsWriter.isNum(a)
                parts{end+1} = sprintf(['Waveforms (&plusmn;%s ms around the peak) were re-centred on their extremum, ' ...
                    'searched from %s ms before to %s ms after the detection, and duplicate detections were removed.'], ...
                    MethodsWriter.num(a), MethodsWriter.num(0.5 * a), MethodsWriter.num(a));
            end
            nc = MethodsWriter.num(MethodsWriter.getf(p, 'numComponents', NaN));
            switch lower(MethodsWriter.getf(p, 'featureMethod', 'PCA'))
                case 'ica',      feat = sprintf('%s independent components (FastICA) of the waveforms', nc);
                case 'waveform', feat = 'the waveform samples';
                case 'wavelet',  feat = 'wavelet coefficients of the waveforms';
                case 't-sne',    feat = sprintf('a %s-dimensional t-SNE embedding of the waveforms', nc);
                otherwise,       feat = sprintf('the first %s principal components of the waveforms', nc);
            end
            if logical(MethodsWriter.getf(p, 'normalize', 0)), feat = [feat ', z-scored']; end
            minN = MethodsWriter.num(MethodsWriter.getf(p, 'minSpikesPerCluster', NaN));
            switch lower(MethodsWriter.getf(p, 'clusterMethod', 'K-means'))
                case 'gmm'
                    cl = sprintf(['Gaussian mixture models with 2&ndash;10 components, keeping the solution with the highest ' ...
                        'mean silhouette value ({{rousseeuw1987}}) among those in which every cluster had at least %s spikes'], minN);
                case 'dbscan'
                    ep = MethodsWriter.getf(p, 'dbscanEpsilon', NaN);
                    if MethodsWriter.isNum(ep)
                        cl = sprintf('DBSCAN ({{ester1996}}; &epsilon; = %s, at least %s spikes per cluster)', MethodsWriter.num(ep), minN);
                    else
                        cl = sprintf('DBSCAN ({{ester1996}}; &epsilon; chosen automatically, at least %s spikes per cluster)', minN);
                    end
                otherwise
                    cl = sprintf(['k-means (5 replicates) for 2&ndash;10 clusters, keeping the solution with the highest mean ' ...
                        'silhouette value ({{rousseeuw1987}}) among those in which every cluster had at least %s spikes'], minN);
            end
            parts{end+1} = sprintf('Features were %s, and spikes were clustered with %s.', feat, cl);
            if logical(MethodsWriter.getf(p, 'enableDriftCorrection', 0))
                if strcmpi(MethodsWriter.getf(p, 'driftMethod', ''), 'Time Binning')
                    parts{end+1} = sprintf(['To follow slow waveform drift, clustering was done in time bins of %s s ' ...
                        'and the clusters of consecutive bins were matched.'], MethodsWriter.num(p.driftBinWidth));
                else
                    parts{end+1} = 'Slow waveform drift was handled by dynamic clustering over time.';
                end
            end
            if logical(MethodsWriter.getf(p, 'autoMerge', 0))
                parts{end+1} = sprintf(['Over-split clusters whose mean waveforms correlated with r of at least %s ' ...
                    'and whose peak-to-peak amplitude ratio was at least %s were merged.'], ...
                    MethodsWriter.num(p.mergeThreshold), MethodsWriter.num(p.mergeMinAmpRatio));
            end
            parts{end+1} = sprintf(['Clusters were rejected when their signal-to-noise ratio (peak-to-peak amplitude ' ...
                'divided by twice the baseline SD) was below 2 or when more than 2%% of their inter-spike intervals ' ...
                'were shorter than the refractory period (%s ms).'], MethodsWriter.num(MethodsWriter.getf(p, 'refractoryMs', 1)));
            edits = MethodsWriter.getf(s, 'results.clusterEdits', {});
            if iscell(edits) && ~isempty(edits)
                parts{end+1} = sprintf('Clusters were then curated by hand (%s).', ...
                    MethodsWriter.plural(numel(edits), 'merge or split operation'));
            end
            qc = MethodsWriter.getf(s, 'results.clusterQC', []);
            if isstruct(qc) && isfield(qc, 'id')
                ids = [qc.id];
                rej = false(size(ids));
                if isfield(qc, 'rejected'), rej = logical([qc.rejected]); end
                nSp = numel(MethodsWriter.getf(res, 'spikeTimes', []));
                t = sprintf('This yielded %s', MethodsWriter.plural(sum(ids > 0 & ~rej), 'unit'));
                if any(rej & ids > 0)
                    t = sprintf('%s (%s rejected)', t, MethodsWriter.plural(sum(rej & ids > 0), 'further cluster'));
                end
                if nSp > 0, t = sprintf('%s from %d detected spikes', t, nSp); end
                parts{end+1} = [t '.'];
            end
            paras = {strjoin(parts, ' ')};
        end

        %% roiAnalysis - Stack, motion correction, preprocessing, ROIs, measure
        function paras = roiAnalysis(s)
            tok = MethodsWriter.summaryTokens(s, 'Stack: (\d+) x (\d+) px, (\d+) frames');
            parts = {};
            t = 'Image stacks';
            if numel(tok) == 3
                t = sprintf('%s (%s &times; %s pixels, %s frames)', t, tok{1}, tok{2}, tok{3});
            end
            parts{end+1} = [t ' were acquired [please add: imaging modality, indicator, ' ...
                'objective, pixel size in &mu;m and frame rate] and analysed as follows.'];
            pre = MethodsWriter.getf(s, 'settings.preprocess', struct());
            if logical(MethodsWriter.getf(pre, 'motionCorrection', false))
                t = ['Rigid (translation-only) motion correction was applied to every frame by FFT phase ' ...
                    'correlation with the mean image (Gaussian-weighted cross-power spectrum, sub-pixel refinement of ' ...
                    'the correlation peak, reference re-estimated from the registered mean in 2 iterations)'];
                sh = MethodsWriter.getf(s, 'results.shifts', []);
                if isnumeric(sh) && ~isempty(sh) && all(isfinite(sh(:)))
                    t = sprintf('%s; the largest shift was %s pixels', t, MethodsWriter.num(max(abs(sh(:)))));
                end
                parts{end+1} = [t '.'];
            end
            steps = {};
            if logical(MethodsWriter.getf(pre, 'bw256', false)), steps{end+1} = 'converted to 8-bit grayscale (256 levels)'; end
            if logical(MethodsWriter.getf(pre, 'smooth', false))
                steps{end+1} = 'smoothed with a Gaussian filter (&sigma; = 2 pixels)';
            end
            if logical(MethodsWriter.getf(pre, 'normalize', false))
                steps{end+1} = 'normalised frame by frame to the range 0&ndash;1 (each frame''s minimum and maximum)';
            end
            if ~isempty(steps), parts{end+1} = sprintf('Frames were then %s.', MethodsWriter.listText(steps)); end
            method = MethodsWriter.getf(s, 'results.method', '');
            if isempty(method), method = MethodsWriter.getf(s, 'settings.method', ''); end
            isLine = any(strcmp(method, {'Kymograph', 'Vessel diameter'}));
            if ~isLine
                src = cellstr(MethodsWriter.getf(s, 'settings.roiSources', {}));
                src = src(~cellfun(@isempty, src));
                if ~isempty(src)
                    kinds = {};
                    nDr = sum(ismember(src, {'drawn', 'added'}));
                    nDet = sum(strcmp(src, 'detected'));
                    nFile = sum(ismember(src, {'file', 'mask'}));
                    if nDr > 0, kinds{end+1} = sprintf('%d drawn by hand', nDr); end
                    if nFile > 0, kinds{end+1} = sprintf('%d loaded from a mask file', nFile); end
                    if nDet > 0, kinds{end+1} = sprintf('%d detected automatically', nDet); end
                    if numel(src) == 1, roiW = 'one region of interest (ROI'; else, roiW = sprintf('%d regions of interest (ROIs', numel(src)); end
                    t = sprintf('Measurements were made in %s; %s).', roiW, MethodsWriter.listText(kinds));
                    if nDet > 0
                        thr = MethodsWriter.getf(s, 'settings.detectThresholdUsed', NaN);
                        t = [t ' Cells were detected in the local correlation image (mean Pearson correlation of each ' ...
                            'pixel''s time series with its 8 neighbours) as compact, non-elongated connected components'];
                        if MethodsWriter.isNum(thr)
                            t = sprintf('%s above a correlation of %s.', t, MethodsWriter.num(thr));
                        else
                            t = [t ' above an automatic threshold (median plus a multiple of the robust SD of the image).'];
                        end
                    end
                    parts{end+1} = t;
                end
            end
            nb = MethodsWriter.getf(s, 'settings.dffBaselineFrames', NaN);
            ln = MethodsWriter.lineText(MethodsWriter.getf(s, 'settings.line', []));
            switch method
                case 'Brightness'
                    parts{end+1} = 'The mean pixel intensity within each ROI was measured in every frame.';
                case 'Movement'
                    parts{end+1} = ['Movement within each ROI was quantified as the mean absolute intensity ' ...
                        'difference between consecutive frames.'];
                case 'Both'
                    parts{end+1} = ['The mean pixel intensity within each ROI was measured in every frame, and ' ...
                        'movement was quantified as the mean absolute intensity difference between consecutive frames.'];
                case 'Speed (flow)'
                    parts{end+1} = ['As a flow-speed proxy, the mean absolute intensity difference between ' ...
                        'consecutive frames was computed within each ROI.'];
                case 'Kymograph'
                    parts{end+1} = sprintf('A kymograph (intensity along a line versus time) was extracted along %s.', ln);
                case 'Vessel diameter'
                    t = sprintf(['Vessel diameter was measured in every frame as the full width at half depth of the ' ...
                        'intensity profile along %s, perpendicular to the vessel, with the wall positions interpolated ' ...
                        'linearly between samples.'], ln);
                    if logical(MethodsWriter.getf(s, 'settings.robustDiameter', false))
                        t = [t ' To reject red blood cells crossing the line, the background level was taken from the ' ...
                            'two ends of the line (15 percent of the samples at each end) and the vessel core from the 2nd ' ...
                            'percentile of the profile, both as running medians over 7 frames; the walls were the ' ...
                            'outermost crossings of the half level, and remaining outliers were replaced by a Hampel ' ...
                            'filter over time (7 frames, 3 robust SDs).'];
                    end
                    parts{end+1} = t;
                otherwise
                    if ~isempty(method) && ~isempty(strfind(method, 'F/F'))
                        if MethodsWriter.isNum(nb)
                            parts{end+1} = sprintf(['Fluorescence changes were expressed as &Delta;F/F = (F &minus; F0)/F0, with F the ' ...
                                'mean intensity within the ROI and F0 the mean of the first %s frames.'], MethodsWriter.num(nb));
                        else
                            parts{end+1} = ['Fluorescence changes were expressed as &Delta;F/F = (F &minus; F0)/F0, with F the mean ' ...
                                'intensity within the ROI [please add: baseline F0].'];
                        end
                    end
            end
            if isLine
                parts{end+1} = '[please add: pixel size to convert pixels to micrometres.]';
            end
            paras = {strjoin(parts, ' ')};
        end

        %% histology - Images, pixel size, alignment, cell counting, markers, regions
        function paras = histology(s)
            tok = MethodsWriter.summaryTokens(s, '(\d+) image\(s\), (\d+) x (\d+) px, (\d+) channel');
            names = cellstr(MethodsWriter.getf(s, 'settings.channelNames', {}));
            names = names(~cellfun(@isempty, names));
            px = MethodsWriter.getf(s, 'settings.pixelSizeUm', NaN);
            parts = {};
            if numel(tok) == 4
                t = sprintf('%s (%s &times; %s pixels, %s', MethodsWriter.capital(MethodsWriter.plural( ...
                    str2double(tok{1}), 'image')), tok{2}, tok{3}, MethodsWriter.plural(str2double(tok{4}), 'channel'));
                if ~isempty(names), t = sprintf('%s: %s', t, MethodsWriter.listText(names)); end
                t = [t ')'];
            else
                t = 'Images';
            end
            t = [t ' of [please add: sections or cultures, staining and microscope]'];
            if MethodsWriter.isNum(px)
                if logical(MethodsWriter.getf(s, 'settings.pixelSizeFromFile', false))
                    t = sprintf('%s were acquired at %s &mu;m per pixel (read from the image files)', t, MethodsWriter.num(px));
                else
                    t = sprintf('%s were acquired at %s &mu;m per pixel', t, MethodsWriter.num(px));
                end
            else
                t = [t ' were acquired [please add: pixel size in &mu;m]'];
            end
            parts{end+1} = [t ' and analysed as follows.'];
            % Alignment
            al = {};
            if logical(MethodsWriter.getf(s, 'settings.channelsAligned', false))
                al{end+1} = ['every channel was shifted onto the first by the peak of their FFT cross-correlation ' ...
                    '(chromatic shift, sub-pixel peak fit)'];
            end
            switch MethodsWriter.getf(s, 'settings.alignedMethod', 'none')
                case 'shift'
                    t = ['images 2 onwards were aligned to the first by translation, estimated by FFT phase ' ...
                        'correlation of the background-subtracted'];
                    ch = MethodsWriter.getf(s, 'settings.alignChannel', NaN);
                    if MethodsWriter.isNum(ch) && ch <= numel(names)
                        t = sprintf('%s %s channel', t, names{ch});
                    else
                        t = [t ' reference channel'];
                    end
                    sh = MethodsWriter.getf(s, 'results.shifts', []);
                    if isnumeric(sh) && ~isempty(sh) && all(isfinite(sh(:)))
                        t = sprintf('%s (largest shift %s pixels)', t, MethodsWriter.num(round(max(hypot(sh(:, 1), sh(:, 2))) * 10) / 10));
                    end
                    al{end+1} = t;
                case 'landmarks'
                    t = ['images 2 onwards were aligned to the first by an affine transform fitted by least squares ' ...
                        'to at least three pairs of matching landmarks placed by hand, with bilinear interpolation'];
                    e = MethodsWriter.getf(s, 'results.landmarkRms', []);
                    e = e(isfinite(e));
                    if isnumeric(e) && ~isempty(e)
                        t = sprintf('%s (root-mean-square landmark error at most %s pixels)', t, MethodsWriter.num(round(max(e) * 10) / 10));
                    end
                    al{end+1} = t;
            end
            if ~isempty(al), parts{end+1} = [MethodsWriter.capital(MethodsWriter.listText(al)) '.']; end
            % Counting
            o = MethodsWriter.getf(s, 'settings.count', struct());
            if isempty(MethodsWriter.getf(s, 'results.counts', {}))
                paras = {strjoin(parts, ' ')};
                return;
            end
            ch = MethodsWriter.getf(o, 'channel', 1);
            if MethodsWriter.isNum(ch) && ch <= numel(names), chName = sprintf('the %s channel', names{ch}); else, chName = 'the nuclear channel'; end
            t = sprintf(['Cells were counted in %s. Uneven illumination was removed by subtracting a background ' ...
                'estimated by a grey-level opening (minimum then maximum filter) with a square of side twice %s &mu;m; ' ...
                'the image was smoothed with a Gaussian filter and thresholded'], chName, ...
                MethodsWriter.num(MethodsWriter.getf(o, 'backgroundRadiusUm', NaN)));
            thr = MethodsWriter.getf(o, 'threshold', 0);
            if MethodsWriter.isNum(thr) && thr > 0
                t = sprintf('%s at %s (intensity above background)', t, MethodsWriter.num(thr));
            else
                t = [t ' automatically with Otsu''s method ({{otsu1979}}), but never below three robust standard ' ...
                    'deviations of the background noise'];
            end
            t = [t '. Holes were filled and 8-connected pixels formed objects.'];
            if logical(MethodsWriter.getf(o, 'split', true))
                t = [t ' Touching cells were separated at peaks of the distance-to-edge map: two peaks were kept as ' ...
                    'separate cells when the object narrowed between them to less than 0.85 times the smaller peak, ' ...
                    'and pixels were assigned to the nearest peak weighted by its radius.'];
            end
            t = sprintf(['%s Objects smaller than %s &mu;m&sup2;, larger than %s &mu;m&sup2; or with a length-to-width ' ...
                'ratio above %s were not counted.'], t, MethodsWriter.num(MethodsWriter.getf(o, 'minAreaUm2', NaN)), ...
                MethodsWriter.num(MethodsWriter.getf(o, 'maxAreaUm2', NaN)), MethodsWriter.num(MethodsWriter.getf(o, 'maxElongation', NaN)));
            parts{end+1} = t;
            % Markers
            if numel(names) > 1
                mt = MethodsWriter.getf(o, 'markerThreshold', 0);
                if MethodsWriter.isNum(mt) && mt > 0
                    thrText = sprintf('a threshold of %s above background', MethodsWriter.num(mt));
                else
                    thrText = 'the automatic threshold of that channel';
                end
                parts{end+1} = sprintf(['A cell was scored positive for a marker when at least %s%% of its pixels ' ...
                    'exceeded %s after the same background subtraction.'], ...
                    MethodsWriter.num(MethodsWriter.getf(o, 'minFractionPct', NaN)), thrText);
            end
            % Regions
            rg = MethodsWriter.getf(s, 'settings.regions', struct([]));
            if isstruct(rg) && ~isempty(rg)
                parts{end+1} = sprintf(['Cells were assigned to %s drawn by hand on the first image (%s) by their ' ...
                    'centroid; densities are cells per mm&sup2; of region area within the image.'], ...
                    MethodsWriter.plural(numel(rg), 'region'), MethodsWriter.listText({rg.name}));
            else
                parts{end+1} = 'Densities are cells per mm&sup2; of image area.';
            end
            paras = {strjoin(parts, ' ')};
        end

        %% signalCharacterization - Response features and group statistics
        function paras = signalCharacterization(s)
            paras = {};
            sg = MethodsWriter.getf(s, 'settings.single', struct());
            if logical(MethodsWriter.getf(sg, 'extracted', false))
                n = MethodsWriter.fromSummary(s, 'Single file: (\d+) series');
                dt = strtrim(strtok(char(MethodsWriter.getf(sg, 'dataType', '')), '('));
                t = 'Response features were extracted from each';
                if MethodsWriter.isNum(n), t = sprintf('%s of %s', t, MethodsWriter.num(n)); end
                if ~isempty(dt), t = sprintf('%s series (%s)', t, dt); else, t = [t ' series']; end
                t = [t MethodsWriter.baselineClause(MethodsWriter.getf(sg, 't0', NaN), MethodsWriter.getf(sg, 'baseline', []), ...
                    MethodsWriter.getf(sg, 'direction', ''))];
                feats = cellstr(MethodsWriter.getf(sg, 'features', {}));
                defs = cellfun(@(x) MethodsWriter.featureDefinition(x), feats, 'UniformOutput', false);
                defs = defs(~cellfun(@isempty, defs));
                if ~isempty(defs), t = sprintf('%s The features were %s.', t, MethodsWriter.listText(defs)); end
                paras{end+1} = t;
            end
            gt = MethodsWriter.getf(s, 'results.groupTest', []);
            gs = MethodsWriter.getf(s, 'settings.groups', struct());
            if isstruct(gt) && isfield(gt, 'main') && isstruct(gt.main)
                paras{end+1} = MethodsWriter.groupText(gt, gs);
            end
        end

        %% eegLayout - Where the electrode positions came from (confirmed layouts only)
        % s.settings.layout as the EEG window saves it: channels per source
        % (counts.file / template / positionsFile / edited / none), the
        % positions file and its format, the frame, the renamed channels
        % ({channel, as}) and the summary line (EEGLayout). Nothing for
        % sessions without a layout, a layout not confirmed or one without
        % any position. The counts are read from the summary when missing.
        function parts = eegLayout(s)
            parts = {};
            ly = MethodsWriter.getf(s, 'settings.layout', struct());
            ok = MethodsWriter.getf(ly, 'confirmed', false);
            if ~MethodsWriter.isNum(ok) || ~logical(ok), return; end
            sm = char(MethodsWriter.getf(ly, 'summary', ''));
            keys = {'file', 'template', 'positionsFile', 'edited'};
            words = {'from the file', 'by name', 'from the positions file', 'placed by hand'};
            n = struct();
            for k = 1:numel(keys)
                v = MethodsWriter.getf(ly, ['counts.' keys{k}], NaN);
                if ~MethodsWriter.isNum(v)
                    tok = regexp(sm, ['(\d+) ' words{k}], 'tokens', 'once');
                    v = 0;
                    if ~isempty(tok), v = str2double(tok{1}); end
                end
                n.(keys{k}) = double(v);
            end
            kind = lower(char(MethodsWriter.getf(ly, 'kind', 'scalp')));
            if strcmp(kind, 'none') || n.file + n.template + n.positionsFile + n.edited == 0, return; end
            skull = strcmp(kind, 'skull');
            cite = '({{oostenveld2001}}; idealized positions on a sphere, {{jurcak2007}})';
            pfName = regexprep(char(MethodsWriter.getf(ly, 'positionsFile', '')), '^.*[\\/]', '');
            pf = pfName;
            if isempty(pf), pf = 'a positions file'; end
            fmt = char(MethodsWriter.getf(ly, 'format', ''));
            if ~isempty(fmt), pf = sprintf('%s (%s)', pf, fmt); end

            % ---- Sources: one sentence, with the channels per source when mixed ----
            src = {n.file, 'from the recording files', 'were taken from the recording files'
                n.positionsFile, ['from ' pf], ['were read from ' pf]
                n.template, ['from their names on the 10-5 system ' cite], ...
                ['were assigned from the channel names on the 10-5 system ' cite]};
            use = find([src{:, 1}] > 0);
            byHand = '';
            if ~skull && n.template == 0, byHand = [' on the 10-5 system ' cite]; end
            if isempty(use)
                t = ['Electrode positions were placed by hand' byHand];
            elseif numel(use) == 1 && n.edited == 0
                t = ['Electrode positions ' src{use, 3}];
            else
                each = arrayfun(@(i) sprintf('for %s %s', MethodsWriter.num(src{i, 1}), src{i, 2}), use, ...
                    'UniformOutput', false);
                each{1} = sprintf('for %s %s', MethodsWriter.plural(src{use(1), 1}, 'channel'), src{use(1), 2});
                t = ['Electrode positions were taken ' MethodsWriter.listText(each)];
                if n.edited > 0
                    verb = 'were';
                    if n.edited == 1, verb = 'was'; end
                    t = sprintf('%s; %s %s placed by hand%s', t, MethodsWriter.plural(n.edited, 'channel'), verb, byHand);
                end
            end
            bregma = 'in mm from bregma (anterior-posterior, medial-lateral)';
            if skull && numel(use) + (n.edited > 0) == 1
                parts{end+1} = sprintf('%s and given %s.', t, bregma);
            elseif skull
                parts{end+1} = sprintf('%s. All electrode positions were given %s.', t, bregma);
            else
                parts{end+1} = [t '.'];
            end

            % ---- 10-5 positions put on the head of the measured ones (EEGLayout.templateScale) ----
            frAll = char(MethodsWriter.getf(ly, 'frame', ''));
            tok = regexp(frAll, 'the 10-5 positions on this head: angles from the vertex x ([\d.]+)', 'tokens', 'once');
            if ~skull && ~isempty(tok) && (n.file > 0 || n.positionsFile > 0)
                parts{end+1} = sprintf(['The 10-5 positions were put on the head of the measured positions by ' ...
                    'scaling their angles from the vertex by %s (least-squares fit on the channels that had both).'], tok{1});
            end

            % ---- How the file's coordinates were read, when assumed or turned ----
            fr = regexprep(frAll, ';\s*(the other channels|the 10-5 positions on this head):.*$', '');
            fr = regexprep(strtrim(regexprep(fr, '^positions file(.*?\))?:\s*', '')), '\.$', '');
            if (n.file > 0 || n.positionsFile > 0) && ~isempty(regexp(fr, 'turned|not stated|guessed|assumed', 'once'))
                where = 'the recording files';
                if n.positionsFile > 0 && ~isempty(pfName), where = pfName; end
                parts{end+1} = sprintf('The coordinates in %s were interpreted as follows: %s.', where, fr);
            end

            % ---- Old 10-20 names (T3 -> T7 ...) and channels without a position ----
            rn = MethodsWriter.getf(ly, 'renamed', cell(0, 2));
            if iscell(rn) && size(rn, 2) == 2
                rn = cellfun(@char, rn, 'UniformOutput', false);
                old = ~cellfun(@isempty, regexpi(rn(:, 1), '(^|[^a-z0-9])T[3-6]([^a-z0-9]|$)', 'once')) & ...
                    ismember(upper(rn(:, 2)), {'T7', 'T8', 'P7', 'P8'});
                from = rn(old, 1)';
                to = rn(old, 2)';
                if numel(from) == 1
                    parts{end+1} = sprintf('Channel %s was treated as %s (old 10-20 name).', from{1}, to{1});
                elseif numel(from) > 1
                    parts{end+1} = sprintf('Channels %s were treated as %s (old 10-20 names).', ...
                        MethodsWriter.listText(from), MethodsWriter.listText(to));
                end
            end
            miss = cellstr(MethodsWriter.getf(ly, 'missing', {}));
            if isempty(miss)
                tok = regexp(sm, 'no position: (.*)\.\s*$', 'tokens', 'once');
                if ~isempty(tok), miss = strsplit(tok{1}, ', '); end
            end
            others = 0;
            if ~isempty(miss)
                tok = regexp(miss{end}, '^(\d+) more$', 'tokens', 'once');
                if ~isempty(tok), others = str2double(tok{1}); miss(end) = []; end
            end
            nNone = MethodsWriter.getf(ly, 'counts.none', 0);
            if others > 0
                parts{end+1} = sprintf('Channels %s and %s others had no position.', strjoin(miss, ', '), ...
                    MethodsWriter.num(others));
            elseif numel(miss) == 1
                parts{end+1} = sprintf('Channel %s had no position.', miss{1});
            elseif numel(miss) > 1
                parts{end+1} = sprintf('Channels %s had no position.', MethodsWriter.listText(miss));
            elseif MethodsWriter.isNum(nNone) && nNone > 0
                parts{end+1} = sprintf('%s had no position.', MethodsWriter.capital(MethodsWriter.plural(nNone, 'channel')));
            end
        end

        %% eegCleaning - Bad channels, filters and re-reference applied in the EEG window
        function parts = eegCleaning(s)
            parts = {};
            cl = MethodsWriter.getf(s, 'settings.cleaning', struct());
            if ~isstruct(cl) || ~logical(MethodsWriter.getf(cl, 'applied', false)), return; end
            bad = MethodsWriter.getf(cl, 'bad', {});
            if ~iscell(bad), bad = {}; end
            nBad = cellfun(@(b) numel(cellstr(b)) * ~isempty(b), bad);
            mode = lower(char(MethodsWriter.getf(cl, 'referenceMode', 'as recorded')));
            if any(nBad > 0)
                every = cellfun(@(b) cellstr(b), bad(nBad > 0), 'UniformOutput', false);
                every = unique([every{:}], 'stable');
                what = 'the trial rejection and the ERPs';
                if strcmp(mode, 'average'), what = ['the average reference, ' what]; end
                parts{end+1} = sprintf(['Channels with flat or excessively noisy signals were marked as bad ' ...
                    '(%s; %s of %s) and left out of %s.'], ...
                    MethodsWriter.listText(every), MethodsWriter.plural(sum(nBad > 0), 'participant'), ...
                    MethodsWriter.num(numel(bad)), what);
            end
            ft = cellstr(MethodsWriter.getf(cl, 'filterText', {}));
            ft = ft(~cellfun(@isempty, ft));
            if ~isempty(ft)
                parts{end+1} = sprintf(['The recordings were filtered with zero-phase windowed-sinc FIR filters ' ...
                    'designed following published recommendations ({{widmann2015}}): %s.'], ...
                    strjoin(cellfun(@(f) regexprep(strtrim(f), '\.$', ''), ft, 'UniformOutput', false), '; '));
            end
            if ~any(strcmp(mode, {'as recorded', ''}))
                ref = char(MethodsWriter.getf(s, 'settings.reference', ''));
                parts{end+1} = sprintf('They were re-referenced offline to the %s.', ref);
            end
        end

        %% eegRejection - Trials rejected by amplitude, per condition over the participants
        function t = eegRejection(rj, trials)
            rules = {};
            pp = MethodsWriter.getf(trials, 'peakToPeak', []);
            ab = MethodsWriter.getf(trials, 'absolute', []);
            if MethodsWriter.isNum(pp) && pp > 0
                rules{end+1} = sprintf('a peak-to-peak amplitude above %s microvolts', MethodsWriter.num(pp));
            end
            if MethodsWriter.isNum(ab) && ab > 0
                rules{end+1} = sprintf('an absolute amplitude above %s microvolts', MethodsWriter.num(ab));
            end
            conds = {};
            for p = 1:numel(rj), conds = [conds, cellstr(rj(p).conditions)]; end %#ok<AGROW>
            conds = unique(conds, 'stable');
            per = cell(1, numel(conds));
            for c = 1:numel(conds)
                b = 0; a = 0;
                for p = 1:numel(rj)
                    k = find(strcmp(rj(p).conditions, conds{c}), 1);
                    if ~isempty(k), b = b + rj(p).before(k); a = a + rj(p).after(k); end
                end
                per{c} = sprintf('%s %s of %s', conds{c}, MethodsWriter.num(b - a), MethodsWriter.num(b));
            end
            n = [rj.total] - [rj.kept];
            span = MethodsWriter.num(min(n));
            if max(n) > min(n), span = sprintf('%s to %s', span, MethodsWriter.num(max(n))); end
            t = sprintf('Epochs with %s on any good channel were rejected (%s; %s per participant).', ...
                strjoin(rules, ' or '), MethodsWriter.listText(per), span);
            if isempty(rules)
                t = sprintf('Epochs were rejected by amplitude (%s).', MethodsWriter.listText(per));
            end
        end

        %% eegAnalysis - EEG files, earlier processing, epochs, ERPs, measure, statistics
        function paras = eegAnalysis(s)
            st = MethodsWriter.getf(s, 'settings', struct());
            names = cellstr(MethodsWriter.getf(st, 'participants', {}));
            nP = numel(names);
            if nP == 0, paras = {}; return; end
            src = cellstr(MethodsWriter.getf(st, 'sources', {}));
            src = unique(src(~cellfun(@isempty, src)));
            tools = {};
            if any(strcmp(src, 'EEGLAB')), tools{end+1} = 'EEGLAB ({{delorme2004}})'; end
            if any(strcmp(src, 'FieldTrip')), tools{end+1} = 'FieldTrip ({{oostenveld2011}})'; end
            t = sprintf(['EEG was recorded from %s [please add: recording system, electrodes and montage, ' ...
                'sampling and online filters]'], MethodsWriter.plural(nP, 'participant'));
            cleanedHere = logical(MethodsWriter.getf(st, 'cleaning.applied', false));
            if isempty(tools) && cleanedHere
                t = [t '.'];        % the cleaning follows (eegCleaning)
            elseif isempty(tools)
                t = [t ' and cleaned before the analysis [please add: cleaning steps and software].'];
            else
                t = sprintf('%s and cleaned in %s before the analysis.', t, MethodsWriter.listText(tools));
            end
            parts = {t};
            nCh = MethodsWriter.getf(st, 'nChannels', NaN);
            fs = MethodsWriter.getf(st, 'fs', NaN);
            ref = char(MethodsWriter.getf(st, 'recordedReference', MethodsWriter.getf(st, 'reference', '')));
            if MethodsWriter.isNum(nCh) && MethodsWriter.isNum(fs)
                t = sprintf('The data comprised %s at %s Hz', MethodsWriter.plural(nCh, 'channel'), MethodsWriter.num(fs));
                if ~isempty(ref) && ~strcmpi(ref, 'unknown'), t = sprintf('%s, referenced to the %s', t, ref); end
                parts{end+1} = [t '.'];
            end
            parts = [parts, MethodsWriter.eegLayout(s)];
            hist = cellstr(MethodsWriter.getf(st, 'history', {}));
            hist = hist(~cellfun(@isempty, hist));
            if ~isempty(hist)
                parts{end+1} = sprintf('The data files recorded these earlier processing steps: %s', ...
                    strjoin(cellfun(@(h) regexprep(strtrim(h), '\.$', ''), hist, 'UniformOutput', false), '; '));
                parts{end} = [parts{end} '.'];
            end
            parts = [parts, MethodsWriter.eegCleaning(s)];
            tw = MethodsWriter.getf(st, 'trialWindow', []);
            if isnumeric(tw) && numel(tw) == 2
                ren = MethodsWriter.getf(st, 'trials.rename', cell(0, 2));
                ev = '';
                if iscell(ren) && size(ren, 2) == 2 && ~isempty(ren)
                    ev = sprintf(' (%s)', MethodsWriter.listText(cellfun(@(a, b) sprintf('%s = %s', ...
                        regexprep(strtrim(a), '\s+', ' '), b), ren(:, 1)', ren(:, 2)', 'UniformOutput', false)));
                end
                parts{end+1} = sprintf(['The continuous recordings were cut into epochs from %s to %s ms around ' ...
                    'each event%s; events too close to the start or end of a recording were left out.'], ...
                    MethodsWriter.num(tw(1) * 1000), MethodsWriter.num(tw(2) * 1000), ev);
            end
            rj = MethodsWriter.getf(s, 'results.rejection', []);
            if isstruct(rj) && ~isempty(rj) && isfield(rj, 'sentence')
                parts{end+1} = MethodsWriter.eegRejection(rj, MethodsWriter.getf(st, 'trials', struct()));
            end
            paras = {strjoin(parts, ' ')};
            tfParas = MethodsWriter.eegTimeFrequency(s, nP);
            if ~logical(MethodsWriter.getf(st, 'erpsShown', false)), paras = [paras, tfParas]; return; end

            conds = cellstr(MethodsWriter.getf(s, 'results.conditions', {}));
            trials = MethodsWriter.getf(s, 'results.trials', []);
            cl = conds;
            if numel(trials) == numel(conds)
                cl = arrayfun(@(k) sprintf('%s (%s)', conds{k}, MethodsWriter.plural(trials(k), 'trial')), ...
                    1:numel(conds), 'UniformOutput', false);
            end
            t = 'Event-related potentials (ERPs) were computed for each participant as the mean of the trials of each condition';
            if ~isempty(cl), t = sprintf('%s (%s in total)', t, MethodsWriter.listText(cl)); end
            bl = MethodsWriter.getf(st, 'baseline', []);
            if logical(MethodsWriter.getf(st, 'baselineOn', false)) && isnumeric(bl) && numel(bl) == 2
                t = sprintf(['%s, after subtracting from every trial and channel its mean from %s to %s ms ' ...
                    '(baseline correction)'], t, MethodsWriter.num(bl(1) * 1000), MethodsWriter.num(bl(2) * 1000));
            else
                t = [t ', without further baseline correction'];
            end
            parts = {[t '.']};
            if nP > 1
                parts{end+1} = 'Grand averages were the mean of the participants'' ERPs, each participant weighted equally.';
            end
            sm = MethodsWriter.getf(st, 'scalpMaps', []);
            if isstruct(sm) && isscalar(sm) && isfield(sm, 'window') && numel(sm.window) == 2
                w = sm.window * 1000;
                if abs(w(2) - w(1)) < 1e-6
                    when = sprintf('the voltage at %s ms', MethodsWriter.num(w(1)));
                else
                    when = sprintf('the mean voltage from %s to %s ms', MethodsWriter.num(w(1)), MethodsWriter.num(w(2)));
                end
                if strcmp(MethodsWriter.getf(s, 'results.scalpMaps.kind', 'scalp'), 'skull')
                    parts{end+1} = sprintf(['Maps of %s were interpolated between the skull electrodes with a ' ...
                        'thin-plate spline ({{duchon1977}}) and drawn only within their outline.'], when);
                else
                    parts{end+1} = sprintf(['Scalp maps of %s were interpolated over the head with spherical ' ...
                        'splines ({{perrin1989}}; order m = 4, 50 Legendre terms, no regularization).'], when);
                end
            end
            m = MethodsWriter.getf(st, 'measure', struct());
            mtxt = '';
            if logical(MethodsWriter.getf(st, 'measured', false)) && isfield(m, 'Window')
                w = m.Window * 1000;
                ch = cellstr(MethodsWriter.getf(m, 'Channels', {}));
                ch = ch(~cellfun(@isempty, ch));
                if isempty(ch)
                    where = 'averaged over all channels';
                elseif numel(ch) == 1
                    where = sprintf('at %s', ch{1});
                else
                    where = sprintf('averaged over %s', MethodsWriter.listText(ch));
                end
                if strcmpi(MethodsWriter.getf(m, 'Measure', 'mean'), 'peak')
                    pol = lower(MethodsWriter.getf(m, 'Polarity', 'positive'));
                    mtxt = sprintf('%s peak amplitude from %s to %s ms %s', pol, MethodsWriter.num(w(1)), ...
                        MethodsWriter.num(w(2)), where);
                    parts{end+1} = sprintf(['In each participant''s ERP, the %s was measured as the most %s value ' ...
                        'in the window, with its latency; peaks falling on the edge of the window were flagged.'], ...
                        mtxt, pol);
                else
                    mtxt = sprintf('mean amplitude from %s to %s ms %s', MethodsWriter.num(w(1)), ...
                        MethodsWriter.num(w(2)), where);
                    parts{end+1} = sprintf('In each participant''s ERP, the %s was measured.', mtxt);
                end
            end
            paras{end+1} = strjoin(parts, ' ');
            gt = MethodsWriter.getf(s, 'results.groupTest', []);
            if isstruct(gt) && isfield(gt, 'main') && isstruct(gt.main) && ~isempty(mtxt)
                gs = struct('featureText', mtxt, 'subjectText', ...
                    'one value per participant and condition, with participants matched across conditions');
                paras{end+1} = MethodsWriter.groupText(gt, gs);
            end
            paras = [paras, tfParas];
        end

        %% eegTimeFrequency - Morlet ERSP, ITPC and band power per condition (EEG window, step 7)
        function paras = eegTimeFrequency(s, nP)
            paras = {};
            r = MethodsWriter.getf(s, 'results.timeFrequency', []);
            if ~logical(MethodsWriter.getf(s, 'settings.tfShown', false)) || ~isstruct(r) || ~isfield(r, 'freqs') ...
                    || isempty(r.freqs)
                return;
            end
            f = r.freqs;
            nc = unique(r.cycles);
            if isscalar(nc), cyc = sprintf('%s cycles', MethodsWriter.num(nc));
            else, cyc = sprintf('%s&ndash;%s cycles', MethodsWriter.num(min(nc)), MethodsWriter.num(max(nc))); end
            ch = cellstr(r.channels);
            if isscalar(ch), where = sprintf('at %s', ch{1});
            else, where = sprintf('at %s (power and phase locking averaged over channels)', MethodsWriter.listText(ch)); end
            t = sprintf(['Time&ndash;frequency representations were computed for every trial %s from complex Morlet ' ...
                'wavelet transforms (%s; %d frequencies from %s to %s Hz; wavelets truncated at &plusmn;3 standard ' ...
                'deviations of their Gaussian envelope and normalised to unit energy; the mean of each trial removed ' ...
                'first). Values were kept only where the whole wavelet lay within the trial'], where, cyc, numel(f), ...
                MethodsWriter.num(f(1)), MethodsWriter.num(f(end)));
            lv = MethodsWriter.getf(r, 'lowestWithValues', NaN);
            if MethodsWriter.isNum(lv) && lv > f(1)
                t = sprintf('%s (from %s Hz up for these trials)', t, MethodsWriter.num(lv));
            end
            b = r.baseline * 1000;
            t = sprintf(['%s. Event-related spectral perturbation (ERSP; {{makeig1993}}) was expressed in dB relative ' ...
                'to the mean power of each condition from %s to %s ms'], t, MethodsWriter.num(b(1)), MethodsWriter.num(b(2)));
            lb = MethodsWriter.getf(r, 'lowestWithBaseline', NaN);
            if MethodsWriter.isNum(lb) && lb > f(1)
                t = sprintf('%s (from %s Hz up, where whole wavelets fitted within that window)', t, MethodsWriter.num(lb));
            end
            bd = r.band;
            t = sprintf(['%s, inter-trial phase coherence (ITPC; {{tallonbaudry1996}}) as the length of the mean unit ' ...
                'phase vector across trials, and %s band power (%s&ndash;%s Hz; the mean wavelet power over its ' ...
                'frequencies) as the percent change of each trial from the mean baseline band power of its condition ' ...
                '({{pfurtscheller1999}}).'], t, lower(char(r.bandName)), MethodsWriter.num(bd(1)), MethodsWriter.num(bd(2)));
            if nP > 1
                t = [t ' Grand averages were the means of the participants'' ERSP (in dB), ITPC and band power, each ' ...
                    'participant weighted equally.'];
            end
            paras = {t};
        end

        %% baselineClause - ", with stimulus onset at t0 = 0 s, ..." sentence ending
        function t = baselineClause(t0, bl, dirn)
            det = {};
            if MethodsWriter.isNum(t0), det{end+1} = sprintf('stimulus onset at t = %s s', MethodsWriter.num(t0)); end
            if isnumeric(bl) && numel(bl) == 2 && all(isfinite(bl))
                det{end+1} = sprintf('the baseline defined as the mean signal from %s', MethodsWriter.secRange(bl(1), bl(2)));
            end
            t = '';
            if ~isempty(det), t = sprintf(', with %s', MethodsWriter.listText(det)); end
            switch lower(char(dirn))
                case 'positive', t = [t '; responses were taken as positive-going (peaks)'];
                case 'negative', t = [t '; responses were taken as negative-going (troughs)'];
                case 'auto'
                    t = [t '; the response direction was set for each trace (negative when the post-onset deflection ' ...
                        'below baseline was larger than above)'];
            end
            t = [t '.'];
        end

        %% featureDefinition - Plain definition of one feature ('' if unknown)
        function d = featureDefinition(name)
            n = regexprep(char(name), '[^A-Za-z0-9 ()]', '');   % drops the en dash of 'Stim-response integral'
            switch n
                case 'Peak latency',      d = 'peak latency (time from onset to the response extremum)';
                case 'Onset delay (50)',  d = 'onset delay (time from onset until the response first reached 50% of its baseline-to-peak amplitude)';
                case 'FWHM',              d = 'full width at half maximum (FWHM) of the response lobe containing the peak';
                case 'AUC positive',      d = 'positive area under the curve (trapezoidal integral of the signal above baseline)';
                case 'AUC negative',      d = 'negative area under the curve (absolute trapezoidal integral of the signal below baseline)';
                case 'Rise time',         d = 'rise time (from 10% to 90% of the baseline-to-peak amplitude)';
                case 'Decay time',        d = 'decay time (from the peak to 50% return towards baseline)';
                case 'Peak amplitude',    d = 'peak amplitude relative to baseline';
                case 'Stimresponse integral', d = 'stimulus-response integral (trapezoidal integral of the response from onset)';
                otherwise,                d = '';
            end
        end

        %% groupText - Group comparison: subjects, test, corrections, effect sizes
        function t = groupText(gt, gs)
            names = cellstr(MethodsWriter.getf(gt, 'groupNames', {}));
            n = [];
            desc = MethodsWriter.getf(gt, 'desc', []);
            if isstruct(desc) && isfield(desc, 'n'), n = [desc.n]; end
            grp = {};
            for k = 1:numel(names)
                if k <= numel(n)
                    grp{end+1} = sprintf('%s (n = %d)', names{k}, n(k)); %#ok<AGROW>
                else
                    grp{end+1} = names{k}; %#ok<AGROW>
                end
            end
            feat = MethodsWriter.getf(gs, 'feature', '');
            fd = MethodsWriter.getf(gs, 'featureText', '');        % EEG Analysis: its own wording
            if isempty(fd), fd = MethodsWriter.featureDefinition(feat); end
            if isempty(fd), fd = 'response feature'; end
            design = lower(MethodsWriter.getf(gt, 'design', ''));
            method = lower(MethodsWriter.getf(gt, 'method', 'parametric'));
            nonPar = strncmp(method, 'non', 3);
            parts = {};
            switch MethodsWriter.getf(gs, 'subjectMode', '')
                case 'File (mean trace)'
                    subj = 'one value per file (one file per subject), computed from the mean trace of the file''s trials';
                case 'File (mean of series)'
                    subj = 'one value per file (one file per subject): the mean of the values of the file''s trials';
                case 'Each series'
                    subj = 'one value per trial (each trial treated as one subject)';
                otherwise
                    subj = MethodsWriter.getf(gs, 'subjectText', '');
            end
            t = sprintf('The %s was compared between %s', fd, MethodsWriter.listText(grp));
            if ~isempty(subj), t = sprintf('%s, using %s', t, subj); end
            t = [t MethodsWriter.baselineClause(MethodsWriter.getf(gs, 't0', NaN), MethodsWriter.getf(gs, 'baseline', []), ...
                MethodsWriter.getf(gs, 'direction', ''))];
            parts{end+1} = t;
            switch design
                case 'paired'
                    if nonPar
                        parts{end+1} = ['Conditions were compared with the Wilcoxon signed-rank test ({{wilcoxon1945}}; ' ...
                            'exact p without ties or zero differences and n < 50, otherwise the normal approximation with ' ...
                            'continuity correction); the effect size was the rank-biserial correlation. A paired t-test ' ...
                            '({{student1908}}) was run as a robustness check.'];
                    else
                        parts{end+1} = ['Conditions were compared with a paired t-test ({{student1908}}) on the ' ...
                            'within-subject differences; the effect size was d_z (mean difference divided by the SD of ' ...
                            'the differences). The Wilcoxon signed-rank test ({{wilcoxon1945}}) was run as a robustness check.'];
                    end
                case 'unpaired'
                    if nonPar
                        parts{end+1} = ['Groups were compared with the Mann&ndash;Whitney U test ({{mannwhitney1947}}); the ' ...
                            'effect size was the rank-biserial correlation. Welch''s t-test ({{welch1947}}) was run as a ' ...
                            'robustness check.'];
                    else
                        parts{end+1} = ['Groups were compared with Welch''s t-test ({{welch1947}}), which does not ' ...
                            'assume equal variances; the effect size was Hedges'' g ({{hedges1981}}). The Mann&ndash;Whitney ' ...
                            'U test ({{mannwhitney1947}}) was run as a robustness check.'];
                    end
                case 'anova'
                    if nonPar
                        parts{end+1} = ['Groups were compared with the Kruskal&ndash;Wallis test ({{kruskal1952}}; effect size ' ...
                            '&eta;&sup2;_H), followed by pairwise Mann&ndash;Whitney U tests ({{mannwhitney1947}}) with ' ...
                            'Holm-adjusted p-values ({{holm1979}}). A one-way ANOVA was run as a robustness check.'];
                    else
                        parts{end+1} = ['Groups were compared with a one-way ANOVA (effect sizes &eta;&sup2; and ' ...
                            '&omega;&sup2;) followed by Tukey&ndash;Kramer post hoc comparisons ({{kramer1956}}). The ' ...
                            'Kruskal&ndash;Wallis test ({{kruskal1952}}) was run as a robustness check.'];
                    end
                case 'rm'
                    if nonPar
                        parts{end+1} = ['Conditions were compared with the Friedman test ({{friedman1937}}; tie-corrected; ' ...
                            'effect size Kendall''s W), with subjects matched across conditions, followed by Wilcoxon ' ...
                            'signed-rank tests ({{wilcoxon1945}}) on every pair of conditions with Holm-adjusted p-values ' ...
                            '({{holm1979}}). A repeated-measures ANOVA was run as a robustness check.'];
                    else
                        parts{end+1} = ['Conditions were compared with a one-way repeated-measures ANOVA, with subjects ' ...
                            'matched across conditions. Sphericity was tested with Mauchly''s test ({{mauchly1940}}); when ' ...
                            'it was significant (p < 0.05) or could not be computed, the Greenhouse&ndash;Geisser correction ' ...
                            '({{greenhouse1959}}) was applied (Huynh&ndash;Feldt corrected values, {{huynh1976}}, were also ' ...
                            'computed). Effect sizes were partial and generalized &eta;&sup2; ({{olejnik2003}}; ' ...
                            '{{bakeman2005}}). Post hoc comparisons were paired t-tests on every pair of conditions with ' ...
                            'Holm-adjusted p-values ({{holm1979}}) and d_z effect sizes with exact 95% confidence ' ...
                            'intervals. The Friedman test ({{friedman1937}}) was run as a robustness check.'];
                        sph = MethodsWriter.getf(gt, 'main.sphericity', []);
                        if isstruct(sph) && numel(names) >= 3
                            parts{end+1} = MethodsWriter.sphericitySentence(sph);
                        end
                    end
                otherwise
                    parts{end+1} = '[please add: statistical test.]';
            end
            parts{end+1} = 'All tests were two-sided with a significance level of 0.05.';
            switch MethodsWriter.getf(gs, 'plotStyle', '')
                case 'Box plot (median, IQR)'
                    parts{end+1} = 'Figures show the median and interquartile range (box plots) with individual subjects.';
                case ''
                otherwise
                    parts{end+1} = 'Figures show the mean and standard error of the mean (SEM) with individual subjects.';
            end
            parts = parts(~cellfun(@isempty, parts));
            t = strjoin(parts, ' ');
        end

        %% sphericitySentence - What Mauchly's test gave in these data
        function t = sphericitySentence(sph)
            t = '';
            testable = logical(MethodsWriter.getf(sph, 'testable', false));
            corrName = MethodsWriter.getf(sph, 'correction', '');
            epsGG = MethodsWriter.getf(sph, 'epsGG', NaN);
            if ~testable
                t = 'In these data, Mauchly''s test could not be computed (fewer subjects than conditions)';
            else
                W = MethodsWriter.getf(sph, 'W', NaN);
                p = MethodsWriter.getf(sph, 'p', NaN);
                if ~MethodsWriter.isNum(W) || ~MethodsWriter.isNum(p), return; end
                t = sprintf('In these data, Mauchly''s test gave W = %s, %s', MethodsWriter.num(W), MethodsWriter.pText(p));
            end
            if strcmp(corrName, 'Greenhouse-Geisser') && MethodsWriter.isNum(epsGG)
                t = sprintf('%s, so the Greenhouse&ndash;Geisser corrected p-value is reported (&epsilon; = %s).', t, MethodsWriter.num(epsGG));
            else
                t = [t ', so the uncorrected p-value is reported.'];
            end
        end

        %% softwareParagraph - Neuronal Data Analyzer Lab and MATLAB versions (and toolboxes)
        function t = softwareParagraph(list, tbx)
            vers = {}; rels = {};
            for k = 1:numel(list)
                v = char(MethodsWriter.getf(list{k}, 'toolboxVersion', ''));
                if ~isempty(v), vers{end+1} = ['v' v]; end %#ok<AGROW>
                r = MethodsWriter.releaseText(list{k});
                if ~isempty(r), rels{end+1} = r; end %#ok<AGROW>
            end
            vers = MethodsWriter.uniqueStable(vers);
            rels = MethodsWriter.uniqueStable(rels);
            if isempty(vers), vers = {'[please add: version]'}; end
            t = sprintf('Analyses were performed with Neuronal Data Analyzer Lab %s ({{suarez}}), a MATLAB toolbox', MethodsWriter.listText(vers));
            if isempty(rels)
                t = [t ', running on MATLAB [please add: release] (The MathWorks Inc., Natick, MA, USA)'];
            else
                t = sprintf('%s, running on MATLAB %s (The MathWorks Inc., Natick, MA, USA)', t, MethodsWriter.listText(rels));
            end
            if ~isempty(tbx)
                t = sprintf('%s with %s', t, MethodsWriter.listText(cellfun(@(x) ['the ' x], tbx, 'UniformOutput', false)));
            end
            t = [t '.'];
        end

        %% releaseText - 'R2021a' from matlabRelease or matlabVersion ('' if unknown)
        function r = releaseText(s)
            r = char(MethodsWriter.getf(s, 'matlabRelease', ''));
            if ~isempty(r)
                if r(1) ~= 'R', r = ['R' r]; end
                return;
            end
            tok = regexp(char(MethodsWriter.getf(s, 'matlabVersion', '')), '\((R\d{4}[ab])\)', 'tokens', 'once');
            if ~isempty(tok), r = tok{1}; end
        end

        %% resolveCitations - {{key}} -> 'Author, year'; keys in order of appearance
        function [txt, keys] = resolveCitations(txt, list)
            R = MethodsWriter.references();
            tok = regexp(txt, '\{\{(\w+)\}\}', 'tokens');
            keys = {};
            for k = 1:numel(tok)
                key = tok{k}{1};
                if any(strcmp(keys, key)), continue; end
                keys{end+1} = key; %#ok<AGROW>
            end
            for k = 1:numel(keys)
                if strcmp(keys{k}, 'suarez')
                    short = sprintf('Suarez, %s', MethodsWriter.toolboxYear(list));
                else
                    i = find(strcmp(R(:, 1), keys{k}), 1);
                    if isempty(i), short = ''; else, short = R{i, 2}; end
                end
                txt = strrep(txt, ['{{' keys{k} '}}'], short);
            end
        end

        %% referenceList - Full references of the keys (alphabetical)
        function refs = referenceList(keys, list)
            R = MethodsWriter.references();
            refs = {};
            for k = 1:numel(keys)
                if strcmp(keys{k}, 'suarez')
                    refs{end+1} = MethodsWriter.toolboxReference(list); %#ok<AGROW>
                else
                    i = find(strcmp(R(:, 1), keys{k}), 1);
                    if ~isempty(i), refs{end+1} = R{i, 3}; end %#ok<AGROW>
                end
            end
            refs = sort(refs);
        end

        %% toolboxReference - The Neuronal Data Analyzer Lab reference (version and year of the sessions)
        function r = toolboxReference(list)
            vers = {};
            for k = 1:numel(list)
                v = char(MethodsWriter.getf(list{k}, 'toolboxVersion', ''));
                if ~isempty(v), vers{end+1} = v; end %#ok<AGROW>
            end
            vers = MethodsWriter.uniqueStable(vers);
            y = MethodsWriter.toolboxYear(list);
            if isempty(vers), vtxt = '[please add: version]'; else, vtxt = strjoin(vers, ', '); end
            r = sprintf('Suarez A (%s). Neuronal Data Analyzer Lab, version %s [computer software]. %s', ...
                y, vtxt, MethodsWriter.RepoURL);
        end

        %% toolboxYear - Latest year the sessions were saved (placeholder if unknown)
        function y = toolboxYear(list)
            y = '[please add: year]';
            best = 0;
            for k = 1:numel(list)
                c = char(MethodsWriter.getf(list{k}, 'created', ''));
                if numel(c) >= 4 && all(isstrprop(c(1:4), 'digit')) && str2double(c(1:4)) > best
                    best = str2double(c(1:4));
                    y = c(1:4);
                end
            end
        end

        %% sessionList - Normalise the input to a cell of session structs
        function out = sessionList(list)
            if ischar(list), list = {list}; end
            if isstruct(list), list = num2cell(list); end
            if ~iscell(list)
                error('NeuroAnalyzer:MethodsWriter:invalidSession', ...
                    'Give a session struct, a .nasession.mat path, or a list of them.');
            end
            out = cell(1, numel(list));
            for k = 1:numel(list)
                s = list{k};
                if ischar(s), s = Session.load(s); end
                if ~isstruct(s) || ~isscalar(s) || ~isfield(s, 'app') || ~isfield(s, 'settings')
                    error('NeuroAnalyzer:MethodsWriter:invalidSession', ...
                        'Item %d is not a Neuronal Data Analyzer Lab session.', k);
                end
                if ~isfield(s, 'results'), s.results = struct(); end
                if ~isfield(s, 'summary'), s.summary = {}; end
                if ~isfield(s, 'inputs'), s.inputs = struct([]); end
                out{k} = s;
            end
        end

        %% pipelineRank - Position of a window in the pipeline order
        function r = pipelineRank(app)
            order = MethodsWriter.PipelineOrder;
            r = find(strcmp(order, app), 1);
            if isempty(r), r = numel(order) - 0.5; end   % unknown: just before the last step
        end

        % ---------------------------------------------------------------
        % Dialog callbacks
        % ---------------------------------------------------------------

        %% refreshDialog - Regenerate the text from the sessions in the dialog
        function refreshDialog(fig)
            d = fig.UserData;
            [txt, refs] = MethodsWriter.fromSessions(d.sessions);
            full = MethodsWriter.compose(txt, refs);
            % A text area drops empty (and blank) lines: it shows one line per
            % paragraph (each paragraph is one line, so pasted into a word
            % processor they are still separate paragraphs)
            lines = strsplit(full, newline)';
            shown = lines(~cellfun(@(x) isempty(strtrim(x)), lines));
            d.ta.Value = shown;
            d.generated = strjoin(shown, newline);   % compared with dialogText to detect edits
            names = cellfun(@(x) MethodsWriter.sessionName(x), d.sessions, 'UniformOutput', false);
            if numel(d.sessions) == 1
                d.status.Text = sprintf('Drafted from 1 session: %s. Square brackets mark what you must add.', names{1});
            else
                d.status.Text = sprintf(['Drafted from %d sessions, in pipeline order: %s. Square brackets mark ' ...
                    'what you must add.'], numel(d.sessions), strjoin(MethodsWriter.uniqueStable(names), ', '));
            end
            fig.UserData = d;
        end

        %% sessionName - Window title (or class) of a session
        function n = sessionName(s)
            n = char(MethodsWriter.getf(s, 'appTitle', ''));
            if isempty(n), n = s.app; end
        end

        %% dialogText - Current (edited) text of the dialog
        function txt = dialogText(fig)
            txt = strjoin(cellstr(fig.UserData.ta.Value), newline);
        end

        %% copyText - Copy the edited text to the clipboard
        function copyText(fig)
            d = fig.UserData;
            try
                clipboard('copy', MethodsWriter.dialogText(fig));
                d.status.Text = 'Copied. Paste it into your manuscript (Ctrl+V or Cmd+V) and check every sentence.';
            catch ME
                d.status.Text = sprintf('Could not copy to the clipboard (%s): use Save .txt instead.', ME.message);
            end
        end

        %% saveText - Save the edited text as .txt
        function saveText(fig)
            d = fig.UserData;
            folder = pwd;
            base = 'methods';
            if ~isempty(d.app)
                try, folder = UIKit.sessionFolder(d.app); catch, end
                [~, b] = fileparts(Session.lastPath(d.app));
                b = regexprep(b, '\.nasession$', '');
                if ~isempty(b), base = [b '_methods']; end
            end
            [f, p] = uiputfile({'*.txt', 'Text file (*.txt)'}, 'Save methods text', fullfile(folder, [base '.txt']));
            figure(fig);
            if isequal(f, 0), return; end
            try
                out = MethodsWriter.write(fullfile(p, f), MethodsWriter.dialogText(fig));
                [~, n, e] = fileparts(out);
                d.status.Text = sprintf('Saved to %s%s (UTF-8 text: open it in Word, or copy and paste).', n, e);
            catch ME
                uialert(fig, ME.message, 'Save methods text', 'Icon', 'error');
            end
        end

        %% addSessions - Add .nasession.mat files and regenerate the combined text
        function addSessions(fig)
            d = fig.UserData;
            folder = pwd;
            if ~isempty(d.app)
                try, folder = UIKit.sessionFolder(d.app); catch, end
            end
            [f, p] = uigetfile({['*' Session.Extension], 'Neuronal Data Analyzer Lab session (*.nasession.mat)'}, ...
                'Add saved sessions (select several with Ctrl or Shift)', folder, 'MultiSelect', 'on');
            figure(fig);
            if isequal(f, 0), return; end
            f = cellstr(f);
            added = {}; bad = {};
            for k = 1:numel(f)
                try
                    added{end+1} = Session.load(fullfile(p, f{k})); %#ok<AGROW>
                catch ME
                    bad{end+1} = sprintf('%s: %s', f{k}, ME.message); %#ok<AGROW>
                end
            end
            if ~isempty(bad)
                uialert(fig, sprintf('These files were not added:\n%s', strjoin(bad, newline)), ...
                    'Add saved sessions', 'Icon', 'warning');
            end
            if isempty(added), return; end
            if ~strcmp(MethodsWriter.dialogText(fig), d.generated)
                sel = uiconfirm(fig, ['The combined text replaces the text in the box, including your edits. ' ...
                    'Copy or save your edits first if you want to keep them.'], 'Add saved sessions', ...
                    'Options', {'Replace', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
                if ~strcmp(sel, 'Replace'), return; end
            end
            d.sessions = [d.sessions, added];
            fig.UserData = d;
            MethodsWriter.refreshDialog(fig);
        end

        % ---------------------------------------------------------------
        % Text helpers
        % ---------------------------------------------------------------

        %% getf - Field at a dotted path, or default when missing / empty
        function v = getf(s, path, default)
            v = default;
            parts = strsplit(path, '.');
            cur = s;
            for k = 1:numel(parts)
                if ~isstruct(cur) || ~isscalar(cur) || ~isfield(cur, parts{k}), return; end
                cur = cur.(parts{k});
            end
            if isempty(cur) && ~isstruct(cur), return; end
            v = cur;
        end

        %% isNum - Finite real numeric (or logical) scalar
        function tf = isNum(x)
            tf = (isnumeric(x) || islogical(x)) && isscalar(x) && isreal(x) && isfinite(double(x));
        end

        %% num - Number as text: integers plain, others to 3 significant digits (2 decimals above 100)
        function t = num(x)
            x = double(x);
            if ~MethodsWriter.isNum(x)
                t = '[please add: value]';
                return;
            end
            if x < 0
                t = ['&minus;' MethodsWriter.num(-x)];
                return;
            end
            ax = abs(x);
            if x == round(x) && ax < 1e9
                t = sprintf('%d', round(x));
            elseif ax >= 100
                t = regexprep(sprintf('%.2f', x), '\.?0+$', '');
            elseif ax >= 1e-3
                t = sprintf('%.3g', x);
            else
                e = floor(log10(ax));
                t = sprintf('%.2g &times; 10^%d', x / 10^e, e);
            end
        end

        %% dur - Duration: '50 ms' below 1 s, else '2 s'
        function t = dur(sec)
            if MethodsWriter.isNum(sec) && abs(sec) < 1 && sec ~= 0
                t = sprintf('%s ms', MethodsWriter.num(sec * 1000));
            else
                t = sprintf('%s s', MethodsWriter.num(sec));
            end
        end

        %% secRange - '-5 to 20 s'
        function t = secRange(a, b)
            t = sprintf('%s to %s s', MethodsWriter.num(a), MethodsWriter.num(b));
        end

        %% ordinal - '1st', '2nd', '3rd', '4th', '11th', '22nd', ...
        function t = ordinal(n)
            n = round(double(n));
            if mod(floor(n / 10), 10) == 1
                suf = 'th';
            else
                switch mod(n, 10)
                    case 1, suf = 'st';
                    case 2, suf = 'nd';
                    case 3, suf = 'rd';
                    otherwise, suf = 'th';
                end
            end
            t = sprintf('%d%s', n, suf);
        end

        %% plural - '1 file', '3 files'
        function t = plural(n, word)
            if n == 1, t = sprintf('1 %s', word); else, t = sprintf('%d %ss', n, word); end
        end

        %% listText - 'a', 'a and b', 'a, b and c'
        function t = listText(c)
            c = cellstr(c);
            c = c(~cellfun(@isempty, c));
            if isempty(c)
                t = '';
            elseif numel(c) == 1
                t = c{1};
            else
                t = sprintf('%s and %s', strjoin(c(1:end-1), ', '), c{end});
            end
        end

        %% chanText - 'channel 4', 'channels 1-8', 'channels 1, 3 and 5'
        function t = chanText(v)
            v = double(v(:)');
            if numel(v) == 1
                t = sprintf('channel %s', MethodsWriter.num(v));
            elseif numel(v) >= 3 && all(diff(v) == 1)
                t = sprintf('channels %s&ndash;%s', MethodsWriter.num(v(1)), MethodsWriter.num(v(end)));
            else
                t = sprintf('channels %s', MethodsWriter.listText(arrayfun(@(x) MethodsWriter.num(x), v, 'UniformOutput', false)));
            end
        end

        %% orderText - Channel order: 'channels 1-8' when ascending, else the list in order
        function t = orderText(v)
            v = double(v(:)');
            if numel(v) >= 3 && all(diff(v) == 1)
                t = MethodsWriter.chanText(v);
            else
                t = sprintf('channels %s', strjoin(arrayfun(@(x) MethodsWriter.num(x), v, 'UniformOutput', false), ', '));
            end
        end

        %% lineText - 'a line from (x1, y1) to (x2, y2) pixels (length L pixels)'
        function t = lineText(ln)
            if isnumeric(ln) && numel(ln) == 4 && all(isfinite(ln(:)))
                if isequal(size(ln), [2 2]), xy = ln; else, xy = reshape(ln(:), 2, 2)'; end
                L = sqrt(sum((xy(2, :) - xy(1, :)).^2));
                t = sprintf('a line from (%s, %s) to (%s, %s) pixels (length %s pixels)', MethodsWriter.num(xy(1, 1)), ...
                    MethodsWriter.num(xy(1, 2)), MethodsWriter.num(xy(2, 1)), MethodsWriter.num(xy(2, 2)), MethodsWriter.num(L));
            else
                t = 'a line';
            end
        end

        %% pText - 'p = 0.012' / 'p < 0.0001'
        function t = pText(p)
            if p < 1e-4
                t = 'p < 0.0001';
            else
                t = sprintf('p = %.2g', p);
                if p >= 0.001, t = sprintf('p = %.3f', p); end
            end
        end

        %% capital - First letter upper case
        function t = capital(t)
            if ~isempty(t), t(1) = upper(t(1)); end
        end

        %% fromSummary - First numeric token of a summary line matching expr (NaN if none)
        function v = fromSummary(s, expr)
            v = NaN;
            tok = MethodsWriter.summaryTokens(s, expr);
            if ~isempty(tok), v = str2double(tok{1}); end
        end

        %% summaryTokens - Tokens of the first summary line matching expr ({} if none)
        function tok = summaryTokens(s, expr)
            tok = {};
            lines = MethodsWriter.getf(s, 'summary', {});
            if ischar(lines), lines = {lines}; end
            for k = 1:numel(lines)
                t = regexp(char(lines{k}), expr, 'tokens', 'once');
                if ~isempty(t), tok = t; return; end
            end
        end

        %% formatLabel - Recording format description ('' if unknown)
        function t = formatLabel(fmt)
            switch lower(char(fmt))
                case 'tdt',       t = 'Tucker-Davis Technologies (TDT) tank';
                case 'intan',     t = 'Intan RHD2000 data file (.rhd)';
                case 'openephys', t = 'Open Ephys binary recording';
                case 'nwb',       t = 'Neurodata Without Borders (NWB 2.x) file';
                case 'spikeglx',  t = 'SpikeGLX binary file (.bin with .meta)';
                case 'blackrock', t = 'Blackrock Microsystems NSx file';
                case 'neuralynx', t = 'Neuralynx continuous sampled channel (.ncs) files';
                case 'mcs',       t = 'Multi Channel Systems HDF5 file';
                case 'intanrhs',  t = 'Intan RHS2000 data file (.rhs)';
                case 'openephyslegacy', t = 'Open Ephys data format (.continuous) files';
                otherwise,        t = '';
            end
        end

        %% entities - Replace &name; tokens by the characters (micro, plus-minus, en dash, Greek ...)
        % The text is built from ASCII with these tokens so that the source
        % stays ASCII and the result is right in MATLAB (UTF-16 char) and in
        % Octave (UTF-8 bytes).
        function t = entities(t)
            map = {'&mu;', 181; '&plusmn;', 177; '&times;', 215; '&ndash;', 8211; '&minus;', 8722; ...
                '&sup2;', 178; '&sup3;', 179; '&lambda;', 955; '&sigma;', 963; '&epsilon;', 949; ...
                '&eta;', 951; '&omega;', 969; '&psi;', 968; '&Delta;', 916; '&tau;', 964; '&beta;', 946};
            for k = 1:size(map, 1)
                if ~isempty(strfind(t, map{k, 1}))
                    t = strrep(t, map{k, 1}, MethodsWriter.sym(map{k, 2}));
                end
            end
        end

        %% sym - One Unicode character as text (UTF-8 bytes in Octave)
        function c = sym(code)
            if exist('OCTAVE_VERSION', 'builtin') == 0
                c = char(code);
            elseif code < 128
                c = char(code);
            elseif code < 2048
                c = char([192 + floor(code / 64), 128 + mod(code, 64)]);
            else
                c = char([224 + floor(code / 4096), 128 + mod(floor(code / 64), 64), 128 + mod(code, 64)]);
            end
        end

        %% uniqueStable - Unique cellstr in order of first appearance
        function out = uniqueStable(c)
            out = {};
            for k = 1:numel(c)
                if ~any(strcmp(out, c{k})), out{end+1} = c{k}; end %#ok<AGROW>
            end
        end
    end
end
