#!/usr/bin/env Rscript
# Saved profiles only: no LLM requests, generation, simulation or model fitting.
# jsonlite reads the existing JSONL files; all calculations use base R.
# Run from any directory: Rscript /path/to/this/script.R
args <- grep('^--file=', commandArgs(FALSE), value = TRUE)
if (length(args) != 1L) stop('Run using Rscript.')
root <- normalizePath(file.path(dirname(sub('^--file=', '', args)), '..'))
scales <- c(Extraversion = 'extraversion', Openness = 'openness',
            Neuroticism = 'neuroticism', Agreeableness = 'agreeableness',
            Conscientiousness = 'conscientiousness',
            'Work Conscientiousness' = 'work_conscientiousness',
            'Work Honesty–Humility' = 'work_honesty_humility')
required <- c('persona_id', 'gender', 'age', 'country')

read_profiles <- function(path) {
  first <- readLines(path, n = 1L, warn = FALSE)
  if (!length(first)) stop('Empty persona file: ', path)
  if (startsWith(trimws(first), '{')) {
    if (!requireNamespace('jsonlite', quietly = TRUE))
      stop('Reading JSONL requires jsonlite; no packages are installed automatically.')
    con <- file(path, 'r', encoding = 'UTF-8')
    on.exit(close(con))
    d <- jsonlite::stream_in(con, verbose = FALSE)
    format <- 'JSONL'
  } else {
    d <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    format <- 'CSV'
  }
  if (!is.data.frame(d) || !setequal(names(d), required))
    stop('Unexpected columns in ', path, ': ', paste(names(d), collapse = ', '))
  d <- d[required]
  for (key in required) {
    d[[key]] <- trimws(as.character(d[[key]]))
    bad <- is.na(d[[key]]) | !nzchar(d[[key]])
    if (any(bad)) stop('Missing ', key, ' in ', path, '; rows: ', paste(which(bad), collapse = ', '))
  }
  raw_gender <- d$gender; raw_country <- d$country
  gender <- tolower(raw_gender)
  unknown <- !gender %in% c('m', 'male', 'f', 'female')
  if (any(unknown)) stop('Unexpected gender labels in ', path, ': ', paste(unique(raw_gender[unknown]), collapse = ', '))
  d$gender <- ifelse(gender %in% c('f', 'female'), 'Female', 'Male')
  age <- suppressWarnings(as.numeric(d$age))
  if (any(!is.finite(age) | age <= 0 | age != floor(age)))
    stop('Missing/nonpositive/noninteger age in ', path)
  if (any(age < 10 | age > 100)) warning('Unusual ages retained in ', path, ': ', paste(unique(age[age < 10 | age > 100]), collapse = ', '))
  d$age <- age
  country <- tolower(gsub('[[:space:]]+', ' ', raw_country))
  if (any(country %in% c('na', 'n/a', 'unknown', 'other', 'not specified', 'prefer not to say')))
    stop('Unspecified/unexpected country category in ', path, ': ', paste(unique(raw_country[country %in% c('na', 'n/a', 'unknown', 'other', 'not specified', 'prefer not to say')]), collapse = ', '))
  # Only explicit aliases are mapped; every remaining named country is Other.
  uk <- country %in% c('uk', 'u.k.', 'united kingdom', 'great britain')
  usa <- country %in% c('us', 'u.s.', 'usa', 'u.s.a.', 'united states', 'united states of america')
  d$country <- ifelse(uk, 'UK', ifelse(usa, 'USA', country))
  # Deduplicate complete records with the same ID; conflicting reuse is an error.
  distinct <- unique(d)
  if (anyDuplicated(distinct$persona_id)) {
    ids <- unique(distinct$persona_id[duplicated(distinct$persona_id)])
    stop('Conflicting demographics for persona ID(s) in ', path, ': ', paste(ids, collapse = ', '))
  }
  cat('  Source: ', path, ' [', format, ']\n', sep = '')
  cat('  Gender labels: ', paste(sort(unique(raw_gender)), collapse = ', '), '\n', sep = '')
  cat('  Country labels: ', paste(sort(unique(raw_country)), collapse = ', '), '\n', sep = '')
  if (nrow(distinct) != nrow(d)) cat('  Identical duplicate-ID records counted once: ', nrow(d) - nrow(distinct), '\n', sep = '')
  if (!all(c('Female', 'Male') %in% distinct$gender))
    warning('One gender category is absent in ', path)
  distinct <- distinct[order(distinct$persona_id), ]
  rownames(distinct) <- NULL
  distinct
}

rows <- list(); sources <- list()
for (i in seq_along(scales)) {
  dir <- file.path(root, 'data', scales[i], 'llm_responses')
  paths <- sort(list.files(dir, pattern = '^synth_personas_base($|[_.-])',
                          recursive = TRUE, full.names = TRUE, all.files = TRUE))
  paths <- paths[!file.info(paths)$isdir]
  if (!length(paths)) stop('No base-persona files found for ', names(scales)[i])
  cat('\n', names(scales)[i], '\n', sep = '')
  copies <- lapply(paths, read_profiles)
  # Never union distinct model/condition-specific sets: the scale must have one
  # consistent set of IDs and demographics across all matching source files.
  for (j in seq_along(copies)) {
    if (!identical(copies[[1]], copies[[j]]))
      stop('Different persona sets for ', names(scales)[i], ': ', paths[1], ' versus ', paths[j])
  }
  d <- copies[[1]]; n <- nrow(d)
  if (n != 1000L) warning(names(scales)[i], ' has ', n, ' unique persona IDs; expected 1000.')
  if (n < 2L) stop('At least two personas required to report age SD.')
  rows[[i]] <- data.frame(
    'Scale' = names(scales)[i], 'N personas' = n,
    'Female (%)' = 100 * mean(d$gender == 'Female'),
    'Male (%)' = 100 * mean(d$gender == 'Male'),
    'Age mean' = mean(d$age), 'Age SD' = sd(d$age),
    'Age minimum' = min(d$age), 'Age maximum' = max(d$age),
    'UK (%)' = 100 * mean(d$country == 'UK'),
    'USA (%)' = 100 * mean(d$country == 'USA'),
    'Other countries (%)' = 100 * mean(!d$country %in% c('UK', 'USA')),
    check.names = FALSE, stringsAsFactors = FALSE)
  sources[[i]] <- paths
  cat('  Unique personas: ', n, '; source files: ', length(paths),
      if (length(paths) > 1L) ' (consistent duplicate copies)' else ' (no duplicate copies)', '\n', sep = '')
}
summary <- do.call(rbind, rows)
stopifnot(nrow(summary) == 7L,
          all(abs(summary[['Female (%)']] + summary[['Male (%)']] - 100) < 1e-10),
          all(abs(summary[['UK (%)']] + summary[['USA (%)']] + summary[['Other countries (%)']] - 100) < 1e-10))
output <- file.path(root, 'tables', 'synthetic_persona_demographics.csv')
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
# Serialize numeric values with 17 significant digits for double round-trip
# precision; do not apply manuscript rounding. SD uses the sample denominator n-1.
csv <- summary
csv[-1] <- lapply(csv[-1], function(x) sprintf('%.17g', x))
write.table(csv, output, sep = ',', row.names = FALSE, col.names = TRUE,
            quote = 1L, fileEncoding = 'UTF-8', na = '')
cat('\nSaved: ', output, '\nAll seven scales found. Counts: ',
    paste(summary$Scale, summary[['N personas']], sep = '=', collapse = '; '), '\n', sep = '')
print(summary, row.names = FALSE)
