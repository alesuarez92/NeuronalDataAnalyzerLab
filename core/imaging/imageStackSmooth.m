function out = imageStackSmooth(stack, sigmaOrSize, method)
% imageStackSmooth - Smooth image stack (Gaussian or median).
%
% method: 'gaussian' (sigma in pixels), 'median' (kernel size).
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
                out(:, :, c, k) = imgaussfilt(frame, sigmaOrSize);
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
            out(:, :, k) = imgaussfilt(frame, sigmaOrSize);
        end
    end
end
end
