%% ClusterTools.m
% =========================================================================
% CLUSTER TOOLS - COMPARE, MERGE AND SPLIT SPIKE CLUSTERS
% =========================================================================
% Headless helpers to clean up a spike sorting result. Labels are a
% vector with one cluster ID per spike; 0 is noise (unclustered spikes)
% and is never merged, split or renumbered. Waveforms are [nSpikes x
% nSamples], one aligned snippet per spike, in the same order as labels.
%
%   [r, lag, ampRatio] = ClusterTools.similarity(wA, wB, maxLag)
%       Similarity of two mean waveforms: r = highest Pearson correlation
%       over shifts of -maxLag..maxLag samples (normalized cross-
%       correlation on the overlapping part), lag = the shift giving r
%       (samples, positive = wB later than wA), ampRatio = smaller /
%       larger peak-to-peak amplitude (0..1; 1 = same size).
%   [R, L, A, ids] = ClusterTools.similarityMatrix(labels, waveforms, maxLag)
%       The same for every pair of units (IDs > 0); ids lists the units.
%   [labels, log] = ClusterTools.autoMerge(labels, waveforms, opts)
%       Repeatedly merges the most similar pair of units while their r >=
%       opts.threshold (default 0.95) and ampRatio >= opts.minAmpRatio
%       (default 0.85). The lower ID is kept; mean waveforms are recomputed
%       after every merge. opts.maxLag in samples (default 5% of the
%       snippet length, at least 1). log: struct array with fields keep,
%       absorbed, r, lag, ampRatio, nKeep, nAbsorbed (one row per merge).
%   labels = ClusterTools.merge(labels, ids)
%       Manual merge: every unit in ids becomes min(ids). Noise (0) in ids
%       is ignored; fewer than two units left is an error.
%   [labels, newIds] = ClusterTools.split(labels, data, id, k)
%       Manual split of unit id into k (default 2) parts: k-means on the
%       first (up to 3) principal components of data(labels == id, :)
%       (waveforms or features). The largest part keeps id, the others
%       get max(labels)+1, ... (newIds = [id, new IDs]).
%   M = ClusterTools.meanWaveforms(labels, waveforms, ids)
%   labels = ClusterTools.renumber(labels)   units as 1..K (0 stays 0)
%   s = ClusterTools.describeLog(log)        'cluster 3 into 1 (r = 0.99)'
%
% Method: two clusters are treated as one unit that was over-split when
% their mean waveforms have (nearly) the same shape (normalized cross-
% correlation allowing a small misalignment) and a similar size (ratio of
% peak-to-peak amplitudes). The amplitude criterion keeps apart units with
% similar shapes but clearly different sizes (e.g. two cells at different
% distances from the electrode). Split uses Lloyd's k-means with a
% deterministic start (equal-size groups along PC 1), so it gives the same
% answer every time. Base MATLAB only (no toolboxes).
% =========================================================================

classdef ClusterTools
    methods(Static)

        %% similarity - Shape correlation (with lag), lag and amplitude ratio
        function [r, lag, ampRatio] = similarity(wA, wB, maxLag)
            wA = double(wA(:)); wB = double(wB(:));
            n = min(numel(wA), numel(wB));
            wA = wA(1:n); wB = wB(1:n);
            if nargin < 3 || isempty(maxLag), maxLag = ClusterTools.defaultMaxLag(n); end
            maxLag = max(0, min(round(maxLag), n - 3));
            r = -Inf; lag = 0;
            for l = -maxLag:maxLag
                a = wA(1 + max(0, -l) : n - max(0, l));
                b = wB(1 + max(0, l) : n - max(0, -l));
                rl = ClusterTools.pearson(a, b);
                if rl > r, r = rl; lag = l; end
            end
            pA = max(wA) - min(wA);
            pB = max(wB) - min(wB);
            if max(pA, pB) > 0
                ampRatio = min(pA, pB) / max(pA, pB);
            else
                ampRatio = 1;
            end
        end

        %% similarityMatrix - Pairwise similarity of all units (IDs > 0)
        function [R, L, A, ids] = similarityMatrix(labels, waveforms, maxLag)
            if nargin < 3, maxLag = []; end
            labels = labels(:);
            ids = unique(labels(labels > 0))';
            M = ClusterTools.meanWaveforms(labels, waveforms, ids);
            K = numel(ids);
            R = eye(K); L = zeros(K); A = ones(K);
            for i = 1:K
                for j = i + 1:K
                    [r, lg, a] = ClusterTools.similarity(M(i, :), M(j, :), maxLag);
                    R(i, j) = r; R(j, i) = r;
                    L(i, j) = lg; L(j, i) = -lg;
                    A(i, j) = a; A(j, i) = a;
                end
            end
        end

        %% autoMerge - Merge over-split units until no similar pair is left
        function [labels, mergeLog] = autoMerge(labels, waveforms, opts)
            if nargin < 3 || isempty(opts), opts = struct(); end
            if ~isfield(opts, 'threshold') || isempty(opts.threshold), opts.threshold = 0.95; end
            if ~isfield(opts, 'minAmpRatio') || isempty(opts.minAmpRatio), opts.minAmpRatio = 0.85; end
            if ~isfield(opts, 'maxLag'), opts.maxLag = []; end
            ClusterTools.checkInputs(labels, waveforms);
            mergeLog = struct('keep', {}, 'absorbed', {}, 'r', {}, 'lag', {}, ...
                'ampRatio', {}, 'nKeep', {}, 'nAbsorbed', {});
            while true
                [R, L, A, ids] = ClusterTools.similarityMatrix(labels, waveforms, opts.maxLag);
                K = numel(ids);
                if K < 2, break; end
                ok = triu(true(K), 1) & R >= opts.threshold & A >= opts.minAmpRatio;
                if ~any(ok(:)), break; end
                score = R;
                score(~ok) = -Inf;
                [~, best] = max(score(:));
                [i, j] = ind2sub([K K], best);
                keep = min(ids(i), ids(j));
                absorbed = max(ids(i), ids(j));
                entry = struct('keep', keep, 'absorbed', absorbed, 'r', R(i, j), ...
                    'lag', L(i, j), 'ampRatio', A(i, j), 'nKeep', sum(labels == keep), ...
                    'nAbsorbed', sum(labels == absorbed));
                mergeLog(end + 1) = entry; %#ok<AGROW>
                labels(labels == absorbed) = keep;
            end
        end

        %% merge - Manual merge of units ids into min(ids); noise ignored
        function labels = merge(labels, ids)
            ids = unique(ids(:)');
            ids = ids(ids > 0 & ismember(ids, labels(:)'));
            if numel(ids) < 2
                error('NeuroAnalyzer:ClusterTools:merge', ...
                    'Select at least two units to merge (noise cluster 0 cannot be merged).');
            end
            labels(ismember(labels, ids)) = min(ids);
        end

        %% split - Split unit id into k parts (k-means on up to 3 PCs)
        function [labels, newIds] = split(labels, data, id, k)
            if nargin < 4 || isempty(k), k = 2; end
            ClusterTools.checkInputs(labels, data);
            if id <= 0
                error('NeuroAnalyzer:ClusterTools:split', 'Noise cluster 0 cannot be split.');
            end
            members = find(labels(:) == id);
            if numel(members) < 2 * k
                error('NeuroAnalyzer:ClusterTools:split', ...
                    'Cluster %d has %d spikes; at least %d are needed to split it into %d.', ...
                    id, numel(members), 2 * k, k);
            end
            X = double(data(members, :));
            X = X - mean(X, 1);
            % Principal components via SVD (base MATLAB)
            [~, S, V] = svd(X, 'econ');
            nPC = min([3, size(V, 2), rank(S)]);
            if nPC < 1
                error('NeuroAnalyzer:ClusterTools:split', ...
                    'Cluster %d cannot be split: all its spikes are identical.', id);
            end
            score = X * V(:, 1:nPC);
            part = ClusterTools.kmeansLloyd(score, k);
            counts = accumarray(part, 1, [k 1]);
            [~, order] = sort(counts, 'descend');
            order = order(counts(order) > 0);
            if numel(order) < 2
                error('NeuroAnalyzer:ClusterTools:split', ...
                    'Cluster %d could not be split: its spikes form a single group.', id);
            end
            base = max(labels(:));
            newIds = id;
            for m = 2:numel(order)
                nid = base + m - 1;
                labels(members(part == order(m))) = nid;
                newIds(end + 1) = nid; %#ok<AGROW>
            end
        end

        %% meanWaveforms - One mean waveform per ID (rows in ids order)
        function M = meanWaveforms(labels, waveforms, ids)
            labels = labels(:);
            if nargin < 3, ids = unique(labels(labels > 0))'; end
            M = zeros(numel(ids), size(waveforms, 2));
            for i = 1:numel(ids)
                M(i, :) = mean(double(waveforms(labels == ids(i), :)), 1);
            end
        end

        %% renumber - Units as 1..K in order of their current IDs (0 stays 0)
        function labels = renumber(labels)
            pos = labels > 0;
            [~, ~, seq] = unique(labels(pos));
            labels(pos) = seq;
        end

        %% describeLog - One line per merge, e.g. 'cluster 3 into 1 (r = 0.99)'
        function s = describeLog(mergeLog)
            parts = arrayfun(@(e) sprintf('cluster %d into %d (r = %.2f, amplitude ratio %.2f)', ...
                e.absorbed, e.keep, e.r, e.ampRatio), mergeLog, 'UniformOutput', false);
            s = strjoin(parts, '; ');
        end
    end

    methods(Static, Access = private)

        %% defaultMaxLag - 5% of the snippet length, at least 1 sample
        function m = defaultMaxLag(n)
            m = max(1, round(0.05 * n));
        end

        %% pearson - Correlation of two vectors (NaN-safe: flat -> 0)
        function r = pearson(a, b)
            a = a - mean(a); b = b - mean(b);
            d = sqrt(sum(a .^ 2) * sum(b .^ 2));
            if d > 0
                r = sum(a .* b) / d;
            else
                r = 0;
            end
        end

        %% checkInputs - labels and data rows must match
        function checkInputs(labels, data)
            if numel(labels) ~= size(data, 1)
                error('NeuroAnalyzer:ClusterTools:size', ...
                    'labels has %d elements but the waveform/feature matrix has %d rows.', ...
                    numel(labels), size(data, 1));
            end
        end

        %% kmeansLloyd - Deterministic k-means (equal groups along column 1)
        function part = kmeansLloyd(X, k)
            n = size(X, 1);
            [~, ord] = sort(X(:, 1));
            part = zeros(n, 1);
            edges = round(linspace(0, n, k + 1));
            for m = 1:k
                part(ord(edges(m) + 1:edges(m + 1))) = m;
            end
            for it = 1:200
                C = zeros(k, size(X, 2));
                empty = false(k, 1);
                for m = 1:k
                    empty(m) = ~any(part == m);
                    if ~empty(m), C(m, :) = mean(X(part == m, :), 1); end
                end
                if any(empty)
                    % Empty group: restart it on the point farthest from its centre
                    d0 = sum((X - C(part, :)) .^ 2, 2);
                    [~, far] = sort(d0, 'descend');
                    C(empty, :) = X(far(1:sum(empty)), :);
                end
                D = zeros(n, k);
                for m = 1:k
                    D(:, m) = sum((X - C(m, :)) .^ 2, 2);
                end
                [~, newPart] = min(D, [], 2);
                if isequal(newPart, part), break; end
                part = newPart;
            end
        end
    end
end
