# =====================================================================
# Rapa Nui coral spatial pattern — Pocillopora colony dispersion
# Shinylive (runs entirely in the browser via WebR — no install, no server)
# Hands-on app for the SCCS-NY 2026 workshop.
#
# Two modes:
#   * Real reef data  — size-filtered colony centroids from large-area
#                       imaging at three Rapa Nui sites (Herlan et al. 2026).
#   * Simulation      — a sandbox with two sub-tools:
#       (1) "Build a pattern" — one axis that spans the full trichotomy
#             REGULAR (inhibition) <- RANDOM (CSR) -> CLUSTERED,
#             holding intensity (lambda = N/250) fixed so only the
#             second-order structure changes.
#       (2) "Pick the generating process" — simulate from the four
#             candidate point-process models compared in the manuscript
#             (Fig. 7 / DCLF): CSR, habitat filtering (inhomogeneous
#             Poisson), biotic clustering (Cauchy cluster process), and
#             both (an inhomogeneous Cauchy cluster process).
#
# Primary dispersion metric = variance-to-mean ratio (VMR), as in the paper;
# Clark-Evans shown as a complementary nearest-neighbour view.
# All generators use only base R + spatstat.geom (ppp/owin) so they run
# in WebR without the spatstat.random package.
# =====================================================================

library(shiny)
library(spatstat.geom)
library(spatstat.explore)

# --- Sites (wave-exposure gradient) ----------------------------------
sites <- c(
  "Anakena — sheltered (north)"    = "ana.csv",
  "Manavai — moderate (west)"      = "man.csv",
  "Vaihu — exposed (southeast)"    = "vhu.csv"
)

# All plots are 10 m (x) x 25 m (y) = 250 m^2
WIN  <- owin(xrange = c(0, 10), yrange = c(0, 25))
AREA <- 250

site_label <- function(file) names(sites)[match(file, sites)]

# =====================================================================
# SIMULATION (1): "Build a pattern" — regular <-> random <-> clustered
# axis in [-1, 1]:  -1 = strongly regular (inhibition),
#                    0 = complete spatial randomness (CSR),
#                   +1 = strongly clustered.
# Intensity is held fixed (exactly N points, except at the extreme
# regular end where sequential inhibition may fall a few short).
# =====================================================================
simulate_pattern <- function(N, axis, seed = 1) {
  set.seed(seed)
  if (N <= 0) return(ppp(numeric(0), numeric(0), window = WIN))

  # --- RANDOM (CSR): exactly N uniform points --------------------
  if (abs(axis) < 0.04) {
    return(ppp(runif(N, 0, 10), runif(N, 0, 25), window = WIN))
  }

  # --- REGULAR: simple sequential inhibition (RSA) ---------------
  if (axis < 0) {
    reg    <- -axis                          # 0..1
    meannn <- 7.906 / sqrt(N)                # CSR mean nearest-neighbour dist
    rhc    <- reg * 0.85 * meannn            # inhibition distance (kept feasible)
    r2     <- rhc^2
    x <- numeric(N); y <- numeric(N); placed <- 0L
    tries <- 0L; maxtries <- 4000L * N + 20000L
    while (placed < N && tries < maxtries) {
      xi <- runif(1, 0, 10); yi <- runif(1, 0, 25); tries <- tries + 1L
      ok <- TRUE
      if (placed > 0L) {
        if (min((x[seq_len(placed)] - xi)^2 + (y[seq_len(placed)] - yi)^2) < r2) ok <- FALSE
      }
      if (ok) { placed <- placed + 1L; x[placed] <- xi; y[placed] <- yi }
    }
    return(ppp(x[seq_len(placed)], y[seq_len(placed)], window = WIN))
  }

  # --- CLUSTERED: Matern-cluster style, exactly N ----------------
  clus     <- axis                           # 0..1
  nparents <- max(3, round(N * (1 - clus) * 0.30)); nparents <- min(nparents, N)
  px <- runif(nparents, 0, 10); py <- runif(nparents, 0, 25)
  pid <- sample(seq_len(nparents), N, replace = TRUE)
  sdx <- 0.15 + (1 - clus) * 1.50            # spread shrinks as clus rises
  sdy <- sdx * 2.2
  x <- numeric(N); y <- numeric(N)
  for (i in seq_len(N)) {
    repeat {
      xi <- rnorm(1, px[pid[i]], sdx); yi <- rnorm(1, py[pid[i]], sdy)
      if (xi >= 0 && xi <= 10 && yi >= 0 && yi <= 25) break
    }
    x[i] <- xi; y[i] <- yi
  }
  ppp(x, y, window = WIN)
}

# =====================================================================
# SIMULATION (2): "Pick the generating process" — the paper's 4 models
# Each is a genuine stochastic process, so the realised count varies
# around the expected N (click Resample to see the variability).
# =====================================================================

# Habitat relative intensity: a smooth ~4:1 gradient down the plot
# (mimics a depth/substrate gradient driving first-order inhomogeneity).
trend_habitat <- function(x, y) exp(1.4 * (1 - y / 25))

# Inhomogeneous-Poisson points by thinning; returns a 2-col matrix.
# Expected count = m, with spatial intensity proportional to trend_habitat.
rinhom_pts <- function(m) {
  gx <- seq(0.1, 9.9, length.out = 30)
  gy <- seq(0.2, 24.8, length.out = 70)
  g  <- expand.grid(x = gx, y = gy)
  tv <- trend_habitat(g$x, g$y); meant <- mean(tv)
  lam_bar <- m / AREA
  lmax    <- max(tv) * lam_bar / meant
  nh <- rpois(1, lmax * AREA)
  if (nh < 1) return(matrix(numeric(0), ncol = 2))
  x <- runif(nh, 0, 10); y <- runif(nh, 0, 25)
  p <- (trend_habitat(x, y) * lam_bar / meant) / lmax
  keep <- runif(nh) < p
  cbind(x[keep], y[keep])
}

# Scatter Poisson(mu) offspring around each parent with a Cauchy kernel
# (isotropic bivariate t with 1 df, scale omega), the kernel of spatstat's
# rCauchy / kppm(clusters = "Cauchy") fitted in the paper. Heavy-tailed:
# most offspring stay close, a few land far away. Offspring falling
# outside the plot are dropped. Returns a 2-col matrix.
scatter_offspring <- function(px, py, mu, omega) {
  x <- numeric(0); y <- numeric(0)
  for (i in seq_along(px)) {
    k <- rpois(1, mu)
    if (k > 0) {
      w  <- sqrt(rchisq(k, df = 1))           # one draw per offspring -> isotropic
      ox <- px[i] + rnorm(k, 0, omega) / w
      oy <- py[i] + rnorm(k, 0, omega) / w
      inside <- ox >= 0 & ox <= 10 & oy >= 0 & oy <= 25
      x <- c(x, ox[inside]); y <- c(y, oy[inside])
    }
  }
  cbind(x, y)
}

simulate_process <- function(proc, N, seed = 1) {
  set.seed(seed)
  if (N <= 0) return(ppp(numeric(0), numeric(0), window = WIN))
  mu <- 6; omega <- 0.55                      # offspring per parent / Cauchy scale (m)
                                              # median parent-offspring distance = omega*sqrt(3) ~ 0.95 m

  if (proc == "csr") {
    n <- rpois(1, N)
    X <- ppp(runif(n, 0, 10), runif(n, 0, 25), window = WIN)

  } else if (proc == "inhom") {
    m <- rinhom_pts(N)
    X <- ppp(m[, 1], m[, 2], window = WIN)

  } else if (proc == "cauchy") {
    kappa <- (N / AREA) / mu                  # parent intensity so kappa*mu = lambda
    np <- rpois(1, kappa * AREA); if (np < 1) np <- 1
    px <- runif(np, 0, 10); py <- runif(np, 0, 25)
    o  <- scatter_offspring(px, py, mu, omega)
    X  <- ppp(o[, 1], o[, 2], window = WIN)

  } else {                                    # "both": inhomogeneous Cauchy cluster
    kappa <- (N / AREA) / mu
    par <- rinhom_pts(kappa * AREA)           # parents placed by the habitat gradient
    if (nrow(par) < 1) par <- cbind(runif(1, 0, 10), runif(1, 0, 25))
    o <- scatter_offspring(par[, 1], par[, 2], mu, omega)
    X <- ppp(o[, 1], o[, 2], window = WIN)
  }
  X
}

proc_label <- c(
  csr    = "CSR — complete spatial randomness (Poisson)",
  inhom  = "Habitat filtering — inhomogeneous Poisson",
  cauchy = "Biotic clustering — Cauchy cluster process",
  both   = "Both — habitat gradient + Cauchy clustering"
)

# =====================================================================
# NEIGHBOURHOOD OVERLAP (germ-grain / zone-of-influence)
# Each colony is a disc of its real equivalent radius r = sqrt(area/pi),
# surrounded by a buffer halo of width b (the "zone of influence").
# Two colonies co-occur as neighbours when their haloed discs overlap.
# We measure how much the neighbourhoods overlap and test it against a
# random (CSR) layout that keeps the same colonies and sizes.
# Uses only base R + spatstat.geom (closepairs, discs) -> WebR-safe.
# =====================================================================

# log-normal fits of colony area (m^2) per site, for simulated colonies
size_par <- list(
  ana = c(-5.1156, 0.7585),
  man = c(-4.6267, 0.9464),
  vhu = c(-3.7225, 0.9697)
)
colony_radii <- function(n, site) {
  p <- size_par[[if (is.null(site) || !site %in% names(size_par)) "man" else site]]
  sqrt(rlnorm(n, p[1], p[2]) / pi)
}

# Vectorised area of intersection of two discs (radii r1, r2, centre dist d)
lens_area <- function(d, r1, r2) {
  out  <- numeric(length(d))
  sep  <- d >= (r1 + r2)
  incl <- d <= abs(r1 - r2)
  out[incl] <- pi * pmin(r1, r2)[incl]^2
  m <- !sep & !incl
  if (any(m)) {
    dd <- d[m]; a <- r1[m]; b <- r2[m]
    t1 <- a^2 * acos(pmin(pmax((dd^2 + a^2 - b^2) / (2 * dd * a), -1), 1))
    t2 <- b^2 * acos(pmin(pmax((dd^2 + b^2 - a^2) / (2 * dd * b), -1), 1))
    t3 <- 0.5 * sqrt(pmax((-dd + a + b) * (dd + a - b) * (dd - a + b) * (dd + a + b), 0))
    out[m] <- t1 + t2 - t3
  }
  out
}

# Neighbourhood statistics for a pattern X with radii r and buffer b
overlap_metrics <- function(X, r, b) {
  n <- npoints(X)
  if (n < 2) return(list(pairs = 0, degree = 0, oarea = 0, n = n))
  R    <- r + b
  rmax <- 2 * max(R) + 1e-6
  cp   <- closepairs(X, rmax)
  keep <- cp$i < cp$j                       # each unordered pair once
  I <- cp$i[keep]; J <- cp$j[keep]; D <- cp$d[keep]
  Ri <- R[I]; Rj <- R[J]
  ov <- D < (Ri + Rj)                        # haloed discs actually overlap
  pairs <- sum(ov)
  list(
    pairs  = pairs,
    degree = if (pairs > 0) 2 * pairs / n else 0,
    oarea  = if (pairs > 0) sum(lens_area(D[ov], Ri[ov], Rj[ov])) else 0,
    n      = n
  )
}

# --- UI --------------------------------------------------------------
# The manual is a separate page on the same site (rendered from manual-src/USER_MANUAL.qmd),
# so it can be updated without re-exporting the app.
MANUAL_URL <- "https://jjherlan.github.io/rpn-spatial/manual.html"
MANUAL_PDF <- "https://jjherlan.github.io/rpn-spatial/USER_MANUAL.pdf"
# Feedback pages (rendered from feedback-src/*.qmd). The Google Form and the anonymised
# summary sheet are configured in feedback-config.json on the site, so no re-export is needed.
FEEDBACK_URL <- "https://jjherlan.github.io/rpn-spatial/feedback.html"
FEEDBACK_SUMMARY_URL <- "https://jjherlan.github.io/rpn-spatial/feedback-summary.html"

ui <- fluidPage(
  tags$head(tags$style(HTML(
    ".well{background:#f4f8f5} h4{color:#1b5e3f;margin-top:0}"))),
  titlePanel("Rapa Nui coral spatial pattern — Pocillopora dispersion"),
  helpText("Each point is a coral colony. Explore the real reef data, or switch to the",
           "simulation sandbox to build your own pattern or sample from a candidate",
           "process model. Then read the dispersion statistics and the distance function",
           "to decide: clustered, random, or over-dispersed?"),
  tags$p(style = "margin-top:-4px",
         tags$a(href = MANUAL_URL, target = "_blank", rel = "noopener",
                HTML("&#128214; User&rsquo;s manual")),
         " (opens in a new tab) · ",
         tags$a(href = MANUAL_PDF, target = "_blank", rel = "noopener", "PDF"),
         " · ",
         tags$a(href = FEEDBACK_URL, target = "_blank", rel = "noopener",
                HTML("&#128172; Workshop feedback"))),
  sidebarLayout(
    sidebarPanel(
      radioButtons("mode", "Data",
                   c("Real reef data" = "real", "Simulation sandbox" = "sim"),
                   inline = TRUE),
      tags$hr(),

      conditionalPanel(
        "input.mode == 'real'",
        selectInput("site", "Reef site (wave-exposure gradient)", choices = sites)
      ),
      conditionalPanel(
        "input.mode == 'sim'",
        h4("Simulation sandbox"),
        radioButtons("simkind", NULL,
          c("Build a pattern  (regular → random → clustered)" = "build",
            "Pick the generating process  (paper's 4 models)"  = "process")),
        sliderInput("Nsim", "Number of colonies  (intensity λ = N / 250 m²)",
                    min = 0, max = 500, value = 150, step = 10),

        conditionalPanel(
          "input.simkind == 'build'",
          sliderInput("axis",
                      "Pattern:  ◀ regular (inhibition)   ·   random   ·   clustered ▶",
                      min = -100, max = 100, value = 0, step = 5),
          helpText("Intensity stays fixed as you slide — only the arrangement ",
                   "(second-order structure) changes. Left of centre colonies repel: ",
                   "over-dispersed, VMR < 1, R > 1, g(r) < 1. Centre = complete spatial ",
                   "randomness. Right they aggregate: clustered, VMR > 1, R < 1, g(r) > 1.")
        ),
        conditionalPanel(
          "input.simkind == 'process'",
          selectInput("proc", "Candidate process model",
            c("Complete spatial randomness (CSR / Poisson)" = "csr",
              "Habitat filtering (inhomogeneous Poisson)"    = "inhom",
              "Biotic clustering (Cauchy cluster process)"   = "cauchy",
              "Both — habitat + clustering (inhom. Cauchy)"  = "both")),
          helpText("The four candidate processes compared in the manuscript (Fig. 7 / ",
                   "DCLF). CSR is the null. Habitat filtering varies intensity with the ",
                   "environment (first-order). Biotic clustering scatters offspring around ",
                   "parents with a heavy-tailed Cauchy kernel, as fitted in the paper (second-order). Both layers clustering onto a habitat gradient. ",
                   "Number of colonies sets the expected count; each process is random, so ",
                   "the realised n varies — click Resample.")
        ),
        actionButton("resim", "Resample", class = "btn-default")
      ),
      tags$hr(),

      h4("Dispersion (quadrats)"),
      helpText("Keep 10 × 25 to reproduce the paper's 250 one-m² cells."),
      sliderInput("nx", "Quadrats across plot width (x)",  2, 12, 10),
      sliderInput("ny", "Quadrats down plot length (y)",   2, 30, 25),
      tags$hr(),

      h4("Distance function + CSR envelope"),
      radioButtons("fun", "Function",
                   c("L-function  L(r)" = "L", "Pair correlation  g(r)" = "pcf")),
      sliderInput("rmax", "Max distance r (m)", 0.5, 5, 2.5, step = 0.5),
      sliderInput("nsim", "CSR simulations (envelope)", 0, 199, 39, step = 10),
      conditionalPanel(
        "input.mode == 'real' && input.site == 'vhu.csv'",
        checkboxInput("sub",
          "Subsample Vaihu to 800 colonies (speeds up envelopes)", TRUE)),
      actionButton("go", "Run distance function", class = "btn-primary"),
      helpText("Summary stats update instantly; the envelope runs when you click."),
      tags$hr(),

      h4("Neighbourhood overlap"),
      helpText("Give each colony its real footprint (area → equivalent radius) plus a ",
               "buffer halo of width b — the 'zone of influence'. Two colonies co-occur ",
               "as neighbours when their haloed discs overlap."),
      conditionalPanel(
        "input.mode == 'sim'",
        selectInput("ovsize", "Simulated colony sizes drawn from",
                    c("Anakena sizes" = "ana", "Manavai sizes" = "man",
                      "Vaihu sizes" = "vhu"), selected = "man")),
      sliderInput("bwidth", "Buffer / border width b (m)", 0, 1, 0.25, step = 0.05),
      sliderInput("ovnsim", "Random (CSR) null simulations", 0, 199, 39, step = 10),
      actionButton("ovgo", "Run neighbourhood overlap", class = "btn-primary")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Point map",        plotOutput("map",     height = "620px")),
        tabPanel("Summary",          verbatimTextOutput("summary")),
        tabPanel("Distance function",
                 plotOutput("envplot", height = "500px"),
                 uiOutput("envnote")),
        tabPanel("Neighbourhood overlap",
                 plotOutput("ovmap", height = "520px"),
                 verbatimTextOutput("ovsummary"),
                 plotOutput("ovnull", height = "240px")),
        tabPanel("User's manual",
                 tags$p(style = "margin-top:10px",
                        "The full manual, also available ",
                        tags$a(href = MANUAL_URL, target = "_blank", rel = "noopener", "in its own tab"),
                        " and as a ",
                        tags$a(href = MANUAL_PDF, target = "_blank", rel = "noopener", "PDF"), "."),
                 tags$iframe(src = MANUAL_URL, title = "User's manual",
                             style = "width:100%; height:80vh; border:1px solid #cfe3d6; border-radius:4px;")),
        tabPanel("Feedback",
                 tags$p(style = "margin-top:10px",
                        "Anonymous workshop feedback and questions. ",
                        tags$a(href = FEEDBACK_URL, target = "_blank", rel = "noopener", "Open the form in its own tab"),
                        " · ",
                        tags$a(href = FEEDBACK_SUMMARY_URL, target = "_blank", rel = "noopener",
                               "See what participants said (name-blind summary)"), "."),
                 tags$iframe(src = FEEDBACK_URL, title = "Workshop feedback",
                             style = "width:100%; height:80vh; border:1px solid #cfe3d6; border-radius:4px;"))
      )
    )
  )
)

# --- Server ----------------------------------------------------------
server <- function(input, output, session) {

  # reseed the simulation when "Resample" is clicked
  seedval <- reactiveVal(1)
  observeEvent(input$resim, seedval(seedval() + 1))

  # current point pattern (real or simulated)
  pp <- reactive({
    if (input$mode == "sim") {
      sd <- 1000 + seedval()
      if (input$simkind == "build") {
        simulate_pattern(input$Nsim, input$axis / 100, seed = sd)
      } else {
        simulate_process(input$proc, input$Nsim, seed = sd)
      }
    } else {
      df <- read.csv(input$site)
      ppp(df$x, df$y, window = WIN)
    }
  })

  # label describing the current pattern
  cur_label <- reactive({
    if (input$mode == "sim") {
      if (input$simkind == "build") {
        a    <- input$axis
        kind <- if (a < -4) "regular / inhibited" else if (a > 4) "clustered" else "random (CSR)"
        sprintf("Simulation — %d colonies, %s (axis %d)", input$Nsim, kind, a)
      } else {
        sprintf("Simulation — %s", proc_label[[input$proc]])
      }
    } else site_label(input$site)
  })

  # pattern used for the (heavier) envelope — optionally subsampled for real Vaihu
  ppUse <- reactive({
    X <- pp()
    if (input$mode == "real" && isTRUE(input$sub) &&
        input$site == "vhu.csv" && npoints(X) > 800) {
      set.seed(42)
      X <- X[sample(npoints(X), 800)]
    }
    X
  })

  output$map <- renderPlot({
    X <- pp()
    col <- if (input$mode == "sim") "#b5482f" else "#1b7837"
    plot(X, main = paste0(cur_label(), "   (n = ", npoints(X), ")"),
         pch = 19, cex = 0.5, cols = col)
    axis(1); axis(2)
    title(xlab = "x (m)", ylab = "y (m)")
  })

  output$summary <- renderPrint({
    X <- pp()
    cat("Pattern:   ", cur_label(), "\n")
    cat("Colonies:  ", npoints(X), "\n")
    cat("Plot:       10 x 25 m  (250 m^2)\n")
    if (npoints(X) < 5) {
      cat("\n(n is too small to analyse — add more colonies.)\n")
      return(invisible())
    }
    lam   <- intensity(X)
    ncell <- input$nx * input$ny
    qc    <- as.numeric(quadratcount(X, nx = input$nx, ny = input$ny))
    vmr   <- var(qc) / mean(qc)
    qt    <- suppressWarnings(quadrat.test(X, nx = input$nx, ny = input$ny))
    ce    <- clarkevans(X)[["naive"]]
    cet   <- suppressWarnings(clarkevans.test(X, alternative = "two.sided", nsim = 99))
    nnd   <- nndist(X)

    vmr_verdict <- if (vmr > 1) "CLUSTERED (aggregated)" else
                   if (vmr < 1) "REGULAR (over-dispersed)" else "RANDOM"
    ce_verdict  <- if (ce < 1) "clustered" else
                   if (ce > 1) "over-dispersed" else "random"

    cat(sprintf("Intensity:  %.3f colonies / m^2   (first-order, lambda)\n\n", lam))
    cat("====  DISPERSION  —  variance-to-mean ratio (VMR)  ====\n")
    cat(sprintf("  VMR = %.2f   over %d quadrats (%d x %d grid)\n",
                vmr, ncell, input$nx, input$ny))
    cat(sprintf("  ->  %s\n", vmr_verdict))
    cat(sprintf("  Quadrat chi-square test of CSR:  chi-sq = %.1f,  p = %.4g\n",
                qt$statistic, qt$p.value))
    cat("  (VMR > 1 = clustered; VMR < 1 = over-dispersed; small p = departs from random)\n\n")

    cat("----  Nearest-neighbour view: Clark-Evans index  ----\n")
    cat(sprintf("  R = %.3f   (%s at nearest-neighbour scale)\n", ce, ce_verdict))
    cat(sprintf("  Mean nearest-neighbour distance = %.3f m;  test p = %.4g\n",
                mean(nnd), cet$p.value))
    cat("  Note: R and VMR can disagree — they describe different scales\n")
    cat("  (R = nearest-neighbour; VMR = quadrat / plot scale). The paper uses VMR.\n")
    if (input$mode == "real" && input$site == "vhu.csv") {
      cat("  At exposed Vaihu, R reads over-dispersed (tight local packing) while\n")
      cat("  VMR reads clustered (plot-scale patchiness).\n")
    }
  })

  # envelope computed only when the button is pressed
  env <- eventReactive(input$go, {
    X   <- ppUse()
    validate(need(npoints(X) >= 10,
                  "Need at least ~10 colonies for a distance function — raise the count."))
    rr  <- seq(0, input$rmax, length.out = 200)
    fun <- if (input$fun == "L") Lest else pcf
    if (input$nsim > 0) {
      envelope(X, fun, nsim = input$nsim, r = rr, verbose = FALSE)
    } else {
      fun(X, r = rr)
    }
  })

  output$envplot <- renderPlot({
    e <- env()
    ttl <- if (input$fun == "L") "L-function with CSR envelope"
           else "Pair correlation g(r) with CSR envelope"
    plot(e, main = ttl, legend = TRUE)
  })

  output$envnote <- renderUI({
    req(input$go)
    if (input$fun == "L") {
      helpText(HTML(paste0(
        "<b>How to read it:</b> the dashed line is the CSR expectation. ",
        "Observed <b>above</b> the grey envelope = <b>clustering</b> at that ",
        "distance; <b>below</b> = <b>over-dispersion</b>; inside = consistent ",
        "with random. The envelope is the range of ", input$nsim,
        " simulated random patterns.")))
    } else {
      helpText(HTML(paste0(
        "<b>How to read it:</b> g(r) = 1 under complete spatial randomness. ",
        "g(r) <b>&gt; 1</b> = more colony pairs at distance r than random ",
        "(<b>clustering</b>); <b>&lt; 1</b> = fewer (<b>inhibition</b>). ",
        "Grey band = ", input$nsim, " CSR simulations.")))
    }
  })

  # --- Neighbourhood overlap -----------------------------------------
  # colony radii aligned with the current pattern pp()
  radii <- reactive({
    if (input$mode == "real") {
      df <- read.csv(input$site)
      if (!is.null(df$area_m2)) sqrt(df$area_m2 / pi) else colony_radii(nrow(df), "man")
    } else {
      set.seed(5000 + seedval())
      colony_radii(npoints(pp()), input$ovsize)
    }
  })

  ovres <- eventReactive(input$ovgo, {
    X <- pp(); r <- radii(); b <- input$bwidth
    n0 <- npoints(X)
    validate(need(n0 >= 5, "Need at least ~5 colonies for the neighbourhood tool."))
    sub <- FALSE
    if (n0 > 1200) {                         # keep it responsive for big Vaihu
      set.seed(7); idx <- sample(n0, 1200)
      X <- X[idx]; r <- r[idx]; sub <- TRUE
    }
    obs <- overlap_metrics(X, r, b)
    R   <- r + b
    cover <- tryCatch(area(discs(X, radii = R, mask = TRUE, eps = 0.1)) / AREA,
                      error = function(e) NA_real_)
    nsim <- input$ovnsim; nn <- npoints(X)
    nulldeg <- numeric(0); nullar <- numeric(0); p_deg <- NA_real_; p_ar <- NA_real_
    if (nsim > 0) {
      nulldeg <- numeric(nsim); nullar <- numeric(nsim)
      for (k in seq_len(nsim)) {
        set.seed(9000 + k)
        Xk <- ppp(runif(nn, 0, 10), runif(nn, 0, 25), window = WIN)
        m  <- overlap_metrics(Xk, r, b)
        nulldeg[k] <- m$degree; nullar[k] <- m$oarea
      }
      p_deg <- (1 + sum(nulldeg >= obs$degree)) / (nsim + 1)
      p_ar  <- (1 + sum(nullar  >= obs$oarea )) / (nsim + 1)
    }
    list(X = X, r = r, R = R, b = b, obs = obs, cover = cover, sub = sub,
         n0 = n0, nulldeg = nulldeg, nullar = nullar, p_deg = p_deg, p_ar = p_ar,
         nsim = nsim)
  })

  output$ovmap <- renderPlot({
    v <- ovres(); X <- v$X
    plot(WIN, main = sprintf("Neighbourhood overlap — buffer b = %.2f m   (n = %d%s)",
                             v$b, npoints(X), if (v$sub) ", subsampled" else ""))
    symbols(X$x, X$y, circles = v$R, add = TRUE, inches = FALSE,
            fg = adjustcolor("#4E8FC2", 0.6), bg = adjustcolor("#4E8FC2", 0.10))
    symbols(X$x, X$y, circles = v$r, add = TRUE, inches = FALSE,
            fg = NA, bg = adjustcolor("#b5482f", 0.65))
    axis(1); axis(2); title(xlab = "x (m)", ylab = "y (m)")
    legend("topright", bty = "n", pch = 21, pt.cex = 1.6,
           pt.bg = c(adjustcolor("#b5482f", 0.65), adjustcolor("#4E8FC2", 0.10)),
           col   = c(NA, adjustcolor("#4E8FC2", 0.6)),
           legend = c("colony footprint (r)", "buffer halo (r + b)"))
  })

  output$ovsummary <- renderPrint({
    v <- ovres(); o <- v$obs
    cat("Colonies:            ", v$n0,
        if (v$sub) "  (analysis on a random 1200 for speed)" else "", "\n")
    cat(sprintf("Equivalent radius:    median %.3f m   (from colony area)\n",
                median(v$r)))
    cat(sprintf("Buffer width b:       %.2f m\n", v$b))
    cat("\n====  NEIGHBOURHOOD CO-OCCURRENCE  ====\n")
    cat(sprintf("  Overlapping neighbour pairs:  %d\n", o$pairs))
    cat(sprintf("  Mean neighbours per colony:   %.2f\n", o$degree))
    cat(sprintf("  Total overlap area:           %.3f m^2\n", o$oarea))
    if (!is.na(v$cover))
      cat(sprintf("  Halo coverage of plot:        %.1f%% of 250 m^2\n", 100 * v$cover))
    if (v$nsim > 0) {
      cat(sprintf("\n----  vs a random (CSR) layout, same colonies & sizes (%d sims)  ----\n",
                  v$nsim))
      cat(sprintf("  Mean neighbours:  observed %.2f   CSR mean %.2f   p = %.4g\n",
                  o$degree, mean(v$nulldeg), v$p_deg))
      cat(sprintf("  Overlap area:     observed %.3f   CSR mean %.3f   p = %.4g\n",
                  o$oarea, mean(v$nullar), v$p_ar))
      verdict <- if (v$p_deg <= 0.05) "MORE overlap than random — neighbourhoods crowd (aggregated)"
                 else if (v$p_deg >= 0.95) "LESS overlap than random — neighbourhoods avoid each other"
                 else "overlap consistent with a random layout"
      cat(sprintf("  ->  %s\n", verdict))
    } else {
      cat("\n(Set the null simulations above 0 to test overlap against a random layout.)\n")
    }
    if (o$pairs == 0)
      cat("\nNo neighbourhoods overlap at this buffer — increase b to grow the zone of influence.\n")
  })

  output$ovnull <- renderPlot({
    v <- ovres()
    if (v$nsim <= 0) {
      plot.new(); text(0.5, 0.5, "Null simulations = 0 — no envelope to show.", cex = 1.1)
      return(invisible())
    }
    xr <- range(c(v$nulldeg, v$obs$degree))
    hist(v$nulldeg, breaks = 15, col = "grey85", border = "white", xlim = xr,
         main = "Mean neighbours per colony: random (CSR) null vs observed",
         xlab = "mean neighbours per colony")
    abline(v = v$obs$degree, col = "#b5482f", lwd = 3)
    legend("topright", bty = "n", lwd = 3, col = "#b5482f", legend = "observed")
  })
}

shinyApp(ui, server)
