function [diameter, t, profile] = vesselDiameterFromLine(stack, lineStart, lineEnd, timeVec, method)
% vesselDiameterFromLine - Vessel diameter over time from intensity profile along perpendicular line.
%
% For each frame, sample intensity along the line; diameter = FWHM of the
% (inverted) profile (vessel = dark) or width at half-max (vessel = bright).
% method: 'fwhm' (full width half max), 'threshold' (width at 50% of range).
%
% Usage:
%   [diameter, t, profile] = vesselDiameterFromLine(stack, [x1 y1], [x2 y2], timeVec, 'fwhm');
%
% INPUT:
%   stack    - H x W x N.
%   lineStart, lineEnd - line perpendicular to vessel ([x y]).
%   timeVec  - (optional).
%   method   - 'fwhm' or 'threshold'.
% OUTPUT:
%   diameter - 1 x N (in pixels).
%   t        - 1 x N.
%   profile  - nPix x N (optional; intensity profiles).
%
if nargin < 4, timeVec = []; end
if nargin < 5, method = 'fwhm'; end

[profile, xOrY, t] = kymograph(stack, lineStart, lineEnd, timeVec);
N = size(profile, 2);
nPix = size(profile, 1);
diameter = zeros(1, N);

for k = 1:N
    p = profile(:, k);
    p = p - min(p);
    if max(p) < eps
        diameter(k) = NaN;
        continue;
    end
    p = p / max(p);
    % Vessel often dark: invert so "peak" is vessel center
    p = 1 - p;
    if max(p) < 0.5
        diameter(k) = NaN;
        continue;
    end
    if strcmpi(method, 'threshold')
        idx = p >= 0.5;
        if ~any(idx)
            diameter(k) = NaN;
            continue;
        end
        i1 = find(idx, 1);
        i2 = find(idx, 1, 'last');
        diameter(k) = (i2 - i1 + 1) / nPix * sqrt((lineEnd(1)-lineStart(1))^2 + (lineEnd(2)-lineStart(2))^2);
    else
        % FWHM
        half = 0.5 * max(p);
        above = p >= half;
        if sum(above) < 2
            diameter(k) = NaN;
            continue;
        end
        ii = find(above);
        lenPix = ii(end) - ii(1) + 1;
        lineLen = sqrt((lineEnd(1)-lineStart(1))^2 + (lineEnd(2)-lineStart(2))^2);
        diameter(k) = lenPix / nPix * lineLen;
    end
end
end
