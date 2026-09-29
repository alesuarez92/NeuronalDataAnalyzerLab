function [speed, t] = roiFlowSpeed(stack, mask, timeVec)
% roiFlowSpeed - Mean absolute frame-to-frame difference in the ROI.
%
% NOT a speed: it measures how much the ROI intensity changes between
% consecutive frames, the same as roiMovement(stack, mask, t, 'diff')
% (for RGB stacks the colour channels are averaged first). Kept so old
% scripts still run; ROI Analysis no longer offers it. For red-blood-cell
% speed, use a kymograph of a line along the vessel
% (kymograph + propagationSpeedFromKymograph).
%
% INPUT:
%   stack  - H x W x N grayscale (or RGB; converted to gray).
%   mask   - H x W logical.
%   timeVec - (optional) 1 x N.
% OUTPUT:
%   speed - 1 x N (first frame NaN); mean |frame difference| in the ROI.
%   t     - 1 x N.
%
if ndims(stack) == 4
    N = size(stack, 4);
    gray = squeeze(mean(stack, 3));
else
    N = size(stack, 3);
    gray = stack;
end
if nargin < 3 || isempty(timeVec)
    timeVec = 1:N;
end
t = timeVec(:)';

speed = zeros(1, N);
speed(1) = NaN;
mask = logical(mask);

% Mean absolute frame difference in ROI as flow/speed proxy (no toolbox required).
% For true optical flow, use vision.OpticalFlow or Image Processing Toolbox externally.
for k = 2:N
    a = double(gray(:, :, k-1));
    b = double(gray(:, :, k));
    speed(k) = mean(abs(b(mask) - a(mask)));
end
end
