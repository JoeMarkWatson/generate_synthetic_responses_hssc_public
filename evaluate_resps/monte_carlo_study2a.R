#!/usr/bin/env Rscript

# Study 2a: four non-Extraversion scales, using the Study 1 24-item calibration
# and raw-sum validity procedure. Per-scale CSV checkpoints append by repetition.

suppressPackageStartupMessages({
  if (!requireNamespace("mirt", quietly = TRUE)) stop("The mirt package is required.")
})

script_dir <- normalizePath(dirname(sub("^--file=", "", grep(
  "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[1])), winslash = "/", mustWork = TRUE)
repo_root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
source(file.path(script_dir, "ATA.R"))
helpers <- new.env(parent = globalenv())
sys.source(file.path(script_dir, "monte_carlo_study1.R"), envir = helpers)

scales <- c("Openness", "Neuroticism", "Agreeableness", "Conscientiousness")
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(key, default = NULL) {
  eq <- grep(paste0("^", key, "="), args, value = TRUE)
  if (length(eq)) return(sub(paste0("^", key, "="), "", eq[[1]]))
  idx <- match(key, args)
  if (!is.na(idx) && idx < length(args)) return(args[[idx + 1L]])
  default
}
reps <- suppressWarnings(as.integer(arg_value("--reps", "20")))
seed <- suppressWarnings(as.integer(arg_value("--seed", "1")))
output_root <- arg_value("--output-dir", file.path(script_dir, "monte_carlo_study2a_output"))
resume <- "--resume" %in% args
scale_arg <- arg_value("--scale", paste(scales, collapse = ","))
scales <- unique(trimws(unlist(strsplit(scale_arg, ",", fixed = TRUE), use.names = FALSE)))
if (length(reps) != 1L || is.na(reps) || reps < 1L) stop("--reps must be positive.")
if (length(seed) != 1L || is.na(seed) || seed != 1L) stop("The repetition seed is fixed at 1, as in Study 1.")
if (any(!scales %in% c("Openness", "Neuroticism", "Agreeableness", "Conscientiousness"))) stop("Unsupported scale.")

atomic_write_csv <- function(x, path) {
  tmp <- tempfile(".stage-", tmpdir = dirname(path), fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  write.csv(x, tmp, row.names = FALSE, na = "")
  if (!file.rename(tmp, path)) stop("Could not publish checkpoint state.")
}

final_reports_pending <- function(completed, target, summary_count) {
  isTRUE(completed == target && completed > summary_count)
}

write_combined_summary <- function() {
  paths <- file.path(output_root, c("Openness", "Neuroticism", "Agreeableness", "Conscientiousness"), "monte_carlo_summary.csv")
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(invisible(NULL))
  tables <- lapply(paths, read.csv, stringsAsFactors = FALSE, check.names = FALSE)
  columns <- unique(unlist(lapply(tables, names), use.names = FALSE))
  tables <- lapply(tables, function(x) {
    for (nm in setdiff(columns, names(x))) x[[nm]] <- NA
    x[, columns, drop = FALSE]
  })
  atomic_write_csv(do.call(rbind, tables), file.path(output_root, "cross_scale_summary.csv"))
}

run_scale <- function(scale) {
  cat(sprintf("Starting %s (%d repetitions)\n", scale, reps)); flush.console()
  scale_lower <- tolower(scale)
  scale_dir <- file.path(repo_root, "scales_info", paste0(scale, "_info"))
  meta <- read.csv(file.path(scale_dir, "scale_items.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(meta) != 64L) stop(sprintf("%s metadata must have 64 rows.", scale))
  meta$response_col <- meta$item_code
  target_items <- meta$item_code[seq_len(60L)]
  nuisance <- meta$item_code[61:64]
  reverse <- meta$item_code[as.integer(meta$reverse_coded) == 1L]
  data_dir <- file.path(repo_root, "data", scale_lower)
  train <- helpers$load_human_matrix(file.path(data_dir, "human_responses", "human_train_responses.csv"), meta)
  test <- helpers$load_human_matrix(file.path(data_dir, "human_responses", "human_test_responses.csv"), meta)
  llm_dir <- file.path(data_dir, "llm_responses")
  synth_paths <- c(
    openai_no_detail_variation = file.path(llm_dir, "synth_item_responses_fullV2.1.1_no_detail_variation__openai_gpt_5_6_luna_floor.csv"),
    xiaomi_no_detail_variation = file.path(llm_dir, "synth_item_responses_fullV2.1.1_no_detail_variation__xiaomi_mimo_v2_6_flash.csv")
  )
  missing <- synth_paths[!file.exists(synth_paths)]
  if (length(missing)) stop(sprintf("Missing %s synthetic input(s): %s", scale, paste(missing, collapse = ", ")))
  blocks <- lapply(synth_paths, helpers$load_synthetic_blocks)
  methods <- c("human100", "human300", "human1000", names(blocks), "random10")
  helpers$methods_to_include <- methods

  out_dir <- file.path(output_root, scale); dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  detail_path <- file.path(out_dir, "monte_carlo_results.csv")
  events_path <- file.path(out_dir, "monte_carlo_exclusions_and_failures.csv")
  state_path <- file.path(out_dir, "monte_carlo_state.csv")
  summary_path <- file.path(out_dir, "monte_carlo_summary.csv")
  workbook_path <- file.path(out_dir, "monte_carlo_comparisons.xlsx")
  result_header <- c("repetition", "attempt", "seed", "stage", "method", "scoring_method", "candidate_items", "selected_items", "nuisance_selected_n", "overlap_n", "a_abs_diff_median", paste0("b", 1:4, "_abs_diff_median"), "pearson_r", "spearman_r", "eval_n", "eval_short_sum", "eval_target_sum", "train_items", "heldout_items")
  event_header <- c("record_type", "repetition", "attempt", "seed", "method", "items", "reason")

  has_state <- file.exists(state_path)
  if (!has_state && any(file.exists(c(detail_path, events_path)))) stop("Output files exist without a committed state; refusing to overwrite them.")
  if (!resume && has_state) stop(sprintf("Output exists for %s; use --resume.", scale))
  state <- if (has_state) read.csv(state_path, stringsAsFactors = FALSE) else data.frame(completed = 0L, target = reps, seed = seed, summary_count = 0L)
  required_state <- c("completed", "target", "seed", "summary_count")
  if (nrow(state) != 1L || !all(required_state %in% names(state)) ||
      any(!is.finite(as.numeric(state[1, required_state]))) ||
      any(as.numeric(state[1, required_state]) != floor(as.numeric(state[1, required_state]))) ||
      state$seed != seed || state$completed < 0 || state$target < state$completed ||
      state$summary_count < 0 || state$summary_count > state$completed) {
    stop(sprintf("Invalid resume state for %s.", scale))
  }
  if (resume && state$target < reps) state$target <- reps
  if (!has_state) {
    if (file.exists(detail_path) || file.exists(events_path)) stop(sprintf("Output exists for %s; use --resume.", scale))
    writeLines(paste(result_header, collapse = ","), detail_path)
    writeLines(paste(event_header, collapse = ","), events_path)
    state$completed <- 0L
  } else {
    if (!file.exists(detail_path) || !file.exists(events_path)) stop(sprintf("Missing checkpoint files for %s.", scale))
    # Byte offsets permit recovery even when the last appended CSV row is partial.
    # Older Study 2a states need a one-time scan to locate their committed prefix.
    if (!all(c("results_bytes", "events_bytes") %in% names(state))) {
      state$results_bytes <- helpers$legacy_committed_bytes(detail_path, state$completed)
      state$events_bytes <- helpers$legacy_committed_bytes(events_path, state$completed)
    }
    helpers$recover_checkpoint_tails(c(results = detail_path, events = events_path), state)
    if (!identical(names(read.csv(detail_path, nrows = 0L)), result_header) ||
        !identical(names(read.csv(events_path, nrows = 0L)), event_header)) stop("Unexpected checkpoint CSV schema.")
  }
  state$results_bytes <- file.info(detail_path)$size
  state$events_bytes <- file.info(events_path)$size
  atomic_write_csv(state, state_path)
  if (state$completed > reps) reps <- state$completed

  read_detail <- function() read.csv(detail_path, stringsAsFactors = FALSE, check.names = FALSE)
  write_reports <- function(completed) {
    current <- read_detail()
    summary <- helpers$summarise_results(current, methods)
    events <- read.csv(events_path, stringsAsFactors = FALSE, check.names = FALSE)
    failures <- helpers$summarize_method_failures(
      if (nrow(events)) split(events, seq_len(nrow(events))) else list(),
      c("reference", methods), current, completed
    )
    for (field in c("attempted_reps", "method_failure_repetitions", "item_drop_repetitions")) {
      summary[[field]] <- failures[[field]][match(summary$method, failures$method)]
    }
    summary$scale <- scale
    if (!requireNamespace("openxlsx", quietly = TRUE)) stop("The openxlsx package is required for comparison workbooks.")
    tmp_csv <- tempfile(".summary-", tmpdir = out_dir, fileext = ".csv")
    tmp_xlsx <- tempfile(".workbook-", tmpdir = out_dir, fileext = ".xlsx")
    on.exit(unlink(c(tmp_csv, tmp_xlsx)), add = TRUE)
    write.csv(summary, tmp_csv, row.names = FALSE, na = "")
    helpers$write_summary_workbook(summary, tmp_xlsx)
    suspendInterrupts({
      if (!file.rename(tmp_csv, summary_path) || !file.rename(tmp_xlsx, workbook_path)) stop("Could not publish reports; --resume will retry.")
      state$summary_count <<- completed
      atomic_write_csv(state, state_path)
    })
    cat(sprintf("[%s] refreshed summary and workbook at repetition %d\n", scale, completed)); flush.console()
  }
  # If report publication was interrupted exactly at the final repetition,
  # finish that publication on resume. A larger requested target does not
  # trigger reports for an earlier checkpoint.
  if (final_reports_pending(state$completed, state$target, state$summary_count)) {
    write_reports(state$completed)
  }
  if (state$completed < state$target) for (rep in seq.int(state$completed + 1L, state$target)) {
    set.seed(seed + rep - 1L)
    rep_events <- list(); rep_rows <- list()
    add_event <- function(type, method, item, reason) rep_events[[length(rep_events) + 1L]] <<- data.frame(
      record_type = type, repetition = rep, attempt = rep, seed = seed + rep - 1L,
      method = method, items = item, reason = gsub("[\r\n]+", " ", reason), stringsAsFactors = FALSE
    )
    train_items <- sort(sample(target_items, 20L, replace = FALSE))
    heldout <- setdiff(target_items, train_items)
    candidates <- c(train_items, nuisance)
    method_sources <- c("human100", "human300", "human1000", names(blocks))
    # Shared full-training reference, one calibration fit from the same candidates.
    process_method <- function(method, dat) {
      calibration <- helpers$prepare_calibration_data(dat, candidates)
      if (nrow(calibration$exclusions)) for (i in seq_len(nrow(calibration$exclusions))) {
        add_event("item_exclusion", method, calibration$exclusions$item[i], calibration$exclusions$reason[i])
      }
      if (!calibration$enough_items) stop("Fewer than 10 eligible candidates remain after exclusions.")
      maps <- helpers$build_category_collapse_maps(calibration$fit_mat)
      collapsed <- helpers$collapse_response_matrix(calibration$fit_mat, maps)
      fit <- helpers$fit_graded_model(collapsed, calibration$items)
      selected <- assemble_greedy_maximin_ata(fit, n_select = 10L)$selected_items
      list(calibration = calibration, maps = maps, fit = fit, selected = selected)
    }
    ref <- tryCatch({
      value <- process_method("reference", train)
      helpers$score_sum_scores(test[, value$selected, drop = FALSE], test[, heldout, drop = FALSE])
      value
    }, error = function(e) e)
    if (inherits(ref, "error")) {
      add_event("method_failure", "reference", paste(candidates, collapse = ";"), conditionMessage(ref))
    } else {
      make_rows <- function(method, selection, parameter_metrics = NULL) {
        selected <- selection$selected
        ev <- tryCatch(helpers$score_sum_scores(test[, selected, drop = FALSE], test[, heldout, drop = FALSE]), error = function(e) e)
        if (inherits(ev, "error")) stop(conditionMessage(ev))
        p <- if (method == "reference") base::rep(0, 5L) else if (is.null(parameter_metrics)) base::rep(NA_real_, 5L) else c(
          parameter_metrics$a_abs_diff_median,
          unlist(lapply(1:4, function(k) parameter_metrics[[paste0("b", k, "_abs_diff_median")]]))
        )
        base_row <- data.frame(
          repetition = rep, attempt = rep, seed = seed + rep - 1L,
          stage = "candidate_selection", method = method, scoring_method = NA_character_,
          candidate_items = paste(selection$calibration$items, collapse = ";"),
          selected_items = paste(selected, collapse = ";"),
          nuisance_selected_n = NA_integer_,
          overlap_n = if (method == "reference") 10L else length(intersect(selected, ref$selected)),
          a_abs_diff_median = p[1], b1_abs_diff_median = p[2],
          b2_abs_diff_median = p[3], b3_abs_diff_median = p[4], b4_abs_diff_median = p[5],
          pearson_r = NA_real_, spearman_r = NA_real_, eval_n = NA_integer_,
          eval_short_sum = NA_character_, eval_target_sum = NA_character_,
          train_items = paste(train_items, collapse = ";"),
          heldout_items = paste(heldout, collapse = ";"), stringsAsFactors = FALSE
        )
        nuisance_row <- base_row
        nuisance_row$stage <- "nuisance_screening"
        nuisance_row$nuisance_selected_n <- length(intersect(selected, nuisance))
        nuisance_row$overlap_n <- NA_integer_
        nuisance_row$a_abs_diff_median <- nuisance_row$b1_abs_diff_median <- NA_real_
        nuisance_row$b2_abs_diff_median <- nuisance_row$b3_abs_diff_median <- NA_real_
        nuisance_row$b4_abs_diff_median <- NA_real_
        validity_row <- base_row
        validity_row$stage <- "short_form_evaluation"
        validity_row$scoring_method <- "SUM_SCORE"
        validity_row$nuisance_selected_n <- NA_integer_
        validity_row$overlap_n <- NA_integer_
        validity_row$a_abs_diff_median <- validity_row$b1_abs_diff_median <- NA_real_
        validity_row$b2_abs_diff_median <- validity_row$b3_abs_diff_median <- NA_real_
        validity_row$b4_abs_diff_median <- NA_real_
        validity_row$pearson_r <- ev$pearson_r
        validity_row$spearman_r <- ev$spearman_r
        validity_row$eval_n <- ev$n_eval
        validity_row$eval_short_sum <- paste(sprintf("%.17g", ev$short_sum_values), collapse = ";")
        validity_row$eval_target_sum <- paste(sprintf("%.17g", ev$target_values), collapse = ";")
        rbind(nuisance_row, base_row, validity_row)
      }
      ref_rows <- make_rows("reference", ref)
      rep_rows[[length(rep_rows)+1L]] <- ref_rows
      for (method in method_sources) {
        # Independent method sub-seed: sample/fit methods cannot perturb later ones.
        method_seed <- seed + rep - 1L + match(method, methods) * 10000L
        set.seed(method_seed)
        result <- tryCatch({
          method_data <- if (method == "human100") {
            train[sample(seq_len(nrow(train)), 100L), , drop = FALSE]
          } else if (method == "human300") {
            train[sample(seq_len(nrow(train)), 300L), , drop = FALSE]
          } else if (method == "human1000") {
            train[sample(seq_len(nrow(train)), 1000L), , drop = FALSE]
          } else {
            helpers$sample_synthetic_matrix_from_prob_blocks(blocks[[method]], meta)
          }
          result <- process_method(method, method_data)
          common_items <- intersect(ref$calibration$items, result$calibration$items)
          parameters <- helpers$compare_graded_parameters(
            ref$fit, result$fit, common_items, ref$maps[common_items],
            result$maps[common_items], reverse_coded_items = reverse
          )
          make_rows(method, result, parameters)
        }, error=function(e)e)
        if (inherits(result,"error")) { add_event("method_failure",method,paste(candidates,collapse=";"),conditionMessage(result)); next }
        rep_rows[[length(rep_rows)+1L]] <- result
      }
      # Baseline seed is isolated and does not alter the main method RNG stream.
      random_selected <- helpers$random10_selection(candidates, seed + rep - 1L)
      random_obj <- list(selected=random_selected,calibration=list(items=candidates))
      random_rows <- tryCatch(make_rows("random10", random_obj), error = function(e) e)
      if (inherits(random_rows, "error")) add_event("method_failure", "random10", paste(candidates, collapse = ";"), conditionMessage(random_rows))
      else rep_rows[[length(rep_rows)+1L]] <- random_rows
    }
    rows <- if (length(rep_rows)) do.call(rbind, rep_rows) else data.frame()
    suspendInterrupts({
      if (!identical(as.numeric(file.info(c(detail_path, events_path))$size),
                     as.numeric(c(state$results_bytes, state$events_bytes)))) stop("Checkpoint files changed externally; resume to recover.")
      if (nrow(rows)) write.table(rows,detail_path,sep=",",row.names=FALSE,col.names=FALSE,append=TRUE,quote=TRUE,qmethod="double")
      if (length(rep_events)) write.table(do.call(rbind,rep_events),events_path,sep=",",row.names=FALSE,col.names=FALSE,append=TRUE,quote=TRUE,qmethod="double")
      state$completed <- rep
      state$results_bytes <- file.info(detail_path)$size
      state$events_bytes <- file.info(events_path)$size
      atomic_write_csv(state,state_path)
    })
    cat(sprintf("[%s] saved repetition %d/%d\n",scale,rep,state$target)); flush.console()
    if (final_reports_pending(rep, state$target, state$summary_count)) {
      write_reports(rep)
    }
  }
  invisible(state)
}

invisible(lapply(scales, run_scale))

# Publish the combined summary only when every requested scale has reached its
# final target and its per-scale reports have been committed.
all_scale_names <- c("Openness", "Neuroticism", "Agreeableness", "Conscientiousness")
all_state_paths <- file.path(output_root, all_scale_names, "monte_carlo_state.csv")
if (all(file.exists(all_state_paths))) {
  scale_states <- lapply(all_state_paths, read.csv, stringsAsFactors = FALSE)
  all_scales_complete <- all(vapply(scale_states, function(state) {
    nrow(state) == 1L && state$completed == reps && state$target == reps &&
      state$summary_count == reps
  }, logical(1)))
  if (all_scales_complete) write_combined_summary()
}
