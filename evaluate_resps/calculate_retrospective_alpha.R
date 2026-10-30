#!/usr/bin/env Rscript
# Retrospective only: reads committed selections; never samples responses or fits IRT.
# Raw (unstandardised) alpha = k/(k-1) * (1 - sum(item variances)/variance(total)).
# Missingness follows the original validity analysis, not pairwise covariance.

alpha_script_dir <- local({
  arg <- grep('^--file=', commandArgs(FALSE), value = TRUE)
  if (length(arg)) dirname(normalizePath(sub('^--file=', '', arg[1]))) else normalizePath('evaluate_resps')
})
alpha_root <- normalizePath(file.path(alpha_script_dir, '..'))
alpha_common <- new.env(parent = globalenv())
sys.source(file.path(alpha_script_dir, 'monte_carlo_study1.R'), alpha_common)
alpha_work <- new.env(parent = globalenv())
alpha_work$repo_root <- alpha_root
sys.source(file.path(alpha_script_dir, 'study2b_helpers.R'), alpha_work)
ALPHA_VERSION <- 'retrospective_raw_alpha_v1'
FACET_VERSION <- 'ipip_neo_facet_coverage_v1'

# The repository's IPIP import uses this BIFF reader for the authoritative item
# key. Reuse its Full# ordering and read Key directly; item-code suffixes alone
# are never treated as facet assignments.
read_ipip_facet_map <- function() {
  py <- Sys.which('python3')
  if (!nzchar(py)) stop('python3 is required to read IPIP-NEO-ItemKey.xls with the repository BIFF reader.')
  module <- file.path(alpha_root, 'data/human_data_details/ipip/build_human_response_splits.py')
  code <- paste(
    'import importlib.util, struct, sys; sys.dont_write_bytecode=True',
    sprintf("spec=importlib.util.spec_from_file_location('ipip_key', %s)", shQuote(module)),
    'm=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)',
    'p=m.IPIP_ITEM_KEY_PATH; stream=m._read_ole_stream(p, "Workbook"); sst=m._read_biff_sst(stream)',
    'offsets=[struct.unpack_from("<I", payload, 0)[0] for op,payload in m._read_biff_records(stream) if op==0x0085]',
    'found={}',
    'for off in offsets:',
    ' rows={}',
    ' for op,payload in m._read_biff_records(stream[off:]):',
    '  if op==0x000A: break',
    '  if op==0x0203: r,c=struct.unpack_from("<HH",payload,0); v=struct.unpack_from("<d",payload,6)[0]',
    '  elif op==0x027E: r,c=struct.unpack_from("<HH",payload,0); v=m._decode_biff_rk(struct.unpack_from("<I",payload,6)[0])',
    '  elif op==0x00BD:',
    '   r,c0=struct.unpack_from("<HH",payload,0); c1=struct.unpack_from("<H",payload,len(payload)-2)[0]',
    '   for j in range(c1-c0+1): rows.setdefault(r,{})[c0+j]=m._decode_biff_rk(struct.unpack_from("<I",payload,6+j*6)[0])',
    '   continue',
    '  elif op==0x00FD: r,c=struct.unpack_from("<HH",payload,0); v=sst[struct.unpack_from("<I",payload,6)[0]]',
    '  elif op==0x0204: r,c=struct.unpack_from("<HH",payload,0); v=payload[8:].decode("latin1",errors="replace")',
    '  else: continue',
    '  rows.setdefault(r,{})[c]=v',
    ' header=next((r for r,cells in sorted(rows.items()) if "Key" in [str(x).strip() for x in cells.values()] and "Full#" in [str(x).strip() for x in cells.values()]),None)',
    ' if header is None: continue',
    ' cells=rows[header]; kc=next(c for c,v in cells.items() if str(v).strip()=="Key"); nc=next(c for c,v in cells.items() if str(v).strip()=="Full#")',
    ' for r,cells in rows.items():',
    '  if r<=header or kc not in cells or nc not in cells: continue',
    '  try: num=int(cells[nc])',
    '  except (TypeError,ValueError): continue',
    '  key=str(cells[kc]).strip().upper()',
    '  if key and 1<=num<=300: found.setdefault(num,set()).add(key)',
    ' if found: break',
    'for num,keys in sorted(found.items()): print(str(num)+"\\t"+";".join(sorted(keys)))',
    sep='\n')
  output <- system2(py, c('-c', shQuote(code)), stdout=TRUE, stderr=TRUE)
  status <- attr(output, 'status')
  if (!is.null(status) && status != 0L) stop(paste('Could not parse IPIP item key:', paste(output, collapse=' ')))
  lines <- output[grepl('^[0-9]+\\t', output)]
  if (!length(lines)) stop('IPIP item key parser returned no item mappings.')
  fields <- strsplit(lines, '\\t', fixed=FALSE)
  nums <- as.integer(vapply(fields, `[`, character(1), 1L))
  keys <- vapply(fields, `[`, character(1), 2L)
  if (anyDuplicated(nums) || any(nums < 1L | nums > 300L)) stop('IPIP item key has duplicate or out-of-range Full# mappings.')
  list(key=setNames(keys, nums), path=file.path(alpha_root,'data/human_data_details/ipip/IPIP-NEO-ItemKey.xls'))
}

FACET_DOMAINS <- c(Extraversion='E', Openness='O', Neuroticism='N', Agreeableness='A', Conscientiousness='C')
FACET_PREFIXES <- c(Extraversion='EXT', Openness='OPN', Neuroticism='NEU', Agreeableness='AGR', Conscientiousness='CON')

facet_item_map <- function(scale, meta, key_map) {
  domain <- unname(FACET_DOMAINS[[scale]])
  if (is.null(domain) || nrow(meta)!=64L) stop(sprintf('Cannot establish 64-item IPIP ID ordering for %s.', scale))
  # The existing import selects the 60 domain items in Full# order, followed
  # by four nuisance items; this validates that exact ordering before use.
  domain_numbers <- sort(as.integer(names(key_map$key)[vapply(key_map$key, function(k) grepl(paste0('^',domain,'[1-6]$'),k), logical(1))]))
  if (length(domain_numbers)!=60L || !identical(domain_numbers, sort(domain_numbers))) stop(sprintf('Expected 60 keyed %s items; mapping is incomplete.',scale))
  ids <- as.character(meta$item_code)
  if (anyDuplicated(ids) || length(ids)!=64L) stop(sprintf('Invalid item codes for %s.',scale))
  prefix <- unname(FACET_PREFIXES[[scale]])
  if (!all(ids[seq_len(60L)]==sprintf('%s%02d',prefix,seq_len(60L))) ||
      !all(grepl(sprintf('^%s6[1-4]_d[A-Z]$',prefix),ids[61:64]))) stop(sprintf('Unexpected target/nuisance item-code ordering for %s.',scale))
  out <- rep(NA_character_,length(ids)); names(out)<-ids
  for (i in seq_len(60L)) {
    id <- ids[[i]]
    key <- unname(key_map$key[as.character(domain_numbers[[i]])])
    expected <- sprintf('^%s%02d$',prefix,i)
    if (!grepl(expected,id) || length(key)!=1L || is.na(key) || !grepl(paste0('^',domain,'[1-6]$'),key)) stop(sprintf('Item-key/order mismatch for %s at position %d.',scale,i))
    out[[id]] <- key
  }
  # Nuisance codes are deliberately left unmapped, even when their underlying
  # IPIP item has a facet in another Big Five domain.
  out
}

facet_coverage <- function(selected, mapping) {
  unknown <- setdiff(selected, names(mapping))
  if (length(unknown)) stop(sprintf('Selected IDs missing from item metadata: %s',paste(unknown,collapse=';')))
  facets <- unique(na.omit(unname(mapping[selected])))
  list(value=as.integer(length(facets)), unmapped=paste(selected[is.na(mapping[selected])],collapse=';'))
}

alpha_hash <- function(x) digest::digest(x, algo = 'sha256', serialize = FALSE)
alpha_items <- function(x) alpha_common$split_recorded_items(x)
alpha_vector <- function(x) paste(as.integer(x), collapse = ';')
alpha_field <- function(x) {
  if (startsWith(x, '"')) {
    if (!endsWith(x, '"')) stop('Unterminated CSV field.')
    return(gsub('""', '"', substr(x, 2L, nchar(x)-1L), fixed = TRUE))
  }
  if (x == 'NA') NA_character_ else x
}

raw_alpha_cov <- function(s, n) {
  if (nrow(s) != 10L || ncol(s) != 10L) stop('Alpha requires the selected ten items.')
  zero <- if (n >= 2L) rownames(s)[is.finite(diag(s)) & diag(s) == 0] else character()
  total <- sum(s)
  value <- if (n >= 2L && all(is.finite(s)) && is.finite(total) && total > 0) {
    10/9 * (1 - sum(diag(s))/total)
  } else NA_real_
  list(alpha = value, zero_variance_items = paste(zero, collapse = ';'), total_variance = total,
       status = if (is.finite(value)) 'ok' else 'undefined',
       reason = if (n < 2L) 'Fewer than two complete evaluation respondents.' else if (!all(is.finite(s))) {
         'Nonfinite item covariance.'
       } else if (!is.finite(total) || total <= 0) 'Zero or invalid total-score variance.' else '')
}

empty_alpha_events <- function() data.frame(study=character(), scale=character(), repetition=integer(),
  method=character(), record_type=character(), items=character(), affected_n=integer(), reason=character())
alpha_event <- function(study, scale, rep=NA_integer_, method='', type, items='', n=NA_integer_, reason) {
  data.frame(study=study, scale=scale, repetition=rep, method=method, record_type=type,
    items=items, affected_n=n, reason=reason, stringsAsFactors=FALSE)
}

load_alpha_humans <- function(study, scale, folder, state) {
  meta_path <- file.path(alpha_root, 'scales_info', paste0(scale, '_info'), 'scale_items.csv')
  meta <- if (study == 'study1') alpha_common$read_item_meta(meta_path) else read.csv(meta_path, stringsAsFactors=FALSE)
  if (study != 'study1') meta$response_col <- meta$item_code
  human_path <- file.path(alpha_root, 'data', tolower(scale), 'human_responses',
    if (study == 'study2b') 'human_responses.csv' else 'human_test_responses.csv')
  human <- read.csv(human_path, stringsAsFactors=FALSE, check.names=FALSE,
    colClasses=if (study == 'study2b') c(participant_id='character') else NA)
  if (!all(meta$response_col %in% names(human))) stop('Missing expected human item columns.')
  original <- as.matrix(human[,meta$response_col,drop=FALSE]); storage.mode(original) <- 'numeric'
  colnames(original) <- meta$item_code
  events <- empty_alpha_events()
  if (study == 'study2b') {
    if (nrow(human) != 324L || anyNA(human$participant_id) || anyDuplicated(trimws(human$participant_id))) stop('Expected 324 unique human IDs.')
    original <- alpha_work$normalize_original_matrix(original, meta$item_code)
    reverse <- meta$item_code[meta$reverse_coded == 1L]
    if (!setequal(reverse, alpha_work$REVERSE_ITEMS[[scale]])) stop('Reverse-coding metadata disagrees with Study 2b.')
    mat <- alpha_work$reverse_code_and_dichotomise(original, reverse)
    independent <- original >= 4
    independent[,reverse] <- original[,reverse,drop=FALSE] <= 2
    if (!identical(unname(mat), unname(independent * 1))) stop('Independent binary coding check failed.')
    ids <- trimws(human$participant_id)
    vpath <- alpha_work$study2b_validity_path(scale)
    validity <- read.csv(vpath, stringsAsFactors=FALSE, colClasses=c(participant_id='character'))
    validity$participant_id <- trimws(validity$participant_id)
    if (anyNA(validity$participant_id) || anyDuplicated(validity$participant_id)) stop('Invalid convergent IDs.')
    target <- as.numeric(validity$sum_score[match(ids, validity$participant_id)])
    if (any(!is.finite(target))) stop('Unmatched or nonfinite convergent values.')
    signature <- strsplit(state$signature, ';', fixed=TRUE)[[1]]
    if (!identical(signature[1:3], unname(tools::md5sum(c(meta_path,human_path,vpath))))) stop('Human/metadata/convergent inputs changed since the simulation.')
    list(mat=mat, ids=ids, target=target, events=events, input_n=nrow(human), excluded_n=0L, coding='reverse_coded_binary')
  } else {
    # DAT300.doc: IPIP human responses are already reverse-scored. Do not reverse twice.
    normalised <- alpha_common$normalize_response_matrix(original)
    complete <- complete.cases(normalised)
    if (any(!complete)) events <- alpha_event(study,scale,type='human_row_exclusion', n=sum(!complete),
      reason='Rows with missing/out-of-range responses among all 64 items excluded, exactly as the original validity loader; no additional alpha deletion.')
    mat <- normalised[complete,,drop=FALSE]
    if (!nrow(mat)) stop('No complete human evaluation rows.')
    list(mat=mat, covariance=stats::cov(mat), events=events, input_n=nrow(human), excluded_n=sum(!complete), coding='already_keyed_1_to_5')
  }
}

# Reads only the committed immutable checkpoint. Never invokes recovery or updates state.
alpha_checkpoint <- function(folder, study) {
  state <- read.csv(file.path(folder,'monte_carlo_state.csv'), stringsAsFactors=FALSE)
  if (nrow(state)!=1L) stop('Invalid checkpoint state.')
  completed <- if (study=='study2a') state$completed else state$success_count
  if (length(completed)!=1L || !is.finite(completed) || completed<1 || completed!=floor(completed)) stop('No valid completed repetitions.')
  path <- file.path(folder,'monte_carlo_results.csv')
  if (!'results_bytes' %in% names(state) || file.info(path)$size != state$results_bytes) stop('Results differ from committed byte offset; resolve the simulation checkpoint before retrospective analysis.')
  list(state=state, completed=completed, path=path)
}

# Independently reconstruct every split BEFORE alpha, rather than trusting saved ID strings.
validate_alpha_splits <- function(data, state, completed, scale, ids) {
  if (!setequal(unique(data$repetition), seq_len(completed))) stop('Missing completed Study 2b repetitions.')
  if (anyDuplicated(paste(data$repetition,data$method))) stop('Duplicate Study 2b repetition/method.')
  splits <- vector('list',completed)
  scale_offset <- switch(scale, Work_conscientiousness=10000000, Work_honesty_humility=20000000, stop('Unknown scale.'))
  for (r in seq_len(completed)) {
    expected_seed <- as.integer(state$seed + scale_offset + (r-1)*100)
    rows <- data[data$repetition==r,,drop=FALSE]
    if (any(rows$split_seed!=expected_seed) || any(rows$seed!=state$seed+r-1L)) stop('Saved split/repetition seeds disagree with reconstruction.')
    partition <- alpha_work$with_study2b_seed(expected_seed, function() sample.int(324L))
    eval <- partition[225:324]; cal <- partition[1:224]
    if (any(rows$evaluation_ids != paste(ids[eval],collapse=';')) ||
        any(rows$calibration_ids != paste(ids[cal],collapse=';'))) stop(sprintf('Independent participant split check failed at repetition %d.',r))
    if (any(rows$eval_n!=100L)) stop('Unexpected evaluation size.')
    splits[[r]] <- eval
  }
  splits
}

calculate_alpha_scale <- function(study, scale, folder) {
  checkpoint <- alpha_checkpoint(folder,study); state <- checkpoint$state
  cat(sprintf('[%s %s] checking %d completed repetitions\n',study,scale,checkpoint$completed)); flush.console()
  human <- load_alpha_humans(study,scale,folder,state)
  coverage_map <- NULL
  if (study %in% c('study1','study2a')) {
    meta_path <- file.path(alpha_root,'scales_info',paste0(scale,'_info'),'scale_items.csv')
    coverage_map <- facet_item_map(scale,read.csv(meta_path,stringsAsFactors=FALSE),read_ipip_facet_map())
  }
  events <- human$events
  add_event <- function(...) events <<- rbind(events,alpha_event(study,scale,...))
  cache <- new.env(hash=TRUE,parent=emptyenv()); stage_seen <- new.env(hash=TRUE,parent=emptyenv())
  selections <- new.env(hash=TRUE,parent=emptyenv()); targets <- new.env(hash=TRUE,parent=emptyenv())
  rows <- list(); valid_keys <- character(); row_count <- 0L
  make_value <- function(selected, evaluation, cache_key, covariance=NULL) {
    if (!exists(cache_key,cache,inherits=FALSE)) {
      if (is.null(covariance)) covariance <- stats::cov(evaluation)
      value <- raw_alpha_cov(covariance,nrow(evaluation))
      sums <- rowSums(evaluation)
      value$score_hash <- alpha_hash(alpha_vector(sums))
      value$n <- length(sums)
      cache[[cache_key]] <- value
    }
    cache[[cache_key]]
  }
  # Every retained ordered score vector must equal the original validity input.
  verify_value <- function(record,value,target_hash) {
    if (record$scoring_method!='SUM_SCORE' || as.integer(record$eval_n)!=value$n) stop('Validity coding/count does not match alpha evaluation rows.')
    if (alpha_hash(record$eval_short_sum)!=value$score_hash || alpha_hash(record$eval_target_sum)!=target_hash) {
      stop(sprintf('Ordered human sum scores do not match saved validity vectors: repetition %s method %s.',record$repetition,record$method))
    }
  }
  append_value <- function(record,selected,value,cache_key) {
    rep <- as.integer(record$repetition); method <- record$method
    if (nzchar(value$zero_variance_items)) add_event(rep,method,type='zero_variance_item_retained',items=value$zero_variance_items,
      reason='Constant evaluation items retained in the original 10-item form; raw alpha uses k=10, with no replacement or automatic item deletion.')
    if (value$status!='ok') add_event(rep,method,type='alpha_failure',reason=value$reason)
    if (is.finite(value$alpha) && value$alpha<0) add_event(rep,method,type='negative_alpha',reason='Negative conventional alpha retained without truncation or automatic reverse-keying.')
    row <- data.frame(study=study,scale=scale,repetition=rep,method=method,
      selected_items=paste(selected,collapse=';'),alpha=value$alpha,status=value$status,
      eval_n=value$n,input_human_n=human$input_n,human_rows_excluded=human$excluded_n,
      completed_repetitions=checkpoint$completed,
      zero_variance_items=value$zero_variance_items,coding=human$coding,
      validity_vectors_verified=TRUE,split_ids_verified=study=='study2b', stringsAsFactors=FALSE)
    if (!is.null(coverage_map)) {
      coverage <- facet_coverage(selected,coverage_map)
      row$FACET_COVERAGE <- coverage$value
      if (nzchar(coverage$unmapped)) add_event(rep,method,type='facet_mapping_problem',items=coverage$unmapped,
        reason='Selected nuisance item has no facet in the target Big Five domain and was excluded from FACET_COVERAGE.')
    }
    rows[[length(rows)+1L]] <<- row
  }
  if (study=='study2b') {
    data <- read.csv(checkpoint$path,stringsAsFactors=FALSE,check.names=FALSE)
    splits <- validate_alpha_splits(data,state,checkpoint$completed,scale,human$ids)
    cat(sprintf('[%s %s] all %d reconstructed splits match saved evaluation/calibration IDs\n',study,scale,length(splits))); flush.console()
    for (i in seq_len(nrow(data))) {
      record <- as.list(data[i,]); rep <- as.integer(record$repetition)
      selected <- alpha_items(record$selected_items)
      if (length(selected)!=10L || !all(selected %in% colnames(human$mat)) || !all(selected %in% alpha_items(record$candidate_items))) stop('Invalid saved selection.')
      eval <- splits[[rep]]
      cache_key <- paste(rep,paste(sort(selected),collapse=';'),sep='/')
      value <- make_value(selected,human$mat[eval,sort(selected),drop=FALSE],cache_key)
      target_hash <- alpha_hash(alpha_vector(human$target[eval]))
      verify_value(record,value,target_hash)
      append_value(record,selected,value,cache_key)
    }
    row_count <- nrow(data)
  } else {
    con <- file(checkpoint$path,'rb'); on.exit(close(con),add=TRUE)
    header <- names(read.csv(text=readLines(con,n=1L),nrows=0L,check.names=FALSE))
    needed <- c('repetition','method','stage','selected_items','candidate_items','train_items','heldout_items','seed','attempt','eval_n','scoring_method','eval_short_sum','eval_target_sum')
    if (!all(needed %in% header)) stop('Missing selection/evaluation metadata.')
    repeat {
      lines <- readLines(con,n=16L,warn=FALSE)
      if (!length(lines)) break
      for (line in lines) {
        fields <- alpha_common$split_results_csv_line(line,length(header))
        record <- setNames(lapply(fields[match(needed,header)],alpha_field),needed)
        rep <- as.integer(record$repetition)
        if (!is.finite(rep) || rep<1 || rep>checkpoint$completed || as.integer(record$seed)!=state$seed+as.integer(record$attempt)-1L) stop('Results disagree with checkpoint repetition/seed.')
        key <- paste(rep,record$method,sep='/'); skey <- paste(key,record$stage,sep='/')
        if (exists(skey,stage_seen,inherits=FALSE)) stop('Duplicate repetition/method/stage.')
        stage_seen[[skey]] <- TRUE
        selected <- alpha_items(record$selected_items)
        if (length(selected)!=10L || !all(selected %in% colnames(human$mat)) || !all(selected %in% alpha_items(record$candidate_items))) stop('Invalid saved selection.')
        canonical <- paste(sort(selected),collapse=';')
        if (exists(key,selections,inherits=FALSE) && selections[[key]]!=canonical) stop('Selection differs across stage rows.')
        selections[[key]] <- canonical
        if (record$stage=='short_form_evaluation') {
          heldout <- alpha_items(record$heldout_items); train <- alpha_items(record$train_items)
          if (length(heldout)!=40L || length(train)!=20L || !setequal(c(heldout,train),colnames(human$mat)[1:60]) || length(intersect(heldout,selected))) stop('Invalid development/held-out item split.')
          tkey <- as.character(rep)
          if (exists(tkey,targets,inherits=FALSE)) {
            target <- targets[[tkey]]
            if (!setequal(target$items,heldout)) stop('Held-out targets differ by method.')
          } else {
            target <- list(items=heldout,hash=alpha_hash(alpha_vector(rowSums(human$mat[,heldout,drop=FALSE]))))
            targets[[tkey]] <- target
          }
          # Covariance makes repeated alpha calculations O(k^2); score verification
          # is calculated once per distinct form, with only a compact hash cached.
          if (!exists(canonical,cache,inherits=FALSE)) {
            value <- make_value(selected,human$mat[,sort(selected),drop=FALSE],canonical,
              human$covariance[sort(selected),sort(selected),drop=FALSE])
          } else value <- cache[[canonical]]
          verify_value(record,value,target$hash)
          append_value(record,selected,value,canonical)
          valid_keys <- c(valid_keys,key)
        }
        row_count <- row_count+1L
      }
      if (row_count %% 256L==0L) { cat(sprintf('[%s %s] streamed %d rows; %d forms verified, %d unique alpha calculations\n',study,scale,row_count,length(rows),length(ls(cache)))); flush.console() }
    }
    if (!setequal(ls(selections),valid_keys)) stop('A saved selection has no validity row; evaluation respondents cannot be established.')
    if (!setequal(unique(as.integer(vapply(rows,function(x)x$repetition,integer(1)))),seq_len(checkpoint$completed))) stop('Some committed repetitions have no recoverable selected forms.')
    for (key in valid_keys) for (stage in c('nuisance_screening','candidate_selection','short_form_evaluation')) {
      if (!exists(paste(key,stage,sep='/'),stage_seen,inherits=FALSE)) stop('Incomplete set of stage rows.')
    }
  }
  if (!length(rows)) stop('No selected forms recovered.')
  detail <- do.call(rbind,rows)
  if (anyDuplicated(paste(detail$repetition,detail$method))) stop('Duplicate alpha result keys.')
  cat(sprintf('[%s %s] verified %d forms from %d source rows; %d distinct alpha calculations\n',study,scale,nrow(detail),row_count,length(ls(cache)))); flush.console()
  list(detail=detail,events=events)
}

alpha_reports <- function(detail) {
  summaries <- list(); comparisons <- list()
  for (scale in unique(detail$scale)) {
    dat <- detail[detail$scale==scale,,drop=FALSE]; study <- unique(dat$study)
    for (method in unique(dat$method)) {
      z<-dat[dat$method==method,,drop=FALSE]; a<-z$alpha[is.finite(z$alpha)]
      summaries[[length(summaries)+1L]]<-data.frame(study=study,scale=scale,method=method,
        mean_alpha=if(length(a))mean(a) else NA_real_,sd_alpha=if(length(a)>1L)sd(a) else NA_real_,
        min_alpha=if(length(a))min(a) else NA_real_,max_alpha=if(length(a))max(a) else NA_real_,
        completed_repetitions=max(z$completed_repetitions),selected_repetitions=nrow(z),
        no_selected_form_repetitions=max(z$completed_repetitions)-nrow(z),
        successful_repetitions=length(a),undefined_repetitions=sum(!is.finite(z$alpha)),
        unique_selections=length(unique(vapply(z$selected_items,function(x)paste(sort(alpha_items(x)),collapse=';'),character(1)))),mean_eval_n=mean(z$eval_n))
      if ('FACET_COVERAGE' %in% names(z)) {
        summaries[[length(summaries)]]$mean_FACET_COVERAGE <- mean(z$FACET_COVERAGE)
        summaries[[length(summaries)]]$sd_FACET_COVERAGE <- if(nrow(z)>1L)sd(z$FACET_COVERAGE) else NA_real_
      }
    }
    dat$stage <- 'retrospective_reliability'
    benchmarks <- if(study=='study2b') c('human100','human224') else c('human100','human300','human1000','reference')
    methods <- if(study=='study2b') setdiff(unique(dat$method),'human224') else setdiff(unique(dat$method),benchmarks)
    family <- list()
    for(method in methods) for(benchmark in benchmarks) {
      if(method==benchmark || (study=='study2b' && method=='human100' && benchmark!='human224')) next
      paired <- alpha_common$paired_test_row(dat,'retrospective_reliability','alpha',method,benchmark)
      a<-dat[dat$method==method,c('repetition','alpha')]; b<-dat[dat$method==benchmark,c('repetition','alpha')]
      joined<-merge(a,b,by='repetition'); diff<-joined$alpha.x-joined$alpha.y; diff<-diff[is.finite(diff)]
      alpha_comparison<-data.frame(study=study,scale=scale,method=method,benchmark=benchmark,
        mean_diff=paired$mean_diff,ci_lower=paired$ci_lower,ci_upper=paired$ci_upper,
        valid_paired_repetitions=paired$valid_paired_repetitions,win_n=sum(diff>0),tie_n=sum(diff==0),
        win_pct=if(length(diff))100*mean(diff>0) else NA_real_,p_value=paired$p,p_holm=NA_real_,
        holm_family=if(method=='random10') 'random10' else if(study=='study2b' && method=='human100') 'human' else 'synthetic')
      if ('FACET_COVERAGE' %in% names(dat)) alpha_comparison$metric <- 'alpha'
      family[[length(family)+1L]]<-alpha_comparison
      if ('FACET_COVERAGE' %in% names(dat)) {
        cov_test <- alpha_common$paired_test_row(dat,'retrospective_reliability','FACET_COVERAGE',method,benchmark)
        ca<-dat[dat$method==method,c('repetition','FACET_COVERAGE')]; cb<-dat[dat$method==benchmark,c('repetition','FACET_COVERAGE')]
        cj<-merge(ca,cb,by='repetition'); cd<-cj$FACET_COVERAGE.x-cj$FACET_COVERAGE.y
        family[[length(family)+1L]]<-data.frame(study=study,scale=scale,method=method,benchmark=benchmark,
          mean_diff=cov_test$mean_diff,ci_lower=cov_test$ci_lower,ci_upper=cov_test$ci_upper,
          valid_paired_repetitions=cov_test$valid_paired_repetitions,win_n=sum(cd>0),tie_n=sum(cd==0),
          win_pct=if(length(cd))100*mean(cd>0) else NA_real_,p_value=cov_test$p,p_holm=NA_real_,
          holm_family=if(method=='random10') 'random10' else 'synthetic',metric='FACET_COVERAGE')
      }
    }
    if(length(family)) {
      f<-do.call(rbind,family)
      metrics<-if('metric' %in% names(f))unique(f$metric) else NA_character_
      for(metric_name in metrics) for(id in unique(f$holm_family)) {
        keep<-f$holm_family==id & is.finite(f$p_value)
        if(!is.na(metric_name)) keep<-keep & f$metric==metric_name
        f$p_holm[keep]<-p.adjust(f$p_value[keep],method='holm')
      }
      comparisons[[length(comparisons)+1L]]<-f
    }
  }
  list(summary=do.call(rbind,summaries),comparisons=if(length(comparisons))do.call(rbind,comparisons) else data.frame())
}

# Small inputs are hashed. The 13 GB result file is guarded by byte count, mtime,
# immutable state hash and full ordered-vector verification, avoiding a second scan.
alpha_manifest <- function(study, folders) {
  paths <- c(file.path(alpha_script_dir,c('calculate_retrospective_alpha.R','monte_carlo_study1.R','monte_carlo_study2a.R','monte_carlo_study2b.R','study2b_helpers.R','ATA.R')),
    unlist(lapply(folders,function(f)file.path(f,c('monte_carlo_state.csv','monte_carlo_results.csv')))))
  for(scale in names(folders)) {
    paths <- c(paths,file.path(alpha_root,'scales_info',paste0(scale,'_info'),'scale_items.csv'),
      file.path(alpha_root,'data',tolower(scale),'human_responses',if(study=='study2b')'human_responses.csv' else 'human_test_responses.csv'))
    if(study=='study2b') paths<-c(paths,alpha_work$study2b_validity_path(scale))
  }
  if(study %in% c('study1','study2a')) paths<-c(paths,file.path(alpha_root,'data/human_data_details/ipip/IPIP-NEO-ItemKey.xls'))
  paths<-unique(paths); info<-file.info(paths)
  if(anyNA(info$size)) stop('Missing source input for retrospective analysis.')
  hash<-rep('',length(paths)); small<-basename(paths)!='monte_carlo_results.csv'
  hash[small]<-unname(tools::md5sum(paths[small]))
  version<-if(study %in% c('study1','study2a')) FACET_VERSION else ALPHA_VERSION
  data.frame(kind='source',path=normalizePath(paths),size=info$size,mtime=sprintf('%.6f',as.numeric(info$mtime)),md5=hash,version=version,stringsAsFactors=FALSE)
}

run_alpha_study <- function(study, root) {
  root<-normalizePath(root,mustWork=TRUE)
  scales<-switch(study,study1='Extraversion',study2a=c('Openness','Neuroticism','Agreeableness','Conscientiousness'),study2b=alpha_work$STUDY2B_SCALES,stop('Unknown study.'))
  folders<-setNames(if(study=='study1')root else file.path(root,scales),scales)
  sources<-alpha_manifest(study,folders)
  paths<-file.path(root,paste0('retrospective_alpha_',c('results','summary','comparisons','exclusions_and_failures','manifest'),'.csv'))
  names(paths)<-c('results','summary','comparisons','events','manifest')
  if(all(file.exists(paths))) {
    old<-read.csv(paths['manifest'],stringsAsFactors=FALSE,colClasses='character')
    current<-read.csv(text=paste(capture.output(write.csv(sources,row.names=FALSE)),collapse='\n'),colClasses='character')
    old_sources<-old[old$kind=='source',]; current_sources<-current
    if(study=='study2b') {
      irrelevant<-'/(calculate_retrospective_alpha|monte_carlo_study2a)[.]R$'
      keep_old<-!grepl(irrelevant,old_sources$path)
      keep_current<-!grepl(irrelevant,current_sources$path)
      old_sources<-old_sources[keep_old,,drop=FALSE]; current_sources<-current_sources[keep_current,,drop=FALSE]
      old_state<-grepl('/monte_carlo_state[.]csv$',old_sources$path)
      current_state<-grepl('/monte_carlo_state[.]csv$',current_sources$path)
      old_sources$mtime[old_state]<-''; current_sources$mtime[current_state]<-''
    }
    if(identical(old_sources,current_sources) &&
        isTRUE(all(old$md5[old$kind=='output']==unname(tools::md5sum(old$path[old$kind=='output']))))) {
      cat(sprintf('[%s] unchanged verified inputs and alpha files: skipped\n',study)); return(invisible(TRUE))
    }
  }
  results<-list(); events<-empty_alpha_events(); failed<-FALSE
  for(scale in scales) {
    result<-tryCatch(calculate_alpha_scale(study,scale,folders[[scale]]),error=function(e)e)
    if(inherits(result,'error')) {
      failed<-TRUE; events<-rbind(events,alpha_event(study,scale,type='portion_failure',reason=conditionMessage(result)))
      cat(sprintf('[%s %s] STOPPED portion: %s\n',study,scale,conditionMessage(result)))
    } else { results[[scale]]<-result$detail; events<-rbind(events,result$events) }
  }
  if(!identical(sources,alpha_manifest(study,folders))) stop('Source files changed during analysis; no alpha files published.')
  detail<-if(length(results))do.call(rbind,results) else data.frame(study=character(),scale=character(),repetition=integer(),method=character(),alpha=numeric())
  reports<-if(nrow(detail))alpha_reports(detail) else list(summary=data.frame(),comparisons=data.frame())
  tables<-list(results=detail,summary=reports$summary,comparisons=reports$comparisons,events=events)
  stage<-tempfile('.alpha-stage-',tmpdir=root); dir.create(stage); on.exit(unlink(stage,recursive=TRUE),add=TRUE)
  staged<-file.path(stage,basename(paths)); names(staged)<-names(paths)
  for(name in names(tables)) write.csv(tables[[name]],staged[name],row.names=FALSE,na='')
  output_manifest<-data.frame(kind='output',path=unname(paths[names(tables)]),size=file.info(staged[names(tables)])$size,mtime='',md5=unname(tools::md5sum(staged[names(tables)])),version=ALPHA_VERSION)
  manifest<-rbind(sources,output_manifest)
  # A failed portion must be retried, not treated as an unchanged successful run.
  if(failed) manifest$version<-'INCOMPLETE'
  write.csv(manifest,staged['manifest'],row.names=FALSE,na='')
  suspendInterrupts({for(name in names(paths)) if(!file.rename(staged[name],paths[name]))stop('Could not publish alpha files; rerun to regenerate the alpha outputs.')})
  cat(sprintf('[%s] published %d alpha rows; %d audit events in %s\n',study,nrow(detail),nrow(events),root)); flush.console()
  invisible(!failed)
}

retrospective_alpha_main <- function(args=commandArgs(TRUE)) {
  if(!requireNamespace('digest',quietly=TRUE)) stop('digest is required for efficient saved-vector verification.')
  if('--help' %in% args) {cat('Usage: Rscript evaluate_resps/calculate_retrospective_alpha.R [--study=study1|study2a|study2b] [--output-dir=PATH]\nWith no arguments, reads all three specified existing output directories.\n');return(invisible(NULL))}
  study_arg<-args[startsWith(args,'--study=')]; dir_arg<-args[startsWith(args,'--output-dir=')]
  if(any(!startsWith(args,'--study=') & !startsWith(args,'--output-dir=')) || length(study_arg)>1L || length(dir_arg)>1L)stop('Unknown or duplicate argument; use --help.')
  studies<-if(length(study_arg))sub('^--study=','',study_arg) else c('study1','study2a','study2b')
  if(any(!studies %in% c('study1','study2a','study2b')) || (length(dir_arg) && length(studies)!=1L))stop('--output-dir requires exactly one --study.')
  defaults<-c(study1='monte_carlo_study1_output',study2a='monte_carlo_study2a_output',study2b='monte_carlo_study2b_output')
  status<-logical()
  for(study in studies) {
    path<-if(length(dir_arg))sub('^--output-dir=','',dir_arg) else file.path(alpha_script_dir,defaults[[study]])
    status<-c(status,isTRUE(run_alpha_study(study,path)))
  }
  invisible(status)
}
if(sys.nframe()==0L) {
  status <- retrospective_alpha_main()
  if(length(status) && any(!status)) quit(status=1L)
}
