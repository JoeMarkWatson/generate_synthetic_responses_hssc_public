build_item_info_matrix <- function(model_obj, theta_grid = seq(-2, 2, by = 0.1)) {
  theta_mat <- matrix(theta_grid, ncol = 1)
  n_items <- mirt::extract.mirt(model_obj, "nitems")
  item_names <- rownames(mirt::coef(model_obj, IRTpars = TRUE, simplify = TRUE)$items)
  if (is.null(item_names) || length(item_names) != n_items) {
    item_names <- paste0("item_", seq_len(n_items))
  }

  info_mat <- matrix(
    NA_real_,
    nrow = n_items,
    ncol = length(theta_grid),
    dimnames = list(item_names, paste0("theta_", seq_along(theta_grid)))
  )

  for (item_idx in seq_len(n_items)) {
    item_obj <- mirt::extract.item(model_obj, item_idx)
    info_mat[item_idx, ] <- as.numeric(mirt::iteminfo(item_obj, Theta = theta_mat))
  }

  info_mat
}

assemble_greedy_maximin_ata <- function(model_obj, n_select = 10, theta_grid = seq(-2, 2, by = 0.1)) {
  info_mat <- build_item_info_matrix(model_obj, theta_grid)
  item_ids <- rownames(info_mat)

  if (length(item_ids) < n_select) {
    stop(sprintf("ATA needs at least %d modeled items; found %d.", n_select, length(item_ids)))
  }

  selected_idx <- integer(0)
  remaining_idx <- seq_along(item_ids)
  running_info <- rep(0, length(theta_grid))
  eps <- 1e-12

  for (step in seq_len(n_select)) {
    best_idx <- NA_integer_
    best_min_info <- -Inf
    best_mean_info <- -Inf

    for (candidate_idx in remaining_idx) {
      candidate_info <- running_info + info_mat[candidate_idx, ]
      min_info <- min(candidate_info)
      mean_info <- mean(candidate_info)

      if (
        is.na(best_idx) ||
        min_info > (best_min_info + eps) ||
        (abs(min_info - best_min_info) <= eps && mean_info > (best_mean_info + eps))
      ) {
        best_idx <- candidate_idx
        best_min_info <- min_info
        best_mean_info <- mean_info
      }
    }

    selected_idx <- c(selected_idx, best_idx)
    remaining_idx <- setdiff(remaining_idx, best_idx)
    running_info <- running_info + info_mat[best_idx, ]
  }

  list(
    selected_items = item_ids[selected_idx],
    min_test_information = min(running_info),
    mean_test_information = mean(running_info),
    theta_grid = theta_grid
  )
}

assemble_maximin_ata <- function(model_obj, n_select = 10, theta_grid = seq(-2, 2, by = 0.1)) {
  info_mat <- build_item_info_matrix(model_obj, theta_grid)
  item_ids <- rownames(info_mat)

  if (length(item_ids) < n_select) {
    stop(sprintf("ATA needs at least %d modeled items; found %d.", n_select, length(item_ids)))
  }

  n_combinations <- choose(length(item_ids), n_select)
  if (!is.finite(n_combinations) || n_combinations <= 0) {
    stop("ATA maximin combination count is invalid.")
  }
  if (n_combinations > 5e6) {
    stop(sprintf(
      "ATA exhaustive maximin search too large: choose(%d, %d)=%.0f combinations.",
      length(item_ids), n_select, n_combinations
    ))
  }

  combo_idx <- utils::combn(seq_along(item_ids), n_select)
  best_combo_col <- NA_integer_
  best_min_info <- -Inf
  best_mean_info <- -Inf
  eps <- 1e-12

  for (combo_col in seq_len(ncol(combo_idx))) {
    idx <- combo_idx[, combo_col]
    test_info <- colSums(info_mat[idx, , drop = FALSE])
    min_info <- min(test_info)
    mean_info <- mean(test_info)

    if (
      is.na(best_combo_col) ||
      min_info > (best_min_info + eps) ||
      (abs(min_info - best_min_info) <= eps && mean_info > (best_mean_info + eps))
    ) {
      best_combo_col <- combo_col
      best_min_info <- min_info
      best_mean_info <- mean_info
    }
  }

  list(
    selected_items = item_ids[combo_idx[, best_combo_col]],
    min_test_information = best_min_info,
    mean_test_information = best_mean_info,
    theta_grid = theta_grid
  )
}
