%% Main.m
% =========================================================================
% NEURONAL DATA ANALYZER - MAIN LAUNCHER
% =========================================================================
% Entry point for the NeuroAnalyzer application. On first run (or
% when no project dirs are set), prompts for Import/Export directories.
%
% Layout (top to bottom): header (title, subtitle, Help) | project bar
% (Import/Export folders, Set folders) | "Getting started" hint (with a
% "Try with demo data" button that opens Help on Welcome, and a "Virtual
% lab" button that opens VirtualLabApp) | one
% workflow card per pipeline | status bar (toolbox availability) | footer.
% Each workflow card holds a one-line description, the pipeline's steps as
% numbered buttons in order (tooltips say which file goes in and out) and
% a '?' button that opens the matching HelpApp topic:
%   LDF:               1 Extract -> 2 Process -> 3 Average
%   Electrophysiology: 1 Extract -> 2 LFP analysis or 2 MUA analysis
%   Imaging:           ROI analysis
%   Response features: Signal Characterization
%   Batch:             Batch processing (one pipeline on many files)
% =========================================================================

classdef Main < handle
    properties
        UIFig
        HeaderPanel
        HelpBtn
        ProjectPanel
        ImportLabel
        ExportLabel
        ContentPanel
        StatusLabel        % Status bar (toolbox availability, last action)
        DemoBtn            % "Try with demo data" (opens HelpApp('Welcome'))
        VirtualLabBtn      % "Virtual lab" (opens VirtualLabApp)
        % Workflow cards
        LDFPanel
        EphysPanel
        ImagingPanel
        CharPanel
        BatchPanel
        % Step buttons
        ExtractLDFBtn
        ProcessLDFBtn
        AverageLDFBtn
        ExtractEphysBtn
        LFPAnalysisBtn
        ProcessMUABtn
        ROIBtn             % Open ROI / image analysis
        CharBtn            % Open Signal Characterization
        BatchBtn           % Open Batch processing
        % Environment checks (set by checkSignalToolbox / checkTDTSDK)
        HasSignalToolbox = true
        HasTDTSDK = false
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
                'Position', UIKit.centeredPosition([1060 940]), 'Resize', 'on', ...
                'Color', T.bgGray);
            UIKit.setAppIcon(app.UIFig);

            % === MAIN GRID: Header | Project bar | Hint | Cards | Status | Footer ===
            mainGrid = uigridlayout(app.UIFig, [6, 1], ...
                'RowHeight', {T.headerHeight, 48, 50, '1x', T.statusHeight, T.footerHeight}, ...
                'ColumnWidth', {'1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0, ...
                'BackgroundColor', T.bgGray);

            % === HEADER ===
            [app.HeaderPanel, app.HelpBtn] = UIKit.header(mainGrid, 'Neuronal Data Analyzer Lab', ...
                'Analysis toolbox for LDF, electrophysiology, imaging and response features', 'Welcome', [], true);
            app.HelpBtn.Tooltip = 'Overview of the pipelines, project folders and where to get help';

            % === PROJECT BAR ===
            app.ProjectPanel = uipanel(mainGrid, 'BackgroundColor', T.projectBarBg, ...
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

            % === GETTING STARTED HINT ===
            hintPanel = uipanel(mainGrid, 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            hintGrid = uigridlayout(hintPanel, [1 3], 'ColumnWidth', {'1x', 190, 150}, ...
                'RowHeight', {'1x'}, 'Padding', [16 10 16 0], 'ColumnSpacing', 10, ...
                'BackgroundColor', T.bgGray);
            UIKit.hint(hintGrid, ['Getting started: pick the card for your data and click its steps ' ...
                'in order; each step saves a .mat file that the next step loads. Hover a button to see ' ...
                'which file it needs, and use ? on a card (or ? Help in any window) for a quick start.']);
            demoGrid = uigridlayout(hintGrid, [3 1], 'RowHeight', {'1x', T.buttonHeight, '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 0, 'BackgroundColor', T.bgGray);
            app.DemoBtn = UIKit.button(demoGrid, [char(9654) ' Try with demo data'], ...
                @(~,~)app.openDemoHelp(), 'secondary', ...
                ['New here? Open Help: every topic has a "Try it with demo data" button that opens ' ...
                 'the window with synthetic data whose answers are known']);
            app.DemoBtn.Layout.Row = 2;
            labGrid = uigridlayout(hintGrid, [3 1], 'RowHeight', {'1x', T.buttonHeight, '1x'}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 0, 'BackgroundColor', T.bgGray);
            app.VirtualLabBtn = UIKit.button(labGrid, 'Virtual lab', ...
                @(~,~)app.launch(@()VirtualLabApp(), 'Virtual lab'), 'secondary', ...
                ['Learn by doing: plan and record a simulated experiment (LDF, whisker stimulation), ' ...
                 'analyse it yourself in the normal windows, and get feedback on every step']);
            app.VirtualLabBtn.Layout.Row = 2;

            % === WORKFLOW CARDS ===
            app.ContentPanel = uipanel(mainGrid, 'BackgroundColor', T.bgGray, 'BorderType', 'none');
            contentGrid = uigridlayout(app.ContentPanel, [5, 1], ...
                'RowHeight', {'1x', '1x', '1x', '1x', '1x'}, 'Padding', [16 10 16 10], ...
                'RowSpacing', 10, 'BackgroundColor', T.bgGray, 'Scrollable', 'on');

            % --- LDF ---
            [app.LDFPanel, chain] = app.workflowCard(contentGrid, ...
                'LDF  ·  Laser Doppler Flowmetry', ...
                'Blood-flow recordings: crop, filter, cut trials around each stimulus and average them.', ...
                'In: LabChart .mat export  ·  Out: cropped .mat, then segmented trials .mat', ...
                'LDF Extract');
            app.ExtractLDFBtn = chainButton(chain, 1, '1   Extract', @()ExtractLDFApp(), ...
                ['Input: LabChart .mat export (data, datastart, dataend, samplerate; stimulus on ' ...
                 'channel 6, LDF on channel 8). Select a time range and crop. ' ...
                 'Output: cropped .mat with stim, LDF, t, Fs.'], app);
            chainArrow(chain, 2);
            app.ProcessLDFBtn = chainButton(chain, 3, '2   Process', @()ProcessingLDFApp(), ...
                ['Input: cropped .mat from step 1 (stim, LDF, t, Fs). Downsample, filter and ' ...
                 'segment trials around stimulus onsets. Output: .mat with segmentedLDF ' ...
                 '(trials x samples), segmentedTime, Fs; saving to an existing file appends trials.'], app);
            chainArrow(chain, 4);
            app.AverageLDFBtn = chainButton(chain, 5, '3   Average', @()LDFGrandAverageApp(), ...
                ['Input: one or more segmented .mat files from step 2 (segmentedLDF, segmentedTime; ' ...
                 'time axes must match). Output: grand average (mean ± SD) across all trials, ' ...
                 'optionally relative to the pre-stimulus baseline.'], app);

            % --- Electrophysiology ---
            [app.EphysPanel, chain] = app.workflowCard(contentGrid, ...
                'Electrophysiology  ·  LFP and MUA', ...
                'TDT, Intan, Open Ephys or NWB recordings: extract LFP and MUA, then ERP, CSD, time-frequency, spike sorting and rates.', ...
                'In: TDT tank, .rhd, Open Ephys folder or .nwb  ·  Out: LFP .mat and MUA .mat', ...
                'Ephys Extract');
            app.ExtractEphysBtn = chainButton(chain, 1, '1   Extract', @()ExtractEphysApp(), ...
                ['Input: TDT tank/block folder (needs the TDT MATLAB SDK, README: Install the TDT SDK), ' ...
                 'Intan .rhd, Open Ephys binary folder or NWB file. Output: LFP .mat (lfp_data, lfp_channels, ' ...
                 'lfp_fs, t_lfp, stim_data, stim_fs, t_stim) and MUA .mat (mua_data, mua_channels, ' ...
                 'mua_fs, t_mua, stim_*, filterParams).'], app);
            chainArrow(chain, 2);
            app.LFPAnalysisBtn = chainButton(chain, 3, '2   LFP analysis', @()LFPAnalysisApp(), ...
                ['Input: LFP .mat from step 1 (lfp_data, t_lfp, lfp_fs, stim_data, t_stim, stim_fs). ' ...
                 'ERP: epochs around stimulus onsets averaged per channel; CSD across channels ' ...
                 '(needs the ERP first). Output: ERP / CSD plots and an exported .mat (t, y = channel ' ...
                 'mean ERP, erp_avg, erp_std, csd) that Signal Characterization can read.'], app);
            orLbl = uilabel(chain, 'Text', 'or', 'FontSize', T.fontSmall, ...
                'FontColor', T.mutedColor, 'HorizontalAlignment', 'center');
            orLbl.Layout.Row = 2; orLbl.Layout.Column = 4;
            app.ProcessMUABtn = chainButton(chain, 5, '2   MUA analysis', @()MUAAnalysisApp(), ...
                ['Input: MUA .mat from step 1 (mua_data, mua_fs, t_mua, mua_channels; stim_data ' ...
                 'optional, needed to segment by stimulus). Spike detection, clustering and ' ...
                 'spike rate. Output: .mat with SpikeResults (spike times, cluster IDs, waveforms), ' ...
                 'SpikeSortParams, clusterQuality, info.'], app);

            % --- Imaging ---
            [app.ImagingPanel, chain] = app.workflowCard(contentGrid, ...
                'Imaging  ·  ROI and line analysis', ...
                'Image stacks (2-photon, gCaMP, blood-flow imaging): measure a ROI or a line over time.', ...
                'In: .mat stack or multi-frame TIFF  ·  Out: time series .csv / .mat', ...
                'ROI Analysis');
            app.ROIBtn = chainButton(chain, 1, 'ROI analysis', @()ROIAnalysisApp(), ...
                ['Input: .mat with stack or frames (H x W x N or H x W x 3 x N; optional timeVec or t ' ...
                 'and roiMask) or a multi-frame TIFF. Output: brightness, movement, ΔF/F, flow speed, ' ...
                 'kymograph or vessel diameter as .csv or .mat.'], app);
            chainNote(chain, 'Motion correction · Cell detection · ΔF/F · Flow speed · Kymograph · Vessel diameter');

            % --- Response features ---
            [app.CharPanel, chain] = app.workflowCard(contentGrid, ...
                'Response features  ·  Signal Characterization', ...
                'Measure each response (latency, FWHM, AUC, rise / decay) and compare groups of animals statistically.', ...
                'In: segmented LDF, LFP .mat or any t / y .mat  ·  Out: feature table .csv / .mat', ...
                'Signal Characterization');
            app.CharBtn = chainButton(chain, 1, 'Signal Characterization', @()SignalCharacterizationApp(), ...
                ['Input: segmented LDF .mat (segmentedLDF, segmentedTime) from LDF step 2, LFP .mat ' ...
                 '(lfp_data, t_lfp) from Extract Ephys, the ERP export of LFP analysis, or any .mat ' ...
                 'with t and y. Output: one row of ' ...
                 'features per trial, exported as .csv or .mat.'], app);
            chainNote(chain, 'Features · Group statistics · Publication figures (PDF / SVG)');

            % --- Batch processing ---
            [app.BatchPanel, chain] = app.workflowCard(contentGrid, ...
                'Batch  ·  Many files at once', ...
                'Run one analysis on a whole folder with the same settings and get one summary table.', ...
                'In: a folder of files for one pipeline  ·  Out: summary .csv / .mat + log', ...
                'Batch processing');
            app.BatchBtn = chainButton(chain, 1, 'Batch processing', @()BatchApp(), ...
                ['Input: a folder or list of files for one pipeline: cropped LDF .mat (trials + response ' ...
                 'features), LFP .mat (ERP / CSD per channel), MUA .mat (spike sorting per channel), ' ...
                 'image stacks (ROI dF/F, vessel diameter) or any trace file (response features). ' ...
                 'Output: one summary table (.csv and .mat, one row per file / channel / ROI) and a log; ' ...
                 'files that fail are listed with their error.'], app);
            chainNote(chain, 'LDF trials · ERP / CSD · MUA sorting · ROI ΔF/F and diameter · Response features');

            % === STATUS + FOOTER ===
            app.StatusLabel = UIKit.statusBar(mainGrid);
            UIKit.footer(mainGrid);

            app.updateProjectLabels();
        end

        %% workflowCard - Card: [description / in-out] | step chain | '?' help
        % Returns the card panel and the 3x5 chain grid; buttons go in row 2
        % (columns 1, 3, 5 with arrows in 2 and 4).
        function [card, chain] = workflowCard(~, parent, titleText, descText, ioText, helpTopic)
            T = UITheme;
            card = UIKit.card(parent, titleText);
            g = uigridlayout(card, [1 3], 'ColumnWidth', {280, '1x', 32}, 'RowHeight', {'1x'}, ...
                'Padding', [12 6 10 8], 'ColumnSpacing', 14, 'BackgroundColor', T.cardBg);
            left = uigridlayout(g, [2 1], 'RowHeight', {'1x', 'fit'}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 2, 'BackgroundColor', T.cardBg);
            uilabel(left, 'Text', descText, 'FontSize', T.fontBody, 'WordWrap', 'on', ...
                'FontColor', T.sectionTitleColor, 'VerticalAlignment', 'center');
            uilabel(left, 'Text', ioText, 'FontSize', T.fontTiny, 'WordWrap', 'on', ...
                'FontColor', T.mutedColor);
            chain = uigridlayout(g, [3 5], 'RowHeight', {'1x', T.buttonHeight + 6, '1x'}, ...
                'ColumnWidth', {'1x', 24, '1x', 24, '1x'}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 0, 'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            helpCol = uigridlayout(g, [2 1], 'RowHeight', {T.buttonHeight - 4, '1x'}, ...
                'Padding', [0 0 0 0], 'BackgroundColor', T.cardBg);
            UIKit.button(helpCol, '?', @(~,~)HelpApp(helpTopic), 'secondary', ...
                sprintf('Help: %s (quick start, file formats, troubleshooting)', helpTopic));
        end

        %% launch - Open a sub-app, reporting success or failure in the status bar
        function launch(app, ctor, name)
            UIKit.setStatus(app.StatusLabel, sprintf('Opening %s', name), 'busy');
            try
                ctor();
                UIKit.setStatus(app.StatusLabel, sprintf('Opened %s', name), 'success');
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Could not open %s', name), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not open %s:\n%s', name, ME.message), name);
            end
        end

        %% openDemoHelp - Help on Welcome: demo files and a "Try it" per window
        function openDemoHelp(app)
            try
                HelpApp('Welcome');
                UIKit.setStatus(app.StatusLabel, ['Help opened: pick a topic and click "Try it with demo ' ...
                    'data", or "Generate all demo files" on Welcome'], 'success');
            catch ME
                UIKit.setStatus(app.StatusLabel, 'Could not open Help', 'error');
                UIKit.alert(app.UIFig, sprintf('Could not open Help:\n%s', ME.message), 'Help');
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
end

%% ------------------------------------------------------------------------
%  Local helpers
%% ------------------------------------------------------------------------

%% chainButton - Primary step button in row 2, column col of a workflow chain
% Single-app cards pass col = 1 and put a chainNote in columns 3-5.
function b = chainButton(chain, col, text, ctor, tooltip, app)
    name = strtrim(regexprep(text, '^\d+\s+', ''));
    b = UIKit.button(chain, text, @(~,~)app.launch(ctor, name), 'primary', tooltip);
    b.Layout.Row = 2;
    b.Layout.Column = col;
end

%% chainArrow - Right arrow between two step buttons
function chainArrow(chain, col)
    T = UITheme;
    a = uilabel(chain, 'Text', char(8594), 'FontSize', T.fontSection, ...
        'FontColor', T.mutedColor, 'HorizontalAlignment', 'center');
    a.Layout.Row = 2; a.Layout.Column = col;
end

%% chainNote - Muted note next to a single-step card's button (columns 3-5)
function chainNote(chain, text)
    T = UITheme;
    n = uilabel(chain, 'Text', text, 'FontSize', T.fontSmall, 'FontColor', T.mutedColor, ...
        'WordWrap', 'on');
    n.Layout.Row = 2; n.Layout.Column = [3 5];
end

function s = pathShorten(p, maxLen)
    if length(p) <= maxLen
        s = p;
        return;
    end
    s = ['...' p(end-maxLen+3:end)];
end
