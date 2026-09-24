%% LFPProcessingParamsApp.m
% =========================================================================
% LFP PROCESSING PARAMETERS - DIALOG FOR LFP FILTER AND DOWNSAMPLE
% =========================================================================
% Modal dialog opened from ExtractEphysApp when processing LFP. User sets
% an optional lowpass cutoff (Hz), an optional 60 Hz notch and an optional
% downsample rate (Hz). Built with UIKit.dialog.
%
% Contract: dlg = LFPProcessingParamsApp(); uiwait(dlg.UIFig); p = dlg.Params;
%   Params is empty when the dialog is cancelled or closed. On OK it has
%   lowCutoff (Hz; NaN = no lowpass), notch60, downsample (logical) and
%   downsampleRate (Hz), and the dialog deletes its UIFig.
% Last-used values are remembered in getpref('NeuroAnalyzer','LFPProcessingParams').
% Help button opens HelpApp on the "Filtering" tab.
% =========================================================================

classdef LFPProcessingParamsApp < handle
    %% PROPERTIES: UI controls and Params (filled on OK)
    properties
        UIFig
        LowpassCheckbox     % Apply lowpass filter
        FreqLowEdit         % Lowpass cutoff (Hz), numeric
        NotchCheckbox       % Apply 60 Hz notch
        DownsampleCheckbox  % Downsample after anti-alias filtering
        DownsampleRateEdit  % Target rate (Hz), numeric
        ApplyBtn            % OK (primary)
        CancelBtn
        Params
    end

    properties (Constant, Access = private)
        PrefName = 'LFPProcessingParams'
    end

    methods
        %% Constructor - Build dialog
        function app = LFPProcessingParamsApp()
            app.buildUI();
        end

        %% buildUI - UIKit dialog: lowpass, notch, downsample rows + hint + Cancel/OK
        function buildUI(app)
            T = UITheme;
            defaults = struct('useLowpass', true, 'lowCutoff', 300, 'notch60', false, ...
                'downsample', true, 'downsampleRate', 1000);
            v = loadPrefs(LFPProcessingParamsApp.PrefName, defaults);

            D = UIKit.dialog('LFP Processing', 'Lowpass, notch and downsampling for LFP', ...
                'Filtering', [440 390]);
            app.UIFig = D.Fig;
            app.UIFig.CloseRequestFcn = @(~,~)app.cancel();
            D.Body.RowHeight = {T.controlHeight, T.controlHeight, T.controlHeight, ...
                T.controlHeight, T.controlHeight, '1x'};
            D.Body.ColumnWidth = {'1.3x', '1x'};

            app.LowpassCheckbox = UIKit.field(D.Body, 'Apply lowpass filter', 'checkbox', ...
                v.useLowpass, 'Zero-phase 4th-order Butterworth lowpass (applied after downsampling)');
            app.LowpassCheckbox.ValueChangedFcn = @(~,~)app.updateControls();
            app.FreqLowEdit = UIKit.field(D.Body, 'Lowpass cutoff (Hz)', 'numeric', v.lowCutoff, ...
                'Frequencies above this are removed; must be below half the (new) sampling rate', [0 Inf]);
            app.FreqLowEdit.LowerLimitInclusive = 'off';

            app.NotchCheckbox = UIKit.field(D.Body, 'Apply 60 Hz notch', 'checkbox', v.notch60, ...
                'Remove 60 Hz mains interference with a narrow notch filter');

            app.DownsampleCheckbox = UIKit.field(D.Body, 'Downsample', 'checkbox', v.downsample, ...
                'Anti-alias filter, then keep every n-th sample (smaller files, faster analysis)');
            app.DownsampleCheckbox.ValueChangedFcn = @(~,~)app.updateControls();
            app.DownsampleRateEdit = UIKit.field(D.Body, 'Target rate (Hz)', 'numeric', v.downsampleRate, ...
                'Requested LFP sampling rate; must be below the raw rate', [0 Inf]);
            app.DownsampleRateEdit.LowerLimitInclusive = 'off';

            lbl = UIKit.hint(D.Body, ['The real LFP rate is the raw rate divided by a whole number ' ...
                '(e.g. 24414.06 Hz / 24 = 1017.25 Hz); that exact rate is used and saved. ' ...
                'Leave lowpass off to keep the full band.']);
            lbl.Parent.Parent.Layout.Row = 6;
            lbl.Parent.Parent.Layout.Column = [1 2];

            app.CancelBtn = UIKit.button(D.Buttons, 'Cancel', @(~,~)app.cancel(), 'secondary', ...
                'Close without processing');
            app.CancelBtn.Layout.Column = 2;
            app.ApplyBtn = UIKit.button(D.Buttons, 'OK', @(~,~)app.applyParams(), 'primary', ...
                'Process the selected channels with these settings');
            app.ApplyBtn.Layout.Column = 3;

            app.updateControls();
        end

        %% updateControls - Cutoff/rate fields follow their checkboxes
        function updateControls(app)
            app.FreqLowEdit.Enable = onOff(app.LowpassCheckbox.Value);
            app.DownsampleRateEdit.Enable = onOff(app.DownsampleCheckbox.Value);
        end

        %% applyParams - Validate inputs; on error show an alert and keep dialog open
        function applyParams(app)
            useLowpass = logical(app.LowpassCheckbox.Value);
            doDownsample = logical(app.DownsampleCheckbox.Value);
            lowCutoff = app.FreqLowEdit.Value;
            downsampleRate = app.DownsampleRateEdit.Value;

            % Lowpass is optional (off = skip), but if used it must be valid
            if useLowpass && (~isfinite(lowCutoff) || lowCutoff <= 0)
                UIKit.alert(app.UIFig, 'Lowpass cutoff must be a positive number (or turn lowpass off).', ...
                    'Invalid Parameters');
                return;
            end
            if doDownsample && (~isfinite(downsampleRate) || downsampleRate <= 0)
                UIKit.alert(app.UIFig, 'Downsample rate must be a positive number (Hz).', 'Invalid Parameters');
                return;
            end

            savePrefs(LFPProcessingParamsApp.PrefName, struct('useLowpass', useLowpass, ...
                'lowCutoff', lowCutoff, 'notch60', logical(app.NotchCheckbox.Value), ...
                'downsample', doDownsample, 'downsampleRate', downsampleRate));

            if ~useLowpass, lowCutoff = NaN; end   % NaN = skip lowpass (caller checks isnan)
            app.Params = struct();
            app.Params.lowCutoff = lowCutoff;
            app.Params.notch60 = logical(app.NotchCheckbox.Value);
            app.Params.downsample = doDownsample;
            app.Params.downsampleRate = downsampleRate;
            delete(app.UIFig);
        end

        %% cancel - Close without Params (also the window close button)
        function cancel(app)
            app.Params = [];
            delete(app.UIFig);
        end
    end
end

%% Local helper: 'on'/'off' from a logical
function s = onOff(tf)
    if tf, s = 'on'; else, s = 'off'; end
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
