function writeSpikeGLX(binFile, data, kind, varargin)
% writeSpikeGLX - Write a synthetic SpikeGLX .bin + .meta pair (for tests and demos).
%
% writeSpikeGLX(binFile, data, kind, Name, Value, ...)
%
% data   channels x samples int16, every saved channel (imec: AP or LF
%        channels then the sync word; nidq: MN, MA, XA, DW in that order)
% kind   'imec1' (Neuropixels 1.0: gains in ~imroTbl), 'imec2'
%        (Neuropixels 2.0: fixed gain) or 'nidq'
% Options: 'Fs' (default 30000 imec, 25000 nidq), 'Gain' (imec1 AP gain,
%        default 500; LF gain 250), 'Counts' (nidq [MN MA XA DW], default
%        [0 0 size(data,1) 0]), 'MNGain' (200), 'MAGain' (1),
%        'RangeMax' (imec 0.6 / 0.5, nidq 5)
% Writes the keys readSpikeGLX (and other readers) use; not a replacement
% for SpikeGLX. Base MATLAB only; also runs in GNU Octave.
%
o = struct('Fs', [], 'Gain', 500, 'Counts', [], 'MNGain', 200, 'MAGain', 1, 'RangeMax', []);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
data = int16(data);
[nCh, n] = size(data);
[folder, base] = fileparts(binFile);
fid = fopen(binFile, 'w', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:spikeglx', 'Cannot write %s', binFile); end
fwrite(fid, data, 'int16');
fclose(fid);
L = {};
L{end+1} = sprintf('nSavedChans=%d', nCh);
L{end+1} = sprintf('fileSizeBytes=%d', 2 * nCh * n);
L{end+1} = sprintf('fileName=%s', strrep(binFile, '\', '/'));
L{end+1} = 'typeThis=imec';
switch kind
    case {'imec1', 'imec2'}
        fs = pick(o.Fs, 30000);
        nNeural = nCh - 1;
        L{end+1} = sprintf('imSampRate=%.10g', fs);
        L{end+1} = sprintf('fileTimeSecs=%.10g', n / fs);
        L{end+1} = sprintf('snsApLfSy=%d,0,1', nNeural);
        L{end+1} = sprintf('snsSaveChanSubset=0:%d', nCh - 1);
        if strcmp(kind, 'imec1')
            L{end+1} = sprintf('imAiRangeMax=%g', pick(o.RangeMax, 0.6));
            L{end+1} = 'imAiRangeMin=-0.6';
            L{end+1} = 'imMaxInt=512';
            L{end+1} = 'imDatPrb_pn=NP1000';
            L{end+1} = 'imDatPrb_type=0';
            t = sprintf('(0,%d)', nNeural);
            for c = 0:nNeural-1, t = [t sprintf('(%d 0 0 %g 250 1)', c, o.Gain)]; end %#ok<AGROW>
        else
            L{end+1} = sprintf('imAiRangeMax=%g', pick(o.RangeMax, 0.5));
            L{end+1} = 'imAiRangeMin=-0.5';
            L{end+1} = 'imMaxInt=8192';
            L{end+1} = 'imChan0apGain=80';
            L{end+1} = 'imDatPrb_pn=NP2000';
            L{end+1} = 'imDatPrb_type=21';
            t = sprintf('(21,%d)', nNeural);
            for c = 0:nNeural-1, t = [t sprintf('(%d 1 0 %d)', c, c)]; end %#ok<AGROW>
        end
        L{end+1} = ['~imroTbl=' t];
        m = sprintf('(%d,0,1)', nNeural);
        for c = 0:nNeural-1, m = [m sprintf('(AP%d;%d:%d)', c, c, c)]; end %#ok<AGROW>
        L{end+1} = ['~snsChanMap=' m sprintf('(SY0;%d:%d)', nNeural, nNeural)];
    case 'nidq'
        L{4} = 'typeThis=nidq';
        fs = pick(o.Fs, 25000);
        cnt = pick(o.Counts, [0 0 nCh 0]);
        L{end+1} = sprintf('niSampRate=%.10g', fs);
        L{end+1} = sprintf('fileTimeSecs=%.10g', n / fs);
        L{end+1} = sprintf('snsMnMaXaDw=%d,%d,%d,%d', cnt);
        L{end+1} = sprintf('snsSaveChanSubset=0:%d', nCh - 1);
        L{end+1} = sprintf('niAiRangeMax=%g', pick(o.RangeMax, 5));
        L{end+1} = sprintf('niAiRangeMin=-%g', pick(o.RangeMax, 5));
        L{end+1} = sprintf('niMNGain=%g', o.MNGain);
        L{end+1} = sprintf('niMAGain=%g', o.MAGain);
        L{end+1} = 'niMaxInt=32768';
        m = sprintf('(%d,%d,%d,%d)', cnt);
        pre = {'MN', 'MA', 'XA', 'XD'};
        c = 0;
        for g = 1:4
            for j = 0:cnt(g)-1, m = [m sprintf('(%s%d;%d:%d)', pre{g}, j, c, c)]; c = c + 1; end %#ok<AGROW>
        end
        L{end+1} = ['~snsChanMap=' m];
    otherwise
        error('NeuroAnalyzer:io:spikeglx', 'kind must be imec1, imec2 or nidq.');
end
fid = fopen(fullfile(folder, [base '.meta']), 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function v = pick(v, default)
if isempty(v), v = default; end
end
