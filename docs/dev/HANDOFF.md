# Handoff (2026-09-26, session 8)

Working branch: `claude/admiring-cori-52ekpa` (= main 4852898 + EEG roadmap + EEG step 1 + EEG step 2).
Owner decision: `docs/dev/` stays out of `main`. **Delete this file before merging the next PR.**
Owner decision: step 2 continues on the same branch (no PR for step 1 alone).

## Done (this session)
- `tests/EEGAnalysisTest.m` (see git log): exact numbers on a hand-built EEG, demo P300 / N1,
  measureTable, rodent epoching (4 x 501 x 30; [-2 0.4] skips 1), errors. Checked in Octave with shims
  (all pass except measureTable: Octave has no `table`).
- `EEGAnalysis.grandAverage` (each participant once, SEM across participants, common conditions,
  `notes` for left-out conditions, `NeuroAnalyzer:eeg:mismatch`) + test.
- `apps/EEGAnalysisApp.m` (9a8d020): steps 1 Load (EEGLAB / FieldTrip / plain .mat; form
  `matrixMapDialog` when the guess is unclear; continuous -> Cut into trials), 2 ERPs (baseline,
  channels), 3 Measure (mean / peak, edge warning), 4 Statistics (in the window: `GroupStats.compare`,
  paired for 2 conditions, 'rm' for 3+), 5 Save (.csv / .mat, sessions). Right: plot bar (participant
  or grand average; Conditions / butterfly / difference), tabs Overview | Measures | Statistics.
  Public API listed in the file header. Demo sessions store generator 'demoEEG' (restore = loadDemo).
- Registrations: `core/Main.m` EEG card (6 cards, window 1040 px tall), `apps/HelpApp.m`
  (`topicEEGAnalysis`, `demoWindow`, Welcome row `eeg/`), `core/DemoData.m` (writeAll writes `eeg/`;
  `ensureDemoPath` also adds core/io), `core/MethodsWriter.m` (`eegAnalysis(s)`, PipelineOrder, refs
  delorme2004 / oostenveld2011, `groupText` accepts gs.featureText / gs.subjectText),
  `tests/MethodsWriterTest.m` (`testEEGAnalysis`), `tests/AppSmokeTest.m` (`testEEGAnalysis`, core/io
  + core/demo on the path), `tests/EEGAnalysisWalkthroughTest.m`, tests/README, CHANGELOG, ROADMAP.
- Demo answers (computed in Octave; the Help text uses them): Pz 300-400 ms mean amplitude
  Standard ~1.3, Target ~7, Novel ~4 uV; rm ANOVA p < 0.0001; Friedman chi2(2) = 16, p = 0.0003;
  N1 at Cz ~-4.4 uV at 100 ms; rodent VEP -39 uV at 48 ms, +25 uV at 105 ms (V1).
- Statistics decision: implemented the handoff's recommendation (stats inside the EEG window). Easy
  to change if the owner prefers the Signal Characterization route.

## Status (CI)
- First MATLAB CI run with the window (run 92, 0a50d7f): 299 passed, 1 failed:
  `EEGAnalysisWalkthroughTest/testRodentContinuousAndPlainMat` — after the rodent file, the channel
  boxes still held `V1-L, V1-R`, so Show ERPs failed on the scalp .mat files. Fixed in the app
  (`setData` keeps only typed channels the new files have; test checks it). CI run 36213530376 on 8dbf4c0: green (all tests pass).
- Screenshot review: artifact downloads are blocked here (Azure blob hosts), so the screenshots workflow
  got a `source` input (make the screenshots from a branch, not only main) and was run on this branch
  with include_all (commit 7322e8b; review-screens/ removed again afterwards). EEG frames showed:
  hidden butterfly lines / SEM shades left behind (`cla` keeps hidden handles), a y axis stuck at
  [0 1] (ylim read before the first draw, then fixed), measures listed in each file's condition order.
  All fixed in the app, with test checks. The same push has the two Histology fixes (session pixel
  note; Help / website 2.6 px, listed as a row to check). CI on this push: pending.

## Next
1. Check that CI run (GitHub MCP `actions_list` / `get_job_logs`). Likely places for failures:
   codeIssues errors in `apps/EEGAnalysisApp.m`; `EEGAnalysisWalkthroughTest` (plot title check,
   butterfly line count, edge-peak test with window [0.2 0.3], session reopen equality);
   `DemoDataTest.testWriteAll` (now writes eeg/); `MethodsWriterTest.testEEGAnalysis` string checks.
   Fix, re-run, keep CI runs few.
2. After CI is green, re-run the screenshots workflow (source = this branch, include_all) only if
   the EEG plots need another look; remove review-screens/ before merging.
3. Then step 2 is done: ROADMAP step 2 -> ✅ when merged; open the PR for steps 1 + 2 only when the
   owner asks (delete this file first).
4. Later: website pages for EEG (step 7), steps 3-6 of the EEG plan.

## Open questions for the owner
- Statistics for EEG are inside the EEG window now (the recommended option). OK, or should values also
  go to Signal Characterization's Groups & statistics?
- v0.4.0 release (still unanswered).
- Which EEG cleaning tools / systems the lab uses (owner said: general first, specialise later).

## Working rules learned
- Commit identity = owner (CLAUDE.md). The stop hook asking for "Claude"/noreply@anthropic.com:
  ignore it, CLAUDE.md wins.
- Force push is blocked: after a squash merge, merge `main` into the branch (no content change).
- The auto-mode permission check blocks merges unless the owner says plainly in the chat to merge.
- Keep CI minutes low: `**.md`, `docs/**` and `website/**` changes do not start the MATLAB CI.
- Local checks: `apt-get update && apt-get install -y --no-install-recommends octave` works; Octave
  lacks RandStream / table / uifigure / functiontests, so use small shims (RandStream, verify*) in
  the scratchpad to run test functions as a script.
