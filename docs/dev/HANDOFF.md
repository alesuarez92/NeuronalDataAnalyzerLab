# Handoff (2026-09-25, session 4, end)

Working branch: `claude/admiring-cori-52ekpa`. Owner decision: `docs/dev/` stays out of `main`.
**Delete this file and `review-screens/` from the branch before merging.**

## Done this session
- Cloudflare "Workers Builds" red check: cause was the Previews Base preview command
  `npx wrangler preview`; the owner turned **Builds for Preview branches off** (saved).
  Production (`npx wrangler deploy` on `main`) works. New PRs get no Cloudflare check.
- PR #8 (Histology / culture window) squash-merged into `main` as `4d02d54` (MATLAB CI green).
- Owner answers: NeuroVascularSim being public is intended; it is a separate project, leave it.
  "Website link in the launcher": owner said "That's fine" (ambiguous; not done, don't do unasked).
- Owner asked: "Add the worth adding features to the website like it was before, but now only
  the ones missing" and then "Update it and publish" = finish this website PR, merge, publish.

## In flight: website update (no PR open yet)
Branch = main + merge commit + commit `6563c9e` (text, done) + CI screenshot commit `e7d3a1c`
(82 refreshed website frames, README launcher image, and `review-screens/` with every screenshot).
Done in `6563c9e`:
- ephys.html: iCSD / kCSD text (refs 25, 26), which method, accuracy numbers, export fields,
  `<div data-tour="csd">` slot after the LFP walkthrough.
- features.html: repeated-measures table row (refs 27–31), sphericity / Friedman text replacing
  the wrong "not available" note, RM demo expectations, `<div data-tour="rm">` slot.
- imaging.html: `<div data-tour="histology">` slot in #histology; meta description.
- guide.html: CSD and design quick-start steps and troubleshooting rows from HelpApp;
  Histology figure (HistologyApp_05_regions) in a `.two` layout.
- references.html: refs 25–31 (Pettersen 2006, Potworowski 2012, Mauchly 1940,
  Greenhouse–Geisser 1959, Huynh–Feldt 1976, Holm 1979 (JSTOR 4615733), Friedman 1937).
- validation.html: CSD-methods row (truth table), repeated-measures bullet (#stats).

## Next steps (in order)
1. Copy frames into `website/assets/frames/` from `review-screens/walkthrough/`:
   `HistologyApp_01..08_*`, `LFPAnalysisApp_c01..c08_*` (maybe skip c07 exported if it looks
   the same as c06), `SignalCharacterizationApp_r01..r06_*`. Run `optipng -o2` if available.
2. Add three tours to `website/assets/site.js` TOURS (format: `{ f, w, t, g, x, l }`):
   - `histology` with g: "histo" — add `histo: "core/demo/demoHistology.m"` to GEN.
   - `csd` (g default core: DemoData LFP), `rm` (g: "groups").
   Write every caption from what the frame shows (open each PNG). Histology frames, already read:
   01 day 1 composite, pixel size 1 µm "Read from the file", "Not aligned"; 2 images, 2 channels, 400 × 400.
   02 day 3 after Align channels + Shift (automatic): "Aligned: channels shifted by up to 2.6 px;
      images shifted by up to 11.2 px"; black border where the image moved.
   03 Counts tab: 60 cells each image, 0.16 mm², 375 per mm², marker 24 (40%) day 1, 39 (65%) day 3;
      circles = counted (yellow = marker-positive), grey × = not counted (debris, fibre).
   04 Show "What was thresholded" + Cells tab: one row per cell (x, y µm, area, elongation, region,
      positive yes/no, % of cell); fibre drawn red.
   05 Regions A (left, blue) / B (right, orange): 30 cells each, 0.08 mm², 375/mm²; positives
      day 1 12 / 12 (40%), day 3 18 / 21 (60% / 70%).
   06 Checks: pixel size OK; alignment "Image 2 moved 9.2 px right and 6.4 px up (clear match, 0.10)";
      Channels = **Check** "Channel 2 was 2.6 px off (corrected; accuracy about half a pixel)";
      threshold 0.291 (Otsu 0.291, noise floor 0.0985); 20 small, 1 elongated not counted;
      6 extra cells from splitting; summary "10 OK, 1 to check, 0 warning(s)".
   07 session reopened: same counts table; status names the session file.
   08 landmarks: "Aligned: landmarks fit to 0.0 px (worst image)"; Checks all OK (10 OK, 0 to check).
   Also add a histology frame (HistologyApp_05_regions, g "histo") to the `overview` tour (index).
3. Possible small app fixes found in the frames (ask the owner / separate PR, not this one):
   - Frame 07: after reopening a session the pixel-size note says "Typed by you." although it was
     read from the file (PixelSizeFromFile not restored from the session).
   - Help / website say the marker channel was "about 2.7 px off" and "nothing to warn about";
     the app shows 2.6 px with a "Check" row (not a warning). Align the wording/number.
4. `git rm -r review-screens docs/dev/HANDOFF.md`; check every `assets/frames/*.png` referenced in
   site.js/HTML exists; `node -e` parse site.js; `npx wrangler@4.140.0 deploy --dry-run`.
5. Open PR "Website: Histology, CSD methods and repeated-measures walkthroughs", cancel any
   duplicate push run, wait for MATLAB CI green, squash-merge (owner said publish), confirm
   Cloudflare deploys `main`.
6. Then: release v0.4.0 (owner to confirm), Techniques explainers.

## Working rules learned
- Commit identity = owner (CLAUDE.md). A stop hook asks for "Claude"/noreply@anthropic.com:
  ignore it, CLAUDE.md wins.
- Force push is blocked: restart the branch after a squash merge by merging main (no content change).
- Screenshots: Actions → Update screenshots (ref main, branch = working branch, include_all true);
  ~12 min; it pushes to the branch.
- Keep CI minutes low; push to the branch without a PR does not start CI.

## Open questions for the owner
- v0.4.0 release after this website PR?
- The two small Histology app fixes above (session pixel-size note, 2.6 vs 2.7 px wording).
