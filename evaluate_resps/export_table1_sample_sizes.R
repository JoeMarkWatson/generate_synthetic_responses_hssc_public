#!/usr/bin/env Rscript
# Table 1 from actual response CSVs; base R only. No fits or simulations.
# Run from any directory: Rscript /path/to/evaluate_resps/export_table1_sample_sizes.R
# No summary CSV, manuscript value, raw Monte Carlo result or RDS is read.
# IDs/demographics are not loaded. Workplace criterion rows must retain their
# original alignment with response rows, as stipulated for anonymised replacements.
argv <- grep('^--file=',commandArgs(FALSE),value=TRUE)
if(length(argv)!=1L)stop('Run using Rscript.')
root <- normalizePath(file.path(dirname(sub('^--file=','',argv)),'..'))

# Parse definitions, but evaluate ONLY explicitly requested data-only functions.
# Sourcing entire analysis scripts could require mirt or execute an analysis.
definition <- function(path,name) {
  expressions <- parse(file.path(root,path))
  hits <- Filter(function(e)is.call(e)&&identical(e[[1]],as.name('<-'))&&
    identical(e[[2]],as.name(name))&&is.call(e[[3]])&&
    identical(e[[3]][[1]],as.name('function')),as.list(expressions))
  if(length(hits)!=1L)stop('Expected one function definition: ',path,' / ',name)
  hits[[1]][[3]]
}
pure <- new.env(parent=globalenv())
for(name in c('read_item_meta','normalize_response_matrix','keep_complete_response_rows'))
  pure[[name]] <- eval(definition('evaluate_resps/monte_carlo_study1.R',name),pure)
pure$normalize_original_matrix <- eval(definition('evaluate_resps/study2b_helpers.R',
                                                 'normalize_original_matrix'),pure)
read_columns <- function(path,columns) {
  path <- file.path(root,path)
  header <- names(read.csv(path,nrows=0,check.names=FALSE))
  if(anyDuplicated(header)||anyDuplicated(columns)||!all(columns%in%header))
    stop('Missing/duplicate response fields: ',path)
  classes <- rep('NULL',length(header));classes[match(columns,header)] <- 'character'
  d <- read.csv(path,colClasses=classes,check.names=FALSE,stringsAsFactors=FALSE)
  as.matrix(d[,columns,drop=FALSE])
}
format_n <- function(x)format(x,big.mark=',',scientific=FALSE,trim=TRUE)

# Derive workplace allocation from the analysis's literal split expressions.
# A permutation changes membership, not N: use ordered indices without RNG calls.
# Only simple indexing/colon expressions are allowed; code changes fail explicitly.
workplace_partition <- function(n) {
  fun <- definition('evaluate_resps/monte_carlo_study2b.R','run_study2b_repetition')
  body <- as.list(fun[[3]])[-1L]
  assignment <- function(name) {
    hits<-Filter(function(e)is.call(e)&&identical(e[[1]],as.name('<-'))&&
                  identical(e[[2]],as.name(name)),body)
    if(length(hits)!=1L)stop('Cannot establish workplace split: ',name)
    hits[[1]][[3]]
  }
  find_calls <- function(e,name) {
    if(!is.call(e))return(list())
    found<-if(identical(e[[1]],as.name(name)))list(e)else list()
    for(child in as.list(e)[-1L])found<-c(found,find_calls(child,name))
    found
  }
  draws<-find_calls(assignment('partition'),'sample.int')
  if(length(draws)!=1L||length(draws[[1]])!=2L||!is.numeric(draws[[1]][[2]]))
    stop('Workplace partition code changed; review sample-size derivation.')
  if(n!=draws[[1]][[2]])stop('Human row count differs from the analysis split population.')
  simple <- function(e) {
    if(is.numeric(e))return(TRUE)
    if(is.symbol(e))return(identical(e,as.name('partition')))
    is.call(e)&&as.character(e[[1]])%in%c('[',':')&&
      all(vapply(as.list(e)[-1L],simple,logical(1)))
  }
  env<-list2env(list(partition=seq_len(n)),parent=baseenv())
  pick <- function(name) {
    e<-assignment(name)
    if(!simple(e))stop('Unsupported workplace split expression: ',name)
    eval(e,env)
  }
  cal<-pick('calibration');evaluation<-pick('evaluation')
  if(anyNA(c(cal,evaluation))||anyDuplicated(c(cal,evaluation))||
     !setequal(c(cal,evaluation),seq_len(n)))stop('Workplace split is not an exhaustive disjoint partition.')
  c(reference=length(cal),evaluation=length(evaluation))
}

big<-c('Extraversion','Openness','Neuroticism','Agreeableness','Conscientiousness')
work<-c('Work_conscientiousness','Work_honesty_humility')
rows<-list()
for(scale in c(big,work)) {
  message('Counting response rows: ',scale)
  meta_path<-file.path('scales_info',paste0(scale,'_info'),'scale_items.csv')
  meta<-if(scale=='Extraversion')pure$read_item_meta(file.path(root,meta_path))else
    read.csv(file.path(root,meta_path),stringsAsFactors=FALSE,check.names=FALSE)
  if(scale!='Extraversion')meta$response_col<-meta$item_code
  if(!all(c('item_code','response_col')%in%names(meta))||anyDuplicated(meta$item_code))stop('Invalid item metadata: ',scale)
  folder<-file.path('data',tolower(scale),'human_responses')
  if(scale%in%big) {
    if(nrow(meta)!=64L)stop('Expected all 60 target and four nuisance items: ',scale)
    count_big <- function(filename) {
      x<-read_columns(file.path(folder,filename),meta$response_col)
      available<-nrow(x)
      x<-pure$normalize_response_matrix(x)
      retained<-pure$keep_complete_response_rows(x)
      # All candidate/evaluation subsets remain complete after this global filter.
      if(anyNA(retained)||any(!is.finite(retained)))stop('Unexpected nonfinite retained responses.')
      c(available=available,retained=nrow(retained))
    }
    training<-count_big('human_train_responses.csv')
    invisible(gc())
    evaluation<-count_big('human_test_responses.csv')
    reference_n<-unname(training['retained']);evaluation_n<-unname(evaluation['retained'])
    available<-paste0(format_n(training['available']),' train; ',format_n(evaluation['available']),' evaluate')
    other<-'100, 300, 1,000' # Fixed smaller-calibration design settings only.
    panel<-'Panel A. Big Five-based unidimensional scales'
    label<-scale
    cat(sprintf('%s: available train=%d, evaluation=%d; retained reference=%d, evaluation=%d; excluded train=%d, evaluation=%d.\n',
      scale,training['available'],evaluation['available'],reference_n,evaluation_n,
      training['available']-reference_n,evaluation['available']-evaluation_n))
  } else {
    x<-read_columns(file.path(folder,'human_responses.csv'),meta$response_col)
    # Reuse Study 2b's strict validation: invalid/missing data cause failure,
    # never a silent change in the calibration/evaluation sample.
    x<-pure$normalize_original_matrix(x,meta$item_code)
    n<-nrow(x)
    criterion<-if(scale=='Work_conscientiousness')
      'work_conscientiousness_conv_crit/Conscientiousness_IPIP60.csv'else
      'work_honesty_humility_conv_crit/HH_Hexaco.csv'
    target<-read_columns(file.path('data/human_data_details/new_scales',criterion),'sum_score')
    target<-suppressWarnings(as.numeric(target))
    if(length(target)!=n||any(!is.finite(target)))stop('Criterion rows must align and have finite scores: ',scale)
    allocation<-workplace_partition(n)
    reference_n<-unname(allocation['reference']);evaluation_n<-unname(allocation['evaluation'])
    available<-paste(format_n(n),'total');other<-'100'
    panel<-'Panel B. Newly developed workplace scales'
    label<-if(scale=='Work_conscientiousness')'Work Conscientiousness'else'Work Honesty\u2013Humility'
    cat(sprintf('%s: available=%d; split reference=%d, evaluation=%d; invalid/missing responses=0; aligned finite criteria=%d.\n',
                label,n,reference_n,evaluation_n,length(target)))
  }
  if(reference_n<1L||evaluation_n<1L)stop('No eligible respondents: ',scale)
  rows[[scale]]<-data.frame(Panel=panel,Scale=label,'Human data available'=available,
    'Human-reference calibration N'=reference_n,'Other human calibration Ns'=other,
    'Human evaluation N'=evaluation_n,check.names=FALSE)
  invisible(gc())
}
result<-do.call(rbind,unname(rows))
stopifnot(nrow(result)==length(c(big,work)),!anyDuplicated(result$Scale),ncol(result)==6L)
output<-file.path(root,'tables/table1_sample_sizes.csv')
dir.create(dirname(output),recursive=TRUE,showWarnings=FALSE)
write.csv(result,output,row.names=FALSE,na='NA')
cat('All Ns calculated from response rows, analysis filtering functions and the parsed workplace split procedure.\n')
cat('Manuscript agreement must be checked independently; no manuscript or summary values are used by this script.\n')
cat('Output contains only scale/panel labels and aggregate Ns; no respondent records or identifiers.\n')
cat('Output: ',output,'\n',sep='')
