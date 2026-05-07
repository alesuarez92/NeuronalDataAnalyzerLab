function [speedPixPerFrame, angleRad, slope] = propagationSpeedFromKymograph(ky, method)
% propagationSpeedFromKymograph - Estimate propagation speed from kymograph.
%
% ky is space x time. Finds dominant ridge slope (space/time = speed in
% pixels/frame). method: 'maxgrad' (max gradient direction), 'correlation'
% (peak of space-time cross-correlation), or 'fit' (fit line to thresholded ridge).
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
        [gx, gt] = gradient(ky);
        gmag = sqrt(gx.^2 + gt.^2) + eps;
        % Dominant slope: weighted mean of (gt/gx) or (gx/gt)
        slope = -mean(gt(:)) / (mean(gx(:)) + eps);
    case 'correlation'
        ref = mean(ky, 2);
        c = zeros(1, nt);
        for j = 1:nt
            c(j) = corr(ref, ky(:, j));
        end
        [~, peak] = max(c);
        slope = (peak - 1) / nt * ns;
    otherwise
        % Simple: max variance along diagonal
        slope = 0;
        best = -inf;
        for s = -ns:ns
            d = diag(ky, s);
            if numel(d) < 10, continue; end
            v = var(d);
            if v > best
                best = v;
                slope = s / nt;
            end
        end
end

speedPixPerFrame = slope;
angleRad = atan(slope);
end
