function out = imageStackNormalize(stack, mode, lowHigh)
% imageStackNormalize - Normalize stack to 0-1 or percentile range.
%
% mode: 'minmax' (full stack min/max), 'percentile' (lowHigh = [pLow pHigh], e.g. [1 99]),
%       'frame' (each frame normalized to its own min/max).
% INPUT: stack H x W x N. lowHigh optional for percentile.
% OUTPUT: double, same size, values in [0 1].
%
if nargin < 2, mode = 'minmax'; end
if nargin < 3, lowHigh = [1 99]; end

stack = double(stack);
switch lower(mode)
    case 'frame'
        out = zeros(size(stack));
        for k = 1:size(stack, 3)
            f = stack(:, :, k);
            mn = min(f(:)); mx = max(f(:));
            if mx > mn
                out(:, :, k) = (f - mn) / (mx - mn);
            else
                out(:, :, k) = 0;
            end
        end
    case 'percentile'
        pl = lowHigh(1); ph = lowHigh(2);
        mn = pctl(stack(:), pl);
        mx = pctl(stack(:), ph);
        out = (stack - mn) / (mx - mn + eps);
        out = max(0, min(1, out));
    otherwise
        mn = min(stack(:));
        mx = max(stack(:));
        out = (stack - mn) / (mx - mn + eps);
end
end

function v = pctl(x, p)
% Percentile with linear interpolation; toolbox-free stand-in for prctile.
x = sort(x(isfinite(x(:))));
n = numel(x);
if n == 0, v = NaN; return; end
if n == 1, v = x; return; end
pos = 1 + (n - 1) * p / 100;
lo = floor(pos);
hi = min(lo + 1, n);
v = x(lo) + (pos - lo) * (x(hi) - x(lo));
end
