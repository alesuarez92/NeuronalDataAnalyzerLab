function [C, Pu] = perimedPerfusion(V, I, beta, gain)
% perimedPerfusion - Speckle contrast and perfusion from PIMSoft variance and intensity images.
%
% [C, Pu] = perimedPerfusion(V, I, beta, gain)
%
% As PIMSoft (Perimed PeriCam PSI) converts them:
%   C  = beta * sign(V) * sqrt(|V|) / I
%   Pu = gain * (1 / C - 1), limited to 0..3000 (non-finite values -> 0)
% V, I: arrays of the same size (one or more frames). To average frames
% or pixels, average V and I first and convert after. Used by
% readPerimedDat. Base MATLAB only; also runs in GNU Octave.
%
C = beta .* sign(V) .* sqrt(abs(V)) ./ I;
Pu = gain .* (1 ./ C - 1);
Pu(~isfinite(Pu)) = 0;
Pu = min(max(Pu, 0), 3000);
end
