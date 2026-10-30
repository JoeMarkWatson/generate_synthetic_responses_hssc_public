#!/usr/bin/env Rscript
# Retrospective full-bank diagnostics on all available workplace humans.
# Never sources/runs a Monte Carlo script or changes selection procedures.
# Run from any directory: Rscript /path/to/this/script.R
argv <- grep('^--file=', commandArgs(FALSE), value = TRUE)
if (length(argv) != 1L) stop('Run with Rscript.')
root <- normalizePath(file.path(dirname(sub('^--file=', '', argv)), '..'))
if (!requireNamespace('mirt', quietly = TRUE)) stop('mirt is required; no packages are installed automatically.')
outdir <- file.path(root, 'tables', 'retrospective_workplace_item_bank_diagnostics')
scales <- c('Work_conscientiousness', 'Work_honesty_humility')
expected_items <- c(19L, 20L)
seed <- 20261028L
pa_repetitions <- 1000L
helpers <- new.env(parent = globalenv())
helpers$repo_root <- root
sys.source(file.path(root, 'evaluate_resps', 'study2b_helpers.R'), helpers)
flags <- read.csv(file.path(root, 'data/human_data_details/new_scales/new_scales_potentially_weak_items.csv'),
                  fileEncoding = 'UTF-8-BOM', stringsAsFactors = FALSE)
notes <- c('RETROSPECTIVE FULL WORKPLACE ITEM-BANK DIAGNOSTICS',
  'All available humans (expected N=324); not a Monte Carlo calibration/evaluation split.',
  'All 19 WC and 20 WHH items, including researcher-flagged weak items, are retained.',
  'No automatic respondent deletion, item deletion, imputation, or category collapsing.',
  'Original frequencies use literal, unreversed response categories 1,2,3,4,5, including zeros.',
  'Main-study coding: reverse WC16-WC20 and WHH08 using 6-x, then code keyed 4/5=1 and 1/2/3=0.',
  '2PL: mirt one-factor model, EM, NCYCLES=5000; other estimation settings use installed mirt defaults.',
  'M2: explicit type="M2", calcNull=TRUE; fallback calcNull=FALSE only if null-model indices fail.',
  'S-X2: mirt itemfit, mincell=1, na.rm=FALSE; Holm correction separately within each full item bank.',
  'S-X2 may internally merge score groups for sparse expected cells; response categories/data are not recoded for this diagnostic.',
  'Parallel analysis: PCA eigenvalues of Pearson correlations; 1000 independent within-column permutations.',
  'Each null permutation preserves each item\'s category frequencies and removes cross-item association.',
  'Both original keyed 1-5 responses and keyed binary responses are examined. No polychoric/tetrachoric correlations are used.',
  'Retention: leading consecutive observed eigenvalues above their ordered null 95th percentiles (quantile type=7).',
  'Also report total eigenvalues above threshold, in case of nonconsecutive crossings; inspect the stored eigenvalue sequences.',
  'PCA-based parallel analysis is a dimensionality screen, not a formal proof of unidimensional latent-factor structure.',
  'Pearson correlations may be affected by ordinal/binary scaling and skew; ordinal-factor analyses could differ.',
  'No universal fit-index cutoff is used to declare an item or bank acceptable. Interpret global and item diagnostics jointly.',
  paste('R:', R.version.string), paste('mirt:', as.character(utils::packageVersion('mirt'))),
  paste('RNG seed:', seed), paste('RNGkind:', paste(RNGkind(), collapse=', ')))
record <- function(message) { notes <<- c(notes, message); cat(message, '\n') }
attempt <- function(label, expr) {
  warnings <- character()
  value <- tryCatch(withCallingHandlers(expr, warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w)); invokeRestart('muffleWarning')
  }), error = function(e) e)
  for (w in unique(warnings)) record(paste(label, 'WARNING:', w))
  error <- if (inherits(value, 'error')) conditionMessage(value) else ''
  if (nzchar(error)) { record(paste(label, 'UNAVAILABLE:', error)); value <- NULL }
  list(value=value, error=error, warnings=paste(unique(warnings), collapse=' | '))
}
encode <- function(x) paste(sprintf('%.17g', x), collapse=';')
pa <- function(x, rng_seed) {
  if (anyNA(x) || any(!is.finite(x))) stop('PA not run: missing/nonfinite values; no rows removed.')
  if (any(apply(x,2,sd)==0)) stop('PA not run: constant item; no items removed.')
  set.seed(rng_seed)
  observed <- eigen(cor(x), symmetric=TRUE, only.values=TRUE)$values
  null <- replicate(pa_repetitions, {
    permuted <- apply(x, 2, function(v) v[sample.int(length(v))])
    eigen(cor(permuted), symmetric=TRUE, only.values=TRUE)$values
  })
  threshold <- apply(null, 1, quantile, probs=.95, names=FALSE, type=7)
  exceeds <- observed > threshold
  leading <- if (all(exceeds)) length(exceeds) else which(!exceeds)[1]-1L
  list(leading=leading, total=sum(exceeds), eigenvalues=observed, null95=threshold)
}
extract_one <- function(x, candidates) {
  key <- intersect(candidates, names(x))
  if (!length(key)) return(NA_real_)
  as.numeric(x[[key[1]]][1])
}
summary_rows <- item_rows <- frequency_rows <- list()
for (i in seq_along(scales)) {
  scale <- scales[i]
  record(paste('\nSCALE:', scale))
  metadata_path <- file.path(root,'scales_info',paste0(scale,'_info'),'scale_items.csv')
  input_path <- file.path(root,'data',tolower(scale),'human_responses','human_responses.csv')
  meta <- read.csv(metadata_path,stringsAsFactors=FALSE)
  human <- read.csv(input_path,stringsAsFactors=FALSE,check.names=FALSE,colClasses=c(participant_id='character'))
  if (nrow(meta)!=expected_items[i] || anyDuplicated(meta$item_code) || !all(meta$item_code %in% names(human)))
    stop('Unexpected item bank/schema; no data were dropped: ',scale)
  if (nrow(human)!=324L || anyNA(human$participant_id) || any(!nzchar(trimws(human$participant_id))) || anyDuplicated(human$participant_id))
    stop('Expected 324 unique participant IDs: ',scale)
  reverse <- meta$item_code[meta$reverse_coded==1L]
  if (!setequal(reverse, helpers$REVERSE_ITEMS[[scale]])) stop('Reverse coding differs from main study: ',scale)
  weak <- helpers$workplace_weak_items(flags,meta,scale)
  original <- as.matrix(human[meta$item_code]); storage.mode(original) <- 'numeric'
  missing <- sum(is.na(original)); invalid <- sum(!is.na(original)&!(original%in%1:5))
  record(sprintf('Input: %s; MD5: %s',input_path,unname(tools::md5sum(input_path))))
  record(sprintf('N=%d; items=%d; missing cells=%d; invalid cells=%d; respondents/items removed=0/0.',nrow(human),ncol(original),missing,invalid))
  record(paste('Flagged weak items retained:',paste(weak,collapse=', ')))
  for (j in seq_len(ncol(original))) {
    x <- original[,j]; counts <- vapply(1:5,function(k)sum(x==k,na.rm=TRUE),integer(1))
    frequency_rows[[length(frequency_rows)+1L]] <- data.frame(scale=scale,item=colnames(original)[j],
      reverse_keyed=colnames(original)[j]%in%reverse,potentially_weak=colnames(original)[j]%in%weak,
      category=1:5,count=counts,percent_of_all_respondents=100*counts/nrow(human),
      n_respondents=nrow(human),n_missing=sum(is.na(x)),n_invalid=sum(!is.na(x)&!(x%in%1:5)))
    if (any(counts==0)) record(paste('Zero-count original categories:',colnames(original)[j],paste(which(counts==0),collapse=',')))
  }
  items <- data.frame(scale=scale,item=meta$item_code,reverse_keyed=meta$item_code%in%reverse,
    potentially_weak=meta$item_code%in%weak,n_respondents=nrow(human),
    binary_n0=NA_integer_,binary_n1=NA_integer_,S_X2=NA_real_,df_S_X2=NA_real_,
    p_S_X2=NA_real_,p_holm=NA_real_,status='not_run',diagnostic_warnings='',stringsAsFactors=FALSE)
  result <- data.frame(scale=scale,analysis='Retrospective full item bank; all available human respondents',
    n_respondents=nrow(human),n_items=ncol(original),n_missing=missing,n_invalid=invalid,
    respondents_removed=0L,items_removed=0L,category_collapsing='None; deliberate main-study dichotomisation only',
    pa_method='Pearson PCA; within-item permutations; ordered null 95th percentiles',pa_repetitions=pa_repetitions,
    pa_original_seed=seed+i*10L,pa_binary_seed=seed+i*10L+1L,
    pa_original_leading=NA_integer_,pa_original_total_exceedances=NA_integer_,
    pa_original_eigenvalues='',pa_original_null95='',pa_original_status='not_run',
    pa_binary_leading=NA_integer_,pa_binary_total_exceedances=NA_integer_,
    pa_binary_eigenvalues='',pa_binary_null95='',pa_binary_status='not_run',
    irt_seed=seed+i*10L+2L,irt_converged=NA,irt_em_iterations=NA_integer_,irt_status='not_run',
    M2=NA_real_,df=NA_real_,p=NA_real_,RMSEA=NA_real_,SRMSR=NA_real_,CFI=NA_real_,TLI=NA_real_,
    global_fit_status='not_run',item_fit_status='not_run',item_fit_holm_family_n=NA_integer_,
    item_fit_holm_significant_n=NA_integer_,warnings='',stringsAsFactors=FALSE)
  if (missing || invalid) {
    record('Coding, PA and IRT unavailable: invalid/missing responses; no deletion or imputation permitted.')
    result$irt_status <- result$global_fit_status <- result$item_fit_status <- 'Unavailable: missing/invalid data; none dropped'
    result$pa_original_status <- result$pa_binary_status <- result$irt_status
  } else {
    keyed <- original;keyed[,reverse] <- 6-keyed[,reverse,drop=FALSE]
    binary <- helpers$reverse_code_and_dichotomise(original,reverse)
    stopifnot(identical(unname(binary),unname(1*(keyed>=4))))
    items$binary_n0 <- colSums(binary==0);items$binary_n1 <- colSums(binary==1)
    for (coding in c('original','binary')) {
      label <- paste(scale,'PA',coding)
      pr <- attempt(label,pa(if(coding=='original')keyed else binary,
                            result[[paste0('pa_',coding,'_seed')]]))
      result[[paste0('pa_',coding,'_status')]] <- if(is.null(pr$value))pr$error else 'ok'
      if (!is.null(pr$value)) {
        result[[paste0('pa_',coding,'_leading')]] <- pr$value$leading
        result[[paste0('pa_',coding,'_total_exceedances')]] <- pr$value$total
        result[[paste0('pa_',coding,'_eigenvalues')]] <- encode(pr$value$eigenvalues)
        result[[paste0('pa_',coding,'_null95')]] <- encode(pr$value$null95)
        record(sprintf('%s: %d leading components exceed 95th percentile (%d total exceedances).',label,pr$value$leading,pr$value$total))
      }
    }
    constants <- colnames(binary)[apply(binary,2,sd)==0]
    fit <- if(length(constants))list(value=NULL,error=paste('Constant binary items retained; fitting not attempted:',paste(constants,collapse=',')),warnings='') else {
      set.seed(result$irt_seed);attempt(paste(scale,'2PL fit'),helpers$fit_2pl(binary))
    }
    result$warnings <- fit$warnings
    if (is.null(fit$value)) {
      result$irt_status <- result$global_fit_status <- result$item_fit_status <- fit$error
      items$status <- fit$error;record(paste('2PL unavailable:',fit$error))
    } else {
      model <- fit$value
      result$irt_converged <- isTRUE(model@OptimInfo$converged)
      result$irt_em_iterations <- if(length(model@OptimInfo$iter))model@OptimInfo$iter else NA_integer_
      result$irt_status <- if(result$irt_converged)'ok' else 'NONCONVERGED; fit indices not computed'
      record(sprintf('2PL converged=%s; EM iterations=%s.',result$irt_converged,result$irt_em_iterations))
      if (!result$irt_converged) {
        result$global_fit_status <- result$item_fit_status <- items$status <- result$irt_status
      } else {
        global <- attempt(paste(scale,'M2 with null indices'),mirt::M2(model,type='M2',calcNull=TRUE))
        if (is.null(global$value)) {
          global <- attempt(paste(scale,'M2 without null indices'),mirt::M2(model,type='M2',calcNull=FALSE))
          record('CFI/TLI may be unavailable: null-model calculation failed; unadjusted M2 fallback attempted.')
        }
        result$global_fit_status <- if(is.null(global$value))global$error else 'ok'
        if (!is.null(global$value)) for (field in c('M2','df','p','RMSEA','SRMSR','CFI','TLI')) {
          result[[field]] <- extract_one(global$value,field)
          if (!is.finite(result[[field]])) record(paste('Global diagnostic unavailable:',field))
        }
        sx <- attempt(paste(scale,'S-X2'),mirt::itemfit(model,fit_stats='S_X2',mincell=1,na.rm=FALSE,p.adjust='none'))
        result$item_fit_status <- if(is.null(sx$value))sx$error else 'ok'
        if (!is.null(sx$value)) {
          fit_rows <- match(items$item,sx$value$item)
          if (anyNA(fit_rows)) record('Some requested items are absent from S-X2 output; retained as NA.')
          source_fields <- c(S_X2='S_X2',df_S_X2='df.S_X2',p_S_X2='p.S_X2')
          for (field in names(source_fields)) {
            source_field <- source_fields[[field]]
            if (source_field%in%names(sx$value))items[[field]] <- sx$value[[source_field]][fit_rows]
            else record(paste('S-X2 output column unavailable:',source_field))
          }
          valid <- is.finite(items$p_S_X2)&items$p_S_X2>=0&items$p_S_X2<=1
          # Keep the prespecified full-bank multiplicity family even if a
          # diagnostic is unavailable for some items (p.adjust n=all items).
          items$p_holm[valid] <- p.adjust(items$p_S_X2[valid],method='holm',n=nrow(items))
          items$status <- ifelse(valid,'ok','S-X2 unavailable/nonfinite')
          items$diagnostic_warnings <- sx$warnings
          result$item_fit_holm_family_n <- nrow(items)
          result$item_fit_holm_significant_n <- if(any(valid)) sum(items$p_holm<.05,na.rm=TRUE) else NA_integer_
          if(any(!valid))record(paste('S-X2 unavailable for:',paste(items$item[!valid],collapse=', ')))
          record(sprintf('Holm-significant item misfit: %d/%d; finite item p-values: %d.',result$item_fit_holm_significant_n,nrow(items),sum(valid)))
        } else items$status <- sx$error
      }
    }
  }
  if (any(c(result$pa_original_leading,result$pa_binary_leading)>1,na.rm=TRUE))
    record('Dimensionality caution: parallel analysis retains more than one component; the one-factor 2PL is a diagnostic of the main-study specification, not an endorsed final model.')
  if (any(items$p_holm<.05,na.rm=TRUE))
    record(paste('Holm-significant S-X2 items:',paste(items$item[which(items$p_holm<.05)],collapse=', ')))
  summary_rows[[i]] <- result;item_rows[[i]] <- items
}
summary <- do.call(rbind,summary_rows);items <- do.call(rbind,item_rows);frequencies <- do.call(rbind,frequency_rows)
stopifnot(nrow(items)==39L,nrow(frequencies)==195L,nrow(summary)==2L)
notes <- c(notes,'',capture.output(print(summary[c('scale','pa_original_leading','pa_binary_leading','irt_converged','M2','df','p','RMSEA','SRMSR','CFI','TLI','item_fit_holm_significant_n')],row.names=FALSE)),
  '', 'Session information:',capture.output(sessionInfo()))
dir.create(outdir,recursive=TRUE,showWarnings=FALSE)
paths <- file.path(outdir,c('dimensionality_global_fit.csv','item_fit.csv','original_category_frequencies.csv','diagnostic_report.txt'))
write.csv(summary,paths[1],row.names=FALSE,na='NA')
write.csv(items,paths[2],row.names=FALSE,na='NA')
write.csv(frequencies,paths[3],row.names=FALSE,na='NA')
writeLines(notes,paths[4],useBytes=TRUE)
cat('\nSaved:\n',paste(paths,collapse='\n'),'\n',sep='')
