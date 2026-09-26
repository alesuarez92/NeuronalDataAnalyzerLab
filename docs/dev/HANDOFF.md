# Handoff (2026-09-26, session 8, end: context budget reached)

Working branch: `claude/admiring-cori-52ekpa` (= main ecd76ff, v0.4.0, + merge commit + BrainVision draft).
Owner decision: `docs/dev/` stays out of `main`. **Delete this file before merging the next PR.**

## Done (this session)
- EEG window CI fixes and screenshot review (plot clearing, y range, measure row order), Histology fixes.
- PR #10 merged (squash, ecd76ff): EEG steps 1-2. **v0.4.0 released**
  (https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.4.0).
- Screenshots workflow has a `source` input (make screenshots from an unmerged branch; run with
  include_all to get them committed under review-screens/ — artifact downloads are blocked in this
  environment; remove review-screens/ afterwards).

## Owner decisions (this session)
- EEG statistics stay only inside the EEG window.
- Keep EEG compatible with many systems; the owner's lab uses "Brain Lab" (asked whether that means
  Brain Products / BrainVision; the owner answered "Go", taken as yes — confirm when convenient).

## In flight: NEW STRAND "EEG raw formats, BrainVision first" (session 8, continued at the owner's request)
- BrainVision read and wired in: `core/io/readBrainVision.m`, `writeBrainVision.m`, `EEGSource`
  ('brainvision'; .vmrk / .eeg point to the .vhdr), EEG window load filter and tooltip, Help,
  `demoEEG` (cacheVersion 2: scalp Analyzer export float32 with positions; rodent Recorder INT_16
  0.1 uV, 'S  1' markers, ref Cb, amplifier table), `EEGFormatsTest` (demo, hand-built Recorder /
  Analyzer / ASCII headers, writer round trip, detect), `EEGAnalysisWalkthroughTest` (loads the
  BrainVision copy), ROADMAP, CHANGELOG [Unreleased], tests/README.
- Checked locally in Octave (shims for verify* / RandStream / DemoData): all BrainVision tests pass.
  Fixed on the way: `strsplit` collapses ',,' by default (use 'CollapseDelimiters', false);
  Octave needs Latin-1 decoded with native2unicode and no char(956) literal.
- MATLAB CI on this push: pending.

## Next
1. Check that CI run; fix if red.
2. Open the PR for BrainVision when the owner asks (delete this file first).
3. Then, per ROADMAP: EDF / BDF reader, or step 3 (electrode layouts), as the owner prefers.

## Open questions for the owner
- "Brain Lab" = Brain Products (BrainVision Recorder / Analyzer)? Continuous Recorder files,
  Analyzer exports, or both? A sample .vhdr/.vmrk (no data needed) would help test real headers.

## Working rules learned
- Commit identity = owner (CLAUDE.md). The stop hook asking for "Claude"/noreply@anthropic.com:
  ignore it, CLAUDE.md wins.
- Force push is blocked: after a squash merge, merge `main` into the branch (no content change).
- Keep CI minutes low: `**.md`, `docs/**` and `website/**` changes do not start the MATLAB CI;
  `[skip ci]` in a commit message skips it too.
- Artifact downloads (Azure blob hosts) are blocked; use the screenshots workflow with a `source`.
- `send_later` / new sessions may fail here: session lineage depth limit reached.
