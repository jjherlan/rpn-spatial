# Rapa Nui coral spatial pattern — local R app

A small Shiny app that runs your Chapter 2 spatial-pattern analysis on the
pre-extracted *Pocillopora* colony centroids for the three reef sites
(Anakena, Manavai, Vaihu). It's the same `app.R` we'll later compile to a
browser (Shinylive) build for the workshop — this folder is for running and
testing it on your own computer.

## What it does

Pick a site, and the app builds a `spatstat` point pattern (10 × 25 m plot)
and reports:

- colony count and intensity (colonies / m²), mean nearest-neighbour distance
- **Clark-Evans** aggregation index + test (clustered / random / over-dispersed)
- **quadrat χ² test** of complete spatial randomness (CSR)
- **L-function** or **pair-correlation g(r)** with a CSR simulation envelope

The three sites already show the gradient from your dissertation: Anakena
(sheltered) R ≈ 0.80 and Manavai (moderate) R ≈ 0.60 are **clustered**, while
Vaihu (exposed) R ≈ 1.26 is **over-dispersed**.

## Data

`ana.csv`, `man.csv`, `vhu.csv` — the `*_poci_sizefiltered.csv` centroid files
(columns `x`, `y` in metres), copied from
`R Final/output_dispersion/` in your Chapter 2 folder.

## How to run (local)

1. Install the packages once (in R or RStudio):

   ```r
   install.packages(c("shiny", "spatstat.geom", "spatstat.explore"))
   ```

2. Run the app, pointing at this folder:

   ```r
   shiny::runApp("path/to/this/folder")
   ```

   In RStudio you can also just open `app.R` and click **Run App**.

## How to build the browser (Shinylive) version

From the folder that CONTAINS this folder:

```r
install.packages("shinylive")              # once
shinylive::export("rpn-spatial-local", "site")
httpuv::runStaticServer("site")            # test locally in your browser
```

Then push the contents of `site/` to a GitHub repo (add an empty `.nojekyll`
file first) and enable GitHub Pages.

## Notes

- These CSVs have only `x, y` (no colony area), so the app reports colony
  *intensity/density*, not percent cover.
- To add the live-vs-dead **Lcross** bivariate analysis, add the matching
  dead-colony centroid files.
