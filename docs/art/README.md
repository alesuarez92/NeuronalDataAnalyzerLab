# Help figures

The explanatory figures in `docs/` that the Help window shows
(`*Principle.png`, `*Workflow.png`, `FilterHowItWorks.png`, `LFPAnalysisCSD.png`)
are drawn by the script `make_figures.py` in this folder. The script draws
boxes, arrows and plots of synthetic signals computed with NumPy. It uses no AI
image tools, no third-party images and no figures copied from papers.

## How to run it

```
python3 docs/art/make_figures.py                         # all figures
python3 docs/art/make_figures.py ROIAnalysisPrinciple    # only some, by name
```

You need Python 3 with matplotlib, NumPy and Pillow. The PNG files are written
to `docs/` and keep the names that `apps/HelpApp.m` uses. When a window's
steps or buttons change, edit the matching `wf_...` function and run the script
again.

## Tools and licences

The tools below are used only to draw the figures. Nothing from them is copied
into the figures except the font's letter shapes.

- **matplotlib**: plotting library, under the matplotlib licence (based on the
  PSF licence; permissive).
- **NumPy**: computes the synthetic signals, under the BSD 3-Clause licence.
- **Pillow**: optimises the PNG files, under the MIT-CMU (HPND) licence.
- **DejaVu Sans**: the only font, the one bundled with matplotlib. It is under
  the Bitstream Vera licence plus a public-domain dedication for the DejaVu
  changes (a free licence that allows use and embedding).

Colours are the app's plot palette from `core/UITheme.m`.
