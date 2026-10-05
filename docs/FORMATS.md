# Files and functions kept stable from 1.0

From version 1.0 on, the names below keep their meaning. A change that
renames or removes one of them waits for 2.0; new fields, columns and
options may be added in any 1.x release. Tests fail when a listed name
goes missing (`tests/StableFormatsTest.m`, `tests/SessionFeaturesTest.m`,
`tests/SessionWalkthroughTest.m` and the window walkthroughs).

Names written to files use ASCII units (`_uV`, `_ms`, `_um`; Histology:
`(um)`, `(um2)`, `(mm2)`); the windows show µV, ms and µm.

## Session files

`<name>.nasession.mat`, one variable `session` (`core/Session.m`):

| Field | Content |
|---|---|
| `format`, `formatVersion` | `'NeuroAnalyzer session'`, `1` |
| `app`, `appTitle` | window class (e.g. `LFPAnalysisApp`) and its title |
| `toolboxVersion`, `matlabVersion`, `matlabRelease`, `os`, `created` | where and when it was saved (`created`: ISO 8601) |
| `inputs` | one element per input: `role, path, name, isFolder, bytes, modified, md5` |
| `settings`, `results` | the window's settings and results (fields per window: `sessionState` of each app) |
| `summary`, `checks`, `notes` | key results (cellstr), quality checks (`level, topic, found, why, action`), free text |

`Session.load` reads `formatVersion` (missing = 1), upgrades older files
in `Session.upgrade` and refuses a file from a newer format with a message
to update the toolbox. Every format change after 1.0 raises
`Session.FormatVersion` and adds one upgrade step, so older sessions keep
opening.

## Files the windows write

| Window | File | Variables or columns |
|---|---|---|
| Extract LDF | cropped `.mat` | `stim, LDF, t, Fs, flowName, flowUnits, stimName` |
| LDF Process, Batch `ldf`, Laser speckle (Save trials) | trials `.mat` | `segmentedLDF, segmentedTime, Fs` (Laser speckle adds `onsetTimes, roiName, units, source`) |
| Extract Ephys | LFP `.mat` | `lfp_data, lfp_channels, lfp_fs, t_lfp, stim_data, stim_fs, t_stim`; `lfp_spacing_um` when the electrode spacing is given |
| Extract Ephys | MUA `.mat` | `mua_data, mua_channels, mua_fs, t_mua, stim_data, stim_fs, t_stim, filterParams` |
| Extract Ephys | `.nwb` | LFP in `/processing/ecephys/LFP`, stimulus in `/stimulus/presentation` (`core/io/writeNWB.m`) |
| LFP Analysis | `<file>_ERP.mat` | `t, y, erp_avg, erp_std, erp_channels, erp_params, n_epochs, onset_times, lfp_fs, source_file`; with a CSD `csd, csd_channel_order, csd_spacing_um, csd_method, csd_unit, csd_params, csd_depth_um, csd_method_label, csd_grid, csd_grid_depth_um` (kCSD: `csd_kcsd`); TDT files: `erp_tdt_channels` |
| MUA Analysis | `<file>_ch<N>_spikes.mat` (or `_ch<N>_seg<K>_spikes.mat`) | `SpikeResults, SpikeSortParams, clusterQuality, info` |
| Laser speckle | `.csv` / `.mat` | `Time_s`, `FlowChange_pct_<ROI>`, `FlowIndex_<ROI>` / `results` |
| ROI Analysis | `.csv` / `.mat` | `Time_s` and one column per measure and ROI (`<measure>_<ROI>`, e.g. `DFF_Cell_1`, also with one ROI); diameter: `Time_s, Diameter_px` (+ `Diameter_standard_px, Replaced` when robust); kymograph: a matrix, first row time / `results` |
| Histology / culture | `<name>.csv`, `<name>_counts.csv`, `.mat` | `Image, Cell, x (um), y (um), Area (um2), Elongation, Region`, then per marker `<marker> positive, <marker> part of cell (%)` / `Image, Region, Cells, Area (mm2), Cells per mm2`, then `Positive <marker>, % <marker>` (and `All markers positive`) / `results` |
| EEG Analysis | `.csv` / `.mat` | `Participant, Condition, Value_uV, Latency_ms, Trials, PeakAtEdge` / `results` |
| Signal Characterization | features `.csv` / `.mat`; group `.csv` / `.mat` | `Series` and the 9 feature columns (as Batch) / `data, colNames`; `Group, Subject, <feature>` + `<name>_report.txt` / `results` |
| Batch | `<name>_summary.csv`, `<name>_summary.mat`, `<name>_log.txt` | columns `File, Status, Message`, then `Batch.columns(pipeline)`; `.mat`: `summary` (table) and `batch` (`pipeline, params, files, fileStatus, messages, log, created`); LDF with Save trials: a `trials/` folder; **Export…** writes the same two variables to `.mat` (or the table to `.csv` / `.xlsx`) |
| every window with sessions | report `.pdf`, methods `.txt` | one page; plain text |

The 9 feature columns (`Batch.FeatureColumns`): `PeakLatency_s,
OnsetDelay_s, FWHM_s, AUCpos, AUCneg, RiseTime_s, DecayTime_s, PeakAmp,
Integral`.

## Script functions

The functions below keep their names, inputs and the fields of what they
return (each class's header comment lists them in full):

- `GroupStats`: the tests (`ttestPaired`, `ttestWelch`, `anova1way`,
  `wilcoxonSignedRank`, `mannWhitney`, `kruskalWallis`, `rmAnova`,
  `friedman`), `describe`, `shapiroWilk`, `sphericity`, effect sizes,
  `compare(values, names, design, method)` (`design, method, groupNames,
  values, nExcluded, desc, main, check, checkAgrees, comparisons,
  assumptions, summary`), `checkOptions`, `checks`.
- `EEGAnalysis`: `epoch`, `conditionERPs`, `grandAverage`, `difference`,
  `measure` (`condition, value, latency, atEdge, n`), `measureTable`
  (the columns of the window's `.csv`), `timeFrequency`, `filter`,
  `rereference`, `rejectTrials`, `checks`.
- `ERPAnalysis`: `detectOnsets`, `average`, `csd`, `checkOptions`, `checks`.
- `LDFPipeline`: `defaultParams`, `process`, `segment`, `run`, `checks`.
- `MUAPipeline`: `defaultParams`, `sort`, `qualityMetrics`, `checks`.
- `LaserSpeckle`: `defaults`, `contrastSquared`, `analyze`, `checks`.
- `Histology`: `readImage`, `defaultCountOptions`, `countCells`,
  `regionCounts`, `checks`.
- `ImagingChecks`, `PerfusionChecks`: `options`, `run`.
- `QualityChecks`: rows `level, topic, found, why, action` and their helpers.
- `Batch`: `pipelines`, `describe`, `defaults`, `run(pipeline, inputs,
  params, outFolder, Name, Value)` (`pipeline, params, files, summary,
  fileStatus, messages, log, paths, nOK, nWarning, nError, nSkipped,
  cancelled, elapsed, record`), `columns`.
- `Session`, `MethodsWriter` (`fromSession`, `write`), `DemoData`.
- Readers in `core/io`: `EEGSource.open`, `EphysSource.open`,
  `SignalSource.open` and the `read*` functions, with the fields of the
  structs they return. EEG channel positions (`eeg.chanlocs`) carry the
  name as `label` and as `labels` (EEGLAB's field).

Private helpers, the windows' internal properties and the layout of the
windows are not part of this promise.

## Where the readers' file layouts come from

A reader of a company's file format is written only from a format
description that the company publishes (or allows in writing), never from
its software development kit or its own code. Open formats follow their
published specifications. Company and product names here only say which
files are read.

| Reader (`core/io`) | Published description followed |
|---|---|
| `readIntanRHD`, `readIntanRHS` | Intan Technologies' RHD2000 / RHS2000 data file format documents (intantech.com) |
| `readBlackrock` | Blackrock's NEV / NSx file specification (File Spec 2.1-3.0; support.blackrockneurotech.com) |
| `readNeuralynx` | "Neuralynx Data File Formats" (Neuralynx, Inc.; linked from https://support.neuralynx.com/hc/en-us/articles/360040444811) |
| `readSpikeGLX` | SpikeGLX metadata documentation (billkarsh.github.io/SpikeGLX) |
| `readOpenEphysBinary`, `readOpenEphysLegacy` | Open Ephys GUI documentation, data formats (open-ephys.github.io) |
| `readNWB` | NWB 2.x format specification (nwb-schema.readthedocs.io) |
| `readEDF` | EDF (Kemp et al. 1992) and EDF+ (Kemp & Olivan 2003; edfplus.info) |
| `readXDF` | XDF specification (github.com/sccn/xdf) |
| `readEEGBIDS` | BIDS specification, EEG (bids-specification.readthedocs.io) |
| `readNPY` | NumPy `.npy` format specification |

Readers whose layout had no such published description were removed:
Perimed `.dat`, Plexon `.plx`, Axon ABF, AcqKnowledge `.acq` and EGI
`.mff` in 1.0.1; Multi Channel Systems HDF5, Inscopix `.isxd`, ThorImageLS
`.raw`, Bruker Prairie View and UCLA Miniscope folders after 1.0.1. Export
such recordings with the company's own software to a format that is read
(for example NWB, EDF, TIFF or a MATLAB file).
