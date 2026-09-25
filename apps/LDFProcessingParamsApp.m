%% LDFProcessingParamsApp.m
% =========================================================================
% LDF PROCESSING PARAMETERS - DIALOG FOR FILTER AND DOWNSAMPLE SETTINGS
% =========================================================================
% Modal UIKit.dialog opened from ProcessingLDFApp (step 2 "Settings...").
% Parent passes a callback and the loaded sampling rate. User selects:
% Downsample (1x, 2x, 5x, 10x), Filter type (None, Low-pass, High-pass,
% Band-pass, Notch), Design (Butterworth, Chebyshev I, FIR), Low/High
% cutoff (Hz) and Order. A live preview shows the effective sampling
% rate and Nyquist after downsampling; settings are validated as they
% change (inline message, Apply disabled while invalid). Cutoff fields
% are enabled and given defaults based on the filter type and the
% post-downsample Nyquist (updateCutoffFields). On Apply,
% ParentCallback(params) is called and the dialog closes; Cancel closes
% without calling it (Params stays empty). Last-used settings are kept
% in getpref('NeuroAnalyzer', 'LDFProcessingParams'). "? Filter help"
% opens HelpApp on the Filtering tab; the header Help opens 'LDF Process'.
%
% params struct: downsample (1|2|5|10), filterType (1-5 menu index),
% designType (1-3 menu index), filterOrder, cutoffLow, cutoffHigh (NaN
% when the field does not apply to the filter type).
% =========================================================================

classdef LDFProcessingParamsApp < handle
    %% PROPERTIES
    properties
        UIFig          % Modal uifigure (UIKit.dialog)
        DSMenu         % dropdown: downsample factor (1x, 2x, 5x, 10x)
        FilterMenu     % (unused; kept for compatibility)
        FilterTypeMenu % dropdown: None, Low-pass, High-pass, Band-pass, Notch
        DesignMenu     % dropdown: Butterworth, Chebyshev I, FIR
        CutoffLow      % numeric: low cutoff (Hz); high-pass, band-pass, notch
        CutoffHigh     % numeric: high cutoff (Hz); low-pass, band-pass, notch
        OrderEdit      % numeric: filter order (positive integer)
        PreviewLabel   % effective Fs / Nyquist after downsampling
        MessageLabel   % inline validation message
        ApplyBtn       % OK / Apply (primary)
        CancelBtn      % Cancel
        FilterHelpBtn  % "? Filter help" -> HelpApp('Filtering')
        ParentCallback % function handle: called with params struct on Apply
        SamplingRate   % scalar: loaded Fs (Hz), before downsampling
        Params = []    % params passed to ParentCallback (empty if cancelled)
    end

    properties (Constant, Access = private)
        DSOptions   = [1, 2, 5, 10]
        DSItems     = {'1x (none)', '2x', '5x', '10x'}
        TypeItems   = {'None', 'Low-pass', 'High-pass', 'Band-pass', 'Notch (band-stop)'}
        DesignItems = {'Butterworth', 'Chebyshev I (0.5 dB ripple)', 'FIR (window)'}
    end

    methods
        %% Constructor - Store callback and Fs, then build UI
        function app = LDFProcessingParamsApp(parentCallback, samplingRate)
            app.ParentCallback = parentCallback;
            app.SamplingRate = samplingRate;
            app.buildUI();
        end

        %% buildUI - Dialog form, preview, validation message and buttons
        % -------------------------------------------------------------
        % Rows: Downsample | Effective rate (preview) | Filter type |
        % Design | Low cutoff (Hz) | High cutoff (Hz) | Order | message.
        % Restores the last-used settings, then validates.
        % -------------------------------------------------------------
        function buildUI(app)
            T = UITheme;
            D = UIKit.dialog('LDF processing settings', ...
                sprintf('Downsample and filter the LDF (loaded at %g Hz)', app.SamplingRate), ...
                'LDF Process', [460 470]);
            app.UIFig = D.Fig;
            ch = T.controlHeight;
            D.Body.ColumnWidth = {150, '1x'};
            D.Body.RowHeight = {ch, 22, ch, ch, ch, ch, ch, 40};

            app.DSMenu = addField(D.Body, 1, 'Downsample', 'dropdown', {app.DSItems, app.DSItems{1}}, ...
                'Reduce the sampling rate before filtering (LDF is decimated with an anti-alias filter)');
            lbl = uilabel(D.Body, 'Text', 'Effective rate', 'FontSize', T.fontBody, ...
                'FontColor', T.sectionTitleColor, 'Tooltip', 'Sampling rate and Nyquist frequency after downsampling');
            lbl.Layout.Row = 2; lbl.Layout.Column = 1;
            app.PreviewLabel = uilabel(D.Body, 'Text', '', 'FontSize', T.fontSmall, ...
                'FontColor', T.info, 'Tooltip', 'Cutoffs must stay below the Nyquist frequency');
            app.PreviewLabel.Layout.Row = 2; app.PreviewLabel.Layout.Column = 2;

            app.FilterTypeMenu = addField(D.Body, 3, 'Filter type', 'dropdown', {app.TypeItems, app.TypeItems{1}}, ...
                'Low-pass smooths noise, high-pass removes drift, band-pass keeps a band, notch removes a narrow band');
            app.DesignMenu = addField(D.Body, 4, 'Design', 'dropdown', {app.DesignItems, app.DesignItems{1}}, ...
                'Butterworth: flat pass band (recommended). Chebyshev I: steeper, 0.5 dB ripple. FIR: linear phase, needs a higher order');
            app.CutoffLow = addField(D.Body, 5, 'Low cutoff (Hz)', 'numeric', 0.5, ...
                'Lower edge (high-pass, band-pass, notch); must be > 0 and below Nyquist', [0 Inf]);
            app.CutoffLow.LowerLimitInclusive = 'off';
            app.CutoffHigh = addField(D.Body, 6, 'High cutoff (Hz)', 'numeric', 5, ...
                'Upper edge (low-pass, band-pass, notch); must be below Nyquist', [0 Inf]);
            app.CutoffHigh.LowerLimitInclusive = 'off';
            app.OrderEdit = addField(D.Body, 7, 'Order', 'numeric', 4, ...
                'Filter order: higher = steeper roll-off (typical 2-6 for IIR, 50+ for FIR)', [1 Inf]);
            app.OrderEdit.RoundFractionalValues = 'on';

            app.MessageLabel = uilabel(D.Body, 'Text', '', 'FontSize', T.fontSmall, ...
                'FontColor', T.danger, 'WordWrap', 'on', 'VerticalAlignment', 'top');
            app.MessageLabel.Layout.Row = 8; app.MessageLabel.Layout.Column = [1 2];

            app.DSMenu.ValueChangedFcn = @(~,~)app.updateCutoffFields(app.filterTypeIndex());
            app.FilterTypeMenu.ValueChangedFcn = @(~,~)app.updateCutoffFields(app.filterTypeIndex());
            for c = {app.DesignMenu, app.CutoffLow, app.CutoffHigh, app.OrderEdit}
                c{1}.ValueChangedFcn = @(~,~)app.validate();
            end

            % Buttons: "? Filter help" (left), Cancel, Apply
            app.FilterHelpBtn = UIKit.button(D.Buttons, '? Filter help', @(~,~)HelpApp('Filtering'), ...
                'secondary', 'How low-pass, high-pass, band-pass and notch filters work');
            app.FilterHelpBtn.Layout.Row = 1; app.FilterHelpBtn.Layout.Column = 1;
            app.CancelBtn = UIKit.button(D.Buttons, 'Cancel', @(~,~)delete(app.UIFig), ...
                'secondary', 'Close without changing the processing');
            app.CancelBtn.Layout.Row = 1; app.CancelBtn.Layout.Column = 2;
            app.ApplyBtn = UIKit.button(D.Buttons, 'Apply', @(~,~)app.applySettings(), ...
                'primary', 'Apply these settings to the loaded LDF and close');
            app.ApplyBtn.Layout.Row = 1; app.ApplyBtn.Layout.Column = 3;

            app.restoreSettings();
        end

        %% applySettings - Read UI, validate, build params struct, call parent, close
        % -------------------------------------------------------------
        % params: downsample, filterType (menu index), designType (index),
        % filterOrder, cutoffLow, cutoffHigh (NaN when field disabled).
        % Invalid settings keep the dialog open with an inline message.
        % Valid: remember settings, hide the dialog, ParentCallback(params),
        % then close.
        % -------------------------------------------------------------
        function applySettings(app)
            [ok, msg] = app.validate();
            if ~ok
                UIKit.alert(app.UIFig, msg, 'Invalid settings', 'error');
                return;
            end
            params = app.readParams();
            app.Params = params;
            try
                setpref('NeuroAnalyzer', 'LDFProcessingParams', params);
            catch
                % Preferences are a convenience only
            end
            app.UIFig.Visible = 'off';
            try
                app.ParentCallback(params);
            catch ME
                delete(app.UIFig);
                rethrow(ME);
            end
            if isvalid(app.UIFig), delete(app.UIFig); end
        end

        %% readParams - Build the params struct from the controls
        function params = readParams(app)
            params.downsample = app.DSOptions(app.dsIndex());
            params.filterType = app.filterTypeIndex();
            params.designType = find(strcmp(app.DesignMenu.Items, app.DesignMenu.Value), 1);
            params.filterOrder = app.OrderEdit.Value;
            if strcmp(app.CutoffLow.Enable, 'on')
                params.cutoffLow = app.CutoffLow.Value;
            else
                params.cutoffLow = NaN;
            end
            if strcmp(app.CutoffHigh.Enable, 'on')
                params.cutoffHigh = app.CutoffHigh.Value;
            else
                params.cutoffHigh = NaN;
            end
        end

        %% validate - Check settings, update preview/message and Apply state
        % Same rules ProcessingLDFApp.applyFilter enforces: order > 0,
        % enabled cutoffs > 0 and below the post-downsample Nyquist,
        % low < high for band-pass and notch.
        function [ok, msg] = validate(app)
            nyq = app.effectiveFs() / 2;
            app.PreviewLabel.Text = sprintf('%g Hz  (Nyquist %g Hz)', app.effectiveFs(), nyq);
            p = app.readParams();
            msg = '';
            if isnan(p.filterOrder) || p.filterOrder <= 0
                msg = 'Filter order must be a positive number.';
            elseif p.filterType ~= 1
                if ~isnan(p.cutoffLow) && (p.cutoffLow <= 0 || p.cutoffLow >= nyq)
                    msg = sprintf('Low cutoff must be between 0 and the Nyquist frequency (%g Hz).', nyq);
                elseif ~isnan(p.cutoffHigh) && (p.cutoffHigh <= 0 || p.cutoffHigh >= nyq)
                    msg = sprintf('High cutoff must be between 0 and the Nyquist frequency (%g Hz).', nyq);
                elseif ismember(p.filterType, [4, 5]) && p.cutoffLow >= p.cutoffHigh
                    msg = 'For band-pass and notch filters, Low cutoff must be below High cutoff.';
                end
            end
            ok = isempty(msg);
            app.MessageLabel.Text = msg;
            app.ApplyBtn.Enable = onoff(ok);
            app.DesignMenu.Enable = onoff(p.filterType ~= 1);
            app.OrderEdit.Enable = onoff(p.filterType ~= 1);
        end

        %% updateCutoffFields - Enable/disable cutoff fields and set defaults by filter type
        % -------------------------------------------------------------
        % filterType: 1=None, 2=Low-pass, 3=High-pass, 4=Band-pass, 5=Notch.
        % Low-pass: only High cutoff; High-pass: only Low; Band/Notch: both.
        % Defaults use the effective Nyquist after downsampling
        % (Fs/factor/2), since filtering runs after downsampling: e.g.
        % low-pass high = 0.5*nyq. Also called when Downsample changes.
        % -------------------------------------------------------------
        function updateCutoffFields(app, filterType)
            nyq = app.effectiveFs() / 2;
            app.setCutoffEnable(filterType);
            switch filterType
                case 2  % Low-pass
                    app.CutoffHigh.Value = round(0.5 * nyq, 2);
                case 3  % High-pass
                    app.CutoffLow.Value = max(round(0.01 * nyq, 2), 0.01);
                case {4, 5}  % Band-pass or Notch
                    app.CutoffLow.Value  = max(round(0.01 * nyq, 2), 0.01);
                    app.CutoffHigh.Value = round(0.5 * nyq, 2);
            end
            app.validate();
        end
    end

    methods (Access = private)
        %% setCutoffEnable - Enable the cutoff fields that apply to filterType
        function setCutoffEnable(app, filterType)
            app.CutoffLow.Enable  = onoff(ismember(filterType, [3 4 5]));
            app.CutoffHigh.Enable = onoff(ismember(filterType, [2 4 5]));
        end

        %% restoreSettings - Last-used settings from preferences (if valid)
        function restoreSettings(app)
            s = [];
            try
                if ispref('NeuroAnalyzer', 'LDFProcessingParams')
                    s = getpref('NeuroAnalyzer', 'LDFProcessingParams');
                end
            catch
                s = [];
            end
            if isstruct(s)
                if isfield(s, 'downsample') && any(app.DSOptions == s.downsample)
                    app.DSMenu.Value = app.DSItems{app.DSOptions == s.downsample};
                end
                if isfield(s, 'filterType') && ismember(s.filterType, 1:5)
                    app.FilterTypeMenu.Value = app.TypeItems{s.filterType};
                end
                if isfield(s, 'designType') && ismember(s.designType, 1:3)
                    app.DesignMenu.Value = app.DesignItems{s.designType};
                end
                if isfield(s, 'filterOrder') && isscalar(s.filterOrder) && s.filterOrder >= 1
                    app.OrderEdit.Value = round(s.filterOrder);
                end
            end
            ft = app.filterTypeIndex();
            app.setCutoffEnable(ft);
            restored = false(1, 2);
            if isstruct(s)
                if isfield(s, 'cutoffLow') && isscalar(s.cutoffLow) && s.cutoffLow > 0
                    app.CutoffLow.Value = s.cutoffLow; restored(1) = true;
                end
                if isfield(s, 'cutoffHigh') && isscalar(s.cutoffHigh) && s.cutoffHigh > 0
                    app.CutoffHigh.Value = s.cutoffHigh; restored(2) = true;
                end
            end
            if ft ~= 1 && ~all(restored(ismember([1 2], app.neededCutoffs(ft))))
                app.updateCutoffFields(ft);   % fill missing cutoffs with defaults
            else
                app.validate();
            end
        end

        %% neededCutoffs - Which cutoffs (1 = low, 2 = high) a filter type uses
        function k = neededCutoffs(~, filterType)
            switch filterType
                case 2, k = 2;
                case 3, k = 1;
                case {4, 5}, k = [1 2];
                otherwise, k = [];
            end
        end

        %% dsIndex / filterTypeIndex - Selected dropdown positions
        function k = dsIndex(app)
            k = find(strcmp(app.DSMenu.Items, app.DSMenu.Value), 1);
        end
        function k = filterTypeIndex(app)
            k = find(strcmp(app.FilterTypeMenu.Items, app.FilterTypeMenu.Value), 1);
        end

        %% effectiveFs - Sampling rate after the selected downsampling
        function fs = effectiveFs(app)
            fs = app.SamplingRate / app.DSOptions(app.dsIndex());
        end
    end
end

%% Local helpers
% -------------------------------------------------------------------------

%% addField - UIKit.field placed on grid row 'row' (label col 1, control col 2)
function c = addField(g, row, labelText, varargin)
    c = UIKit.field(g, labelText, varargin{:});
    lbl = findobj(g, '-depth', 1, 'Type', 'uilabel', 'Text', labelText);
    if ~isempty(lbl), lbl(end).Layout.Row = row; lbl(end).Layout.Column = 1; end
    c.Layout.Row = row; c.Layout.Column = 2;
end

%% onoff - 'on'/'off' from a logical
function s = onoff(cond)
    if cond, s = 'on'; else, s = 'off'; end
end
