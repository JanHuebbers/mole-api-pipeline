# src/R/P1_poreprofile_perPDB.R

# ────────────────────────────────────────────────────────────────────────────────
# Parse arguments, load packages/theme **and** config (via RunSetup.R)
# Expected args from Snakemake / python wrapper:
#   1) <config.yml>
#   2) <input_pore_data.csv>
#   3) <out_rel.svg>
#   4) <out.rds>
#   5) <out_csv>
#   6) <sample>
# ────────────────────────────────────────────────────────────────────────────────
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6) {
  stop("Usage: Rscript P1_poreprofile_perPDB.R <config.yml> <pore_data.csv> <out_abs.svg> <out.rds> <out_csv> <sample>")
}

# This pulls in 03.00_RunSetup.R which sources LoadPackages.R, ggPlotTheme.R, LoadConfig.R
# RunSetup.R also defines: config_path (args[1]) and args_extra (args[-1])
source("src/R/RunSetup.R")

# args_extra comes from RunSetup.R (everything after config path)
input_csv    <- args_extra[1]
out_svg_rel  <- args_extra[2]
out_rds      <- args_extra[3]
out_csv      <- args_extra[4]
sample_id    <- args_extra[5]

# ────────────────────────────────────────────────────────────────────────────────
# 📥 Import per-sample pore data (from results/<sample>/pore_data.csv)
# ────────────────────────────────────────────────────────────────────────────────
if (!file.exists(input_csv)) {
  stop("❌ Pore data CSV not found: ", input_csv)
}

pore_data_R <- readr::read_csv(
  file = input_csv, show_col_types = FALSE, progress = FALSE
) %>%
  separate_wider_delim(
    sample,
    names = c("runID", "jobID", "seed", "modelID"),
    delim = "_",
    too_many = "merge",
    cols_remove = FALSE
  ) %>%
  group_by(sample) %>%  # harmless even if there’s only one sample in the file
  mutate(
    T        = max(T,        na.rm = TRUE) - T,
    Distance = max(Distance, na.rm = TRUE) - Distance
  ) %>%
  ungroup() %>%
  arrange(sample, T)     # keeps the table ordered “bottom to top” after flipping

message("✅ Imported pore data: ", nrow(pore_data_R), " rows from ", input_csv)

# export processed table (Snakemake decides the path)
dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(pore_data_R, out_csv)

# ────────────────────────────────────────────────────────────────────────────────
# Fixed level definitions for consistent aesthetics (seed gradient + job shapes)
# ────────────────────────────────────────────────────────────────────────────────
# Define seed levels for consistent plotting of AF3 model pores
gradient_seeds <- c(
  "1710", "1711", "1712",
  "1701", "1702", "1703", "1704", "1705", "1706",
  "1707", "1708", "1709"
)

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
# 📈 Plotting Function
# ────────────────────────────────────────────────────────────────────────────────
plot_fun <- function(data, x, y, ytitle) {

  # Ensure jobID is treated as discrete
  data <- data %>% dplyr::mutate(jobID = as.character(jobID))

  # Map concrete jobIDs -> concrete shapes (stable within this plot)
  
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
      breaks = seq(0.0, 1.00, 0.1),
      limits = c(-0.05, 1.05),
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
# 🖼 Generate Plots (relative + absolute distance)
# ────────────────────────────────────────────────────────────────────────────────
plot_T <- plot_fun(
  pore_data_R,
  x      = "Radius",
  y      = "T",
  ytitle = "Relative position"
)

# Ensure output dirs exist
dir.create(dirname(out_svg_rel), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(out_rds),     recursive = TRUE, showWarnings = FALSE)

# Save SVGs (Snakemake paths)
ggsave(
  filename = out_svg_rel,
  plot     = plot_T,
  width    = WiP1,
  height   = HiP1,
  units    = "cm",
  limitsize = FALSE
)

# Save RDS (both plots)
saveRDS(list(plot_T = plot_T), file = out_rds)

# ────────────────────────────────────────────────────────────────────────────────
# ✅ Done
# ────────────────────────────────────────────────────────────────────────────────
