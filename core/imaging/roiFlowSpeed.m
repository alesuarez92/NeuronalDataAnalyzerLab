function [speed, t] = roiFlowSpeed(stack, mask, timeVec)
% roiFlowSpeed - Mean magnitude of frame-to-frame motion in ROI (flow/speed proxy).
%
% Uses optical flow (if vision.OpticalFlow available) or mean absolute
% gradient magnitude between frames. Useful for blood flow, particle
% movement, or activity propagation in 2P/multiphoton.
%
% INPUT:
%   stack  - H x W x N grayscale (or RGB; converted to gray).
%   mask   - H x W logical.
%   timeVec - (optional) 1 x N.
% OUTPUT:
%   speed - 1 x N (first frame NaN); mean flow magnitude in ROI per frame.
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
