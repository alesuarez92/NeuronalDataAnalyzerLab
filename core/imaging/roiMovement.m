function [movement, t] = roiMovement(stack, mask, timeVec, method)
% roiMovement - Simple movement/change metric in ROI over time.
%
% Computes frame-to-frame change or variance within the ROI (e.g. for
% motion or activity). Methods: 'diff' (mean absolute frame difference),
% 'variance' (variance of pixel values in ROI per frame).
%
% Usage:
%   [movement, t] = roiMovement(stack, mask);
%   [movement, t] = roiMovement(stack, mask, timeVec, 'diff');
%
% INPUT:
%   stack  - H x W x N image stack.
%   mask   - H x W logical or numeric (nonzero = ROI).
%   timeVec - (optional) 1 x N. If omitted, t = 1:N.
%   method - (optional) 'diff' (default) or 'variance'.
% OUTPUT:
%   movement - 1 x N (for 'diff', N-1; first sample NaN or zero).
%   t        - 1 x N (or N-1 for diff).
%
if nargin < 3
    timeVec = [];
end
if nargin < 4
    method = 'diff';
end
mask = logical(mask);
if ndims(stack) == 4
    N = size(stack, 4);
else
    N = size(stack, 3);
end
if strcmpi(method, 'variance')
    movement = zeros(1, N);
    for k = 1:N
        frame = stack(:, :, k);
        if ndims(frame) == 3
            frame = mean(frame, 3);
        end
        movement(k) = var(double(frame(mask)));
    end
    t = timeVec;
    if isempty(t) || numel(t) ~= N
        t = 1:N;
    end
    t = t(:)';
    return;
end
% 'diff': mean absolute difference from previous frame
movement = zeros(1, N);
movement(1) = NaN;
for k = 2:N
    if ndims(stack) == 4
        a = double(stack(:, :, :, k - 1));
        b = double(stack(:, :, :, k));
    else
        a = double(stack(:, :, k - 1));
        b = double(stack(:, :, k));
    end
    if ndims(a) == 3
        a = mean(a, 3);
        b = mean(b, 3);
    end
    movement(k) = mean(abs(b(mask) - a(mask)));
end
if isempty(timeVec) || numel(timeVec) ~= N
    t = 1:N;
else
    t = timeVec(:)';
end
end
