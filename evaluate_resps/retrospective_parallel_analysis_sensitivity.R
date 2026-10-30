#!/usr/bin/env Rscript
# Standalone, package-free common-factor PA sensitivity check. No IRT fitting.
a <- grep('^--file=',commandArgs(FALSE),value=TRUE)
stopifnot(length(a)==1L)
root <- normalizePath(file.path(dirname(sub('^--file=','',a)),'..'))
out <- file.path(root,'tables','retrospective_parallel_analysis_sensitivity')
dir.create(out,recursive=TRUE,showWarnings=FALSE)
bigdir <- file.path(root,'tables','retrospective_big_five_item_bank_diagnostics')
workdir <- file.path(root,'tables','retrospective_workplace_item_bank_diagnostics')
big <- read.csv(file.path(bigdir,'dimensionality_global_fit.csv'),stringsAsFactors=FALSE)
work <- read.csv(file.path(workdir,'dimensionality_global_fit.csv'),stringsAsFactors=FALSE)
rows <- read.csv(file.path(bigdir,'diagnostic_sample_rows.csv'),stringsAsFactors=FALSE)
notes <- c('RETROSPECTIVE PARALLEL-ANALYSIS SENSITIVITY CHECK',
 'Exactly the saved 1000-person Big Five PA subsets; all 324 workplace respondents. No sampling of respondents.',
 'All 60 Big Five target items (no nuisance items), all 19/20 workplace items including flagged items. No deletion, imputation or new category collapsing.',
 'Common-factor PA uses the eigenvalues of a reduced Pearson correlation matrix: diagonal replaced by squared multiple correlations (SMC = 1 - 1/diag(solve(R))).',
 'This is SMC-based common-factor/principal-axis PA, NOT PCA, NOT minimum-residual fitting and NOT iterative principal-axis factor extraction.',
 'SMCs are estimated anew for each independently column-permuted null dataset, using the same estimator as the observed matrix. No correlation smoothing or SMC clipping.',
 'Original permutation seeds and counts are reused: 200 for Big Five; 1000 for workplace. Ordered null 95th percentiles, quantile type 7.',
 'Retention is the number of leading consecutive eigenvalues exceeding the thresholds. Total exceedances are separately recorded to expose later crossings.',
 'PCA is recomputed with the identical permutations solely to verify the exact sample/coding/RNG against saved results; old outputs remain untouched.',
 'Pearson correlations are used for both methods. Ordinal/polychoric and binary/tetrachoric PA are not run: psych/polycor are not installed; no packages installed.',
 'This is a bounded alternative common-factor sensitivity check, not an ordinal/minres replication. SMC choice and Pearson scaling can affect retention.',
 'Negative reduced-matrix eigenvalues are permitted and expected; they are not negative eigenvalues of the original correlation matrix.',
 '95th-percentile retention remains subject to finite-permutation Monte Carlo uncertainty; no additional seeds or respondent subsets are explored.',
 paste('psych available:',requireNamespace('psych',quietly=TRUE)),paste('polycor available:',requireNamespace('polycor',quietly=TRUE)))
log <- function(x){cat(x,'\n');notes<<-c(notes,x)}
leading <- function(x,q){above<-x>q;if(all(above))length(above)else which(!above)[1]-1L}
encode <- function(x)paste(sprintf('%.17g',x),collapse=';')
spectra <- function(x){
 r<-cor(x);ev<-eigen(r,symmetric=TRUE,only.values=TRUE)$values
 if(min(ev)<=1e-10)stop('Non-positive-definite/near-singular correlation matrix; no smoothing or item deletion.')
 smc<-1-1/diag(solve(r))
 if(any(!is.finite(smc))||any(smc< -1e-10|smc>1+1e-10))stop('Invalid SMC; none clipped.')
 diag(r)<-smc
 list(pca=ev,factor=eigen(r,symmetric=TRUE,only.values=TRUE)$values,smc=smc)
}
results<-details<-list()
run <- function(scale,coding,x,old,prefix){
 stopifnot(!anyNA(x),all(is.finite(x)),all(apply(x,2,sd)>0))
 reps<-old$pa_repetitions;seed<-old[[paste0(prefix,'seed')]]
 log(paste(scale,coding,'N=',nrow(x),'items=',ncol(x),'permutations=',reps))
 RNGkind('Mersenne-Twister','Inversion','Rejection');set.seed(seed)
 started<-proc.time()[['elapsed']];obs<-spectra(x)
 null<-array(NA_real_,c(ncol(x),2L,reps));warnings<-character()
 for(b in seq_len(reps)){
  p<-apply(x,2,function(v)v[sample.int(length(v))]);s<-spectra(p)
  null[,1,b]<-s$pca;null[,2,b]<-s$factor
 }
 qp<-apply(null[,1,,drop=FALSE],1,quantile,.95,names=FALSE,type=7)
 qf<-apply(null[,2,,drop=FALSE],1,quantile,.95,names=FALSE,type=7)
 oldev<-as.numeric(strsplit(old[[paste0(prefix,'eigenvalues')]],';',fixed=TRUE)[[1]])
 oldq<-as.numeric(strsplit(old[[paste0(prefix,'null95')]],';',fixed=TRUE)[[1]])
 error<-max(abs(c(obs$pca-oldev,qp-oldq)))
 if(!is.finite(error)||error>1e-10||leading(obs$pca,qp)!=old[[paste0(prefix,'leading')]])stop('Saved PCA reproduction failed: ',scale,' ',coding,' discrepancy=',error)
 nf<-leading(obs$factor,qf);total<-sum(obs$factor>qf)
 if(nf!=total)warnings<-c(warnings,'Nonconsecutive threshold crossings: inspect spectra; leading rule retained.')
 elapsed<-proc.time()[['elapsed']]-started
 results[[length(results)+1L]]<<-data.frame(scale=scale,response_coding=coding,n_respondents=nrow(x),n_items=ncol(x),correlation='Pearson',existing_PCA_components=old[[paste0(prefix,'leading')]],common_factors=nf,factor_method='SMC reduced-correlation eigenvalues',factor_total_exceedances=total,permutations=reps,permutation_seed=seed,PCA_reproduction_max_abs_error=error,SMC_min=min(obs$smc),SMC_max=max(obs$smc),ordinal_correlation_status='Not run: psych/polycor unavailable; no package installation',warnings=paste(warnings,collapse=' | '),elapsed_seconds=elapsed)
 details[[length(details)+1L]]<<-data.frame(scale=scale,response_coding=coding,order=seq_len(ncol(x)),PCA_eigenvalue=obs$pca,PCA_null95=qp,common_factor_eigenvalue=obs$factor,common_factor_null95=qf)
 log(sprintf('  Saved PCA reproduced (max error %.3g); PCA=%d; common factors=%d (total crossings=%d); %.1f s.',error,old[[paste0(prefix,'leading')]],nf,total,elapsed))
 if(length(warnings))log(paste('  WARNING:',paste(warnings,collapse=' | ')))
 write.csv(do.call(rbind,results),file.path(out,'parallel_analysis_comparison.csv'),row.names=FALSE,na='NA')
 write.csv(do.call(rbind,details),file.path(out,'parallel_analysis_eigenvalues.csv'),row.names=FALSE,na='NA')
 writeLines(c(notes,'',capture.output(sessionInfo())),file.path(out,'diagnostic_report.txt'))
}
for(scale in big$scale){
 old<-big[big$scale==scale,,drop=FALSE]
 input<-file.path(root,'data',tolower(scale),'human_responses','human_train_responses.csv')
 mp<-file.path(root,'scales_info',paste0(scale,'_info'),'scale_items.csv')
 ids<-read.csv(mp,stringsAsFactors=FALSE)$item_code[1:60]
 rr<-sort(rows$training_csv_row[rows$scale==scale & rows$used_in_parallel_analysis])
 cache<-readRDS(file.path(bigdir,'cache',paste0(scale,'_parallel_analysis.rds')))
 stopifnot(length(rr)==1000L,!anyDuplicated(rr),identical(as.integer(rr),as.integer(cache$key$pa_rows)),identical(unname(tools::md5sum(input)),cache$key$input_md5),identical(unname(tools::md5sum(mp)),cache$key$meta_md5))
 h<-names(read.csv(input,nrows=0));cc<-rep('NULL',length(h));stopifnot(all(ids%in%h));cc[match(ids,h)]<-'numeric'
 x<-as.matrix(read.csv(input,colClasses=cc,check.names=FALSE))[rr,ids,drop=FALSE]
 stopifnot(all(x%in%1:5))
 log(paste('Input:',input,'; exact PA rows from diagnostic_sample_rows.csv; input/metadata MD5 match saved cache.'))
 run(scale,'Original keyed 1-5',x,old,'pa_original_')
}
for(scale in work$scale){
 old<-work[work$scale==scale,,drop=FALSE]
 input<-file.path(root,'data',tolower(scale),'human_responses','human_responses.csv')
 meta<-read.csv(file.path(root,'scales_info',paste0(scale,'_info'),'scale_items.csv'),stringsAsFactors=FALSE)
 d<-read.csv(input,check.names=FALSE,colClasses=c(participant_id='character'))
 stopifnot(nrow(d)==324L,!anyDuplicated(d$participant_id),nrow(meta)==if(scale=='Work_conscientiousness')19L else 20L)
 x<-as.matrix(d[meta$item_code]);storage.mode(x)<-'numeric';stopifnot(!anyNA(x),all(x%in%1:5))
 reverse<-meta$item_code[meta$reverse_coded==1L];x[,reverse]<-6-x[,reverse,drop=FALSE]
 log(paste('Input:',input,'; all original 324 respondents.'))
 run(scale,'Original keyed 1-5',x,old,'pa_original_')
 run(scale,'Keyed binary: 4/5=1; 1/2/3=0',1*(x>=4),old,'pa_binary_')
}
stopifnot(length(results)==9L,length(unique(vapply(results,function(x)x$scale,'')))==7L)
log('All seven scales completed; all nine saved PCA analyses reproduced. No respondents/items removed; no IRT models fitted.')
writeLines(c(notes,'',capture.output(print(do.call(rbind,results)[c('scale','response_coding','existing_PCA_components','common_factors')],row.names=FALSE)),'',capture.output(sessionInfo())),file.path(out,'diagnostic_report.txt'))
cat('Outputs:',out,'\n')
