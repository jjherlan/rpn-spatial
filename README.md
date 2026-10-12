# Rapa Nui Coral Spatial Pattern

An interactive, **browser-based** app for exploring the spatial pattern of coral
(*Pocillopora*) colonies on Rapa Nui (Easter Island) reefs — built with R and
[`spatstat`](https://spatstat.org), compiled to WebAssembly with
[Shinylive](https://posit-dev.github.io/r-shinylive/) so it runs entirely in the
visitor's browser. **No R installation, no server, no account.**

Built as a hands-on teaching app for the SCCS-NY 2026 workshop
*"From Photos to Spatial Pattern: Large-Area Imaging for Coral Reef Conservation."*

🔗 **Live demo:** https://jjherlan.github.io/rpn-spatial/
📖 **User's manual:** [USER_MANUAL.md](USER_MANUAL.md) · [PDF](USER_MANUAL.pdf)

<!-- Add a screenshot once deployed:
![App screenshot](docs/screenshot.png)
-->

## What it does

Each point is a coral colony extracted from a segmented large-area-imaging
2D orthoprojection of a 10 × 25 m (250 m²) reef plot. Pick a site and the app asks:
are the colonies **clustered, random, or over-dispersed** — and how does that
change along a wave-exposure gradient?

It computes, live in the browser:

- Colony count, intensity (colonies / m²), and mean nearest-neighbour distance
- **Clark-Evans** aggregation index and test
- **Quadrat χ² test** of complete spatial randomness (CSR)
- **Ripley's K / L-function** and the **pair-correlation function g(r)**, each
  with a CSR simulation envelope

## Results at a glance

Three sites span a wave-exposure gradient, and the dispersion pattern shifts
across it:

| Site | Exposure | Colonies | Clark-Evans R | Pattern |
|------|----------|---------:|--------------:|---------|
| Anakena (north)     | Sheltered | 124   | ≈ 0.80 | Clustered |
| Manavai (west)      | Moderate  | 368   | ≈ 0.60 | Clustered |
| Vaihu (southeast)   | Exposed   | 3,106 | ≈ 1.26 | Over-dispersed |

## Run it locally (R / RStudio)

```r
install.packages(c("shiny", "spatstat.geom", "spatstat.explore"))
shiny::runApp("rpn-spatial-local")
```

(In RStudio you can also open `rpn-spatial-local/app.R` and click **Run App**.)

## Build the browser (Shinylive) version

```r
install.packages("shinylive")
shinylive::export("rpn-spatial-local", "site")
httpuv::runStaticServer("site")   # test locally before deploying
```

This writes a self-contained static site to `site/`.

## Deploy to GitHub Pages

1. Add an empty file named **`.nojekyll`** to the top of the `site/` folder
   (otherwise GitHub's Jekyll step strips files the app needs).
2. Push the **contents** of `site/` to this repo (so `index.html` is at the root).
3. **Settings → Pages → Source: Deploy from a branch → `main` / `/ (root)`.**
4. Your app goes live at `https://jjherlan.github.io/rpn-spatial/`.

Shinylive ships a service worker that supplies the cross-origin isolation WebR
needs, so it works on GitHub Pages even though Pages can't set custom HTTP
headers. Make sure the whole `shinylive/` folder and `shinylive-sw.js` are
pushed. First load boots WebR and loads the bundled packages; after that it runs
fully in-browser and works offline.

## Data

`ana.csv`, `man.csv`, `vhu.csv` — size-filtered *Pocillopora* colony centroids
(columns `x`, `y` in metres, plus `area_m2`, colony area in m²) from manual
segmentation of 2D orthoprojections, one file per reef site. Colony areas
are used by the neighbourhood-overlap tool; see the user's manual (Section 13)
for how they were matched.


## Repository structure

```
rpn-spatial/
├── rpn-spatial-local/     # the R app + data (run locally or export with shinylive)
│   ├── app.R
│   ├── ana.csv  man.csv  vhu.csv
│   └── README.md
├── index.html             # exported Shinylive site (after `shinylive::export`)
├── shinylive/             #   "
├── shinylive-sw.js        #   "
├── .nojekyll
└── README.md
```

## Built with

[R](https://www.r-project.org) · [Shiny](https://shiny.posit.co) ·
[spatstat](https://spatstat.org) · [Shinylive](https://posit-dev.github.io/r-shinylive/) ·
[WebR](https://docs.r-wasm.org/webr/latest/)

## Citation & data

If you use this app or its data, please cite the associated work:

- **Data archive:** Herlan, J. et al. Rapa Nui coral spatial ecology.
  Dryad, https://doi.org/10.5061/dryad.s1rn8pkp4
- **Associated manuscript:** Herlan, J. et al. *Marine Ecology Progress Series*
  (fill in final volume/pages/year).

*(Please update these entries with the final publication details.)*

## Acknowledgments

Developed for the Society for Conservation Biology — New York (SCCS-NY) 2026
workshops at the American Museum of Natural History.

## License

Add a license file (e.g. MIT for the code, CC-BY-4.0 for the data) to make reuse
terms explicit.
