function C = localCorrelationImage(stack, varargin)
% localCorrelationImage - Mean correlation of each pixel's time series with its 8 neighbours.
%
% Pixels of an active cell rise and fall together, so their time series
% are correlated with those of their neighbours, while pixels of static
% background only share independent noise (correlation near 0). The
% resulting image highlights active cells even when they are dim in the
% mean image, and is the input of detectCellsFromCorrelation.
%
% Method: every pixel's time series is centred and scaled to unit norm;
% the Pearson correlation with each of the 8 neighbours (fewer at the
% image border) is the sum over time of the product of the two
% normalised series, and C is their mean. Optionally, each time series
% is high-pass filtered first by subtracting its running mean over
% 'HighPass' frames, which removes slow drift and bleaching that would
% otherwise correlate every pixel. Run motion correction first: residual
% motion makes every edge in the image look correlated.
%
% Usage:
%   C = localCorrelationImage(stack);
%   C = localCorrelationImage(stack, 'HighPass', 50);
%
% INPUT:
%   stack - H x W x N (or H x W x C x N; channels are averaged).
%   Options (name-value or struct):
%     'HighPass' - running-mean window in frames removed from every pixel
%                  (default 0 = only the mean is removed).
% OUTPUT:
%   C - H x W double, values in [-1, 1]; 0 for pixels with a constant time series.
%
% Toolbox-free (base MATLAB only). Memory: about three copies of the
% stack as double.
%
opt = struct('highpass', 0);
if numel(varargin) == 1 && isstruct(varargin{1})
    f = fieldnames(varargin{1});
    for k = 1:numel(f), opt.(lower(f{k})) = varargin{1}.(f{k}); end
else
    for k = 1:2:numel(varargin), opt.(lower(char(varargin{k}))) = varargin{k + 1}; end
end

if ndims(stack) == 4
    [H, W, ~, N] = size(stack);
    Z = reshape(mean(double(stack), 3), H, W, N);
else
    [H, W, N] = size(stack);
    Z = double(stack);
end
if opt.highpass > 1
    Z = Z - movmean(Z, round(opt.highpass), 3);
else
    Z = Z - mean(Z, 3);
end
nrm = sqrt(sum(Z.^2, 3));
nrm(nrm < eps) = Inf;                  % constant pixels -> correlation 0
Z = Z ./ nrm;

S = zeros(H, W);
cnt = zeros(H, W);
for dy = -1:1
    for dx = -1:1
        if dy == 0 && dx == 0, continue; end
        ya = max(1, 1 - dy):min(H, H - dy);   % pixels whose neighbour (y+dy, x+dx) exists
        xa = max(1, 1 - dx):min(W, W - dx);
        S(ya, xa) = S(ya, xa) + sum(Z(ya, xa, :) .* Z(ya + dy, xa + dx, :), 3);
        cnt(ya, xa) = cnt(ya, xa) + 1;
    end
end
C = S ./ cnt;
end
