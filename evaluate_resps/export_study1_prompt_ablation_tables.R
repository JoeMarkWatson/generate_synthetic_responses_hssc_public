#!/usr/bin/env Rscript
# Base R only. Run from any directory; no simulations, IRT fits or packages.
# Input means are calculated by monte_carlo_study1.R::summarise_results():
# arithmetic means of finite repetition-level outcomes, with failed fits omitted.
# In particular, a_abs_diff_median_mean is a MEAN of within-repetition medians.
# CSVs retain full precision; console tables use decimal half-up display rounding.
args <- grep('^--file=', commandArgs(FALSE), value = TRUE)
if (length(args) != 1L) stop('Run this script with Rscript.')
root <- normalizePath(file.path(dirname(sub('^--file=', '', args)), '..'))
input <- file.path(root, 'evaluate_resps/monte_carlo_study1_output/monte_carlo_summary.csv')
output_dir <- file.path(root, 'tables/study1')
summary <- read.csv(input, stringsAsFactors = FALSE, check.names = FALSE)
conditions <- c('full', 'no_assoc', 'no_demogs', 'no_detail_variation',
                'no_probabilities', 'no_trait', 'single_answer_demogs')
condition_labels <- c('Full prompt', 'No association information', 'No demographics',
                      'No variation detail', 'No response probabilities', 'No trait information',
                      'Demographics-only direct response')
models <- c('OpenAI', 'Claude', 'Xiaomi', 'DeepSeek')
prefixes <- c('openai', 'claude', 'xiaomi', 'v2.1.1')
metric_names <- c('mean_median_abs_delta_a', 'mean_overlap_out_of_10',
                  'mean_nuisance_items', 'pearson_r', 'spearman_rho')
source_columns <- c('a_abs_diff_median_mean', 'overlap_n_mean',
                    'nuisance_selected_n_mean', 'pearson_r_mean', 'spearman_r_mean')
metric_stages <- c('candidate_selection', 'candidate_selection',
                   'nuisance_screening', 'short_form_evaluation', 'short_form_evaluation')
required <- c('stage', 'method', 'successful_method_reps', 'scoring_method', source_columns)
if (!all(required %in% names(summary))) stop('Unexpected source summary schema.')

get_stage <- function(method, stage) {
  row <- summary[summary$method == method & summary$stage == stage, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf('Expected one %s/%s row; found %d.', method, stage, nrow(row)))
  if (stage == 'short_form_evaluation' &&
      (is.na(row$scoring_method) || row$scoring_method != 'SUM_SCORE')) stop('Expected raw-sum validity.')
  row
}
rows <- list()
for (model_index in seq_along(models)) for (condition_index in seq_along(conditions)) {
  condition <- conditions[condition_index]
  method <- if (condition == 'single_answer_demogs') {
    if (models[model_index] == 'DeepSeek') condition else paste(prefixes[model_index], condition, sep = '_')
  } else if (models[model_index] == 'DeepSeek' && condition == 'full') {
    'v2.1.1'
  } else paste(prefixes[model_index], condition, sep = '_')
  stage_rows <- lapply(unique(metric_stages), function(stage) get_stage(method, stage))
  counts <- vapply(stage_rows, function(row) row$successful_method_reps, numeric(1))
  if (any(!is.finite(counts)) || any(counts < 1 | counts != floor(counts)) ||
      length(unique(counts)) != 1L) stop(paste('Missing or inconsistent successful counts:', method))
  values <- vapply(seq_along(metric_names), function(j) {
    get_stage(method, metric_stages[j])[[source_columns[j]]]
  }, numeric(1))
  if (any(!is.finite(values))) stop(paste('Missing/nonfinite metric:', method))
  row <- data.frame(model = models[model_index], prompt_condition = condition_labels[condition_index],
                    source_method = method, successful_repetitions = counts[1], stringsAsFactors = FALSE)
  row[metric_names] <- as.list(values)
  rows[[length(rows) + 1L]] <- row
}
table_f1 <- do.call(rbind, rows)
stopifnot(nrow(table_f1) == 28L, !anyDuplicated(table_f1[c('model', 'prompt_condition')]))
# Equal weight for each model, regardless of its number of successful fits.
# Do not average pre-rounded values and do not pool repetitions across models.
table_3 <- do.call(rbind, lapply(condition_labels, function(condition) {
  selected <- table_f1[table_f1$prompt_condition == condition, , drop = FALSE]
  stopifnot(nrow(selected) == 4L, setequal(selected$model, models))
  row <- data.frame(prompt_condition = condition, stringsAsFactors = FALSE)
  row[metric_names] <- lapply(selected[metric_names], mean)
  row
}))

# Display policy: conventional decimal half-up (ties away from zero).
# A few floating-point ulps prevent binary representation of a decimal tie
# (e.g. 6.985) from erroneously rounding down. This never changes CSV values.
display_number <- function(x, digits) {
  scaled <- abs(x) * 10^digits
  guard <- 8 * .Machine$double.eps * pmax(1, scaled)
  rounded <- sign(x) * floor(scaled + 0.5 + guard) / 10^digits
  formatC(rounded, format = 'f', digits = digits)
}
display_table <- function(x) {
  digits <- c(3L, 2L, 3L, 3L, 3L)
  for (j in seq_along(metric_names)) x[[metric_names[j]]] <- display_number(x[[metric_names[j]]], digits[j])
  x
}

# Independent checks only: expected manuscript values below are NEVER used to
# calculate, replace or populate either output table. All estimates exist above.
manuscript <- rbind(
  c('0.346', '7.14', '0.003', '0.856', '0.846'),
  c('0.314', '7.02', '0.007', '0.854', '0.843'),
  c('0.313', '6.99', '0.000', '0.855', '0.844'),
  c('0.289', '7.36', '0.000', '0.861', '0.851'),
  c('9.418', '1.66', '3.439', '0.648', '0.627'),
  c('0.897', '4.16', '1.695', '0.784', '0.769'))
manuscript_rows <- match(condition_labels[seq_len(nrow(manuscript))], table_3$prompt_condition)
computed <- as.matrix(display_table(table_3[manuscript_rows, , drop = FALSE])[metric_names])
mismatches <- which(computed != manuscript, arr.ind = TRUE)
expected_counts <- c(OpenAI = 482L, Claude = 500L, Xiaomi = 478L, DeepSeek = 482L)
no_prob <- table_f1[table_f1$prompt_condition == 'No response probabilities', ]
actual_counts <- setNames(no_prob$successful_repetitions, no_prob$model)
wrong_counts <- names(expected_counts)[actual_counts[names(expected_counts)] != expected_counts]
if (nrow(mismatches) || length(wrong_counts)) {
  cat('VERIFICATION FAILED; no output tables were written.\n')
  for (i in seq_len(nrow(mismatches))) {
    r <- mismatches[i, 1]; c <- mismatches[i, 2]
    cat(sprintf('%s / %s: computed %s; manuscript %s\n', condition_labels[r], metric_names[c], computed[r,c], manuscript[r,c]))
  }
  for (model in wrong_counts) cat(sprintf('%s no-probabilities count: computed %d; expected %d\n', model, actual_counts[model], expected_counts[model]))
  stop('Source results differ from the manuscript verification targets.', call. = FALSE)
}

# Write full-precision numeric values only after every verification passes.
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
paths <- file.path(output_dir, c('table_3_prompt_ablation.csv', 'table_F1_model_prompt_ablation.csv'))
write.csv(table_3, paths[1], row.names = FALSE, na = '')
write.csv(table_f1, paths[2], row.names = FALSE, na = '')
cat('VERIFICATION PASSED: all 30 manuscript values match at reported precision.\n')
cat('Display rounding: decimal half-up; CSVs retain full precision.\n')
cat('No-probabilities successful repetitions: ', paste(names(expected_counts), actual_counts[names(expected_counts)], sep = '=', collapse = ', '), '\n', sep = '')
cat('Table 3: equal-weight mean of four model means; failed fits omitted, never zero-filled.\n')
print(display_table(table_3), row.names = FALSE, right = FALSE)
cat('\nTable F1: 28 model-by-prompt combinations.\nInput: ', input, '\nOutputs:\n', paste(paths, collapse = '\n'), '\n', sep = '')
