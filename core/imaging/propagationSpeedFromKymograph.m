function [speedPixPerFrame, angleRad, slope] = propagationSpeedFromKymograph(ky, method)
% propagationSpeedFromKymograph - Estimate propagation speed from kymograph.
%
% ky is space x time. Finds dominant ridge slope (space/time = speed in
% pixels/frame). method: 'maxgrad' (least-squares gradient / optical-flow
% constraint), 'correlation' (median frame-to-frame spatial lag from
% cross-correlation), or 'fit' (line fitted to the per-frame intensity peak).
%
% OUTPUT:
%   speedPixPerFrame - speed in pixels per frame (positive = one direction).
%   angleRad        - angle of propagation (optional).
%   slope           - slope of ridge (space/time).
%
if nargin < 2, method = 'maxgrad'; end

[ns, nt] = size(ky);
if nt < 2 || ns < 2
    speedPixPerFrame = NaN;
    angleRad = NaN;
    slope = NaN;
    return;
end

switch lower(method)
    case 'maxgrad'
        % ky is space (rows) x time (columns). gradient() returns the
        % column-wise (time) derivative first, then the row-wise (space) one.
        % Brightness constancy I_t + v * I_x = 0, solved for v in the
        % least-squares sense over the whole kymograph.
        [gTime, gSpace] = gradient(double(ky));
        slope = -sum(gTime(:) .* gSpace(:)) / (sum(gSpace(:).^2) + eps);
    case 'correlation'
        % Spatial lag that best aligns each column with the next one,
        % median over frame pairs (pixels per frame).
        maxLag = max(1, floor(ns / 2));
        lags = -maxLag:maxLag;
        best = zeros(1, nt - 1);
        for j = 1:nt-1
            a = double(ky(:, j));   a = a - mean(a);
            b = double(ky(:, j+1)); b = b - mean(b);
            c = zeros(size(lags));
            for m = 1:numel(lags)
                L = lags(m);
                ia = max(1, 1-L):min(ns, ns-L);
                c(m) = sum(a(ia) .* b(ia + L)) / numel(ia);
            end
            [~, iBest] = max(c);
            best(j) = lags(iBest);
        end
        slope = median(best);
    otherwise
        % 'fit': follow the brightest pixel along space in each frame and
        % fit a straight line position = slope * frame + offset.
        [~, ridge] = max(double(ky), [], 1);
        p = polyfit(1:nt, ridge, 1);
        slope = p(1);
end

speedPixPerFrame = slope;
angleRad = atan(slope);
end
