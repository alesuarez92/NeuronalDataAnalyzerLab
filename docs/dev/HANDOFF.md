# Handoff (2026-09-25, session 2)

Working branch: `claude/admiring-cori-52ekpa`. Owner decision: `docs/dev/` stays out of `main`.
**Delete this file from the branch before merging any PR.**

## Done
- PR #7 (website Virtual lab page) merged into `main` as `21ee836` (owner said go).
- Branch restarted from `main` for the next strand. The remote still had the two
  pre-squash commits of #7; a force push was blocked, so the old tip was **merged**
  into the branch (no content change) and pushed normally.
- Owner said **go** for both: Histology / culture window first, then the Techniques pages.

## In flight: Histology / culture window (NEW STRAND, no PR yet)
Committed on the branch:
- `core/Histology.m` (base MATLAB, runs in Octave): readImage (TIFF pages = channels,
  PNG/JPG, .mat `images` H x W x C x N; pixel size from ImageJ/TIFF tags), background
  (min/max-filter opening), autoThreshold (Otsu, >= 3 robust noise SD), labelComponents
  (run-based union-find, 8-conn), fillHoles, countCells (split touching cells: distance
  map peaks, a lower peak is a new cell only if disconnected from higher peaks in
  D >= SplitNeck*height, default 0.85; pixels assigned by power distance), positive
  (>= MinFraction of the cell above the marker threshold), regionCounts (per polygon,
  per mm2), alignChannels (FFT cross-correlation, ~0.5 px accuracy), alignImagesRigid
  (registerStackRigid on high-passed channel), fitAffine / warpAffine (landmarks),
  checks (plain-language Checks tab rows).
- `core/demo/demoHistology.m`: 2 images (culture day 1 / day 3), 400x400 px at 1 um,
  60 nuclei (6 edge-touching pairs), 24 / 39 marker-positive, 20 debris, 1 fibre,
  illumination, day-3 stage shift [6.4 -9.2], chromatic shift [1 2]. Regions A/B = halves.
- `tests/HistologyTest.m`: 15 tests, all pass in Octave (exact counts, positives,
  per-region counts after alignment, affine, TIFF/.mat loading).
- `apps/HistologyApp.m`: full window (steps 1 Load, 2 Align, 3 Count, 4 Regions and
  markers, 5 Export + session buttons; image with overlays; tabs Counts / Cells / Checks;
  sessions; scriptable API). **Written but never run** (no MATLAB here): expect small
  UI bugs; CI is the first real test.

## Next steps (in order)
1. Integrate the window:
   - `core/Main.m`: Imaging card, second button "Histology / culture" (column 3; move the
     chainNote or shorten it); update the header comment.
   - `apps/HelpApp.m`: topic `Histology` (window uses helpTopic 'Histology'): quick start,
     demo answers (60 nuclei, 30/30 per region, 375 per mm2; positives 24 then 39;
     region A 18 positive on day 3, region B 21; shift 6.4/-9.2; debris 20, fibre 1),
     inputs/outputs, how it works (from the Histology.m header), troubleshooting
     (strongly overlapping nuclei count as one; pixel size; threshold view). Add to
     `topicData`, `demoWindow` ('Histology' -> 'HistologyApp'), `websitePage` ('imaging').
   - `core/MethodsWriter.m`: `histology(s)` paragraph + 'HistologyApp' in PipelineOrder
     and `describe` (settings.count, alignedMethod, regions, pixel size).
   - `core/DemoData.m`: kind 'histology' (demo_histology.mat) in `file` and `writeAll`
     (+ HelpApp generateDemoFiles status text).
   - `tests/AppSmokeTest.m`: testHistology. New `tests/HistologyWalkthroughTest.m`
     (loadDemo, align shift, count, add regions A/B, exportResultsTo csv+mat, session
     save/open, frames `HistologyApp_<NN>_<step>.png`).
   - CHANGELOG `[Unreleased]`, README (window list), website imaging page (text; frames
     come from the Update screenshots workflow after merge), ROADMAP if it lists this.
2. Open the PR (cancel the duplicate push run); fix CI; ask the owner before merging.
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
