function [ky, xOrY, t] = kymograph(stack, lineStart, lineEnd, timeVec)
% kymograph - Extract space-time image along a line (for propagation, flow).
%
% For each frame, sample intensity along the line from lineStart to lineEnd
% (pixel coords [x1 y1; x2 y2] or [x1 y1 x2 y2]). Result: 2D image (space x time).
% Useful for measuring propagation speed (e.g. blood flow, calcium waves).
%
% Usage:
%   [ky, xOrY, t] = kymograph(stack, [x1 y1], [x2 y2], timeVec);
%
% INPUT:
%   stack    - H x W x N (or H x W x 3 x N; will use mean).
%   lineStart - [x1 y1] or [x1 y1 x2 y2].
%   lineEnd   - [x2 y2] (if lineStart is [x1 y1]).
%   timeVec  - (optional) 1 x N.
% OUTPUT:
%   ky   - nPixels x N (space along line x time).
%   xOrY - 1 x nPixels, distance along line.
%   t    - 1 x N.
%
if nargin < 4, timeVec = []; end
if numel(lineStart) == 4
    x1 = lineStart(1); y1 = lineStart(2); x2 = lineStart(3); y2 = lineStart(4);
else
    x1 = lineStart(1); y1 = lineStart(2);
    x2 = lineEnd(1);   y2 = lineEnd(2);
end
if ndims(stack) == 4
    N = size(stack, 4);
    stack = squeeze(mean(stack, 3));
else
    N = size(stack, 3);
end
nPix = max(round(sqrt((x2-x1)^2 + (y2-y1)^2)), 2);
xi = linspace(x1, x2, nPix);
yi = linspace(y1, y2, nPix);
H = size(stack, 1); W = size(stack, 2);
xi = max(1, min(W, xi));
yi = max(1, min(H, yi));

ky = zeros(nPix, N);
for k = 1:N
    frame = double(stack(:, :, k));
    ky(:, k) = interp2(1:W, (1:H)', frame, xi, yi, 'linear', NaN);
end
ky(isnan(ky)) = 0;
xOrY = (0 : nPix-1) / max(nPix-1, 1);
if isempty(timeVec) || numel(timeVec) ~= N
    t = 1:N;
else
    t = timeVec(:)';
end
end
