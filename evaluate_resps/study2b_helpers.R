REVERSE_ITEMS <- list(
  Work_conscientiousness = c("WC16", "WC17", "WC18", "WC19", "WC20"),
  Work_honesty_humility = "WHH08"
)

scale_paths <- function(scale) {
  scale_lower <- tolower(scale)
  list(
    item_meta = file.path(repo_root, "scales_info", paste0(scale, "_info"), "scale_items.csv"),
    human = file.path(repo_root, "data", scale_lower, "human_responses", "human_responses.csv"),
    gpt = file.path(
      repo_root, "data", scale_lower, "llm_responses",
      "synth_item_responses_fullV2.1.1_no_detail_variation__openai_gpt_5_6_luna_floor.csv"
    )
  )
}

read_item_meta <- function(scale) {
  path <- scale_paths(scale)$item_meta
  meta <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("item_code", "reverse_coded")
  missing <- setdiff(required, names(meta))
  if (length(missing)) {
    stop(sprintf("%s is missing metadata columns: %s", path, paste(missing, collapse = ", ")))
  }
  if (anyDuplicated(meta$item_code)) {
    stop(sprintf("Duplicate item codes found in %s.", path))
  }
  meta$response_col <- meta$item_code
  meta
}

normalize_original_matrix <- function(mat, item_codes) {
  mat <- as.matrix(mat)
  mat <- suppressWarnings(matrix(
    as.numeric(mat),
    nrow = nrow(mat),
    ncol = ncol(mat),
    dimnames = list(NULL, item_codes)
  ))
  if (any(!is.finite(mat)) || any(!(mat %in% 1:5))) {
    stop("Original response matrix contains values outside 1:5 or missing values.")
  }
  mat
}

load_human_original <- function(scale, item_meta) {
  path <- scale_paths(scale)$human
  df <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  missing <- setdiff(item_meta$item_code, names(df))
  if (length(missing)) {
    stop(sprintf("Human file is missing item columns: %s", paste(missing, collapse = ", ")))
  }
  normalize_original_matrix(df[, item_meta$item_code, drop = FALSE], item_meta$item_code)
}

load_gpt_blocks <- function(scale, item_meta, path = scale_paths(scale)$gpt) {
  df <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("persona_id", "item_id", paste0("prob_", 1:5))
  missing <- setdiff(required, names(df))
  if (length(missing)) {
    stop(sprintf("GPT file is missing columns: %s", paste(missing, collapse = ", ")))
  }
  if (anyDuplicated(df[c("persona_id", "item_id")])) {
    stop("GPT file contains duplicate persona-item rows.")
  }
  missing_items <- setdiff(item_meta$item_code, unique(df$item_id))
  if (length(missing_items)) {
    stop(sprintf("GPT file is missing item blocks: %s", paste(missing_items, collapse = ", ")))
  }
  split(df, df$item_id, drop = TRUE)
}

reverse_code_and_dichotomise <- function(mat, reverse_items) {
  mat <- mat
  if (length(reverse_items)) {
    reverse_idx <- match(reverse_items, colnames(mat))
    if (anyNA(reverse_idx)) {
      stop(sprintf(
        "Reverse-coded items missing from matrix: %s",
        paste(reverse_items[is.na(reverse_idx)], collapse = ", ")
      ))
    }
    mat[, reverse_idx] <- 6 - mat[, reverse_idx]
  }
  if (any(!(mat %in% 1:5))) {
    stop("Reverse-coded matrix contains values outside 1:5.")
  }
  dichotomised <- ifelse(mat >= 4, 1, 0)
  storage.mode(dichotomised) <- "numeric"
  dimnames(dichotomised) <- dimnames(mat)
  dichotomised
}

sample_gpt_original <- function(blocks, item_meta) {
  item_codes <- item_meta$item_code
  first_block <- blocks[[item_codes[1]]]
  persona_ids <- unique(first_block$persona_id)
  out <- matrix(
    NA_real_,
    nrow = length(persona_ids),
    ncol = length(item_codes),
    dimnames = list(persona_ids, item_codes)
  )

  for (item_code in item_codes) {
    block <- blocks[[item_code]]
    if (nrow(block) != length(persona_ids) || !identical(unique(block$persona_id), persona_ids)) {
      stop(sprintf("GPT persona ordering/count differs for item %s.", item_code))
    }
    probs <- as.matrix(block[, paste0("prob_", 1:5), drop = FALSE])
    storage.mode(probs) <- "numeric"
    if (any(!is.finite(probs)) || any(probs < 0)) {
      stop(sprintf("Invalid GPT probabilities for item %s.", item_code))
    }
    out[, item_code] <- vapply(seq_len(nrow(probs)), function(row_idx) {
      row_probs <- probs[row_idx, ]
      total <- sum(row_probs)
      if (total <= 0) stop(sprintf("Non-positive GPT probability total for %s.", item_code))
      sample.int(5L, size = 1L, replace = TRUE, prob = row_probs / total)
    }, numeric(1))
  }
  out
}

fit_2pl <- function(binary_mat) {
  if (any(!(binary_mat %in% 0:1))) {
    stop("2PL input must contain only 0/1 responses.")
  }
  mirt::mirt(
    binary_mat,
    1,
    itemtype = "2PL",
    method = "EM",
    verbose = FALSE,
    technical = list(NCYCLES = 5000)
  )
}

STUDY2B_SCALES <- c("Work_conscientiousness", "Work_honesty_humility")
STUDY2B_METHODS <- c("human224", "human100", "openai_no_detail_variation", "xiaomi_no_detail_variation", "random10")
STUDY2B_WORKFLOW <- "study2b_224_100_binary_v1"

# Preserve the caller's RNG state, including when sampling or fitting fails.
with_study2b_seed <- function(seed, action) {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) previous <- get(".Random.seed", envir = .GlobalEnv)
  on.exit({
    if (had_seed) assign(".Random.seed", previous, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
  })
  set.seed(seed)
  action()
}

study2b_seed <- function(scale, repetition, base_seed, method = NULL) {
  scale_id <- match(scale, STUDY2B_SCALES)
  method_id <- if (is.null(method)) 0L else match(method, STUDY2B_METHODS)
  value <- as.double(base_seed) + scale_id * 10000000 + (as.double(repetition) - 1) * 100 + method_id * 10
  if (anyNA(c(scale_id, method_id)) || !is.finite(value) || value > .Machine$integer.max) stop("Unsupported scale, method or seed range.")
  as.integer(value)
}

random10_workplace <- function(items, seed) {
  if (length(items) < 10L || anyDuplicated(items)) stop("random10 needs at least 10 distinct candidates.")
  with_study2b_seed(seed, function() items[sample.int(length(items), 10L, replace = FALSE)])
}

study2b_validity_path <- function(scale) {
  if (scale == "Work_conscientiousness") {
    file.path(repo_root, "data", "human_data_details", "new_scales", "work_conscientiousness_conv_crit", "Conscientiousness_IPIP60.csv")
  } else {
    file.path(repo_root, "data", "human_data_details", "new_scales", "work_honesty_humility_conv_crit", "HH_Hexaco.csv")
  }
}

workplace_weak_items <- function(flags, meta, scale) {
  marked <- flags$potentially_weak_item %in% c(1, "1", TRUE, "TRUE")
  prefix <- if (scale == "Work_conscientiousness") "C_W_" else "HH_W_"
  relevant <- startsWith(flags$variable_name, prefix) | flags$variable_name %in% meta$item_code
  flags <- flags[marked & relevant, , drop = FALSE]
  direct <- match(flags$variable_name, meta$item_code)
  # The researcher's file uses original variable names and annotates some stems
  # with '(R)'; the simulation metadata supplies the canonical WC/WHH item codes.
  if ("item_text" %in% names(flags)) {
    normalize <- function(x) trimws(gsub("[[:space:]]+", " ", sub("[[:space:]]*\\(R\\)[[:space:]]*$", "", x)))
    stems <- normalize(meta$item_text)
    if (anyDuplicated(stems)) stop("Ambiguous workplace item text in metadata.")
    by_text <- match(normalize(flags$item_text), stems)
    if (any(!is.na(direct) & !is.na(by_text) & direct != by_text)) stop("Weak-item codes and text disagree.")
    direct[is.na(direct)] <- by_text[is.na(direct)]
  }
  if (anyNA(direct)) stop("A researcher-flagged workplace item could not be mapped to the candidate bank.")
  unique(meta$item_code[direct])
}

load_study2b_data <- function(scale) {
  meta <- read_item_meta(scale)
  if (nrow(meta) < 10L || !setequal(meta$item_code[meta$reverse_coded == 1L], REVERSE_ITEMS[[scale]])) stop("Unexpected candidate bank or reverse-coding metadata.")
  human_path <- scale_paths(scale)$human
  human <- read.csv(human_path, stringsAsFactors = FALSE, check.names = FALSE, colClasses = c(participant_id = "character"))
  if (!"participant_id" %in% names(human)) stop("Missing human participant_id.")
  ids <- trimws(human$participant_id)
  if (nrow(human) != 324L || anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids)) stop("Study 2b requires exactly 324 unique human participants for its 224/100 split.")
  original <- normalize_original_matrix(human[, meta$item_code, drop = FALSE], meta$item_code)
  binary <- reverse_code_and_dichotomise(original, REVERSE_ITEMS[[scale]])
  validity_path <- study2b_validity_path(scale)
  validity <- read.csv(validity_path, stringsAsFactors = FALSE, colClasses = c(participant_id = "character"))
  if (!all(c("participant_id", "sum_score") %in% names(validity))) stop("Missing convergent participant IDs or sum_score.")
  validity$participant_id <- trimws(validity$participant_id)
  if (anyNA(validity$participant_id) || any(!nzchar(validity$participant_id)) || anyDuplicated(validity$participant_id)) stop("Invalid convergent participant IDs.")
  matched <- match(ids, validity$participant_id)
  scores <- suppressWarnings(as.numeric(validity$sum_score[matched]))
  if (anyNA(matched) || any(!is.finite(scores))) stop("All 324 human IDs must match finite convergent scores.")
  llm <- file.path(repo_root, "data", tolower(scale), "llm_responses")
  synthetic_paths <- c(
    openai_no_detail_variation = file.path(llm, "synth_item_responses_fullV2.1.1_no_detail_variation__openai_gpt_5_6_luna_floor.csv"),
    xiaomi_no_detail_variation = file.path(llm, "synth_item_responses_fullV2.1.1_no_detail_variation__xiaomi_mimo_v2_6_flash.csv")
  )
  blocks <- lapply(synthetic_paths, function(path) load_gpt_blocks(scale, meta, path))
  weak_path <- file.path(repo_root, "data", "human_data_details", "new_scales", "new_scales_potentially_weak_items.csv")
  flags <- read.csv(weak_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM")
  if (!all(c("variable_name", "potentially_weak_item") %in% names(flags))) stop("Invalid potentially weak item file.")
  weak <- workplace_weak_items(flags, meta, scale)
  inputs <- c(scale_paths(scale)$item_meta, human_path, validity_path, synthetic_paths, weak_path)
  list(meta = meta, binary = binary, ids = ids, scores = scores, blocks = blocks, weak = weak,
       signature = paste(unname(tools::md5sum(inputs)), collapse = ";"))
}

fit_parameter_table <- function(model) {
  params <- mirt::coef(model, IRTpars = TRUE, simplify = TRUE)$items
  data.frame(item = rownames(params), a = as.numeric(params[, "a"]), b = as.numeric(params[, "b"]), stringsAsFactors = FALSE)
}

compare_2pl_parameters <- function(reference_model, method_model, item_codes) {
  reference <- fit_parameter_table(reference_model)
  method <- fit_parameter_table(method_model)
  reference <- reference[match(item_codes, reference$item), , drop = FALSE]
  method <- method[match(item_codes, method$item), , drop = FALSE]
  a <- abs(method$a - reference$a); b <- abs(method$b - reference$b)
  a <- a[is.finite(a)]; b <- b[is.finite(b)]
  list(a_abs_diff_median = if (length(a)) median(a) else NA_real_,
       b_abs_diff_median = if (length(b)) median(b) else NA_real_,
       a_compared_n = length(a), b_compared_n = length(b))
}

study2b_empty_results <- function() {
  data.frame(scale = character(), repetition = integer(), seed = integer(), split_seed = integer(),
    method_seed = integer(), method = character(), candidate_items = character(), eligible_items = character(),
    selected_items = character(), reference_selected_items = character(), calibration_ids = character(),
    method_participant_ids = character(), evaluation_ids = character(), fit_n = integer(), fit_items = integer(),
    a_abs_diff_median = numeric(), b_abs_diff_median = numeric(), a_compared_n = integer(), b_compared_n = integer(),
    overlap_n = integer(), potentially_weak_selected_n = integer(), pearson_r = numeric(), spearman_r = numeric(),
    eval_n = integer(), scoring_method = character(), eval_short_sum = character(), eval_target_sum = character(),
    stringsAsFactors = FALSE)
}

# State is committed only after the two append writes have closed successfully.
write_study2b_csv <- function(data, path) {
  staged <- tempfile(".study2b-", tmpdir = dirname(path), fileext = ".csv")
  on.exit(unlink(staged))
  write.csv(data, staged, row.names = FALSE)
  suspendInterrupts({ if (!file.rename(staged, path)) stop("Could not publish Study 2b checkpoint.") })
}

study2b_paths <- function(output_root, scale) {
  setNames(file.path(output_root, scale, c("monte_carlo_results.csv", "monte_carlo_exclusions_and_failures.csv",
    "monte_carlo_state.csv", "monte_carlo_summary.csv", "monte_carlo_comparisons.xlsx")),
    c("results", "events", "state", "summary", "workbook"))
}

prepare_study2b_checkpoint <- function(paths, scale, args, signature) {
  dir <- dirname(paths["state"])
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (any(file.exists(file.path(dir, c("new_scale_raw_results.csv", "new_scale_results.csv", "convergence_log.csv"))))) stop("Choose a fresh Study 2b output directory; legacy results will not be reused.")
  if (!file.exists(paths["state"])) {
    if (any(file.exists(paths[c("results", "events", "summary", "workbook")]))) stop("Output exists without a state file; refusing to overwrite it.")
    state <- data.frame(workflow = STUDY2B_WORKFLOW, scale = scale, seed = args$seed, target_reps = args$reps,
      success_count = 0L, attempt_count = 0L, summary_count = 0L, signature = signature)
    suspendInterrupts({
      write.csv(study2b_empty_results(), paths["results"], row.names = FALSE)
      write.csv(common$empty_event_rows(), paths["events"], row.names = FALSE)
      state$results_bytes <- file.info(paths["results"])$size
      state$events_bytes <- file.info(paths["events"])$size
      write_study2b_csv(state, paths["state"])
    })
  } else {
    if (!args$resume) stop("Output exists; use --resume.")
    state <- read.csv(paths["state"], stringsAsFactors = FALSE)
    required <- c("workflow", "scale", "seed", "target_reps", "success_count", "attempt_count", "summary_count", "signature", "results_bytes", "events_bytes")
    if (nrow(state) != 1L || !all(required %in% names(state))) stop("Invalid Study 2b state schema.")
    numbers <- unlist(state[c("seed", "target_reps", "success_count", "attempt_count", "summary_count", "results_bytes", "events_bytes")], use.names = FALSE)
    if (any(!is.finite(numbers)) || any(numbers != floor(numbers)) || state$workflow != STUDY2B_WORKFLOW ||
        state$scale != scale || state$seed != args$seed || state$signature != signature ||
        state$success_count < 0 || state$attempt_count != state$success_count || state$target_reps < state$success_count ||
        state$summary_count < 0 || state$summary_count > state$success_count || state$summary_count %% 10L != 0L) stop("Invalid or incompatible checkpoint/input files.")
    common$recover_checkpoint_tails(paths, state)
    if (!identical(names(read.csv(paths["results"], nrows = 0L)), names(study2b_empty_results())) ||
        !identical(names(read.csv(paths["events"], nrows = 0L)), names(common$empty_event_rows()))) stop("Unexpected checkpoint CSV headers.")
  }
  state$target_reps <- if (!is.na(args$additional_reps)) state$success_count + args$additional_reps else max(state$target_reps, args$reps)
  write_study2b_csv(state, paths["state"])
  state
}

save_study2b_checkpoint <- function(rows, events, paths, state) {
  next_rep <- state$success_count + 1L
  if (next_rep > state$target_reps) stop("Checkpoint would exceed the repetition target.")
  if (nrow(rows) && (any(rows$repetition != next_rep | rows$scale != state$scale |
      rows$seed != state$seed + next_rep - 1L | rows$split_seed != study2b_seed(state$scale, next_rep, state$seed)) ||
      any(!rows$method %in% STUDY2B_METHODS) || anyDuplicated(rows$method))) stop("Invalid or duplicate repetition rows.")
  if (nrow(rows) && any(rows$method_seed != vapply(rows$method, function(m) study2b_seed(state$scale, next_rep, state$seed, m), integer(1)))) stop("Wrong method seed in checkpoint.")
  if (nrow(events) && (any(events$repetition != next_rep | events$attempt != next_rep) ||
      any(!events$method %in% STUDY2B_METHODS) || any(!events$record_type %in% c("item_exclusion", "method_failure")))) stop("Invalid exclusion/failure log.")
  if (nrow(events) && any(events$seed != vapply(events$method, function(m) study2b_seed(state$scale, next_rep, state$seed, m), integer(1)))) stop("Wrong method seed in exclusion/failure log.")
  failures <- events$method[events$record_type == "method_failure"]
  if (anyDuplicated(failures) || length(intersect(rows$method, failures)) || !setequal(c(rows$method, failures), STUDY2B_METHODS)) stop("Each method must have a complete result or one genuine failure.")
  actual <- as.numeric(file.info(paths[c("results", "events")])$size)
  if (!identical(actual, as.numeric(c(state$results_bytes, state$events_bytes)))) stop("Output changed externally; resume to recover.")
  suspendInterrupts({
    common$append_checkpoint_csv(rows, paths["results"], names(study2b_empty_results()))
    common$append_checkpoint_csv(events, paths["events"], names(common$empty_event_rows()))
    state$success_count <- state$attempt_count <- next_rep
    state$results_bytes <- file.info(paths["results"])$size
    state$events_bytes <- file.info(paths["events"])$size
    write_study2b_csv(state, paths["state"])
  })
  cat(sprintf("[%s] saved repetition %d/%d (%d successful methods; %d log events)\n", state$scale, next_rep, state$target_reps, nrow(rows), nrow(events)))
  flush.console()
  state
}

study2b_summary <- function(results) {
  specs <- c(a_abs_diff_median = "candidate_selection", b_abs_diff_median = "candidate_selection",
    overlap_n = "candidate_selection", potentially_weak_selected_n = "candidate_selection",
    pearson_r = "short_form_evaluation", spearman_r = "short_form_evaluation")
  summaries <- list()
  for (metric in names(specs)) {
    stage <- specs[[metric]]
    data <- results
    data$stage <- rep(stage, nrow(data))
    # Recompute score correlations from saved vectors for the paired tests, as in Study 1.
    if (stage == "short_form_evaluation" && nrow(data)) data[[metric]] <- vapply(seq_len(nrow(data)), function(i) {
      common$validity_metric_from_scores(common$decode_semicolon_numeric(data$eval_short_sum[i]),
        common$decode_semicolon_numeric(data$eval_target_sum[i]), metric)
    }, numeric(1))
    methods <- if (grepl("abs_diff", metric)) setdiff(STUDY2B_METHODS, "random10") else STUDY2B_METHODS
    family <- list(); family_ids <- character()
    for (method in methods) {
      x <- data[[metric]][data$method == method]; x <- x[is.finite(x)]
      summaries[[length(summaries) + 1L]] <- data.frame(stage = stage, metric = metric, method = method,
        mean = if (length(x)) mean(x) else NA_real_, successful_reps = length(x), comparison = NA_character_,
        mean_diff = NA_real_, ci_lower = NA_real_, ci_upper = NA_real_, win_n = NA_integer_, win_pct = NA_real_,
        p_value = NA_real_, p_holm = NA_real_, valid_paired_repetitions = NA_integer_)
    }
    for (method in setdiff(methods, "human224")) for (benchmark in c("human100", "human224")) {
      if (method == benchmark || (method == "human100" && benchmark != "human224")) next
      paired <- common$paired_test_row(data, stage, metric, method, benchmark,
        if (stage == "short_form_evaluation") "SUM_SCORE" else NULL)
      a <- data[data$method == method, c("repetition", metric), drop = FALSE]
      b <- data[data$method == benchmark, c("repetition", metric), drop = FALSE]
      joined <- merge(a, b, by = "repetition")
      diff <- joined[[paste0(metric, ".x")]] - joined[[paste0(metric, ".y")]]
      diff <- diff[is.finite(diff)]
      direction <- if (metric %in% c("a_abs_diff_median", "b_abs_diff_median", "potentially_weak_selected_n")) -1 else 1
      family[[length(family) + 1L]] <- data.frame(stage = stage, metric = metric, method = method,
        mean = if (any(is.finite(a[[metric]]))) mean(a[[metric]][is.finite(a[[metric]])]) else NA_real_,
        successful_reps = sum(is.finite(a[[metric]])), comparison = paste0("vs_", benchmark),
        mean_diff = paired$mean_diff, ci_lower = paired$ci_lower, ci_upper = paired$ci_upper,
        win_n = sum(direction * diff > 0), win_pct = if (length(diff)) 100 * mean(direction * diff > 0) else NA_real_,
        p_value = paired$p, p_holm = NA_real_, valid_paired_repetitions = paired$valid_paired_repetitions)
      family_ids <- c(family_ids, if (method == "random10") "random10" else if (method == "human100") "human" else "synthetic")
    }
    if (length(family)) {
      family <- do.call(rbind, family)
      for (id in unique(family_ids)) {
        keep <- family_ids == id & is.finite(family$p_value)
        family$p_holm[keep] <- p.adjust(family$p_value[keep], method = "holm")
      }
      summaries[[length(summaries) + 1L]] <- family
    }
  }
  do.call(rbind, summaries)
}

write_study2b_combined <- function(output_root) {
  paths <- vapply(STUDY2B_SCALES, function(scale) study2b_paths(output_root, scale)["summary"], character(1))
  paths <- paths[file.exists(paths)]
  if (length(paths)) write_study2b_csv(do.call(rbind, lapply(paths, read.csv, stringsAsFactors = FALSE)), file.path(output_root, "monte_carlo_study2b_summary.csv"))
}

report_study2b <- function(paths, state, output_root) {
  count <- state$success_count
  if (!count || count %% 10L != 0L || state$summary_count >= count) return(state)
  cat(sprintf("[%s] generating summary and workbook through repetition %d...\n", state$scale, count)); flush.console()
  data <- read.csv(paths["results"], stringsAsFactors = FALSE)
  summary <- study2b_summary(data)
  summary$scale <- state$scale
  events <- read.csv(paths["events"], stringsAsFactors = FALSE)
  summary$attempted_reps <- count
  summary$method_failure_repetitions <- vapply(summary$method, function(m) length(unique(events$repetition[events$method == m & events$record_type == "method_failure"])), integer(1))
  summary$item_drop_repetitions <- vapply(summary$method, function(m) length(unique(events$repetition[events$method == m & events$record_type == "item_exclusion"])), integer(1))
  tmp_csv <- tempfile(".study2b-summary-", tmpdir = dirname(paths["summary"]), fileext = ".csv")
  tmp_xlsx <- tempfile(".study2b-workbook-", tmpdir = dirname(paths["workbook"]), fileext = ".xlsx")
  on.exit(unlink(c(tmp_csv, tmp_xlsx)))
  write.csv(summary, tmp_csv, row.names = FALSE)
  openxlsx::write.xlsx(list(
    "Parameter recovery" = summary[summary$metric %in% c("a_abs_diff_median", "b_abs_diff_median"), ],
    "Item overlap" = summary[summary$metric == "overlap_n", ],
    "Weak item selection" = summary[summary$metric == "potentially_weak_selected_n", ],
    "Convergent validity" = summary[summary$metric %in% c("pearson_r", "spearman_r"), ]
  ), tmp_xlsx, overwrite = TRUE)
  suspendInterrupts({
    if (!file.rename(tmp_csv, paths["summary"]) || !file.rename(tmp_xlsx, paths["workbook"])) stop("Report publication failed; resume will retry.")
    write_study2b_combined(output_root)
    state$summary_count <- count
    write_study2b_csv(state, paths["state"])
  })
  cat(sprintf("[%s] summary and workbook saved\n", state$scale)); flush.console()
  state
}
