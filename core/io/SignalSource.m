%% SignalSource.m
% =========================================================================
% SIGNAL SOURCE - PHYSIOLOGY RECORDINGS FROM THE COMMON ACQUISITION SYSTEMS
% =========================================================================
% Laser Doppler monitors (Perimed PeriFlux, Moor moorVMS-LDF, Oxford
% Optronix OxyFlo, ADInstruments Blood FlowMeter, BIOPAC LDF100C,
% Transonic BLF22) are usually recorded, next to the stimulus trigger, by a
% general data acquisition system. This class reads their files into one
% structure, so Extract LDF (and scripts) can pick the flow channel and the
% stimulus from any of them:
%
%   ADInstruments LabChart  MATLAB export .mat (data, datastart, dataend,
%                           samplerate, titles, unittext / unittextmap,
%                           com / comtext, tickrate, blocktimes; several
%                           blocks) and text export (Interval=,
%                           ChannelTitle=, Range= ... then time + columns)
%   BIOPAC AcqKnowledge     native .acq (readBiopacACQ), MATLAB export .mat
%                           (data, labels, units, isi, isi_units) and text
%                           export
%   CED Spike2              MATLAB export .mat (one struct per channel:
%                           title, interval, values / times, start, codes)
%   EDF / EDF+ / BDF        via readEDF when it is on the path (LabChart,
%                           clinical and many other systems export EDF)
%   Any delimited text      .txt / .csv / .tsv with a header row (PeriSoft,
%                           moorVMS-PC and spreadsheet exports; readSignalText)
%   Cropped LDF .mat        stim, LDF, t, Fs (as Extract LDF saves it)
%
%   list = SignalSource.formats()     key, label, extensions (for dialogs, Help)
%   fmt  = SignalSource.detect(path)  one of the keys
%   rec  = SignalSource.open(path)    read with the matching reader
%   rec  = SignalSource.open(path, '', struct('Fs', 40))   rate of a text
%          file without a time column (readSignalText options)
%   rec  = SignalSource.fromStruct(d, file)   a loaded .mat struct
%   [iFlow, iStim] = SignalSource.guessChannels(rec)
%          channel numbers of the flow signal and the stimulus, from the
%          names (LDF, flux, perfusion, BPU / PU units; stim, trigger, TTL,
%          pulse); a LabChart file with 8 or more unnamed channels keeps the
%          old convention (stimulus 6, LDF 8); iStim = 0 when none is found
%   L = SignalSource.toLDF(rec, iFlow, stim, block)
%          the chosen flow channel and stimulus on one time base: L.LDF,
%          L.stim, L.t (s), L.Fs (the flow channel's rate), L.flowName,
%          L.flowUnits, L.stimName, L.onsets (s, when the stimulus is made
%          from comments / markers). stim: a channel number, 0 = none, or
%          'events' (every comment / marker) or 'events:<text>' (the
%          comments with that text), which become 0.5 s pulses of height 1.
%          A faster stimulus channel is reduced to the flow rate by taking
%          the maximum of each flow sample's interval (pulses are kept); a
%          slower one is held.
%   c = SignalSource.channelItems(rec)   dropdown labels, e.g.
%          '8: LDF (PU, 1000 Hz)'
%   c = SignalSource.stimItems(rec)      stimulus choices: channels, then
%          'Comments / markers (n)' and one item per comment text, then
%          'None'; with the matching values (numbers or 'events...')
%
% rec (every format):
%   channels  struct array: chan (channel number), block, name, units, fs
%             (Hz), data (1 x n double), t0 (s from the block start)
%   events    struct array: time (s from the block start), block, channel
%             (0 = all), type ('comment' | 'marker' | 'event'), text
%   nChannels, nBlocks, names (1 x nChannels), units (1 x nChannels)
%   info      format (key), label, file, notes (cellstr), blockStart
%             (cellstr, ISO date-time of each block when known)
%
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:unknownFormat,
% NeuroAnalyzer:io:noChannels. Base MATLAB only.
% =========================================================================

classdef SignalSource
    properties(Constant)
        EventPulseSec = 0.5          % stimulus pulse made from each comment / marker
    end

    methods(Static)

        %% formats - Supported files, for dialogs and Help
        function list = formats()
            list = struct( ...
                'key', {'labchart', 'acq', 'acqmat', 'spike2', 'edf', 'text', 'ldfcropped'}, ...
                'label', {'LabChart .mat export (ADInstruments)', 'AcqKnowledge .acq (BIOPAC)', ...
                    'AcqKnowledge .mat export (BIOPAC)', 'Spike2 .mat export (CED)', 'EDF / EDF+ / BDF', ...
                    'Text export (LabChart, AcqKnowledge, PeriSoft, moorVMS, CSV)', 'Cropped LDF .mat (stim, LDF, t, Fs)'}, ...
                'ext', {'.mat', '.acq', '.mat', '.mat', '.edf;.bdf', '.txt;.csv;.tsv;.dat', '.mat'});
        end

        %% label - Text of a format key
        function s = label(fmt)
            list = SignalSource.formats();
            k = find(strcmp({list.key}, fmt), 1);
            if isempty(k), s = fmt; else, s = list(k).label; end
        end

        %% detect - Format key of a file (from its extension, and its variables for .mat)
        function fmt = detect(p)
            if exist(p, 'file') ~= 2
                error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
            end
            [~, ~, ext] = fileparts(p);
            switch lower(ext)
                case '.acq',                         fmt = 'acq';
                case {'.edf', '.bdf', '.rec'},       fmt = 'edf';
                case {'.txt', '.csv', '.tsv', '.dat', '.asc'}, fmt = 'text';
                case '.mat'
                    v = who('-file', p);
                    fmt = SignalSource.matKind(v, []);
                otherwise
                    error('NeuroAnalyzer:io:unknownFormat', ['Cannot tell what kind of recording %s is. ' ...
                        'Supported: LabChart .mat or text export, AcqKnowledge .acq / .mat / text, Spike2 .mat ' ...
                        'export, EDF / BDF, delimited text (.txt, .csv).'], p);
            end
        end

        %% open - Read a recording (any supported format)
        function rec = open(p, fmt, opts)
            if nargin < 2 || isempty(fmt), fmt = SignalSource.detect(p); end
            if nargin < 3, opts = struct(); end
            switch fmt
                case 'acq'
                    rec = SignalSource.fromAcq(readBiopacACQ(p), p);
                case 'edf'
                    if exist('readEDF', 'file') ~= 2
                        error('NeuroAnalyzer:io:unknownFormat', ['Reading EDF / BDF files needs readEDF ' ...
                            '(core/io); update Neuronal Data Analyzer Lab.']);
                    end
                    rec = SignalSource.fromEDF(readEDF(p), p);
                case 'text'
                    rec = readSignalText(p, opts);
                otherwise
                    rec = SignalSource.fromStruct(load(p), p);
            end
            rec = SignalSource.finish(rec);
        end

        %% fromStruct - A loaded .mat file (LabChart, AcqKnowledge, Spike2 export or cropped LDF)
        function rec = fromStruct(d, p)
            if nargin < 2, p = ''; end
            kind = SignalSource.matKind(fieldnames(d), d);
            switch kind
                case 'labchart',   rec = SignalSource.fromLabChart(d, p);
                case 'acqmat',     rec = SignalSource.fromAcqMat(d, p);
                case 'spike2',     rec = SignalSource.fromSpike2(d, p);
                case 'ldfcropped', rec = SignalSource.fromCropped(d, p);
                otherwise
                    error('NeuroAnalyzer:io:unknownFormat', ['%s is not a recording this window knows: ' ...
                        'expected a LabChart export (data, datastart, dataend), an AcqKnowledge export (data, ' ...
                        'isi, labels), a Spike2 export (channel structs with values and interval) or a cropped ' ...
                        'LDF file (stim, LDF, t, Fs).'], SignalSource.nameOf(p));
            end
            rec = SignalSource.finish(rec);
        end

        %% guessChannels - Flow and stimulus channel numbers from the names (see the header)
        function [iFlow, iStim] = guessChannels(rec)
            names = lower(rec.names);
            units = lower(rec.units);
            n = rec.nChannels;
            % Strong: LDF names or perfusion units; weak: 'flow', 'blood', 'CBF' (not a pressure)
            strong = ~cellfun(@isempty, regexp(names, 'ldf|doppler|flux|perfusion', 'once')) | ...
                ~cellfun(@isempty, regexp(units, '^(b|t)?pu$|perfusion|flux', 'once'));
            weak = ~cellfun(@isempty, regexp(names, 'flow|blood|cbf', 'once')) & ...
                cellfun(@isempty, regexp(names, 'press|mmhg|(^|\W)bp(\W|$)', 'once')) & ...
                cellfun(@isempty, regexp(units, 'mmhg|kpa', 'once'));
            isFlow = strong | weak;
            isStim = ~cellfun(@isempty, regexp(names, 'stim|trig|ttl|pulse|whisk|shock|sync|marker|light|tone', 'once'));
            isStim = isStim & ~isFlow;
            iFlow = find(strong, 1);
            if isempty(iFlow), iFlow = find(weak, 1); end
            iStim = find(isStim, 1);
            if isempty(iFlow) && strcmp(rec.info.format, 'labchart') && n >= 8
                iFlow = 8;                             % the long-standing LabChart convention
                if isempty(iStim), iStim = 6; end
            end
            if isempty(iStim), iStim = SignalSource.ttlChannel(rec, iFlow); end
            if isempty(iFlow)
                others = setdiff(1:n, iStim);
                if isempty(others), iFlow = 1; else, iFlow = others(1); end
            end
            if isempty(iStim), iStim = 0; end
        end

        %% toLDF - Flow channel and stimulus on the flow channel's time base
        function L = toLDF(rec, iFlow, stim, block)
            if nargin < 4 || isempty(block), block = 1; end
            f = SignalSource.channel(rec, iFlow, block);
            if isempty(f)
                error('NeuroAnalyzer:io:noChannels', 'Channel %d has no data in block %d.', iFlow, block);
            end
            n = numel(f.data);
            L.Fs = f.fs;
            L.t = (0:n-1) / f.fs;
            L.LDF = f.data;
            L.flowName = f.name;
            L.flowUnits = f.units;
            L.onsets = [];
            if ischar(stim) || isstring(stim)
                stim = char(stim);
                ev = rec.events([rec.events.block] == block);
                if strncmp(stim, 'events:', 7)
                    ev = ev(strcmp({ev.text}, stim(8:end)));
                    L.stimName = sprintf('Comments "%s"', stim(8:end));
                else
                    L.stimName = 'Comments / markers';
                end
                on = sort([ev.time]);
                L.onsets = on;
                x = zeros(1, n);
                w = max(1, round(SignalSource.EventPulseSec * f.fs));
                for k = 1:numel(on)
                    i1 = round((on(k) - f.t0) * f.fs) + 1;
                    if i1 >= 1 && i1 <= n, x(i1:min(n, i1 + w - 1)) = 1; end
                end
                L.stim = x;
            elseif isempty(stim) || stim == 0
                L.stim = zeros(1, n);
                L.stimName = '(none)';
            else
                s = SignalSource.channel(rec, stim, block);
                if isempty(s)
                    error('NeuroAnalyzer:io:noChannels', 'Stimulus channel %d has no data in block %d.', stim, block);
                end
                L.stim = SignalSource.resampleTrigger(s.data, s.fs, f.fs, n);
                L.stimName = s.name;
            end
        end

        %% channelItems - '8: LDF (PU, 1000 Hz)' for every channel number
        function c = channelItems(rec)
            c = cell(1, rec.nChannels);
            for k = 1:rec.nChannels
                i = find([rec.channels.chan] == k, 1);
                if isempty(i)
                    c{k} = sprintf('%d: %s (empty)', k, rec.names{k});
                    continue;
                end
                parts = {};
                if ~isempty(rec.units{k}), parts{end+1} = rec.units{k}; end %#ok<AGROW>
                parts{end+1} = sprintf('%g Hz', rec.channels(i).fs); %#ok<AGROW>
                c{k} = sprintf('%d: %s (%s)', k, rec.names{k}, strjoin(parts, ', '));
            end
        end

        %% stimItems - Stimulus choices (labels) and their values
        function [items, values] = stimItems(rec)
            items = SignalSource.channelItems(rec);
            values = num2cell(1:rec.nChannels);
            if ~isempty(rec.events)
                items{end+1} = sprintf('Comments / markers (%d)', numel(rec.events));
                values{end+1} = 'events';
                txt = {rec.events.text};
                u = unique(txt(~cellfun(@isempty, txt)), 'stable');
                if numel(u) > 1 && numel(u) <= 12
                    for k = 1:numel(u)
                        items{end+1} = sprintf('Comments "%s" (%d)', u{k}, sum(strcmp(txt, u{k}))); %#ok<AGROW>
                        values{end+1} = ['events:' u{k}]; %#ok<AGROW>
                    end
                end
            end
            items{end+1} = 'None';
            values{end+1} = 0;
        end

        %% channel - The channel record of channel number chan in block b ([] if none)
        function c = channel(rec, chan, b)
            k = find([rec.channels.chan] == chan & [rec.channels.block] == b, 1);
            if isempty(k), c = []; else, c = rec.channels(k); end
        end
    end

    methods(Static, Hidden)

        %% matKind - Which .mat export a variable list is
        function kind = matKind(v, d)
            v = cellstr(v);
            if all(ismember({'data', 'datastart', 'dataend'}, v))
                kind = 'labchart';
            elseif all(ismember({'stim', 'LDF', 't', 'Fs'}, v))
                kind = 'ldfcropped';
            elseif all(ismember({'data', 'isi'}, v))
                kind = 'acqmat';
            else
                kind = '';
                if isempty(d)
                    kind = 'mat';                              % decided when loaded
                    return;
                end
                for k = 1:numel(v)
                    x = d.(v{k});
                    if isstruct(x) && isscalar(x) && isfield(x, 'title') && ...
                            (isfield(x, 'values') || isfield(x, 'times'))
                        kind = 'spike2'; return;
                    end
                end
            end
        end

        %% fromLabChart - LabChart MATLAB export, every block and channel, comments as events
        function rec = fromLabChart(d, p)
            % datastart / dataend / samplerate are channels x blocks; a vector
            % is one block of several channels, unless the file has one title
            ds = double(d.datastart); de = double(d.dataend);
            nTitles = numel(SignalSource.rows(SignalSource.field(d, 'titles', ''), 0, ''));
            if isvector(ds)
                if nTitles == 1 && numel(ds) > 1
                    ds = ds(:)'; de = de(:)';
                else
                    ds = ds(:); de = de(:);
                end
            end
            nCh = size(ds, 1); nB = size(ds, 2);
            titles = SignalSource.rows(SignalSource.field(d, 'titles', ''), nCh, 'Channel %d');
            fsAll = double(SignalSource.field(d, 'samplerate', []));
            noRate = isempty(fsAll);
            if noRate
                fsAll = 1000 * ones(nCh, nB);
            elseif isvector(fsAll)
                if nCh == 1, fsAll = fsAll(:)'; else, fsAll = fsAll(:); end
            end
            unitText = SignalSource.rows(SignalSource.field(d, 'unittext', ''), 0, '');
            map = double(SignalSource.field(d, 'unittextmap', []));
            if isvector(map) && nB == 1, map = map(:); end
            fso = double(SignalSource.field(d, 'firstsampleoffset', zeros(nCh, nB)));
            ch = SignalSource.emptyChannels();
            units = repmat({''}, 1, nCh);
            for b = 1:nB
                for c = 1:nCh
                    if ds(c, b) < 1 || de(c, b) < ds(c, b), continue; end
                    if ~isempty(map) && all(size(map) >= [c b]) && map(c, b) < 1, continue; end
                    u = '';
                    if ~isempty(map) && all(size(map) >= [c b]) && map(c, b) <= numel(unitText)
                        u = unitText{map(c, b)};
                    elseif isempty(map) && numel(unitText) >= c && numel(unitText) == nCh
                        u = unitText{c};
                    end
                    if isempty(units{c}), units{c} = u; end
                    fs = fsAll(min(c, size(fsAll, 1)), min(b, size(fsAll, 2)));
                    t0 = 0;
                    if all(size(fso) >= [c b]), t0 = -fso(c, b) / fs; end
                    ch(end+1) = struct('chan', c, 'block', b, 'name', titles{c}, 'units', u, 'fs', fs, ...
                        'data', double(d.data(ds(c, b):de(c, b))), 't0', t0); %#ok<AGROW>
                end
            end
            % Comments: channel (-1 = all), block, position in ticks, type (1 user, 2 event marker), text index
            ev = SignalSource.emptyEvents();
            com = SignalSource.field(d, 'com', []);
            if ~isempty(com) && size(com, 2) >= 5
                ctext = SignalSource.rows(SignalSource.field(d, 'comtext', ''), 0, '');
                tick = SignalSource.field(d, 'tickrate', []);
                for k = 1:size(com, 1)
                    b = com(k, 2);
                    if isempty(tick)
                        tr = max(fsAll(:, min(b, end)));
                    else
                        tr = tick(min(b, numel(tick)));
                    end
                    txt = '';
                    if com(k, 5) >= 1 && com(k, 5) <= numel(ctext), txt = ctext{com(k, 5)}; end
                    typ = 'comment';
                    if com(k, 4) == 2, typ = 'marker'; end
                    ev(end+1) = struct('time', com(k, 3) / tr, 'block', b, 'channel', max(0, com(k, 1)), ...
                        'type', typ, 'text', txt); %#ok<AGROW>
                end
            end
            rec = SignalSource.makeRec(ch, ev, titles, units, 'labchart', p);
            rec.nBlocks = nB;
            bt = SignalSource.field(d, 'blocktimes', []);
            rec.info.blockStart = repmat({''}, 1, nB);
            for b = 1:min(nB, numel(bt))
                if bt(b) > 0, rec.info.blockStart{b} = datestr(bt(b), 'yyyy-mm-ddTHH:MM:SS.FFF'); end
            end
            if nB > 1
                rec.info.notes{end+1} = sprintf('%d blocks (recording periods): choose one.', nB);
            end
            if noRate
                rec.info.notes{end+1} = 'The file has no sampling rate (samplerate): 1000 Hz assumed.';
            end
            rec.info.rateAssumed = noRate;
        end

        %% fromAcq - readBiopacACQ struct
        function rec = fromAcq(a, p)
            ch = SignalSource.emptyChannels();
            for k = 1:numel(a.channels)
                c = a.channels(k);
                ch(end+1) = struct('chan', k, 'block', 1, 'name', c.name, 'units', c.units, 'fs', c.fs, ...
                    'data', c.data, 't0', 0); %#ok<AGROW>
            end
            ev = SignalSource.emptyEvents();
            for k = 1:numel(a.events)
                e = a.events(k);
                ev(end+1) = struct('time', e.time, 'block', 1, 'channel', e.channel, 'type', 'marker', ...
                    'text', e.text); %#ok<AGROW>
            end
            rec = SignalSource.makeRec(ch, ev, {a.channels.name}, {a.channels.units}, 'acq', p);
            rec.info.notes = [rec.info.notes, a.info.notes];
        end

        %% fromAcqMat - AcqKnowledge "Save As .mat": data (samples x channels), labels, units, isi, isi_units
        function rec = fromAcqMat(d, p)
            data = double(d.data);
            if size(data, 1) < size(data, 2) && isfield(d, 'labels') && size(data, 1) == size(d.labels, 1)
                data = data';
            end
            nCh = size(data, 2);
            isi = double(d.isi);
            u = lower(strtrim(char(SignalSource.field(d, 'isi_units', 'ms'))));
            switch u
                case {'s', 'sec', 'seconds'}, fs = 1 / isi;
                case {'us', 'µs', 'microseconds'}, fs = 1e6 / isi;
                otherwise, fs = 1000 / isi;                   % ms (AcqKnowledge's default)
            end
            names = SignalSource.rows(SignalSource.field(d, 'labels', ''), nCh, 'Channel %d');
            units = SignalSource.rows(SignalSource.field(d, 'units', ''), nCh, '');
            ch = SignalSource.emptyChannels();
            for k = 1:nCh
                ch(end+1) = struct('chan', k, 'block', 1, 'name', names{k}, 'units', units{k}, 'fs', fs, ...
                    'data', data(:, k)', 't0', 0); %#ok<AGROW>
            end
            rec = SignalSource.makeRec(ch, SignalSource.emptyEvents(), names, units, 'acqmat', p);
            rec.info.notes{end+1} = 'AcqKnowledge .mat exports do not contain the event markers.';
        end

        %% fromSpike2 - Spike2 "Export As > MATLAB": one struct per channel
        function rec = fromSpike2(d, p)
            f = fieldnames(d);
            ch = SignalSource.emptyChannels();
            ev = SignalSource.emptyEvents();
            names = {}; units = {};
            for k = 1:numel(f)
                x = d.(f{k});
                if ~(isstruct(x) && isscalar(x) && isfield(x, 'title')), continue; end
                nm = strtrim(char(x.title));
                if isfield(x, 'values') && isfield(x, 'interval') && numel(x.values) > 1
                    t0 = 0;
                    if isfield(x, 'start'), t0 = double(x.start);
                    elseif isfield(x, 'times') && ~isempty(x.times), t0 = double(x.times(1)); end
                    u = '';
                    if isfield(x, 'units'), u = strtrim(char(x.units)); end
                    names{end+1} = nm; units{end+1} = u; %#ok<AGROW>
                    ch(end+1) = struct('chan', numel(names), 'block', 1, 'name', nm, 'units', u, ...
                        'fs', 1 / double(x.interval), 'data', double(x.values(:))', 't0', t0); %#ok<AGROW>
                elseif isfield(x, 'times')
                    tt = double(x.times(:))';
                    for j = 1:numel(tt)
                        txt = nm;
                        if isfield(x, 'codes') && size(x.codes, 1) >= j
                            txt = sprintf('%s %d', nm, x.codes(j, 1));
                        end
                        ev(end+1) = struct('time', tt(j), 'block', 1, 'channel', 0, 'type', 'event', ...
                            'text', txt); %#ok<AGROW>
                    end
                end
            end
            rec = SignalSource.makeRec(ch, ev, names, units, 'spike2', p);
            % Waveforms can start at different times: event times are made relative to the flow channel later
        end

        %% fromEDF - readEDF struct (signals with physical units, annotations)
        function rec = fromEDF(E, p)
            ch = SignalSource.emptyChannels();
            for k = 1:numel(E.signals)
                s = E.signals(k);
                ch(end+1) = struct('chan', k, 'block', 1, 'name', strtrim(s.label), 'units', strtrim(s.units), ...
                    'fs', s.fs, 'data', double(s.data(:))', 't0', 0); %#ok<AGROW>
            end
            ev = SignalSource.emptyEvents();
            if isfield(E, 'annotations')
                for k = 1:numel(E.annotations)
                    a = E.annotations(k);
                    ev(end+1) = struct('time', a.onset, 'block', 1, 'channel', 0, 'type', 'event', ...
                        'text', a.text); %#ok<AGROW>
                end
            end
            rec = SignalSource.makeRec(ch, ev, {ch.name}, {ch.units}, 'edf', p);
        end

        %% fromCropped - stim, LDF, t, Fs (Extract LDF's own output)
        function rec = fromCropped(d, p)
            fs = double(d.Fs);
            t0 = 0;
            if ~isempty(d.t), t0 = double(d.t(1)); end
            ch = struct('chan', {1, 2}, 'block', 1, 'name', {'Stimulus', 'LDF'}, 'units', {'', ''}, ...
                'fs', fs, 'data', {double(d.stim(:))', double(d.LDF(:))'}, 't0', t0);
            rec = SignalSource.makeRec(ch, SignalSource.emptyEvents(), {'Stimulus', 'LDF'}, {'', ''}, 'ldfcropped', p);
        end

        function rec = makeRec(ch, ev, names, units, fmt, p)
            rec.channels = ch;
            rec.events = ev;
            rec.nChannels = max([numel(names), ch.chan]);
            rec.nBlocks = max([1, ch.block]);
            names = cellstr(names); units = cellstr(units);
            names(end+1:rec.nChannels) = {''};
            units(end+1:rec.nChannels) = {''};
            for k = 1:rec.nChannels
                if isempty(names{k}), names{k} = sprintf('Channel %d', k); end
            end
            rec.names = names(1:rec.nChannels);
            rec.units = units(1:rec.nChannels);
            rec.info = struct('format', fmt, 'label', SignalSource.label(fmt), 'file', p, ...
                'notes', {{}}, 'blockStart', {{}}, 'rateAssumed', false);
        end

        %% finish - Checks common to every format
        function rec = finish(rec)
            if isempty(rec.channels)
                error('NeuroAnalyzer:io:noChannels', '%s has no signal channels with data.', ...
                    SignalSource.nameOf(rec.info.file));
            end
            if isempty(rec.info.blockStart), rec.info.blockStart = repmat({''}, 1, rec.nBlocks); end
            rates = unique([rec.channels.fs]);
            if numel(rates) > 1
                rec.info.notes{end+1} = sprintf(['Channels have different rates (%s Hz): the stimulus is put ' ...
                    'on the flow channel''s time base.'], strjoin(arrayfun(@(x) sprintf('%g', x), rates, ...
                    'UniformOutput', false), ', '));
            end
        end

        %% ttlChannel - A channel that looks like a trigger: two levels, mostly at the low one
        function k = ttlChannel(rec, iFlow)
            k = [];
            for c = 1:rec.nChannels
                if ~isempty(iFlow) && c == iFlow, continue; end
                i = find([rec.channels.chan] == c, 1);
                if isempty(i), continue; end
                x = rec.channels(i).data;
                if numel(x) < 10, continue; end
                lo = min(x); hi = max(x);
                if hi - lo <= 0, continue; end
                y = (x - lo) / (hi - lo);
                if mean(y < 0.1 | y > 0.9) > 0.98 && mean(y > 0.5) < 0.5
                    k = c; return;
                end
            end
        end

        %% resampleTrigger - Stimulus at rate fsS onto n samples at rate fsF
        function y = resampleTrigger(x, fsS, fsF, n)
            x = double(x(:))';
            if abs(fsS - fsF) < 1e-9 * fsF
                y = x(1:min(end, n));
                y(end+1:n) = 0;
                return;
            end
            ti = (0:n-1) / fsF;                           % flow sample times
            if fsS > fsF
                % Maximum of the stimulus samples inside each flow sample's interval
                idx = floor((0:numel(x)-1) / fsS * fsF) + 1;
                keep = idx <= n;
                y = accumarray(idx(keep)', x(keep)', [n 1], @max, -Inf)';
                empty = ~isfinite(y);
                if any(empty)
                    j = min(numel(x), max(1, round(ti(empty) * fsS) + 1));
                    y(empty) = x(j);
                end
            else
                j = min(numel(x), floor(ti * fsS) + 1);       % hold the last stimulus sample
                y = x(j);
            end
        end

        function c = rows(v, n, fmt)
            if iscell(v)
                c = cellfun(@(s) strtrim(char(s)), v(:)', 'UniformOutput', false);
            elseif ischar(v) && ~isempty(v)
                c = cellstr(v)';
                c = cellfun(@strtrim, c, 'UniformOutput', false);
            elseif isstring(v)
                c = cellstr(v(:))';
            else
                c = {};
            end
            if n > 0
                c(end+1:n) = {''};
                c = c(1:n);
                for k = 1:n
                    if isempty(c{k}) && ~isempty(fmt), c{k} = sprintf(fmt, k); end
                end
            end
        end

        function v = field(d, name, default)
            if isfield(d, name) && ~isempty(d.(name)), v = d.(name); else, v = default; end
        end

        function c = emptyChannels()
            c = struct('chan', {}, 'block', {}, 'name', {}, 'units', {}, 'fs', {}, 'data', {}, 't0', {});
        end

        function e = emptyEvents()
            e = struct('time', {}, 'block', {}, 'channel', {}, 'type', {}, 'text', {});
        end

        function n = nameOf(p)
            if isempty(p), n = 'The data'; return; end
            [~, a, b] = fileparts(p);
            n = [a b];
        end
    end
end
