# =====================================================================
# Rapa Nui coral spatial pattern — Pocillopora colony dispersion
# Shinylive (runs entirely in the browser via WebR — no install, no server)
# Hands-on app for the SCCS-NY 2026 workshop.
#
# Two modes:
#   * Real reef data  — size-filtered colony centroids from large-area
#                       imaging at three Rapa Nui sites (Herlan et al. 2026).
#   * Simulation      — an idealized sandbox: set the number of colonies and
#                       two environmental knobs (wave exposure, structural
#                       complexity); clustering rises with both. This is a
#                       hypothesis to explore, NOT the Rapa Nui result.
#
# Primary dispersion metric = variance-to-mean ratio (VMR), as in the paper;
# Clark-Evans shown as a complementary nearest-neighbour view.
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

# --- Idealized cluster generator -------------------------------------
# clus in [0,1]: 0 = complete spatial randomness, 1 = tight clusters.
# Exactly N points placed in the 10 x 25 m window (rejection-sampled).
simulate_colonies <- function(N, clus, seed = 1) {
  set.seed(seed)
  if (N <= 0) return(ppp(numeric(0), numeric(0), window = WIN))
  if (clus < 0.04) {                                   # ~CSR
    return(ppp(runif(N, 0, 10), runif(N, 0, 25), window = WIN))
  }
  nparents <- max(3, round(N * (1 - clus) * 0.30))      # fewer parents = more clustered
  nparents <- min(nparents, N)
  px <- runif(nparents, 0, 10); py <- runif(nparents, 0, 25)
  pid <- sample(seq_len(nparents), N, replace = TRUE)
  sdx <- 0.15 + (1 - clus) * 1.50                       # spread shrinks as clus rises
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

# --- UI --------------------------------------------------------------
ui <- fluidPage(
  tags$head(tags$style(HTML(
    ".well{background:#f4f8f5} h4{color:#1b5e3f;margin-top:0}"))),
  titlePanel("Rapa Nui coral spatial pattern — Pocillopora dispersion"),
  helpText("Each point is a coral colony. Explore the real reef data, or switch to the",
           "simulation sandbox to build your own pattern. Then read the dispersion",
           "statistics and the distance function to decide: clustered, random, or over-dispersed?"),
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
        h4("Build a pattern"),
        sliderInput("Nsim", "Number of colonies", min = 0, max = 500, value = 150, step = 10),
        sliderInput("exposure", "Wave exposure", min = 0, max = 100, value = 50),
        sliderInput("complexity", "Structural complexity", min = 0, max = 100, value = 50),
        actionButton("resim", "Resample", class = "btn-default"),
        helpText("Idealized sandbox: clustering rises with exposure AND complexity ",
                 "— a hypothesis to explore, not the Rapa Nui result.")
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
      helpText("Summary stats update instantly; the envelope runs when you click.")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Point map",        plotOutput("map",     height = "620px")),
        tabPanel("Summary",          verbatimTextOutput("summary")),
        tabPanel("Distance function",
                 plotOutput("envplot", height = "500px"),
                 uiOutput("envnote"))
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
      clus <- (input$exposure + input$complexity) / 200
      simulate_colonies(input$Nsim, clus, seed = 1000 + seedval())
    } else {
      df <- read.csv(input$site)
      ppp(df$x, df$y, window = WIN)
    }
  })

  # label describing the current pattern
  cur_label <- reactive({
    if (input$mode == "sim")
      sprintf("Simulation — exposure %d, complexity %d", input$exposure, input$complexity)
    else site_label(input$site)
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

    cat(sprintf("Intensity:  %.3f colonies / m^2\n\n", lam))
    cat("====  DISPERSION  —  variance-to-mean ratio (VMR)  ====\n")
    cat(sprintf("  VMR = %.2f   over %d quadrats (%d x %d grid)\n",
                vmr, ncell, input$nx, input$ny))
    cat(sprintf("  ->  %s\n", vmr_verdict))
    cat(sprintf("  Quadrat chi-square test of CSR:  chi-sq = %.1f,  p = %.4g\n",
                qt$statistic, qt$p.value))
    cat("  (VMR > 1 = clustered; small p = departs from randomness)\n\n")

    cat("----  Nearest-neighbour view: Clark-Evans index  ----\n")
    cat(sprintf("  R = %.3f   (%s at nearest-neighbour scale)\n", ce, ce_verdict))
    cat(sprintf("  Mean nearest-neighbour distance = %.3f m;  test p = %.4g\n",
                mean(nnd), cet$p.value))
    cat("  Note: R and VMR can disagree — they measure different scales.\n")
    cat("  At exposed Vaihu, R reads over-dispersed (tight local packing)\n")
    cat("  while VMR reads clustered (plot-scale patchiness). The paper uses VMR.\n")
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
}

shinyApp(ui, server)
