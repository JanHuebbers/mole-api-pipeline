# src/R/P2_poreprofile_merged.R
#
# ────────────────────────────────────────────────────────────────────────────────
# Purpose
#   Create a single "merged" pore profile plot from multiple samples (PDBs),
#   using the combined table (results/pore_data_long.csv) and filters from config.yaml.
#
#   Aesthetics:
#     - Fill color: seed (stable gradient via fixed seed_levels)
#     - Shape:      jobID (stable mapping via fixed job_levels -> shape_pool)
#
# Expected args from Snakemake / python wrapper:
#   1) <config.yml>
#   2) <pore_data_long.csv>
#   3) <out_rel.svg>
#   4) <out.rds>
# ────────────────────────────────────────────────────────────────────────────────


# ────────────────────────────────────────────────────────────────────────────────
# 1) Parse arguments + load packages/theme/config (via RunSetup.R)
# ────────────────────────────────────────────────────────────────────────────────
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6) {
  stop("Usage: Rscript P2_poreprofile_merged.R <config.yml> <pore_data_long.csv> <output_T.svg> <output_T.rds> <output_D.svg> <output_D.rds>")
}

source("src/R/RunSetup.R")

# args_extra comes from RunSetup.R (everything after config path)
if (length(args_extra) != 5) {
  stop("Expected 5 extra arguments after config path")
}

input_csv <- args_extra[1]
out_T_svg <- args_extra[2]
out_T_rds <- args_extra[3]
out_D_svg <- args_extra[4]
out_D_rds <- args_extra[5]

# ────────────────────────────────────────────────────────────────────────────────
# 2) Import merged pore data (results/pore_data_long.csv) and parse IDs from sample
# ────────────────────────────────────────────────────────────────────────────────
if (!file.exists(input_csv)) {
  stop("❌ Input CSV not found: ", input_csv)
}

pore_data_R <- readr::read_csv(input_csv, show_col_types = FALSE, progress = FALSE) %>%
  tidyr::separate_wider_delim(
    sample,
    names = c("runID", "jobID", "seed", "modelID"),
    delim = "_",
    too_many = "merge",
    cols_remove = FALSE
  ) %>%
  dplyr::mutate(
    runID   = as.character(runID),
    jobID   = sprintf("%02d", as.integer(jobID)),
    seed    = as.character(seed),
    modelID = as.character(modelID)
  ) %>%
  dplyr::group_by(sample) %>%
  dplyr::mutate(
    T        = max(T, na.rm = TRUE) - T
  ) %>%
  dplyr::ungroup() %>%
  dplyr::arrange(sample, T)

# ────────────────────────────────────────────────────────────────────────────────
# 3) Apply config filters (plot_filters in config.yaml)
#    - Empty list => no filter on that dimension
#    - Lists combine with AND across dimensions
# ────────────────────────────────────────────────────────────────────────────────
pf <- params$plot_filters %||% list()

run_ids   <- pf$run_ids   %||% character()
job_ids   <- pf$job_ids   %||% character()
seed_ids  <- pf$seed_ids  %||% character()
model_ids <- pf$model_ids %||% character()

# normalize filter job IDs too
if (length(job_ids) > 0) job_ids <- sprintf("%02d", as.integer(job_ids))

# Always apply run/job filters first (AND logic)
pore_data_f <- pore_data_R %>%
  dplyr::filter(
    (length(run_ids) == 0 | runID %in% run_ids),
    (length(job_ids) == 0 | jobID %in% job_ids)
  )

# ✅ Paired seed-model filtering (OR across pairs)
seed_model <- pf$seed_model %||% NULL

if (!is.null(seed_model) && length(seed_model) > 0) {

  keep <- rep(FALSE, nrow(pore_data_f))

  for (s in names(seed_model)) {
    models <- seed_model[[s]] %||% character()
    models <- as.character(models)

    # allow either single string or list
    keep <- keep | (pore_data_f$seed == as.character(s) & pore_data_f$modelID %in% models)
  }

  pore_data_f <- pore_data_f[keep, , drop = FALSE]

} else {
  # fallback: independent lists (original behavior)
  pore_data_f <- pore_data_f %>%
    dplyr::filter(
      (length(seed_ids)  == 0 | seed    %in% seed_ids),
      (length(model_ids) == 0 | modelID %in% model_ids)
    )
}

message("✅ Filtered pore data: ", nrow(pore_data_f), " rows (from ", nrow(pore_data_R), ")")

##### Invert distance values and align values at bottleneck (minD=0) for better comparison across samples
pore_data_f <- pore_data_f %>%
  dplyr::group_by(sample) %>%
  dplyr::mutate(
    Distance_inv = max(Distance, na.rm = TRUE) - Distance
  ) %>%
  dplyr::mutate(
    Distance_ref = Distance_inv[which.min(Radius)][1],
    Distance     = Distance_inv - Distance_ref
  ) %>%
  dplyr::ungroup() %>%
  dplyr::select(-Distance_inv, -Distance_ref)

# ────────────────────────────────────────────────────────────────────────────────
# 4) Fixed level definitions for consistent aesthetics (seed gradient + job shapes)
# ────────────────────────────────────────────────────────────────────────────────
# Define seed levels for consistent plotting of AF3 model pores
gradient_seeds <- c(
  "1710", "1711", "1712",
  "1701", "1702", "1703", "1704", "1705", "1706",
  "1707", "1708", "1709"
)

# Production seeds (XXXX), where XXXX is the productionID
# Define custom colors for individual seeds
fixed_seed_cols <- c(
  "0001" = "#2D7F83",
  "0002" = "#939E69",
  "0003" = "#FABE50",
  "0004" = "#D88853",
  "0003" = "#B65256"
  "0004" = "#646567",
  "0005" = "#407FB7",
  "0006" = "#00B1B7",
  "0007" = "#834E75",
  "0008" = "#8DC060",
  "0009" = "#FFF055"
)

gradient_cols <- setNames(
  colorRampPalette(c("#0098A1", "#F6A800"))(length(gradient_seeds)),
  gradient_seeds
)

seed_col_map <- c(gradient_cols, fixed_seed_cols)

# ────────────────────────────────────────────────────────────────────────────────
# 5) Plotting function (relative pore outline, merged samples)
# ────────────────────────────────────────────────────────────────────────────────
plot_fun <- function(data, x, y, ytitle, y_breaks = seq(0.0, 1.00, 0.1), y_limits = c(-0.05, 1.05))
{
  # Shape pool and jobID levels:
  # - jobID is normalized to "01".."30"
  # - factor level order fixes which shape each jobID gets (e.g. "08" -> shape 4)
  shape_pool <- c(15, 13, 28, 11, 23, 1, 2, 4, 5, 29, 24, 27,
                  3, 6, 7, 8, 9, 10, 12, 14, 16, 17, 18, 19,
                  20, 21, 22, 25, 26, 30)

  job_levels <- sprintf("%02d", seq_along(shape_pool))

  data <- data %>%
    dplyr::mutate(
      seed  = sprintf("%04d", as.integer(seed)),
      jobID = sprintf("%02d", as.integer(jobID)),
      jobID = factor(jobID, levels = job_levels, ordered = TRUE),
      fill_col = seed_col_map[seed]
    )

  ggplot(data = data, aes(x = .data[[x]], y = .data[[y]])) +
    ggstar::geom_star(
      aes(
        starshape = jobID,
        fill      = fill_col
      ),
      alpha = 0.3,
      size = 0.4,
      color = "#000000",
      starstroke = 0.1
    ) +
    scale_fill_identity(na.value = "white") +
    scale_x_continuous(
      limits = c(-0.05, 10.05),
      name   = axis_title_expr,
      expand = c(0.03, 0.03)
    ) +
    scale_y_continuous(
      breaks = y_breaks,
      limits = y_limits,
      name   = ytitle,
      expand = c(0.001, 0.001)
    ) +
    scale_starshape_manual(values = setNames(shape_pool, job_levels)) +
    guides(
      fill = "none", color = "none", size = "none",
      shape = "none", starshape = "none", alpha = "none"
    )
}

# ────────────────────────────────────────────────────────────────────────────────
# 6) Generate plot (relative position)
# ────────────────────────────────────────────────────────────────────────────────
plot_T <- plot_fun(
  pore_data_f,
  x        = "Radius",
  y        = "T",
  ytitle   = "Relative position"
)

plot_D <- plot_fun(
  pore_data_f,
  x        = "Radius",
  y        = "Distance",
  ytitle   = expression(paste(bold("Distance"), plain(" [Å]"))),
  y_breaks = seq(-40.00, 20.00, 5.00),
  y_limits = c(-41.00, 21.00)
)

# ────────────────────────────────────────────────────────────────────────────────
# 7) Write outputs (SVG + RDS)
# ────────────────────────────────────────────────────────────────────────────────
dir.create(dirname(out_T_svg), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(out_T_rds),     recursive = TRUE, showWarnings = FALSE)

ggsave(
  filename  = out_T_svg,
  plot      = plot_T,
  width     = WiP1,
  height    = HiP1,
  units     = "cm",
  limitsize = FALSE
)

saveRDS(list(plot_T = plot_T), file = out_T_rds)

###################################################################################

dir.create(dirname(out_D_svg), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(out_D_rds),     recursive = TRUE, showWarnings = FALSE)

ggsave(
  filename  = out_D_svg,
  plot      = plot_D,
  width     = WiP1,
  height    = HiP1,
  units     = "cm",
  limitsize = FALSE
)

saveRDS(list(plot_D = plot_D), file = out_D_rds)


# ────────────────────────────────────────────────────────────────────────────────
# ✅ Done
# ────────────────────────────────────────────────────────────────────────────────
