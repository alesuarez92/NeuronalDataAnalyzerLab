%% Validation.m
% =========================================================================
% VALIDATION - STATIC HELPERS FOR DATA AND PARAMETER VALIDATION
% =========================================================================
% Used by DataLoader, ExtractLDFApp, and unit tests. All methods are static.
% - isValidLDFStruct(d): checks that a loaded struct has the required LDF
%   export fields (data, datastart, dataend) so we can safely index into it.
% - cropRange(startSec, endSec, durationSec): validates a time range for
%   cropping (numeric, start < end, within [0, durationSec]); returns
%   [ok, msg] for caller to show errordlg if not ok.
% =========================================================================

classdef Validation
    methods(Static)

        %% isValidLDFStruct - Check if struct has required LDF export format
        % -----------------------------------------------------------------
        % INPUT:  d - struct (e.g. from load('file.mat'))
        % OUTPUT: ok - true if d has fields 'data', 'datastart', 'dataend',
        %              and data is a numeric vector, datastart/dataend numeric.
        % Used by DataLoader.load() before indexing d.data(d.datastart(i):...).
        % -----------------------------------------------------------------
        function ok = isValidLDFStruct(d)
            ok = false;
            if ~isstruct(d)
                return;
            end
            required = {'data', 'datastart', 'dataend'};
            for i = 1:numel(required)
                if ~isfield(d, required{i})
                    return;
                end
            end
            if ~isvector(d.data) || ~isnumeric(d.data)
                return;
            end
            if ~isnumeric(d.datastart) || ~isnumeric(d.dataend)
                return;
            end
            ok = true;
        end

        %% cropRange - Validate crop time range against signal duration
        % -----------------------------------------------------------------
        % INPUT:  startSec, endSec - crop window in seconds (user input)
        %         durationSec - total signal length in seconds (e.g. N/Fs)
        % OUTPUT: ok - true if range is valid
        %         msg - empty if ok; otherwise error message for errordlg
        % Checks: numeric, not NaN, start < end, 0 <= start, end <= durationSec.
        % -----------------------------------------------------------------
        function [ok, msg] = cropRange(startSec, endSec, durationSec)
            msg = '';
            if isempty(startSec) || isempty(endSec) || ~isnumeric(startSec) || ~isnumeric(endSec)
                ok = false;
                msg = 'Start and End must be numeric values.';
                return;
            end
            if isnan(startSec) || isnan(endSec)
                ok = false;
                msg = 'Start and End times must be numeric values.';
                return;
            end
            if startSec >= endSec
                ok = false;
                msg = 'Start time must be less than End time.';
                return;
            end
            if startSec < 0 || endSec > durationSec
                ok = false;
                msg = sprintf('Range must be within 0 and %.2f s (signal duration).', durationSec);
                return;
            end
            ok = true;
        end
    end
end
