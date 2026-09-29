%% demoCSD.m
% =========================================================================
% DEMO CSD - SYNTHETIC LAMINAR POTENTIALS WITH A KNOWN CURRENT SOURCE DENSITY
% =========================================================================
% s = demoCSD(caseName, noiseLevel, opts) builds a laminar recording whose
% true current source density (CSD) is known, to check and compare the
% CSD methods in core/CSDMethods (standard, iCSD delta / step / spline,
% kCSD). Deterministic: same inputs, same output, in MATLAB and Octave.
%
% Ground truth: a Gaussian current SINK (SD 100 um) at sinkDepthUm with two
% balancing Gaussian SOURCES (SD 100 um, each half the sink amplitude) 300
% um above and below it, so the net current is zero. Each layer is a disc
% of radius radiusUm (default 250 um, i.e. 500 um diameter) in a
% homogeneous medium of conductivity sigma (default 0.3 S/m): a finite
% lateral extent, which the standard (second-derivative) CSD does not
% model. Time course (1 kHz, -20 to 100 ms): the profile x (a -1 peak at
% 15 ms, SD 5 ms, plus a reversed +0.4 peak at 40 ms, SD 12 ms), so the
% strongest sink is at 15 ms. amplitude (1000 A/m^3 = 1 uA/mm^3) scales the
% sink Gaussian; the flanking sources and the 40 ms component overlap it
% slightly, so the true CSD at the sink at 15 ms is about -940 A/m^3.
% Potentials are forward-modelled with CSDMethods.forwardDisc (on-axis
% potential of uniform discs, Pettersen et al. 2006) on a 1 um grid
% reaching 1000 um beyond the contacts.
%
% caseName:
%   'laminar16' (default)  16 contacts 100 um apart at 100..1600 um, sink
%                          at 800 um (contact 8).
%   'edge16'               the same probe, sink at 200 um (contact 2): the
%                          upper source (-100 um) lies above the top
%                          contact, which shows edge effects.
%   'demo8'                8 contacts 100 um apart at 0..700 um, sink at
%                          300 um (contact 4), like DemoData's LFP.
% noiseLevel (default 0): SD of added white noise as a fraction of the
%   largest absolute potential. Noise comes from a seeded Park-Miller
%   generator with Box-Muller (identical in MATLAB and Octave).
% opts (struct, optional): radiusUm (250), sigma (0.3), seed (1),
%   sinkDepthUm (case default), amplitude (1000 A/m^3).
%
% Output fields: case, potentials (V, contacts x time), depthsUm, t (s),
%   fs (Hz), spacingUm, noiseSdV, noiseLevel, and truth: csdGrid (A/m^3,
%   grid x time), zGridUm, csdAtContacts (A/m^3, contacts x time),
%   sinkDepthUm, sinkContact, sinkTimeS, sinkTimeIdx, sourceDepthsUm,
%   radiusUm, diameterUm, sigma, amplitude, profile (at contacts, peak
%   time), cleanPotentials (V, without noise).
% =========================================================================

function s = demoCSD(caseName, noiseLevel, opts)
    if nargin < 1 || isempty(caseName), caseName = 'laminar16'; end
    if nargin < 2 || isempty(noiseLevel), noiseLevel = 0; end
    if nargin < 3 || isempty(opts), opts = struct(); end
    o = struct('radiusUm', 250, 'sigma', 0.3, 'seed', 1, 'sinkDepthUm', [], 'amplitude', 1000);
    f = fieldnames(opts);
    for k = 1:numel(f), o.(f{k}) = opts.(f{k}); end

    switch lower(caseName)
        case 'laminar16'
            depths = (1:16) * 100; sink = 800;
        case 'edge16'
            depths = (1:16) * 100; sink = 200;
        case 'demo8'
            depths = (0:7) * 100; sink = 300;
        otherwise
            error('NeuroAnalyzer:demoCSD:badCase', 'Unknown case. Use laminar16, edge16 or demo8.');
    end
    if ~isempty(o.sinkDepthUm), sink = o.sinkDepthUm; end
    if ~(isscalar(noiseLevel) && isfinite(noiseLevel) && noiseLevel >= 0)
        error('NeuroAnalyzer:demoCSD:badNoise', 'noiseLevel must be a number >= 0.');
    end

    % --- Time course ---
    fs = 1000;
    t = (-20:100) / fs;
    wave = -exp(-(t - 0.015) .^ 2 / (2 * 0.005 ^ 2)) + 0.4 * exp(-(t - 0.040) .^ 2 / (2 * 0.012 ^ 2));

    % --- True CSD profile (A/m^3 per unit of wave): sink with balancing sources ---
    sd = 100; offs = 300;
    prof = @(z) exp(-(z - sink) .^ 2 / (2 * sd ^ 2)) ...
        - 0.5 * exp(-(z - sink + offs) .^ 2 / (2 * sd ^ 2)) ...
        - 0.5 * exp(-(z - sink - offs) .^ 2 / (2 * sd ^ 2));
    % prof > 0 at the sink; CSD = amplitude * prof * wave, wave(15 ms) = -1 -> sink negative
    zGrid = (depths(1) - 1000):1:(depths(end) + 1000);
    csdGrid = o.amplitude * prof(zGrid(:)) * wave;
    csdAt = o.amplitude * prof(depths(:)) * wave;

    clean = CSDMethods.forwardDisc(depths, zGrid, csdGrid, o.radiusUm, o.sigma);
    noiseSd = noiseLevel * max(abs(clean(:)));
    pot = clean;
    if noiseSd > 0
        pot = clean + noiseSd * parkMillerNormal(o.seed, size(clean));
    end

    [~, iPk] = min(abs(t - 0.015));
    [~, sinkContact] = min(abs(depths - sink));
    s = struct();
    s.case = lower(caseName);
    s.potentials = pot;
    s.depthsUm = depths;
    s.t = t;
    s.fs = fs;
    s.spacingUm = 100;
    s.noiseLevel = noiseLevel;
    s.noiseSdV = noiseSd;
    s.truth = struct('csdGrid', csdGrid, 'zGridUm', zGrid, 'csdAtContacts', csdAt, ...
        'sinkDepthUm', sink, 'sinkContact', sinkContact, 'sinkTimeS', t(iPk), 'sinkTimeIdx', iPk, ...
        'sourceDepthsUm', sink + [-offs offs], 'radiusUm', o.radiusUm, 'diameterUm', 2 * o.radiusUm, ...
        'sigma', o.sigma, 'amplitude', o.amplitude, 'profile', csdAt(:, iPk), ...
        'cleanPotentials', clean);
end

%% parkMillerNormal - Standard normal numbers from a seeded Park-Miller LCG (Box-Muller)
function x = parkMillerNormal(seed, sz)
    n = prod(sz);
    m = 2147483647; a = 16807;
    state = mod(round(seed) * 7919 + 12345, m);
    if state == 0, state = 1; end
    nu = 2 * ceil(n / 2);
    u = zeros(1, nu);
    for k = 1:nu
        state = mod(a * state, m);   % exact in double: a * m < 2^53
        u(k) = state / m;
    end
    u1 = u(1:2:end); u2 = u(2:2:end);
    r = sqrt(-2 * log(u1));
    z = [r .* cos(2 * pi * u2); r .* sin(2 * pi * u2)];
    x = reshape(z(1:n), sz);
end
