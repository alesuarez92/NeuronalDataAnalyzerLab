%% ERPAnalysis.m
% =========================================================================
% ERP ANALYSIS - HEADLESS ONSET DETECTION, EPOCH AVERAGING AND CSD
% =========================================================================
% The computations behind LFPAnalysisApp's ERP and CSD steps, without any
% UI, so scripts and batch processing get exactly the same numbers as the
% window. Toolbox-free (base MATLAB).
%
%   [onsetTimes, onsetIdx] = ERPAnalysis.detectOnsets(stim, fs, threshold, minISI)
%       Stimulus onsets: upward crossings of threshold by the
%       mean-subtracted stimulus. A crossing within minISI (s) of the last
%       kept onset is dropped (a pulse train gives one onset; same rule as
%       LDFPipeline.detectOnsets and SpikeTrains.stimulusOnsets). Sample k is at time
%       (k-1)/fs, so onsetTimes = (onsetIdx - 1) / fs (s).
%   [erpAvg, erpStd, t, nValid, epochs, valid] = ...
%           ERPAnalysis.average(lfp, fs, onsetTimes, pre, post)
%       Cuts one epoch per onset from onset - pre to onset + post (s) out
%       of lfp (channels x samples, sampled at fs, first sample at t = 0).
%       The onset sample is round(onsetTime * fs) + 1. Epochs that would
%       run past either end of the recording are left NaN and excluded
%       ('omitnan'); nValid counts the complete ones. erpAvg / erpStd are
%       channels x time (mean and SD over epochs), t = (-preN:postN) / fs,
%       epochs is channels x time x onsets and valid flags complete epochs.
%   csd = ERPAnalysis.csd(erp, spacingUm, order)
%       Current source density: the negative second spatial derivative of
%       the ERP across depth, -d2V/dz2, with z the channel position
%       (spacingUm micrometres apart; converted to metres, so the result
%       is in erp units / m^2). order (optional, default all rows) lists
%       the erp rows from top (superficial) to bottom (deep); at least 3.
%       The first and last rows (where the three-point difference is not
%       defined) are copied from their neighbours. Sinks are negative.
%       Constant conductivity is assumed (it is left out, so the units are
%       those of the potential's second derivative, not A/m^3).
%       This is the 'standard' method of core/CSDMethods, which adds
%       inverse CSD (delta / step / spline) and kernel CSD in A/m^3.
%   o = ERPAnalysis.checkOptions()
%       Settings of the checks (defaults): channels (channel number of
%       each erp row; [] = 1..n), nOnsets (stimuli found), nEpochs
%       (complete epochs averaged), preSec / postSec (epoch window, s),
%       n1WindowMs ([5 50], where the N1 and the CSD sink are looked for),
%       computeCSD (true when a CSD was computed or attempted: the spacing
%       is checked), csd (contacts x time, rows top to bottom; [] = none),
%       csdOrder (channel number of each csd row), csdMethod ('standard' |
%       'delta' | 'step' | 'spline' | 'kcsd'), spacingUm (used; NaN =
%       none), spacingFile (the file's lfp_spacing_um; NaN = not given),
%       spacingSource ('file' | 'typed' | 'default' | 'setting'),
%       amplitudeScale / amplitudeUnit (1e6, uV: how amplitudes are shown).
%   Q = ERPAnalysis.checks(erpAvg, t, o)
%       Quality checks of an ERP (channels x time, t in s, 0 = onset) and
%       of its CSD (QualityChecks rows, one per topic):
%         Epochs             stimuli left out (epoch does not fit), fewer
%                            than MinEpochs (10) epochs: Check.
%         Stimulus artefact  each channel minus its pre-onset mean; an
%                            artefact when its largest deflection in the
%                            first ArtefactPeakMs (1.5 ms) exceeds
%                            ArtefactSD (10) baseline SDs; it ends when the
%                            deflection first falls below max(ArtefactEndSD
%                            (5) SDs, ArtefactEndFraction (5%) of its peak).
%                            Warning when it lasts into the N1 window (its
%                            tail moves the N1); says whether it is the
%                            same on every contact (it then largely cancels
%                            in the CSD, not in the ERP). Note without a
%                            pre-onset part.
%         Electrode spacing  (computeCSD) none: Warning; the default used
%                            because the file does not give it, or a
%                            spacing other than the file's: Check.
%         CSD sink           the most negative CSD in the N1 window; at
%                            an edge contact (standard: contacts 1, 2,
%                            n-1, n, since 1 and n are copies; other
%                            methods: 1 and n): Warning; no sink: Check.
%       Never throws on odd input (fewer rows instead); base MATLAB only,
%       also runs in GNU Octave.
%
% Method reference (CSD):
%   Mitzdorf U (1985). Current source-density method and application in
%     cat cerebral cortex: investigation of evoked potentials and EEG
%     phenomena. Physiol Rev 65(1):37-100.
% =========================================================================

classdef ERPAnalysis
    properties(Constant)
        MinEpochs = 10              % fewer epochs: Check
        ArtefactPeakMs = 1.5        % an artefact peaks within this time after the onset
        ArtefactSD = 10             % ... above this many baseline SDs
        ArtefactEndSD = 5           % it ends below max(this many SDs,
        ArtefactEndFraction = 0.05  % this fraction of its peak)
        ArtefactCommon = 0.8        % same on every contact: smallest / largest peak above this
    end

    methods(Static)

        %% detectOnsets - Upward threshold crossings of the mean-subtracted stimulus
        % stim: vector (row or column). fs: stimulus sampling rate (Hz).
        % threshold: in stimulus units, applied after subtracting the mean.
        % minISI: minimum interval (s) after the last kept onset.
        % OUTPUT: onsetTimes (s, row), onsetIdx (sample indices, row).
        function [onsetTimes, onsetIdx] = detectOnsets(stim, fs, threshold, minISI)
            if ~isvector(stim)
                error('NeuroAnalyzer:ERPAnalysis:stimNotVector', 'The stimulus must be a vector.');
            end
            stim = stim(:).';
            stim = stim - mean(stim);
            above = stim > threshold;
            onsetIdx = find(diff([0 above]) == 1);
            if isempty(onsetIdx)
                onsetIdx = zeros(1, 0);
                onsetTimes = zeros(1, 0);
                return;
            end
            % Keep a crossing only if it comes more than minISI after the last
            % KEPT onset (as LDF): a pulse train gives one onset per train
            keep = false(size(onsetIdx));
            last = -Inf;
            for i = 1:numel(onsetIdx)
                if (onsetIdx(i) - last) / fs > minISI
                    keep(i) = true;
                    last = onsetIdx(i);
                end
            end
            onsetIdx = onsetIdx(keep);
            onsetTimes = (onsetIdx - 1) / fs;   % sample k is at (k-1)/Fs
        end

        %% average - NaN-filled epochs around each onset; mean and SD of the complete ones
        function [erpAvg, erpStd, t, nValid, epochs, valid] = average(lfp, fs, onsetTimes, preS, postS)
            preSamples = round(preS * fs);
            postSamples = round(postS * fs);
            totalSamples = preSamples + postSamples + 1;
            nOn = numel(onsetTimes);
            % NaN-filled so skipped (edge) epochs are ignored by 'omitnan'
            epochs = nan(size(lfp, 1), totalSamples, nOn);
            valid = false(1, nOn);
            for k = 1:nOn
                centerIdx = round(onsetTimes(k) * fs) + 1;
                idxRange = centerIdx - preSamples : centerIdx + postSamples;
                if idxRange(1) < 1 || idxRange(end) > size(lfp, 2)
                    continue;
                end
                epochs(:, :, k) = lfp(:, idxRange);
                valid(k) = true;
            end
            nValid = sum(valid);
            erpAvg = mean(epochs, 3, 'omitnan');
            erpStd = std(epochs, 0, 3, 'omitnan');
            t = (-preSamples:postSamples) / fs;
        end

        %% csd - Negative second spatial derivative across ordered channels
        function c = csd(erp, spacingUm, order)
            if nargin < 3 || isempty(order), order = 1:size(erp, 1); end
            if ~(isscalar(spacingUm) && isfinite(spacingUm) && spacingUm > 0)
                error('NeuroAnalyzer:ERPAnalysis:badSpacing', ...
                    'Inter-electrode spacing must be a positive number (um).');
            end
            if numel(order) < 3
                error('NeuroAnalyzer:ERPAnalysis:tooFewChannels', 'CSD needs at least 3 channels.');
            end
            erp = erp(order, :);
            dz = spacingUm * 1e-6;                  % metres
            c = -diff(erp, 2, 1) / dz^2;
            c = [c(1,:); c; c(end,:)];              % replicate edge rows (no padarray dependency)
        end

        %% checkOptions - Default settings of ERPAnalysis.checks
        function o = checkOptions()
            o = struct('channels', [], 'nOnsets', NaN, 'nEpochs', NaN, 'preSec', NaN, 'postSec', NaN, ...
                'n1WindowMs', [5 50], 'computeCSD', false, 'csd', [], 'csdOrder', [], ...
                'csdMethod', 'standard', 'spacingUm', NaN, 'spacingFile', NaN, 'spacingSource', '', ...
                'amplitudeScale', 1e6, 'amplitudeUnit', [char(181) 'V']);
        end

        %% checks - Quality checks of an ERP and its CSD (QualityChecks rows)
        function Q = checks(erpAvg, t, o)
            if nargin < 3, o = []; end
            Q = QualityChecks.none();
            x = ERPAnalysis.numeric(erpAvg);
            t = ERPAnalysis.numeric(t);
            t = t(:)';
            o = ERPAnalysis.completeOptions(o, size(x, 1));
            Q = ERPAnalysis.epochCheck(Q, o);
            if ~isempty(x) && ismatrix(x) && size(x, 2) == numel(t)
                Q = ERPAnalysis.artefactCheck(Q, x, t, o);
            end
            if o.computeCSD || ~isempty(o.csd)
                Q = ERPAnalysis.spacingCheck(Q, o);
            end
            if ~isempty(o.csd) && size(o.csd, 2) == numel(t)
                Q = ERPAnalysis.sinkCheck(Q, o.csd, t, o);
            end
        end
    end

    methods(Static, Hidden)

        %% epochCheck - Stimuli left out (epoch does not fit), fewer than MinEpochs epochs
        function Q = epochCheck(Q, o)
            nE = o.nEpochs;
            nOn = o.nOnsets;
            if ~(isfinite(nE) && nE >= 0), return; end
            if ~(isfinite(nOn) && nOn >= nE), nOn = nE; end
            found = {}; why = {}; act = {};
            if nOn > nE
                win = '';
                if isfinite(o.preSec) && isfinite(o.postSec)
                    win = sprintf(' (%g s before to %g s after the onset)', o.preSec, o.postSec);
                end
                found{end+1} = sprintf('%d of %d stimuli were left out because their epoch%s does not fit in the recording', ...
                    nOn - nE, nOn, win);
                act{end+1} = ['shorten the epoch (pre- / post-stimulus time), or record longer before the first ' ...
                    'and after the last stimulus'];
            end
            if nE < ERPAnalysis.MinEpochs
                found{end+1} = sprintf('only %d epoch(s) averaged', nE);
                why{end+1} = sprintf(['with fewer than %d epochs the average keeps much of the background ' ...
                    'activity, so the N1 latency and amplitude are uncertain'], ERPAnalysis.MinEpochs);
                act{end+1} = sprintf('record more stimuli (at least %d; more for small responses)', ERPAnalysis.MinEpochs);
            end
            if isempty(found)
                Q = QualityChecks.add(Q, 'ok', 'Epochs', sprintf('%d of %d stimuli averaged (check below %d epochs).', ...
                    nE, nOn, ERPAnalysis.MinEpochs));
            else
                w = '';
                if ~isempty(why), w = [ERPAnalysis.upperFirst(strjoin(why, '; ')) '.']; end
                Q = QualityChecks.add(Q, 'check', 'Epochs', [ERPAnalysis.upperFirst(strjoin(found, '; ')) '.'], w, ...
                    [ERPAnalysis.upperFirst(strjoin(act, '; ')) '.']);
            end
        end

        %% artefactCheck - A stimulus artefact at the onset that lasts into the N1 window
        function Q = artefactCheck(Q, x, t, o)
            topic = 'Stimulus artefact';
            n = size(x, 1);
            pre = t < 0;
            early = t >= 0 & t <= ERPAnalysis.ArtefactPeakMs / 1000;
            if nnz(early) < 2
                early(find(t >= 0, 2)) = true;            % at least the onset and the next sample
            end
            if nnz(pre) < 3 || ~any(early)
                Q = QualityChecks.add(Q, 'note', topic, ['Not checked: the epoch has no time before the onset ' ...
                    'to compare the first milliseconds with.'], '', ['Keep some time before each onset (pre-stimulus ' ...
                    'time), e.g. 50 ms.']);
                return;
            end
            e = find(early);
            pk = NaN(n, 1); sd = NaN(n, 1); tEnd = NaN(n, 1); has = false(n, 1);
            for c = 1:n
                y = x(c, :);
                b = y(pre);
                b = b(isfinite(b));
                if numel(b) < 3, continue; end
                y = y - mean(b);
                sd(c) = std(b);
                [m, j] = max(abs(y(e)));
                if ~(m > ERPAnalysis.ArtefactSD * sd(c)), continue; end
                has(c) = true;
                ip = e(j);
                pk(c) = y(ip);
                thr = max(ERPAnalysis.ArtefactEndSD * sd(c), ERPAnalysis.ArtefactEndFraction * abs(pk(c)));
                k = find(~(sign(pk(c)) * y(ip:end) >= thr), 1);
                if isempty(k), tEnd(c) = Inf; else, tEnd(c) = t(ip + k - 1); end
            end
            if ~any(isfinite(sd)), return; end
            if ~any(has)
                Q = QualityChecks.add(Q, 'ok', topic, sprintf(['No stimulus artefact: the ERP stays within %g times ' ...
                    'the baseline noise in the first %g ms after the onset.'], ERPAnalysis.ArtefactSD, ERPAnalysis.ArtefactPeakMs));
                return;
            end
            idx = find(has);
            [~, ord] = sort(tEnd(idx), 'descend');           % longest first
            idx = idx(ord);
            w = idx(1);
            [~, ib] = max(abs(pk(idx)));
            big = idx(ib);
            pks = pk(idx);
            common = n > 1 && numel(idx) == n && all(sign(pks) == sign(pks(1))) && ...
                min(abs(pks)) >= ERPAnalysis.ArtefactCommon * max(abs(pks));
            if n == 1
                where = '';
            elseif common
                where = sprintf(', the same on all %d channels,', n);
            elseif numel(idx) == n
                where = sprintf(', on all %d channels but of different sizes,', n);
            else
                where = sprintf(', on %s,', ERPAnalysis.channelList(o.channels, idx));
            end
            what = sprintf('A stimulus artefact of up to %s (%.0f times the baseline noise)%s', ...
                ERPAnalysis.amplitude(pk(big), o), abs(pk(big)) / sd(big), where);
            n1 = o.n1WindowMs(1);
            if isinf(tEnd(w))
                ends = 'lasts to the end of the epoch';
            else
                ends = sprintf('lasts until %.1f ms after the onset', 1000 * tEnd(w));
            end
            if tEnd(w) > n1 / 1000 + 1e-9
                why = ['The N1 is the most negative point of the N1 window: the artefact''s tail adds to it or ' ...
                    'pulls it up, and shifts its latency.'];
                if common
                    why = [why ' Being the same on every contact, it largely cancels in the CSD (a difference ' ...
                        'across depth), but not in the ERP.'];
                else
                    why = [why ' It differs between contacts, so it also enters the CSD.'];
                end
                act = ['remove the artefact before averaging (blank or interpolate the first milliseconds after ' ...
                    'each stimulus); for the next recordings lower the stimulus or use a reference closer to the ' ...
                    'recording site.'];
                if isfinite(tEnd(w))
                    act = sprintf('Measure the N1 after the artefact (e.g. an N1 window from %g ms), or %s', ...
                        ceil(1000 * tEnd(w)) + 1, act);
                else
                    act = ERPAnalysis.upperFirst(act);
                end
                Q = QualityChecks.add(Q, 'warning', topic, sprintf('%s %s: into the N1 window (from %g ms).', ...
                    what, ends, n1), why, act);
            else
                Q = QualityChecks.add(Q, 'ok', topic, sprintf('%s ends at %.1f ms, before the N1 window (from %g ms).', ...
                    what, 1000 * tEnd(w), n1));
            end
        end

        %% spacingCheck - The electrode spacing the CSD used, and where it came from
        function Q = spacingCheck(Q, o)
            topic = 'Electrode spacing';
            um = [char(181) 'm'];
            sp = o.spacingUm;
            f = o.spacingFile;
            why = sprintf(['The standard CSD is divided by the spacing squared (half the spacing gives 4 times ' ...
                'the CSD) and the depths of the sinks and sources follow the spacing; the iCSD and kCSD methods ' ...
                'also change shape.']);
            if ~(isfinite(sp) && sp > 0)
                Q = QualityChecks.add(Q, 'warning', topic, 'No electrode spacing: the CSD was not computed.', ...
                    'The CSD needs the distance between neighbouring contacts: without it there is no CSD and no sink.', ...
                    sprintf(['Type the probe''s contact spacing (%s, from its datasheet) in the settings, or save it ' ...
                    'with the LFP as lfp_spacing_um.'], um));
                return;
            end
            hasFile = isfinite(f) && f > 0;
            if hasFile && abs(f - sp) > 1e-6 * f
                Q = QualityChecks.add(Q, 'check', topic, sprintf(['The CSD used %g %s, but the file gives an ' ...
                    'electrode spacing of %g %s (lfp_spacing_um).'], sp, um, f, um), why, ...
                    'Use the probe''s contact spacing: the file''s value if it is right.');
            elseif ~hasFile && strcmp(o.spacingSource, 'default')
                Q = QualityChecks.add(Q, 'check', topic, sprintf(['The file does not give the electrode spacing; ' ...
                    'the CSD used the default %g %s.'], sp, um), why, sprintf(['Type the probe''s contact spacing ' ...
                    'from its datasheet in Spacing (%s) and compute the CSD again.'], um));
            else
                switch o.spacingSource
                    case 'file',    src = ', from the file (lfp_spacing_um)';
                    case 'typed',   src = ', typed';
                    case 'setting', src = ', from the batch settings';
                    otherwise,      src = '';
                end
                if hasFile && ~strcmp(o.spacingSource, 'file')
                    src = [src ' (the file gives the same)'];
                end
                Q = QualityChecks.add(Q, 'ok', topic, sprintf('Electrode spacing %g %s%s.', sp, um, src));
            end
        end

        %% sinkCheck - The CSD sink in the N1 window: inside the probe or at an edge contact
        function Q = sinkCheck(Q, C, t, o)
            topic = 'CSD sink';
            n = size(C, 1);
            w = o.n1WindowMs;
            in = find(t >= w(1) / 1000 & t <= w(2) / 1000);
            if n < 3 || isempty(in), return; end
            Cw = C(:, in);
            [m, k] = min(Cw(:));
            if ~(m < 0)
                Q = QualityChecks.add(Q, 'check', topic, sprintf(['The CSD has no sink (no negative value) in the ' ...
                    'N1 window (%g-%g ms).'], w(1), w(2)), ['A response normally draws current into the cells of ' ...
                    'the responding layer, a sink.'], ['Check the N1 window, the channel order (top to bottom) and ' ...
                    'that the probe reaches the responding layer.']);
                return;
            end
            [r, c] = ind2sub(size(Cw), k);
            standard = strcmp(o.csdMethod, 'standard');
            if standard
                if r == 1, r = 2; elseif r == n, r = n - 1; end     % the end rows are copies
                edge = r <= 2 || r >= n - 1;
                rule = sprintf('edge: contacts 1-2 and %d-%d for the standard CSD', n - 1, n);
            else
                edge = r == 1 || r == n;
                rule = sprintf('edge: contacts 1 and %d', n);
            end
            where = sprintf('The CSD sink (most negative at %.1f ms) is at contact %d of %d (channel %g)', ...
                1000 * t(in(c)), r, n, o.csdOrder(r));
            if edge
                extra = '';
                act = 'Place the probe so that the responding layer is in the middle of the shank.';
                if standard
                    extra = sprintf([' (the standard CSD cannot compute the end contacts: it copies contacts 2 ' ...
                        'and %d to them)'], n - 1);
                    act = [act ' The iCSD spline or step methods (LFP Analysis, step 4) estimate the CSD up to ' ...
                        'the end contacts.'];
                end
                Q = QualityChecks.add(Q, 'warning', topic, sprintf('%s, at the edge of the probe%s.', where, extra), ...
                    ['The true sink may lie beyond the end of the probe, so its depth and its size are not ' ...
                    'measured.'], act);
            else
                Q = QualityChecks.add(Q, 'ok', topic, sprintf('%s, inside the probe (%s).', where, rule));
            end
        end

        %% completeOptions - Missing settings from checkOptions; odd values to safe ones
        function o = completeOptions(o, n)
            d = ERPAnalysis.checkOptions();
            if ~isstruct(o) || isempty(o), o = d; end
            o = o(1);
            f = fieldnames(d);
            for k = 1:numel(f)
                if ~isfield(o, f{k}), o.(f{k}) = d.(f{k}); end
            end
            o.channels = ERPAnalysis.numeric(o.channels);
            o.channels = o.channels(:)';
            if numel(o.channels) ~= n, o.channels = 1:n; end
            for k = {'nOnsets', 'nEpochs', 'preSec', 'postSec', 'spacingUm', 'spacingFile', 'amplitudeScale'}
                v = ERPAnalysis.numeric(o.(k{1}));
                if numel(v) == 1, o.(k{1}) = v; else, o.(k{1}) = NaN; end
            end
            if ~isfinite(o.amplitudeScale), o.amplitudeScale = 1; o.amplitudeUnit = ''; end
            w = ERPAnalysis.numeric(o.n1WindowMs);
            w = w(:)';
            if numel(w) ~= 2 || ~all(isfinite(w)) || w(2) <= w(1), w = d.n1WindowMs; end
            o.n1WindowMs = w;
            v = ERPAnalysis.numeric(o.computeCSD);
            o.computeCSD = numel(v) == 1 && v ~= 0;
            o.csd = ERPAnalysis.numeric(o.csd);
            if ~ismatrix(o.csd), o.csd = []; end
            o.csdOrder = ERPAnalysis.numeric(o.csdOrder);
            o.csdOrder = o.csdOrder(:)';
            if numel(o.csdOrder) ~= size(o.csd, 1), o.csdOrder = 1:size(o.csd, 1); end
            for k = {'csdMethod', 'spacingSource', 'amplitudeUnit'}
                if ~ischar(o.(k{1})), o.(k{1}) = ''; end
            end
            o.csdMethod = lower(o.csdMethod);
            o.spacingSource = lower(o.spacingSource);
        end

        %% numeric - Numbers as double ([] for anything else)
        function v = numeric(v)
            if isnumeric(v) || islogical(v)
                v = double(v);
            else
                v = [];
            end
        end

        %% amplitude - '+800 uV' with the options' scale and unit
        function s = amplitude(v, o)
            s = strtrim(sprintf('%+.3g %s', o.amplitudeScale * v, o.amplitudeUnit));
        end

        %% channelList - 'channel 4' | 'channels 4, 5 and 3' | 'channels 4, 5, 3, ...' (idx in that order)
        function s = channelList(ids, idx)
            names = arrayfun(@(k) sprintf('%g', ids(k)), idx(:)', 'UniformOutput', false);
            if numel(names) == 1
                s = ['channel ' names{1}];
            elseif numel(names) <= 3
                s = sprintf('channels %s and %s', strjoin(names(1:end-1), ', '), names{end});
            else
                s = sprintf('channels %s, ...', strjoin(names(1:3), ', '));
            end
        end

        function s = upperFirst(s)
            if ~isempty(s), s(1) = upper(s(1)); end
        end
    end
end
