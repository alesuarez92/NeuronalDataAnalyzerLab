function [dff, t, F0] = deltaFOverF(stack, mask, timeVec, baselineMode, baselineWindow)
% deltaFOverF - Compute (F - F0) / F0 in ROI over time (e.g. gCaMP, fluorescence).
%
% F0 = baseline. baselineMode: 'first' (mean of first N frames), 'percentile' (e.g. 10th),
% 'rolling' (rolling median, window in frames), or 'mean' (mean of full trace).
%
% Usage:
%   [dff, t, F0] = deltaFOverF(stack, mask, timeVec, 'first', 30);
%   [dff, t, F0] = deltaFOverF(stack, mask, timeVec, 'percentile', 10);
%
% INPUT:
%   stack   - H x W x N or H x W x 3 x N.
%   mask    - H x W logical.
%   timeVec - (optional) 1 x N.
%   baselineMode - 'first', 'percentile', 'rolling', or 'mean'.
%   baselineWindow - for 'first': number of frames; for 'percentile': 0-100; for 'rolling': window length.
% OUTPUT:
%   dff - 1 x N, (F - F0) / F0.
%   t  - 1 x N.
%   F0 - scalar or 1 x N (for rolling).
%
if nargin < 3, timeVec = []; end
if nargin < 4, baselineMode = 'first'; end
if nargin < 5, baselineWindow = 30; end

[intensity, t] = roiIntensityOverTime(stack, mask, timeVec);
F = intensity;
N = numel(F);

switch lower(baselineMode)
    case 'first'
        n = min(baselineWindow, N);
        F0 = mean(F(1:n));
        dff = (F - F0) / (F0 + eps);
    case 'percentile'
        p = max(0, min(100, baselineWindow));
        F0 = prctile(F, p);
        dff = (F - F0) / (F0 + eps);
    case 'mean'
        F0 = mean(F);
        dff = (F - F0) / (F0 + eps);
    case 'rolling'
        w = max(1, round(baselineWindow));
        F0 = movmedian(F, w);
        dff = (F - F0) ./ (F0 + eps);
    otherwise
        F0 = mean(F(1:min(30, N)));
        dff = (F - F0) / (F0 + eps);
end
end
