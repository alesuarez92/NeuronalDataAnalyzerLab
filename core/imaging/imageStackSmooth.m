function out = imageStackSmooth(stack, sigmaOrSize, method)
% imageStackSmooth - Smooth image stack (Gaussian or median).
%
% method: 'gaussian' (sigma in pixels), 'median' (kernel size).
% Gaussian smoothing uses imgaussfilt when the Image Processing Toolbox is
% installed and a separable conv2 kernel (replicated edges) otherwise.
% Median filtering requires medfilt2 (Image Processing Toolbox).
% INPUT: stack H x W x N or H x W x 3 x N.
% OUTPUT: same size, smoothed per frame.
%
if nargin < 2, sigmaOrSize = 2; end
if nargin < 3, method = 'gaussian'; end

if ndims(stack) == 4
    [H, W, C, N] = size(stack);
    out = zeros(size(stack), class(stack));
    for k = 1:N
        for c = 1:C
            frame = stack(:, :, c, k);
            if strcmpi(method, 'median')
                out(:, :, c, k) = medfilt2(frame, [sigmaOrSize sigmaOrSize]);
            else
                out(:, :, c, k) = gaussFrame(frame, sigmaOrSize);
            end
        end
    end
else
    [H, W, N] = size(stack);
    out = zeros(size(stack), class(stack));
    for k = 1:N
        frame = stack(:, :, k);
        if strcmpi(method, 'median')
            out(:, :, k) = medfilt2(frame, [sigmaOrSize sigmaOrSize]);
        else
            out(:, :, k) = gaussFrame(frame, sigmaOrSize);
        end
    end
end
end

function out = gaussFrame(frame, sigma)
% Gaussian blur of one 2-D frame; toolbox-free fallback for imgaussfilt.
if exist('imgaussfilt', 'file') == 2
    out = imgaussfilt(frame, sigma);
    return;
end
r = max(1, ceil(2 * sigma));
g = exp(-((-r:r).^2) / (2 * sigma^2));
g = g / sum(g);
f = double(frame);
[h, w] = size(f);
f = f([ones(1, r), 1:h, h * ones(1, r)], [ones(1, r), 1:w, w * ones(1, r)]);
f = conv2(g, g, f, 'valid');
out = cast(f, class(frame));
end
