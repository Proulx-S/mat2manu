# mat2manu

From MATLAB analysis scripts to manuscript-ready figures: regenerated from code, laid out by hand,
delivered at exact journal size.

## The problem

Two properties must hold at once:

1. **Regeneration.** Change the data, re-run, and every figure is correct with no manual work.
2. **Hand layout survives.** Panel positions and sizes set by hand, and a hand-drawn annotation
   layer (arrows, brackets, free text, panel letters), survive that regeneration.

Delivery target first: PNAS on Overleaf. That means vector PDF figures at exactly 87, 114.3 or
178 mm wide, with Arial as real text.

## The approach under evaluation

The figurefirst model ([Lindsay, Weir & van Breugel, SciPy 2017](https://proceedings.scipy.org/articles/shinma-7f4c6e7-009);
[FlyRanch/figurefirst](https://github.com/FlyRanch/figurefirst)), ported to MATLAB:

- **A layout SVG is drawn by hand in Inkscape,** on a page of the journal width. Each tagged
  rectangle *is* an axis box.
- **MATLAB reads the rectangles and draws each axis inside its rectangle at its true size,** on one
  page-sized figure. Tick labels spill outside the box, as they should. Nothing is scaled after
  plotting.
- **The generated content goes into one reserved layer that is wiped and refilled on every run.**
  Every other layer (annotations, panel letters) is never touched.

Unlike [matlab2manuscript](https://github.com/Proulx-S/matlab2manuscript), its predecessor, this
never needs to identify elements in MATLAB's SVG export, which carries no ids. The geometry comes
from rectangles a human drew, not from decoding MATLAB's output.

**Status:** started 2026-11-01. A prototype and an honest evaluation are in progress; see `docs/`.
Why this approach and not a notebook platform: [docs/survey-2026-11-01.md](docs/survey-2026-11-01.md).

## Conventions

- Work on `dev`. `main` holds only shareable states.
- **This repository is public:** synthetic data only, never real subject data or names.
- MATLAB R2025a, run headless (`matlab -batch`).
