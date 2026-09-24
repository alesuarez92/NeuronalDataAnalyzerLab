# Wave 1 report: data formats (Intan RHD, Open Ephys binary, NWB) in Extract Ephys

> Development notes for the in-progress improvement strand. They are removed before merging to `main`.

Classification: NEW STRAND (area: data formats / acquisition-system adapters).

Nothing here has been run in real MATLAB yet. This is what was checked, and how:

- **Intan and Open Ephys readers and writers, `.npy` I/O, `EphysSource` and `demoFormats`**: run in Octave 8.
- **Independent check of the files the writers produce**: the neo library (`IntanRawIO`, `OpenEphysBinaryRawIO`, BSD licence) reads them back with the same samples, rates, channel names and TTL events. neo was used only as a black-box checker; none of its code was copied.
- **NWB layout from `writeNWB`**: written to HDF5 from Octave and validated with pynwb's schema validator. It shows **0 errors against NWB core 2.7.0** (pynwb 2.8.3) **and 2.11.0** (pynwb 4.2.0). pynwb reads every object back. nwbinspector reports no structural problems (details below). Two routes were used to write the file:
  - a Python (h5py) copy of the layout;
  - the real `commitLayout` code, run through an Octave stand-in for MATLAB's low-level `H5F/H5G/H5D/H5A/H5T/H5S/H5R/H5L` calls. The stand-in accepts only the documented argument forms and data shapes, and replays the calls with h5py.
- **`readNWB`**: run in Octave through h5py-backed stand-ins for `h5info`, `h5read` and `h5readatt`. It was tested on:
  - files from `writeNWB`;
  - a file written by pynwb itself: int16 data with `conversion` and `channel_conversion`, an electrode `label` column, a series starting at 5 s, a timestamp-based stimulus, an IntervalSeries, trials and units.
- **`tests/FormatsFeaturesTest.m`**: run in Octave with these stand-ins and small `verify*` shims. 18 tests passed; 1 was skipped (matnwb is not installed).
- **`apps/ExtractEphysApp.m` and `tests/FormatsWalkthroughTest.m`**: parse-checked only. Octave has no uifigure.

What real MATLAB still has to confirm:
- the low-level HDF5 calls in `writeNWB` behave as their documentation says (variable-length UTF-8 strings written from cell arrays, `H5R.create` object references, `H5L.create_soft`);
- the types that `h5info` / `h5read` return (the reader accepts char, cell or string for text);
- the UI.

## Files

Changed
- `apps/ExtractEphysApp.m` (+414 / −66)

New
- `core/io/EphysSource.m`: the adapter. It lists the formats, detects the format of a file or folder, dispatches to the right reader, builds the common struct, turns TTL events into square waves and finds rising edges.
- `core/io/readIntanRHD.m`: Intan RHD2000 `.rhd` reader.
- `core/io/writeIntanRHD.m`: `.rhd` writer, for synthetic test and demo files.
- `core/io/readOpenEphysBinary.m`: Open Ephys binary format reader (GUI 0.5 and later).
- `core/io/writeOpenEphysBinary.m`: Open Ephys writer, with the 0.6 and 0.5 layouts, for synthetic test and demo files.
- `core/io/readNPY.m`, `core/io/writeNPY.m`: minimal NumPy `.npy` I/O.
- `core/io/readNWB.m`: NWB 2.x reader (HDF5).
- `core/io/writeNWB.m`: NWB 2.x export. It uses matnwb when that is on the path, otherwise a minimal built-in writer.
- `core/demo/demoFormats.m`: writes the demo tank in the three new formats.
- `tests/FormatsFeaturesTest.m`: 19 unit tests.
- `tests/FormatsWalkthroughTest.m`: 5 UI tests that save frames `ExtractEphysApp_x01..x13_*.png`.
- `docs/dev/reports/formats.md`: this report.

`git diff --stat` (tracked files): `apps/ExtractEphysApp.m | 480 ++++++++++++++++++++++++++++++++++++++++++-------` (414 insertions, 66 deletions).

## The common struct

Every reader returns the struct shape that `TDTbin2mat` gives for the TDT tanks Extract Ephys already loads. The rest of the app is therefore unchanged: filtering, plotting, Save LFP / Save MUA and the `.mat` variables are the same as before.

```text
rec.streams.xRAW.data   neural channels x samples, single, volts   .fs (Hz)   .channel = 1:n
rec.streams.Whis.data   candidate stimulus channels x samples, single   .fs   .channel = 1:m
rec.info                source, format, file, blockname, duration (s), channelNames, stimNames,
                        stimKinds, units 'V' (+ format-specific fields listed below)
```

When a recording has no stimulus channel, `Whis` is one zero row at the raw rate, named `(no stimulus channel)`.

## New public API

```matlab
% core/io
list = EphysSource.formats()            % struct: key, label, pick ('folder'|'file'), filter, prompt, hint
fmt  = EphysSource.detect(path)         % 'tdt' | 'intan' | 'openephys' | 'nwb'
rec  = EphysSource.open(path, fmt)      % fmt 'auto' or omitted: detect
s    = EphysSource.label(fmt)
rec  = EphysSource.makeRecording(raw, fs, stim, stimFs, info)
x    = EphysSource.eventsToSquare(onIdx, offIdx, n)   % 0/1 row from 1-based edge indices
t    = EphysSource.risingEdges(x, fs, thr)            % onset times (s)
data = EphysSource.openTDT(folder)      % TDTbin2mat, or DemoData.loadTank for a demo tank
tf   = EphysSource.isDemoTank(folder)
p    = EphysSource.findFile(root, name, maxDepth)

rec  = readIntanRHD(file)               % also readIntanRHD(file, 'HeaderOnly', true) -> header struct
out  = writeIntanRHD(file, amp, fs, 'Version', [3 0], 'DigitalIn', L, 'ADC', A, 'ChannelNames', c, ...
                     'Notes', c, 'NotchMode', 0, 'FirstTimestamp', 0, 'AuxChannels', 0, ...
                     'SupplyChannels', 0, 'TempSensors', 0, 'DisabledChannels', 0, 'DisabledGroup', false)
rec  = readOpenEphysBinary(path)        % also readOpenEphysBinary(path, 'Stream', indexOrName)
out  = writeOpenEphysBinary(folder, data, fs, 'Version', '0.6.7'|'0.5.5', 'ChannelNames', c, ...
                     'BitVolts', 0.195, 'ADC', A, 'TTL', struct('line',..,'on',..,'off',..), 'FirstSample', 0)
x    = readNPY(file);   writeNPY(file, x)
rec  = readNWB(file)                    % also readNWB(file, 'Series', nameOrPath)
out  = writeNWB(file, results)          % also writeNWB(file, results, 'Engine', 'auto'|'matnwb'|'minimal', 'DryRun', tf)

% core/demo
files = demoFormats()                   % cached in <DemoData.folder>/formats (per format)
files = demoFormats(folder, 'Formats', {'intan','openephys','nwb'}, 'Tank', tank, 'Force', tf)

% ExtractEphysApp (new public methods; all dialog-free except the button callbacks)
ok = app.openRecording(path, format)    % format 'tdt'|'intan'|'openephys'|'nwb'|'auto'
app.loadDemo(format)                    % optional format; default = Source dropdown ('tdt' initially)
ok = app.exportNWB(path)                % last processed LFP + its stimulus channel
app.loadRecording()                     % Load recording… button (picker for the selected Source)
app.saveNWBData()                       % Export NWB… button (uiputfile, then exportNWB)
app.onSourceChanged()                   % Source dropdown callback
```

Existing public methods keep their signatures and behaviour:
- `openTank(folder)` now calls `openRecording(folder, 'tdt')`. The TDT and demo-tank paths are identical: same reader (`TDTbin2mat` or `DemoData.loadTank`), same messages, same stream check, same list labels (`Ch k`), same info text and same plot title (`Stimulus (Whis Ch k)`).
- These are unchanged: `loadTDT`, `setChannels`, `plotRAWData`, `processLFPData(params)`, `processMUAData(params)`, `saveLFPTo`, `saveMUATo`.
- New properties: `SourceMenu`, `ExportNWBBtn`, `SourceFormat`, `LastLFPParams`, `LastNWBExport`.

## What changed in Extract Ephys

- **Step 1 "Load recording"**:
  - a **Source** dropdown: TDT tank, Intan .rhd, Open Ephys folder, NWB file;
  - **Load recording…** (primary button), which opens a folder or file picker to suit the source;
  - **Try demo data**, which loads the demo in the selected format;
  - the info line now names the source.
- **Step 2**: the stimulus dropdown is now labelled **Stimulus channel**. Its items come from the source:
  - TDT: `Ch k` (the Whis channels);
  - Intan: `DIGITAL-IN-01`, `ANALOG-IN-1`;
  - Open Ephys: `TTL line 1`, `ADC1`;
  - NWB: the stimulus TimeSeries names, and `trials (intervals)`.

  RAW items show the source channel name, for example `Ch 1  A-000`. The stimulus plot is titled with the stimulus name.
- **Step 4**: a new **Export NWB…** button, enabled after Process LFP. The default file name is `<recording>_LFP.nwb`. The status bar says **"NWB-style file (not validated)"** when the built-in writer is used, or "written with matnwb".
- The window is 840 px tall instead of 800, so the channel list keeps its height.
- `ensureIOPath()` adds `core/io` and `core/demo` to the path when the app is built, because `NeuroAnalyzer.m` and `run_tests.m` do not add them yet (see "Wiring").

## Readers: method and limitations

### Intan RHD2000 (`readIntanRHD`)

The reader was written from Intan's published RHD2000 data file format documentation. Intan's own MATLAB reader was not used.

**Header** (little-endian):
- magic number `0xC6912702`;
- version as two int16 values (major, minor);
- float32 sample rate;
- DSP and bandwidth settings;
- notch mode;
- three notes;
- from version 1.1: number of temperature sensors;
- from version 1.3: board mode;
- from version 2.0: reference channel;
- the signal groups, then one record per channel.

**Data blocks:**
- A block holds 60 samples for major version 1 and 128 samples for version 2 and later.
- Order within a block: timestamps (int32, or uint32 before version 1.2), amplifier channels, aux (N/4 samples), supply, temperature, ADC, digital-in word, digital-out word.
- Amplifier volts = 0.195e-6 × (value − 32768).
- Board ADC volts depend on the board mode: 50.354 µV × value (mode 0), 152.59 µV × (value − 32768) (mode 1), or 312.5 µV × (value − 32768) (mode 13).
- Digital input *k* is bit `native_order` of each digital word.

**Stimulus candidates:** the enabled digital inputs (as 0/1), then the ADC channels (in volts).

**Supported:**
- versions 1.0–3.x, in the traditional single-file format;
- enabled and disabled channels and groups;
- aux, supply and temperature channels, which are skipped;
- timestamp gaps: counted, with a warning.

**Clear errors:**

| Error | When |
|---|---|
| `NeuroAnalyzer:io:badMagic` | wrong magic number; this also catches `.rhs` stimulation files |
| `:unsupportedVersion` | major version is not 1–3 |
| `:truncated` | the data is not a whole number of blocks |
| `:noData` | header only: Intan's "one file per signal type / per channel" formats |
| `:fileNotFound` | the file does not exist |

**Not done:**
- The notch-filter setting is reported in `info.header.notchFilterHz` but not applied.
- UTF-16 surrogate pairs in channel names are not decoded.
- RHS files and the multi-file `.dat` formats are not read.

**Checked:** neo reads the written version 1.2, 1.3, 2.0 and 3.0 files with the same values: amplifier within half an LSB, aux 0.748 V, supply 3.3 V, ADC, digital lines. neo itself fails on files that contain temperature-sensor channels (a neo bug), so that case is covered only by my own round trip.

### Open Ephys binary (`readOpenEphysBinary`)

**`structure.oebin`** (JSON) lists the continuous streams, with `folder_name`, `sample_rate`, `num_channels` and the channels' `channel_name`, `bit_volts` and `units`.

**Samples:** `continuous/<stream>/continuous.dat` holds int16 values interleaved by channel. value × `bit_volts` is in the channel's units: µV for headstage channels, V for ADC channels.

**First sample number:** from `sample_numbers.npy` (GUI 0.6 and later), or from the integer `timestamps.npy` (GUI 0.5).

**TTL events** are in `events/<stream>/TTL[_n]/`:
- the states file is `states.npy` (0.6) or `channel_states.npy` (0.5); +line marks a rising edge and −line a falling edge;
- the sample numbers are in `sample_numbers.npy` (0.6) or the integer `timestamps.npy` (0.5).

Each line becomes a square wave on the continuous grid; `info.stimOnsets` holds the exact onset times.

**Channels:** `ADC*` channels become stimulus candidates. `AUX*` channels (headstage accelerometer) are skipped and listed in `info.skippedChannels`.

**Which recording is read:** the path can be the recording folder, `structure.oebin` itself, or any folder above it. The first recording in sorted order is used; the others are listed in `info.otherRecordings`. One stream is read per call (`'Stream'`).

**Not read:** text and message events, spikes, and the older "Open Ephys format" (`.continuous` files).

**Checked:** neo reads the written 0.6 folders with the same data, the ADC stream split off, and TTL times and durations. For 0.5 folders, the data and labels match. neo's 0.5 event times are divided by the rate twice, which is a neo quirk: the raw sample numbers it reads are the ones I wrote.

### NWB 2.x (`readNWB`)

`readNWB` uses `h5info`, `h5read` and `h5readatt`. It recognises objects by their `neurodata_type` attribute.

**Which series is read:** by default, the first ElectricalSeries in `/acquisition`, else the first one in `/processing`, for example an LFP exported by `writeNWB`. Use `'Series'` to choose another.

**Data:**
- volts = data × `conversion` (× `channel_conversion`) + `offset`;
- the rate comes from `starting_time` + `rate`, or from `timestamps` (median step, with a warning when they are irregular);
- electrode ids come from the region; channel names come from the electrodes table's `label` column.

**Stimulus candidates**, all put on one grid (the rate of the first regular stimulus TimeSeries, else the series rate) and aligned to the series start time:
- TimeSeries in `/stimulus/presentation`;
- non-ElectricalSeries TimeSeries in `/acquisition`;
- IntervalSeries;
- every TimeIntervals table under `/intervals` (for example trials), which becomes a square wave.

`info.spikeUnits` returns spike times when the file has a `/units` table.

**matnwb's `nwbRead` is deliberately not used for reading.** It generates class files on first use, and plain HDF5 reads work on any NWB 2.x file, including those matnwb writes. This departs from the brief ("prefer matnwb for reading"); matnwb *is* preferred for writing.

**Limitations:** 3-D series are rejected, and the whole series is loaded into memory.

**Clear errors:**

| Error | When |
|---|---|
| `NeuroAnalyzer:io:notHDF5` | no HDF5 signature at byte 0, 512, 1024 or 2048 |
| `:notNWB` | HDF5 without the `nwb_version` root attribute |
| `:noData` | no ElectricalSeries in the file |
| `:fileNotFound` | the file does not exist |

## NWB export (`writeNWB`): what is and isn't compliant

**Engines:**
- `'auto'` (the default) uses matnwb when `NwbFile` and `nwbExport` are on the path, otherwise the minimal writer.
- If the matnwb export throws an error, a warning is issued and the minimal writer is used instead.
- `out.validated` is always `false`: nothing in the toolbox runs a validator at run time.

**What the minimal writer produces** (declares `nwb_version` 2.7.0):
- **Root:**
  - attributes `nwb_version`, `neurodata_type` = NWBFile, `namespace` = core and `object_id` (a UUID v4);
  - datasets `identifier`, `session_description`, `session_start_time`, `timestamps_reference_time` and `file_create_date`;
  - groups `acquisition`, `analysis`, `processing`, `stimulus/presentation`, `stimulus/templates`, `general` and `general/devices`.
- **Every typed object** has `neurodata_type`, `namespace` and a unique `object_id`.
- **Electrodes:**
  - a Device;
  - an ElectrodeGroup with a soft link `device` to that Device;
  - the `electrodes` DynamicTable with `colnames`, `description`, `id`, `location`, `group` (object references), `group_name` and `label`.
- **ElectricalSeries:**
  - raw data goes to `/acquisition`;
  - LFP goes to `/processing/ecephys` (ProcessingModule) → `LFP` → `ElectricalSeries`;
  - each series has `data` (HDF5 order time × channel, with unit volts, conversion, offset and resolution), `starting_time` with `rate` and `unit`, `electrodes` (a DynamicTableRegion with a `table` object reference), and `description`, `comments` and `filtering` (the processing actually done).
- **Other objects:**
  - the stimulus as a TimeSeries in `/stimulus/presentation`;
  - trials as TimeIntervals in `/intervals/trials`;
  - `/units`, with `spike_times` + `spike_times_index` (a VectorIndex with a `target` object reference) and an optional `resolution`.
- **Optional metadata:** `/general/subject`, `experiment_description`, `experimenter`, `lab`, `institution`, `data_collection` (the source recording) and `notes`.
- **Text** is written as variable-length UTF-8.

**Checked:**
- pynwb's schema validator reports **0 errors against core 2.7.0 and core 2.11.0**, for files built from this layout by both the h5py copy and the emulated MATLAB committer.
- pynwb reads back the LFP, raw data, electrodes, units, trials and stimulus.
- **nwbinspector**:
  - no schema or structural issues;
  - "Subject is missing" (CRITICAL, a DANDI requirement) when no `results.subject` is given — the app does not know the subject;
  - "Units resolution not set" (a best-practice violation) unless `unitsResolution` is given;
  - suggestions for experimenter, experiment description, institution and keywords.

**Not compliant / not done:**
- The file is not validated at run time. That is why the UI and docs say "NWB-style export (not validated)".
- The cached schema (`/specifications`) is not embedded. Readers fall back to their installed core namespace.
- No chunking or compression.
- Electrode x/y/z and impedance are not written; these columns are optional in 2.7.
- There are no units–electrodes links and no waveforms.
- Session start time for TDT, Intan and Open Ephys sources is the export time, with a note in `/general/notes`. For NWB sources the original start time is kept.
- When the same MATLAB call path runs in real MATLAB, the HDF5 details (for example string padding) may differ from the emulation. Validate a file once with `pynwb`/`nwbinspector` after CI.

**matnwb engine:** written from the matnwb tutorial API (`NwbFile`, `types.core.*`, `types.hdmf_common.*`, `util.create_indexed_column`, `nwbExport`). It is **untested**: matnwb is not installed here or in CI. `testNWBWithMatnwb` is skipped when matnwb is missing.

## Demo data (`core/demo/demoFormats.m`)

The first 6 s of demo-tank channels 3–6 (the evoked sink is at tank channel 4, which is RAW Ch 2; the units are near RAW Ch 2–3). The stimuli come at 1, 3 and 5 s, 20 ms each.

| Format | File | Rate | Stimulus |
|---|---|---|---|
| Intan (format 3.0) | `demo_intan.rhd` | 20 kHz (linear resampling) | `DIGITAL-IN-01` (TTL) and `ANALOG-IN-1` (1 V pulses) |
| Open Ephys (GUI 0.6 layout) | `demo_openephys/` | 30 kHz | CH1–CH4 plus `ADC1` (1 V pulses), TTL line 1; first sample 512000 |
| NWB | `demo.nwb` | tank rate 24414.0625 Hz | the tank's whisker stimulus TimeSeries (1017.25 Hz) and `/intervals/trials` |

- In the NWB file the raw data are int16 × 0.195 µV. It has electrode labels `tank chN` and a synthetic subject entry.
- `files.truth` holds onsets, duration, channels and `sinkIndex`, and, per format, fs, nSamples, lsb and the data before quantization. The cached copy keeps no sample arrays.
- The generator is deterministic: it adds nothing random to DemoData's fixed seed.
- The cache is per format. `loadDemo('intan')` therefore does not depend on the NWB writer.

## Tests

### `tests/FormatsFeaturesTest.m` (setupOnce writes `demoFormats` into a temp folder)

**Intan**

| Test | What it checks |
|---|---|
| `testIntanDemoRoundTrip` | fs 20000; 4 channels; samples within half an LSB (0.0975 µV); channel names; the digital row equals the written TTL; onsets from DIGITAL-IN and ANALOG-IN equal the truth within one sample; 128-sample blocks |
| `testIntanVersionsAndBlockLayout` | versions 1.0, 1.1, 1.2, 1.3, 2.0 and 3.0 with aux, supply, temperature, a disabled channel and a disabled group all round-trip; 60 or 128 samples per block; no gaps |
| `testIntanHandBuiltHeader` | a file assembled byte by byte from the documented layout (version 1.3). Checks the magic bytes `02 27 91 C6`, sample rate, 60 Hz notch, note text, header size, bytes per block, custom names, disabled channel skipped, amplifier = 0.195 µV × k, the digital bit-3 channel, first timestamp 100. It also checks that the writer's first 12 bytes are the documented magic, version and float32 rate |
| `testIntanErrors` | missing file, wrong magic, version 9, truncated file, header only; each raises its error id |

**Open Ephys and `.npy`**

| Test | What it checks |
|---|---|
| `testOpenEphysDemoRoundTrip` | fs 30000; 4 channels; samples within half a `bit_volts` step; stimulus names `{'TTL line 1','ADC1'}`; first sample 512000; TTL and ADC onsets; opening by folder, by `structure.oebin` or by parent folder gives the same data |
| `testOpenEphysLegacyLayout` | the GUI 0.5 layout (`channel_states`, integer `timestamps`), with TTL line 2 onsets and durations |
| `testOpenEphysHandBuilt` | a hand-written oebin JSON, a hand-packed int16 `continuous.dat` and hand-built `.npy` bytes give ch1 = value × 0.195 µV, ch2 = value × 2 µV, ADC = value × 0.5 V, and TTL high on samples 2–3 |
| `testNpyHandBuilt` | little-endian int64; big-endian float32 2 × 2 in C order; writer header (`\x93NUMPY`, version 1.0, 64-byte padding); bad magic |
| `testOpenEphysErrors` | no oebin; missing folder; missing `continuous.dat`; bad JSON |

**NWB**

| Test | What it checks |
|---|---|
| `testNWBDemoRead` | fs, 4 channels, samples within half an LSB, electrode ids 3–6 and labels, stimulus names, the stimulus grid at the TimeSeries rate, onsets from trials (exact) and from the TimeSeries (within one sample), identifier, series path |
| `testNWBWriteReadRoundTrip` | LFP, stimulus, trials and units: LFP values, fs, ids and names, stimulus trace, trial onsets, units' spike times including an empty unit, start time. A second write adds int16 raw data with `conversion` in `/acquisition`, which takes precedence, and `'Series'` selects the LFP |
| `testNWBRequiredTopLevel` | HDF5 signature bytes; root `nwb_version` 2.7.0, NWBFile, core, a 36-character `object_id`; the five required root datasets; the required groups; the ProcessingModule, LFP, ElectricalSeries and DynamicTableRegion types and namespaces; `unit` volts; `rate`; data dims (time, channel); electrodes table |
| `testNWBHandBuiltFile` | an NWB-shaped file made only with `h5create`, `h5write` and `h5writeatt` (not `writeNWB`), with fixed-length text attributes, is read correctly: conversion, rate, start time, version, and a zero-order hold of a timestamped stimulus |
| `testNWBErrors` | missing file, non-HDF5 file, HDF5 without `nwb_version`, NWB without an ElectricalSeries, bad `results` |
| `testNWBDryRunLayout` | the required nodes are in the layout; every typed object has a valid, unique UUID v4 `object_id`; `spike_times_index` values |
| `testNWBWithMatnwb` | the matnwb engine; runs only when matnwb is installed |

**EphysSource and demo cache**

| Test | What it checks |
|---|---|
| `testEphysSourceDetectAndOpen` | detection by extension, by magic number (a renamed `.dat`), of a demo-tank folder and of an unknown file; `open` with `'auto'` gives the common struct for every format; TDT through `EphysSource` |
| `testEphysSourceHelpers` | `eventsToSquare` (edges at the start and at the end), `risingEdges`, `makeRecording` defaults, the `formats()` keys |
| `testDemoFormatsCache` | the cache returns the same paths, keeps no sample arrays, and has onsets `[1 3 5]` |

### `tests/FormatsWalkthroughTest.m`

The frames go to `test-artifacts/screens/walkthrough/ExtractEphysApp_xNN_*.png`.

| Test | What it does | Frames |
|---|---|---|
| `testSourceDropdown` | checks the dropdown items; selecting Open Ephys changes the Load tooltip | x01 |
| `testIntanRecording` | `loadDemo('intan')`, then Process LFP (1000 Hz), then `exportNWB`; reopens the exported NWB (the LFP at 1000 Hz, same channel names) and runs Plot RAW | x02–x05 |
| `testOpenEphysRecording` | the same steps; ADC1 as the stimulus | x06–x09 |
| `testNWBRecording` | the same steps; LFP at 24414.0625 / 24 Hz; stimulus items | x10–x12 |
| `testOpenRecordingAutoDetect` | freshly written files opened with format detection; a bad `.rhd` shows "magic number" in the status bar and keeps the previous recording | x13 |

## References cited in the headers

- **Intan Technologies**: RHD2000 data file format documentation (application note), intantech.com. The document's exact title is uncertain, so it is cited by publisher and site.
- **Open Ephys GUI documentation**: "Binary format", open-ephys.github.io.
- **NWB 2.x format specification**: nwb-schema.readthedocs.io.
- **Rübel O. et al. (2022)**: The Neurodata Without Borders ecosystem for neurophysiological data science. *eLife* 11:e78362.
- **NumPy `.npy` format**: described in the `readNPY` / `writeNPY` headers, without a paper citation.

## Not verified / risks

1. **Low-level HDF5 calls in `writeNWB/commitLayout`** have not been run in MATLAB.
   - The calls: `H5F.create`, `H5G.create/open`, `H5S.create/create_simple`, `H5T.copy/set_size('H5T_VARIABLE')/set_cset`, `H5D.create/write/open`, `H5A.create/write`, `H5R.create(fid, path, 'H5R_OBJECT', -1)`, `H5L.create_soft`.
   - They follow the documented forms and the HDF Group's MATLAB examples: cell arrays for variable-length strings, and uint8 8 × n arrays for object references.
   - If one of them misbehaves in CI, the failing tests are: every NWB test, `testDemoFormatsCache`, and the NWB parts of the walkthrough.
   - Intan and Open Ephys do not depend on it: the demo cache is per format.
2. **Types that `h5info`, `h5read` and `h5readatt` return** for text (char, cell or string). The reader and the tests accept all three.
3. **The UI** (layout, and dropdown `ItemsData` as a cell of char) is parse-checked only.
4. **The matnwb engine** is untested.

## Wiring suggestions (files outside this area's scope)

- **`NeuroAnalyzer.m`, `run_tests.m`, `tests/AppSmokeTest.m`, `tests/DemoWalkthroughTest.m`**: add `addpath(fullfile(root, 'core', 'io'))` and `addpath(fullfile(root, 'core', 'demo'))`. The app already does this itself (`ensureIOPath`), so nothing breaks without it.
- **`core/DemoData.m`**:
  - `DemoData.file('intan' | 'openephys' | 'nwb')` → `f = demoFormats([], 'Formats', {kind}); p = f.(kind);`
  - `writeAll` → `files.formats = demoFormats(fullfile(folder, 'formats'));`
- **CHANGELOG**: "Extract Ephys loads Intan RHD2000 (.rhd), Open Ephys binary and NWB 2.x recordings (core/io); Export NWB… writes the processed LFP as NWB (matnwb when installed, otherwise an NWB-style export, not validated)."
- **README**: in the requirements, note that Intan, Open Ephys and NWB need no extra toolbox; matnwb is optional (<https://github.com/NeurodataWithoutBorders/matnwb>).

## Ready-to-paste Help text (HelpApp `topicEphysExtract`)

Replace `t.quick`:

```matlab
t.quick = {
    '**1 Load recording**: choose the **Source** (TDT tank, Intan .rhd, Open Ephys folder or NWB file), click **Load recording…** and select the tank / block folder, the .rhd file, the Open Ephys recording folder (or any folder above it) or the .nwb file. The channel lists are filled from the recording.'
    '**2 Choose channels**: pick the **Stimulus channel** (TDT: Whis; Intan: DIGITAL-IN / ANALOG-IN; Open Ephys: TTL line / ADC; NWB: stimulus TimeSeries or trials) and one or more raw channels (**All** / **None** help).'
    '**3 Process**: optionally **Plot RAW**; then **Process LFP…** (low-pass, 60 Hz notch, downsample) and/or **Process MUA…** (band-pass, default 300–3000 Hz).'
    '**4 Save**: **Save LFP…** / **Save MUA…**, choose which channels to keep and a file name (default `<recording>_LFP.mat` / `<recording>_MUA.mat`). Open these files in **LFP analysis** / **MUA analysis**. **Export NWB…** writes the processed LFP and its stimulus channel as an NWB 2.x file (default `<recording>_LFP.nwb`).'};
```

Append to `t.demo`:

```matlab
    '* **Other formats**: choose a **Source** before **Try demo data** to open the first 6 s of demo channels 3–6 written as an Intan .rhd (20 kHz; stimulus on DIGITAL-IN-01 and a 1 V copy on ANALOG-IN-1), an Open Ephys folder (30 kHz; TTL line 1 and ADC1) or an NWB file (24414 Hz; the whisker stimulus TimeSeries and a trials table). There are 3 stimuli (1, 3 and 5 s). **Process LFP** gives 1000 Hz (Intan, Open Ephys) or 1017.25 Hz (NWB), with the evoked negative deflection at **15 ms**, largest on **RAW Ch 2** (= demo channel 4).'
    '* **Export NWB…** after Process LFP, then choose Source **NWB file** and **Load recording…** with the exported file: the LFP opens at its LFP rate with the same channel names and stimulus.'
```

Replace `t.inputs`:

```matlab
t.inputs = {
    'TDT tank / block folder containing the `Whis` (stimulus) and `xRAW` (raw neural) streams (needs the TDT MATLAB SDK, `TDTbin2mat`, under `Utilities/TDTMatlabSDK/`)'
    'Intan RHD2000 `.rhd` file (file format 1.0–3.x, traditional single-file format)'
    'Open Ephys binary recording folder (GUI 0.5 or later: `structure.oebin`, `continuous.dat`, TTL events)'
    'NWB 2.x `.nwb` file with an ElectricalSeries in /acquisition or /processing'};
```

Append to `t.outputs`:

```matlab
    'NWB `.nwb` (Export NWB…): LFP in volts in /processing/ecephys/LFP, the stimulus in /stimulus/presentation, electrodes with source channel names. Written with matnwb when installed, otherwise an NWB-style export (not validated).'
```

Append to `t.details`:

```matlab
    '## Recording formats'
    '* All sources are read into the same form: raw channels in volts plus a list of candidate stimulus channels, so processing and saving are identical for every format.'
    '* **Intan .rhd**: amplifier channels (0.195 µV per bit); stimulus candidates are the board digital inputs (0/1) and board ADC inputs (volts). The notch-filter setting is shown in the header but not applied.'
    '* **Open Ephys**: headstage channels (value × bit_volts); ADC channels become stimulus candidates; each TTL line becomes a 0/1 stimulus trace at the recording rate. AUX (accelerometer) channels are skipped.'
    '* **NWB**: the first ElectricalSeries (data × conversion); stimulus candidates are stimulus TimeSeries and trial / interval tables, aligned to the series start.'
    '## NWB export'
    '* Without matnwb the file is written by a built-in minimal writer that follows the NWB 2.7 layout but is **not validated** at run time and does not embed the schema. To check a file, run `nwbinspector` or `pynwb.validate` in Python. Subject metadata is not written by the app.'
```

Append to `t.trouble`:

```matlab
    '"not an Intan RHD2000 file: magic number …"', 'The file is not an Intan .rhd data file. Intan stimulation files (.rhs) are not supported.'
    '"holds only a header (no data blocks)"', 'The recording was saved as "one file per signal type" or "one file per channel" (info.rhd + .dat files). Save it in the traditional single-file .rhd format.'
    '"… is not a whole number of … data blocks"', 'The .rhd file is truncated (for example the recording was interrupted). Re-export it from the Intan software.'
    '"No structure.oebin found"', 'Choose the Open Ephys recording folder (…/Record Node */experiment*/recording*) or a folder above it. Only the binary format is supported; for the older "Open Ephys format" (.continuous files), re-save as binary.'
    '"not an HDF5 file" / "without the NWB root attribute nwb_version" / "No ElectricalSeries"', 'The file is not an NWB 2.x file with extracellular data. NWB 1.x files are not supported.'
    'The stimulus channel list shows "(no stimulus channel)"', 'The recording has no digital / analog input, TTL events or stimulus series. LFP / MUA files are still saved, with an all-zero stimulus.'
    'Export NWB says "NWB-style file (not validated)"', 'matnwb is not installed. The file follows the NWB 2.7 layout; install matnwb (github.com/NeurodataWithoutBorders/matnwb) to write it with the official schema classes, or validate it with nwbinspector.'
    'Loading a long recording runs out of memory', 'The whole recording is loaded (as for TDT tanks). Split long recordings, or export a shorter segment from the acquisition software.'
```

Welcome topic (optional): in `t.inputs`, replace the TDT line with `'TDT tank / block folder, Intan .rhd, Open Ephys binary folder or NWB 2.x file (electrophysiology; TDT needs the TDT MATLAB SDK)'`.
