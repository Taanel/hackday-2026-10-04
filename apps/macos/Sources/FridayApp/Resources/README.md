# Mascot artwork

`mascot.png` is the normal mascot. The app loads it through SwiftPM's resource bundle
and shows it on the desktop and in the assistant window. Without it the app uses the
SF Symbol `sparkles`.

Reactions follow the assistant phase: `mascot-curious.png` (recording, reasoning),
`mascot-focused.png` (transcribing, deciding), `mascot-excited.png` (acting, being
dragged) and `mascot-worried.png` (failed). `mascot-sleeping.png` appears after a minute
without requests; hovering plays `mascot-hover.png`. A missing file falls back to
`mascot.png`.

Every file is a transparent PNG on the same canvas (currently 148 × 132 px) and may be
an animated PNG, e.g. exported from Procreate. Reactions loop while their phase lasts,
play at least once and change at the end of a loop; the normal and sleeping mascots rest
on their first frame between loops.

The current blob frames were cut from a GIF supplied by a team member. Its source and
license are not verified and it is not covered by the app's MIT license; confirm the
rights or replace it with original artwork before redistributing the app.
