function out = writeImagingFormat(kind, target, stack, varargin)
% writeImagingFormat - Write a synthetic image stack as a microscope program saves it (for tests and demos).
%
% out = writeImagingFormat(kind, target, stack, Name, Value, ...)
%
% kind    'isxd'       Inscopix movie file (target: .isxd path)
%         'thorimage'  ThorImageLS folder: Experiment.xml + Image_0001_0001.raw
%         'prairie'    Bruker Prairie View T-series folder: PVScan .xml and
%                      one TIFF per frame and channel
% stack   H x W x N (one channel) or H x W x C x N (several channels);
%         uint16 (isxd also single / uint8)
% Options: 'Fps' (default 10), 'PixelSizeUm' (default 1), 'ChannelNames'
%          (cellstr), 'Times' (s, one per frame; Prairie View)
% Output out: the file or folder written. Layouts as readImagingFolder
% reads them; fields the reader does not use are left out. Not a
% replacement for the vendors' software. Base MATLAB (jsonencode, imwrite);
% also runs in GNU Octave.
%
o = struct('Fps', 10, 'PixelSizeUm', 1, 'ChannelNames', {{}}, 'Times', []);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
if ndims(stack) == 4
    [H, W, C, N] = size(stack);
else
    [H, W, N] = size(stack);
    C = 1;
    stack = reshape(stack, H, W, 1, N);
end
names = o.ChannelNames;
for c = numel(names)+1:C, names{c} = sprintf('Chan%c', 'A' + c - 1); end
switch kind
    case 'isxd'
        cls = class(stack);
        codes = struct('uint16', 0, 'single', 1, 'uint8', 2);
        if ~isfield(codes, cls), stack = uint16(stack); cls = 'uint16'; end
        prec = cls; if strcmp(cls, 'single'), prec = 'float32'; end
        fid = fopen(target, 'w', 'ieee-le');
        if fid < 0, error('NeuroAnalyzer:io:imaging', 'Cannot write %s', target); end
        for k = 1:N, fwrite(fid, stack(:, :, 1, k)', prec); end
        J = struct('type', 0, 'dataType', codes.(cls), 'hasFrameHeaderFooter', false, ...
            'timingInfo', struct('numTimes', N, 'period', struct('num', 1000, 'den', round(1000 * o.Fps)), ...
                'start', struct('secsSinceEpoch', struct('num', 0, 'den', 1), 'utcOffset', 0), ...
                'dropped', [], 'cropped', []), ...
            'spacingInfo', struct('numPixels', struct('x', W, 'y', H), ...
                'pixelSize', struct('x', struct('num', round(1000 * o.PixelSizeUm), 'den', 1000), ...
                                    'y', struct('num', round(1000 * o.PixelSizeUm), 'den', 1000))), ...
            'producer', struct('name', 'Neuronal Data Analyzer Lab (synthetic)'));
        txt = jsonencode(J);
        fwrite(fid, [uint8(txt) 0], 'uint8');
        fwrite(fid, [numel(txt) 0], 'int32');
        fclose(fid);
        out = target;
    case 'thorimage'
        if ~exist(target, 'dir'), mkdir(target); end
        wl = '';
        for c = 1:C, wl = [wl sprintf('    <Wavelength name="%s" exposureTimeMS="0" />\n', names{c})]; end %#ok<AGROW>
        xml = sprintf(['<?xml version="1.0"?>\n<ThorImageExperiment>\n  <Name name="synthetic" />\n' ...
            '  <LSM name="GalvoResonance" pixelX="%d" pixelY="%d" widthUM="%g" heightUM="%g" ' ...
            'pixelSizeUM="%g" frameRate="%g" averageMode="0" averageNum="1" />\n' ...
            '  <Wavelengths nyquistExWavelengthNM="0" nyquistEmWavelengthNM="0">\n%s  </Wavelengths>\n' ...
            '  <ZStage name="ThorZStage" steps="1" stepSizeUM="0" />\n' ...
            '  <Timelapse timepoints="1" intervalSec="0" />\n' ...
            '  <Streaming enable="1" frames="%d" rawData="1" zFastEnable="0" flybackFrames="0" />\n' ...
            '</ThorImageExperiment>\n'], W, H, W * o.PixelSizeUm, H * o.PixelSizeUm, o.PixelSizeUm, o.Fps, wl, N);
        writeText(fullfile(target, 'Experiment.xml'), xml);
        fid = fopen(fullfile(target, 'Image_0001_0001.raw'), 'w', 'ieee-le');
        for k = 1:N
            for c = 1:C, fwrite(fid, uint16(stack(:, :, c, k))', 'uint16'); end
        end
        fclose(fid);
        out = target;
    case 'prairie'
        if ~exist(target, 'dir'), mkdir(target); end
        [~, base] = fileparts(target);
        t = o.Times;
        if isempty(t), t = (0:N-1) / o.Fps; end
        fr = '';
        for k = 1:N
            files = '';
            for c = 1:C
                fn = sprintf('%s_Cycle00001_Ch%d_%06d.ome.tif', base, c, k);
                imwrite(uint16(stack(:, :, c, k)), fullfile(target, fn));
                files = [files sprintf('      <File channel="%d" channelName="%s" page="1" filename="%s" />\n', ...
                    c, names{c}, fn)]; %#ok<AGROW>
            end
            fr = [fr sprintf('    <Frame relativeTime="%.6f" absoluteTime="%.6f" index="%d" parameterSet="CurrentSettings">\n%s    </Frame>\n', ...
                t(k), t(k) + 1.5, k, files)]; %#ok<AGROW>
        end
        xml = sprintf(['<?xml version="1.0" encoding="utf-8"?>\n<PVScan version="5.5.64.100" date="9/30/2026 10:00:00 AM" notes="">\n' ...
            '  <PVStateShard>\n    <PVStateValue key="framePeriod" value="%g" />\n' ...
            '    <PVStateValue key="linesPerFrame" value="%d" />\n    <PVStateValue key="pixelsPerLine" value="%d" />\n' ...
            '    <PVStateValue key="micronsPerPixel">\n      <IndexedValue index="XAxis" value="%g" />\n' ...
            '      <IndexedValue index="YAxis" value="%g" />\n      <IndexedValue index="ZAxis" value="1" />\n' ...
            '    </PVStateValue>\n  </PVStateShard>\n' ...
            '  <Sequence type="TSeries Timed Element" cycle="1" time="10:00:00.0000000">\n%s  </Sequence>\n</PVScan>\n'], ...
            1 / o.Fps, H, W, o.PixelSizeUm, o.PixelSizeUm, fr);
        writeText(fullfile(target, [base '.xml']), xml);
        out = target;
    otherwise
        error('NeuroAnalyzer:io:imaging', 'Unknown kind ''%s'' (isxd, thorimage, prairie).', kind);
end
end

function writeText(f, s)
fid = fopen(f, 'w');
if fid < 0, error('NeuroAnalyzer:io:imaging', 'Cannot write %s', f); end
fwrite(fid, s, 'char');
fclose(fid);
end
