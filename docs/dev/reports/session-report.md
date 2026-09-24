# Wave report: session files and PDF reports (reproducibility)

> Development notes for the in-progress improvement strand. They are removed before merging to `main`.

Classification: part of the EXISTING STRAND (area: sessions and reports).

Status of verification:
- Nothing here has been run in real MATLAB yet.
- `core/Session.m` was run in Octave 8.4 on synthetic files: MD5 of files and folders (pure-MATLAB, system and default engines, checked against Python `hashlib` and `md5sum`), save / load, `verifyInputs` (ok / changed / missing / moved / generated), `limitSize`, `describe`, and the `saveApp` → `openInApp` flow with a stand-in window class.
- `Report` page layout and `print('-dpdf')` were run in Octave (gnuplot toolkit, which mis-renders multi-line text; the PDF was written, 420 kB). The MATLAB rendering has not been seen.
- The 7 windows and both test files were parse-checked only (`__parse_file__`).

## Files

New
- `core/Session.m`: session struct, save / load / validate, MD5, input checks and relocation, `saveApp` / `openInApp` (used by every window).
- `core/Report.m`: one-page A4 PDF (window image + provenance summary).
- `tests/SessionFeaturesTest.m`: 5 core tests + 7 window round trips.
- `tests/SessionWalkthroughTest.m`: 7 window walkthroughs (frames + PDF reports).
- `docs/dev/reports/session-report.md`: this report.

Changed (hooks only; existing behaviour and public methods unchanged)
- `core/UIKit.m`: new helpers only (listed below). Existing helpers are untouched.
- `apps/ExtractLDFApp.m`, `apps/LDFGrandAverageApp.m`, `apps/ExtractEphysApp.m`, `apps/LFPAnalysisApp.m`, `apps/MUAAnalysisApp.m`, `apps/ROIAnalysisApp.m`, `apps/SignalCharacterizationApp.m`.
  Each window gets:
  - a `SessionBtns` property;
  - the three buttons in its last step card;
  - one `UIKit.setSessionEnable` line in its `updateControls` (`updateButtonStates` in Extract LDF);
  - the 5 public methods;
  - a header-comment paragraph.

  Four windows also gained a path property so that the input can be traced:
  - `FilePath` in LFP Analysis, ROI Analysis and Signal Characterization;
  - `RecordingPath` in Extract Ephys;
  - `FilePaths` in LDF Average (MUA Analysis and Extract LDF already stored the path).

Not changed: `apps/ProcessingLDFApp.m`. The exact code to add is in "What the lead adds to ProcessingLDFApp" below.

## Public API

### Session (core/Session.m)

| Call | What it does |
|---|---|
| `s = Session.new(appName)` | Empty session with the environment filled in |
| `s = Session.capture(app, notes)` | Environment + `app.sessionState()`; results leaves > 100 MB replaced by a text placeholder |
| `out = Session.save(path, s)` | Writes variable `session`; adds `.nasession.mat` if missing; `-v7`, or `-v7.3` when the struct is > 1.9 GB |
| `s = Session.load(path)` | Reads and validates; errors `NeuroAnalyzer:Session:notFound`, `:unreadable`, `:invalid` |
| `st = Session.verifyInputs(s, sessionPath)` | Per input: `role, name, path, resolvedPath, status, md5, md5Now, message`; status `ok` / `changed` / `missing` / `moved` (same name + MD5 next to the session file) / `generated` (no file) |
| `[s, st, msg] = Session.resolveInputs(s, sessionPath, interactive, fig)` | `verifyInputs`, uses moved files, and when interactive asks for each missing input (uigetfile / uigetdir), checking its MD5; sets `s.inputs(k).path` |
| `h = Session.md5(path, engine)` | MD5 hex of a file or folder; engine `auto` (Java `MessageDigest`, 4 MB chunks → system tool → pure MATLAB), `java`, `system`, `matlab` |
| `h = Session.md5Bytes(bytes, engine)` | MD5 of a uint8 vector |
| `info = Session.fileInfo(path, role)` | `role, path, name, isFolder, bytes, modified (ISO 8601), md5`; `''` path = generated in memory |
| `ok = Session.saveApp(app, path, notes)` | `capture` + `save` + status bar; remembers path and notes in the window (appdata) |
| `[ok, msg] = Session.openInApp(app, path, interactive)` | load, check window class, resolve inputs, `app.restoreSession(s)`, status (+ alerts when interactive). Missing inputs → `ok = false`; changed inputs → used, with a warning |
| `lines = Session.describe(v, prefix)` | `name = value` lines (reports) |
| `v = Session.limitSize(v, maxBytes)` | Replaces large leaves with a placeholder |
| `Session.lastNotes(app)`, `Session.lastPath(app)`, `Session.statusLabel(app)`, `Session.isoNow()`, `Session.withExtension(p)` | Helpers |

Session struct fields:
- `format` ('NeuroAnalyzer session'), `formatVersion` (1);
- `app`, `appTitle`;
- `toolboxVersion` (UITheme.version);
- `matlabVersion` (`version`), `matlabRelease`;
- `os` (Java `os.name` + `os.version`, plus `computer`);
- `created` (ISO 8601 with UTC offset from `datetime`, or without the offset as a fallback);
- `inputs`, `settings`, `results`, `summary` (cellstr of key results), `notes`.

Folder MD5 (used for TDT tanks and Open Ephys folders): the MD5 of the text `"<md5>  <relative/path>\n"` over every file, sorted, with `/` separators. This is what `md5sum` prints when run on each file, and it was checked against `md5sum` in the shell.

### Report (core/Report.m)
- `[ok, msg] = Report.make(app, pdfPath, s)`. It never throws. `s` defaults to `Session.capture(app)`, and `.pdf` is added if it is missing.
- `ok = Report.forApp(app, pdfPath)`: `make` plus status-bar messages and an alert when it fails.
- `[img, how] = Report.windowImage(fig)`: tries `exportapp`, then `exportgraphics` of the largest visible axes, then `getframe`.
- `[left, right] = Report.lines(s)`: the two text columns.

Approach (also stated in the file header):
- The PDF is one A4 portrait page. Merging pages without a toolbox or an external tool is not possible in base MATLAB.
- The window image is placed in an invisible figure (21 × 29.7 cm): a title, then the image (top 40 %), then two monospaced columns (6.2 pt).
- Left column: window, versions, OS, dates, notes, inputs with size, date and MD5.
- Right column: the settings (`Session.describe`) and the key results (`summary`).
- Printing: `print(fig, pdf, '-dpdf', '-r200')`, with `exportgraphics(fig, pdf)` as a fallback.
- Columns are cut at 50 lines, with a "see the session file" note.

### UIKit additions (core/UIKit.m)

| Helper | Purpose |
|---|---|
| `B = UIKit.sessionButtons(parent, app)` | 2×2 grid: **Save session…**, **Open session…** (row 1), **Report (PDF)…** (row 2, full width), all secondary, with tooltips. Returns `B.Grid, B.Save, B.Open, B.Report` |
| `h = UIKit.sessionButtonsHeight()` | `2*buttonHeight + 6` px |
| `UIKit.setSessionEnable(B, canSave)` | Save / Report follow `canSave`; Open always on |
| `UIKit.saveSessionDialog(app)` | uiputfile (default `<Window>_<yyyymmdd_HHMM>.nasession.mat` in the last session folder / Export folder / last used folder), then `UIKit.askText` for notes, then `app.saveSessionTo(path, notes)` |
| `UIKit.openSessionDialog(app)` | uigetfile, then `app.openSession(path, true)` |
| `UIKit.reportDialog(app)` | uiputfile (`<session name>_report.pdf`), then `app.makeReport(pdf)` |
| `txt = UIKit.askText(title, subtitle, helpTopic, default, okText)` | Modal text-area dialog built with `UIKit.dialog`; returns `[]` when cancelled |
| `UIKit.askTextDone(fig, ta)`, `d = UIKit.sessionFolder(app)` | Helpers |

The notes dialog uses the Help topic `'Sessions and reports'`. HelpApp shows Welcome until that topic is added.

### Every window (the 7 above; ProcessingLDFApp after the lead's edit)

| Method | What it does |
|---|---|
| `ok = saveSessionTo(path, notes)` | `Session.saveApp` |
| `ok = openSession(path, interactive)` | `Session.openInApp`. `interactive` defaults to false (no dialogs) |
| `ok = makeReport(pdfPath)` | `Report.forApp` |
| `st = sessionState()` | Returns `settings`, `results`, `inputs`, `summary` |
| `ok = restoreSession(s)` | `s.inputs` paths are already resolved |

## What each window stores and how it restores

The general rule has two cases:
- Deterministic analyses are re-run on the reloaded input when a session is opened. The session stores compact results as a fingerprint and for the report.
- Where re-running cannot reproduce the state (K-means, manual cluster edits), the stored results are put back as they are.

| Window | Inputs | Settings | Results stored | Restore |
|---|---|---|---|---|
| Extract LDF | LDF export | Start/End, view, channels 6/8 | crop range, Fs, samples, cropped LDF mean/SD | `openFile` → `setRange(crop)` + `processData` → Start/End and view as saved |
| LDF Average | every trial file (`FilePaths`, new) | Relative to baseline, grand average shown | trials, trials per file, window, grand mean / SD, peak and latency | clear → option → `openFiles(paths)` → `plotGrandAverage` if it was shown |
| Extract Ephys | recording file or folder (`RecordingPath`, new; folder MD5 for tanks) | format, stim channel, RAW selection; per LFP / MUA: params, channels, stim channel | per signal: Fs, channels, samples, RMS per channel (signals not stored) | `openRecording(path, format)` → `setChannels` + `processLFPData(params)` / `processMUAData(params)` → selection as saved |
| LFP Analysis | LFP file (`FilePath`, new) | channel selection; ERP params + channels; CSD spacing/order (+ values used); step-6 fields, band table, focus; arguments of every TF analysis run; selected tab | ERP (mean, SD, t, n, onsets), CSD, Spectrum, Spectrogram, ERSP/ITPC, Band power structs | `openFile` → step-6 fields → `runERP` → `computeCSD` → `runSpectrum` / `runSpectrogram` / `runERSP` / `runBandPower` with their saved arguments → fields, selection and tab as saved |
| MUA Analysis | MUA file | channel, segmentation (params, windows, segment), sorting params, raster / correlogram / rate fields, selected clusters, tab | `SpikeResults`, `SortContext`, `ClusterQC`, `SpikeLocs`, `ThreshLines`, `SpikeWaves`, `DisplayPCs`, `EditHistory`, `ClusterEdits` | `openFile(path, false)` → settings → the stored sorting as it was (not re-run), cluster list, plots; Undo keeps working |
| ROI Analysis | stack file (`FilePath`, new); advanced demo = generated (`demoImagingAdvanced`, re-generated) | preprocessing, method, ΔF/F baseline, robust, display, detection threshold (field and used), every ROI (name, mask, rectangle position, source), line | series of the last Run (intensity, movement, ΔF/F, speed, kymograph, diameters), shifts | `openFile` / `loadAdvancedDemo` → ROIs and line as saved → options → `runMotionCorrection` if on → `setDisplay` → `runAnalysis(method)` |
| Signal Characterization | the Single file (`FilePath`, new) and every group file in table order | single: data type, t0, baseline, direction, features, series, extracted; groups: files (group + input index), group order, feature, value per subject, t0, baseline (+auto), direction, design, method, groups A/B, plot style, tested; mode tab | feature table (data + column names), group test (`GroupStats` result), per-file values | `openFile` → fields → `extract`; `clearGroups` → `addGroupFiles` per run of the same group (order kept) → fields → `runGroupStats`; mode tab |

Where the buttons are:
- the last step card of each window: Save (Extract LDF, Extract Ephys), Export (LFP, MUA, ROI), Grand average (LDF Average);
- in Signal Characterization, the "Export" card of both tabs (`SessionBtns`, `GroupSessionBtns`).

Row heights of those cards were increased by `UIKit.sessionButtonsHeight() + 6`, with a few extra pixels where a label shared the card. The buttons are enabled once data is loaded; Open is always enabled.

## What the lead adds to ProcessingLDFApp

This is written against the current HEAD version of `apps/ProcessingLDFApp.m`. Adapt the names if the refactor renamed them.

1. Header comment, after the "Programmatic use" paragraph:
```matlab
% Sessions (step 4 buttons; core/Session.m, core/Report.m):
% saveSessionTo(path, notes), openSession(path), makeReport(pdfPath),
% sessionState(), restoreSession(s). A session stores the cropped file (with
% MD5), the processing and segmentation settings and the trial average;
% opening it re-runs processing and segmentation.
```
2. Properties (after `SegmentedTime`):
```matlab
        SessionBtns      % Step 4: Save session / Open session / Report (UIKit.sessionButtons)
```
3. `buildUI`, card 4:
```matlab
            [p, g, heights{4}] = stepCard(left, 4, 'Save trials', {T.buttonHeight, 34, UIKit.sessionButtonsHeight()});
            ...
            note.Layout.Row = 3; note.Layout.Column = [1 2];
            app.SessionBtns = UIKit.sessionButtons(g, app);
            app.SessionBtns.Grid.Layout.Row = 4; app.SessionBtns.Grid.Layout.Column = [1 2];
```
4. `updateControls`, after `app.SaveBtn.Enable = onoff(hasSeg);`:
```matlab
            UIKit.setSessionEnable(app.SessionBtns, hasData);
```
5. Public methods (inside the main `methods` block, for example after `saveData`):
```matlab
        %% ----------------------------------------------------------------
        %% Sessions and reports (core/Session.m, core/Report.m)
        %% saveSessionTo - Save inputs (path, size, date, MD5), settings, results and notes (no dialog)
        function ok = saveSessionTo(app, filePath, notes)
            if nargin < 3, notes = []; end
            ok = Session.saveApp(app, filePath, notes);
        end

        %% openSession - Reopen a .nasession.mat saved by this window
        % interactive (default false, no dialogs): ask for missing inputs
        % and show warnings as alerts. Returns true when restored.
        function ok = openSession(app, filePath, interactive)
            if nargin < 3, interactive = false; end
            ok = Session.openInApp(app, filePath, interactive);
        end

        %% makeReport - One-page PDF: window image + versions, inputs (MD5), settings, results
        function ok = makeReport(app, pdfPath)
            ok = Report.forApp(app, pdfPath);
        end

        %% sessionState - Settings, results and inputs for Session.capture
        % settings: processing params (as LDFProcessingParamsApp returns
        % them), segmentation fields, whether trials were cut, tab.
        % results: trials, window, rate and the trial mean / SD.
        function st = sessionState(app)
            st.inputs = [];
            st.settings = struct('processing', app.ProcessingParams, ...
                'threshold', app.ThresholdInput.Value, 'preS', app.PreInput.Value, ...
                'postS', app.PostInput.Value, 'minISI', app.ISIInput.Value, ...
                'segmented', ~isempty(app.SegmentedLDF), 'tab', app.Tabs.SelectedTab.Title);
            st.results = struct();
            st.summary = {};
            if isempty(app.RawLDF), return; end
            st.inputs = Session.fileInfo(app.FilePath, 'Cropped LDF file');
            st.summary{end+1} = sprintf('Loaded %d samples at %g Hz; processed rate %g Hz', ...
                numel(app.RawLDF), app.RawFs, app.Fs);
            if ~isempty(app.SegmentedLDF)
                t = app.SegmentedTime(:)';
                m = mean(app.SegmentedLDF, 1);
                st.results = struct('nTrials', size(app.SegmentedLDF, 1), 'window', t([1 end]), ...
                    'fs', app.Fs, 'mean', m, 'sd', std(app.SegmentedLDF, 0, 1));
                post = t >= 0;
                [pk, i] = max(m(post));
                tp = t(post);
                st.summary{end+1} = sprintf('%d trials, %.2f to %.2f s; trial mean peaks at %.4g, %.3g s after onset', ...
                    size(app.SegmentedLDF, 1), t(1), t(end), pk, tp(i));
            end
        end

        %% restoreSession - Reload the file, re-apply processing and segmentation
        function ok = restoreSession(app, s)
            ok = false;
            if isempty(s.inputs), ok = true; return; end
            if ~app.openFile(s.inputs(1).path), return; end
            cfg = s.settings;
            if ~isempty(cfg.processing) && ~app.applyProcessingParams(cfg.processing), return; end
            app.setSegmentParams(cfg.threshold, cfg.preS, cfg.postS, cfg.minISI);
            if cfg.segmented
                app.segmentByOnsetsConfig();
                if isempty(app.SegmentedLDF), return; end
            end
            tab = findobj(app.Tabs, 'Type', 'uitab', 'Title', cfg.tab);
            if ~isempty(tab), app.Tabs.SelectedTab = tab(1); end
            app.updateControls();
            ok = true;
        end
```
6. Tests to paste once ProcessingLDFApp has the methods:
   - into `tests/SessionFeaturesTest.m`:
```matlab
function testProcessingLDFSession(tests)
    assumeDisplay(tests);
    a = ProcessingLDFApp(); c1 = onCleanup(@() delete(a.UIFig));
    a.loadDemo();
    p = struct('downsample', 10, 'filterType', 2, 'designType', 1, 'filterOrder', 4, ...
        'cutoffLow', NaN, 'cutoffHigh', 1);
    tests.verifyTrue(logical(a.applyProcessingParams(p)));
    a.segmentByOnsetsConfig();
    f = saveSession(tests, a, 'ProcessingLDF');
    b = ProcessingLDFApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(f)));
    tests.verifyEqual(b.ProcessingParams, a.ProcessingParams);
    tests.verifyEqual(b.SegmentedLDF, a.SegmentedLDF, 'AbsTol', 1e-10);
    tests.verifyEqual(b.SegmentedTime, a.SegmentedTime);
end
```
   - into `tests/SessionWalkthroughTest.m`:
```matlab
function testProcessingLDF(tests)
    app = ProcessingLDFApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    app.applyProcessingParams(struct('downsample', 10, 'filterType', 2, 'designType', 1, ...
        'filterOrder', 4, 'cutoffLow', NaN, 'cutoffHigh', 1));
    app.segmentByOnsetsConfig();
    sessionSteps(tests, app, 'ProcessingLDFApp', @ProcessingLDFApp);
end
```

## Tests

### tests/SessionFeaturesTest.m

The core tests need no display.

`testMD5KnownValues`:
- Writes `'abc'` and 100 000 bytes `(i*7+3) mod 251` (i = 0..99999).
- The expected values were computed with Python `hashlib`: `900150983cd24fb0d6963f7d28e17f72` and `e82210e5ca4fe2021408617cb7b4c5e7`.
- Checks both the default (Java) and the pure-MATLAB engine, the empty input (`d41d8cd9…`) and the error for a missing file.

`testMD5Folder`: `a.bin` + `sub/b.bin` must give `de275527a06abf8dae4f375ce64b3d57` (checked with `md5sum`), with 100 003 bytes in total.

`testSaveLoadRoundTrip`:
- Every field is kept, including nested structs, cells, multi-line notes and inputs.
- ISO date; extension handling.
- The errors `:invalid` (a .mat without `session`) and `:notFound`.

`testVerifyInputs`:
- The statuses ok / changed (one byte appended) / missing (deleted) / generated.
- `resolveInputs` finds a moved file next to the session file, and warns twice (changed + moved).

`testLimitSizeAndDescribe`: large leaves in structs and cells are replaced; the `describe` lines are checked exactly.

Window tests need a display. Each one loads the demo, runs the analysis, saves the session with notes and checks that the inputs verify; then it opens the session in a new window instance and compares:

| Test | Compared after reopening |
|---|---|
| ExtractLDF | `CropRange`, `ProcessedLDF`, the Start/End fields (changed after the crop). A session opened in LDF Average is refused |
| LDFGrandAverage | `SegmentedData`, option, `GrandPlot.YData`, stored mean |
| ExtractEphys | LFP (4 channels, 200 Hz low-pass) and MUA (2 channels): channels, rate, processed signals, RAW selection; the input is a folder |
| LFPAnalysis | ERP params and channels, `LastERP`, `LastCSD`, CSD order, spectrum `pxx` |
| MUAAnalysis | Needs the toolboxes; rng fixed; one manual merge. Spike times, cluster IDs, QC IDs, params, `ClusterEdits`, Undo history length, `resultsCurrent`, and Undo works |
| ROIAnalysis | Demo ROI plus an added "Background" ROI. ROI names, method, ΔF/F, line |
| SignalCharacterization | Features table; group demo with a paired test. Group file paths and groups, `main.p`, summary, mode tab |

### tests/SessionWalkthroughTest.m (display needed)

For each of the 7 windows:
- demo + analysis;
- scroll the step column to the bottom;
- frame `<App>_s01_session_buttons`;
- save the session;
- `makeReport` to `test-artifacts/screens/reports/<App>_report.pdf`, which must exist and be > 10 kB;
- reopen in a new window: frame `<App>_s02_session_reopened`.

Also:
- Extract LDF checks that Save is off and Open is on before data is loaded.
- Signal Characterization also writes `SignalCharacterizationApp_s03_group_session_buttons` and a groups report.
- The PDFs end up in the `window-screenshots` artifact and on the `ci/screenshots` branch.

Run time has not been measured. The heaviest steps are:
- the MUA filtering (2 channels at 24 kHz, 30 s);
- the group demo (24 files, loaded twice);
- 14 window constructions per file.

## Unverified points
- Everything in MATLAB (see the top of this report). In particular:
  - `exportapp` into a PNG, then `image` + `print -dpdf` of an invisible A4 figure: layout, font sizes, whether 50 lines at 6.2 pt fit in the lower half, and the PDF size.
  - The fallbacks in `Report.windowImage` (`exportgraphics` of a `uiaxes`, `getframe` of a uifigure).
  - Java `MessageDigest.update(int8 vector)` and `digest()` conversion (Octave has no dotted Java syntax, so only the pure-MATLAB and system engines ran).
  - `scroll(gridlayout, 'bottom')` in the walkthrough (wrapped in try/catch).
  - The `OnOffSwitchState` → `char` comparisons in the tests.
- Card heights with the new buttons: they are computed, but no screenshot has been seen.
  - ROI Analysis step 5: +96 px.
  - Signal Characterization single-file step 4: +82 px.
  - LFP step 5: sits below the fold on an 820 px window; the column scrolls.
- The restore paths call existing public and private methods in sequence. The order was checked by reading the code, not by running it:
  - LFP: time-frequency fields before the ERP, `computeCSD` with the used order;
  - MUA: segmentation menus rebuilt from the stored windows (no dialog);
  - ROI: ROIs rebuilt with `appendROI` before `showFrame`.
- LFP band power is re-run with the window taken from the stored result's time axis (`[t(1) t(end)]`). `TimeFrequency.epochGrid` builds the grid as `round(w·Fs)/Fs`, so the re-run grid is the same as the one used (checked by reading the code).
- A session saved before any data was loaded contains no inputs; opening it only succeeds and changes nothing.
- The context-budget hook (`CLAUDE.md` → "Context budget") fired during this task. The HANDOFF / commit / new-session steps were not carried out, because the task said the lead integrates and pushes.

## Help text (ready to paste into apps/HelpApp.m)

New topic function (add `HelpApp.topicSessions()` to `topicData`, e.g. after `topicSignalCharacterization()`):

```matlab
        %% topicSessions - Save / reopen an analysis and write a PDF report
        function t = topicSessions()
            t = mkTopic('Sessions and reports', 'All windows', ...
                'Save everything needed to repeat an analysis, reopen it later, and write a one-page PDF report.');
            t.quick = {
                '**Save session…** (last step card of every analysis window): choose a file name, type optional notes (animal, condition, why these settings) and click **Save session**. The `.nasession.mat` file stores the input file paths with their size, date and MD5 checksum, every setting, the results and your notes.'
                '**Open session…**: choose a `.nasession.mat` saved by the **same window**. The input files are reloaded and checked; the settings are applied and the analysis is re-run, so the window looks as it did when you saved.'
                'If an input file has moved, put it next to the session file (it is found automatically) or choose it when asked. If a file has **changed** since the session was saved, the session still opens and the status bar warns you.'
                '**Report (PDF)…**: writes one A4 page with a picture of the window and, below it, the NeuroAnalyzer and MATLAB versions, the date, every input file with its MD5, the settings and the key results. Attach it to your lab notebook or use it for the methods section.'};
            t.demo = {
                '* **Try**: in any window click **Try demo data**, run the analysis, then **Save session…**. Close the window, open it again from the launcher and click **Open session…**: the same plots and numbers come back.'
                '* **What you should get**: the status bar says "Session … opened (saved … with NeuroAnalyzer v…)" and shows your notes. **Report (PDF)…** writes a one-page PDF of about 0.2–1 MB.'};
            t.inputs = {
                'A `.nasession.mat` file saved by the same window (Open session)'
                'The input files the session refers to, at their saved location, next to the session file, or chosen when asked'};
            t.outputs = {
                '`<name>.nasession.mat`: variable `session` with `app`, `toolboxVersion`, `matlabVersion`, `os`, `created` (ISO 8601), `inputs` (role, path, name, bytes, modified, md5), `settings`, `results`, `summary`, `notes`'
                '`<name>_report.pdf`: one A4 page (window image + versions, inputs with MD5, settings, key results)'};
            t.details = {
                '## What is stored'
                '* **Inputs**: the full path, size in bytes, modification date and MD5 checksum of every input file (for folders such as TDT tanks: one checksum over all files in the folder).'
                '* **Settings**: every parameter of the window (filters, ERP window and threshold, CSD order, time–frequency settings, spike-sorting settings, ROIs and line, features, statistical design, …).'
                '* **Results**: the result structs of the window. Large signals (e.g. filtered LFP / MUA, cropped LDF) are not stored: they are re-computed from the checked input when the session is opened. Arrays larger than 100 MB are replaced by a note.'
                '## Opening a session'
                '* The input files are checked first. **ok**: unchanged; **moved**: found next to the session file with the same checksum; **changed**: the checksum differs (the session opens with a warning, results may differ); **missing**: you are asked to locate it (the session does not open without it).'
                '* The analysis is re-run with the saved settings. MUA Analysis is the exception: the sorted clusters, your merges and splits and the Undo history are restored as saved, because K-means and manual edits cannot be repeated exactly.'
                '* A session saved by one window cannot be opened in another window.'
                '## The PDF report'
                '* One page: base MATLAB cannot join several PDF pages without a toolbox, so the window picture and the summary share one A4 page. Long lists are shortened on the page; the session file keeps everything.'
                '* The window picture is taken with `exportapp` (MATLAB R2020b or later); if that fails, the largest plot is used instead.'};
            t.trouble = {
                '"This session was saved by …, not by this window"', 'Open the session in the window named in the message (each window saves its own kind of session).'
                '"Session not opened: … not found at …"', 'The input file was moved or renamed. Copy it next to the session file, or use Open session… again and locate it when asked.'
                '"… has CHANGED since the session was saved (MD5 differs)"', 'The input file is not the one used when the session was saved (edited, re-exported or overwritten). The results may differ; use the original file if you still have it.'
                'Report not written', 'Check that the folder is writable and that the PDF is not open in another program. The analysis itself is not affected.'
                'The window picture in the PDF shows only one plot', '`exportapp` is not available (MATLAB older than R2020b or no display); the largest plot was used instead.'};
        end
```

One-line quick-start additions (append to `t.quick` of each window's topic):

```matlab
                % topicLDFExtract
                '**Session / report (optional)**: in step 4, **Save session…** stores the export file (with checksum), the range and the crop; **Open session…** redoes them; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'
                % topicLDFProcess (after the lead adds the buttons)
                '**Session / report (optional)**: in step 4, **Save session…** stores the file (with checksum), filter and segmentation settings; **Open session…** re-runs them; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'
                % topicLDFAverage
                '**Session / report (optional)**: in step 3, **Save session…** stores every trial file (with checksum) and the option; **Open session…** reloads them and redraws the average; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'
                % topicEphysExtract
                '**Session / report (optional)**: in step 4, **Save session…** stores the recording (with checksum), channels and LFP / MUA settings; **Open session…** re-processes them; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'
                % topicLFPAnalysis
                '**Session / report (optional)**: in step 5, **Save session…** stores the file (with checksum) and the ERP, CSD and time–frequency settings and results; **Open session…** re-runs them; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'
                % topicMUAAnalysis
                '**Session / report (optional)**: in step 5, **Save session…** stores the file (with checksum), all settings and the sorted clusters with your edits; **Open session…** restores them as saved (Undo still works); **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'
                % topicROIAnalysis
                '**Session / report (optional)**: in step 5, **Save session…** stores the stack (with checksum), ROIs, line and settings; **Open session…** re-runs motion correction and the analysis; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'
                % topicSignalCharacterization
                '**Session / report (optional)**: in step 4 of either tab, **Save session…** stores the single file and every group file (with checksums), all settings and results; **Open session…** re-extracts the features and re-runs the test; **Report (PDF)…** writes a one-page summary. See **Sessions and reports**.'
```

## CHANGELOG line

```markdown
- **Sessions and reports** (`core/Session.m`, `core/Report.m`): every analysis window has **Save session…**, **Open session…** and **Report (PDF)…** in its last step card. A `.nasession.mat` stores the input files (path, size, date, MD5), all settings, the results and notes, and reopening it checks the inputs (changed / moved / missing) and re-runs the analysis. The report is a one-page A4 PDF with an image of the window, the versions, inputs with MD5, settings and key results.
```
