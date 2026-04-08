# RunSetup.R

# Get directory of this script (works under Rscript)
argv <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", argv, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg) else ""
RDIR <- if (nzchar(this_file)) dirname(normalizePath(this_file)) else getwd()

# ---- Load core packages + theme
source(file.path(RDIR, "LoadPackages.R"))
source(file.path(RDIR, "ggPlotTheme.R"))

# ---- Parse args (config is first; keep the rest for the plot script)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Please provide config path as first argument")
config_path <- args[1]
args_extra  <- if (length(args) > 1) args[-1] else character(0)

# ---- Load config (expects config_path)
source(file.path(RDIR, "LoadConfig.R"))

message("✅ Environment initialized: Packages loaded, theme applied, config loaded.")
