# mat2manu

MATLAB figures → manuscript figures, using the figurefirst model: Inkscape layout rectangles are
the axis boxes; MATLAB fills one reserved layer; hand-drawn layers survive regeneration. Read
`README.md` first, then `docs/`.

- **Public repo:** synthetic data only. No subject data, IDs, collaborator names or unpublished
  results, ever, including in commit messages and test fixtures.
- **Branches:** work on `dev`; PRs target `dev` (`bin/bass-pr --base dev`). Merge to `main` only on Seb's ask.
- **Target spec (PNAS):** vector PDF, width exactly 87 / 114.3 / 178 mm, Arial as real text (set
  the font explicitly: MATLAB's default falls back to LiberationSans on tako). Deliver PDF only.
  Mind `pt` (1/72.27 in) vs `bp` (1/72 in).
- **Tools on tako:** MATLAB R2025a (`matlab -batch`), Inkscape 1.2.2, `rsvg-convert` (librsvg).
  Inkscape's `--export-text-to-path=false` silently converts text to paths: render SVG→PDF
  with librsvg.
- **Predecessor:** `/scratch/bass/tools/matlab2manuscript` (read-only for this project). Its
  `docs/findings.md` records MATLAB's SVG-export mechanics: no element ids; every group wrapped in
  `matrix(72/ScreenPixelsPerInch…)`; size drift. Read it before trusting MATLAB SVG geometry.
- **Research behind the approach:** `docs/survey-2026-11-01.md`.
- **Prototype and its measurements:** `src/`, `test/` (`run_all.m`), `docs/evaluation.md`.
  pypdf lives in the venv `~/opt/mat2manu-py`. Keep `DISPLAY` as is: without it, MATLAB's
  `print`/`exportgraphics` hang on tako. With it, positions snap to 1/95 inch and font sizes
  floor to whole pixels (7 pt prints as 6.82 pt).
