%% ERPConfigApp.m
% =========================================================================
% ERP CONFIGURATION - DIALOG FOR ERP WINDOW AND STIMULUS DETECTION
% =========================================================================
% Modal dialog opened from LFPAnalysisApp when configuring ERP Analysis.
% User sets pre-stimulus time, post-stimulus time, stimulus threshold, and
% minimum ISI (inter-stimulus interval) for detecting events. Built with
% UIKit.dialog.
%
% Contract: dlg = ERPConfigApp(Fs); uiwait(dlg.UIFig); p = dlg.Params;
%   Params is empty when cancelled/closed. On OK it is a struct with
%   preTime, postTime, threshold and minISI, and the dialog deletes its
%   UIFig; LFPAnalysisApp uses it to cut trials and average.
% Last-used values are remembered in getpref('NeuroAnalyzer','ERPConfigParams').
% Help button opens HelpApp on the "LFP Analysis" tab.
% =========================================================================

classdef ERPConfigApp < handle
    %% PROPERTIES: UI fields and Params struct (preTime, postTime, threshold, minISI)
    properties
        UIFig
        PreEdit         % Pre-stimulus time (s)
        PostEdit        % Post-stimulus time (s)
        ThresholdEdit   % Stimulus threshold (stim units)
        ISIEdit         % Minimum inter-stimulus interval (s)
        ConfirmBtn      % OK (primary)
        CancelBtn

        Fs              % LFP sampling rate (Hz), shown for reference
        Params
    end

    properties (Constant, Access = private)
        PrefName = 'ERPConfigParams'
    end

    methods
        %% Constructor - Store Fs, build modal dialog
        function app = ERPConfigApp(Fs)
            if nargin < 1, Fs = []; end
            app.Fs = Fs;
            app.buildUI();
        end

        %% buildUI - UIKit dialog: Pre/Post, Threshold, Min ISI + hint + Cancel/OK
        function buildUI(app)
            T = UITheme;
            defaults = struct('preTime', 0.1, 'postTime', 0.3, 'threshold', 0.5, 'minISI', 0.5);
            v = loadPrefs(ERPConfigApp.PrefName, defaults);

            if ~isempty(app.Fs) && isnumeric(app.Fs) && isscalar(app.Fs)
                sub = sprintf('Epoch window and stimulus detection  ·  LFP %.2f Hz', app.Fs);
            else
                sub = 'Epoch window and stimulus detection';
            end
            D = UIKit.dialog('ERP Configuration', sub, 'LFP Analysis', [430 370]);
            app.UIFig = D.Fig;
            app.UIFig.CloseRequestFcn = @(~,~)app.cancel();
            ch = T.controlHeight;
            D.Body.RowHeight = {ch, ch, ch, ch, '1x'};
            D.Body.ColumnWidth = {'1.3x', '1x'};

            app.PreEdit = UIKit.field(D.Body, 'Pre-stimulus time (s)', 'numeric', v.preTime, ...
                'Time kept before each stimulus onset (also the baseline shown)', [0 Inf]);
            app.PostEdit = UIKit.field(D.Body, 'Post-stimulus time (s)', 'numeric', v.postTime, ...
                'Time kept after each stimulus onset', [0 Inf]);
            app.PostEdit.LowerLimitInclusive = 'off';
            app.ThresholdEdit = UIKit.field(D.Body, 'Threshold (stim units)', 'numeric', v.threshold, ...
                'Onset = upward crossing of this level by the mean-subtracted stimulus');
            app.ISIEdit = UIKit.field(D.Body, 'Min ISI (s)', 'numeric', v.minISI, ...
                'Onsets closer than this to the previous onset are ignored', [0 Inf]);

            lbl = UIKit.hint(D.Body, ['The stimulus is mean-subtracted, then every upward crossing of ' ...
                'the threshold is an onset. Epochs that run past the start or end of the recording are skipped.']);
            lbl.Parent.Parent.Layout.Row = 5;
            lbl.Parent.Parent.Layout.Column = [1 2];

            app.CancelBtn = UIKit.button(D.Buttons, 'Cancel', @(~,~)app.cancel(), 'secondary', ...
                'Close without running the ERP analysis');
            app.CancelBtn.Layout.Column = 2;
            app.ConfirmBtn = UIKit.button(D.Buttons, 'OK', @(~,~)app.confirm(), 'primary', ...
                'Detect onsets and average the epochs');
            app.ConfirmBtn.Layout.Column = 3;
        end

        %% confirm - Validate fields, fill Params struct and close dialog
        % On invalid input show an alert and keep the dialog open (Params unset).
        function confirm(app)
            preTime   = app.PreEdit.Value;
            postTime  = app.PostEdit.Value;
            threshold = app.ThresholdEdit.Value;
            minISI    = app.ISIEdit.Value;

            if any(isnan([preTime postTime threshold minISI]))
                UIKit.alert(app.UIFig, 'All fields must be numeric.', 'Invalid ERP Settings'); return;
            end
            if preTime < 0
                UIKit.alert(app.UIFig, 'Pre-stimulus time must be >= 0.', 'Invalid ERP Settings'); return;
            end
            if postTime <= 0
                UIKit.alert(app.UIFig, 'Post-stimulus time must be > 0.', 'Invalid ERP Settings'); return;
            end
            if minISI < 0
                UIKit.alert(app.UIFig, 'Min ISI must be >= 0.', 'Invalid ERP Settings'); return;
            end

            app.Params = struct( ...
                'preTime', preTime, ...
                'postTime', postTime, ...
                'threshold', threshold, ...
                'minISI', minISI ...
            );
            savePrefs(ERPConfigApp.PrefName, app.Params);
            delete(app.UIFig);
        end

        %% cancel - Close without Params (also the window close button)
        function cancel(app)
            app.Params = [];
            delete(app.UIFig);
        end
    end
end

%% Local helper: read remembered values; fall back to defaults field by field
function v = loadPrefs(name, defaults)
    v = defaults;
    try
        s = getpref('NeuroAnalyzer', name, struct());
        f = fieldnames(defaults);
        for k = 1:numel(f)
            if ~isstruct(s) || ~isfield(s, f{k}), continue; end
            x = s.(f{k});
            if isscalar(x) && strcmp(class(x), class(defaults.(f{k}))) && ...
                    ~(isnumeric(x) && ~isfinite(x))
                v.(f{k}) = x;
            end
        end
    catch
        v = defaults;
    end
end

%% Local helper: remember values for next time (failures are not fatal)
function savePrefs(name, s)
    try
        setpref('NeuroAnalyzer', name, s);
    catch
    end
end
