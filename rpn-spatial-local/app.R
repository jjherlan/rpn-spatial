# =====================================================================
# Rapa Nui coral spatial pattern — Pocillopora colony dispersion
# Shinylive (runs entirely in the browser via WebR — no install, no server)
# Proof-of-concept for SCCS-NY 2026 hands-on workshop.
# Data: pre-extracted, size-filtered colony centroids (x, y in metres)
#       from manual segmentation of large-area-imaging orthomosaics.
#       Three reef sites along a wave-exposure gradient (Herlan et al., ch.2).
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

# --- UI --------------------------------------------------------------
ui <- fluidPage(
  tags$head(tags$style(HTML(
    ".well{background:#f4f8f5} h4{color:#1b5e3f;margin-top:0}"))),
  titlePanel("Rapa Nui coral spatial pattern — Pocillopora dispersion"),
  helpText("From photos to spatial pattern: each point is a coral colony extracted",
           "from a segmented large-area-imaging orthomosaic. Pick a site, then ask:",
           "are the colonies clustered, random, or over-dispersed — and how does that",
           "change along the wave-exposure gradient?"),
  sidebarLayout(
    sidebarPanel(
      selectInput("site", "Reef site (wave-exposure gradient)", choices = sites),
      tags$hr(),
      h4("Quadrat CSR test"),
      sliderInput("nx", "Quadrats across plot width (x)",  2, 10, 4),
      sliderInput("ny", "Quadrats down plot length (y)",   2, 20, 10),
      tags$hr(),
      h4("Distance function + CSR envelope"),
      radioButtons("fun", "Function",
                   c("L-function  L(r)" = "L", "Pair correlation  g(r)" = "pcf")),
      sliderInput("rmax", "Max distance r (m)", 0.5, 5, 2.5, step = 0.5),
      sliderInput("nsim", "CSR simulations (envelope)", 0, 199, 39, step = 10),
      conditionalPanel(
        "input.site == 'vhu.csv'",
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

  # full point pattern for the selected site
  pp <- reactive({
    df <- read.csv(input$site)
    ppp(df$x, df$y, window = WIN)
  })

  # pattern used for the (heavier) envelope — optionally subsampled for Vaihu
  ppUse <- reactive({
    X <- pp()
    if (isTRUE(input$sub) && input$site == "vhu.csv" && npoints(X) > 800) {
      set.seed(42)
      X <- X[sample(npoints(X), 800)]
    }
    X
  })

  output$map <- renderPlot({
    X <- pp()
    plot(X, main = paste0(site_label(input$site), "   (n = ", npoints(X), ")"),
         pch = 19, cex = 0.45, cols = "#1b7837")
    axis(1); axis(2)
    title(xlab = "x (m)", ylab = "y (m)")
  })

  output$summary <- renderPrint({
    X   <- pp()
    lam <- intensity(X)
    ce  <- clarkevans(X)[["naive"]]
    cet <- clarkevans.test(X, alternative = "two.sided", nsim = 99)
    qt  <- quadrat.test(X, nx = input$nx, ny = input$ny)
    nnd <- nndist(X)
    verdict <- if (ce < 1) "CLUSTERED (aggregated)" else
               if (ce > 1) "REGULAR (over-dispersed)" else "RANDOM"

    cat("Site:      ", site_label(input$site), "\n")
    cat("Colonies:  ", npoints(X), "\n")
    cat("Plot:       10 x 25 m  (250 m^2)\n")
    cat(sprintf("Intensity:  %.3f colonies / m^2\n", lam))
    cat(sprintf("Mean nearest-neighbour distance: %.3f m\n\n", mean(nnd)))
    cat("-- Clark-Evans aggregation index --\n")
    cat(sprintf("  R = %.3f  ->  %s\n", ce, verdict))
    cat(sprintf("  test p-value (two-sided, 99 sims) = %.4g\n\n", cet$p.value))
    cat(sprintf("-- Quadrat chi-square test of CSR (%d x %d grid) --\n",
                input$nx, input$ny))
    cat(sprintf("  chi-sq = %.1f,  p-value = %.4g\n", qt$statistic, qt$p.value))
    cat("  (small p = significant departure from complete spatial randomness)\n")
  })

  # envelope computed only when the button is pressed
  env <- eventReactive(input$go, {
    X   <- ppUse()
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
