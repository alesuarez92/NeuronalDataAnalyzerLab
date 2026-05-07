%% MUAAnalysisApp.m
% =========================================================================
% PROCESS MUA DATA - LOAD MUA, SEGMENT BY STIMULUS, SPIKE SORTING, SPIKE RATE
% =========================================================================
% Launched from Main. Loads .mat saved from ExtractEphysApp (MUA data).
% User selects channel, optionally segments by stimulation onsets. Spike
% Sorting: configure detection (threshold, polarity) and clustering (K-means,
% DBSCAN, etc.), run to get spike times and cluster IDs. Can view cluster
% waveforms, alignment diagnostics, and spike rate over time (PSTH-style).
% Large file: key methods include loadData, updateMUAPlot, configureSpikeSorting,
% runSpikeSorting, and spike rate plotting.
% =========================================================================

classdef MUAAnalysisApp < handle
    %% PROPERTIES: UI (ControlPanel, axes, buttons, menus), MUA/Stim data, Segments, SpikeSort params/results
    properties
        UIFig
        ControlPanel
        AxStim
        AxMUA
        LoadBtn
        StatusLabel
        FileLabel
        ChannelMenu
        ChannelLabel
        SegmentCheckbox
        SegmentMenu
        MUAData
        StimData
        Segments
        SegmentParams
        SpikeSortParams % NEW: Holds spike sorting parameters
        SpikeResults % NEW: Holds spike times and cluster results
        ProgressLabel
        ClusterSelectMenu
        SelectAllBtn
        ClearBtn
        SpikeRateButton
    end

    methods
        %% Constructor - Build UI; data loaded via Load Data
        function app = MUAAnalysisApp()
            app.buildUI();
        end

        %% buildUI - Fixed footer, compact controls, graphs get most of the space
        function buildUI(app)
            T = UITheme;
            figW = 1120;
            figH = 920;
            ss = get(0, 'ScreenSize');
            figLeft = max(10, round((ss(3) - figW) / 2));
            figBottom = max(10, round((ss(4) - figH) / 2));
            app.UIFig = figure('Name', 'MUA Analysis', ...
                'Position', [figLeft figBottom figW figH], 'Resize', 'on', ...
                'Color', T.bgGray);

            % === HEADER: full-width (covers upper part completely) ===
            headerH = 0.065;
            headerPanel = uipanel(app.UIFig, 'Units', 'normalized', ...
                'Position', [0 1-headerH 1 headerH], 'BorderType', 'none', ...
                'BackgroundColor', T.headerBg);
            uicontrol(headerPanel, 'Style', 'text', 'String', 'MUA Analysis', ...
                'Units', 'normalized', 'Position', [0.02 0.45 0.4 0.45], ...
                'FontSize', 18, 'FontWeight', 'bold', 'ForegroundColor', T.headerTitleColor, ...
                'BackgroundColor', T.headerBg, 'HorizontalAlignment', 'left');
            uicontrol(headerPanel, 'Style', 'text', 'String', 'Spike sorting and rate', ...
                'Units', 'normalized', 'Position', [0.02 0.05 0.4 0.4], ...
                'FontSize', T.fontSubtitle, 'ForegroundColor', T.headerSubtitleColor, ...
                'BackgroundColor', T.headerBg, 'HorizontalAlignment', 'left');

            % === FIXED FOOTER (copyright only) ===
            footerH = 0.06;
            footerPanel = uipanel(app.UIFig, 'Units', 'normalized', ...
                'Position', [0 0 1 footerH], 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            uicontrol(footerPanel, 'Style', 'pushbutton', 'String', '© Copyrights by Alejandro Suarez, Ph.D.', ...
                'Units', 'normalized', 'Position', [0.45 0.1 0.54 0.8], ...
                'HorizontalAlignment', 'right', 'FontSize', T.fontSmall, 'ForegroundColor', [0.1 0.4 0.7], ...
                'BackgroundColor', T.bgGray, 'Callback', @(~,~)web('https://github.com/alesuarez92', '-browser'));

            % === FIXED CONTROLS PANEL (below header) ===
            panelTop = 1 - headerH - 0.01;
            panelH = 0.24;
            app.ControlPanel = uipanel(app.UIFig, 'Title', 'Controls', ...
                'Units', 'normalized', 'Position', [0.012 panelTop - panelH 0.976 panelH], ...
                'BackgroundColor', T.cardBg, 'HighlightColor', T.cardBorder, 'FontSize', T.fontSmall);

            % Compact row heights; small buttons so panel stays short
            app.LoadBtn = uicontrol(app.ControlPanel, 'Style', 'pushbutton', ...
                'String', 'Load Data', 'Units', 'normalized', ...
                'Position', [0.02 0.72 0.16 0.22], 'FontSize', T.fontSmall, ...
                'Callback', @(~,~)app.loadData());
            app.StatusLabel = uicontrol(app.ControlPanel, 'Style', 'text', ...
                'String', '', 'Units', 'normalized', ...
                'Position', [0.02 0.58 0.26 0.12], 'FontSize', T.fontSmall, ...
                'HorizontalAlignment', 'left', 'ForegroundColor', 'blue');
            app.FileLabel = uicontrol(app.ControlPanel, 'Style', 'text', ...
                'String', 'No file loaded', 'Units', 'normalized', ...
                'Position', [0.02 0.46 0.26 0.10], 'FontSize', T.fontSmall, ...
                'HorizontalAlignment', 'left');
            uicontrol(app.ControlPanel, 'Style', 'text', 'String', 'Select Channel:', ...
                'Units', 'normalized', 'Position', [0.02 0.36 0.12 0.08], 'FontSize', T.fontSmall, ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'left');
            app.ChannelMenu = uicontrol(app.ControlPanel, 'Style', 'popupmenu', ...
                'String', {'-'}, 'Units', 'normalized', ...
                'Position', [0.02 0.24 0.18 0.10], 'FontSize', T.fontSmall, ...
                'Enable', 'off', 'Callback', @(~,~)app.updateMUAPlot());
            app.SegmentCheckbox = uicontrol(app.ControlPanel, 'Style', 'checkbox', ...
                'String', 'Segment by stimulation onsets', 'Units', 'normalized', ...
                'Position', [0.02 0.08 0.22 0.14], 'FontSize', T.fontSmall, 'FontWeight', 'bold', ...
                'Callback', @(~,~)app.handleSegmentationToggle());
            app.SegmentMenu = uicontrol(app.ControlPanel, 'Style', 'popupmenu', ...
                'String', {'-'}, 'Units', 'normalized', ...
                'Position', [0.02 0.01 0.14 0.06], 'FontSize', T.fontSmall, ...
                'Enable', 'off', 'Callback', @(~,~)app.updateMUAPlot());

            uicontrol(app.ControlPanel, 'Style', 'pushbutton', 'String', 'Spike Sorting', ...
                'Units', 'normalized', 'Position', [0.30 0.72 0.16 0.22], 'FontSize', T.fontSmall, ...
                'Callback', @(~,~)app.configureSpikeSorting());
            uicontrol(app.ControlPanel, 'Style', 'text', 'String', 'Status:', ...
                'Units', 'normalized', 'Position', [0.50 0.78 0.06 0.08], 'FontSize', T.fontSmall, ...
                'HorizontalAlignment', 'left');
            app.ProgressLabel = uicontrol(app.ControlPanel, 'Style', 'text', ...
                'String', '', 'Units', 'normalized', 'Enable', 'off', ...
                'Position', [0.56 0.78 0.38 0.08], 'FontSize', T.fontSmall, ...
                'HorizontalAlignment', 'left', 'ForegroundColor', [0.1 0.5 0.1], 'FontWeight', 'bold');
            uicontrol(app.ControlPanel, 'Style', 'pushbutton', 'String', 'Check Alignment', ...
                'Units', 'normalized', 'Position', [0.30 0.48 0.18 0.20], 'FontSize', T.fontSmall, ...
                'Callback', @(~,~)app.plotAlignmentDiagnostics());
            app.SpikeRateButton = uicontrol(app.ControlPanel, 'Style', 'pushbutton', ...
                'String', 'Plot Spike Rate', 'Units', 'normalized', ...
                'Position', [0.30 0.24 0.18 0.20], 'FontSize', T.fontSmall, ...
                'Callback', @(src, event) app.plotSpikeRateOverTime());

            uicontrol(app.ControlPanel, 'Style', 'text', 'String', 'Clusters:', ...
                'Units', 'normalized', 'Position', [0.68 0.88 0.10 0.08], 'FontSize', T.fontSmall, ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'left');
            app.ClusterSelectMenu = uicontrol(app.ControlPanel, 'Style', 'listbox', ...
                'Units', 'normalized', 'Position', [0.68 0.22 0.26 0.64], ...
                'Max', 2, 'Min', 0, 'String', {}, 'FontSize', T.fontSmall, ...
                'TooltipString', 'Use Ctrl/Shift to select multiple clusters', ...
                'Callback', @(src, ~)app.updateClusterScatter());
            app.SelectAllBtn = uicontrol(app.ControlPanel, 'Style', 'pushbutton', 'String', 'Select All', ...
                'Units', 'normalized', 'Position', [0.68 0.08 0.12 0.12], 'FontSize', T.fontSmall, ...
                'Callback', @(~,~)selectAllClusters(app));
            app.ClearBtn = uicontrol(app.ControlPanel, 'Style', 'pushbutton', 'String', 'Clear', ...
                'Units', 'normalized', 'Position', [0.82 0.08 0.12 0.12], 'FontSize', T.fontSmall, ...
                'Callback', @(~,~)clearClusterSelection(app));

            % === GRAPHS SECTION: between footer and controls; margin so titles not clipped ===
            graphBottom = footerH + 0.02;
            graphTop = panelTop - panelH - 0.01;
            graphH = graphTop - graphBottom;
            axGap = 0.015;
            axStimH = graphH * 0.18;
            axMuaH = graphH - axStimH - axGap;
            muaBottom = graphBottom;
            stimBottom = muaBottom + axMuaH + axGap;
            % Leave small top margin in each axis so title text is not clipped
            titleMargin = 0.02;
            app.AxStim = axes('Parent', app.UIFig, 'Units', 'normalized', ...
                'Position', [0.07 stimBottom + titleMargin*0.5 0.86 axStimH - titleMargin]);
            title(app.AxStim, 'Stimulation Signal');
            ylabel(app.AxStim, 'Amplitude');
            set(app.AxStim, 'XTickLabel', []);
            app.AxMUA = axes('Parent', app.UIFig, 'Units', 'normalized', ...
                'Position', [0.07 muaBottom 0.86 axMuaH - titleMargin]);
            title(app.AxMUA, 'MUA Signal');
            xlabel(app.AxMUA, 'Time (s)');
            ylabel(app.AxMUA, 'Amplitude');
        end


        function loadData(app)
            uistack(app.UIFig, 'bottom');
            drawnow;
            [file, path] = uigetfile('*.mat', 'Select MUA Data File');
            figure(app.UIFig);
            if isequal(file, 0)
                app.StatusLabel.String = 'Loading cancelled.';
                app.StatusLabel.ForegroundColor = 'red';
                return;
            end

            app.StatusLabel.String = 'Loading data... please wait';
            app.StatusLabel.ForegroundColor = 'blue';
            drawnow;

            try
                data = load(fullfile(path, file));

                app.MUAData.data = data.mua_data;
                app.MUAData.fs = data.mua_fs;
                app.MUAData.time = data.t_mua;
                app.MUAData.channels = data.mua_channels;

                if isfield(data, 'stim_data') && isfield(data, 'stim_fs') && isfield(data, 't_stim')
                    app.StimData.signal = data.stim_data;
                    app.StimData.fs = data.stim_fs;
                    app.StimData.time = data.t_stim;

                    plot(app.AxStim, app.StimData.time, app.StimData.signal);
                    title(app.AxStim, 'Stimulation Signal');
                else
                    cla(app.AxStim);
                    title(app.AxStim, 'No Stimulation Data');
                end

                cla(app.AxMUA);
                plot(app.AxMUA, app.MUAData.time, app.MUAData.data(1,:),'k');
                title(app.AxMUA, sprintf('MUA Signal - Channel %d', app.MUAData.channels(1)));

                chNames = compose('Ch %d', app.MUAData.channels);
                app.ChannelMenu.String = chNames;
                app.ChannelMenu.Value = 1;
                app.ChannelMenu.Enable = 'on';

                app.StatusLabel.String = 'Data loaded successfully.';
                app.StatusLabel.ForegroundColor = [0.1 0.5 0.1];
                app.ProgressLabel.String = 'Ready';
                set(app.ProgressLabel,'Enable','on')
                app.FileLabel.String = sprintf('Loaded file: %s', file);

            catch ME
                app.StatusLabel.String = sprintf('Error loading data: %s', ME.message);
                app.StatusLabel.ForegroundColor = 'red';
            end
        end

        function handleSegmentationToggle(app)
            if app.SegmentCheckbox.Value
                prompt = {'Minimum ISI (s):', 'Threshold:', 'Pre-stim time (s):', 'Post-stim time (s):'};
                dlgtitle = 'Stimulation Onset Detection Parameters';
                dims = [1 35];
                definput = {'1', '0.5', '0.5', '1.0'};
                answer = inputdlg(prompt, dlgtitle, dims, definput);
                if isempty(answer)
                    app.SegmentCheckbox.Value = 0;
                    return;
                end
                minISI = str2double(answer{1});
                threshold = str2double(answer{2});
                preTime = str2double(answer{3});
                postTime = str2double(answer{4});
                stim = app.StimData.signal;
                t = app.StimData.time;
                aboveThresh = stim > threshold;
                onsetIdx = find(diff([0; aboveThresh(:)]) == 1);
                onsetTimes = t(onsetIdx(:));
                if isempty(onsetTimes), app.Segments = []; return; end
                isi = [Inf; diff(onsetTimes(:))];
                onsetTimes = onsetTimes(isi > minISI);
                segs = [onsetTimes' - preTime, onsetTimes' + postTime];
                app.Segments = segs;
                app.SegmentParams = struct('minISI', minISI, 'threshold', threshold, 'preTime', preTime, 'postTime', postTime);
                segNames = arrayfun(@(i) sprintf('Segment %d', i), 1:size(segs,1), 'UniformOutput', false);
                app.SegmentMenu.String = segNames;
                app.SegmentMenu.Value = 1;
                app.SegmentMenu.Enable = 'on';
                app.updateMUAPlot();
            else
                app.SegmentMenu.Enable = 'off';
                app.Segments = [];
                app.updateMUAPlot();
            end
        end

        function updateMUAPlot(app)
            if isempty(app.MUAData), return; end
            chIdx = app.ChannelMenu.Value;

            % Always plot full stimulus trace
            cla(app.AxStim);
            plot(app.AxStim, app.StimData.time, app.StimData.signal);
            title(app.AxStim, 'Stimulation Signal');
            ylabel(app.AxStim, 'Amplitude');
            set(app.AxStim, 'XTickLabel', []);

            if app.SegmentCheckbox.Value && ~isempty(app.Segments)
                hold(app.AxStim, 'on');
                yLims = ylim(app.AxStim);
                segIdx = app.SegmentMenu.Value;
                for i = 1:size(app.Segments,1)
                    segX = app.Segments(i,:);
                    color = [0.7 0.7 0.7];
                    if i == segIdx
                        color = [1 0.6 0.6];
                    end
                    fill(app.AxStim, [segX(1) segX(2) segX(2) segX(1)],...
                        [yLims(1) yLims(1) yLims(2) yLims(2)], color, ...
                        'FaceAlpha', 0.3, 'EdgeColor', 'none');
                end
                hold(app.AxStim, 'off');

                % Plot only selected MUA segment, stretched to full plot width
                seg = app.Segments(segIdx, :);
                idxRange = app.MUAData.time >= seg(1) & app.MUAData.time <= seg(2);
                segTime = app.MUAData.time(idxRange);
                segTime = segTime - segTime(1);
                cla(app.AxMUA);
                plot(app.AxMUA, segTime, app.MUAData.data(chIdx, idxRange),'k');
                title(app.AxMUA, sprintf('Segment %d - Channel %d', segIdx, app.MUAData.channels(chIdx)));
                xlabel(app.AxMUA, 'Time from Stim (s)'); ylabel(app.AxMUA, 'Amplitude');
            else
                cla(app.AxMUA);
                plot(app.AxMUA, app.MUAData.time, app.MUAData.data(chIdx, :),'k');
                title(app.AxMUA, sprintf('MUA Signal - Channel %d', app.MUAData.channels(chIdx)));
                xlabel(app.AxMUA, 'Time (s)'); ylabel(app.AxMUA, 'Amplitude');
            end
        end

        function configureSpikeSorting(app)
            d = dialog('Name', 'Spike Sorting Configuration', 'Position', [300 200 420 500]);

            uicontrol(d, 'Style', 'text', 'Position', [20 450 200 20], 'String', 'Detection Method:');
            detectMethodPopup = uicontrol(d, 'Style', 'popupmenu', ...
                    'Position', [220 450 120 25], ...
                    'String', {'Standard', 'MAD', 'NEO', 'Rolling MAD', 'Percentile'}, ...
                    'Value', 1);

            % Threshold multiplier
            uicontrol(d, 'Style', 'text', 'Position', [20 420 200 20], 'String', 'Threshold Multiplier (e.g. 3.5):');
            thresholdBox = uicontrol(d, 'Style', 'edit', 'Position', [230 420 100 25], 'String', '3.5');

            % Refractory period
            uicontrol(d, 'Style', 'text', 'Position', [20 390 200 20], 'String', 'Refractory Period (ms):');
            refractoryBox = uicontrol(d, 'Style', 'edit', 'Position', [230 390 100 25], 'String', '1.0');

            % Alignment window
            uicontrol(d, 'Style', 'text', 'Position', [20 360 200 20], 'String', 'Alignment Window (ms):');
            alignBox = uicontrol(d, 'Style', 'edit', 'Position', [230 360 100 25], 'String', '1.5');

            % Polarity
            uicontrol(d, 'Style', 'text', 'Position', [20 330 200 20], 'String', 'Polarity:');
            polarityPopup = uicontrol(d, 'Style', 'popupmenu', 'Position', [230 330 100 25], ...
                'String', {'positive','negative', 'both'});

            % Filter before detection
            filterCheckbox = uicontrol(d, 'Style', 'checkbox', 'Position', [20 290 300 25], ...
                'String', 'Filter before detection?', 'Value', 0,...
                'Callback', @(src,~)toggleFilter());

            % Bandpass range
            uicontrol(d, 'Style', 'text', 'Position', [180 300 200 20], 'String', 'Bandpass Range (Hz):');
            bandpassLow = uicontrol(d, 'Style', 'edit', 'Position', [230 280 45 25], 'String', '300', 'Enable', 'off');
            bandpassHigh = uicontrol(d, 'Style', 'edit', 'Position', [285 280 45 25], 'String', '3000', 'Enable', 'off');


            % Enable/disable logic
            function toggleFilter()
                if filterCheckbox.Value
                    set([bandpassLow,bandpassHigh], 'Enable', 'on');
                else
                    set([bandpassLow,bandpassHigh], 'Enable', 'off');
                end
            end

            % Feature extraction method
            uicontrol(d, 'Style', 'text', 'Position', [20 240 200 20], 'String', 'Feature Extraction Method:');
            featurePopup = uicontrol(d, 'Style', 'popupmenu', 'Position', [220 240 120 25], ...
                'String', {'PCA', 'ICA', 'Waveform', 'Wavelet', 't-SNE'});

            % Number of components
            uicontrol(d, 'Style', 'text', 'Position', [20 210 200 20], 'String', '# of Components:');
            compBox = uicontrol(d, 'Style', 'edit', 'Position', [230 210 100 25], 'String', '3');

            % Normalize features (z-score) before clustering
            normCheckbox = uicontrol(d, 'Style', 'checkbox', 'Position', [20 180 220 22], ...
                'String', 'Normalize features?', 'Value', 1);

            % --- Clustering method dropdown ---
            uicontrol(d, 'Style', 'text', 'Position', [20 170 200 20], 'String', 'Clustering Method:');
            clusterPopup = uicontrol(d, 'Style', 'popupmenu', ...
                'Position', [230 170 100 25], ...
                'String', {'K-means', 'GMM', 'DBSCAN'}, ...
                'Callback', @(src,~) toggleEpsilonBox());  % assign callback AFTER definition

            % --- DBSCAN epsilon input ---
            uicontrol(d, 'Style', 'text', 'Position', [20 150 200 20], ...
                'String', 'DBSCAN Epsilon (optional):', 'Tag', 'EpsLabel');
            dbscanEpsBox = uicontrol(d, 'Style', 'edit', 'Position', [230 150 60 20], ...
                'String', '', 'Enable', 'off', 'Tag', 'EpsBox');

            % --- Toggle epsilon field visibility ---
            function toggleEpsilonBox()
                isDBSCAN = strcmp(clusterPopup.String{clusterPopup.Value}, 'DBSCAN');
                set(findobj(d, 'Tag', 'EpsBox'), 'Enable', ternary(isDBSCAN, 'on', 'off'));
                set(findobj(d, 'Tag', 'EpsLabel'), 'Enable', ternary(isDBSCAN, 'on', 'off'));
            end
            function val = ternary(cond, a, b)
                if cond
                    val = a;
                else
                    val = b;
                end
            end

            % Minimum spikes per cluster
            uicontrol(d, 'Style', 'text', 'Position', [20 120 200 20], 'String', 'Minimum Spikes per Cluster:');
            minSpikesBox = uicontrol(d, 'Style', 'edit', 'Position', [230 120 100 25], 'String', '20');

            % Drift Correction Controls
            driftCheck = uicontrol(d, 'Style', 'checkbox', 'Position', [20 80 100 20],...
                'String', 'Drift Correction?',...
                'Value', 0, ...
                'Callback', @(src,~) toggleDrift());

            driftMethodPopup = uicontrol(d, 'Style', 'popupmenu', ...
                'Position', [210 75 140 25], ...
                'String', {'Time Binning','Dynamic Clustering'}, ...
                'Enable', 'off',...
                'Callback', @(src,~) toggleDriftOptions());

            uicontrol(d, 'Style', 'text', 'Position', [30 50 100 20], ...
                'String', 'Bin Width (s):');

            driftBinBox = uicontrol(d, 'Style', 'edit', ...
                'Position', [120 50 50 25], 'String', '30', ...
                'Enable', 'off');

            % Drift Correction Controls
            GridSearchCheck = uicontrol(d, 'Style', 'checkbox', 'Position', [200 50 180 20],...
                'String', 'Optimize thresh (Grid search)',...
                'Value', 0);


            % Enable/disable logic
            function toggleDrift()
                if driftCheck.Value
                    set([driftMethodPopup,driftBinBox,GridSearchCheck], 'Enable', 'on');

                else
                    set([driftMethodPopup,driftBinBox,GridSearchCheck], 'Enable', 'off');
                end
            end

            function toggleDriftOptions()
                if  driftMethodPopup.Value
                    if driftMethodPopup.String(driftMethodPopup.Value) == "Time Binning"
                        set(driftBinBox, 'Enable', 'on');
                        set(GridSearchCheck,'Enable', 'on');
                    elseif driftMethodPopup.String(driftMethodPopup.Value) == "Dynamic Clustering"
                        set(driftBinBox, 'Enable', 'off');
                        set(GridSearchCheck,'Enable', 'off');
                    end
                end
            end

            % Confirm button
            uicontrol(d, 'Style', 'pushbutton', 'String', 'Run Detection', ...
                'Position', [150 10 100 30], ...
                'Callback', @(~,~)submitAndClose());
        
            function submitAndClose()
                params = struct();
                params.detectMethod = detectMethodPopup.String{detectMethodPopup.Value};
                params.clusterMethod = clusterPopup.String{clusterPopup.Value};
                params.threshold = str2double(thresholdBox.String);
                params.refractoryMs = str2double(refractoryBox.String);
                params.alignWinMs = str2double(alignBox.String);
                params.polarity = polarityPopup.String{polarityPopup.Value};
                params.filter = filterCheckbox.Value;
                params.bpLow = str2double(bandpassLow.String);
                params.bpHigh = str2double(bandpassHigh.String);
                params.featureMethod = featurePopup.String{featurePopup.Value};
                params.numComponents = str2double(compBox.String);
                params.normalize = normCheckbox.Value;
                params.minSpikesPerCluster = str2double(minSpikesBox.String);
                params.enableDriftCorrection = driftCheck.Value;
                params.driftMethod = driftMethodPopup.String{driftMethodPopup.Value};
                params.driftBinWidth = str2double(driftBinBox.String);
                params.enableGridSearchCheck = GridSearchCheck.Value;
                epsStr = strtrim(dbscanEpsBox.String);
                if isempty(epsStr)
                    params.dbscanEpsilon = NaN;  % auto-tune
                else
                    params.dbscanEpsilon = str2double(epsStr);
                end
                disp(params);
                delete(d);
                app.runSpikeSorting(params);
                
            end
            
        end

        function runSpikeSorting(app, params)
            % Update status <<<<<<<<<<<<<<<<<<<
            app.ProgressLabel.String = 'Starting spike detection...';
            drawnow;
            % <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
            
            app.SpikeSortParams = params;
            chIdx = app.ChannelMenu.Value;

            % Extract data (either full trace or segmented portion)
            if app.SegmentCheckbox.Value && ~isempty(app.Segments)
                segIdx = app.SegmentMenu.Value;
                tAll = app.MUAData.time;
                xAll = app.MUAData.data(chIdx, :);
                seg = app.Segments(segIdx, :);
                idxRange = tAll >= seg(1) & tAll <= seg(2);
                t = tAll(idxRange);
                x = xAll(idxRange);
                app.SpikeResults.segmentedMUA = x;
                app.SpikeResults.segmentedTime = t;
            else
                t = app.MUAData.time;
                x = app.MUAData.data(chIdx, :);
                tAll = t;
                xAll = x;
                app.SpikeResults.segmentedMUA = x;
                app.SpikeResults.segmentedTime = t;    
            end
        
            fs = app.MUAData.fs;
        
            % --- Spike detection based on method and polarity ---
            refracSamples = round(params.refractoryMs / 1000 * fs);
            polarityFactor = 1;  % default
            
            %% Spike detection
            % Step 1: Preprocess signal based on detection method
            % Update status <<<<<<<<<<<<<<<<<<<
            app.ProgressLabel.String = sprintf('Detecting spikes using %s...', params.detectMethod);
            drawnow;
            % <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
            switch lower(params.detectMethod)
                case 'neo'
                    % Nonlinear Energy Operator: Ψ[x(t)] = x(t)^2 - x(t-1)*x(t+1)
                    xProc = x;
                    xProc = (xProc - min(xProc)) / (max(xProc) - min(xProc));  % normalize to [0,1]
                    %xProc = [0 diff(xProc)].^2 - [0 xProc(1:end-1)].*[xProc(2:end) 0];
                    med = median(xProc);
                    mad = 1.4826 * median(abs(xProc - med));
                    baseThresh = med + params.threshold * mad;
                    %baseThresh = mean(xProc) + params.threshold * std(xProc);
            
                case 'mad'
                    % Global MAD threshold (median + threshold * 1.4826*MAD), like OLD threshold method
                    xProc = x;
                    med = median(xProc);
                    mad_val = 1.4826 * median(abs(xProc - med));
                    baseThresh = med + params.threshold * mad_val;
            
                case 'rolling mad'
                    med = median(x);
                    mad = 1.4826 * median(abs(x - med));
                    baseThresh = med + params.threshold * mad;
                    xProc = x;
            
                case 'percentile'
                    xProc = x;
                    baseThresh = prctile(abs(xProc), 99.9);  % 99.9th percentile
            
                otherwise  % 'standard'                    
                    baseThresh = mean(x) + params.threshold * std(x);
                    xProc = x;
            end
            
            % Step 2: Polarity control
            switch lower(params.polarity)
                case 'negative'
                    dataToSearch = -xProc;
                    threshVal = baseThresh;
                    polarityFactor = -1;
            
                case 'positive'
                    dataToSearch = xProc;
                    threshVal = baseThresh;
                    polarityFactor = 1;
            
                case 'both'
                    if strcmpi(params.detectMethod, 'rolling mad')
                        warning('Polarity="both" not supported with Rolling MAD. Using standard threshold.');
                        threshValPos = mean(x) + params.threshold * std(x);
                        threshValNeg = -threshValPos;
                    elseif strcmpi(params.detectMethod, 'mad')
                        med = median(x);
                        mad_val = 1.4826 * median(abs(x - med));
                        threshValPos = med + params.threshold * mad_val;
                        threshValNeg = med - params.threshold * mad_val;
                    elseif strcmpi(params.detectMethod, 'percentile')
                        threshValPos = baseThresh;
                        threshValNeg = -baseThresh;
                    elseif strcmpi(params.detectMethod, 'neo')
                        threshValPos = baseThresh;
                        threshValNeg = baseThresh;  % NEO is symmetric
                    else
                        threshValPos = mean(x) + params.threshold * std(x);
                        threshValNeg = -threshValPos;
                    end
            
                    [~, posLocs] = findpeaks(x, 'MinPeakHeight', threshValPos, ...
                        'MinPeakDistance', refracSamples);
                    [~, negLocs] = findpeaks(-x, 'MinPeakHeight', -threshValNeg, ...
                        'MinPeakDistance', refracSamples);
            
                    locs = sort([posLocs(:); negLocs(:)]);
                    spikeTimes = t(locs);
            
                    fprintf('[Detection] BOTH polarity | spikes: %d\n', numel(locs));
                    return;
            end
            
            % Step 3: Detect spikes
            if strcmpi(params.detectMethod, 'rolling mad')
                initialIdx = find(dataToSearch > baseThresh);
                locs = [];
                last = -Inf;
                searchWindow = round(0.5 * fs / 1000 * params.alignWinMs);  % 0.5 ms in samples
                
                for i = 1:length(initialIdx)
                    if initialIdx(i) - last > refracSamples
                        winStart = max(1, initialIdx(i) - searchWindow);
                        winEnd = min(length(dataToSearch), initialIdx(i) + searchWindow);
                        [~, peakRel] = max(dataToSearch(winStart:winEnd));
                        locs(end+1,1) = winStart + peakRel - 1;
                        last = locs(end);
                    end
                end
            else
                % Global threshold
                [~, locs] = findpeaks(dataToSearch, 'MinPeakHeight', baseThresh, ...
                    'MinPeakDistance', refracSamples);
            end
            
            spikeTimes = t(locs);

            fprintf('[Detection] Method: %s | Polarity: %s | Spikes: %d\n', ...
                lower(params.detectMethod), lower(params.polarity), numel(locs));
        
            % Exit if no spikes or too few
            if isempty(locs)
                errordlg('No spikes detected with the current threshold.', 'Detection Error');
                return;
            end
            if numel(spikeTimes) < params.minSpikesPerCluster * 2
                errordlg('Too few spikes for clustering.', 'Clustering Error');
                return;
            end
        
            %% Align waveforms around spike locations
            % Update status <<<<<<<<<<<<<<<<<<<
            app.ProgressLabel.String = 'Aligning waveforms...';
            drawnow;
            % <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            win = round(params.alignWinMs / 1000 * fs);  % half window for output (symmetric)
            preAlignMs = 0.5 * params.alignWinMs;
            postAlignMs = 1.0 * params.alignWinMs;
            
            preSearch = round(preAlignMs / 1000 * fs);
            postSearch = round(postAlignMs / 1000 * fs);
            
            alignedWaves = nan(length(locs), 2*win + 1);
            validIdx = false(size(locs));
            
            for i = 1:length(locs)
                center = locs(i);
                searchLeft = center - preSearch;
                searchRight = center + postSearch;
                if searchLeft > 0 && searchRight <= length(x)
                    snip = x(searchLeft:searchRight);
                    switch lower(params.polarity)
                        case 'negative', [~, peakIdx] = min(snip);
                        case 'positive', [~, peakIdx] = max(snip);
                        case 'both',     [~, peakIdx] = max(abs(snip));
                    end
                    peakLoc = searchLeft + peakIdx - 1;
                    leftFinal = peakLoc - win;
                    rightFinal = peakLoc + win;
                    if leftFinal > 0 && rightFinal <= length(x)
                        alignedWaves(i,:) = x(leftFinal:rightFinal);
                        validIdx(i) = true;
                    end
                end
                
            end
            
            % Filter only valid waveform rows
            alignedWaves = alignedWaves(validIdx, :);
            locs = locs(validIdx);  % spike indices
            spikeTimes = spikeTimes(validIdx);  % spike times aligned with waveforms

            % Store original waveforms (centered at detection locs)
            preAlignedWaves = nan(length(locs), 2*win + 1);
            for i = 1:length(locs)
                if locs(i)-win > 0 && locs(i)+win <= length(x)
                    preAlignedWaves(i,:) = x(locs(i)-win : locs(i)+win);
                end
            end

            % Save both raw and aligned waveforms for diagnostics
            app.SpikeResults.waveformsAligned = alignedWaves;
            app.SpikeResults.waveformsRaw = preAlignedWaves;
             
            %% Feature extraction for clustering
            % Update status <<<<<<<<<<<<<<<<<<<
            app.ProgressLabel.String = 'Extracting features...';
            drawnow;
            % <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            switch lower(params.featureMethod)
                case 'pca'
                    maxComp = min(params.numComponents, size(alignedWaves,2));
                    coeff = pca(alignedWaves);
                    features = alignedWaves * coeff(:, 1:maxComp);
                case 'ica'
                    try
                        [icasig, ~, ~] = fastica(alignedWaves', 'numOfIC', params.numComponents);
                        features = icasig(1:params.numComponents, :)';
                    catch
                        warning('ICA failed, using zeros.');
                        features = zeros(size(alignedWaves,1), params.numComponents);
                    end
                case 'waveform'
                    maxComp = min(params.numComponents, size(alignedWaves,2));
                    features = alignedWaves(:, 1:maxComp);
                case 'wavelet'
                    wv = cell(size(alignedWaves,1), 1);  % preallocate
                    for i = 1:size(alignedWaves,1)
                        [c,~] = wavedec(alignedWaves(i,:), 3, 'haar');
                        nComp = min(params.numComponents, length(c));
                        wv{i} = c(1:nComp);  % truncate to fixed length
                    end
            
                    try
                        features = cell2mat(wv);  % results in N x numComponents
                    catch
                        warning('Wavelet features inconsistent in size. Falling back to zeros.');
                        features = zeros(size(alignedWaves,1), params.numComponents);
                    end
                case 't-sne'
                    try
                        maxComp = min(params.numComponents, 3);
                        features = tsne(alignedWaves, 'NumDimensions', maxComp);
                    catch
                        warning('t-SNE failed, using zeros.');
                        features = zeros(size(alignedWaves,1), maxComp);
                    end
                otherwise
                    errordlg('Unknown feature method.');
                    return;
            end
            % Enforce feature matrix shape [N x numComponents]
            [N, ~] = size(alignedWaves);
            if size(features, 1) ~= N
                warning('Feature shape mismatch. Forcing consistent rows.');
                features = reshape(features, N, []);
            end
            % Optional z-score normalization of features (helps clustering)
            if isfield(params, 'normalize') && params.normalize
                mu = mean(features, 1);
                sig = std(features, 0, 1);
                sig(sig < 1e-8) = 1;
                features = (features - mu) ./ sig;
            end

            %% Running clustering
            % Update status <<<<<<<<<<<<<<<<<<<
            app.ProgressLabel.String = 'Running clustering...';
            drawnow;
            % <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

            % DRIFT CORRECTION: time binning strategy
            if params.enableDriftCorrection && strcmpi(params.driftMethod, 'Time Binning')
                % Compute bin IDs for filtered spikeTimes (aligned to features)
                fullStart = t(1);
                fullEnd = t(end);
                % Add one extra bin edge to guarantee coverage of fullEnd
                nBins = ceil((fullEnd - fullStart) / params.driftBinWidth);
                binEdges = linspace(fullStart, fullStart + nBins * params.driftBinWidth, nBins + 1);              
                % Use right-edge inclusion for final bin coverage
                binIDs = discretize(spikeTimes, binEdges, 'IncludedEdge', 'right');
                uniqueBins = unique(binIDs(~isnan(binIDs)));
                numBins = numel(uniqueBins);
                minSpikesPerBin = max(2, ceil(params.minSpikesPerCluster / numBins));  % minimum 2 to allow 1 cluster
                fprintf('[Auto] Using minSpikesPerBin = %d (from global %d across %d bins)\n', ...
                            minSpikesPerBin, params.minSpikesPerCluster, numBins);
                
                % Initialize
                waveformBins = {};
                labelBins = {};
                timeBins = {};

                for b = uniqueBins(:)'  % loop over bins
                    binIdx = (binIDs == b);
                    fprintf('[DEBUG] Bin %d: %d spikes\n', b, sum(binIdx));
                    if sum(binIdx) < minSpikesPerBin
                        continue;  % skip small bins
                    end
                
                    binFeatures = features(binIdx, :);         
                    binWaveforms = alignedWaves(binIdx, :);   
                    binTimes = spikeTimes(binIdx);            
                    
                    switch lower(params.clusterMethod)
                        case 'k-means', [labels, valid] = tryKMeans(binFeatures, minSpikesPerBin);
                        case 'gmm',    [labels, valid] = tryGMM(binFeatures, minSpikesPerBin);
                        case 'dbscan', [labels, valid] = tryDBSCAN(binFeatures, minSpikesPerBin, params.dbscanEpsilon);
                    end
                    
                    if valid
                        waveformBins{end+1} = binWaveforms;
                        labelBins{end+1} = labels;
                        timeBins{end+1} = binTimes;
                    end
                    fprintf('[DEBUG] Bin %d → valid: %d | #clusters: %d\n', ...
                        b, valid, numel(unique(labels)));
                end
        
                % Flatten all bins into one array
                spikeTimesFlat = []; waveformsFlat = []; labelsFlat = []; binIDsFlat = [];
                for i = 1:numel(waveformBins)
                    waveformsFlat = [waveformsFlat; waveformBins{i}];
                    labelsFlat = [labelsFlat; labelBins{i}(:)];
                    spikeTimesFlat = [spikeTimesFlat; timeBins{i}(:)];
                    binIDsFlat = [binIDsFlat; i * ones(size(labelBins{i}(:)))];
                end
        
                % Grid search over thresholds to merge clusters
                clusterLabels = app.optimizeClusterMerging(spikeTimesFlat, waveformsFlat, labelsFlat, binIDsFlat,params);
                % Enforce global minSpikesPerCluster after merging
                uniqueLabels = unique(clusterLabels);
                for i = 1:numel(uniqueLabels)
                    k = uniqueLabels(i);
                    if k == 0, continue; end  % skip unclustered
                    if sum(clusterLabels == k) < params.minSpikesPerCluster
                        clusterLabels(clusterLabels == k) = 0;  % reassign to noise
                    end
                end
                % Replace segment-relative spike times and indices
                spikeTimes = spikeTimesFlat;
                locs = round((spikeTimes - t(1)) * fs) + 1;  % aligned to segment trace

            % DRIFT CORRECTION: dynamic clustering
            elseif params.enableDriftCorrection && strcmpi(params.driftMethod, 'Dynamic Clustering')
                
                tnorm = ((spikeTimes - min(spikeTimes)) / range(spikeTimes))';
                dynFeatures = [features, tnorm];  
                switch lower(params.clusterMethod)
                    case 'k-means', [clusterLabels, valid] = tryKMeans(dynFeatures, params.minSpikesPerCluster);
                    case 'gmm',    [clusterLabels, valid] = tryGMM(dynFeatures, params.minSpikesPerCluster);
                    case 'dbscan', [clusterLabels, valid] = tryDBSCAN(dynFeatures, params.minSpikesPerCluster, params.dbscanEpsilon);
                end
                if ~valid, errordlg('Dynamic clustering failed.'); return; end
                clusterLabels = app.mergeWithinClusters(alignedWaves, clusterLabels, 0.8, 0.5);  % adjust as needed
            % NO drift correction
            else
                switch lower(params.clusterMethod)
                    case 'k-means', [clusterLabels, valid] = tryKMeans(features, params.minSpikesPerCluster);
                    case 'gmm',    [clusterLabels, valid] = tryGMM(features, params.minSpikesPerCluster);
                    case 'dbscan', [clusterLabels, valid] = tryDBSCAN(features, params.minSpikesPerCluster, params.dbscanEpsilon);
                end
                if ~valid, errordlg('Clustering failed.'); return; end
            end
            
            % Update status <<<<<<<<<<<<<<<<<<<
            app.ProgressLabel.String = 'Spike sorting complete. Plotting results...';
            drawnow;
            % <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
            
            %% Save and plot results
            clusterLabels(~isfinite(clusterLabels)) = 0;
            clusterLabels = round(clusterLabels);
            app.SpikeResults.spikeTimes = spikeTimes;
            app.SpikeResults.clusterIdx = clusterLabels;
            app.SpikeResults.waveforms = [];
        
            hold(app.AxMUA, 'on');
            clusterIDs = unique(clusterLabels);
            cmap = lines(numel(clusterIDs));
        
            % Plot threshold lines
            if ~strcmp(params.polarity, 'both')
                yline(app.AxMUA, polarityFactor * threshVal, '--r', 'LineWidth', 1.5);
            else
                yline(app.AxMUA, mean(x) + params.threshold * std(x), '--r', 'LineWidth', 1.5);
                yline(app.AxMUA, -mean(x) - params.threshold * std(x), '--r', 'LineWidth', 1.5);
            end
        
            % Plot each cluster: spikes, waveforms, and ISI
            app.SpikeResults.isiViolationRate = containers.Map('KeyType', 'double', 'ValueType', 'double');
            refracMs = params.refractoryMs;  % ← e.g., 1.5
            isiThresh = 2.0;  % max % spikes with ISIs < 1.5 ms allowed
            SNRThresh = 2.0;  % min SNR allowed
            preSpikeBasleine = 0.5; % pre-spike baseline (e.g., first 0.5 ms)
            % Scatter x-axis: absolute time when full trace, relative when segmented (match axes)
            useRelativeTime = app.SegmentCheckbox.Value && ~isempty(app.Segments);
            for i = 1:numel(clusterIDs)
                k = clusterIDs(i);
                si = locs(clusterLabels == k);
                relSpikeTimes = t(si) - t(1);
                if useRelativeTime
                    scatterX = relSpikeTimes;
                else
                    scatterX = t(si);
                end
                clusterWaves = alignedWaves(clusterLabels == k, :);

                % Default color and rejection flag
                color = cmap(i, :);
                isRejected = false;
                rejectionReason = "";

                % --- SNR Calculation ---
                meanWave = mean(clusterWaves, 1);
                ampP2P = max(meanWave) - min(meanWave);
                
                % Estimate noise from pre-spike baseline (e.g., first 0.5 ms)
                baselineEnd = round(preSpikeBasleine / 1000 * fs);
                baselineRegion = clusterWaves(:, 1:baselineEnd);
                noiseSD = std(baselineRegion(:));
                
                snr = ampP2P / (2 * noiseSD);
                if k == 0
                    app.SpikeResults.noiseSNR = snr;
                else
                    app.SpikeResults.snr(k) = snr;
                end
                
                % Report to console
                fprintf('[SNR] Cluster %d: %.2f (P2P=%.3f, noise=%.3f)\n', ...
                    k, snr, ampP2P, noiseSD);
                % Optional rejection
                if snr < SNRThresh && k ~= 0
                    isRejected = true;
                    rejectionReason = "Low SNR";
                end
                  
            
                % --- ISI analysis ---
                isi = diff(t(si));
                isiViolations = sum(isi < (refracMs / 1000));  % convert ms to seconds
                violationRate = 100 * isiViolations / max(1, length(isi));

            
                % Optional rejection
                if violationRate > isiThresh && k ~= 0
                    isRejected = true;
                    if rejectionReason == ""
                        rejectionReason = "ISI Violation";
                    else
                        rejectionReason = rejectionReason + " + ISI Violation";
                    end
                else
                    fprintf('[ISI] Cluster %d: %.2f%% ISIs < %.1f ms\n',k, violationRate, refracMs);
                end

                clusterWaves = alignedWaves(clusterLabels == k, :);
                app.SpikeResults.waveforms{i} = clusterWaves;
                

                color = (k == 0) * [0.5 0.5 0.5] + (k ~= 0) * cmap(i, :);  
                if isRejected
                    scatter(app.AxMUA, scatterX, x(si), 20, 'x', 'MarkerEdgeColor', color);
                    fprintf('[REJECTED] Cluster %d: %s\n', k, rejectionReason);
                else
                    scatter(app.AxMUA, scatterX, x(si), 20, color, 'filled');
                    if k > 0
                        app.SpikeResults.rejectedClusters(k) = false;
                    end
                end

                % --- Plot ---
                figure('Name', sprintf('Cluster %d Details', k), 'Position', [100 100 600 300]);
                subplot(2,1,1); hold on;
                plot((-win:win)/fs*1000, clusterWaves', 'Color', [color 0.15]);
                plot((-win:win)/fs*1000, mean(clusterWaves,1), 'Color', color, 'LineWidth', 2.5);
                
                rejectedLabel = "";
                if isRejected
                    rejectedLabel = " (Rejected)";
                end
                
                title(sprintf('Cluster %d%s: Aligned Spikes (n = %d, SNR = %.2f)', ...
                    k, rejectedLabel, size(clusterWaves,1), snr));
                xlabel('Time (ms)'); ylabel('Amplitude');
                
                subplot(2,1,2);
                histogram(isi * 1000);
                title(sprintf('Cluster %d: ISI < %.1f ms = %.1f%%', k, refracMs, violationRate));
                xlabel('ISI (ms)'); ylabel('Count');
            end
            clusterIDs = unique(clusterLabels);
            clusterStr = arrayfun(@(k) sprintf('Cluster %d', k), clusterIDs, 'UniformOutput', false);
            app.ClusterSelectMenu.String = clusterStr;
            app.ClusterSelectMenu.Value = 1:numel(clusterIDs);  % Select all by default
        end
        % ---------------------------------------------------------------------------------------------
        %% Other method functions
        function plotAlignmentDiagnostics(app)
            if ~isfield(app.SpikeResults, 'waveformsRaw') || isempty(app.SpikeResults.waveformsRaw)
                errordlg('No spike waveforms available. Run spike sorting first.');
                return;
            end
        
            rawWaves = app.SpikeResults.waveformsRaw;
            alignedWaves = app.SpikeResults.waveformsAligned;
        
            N = min(50, size(rawWaves,1));  % visualize up to 50 spikes
            fs = app.MUAData.fs;
            tAxis = (-floor(size(rawWaves,2)/2):floor(size(rawWaves,2)/2)) / fs * 1000;
        
            figure('Name', 'Alignment Diagnostics', 'Position', [200 200 1000 400]);
        
            subplot(1,2,1);
            hold on;
            plot(tAxis, rawWaves(1:N,:)', 'Color', [0.6 0.6 0.6 0.3]);
            plot(tAxis, mean(rawWaves(1:N,:),1), 'k', 'LineWidth', 2);
            title('Before Alignment');
            xlabel('Time (ms)'); ylabel('Amplitude'); grid on;
        
            subplot(1,2,2);
            hold on;
            plot(tAxis, alignedWaves(1:N,:)', 'Color', [0.2 0.4 1 0.3]);
            plot(tAxis, mean(alignedWaves(1:N,:),1), 'b', 'LineWidth', 2);
            title('After Alignment');
            xlabel('Time (ms)'); ylabel('Amplitude'); grid on;
        end

        function updateClusterScatter(app)
            % Clear AxMUA but restore MUA trace
            cla(app.AxMUA);
            hold(app.AxMUA, 'on');
        
            % Re-plot segmented MUA trace
            t = app.SpikeResults.segmentedTime;
            x = app.SpikeResults.segmentedMUA;
            plot(app.AxMUA, t - t(1), x, 'k');  % Black MUA trace
        
            % Validate cluster data
            if isempty(app.SpikeResults.clusterIdx) || isempty(app.SpikeResults.spikeTimes)
                return;
            end
        
            allClusterIDs = unique(app.SpikeResults.clusterIdx);
            selectedIdx = app.ClusterSelectMenu.Value;
            if isempty(selectedIdx), return; end
        
            selectedClusters = allClusterIDs(selectedIdx);
            cmap = lines(numel(allClusterIDs));
            clusterIdx = app.SpikeResults.clusterIdx;
        
            % Use waveform peak amplitudes if available
            useAmps = isfield(app.SpikeResults, 'waveforms') && ~isempty(app.SpikeResults.waveforms);
        
            for j = 1:numel(selectedClusters)
                k = selectedClusters(j);
                colorIdx = find(allClusterIDs == k);
                si = find(clusterIdx == k);
        
                if useAmps && numel(app.SpikeResults.waveforms) >= k && ~isempty(app.SpikeResults.waveforms{k})
                    clusterWaves = app.SpikeResults.waveforms{k};
                    amps = max(clusterWaves, [], 2);  % Use max amp
                else
                    amps = x(si);  % Fallback to raw MUA value at spike index (may be off if x ≠ spike-trace)
                end
        
                scatter(app.AxMUA, app.SpikeResults.spikeTimes(si)-t(1), amps, 20,...
                    'MarkerEdgeColor', cmap(colorIdx,:), ...
                    'MarkerFaceColor', cmap(colorIdx,:));
            end
        end

        function selectAllClusters(app)
            allClusterIDs = unique(app.SpikeResults.clusterIdx);
            
            % Only include cluster IDs ≥ 1
            validIdx = find(allClusterIDs > 0);
            
            if ~isempty(validIdx)
                app.ClusterSelectMenu.Value = validIdx;
                app.updateClusterScatter();
            end
        end

        function clearClusterSelection(app)
            app.ClusterSelectMenu.Value = [];
            app.updateClusterScatter();
        end

        function bestLabels = optimizeClusterMerging(app, spikeTimes, alignedWaves, clusterLabels, binIDs,params)
            
            fixedLabels = app.mergeClustersAcrossBins(spikeTimes, alignedWaves, clusterLabels, binIDs, 0.85, 0.5);
            if params.enableGridSearchCheck
                corrVals = 0.8:0.05:0.95;
                distVals = 0.4:0.05:0.6;
                bestScore = -Inf;
                bestLabels = zeros(size(clusterLabels));
                bestCorr = NaN;
                bestDist = NaN;
                
                fprintf('Running grid search over correlation × distance thresholds...\n');
                
                for c = 1:numel(corrVals)
                    for d = 1:numel(distVals)
                        try
                            labels = app.mergeSimilarClusters(alignedWaves, fixedLabels, corrVals(c), distVals(d));
                            u = unique(labels);
                            numClusters = numel(u(u > 0));  % exclude 0
    
                            if numClusters < 2, continue;  end
                            %if numel(unique(labels(labels > 0))) < 2, continue; end  % skip trivial results
                            sil = silhouette(alignedWaves, labels);
                            avgSil = mean(sil(~isnan(sil)));
            
                            if avgSil > bestScore
                                bestScore = avgSil;
                                bestLabels = labels;
                                bestCorr = corrVals(c);
                                bestDist = distVals(d);
                            end
                        catch
                            continue;
                        end
                        u = unique(labels);
                        fprintf('[GridSearch] Corr %.2f Dist %.2f → %d nonzero clusters\n', ...
                            corrVals(c), distVals(d), numel(u(u > 0)));
                    end
                end
                fprintf('Best thresholds → Corr: %.2f, Dist: %.2f | Mean silhouette: %.3f\n', bestCorr, bestDist, bestScore);
            else
                bestLabels = app.mergeSimilarClusters(alignedWaves, fixedLabels, 0.85, 0.5);
            end
        
            
        end

        function finalLabels = mergeClustersAcrossBins(app,spikeTimes, waveforms, labels, binIDs, corrThresh, distThresh)
            % mergeClustersAcrossBins - merges cluster labels across time bins
            % for 2D waveforms [nSpikes x nSamples]
            
            % Inputs:
            %   - spikeTimes: [nSpikes x 1] spike time vector
            %   - waveforms:  [nSpikes x nSamples] (2D array)
            %   - labels:     [nSpikes x 1] initial cluster labels
            %   - binIDs:     [nSpikes x 1] bin index each spike belongs to
            %   - corrThresh: scalar threshold for centroid correlation
            %   - distThresh: scalar threshold for centroid distance
            %
            % Outputs:
            %   - finalLabels: updated label assignments across bins
            %   - labelBank: cell array of cluster info per bin
            
            uniqueBins = unique(binIDs);
            labelOffset = 0;
            finalLabels = zeros(size(labels));
            
            % Store cluster centroids from previous bin
            prevCentroids = [];
            
            for b = 1:length(uniqueBins)
                bin = uniqueBins(b);
                idx = (binIDs == bin);
                
                waveBin = waveforms(idx, :);
                labelBin = labels(idx);
                uniqueClusts = unique(labelBin);
                
                % Compute centroids for each cluster in this bin
                centroids = zeros(length(uniqueClusts), size(waveBin, 2));
                for c = 1:length(uniqueClusts)
                    clusterIdx = labelBin == uniqueClusts(c);
                    centroids(c, :) = mean(waveBin(clusterIdx, :), 1);
                end
                
                % Match clusters to previous bin centroids
                newLabels = zeros(size(labelBin));
                assigned = false(1, length(uniqueClusts));
                
                for c = 1:length(uniqueClusts)
                    thisCentroid = centroids(c, :);
                    bestMatch = 0;
                    bestScore = -Inf;
                    
                    for p = 1:size(prevCentroids,1)
                        corrVal = corr(thisCentroid', prevCentroids(p,:)');
                        distVal = norm(thisCentroid - prevCentroids(p,:));
                        
                        if corrVal >= corrThresh && distVal <= distThresh
                            score = corrVal - 0.01 * distVal;
                            if score > bestScore
                                bestScore = score;
                                bestMatch = p;
                            end
                        end
                    end
                    
                    if bestMatch > 0
                        newLabels(labelBin == uniqueClusts(c)) = bestMatch;
                    else
                        labelOffset = labelOffset + 1;
                        newLabels(labelBin == uniqueClusts(c)) = labelOffset;
                    end
                end
                
                finalLabels(idx) = newLabels;
                prevCentroids = centroids;
            end
        end

        function mergedLabels = mergeWithinClusters(app, waveforms, labels, corrThresh, distThresh)
            mergedLabels = labels;
            uniqueClusts = unique(labels(labels > 0));  % exclude noise
            centroids = [];
        
            for k = uniqueClusts(:)'
                centroids(k,:) = mean(waveforms(labels == k,:), 1);
            end
        
            % Compare all pairs
            for i = 1:length(uniqueClusts)
                for j = i+1:length(uniqueClusts)
                    c1 = centroids(uniqueClusts(i),:);
                    c2 = centroids(uniqueClusts(j),:);
                    r = corr(c1', c2');
                    d = norm(c1 - c2);
                    if r > corrThresh && d < distThresh
                        mergedLabels(mergedLabels == uniqueClusts(j)) = uniqueClusts(i);
                    end
                end
            end
        
            % Reassign cluster labels to be sequential
            [~,~,mergedLabels] = unique(mergedLabels, 'sorted');
        end

        function mergedLabels = mergeSimilarClusters(app, waveforms, labels, corrThresh, distThresh)
            mergedLabels = labels;
            uClust = unique(labels(labels > 0));  % ignore 0/noise
            K = numel(uClust);
            centroids = zeros(K, size(waveforms,2));
        
            % Compute centroid of each cluster
            for i = 1:K
                centroids(i,:) = mean(waveforms(labels == uClust(i), :), 1);
            end
        
            % Pairwise comparison
            map = containers.Map('KeyType', 'double', 'ValueType', 'double');
            for i = 1:K
                map(uClust(i)) = uClust(i);  % initialize
            end
        
            for i = 1:K
                for j = i+1:K
                    r = corr(centroids(i,:)', centroids(j,:)');
                    d = norm(centroids(i,:) - centroids(j,:));
                    if r > corrThresh && d < distThresh
                        % Merge cluster j into i
                        map(uClust(j)) = map(uClust(i));
                    end
                end
            end
        
            % Apply mapping
            for k = 1:length(labels)
                if labels(k) > 0 && isKey(map, labels(k))
                    mergedLabels(k) = map(labels(k));
                end
            end
        
            % Reassign cluster labels to be sequential
            [~,~,mergedLabels] = unique(mergedLabels, 'sorted');
        end


        function plotSpikeRateOverTime(app)
            if ~isstruct(app.SpikeResults) || ...
               ~isfield(app.SpikeResults, 'spikeTimes') || ...
               ~isfield(app.SpikeResults, 'clusterIdx') || ...
               isempty(app.SpikeResults.spikeTimes) || ...
               isempty(app.SpikeResults.clusterIdx)
            
                errordlg('Spike sorting results are missing.');
                return;
            end
        
            % Ask user for bin size
            prompt = {'Enter time bin size (in seconds):', 'Plot as relative rate? (0 = No, 1 = Yes)'};
            dlgtitle = 'Spike Rate Settings';
            dims = [1 50];
            definput = {'1', '0'};
            answer = inputdlg(prompt, dlgtitle, dims, definput);
            if isempty(answer), return; end
        
            binSize = str2double(answer{1});
            isRelative = logical(str2double(answer{2}));
        
            if isnan(binSize) || binSize <= 0
                errordlg('Invalid bin size.');
                return;
            end
        
            clusterIDs = app.ClusterIDLookup(app.ClusterSelectMenu.Value);
            t = app.SpikeResults.spikeTimes;
            c = app.SpikeResults.clusterIdx;
        
            tStart = min(t);
            tEnd = max(t);
            edges = tStart:binSize:tEnd;
            centers = edges(1:end-1) + binSize/2;
        
            figure('Name', 'Spike Rate Over Time', 'Position', [100 100 700 400]); hold on;
        
            cmap = lines(numel(clusterIDs));
            for i = 1:numel(clusterIDs)
                k = clusterIDs(i);
                spikes = t(c == k);
                counts = histcounts(spikes, edges);
        
                if isRelative
                    rate = counts / sum(counts);  % normalize
                else
                    rate = counts / binSize;  % absolute rate (Hz)
                end
        
                plot(centers, rate, 'LineWidth', 2, 'Color', cmap(i,:), ...
                    'DisplayName', sprintf('Cluster %d', k));
            end
        
            xlabel('Time (s)');
            ylabel(isRelative * "Relative Rate" + ~isRelative * "Firing Rate (Hz)");
            title('Spike Rate Over Time');
            legend show;
        end
            
    end
end


function [idx, valid] = tryKMeans(features, minSpikes)
    valid = false;
    maxK = 10;
    bestScore = -Inf;
    bestK = 2;
    idx = [];

    for k = 2:maxK
        tempIdx = kmeans(features, k, 'Replicates', 5, 'MaxIter', 500);
        counts = histcounts(tempIdx, 1:(k+1));

        if all(counts >= minSpikes)
            silScore = mean(silhouette(features, tempIdx));
            if silScore > bestScore
                bestScore = silScore;
                bestK = k;
                idx = tempIdx;
                valid = true;
            end
        end

        
    end
end

function [idx, valid] = tryGMM(features, minSpikes)
    valid = false;
    maxK = 10;
    bestScore = -Inf;
    bestK = 2;
    idx = [];

    for k = 2:maxK
        try
            gmOptions = statset('MaxIter', 500);
            GM = fitgmdist(features, k, 'Options', gmOptions, ...
                'RegularizationValue', 1e-5, 'Replicates', 3);
            tempIdx = cluster(GM, features);
        catch
            continue;
        end

        counts = histcounts(tempIdx, 1:(k+1));
        if all(counts >= minSpikes)
            silScore = mean(silhouette(features, tempIdx));
            if silScore > bestScore
                bestScore = silScore;
                bestK = k;
                idx = tempIdx;
                valid = true;
            end
        end
        
    end
end

function [idx, valid] = tryDBSCAN(features, minSpikes, epsilon)
    if isnan(epsilon) || epsilon <= 0
        % Auto-tune epsilon using k-distance heuristic
        k = min(10, size(features, 2)); % e.g., 10th nearest neighbor
        D = pdist2(features, features);
        D = sort(D, 2);
        kDistances = D(:, k + 1);  % skip self-distance
        epsilon = prctile(kDistances, 95);  % choose 95th percentile
    end

    idx = dbscan(features, epsilon, minSpikes);

    if all(idx == -1)
        valid = false;
        return;
    end

    idx(idx == -1) = 0; % unclustered
    valid = true;
end
