%% HelpApp.m
% =========================================================================
% HELP APP - TABBED HELP WINDOW WITH PROCESS EXPLANATIONS AND FILTER DIAGRAM
% =========================================================================
% Opened from Main (Help button) or from ExtractLDFApp (?), or from
% LDFProcessingParamsApp ("? Filter help"). Optional constructor argument
% tabTitle (e.g. 'LDF Extract', 'Filtering') opens the window with that tab
% selected. Each tab shows step-by-step text plus an explanatory image (same format as
% Filtering). Images are in docs/ (e.g. FilterPrinciple.png, LDFExtractPrinciple.png).
% Path is resolved relative to the folder containing Main.m (getDocsPath).
% =========================================================================

classdef HelpApp < handle
    %% PROPERTIES
    properties
        UIFig       % Main uifigure
        HeaderPanel % Top bar (same style as Main)
        TabGroup    % uitabgroup containing all tabs
        Tabs        % Cell of tab titles (for finding tab by name)
        TabHandles  % Cell of uitab handles (for setting SelectedTab)
    end

    methods
        %% Constructor - Build UI and optionally select tab by title
        % -------------------------------------------------------------
        % If tabTitle is given and matches a tab name (case-insensitive),
        % sets TabGroup.SelectedTab to that tab after buildUI.
        % -------------------------------------------------------------
        function app = HelpApp(tabTitle)
            if nargin < 1, tabTitle = ''; end
            app.buildUI();
            if ~isempty(tabTitle)
                idx = find(strcmpi(app.Tabs, tabTitle), 1);
                if ~isempty(idx) && idx <= numel(app.TabHandles)
                    app.TabGroup.SelectedTab = app.TabHandles{idx};
                end
            end
        end

        %% getDocsPath - Resolve path to docs/filename relative to toolbox root
        % -------------------------------------------------------------
        % Uses preference NeuroAnalyzer.RootDir (set by NeuroAnalyzer.m), or
        % folder containing Main.m, or parent of that if docs live at project root.
        % -------------------------------------------------------------
        function p = getDocsPath(app, filename)
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

        %% buildUI - Create figure, tab group, and all 8 tabs with content
        % -------------------------------------------------------------
        % Tabs: Welcome (text only), then each process tab gets addProcessTab
        % (text + explanatory image from docs/, same format as Filtering).
        % -------------------------------------------------------------
        function buildUI(app)
            T = UITheme;
            app.UIFig = uifigure('Name', 'NeuroAnalyzer Help', ...
                'Position', [120 80 740 580], 'Resize', 'on', ...
                'Color', T.bgGray);

            mainGrid = uigridlayout(app.UIFig, [3, 1], ...
                'RowHeight', {T.headerHeight, '1x', T.footerHeight}, 'Padding', [0 0 0 0], 'RowSpacing', 0);
            % --- Header: full-width (covers upper part completely) ---
            app.HeaderPanel = uipanel(mainGrid, ...
                'BackgroundColor', T.headerBg, 'BorderType', 'none');
            uilabel(app.HeaderPanel, 'Text', 'NeuroAnalyzer Help', ...
                'Position', [T.headerPaddingH 14 400 24], ...
                'FontSize', 18, 'FontWeight', 'bold', 'FontColor', T.headerTitleColor);
            uilabel(app.HeaderPanel, 'Text', 'Process guides and filter reference', ...
                'Position', [T.headerPaddingH 2 320 16], ...
                'FontSize', T.fontSubtitle, 'FontColor', T.headerSubtitleColor);
            app.TabGroup = uitabgroup(mainGrid);
            app.Tabs = {'Welcome', 'LDF Extract', 'LDF Process', 'Filtering', ...
                'LDF Average', 'Ephys Extract', 'LFP Analysis', 'MUA Analysis', ...
                'ROI Analysis', 'Signal Characterization'};

            t0 = uitab(app.TabGroup, 'Title', app.Tabs{1});
            app.TabHandles = {t0};
            app.addScrollText(t0, HelpApp.textWelcome());
            t1 = uitab(app.TabGroup, 'Title', app.Tabs{2});
            app.TabHandles{2} = t1;
            app.addProcessTab(t1, HelpApp.textLDFExtract(), 'LDFExtractWorkflow.png', 'LDFExtractPrinciple.png');
            t2 = uitab(app.TabGroup, 'Title', app.Tabs{3});
            app.TabHandles{3} = t2;
            app.addProcessTab(t2, HelpApp.textLDFProcess(), 'LDFProcessWorkflow.png', 'LDFProcessPrinciple.png');
            t3 = uitab(app.TabGroup, 'Title', app.Tabs{4});
            app.TabHandles{4} = t3;
            app.addProcessTab(t3, HelpApp.textFiltering(), 'FilterWorkflow.png', 'FilterPrinciple.png', 'FilterHowItWorks.png');
            t4 = uitab(app.TabGroup, 'Title', app.Tabs{5});
            app.TabHandles{5} = t4;
            app.addProcessTab(t4, HelpApp.textLDFAverage(), 'LDFAverageWorkflow.png', 'LDFAveragePrinciple.png');
            t5 = uitab(app.TabGroup, 'Title', app.Tabs{6});
            app.TabHandles{6} = t5;
            app.addProcessTab(t5, HelpApp.textEphysExtract(), 'EphysExtractWorkflow.png', 'EphysExtractPrinciple.png');
            t6 = uitab(app.TabGroup, 'Title', app.Tabs{7});
            app.TabHandles{7} = t6;
            app.addProcessTab(t6, HelpApp.textLFPAnalysis(), 'LFPAnalysisWorkflow.png', 'LFPAnalysisPrinciple.png', 'LFPAnalysisCSD.png');
            t7 = uitab(app.TabGroup, 'Title', app.Tabs{8});
            app.TabHandles{8} = t7;
            app.addProcessTab(t7, HelpApp.textMUAAnalysis(), 'MUAAnalysisWorkflow.png', 'MUAAnalysisPrinciple.png');
            t8 = uitab(app.TabGroup, 'Title', app.Tabs{9});
            app.TabHandles{9} = t8;
            app.addProcessTab(t8, HelpApp.textROIAnalysis(), 'ROIAnalysisWorkflow.png', 'ROIAnalysisPrinciple.png');
            t9 = uitab(app.TabGroup, 'Title', app.Tabs{10});
            app.TabHandles{10} = t9;
            app.addProcessTab(t9, HelpApp.textSignalCharacterization(), 'SignalCharacterizationWorkflow.png', 'SignalCharacterizationPrinciple.png');
            % --- Fixed footer section for copyright ---
            footerPanel = uipanel(mainGrid, 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            footerGrid = uigridlayout(footerPanel, [1, 1], 'Padding', [12 4 12 4]);
            uihyperlink(footerGrid, 'Text', '© Copyrights by Alejandro Suarez, Ph.D.', ...
                'URL', 'https://github.com/alesuarez92', ...
                'FontSize', T.fontSmall, 'HorizontalAlignment', 'right', 'FontColor', T.mutedColor);
        end

        %% addScrollText - Add a read-only text area with wrapped text to a tab
        % -------------------------------------------------------------
        % parent = uitab; txt = cell array of strings (one per line).
        % -------------------------------------------------------------
        function addScrollText(app, parent, txt)
            grid = uigridlayout(parent, [1, 1], 'Padding', [8 8 8 8]);
            ta = uitextarea(grid, 'Value', txt, 'Editable', 'off', ...
                'WordWrap', 'on', 'FontSize', 11);
        end

        %% addProcessTab - Process tab: two columns – text left, images right
        % -------------------------------------------------------------
        % workflowFilename: flowchart. principleFilename: signal/concept diagram.
        % optionalMiddleFilename (e.g. FilterHowItWorks.png): extra image between workflow and principle.
        % -------------------------------------------------------------
        function addProcessTab(app, parent, textCell, workflowFilename, principleFilename, optionalMiddleFilename)
            if nargin < 6, optionalMiddleFilename = ''; end
            hasWorkflow = ~isempty(workflowFilename) && exist(app.getDocsPath(workflowFilename), 'file');
            hasMiddle = ~isempty(optionalMiddleFilename) && exist(app.getDocsPath(optionalMiddleFilename), 'file');
            grid = uigridlayout(parent, [1, 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', [8 8 8 8], 'ColumnSpacing', 12);
            uitextarea(grid, 'Value', textCell, 'Editable', 'off', ...
                'WordWrap', 'on', 'FontSize', 11);
            nRows = 1 + double(hasWorkflow) + double(hasMiddle);
            rowHeights = repmat({'1x'}, 1, nRows);
            rightCol = uigridlayout(grid, [nRows, 1], 'RowHeight', rowHeights, 'RowSpacing', 10);
            row = 0;
            if hasWorkflow
                row = row + 1;
                innerW = uigridlayout(rightCol, [1, 1]);
                uiimage(innerW, 'ImageSource', app.getDocsPath(workflowFilename));
            end
            if hasMiddle
                row = row + 1;
                innerM = uigridlayout(rightCol, [1, 1]);
                uiimage(innerM, 'ImageSource', app.getDocsPath(optionalMiddleFilename));
            end
            inner = uigridlayout(rightCol, [1, 1]);
            imgPath = app.getDocsPath(principleFilename);
            if exist(imgPath, 'file')
                uiimage(inner, 'ImageSource', imgPath);
            else
                uilabel(inner, 'Text', sprintf('(Diagram: docs/%s not found)', principleFilename), ...
                    'FontColor', [0.6 0.6 0.6]);
            end
        end
    end

    %% STATIC TEXT CONTENT - Each returns cell array of strings for uitextarea
    methods(Static)
        %% textWelcome - Overview of LDF and Ephys workflows and tab list
        function s = textWelcome()
            s = {
                'NeuroAnalyzer – NMD Lab'
                ''
                'This app supports two main workflows:'
                ''
                '  1. LDF (Laser Doppler Flowmetry): blood flow signals'
                '  2. Ephys (Electrophysiology): LFP and MUA from neural recordings'
                ''
                'Use the tabs above to read step-by-step help for each process.'
                ''
                '• LDF Extract: load and crop LDF export files'
                '• LDF Process: filter and segment by stimulus'
                '• Filtering: how low-pass, high-pass, and band-pass filters work'
                '• LDF Average: grand average across trials'
                '• Ephys Extract: load TDT data and extract LFP/MUA'
                '• LFP Analysis: ERP and CSD'
                '• MUA Analysis: spike sorting and rate'
                '• ROI Analysis: coregistered images, ROI/line, brightness, ΔF/F, speed, kymograph, vessel diameter'
                '• Signal Characterization: extract response features (peak latency, FWHM, AUC, etc.)'
                ''};
        end

        %% textROIAnalysis - Step-by-step for ROI / Coregistered Image Analysis
        function s = textROIAnalysis()
            s = {
                'ROI / Coregistered Image Analysis – Step by step'
                '================================================'
                ''
                'Use this tool for image stacks (time series of coregistered frames):'
                'blood flow, two-photon/multiphoton, fluorescence (e.g. gCaMP), vessel diameter.'
                ''
                '1. Load Stack'
                '   Load a .mat (variables: stack or frames; optional: timeVec, roiMask)'
                '   or a multi-frame TIFF. The stack can be grayscale (H×W×N) or RGB (H×W×3×N).'
                ''
                '2. Preprocessing (optional)'
                '   • B&W 256: convert to 256-level grayscale (for fluorescence intensity).'
                '   • Smooth: Gaussian smooth each frame.'
                '   • Normalize: normalize to 0–1 (per frame or overall).'
                ''
                '3. Define ROI or Line'
                '   • ROI: Click "Draw ROI" and draw a rectangle on the first frame.'
                '     Used for: Brightness, Movement, ΔF/F, Speed.'
                '   • Line: Click "Draw Line" and draw a line on the first frame.'
                '     Used for: Kymograph, Vessel diameter.'
                ''
                '4. Choose Analysis'
                '   • Brightness: mean intensity in ROI over time.'
                '   • Movement: frame-to-frame change (mean absolute difference) in ROI.'
                '   • Both: plot brightness and movement (two axes).'
                '   • ΔF/F (gCaMP): (F − F0)/F0 in ROI; baseline = first N frames.'
                '   • Speed (flow): flow/speed proxy in ROI (blood flow, 2P).'
                '   • Kymograph: space–time image along the line (propagation, flow direction).'
                '   • Vessel diameter: diameter over time from intensity profile along the line (FWHM).'
                ''
                '5. Compute & Plot'
                '   Click to run. Time series appear in the plot axes; for Kymograph,'
                '   a space–time image is shown. Export or use results for further analysis.'
                ''
                'Diagram (right): workflow and concepts (ROI intensity, kymograph, vessel diameter).'
                ''};
        end

        %% textSignalCharacterization - Step-by-step for Signal Characterization
        function s = textSignalCharacterization()
            s = {
                'Signal Characterization – Step by step'
                '======================================'
                ''
                '1. Load Data'
                '   Load processed data: LDF segments (segmentedLDF, segmentedTime),'
                '   ERP/average (t, lfp_data or t, y), or generic time series (t, y).'
                ''
                '2. Set Parameters'
                '   Stimulus onset t0 (s): time of stimulus in the trace.'
                '   Baseline window: e.g. 0 0.05 for 0 to 0.05 s (used for AUC and peak amplitude).'
                ''
                '3. Select Features'
                '   Multi-select the features to compute:'
                '   • Peak latency: time from t0 to peak'
                '   • Onset delay (50%): time to reach 50% of peak'
                '   • FWHM: full width at half maximum'
                '   • AUC positive / negative: area under curve above/below baseline'
                '   • Rise time: 10% to 90% of peak'
                '   • Decay time: peak to 50% return'
                '   • Peak amplitude: peak minus baseline'
                '   • Stim–response integral: integral of response after t0'
                ''
                '4. Extract Features'
                '   Click to compute; results appear in the table (per trial or channel).'
                ''
                '5. Export'
                '   Export table to CSV or .mat for further analysis.'
                ''};
        end

        %% textLDFExtract - Step-by-step for Extract LDF Data
        function s = textLDFExtract()
            s = {
                'Extract LDF Data – Step by step'
                '================================'
                ''
                '1. Load File'
                '   Click "Load File" and choose a .mat file in LDF export format'
                '   (containing data, datastart, dataend for channels).'
                ''
                '2. View'
                '   Stimulus (e.g. channel 6) and LDF (e.g. channel 8) are plotted.'
                ''
                '3. Select Range'
                '   Click "Select Range", then click two points on the stimulus plot'
                '   (start and end). Or type Start (s) and End (s) in the boxes.'
                ''
                '4. Crop & Plot'
                '   Click "Crop & Plot" to keep only that time range. A new figure'
                '   shows the cropped signals.'
                ''
                '5. Save Cropped'
                '   Save the cropped stim, LDF, time vector, and sampling rate to .mat.'
                ''};
        end

        %% textLDFProcess - Step-by-step for Process LDF Data (filter, segment)
        function s = textLDFProcess()
            s = {
                'Process LDF Data – Step by step'
                '================================='
                ''
                '1. Load a file (raw or cropped LDF + stimulus).'
                ''
                '2. Set Processing'
                '   Open "Set Processing" to choose:'
                '   • Downsample: 1x, 2x, 5x, or 10x'
                '   • Filter type: None, Low-pass, High-pass, Band-pass, or Notch'
                '   • Design: Butterworth, Chebyshev I, or FIR'
                '   • Cutoff frequencies (Hz) and filter order'
                '   See the "Filtering" tab for how filter types work.'
                ''
                '3. Apply Filter'
                '   Apply the filter to the LDF signal.'
                ''
                '4. Segment by Onsets'
                '   Optionally segment trials around stimulus onsets.'
                ''
                '5. Plot / Save'
                '   View segments or average; save segmented data for the'
                '   Average LDF Viewer.'
                ''};
        end

        %% textFiltering - How low-pass, high-pass, band-pass, notch work; order; Nyquist
        function s = textFiltering()
            s = {
                'How digital filters work'
                '========================='
                ''
                'Filters remove or keep certain frequencies in a signal:'
                ''
                '• LOW-PASS: Keeps low frequencies, removes high (e.g. smooths noise).'
                '  Use one cutoff (high). Frequencies above it are attenuated.'
                ''
                '• HIGH-PASS: Removes low frequencies, keeps high (e.g. remove drift).'
                '  Use one cutoff (low). Frequencies below it are attenuated.'
                ''
                '• BAND-PASS: Keeps a band of frequencies between low and high cutoffs.'
                '  Use two cutoffs. Useful for isolating a frequency band (e.g. 0.5–5 Hz for LDF).'
                ''
                '• NOTCH: Removes a narrow band (e.g. 50/60 Hz line noise).'
                ''
                'Order: higher order = steeper roll-off and sharper cutoffs.'
                'Cutoffs must be below Nyquist (half the sampling rate).'
                ''
                'Diagram below: frequency response (gain vs frequency) for each type.'
                ''};
        end

        %% textLDFAverage - Step-by-step for Average LDF Viewer
        function s = textLDFAverage()
            s = {
                'Average LDF Viewer – Step by step'
                '=================================='
                ''
                '1. Load Segmented Files'
                '   Load one or more .mat files that contain segmented LDF trials'
                '   (from Process LDF Data).'
                ''
                '2. Plot Grand Average'
                '   Click "Plot Grand Average" to see mean ± SD across trials.'
                ''
                '3. Relative to Baseline'
                '   Optionally express the trace relative to a pre-stimulus baseline.'
                ''};
        end

        %% textEphysExtract - Step-by-step for Extract Ephys (TDT, LFP, MUA)
        function s = textEphysExtract()
            s = {
                'Extract Ephys Data – Step by step'
                '=================================='
                ''
                '1. Load TDT Folder'
                '   Click "Load TDT Folder" and select your TDT tank/block folder.'
                ''
                '2. Select Channels'
                '   Choose the stimulus (Whis) channel and the raw (xRAW) channels'
                '   to use.'
                ''
                '3. Plot RAW'
                '   View raw traces if needed.'
                ''
                '4. Process LFP'
                '   Extract and filter for LFP; then "Save LFP Data".'
                ''
                '5. Process MUA'
                '   Extract and filter for MUA; then "Save MUA Data".'
                ''
                'Saved files can be opened in "Process LFP Data" and "Process MUA Data".'
                ''};
        end

        %% textLFPAnalysis - Step-by-step for Process LFP (ERP, CSD)
        function s = textLFPAnalysis()
            s = {
                'Process LFP Data – Step by step'
                '================================'
                ''
                '1. Load LFP Data'
                '   Load a file previously saved from Extract Ephys (LFP).'
                ''
                '2. Select Channels'
                '   Choose which channels to include in the analysis.'
                ''
                '3. ERP Analysis'
                '   Configure the ERP window (time range, baseline) and run.'
                '   Event-related potentials are averaged across trials.'
                ''
                '4. CSD Analysis'
                '   Run current source density (CSD) to visualize current flow'
                '   across channels (e.g. along a linear probe).'
                ''
                'Diagram (right): workflow, CSD explanation (sources/sinks, depth), and principle.'
                ''};
        end

        %% textMUAAnalysis - Step-by-step for Process MUA (spike sort, rate)
        function s = textMUAAnalysis()
            s = {
                'Process MUA Data – Step by step'
                '================================='
                ''
                '1. Load Data'
                '   Load MUA data saved from Extract Ephys.'
                ''
                '2. Select Channel'
                '   Choose the channel to analyze.'
                ''
                '3. Segment (optional)'
                '   Enable "Segment by stimulation onsets" to split into trials.'
                ''
                '4. Spike Sorting'
                '   Configure detection (threshold, polarity) and clustering'
                '   (method, number of clusters). Run to get spike times and'
                '   cluster assignments.'
                ''
                '5. Spike Rate'
                '   View spike rate over time or per segment (e.g. PSTH-style).'
                ''
                'Detection and sorting methods (see diagram below)'
                '--------------------------------------------------'
                ''
                'Detection: Spikes are detected when the (optionally filtered) signal'
                'crosses a threshold. Threshold can be set as a multiplier of'
                'standard deviation or MAD (e.g. 3.5×). Polarity: positive,'
                'negative, or both. Methods: Standard, NEO, Rolling MAD, or'
                'Percentile. A refractory period (ms) avoids double-counting.'
                ''
                'Sorting: For each detected spike, a waveform snippet is extracted.'
                'Features are computed (PCA, ICA, waveform, wavelet, or t-SNE).'
                'Clustering assigns spikes to units: K-means (fixed number of'
                'clusters), GMM (Gaussian mixture), or DBSCAN (density-based,'
                'epsilon parameter). Result: spike times and cluster ID per spike.'
                ''};
        end
    end
end
