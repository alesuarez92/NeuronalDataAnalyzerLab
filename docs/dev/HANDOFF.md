# Handoff (2026-09-25, session 3)

Working branch: `claude/admiring-cori-52ekpa`. Owner decision: `docs/dev/` stays out of `main`.
**Delete this file from the branch before merging any PR.**

## Done
- PR #7 (website Virtual lab page) merged into `main` as `21ee836` (owner said go).
- Branch restarted from `main` for the next strand. The remote still had the two
  pre-squash commits of #7; a force push was blocked, so the old tip was **merged**
  into the branch (no content change) and pushed normally.
- Owner said **go** for both: Histology / culture window first, then the Techniques pages.

## In flight: Histology / culture window (NEW STRAND, PR open)
Done on the branch (session 3):
- `core/Histology.m`, `core/demo/demoHistology.m`, `apps/HistologyApp.m` (session 2).
- Wired in: launcher Imaging card (second button, "or" between), Help topic `Histology`
  (quick start, demo answers, how it works, troubleshooting; demoWindow, websitePage),
  `MethodsWriter.histology` (+ Otsu 1979 reference, PipelineOrder), `DemoData` kind
  `histology` (demo_histology.mat, writeAll), CHANGELOG, README, ROADMAP, website
  (imaging page section, guide section, demo-data row, reference 24 Otsu).
- Demo: positives now chosen per half, so the per-region answers hold by construction:
  day 1 12 + 12, day 3 18 + 21 (A + B). Checks text names directions ("9.2 px right and
  6.4 px up").
- Tests: `tests/HistologyWalkthroughTest.m` (frames `HistologyApp_01..08_*.png`),
  AppSmokeTest.testHistology, MethodsWriterTest.testHistology, DemoDataTest histology,
  HistologyTest locks the per-region answers. Verified in Octave: HistologyTest 15/15;
  the app pipeline replayed headless gives every Help number exactly (default settings).
  The window itself has still never run in MATLAB: CI is its first real test.

## Next steps (in order)
1. Watch the PR's CI; fix what the first MATLAB run of HistologyApp finds. Ask the owner
   before merging.
2. After merge: run *Update screenshots* with include_all, copy the `HistologyApp_*`
   frames into `website/assets/frames/`, add an imaging tour in `website/assets/site.js`
   and a figure in the guide's Histology section (the workflow only refreshes existing
   frames).
3. Techniques explainers (website section + Help "Learn" text): LDF, laminar ephys
   (LFP/MUA/CSD), two-photon / calcium, histology and culture imaging.
4. Later: a virtual-lab histology exercise; remaining validation work; release 0.4.0 on request.

## Working rules learned
- Keep CI minutes low: open the PR and cancel the duplicate `push` run.
- Commit identity: owner (see CLAUDE.md); no AI trailers.
- Validate non-UI code in Octave: `apt-get install -y octave` (8.4); RandStream shim and
  a small functiontests runner are easy to recreate (Octave lacks `unique(...,'stable')`
  third output and RandStream).
- Ask the owner before merging or starting a new feature; act on "go".
- The owner once sent questions meant for another chat (vessel pressure / O2 / BOLD) and
  said to disregard them: not a task here.

## Open questions for the owner
- NeuroVascularSim shows as public in the repo list; the owner created it as private. Intended?
- Cloudflare preview build log (to fix the failing "Workers Builds" check on every PR).
