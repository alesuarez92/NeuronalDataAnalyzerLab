%% CSDMethods.m
% =========================================================================
% CSD METHODS - STANDARD, INVERSE (iCSD) AND KERNEL (kCSD) CURRENT SOURCE DENSITY
% =========================================================================
% Headless, toolbox-free (base MATLAB) estimators of the current source
% density (CSD) along a linear (laminar) probe, used by LFPAnalysisApp's
% CSD step. All methods take the same inputs:
%
%   V          potentials, channels x time, in volts (V); rows ordered top
%              (superficial) to bottom (deep), one per contact.
%   depthsUm   contact depths in micrometres (um), strictly increasing,
%              one per row of V (e.g. (0:15) * 100). Depths only matter
%              relative to each other, except for sigmaTop (below).
%
% Sign convention (all methods): CSD > 0 is a current source, CSD < 0 a
% sink (current entering cells), so an evoked sink shows as a trough.
%
%   [csd, info] = CSDMethods.estimate(V, depthsUm, method, params)
%       method: 'standard' | 'delta' | 'step' | 'spline' | 'kcsd' (the
%       labels 'Standard', 'iCSD delta', 'iCSD step', 'iCSD spline' and
%       'kCSD' are accepted too, any case). params (struct, all fields
%       optional; see CSDMethods.defaults):
%         sigma       extracellular conductivity (S/m), default 0.3
%         diameterUm  diameter of the (disc-shaped) source layers in the
%                     plane of the cortex (um), default 500 (radius 250)
%         smoothUm    SD (um) of an optional Gaussian spatial filter
%                     applied across depth to the iCSD estimate (0 = off,
%                     default). Weights renormalised at the probe ends.
%         sigmaTop    conductivity above the surface z = 0 (S/m) for the
%                     iCSD methods (method of images); default = sigma,
%                     i.e. homogeneous medium. When set, depthsUm must be
%                     measured from that surface (positive downwards).
%         RUm         kCSD basis width (um, SD of the Gaussian basis
%                     sources); [] or 0 = choose by cross-validation over
%                     RGridUm (default spacing * [0.5 0.75 1 1.5 2 3]).
%         lambda      kCSD ridge regularisation, relative to the mean of
%                     diag(K); [] or 0 = choose by leave-one-out
%                     cross-validation over lambdaGrid (default
%                     logspace(-9, 0, 37)).
%         nSources    number of kCSD basis sources (default 120), spread
%                     evenly from the first contact - extUm to the last
%                     contact + extUm (extUm default = one spacing).
%         gridStepUm  kCSD / spline estimation grid step (um, default
%                     spacing / 4), from the first to the last contact.
%         splineEnds  'extend' (default) | 'zero': spline iCSD beyond the
%                     end contacts (see below).
%       csd is channels x time, the estimate at the contact depths.
%       info: method, label, unit, params (as used), depthsUm, and
%       zGridUm / csdGrid (the estimate on the finer grid; for 'standard',
%       'delta' and 'step' the contact depths and csd themselves); the
%       iCSD methods add condF, the condition number of F. For
%       'kcsd' also R (um), lambda (absolute), lambdaRel, RGridUm,
%       lambdaGrid, cvError (normalised LOO error, numel(RGridUm) x
%       numel(lambdaGrid)), cvErrorMin, nSources, sourcesUm.
%
%   c = CSDMethods.standard(V, depthsUm)
%       ERPAnalysis.csd(V, spacing): -d2V/dz2 by the three-point second
%       difference, first / last rows copied from their neighbours. The
%       contacts must be evenly spaced. UNITS: exactly what the app
%       computed before this class existed - the second derivative of the
%       potential WITHOUT the conductivity, i.e. V/m^2 for V in volts (the
%       app labels it "amplitude / m^2"). Multiply by sigma (S/m) to get
%       A/m^3 (info.toAm3 = sigma). Assumes laterally infinite, uniform
%       sources (Nicholson & Freeman 1975).
%   [c, info] = CSDMethods.deltaICSD(V, depthsUm, params)
%   [c, info] = CSDMethods.stepICSD(V, depthsUm, params)
%   [c, info] = CSDMethods.splineICSD(V, depthsUm, params)
%       Inverse CSD (Pettersen et al. 2006): the CSD is modelled as
%       discs of radius R = diameterUm / 2 in a homogeneous medium of
%       conductivity sigma, the forward matrix F (potential at each
%       contact per unit CSD amplitude) is built from the potential on the
%       axis of a uniform disc, phi = (h / (2 sigma)) (sqrt(dz^2 + R^2) -
%       |dz|) * C, and the CSD is F \ V. Source models:
%         delta   infinitely thin discs at each contact, thickness h =
%                 the local contact spacing;
%         step    CSD constant within +/- h/2 of each contact (closed-form
%                 integral of the disc kernel);
%         spline  natural cubic spline through the CSD values at the
%                 contacts (zero second derivative at the first and last
%                 contact; kernel integrated numerically on a fine grid).
%                 Beyond the end contacts: splineEnds 'extend' (default)
%                 holds the end values for half a spacing, like the step
%                 method's end layers; 'zero' sets the CSD to zero
%                 outside the first-to-last contact span.
%       Output in A/m^3 (V in volts, depths in um converted to m, sigma in
%       S/m). Optional Gaussian smoothing (smoothUm) afterwards.
%   [c, info] = CSDMethods.kCSD(V, depthsUm, params)
%       1-D kernel CSD (Potworowski et al. 2012): Gaussian basis sources
%       (SD R) with the same disc forward model (radius diameterUm / 2),
%       kernel K = B B' at the contacts and cross-kernel Kt = Bt B', the
%       estimate Kt (K + lambda I) \ V on the fine grid, R and lambda by
%       leave-one-out cross-validation of the potentials unless given.
%       Output in A/m^3. Homogeneous medium (sigmaTop is not used).
%
%   F = CSDMethods.forwardMatrix(method, depthsUm, params)
%       'delta' | 'step' | 'spline': the iCSD forward matrix, V = F * C
%       (V in volts for C in A/m^3).
%   phi = CSDMethods.forwardDisc(zElecUm, zGridUm, csdGrid, radiusUm, sigma)
%       Potential (V) at zElecUm from a CSD profile csdGrid (A/m^3,
%       numel(zGridUm) x time, evenly spaced grid, zero outside it) made
%       of discs of radius radiusUm in a homogeneous medium (trapezoid
%       integration of the disc kernel). Used by core/demo/demoCSD.
%   p = CSDMethods.defaults()          default params
%   [id, label] = CSDMethods.methodId(name)   'iCSD step' -> 'step', ...
%   ids = CSDMethods.methodIds()       {'standard','delta','step','spline','kcsd'}
%
% Errors (identifiers NeuroAnalyzer:CSDMethods:*): badMethod,
% badPotentials, badDepths, tooFewChannels, nonUniformSpacing,
% badParameter.
%
% References:
%   Nicholson C, Freeman JA (1975). Theory of current source-density
%     analysis and determination of conductivity tensor for anuran
%     cerebellum. J Neurophysiol 38:356-368.
%   Pettersen KH, Devor A, Ulbert I, Dale AM, Einevoll GT (2006).
%     Current-source density estimation based on inversion of
%     electrostatic forward solution: effects of finite extent of neuronal
%     activity and conductivity discontinuities. J Neurosci Methods
%     154:116-133.
%   Potworowski J, Jakuczun W, Leski S, Wojcik D (2012). Kernel current
%     source density method. Neural Comput 24:541-575.
% =========================================================================

classdef CSDMethods
    methods(Static)

        %% methodIds - Method identifiers in UI order
        function ids = methodIds()
            ids = {'standard', 'delta', 'step', 'spline', 'kcsd'};
        end

        %% methodId - Normalise a method name or label to its identifier
        function [id, label] = methodId(name)
            ids = CSDMethods.methodIds();
            labels = {'Standard', 'iCSD delta', 'iCSD step', 'iCSD spline', 'kCSD'};
            id = '';
            label = '';
            if isstring(name) && isscalar(name), name = char(name); end
            if ~ischar(name), return; end
            key = lower(regexprep(strtrim(name), '[\s_-]+', ''));
            alt = {'standard', 'icsddelta', 'icsdstep', 'icsdspline', 'kcsd'};
            k = find(strcmp(key, ids) | strcmp(key, alt), 1);
            if isempty(k), return; end
            id = ids{k};
            label = labels{k};
        end

        %% defaults - Default parameters (see header)
        function p = defaults()
            p = struct('sigma', 0.3, 'diameterUm', 500, 'smoothUm', 0, 'sigmaTop', [], ...
                'RUm', [], 'lambda', [], 'RGridUm', [], 'lambdaGrid', logspace(-9, 0, 37), ...
                'nSources', 120, 'extUm', [], 'gridStepUm', [], 'splineEnds', 'extend');
        end

        %% estimate - Dispatch to one method (see header)
        function [csd, info] = estimate(V, depthsUm, method, params)
            if nargin < 4 || isempty(params), params = struct(); end
            [id, label] = CSDMethods.methodId(method);
            if isempty(id)
                error('NeuroAnalyzer:CSDMethods:badMethod', ...
                    'Unknown CSD method. Use standard, delta, step, spline or kcsd.');
            end
            switch id
                case 'standard'
                    [V, z] = CSDMethods.checkInputs(V, depthsUm);
                    p = CSDMethods.fillParams(params, z);
                    csd = CSDMethods.standard(V, z);
                    info = struct('method', id, 'label', label, 'unit', 'V/m^2 (no conductivity)', ...
                        'toAm3', p.sigma, 'params', p, 'depthsUm', z, 'zGridUm', z, 'csdGrid', csd);
                case 'delta'
                    [csd, info] = CSDMethods.deltaICSD(V, depthsUm, params);
                case 'step'
                    [csd, info] = CSDMethods.stepICSD(V, depthsUm, params);
                case 'spline'
                    [csd, info] = CSDMethods.splineICSD(V, depthsUm, params);
                case 'kcsd'
                    [csd, info] = CSDMethods.kCSD(V, depthsUm, params);
            end
            info.label = label;
        end

        %% standard - Legacy second-difference CSD (ERPAnalysis.csd), V/m^2
        function c = standard(V, depthsUm)
            [V, z] = CSDMethods.checkInputs(V, depthsUm);
            d = diff(z);
            if max(abs(d - mean(d))) > 1e-6 * mean(d)
                error('NeuroAnalyzer:CSDMethods:nonUniformSpacing', ...
                    'The standard CSD needs evenly spaced contacts.');
            end
            c = ERPAnalysis.csd(V, mean(d));
        end

        %% deltaICSD - Inverse CSD with infinitely thin disc sources at the contacts
        function [c, info] = deltaICSD(V, depthsUm, params)
            if nargin < 3, params = struct(); end
            [c, info] = CSDMethods.icsd('delta', V, depthsUm, params);
        end

        %% stepICSD - Inverse CSD with CSD constant within +/- h/2 of each contact
        function [c, info] = stepICSD(V, depthsUm, params)
            if nargin < 3, params = struct(); end
            [c, info] = CSDMethods.icsd('step', V, depthsUm, params);
        end

        %% splineICSD - Inverse CSD with a natural cubic spline CSD profile
        function [c, info] = splineICSD(V, depthsUm, params)
            if nargin < 3, params = struct(); end
            [c, info] = CSDMethods.icsd('spline', V, depthsUm, params);
        end

        %% kCSD - 1-D kernel CSD with cross-validated R and lambda
        function [c, info] = kCSD(V, depthsUm, params)
            if nargin < 3, params = struct(); end
            [V, z] = CSDMethods.checkInputs(V, depthsUm);
            p = CSDMethods.fillParams(params, z);
            zm = z(:) * 1e-6;                               % contacts (m), column
            h = median(diff(z));                            % um
            r = p.diameterUm / 2 * 1e-6;                    % disc radius (m)
            src = linspace(z(1) - p.extUm, z(end) + p.extUm, p.nSources) * 1e-6;
            zg = CSDMethods.gridUm(z, p.gridStepUm);

            if isempty(p.RUm) || p.RUm == 0
                RGrid = p.RGridUm;
            else
                RGrid = p.RUm;
            end
            if isempty(p.lambda) || p.lambda == 0
                lamGrid = p.lambdaGrid;
            else
                lamGrid = p.lambda;
            end
            doCV = numel(RGrid) > 1 || numel(lamGrid) > 1;
            cvErr = nan(numel(RGrid), numel(lamGrid));
            n = numel(z);
            vNorm = sum(V(:) .^ 2);
            if vNorm == 0, vNorm = 1; end
            Bs = cell(1, numel(RGrid));
            for iR = 1:numel(RGrid)
                Bs{iR} = CSDMethods.kcsdPotBasis(zm, src, RGrid(iR) * 1e-6, r, p.sigma, h * 1e-6);
                if ~doCV, continue; end
                K = Bs{iR} * Bs{iR}';
                s = mean(diag(K));
                for iL = 1:numel(lamGrid)
                    e = 0;
                    for i = 1:n
                        o = [1:i-1, i+1:n];
                        pred = K(i, o) * ((K(o, o) + lamGrid(iL) * s * eye(n - 1)) \ V(o, :));
                        e = e + sum((pred - V(i, :)) .^ 2);
                    end
                    cvErr(iR, iL) = e / vNorm;
                end
            end
            if doCV
                [cvMin, k] = min(cvErr(:));
                [iR, iL] = ind2sub(size(cvErr), k);
            else
                cvMin = NaN; iR = 1; iL = 1;
            end
            R = RGrid(iR) * 1e-6;
            B = Bs{iR};
            K = B * B';
            s = mean(diag(K));
            lam = lamGrid(iL) * s;
            beta = (K + lam * eye(n)) \ V;                    % n x T
            Bt = @(zz) exp(-(zz(:) - src) .^ 2 / (2 * R ^ 2)); % basis CSD at depths (m)
            c = (Bt(zm) * B') * beta;                          % A/m^3 at the contacts
            cg = (Bt(zg(:) * 1e-6) * B') * beta;

            p.RUm = RGrid(iR);
            p.lambda = lamGrid(iL);
            p.sigmaTop = p.sigma;
            info = struct('method', 'kcsd', 'label', 'kCSD', 'unit', 'A/m^3', 'toAm3', 1, ...
                'params', p, 'depthsUm', z, 'zGridUm', zg, 'csdGrid', cg, ...
                'R', RGrid(iR), 'lambda', lam, 'lambdaRel', lamGrid(iL), 'RGridUm', RGrid, ...
                'lambdaGrid', lamGrid, 'cvError', cvErr, 'cvErrorMin', cvMin, ...
                'nSources', p.nSources, 'sourcesUm', src * 1e6);
        end

        %% forwardMatrix - iCSD forward matrix V = F * C (V in V, C in A/m^3)
        function [F, S, zf] = forwardMatrix(method, depthsUm, params)
            if nargin < 3, params = struct(); end
            id = CSDMethods.methodId(method);
            if ~ismember(id, {'delta', 'step', 'spline'})
                error('NeuroAnalyzer:CSDMethods:badMethod', ...
                    'forwardMatrix is defined for the delta, step and spline methods.');
            end
            z = CSDMethods.checkDepths(depthsUm, numel(depthsUm));
            p = CSDMethods.fillParams(params, z);
            zm = z(:) * 1e-6;
            r = p.diameterUm / 2 * 1e-6;
            kImg = (p.sigma - p.sigmaTop) / (p.sigma + p.sigmaTop);   % image weight (surface at z = 0)
            h = CSDMethods.layerThickness(zm);                        % column, m
            S = []; zf = [];
            switch id
                case 'delta'
                    dz = zm - zm';                                     % (i, j) = z_i - z_j
                    F = (CSDMethods.discKernel(dz, r) + kImg * CSDMethods.discKernel(zm + zm', r)) ...
                        .* h' / (2 * p.sigma);
                case 'step'
                    a = zm' - h' / 2; b = zm' + h' / 2;                % layer j spans [a_j, b_j]
                    G = @(u) CSDMethods.discKernelIntegral(u, r);
                    F = (G(b - zm) - G(a - zm)) / (2 * p.sigma);
                    if kImg ~= 0
                        F = F + kImg * (G(b + zm) - G(a + zm)) / (2 * p.sigma);
                    end
                case 'spline'
                    step = min(diff(zm)) / 200;
                    nf = max(2, ceil((zm(end) - zm(1)) / step) + 1);
                    zf = linspace(zm(1), zm(end), nf);
                    S = CSDMethods.naturalSplineMatrix(zm, zf);         % nf x n
                    w = CSDMethods.trapzWeights(zf);                    % 1 x nf
                    Kf = CSDMethods.discKernel(zm - zf, r);             % n x nf
                    if kImg ~= 0
                        Kf = Kf + kImg * CSDMethods.discKernel(zm + zf, r);
                    end
                    F = (Kf .* w) * S / (2 * p.sigma);
                    if strcmpi(p.splineEnds, 'extend')
                        % CSD held at the end values for h/2 beyond the first / last contact
                        G = @(u) CSDMethods.discKernelIntegral(u, r);
                        a = zm(1) - h(1) / 2; b = zm(end) + h(end) / 2;
                        F(:, 1) = F(:, 1) + (G(zm(1) - zm) - G(a - zm)) / (2 * p.sigma);
                        F(:, end) = F(:, end) + (G(b - zm) - G(zm(end) - zm)) / (2 * p.sigma);
                        if kImg ~= 0
                            F(:, 1) = F(:, 1) + kImg * (G(zm(1) + zm) - G(a + zm)) / (2 * p.sigma);
                            F(:, end) = F(:, end) + kImg * (G(b + zm) - G(zm(end) + zm)) / (2 * p.sigma);
                        end
                    end
            end
        end

        %% forwardDisc - Potential (V) of a CSD profile of discs, homogeneous medium
        function phi = forwardDisc(zElecUm, zGridUm, csdGrid, radiusUm, sigma)
            ze = zElecUm(:) * 1e-6;
            zg = zGridUm(:)' * 1e-6;
            if size(csdGrid, 1) ~= numel(zg)
                error('NeuroAnalyzer:CSDMethods:badParameter', ...
                    'csdGrid must have one row per grid depth.');
            end
            w = CSDMethods.trapzWeights(zg);
            K = CSDMethods.discKernel(ze - zg, radiusUm * 1e-6) .* w / (2 * sigma);
            phi = K * csdGrid;
        end
    end

    methods(Static, Access = private)

        %% icsd - Shared delta / step / spline inversion, smoothing and info
        function [c, info] = icsd(id, V, depthsUm, params)
            [V, z] = CSDMethods.checkInputs(V, depthsUm);
            p = CSDMethods.fillParams(params, z);
            F = CSDMethods.forwardMatrix(id, z, p);
            c = F \ V;                                         % A/m^3
            if p.smoothUm > 0
                c = CSDMethods.gaussSmooth(z, p.smoothUm) * c;
            end
            [~, label] = CSDMethods.methodId(id);
            zg = z; cg = c;
            if strcmp(id, 'spline')
                zg = CSDMethods.gridUm(z, p.gridStepUm);
                cg = CSDMethods.naturalSplineMatrix(z(:), zg) * c;
            end
            info = struct('method', id, 'label', label, 'unit', 'A/m^3', 'toAm3', 1, ...
                'params', p, 'depthsUm', z, 'zGridUm', zg, 'csdGrid', cg, 'condF', cond(F));
        end

        %% checkInputs - Numeric finite 2-D potentials, matching increasing depths
        function [V, z] = checkInputs(V, depthsUm)
            if ~(isnumeric(V) && ismatrix(V) && ~isempty(V) && all(isfinite(V(:))))
                error('NeuroAnalyzer:CSDMethods:badPotentials', ...
                    'Potentials must be a finite numeric channels x time matrix.');
            end
            V = double(V);
            z = CSDMethods.checkDepths(depthsUm, size(V, 1));
        end

        %% checkDepths - One finite, strictly increasing depth per channel, >= 3
        function z = checkDepths(depthsUm, n)
            if ~(isnumeric(depthsUm) && isvector(depthsUm) && numel(depthsUm) == n && all(isfinite(depthsUm)))
                error('NeuroAnalyzer:CSDMethods:badDepths', ...
                    'Give one finite depth (um) per channel.');
            end
            if n < 3
                error('NeuroAnalyzer:CSDMethods:tooFewChannels', 'CSD needs at least 3 channels.');
            end
            z = double(depthsUm(:)');
            if any(diff(z) <= 0)
                error('NeuroAnalyzer:CSDMethods:badDepths', ...
                    'Depths must increase strictly from the top to the bottom contact.');
            end
        end

        %% fillParams - Defaults for missing fields, validate
        function p = fillParams(params, z)
            if isempty(params), params = struct(); end
            if ~isstruct(params)
                error('NeuroAnalyzer:CSDMethods:badParameter', 'params must be a struct.');
            end
            p = CSDMethods.defaults();
            f = fieldnames(params);
            for k = 1:numel(f)
                p.(f{k}) = params.(f{k});
            end
            h = median(diff(z));
            if isempty(p.sigmaTop), p.sigmaTop = p.sigma; end
            if isempty(p.RGridUm), p.RGridUm = h * [0.5 0.75 1 1.5 2 3]; end
            if isempty(p.extUm), p.extUm = h; end
            if isempty(p.gridStepUm), p.gridStepUm = h / 4; end
            if isempty(p.smoothUm), p.smoothUm = 0; end
            pos = {'sigma', 'diameterUm', 'gridStepUm'};
            for k = 1:numel(pos)
                v = p.(pos{k});
                if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0)
                    error('NeuroAnalyzer:CSDMethods:badParameter', ...
                        'Parameter %s must be a positive number.', pos{k});
                end
            end
            nonneg = {'smoothUm', 'sigmaTop', 'extUm'};
            for k = 1:numel(nonneg)
                v = p.(nonneg{k});
                if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0)
                    error('NeuroAnalyzer:CSDMethods:badParameter', ...
                        'Parameter %s must be a number >= 0.', nonneg{k});
                end
            end
            opt = {'RUm', 'lambda'};
            for k = 1:numel(opt)
                v = p.(opt{k});
                if ~isempty(v) && ~(isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0)
                    error('NeuroAnalyzer:CSDMethods:badParameter', ...
                        'Parameter %s must be empty (automatic) or a number >= 0.', opt{k});
                end
            end
            grids = {'RGridUm', 'lambdaGrid'};
            for k = 1:numel(grids)
                v = p.(grids{k});
                if ~(isnumeric(v) && ~isempty(v) && all(isfinite(v(:))) && all(v(:) > 0))
                    error('NeuroAnalyzer:CSDMethods:badParameter', ...
                        'Parameter %s must be a list of positive numbers.', grids{k});
                end
                p.(grids{k}) = double(v(:)');
            end
            if ~(ischar(p.splineEnds) && any(strcmpi(p.splineEnds, {'extend', 'zero'})))
                error('NeuroAnalyzer:CSDMethods:badParameter', 'Parameter splineEnds must be ''extend'' or ''zero''.');
            end
            v = p.nSources;
            if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v >= 3 && v == round(v))
                error('NeuroAnalyzer:CSDMethods:badParameter', 'Parameter nSources must be an integer >= 3.');
            end
        end

        %% discKernel - sqrt(dz^2 + R^2) - |dz| (m): on-axis potential of a uniform disc x 2 sigma / C
        function k = discKernel(dz, r)
            k = sqrt(dz .^ 2 + r ^ 2) - abs(dz);
        end

        %% discKernelIntegral - Integral of discKernel from 0 to u (closed form, m^2)
        function g = discKernelIntegral(u, r)
            g = 0.5 * (u .* sqrt(u .^ 2 + r ^ 2) + r ^ 2 * asinh(u / r)) - 0.5 * u .* abs(u);
        end

        %% layerThickness - Local contact spacing (m) per contact (column)
        function h = layerThickness(zm)
            d = diff(zm(:));
            h = zeros(numel(zm), 1);
            h(1) = d(1); h(end) = d(end);
            h(2:end-1) = (d(1:end-1) + d(2:end)) / 2;
        end

        %% gridUm - Estimation grid from the first to the last contact
        function zg = gridUm(z, stepUm)
            n = max(2, round((z(end) - z(1)) / stepUm) + 1);
            zg = linspace(z(1), z(end), n);
        end

        %% trapzWeights - Trapezoid weights for an increasing grid (row)
        function w = trapzWeights(x)
            x = x(:)';
            d = diff(x);
            w = [d / 2, 0] + [0, d / 2];
        end

        %% gaussSmooth - Row-normalised Gaussian smoothing matrix across depth
        function G = gaussSmooth(z, sdUm)
            G = exp(-(z(:) - z(:)') .^ 2 / (2 * sdUm ^ 2));
            G = G ./ sum(G, 2);
        end

        %% naturalSplineMatrix - Values at xq of the natural cubic spline through (x, y): S * y
        % Zero outside [x(1), x(end)].
        function S = naturalSplineMatrix(x, xq)
            x = x(:); xq = xq(:);
            n = numel(x);
            h = diff(x);
            A = zeros(n); B = zeros(n);
            A(1, 1) = 1; A(n, n) = 1;
            for i = 2:n-1
                A(i, i-1) = h(i-1); A(i, i) = 2 * (h(i-1) + h(i)); A(i, i+1) = h(i);
                B(i, i-1) = 6 / h(i-1); B(i, i) = -6 / h(i-1) - 6 / h(i); B(i, i+1) = 6 / h(i);
            end
            M = A \ B;                                   % second derivatives = M * y
            S = zeros(numel(xq), n);
            k = CSDMethods.intervalIndex(x, xq);
            in = k > 0;
            kk = k(in); xx = xq(in);
            hk = h(kk);
            a = (x(kk + 1) - xx) ./ hk;                  % weight of y_k
            b = (xx - x(kk)) ./ hk;                      % weight of y_k+1
            ca = (a .^ 3 - a) .* hk .^ 2 / 6;            % weight of M_k
            cb = (b .^ 3 - b) .* hk .^ 2 / 6;            % weight of M_k+1
            rows = find(in);
            Sin = ca .* M(kk, :) + cb .* M(kk + 1, :);
            for j = 1:numel(rows)
                Sin(j, kk(j)) = Sin(j, kk(j)) + a(j);
                Sin(j, kk(j) + 1) = Sin(j, kk(j) + 1) + b(j);
            end
            S(rows, :) = Sin;
        end

        %% kcsdPotBasis - Potential (V per unit amplitude) of each Gaussian basis source at the contacts
        % zm: contacts (m, column); src: centres (m, row); R: basis SD (m);
        % r: disc radius (m). Kernel integrated with the trapezoid rule on
        % a grid fine relative to R, the spacing h and r.
        function B = kcsdPotBasis(zm, src, R, r, sigma, h)
            step = min([R, h, r]) / 25;
            lo = min(src) - 5 * R; hi = max(src) + 5 * R;
            nq = ceil((hi - lo) / step) + 1;
            zq = linspace(lo, hi, nq);
            w = CSDMethods.trapzWeights(zq);
            Kq = CSDMethods.discKernel(zm - zq, r) .* w / (2 * sigma);   % n x nq
            Bq = exp(-(zq(:) - src) .^ 2 / (2 * R ^ 2));                 % nq x M
            B = Kq * Bq;                                                 % n x M
        end

        %% intervalIndex - k with x(k) <= xq <= x(k+1) (k <= n-1), 0 outside [x(1), x(end)]
        function k = intervalIndex(x, xq)
            n = numel(x);
            k = zeros(size(xq));
            tol = 1e-12 * max(1, abs(x(end) - x(1)));
            for i = 1:numel(xq)
                if xq(i) < x(1) - tol || xq(i) > x(end) + tol, continue; end
                j = find(x <= xq(i) + tol, 1, 'last');
                k(i) = min(max(j, 1), n - 1);
            end
        end
    end
end
