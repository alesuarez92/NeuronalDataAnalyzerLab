%% LFPAnalysisApp.m
% =========================================================================
% PROCESS LFP DATA - ERP AND CSD ANALYSIS ON LOADED LFP
% =========================================================================
% Launched from Main. Built with UIKit.window: numbered step cards on the
% left, result tabs on the right, status bar below.
%   1 Load LFP file - .mat saved by ExtractEphysApp (Save LFP): lfp_data,
%                     stim_data, t_lfp, t_stim, lfp_fs, stim_fs (checked).
%   2 Channels      - LFP rows to analyse (multi-select).
%   3 ERP analysis  - ERPConfigApp (window, threshold, min ISI); onsets are
%                     upward threshold crossings of the mean-subtracted
%                     stimulus at time (k-1)/Fs; edge epochs are NaN-filled
%                     and excluded, the valid epoch count is reported.
%   4 CSD           - second spatial derivative of the ERP across a user
%                     channel order (>= 3 channels from the last ERP) and
%                     inter-electrode spacing (um); edge rows replicated.
%   5 Export        - ERP (mean, SD, t, y = channel average) and CSD to .mat.
% Tabs: Stimulus (with threshold and detected onsets), ERP overlay, ERP per
% channel (mean ± SD), CSD map. Help button opens HelpApp on "LFP Analysis".
% =========================================================================

classdef LFPAnalysisApp < handle
    %% PROPERTIES: UI, loaded LFP/Stim/t/Fs, selected channels, ERP params and last results
    properties
        UIFig
        StatusLabel      % Status bar (UIKit.setStatus)
        LoadBtn
        FileLabel        % File name, Fs, duration, channel count

        ChannelList      % Multi-select listbox (ItemsData = LFP row index)
        ChannelLabel     % "n of N selected"
        SelectAllBtn
        SelectNoneBtn
        ERBBtn           % Run ERP analysis (opens ERPConfigApp)
        ERPInfoLabel     % "Averaged n of m epochs"
        SpacingEdit      % CSD inter-electrode spacing (um)
        ChannelOrderEdit % CSD channel order, e.g. "5 4 3 2 1"
        CSDBtn
        ExportBtn

        Tabs             % uitabgroup with the result views
        TabStim
        TabOverlay
        TabChannels
        TabCSD
        AxStim           % Stimulus (mean-subtracted) + threshold + onsets
        AxOverlay        % ERP overlay, all selected channels
        AxContainer      % Panel with the per-channel ERP tiles
        AxCSD            % CSD image

        % Data
        LFP
        Stim
        t_lfp
        t_stim
        Fs_lfp
        Fs_stim
        FileName = ''
        LFPChannelIDs    % lfp_channels from the file (TDT numbers), if present

        % Analysis
        SelectedChannels
        ERPParams
        LastERP
        LastTime
        LastERPStd
        LastNValid       % Number of complete epochs averaged
        LastOnsetTimes   % Detected onset times (s)
        LastCSD
        LastCSDOrder
        LastCSDSpacing   % um
        Exported = false
    end

    methods
        %% Constructor - Build UI; data loaded via Load LFP file
        function app = LFPAnalysisApp()
            app.buildUI();
        end

        %% buildUI - UIKit window: step cards (left) | result tabs (right)
        function buildUI(app)
            T = UITheme;
            W = UIKit.window('LFP / ERP Analysis', ...
                'Load LFP, average evoked responses (ERP) and map current source density (CSD)', ...
                'LFP Analysis', [1200 820]);
            app.UIFig = W.Fig;
            app.StatusLabel = W.Status;
            W.Body.ColumnWidth = {300, '1x'};
            W.Body.RowHeight = {'1x'};
            bh = T.buttonHeight;
            ch = T.controlHeight;

            left = uigridlayout(W.Body, [5 1], 'RowHeight', {124, '1x', 112, 142, 78}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 10, 'BackgroundColor', T.bgGray, ...
                'Scrollable', 'on');
            left.Layout.Row = 1; left.Layout.Column = 1;

            % --- 1 Load LFP file ---
            g = cardGrid(left, {22, bh, '1x'});
            UIKit.step(g, 1, 'Load LFP file');
            app.LoadBtn = UIKit.button(g, 'Load LFP file…', @(~,~)app.loadData(), 'primary', ...
                'Open a .mat saved by Extract Ephys (Save LFP)');
            app.FileLabel = infoLabel(g, 'No file loaded');

            % --- 2 Channels ---
            g = cardGrid(left, {22, 26, '1x'});
            UIKit.step(g, 2, 'Channels');
            sg = uigridlayout(g, [1 3], 'ColumnWidth', {'1x', 48, 52}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 6, 'BackgroundColor', T.cardBg);
            app.ChannelLabel = uilabel(sg, 'Text', 'No channels loaded', 'FontSize', T.fontSmall, ...
                'FontColor', T.bodyColor, 'Tooltip', 'Ctrl/Shift-click in the list to select several channels');
            app.SelectAllBtn = UIKit.button(sg, 'All', @(~,~)app.selectChannels(true), 'secondary', ...
                'Select every channel');
            app.SelectNoneBtn = UIKit.button(sg, 'None', @(~,~)app.selectChannels(false), 'secondary', ...
                'Clear the channel selection');
            app.ChannelList = uilistbox(g, 'Items', {}, 'Multiselect', 'on', ...
                'Tooltip', 'Channels for the ERP (and CSD). Ctrl/Shift-click to select several.', ...
                'ValueChangedFcn', @(~,~)app.onChannelsChanged());

            % --- 3 ERP analysis ---
            g = cardGrid(left, {22, bh, '1x'});
            UIKit.step(g, 3, 'ERP analysis');
            app.ERBBtn = UIKit.button(g, 'Run ERP…', @(~,~)app.openERPConfig(), 'secondary', ...
                'Set the epoch window and stimulus threshold, then average epochs per channel');
            app.ERPInfoLabel = infoLabel(g, 'Not run yet');

            % --- 4 CSD ---
            g = cardGrid(left, {22, ch, ch, bh}, 2);
            lbl = UIKit.step(g, 4, 'CSD');
            lbl.Layout.Column = [1 2];
            app.SpacingEdit = UIKit.field(g, 'Spacing (µm)', 'numeric', 100, ...
                'Distance between neighbouring electrode contacts in micrometres', [0 Inf]);
            app.SpacingEdit.LowerLimitInclusive = 'off';
            app.ChannelOrderEdit = UIKit.field(g, 'Channel order', 'text', '', ...
                ['Channels from the last ERP, top (superficial) to bottom (deep), ' ...
                'e.g. "5 4 3 2 1". At least 3.']);
            app.CSDBtn = UIKit.button(g, 'Compute CSD', @(~,~)app.computeCSD(), 'secondary', ...
                'Second spatial derivative of the ERP across the ordered channels (needs >= 3)');
            app.CSDBtn.Layout.Column = [1 2];

            % --- 5 Export ---
            g = cardGrid(left, {22, bh});
            UIKit.step(g, 5, 'Export');
            app.ExportBtn = UIKit.button(g, 'Export ERP / CSD…', @(~,~)app.exportResults(), 'secondary', ...
                'Save ERP mean/SD, time axis, epoch count and (if computed) CSD to .mat');

            % --- Result tabs ---
            app.Tabs = uitabgroup(W.Body);
            app.Tabs.Layout.Row = 1; app.Tabs.Layout.Column = 2;
            app.TabStim     = uitab(app.Tabs, 'Title', 'Stimulus', 'BackgroundColor', T.cardBg);
            app.TabOverlay  = uitab(app.Tabs, 'Title', 'ERP overlay', 'BackgroundColor', T.cardBg);
            app.TabChannels = uitab(app.Tabs, 'Title', 'ERP per channel', 'BackgroundColor', T.cardBg);
            app.TabCSD      = uitab(app.Tabs, 'Title', 'CSD', 'BackgroundColor', T.cardBg);
            app.AxStim    = uiaxes(tabGrid(app.TabStim));
            app.AxOverlay = uiaxes(tabGrid(app.TabOverlay));
            app.AxContainer = uipanel(tabGrid(app.TabChannels), 'BorderType', 'none', ...
                'BackgroundColor', T.cardBg);
            app.AxCSD     = uiaxes(tabGrid(app.TabCSD));
            UIKit.emptyAxes(app.AxStim, 'Load an LFP file to begin');
            UIKit.emptyAxes(app.AxOverlay, 'Run the ERP analysis (step 3) to see the overlay');
            app.channelPlaceholder('Run the ERP analysis (step 3) to see each channel');
            UIKit.emptyAxes(app.AxCSD, 'Run the ERP, then Compute CSD (step 4)');

            app.updateControls();
        end

        %% updateControls - Enable state and primary (next) action from data state
        function updateControls(app)
            hasData = ~isempty(app.LFP);
            nSel = 0;
            if hasData, nSel = numel(app.ChannelList.Value); end
            hasERP = ~isempty(app.LastERP) && ~isempty(app.LastTime);
            hasCSD = ~isempty(app.LastCSD);
            nERP = numel(app.SelectedChannels);

            setEnable({app.ChannelList, app.SelectAllBtn, app.SelectNoneBtn}, hasData);
            app.ERBBtn.Enable = onOff(nSel > 0);
            setEnable({app.SpacingEdit, app.ChannelOrderEdit, app.CSDBtn}, hasERP);
            app.ExportBtn.Enable = onOff(hasERP);

            if hasData
                app.ChannelLabel.Text = sprintf('%d of %d selected', nSel, size(app.LFP, 1));
            end

            % Recommended next action: load -> ERP -> CSD (>= 3 ch) -> export
            if ~hasData
                next = app.LoadBtn;
            elseif ~hasERP
                next = app.ERBBtn;
            elseif nERP >= 3 && ~hasCSD
                next = app.CSDBtn;
            elseif ~app.Exported
                next = app.ExportBtn;
            else
                next = [];
            end
            for b = [app.LoadBtn, app.ERBBtn, app.CSDBtn, app.ExportBtn]
                setButtonStyle(b, isequal(b, next));
            end
        end

        %% loadData - Pick an LFP .mat, validate its variables, fill channel list
        function loadData(app)
            startDir = ProjectManager.getImportDir();
            if isempty(startDir) || ~isfolder(startDir), startDir = pwd; end
            [file, path] = uigetfile('*.mat', 'Select LFP Data File', startDir);
            figure(app.UIFig);
            if isequal(file, 0)
                UIKit.setStatus(app.StatusLabel, 'Load cancelled.', 'info');
                return;
            end

            UIKit.setStatus(app.StatusLabel, sprintf('Loading %s…', file), 'busy');
            dlg = UIKit.busy(app.UIFig, sprintf('Loading %s…', file));
            try
                s = load(fullfile(path, file));
            catch ME
                UIKit.done(dlg);
                UIKit.setStatus(app.StatusLabel, sprintf('Could not read %s: %s', file, ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Could not read the file:\n%s', ME.message), 'Load Failed');
                return;
            end
            UIKit.done(dlg);

            % Validate that the file was saved by ExtractEphysApp (Save LFP Data)
            required = {'lfp_data', 'stim_data', 't_lfp', 't_stim', 'lfp_fs', 'stim_fs'};
            missing = required(~isfield(s, required));
            if ~isempty(missing)
                msg = sprintf('Invalid LFP file. Missing variable(s): %s', strjoin(missing, ', '));
                UIKit.setStatus(app.StatusLabel, msg, 'error');
                UIKit.alert(app.UIFig, [msg sprintf(['\n\nUse a file written by Extract Ephys ' ...
                    '(step 4, Save LFP).'])], 'Invalid File');
                return;
            end
            app.LFP = s.lfp_data;
            app.Stim = s.stim_data;
            app.t_lfp = s.t_lfp;
            app.t_stim = s.t_stim;
            app.Fs_lfp = s.lfp_fs;
            app.Fs_stim = s.stim_fs;
            app.FileName = file;

            % Drop results from a previously loaded file
            app.SelectedChannels = [];
            app.ERPParams = [];
            app.LastERP = []; app.LastTime = []; app.LastERPStd = [];
            app.LastNValid = []; app.LastOnsetTimes = [];
            app.LastCSD = []; app.LastCSDOrder = []; app.LastCSDSpacing = [];
            app.Exported = false;

            % Channel list: row index (used by ERP/CSD), plus TDT channel if saved
            nChan = size(app.LFP, 1);
            chanLabels = arrayfun(@(i) sprintf('Ch %d', i), 1:nChan, 'UniformOutput', false);
            app.LFPChannelIDs = [];
            if isfield(s, 'lfp_channels') && numel(s.lfp_channels) == nChan
                app.LFPChannelIDs = s.lfp_channels(:)';
                chanLabels = arrayfun(@(i) sprintf('Ch %d  (TDT %d)', i, app.LFPChannelIDs(i)), ...
                    1:nChan, 'UniformOutput', false);
            end
            app.ChannelList.ItemsData = [];
            app.ChannelList.Items = chanLabels;
            app.ChannelList.ItemsData = 1:nChan;
            app.ChannelList.Value = 1:min(4, nChan);
            app.ChannelOrderEdit.Value = '';

            durS = size(app.LFP, 2) / app.Fs_lfp;
            app.FileLabel.Text = sprintf('%s\nLFP %.2f Hz · %s · %d ch\nStim %.2f Hz', ...
                file, app.Fs_lfp, fmtDuration(durS), nChan, app.Fs_stim);
            app.FileLabel.Tooltip = fullfile(path, file);
            app.ERPInfoLabel.Text = 'Not run yet';

            % Reset result views; show the stimulus so the threshold can be judged
            app.plotStimulus();
            resetAxes(app.AxOverlay);
            UIKit.emptyAxes(app.AxOverlay, 'Run the ERP analysis (step 3) to see the overlay');
            app.channelPlaceholder('Run the ERP analysis (step 3) to see each channel');
            resetAxes(app.AxCSD);
            UIKit.emptyAxes(app.AxCSD, 'Run the ERP, then Compute CSD (step 4)');
            app.Tabs.SelectedTab = app.TabStim;

            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf('Loaded %s (%d channels, %.2f Hz, %s). Next: Run ERP.', ...
                file, nChan, app.Fs_lfp, fmtDuration(durS)), 'success');
        end

        %% onChannelsChanged - Selection changed: refresh enable state and status
        function onChannelsChanged(app)
            app.updateControls();
            if isempty(app.ChannelList.Value)
                UIKit.setStatus(app.StatusLabel, 'Select at least one channel for the ERP.', 'warning');
            end
        end

        %% selectChannels - All / None buttons
        function selectChannels(app, selectAll)
            if isempty(app.LFP), return; end
            if selectAll
                app.ChannelList.Value = app.ChannelList.ItemsData;
            else
                app.ChannelList.Value = [];
            end
            app.onChannelsChanged();
        end

        %% openERPConfig - ERPConfigApp dialog, then computeERP on OK
        function openERPConfig(app)
            sel = app.ChannelList.Value;
            if isempty(sel)
                UIKit.alert(app.UIFig, 'Please select at least one channel for ERP analysis.', 'ERP Analysis');
                return;
            end

            cfg = ERPConfigApp(app.Fs_lfp);
            uiwait(cfg.UIFig);
            if isempty(cfg.Params)
                UIKit.setStatus(app.StatusLabel, 'ERP analysis cancelled.', 'info');
                return;
            end
            % Commit selection only once the dialog is confirmed, so a cancel
            % does not desync SelectedChannels from LastERP (used by CSD)
            app.SelectedChannels = sel(:)';
            app.ERPParams = cfg.Params;

            % Next: computeERP()
            app.computeERP();
        end

        %% computeERP - Detect onsets, cut NaN-filled epochs, average, plot
        function computeERP(app)
            % Extract parameters
            fs = app.Fs_lfp;
            preS = app.ERPParams.preTime;
            postS = app.ERPParams.postTime;
            threshold = app.ERPParams.threshold;
            minISI = app.ERPParams.minISI;
            chIdx = app.SelectedChannels;

            % Detect stimulus onsets
            stim = app.Stim;
            stim = stim - mean(stim);
            above = stim > threshold;
            onsets = find(diff([0 above]) == 1);
            isi = diff(onsets) / app.Fs_stim;
            validIdx = [true, isi > minISI];
            onsets = onsets(validIdx);
            if isempty(onsets)
                app.plotStimulus(threshold, []);
                app.Tabs.SelectedTab = app.TabStim;
                app.erpFailed(['No stimulus onsets detected. Check the threshold against the ' ...
                    'Stimulus tab (dashed line).']);
                return;
            end
            onsetTimes = (onsets - 1) / app.Fs_stim;  % sample k is at (k-1)/Fs

            % Convert to LFP indices
            preSamples = round(preS * fs);
            postSamples = round(postS * fs);
            totalSamples = preSamples + postSamples + 1;
            % NaN-filled so skipped (edge) epochs are ignored by 'omitnan'
            erpMat = nan(length(chIdx), totalSamples, length(onsetTimes));
            nValid = 0;

            for t = 1:length(onsetTimes)
                centerIdx = round(onsetTimes(t) * fs) + 1;
                idxRange = centerIdx - preSamples : centerIdx + postSamples;
                if idxRange(1) < 1 || idxRange(end) > size(app.LFP, 2)
                    continue;
                end
                erpMat(:,:,t) = app.LFP(chIdx, idxRange);
                nValid = nValid + 1;
            end
            if nValid == 0
                app.plotStimulus(threshold, onsetTimes);
                app.erpFailed('No complete epochs: all onsets are too close to the recording edges.');
                return;
            end

            % Average and standard deviation ERP
            erpAvg = mean(erpMat, 3, 'omitnan');
            erpStd = std(erpMat, 0, 3, 'omitnan');
            t = (-preSamples:postSamples) / fs;

            app.LastERP  = erpAvg;
            app.LastTime = t;
            app.LastERPStd = erpStd;
            app.LastNValid = nValid;
            app.LastOnsetTimes = onsetTimes;
            app.LastCSD = []; app.LastCSDOrder = []; app.LastCSDSpacing = [];   % CSD now stale
            app.Exported = false;
            app.ChannelOrderEdit.Value = num2str(chIdx);
            resetAxes(app.AxCSD);
            UIKit.emptyAxes(app.AxCSD, 'Compute CSD (step 4) for this ERP');

            dlg = UIKit.busy(app.UIFig, 'Plotting ERPs…');
            try
                app.plotStimulus(threshold, onsetTimes);
                app.plotOverlay(t, erpAvg, chIdx, nValid);
                app.plotPerChannel(t, erpAvg, erpStd, chIdx, nValid);
            catch ME
                UIKit.done(dlg);
                app.updateControls();
                UIKit.setStatus(app.StatusLabel, sprintf('ERP computed but plotting failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Plotting failed:\n%s', ME.message), 'ERP Analysis');
                return;
            end
            UIKit.done(dlg);
            app.Tabs.SelectedTab = app.TabOverlay;

            app.ERPInfoLabel.Text = sprintf('Averaged %d of %d epochs · %d ch · −%g to +%g s', ...
                nValid, numel(onsetTimes), numel(chIdx), preS, postS);
            app.updateControls();
            nextHint = 'Next: Export.';
            if numel(chIdx) >= 3, nextHint = 'Next: Compute CSD or Export.'; end
            UIKit.setStatus(app.StatusLabel, sprintf('ERP: averaged %d epochs (%d onsets detected, %d skipped at edges). %s', ...
                nValid, numel(onsetTimes), numel(onsetTimes) - nValid, nextHint), 'success');
        end

        %% computeCSD - Validate spacing / channel order, second spatial derivative
        function computeCSD(app)
            if isempty(app.LastERP) || isempty(app.LastTime)
                UIKit.alert(app.UIFig, 'No ERP data available. Run ERP analysis first.', 'CSD');
                return;
            end

            spacing_um = app.SpacingEdit.Value * 1e-6;  % meters
            if ~isfinite(spacing_um) || spacing_um <= 0
                app.csdInvalid('Inter-electrode spacing must be a positive number.');
                return;
            end
            chan_order = str2double(regexp(strtrim(app.ChannelOrderEdit.Value), '[\s,;]+', 'split'));
            if isempty(chan_order) || any(~isfinite(chan_order))
                app.csdInvalid('Channel order must be a list of channel numbers.');
                return;
            end
            [isMember, reorder] = ismember(chan_order, app.SelectedChannels);
            if ~all(isMember)
                app.csdInvalid(sprintf(['Channel order may only contain channels used in the last ERP ' ...
                    'analysis (%s).'], num2str(app.SelectedChannels)));
                return;
            end
            if numel(chan_order) < 3
                app.csdInvalid('CSD needs at least 3 channels.');
                return;
            end

            % Reorder ERP to match user input
            erp = app.LastERP(reorder, :);
            t   = app.LastTime;

            % Compute second spatial derivative (discrete Laplacian)
            dz  = spacing_um;
            csd = -diff(erp, 2, 1) / dz^2;
            csd = [csd(1,:); csd; csd(end,:)];  % replicate edge rows (no padarray dependency)

            app.LastCSD = csd;
            app.LastCSDOrder = chan_order;
            app.LastCSDSpacing = app.SpacingEdit.Value;
            app.Exported = false;

            % Plot in the CSD tab
            T = UITheme;
            ax = app.AxCSD;
            resetAxes(ax);
            imagesc(ax, t, 1:length(chan_order), csd);
            colormap(ax, jet);
            cb = colorbar(ax);
            cb.Label.String = 'CSD (amplitude / m^2)';
            m = max(abs(csd(:)));
            if isfinite(m) && m > 0, ax.CLim = [-m m]; end   % symmetric: sinks vs sources
            hold(ax, 'on');
            xline(ax, 0, '--', 'Color', T.sectionTitleColor, 'LineWidth', 1);
            hold(ax, 'off');
            axis(ax, 'tight');
            UIKit.styleAxes(ax, 'Current Source Density (CSD)', 'Time (s)', 'Channel (ordered)');
            ax.XGrid = 'off'; ax.YGrid = 'off';
            ax.YDir = 'reverse';
            ax.YTick = 1:length(chan_order);
            ax.YTickLabel = arrayfun(@(c) sprintf('Ch %d', c), chan_order, 'UniformOutput', false);
            app.Tabs.SelectedTab = app.TabCSD;

            app.updateControls();
            UIKit.setStatus(app.StatusLabel, sprintf('CSD computed over %d channels (%g µm spacing). Next: Export.', ...
                numel(chan_order), app.LastCSDSpacing), 'success');
        end

        %% exportResults - Save ERP (and CSD if computed) to .mat
        % t / y (mean over the ERP channels) are readable by Signal Characterization.
        function exportResults(app)
            if isempty(app.LastERP)
                UIKit.alert(app.UIFig, 'No ERP data available. Run ERP analysis first.', 'Export');
                return;
            end
            d = ProjectManager.getExportDir();
            if isempty(d) || ~isfolder(d), d = pwd; end
            [~, base] = fileparts(app.FileName);
            if isempty(base), base = 'lfp'; end
            [file, path] = uiputfile('*.mat', 'Export ERP / CSD', fullfile(d, [base '_ERP.mat']));
            figure(app.UIFig);
            if isequal(file, 0)
                UIKit.setStatus(app.StatusLabel, 'Export cancelled.', 'info');
                return;
            end

            out = struct();
            out.t = app.LastTime;
            out.y = mean(app.LastERP, 1);
            out.erp_avg = app.LastERP;
            out.erp_std = app.LastERPStd;
            out.erp_channels = app.SelectedChannels;
            if ~isempty(app.LFPChannelIDs)
                out.erp_tdt_channels = app.LFPChannelIDs(app.SelectedChannels);
            end
            out.erp_params = app.ERPParams;
            out.n_epochs = app.LastNValid;
            out.onset_times = app.LastOnsetTimes;
            out.lfp_fs = app.Fs_lfp;
            out.source_file = app.FileName;
            if ~isempty(app.LastCSD)
                out.csd = app.LastCSD;
                out.csd_channel_order = app.LastCSDOrder;
                out.csd_spacing_um = app.LastCSDSpacing;
            end

            try
                save(fullfile(path, file), '-struct', 'out');
            catch ME
                UIKit.setStatus(app.StatusLabel, sprintf('Export failed: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('Export failed:\n%s', ME.message), 'Export');
                return;
            end
            app.Exported = true;
            app.updateControls();
            what = 'ERP';
            if ~isempty(app.LastCSD), what = 'ERP and CSD'; end
            UIKit.setStatus(app.StatusLabel, sprintf('Exported %s to %s.', what, file), 'success');
        end
    end

    methods (Access = private)
        %% plotStimulus - Mean-subtracted stimulus; optional threshold and onsets
        function plotStimulus(app, threshold, onsetTimes)
            T = UITheme;
            ax = app.AxStim;
            resetAxes(ax);
            stim = app.Stim - mean(app.Stim);
            plot(ax, app.t_stim, stim, 'Color', T.stimColor, 'DisplayName', 'Stimulus');
            ttl = 'Stimulus (mean-subtracted)';
            if nargin >= 2 && ~isempty(threshold)
                hold(ax, 'on');
                yline(ax, threshold, '--', 'Color', T.plotColors(2,:), 'LineWidth', 1, ...
                    'DisplayName', sprintf('Threshold (%g)', threshold));
                if nargin >= 3 && ~isempty(onsetTimes)
                    plot(ax, onsetTimes, repmat(threshold, size(onsetTimes)), 'v', ...
                        'Color', T.plotColors(1,:), 'MarkerFaceColor', T.plotColors(1,:), ...
                        'MarkerSize', 5, 'LineStyle', 'none', 'DisplayName', 'Detected onsets');
                    ttl = sprintf('Stimulus: %d onsets detected', numel(onsetTimes));
                else
                    ttl = 'Stimulus: no onsets above the threshold';
                end
                hold(ax, 'off');
                lg = legend(ax); lg.Location = 'northeast'; lg.Box = 'off';
            end
            axis(ax, 'tight');
            UIKit.styleAxes(ax, ttl, 'Time (s)', 'Stimulus (units)');
        end

        %% plotOverlay - All selected channels' ERPs in one axes
        function plotOverlay(app, t, erpAvg, chIdx, nValid)
            T = UITheme;
            ax = app.AxOverlay;
            resetAxes(ax);
            hold(ax, 'on');
            nC = size(T.plotColors, 1);
            styles = {'-', '--', ':'};
            for i = 1:length(chIdx)
                plot(ax, t, erpAvg(i,:), 'Color', T.plotColors(mod(i-1, nC) + 1, :), ...
                    'LineStyle', styles{mod(floor((i-1) / nC), numel(styles)) + 1}, ...
                    'LineWidth', 1, 'DisplayName', sprintf('Ch %d', chIdx(i)));
            end
            xline(ax, 0, '--', 'Color', T.stimColor, 'LineWidth', 1, 'DisplayName', 'Stimulus onset');
            hold(ax, 'off');
            axis(ax, 'tight');
            UIKit.styleAxes(ax, sprintf('ERP overlay (%d epochs)', nValid), 'Time (s)', 'Amplitude');
            lg = legend(ax); lg.Location = 'eastoutside'; lg.Box = 'off';
        end

        %% plotPerChannel - One tile per channel: mean ± SD (shaded) and onset line
        function plotPerChannel(app, t, erpAvg, erpStd, chIdx, nValid)
            T = UITheme;
            delete(app.AxContainer.Children);
            tl = tiledlayout(app.AxContainer, 'flow', 'TileSpacing', 'compact', 'Padding', 'compact');
            for i = 1:length(chIdx)
                ax = nexttile(tl);
                hold(ax, 'on');
                upper = erpAvg(i,:) + erpStd(i,:);
                lower = erpAvg(i,:) - erpStd(i,:);
                fill(ax, [t fliplr(t)], [upper fliplr(lower)], T.shadeColor, ...
                    'FaceAlpha', 0.2, 'EdgeColor', 'none');
                plot(ax, t, erpAvg(i,:), 'Color', T.plotColors(1,:), 'LineWidth', 1);
                xline(ax, 0, '--', 'Color', T.stimColor, 'LineWidth', 1);
                hold(ax, 'off');
                axis(ax, 'tight');
                UIKit.styleAxes(ax, sprintf('Ch %d', chIdx(i)));
            end
            tl.Title.String = sprintf('ERP per channel: mean ± SD (%d epochs)', nValid);
            tl.Title.FontWeight = 'bold';
            tl.Title.Color = T.sectionTitleColor;
            tl.XLabel.String = 'Time (s)';
            tl.YLabel.String = 'Amplitude';
        end

        %% channelPlaceholder - Empty tile with a hint in the per-channel tab
        function channelPlaceholder(app, msg)
            delete(app.AxContainer.Children);
            tl = tiledlayout(app.AxContainer, 1, 1, 'Padding', 'compact');
            UIKit.emptyAxes(nexttile(tl), msg);
        end

        %% erpFailed - ERP could not be computed: status + alert
        function erpFailed(app, msg)
            app.updateControls();
            UIKit.setStatus(app.StatusLabel, msg, 'error');
            UIKit.alert(app.UIFig, msg, 'ERP Analysis');
        end

        %% csdInvalid - Invalid CSD input: status + alert
        function csdInvalid(app, msg)
            UIKit.setStatus(app.StatusLabel, msg, 'error');
            UIKit.alert(app.UIFig, msg, 'CSD Parameters');
        end
    end
end

%% Local helper: white card with a padded grid (one step per card)
function g = cardGrid(parent, rowHeights, nCols)
    T = UITheme;
    if nargin < 3, nCols = 1; end
    c = UIKit.card(parent, '');
    g = uigridlayout(c, [numel(rowHeights) nCols], 'RowHeight', rowHeights, ...
        'ColumnWidth', repmat({'1x'}, 1, nCols), 'Padding', [10 8 10 10], ...
        'RowSpacing', 6, 'ColumnSpacing', 8, 'BackgroundColor', T.cardBg);
end

%% Local helper: clear axes incl. legend/colorbar and reset tick modes
% (UIKit.emptyAxes fixes XTick/YTick to [], so plots must start from a reset)
function resetAxes(ax)
    legend(ax, 'off');
    colorbar(ax, 'off');
    cla(ax, 'reset');
end

%% Local helper: padded 1x1 grid inside a tab (room for titles and labels)
function g = tabGrid(tab)
    T = UITheme;
    g = uigridlayout(tab, [1 1], 'Padding', [8 8 8 8], 'BackgroundColor', T.cardBg);
end

%% Local helper: small wrapped info text inside a card
function lbl = infoLabel(parent, text)
    T = UITheme;
    lbl = uilabel(parent, 'Text', text, 'FontSize', T.fontSmall, 'FontColor', T.bodyColor, ...
        'WordWrap', 'on', 'VerticalAlignment', 'top', 'Interpreter', 'none');
end

%% Local helper: set Enable on a cell array of components
function setEnable(ctrls, tf)
    for k = 1:numel(ctrls)
        ctrls{k}.Enable = onOff(tf);
    end
end

%% Local helper: restyle an existing button as primary / secondary
% (UIKit.button only styles at creation; the "next step" moves as data changes)
function setButtonStyle(b, isPrimary)
    T = UITheme;
    if isPrimary
        b.BackgroundColor = T.accent;      b.FontColor = [1 1 1]; b.FontWeight = 'bold';
    else
        b.BackgroundColor = T.secondaryBg; b.FontColor = T.secondaryFg; b.FontWeight = 'normal';
    end
end

%% Local helper: 'on'/'off' from a logical
function s = onOff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end

%% Local helper: "612.0 s" / "10.2 min" duration text
function s = fmtDuration(sec)
    if sec >= 120
        s = sprintf('%.1f min', sec / 60);
    else
        s = sprintf('%.1f s', sec);
    end
end
