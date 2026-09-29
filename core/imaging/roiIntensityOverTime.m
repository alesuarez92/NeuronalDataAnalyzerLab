function [intensity, t] = roiIntensityOverTime(stack, mask, timeVec)
% roiIntensityOverTime - Mean (or median) intensity in ROI per frame.
%
% For coregistered image stacks: computes intensity time series within
% the given ROI mask. Useful for fluorescence or brightness change over time.
%
% Usage:
%   [intensity, t] = roiIntensityOverTime(stack, mask);
%   [intensity, t] = roiIntensityOverTime(stack, mask, timeVec);
%
% INPUT:
%   stack - H x W x N (grayscale) or H x W x 3 x N (RGB; will use mean across channels).
%   mask  - H x W logical, or H x W double (nonzero = ROI). Same H,W as stack.
%   timeVec - (optional) 1 x N time vector. If omitted, t = 1:N.
% OUTPUT:
%   intensity - 1 x N mean intensity in ROI per frame.
%   t         - 1 x N time vector.
%
if ndims(stack) == 4
    N = size(stack, 4);
else
    N = size(stack, 3);
end
if nargin < 3
    timeVec = 1 : N;
end
mask = logical(mask);
mask = mask(:);
intensity = zeros(1, N);
for k = 1:N
    if ndims(stack) == 4
        frame = stack(:, :, :, k);
    else
        frame = stack(:, :, k);
    end
    if ndims(frame) == 3
        frame = mean(frame, 3);
    end
    frame = double(frame(:));
    intensity(k) = mean(frame(mask));
end
t = timeVec(:)';
if numel(t) ~= N
    t = 1:N;
end
end
