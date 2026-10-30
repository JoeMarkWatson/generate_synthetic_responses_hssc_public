#!/usr/bin/env Rscript

# Fixed workplace candidate banks; a fresh 224/100 human partition per repetition.
# One 2PL calibration per method, shared ATA, and raw binary sum-score validity.

script_file <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_dir <- if (length(script_file)) dirname(normalizePath(sub("^--file=", "", script_file[1]), mustWork = TRUE)) else normalizePath("evaluate_resps", mustWork = TRUE)
repo_root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
source(file.path(script_dir, "ATA.R"), local = TRUE)
# Reuse Study 1's generic exclusions, event schema, append/recovery code and paired tests.
# Its guarded main() is not executed when it is sourced into this private environment.
common <- new.env(parent = globalenv())
sys.source(file.path(script_dir, "monte_carlo_study1.R"), envir = common)
source(file.path(script_dir, "study2b_helpers.R"), local = TRUE)

parse_study2b_args <- function(args) {
  out <- list(scales = STUDY2B_SCALES, reps = 1000L, seed = 1L, resume = FALSE,
    additional_reps = NA_integer_, output_dir = file.path(script_dir, "monte_carlo_study2b_output"))
  i <- 1L
  while (i <= length(args)) {
    arg <- args[i]
    if (arg == "--resume") { out$resume <- TRUE; i <- i + 1L; next }
    if (arg %in% c("--help", "-h")) {
      cat("Usage: Rscript evaluate_resps/monte_carlo_study2b.R [--reps=N] [--scale=Work_conscientiousness,Work_honesty_humility] [--seed=1] [--output-dir=PATH] [--resume] [--additional-reps=N]\n")
      return(NULL)
    }
    parts <- strsplit(arg, "=", fixed = TRUE)[[1]]
    key <- parts[1]
    if (!key %in% c("--reps", "--n-reps", "--seed", "--scale", "--output-dir", "--additional-reps")) stop(sprintf("Unknown argument: %s", arg))
    if (length(parts) > 1L) value <- substring(arg, nchar(key) + 2L) else {
      i <- i + 1L
      if (i > length(args) || startsWith(args[i], "--")) stop(sprintf("%s needs a value.", key))
      value <- args[i]
    }
    if (!nzchar(value)) stop(sprintf("%s needs a value.", key))
    if (key == "--scale") out$scales <- unique(trimws(strsplit(value, ",", fixed = TRUE)[[1]]))
    else if (key == "--output-dir") out$output_dir <- value
    else {
      number <- suppressWarnings(as.numeric(value))
      if (length(number) != 1L || !is.finite(number) || number < 1 || number != floor(number) || number > .Machine$integer.max) stop(sprintf("%s must be a positive integer.", key))
      field <- switch(key, "--reps" = "reps", "--n-reps" = "reps", "--seed" = "seed", "--additional-reps" = "additional_reps")
      out[[field]] <- as.integer(number)
    }
    i <- i + 1L
  }
  if (!length(out$scales) || any(!out$scales %in% STUDY2B_SCALES)) stop("Unsupported workplace scale.")
  if (!is.na(out$additional_reps) && !out$resume) stop("--additional-reps requires --resume.")
  out
}

run_study2b_repetition <- function(scale, repetition, base_seed, data) {
  split_seed <- study2b_seed(scale, repetition, base_seed)
  partition <- with_study2b_seed(split_seed, function() sample.int(324L))
  calibration <- partition[1:224]
  evaluation <- partition[225:324]
  candidates <- data$meta$item_code
  events <- list(); rows <- list(); reference <- NULL
  add_failure <- function(method, items, reason) {
    events[[length(events) + 1L]] <<- common$make_method_failure_event(method, repetition, repetition,
      study2b_seed(scale, repetition, base_seed, method), items, gsub("[\r\n]+", " ", reason))
  }
  for (method in STUDY2B_METHODS) {
    method_seed <- study2b_seed(scale, repetition, base_seed, method)
    cat(sprintf("[%s] repetition %d: %s\n", scale, repetition, method)); flush.console()
    result <- tryCatch(with_study2b_seed(method_seed, function() {
      training_ids <- character(); fit <- NULL; eligible <- candidates
      fit_n <- fit_items <- NA_integer_
      if (method == "random10") {
        selected <- random10_workplace(candidates, method_seed)
      } else {
        if (method %in% c("human224", "human100")) {
          indices <- if (method == "human224") calibration else sample(calibration, 100L, replace = FALSE)
          training <- data$binary[indices, , drop = FALSE]
          training_ids <- data$ids[indices]
        } else {
          original <- sample_gpt_original(data$blocks[[method]], data$meta)
          training <- reverse_code_and_dichotomise(original, REVERSE_ITEMS[[scale]])
          training_ids <- rownames(training)
        }
        prepared <- common$prepare_calibration_data(training, candidates)
        events <<- c(events, common$make_item_exclusion_events(prepared$exclusions, method, repetition, repetition, method_seed))
        eligible <- prepared$items
        if (!prepared$enough_items) stop("Fewer than 10 eligible candidates remain after constant-item exclusions.")
        fit <- fit_2pl(prepared$fit_mat)
        if (!isTRUE(fit@OptimInfo$converged)) stop("2PL model did not converge.")
        fit_n <- nrow(prepared$fit_mat); fit_items <- length(eligible)
        selected <- assemble_greedy_maximin_ata(fit, n_select = 10L)$selected_items
      }
      if (length(selected) != 10L || anyDuplicated(selected) || !all(selected %in% eligible)) stop("Invalid ten-item selection.")
      ref <- if (method == "human224") list(fit = fit, items = eligible, selected = selected) else reference
      parameters <- list(a_abs_diff_median = NA_real_, b_abs_diff_median = NA_real_, a_compared_n = NA_integer_, b_compared_n = NA_integer_)
      if (method != "random10" && !is.null(ref)) parameters <- compare_2pl_parameters(ref$fit, fit, intersect(ref$items, eligible))
      scores <- common$score_sum_scores(data$binary[evaluation, selected, drop = FALSE], matrix(data$scores[evaluation], ncol = 1L))
      if (scores$n_eval != 100L) stop("Validity must use the same 100 held-out respondents for every method.")
      row <- data.frame(scale = scale, repetition = repetition, seed = base_seed + repetition - 1L,
        split_seed = split_seed, method_seed = method_seed, method = method,
        candidate_items = paste(candidates, collapse = ";"), eligible_items = paste(eligible, collapse = ";"),
        selected_items = paste(selected, collapse = ";"), reference_selected_items = if (is.null(ref)) NA_character_ else paste(ref$selected, collapse = ";"),
        calibration_ids = paste(data$ids[calibration], collapse = ";"), method_participant_ids = paste(training_ids, collapse = ";"),
        evaluation_ids = paste(data$ids[evaluation], collapse = ";"), fit_n = fit_n, fit_items = fit_items,
        a_abs_diff_median = parameters$a_abs_diff_median, b_abs_diff_median = parameters$b_abs_diff_median,
        a_compared_n = parameters$a_compared_n, b_compared_n = parameters$b_compared_n,
        overlap_n = if (is.null(ref)) NA_integer_ else length(intersect(selected, ref$selected)),
        potentially_weak_selected_n = length(intersect(selected, data$weak)),
        pearson_r = scores$pearson_r, spearman_r = scores$spearman_r, eval_n = scores$n_eval, scoring_method = "SUM_SCORE",
        eval_short_sum = paste(sprintf("%.17g", scores$short_sum_values), collapse = ";"),
        eval_target_sum = paste(sprintf("%.17g", scores$target_values), collapse = ";"), stringsAsFactors = FALSE)
      list(row = row, reference = if (method == "human224") ref else NULL)
    }), error = function(e) e)
    if (inherits(result, "error")) {
      add_failure(method, candidates, conditionMessage(result))
      cat(sprintf("[%s] repetition %d %s failed: %s\n", scale, repetition, method, conditionMessage(result)))
    } else {
      rows[[length(rows) + 1L]] <- result$row
      if (method == "human224") reference <- result$reference
    }
  }
  list(rows = if (length(rows)) do.call(rbind, rows) else study2b_empty_results(),
       events = if (length(events)) do.call(rbind, events) else common$empty_event_rows())
}

run_study2b <- function(args) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) stop("The openxlsx package is required for scheduled comparison workbooks.")
  for (scale in args$scales) {
    data <- load_study2b_data(scale)
    cat(sprintf("[%s] %d candidates; 324 matched participants; 224 calibration / 100 evaluation\n", scale, nrow(data$meta)))
    paths <- study2b_paths(args$output_dir, scale)
    state <- prepare_study2b_checkpoint(paths, scale, args, data$signature)
    state <- report_study2b(paths, state, args$output_dir)
    while (state$success_count < state$target_reps) {
      result <- run_study2b_repetition(scale, state$success_count + 1L, args$seed, data)
      state <- save_study2b_checkpoint(result$rows, result$events, paths, state)
      state <- report_study2b(paths, state, args$output_dir)
    }
  }
  invisible(NULL)
}

if (sys.nframe() == 0L) {
  args <- parse_study2b_args(commandArgs(trailingOnly = TRUE))
  if (!is.null(args)) run_study2b(args)
}
