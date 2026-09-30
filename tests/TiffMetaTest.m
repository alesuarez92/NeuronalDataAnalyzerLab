%% TiffMetaTest.m
% =========================================================================
% TIFF METADATA: IMAGEJ, OME-TIFF, SCANIMAGE, APERIO AND PLAIN TIFF TAGS
% =========================================================================
% core/io/tiffMeta.m and unitScale.m on the headers each program writes
% (imfinfo-like structs built here): pixel size with ImageJ's escaped
% micro sign (\u00B5m) and the Greek mu, hyperstack page order (channel,
% slice, frame), OME-XML DimensionOrder, sizes, units, time increment and
% channel names, ScanImage saved channels, frame rate, field of view,
% slices with flyback frames and frame timestamps, Aperio MPP, and plain
% ResolutionUnit tags; Histology.pixelSizeFromTiff follows. No display
% needed.
% =========================================================================

function tests = TiffMetaTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests) %#ok<INUSD>
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
end

function fi = pages(n, desc, varargin)
    fi = repmat(struct('ImageDescription', '', 'Software', '', 'XResolution', [], ...
        'YResolution', [], 'ResolutionUnit', 'None'), 1, n);
    fi(1).ImageDescription = desc;
    for k = 1:2:numel(varargin)
        fi(1).(varargin{k}) = varargin{k+1};
    end
end

function testUnits(tests)
    tests.verifyEqual(unitScale('\u00B5m'), 1);
    tests.verifyEqual(unitScale('\u03BCm'), 1);
    tests.verifyEqual(unitScale(char([181 109])), 1, 'micro sign');
    tests.verifyEqual(unitScale(char([956 109])), 1, 'Greek mu');
    tests.verifyEqual(unitScale(char([194 181 109])), 1, 'UTF-8 bytes');
    tests.verifyEqual(unitScale(char([206 188 109])), 1, 'UTF-8 bytes of the Greek mu');
    tests.verifyEqual(unitScale('microns'), 1);
    tests.verifyEqual(unitScale('mm'), 1000);
    tests.verifyEqual(unitScale('nm'), 1e-3);
    tests.verifyEqual(unitScale('cm'), 1e4);
    tests.verifyTrue(isnan(unitScale('pixel')));
    tests.verifyEqual(unitScale('ms', 'time'), 1e-3);
    tests.verifyEqual(unitScale('sec', 'time'), 1);
end

function testImageJ(tests)
    % The bug: ImageJ writes unit=\u00B5m (escaped)
    desc = sprintf('ImageJ=1.54f\nimages=24\nchannels=2\nslices=3\nframes=4\nhyperstack=true\nunit=\\u00B5m\nspacing=2.5\nfinterval=0.5\nloop=false\n');
    fi = pages(24, desc, 'XResolution', 4, 'YResolution', 2);
    M = tiffMeta(fi);
    tests.verifyEqual(M.source, 'imagej');
    tests.verifyEqual(M.pixelSizeUm, 0.25);
    tests.verifyEqual(M.pixelSizeYUm, 0.5);
    tests.verifyEqual(M.zStepUm, 2.5);
    tests.verifyEqual(M.frameInterval, 0.5);
    tests.verifyEqual(M.fps, 2);
    tests.verifyEqual([M.nChannels M.nSlices M.nFrames], [2 3 4]);
    tests.verifyEqual(size(M.pageMap), [2 3 4]);
    tests.verifyEqual(squeeze(M.pageMap(:, 1, 1))', [1 2], 'channel fastest');
    tests.verifyEqual(M.pageMap(1, 2, 1), 3, 'then slice');
    tests.verifyEqual(M.pageMap(1, 1, 2), 7, 'then frame');
    tests.verifyEqual(M.pageMap(2, 3, 4), 24);
    % Greek mu written as a character; frames missing: from the page count
    desc = sprintf('ImageJ=1.54f\nimages=10\nunit=%sm\nfinterval=40\ntunit=ms\n', char(956));
    M = tiffMeta(pages(10, desc, 'XResolution', 2));
    tests.verifyEqual(M.pixelSizeUm, 0.5);
    tests.verifyEqual(M.nFrames, 10);
    tests.verifyEqual(M.frameInterval, 0.04, 'AbsTol', 1e-12);
    % unit=pixel: no scale
    M = tiffMeta(pages(1, sprintf('ImageJ=1.54f\nunit=pixel\n'), 'XResolution', 1));
    tests.verifyTrue(isnan(M.pixelSizeUm));
    % Fewer pages than the header says (a cut acquisition): only complete time points
    desc = sprintf('ImageJ=1.54f\nimages=12\nchannels=2\nframes=6\nhyperstack=true\n');
    M = tiffMeta(pages(9, desc));
    tests.verifyEqual(M.nFrames, 4);
end

function testOME(tests)
    xml = ['<?xml version="1.0" encoding="UTF-8"?><OME xmlns="http://www.openmicroscopy.org/Schemas/OME/2016-06">' ...
        '<Image ID="Image:0" Name="cells"><Pixels ID="Pixels:0" DimensionOrder="XYZCT" Type="uint16" ' ...
        'SizeX="64" SizeY="48" SizeZ="3" SizeC="2" SizeT="5" PhysicalSizeX="0.325" PhysicalSizeXUnit="&#181;m" ' ...
        'PhysicalSizeY="0.325" PhysicalSizeZ="1.5" PhysicalSizeZUnit="µm" TimeIncrement="200" TimeIncrementUnit="ms">' ...
        '<Channel ID="Channel:0:0" Name="DAPI" SamplesPerPixel="1"/><Channel ID="Channel:0:1" Name="GFP &amp; co" SamplesPerPixel="1"/>' ...
        '<TiffData/></Pixels></Image></OME>'];
    M = tiffMeta(pages(30, xml));
    tests.verifyEqual(M.source, 'ome');
    tests.verifyEqual([M.nChannels M.nSlices M.nFrames], [2 3 5]);
    tests.verifyEqual(M.pixelSizeUm, 0.325, 'AbsTol', 1e-12);
    tests.verifyEqual(M.pixelSizeYUm, 0.325, 'AbsTol', 1e-12, 'default unit um');
    tests.verifyEqual(M.zStepUm, 1.5, 'AbsTol', 1e-12);
    tests.verifyEqual(M.frameInterval, 0.2, 'AbsTol', 1e-12);
    tests.verifyEqual(M.channelNames, {'DAPI', 'GFP & co'});
    % XYZCT: Z fastest, then C, then T
    tests.verifyEqual(M.pageMap(1, 2, 1), 2);
    tests.verifyEqual(M.pageMap(2, 1, 1), 4);
    tests.verifyEqual(M.pageMap(1, 1, 2), 7);
    % Plane DeltaT gives the frame times; XYCTZ order
    xml = ['<OME><Image ID="Image:0"><Pixels DimensionOrder="XYCTZ" SizeX="4" SizeY="4" SizeZ="1" SizeC="1" SizeT="3">' ...
        '<Plane TheC="0" TheT="0" TheZ="0" DeltaT="0.0"/><Plane TheC="0" TheT="1" TheZ="0" DeltaT="0.11"/>' ...
        '<Plane TheC="0" TheT="2" TheZ="0" DeltaT="0.19"/></Pixels></Image></OME>'];
    M = tiffMeta(pages(3, xml));
    tests.verifyEqual(M.t, [0 0.11 0.19], 'AbsTol', 1e-12);
    tests.verifyTrue(isnan(M.pixelSizeUm));
end

function testScanImage(tests)
    soft = sprintf(['SI.VERSION_MAJOR = 2020\nSI.hChannels.channelSave = [1;2]\n' ...
        'SI.hRoiManager.scanFrameRate = 30\nSI.hRoiManager.pixelsPerLine = 256\nSI.hRoiManager.linesPerFrame = 128\n' ...
        'SI.hRoiManager.imagingFovUm = [-256 -128;256 -128;256 128;-256 128]\n' ...
        'SI.hFastZ.enable = true\nSI.hFastZ.numDiscardFlybackFrames = 1\nSI.hFastZ.numVolumes = 2\n' ...
        'SI.hStackManager.numSlices = 3\nSI.hStackManager.actualNumSlices = 3\nSI.hStackManager.stackZStepSize = 5\n']);
    n = 2 * (3 + 1) * 2;                                     % channels x (slices + flyback) x volumes
    fi = pages(n, '');
    fi(1).Software = soft;
    for k = 1:n
        fi(k).ImageDescription = sprintf('frameNumbers = %d\nframeTimestamps_sec = %.6f\n', ceil(k / 2), (ceil(k / 2) - 1) / 30);
    end
    M = tiffMeta(fi);
    tests.verifyEqual(M.source, 'scanimage');
    tests.verifyEqual([M.nChannels M.nSlices M.nFrames], [2 3 2]);
    tests.verifyEqual(M.channelNames, {'Channel 1', 'Channel 2'});
    tests.verifyEqual(M.pixelSizeUm, 2);
    tests.verifyEqual(M.pixelSizeYUm, 2);
    tests.verifyEqual(M.zStepUm, 5);
    tests.verifyEqual(M.frameInterval, 4 / 30, 'AbsTol', 1e-12, 'one volume (3 slices + 1 flyback)');
    % channel, slice (flyback skipped), volume
    tests.verifyEqual(squeeze(M.pageMap(:, 1, 1))', [1 2]);
    tests.verifyEqual(M.pageMap(1, 3, 1), 5);
    tests.verifyEqual(M.pageMap(1, 1, 2), 9, 'after the flyback frame (pages 7-8)');
    tests.verifyEqual(M.t, [0 4 / 30], 'AbsTol', 1e-6);
    % A plain time series, one channel, no fast z
    soft = sprintf('SI.hChannels.channelSave = 1\nSI.hRoiManager.scanFrameRate = 15.5\nSI.hStackManager.numSlices = 1\nSI.hStackManager.framesPerSlice = 100\n');
    fi = pages(100, '');
    fi(1).Software = soft;
    M = tiffMeta(fi);
    tests.verifyEqual([M.nChannels M.nSlices M.nFrames], [1 1 100]);
    tests.verifyEqual(M.fps, 15.5, 'AbsTol', 1e-12);
    tests.verifyEqual(squeeze(M.pageMap)', 1:100);
end

function testAperioAndPlain(tests)
    desc = 'Aperio Image Library v11.2.1 46000x32914 [0,100 46000x32814] (240x240) JPEG/RGB Q=30|AppMag = 20|StripeWidth = 2040|MPP = 0.4990|Filename = CMU-1';
    M = tiffMeta(pages(1, desc));
    tests.verifyEqual(M.source, 'aperio');
    tests.verifyEqual(M.pixelSizeUm, 0.499, 'AbsTol', 1e-12);
    tests.verifyEqual(M.magnification, 20);
    M = tiffMeta(pages(1, '', 'XResolution', 20000, 'ResolutionUnit', 'Centimeter'));
    tests.verifyEqual(M.pixelSizeUm, 0.5, 'AbsTol', 1e-12);
    M = tiffMeta(pages(1, '', 'XResolution', 72, 'ResolutionUnit', 'Inch'));
    tests.verifyTrue(isnan(M.pixelSizeUm), '72 dpi is not a scale');
    M = tiffMeta(pages(1, ''));
    tests.verifyTrue(isnan(M.pixelSizeUm));
    tests.verifyEqual(M.source, 'tiff');
end

function testHistologyPixelSize(tests)
    % The escaped micro sign used to give no pixel size
    fi = pages(1, sprintf('ImageJ=1.54f\nunit=\\u00B5m\n'), 'XResolution', 2);
    tests.verifyEqual(Histology.pixelSizeFromTiff(fi(1)), 0.5);
    % Unknown ImageJ unit, then the plain tags
    fi = pages(1, sprintf('ImageJ=1.54f\n'), 'XResolution', 10000, 'ResolutionUnit', 'Centimeter');
    tests.verifyEqual(Histology.pixelSizeFromTiff(fi(1)), 1, 'AbsTol', 1e-12);
    fi = pages(1, '', 'XResolution', 96, 'ResolutionUnit', 'Inch');
    tests.verifyEmpty(Histology.pixelSizeFromTiff(fi(1)));
end
