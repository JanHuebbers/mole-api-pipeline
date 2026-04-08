# src/R/LoadConfig.R  (or keep your filename, but RunSetup must source the same)

# ---- config_path is expected to be defined by RunSetup.R ----
if (!exists("config_path") || is.null(config_path) || !nzchar(config_path)) {
  stop("❌ config_path not set (expected RunSetup.R to define it).")
}
if (!file.exists(config_path)) {
  stop("❌ Config file not found: ", config_path)
}

if (!requireNamespace("yaml", quietly = TRUE)) {
  stop("Please install the yaml package")
}

params <- yaml::read_yaml(config_path)

# ---- helpers ----
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# ---- global parameters (with defaults) ----
WiP1      <- params$WiP1      %||% 10
HiP1      <- params$HiP1      %||% 8
WiP2      <- params$WiP2      %||% 10
sep       <- params$sep       %||% ","
ItalChars <- params$ItalChars %||% 2

at <- params$AxisTitle %||% ""
axis_title_expr <- tryCatch(
  as.expression(parse(text = at)),
  error = function(e) expression("")
)
