function out = imageToGrayscale256(img)
% imageToGrayscale256 - Convert image to 256-level black-and-white (uint8).
%
% For fluorescence or intensity-based analysis: normalizes to 0-255 and
% returns uint8. Handles RGB (converts to grayscale), single/double, or
% already uint8.
%
% Usage:
%   gray = imageToGrayscale256(img);
%   grayStack = imageToGrayscale256(stack);  % stack: H x W x N or H x W x 3 x N
%
% INPUT:
%   img - H x W (grayscale), H x W x 3 (RGB), or H x W x N (stack). Single, double, or uint8.
% OUTPUT:
%   out - uint8, same size as img (or H x W x N). Values 0-255.
%
if isempty(img)
    out = img;
    return;
end
if isinteger(img) && isa(img, 'uint8')
    % Already uint8; optional: ensure full 0-255 range
    out = img;
    return;
end
img = double(img);
% Single frame RGB
if ndims(img) == 3 && size(img, 3) == 3
    img = rgb2gray(img / max(img(:) + eps));
end
% Stack: H x W x N
if ndims(img) == 3 && size(img, 3) ~= 1
    mn = min(img(:));
    mx = max(img(:));
    if mx <= mn
        out = zeros(size(img), 'uint8');
        return;
    end
    out = uint8(255 * (img - mn) / (mx - mn));
    return;
end
% Single 2D frame
mn = min(img(:));
mx = max(img(:));
if mx <= mn
    out = zeros(size(img), 'uint8');
    return;
end
out = uint8(255 * (img - mn) / (mx - mn));
end
