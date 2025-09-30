# Parse positional arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 7) {
  stop("Usage: Rscript script.R <BASE_DIR> <SAMPLE_SHEET> <QUAST_DIR> <MLST_DIR> <RMLST_DIR> <PLASMID_DIR> <AMR_DIR>")
}

BASE_DIR     <- args[1]
SAMPLE_SHEET <- args[2]
QUAST_DIR    <- args[3]
MLST_DIR     <- args[4]
RMLST_DIR    <- args[5]
PLASMID_DIR  <- args[6]
AMR_DIR      <- args[7]

cat("BASE_DIR:     ", BASE_DIR, "\n")
cat("SAMPLE_SHEET: ", SAMPLE_SHEET, "\n")
cat("QUAST_DIR:    ", QUAST_DIR, "\n")
cat("MLST_DIR:     ", MLST_DIR, "\n")
cat("RMLST_DIR:    ", RMLST_DIR, "\n")
cat("PLASMID_DIR:  ", PLASMID_DIR, "\n")
cat("AMR_DIR:      ", AMR_DIR, "\n")

# =========================================================
# 📦 Packages
# =========================================================
suppressPackageStartupMessages({
  if (!requireNamespace("readr",  quietly = TRUE)) install.packages("readr")
  if (!requireNamespace("dplyr",  quietly = TRUE)) install.packages("dplyr")
  if (!requireNamespace("tibble", quietly = TRUE)) install.packages("tibble")
  if (!requireNamespace("purrr",  quietly = TRUE)) install.packages("purrr")
  if (!requireNamespace("stringr",quietly = TRUE)) install.packages("stringr")
})
library(readr); library(dplyr); library(tibble); library(purrr); library(stringr)

# =========================================================
# 🧱 Final report columns (underscored by design)
# =========================================================
final_columns <- c(
  "Lab_ID",
  "Original_ID",
  "Index",
  "Platform",
  "Contig_Num",
  "Genome_Length",
  "N50",
  "Depth",
  "GC_percent",
  "Largest_Contig",
  "Expected_Organism",
  "Organism",
  "ST",
  "Clonal_Complex",
  "Plasmid_PlasmidFinder",
  "ARGs_gt90cov_gt90ID_AMRFinderPlus",
  "Point_Mutations",
  "Predicted_Phenotype",
  "Virulence_Genes_gt90cov_gt90ID_AMRFinderPlus",
  "Comments"
)

# =========================================================
# 🔎 Utility helpers
# =========================================================
find_isolate_file <- function(dir_path, isolate_id, suffix_regex = ".*\\.(tsv|txt)$") {
  patt  <- paste0("^", isolate_id, suffix_regex)
  files <- list.files(dir_path, pattern = patt, full.names = TRUE, ignore.case = TRUE)
  if (length(files) >= 1) files[1] else NA_character_
}

# -------- QUAST: robust reader (2-col key/value OR wide) --------
read_quast_metrics <- function(tsv_path) {
  needed <- c("# contigs","Total length","N50","Avg. coverage depth","GC (%)","Largest contig")
  if (!file.exists(tsv_path)) return(setNames(as.list(rep(NA, length(needed))), needed))
  df <- suppressMessages(readr::read_tsv(tsv_path, show_col_types = FALSE, progress = FALSE))
  
  # Case 1: 2-column key/value table
  if (ncol(df) == 2) {
    keys <- trimws(as.character(df[[1]]))
    vals <- df[[2]]; names(vals) <- keys
    out <- setNames(vector("list", length(needed)), needed)
    for (k in needed) out[[k]] <- if (k %in% names(vals)) vals[[k]] else NA
    return(out)
  }
  
  # Case 2: wide table with columns
  out <- setNames(vector("list", length(needed)), needed)
  for (k in needed) out[[k]] <- if (k %in% names(df)) df[[k]][1] else NA
  out
}

# -------- MLST: ST from row 2, col 3 --------
read_mlst_st <- function(tsv_path) {
  if (!file.exists(tsv_path)) return(NA_character_)
  df <- tryCatch(
    utils::read.delim(tsv_path, sep = "\t", header = FALSE,
                      stringsAsFactors = FALSE, quote = "", comment.char = "",
                      fill = TRUE, check.names = FALSE),
    error = function(e) NULL
  )
  if (is.null(df) || nrow(df) < 2) return(NA_character_)
  if (ncol(df) >= 3 && !is.na(df[2,3]) && nzchar(df[2,3])) return(as.character(df[2,3]))
  row2 <- paste(df[2, ], collapse = " ")
  m <- stringr::str_extract(row2, "(?<!\\d)\\d+(?!\\d)")
  ifelse(is.na(m) || m == "", NA_character_, m)
}

# -------- rMLST: Organism from 'Taxon' --------
read_rmlst_taxon <- function(tsv_path) {
  if (!file.exists(tsv_path)) return(NA_character_)
  df <- tryCatch(readr::read_tsv(tsv_path, show_col_types = FALSE, progress = FALSE),
                 error = function(e) NULL)
  if (is.null(df) || !"Taxon" %in% names(df) || nrow(df) < 1) return(NA_character_)
  val <- df$Taxon[1]
  ifelse(is.na(val) || val == "", NA_character_, as.character(val))
}

# -------- PlasmidFinder: within-contig "/" (keep dupes); between-contigs "; " --------
read_plasmid_list <- function(tsv_path) {
  if (!file.exists(tsv_path)) return(NA_character_)
  df <- tryCatch(readr::read_tsv(tsv_path, show_col_types = FALSE, progress = FALSE),
                 error = function(e) NULL)
  if (is.null(df) || !"Plasmid" %in% names(df) || nrow(df) == 0) return(NA_character_)
  df <- df %>%
    mutate(Plasmid = as.character(Plasmid),
           Contig  = if ("Contig" %in% names(.)) as.character(Contig) else NA_character_) %>%
    filter(!is.na(Plasmid), nzchar(Plasmid))
  if (nrow(df) == 0) return(NA_character_)
  if ("Contig" %in% names(df) && any(!is.na(df$Contig))) {
    per_contig <- df %>% group_by(Contig) %>% summarise(merged = paste(Plasmid, collapse = "/"), .groups = "drop") %>% arrange(Contig)
    paste(per_contig$merged, collapse = "; ")
  } else paste(df$Plasmid, collapse = "; ")
}

# -------- AMRFinderPlus: flexible (keeps duplicates; order preserved) --------
# Filters:
#   Scope == scope_wanted
#   Type  == type_wanted
#   (optional) Subtype %in% subtype_wanted
#   coverage of reference >= 90
#   %identity of reference >= 90
# Output column: "Element symbol" or "Subclass"
read_amr_column <- function(txt_path, scope_wanted, type_wanted, subtype_wanted = NULL, out_col = "Element symbol") {
  if (!file.exists(txt_path)) return(NA_character_)
  df <- tryCatch(readr::read_tsv(txt_path, show_col_types = FALSE, progress = FALSE),
                 error = function(e) NULL)
  if (is.null(df) || nrow(df) == 0) return(NA_character_)
  
  nms <- names(df); nms_lc <- tolower(nms)
  col_idx <- function(pattern) { i <- which(grepl(pattern, nms_lc, perl = TRUE)); if (length(i)) i[1] else NA_integer_ }
  
  i_out   <- col_idx(paste0("^", tolower(out_col), "$"))
  i_scope <- col_idx("^scope$")
  i_type  <- col_idx("^type$")
  i_subty <- col_idx("^subtype$")
  i_cov   <- col_idx("coverage.*reference")
  i_id    <- col_idx("%?identity.*reference")
  
  if (any(is.na(c(i_out, i_scope, i_type, i_cov, i_id)))) return(NA_character_)
  
  outval <- as.character(df[[i_out]])
  scope  <- as.character(df[[i_scope]])
  type_  <- as.character(df[[i_type]])
  subty  <- if (!is.na(i_subty)) as.character(df[[i_subty]]) else rep(NA_character_, length(outval))
  cov_num <- suppressWarnings(readr::parse_number(as.character(df[[i_cov]])))
  id_num  <- suppressWarnings(readr::parse_number(as.character(df[[i_id]])))
  
  keep <- !is.na(outval) & nzchar(outval) &
    scope == scope_wanted & type_ == type_wanted &
    !is.na(cov_num) & cov_num >= 90 &
    !is.na(id_num)  & id_num  >= 90
  
  if (!is.null(subtype_wanted)) keep <- keep & !is.na(subty) & subty %in% subtype_wanted
  
  idx <- which(keep)
  if (!length(idx)) return(NA_character_)
  paste(outval[idx], collapse = ", ")
}

# =========================================================
# 📥 Read sample sheet (expects NEW column names!)
# =========================================================
sample_df <- readr::read_csv(SAMPLE_SHEET, show_col_types = FALSE, progress = FALSE, trim_ws = TRUE)

# Required headers in sample_sheet.csv:
# Lab_ID, Original_ID, Index, Platform, Expected_Organism, Comments
req_cols <- c("Lab_ID", "Original_ID", "Index", "Platform", "Expected_Organism", "Comments")
missing <- setdiff(req_cols, names(sample_df))
if (length(missing)) stop(sprintf("Missing expected columns in sample_sheet.csv: %s", paste(missing, collapse = ", ")))

# =========================================================
# 🏗️ Build each part
# =========================================================
# Base columns (directly use final names)
base_part <- sample_df %>%
  transmute(
    Lab_ID,
    Original_ID,
    Index,
    Platform,
    Expected_Organism,
    Comments
  )

# QUAST → assembly metrics
quast_to_final <- c(
  "# contigs"           = "Contig_Num",
  "Total length"        = "Genome_Length",
  "N50"                 = "N50",
  "Avg. coverage depth" = "Depth",
  "GC (%)"              = "GC_percent",
  "Largest contig"      = "Largest_Contig"
)
quast_part <- purrr::map_dfr(base_part$Lab_ID, function(iso_id) {
  tsv <- find_isolate_file(QUAST_DIR, iso_id, suffix_regex = ".*\\.tsv$")
  met <- read_quast_metrics(tsv)
  vals <- setNames(vector("list", length(quast_to_final)), unname(quast_to_final))
  for (k in names(quast_to_final)) vals[[ quast_to_final[[k]] ]] <- met[[k]]
  tibble::as_tibble(vals)
})

# rMLST → Organism
org_col <- tibble(
  Organism = purrr::map_chr(base_part$Lab_ID, function(iso_id) {
    tsv <- find_isolate_file(RMLST_DIR, iso_id, suffix_regex = ".*_rmlst\\.tsv$")
    read_rmlst_taxon(tsv)
  })
)

# MLST → ST
st_col <- tibble(
  ST = purrr::map_chr(base_part$Lab_ID, function(iso_id) {
    tsv <- find_isolate_file(MLST_DIR, iso_id, suffix_regex = ".*\\.tsv$")
    read_mlst_st(tsv)
  })
)

# PlasmidFinder → Plasmid_PlasmidFinder
plasmid_col <- tibble(
  Plasmid_PlasmidFinder = purrr::map_chr(base_part$Lab_ID, function(iso_id) {
    tsv <- find_isolate_file(PLASMID_DIR, iso_id, suffix_regex = ".*\\.tsv$")
    read_plasmid_list(tsv)
  })
)

# AMRFinderPlus:
amr_col <- tibble(
  ARGs_gt90cov_gt90ID_AMRFinderPlus = purrr::map_chr(base_part$Lab_ID, function(iso_id) {
    txt <- find_isolate_file(AMR_DIR, iso_id, suffix_regex = ".*\\.txt$")
    read_amr_column(txt, scope_wanted = "core", type_wanted = "AMR", subtype_wanted = "AMR", out_col = "Element symbol")
  })
)

point_col <- tibble(
  Point_Mutations = purrr::map_chr(base_part$Lab_ID, function(iso_id) {
    txt <- find_isolate_file(AMR_DIR, iso_id, suffix_regex = ".*\\.txt$")
    read_amr_column(txt, scope_wanted = "core", type_wanted = "AMR", subtype_wanted = "POINT", out_col = "Element symbol")
  })
)

pred_col <- tibble(
  Predicted_Phenotype = purrr::map_chr(base_part$Lab_ID, function(iso_id) {
    txt <- find_isolate_file(AMR_DIR, iso_id, suffix_regex = ".*\\.txt$")
    read_amr_column(txt, scope_wanted = "core", type_wanted = "AMR", subtype_wanted = c("AMR","POINT"), out_col = "Subclass")
  })
)

vir_col <- tibble(
  Virulence_Genes_gt90cov_gt90ID_AMRFinderPlus = purrr::map_chr(base_part$Lab_ID, function(iso_id) {
    txt <- find_isolate_file(AMR_DIR, iso_id, suffix_regex = ".*\\.txt$")
    read_amr_column(txt, scope_wanted = "plus", type_wanted = "VIRULENCE", subtype_wanted = NULL, out_col = "Element symbol")
  })
)

# =========================================================
# 🧩 Assemble, order, and types
# =========================================================
final_report <- bind_cols(
  base_part %>% select(Lab_ID, Original_ID, Index, Platform),
  quast_part,
  base_part %>% select(Expected_Organism),
  org_col,
  st_col,
  plasmid_col,
  amr_col,
  point_col,
  pred_col,
  vir_col,
  base_part %>% select(Comments)
)

# ensure all planned columns exist and in the right order
missing_cols <- setdiff(final_columns, names(final_report))
if (length(missing_cols)) final_report[missing_cols] <- NA
final_report <- final_report[, final_columns]

# 👀 Preview (and save)
print(final_report, n = 50)
write_csv(final_report, file.path(BASE_DIR, "final_report_complete.csv"))
