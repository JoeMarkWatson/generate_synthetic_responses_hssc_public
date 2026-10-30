#!/usr/bin/env Rscript

# Each repetition samples 20 development items and adds four nuisance items.
# Stage 1: one 24-item IRT fit per calibrated method (including the full-training reference)
# supplies parameter recovery, reference-form overlap, and nuisance counts.
# Stage 2: correlate the selected 10-item sum with the other 40 Extraversion
# items' sum in human test data, without fitting or scoring another IRT model.
# The final random10 baseline samples the original 24 candidates without an IRT fit.
# Detailed CSVs append at each checkpoint; reports refresh at repetitions 10, 20, ...

suppressPackageStartupMessages({
  if (!requireNamespace("mirt", quietly = TRUE)) {
    stop("The mirt package is required for this evaluation script.")
  }
})

get_script_dir <- function() {
  arg_matches <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(arg_matches) > 0L) {
    script_path <- sub("^--file=", "", arg_matches[1])
    return(normalizePath(dirname(script_path), winslash = "/", mustWork = TRUE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

script_dir <- get_script_dir()
if (file.exists(file.path(script_dir, "ATA.R"))) {
  repo_root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
  ata_path <- file.path(script_dir, "ATA.R")
} else {
  repo_root <- normalizePath(script_dir, winslash = "/", mustWork = TRUE)
  ata_path <- file.path(script_dir, "evaluate_resps", "ATA.R")
}

source(ata_path)

item_meta_path <- file.path(repo_root, "scales_info", "Extraversion_info", "scale_items.csv")
human_train_path <- file.path(repo_root, "data", "extraversion", "human_responses", "human_train_responses.csv")
human_test_path <- file.path(repo_root, "data", "extraversion", "human_responses", "human_test_responses.csv")
llm_responses_dir <- file.path(repo_root, "data", "extraversion", "llm_responses")
synth_full_path <- file.path(llm_responses_dir, "synth_item_responses_full.csv")
synth_full_v11_path <- file.path(llm_responses_dir, "synth_item_responses_fullV1.1.csv")
synth_full_v12_path <- file.path(llm_responses_dir, "synth_item_responses_fullV1.2.csv")
synth_full_v2_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.csv")
synth_full_v21_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.csv")
synth_full_v21_no_assoc_explan_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1_no_assoc_explan.csv")
synth_full_v21_no_demogs_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1_no_demogs.csv")
synth_full_v21_no_detail_variation_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1_no_detail_variation.csv")
synth_full_v21_no_trait_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1_no_trait.csv")
synth_full_v211_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1.csv")
synth_full_v211_no_assoc_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_assoc_explan.csv")
synth_full_v211_no_demogs_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_demogs.csv")
synth_full_v211_no_detail_variation_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_detail_variation.csv")
synth_full_v211_no_probabilities_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_probabilities.csv")
synth_full_v211_no_trait_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_trait.csv")
synth_full_v211_openai_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1__openai_gpt_5_6_luna_floor.csv")
synth_full_v211_no_probabilities_openai_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_probabilities__openai_gpt_5_6_luna_floor.csv")
synth_full_v211_no_trait_openai_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_trait__openai_gpt_5_6_luna_floor.csv")
synth_full_v211_no_demogs_openai_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_demogs__openai_gpt_5_6_luna_floor.csv")
synth_full_v211_no_assoc_openai_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_assoc_explan__openai_gpt_5_6_luna_floor.csv")
synth_full_v211_no_detail_variation_openai_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_detail_variation__openai_gpt_5_6_luna_floor.csv")
synth_full_v211_claude_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1__anthropic_claude_haiku_5_5.csv")
synth_full_v211_no_assoc_claude_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_assoc_explan__anthropic_claude_haiku_5_5.csv")
synth_full_v211_no_detail_variation_claude_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_detail_variation__anthropic_claude_haiku_5_5.csv")
synth_full_v211_no_demogs_claude_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_demogs__anthropic_claude_haiku_5_5.csv")
synth_full_v211_no_probabilities_claude_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_probabilities__anthropic_claude_haiku_5_5.csv")
synth_full_v211_no_trait_claude_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_trait__anthropic_claude_haiku_5_5.csv")
synth_full_v211_xiaomi_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1__xiaomi_mimo_v2_6_flash.csv")
synth_full_v211_no_assoc_xiaomi_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_assoc_explan__xiaomi_mimo_v2_6_flash.csv")
synth_full_v211_no_detail_variation_xiaomi_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_detail_variation__xiaomi_mimo_v2_6_flash.csv")
synth_full_v211_no_demogs_xiaomi_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_demogs__xiaomi_mimo_v2_6_flash.csv")
synth_full_v211_no_probabilities_xiaomi_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_probabilities__xiaomi_mimo_v2_6_flash.csv")
synth_full_v211_no_trait_xiaomi_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.1.1_no_trait__xiaomi_mimo_v2_6_flash.csv")
synth_single_answer_demogs_openai_path <- file.path(llm_responses_dir, "synth_item_responses_single_answer_demogs__openai_gpt_5_6_luna_floor.csv")
synth_single_answer_demogs_claude_path <- file.path(llm_responses_dir, "synth_item_responses_single_answer_demogs__anthropic_claude_haiku_5_5.csv")
synth_single_answer_demogs_xiaomi_path <- file.path(llm_responses_dir, "synth_item_responses_single_answer_demogs__xiaomi_mimo_v2_6_flash.csv")
synth_single_answer_demogs_path <- file.path(llm_responses_dir, "synth_item_responses_single_answer_demogs.csv")
synth_full_v22_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.2.csv")
synth_full_v23_path <- file.path(llm_responses_dir, "synth_item_responses_fullV2.3.csv")
synth_no_construct_path <- file.path(llm_responses_dir, "synth_item_responses_no_construct_definition.csv")

default_output_dir <- file.path(script_dir, "monte_carlo_study1_output")

parse_cli_args <- function(args) {
  out <- list(
    reps = 1000L,
    seed = 1L,
    output_dir = default_output_dir,
    resume = FALSE,
    backfill_random10 = FALSE,
    verify_random10 = FALSE,
    additional_reps = NA_integer_
  )

  for (arg in args) {
    if (grepl("^--reps=", arg, fixed = FALSE)) {
      out$reps <- as.integer(sub("^--reps=", "", arg))
    } else if (grepl("^--seed=", arg, fixed = FALSE)) {
      out$seed <- as.integer(sub("^--seed=", "", arg))
    } else if (grepl("^--output-dir=", arg, fixed = FALSE)) {
      out$output_dir <- sub("^--output-dir=", "", arg)
    } else if (identical(arg, "--resume")) {
      out$resume <- TRUE
    } else if (identical(arg, "--backfill-random10")) {
      out$backfill_random10 <- TRUE
    } else if (identical(arg, "--verify-random10")) {
      out$verify_random10 <- TRUE
    } else if (grepl("^--resume=", arg, fixed = FALSE)) {
      out$resume <- as.logical(sub("^--resume=", "", arg))
    } else if (grepl("^--additional-reps=", arg, fixed = FALSE)) {
      out$additional_reps <- as.integer(sub("^--additional-reps=", "", arg))
    } else if (arg %in% c("-h", "--help")) {
      cat(
        "Usage: Rscript monte_carlo_study1.R [--reps=1000] [--seed=1] [--output-dir=PATH] [--resume] [--additional-reps=N] [--backfill-random10 | --verify-random10]\n",
        "Backfill adds missing random10 rows for completed repetitions and exits. Verification is read-only.\n",
        sep = ""
      )
      quit(status = 0)
    } else {
      stop(sprintf("Unknown argument: %s", arg))
    }
  }

  if (is.na(out$seed) || out$seed != 1L) {
    stop("The Monte Carlo repetition seed is fixed at 1; use --seed=1 or omit --seed.")
  }
  if (out$backfill_random10 && out$verify_random10) stop("Choose either backfill or verification.")
  if ((out$backfill_random10 || out$verify_random10) && (out$resume || !is.na(out$additional_reps))) {
    stop("Backfill/verification runs independently of --resume and --additional-reps.")
  }
  out
}

# Include all 24 V2.1.1 response files except the temp1 file, plus the four
# single_answer_demogs files. single_answer_trait variants are intentionally out.
methods_to_include <- c(
  "human100", "human300", "human1000",
  "v2.1.1", "v2.1.1_no_assoc", "v2.1.1_no_demogs", "v2.1.1_no_detail_variation",
  "v2.1.1_no_probabilities", "v2.1.1_no_trait",
  "openai_full", "openai_no_assoc", "openai_no_demogs", "openai_no_detail_variation",
  "openai_no_probabilities", "openai_no_trait",
  "claude_full", "claude_no_assoc", "claude_no_demogs", "claude_no_detail_variation",
  "claude_no_probabilities", "claude_no_trait",
  "xiaomi_full", "xiaomi_no_assoc", "xiaomi_no_demogs", "xiaomi_no_detail_variation",
  "xiaomi_no_probabilities", "xiaomi_no_trait",
  "single_answer_demogs", "openai_single_answer_demogs",
  "claude_single_answer_demogs", "xiaomi_single_answer_demogs",
  "random10"
)

read_item_meta <- function(path) {
  meta <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  meta$response_col <- c(
    paste0("EXT", sprintf("%02d", seq_len(60))),
    "EXT61_dN",
    "EXT62_dO",
    "EXT63_dA",
    "EXT64_dC"
  )
  meta
}

normalize_response_matrix <- function(mat) {
  dn <- dimnames(mat)
  mat <- suppressWarnings(matrix(as.numeric(mat), nrow = nrow(mat), ncol = ncol(mat), dimnames = dn))
  mat[!mat %in% 1:5] <- NA_real_
  mat
}

keep_complete_response_rows <- function(mat) {
  mat[complete.cases(mat), , drop = FALSE]
}

reverse_code_matrix <- function(mat, reverse_cols) {
  if (!length(reverse_cols)) {
    return(mat)
  }

  idx <- match(reverse_cols, colnames(mat))
  idx <- idx[!is.na(idx)]
  if (!length(idx)) {
    return(mat)
  }

  reversed <- mat[, idx, drop = FALSE]
  reversed <- ifelse(is.na(reversed), NA_real_, 6 - reversed)
  mat[, idx] <- reversed
  mat
}

build_category_collapse_maps <- function(train_mat, min_level = 1L, max_level = 5L) {
  if (ncol(train_mat) == 0L) {
    stop("Cannot build category collapse maps for an empty matrix.")
  }

  levels <- seq.int(min_level, max_level)
  maps <- vector("list", ncol(train_mat))
  names(maps) <- colnames(train_mat)

  for (item_idx in seq_len(ncol(train_mat))) {
    x <- train_mat[, item_idx]
    x <- x[!is.na(x)]
    if (!length(x)) {
      stop(sprintf("Item %s has no non-missing responses.", colnames(train_mat)[item_idx]))
    }

    counts <- tabulate(match(x, levels), nbins = length(levels))
    present <- which(counts > 0L)
    if (length(present) < 2L) {
      stop(sprintf(
        "Item %s has fewer than 2 observed response categories after filtering.",
        colnames(train_mat)[item_idx]
      ))
    }

    provisional <- integer(length(levels))
    for (lvl_idx in seq_along(levels)) {
      if (counts[lvl_idx] > 0L) {
        provisional[lvl_idx] <- levels[lvl_idx]
        next
      }

      lower <- present[present < lvl_idx]
      if (length(lower)) {
        provisional[lvl_idx] <- levels[max(lower)]
        next
      }

      upper <- present[present > lvl_idx]
      if (length(upper)) {
        provisional[lvl_idx] <- levels[min(upper)]
        next
      }

      stop(sprintf("Unable to collapse empty category for item %s.", colnames(train_mat)[item_idx]))
    }

    maps[[item_idx]] <- match(provisional, sort(unique(provisional)))
  }

  maps
}

collapse_response_matrix <- function(mat, category_maps) {
  if (ncol(mat) != length(category_maps)) {
    stop("Matrix width does not match category map length.")
  }

  out <- mat
  for (item_idx in seq_len(ncol(mat))) {
    x <- out[, item_idx]
    map <- category_maps[[item_idx]]
    if (length(map) != 5L) {
      stop(sprintf("Category map for item %s must have length 5.", colnames(mat)[item_idx]))
    }

    valid <- !is.na(x)
    if (any(!(x[valid] %in% 1:5))) {
      stop(sprintf("Unexpected response values found for item %s.", colnames(mat)[item_idx]))
    }

    collapsed <- rep(NA_real_, length(x))
    collapsed[valid] <- map[match(x[valid], 1:5)]
    out[, item_idx] <- collapsed
  }

  out
}

extract_graded_item_params <- function(fit, item_names) {
  params <- mirt::coef(fit, IRTpars = TRUE, simplify = TRUE)$items
  params <- as.matrix(params)

  if (is.null(rownames(params)) || !all(item_names %in% rownames(params))) {
    rownames(params) <- item_names
  }

  params[item_names, , drop = FALSE]
}

make_item_parameter_plot_data <- function(reference_params, method_params_list, parameter_name, reverse_coded_items = character(0)) {
  reference_df <- data.frame(
    item = rownames(reference_params),
    model = "reference",
    parameter = parameter_name,
    value = suppressWarnings(as.numeric(reference_params[, parameter_name])),
    negatively_worded = rownames(reference_params) %in% reverse_coded_items,
    stringsAsFactors = FALSE
  )

  method_dfs <- lapply(names(method_params_list), function(method_name) {
    params <- method_params_list[[method_name]]
    data.frame(
      item = rownames(params),
      model = method_name,
      parameter = parameter_name,
      value = suppressWarnings(as.numeric(params[, parameter_name])),
      negatively_worded = rownames(params) %in% reverse_coded_items,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, c(list(reference_df), method_dfs))
}

make_boundary_threshold_plot_data <- function(
  reference_fit,
  method_fit_list,
  item_names,
  reference_collapse_maps,
  method_collapse_maps_list,
  boundary_name,
  reverse_coded_items = character(0)
) {
  reference_params <- extract_graded_item_params(reference_fit, item_names)
  reference_a <- suppressWarnings(as.numeric(reference_params[, "a"]))
  names(reference_a) <- rownames(reference_params)

  reference_thresholds <- extract_thresholds_by_boundary(reference_fit, item_names, reference_collapse_maps)
  method_thresholds_list <- lapply(names(method_fit_list), function(method_name) {
    extract_thresholds_by_boundary(
      method_fit_list[[method_name]],
      item_names,
      method_collapse_maps_list[[method_name]]
    )
  })
  names(method_thresholds_list) <- names(method_fit_list)

  plot_rows <- list()
  row_idx <- 0L

  add_plot_row <- function(item_name, model_name, value) {
    if (!is.finite(value)) {
      return()
    }
    row_idx <<- row_idx + 1L
    plot_rows[[row_idx]] <<- data.frame(
      item = item_name,
      model = model_name,
      parameter = boundary_name,
      value = value,
      negatively_worded = item_name %in% reverse_coded_items,
      stringsAsFactors = FALSE
    )
  }

  for (item_name in item_names) {
    if (!is.finite(reference_a[[item_name]]) || reference_a[[item_name]] < ref_a_cutoff) {
      next
    }

    reference_thresholds_item <- reference_thresholds[[item_name]]
    if (!length(reference_thresholds_item) || !(boundary_name %in% names(reference_thresholds_item))) {
      next
    }

    add_plot_row(item_name, "reference", suppressWarnings(as.numeric(reference_thresholds_item[[boundary_name]])))

    for (method_name in names(method_thresholds_list)) {
      method_thresholds <- method_thresholds_list[[method_name]]
      method_thresholds_item <- method_thresholds[[item_name]]
      if (!length(method_thresholds_item) || !(boundary_name %in% names(method_thresholds_item))) {
        next
      }

      add_plot_row(item_name, method_name, suppressWarnings(as.numeric(method_thresholds_item[[boundary_name]])))
    }
  }

  if (!length(plot_rows)) {
    return(data.frame(item = character(0), model = character(0), parameter = character(0), value = numeric(0), negatively_worded = logical(0), stringsAsFactors = FALSE))
  }

  do.call(rbind, plot_rows)
}

save_item_parameter_plot <- function(plot_data, item_order, output_path, plot_title, y_label) {
  plot_data <- plot_data[is.finite(plot_data$value) & plot_data$value >= -5 & plot_data$value <= 5, , drop = FALSE]
  if (!nrow(plot_data)) {
    warning(sprintf("No in-range values available for plot %s.", output_path))
    return(invisible(NULL))
  }

  plot_data$item <- factor(plot_data$item, levels = item_order)
  plot_data$item_index <- as.integer(plot_data$item)
  plot_data <- plot_data[order(plot_data$model, plot_data$item_index), , drop = FALSE]
  plot_data$negatively_worded <- factor(plot_data$negatively_worded, levels = c(FALSE, TRUE))

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = item, y = value, color = model)) +
    ggplot2::geom_line(ggplot2::aes(group = model), linewidth = 0.4) +
    ggplot2::geom_point(
      ggplot2::aes(shape = negatively_worded),
      position = ggplot2::position_dodge(width = 0.35),
      size = 2
    ) +
    ggplot2::labs(
      title = plot_title,
      x = "Item",
      y = y_label,
      color = "Model",
      shape = "Negatively worded"
    ) +
    ggplot2::scale_shape_manual(values = c("FALSE" = 16, "TRUE" = 4), labels = c("FALSE" = "No", "TRUE" = "Yes")) +
    ggplot2::scale_x_discrete(drop = FALSE) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      panel.grid.major.x = ggplot2::element_blank()
    )

  ggplot2::ggsave(filename = output_path, plot = p, width = 12, height = 5, dpi = 300)
}

boundary_labels_from_collapse_map <- function(collapse_map) {
  collapse_map <- as.integer(collapse_map)
  if (!length(collapse_map)) {
    return(character(0))
  }

  change_idx <- which(collapse_map[-length(collapse_map)] != collapse_map[-1])
  paste0("b", change_idx)
}

extract_thresholds_by_boundary <- function(fit, item_names, collapse_maps) {
  params <- mirt::coef(fit, IRTpars = TRUE, simplify = TRUE)$items
  params <- as.matrix(params)
  if (is.null(rownames(params)) || !all(item_names %in% rownames(params))) {
    rownames(params) <- item_names
  }

  threshold_cols <- intersect(paste0("b", 1:4), colnames(params))
  out <- vector("list", length(item_names))
  names(out) <- item_names

  for (item_name in item_names) {
    collapse_map <- collapse_maps[[item_name]]
    boundary_labels <- boundary_labels_from_collapse_map(collapse_map)
    threshold_values <- suppressWarnings(as.numeric(params[item_name, threshold_cols, drop = TRUE]))

    if (!length(threshold_values) || !length(boundary_labels)) {
      out[[item_name]] <- numeric(0)
      next
    }

    n_thresholds <- min(length(threshold_values), length(boundary_labels))
    if (n_thresholds <= 0L) {
      out[[item_name]] <- numeric(0)
      next
    }

    named_thresholds <- threshold_values[seq_len(n_thresholds)]
    names(named_thresholds) <- boundary_labels[seq_len(n_thresholds)]
    out[[item_name]] <- named_thresholds
  }

  out
}

print_graded_item_params <- function(label, fit, item_names) {
  params <- extract_graded_item_params(fit, item_names)
  out <- data.frame(
    item = rownames(params),
    round(as.data.frame(params), 4),
    row.names = NULL,
    check.names = FALSE
  )

  cat(sprintf("=== %s graded item parameters ===\n", label))
  print(out, row.names = FALSE)
  cat(sprintf("=== end %s graded item parameters ===\n", label))
}

print_boundary_mapping_diagnostics <- function(label, item_names, collapse_maps) {
  lines <- character(0)
  for (item_name in item_names) {
    boundary_labels <- boundary_labels_from_collapse_map(collapse_maps[[item_name]])
    if (!identical(boundary_labels, paste0("b", 1:4))) {
      lines <- c(lines, sprintf("%s: %s", item_name, if (length(boundary_labels)) paste(boundary_labels, collapse = ",") else "(none)"))
    }
  }

  if (length(lines)) {
    cat(sprintf("=== %s collapse-boundary mappings ===\n", label))
    cat(paste(lines, collapse = "\n"), "\n")
    cat(sprintf("=== end %s collapse-boundary mappings ===\n", label))
  }
}

make_result_row <- function(values) {
  row <- list(
    workflow_version = "24_to_10_sum_v5",
    repetition = NA_integer_,
    stage = NA_character_,
    method = NA_character_,
    fit_role = NA_character_,
    fit_n = NA_integer_,
    fit_items = NA_integer_,
    candidate_items = NA_character_,
    selected_items = NA_character_,
    selected_count = NA_integer_,
    nuisance_selected_n = NA_integer_,
    nuisance_selected_items = NA_character_,
    nuisance_item_EXT61_dN_selected = NA,
    nuisance_item_EXT62_dO_selected = NA,
    nuisance_item_EXT63_dA_selected = NA,
    nuisance_item_EXT64_dC_selected = NA,
    reference_selected_items = NA_character_,
    selected_overlap_items = NA_character_,
    overlap_n = NA_integer_,
    overlap_jaccard = NA_real_,
    overlap_precision = NA_real_,
    overlap_recall = NA_real_,
    compared_parameters = NA_integer_,
    a_expected_n = NA_integer_,
    a_nonfinite_n = NA_integer_,
    a_nonfinite_items = NA_character_,
    a_abs_diff_median = NA_real_,
    a_abs_diff_n = NA_integer_,
    a_abs_diff_revervse_median = NA_real_,
    a_abs_diff_revervse_n = NA_integer_,
    a_abs_diff_positive_median = NA_real_,
    a_abs_diff_positive_n = NA_integer_,
    a_parameter_r = NA_real_,
    a_parameter_r_n = NA_integer_,
    b1_abs_diff_median = NA_real_,
    b1_abs_diff_n = NA_integer_,
    b1_parameter_r = NA_real_,
    b1_parameter_r_n = NA_integer_,
    b2_abs_diff_median = NA_real_,
    b2_abs_diff_n = NA_integer_,
    b2_parameter_r = NA_real_,
    b2_parameter_r_n = NA_integer_,
    b3_abs_diff_median = NA_real_,
    b3_abs_diff_n = NA_integer_,
    b3_parameter_r = NA_real_,
    b3_parameter_r_n = NA_integer_,
    b4_abs_diff_median = NA_real_,
    b4_abs_diff_n = NA_integer_,
    b4_parameter_r = NA_real_,
    b4_parameter_r_n = NA_integer_,
    eval_n = NA_integer_,
    pearson_r = NA_real_,
    spearman_r = NA_real_,
    short_sum_mean = NA_real_,
    short_sum_sd = NA_real_,
    sum_mean = NA_real_,
    sum_sd = NA_real_,
    scoring_method = NA_character_,
    eval_short_sum = NA_character_,
    eval_target_sum = NA_character_,
    train_items = NA_character_,
    heldout_items = NA_character_
  )

  for (nm in names(values)) {
    row[[nm]] <- values[[nm]]
  }

  as.data.frame(row, stringsAsFactors = FALSE)
}

build_nuisance_screening_row <- function(
  repetition,
  stage_method,
  fit_role,
  fit_n,
  fit_items,
  candidate_items,
  selected_items,
  nuisance_items
) {
  nuisance_selected_items <- intersect(selected_items, nuisance_items)
  nuisance_flags <- setNames(as.list(nuisance_items %in% selected_items), paste0("nuisance_item_", nuisance_items, "_selected"))

  make_result_row(c(
    list(
      repetition = repetition,
      stage = "nuisance_screening",
      method = stage_method,
      fit_role = fit_role,
      fit_n = fit_n,
      fit_items = fit_items,
      candidate_items = paste(candidate_items, collapse = ";"),
      selected_items = paste(selected_items, collapse = ";"),
      selected_count = length(selected_items),
      nuisance_selected_n = length(nuisance_selected_items),
      nuisance_selected_items = paste(nuisance_selected_items, collapse = ";")
    ),
    nuisance_flags
  ))
}

build_candidate_selection_row <- function(
  repetition,
  stage_method,
  fit_role,
  fit_n,
  fit_items,
  candidate_items,
  selected_items,
  reference_selected_items = NULL,
  compared_parameters = NA_integer_,
  a_expected_n = NA_integer_,
  a_nonfinite_n = NA_integer_,
  a_nonfinite_items = NA_character_,
  a_abs_diff_median = NA_real_,
  a_abs_diff_n = NA_integer_,
  a_abs_diff_revervse_median = NA_real_,
  a_abs_diff_revervse_n = NA_integer_,
  a_abs_diff_positive_median = NA_real_,
  a_abs_diff_positive_n = NA_integer_,
  a_parameter_r = NA_real_,
  a_parameter_r_n = NA_integer_,
  b_metrics = NULL,
  overlap_items = NULL,
  overlap_n = NA_integer_,
  overlap_jaccard = NA_real_,
  overlap_precision = NA_real_,
  overlap_recall = NA_real_
) {
  values <- list(
    repetition = repetition,
    stage = "candidate_selection",
    method = stage_method,
    fit_role = fit_role,
    fit_n = fit_n,
    fit_items = fit_items,
    candidate_items = paste(candidate_items, collapse = ";"),
    selected_items = paste(selected_items, collapse = ";"),
    selected_count = length(selected_items),
    reference_selected_items = if (is.null(reference_selected_items)) NA_character_ else paste(reference_selected_items, collapse = ";"),
    selected_overlap_items = if (is.null(overlap_items)) NA_character_ else paste(overlap_items, collapse = ";"),
    overlap_n = overlap_n,
    overlap_jaccard = overlap_jaccard,
    overlap_precision = overlap_precision,
    overlap_recall = overlap_recall,
    compared_parameters = compared_parameters,
    a_expected_n = a_expected_n,
    a_nonfinite_n = a_nonfinite_n,
    a_nonfinite_items = a_nonfinite_items,
    a_abs_diff_median = a_abs_diff_median,
    a_abs_diff_n = a_abs_diff_n,
    a_abs_diff_revervse_median = a_abs_diff_revervse_median,
    a_abs_diff_revervse_n = a_abs_diff_revervse_n,
    a_abs_diff_positive_median = a_abs_diff_positive_median,
    a_abs_diff_positive_n = a_abs_diff_positive_n,
    a_parameter_r = a_parameter_r,
    a_parameter_r_n = a_parameter_r_n
  )

  if (!is.null(b_metrics)) {
    values <- c(values, b_metrics)
  }

  make_result_row(values)
}

build_short_form_row <- function(
  repetition,
  stage_method,
  fit_role,
  fit_n,
  fit_items,
  candidate_items,
  selected_items,
  eval_n,
  eval_metrics,
  train_items = NULL,
  heldout_items = NULL
) {
  make_result_row(list(
    repetition = repetition,
    stage = "short_form_evaluation",
    method = stage_method,
    fit_role = fit_role,
    fit_n = fit_n,
    fit_items = fit_items,
    candidate_items = paste(candidate_items, collapse = ";"),
    selected_items = paste(selected_items, collapse = ";"),
    selected_count = length(selected_items),
    eval_n = eval_n,
    pearson_r = eval_metrics$pearson_r,
    spearman_r = eval_metrics$spearman_r,
    short_sum_mean = eval_metrics$short_sum_mean,
    short_sum_sd = eval_metrics$short_sum_sd,
    sum_mean = eval_metrics$sum_mean,
    sum_sd = eval_metrics$sum_sd,
    scoring_method = eval_metrics$scoring_method,
    eval_short_sum = paste(sprintf("%.17g", eval_metrics$short_sum_values), collapse = ";"),
    eval_target_sum = paste(sprintf("%.17g", eval_metrics$target_values), collapse = ";"),
    train_items = if (is.null(train_items)) NA_character_ else paste(train_items, collapse = ";"),
    heldout_items = if (is.null(heldout_items)) NA_character_ else paste(heldout_items, collapse = ";")
  ))
}

compare_graded_parameters <- function(
  reference_fit,
  method_fit,
  item_names,
  reference_collapse_maps,
  method_collapse_maps,
  reverse_coded_items = character(0),
  ref_a_cutoff = 0.35
) {
  reference_params <- extract_graded_item_params(reference_fit, item_names)
  method_params <- extract_graded_item_params(method_fit, item_names)
  reference_thresholds <- extract_thresholds_by_boundary(reference_fit, item_names, reference_collapse_maps)
  method_thresholds <- extract_thresholds_by_boundary(method_fit, item_names, method_collapse_maps)

  if (!identical(rownames(reference_params), rownames(method_params))) {
    stop("Reference and method parameter tables are misaligned.")
  }

  compare_abs <- function(ref_vec, method_vec) {
    abs(method_vec - ref_vec)
  }

  parameter_correlation <- function(ref_vec, method_vec) {
    keep <- is.finite(ref_vec) & is.finite(method_vec)
    ref_vec <- ref_vec[keep]
    method_vec <- method_vec[keep]

    if (length(ref_vec) < 3L || stats::sd(ref_vec) == 0 || stats::sd(method_vec) == 0) {
      return(list(r = NA_real_, n = length(ref_vec)))
    }

    list(
      r = as.numeric(stats::cor(ref_vec, method_vec, method = "pearson")),
      n = length(ref_vec)
    )
  }

  reference_a <- suppressWarnings(as.numeric(reference_params[, "a"]))
  method_a <- suppressWarnings(as.numeric(method_params[, "a"]))
  names(reference_a) <- rownames(reference_params)
  names(method_a) <- rownames(method_params)

  expected_a_n <- length(item_names)
  a_finite_mask <- is.finite(reference_a) & is.finite(method_a)
  a_nonfinite_items <- item_names[!a_finite_mask]
  a_nonfinite_ref_items <- item_names[!is.finite(reference_a)]
  a_nonfinite_method_items <- item_names[!is.finite(method_a)]

  if (length(a_nonfinite_items)) {
    cat("=== a comparison nonfinite estimates ===\n")
    cat(sprintf(
      "items with nonfinite reference a: %s\n",
      if (length(a_nonfinite_ref_items)) paste(a_nonfinite_ref_items, collapse = ";") else "none"
    ))
    cat(sprintf(
      "items with nonfinite method a: %s\n",
      if (length(a_nonfinite_method_items)) paste(a_nonfinite_method_items, collapse = ";") else "none"
    ))
    cat("=== end a comparison nonfinite estimates ===\n")
  }

  a_abs_diff <- compare_abs(reference_a[a_finite_mask], method_a[a_finite_mask])
  a_abs_diff <- a_abs_diff[is.finite(a_abs_diff)]
  a_abs_diff_n <- length(a_abs_diff)
  a_parameter_cor <- parameter_correlation(reference_a[a_finite_mask], method_a[a_finite_mask])

  reverse_mask <- a_finite_mask & (item_names %in% reverse_coded_items)
  a_abs_diff_reverse <- compare_abs(reference_a[reverse_mask], method_a[reverse_mask])
  a_abs_diff_reverse <- a_abs_diff_reverse[is.finite(a_abs_diff_reverse)]
  a_abs_diff_reverse_n <- length(a_abs_diff_reverse)

  positive_mask <- a_finite_mask & !(item_names %in% reverse_coded_items)
  a_abs_diff_positive <- compare_abs(reference_a[positive_mask], method_a[positive_mask])
  a_abs_diff_positive <- a_abs_diff_positive[is.finite(a_abs_diff_positive)]
  a_abs_diff_positive_n <- length(a_abs_diff_positive)

  if (length(a_nonfinite_items) == 0L && a_abs_diff_n != expected_a_n) {
    stop(sprintf(
      "Expected %d finite discrimination comparisons, but found %d.",
      expected_a_n,
      a_abs_diff_n
    ), call. = FALSE)
  }
  if (length(a_nonfinite_items) > 0L && a_abs_diff_n != expected_a_n - length(a_nonfinite_items)) {
    stop(sprintf(
      "Expected %d finite discrimination comparisons after excluding nonfinite a estimates (%s), but found %d.",
      expected_a_n - length(a_nonfinite_items),
      paste(a_nonfinite_items, collapse = ";"),
      a_abs_diff_n
    ), call. = FALSE)
  }

  out <- list(
    compared_parameters = a_abs_diff_n,
    a_expected_n = expected_a_n,
    a_nonfinite_n = length(a_nonfinite_items),
    a_nonfinite_items = if (length(a_nonfinite_items)) paste(a_nonfinite_items, collapse = ";") else NA_character_,
    a_abs_diff_median = if (length(a_abs_diff)) stats::median(a_abs_diff) else NA_real_,
    a_abs_diff_n = a_abs_diff_n,
    a_abs_diff_revervse_median = if (length(a_abs_diff_reverse)) stats::median(a_abs_diff_reverse) else NA_real_,
    a_abs_diff_revervse_n = a_abs_diff_reverse_n,
    a_abs_diff_positive_median = if (length(a_abs_diff_positive)) stats::median(a_abs_diff_positive) else NA_real_,
    a_abs_diff_positive_n = a_abs_diff_positive_n,
    a_parameter_r = a_parameter_cor$r,
    a_parameter_r_n = a_parameter_cor$n
  )

  for (b_idx in 1:4) {
    b_col <- paste0("b", b_idx)
    b_abs_diff <- numeric(0)
    b_reference_values <- numeric(0)
    b_method_values <- numeric(0)

    for (item_name in item_names) {
      ref_thresholds <- reference_thresholds[[item_name]]
      method_thresholds_item <- method_thresholds[[item_name]]
      if (!length(ref_thresholds) || !length(method_thresholds_item)) next
      if (!(b_col %in% intersect(names(ref_thresholds), names(method_thresholds_item)))) next

      ref_threshold <- suppressWarnings(as.numeric(ref_thresholds[[b_col]]))
      method_threshold <- suppressWarnings(as.numeric(method_thresholds_item[[b_col]]))
      if (!is.finite(ref_threshold) || !is.finite(method_threshold)) next

      b_abs_diff <- c(b_abs_diff, abs(method_threshold - ref_threshold))
      b_reference_values <- c(b_reference_values, ref_threshold)
      b_method_values <- c(b_method_values, method_threshold)
    }

    b_parameter_cor <- parameter_correlation(b_reference_values, b_method_values)
    out[[paste0(b_col, "_abs_diff_median")]] <- if (length(b_abs_diff)) stats::median(b_abs_diff) else NA_real_
    out[[paste0(b_col, "_abs_diff_n")]] <- length(b_abs_diff)
    out[[paste0(b_col, "_parameter_r")]] <- b_parameter_cor$r
    out[[paste0(b_col, "_parameter_r_n")]] <- b_parameter_cor$n
  }

  out$compared_parameters <- out$compared_parameters + sum(vapply(1:4, function(i) out[[paste0("b", i, "_abs_diff_n")]], integer(1)))
  out
}

compute_true_short_form_overlap <- function(selected_items, true_short_form_items) {
  overlap_n <- length(intersect(selected_items, true_short_form_items))
  union_n <- length(union(selected_items, true_short_form_items))

  list(
    true_short_form_overlap_n = overlap_n,
    true_short_form_overlap_jaccard = if (union_n > 0L) overlap_n / union_n else NA_real_,
    true_short_form_precision = if (length(selected_items) > 0L) overlap_n / length(selected_items) else NA_real_,
    true_short_form_recall = if (length(true_short_form_items) > 0L) overlap_n / length(true_short_form_items) else NA_real_
  )
}

load_human_matrix <- function(path, item_meta) {
  df <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  response_cols <- item_meta$response_col
  missing_cols <- setdiff(response_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop(
      "Missing expected human response columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }
  mat <- as.matrix(df[, response_cols, drop = FALSE])
  storage.mode(mat) <- "numeric"
  colnames(mat) <- item_meta$item_code
  mat <- normalize_response_matrix(mat)
  keep_complete_response_rows(mat)
}

load_synthetic_blocks <- function(path) {
  df <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  df$item_order <- match(df$item_id, unique(df$item_id))
  df$persona_order <- match(df$persona_id, unique(df$persona_id))
  df <- df[order(df$persona_order, df$item_order), , drop = FALSE]

  split(df, df$item_id, drop = TRUE)
}

load_synthetic_blocks_if_present <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  load_synthetic_blocks(path)
}

sample_synthetic_matrix_from_dist_blocks <- function(blocks, item_meta) {
  item_ids <- item_meta$item_code
  first_block <- blocks[[item_ids[1]]]
  persona_ids <- unique(first_block$persona_id)
  n_personas <- length(persona_ids)
  n_items <- length(item_ids)

  out <- matrix(NA_real_, nrow = n_personas, ncol = n_items)
  rownames(out) <- persona_ids
  colnames(out) <- item_ids

  for (item_idx in seq_along(item_ids)) {
    item_id <- item_ids[item_idx]
    block <- blocks[[item_id]]
    dist_mat <- as.matrix(block[, paste0("dist_", 1:10), drop = FALSE])
    storage.mode(dist_mat) <- "numeric"
    choices <- sample.int(10, nrow(dist_mat), replace = TRUE)
    sampled <- dist_mat[cbind(seq_len(nrow(dist_mat)), choices)]
    out[, item_idx] <- sampled
  }

  out <- normalize_response_matrix(out)
  out <- reverse_code_matrix(out, item_meta$item_code[item_meta$reverse_coded == 1L])
  keep_complete_response_rows(out)
}

sample_synthetic_matrix_from_prob_blocks <- function(blocks, item_meta) {
  item_ids <- item_meta$item_code
  first_block <- blocks[[item_ids[1]]]
  persona_ids <- unique(first_block$persona_id)
  n_personas <- length(persona_ids)
  n_items <- length(item_ids)

  out <- matrix(NA_real_, nrow = n_personas, ncol = n_items)
  rownames(out) <- persona_ids
  colnames(out) <- item_ids

  for (item_idx in seq_along(item_ids)) {
    item_id <- item_ids[item_idx]
    block <- blocks[[item_id]]
    if (all(c("prob_1", "prob_2", "prob_3", "prob_4", "prob_5") %in% colnames(block))) {
      prob_mat <- as.matrix(block[, paste0("prob_", 1:5), drop = FALSE])
      storage.mode(prob_mat) <- "numeric"

      if (nrow(prob_mat) != n_personas) {
        stop(sprintf(
          "Synthetic probabilistic block for item %s has %d rows; expected %d.",
          item_id,
          nrow(prob_mat),
          n_personas
        ))
      }

      sampled <- vapply(seq_len(nrow(prob_mat)), function(row_idx) {
        probs <- prob_mat[row_idx, ]
        if (any(!is.finite(probs))) {
          stop(sprintf("Non-finite probability found in item %s.", item_id))
        }
        if (any(probs < 0)) {
          stop(sprintf("Negative probability found in item %s.", item_id))
        }
        total <- sum(probs)
        if (total <= 0) {
          stop(sprintf("Non-positive probability total found in item %s.", item_id))
        }
        probs <- probs / total
        sample.int(5L, 1L, replace = TRUE, prob = probs)
      }, integer(1))

      out[, item_idx] <- sampled
      next
    }

    if (!"response" %in% colnames(block)) {
      stop(sprintf(
        "Synthetic block for item %s is missing both probability columns and a response column.",
        item_id
      ))
    }

    response_vec <- suppressWarnings(as.numeric(block$response))
    if (length(response_vec) != n_personas) {
      stop(sprintf(
        "Synthetic single-answer block for item %s has %d rows; expected %d.",
        item_id,
        length(response_vec),
        n_personas
      ))
    }

    out[, item_idx] <- response_vec
  }

  out <- normalize_response_matrix(out)
  out <- reverse_code_matrix(out, item_meta$item_code[item_meta$reverse_coded == 1L])
  keep_complete_response_rows(out)
}

print_fit_diagnostics <- function(mat, item_names) {
  cat("=== mirt fit failure diagnostics ===\n")
  cat("Model spec:\n")
  cat("  itemtype: graded\n")
  cat("  method: EM\n")
  cat("  factors: 1\n")
  cat("  NCYCLES: 5000\n")
  cat(sprintf("  complete cases: %d\n", nrow(mat)))
  cat(sprintf("  items: %d\n", ncol(mat)))
  cat(sprintf("  item names: %s\n", paste(item_names, collapse = ", ")))
  cat("Response category counts by item:\n")
  for (nm in item_names) {
    counts <- table(factor(mat[, nm], levels = 1:5), useNA = "ifany")
    cat(sprintf(
      "  %s: %s\n",
      nm,
      paste(names(counts), as.integer(counts), collapse = " ")
    ))
  }

  start_values <- tryCatch(
    suppressWarnings(
      mirt::mirt(
        mat,
        1,
        itemtype = "graded",
        method = "EM",
        pars = "values",
        verbose = FALSE,
        technical = list(NCYCLES = 1)
      )
    ),
    error = function(e) NULL
  )

  if (!is.null(start_values)) {
    cat("Starting parameter table (head):\n")
    print(utils::head(start_values, 20))
  } else {
    cat("Starting parameter table unavailable.\n")
  }
  cat("=== end diagnostics ===\n")
}

fit_graded_model <- function(mat, item_names = colnames(mat)) {
  mat <- mat[complete.cases(mat), , drop = FALSE]
  if (nrow(mat) < 30L) {
    stop("Not enough complete cases to fit the graded response model.")
  }

  fit <- tryCatch(
    suppressWarnings(
      mirt::mirt(
        mat,
        1,
        itemtype = "graded",
        method = "EM",
        verbose = FALSE,
        technical = list(NCYCLES = 5000)
      )
    ),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    print_fit_diagnostics(mat, item_names)
    stop(
      sprintf(
        "EM graded model fit failed for the current sample: %s",
        conditionMessage(fit)
      ),
      call. = FALSE
    )
  }

  fit
}

prepare_calibration_data <- function(mat, candidate_items, minimum_items = 10L) {
  retained_items <- candidate_items
  exclusions <- data.frame(
    item = character(),
    observed_categories = integer(),
    reason = character(),
    stringsAsFactors = FALSE
  )

  repeat {
    if (!length(retained_items)) {
      fit_mat <- mat[, character(), drop = FALSE]
      category_counts <- integer()
    } else {
      raw_subset <- mat[, retained_items, drop = FALSE]
      fit_mat <- raw_subset[complete.cases(raw_subset), , drop = FALSE]
      category_counts <- vapply(retained_items, function(item) {
        length(unique(fit_mat[, item][!is.na(fit_mat[, item])]))
      }, integer(1))
    }

    nonvarying_items <- names(category_counts)[category_counts < 2L]
    if (!length(nonvarying_items)) break

    exclusions <- rbind(
      exclusions,
      data.frame(
        item = nonvarying_items,
        observed_categories = unname(category_counts[nonvarying_items]),
        reason = paste0(
          "Fewer than 2 observed response categories in complete calibration cases (",
          unname(category_counts[nonvarying_items]), " observed)."
        ),
        stringsAsFactors = FALSE
      )
    )
    retained_items <- setdiff(retained_items, nonvarying_items)
    if (length(retained_items) < minimum_items) {
      fit_mat <- mat[, retained_items, drop = FALSE]
      break
    }
  }

  list(
    items = retained_items,
    fit_mat = fit_mat,
    exclusions = exclusions,
    enough_items = length(retained_items) >= minimum_items
  )
}

make_item_exclusion_events <- function(exclusions, method, repetition, attempt, seed) {
  if (!nrow(exclusions)) return(list())
  lapply(seq_len(nrow(exclusions)), function(idx) {
    data.frame(
      record_type = "item_exclusion",
      repetition = as.integer(repetition),
      attempt = as.integer(attempt),
      seed = as.integer(seed),
      method = method,
      items = exclusions$item[[idx]],
      reason = exclusions$reason[[idx]],
      stringsAsFactors = FALSE
    )
  })
}

make_method_failure_event <- function(method, repetition, attempt, seed, items, reason) {
  data.frame(
    record_type = "method_failure",
    repetition = as.integer(repetition),
    attempt = as.integer(attempt),
    seed = as.integer(seed),
    method = method,
    items = if (length(items)) paste(items, collapse = ";") else NA_character_,
    reason = as.character(reason),
    stringsAsFactors = FALSE
  )
}

# Human response files are already keyed in the scoring direction (see
# data/human_data_details/ipip/DAT300.doc), as are the
# synthetic matrices after loading. Sum the original 1:5 categories directly;
# category collapsing is used only for IRT estimation.
score_sum_scores <- function(eval_short, eval_target) {
  if (nrow(eval_short) != nrow(eval_target)) stop("Evaluation matrices have different row counts.")
  keep <- complete.cases(eval_short) & complete.cases(eval_target)
  short_sum <- rowSums(eval_short[keep, , drop = FALSE])
  target_sum <- rowSums(eval_target[keep, , drop = FALSE])
  valid <- is.finite(short_sum) & is.finite(target_sum)
  short_sum <- short_sum[valid]
  target_sum <- target_sum[valid]
  if (length(short_sum) < 10L) stop("Not enough valid sum-score pairs for evaluation.")
  if (stats::sd(short_sum) == 0 || stats::sd(target_sum) == 0) {
    stop("Cannot correlate constant short-form or held-out sum scores.")
  }
  pearson_r <- as.numeric(stats::cor(short_sum, target_sum, method = "pearson"))
  list(
    scoring_method = "SUM_SCORE", n_eval = length(short_sum),
    pearson_r = pearson_r,
    spearman_r = as.numeric(stats::cor(short_sum, target_sum, method = "spearman")),
    short_sum_mean = mean(short_sum), short_sum_sd = stats::sd(short_sum),
    sum_mean = mean(target_sum), sum_sd = stats::sd(target_sum),
    short_sum_values = short_sum,
    target_values = target_sum
  )
}

random10_selection <- function(candidate_items, seed) {
  if (length(candidate_items) != 24L || anyDuplicated(candidate_items)) {
    stop("random10 requires the original 24 distinct candidate items.")
  }
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) previous_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit({
    if (had_seed) assign(".Random.seed", previous_seed, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
  })
  set.seed(seed)
  candidate_items[sample.int(24L, 10L, replace = FALSE)]
}

build_random10_rows <- function(repetition, attempt, seed, candidate_items, reference_selected,
                                train_items, heldout_items, nuisance_items, human_test) {
  selected <- random10_selection(candidate_items, seed)
  overlap <- compute_true_short_form_overlap(selected, reference_selected)
  scores <- score_sum_scores(human_test[, selected, drop = FALSE], human_test[, heldout_items, drop = FALSE])
  rows <- list(
    build_nuisance_screening_row(repetition, "random10", "random_baseline", NA_integer_, NA_integer_,
      candidate_items, selected, nuisance_items),
    build_candidate_selection_row(repetition, "random10", "random_baseline", NA_integer_, NA_integer_,
      candidate_items, selected, reference_selected_items = reference_selected,
      overlap_items = intersect(selected, reference_selected), overlap_n = overlap$true_short_form_overlap_n,
      overlap_jaccard = overlap$true_short_form_overlap_jaccard,
      overlap_precision = overlap$true_short_form_precision, overlap_recall = overlap$true_short_form_recall),
    build_short_form_row(repetition, "random10", "random_baseline", NA_integer_, NA_integer_,
      candidate_items, selected, scores$n_eval, scores, train_items, heldout_items)
  )
  rows <- lapply(rows, function(row) {
    row$attempt <- attempt
    row$seed <- seed
    row
  })
  attr(rows, "scores") <- scores
  rows
}

summarise_results <- function(results, method_names = character(0)) {
  # Keep the summary focused on the main outcomes. Detailed diagnostics remain
  # available in monte_carlo_results.csv, so counts, SDs, and secondary overlap
  # indices do not need to be repeated here.
  numeric_cols <- c(
    "nuisance_selected_n", "overlap_n", "a_abs_diff_median",
    "b1_abs_diff_median", "b2_abs_diff_median", "b3_abs_diff_median", "b4_abs_diff_median",
    "pearson_r", "spearman_r"
  )

  stages <- c("nuisance_screening", "candidate_selection", "short_form_evaluation")
  combos <- do.call(rbind, lapply(stages, function(stage) {
    scores <- if (stage == "short_form_evaluation") "SUM_SCORE" else NA_character_
    expand.grid(stage = stage, method = c("reference", method_names), scoring_method = scores,
      stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE)
  }))
  combos <- unique(rbind(combos, results[intersect(c("stage", "method", "scoring_method"), names(results))]))
  summary_rows <- lapply(seq_len(nrow(combos)), function(idx) {
    stage <- combos$stage[[idx]]
    method <- combos$method[[idx]]
    score <- combos$scoring_method[[idx]]
    keep <- results$stage == stage & results$method == method
    if (stage == "short_form_evaluation") keep <- keep & results$scoring_method == score
    rows <- results[keep, , drop = FALSE]
    out <- data.frame(stage = stage, method = method, stringsAsFactors = FALSE)
    if (stage == "short_form_evaluation") out$scoring_method <- score

    successful_reps <- !is.na(rows$repetition)
    if (stage == "short_form_evaluation") successful_reps <- successful_reps & is.finite(suppressWarnings(as.numeric(rows$pearson_r)))
    out$successful_method_reps <- length(unique(rows$repetition[successful_reps]))
    for (status_col in "scoring_method") {
      if (status_col %in% names(rows)) {
        values <- unique(na.omit(as.character(rows[[status_col]])))
        out[[status_col]] <- if (length(values)) paste(values, collapse = ";") else NA_character_
      }
    }

    for (col in numeric_cols) {
      x <- if (col %in% names(rows)) rows[[col]] else NA_real_
      x <- suppressWarnings(as.numeric(x))
      finite_x <- x[is.finite(x)]
      out[[paste0(col, "_mean")]] <- if (length(finite_x)) mean(finite_x) else NA_real_
    }

    out
  })

  summary <- do.call(rbind, summary_rows)
  cbind(summary, paired_comparison_summary(results, summary))
}

bind_rows_fill <- function(first, second) {
  all_columns <- union(names(first), names(second))
  for (column in setdiff(all_columns, names(first))) first[[column]] <- NA
  for (column in setdiff(all_columns, names(second))) second[[column]] <- NA
  first <- first[, all_columns, drop = FALSE]
  second <- second[, all_columns, drop = FALSE]
  rownames(first) <- NULL
  rownames(second) <- NULL
  rbind(first, second)
}

finite_atanh <- function(x) {
  eps <- sqrt(.Machine$double.eps)
  x <- pmin(pmax(x, -1 + eps), 1 - eps)
  atanh(x)
}

decode_semicolon_numeric <- function(value) {
  if (!length(value) || is.na(value) || !nzchar(value)) return(numeric(0))
  suppressWarnings(as.numeric(strsplit(value, ";", fixed = TRUE)[[1]]))
}

validity_metric_from_scores <- function(short_sum, target, metric) {
  valid <- is.finite(short_sum) & is.finite(target)
  short_sum <- short_sum[valid]
  target <- target[valid]
  if (length(short_sum) < 10L) return(NA_real_)
  switch(metric,
    pearson_r = as.numeric(cor(short_sum, target, method = "pearson")),
    spearman_r = as.numeric(cor(short_sum, target, method = "spearman")),
    NA_real_
  )
}

paired_test_row <- function(results, stage, metric, method, benchmark, scoring_method = NULL) {
  method_keep <- results$stage == stage & results$method == method
  benchmark_keep <- results$stage == stage & results$method == benchmark
  if (!is.null(scoring_method)) {
    method_keep <- method_keep & results$scoring_method == scoring_method
    benchmark_keep <- benchmark_keep & results$scoring_method == scoring_method
  }
  # The streaming backfill reader validates and computes these correlations once
  # per row before discarding the large score vectors.
  is_validity <- stage == "short_form_evaluation" && metric %in% c("pearson_r", "spearman_r")
  validity_metric <- is_validity && !isTRUE(attr(results, "validated_sum_scores"))
  # Descriptive means use the recorded CSV values; paired tests use the exact
  # correlations recomputed from vectors, as before (without repeated decoding).
  metric_column <- if (is_validity && !validity_metric && paste0(".paired_", metric) %in% names(results)) paste0(".paired_", metric) else metric
  method_cols <- c("repetition", metric_column, if (validity_metric) c("eval_short_sum", "eval_target_sum"))
  method_rows <- results[method_keep, method_cols, drop = FALSE]
  benchmark_rows <- results[benchmark_keep, method_cols, drop = FALSE]
  names(method_rows)[2] <- "method_value"
  names(benchmark_rows)[2] <- "benchmark_value"
  paired <- merge(method_rows, benchmark_rows, by = "repetition", all = FALSE)

  method_value <- benchmark_value <- numeric(0)
  if (validity_metric) {
    for (idx in seq_len(nrow(paired))) {
      method_sum <- decode_semicolon_numeric(paired$eval_short_sum.x[[idx]])
      benchmark_sum <- decode_semicolon_numeric(paired$eval_short_sum.y[[idx]])
      method_target <- decode_semicolon_numeric(paired$eval_target_sum.x[[idx]])
      benchmark_target <- decode_semicolon_numeric(paired$eval_target_sum.y[[idx]])
      if (length(method_sum) != length(benchmark_sum) ||
          length(method_sum) != length(method_target) ||
          length(benchmark_sum) != length(benchmark_target)) {
        stop("Paired methods have different held-out evaluation row counts.")
      }
      if (length(method_target) && any(abs(method_target - benchmark_target) > 1e-8, na.rm = TRUE)) {
        stop("Paired methods have inconsistent held-out target scores for evaluation rows.")
      }
      method_metric <- validity_metric_from_scores(method_sum, method_target, metric)
      benchmark_metric <- validity_metric_from_scores(benchmark_sum, benchmark_target, metric)
      if (is.finite(method_metric) && is.finite(benchmark_metric)) {
        method_value <- c(method_value, method_metric)
        benchmark_value <- c(benchmark_value, benchmark_metric)
      }
    }
  } else {
    method_value <- suppressWarnings(as.numeric(paired$method_value))
    benchmark_value <- suppressWarnings(as.numeric(paired$benchmark_value))
    keep <- is.finite(method_value) & is.finite(benchmark_value)
    method_value <- method_value[keep]
    benchmark_value <- benchmark_value[keep]
  }
  raw_diff <- method_value - benchmark_value
  n_pairs <- length(raw_diff)

  mean_diff <- if (n_pairs) mean(raw_diff) else NA_real_
  ci <- if (n_pairs > 1L && stats::sd(raw_diff) > 0) {
    half_width <- stats::qt(0.975, df = n_pairs - 1L) * stats::sd(raw_diff) / sqrt(n_pairs)
    c(mean_diff - half_width, mean_diff + half_width)
  } else c(NA_real_, NA_real_)
  p_value <- NA_real_
  if (n_pairs > 1L) {
    test <- tryCatch(stats::t.test(raw_diff, mu = 0, alternative = "two.sided"), error = function(e) NULL)
    if (!is.null(test)) p_value <- test$p.value
  }

  list(
    method = method,
    metric = metric,
    benchmark = benchmark,
    mean_diff = mean_diff,
    ci_lower = ci[[1]],
    ci_upper = ci[[2]],
    p = p_value,
    valid_paired_repetitions = n_pairs
  )
}

paired_comparison_summary <- function(results, summary) {
  comparison_specs <- data.frame(
    stage = c("nuisance_screening", "candidate_selection", "candidate_selection",
      rep("short_form_evaluation", 2L)),
    metric = c("nuisance_selected_n", "overlap_n", "a_abs_diff_median",
      "pearson_r", "spearman_r"),
    stringsAsFactors = FALSE
  )
  benchmarks <- c("human100", "human300", "human1000", "reference")
  llm_methods <- methods_to_include[!methods_to_include %in% c("human100", "human300", "human1000")]

  out <- data.frame(row.names = seq_len(nrow(summary)))

  for (spec_idx in seq_len(nrow(comparison_specs))) {
    spec <- comparison_specs[spec_idx, , drop = FALSE]
    score_methods <- if (spec$stage == "short_form_evaluation") "SUM_SCORE" else NA_character_
    for (score_method in score_methods) {
      family <- list()
      comparison_methods <- if (spec$metric == "a_abs_diff_median") setdiff(llm_methods, "random10") else llm_methods
      for (benchmark in benchmarks) for (method in comparison_methods) {
        family[[length(family) + 1L]] <- paired_test_row(
          results = results,
          stage = spec$stage,
          metric = spec$metric,
          method = method,
          benchmark = benchmark,
          scoring_method = if (is.na(score_method)) NULL else score_method
        )
      }
      p_values <- vapply(family, function(x) x$p, numeric(1))
      p_holm <- rep(NA_real_, length(p_values))
      finite_p <- is.finite(p_values)
      # Keep the existing synthetic-method correction family unchanged. The
      # random baseline's four benchmark comparisons form their own family.
      random_family <- vapply(family, function(x) x$method == "random10", logical(1))
      for (is_random in c(FALSE, TRUE)) {
        keep <- finite_p & random_family == is_random
        if (any(keep)) p_holm[keep] <- stats::p.adjust(p_values[keep], method = "holm")
      }

      for (idx in seq_along(family)) {
        record <- family[[idx]]
        record$p_holm <- p_holm[[idx]]

        row_idx <- which(summary$stage == spec$stage & summary$method == record$method)
        if (spec$stage == "short_form_evaluation") row_idx <- row_idx[summary$scoring_method[row_idx] == score_method]
        if (!length(row_idx)) {
          next
        }

        prefix <- paste0(spec$metric, "_vs_", record$benchmark)
        new_cols <- c(
          paste0(prefix, "_mean_diff"),
          paste0(prefix, "_ci_lower"), paste0(prefix, "_ci_upper"),
          paste0(prefix, "_p_holm"),
          paste0(prefix, "_valid_paired_repetitions")
        )
        for (new_col in new_cols) {
          if (!(new_col %in% names(out))) {
            out[[new_col]] <- NA_real_
          }
        }
        out[[paste0(prefix, "_mean_diff")]][row_idx] <- record$mean_diff
        out[[paste0(prefix, "_ci_lower")]][row_idx] <- record$ci_lower
        out[[paste0(prefix, "_ci_upper")]][row_idx] <- record$ci_upper
        out[[paste0(prefix, "_p_holm")]][row_idx] <- record$p_holm
        out[[paste0(prefix, "_valid_paired_repetitions")]][row_idx] <- record$valid_paired_repetitions
      }
    }
  }

  out
}

bind_result_rows <- function(results) {
  if (!length(results)) {
    return(make_result_row(list())[0, , drop = FALSE])
  }

  schema <- names(make_result_row(list()))
  all_names <- unique(c(schema, unlist(lapply(results, names), use.names = FALSE)))
  all_names <- setdiff(all_names, "nuisance_selected_any")

  aligned <- lapply(results, function(row) {
    missing_cols <- setdiff(all_names, names(row))
    for (col in missing_cols) {
      row[[col]] <- NA
    }
    row[, all_names, drop = FALSE]
  })

  do.call(rbind, aligned)
}

read_resume_state <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }

  state <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(state) != 1L) {
    stop(sprintf("Resume state file %s is malformed.", path))
  }

  out <- list(
    seed = as.integer(state$seed[[1]]),
    target_reps = as.integer(state$target_reps[[1]]),
    success_count = as.integer(state$success_count[[1]]),
    attempt_count = as.integer(state$attempt_count[[1]])
  )
  for (field in c("results_bytes", "events_bytes", "summary_count")) {
    if (field %in% names(state)) out[[field]] <- as.numeric(state[[field]][[1]])
  }
  if (any(!is.finite(unlist(out))) || out$success_count < 0 || out$attempt_count < out$success_count ||
      out$target_reps < out$success_count) stop("Invalid checkpoint state.")
  if (!is.null(out$summary_count) && (out$summary_count < 0 || out$summary_count > out$success_count ||
      out$summary_count %% 10L != 0L)) stop("Invalid scheduled-report checkpoint.")
  out
}

write_resume_state <- function(path, seed, target_reps, success_count, attempt_count,
                               results_bytes = NULL, events_bytes = NULL, summary_count = NULL) {
  state <- data.frame(
    seed = seed,
    target_reps = target_reps,
    success_count = success_count,
    attempt_count = attempt_count,
    stringsAsFactors = FALSE
  )
  if (!is.null(results_bytes)) state$results_bytes <- results_bytes
  if (!is.null(events_bytes)) state$events_bytes <- events_bytes
  if (!is.null(summary_count)) state$summary_count <- summary_count
  staged <- tempfile(".mc-state-", tmpdir = dirname(path))
  on.exit(unlink(staged))
  write.csv(state, staged, row.names = FALSE)
  suspendInterrupts({
    if (!file.rename(staged, path)) stop("Could not publish checkpoint state.")
  })
}

display_header <- function(x) {
  x <- gsub("_p_holm$", "_Holm adjusted p", x)
  x <- gsub("_mean_diff$", "_mean difference", x)
  x <- gsub("_n_pairs$", "_complete paired repetitions", x)
  x <- gsub("_mean$", "_mean", x)
  x <- gsub("_sd$", "_SD", x)
  x <- gsub("_", " ", x)
  x <- gsub("\\bdz\\b", "paired dz", x)
  x <- gsub("\\br squared\\b", "R squared", x)
  x <- gsub("\\brmse\\b", "RMSE", x)
  x <- gsub("\\bmae\\b", "MAE", x)
  x <- gsub("\\ba\\b", "a", x)
  x
}

summary_sheet_data <- function(summary_df, stage, descriptive_metrics, comparison_metrics = character(0)) {
  rows <- summary_df[summary_df$stage == stage, , drop = FALSE]
  base_cols <- c("method", "successful_method_reps", "attempted_reps", "method_failure_repetitions", "item_drop_repetitions")
  if (identical(stage, "short_form_evaluation")) {
    base_cols <- c(base_cols, "scoring_method")
  }
  descriptive_cols <- paste0(descriptive_metrics, "_mean")
  comparison_cols <- character(0)
  for (metric in comparison_metrics) {
    for (benchmark in c("human100", "human300", "human1000", "reference")) {
      comparison_cols <- c(
        comparison_cols,
        paste0(metric, "_vs_", benchmark, "_mean_diff"),
        paste0(metric, "_vs_", benchmark, "_ci_lower"),
        paste0(metric, "_vs_", benchmark, "_ci_upper"),
        paste0(metric, "_vs_", benchmark, "_p_holm"),
        paste0(metric, "_vs_", benchmark, "_valid_paired_repetitions")
      )
    }
  }

  cols <- c(base_cols, descriptive_cols, comparison_cols)
  cols <- cols[cols %in% names(rows)]
  out <- rows[, cols, drop = FALSE]
  names(out) <- display_header(names(out))
  out
}

write_summary_workbook <- function(summary_df, output_path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("The openxlsx package is required to write monte_carlo_comparisons.xlsx.")
  }

  sheets <- list(
    "Nuisance screening" = summary_sheet_data(
      summary_df,
      stage = "nuisance_screening",
      descriptive_metrics = "nuisance_selected_n",
      comparison_metrics = "nuisance_selected_n"
    ),
    "Parameter recovery" = summary_sheet_data(
      summary_df[summary_df$method != "random10", , drop = FALSE],
      stage = "candidate_selection",
      descriptive_metrics = c(
        "a_abs_diff_median",
        "b1_abs_diff_median",
        "b2_abs_diff_median",
        "b3_abs_diff_median",
        "b4_abs_diff_median"
      ),
      comparison_metrics = "a_abs_diff_median"
    ),
    "Item overlap" = summary_sheet_data(
      summary_df,
      stage = "candidate_selection",
      descriptive_metrics = "overlap_n",
      comparison_metrics = "overlap_n"
    ),
    "Held-out validity" = summary_sheet_data(
      summary_df,
      stage = "short_form_evaluation",
      descriptive_metrics = c("pearson_r", "spearman_r"),
      comparison_metrics = c("pearson_r", "spearman_r")
    )
  )

  workbook <- openxlsx::createWorkbook()
  header_style <- openxlsx::createStyle(textDecoration = "bold", halign = "center", valign = "center")
  numeric_style <- openxlsx::createStyle(numFmt = "0.000")
  p_style <- openxlsx::createStyle(numFmt = "0.0000")

  for (sheet_name in names(sheets)) {
    sheet_data <- sheets[[sheet_name]]
    openxlsx::addWorksheet(workbook, sheet_name)
    openxlsx::writeData(workbook, sheet_name, sheet_data, withFilter = TRUE)
    openxlsx::freezePane(workbook, sheet_name, firstRow = TRUE)
    openxlsx::addStyle(
      workbook,
      sheet = sheet_name,
      style = header_style,
      rows = 1,
      cols = seq_len(ncol(sheet_data)),
      gridExpand = TRUE
    )

    numeric_cols <- which(vapply(sheet_data, is.numeric, logical(1)))
    if (length(numeric_cols) && nrow(sheet_data) > 0L) {
      openxlsx::addStyle(
        workbook,
        sheet = sheet_name,
        style = numeric_style,
        rows = seq.int(2L, nrow(sheet_data) + 1L),
        cols = numeric_cols,
        gridExpand = TRUE,
        stack = TRUE
      )
      p_cols <- grep("Holm adjusted p", names(sheet_data), fixed = TRUE)
      if (length(p_cols)) {
        openxlsx::addStyle(
          workbook,
          sheet = sheet_name,
          style = p_style,
          rows = seq.int(2L, nrow(sheet_data) + 1L),
          cols = p_cols,
          gridExpand = TRUE,
          stack = TRUE
        )
      }
    }

    widths <- pmin(pmax(nchar(names(sheet_data)) + 2L, 12L), 32L)
    widths[seq_along(widths) %in% which(names(sheet_data) == "method")] <- 34L
    openxlsx::setColWidths(workbook, sheet = sheet_name, cols = seq_along(widths), widths = widths)
  }

  openxlsx::saveWorkbook(workbook, output_path, overwrite = TRUE)
}

output_paths <- function(output_dir) {
  setNames(file.path(output_dir, c("monte_carlo_results.csv", "monte_carlo_exclusions_and_failures.csv",
    "monte_carlo_state.csv", "monte_carlo_summary.csv", "monte_carlo_comparisons.xlsx")),
    c("results", "events", "state", "summary", "workbook"))
}

empty_event_rows <- function() {
  data.frame(record_type = character(), repetition = integer(), attempt = integer(), seed = integer(),
    method = character(), items = character(), reason = character(), stringsAsFactors = FALSE)
}

detailed_result_rows <- function(rows) {
  out <- if (is.data.frame(rows)) rows else bind_result_rows(rows)
  for (field in c("attempt", "seed")) {
    if (!field %in% names(out)) {
      if (nrow(out)) stop("Missing attempt/seed in detailed checkpoint rows.")
      out[[field]] <- integer()
    }
  }
  out
}

# Preserve the original paired statistics: compute exactly the same correlations
# from each score vector once, validate shared targets, then discard the vectors
# from memory. The complete vectors are still appended to the detailed CSV.
compact_result_rows <- function(rows) {
  out <- detailed_result_rows(rows)
  out$.paired_pearson_r <- rep(NA_real_, nrow(out))
  out$.paired_spearman_r <- rep(NA_real_, nrow(out))
  targets <- new.env(parent = emptyenv())
  for (idx in which(out$stage == "short_form_evaluation")) {
    short <- decode_semicolon_numeric(out$eval_short_sum[idx])
    target <- decode_semicolon_numeric(out$eval_target_sum[idx])
    if (!length(short) || length(short) != length(target) || any(!is.finite(c(short, target))) ||
        !isTRUE(length(short) == as.numeric(out$eval_n[idx]))) stop("Invalid evaluation vectors in checkpoint.")
    key <- as.character(out$repetition[idx])
    if (exists(key, envir = targets, inherits = FALSE) && !identical(targets[[key]], target)) stop("Inconsistent held-out targets.")
    targets[[key]] <- target
    for (metric in c("pearson_r", "spearman_r")) {
      value <- suppressWarnings(validity_metric_from_scores(short, target, metric))
      if (!isTRUE(all.equal(value, as.numeric(out[[metric]][idx]), tolerance = 1e-12))) stop("Inconsistent recorded correlation.")
      out[[paste0(".paired_", metric)]][idx] <- value
    }
  }
  out$eval_short_sum <- NULL
  out$eval_target_sum <- NULL
  attr(out, "validated_sum_scores") <- TRUE
  out
}

save_state_list <- function(path, state) {
  do.call(write_resume_state, c(list(path = path), state))
}

truncate_checkpoint_file <- function(path, bytes) {
  con <- file(path, "r+b")
  on.exit(close(con))
  seek(con, where = bytes, origin = "start", rw = "write")
  truncate(con)
  if (file.info(path)$size != bytes) stop("Could not truncate an uncommitted append.")
}

recover_checkpoint_tails <- function(paths, state) {
  expected <- c(results = state$results_bytes, events = state$events_bytes)
  actual <- file.info(paths[names(expected)])$size
  if (length(expected) != 2L || any(!is.finite(expected)) || any(expected < 1 | expected != floor(expected)) ||
      any(!is.finite(actual)) || any(actual < expected)) stop("A committed checkpoint file is missing or truncated; refusing to discard saved repetitions.")
  suspendInterrupts({
    for (idx in seq_along(expected)) {
      if (actual[idx] > expected[idx]) {
        truncate_checkpoint_file(paths[names(expected)[idx]], expected[idx])
        cat(sprintf("Recovered unfinished append in %s.\n", basename(paths[names(expected)[idx]])))
      }
    }
  })
}

# Legacy state has no byte offsets. A one-time streaming pass identifies only
# trailing rows beyond its committed repetition; historical rows are never rewritten.
legacy_committed_bytes <- function(path, completed) {
  con <- file(path, "rb")
  on.exit(close(con))
  size <- file.info(path)$size
  if (!is.finite(size) || size < 1) stop("Missing or empty legacy checkpoint CSV.")
  seek(con, where = size - 1, origin = "start")
  final_newline <- identical(readBin(con, "raw", n = 1L), as.raw(10))
  seek(con, where = 0, origin = "start")
  header <- names(read.csv(text = readLines(con, n = 1L), nrows = 0L, check.names = FALSE))
  rep_column <- match("repetition", header)
  if (is.na(rep_column)) stop("Missing repetition column in legacy output.")
  committed <- seek(con, where = NA, rw = "read")
  tail_started <- FALSE
  repeat {
    line <- readLines(con, n = 1L, warn = FALSE)
    if (!length(line)) break
    fields <- strsplit(line, ",", fixed = TRUE)[[1]]
    rep <- suppressWarnings(as.numeric(gsub('"', "", fields[rep_column], fixed = TRUE)))
    if (length(rep) != 1L || !is.finite(rep) || rep < 1 || rep != floor(rep)) stop("Cannot identify repetition in a legacy output tail.")
    if (rep > completed) {
      tail_started <- TRUE
      next
    }
    if (tail_started) stop("Uncommitted legacy rows are interleaved with committed rows; refusing to truncate.")
    split_results_csv_line(line, length(header))
    committed <- seek(con, where = NA, rw = "read")
    if (committed == size && !final_newline) stop("A committed legacy row is incomplete.")
  }
  committed
}

prepare_output_run <- function(output_dir, resume, seed, target_reps, additional_reps = NA_integer_) {
  paths <- output_paths(output_dir)
  if (!resume) {
    state <- list(seed = seed, target_reps = target_reps, success_count = 0L, attempt_count = 0L,
      results_bytes = 0, events_bytes = 0, summary_count = 0L)
    suspendInterrupts({
      write.csv(detailed_result_rows(list()), paths["results"], row.names = FALSE)
      write.csv(empty_event_rows(), paths["events"], row.names = FALSE)
      state$results_bytes <- file.info(paths["results"])$size
      state$events_bytes <- file.info(paths["events"])$size
      save_state_list(paths["state"], state)
    })
    return(list(state = state, results = compact_result_rows(list()), events = list(),
      header = names(detailed_result_rows(list()))))
  }
  state <- read_resume_state(paths["state"])
  if (is.null(state)) stop("Resume requested, but the state file does not exist.")
  if (state$seed != seed) stop("Resume seed mismatch.")
  state$target_reps <- if (is.na(additional_reps)) state$target_reps else state$success_count + additional_reps
  if (state$target_reps < state$success_count) stop("Target is less than the completed repetition count.")
  if (!file.exists(paths["events"])) write.csv(empty_event_rows(), paths["events"], row.names = FALSE)
  if (is.null(state$results_bytes) || is.null(state$events_bytes)) {
    state$results_bytes <- legacy_committed_bytes(paths["results"], state$success_count)
    state$events_bytes <- legacy_committed_bytes(paths["events"], state$success_count)
  }
  recover_checkpoint_tails(paths, state)
  cat(sprintf("Loading compact checkpoint through repetition %d (score vectors are not retained)...\n", state$success_count))
  checkpoint <- read_random10_checkpoint(paths["results"], state, allow_empty = TRUE)
  if (nrow(checkpoint$data) && any(checkpoint$data$seed != checkpoint$data$attempt)) stop("Existing results use a different seed mapping.")
  events <- read.csv(paths["events"], stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(names(empty_event_rows()) %in% names(events))) stop("Unexpected exclusions/failures log schema.")
  covered <- union(checkpoint$data$repetition, events$repetition[events$record_type == "method_failure"])
  if (!all(seq_len(state$success_count) %in% covered)) stop("A committed repetition is missing from both results and the failure log.")
  if (nrow(checkpoint$data)) {
    groups <- split(checkpoint$data$stage, paste(checkpoint$data$repetition, checkpoint$data$method, sep = "/"))
    stages <- c("nuisance_screening", "candidate_selection", "short_form_evaluation")
    if (any(!vapply(groups, function(x) length(x) == 3L && setequal(x, stages), logical(1)))) {
      stop("A committed method has incomplete result rows; refusing to skip it on resume.")
    }
  }
  if (is.null(state$summary_count)) state$summary_count <- state$success_count - state$success_count %% 10L
  save_state_list(paths["state"], state)
  list(state = state, results = checkpoint$data,
    events = if (nrow(events)) split(events, seq_len(nrow(events))) else list(), header = checkpoint$header)
}

append_checkpoint_csv <- function(rows, path, header) {
  if (!nrow(rows)) return(invisible(NULL))
  if (!setequal(names(rows), header)) stop("Checkpoint CSV schema mismatch.")
  write.table(rows[, header, drop = FALSE], path, append = TRUE, sep = ",", quote = TRUE,
    row.names = FALSE, col.names = FALSE, na = "NA", qmethod = "double")
}

save_repetition_checkpoint <- function(rows, events, output_dir, state, header) {
  paths <- output_paths(output_dir)
  rows <- detailed_result_rows(rows)
  event_df <- if (length(events)) do.call(rbind, events) else empty_event_rows()
  next_rep <- state$success_count + 1L
  if (nrow(rows) && any(rows$repetition != next_rep | rows$attempt != state$attempt_count + 1L)) stop("Wrong repetition in checkpoint append.")
  if (nrow(rows) && (any(rows$seed != state$seed + state$attempt_count) ||
      anyDuplicated(paste(rows$repetition, rows$method, rows$stage)))) stop("Invalid seed or duplicate checkpoint rows.")
  if (nrow(event_df) && any(event_df$repetition != next_rep | event_df$attempt != state$attempt_count + 1L |
      event_df$seed != state$seed + state$attempt_count)) stop("Wrong repetition/seed in log append.")
  compact <- compact_result_rows(rows)
  actual <- file.info(paths[c("results", "events")])$size
  if (!identical(as.numeric(actual), as.numeric(c(state$results_bytes, state$events_bytes)))) stop("Output files changed outside the checkpoint writer; use --resume to recover.")
  # Closing both append writes flushes them before atomically committing state.
  # Ctrl+C is deferred across this short transaction. If the process is killed,
  # old state byte offsets let --resume remove only the unfinished append.
  suspendInterrupts({
    append_checkpoint_csv(rows, paths["results"], header)
    append_checkpoint_csv(event_df, paths["events"], names(empty_event_rows()))
    state$results_bytes <- file.info(paths["results"])$size
    state$events_bytes <- file.info(paths["events"])$size
    state$success_count <- next_rep
    state$attempt_count <- state$attempt_count + 1L
    save_state_list(paths["state"], state)
  })
  cat(sprintf("Checkpoint saved: repetition %d/%d; appended %d result rows and %d log rows.\n",
    state$success_count, state$target_reps, nrow(rows), nrow(event_df)))
  list(state = state, compact = compact)
}

generate_scheduled_reports <- function(results, event_rows, method_names, output_dir, state) {
  count <- state$success_count
  if (!count || count %% 10L != 0L || state$summary_count >= count) return(state)
  cat(sprintf("Generating summary CSV and comparison XLSX for repetition %d...\n", count))
  summary <- summarise_results(results, method_names)
  failures <- summarize_method_failures(event_rows, method_names, results, state$attempt_count)
  for (field in c("attempted_reps", "method_failure_repetitions", "item_drop_repetitions")) {
    summary[[field]] <- failures[[field]][match(summary$method, failures$method)]
  }
  paths <- output_paths(output_dir)
  staged <- c(summary = tempfile(".mc-summary-", tmpdir = output_dir, fileext = ".csv"),
    workbook = tempfile(".mc-workbook-", tmpdir = output_dir, fileext = ".xlsx"))
  on.exit(unlink(staged))
  write.csv(summary, staged["summary"], row.names = FALSE)
  write_summary_workbook(summary, staged["workbook"])
  suspendInterrupts({
    for (name in names(staged)) if (!file.rename(staged[name], paths[name])) stop("Could not publish scheduled reports; --resume will retry.")
    state$summary_count <- count
    save_state_list(paths["state"], state)
  })
  cat(sprintf("Summary CSV and comparison XLSX saved through repetition %d.\n", count))
  state
}

summarize_method_failures <- function(failure_rows, method_names, results, attempt_count) {
  rows <- if (length(failure_rows)) do.call(rbind, failure_rows) else data.frame()
  result_rows <- if (is.data.frame(results)) results else bind_result_rows(results)
  data.frame(
    stage = rep("method_failure_summary", length(method_names)),
    method = method_names,
    successful_method_reps = vapply(method_names, function(method_name) {
      if (!nrow(result_rows)) return(0L)
      length(unique(result_rows$repetition[result_rows$method == method_name]))
    }, integer(1)),
    attempted_reps = as.integer(attempt_count),
    method_failure_repetitions = vapply(method_names, function(method_name) {
      if (!nrow(rows)) return(0L)
      length(unique(rows$repetition[rows$method == method_name & rows$record_type == "method_failure"]))
    }, integer(1)),
    item_drop_repetitions = vapply(method_names, function(method_name) {
      if (!nrow(rows)) return(0L)
      length(unique(rows$repetition[rows$method == method_name & rows$record_type == "item_exclusion"]))
    }, integer(1)),
    stringsAsFactors = FALSE
  )
}

# Separate CSV fields before handing compact metadata to read.table: base R's
# CSV scanner is very slow on megabyte-sized quoted score fields. The uncommon
# quoted-comma case is reassembled using quote parity (escaped quotes count twice).
split_results_csv_line <- function(line, columns) {
  fields <- strsplit(line, ",", fixed = TRUE)[[1]]
  if (endsWith(line, ",")) fields <- c(fields, "")
  if (length(fields) != columns) {
    quotes <- vapply(fields, function(x) nchar(x) - nchar(gsub("\"", "", x, fixed = TRUE)), integer(1))
    open <- cumsum(quotes) %% 2L
    if (!length(open) || tail(open, 1L) != 0L) stop("Unterminated quoted CSV field.")
    starts <- which(c(0L, head(open, -1L)) == 0L)
    ends <- which(open == 0L)
    if (length(starts) != length(ends)) stop("Malformed CSV fields.")
    fields <- vapply(seq_along(starts), function(i) paste(fields[starts[i]:ends[i]], collapse = ","), character(1))
  }
  if (length(fields) != columns) stop("Incorrect number of CSV fields.")
  fields
}

decode_results_score_field <- function(value) {
  if (startsWith(value, "\"")) {
    if (!endsWith(value, "\"") || nchar(value) < 2L) stop("Unterminated score field.")
    value <- substring(value, 2L, nchar(value) - 1L)
  }
  if (grepl("\"", value, fixed = TRUE)) stop("Invalid quote in score field.")
  decode_semicolon_numeric(value)
}

# Read once in bounded chunks, recompute/validate correlations once per row,
# then retain only compact summary data and one held-out target per repetition.
read_random10_checkpoint <- function(path, state, chunk_rows = 32L, allow_empty = FALSE) {
  con <- file(path, "rb")
  on.exit(close(con))
  size <- file.info(path)$size
  if (!is.finite(size) || size < 1) stop("Results CSV is empty.")
  seek(con, where = size - 1, origin = "start")
  if (!identical(readBin(con, "raw", n = 1L), as.raw(10))) {
    stop("Results CSV has an incomplete final line; no files were changed.")
  }
  seek(con, where = 0, origin = "start")
  header <- names(read.csv(text = readLines(con, n = 1L), nrows = 0L, check.names = FALSE))
  required <- c(names(make_result_row(list())), "attempt", "seed")
  if (anyDuplicated(header) || !all(required %in% header)) stop("Unexpected results CSV schema.")
  vector_columns <- match(c("eval_short_sum", "eval_target_sum"), header)
  compact_header <- header[-vector_columns]
  chunks <- list()
  targets <- new.env(parent = emptyenv())
  random_scores <- new.env(parent = emptyenv())
  total <- 0L
  repeat {
    lines <- readLines(con, n = chunk_rows, warn = FALSE)
    if (!length(lines)) break
    fields <- lapply(lines, split_results_csv_line, columns = length(header))
    metadata_lines <- vapply(fields, function(row) paste(row[-vector_columns], collapse = ","), character(1))
    chunk <- read.table(text = metadata_lines, header = FALSE, sep = ",", quote = "\"", comment.char = "",
      col.names = compact_header, colClasses = "character", na.strings = "NA", check.names = FALSE,
      row.names = NULL, fill = FALSE, blank.lines.skip = FALSE)
    if (ncol(chunk) != length(compact_header) || nrow(chunk) != length(lines)) stop("Malformed results CSV rows.")
    if (anyNA(chunk$workflow_version) || any(chunk$workflow_version != "24_to_10_sum_v5")) {
      stop("Backfill requires workflow 24_to_10_sum_v5; no files were changed.")
    }
    for (field in c("repetition", "attempt", "seed")) {
      number <- suppressWarnings(as.numeric(chunk[[field]]))
      if (any(!is.finite(number) | number < 1 | number != floor(number))) stop("Invalid repetition/seed metadata.")
      chunk[[field]] <- as.integer(number)
    }
    if (any(chunk$repetition > state$success_count | chunk$attempt > state$attempt_count) ||
        any(chunk$seed != state$seed + chunk$attempt - 1L)) {
      stop("Results extend beyond or disagree with the saved checkpoint; no files were changed.")
    }
    if (anyNA(chunk$stage) || anyNA(chunk$method)) stop("Missing stage/method metadata.")
    chunk$.paired_pearson_r <- rep(NA_real_, nrow(chunk))
    chunk$.paired_spearman_r <- rep(NA_real_, nrow(chunk))
    for (idx in which(chunk$stage == "short_form_evaluation")) {
      if (is.na(chunk$scoring_method[idx]) || chunk$scoring_method[idx] != "SUM_SCORE") stop("Unexpected scoring method.")
      short <- decode_results_score_field(fields[[idx]][vector_columns[1]])
      target <- decode_results_score_field(fields[[idx]][vector_columns[2]])
      if (!length(short) || length(short) != length(target) || any(!is.finite(c(short, target))) ||
          !isTRUE(length(short) == as.numeric(chunk$eval_n[idx]))) stop("Invalid evaluation score vectors.")
      key <- as.character(chunk$repetition[idx])
      if (exists(key, envir = targets, inherits = FALSE)) {
        if (!identical(target, targets[[key]])) stop("Held-out targets differ between methods within a repetition.")
      } else targets[[key]] <- target
      for (metric in c("pearson_r", "spearman_r")) {
        value <- suppressWarnings(validity_metric_from_scores(short, target, metric))
        stored <- suppressWarnings(as.numeric(chunk[[metric]][idx]))
        if (!isTRUE(all.equal(value, stored, tolerance = 1e-12))) stop("Recorded correlation disagrees with score vectors.")
        chunk[[paste0(".paired_", metric)]][idx] <- value
      }
      if (chunk$method[idx] == "random10") random_scores[[key]] <- short
    }
    chunks[[length(chunks) + 1L]] <- chunk
    total <- total + nrow(chunk)
    if (total %% 512L == 0L) cat(sprintf("Validated %d saved result rows...\n", total))
  }
  if (!length(chunks) && !allow_empty) stop("No completed result rows are available to backfill.")
  compact <- if (length(chunks)) do.call(rbind, chunks) else compact_result_rows(list())
  keys <- paste(compact$repetition, compact$method, compact$stage, sep = "/")
  if (anyDuplicated(keys)) stop("Duplicate repetition/method/stage rows found; no files were changed.")
  attr(compact, "validated_sum_scores") <- TRUE
  list(data = compact, header = header, targets = targets, random_scores = random_scores, row_count = total)
}

split_recorded_items <- function(value) {
  if (length(value) != 1L || is.na(value) || !nzchar(value)) stop("Missing recorded item list.")
  items <- strsplit(value, ";", fixed = TRUE)[[1]]
  if (anyDuplicated(items) || any(!nzchar(items))) stop("Invalid recorded item list.")
  items
}

random10_checkpoint_metadata <- function(checkpoint, state, item_meta) {
  data <- checkpoint$data
  stages <- c("nuisance_screening", "candidate_selection", "short_form_evaluation")
  expected_reps <- seq_len(state$success_count)
  if (!setequal(unique(data$repetition), expected_reps)) stop("Results are missing completed repetitions from state.")
  nuisance <- item_meta$item_code[61:64]
  ext <- item_meta$item_code[1:60]
  lapply(expected_reps, function(rep) {
    rows <- data[data$repetition == rep, , drop = FALSE]
    ref <- rows[rows$method == "reference", , drop = FALSE]
    if (!setequal(ref$stage, stages) || nrow(ref) != 3L) stop(sprintf("Repetition %d lacks complete reference metadata.", rep))
    if (length(unique(rows$seed)) != 1L || length(unique(rows$attempt)) != 1L) stop("Inconsistent repetition seeds/attempts.")
    eval <- ref[ref$stage == "short_form_evaluation", , drop = FALSE]
    train <- split_recorded_items(eval$train_items)
    heldout <- split_recorded_items(eval$heldout_items)
    selected <- split_recorded_items(eval$selected_items)
    original <- c(train, nuisance)
    recorded <- split_recorded_items(eval$candidate_items)
    if (length(train) != 20L || !all(train %in% ext) || length(heldout) != 40L ||
        !setequal(heldout, setdiff(ext, train)) || length(selected) != 10L ||
        !all(selected %in% recorded) || !all(recorded %in% original) ||
        !all(ref$selected_items == eval$selected_items) ||
        (length(recorded) == 24L && !identical(recorded, original))) {
      stop(sprintf("Invalid original candidate/reference/held-out metadata in repetition %d.", rep))
    }
    baseline <- rows[rows$method == "random10", , drop = FALSE]
    if (any(!baseline$stage %in% stages)) stop("Unexpected random10 stage.")
    expected_selection <- paste(random10_selection(original, eval$seed), collapse = ";")
    if (nrow(baseline) && (anyNA(baseline$selected_items) || any(baseline$selected_items != expected_selection) ||
        any(baseline$candidate_items != paste(original, collapse = ";")))) stop("Existing random10 selection is inconsistent with its recorded seed/candidates.")
    parameter_cols <- grep("^(a_|b[1-4]_|compared_parameters$)", names(baseline), value = TRUE)
    if (nrow(baseline) && any(!is.na(as.matrix(baseline[, parameter_cols, drop = FALSE])))) stop("random10 has unexpected parameter recovery values.")
    list(repetition = rep, attempt = eval$attempt, seed = eval$seed, candidate_items = original,
      reference_selected = selected, train_items = train, heldout_items = heldout,
      nuisance_items = nuisance, missing = setdiff(stages, baseline$stage))
  })
}

check_random10_row <- function(actual, expected) {
  for (field in intersect(names(actual), names(expected))) {
    a <- actual[[field]]
    e <- expected[[field]]
    if (is.numeric(e)) {
      a <- suppressWarnings(as.numeric(a))
      matches <- isTRUE(all.equal(a, e, tolerance = 1e-12, check.attributes = FALSE))
    } else matches <- identical(as.character(a), as.character(e))
    if (!matches) stop(sprintf("Existing random10 row disagrees with expected %s (repetition %s).", field, expected$repetition))
  }
}

backfill_random10 <- function(output_dir, verify_only = FALSE) {
  paths <- file.path(output_dir, c("monte_carlo_results.csv", "monte_carlo_summary.csv",
    "monte_carlo_comparisons.xlsx", "monte_carlo_state.csv", "monte_carlo_exclusions_and_failures.csv"))
  names(paths) <- c("results", "summary", "workbook", "state", "events")
  # Detect concurrent changes before publishing; never use this alongside a live simulation.
  signature <- function() {
    info <- file.info(paths)
    list(size = info$size, mtime = as.numeric(info$mtime), state = unname(tools::md5sum(paths["state"])))
  }
  before <- signature()
  state <- read_resume_state(paths["state"])
  if (is.null(state) || any(!is.finite(unlist(state))) || state$success_count < 1L ||
      state$success_count > state$attempt_count || state$attempt_count > state$target_reps) stop("Invalid or missing checkpoint state.")
  if (!is.null(state$results_bytes) && !is.null(state$events_bytes)) {
    actual <- file.info(paths[c("results", "events")])$size
    committed <- c(state$results_bytes, state$events_bytes)
    if (!identical(as.numeric(actual), as.numeric(committed))) {
      if (verify_only) stop("Checkpoint has an unfinished append; recover with --resume or --backfill-random10 first.")
      recover_checkpoint_tails(output_paths(output_dir), state)
      before <- signature()
    }
  }
  cat("Reading and validating the saved checkpoint (no simulation/IRT fits)...\n")
  checkpoint <- read_random10_checkpoint(paths["results"], state)
  item_meta <- read_item_meta(item_meta_path)
  metadata <- random10_checkpoint_metadata(checkpoint, state, item_meta)
  missing <- sum(vapply(metadata, function(x) length(x$missing), integer(1)))
  cat(sprintf("Checkpoint: %d completed repetitions, %d attempts, target %d; %d result rows; %d missing random10 rows.\n",
    state$success_count, state$attempt_count, state$target_reps, checkpoint$row_count, missing))
  if (verify_only && missing) stop("random10 verification failed: expected three rows per completed repetition.")
  if (!verify_only && !missing) {
    if (!identical(before, signature())) stop("Checkpoint changed during verification.")
    cat("random10 is caught up: three unique rows per completed repetition. No files changed.\n")
    return(invisible(list(added_rows = 0L, completed = state$success_count)))
  }
  human_test <- load_human_matrix(human_test_path, item_meta)
  additions <- list()
  for (meta in metadata) {
    if (!verify_only && !length(meta$missing)) next
    arguments <- meta[setdiff(names(meta), "missing")]
    expected <- do.call(build_random10_rows, c(arguments, list(human_test = human_test)))
    key <- as.character(meta$repetition)
    scores <- attr(expected, "scores")
    if (!identical(unname(scores$target_values), checkpoint$targets[[key]])) stop("Original human test data do not match the saved held-out targets.")
    if (exists(key, envir = checkpoint$random_scores, inherits = FALSE) &&
        !identical(unname(scores$short_sum_values), checkpoint$random_scores[[key]])) stop("Saved random10 scores do not match the human test data.")
    for (row in expected) {
      actual <- checkpoint$data[checkpoint$data$method == "random10" & checkpoint$data$repetition == meta$repetition &
        checkpoint$data$stage == row$stage, , drop = FALSE]
      if (nrow(actual)) check_random10_row(actual, row)
      else additions[[length(additions) + 1L]] <- row
    }
  }
  if (verify_only) {
    if (!identical(before, signature())) stop("Checkpoint changed during verification.")
    cat(sprintf("Verified: %d random10 rows, exactly three per repetition; seeds, selections, scores and NA parameters match. No files changed.\n", state$success_count * 3L))
    return(invisible(TRUE))
  }
  added <- bind_result_rows(additions)
  if (nrow(added) != missing) stop("Internal error: incorrect number of backfill rows.")
  for (field in setdiff(checkpoint$header, names(added))) added[[field]] <- NA
  added <- added[, checkpoint$header, drop = FALSE]
  compact_added <- compact_result_rows(added)[, names(checkpoint$data), drop = FALSE]
  combined <- rbind(checkpoint$data, compact_added)
  attr(combined, "validated_sum_scores") <- TRUE
  keys <- paste(combined$repetition, combined$method, combined$stage, sep = "/")
  if (anyDuplicated(keys) || sum(combined$method == "random10") != state$success_count * 3L) stop("Backfill would introduce duplicate or missing baseline rows.")
  method_names <- unique(c(methods_to_include, setdiff(combined$method, "reference")))
  summary <- summarise_results(combined, method_names)
  events <- if (file.exists(paths["events"])) read.csv(paths["events"], stringsAsFactors = FALSE) else data.frame()
  event_rows <- if (nrow(events)) split(events, seq_len(nrow(events))) else list()
  failures <- summarize_method_failures(event_rows, c("reference", method_names), combined, state$attempt_count)
  for (field in c("attempted_reps", "method_failure_repetitions", "item_drop_repetitions")) {
    summary[[field]] <- failures[[field]][match(summary$method, failures$method)]
  }
  # All replacements live on the same filesystem. Copy the existing CSV verbatim
  # once, append only new rows, prepare reports, and publish results LAST. If report
  # publication is interrupted, another backfill can safely finish the transaction.
  staged <- c(results = tempfile(".random10-results-", tmpdir = output_dir, fileext = ".csv"),
    summary = tempfile(".random10-summary-", tmpdir = output_dir, fileext = ".csv"),
    workbook = tempfile(".random10-workbook-", tmpdir = output_dir, fileext = ".xlsx"))
  on.exit(unlink(staged), add = TRUE)
  if (!identical(before, signature())) stop("Checkpoint changed during backfill; no files were replaced.")
  if (!file.copy(paths["results"], staged["results"]) || file.info(staged["results"])$size != before$size[1]) stop("Unable to stage a complete results copy.")
  write.table(added, staged["results"], append = TRUE, sep = ",", quote = TRUE,
    row.names = FALSE, col.names = FALSE, na = "NA", qmethod = "double")
  write.csv(summary, staged["summary"], row.names = FALSE)
  write_summary_workbook(summary, staged["workbook"])
  if (!is.null(state$results_bytes)) {
    # Backfill extends the committed CSV without advancing any repetition counters.
    # Publish matching byte offsets so a later --resume keeps these baseline rows.
    staged <- c(staged, state = tempfile(".random10-state-", tmpdir = output_dir))
    state$results_bytes <- file.info(staged["results"])$size
    if (state$success_count %% 10L == 0L) state$summary_count <- state$success_count
    save_state_list(staged["state"], state)
  }
  if (!identical(before, signature())) stop("Checkpoint changed during backfill; no files were replaced.")
  suspendInterrupts({
    for (name in intersect(c("summary", "workbook", "results", "state"), names(staged))) {
      if (!file.rename(staged[name], paths[name])) stop(sprintf("Could not publish %s; rerun backfill to finish.", name))
    }
  })
  cat(sprintf("Added %d random10 rows. Reports refreshed; state counters unchanged. Backfill finished without starting another repetition.\n", missing))
  invisible(list(added_rows = missing, completed = state$success_count))
}

main <- function() {
  args <- parse_cli_args(commandArgs(trailingOnly = TRUE))
  if (args$backfill_random10 || args$verify_random10) {
    backfill_random10(args$output_dir, verify_only = args$verify_random10)
    return(invisible(NULL))
  }
  set.seed(args$seed)

  dir.create(args$output_dir, recursive = TRUE, showWarnings = FALSE)
  exclusions_and_failures_path <- file.path(args$output_dir, "monte_carlo_exclusions_and_failures.csv")
  results_path <- file.path(args$output_dir, "monte_carlo_results.csv")
  state_path <- file.path(args$output_dir, "monte_carlo_state.csv")

  item_meta <- read_item_meta(item_meta_path)
  extraversion_items <- item_meta$item_code[seq_len(60)]
  nuisance_items <- item_meta$item_code[61:64]
  reverse_coded_items <- item_meta$item_code[as.integer(item_meta$reverse_coded) == 1L]
  human_train <- load_human_matrix(human_train_path, item_meta)
  human_test <- load_human_matrix(human_test_path, item_meta)
  synth_full_blocks <- load_synthetic_blocks_if_present(synth_full_path)
  synth_full_v11_blocks <- load_synthetic_blocks_if_present(synth_full_v11_path)
  synth_full_v12_blocks <- load_synthetic_blocks_if_present(synth_full_v12_path)
  synth_full_v2_blocks <- load_synthetic_blocks_if_present(synth_full_v2_path)
  synth_full_v21_blocks <- load_synthetic_blocks_if_present(if (file.exists(synth_full_v21_path)) synth_full_v21_path else synth_full_v2_path)
  synth_full_v21_no_assoc_explan_blocks <- load_synthetic_blocks_if_present(synth_full_v21_no_assoc_explan_path)
  synth_full_v21_no_demogs_blocks <- load_synthetic_blocks_if_present(synth_full_v21_no_demogs_path)
  synth_full_v21_no_detail_variation_blocks <- load_synthetic_blocks_if_present(synth_full_v21_no_detail_variation_path)
  synth_full_v21_no_trait_blocks <- load_synthetic_blocks_if_present(synth_full_v21_no_trait_path)
  synth_full_v211_blocks <- load_synthetic_blocks_if_present(synth_full_v211_path)
  synth_full_v211_no_assoc_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_assoc_path)
  synth_full_v211_no_demogs_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_demogs_path)
  synth_full_v211_no_detail_variation_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_detail_variation_path)
  synth_full_v211_no_probabilities_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_probabilities_path)
  synth_full_v211_no_trait_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_trait_path)
  synth_full_v211_no_detail_variation_openai_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_detail_variation_openai_path)
  synth_full_v211_claude_blocks <- load_synthetic_blocks_if_present(synth_full_v211_claude_path)
  synth_full_v211_no_assoc_claude_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_assoc_claude_path)
  synth_full_v211_no_detail_variation_claude_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_detail_variation_claude_path)
  synth_full_v211_no_demogs_claude_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_demogs_claude_path)
  synth_full_v211_no_probabilities_claude_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_probabilities_claude_path)
  synth_full_v211_no_trait_claude_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_trait_claude_path)
  synth_full_v211_xiaomi_blocks <- load_synthetic_blocks_if_present(synth_full_v211_xiaomi_path)
  synth_full_v211_no_assoc_xiaomi_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_assoc_xiaomi_path)
  synth_full_v211_no_detail_variation_xiaomi_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_detail_variation_xiaomi_path)
  synth_full_v211_no_demogs_xiaomi_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_demogs_xiaomi_path)
  synth_full_v211_no_probabilities_xiaomi_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_probabilities_xiaomi_path)
  synth_full_v211_no_trait_xiaomi_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_trait_xiaomi_path)
  synth_full_v211_openai_blocks <- load_synthetic_blocks_if_present(synth_full_v211_openai_path)
  synth_full_v211_no_probabilities_openai_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_probabilities_openai_path)
  synth_full_v211_no_trait_openai_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_trait_openai_path)
  synth_full_v211_no_demogs_openai_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_demogs_openai_path)
  synth_full_v211_no_assoc_openai_blocks <- load_synthetic_blocks_if_present(synth_full_v211_no_assoc_openai_path)
  synth_single_answer_demogs_openai_blocks <- load_synthetic_blocks_if_present(synth_single_answer_demogs_openai_path)
  synth_single_answer_demogs_claude_blocks <- load_synthetic_blocks_if_present(synth_single_answer_demogs_claude_path)
  synth_single_answer_demogs_xiaomi_blocks <- load_synthetic_blocks_if_present(synth_single_answer_demogs_xiaomi_path)
  synth_single_answer_demogs_blocks <- load_synthetic_blocks_if_present(synth_single_answer_demogs_path)
  synth_full_v22_blocks <- load_synthetic_blocks_if_present(if (file.exists(synth_full_v22_path)) synth_full_v22_path else synth_full_v21_path)
  synth_full_v23_blocks <- load_synthetic_blocks_if_present(if (file.exists(synth_full_v23_path)) synth_full_v23_path else synth_full_v22_path)
  synth_no_construct_blocks <- if (file.exists(synth_no_construct_path)) {
    load_synthetic_blocks_if_present(synth_no_construct_path)
  } else {
    NULL
  }

  methods <- list(
    human300 = list(
      train_source = "human",
      train_n = 300L,
      eval_source = "human_test",
      blocks = NULL
    ),
    human100 = list(
      train_source = "human",
      train_n = 100L,
      eval_source = "human_test",
      blocks = NULL
    ),
    human1000 = list(
      train_source = "human",
      train_n = 1000L,
      eval_source = "human_test",
      blocks = NULL
    ),
    synth_item_responses_full = list(
      train_source = "synthetic",
      eval_source = "synthetic",
      blocks = synth_full_blocks
    ),
    synth_item_responses_fullV1.1 = list(
      train_source = "synthetic",
      eval_source = "synthetic",
      blocks = synth_full_v11_blocks
    ),
    synth_item_responses_fullV1.2 = list(
      train_source = "synthetic",
      eval_source = "synthetic",
      blocks = synth_full_v12_blocks
    ),
    synth_item_responses_fullV2 = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v2_blocks
    ),
    "synth_item_responses_fullV2.1" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v21_blocks
    ),
    "synth_item_responses_fullV2.1_500" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      sample_n = 500L,
      blocks = synth_full_v21_blocks
    ),
    "v2.1.1" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_blocks
    ),
    "v2.1.1_500" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      sample_n = 500L,
      blocks = synth_full_v211_blocks
    ),
    "v2.1.1_no_trait" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_trait_blocks
    ),
    "v2.1.1_no_probabilities" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_probabilities_blocks
    ),
    "v2.1.1_no_detail_variation" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_detail_variation_blocks
    ),
    openai_gpt_5_6_luna_floor = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_detail_variation_openai_blocks
    ),
    "openai_v2.1.1" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_openai_blocks
    ),
    "openai_v2.1.1_no_probabilities" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_probabilities_openai_blocks
    ),
    "openai_v2.1.1_no_trait" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_trait_openai_blocks
    ),
    "openai_v2.1.1_no_demogs" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_demogs_openai_blocks
    ),
    "openai_v2.1.1_no_assoc" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_assoc_openai_blocks
    ),
    "openai_v2.1.1_no_detail_variation" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_detail_variation_openai_blocks
    ),
    "openai_single_answer_demogs" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_single_answer_demogs_openai_blocks
    ),
    openai_full = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_openai_blocks),
    openai_no_assoc = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_assoc_openai_blocks),
    openai_no_demogs = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_demogs_openai_blocks),
    openai_no_detail_variation = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_detail_variation_openai_blocks),
    openai_no_probabilities = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_probabilities_openai_blocks),
    openai_no_trait = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_trait_openai_blocks),
    claude_full = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_claude_blocks),
    claude_no_assoc = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_assoc_claude_blocks),
    claude_no_detail_variation = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_detail_variation_claude_blocks),
    claude_no_demogs = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_demogs_claude_blocks),
    claude_no_probabilities = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_probabilities_claude_blocks),
    claude_no_trait = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_trait_claude_blocks),
    xiaomi_full = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_xiaomi_blocks),
    xiaomi_no_assoc = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_assoc_xiaomi_blocks),
    xiaomi_no_detail_variation = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_detail_variation_xiaomi_blocks),
    xiaomi_no_demogs = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_demogs_xiaomi_blocks),
    xiaomi_no_probabilities = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_probabilities_xiaomi_blocks),
    xiaomi_no_trait = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_full_v211_no_trait_xiaomi_blocks),
    single_answer_demogs = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_single_answer_demogs_blocks),
    claude_single_answer_demogs = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_single_answer_demogs_claude_blocks),
    xiaomi_single_answer_demogs = list(train_source = "synthetic_prob", eval_source = "synthetic_prob", blocks = synth_single_answer_demogs_xiaomi_blocks),
    "v2.1.1_no_demogs" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_demogs_blocks
    ),
    "v2.1.1_no_assoc" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v211_no_assoc_blocks
    ),
    "synth_item_responses_2.1_no_assoc_explan" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v21_no_assoc_explan_blocks
    ),
    "synth_item_responses_2.1_no_demogs" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v21_no_demogs_blocks
    ),
    "synth_item_responses_2.1_no_detail_variation" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v21_no_detail_variation_blocks
    ),
    "synth_item_responses_2.1_no_trait" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v21_no_trait_blocks
    ),
    "synth_item_responses_single_answer_demogs" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_single_answer_demogs_blocks
    ),
    "synth_item_responses_fullV2.2" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v22_blocks
    ),
    "synth_item_responses_fullV2.3" = list(
      train_source = "synthetic_prob",
      eval_source = "synthetic_prob",
      blocks = synth_full_v23_blocks
    ),
    synth_item_responses_no_construct_definition = list(
      train_source = "synthetic",
      eval_source = "synthetic",
      blocks = synth_no_construct_blocks
    ),
    random10 = list(train_source = "random10", blocks = NULL)
  )
  missing_methods <- setdiff(methods_to_include, names(methods))
  if (length(missing_methods)) {
    stop(sprintf(
      "Unknown method(s) in methods_to_include: %s",
      paste(missing_methods, collapse = ", ")
    ))
  }
  methods <- methods[methods_to_include]
  methods_missing_data <- names(methods)[vapply(methods, function(method) {
    !method$train_source %in% c("human", "random10") && is.null(method$blocks)
  }, logical(1))]
  if (length(methods_missing_data)) {
    stop(sprintf(
      "Missing synthetic response data for configured method(s): %s. Check the expected CSV files under %s.",
      paste(methods_missing_data, collapse = ", "),
      llm_responses_dir
    ))
  }

  run <- prepare_output_run(args$output_dir, args$resume, args$seed, args$reps, args$additional_reps)
  checkpoint_state <- run$state
  results <- run$results
  result_header <- run$header
  method_failure_rows <- run$events
  success_count <- checkpoint_state$success_count
  attempt_count <- checkpoint_state$attempt_count
  target_reps <- checkpoint_state$target_reps
  failure_count <- 0L
  active_method <- "human_reference"
  checkpoint_state <- generate_scheduled_reports(results, method_failure_rows,
    c("reference", names(methods)), args$output_dir, checkpoint_state)

  while (success_count < target_reps) {
    event_start <- length(method_failure_rows)
    attempt_count <- attempt_count + 1L
    attempt_seed <- args$seed + attempt_count - 1L
    set.seed(attempt_seed)

    train_ext_items <- sort(sample(extraversion_items, 20L, replace = FALSE))
    heldout_ext_items <- setdiff(extraversion_items, train_ext_items)
    candidate_items <- c(train_ext_items, nuisance_items)

    cat(sprintf(
      "Repetition %d (counted %d/%d): train=%s\n",
      attempt_count, success_count, target_reps, paste(train_ext_items, collapse = ",")
    ))

    attempt_result <- tryCatch({
      active_method <- "human_reference"
      attempt_rows <- list()

      reference_calibration <- prepare_calibration_data(human_train, candidate_items)
      method_failure_rows <- c(method_failure_rows, make_item_exclusion_events(
        reference_calibration$exclusions, "reference", success_count + 1L, attempt_count, attempt_seed
      ))
      if (!reference_calibration$enough_items) {
        stop(sprintf("Reference calibration has fewer than 10 eligible items after exclusions: %s",
          paste(reference_calibration$items, collapse = ",")))
      }
      reference_candidate_items <- reference_calibration$items
      reference_candidate_fit <- reference_calibration$fit_mat
      reference_candidate_maps <- build_category_collapse_maps(reference_candidate_fit)
      reference_candidate_fit <- collapse_response_matrix(reference_candidate_fit, reference_candidate_maps)
      reference_candidate_model <- fit_graded_model(reference_candidate_fit, item_names = reference_candidate_items)
      print_graded_item_params(
        label = sprintf("repetition %d stage 1 reference", attempt_count),
        fit = reference_candidate_model,
        item_names = reference_candidate_items
      )
      print_boundary_mapping_diagnostics(
        label = sprintf("repetition %d stage 1 reference", attempt_count),
        item_names = reference_candidate_items,
        collapse_maps = reference_candidate_maps
      )
      reference_stage1_selected <- assemble_greedy_maximin_ata(reference_candidate_model, n_select = 10L)$selected_items
      reference_stage1_nuisance <- intersect(reference_stage1_selected, nuisance_items)
      cat(sprintf(
        "Stage 1 reference nuisance selection: %d [%s]\n",
        length(reference_stage1_nuisance),
        if (length(reference_stage1_nuisance)) paste(reference_stage1_nuisance, collapse = ",") else "none"
      ))
      attempt_rows[[length(attempt_rows) + 1L]] <- build_nuisance_screening_row(
        repetition = success_count + 1L,
        stage_method = "reference",
        fit_role = "reference",
        fit_n = nrow(reference_candidate_fit),
        fit_items = length(reference_candidate_items),
        candidate_items = reference_candidate_items,
        selected_items = reference_stage1_selected,
        nuisance_items = nuisance_items
      )

      attempt_rows[[length(attempt_rows) + 1L]] <- build_candidate_selection_row(
        repetition = success_count + 1L,
        stage_method = "reference",
        fit_role = "reference",
        fit_n = nrow(reference_candidate_fit),
        fit_items = length(reference_candidate_items),
        candidate_items = reference_candidate_items,
        selected_items = reference_stage1_selected,
        reference_selected_items = reference_stage1_selected,
        a_abs_diff_median = 0,
        overlap_items = reference_stage1_selected,
        overlap_n = length(reference_stage1_selected),
        overlap_jaccard = 1,
        overlap_precision = 1,
        overlap_recall = 1
      )

      reference_eval_metrics <- score_sum_scores(
        human_test[, reference_stage1_selected, drop = FALSE],
        human_test[, heldout_ext_items, drop = FALSE]
      )
      attempt_rows[[length(attempt_rows) + 1L]] <- build_short_form_row(
        repetition = success_count + 1L, stage_method = "reference", fit_role = "reference",
        fit_n = nrow(reference_candidate_fit), fit_items = length(reference_candidate_items),
        candidate_items = reference_candidate_items, selected_items = reference_stage1_selected,
        eval_n = reference_eval_metrics$n_eval, eval_metrics = reference_eval_metrics,
        train_items = train_ext_items, heldout_items = heldout_ext_items
      )

      for (method_name in names(methods)) {
        active_method <- method_name
        method_row_start <- length(attempt_rows)
        method <- methods[[method_name]]
        candidate_method_items <- candidate_items
        method_result <- tryCatch({
        if (identical(method$train_source, "random10")) {
          attempt_rows <- c(attempt_rows, build_random10_rows(
            repetition = success_count + 1L, attempt = attempt_count, seed = attempt_seed,
            candidate_items = candidate_items, reference_selected = reference_stage1_selected,
            train_items = train_ext_items, heldout_items = heldout_ext_items,
            nuisance_items = nuisance_items, human_test = human_test
          ))
        } else {
        # Method-specific deterministic sub-seeds keep each method's sampling
        # stable within this repetition's seed stream.
        method_seed <- attempt_seed + match(method_name, names(methods)) * 10000L
        set.seed(method_seed)

        if (identical(method$train_source, "human")) {
          train_rows <- sample(seq_len(nrow(human_train)), method$train_n, replace = FALSE)
          train_mat_full <- human_train[train_rows, , drop = FALSE]
          eval_mat_full <- human_test
        } else if (identical(method$train_source, "synthetic_prob")) {
          if (is.null(method$blocks)) {
            stop(sprintf("Missing synthetic blocks for method %s.", method_name))
          }
          train_mat_full <- sample_synthetic_matrix_from_prob_blocks(method$blocks, item_meta)
          eval_mat_full <- human_test
        } else {
          if (is.null(method$blocks)) {
            stop(sprintf("Missing synthetic blocks for method %s.", method_name))
          }
          train_mat_full <- sample_synthetic_matrix_from_dist_blocks(method$blocks, item_meta)
          eval_mat_full <- human_test
        }

        if (!is.null(method$sample_n)) {
          sample_rows <- sample(seq_len(nrow(train_mat_full)), method$sample_n, replace = FALSE)
          train_mat_full <- train_mat_full[sample_rows, , drop = FALSE]
        }

        calibration <- prepare_calibration_data(train_mat_full, candidate_items)
        candidate_method_items <- calibration$items
        method_failure_rows <- c(method_failure_rows, make_item_exclusion_events(
          calibration$exclusions, method_name, success_count + 1L, attempt_count, attempt_seed
        ))
        if (length(calibration$exclusions$item)) {
          cat(sprintf("Repetition %d %s: excluding candidate item(s) with fewer than 2 observed categories: %s\n",
            attempt_count, method_name, paste(calibration$exclusions$item, collapse = ",")))
        }
        if (!calibration$enough_items) {
          stop(sprintf("Fewer than 10 eligible candidate items remain after exclusions: %s",
            paste(candidate_method_items, collapse = ",")))
        }
        train_candidate_fit <- calibration$fit_mat
        train_candidate_maps <- build_category_collapse_maps(train_candidate_fit)
        train_candidate_fit <- collapse_response_matrix(train_candidate_fit, train_candidate_maps)
        method_candidate_fit <- fit_graded_model(train_candidate_fit, item_names = candidate_method_items)
        print_graded_item_params(
          label = sprintf("repetition %d stage 1 method %s", attempt_count, method_name),
          fit = method_candidate_fit,
          item_names = candidate_method_items
        )
        print_boundary_mapping_diagnostics(
          label = sprintf("repetition %d stage 1 method %s", attempt_count, method_name),
          item_names = candidate_method_items,
          collapse_maps = train_candidate_maps
        )
        selected_stage1 <- assemble_greedy_maximin_ata(method_candidate_fit, n_select = 10L)$selected_items
        nuisance_stage1 <- intersect(selected_stage1, nuisance_items)
        cat(sprintf(
          "Stage 1 %s nuisance selection: %d [%s]\n",
          method_name,
          length(nuisance_stage1),
          if (length(nuisance_stage1)) paste(nuisance_stage1, collapse = ",") else "none"
        ))
        attempt_rows[[length(attempt_rows) + 1L]] <- build_nuisance_screening_row(
          repetition = success_count + 1L,
          stage_method = method_name,
          fit_role = "method",
          fit_n = nrow(train_candidate_fit),
          fit_items = length(candidate_method_items),
          candidate_items = candidate_method_items,
          selected_items = selected_stage1,
          nuisance_items = nuisance_items
        )

        overlap_items <- intersect(selected_stage1, reference_stage1_selected)
        overlap_metrics <- compute_true_short_form_overlap(selected_stage1, reference_stage1_selected)
        common_parameter_items <- intersect(reference_candidate_items, candidate_method_items)
        parameter_metrics <- compare_graded_parameters(
          reference_candidate_model,
          method_candidate_fit,
          common_parameter_items,
          reference_candidate_maps[common_parameter_items],
          train_candidate_maps[common_parameter_items],
          reverse_coded_items = reverse_coded_items
        )
        cat(sprintf(
          "Stage 1 %s ATA selection: %s | overlap=%d | a=%d/%d | a_nonfinite=%d\n",
          method_name,
          paste(selected_stage1, collapse = ","),
          overlap_metrics$true_short_form_overlap_n,
          parameter_metrics$a_abs_diff_n,
          parameter_metrics$a_expected_n,
          parameter_metrics$a_nonfinite_n
        ))
        attempt_rows[[length(attempt_rows) + 1L]] <- build_candidate_selection_row(
          repetition = success_count + 1L,
          stage_method = method_name,
          fit_role = "method",
          fit_n = nrow(train_candidate_fit),
          fit_items = length(candidate_method_items),
          candidate_items = candidate_method_items,
          selected_items = selected_stage1,
          reference_selected_items = reference_stage1_selected,
          compared_parameters = parameter_metrics$compared_parameters,
          a_expected_n = parameter_metrics$a_expected_n,
          a_nonfinite_n = parameter_metrics$a_nonfinite_n,
          a_nonfinite_items = parameter_metrics$a_nonfinite_items,
          a_abs_diff_median = parameter_metrics$a_abs_diff_median,
          a_abs_diff_n = parameter_metrics$a_abs_diff_n,
          a_abs_diff_revervse_median = parameter_metrics$a_abs_diff_revervse_median,
          a_abs_diff_revervse_n = parameter_metrics$a_abs_diff_revervse_n,
          a_abs_diff_positive_median = parameter_metrics$a_abs_diff_positive_median,
          a_abs_diff_positive_n = parameter_metrics$a_abs_diff_positive_n,
          a_parameter_r = parameter_metrics$a_parameter_r,
          a_parameter_r_n = parameter_metrics$a_parameter_r_n,
          b_metrics = list(
            b1_abs_diff_median = parameter_metrics$b1_abs_diff_median,
            b1_abs_diff_n = parameter_metrics$b1_abs_diff_n,
            b1_parameter_r = parameter_metrics$b1_parameter_r,
            b1_parameter_r_n = parameter_metrics$b1_parameter_r_n,
            b2_abs_diff_median = parameter_metrics$b2_abs_diff_median,
            b2_abs_diff_n = parameter_metrics$b2_abs_diff_n,
            b2_parameter_r = parameter_metrics$b2_parameter_r,
            b2_parameter_r_n = parameter_metrics$b2_parameter_r_n,
            b3_abs_diff_median = parameter_metrics$b3_abs_diff_median,
            b3_abs_diff_n = parameter_metrics$b3_abs_diff_n,
            b3_parameter_r = parameter_metrics$b3_parameter_r,
            b3_parameter_r_n = parameter_metrics$b3_parameter_r_n,
            b4_abs_diff_median = parameter_metrics$b4_abs_diff_median,
            b4_abs_diff_n = parameter_metrics$b4_abs_diff_n,
            b4_parameter_r = parameter_metrics$b4_parameter_r,
            b4_parameter_r_n = parameter_metrics$b4_parameter_r_n
          ),
          overlap_items = overlap_items,
          overlap_n = overlap_metrics$true_short_form_overlap_n,
          overlap_jaccard = overlap_metrics$true_short_form_overlap_jaccard,
          overlap_precision = overlap_metrics$true_short_form_precision,
          overlap_recall = overlap_metrics$true_short_form_recall
        )

        eval_metrics <- score_sum_scores(
          eval_mat_full[, selected_stage1, drop = FALSE],
          eval_mat_full[, heldout_ext_items, drop = FALSE]
        )
        attempt_rows[[length(attempt_rows) + 1L]] <- build_short_form_row(
          repetition = success_count + 1L, stage_method = method_name, fit_role = "method",
          fit_n = nrow(train_candidate_fit), fit_items = length(candidate_method_items),
          candidate_items = candidate_method_items, selected_items = selected_stage1,
          eval_n = eval_metrics$n_eval, eval_metrics = eval_metrics,
          train_items = train_ext_items, heldout_items = heldout_ext_items
        )
        }
        TRUE
        }, error = function(e) e)

        if (inherits(method_result, "error")) {
          if (method_row_start == 0L) attempt_rows <- list() else attempt_rows <- attempt_rows[seq_len(method_row_start)]
          # Preserve item-drop audit rows and add the failure, without counting
          # a repetition more than once for this method.
          failure_count <- failure_count + 1L
          err_call <- conditionCall(method_result)
          method_failure_rows[[length(method_failure_rows) + 1L]] <- make_method_failure_event(
            method = method_name,
            repetition = success_count + 1L,
            attempt = attempt_count,
            seed = attempt_seed,
            items = candidate_method_items,
            reason = conditionMessage(method_result)
          )
          cat(sprintf("Repetition %d method %s failed; continuing to the next method: %s%s\n",
            attempt_count, method_name, conditionMessage(method_result),
            if (is.null(err_call)) "" else paste0(" | call: ", paste(deparse(err_call), collapse = " "))))
        }
      }

      attempt_rows
    }, error = function(e) e)

    if (inherits(attempt_result, "error")) {
      failure_count <- failure_count + 1L
      error_call <- conditionCall(attempt_result)
      if (!is.null(error_call)) {
        cat(sprintf(
          "Repetition %d failed in method %s and counts toward the requested total; moving to the next repetition: %s | call: %s\n",
          attempt_count,
          active_method,
          conditionMessage(attempt_result),
          deparse(error_call)
        ))
      } else {
        cat(sprintf(
          "Repetition %d failed in method %s and counts toward the requested total; moving to the next repetition: %s\n",
          attempt_count,
          active_method,
          conditionMessage(attempt_result)
        ))
      }
      method_failure_rows[[length(method_failure_rows) + 1L]] <- make_method_failure_event(
        method = active_method,
        repetition = success_count + 1L,
        attempt = attempt_count,
        seed = attempt_seed,
        items = if (exists("candidate_items", inherits = FALSE)) candidate_items else character(),
        reason = conditionMessage(attempt_result)
      )
      # Preserve the existing attempted-repetition accounting, including a
      # reference failure that produces log events but no complete result rows.
      attempt_result <- list()
    }

    attempt_result <- lapply(attempt_result, function(row) {
      row$attempt <- attempt_count
      row$seed <- attempt_seed
      row
    })
    new_events <- if (length(method_failure_rows) > event_start) method_failure_rows[seq.int(event_start + 1L, length(method_failure_rows))] else list()
    saved <- save_repetition_checkpoint(attempt_result, new_events, args$output_dir, checkpoint_state, result_header)
    checkpoint_state <- saved$state
    success_count <- checkpoint_state$success_count
    results <- rbind(results, saved$compact)
    attr(results, "validated_sum_scores") <- TRUE
    # Do not retain historical participant score strings in RAM.
    rm(attempt_result, attempt_rows, saved)
    checkpoint_state <- generate_scheduled_reports(results, method_failure_rows,
      c("reference", names(methods)), args$output_dir, checkpoint_state)
  }

  cat(sprintf("Repetitions counted toward target: %d\n", success_count))
  cat(sprintf("Repetitions started: %d\n", attempt_count))
  cat(sprintf("Fit or attempt errors during this run: %d\n", failure_count))
  cat(sprintf("Recorded exclusion/failure events: %d\n", length(method_failure_rows)))
  cat(sprintf("Wrote detailed results to %s\n", results_path))
  cat(sprintf("Scheduled reports last saved at repetition %d (refreshed only at multiples of 10).\n", checkpoint_state$summary_count))
  cat(sprintf("Wrote resume state to %s\n", state_path))
  cat(sprintf("Wrote exclusions and failure details to %s\n", exclusions_and_failures_path))
}

if (sys.nframe() == 0L) {
  main()
}
