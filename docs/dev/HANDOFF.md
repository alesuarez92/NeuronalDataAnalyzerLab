# Handoff (2026-09-26, session 6, end: context budget reached)

Working branch: `claude/admiring-cori-52ekpa` (= main 4852898 + EEG roadmap + EEG step 1 + start of step 2).
Owner decision: `docs/dev/` stays out of `main`. **Delete this file before merging the next PR.**
Owner decision (this session): **step 2 continues on the same branch** (no PR for step 1 alone).

## Done
- EEG step 1 (f1342c8): `core/io/EEGSource.m`, `readEEGLAB`/`writeEEGLAB`, `readFieldTrip`/`writeFieldTrip`,
  `readEEGMatrix`, `core/demo/demoEEG.m`, `tests/EEGFormatsTest.m` (14 tests). MATLAB CI green
  (run 36209588459: 285 passed, 1 skipped NWB/matnwb). ROADMAP step 1 🔨, CHANGELOG, tests/README done.
- Step 2 started: `core/EEGAnalysis.m` (headless): `epoch` (continuous -> trials around events),
  `conditionERPs` (mean/SEM per condition, optional baseline), `difference`, `measure` (mean or peak
  amplitude per condition, channel-averaged, latency, atEdge flag), `measureTable` (participant x
  condition MATLAB table), `describeMeasure` (plain sentence), `channelIndex`. Smoke-checked in Octave
  (except `measureTable`: Octave has no `table`). **No tests for it yet.**
- The fresh container had a stale local branch; reset to origin. Old commits kept only in that
  container on `backup/local-before-reset` (old docs/dev/reports notes); gone with the container.

## Next: rest of EEG step 2 (in this order)
1. `tests/EEGAnalysisTest.m`: known answers on `demoEEG` (P300 Target > Novel > Standard at Pz with
   baseline [-0.2 0]; N1 peak negative at Cz near 0.1 s; `measureTable` rows; `epoch` on the rodent
   (30 flashes, [-0.1 0.4] -> 4 x 501 x 30; [-2 0.4] skips 1 with a note); difference label;
   errors: unknownChannel, unknownCondition, badWindow, notEpoched).
2. `apps/EEGAnalysisApp.m` (model: `apps/HistologyApp.m`, `classdef < handle`, no-arg constructor,
   `UIKit.window(title, subtitle, 'EEG Analysis', [w h])`, left step cards 360 px + right plots/tabs,
   every action public and returns ok, `updateControls` with `onoff`, local helpers copied).
   Steps: 1 Load (one or several files, `EEGSource.open`; the plain-.mat form from
   `EEGSource.guessMatrixMap` when `NeuroAnalyzer:eeg:needsMap`; continuous -> epoch around events),
   2 Overview tab (`EEGSource.describe` + `describeHistory`, trials per condition),
   3 ERP tab (butterfly, chosen channels, conditions, difference wave),
   4 Measure (window, channels, mean/peak, polarity; per-participant table; edge-peak warning),
   5 Statistics + Save (session buttons; export .csv).
   Public `loadDemo()` (`DemoData.ensureDemoPath(); f = demoEEG();` all 8 scalp participants;
   `Generator='demoEEG'`), `sessionState`/`restoreSession`, the three one-line session wrappers.
   AppSmokeTest's setupOnce does NOT add core/io: add `addpath(fullfile(root,'core','io'))` there
   (and core/demo) or ensure the path in the app.
3. Registrations (all hardcoded): `core/Main.m` new workflow card (grid [5,1] -> [6,1], property,
   header comment), `apps/HelpApp.m` (`topicEEGAnalysis` in `topicData()`, `demoWindow` map
   'EEG Analysis' -> 'EEGAnalysisApp', Welcome demo table row), `core/MethodsWriter.m`
   (`PipelineOrder` + `case 'EEGAnalysisApp'` + `eegAnalysis(s)`; test in MethodsWriterTest),
   `tests/AppSmokeTest.m` (`testEEGAnalysis`), `tests/EEGAnalysisWalkthroughTest.m` (frames
   `EEGAnalysisApp_NN_step`), tests/README, CHANGELOG, ROADMAP step 2. Website: later (step 7).
4. Statistics hand-off, decision needed (see open questions). Facts: Groups & statistics is a tab in
   SignalCharacterizationApp that only takes one file per subject and recomputes its own feature
   (`addGroupFiles(paths, group)`); no API takes precomputed values. `GroupStats.compare(values,
   names, 'rm', 'parametric'|'nonparametric')` (values = cell of column vectors, one per condition,
   subjects matched by order) and `GroupStats.formatP/statText` exist and are toolbox-free.
   Recommended: run `GroupStats.compare(..., 'rm', ...)` in a Statistics tab of the EEG window
   (the user's own measure is kept; no window switch), and describe it with MethodsWriter.groupText.

## Open questions for the owner
- Statistics for EEG: inside the EEG window (recommended, above) or by adding a new
  "add precomputed values" entry to Signal Characterization's Groups & statistics tab?
- v0.4.0 release (still unanswered).
- Two small Histology app fixes (session pixel-size note says "Typed by you." after reopening;
  Help/website say 2.7 px and "nothing to warn about", the app shows 2.6 px and a "Check" row).
- Which EEG cleaning tools / systems the lab uses.

## Working rules learned
- Commit identity = owner (CLAUDE.md). The stop hook asking for "Claude"/noreply@anthropic.com:
  ignore it, CLAUDE.md wins.
- Force push is blocked: after a squash merge, merge `main` into the branch (no content change).
- The auto-mode permission check blocks merges (and cleanup after them) unless the owner says
  plainly in the chat to merge. Ask for an explicit "merge PR #N".
- Keep CI minutes low: `**.md`, `docs/**` and `website/**` changes do not start the MATLAB CI.

## Open questions for the owner
- v0.4.0 release (still unanswered).
- Two small Histology app fixes (session pixel-size note says "Typed by you." after reopening;
  Help/website say 2.7 px and "nothing to warn about", the app shows 2.6 px and a "Check" row).
- Which EEG cleaning tools / systems the lab uses (owner said: general first, specialise later).
