function [y, isOutlier, med, sigma] = robustTimeSeries(x, window, nMad)
% robustTimeSeries - Hampel-style outlier rejection for a 1-D time series.
%
% Slides a window over the series and, for every sample, compares it with
% the running median of the window. A sample is an outlier when it lies
% more than nMad robust standard deviations from that median, where the
% robust standard deviation is 1.4826 x the median absolute deviation
% (MAD) of the window (1.4826 makes the MAD match the standard deviation
% for Gaussian noise). Outliers, and NaN samples, are replaced by the
% running median. Used for per-frame measurements that suffer isolated
% spikes, e.g. a vessel diameter that jumps when a red blood cell crosses
% the measurement line.
%
% Usage:
%   y = robustTimeSeries(x);                 % window 7 samples, 3 MAD
%   [y, isOutlier, med, sigma] = robustTimeSeries(x, 7, 3);
%
% INPUT:
%   x      - 1 x N or N x 1 numeric vector (NaN allowed).
%   window - (optional) window length in samples, default 7. Even values
%            are rounded up to the next odd number; windows are truncated
%            at the ends of the series.
%   nMad   - (optional) threshold in robust standard deviations, default 3.
% OUTPUT:
%   y         - same size as x, outliers and NaNs replaced by the running median.
%   isOutlier - logical, same size as x; true where a value was replaced
%               (including NaN samples that could be filled).
%   med       - running median (same size as x).
%   sigma     - running robust standard deviation, 1.4826 * MAD (same size as x).
%
% Method: Hampel identifier (running median / MAD). The median and MAD
% ignore NaN samples; a window with no finite samples leaves the value NaN.
% Toolbox-free (base MATLAB only).
%
if nargin < 2 || isempty(window), window = 7; end
if nargin < 3 || isempty(nMad), nMad = 3; end
window = max(1, round(window));
if mod(window, 2) == 0, window = window + 1; end
half = (window - 1) / 2;

sz = size(x);
x = double(x(:));
n = numel(x);
med = NaN(n, 1);
sigma = NaN(n, 1);
for k = 1:n
    w = x(max(1, k - half):min(n, k + half));
    w = w(isfinite(w));
    if isempty(w), continue; end
    m = median(w);
    med(k) = m;
    sigma(k) = 1.4826 * median(abs(w - m));
end
% A window of identical values has MAD = 0; use a tiny floor so exact
% repeats of the median are not flagged while any real deviation is.
floorSigma = 1e-9 * max(1, abs(med));
isOutlier = isfinite(med) & (~isfinite(x) | abs(x - med) > nMad * max(sigma, floorSigma));
y = x;
y(isOutlier) = med(isOutlier);

y = reshape(y, sz);
isOutlier = reshape(isOutlier, sz);
med = reshape(med, sz);
sigma = reshape(sigma, sz);
end
