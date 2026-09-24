%% MUAProcessingParamsApp.m
% =========================================================================
% MUA PROCESSING PARAMETERS - DIALOG FOR MUA BANDPASS FILTER AND SMOOTHING
% =========================================================================
% Modal dialog opened from ExtractEphysApp when processing MUA. Presets
% (Standard MUA 300–3000 Hz, Broadband 500–5000 Hz), filter type
% (Butterworth, Chebyshev I) with a one-line description of each, order,
% low/high cutoff (Hz), display smoothing (ms) and a raw-overlay option.
% Built with UIKit.dialog.
%
% Contract: dlg = MUAProcessingParamsApp(); uiwait(dlg.UIFig); p = dlg.Params;
%   Params is empty when cancelled/closed. On OK it has filterType, order,
%   lowCutoff, highCutoff, smoothMs, autoSmooth and overlayRaw, and the
%   dialog deletes its UIFig. Smoothing only affects the displayed envelope;
%   ExtractEphysApp saves the unsmoothed bandpassed signal.
% Last-used values are remembered in getpref('NeuroAnalyzer','MUAProcessingParams').
% Help button opens HelpApp on the "Filtering" tab.
% =========================================================================

classdef MUAProcessingParamsApp < handle
    %% PROPERTIES: UI dropdowns/fields and Params (filled on OK)
    properties
        UIFig
        PresetMenu          % Custom / Standard MUA / Broadband MUA
        FilterTypeMenu      % Butterworth / Chebyshev I
        FilterHint          % One-line description of the chosen filter type
        OrderEdit           % Filter order (integer)
        FreqLowEdit         % Low cutoff (Hz)
        FreqHighEdit        % High cutoff (Hz)
        AutoSmoothCheckbox  % Auto-smooth (2 ms)
        SmoothEdit          % Smoothing window (ms) when auto is off
        OverlayCheckbox     % Overlay raw signal on the plot
        ApplyBtn            % OK (primary)
        CancelBtn
        Params
    end

    properties (Constant, Access = private)
        PrefName = 'MUAProcessingParams'
        Presets = {'Custom', 'Standard MUA (300–3000 Hz, Butter, 4)', 'Broadband MUA (500–5000 Hz)'}
        FilterTypes = {'Butterworth', 'Chebyshev I'}
    end

    methods
        %% Constructor - Build dialog
        function app = MUAProcessingParamsApp()
            app.buildUI();
        end

        %% buildUI - UIKit dialog: preset, filter design, smoothing, overlay + Cancel/OK
        function buildUI(app)
            T = UITheme;
            P = MUAProcessingParamsApp.Presets;
            defaults = struct('preset', P{2}, 'filterType', 'Butterworth', 'order', 4, ...
                'lowCutoff', 300, 'highCutoff', 3000, 'autoSmooth', true, 'smoothMs', 2, ...
                'overlayRaw', false);
            v = loadPrefs(MUAProcessingParamsApp.PrefName, defaults);
            if ~any(strcmp(v.preset, P)), v.preset = defaults.preset; end
            if ~any(strcmp(v.filterType, MUAProcessingParamsApp.FilterTypes))
                v.filterType = defaults.filterType;
            end

            D = UIKit.dialog('MUA Processing', 'Bandpass filter for multi-unit activity', ...
                'Filtering', [470 520]);
            app.UIFig = D.Fig;
            app.UIFig.CloseRequestFcn = @(~,~)app.cancel();
            ch = T.controlHeight;
            D.Body.RowHeight = {ch, ch, 34, ch, ch, ch, ch, ch, ch, '1x'};
            D.Body.ColumnWidth = {'1x', '1.3x'};

            app.PresetMenu = UIKit.field(D.Body, 'Preset', 'dropdown', {P, v.preset}, ...
                'Fill in a standard filter; editing any value switches to Custom');
            app.PresetMenu.ValueChangedFcn = @(~,~)app.applyPreset();

            app.FilterTypeMenu = UIKit.field(D.Body, 'Filter type', 'dropdown', ...
                {MUAProcessingParamsApp.FilterTypes, v.filterType}, ...
                'Filter design used for the zero-phase bandpass');
            app.FilterTypeMenu.ValueChangedFcn = @(~,~)app.onValueEdited();
            app.FilterHint = UIKit.hint(D.Body, '');
            app.FilterHint.Parent.Parent.Layout.Row = 3;
            app.FilterHint.Parent.Parent.Layout.Column = [1 2];

            app.OrderEdit = UIKit.field(D.Body, 'Filter order', 'numeric', v.order, ...
                'Higher order = steeper roll-off (4 is typical)', [1 20]);
            app.OrderEdit.RoundFractionalValues = 'on';
            app.OrderEdit.ValueChangedFcn = @(~,~)app.onValueEdited();
            app.FreqLowEdit = UIKit.field(D.Body, 'Low cutoff (Hz)', 'numeric', v.lowCutoff, ...
                'Lower edge of the passband', [0 Inf]);
            app.FreqLowEdit.LowerLimitInclusive = 'off';
            app.FreqLowEdit.ValueChangedFcn = @(~,~)app.onValueEdited();
            app.FreqHighEdit = UIKit.field(D.Body, 'High cutoff (Hz)', 'numeric', v.highCutoff, ...
                'Upper edge of the passband; must be below half the raw sampling rate', [0 Inf]);
            app.FreqHighEdit.LowerLimitInclusive = 'off';
            app.FreqHighEdit.ValueChangedFcn = @(~,~)app.onValueEdited();

            app.AutoSmoothCheckbox = UIKit.field(D.Body, 'Auto-smooth (2 ms)', 'checkbox', v.autoSmooth, ...
                'Use a 2 ms window for the displayed envelope');
            app.AutoSmoothCheckbox.ValueChangedFcn = @(~,~)app.updateControls();
            app.SmoothEdit = UIKit.field(D.Body, 'Smoothing window (ms)', 'numeric', v.smoothMs, ...
                'Width of the moving average used for the displayed envelope', [0 Inf]);
            app.SmoothEdit.LowerLimitInclusive = 'off';

            app.OverlayCheckbox = UIKit.field(D.Body, 'Overlay raw signal on plot', 'checkbox', ...
                v.overlayRaw, 'Draw the unfiltered signal in gray behind the MUA trace');

            lbl = UIKit.hint(D.Body, ['Smoothing only changes the displayed envelope (rectified, ' ...
                'smoothed MUA). The saved signal is the unsmoothed bandpassed trace used for spike detection.']);
            lbl.Parent.Parent.Layout.Row = 10;
            lbl.Parent.Parent.Layout.Column = [1 2];

            app.CancelBtn = UIKit.button(D.Buttons, 'Cancel', @(~,~)app.cancel(), 'secondary', ...
                'Close without processing');
            app.CancelBtn.Layout.Column = 2;
            app.ApplyBtn = UIKit.button(D.Buttons, 'OK', @(~,~)app.applyParams(), 'primary', ...
                'Filter the selected channels with these settings');
            app.ApplyBtn.Layout.Column = 3;

            app.updateControls();
        end

        %% updateControls - Smoothing field follows Auto; refresh filter hint
        function updateControls(app)
            if app.AutoSmoothCheckbox.Value
                app.SmoothEdit.Enable = 'off';
            else
                app.SmoothEdit.Enable = 'on';
            end
            switch app.FilterTypeMenu.Value
                case 'Chebyshev I'
                    app.FilterHint.Text = ['Chebyshev I: steeper roll-off at the same order, ' ...
                        'with 0.5 dB ripple in the passband.'];
                otherwise
                    app.FilterHint.Text = ['Butterworth: maximally flat passband with a gentle ' ...
                        'roll-off. The safe default for MUA.'];
            end
        end

        %% applyPreset - Fill filter fields from the chosen preset
        function applyPreset(app)
            switch find(strcmp(app.PresetMenu.Value, MUAProcessingParamsApp.Presets))
                case 2 % Standard MUA
                    app.FilterTypeMenu.Value = 'Butterworth';
                    app.OrderEdit.Value = 4;
                    app.FreqLowEdit.Value = 300;
                    app.FreqHighEdit.Value = 3000;
                case 3 % Broadband
                    app.FilterTypeMenu.Value = 'Butterworth';
                    app.OrderEdit.Value = 4;
                    app.FreqLowEdit.Value = 500;
                    app.FreqHighEdit.Value = 5000;
            end
            app.updateControls();
        end

        %% onValueEdited - Manual edit of a filter value: preset becomes Custom
        function onValueEdited(app)
            app.PresetMenu.Value = MUAProcessingParamsApp.Presets{1};
            app.updateControls();
        end

        %% applyParams - Validate; keep the dialog open on bad input
        function applyParams(app)
            order = app.OrderEdit.Value;
            lowCutoff = app.FreqLowEdit.Value;
            highCutoff = app.FreqHighEdit.Value;
            smoothMs = app.SmoothEdit.Value;
            if ~isfinite(order) || order < 1 || order ~= round(order)
                UIKit.alert(app.UIFig, 'Filter order must be a positive integer.', 'Invalid Parameters');
                return;
            end
            if ~isfinite(lowCutoff) || ~isfinite(highCutoff) || lowCutoff <= 0 || highCutoff <= lowCutoff
                UIKit.alert(app.UIFig, 'Cutoffs must satisfy 0 < Low < High (Hz).', 'Invalid Parameters');
                return;
            end
            if ~app.AutoSmoothCheckbox.Value && (~isfinite(smoothMs) || smoothMs <= 0)
                UIKit.alert(app.UIFig, 'Smoothing window must be a positive number of ms.', 'Invalid Parameters');
                return;
            end

            savePrefs(MUAProcessingParamsApp.PrefName, struct('preset', app.PresetMenu.Value, ...
                'filterType', app.FilterTypeMenu.Value, 'order', order, 'lowCutoff', lowCutoff, ...
                'highCutoff', highCutoff, 'autoSmooth', logical(app.AutoSmoothCheckbox.Value), ...
                'smoothMs', smoothMs, 'overlayRaw', logical(app.OverlayCheckbox.Value)));

            app.Params = struct();
            app.Params.filterType = app.FilterTypeMenu.Value;
            app.Params.order = order;
            app.Params.lowCutoff = lowCutoff;
            app.Params.highCutoff = highCutoff;
            app.Params.smoothMs = smoothMs;
            app.Params.autoSmooth = logical(app.AutoSmoothCheckbox.Value);
            app.Params.overlayRaw = logical(app.OverlayCheckbox.Value);
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
            d = defaults.(f{k});
            if ischar(d)
                ok = ischar(x);
            else
                ok = isscalar(x) && strcmp(class(x), class(d)) && ~(isnumeric(x) && ~isfinite(x));
            end
            if ok, v.(f{k}) = x; end
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
