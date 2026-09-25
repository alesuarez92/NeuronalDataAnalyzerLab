# NeuroAnalyzer UI style guide

Every window is built from **`core/UIKit.m`** with colors and sizes from
**`core/UITheme.m`**. Never hard-code RGB values or font sizes in an app.

## Goals

1. **Obvious next step.** A new user should be able to finish a workflow
   without opening the help: steps are numbered, only the actions that make
   sense right now are enabled, and the recommended next action is the
   teal *primary* button.
2. **Always say what happened.** Every action ends with a status-bar
   message (busy → success / error). Errors say what to do next.
3. **One look everywhere.** Same header, status bar, footer, cards, buttons
   and plot styling in every window.

## Window structure

```text
┌──────────────────────────────────────────────────────────────┐
│ Title                                               [? Help] │  header  (UIKit.window)
│ one-line subtitle                                            │
├───────────────────┬──────────────────────────────────────────┤
│ 1  Load data      │                                          │
│   [Load file]     │                                          │
│   file · Fs · dur │               plots                      │  body    (W.Body grid)
│ 2  Settings       │         (UIKit.styleAxes;                │
│   fields…         │     UIKit.emptyAxes before data)         │
│ 3  Run            │                                          │
│   [Run]           │                                          │
│ 4  Save / export  │                                          │
│   [Save]          │                                          │
├───────────────────┴──────────────────────────────────────────┤
│ ✓ Loaded rat12.mat (1000 Hz, 612 s)                          │  status  (UIKit.setStatus)
│                         © Copyrights … · v0.x                │  footer
└──────────────────────────────────────────────────────────────┘
```

- **Sub-windows:** `W = UIKit.window(title, subtitle, helpTopic, [w h])`,
  then lay out `W.Body`. Controls on the left, in a fixed-width column of about 280–320 px,
  one `UIKit.card` per numbered step (`UIKit.step`). Plots on the right (`'1x'`).
- **Parameter dialogs:** `D = UIKit.dialog(title, subtitle, helpTopic, [w h])`.
  Put one `UIKit.field` per row in `D.Body` (label | control). Put Cancel
  (secondary) and OK (primary) in `D.Buttons` columns 2 and 3. The public
  contract stays the same: callers `uiwait(dlg.UIFig)` and then read `dlg.Params`,
  which is empty when the dialog was cancelled.
- The **help topic** is the matching `HelpApp` tab title, e.g. `'LDF Process'`.

## Controls

- **Buttons:** `UIKit.button(parent, text, callback, style, tooltip)`.
  Styles: `'primary'` for the one recommended action per step, `'secondary'`
  for everything else, and `'danger'` for destructive actions. Every button gets a tooltip.
- **Numbers:** use numeric edit fields with `Limits`, not text plus `str2double`.
  Put units in the label: "Pre-stimulus (s)", "Cutoff (Hz)".
- **Choices:** use dropdowns, not free text.
- **Enable state:** each app has one `updateControls()` (or
  `updateButtonStates()`) that enables or disables everything from the
  current data state. Call it after every action.
- **File info:** after loading, show the file name, sampling rate, duration and
  channel count next to the Load button.

## Feedback

- `UIKit.setStatus(W.Status, msg, kind)`, where `kind` is one of `info`, `success`, `warning`, `error` or `busy`.
- Operations that take longer than about 1 s are wrapped in
  `dlg = UIKit.busy(fig, 'Filtering…'); … UIKit.done(dlg);`, with `UIKit.done` also called in the error path.
- Errors go to `UIKit.alert(fig, msg, title, 'error')` (an in-window `uialert`), not
  `errordlg`, which opens a separate window.

## Plots

- `UIKit.styleAxes(ax, title, xlabel, ylabel)` after each plot, since `cla` resets
  styling. Use the `UITheme.plotColors` order for series and
  `UITheme.stimColor` for stimulus traces and onset markers.
- Before data is loaded: `UIKit.emptyAxes(ax, 'Load a file to begin')`.
- Always pass the axes handle explicitly (`plot(ax, …)`, `hold(ax, 'on')`).
  In a `uifigure`, `gca`/`gcf` do not return the app's axes.

## uifigure gotchas

- `ginput` is not reliable in `uifigure`s. For picking a time range, use
  `drawrectangle`/`drawline` (Image Processing Toolbox, wrapped in
  try/catch), axes `ButtonDownFcn` clicks, or typed Start/End fields.
- `annotation` does not work in a `uifigure`. Use a `uilabel` instead.
- `subplot` → `tiledlayout(panel)` + `nexttile`.
- After `uigetfile`/`uiputfile`, call `figure(app.UIFig)` to bring the app back
  to the front.
