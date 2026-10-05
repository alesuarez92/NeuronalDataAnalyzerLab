%% ImagingChecks.m
% =========================================================================
% IMAGING CHECKS - QUALITY CHECKS OF ROI TRACES FROM AN IMAGE STACK
% =========================================================================
% Checks that ROI Analysis runs after every Run, before its traces are
% used: did the tissue move more than the cells are wide, did the dye
% bleach, did the camera saturate, and does a preprocessing step undo the
% measure. Each row says what was found, why it matters and what to try
% (QualityChecks format).
%
%   o = ImagingChecks.options()   settings of the checks:
%       names           {} | one name per ROI (texts name the ROIs)
%       method          the ROI Analysis method ('Brightness', 'Movement',
%                       'Both', 'ΔF/F (gCaMP)', 'Kymograph', 'Vessel
%                       diameter'); the bleaching check only runs for the
%                       methods that measure brightness
%       motionCorrected true when the traces come from the motion-
%                       corrected stack
%       shifts          N x 2 [dy dx] (px): the shifts that motion
%                       correction applied, or the movement estimated on
%                       the raw frames when it is off ([] = not known)
%       residual        M x 2 movement left in the corrected stack ([] =
%                       not measured)
%       normalize       true when every frame was normalised to 0-1
%       baselineFrames  frames of the ΔF/F baseline (F0), for the texts
%   Q = ImagingChecks.run(stack, masks, F, t, o, Q)
%       Motion, Bleaching, Saturation and Preprocessing below. stack: the
%       frames as loaded (H x W x N or H x W x C x N, any class); masks:
%       H x W x K logical ([] for the line methods); F: K x N mean
%       brightness of each ROI (before normalisation; [] for the line
%       methods); t: 1 x N times (s, or frame numbers). Rows are appended
%       to Q ([] or omitted: new rows).
%   Q = ImagingChecks.motion(Q, masks, o)
%       How far the frames moved from their usual position (the largest
%       distance from the median position) against the size of the
%       smallest ROI (the diameter of a disc of the same area). Not
%       corrected: Check above MotionCheck (0.2) of that size and 1 px,
%       Warning from MotionWarning (0.5) of it: the cell leaves its ROI,
%       which then measures its neighbours. Corrected: the same rules on
%       the residual movement; a Check when the correction moved frames by
%       more than a whole ROI (a rigid correction cannot follow tissue that
%       bends or moves in depth). Line methods: Check above 2 px.
%   Q = ImagingChecks.bleaching(Q, F, t, o)
%       Change of each ROI's baseline (20th percentile of the first and of
%       the last tenth of the frames, at least 5 frames each): Check above
%       BleachCheck (10%), Warning above BleachWarning (25%) when it
%       darkens; a Check when it brightens by more than 10% (focus or
%       light drift).
%   Q = ImagingChecks.saturation(Q, stack, masks, o)
%       Pixels at the top value of the stack inside each ROI (the whole
%       image for the line methods): Check above SatCheck (0.1%), Warning
%       above SatWarning (1%) of a ROI's pixel-frames (the worst ROI sets
%       the level; the text names each ROI above 0.1%). The top value
%       counts as clipping when it is a camera's ceiling (255, 4095, 65535,
%       intmax) or values pile up there (more than one step below it);
%       otherwise it is just the brightest value. The top value is
%       named when it is a camera's ceiling (255, 4095, 65535, ...).
%   Q = ImagingChecks.preprocessing(Q, o)
%       Normalising every frame to 0-1 with a brightness or ΔF/F measure:
%       Check (it removes changes of the whole frame's brightness).
%   s = ImagingChecks.estimateShifts(stack, maxFrames)
%       Movement of up to maxFrames (default 100) evenly spaced frames
%       against their mean (registerStackRigid), [dy dx] per frame: how the
%       checks see motion when motion correction is off, and what is left
%       after it.
%   m = ImagingChecks.motionSize(shifts)
%       Largest distance of a frame from the median position (px).
%   d = ImagingChecks.roiSize(masks)
%       Diameter of a disc with the area of each ROI (px), 1 x K.
%   c = ImagingChecks.bleachChange(f)
%       Relative change of one trace's baseline from start to end (-0.3 =
%       30% darker at the end).
%
% Base MATLAB only; also runs in GNU Octave.
% =========================================================================

classdef ImagingChecks
    properties(Constant)
        MotionCheck = 0.2       % movement / smallest ROI size: Check above
        MotionWarning = 0.5     % ... Warning from
        MotionLinePx = 2        % line methods: Check above (px)
        BleachCheck = 0.10      % baseline change from start to end: Check above
        BleachWarning = 0.25    % darker by more than this: Warning
        SatCheck = 0.001        % ROI pixel-frames at the top value: Check above
        SatWarning = 0.01       % ... Warning above
        BrightnessMethods = {'Brightness', 'Both', 'ΔF/F (gCaMP)'}
        LineMethods = {'Kymograph', 'Vessel diameter'}
    end

    methods(Static)

        %% options - Default settings of the checks
        function o = options()
            o = struct('names', {{}}, 'method', '', 'motionCorrected', false, 'shifts', [], ...
                'residual', [], 'normalize', false, 'baselineFrames', NaN);
        end

        %% run - Every imaging check
        function Q = run(stack, masks, F, t, o, Q)
            if nargin < 6 || isempty(Q), Q = QualityChecks.none(); end
            o = ImagingChecks.complete(o);
            Q = ImagingChecks.motion(Q, masks, o);
            Q = ImagingChecks.bleaching(Q, F, t, o);
            Q = ImagingChecks.saturation(Q, stack, masks, o);
            Q = ImagingChecks.preprocessing(Q, o);
        end

        %% motion - Movement of the frames against the size of the smallest ROI
        function Q = motion(Q, masks, o)
            o = ImagingChecks.complete(o);
            if isempty(o.shifts), return; end
            moved = ImagingChecks.motionSize(o.shifts);
            isLine = isempty(masks) || any(strcmp(o.method, ImagingChecks.LineMethods));
            why = ['A ROI stays where it was drawn while the tissue moves: when the cell slides out ' ...
                'of it, the ROI measures its neighbours and the background, and the movement itself ' ...
                'makes false rises and dips in the trace.'];
            if isLine
                lim = ImagingChecks.MotionLinePx;
                if o.motionCorrected
                    left = ImagingChecks.motionSize(o.residual);
                    if isfinite(left) && left > lim
                        Q = QualityChecks.add(Q, 'check', 'Motion', sprintf(['After motion correction the ' ...
                            'frames still move by up to %.1f px (corrected: up to %.1f px).'], left, moved), ...
                            ['The line samples the image, not the vessel: movement along the line shifts ' ...
                            'the kymograph and the diameter profile.'], ...
                            'Look at the corrected movie; crop to the vessel or use a shorter recording.');
                    else
                        Q = QualityChecks.add(Q, 'ok', 'Motion', sprintf(['Motion corrected (rigid): frames ' ...
                            'moved by up to %.1f px and were shifted back.'], moved));
                    end
                elseif moved > lim
                    Q = QualityChecks.add(Q, 'check', 'Motion', sprintf(['The frames move by up to %.1f px ' ...
                        'and motion correction is off.'], moved), ...
                        ['The line samples the image, not the vessel: movement along the line shifts ' ...
                        'the kymograph and the diameter profile.'], 'Tick Motion correction (step 2) and Run again.');
                else
                    Q = QualityChecks.add(Q, 'ok', 'Motion', sprintf('The frames move by %.1f px at most.', moved));
                end
                return;
            end
            d = ImagingChecks.roiSize(masks);
            [dMin, k] = min(d);
            roiTxt = sprintf('the smallest ROI (%s) is %.0f px across', ImagingChecks.roiName(o, k), dMin);
            if o.motionCorrected
                left = ImagingChecks.motionSize(o.residual);
                if isfinite(left)
                    [lvl, rel] = ImagingChecks.motionLevel(left, dMin);
                    if ~strcmp(lvl, 'ok')
                        Q = QualityChecks.add(Q, lvl, 'Motion', sprintf(['After motion correction the frames ' ...
                            'still move by up to %.1f px (%.0f%% of a ROI): %s.'], left, 100 * rel, roiTxt), why, ...
                            ['The correction is rigid (it only shifts whole frames): tissue that bends or ' ...
                            'moves in depth is not corrected. Use a stretch of the recording with less ' ...
                            'movement, or a non-rigid correction in another program (e.g. NoRMCorre, ' ...
                            'suite2p) before loading.']);
                        return;
                    end
                end
                if moved > dMin
                    Q = QualityChecks.add(Q, 'check', 'Motion', sprintf(['Motion corrected (rigid), but the ' ...
                        'frames had moved by up to %.1f px, more than a whole ROI: %s.'], moved, roiTxt), ...
                        ['Shifting whole frames back corrects sliding, not tissue that bends or moves in ' ...
                        'depth; with this much movement some of it is usually left.'], ...
                        ['Show the Mean image: cells should look as sharp as in one frame. If they are ' ...
                        'blurred, correct the movie non-rigidly in another program before loading.']);
                else
                    Q = QualityChecks.add(Q, 'ok', 'Motion', sprintf(['Motion corrected (rigid): frames moved ' ...
                        'by up to %.1f px and were shifted back; %s.'], moved, roiTxt));
                end
                return;
            end
            [lvl, rel] = ImagingChecks.motionLevel(moved, dMin);
            switch lvl
                case 'warning'
                    if moved >= dMin
                        how = 'more than a whole ROI';
                    else
                        how = sprintf('%.0f%% of a ROI', 100 * rel);
                    end
                    Q = QualityChecks.add(Q, 'warning', 'Motion', sprintf(['The frames move by up to %.1f px ' ...
                        '(%s) and motion correction is off: %s.'], moved, how, roiTxt), why, ...
                        'Tick Motion correction (step 2) and Run again.');
                case 'check'
                    Q = QualityChecks.add(Q, 'check', 'Motion', sprintf(['The frames move by up to %.1f px ' ...
                        '(%.0f%% of a ROI) and motion correction is off: %s.'], moved, 100 * rel, roiTxt), why, ...
                        'Tick Motion correction (step 2) and Run again, then compare the traces.');
                otherwise
                    Q = QualityChecks.add(Q, 'ok', 'Motion', sprintf(['The frames move by %.1f px at most ' ...
                        '(motion correction off); %s.'], moved, roiTxt));
            end
        end

        %% bleaching - Baseline of each ROI at the end against the start
        function Q = bleaching(Q, F, t, o) %#ok<INUSL>
            o = ImagingChecks.complete(o);
            if isempty(F) || ~any(strcmp(o.method, ImagingChecks.BrightnessMethods)), return; end
            K = size(F, 1);
            c = zeros(1, K);
            for k = 1:K
                c(k) = ImagingChecks.bleachChange(F(k, :));
            end
            if all(~isfinite(c)), return; end
            [lo, kLo] = min(c);
            [hi, kHi] = max(c);
            isDff = strcmp(o.method, 'ΔF/F (gCaMP)');
            if isDff
                why = sprintf(['ΔF/F divides by F0, the mean of the first %s: as the dye bleaches, ΔF/F ' ...
                    'drifts below 0 and the same response looks smaller late in the recording.'], ...
                    ImagingChecks.framesText(o.baselineFrames));
            else
                why = ['A slow loss of brightness looks like a decrease, and the same response is smaller ' ...
                    'late in the recording.'];
            end
            act = ['Lower the light or the exposure; compare responses at the same time in the recording; ' ...
                'or correct the bleaching before measuring (divide by an exponential fitted to the baseline).'];
            if -lo > ImagingChecks.BleachCheck
                lvl = 'check';
                if -lo > ImagingChecks.BleachWarning, lvl = 'warning'; end
                Q = QualityChecks.add(Q, lvl, 'Bleaching', sprintf(['The baseline is %.0f%% darker at the ' ...
                    'end than at the start%s.'], -100 * lo, ImagingChecks.whichRoi(o, kLo, K, c < -ImagingChecks.BleachCheck)), ...
                    why, act);
            elseif hi > ImagingChecks.BleachCheck
                Q = QualityChecks.add(Q, 'check', 'Bleaching', sprintf(['The baseline is %.0f%% brighter at ' ...
                    'the end than at the start%s.'], 100 * hi, ImagingChecks.whichRoi(o, kHi, K, c > ImagingChecks.BleachCheck)), ...
                    ['A slow rise is not bleaching: the focus, the light or the cell itself changed, and ' ...
                    'it adds to the responses.'], 'Check the focus and the light source over the recording.');
            else
                [~, kMax] = max(abs(c));
                Q = QualityChecks.add(Q, 'ok', 'Bleaching', sprintf(['The baseline changes by %+.0f%% from ' ...
                    'start to end at most (check above %.0f%%).'], 100 * c(kMax), 100 * ImagingChecks.BleachCheck));
            end
        end

        %% saturation - Pixels at the top value inside the ROIs
        function Q = saturation(Q, stack, masks, o)
            o = ImagingChecks.complete(o);
            if isempty(stack), return; end
            top = double(max(stack(:)));
            atTop = stack == top;
            if ndims(stack) == 4
                atTop = reshape(any(atTop, 3), size(stack, 1), size(stack, 2), size(stack, 4));
            end
            nAll = nnz(atTop);
            topTxt = ImagingChecks.topText(stack, top);
            isLine = isempty(masks) || any(strcmp(o.method, ImagingChecks.LineMethods));
            if isLine
                region = true(size(atTop, 1), size(atTop, 2));
                where = 'of the image';
            else
                region = any(masks, 3);
                where = 'of the ROI pixels over all frames';
            end
            N = size(atTop, 3);
            inRoi = nnz(atTop & repmat(region, [1 1 N]));
            if ~ImagingChecks.isCeiling(stack, top, nAll)    % the brightest value, not a ceiling
                inRoi = 0; atTop(:) = false;
            end
            frac = inRoi / max(1, nnz(region) * N);
            worst = frac;
            perRoi = [];
            if ~isLine
                perRoi = zeros(1, size(masks, 3));
                for k = 1:size(masks, 3)
                    m = repmat(masks(:, :, k), [1 1 N]);
                    perRoi(k) = nnz(atTop & m) / max(1, nnz(m));
                end
                worst = max(perRoi);
            end
            why = ['A pixel at the top value is clipped: the true brightness is higher, so peaks are cut ' ...
                'flat and ΔF/F and brightness changes are underestimated.'];
            act = ['Lower the gain, the exposure or the light so the brightest cells stay below the top; ' ...
                'leave out the clipped ROIs.'];
            if worst > ImagingChecks.SatCheck
                lvl = 'check';
                if worst > ImagingChecks.SatWarning, lvl = 'warning'; end
                if isLine
                    Q = QualityChecks.add(Q, lvl, 'Saturation', sprintf('%.2g%% of the image is at the top value %s.', ...
                        100 * frac, topTxt), why, act);
                else
                    Q = QualityChecks.add(Q, lvl, 'Saturation', sprintf(['ROI pixels reach the top value %s; ' ...
                        'share of the pixels over all frames%s.'], topTxt, ...
                        ImagingChecks.namesOver(o, perRoi, ImagingChecks.SatCheck)), why, act);
                end
            elseif inRoi > 0
                Q = QualityChecks.add(Q, 'ok', 'Saturation', sprintf(['%d pixel-frame(s) %s at the top value ' ...
                    '%s (%.2g%%, check above %.1f%%).'], inRoi, where, topTxt, 100 * frac, 100 * ImagingChecks.SatCheck));
            elseif isLine
                Q = QualityChecks.add(Q, 'ok', 'Saturation', sprintf(['No part of the image is clipped (the ' ...
                    'top value %s is reached by a single pixel at most).'], topTxt));
            else
                Q = QualityChecks.add(Q, 'ok', 'Saturation', sprintf(['No ROI pixel is clipped (the brightest ' ...
                    'value of the stack is %s).'], topTxt));
            end
        end

        %% preprocessing - Steps that undo a brightness measure
        function Q = preprocessing(Q, o)
            o = ImagingChecks.complete(o);
            if o.normalize && any(strcmp(o.method, ImagingChecks.BrightnessMethods))
                Q = QualityChecks.add(Q, 'check', 'Preprocessing', sprintf(['Every frame was normalised ' ...
                    'to 0-1 before %s.'], o.method), ...
                    ['Normalising each frame removes changes of the whole frame''s brightness (bleaching, ' ...
                    'but also large responses), so the values are no longer brightness.'], ...
                    'Untick Normalize each frame (step 2) for brightness and ΔF/F.');
            end
        end

        %% estimateShifts - Movement of evenly spaced frames against their mean
        function s = estimateShifts(stack, maxFrames)
            if nargin < 2 || isempty(maxFrames), maxFrames = 100; end
            if ndims(stack) == 4
                N = size(stack, 4);
            else
                N = size(stack, 3);
            end
            if N < 2, s = zeros(N, 2); return; end
            idx = unique(round(linspace(1, N, min(N, maxFrames))));
            if ndims(stack) == 4
                g = reshape(mean(double(stack(:, :, :, idx)), 3), size(stack, 1), size(stack, 2), numel(idx));
            else
                g = double(stack(:, :, idx));
            end
            [~, s] = registerStackRigid(g, 'mean');
        end

        %% motionSize - Largest distance of a frame from the median position (px)
        function m = motionSize(shifts)
            if isempty(shifts), m = NaN; return; end
            dy = shifts(:, 1) - median(shifts(:, 1));
            dx = shifts(:, 2) - median(shifts(:, 2));
            m = max(hypot(dy, dx));
        end

        %% roiSize - Diameter of a disc with the area of each ROI (px)
        function d = roiSize(masks)
            K = size(masks, 3);
            d = zeros(1, K);
            for k = 1:K
                d(k) = 2 * sqrt(nnz(masks(:, :, k)) / pi);
            end
        end

        %% bleachChange - Relative change of the baseline from start to end
        function c = bleachChange(f)
            f = double(f(:)');
            f = f(isfinite(f));
            N = numel(f);
            if N < 10, c = NaN; return; end
            w = max(5, round(N / 10));
            w = min(w, floor(N / 2));
            a = ImagingChecks.pctl(f(1:w), 20);
            b = ImagingChecks.pctl(f(end - w + 1:end), 20);
            if ~(a > 0), c = NaN; return; end
            c = b / a - 1;
        end
    end

    methods(Static, Access = private)

        %% complete - Fill missing option fields with the defaults
        function o = complete(o)
            d = ImagingChecks.options();
            if isempty(o), o = d; return; end
            f = fieldnames(d);
            for k = 1:numel(f)
                if ~isfield(o, f{k}), o.(f{k}) = d.(f{k}); end
            end
            o.method = char(o.method);
        end

        %% isCeiling - Is the top value a ceiling (clipping) rather than just the brightest value?
        % Yes for a camera's top value (intmax of the class, or 2^k - 1 from
        % 255 up) reached by more than one pixel-frame, or when values pile
        % up there: more pixel-frames at the top than one step below it
        % (integer values), or the same top value more than once (others).
        function tf = isCeiling(stack, top, nTop)
            tf = false;
            if nTop <= 1, return; end
            b = log2(top + 1);
            if (isinteger(stack) && top == double(intmax(class(stack)))) || ...
                    (top >= 255 && abs(b - round(b)) < 1e-9)
                tf = true;
                return;
            end
            if all(double(stack(1:min(end, 1e5))) == round(double(stack(1:min(end, 1e5)))))
                tf = nTop > nnz(stack == top - 1);
            else
                tf = true;
            end
        end

        %% motionLevel - Level of a movement against a ROI size
        function [lvl, rel] = motionLevel(moved, dMin)
            rel = moved / max(dMin, eps);
            if rel >= ImagingChecks.MotionWarning && moved > 1
                lvl = 'warning';
            elseif rel > ImagingChecks.MotionCheck && moved > 1
                lvl = 'check';
            else
                lvl = 'ok';
            end
        end

        %% roiName - Name of ROI k
        function s = roiName(o, k)
            if k <= numel(o.names) && ~isempty(o.names{k})
                s = o.names{k};
            else
                s = sprintf('ROI %d', k);
            end
        end

        %% whichRoi - ' (Cell 2)' or ' (Cell 2; also Cell 1)' when there are several ROIs
        function s = whichRoi(o, k, K, hit)
            s = '';
            if K < 2, return; end
            others = setdiff(find(hit), k);
            s = sprintf(' (%s', ImagingChecks.roiName(o, k));
            if ~isempty(others)
                names = arrayfun(@(i) ImagingChecks.roiName(o, i), others, 'UniformOutput', false);
                s = sprintf('%s; also %s', s, strjoin(names, ', '));
            end
            s = [s ')'];
        end

        %% namesOver - ': Cell 2 4.1%, Cell 3 0.2%' for the ROIs above a fraction
        function s = namesOver(o, v, lim)
            s = '';
            idx = find(v > lim);
            if isempty(idx), return; end
            [~, ord] = sort(v(idx), 'descend');
            idx = idx(ord);
            parts = arrayfun(@(i) sprintf('%s %.2g%%', ImagingChecks.roiName(o, i), 100 * v(i)), idx, ...
                'UniformOutput', false);
            s = [': ' strjoin(parts, ', ')];
        end

        %% topText - '4095 (the top of a 12-bit camera)' or '0.93'
        function s = topText(stack, top)
            s = sprintf('%.4g', top);
            if isinteger(stack) && top == double(intmax(class(stack)))
                s = sprintf('%s (the largest %s value)', s, class(stack));
                return;
            end
            b = log2(top + 1);
            if top >= 255 && abs(b - round(b)) < 1e-9 && round(b) <= 32
                s = sprintf('%s (the top of a %d-bit camera)', s, round(b));
            end
        end

        %% framesText - '30 frames'
        function s = framesText(n)
            if isfinite(n)
                s = sprintf('%d frames', round(n));
            else
                s = 'frames';
            end
        end

        %% pctl - Percentile with linear interpolation (no toolbox)
        function v = pctl(x, p)
            x = sort(x(:));
            n = numel(x);
            if n == 0, v = NaN; return; end
            if n == 1, v = x; return; end
            pos = 1 + (n - 1) * p / 100;
            lo = floor(pos);
            hi = min(lo + 1, n);
            v = x(lo) + (pos - lo) * (x(hi) - x(lo));
        end
    end
end
