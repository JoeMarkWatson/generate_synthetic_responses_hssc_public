#!/usr/bin/env Rscript
# Full 60-target-item banks; no Monte Carlo simulations or selection procedures.
# Rscript evaluate_resps/retrospective_big_five_item_bank_diagnostics.R
# Optional: --scale=Extraversion (default: all five); completed stages are cached.
a <- grep('^--file=',commandArgs(FALSE),value=TRUE)
if(length(a)!=1L)stop('Run using Rscript.')
root <- normalizePath(file.path(dirname(sub('^--file=','',a)), '..'))
if(!requireNamespace('mirt',quietly=TRUE))stop('Installed mirt required; no packages installed automatically.')
scales <- c('Extraversion','Openness','Neuroticism','Agreeableness','Conscientiousness')
cli <- commandArgs(TRUE)
if(length(cli)) {
 if(length(cli)!=1L||!startsWith(cli,'--scale='))stop('Only --scale=ScaleName is supported.')
 selected <- sub('^--scale=','',cli)
 if(!selected%in%scales)stop('Unknown scale.')
} else selected <- scales
out <- file.path(root,'tables','retrospective_big_five_item_bank_diagnostics')
dir.create(file.path(out,'cache'),recursive=TRUE,showWarnings=FALSE)
base_seed <- 20261028L; sample_n <- 5000L; pa_sample_n <- 1000L; pa_reps <- 200L
notes <- c('RETROSPECTIVE BIG FIVE FULL TARGET-ITEM BANK DIAGNOSTICS',
 'Training data only. All 60 target items; all four nuisance items excluded before respondent eligibility checks.',
 'This is a fixed 5000-person diagnostic subsample, NOT the original full-human calibration reference.',
 'Zeros/out-of-range responses become missing; complete cases on 60 targets define eligibility. Counts are recorded; no imputation.',
 'Human IPIP responses are already keyed. No additional reverse coding or dichotomisation.',
 'All 60 items retained; no automated item deletion. Empty observed categories are recoded consecutively, as in main-study GRM preparation, and recorded.',
 'One-factor GRM: mirt, EM, NCYCLES=5000, other installed defaults; convergence checked explicitly.',
 'Global fit: polytomous C2, calcNull=TRUE; retry without null indices only after a genuine null/global error.',
 'Item fit: S-X2 mincell=1, na.rm=FALSE, no automatic response deletion. Holm family contains all 60 items within each scale.',
 'Parallel analysis uses a fixed 1000-person subset of the 5000-person GRM sample; original training CSV row indices and subset membership are saved.',
 'An initial 5000-person permutation-analysis attempt exceeded 120 seconds; the final 1000-person PA subset bounds runtime.',
 'Parallel analysis: Pearson PCA, 200 independent within-item permutations preserving marginal category frequencies; ordered 95th percentiles (quantile type 7).',
 'Leading consecutive eigenvalues above thresholds define retention; total exceedances and all eigenvalues are also saved.',
 'Departures from workplace diagnostics: 5000-person GRM subsamples (1000 for PA) rather than all 324; 200 rather than 1000 permutations; C2 rather than binary M2; original keyed ordinal responses only.',
 'Pearson PCA parallel analysis is a screen, not polychoric factor analysis or proof of latent dimensionality. Its 95th-percentile thresholds have simulation uncertainty.',
 'Large N increases fitting, correlation/permutation and diagnostic costs; no full-training-bank models are fitted.',
 'Time limits are R elapsed-time limits per stage (interruptible code), not guaranteed wall-clock caps inside native numerical routines.',
 'Limits: PA 120 s; GRM 180 s; C2 120 s; S-X2 120 s. Unavailable diagnostics are recorded, never replaced with favorable values.',
 'training_csv_row is the one-based data-row index, excluding the CSV header; used_in_parallel_analysis identifies the nested PA subset.',
 'Global p=0 means numerical underflow, not an exactly zero probability. Report p<.001; log-p values are also saved.',
 'These full-60-bank diagnostics do not directly establish fit of any individual Monte Carlo candidate pool or selected short form.',
 'Caches contain only this script\'s retrospective models/results, keyed by inputs, sample rows, settings and installed mirt version.',
 paste('R:',R.version.string),paste('mirt:',packageVersion('mirt')))
log <- function(x){notes<<-c(notes,x);cat(x,'\n')}
encode <- function(x)paste(sprintf('%.17g',x),collapse=';')
pa <- function(x,seed){
 set.seed(seed);ev<-eigen(cor(x),symmetric=TRUE,only.values=TRUE)$values
 sim<-replicate(pa_reps,{p<-apply(x,2,function(v)v[sample.int(length(v))]);eigen(cor(p),symmetric=TRUE,only.values=TRUE)$values})
 q<-apply(sim,1,quantile,.95,names=FALSE,type=7);above<-ev>q
 list(leading=if(all(above))length(above)else which(!above)[1]-1L,total=sum(above),ev=ev,q=q)
}
stage <- function(name,scale,key,seconds,code){
 path<-file.path(out,'cache',paste0(scale,'_',name,'.rds'))
 if(file.exists(path)){old<-readRDS(path);if(identical(old$key,key)){log(paste(scale,name,'reusing diagnostic cache'));if(nzchar(old$result$error))log(paste('Cached unavailable diagnostic:',old$result$error));if(nzchar(old$result$warnings))log(paste('Cached warnings:',old$result$warnings));return(old$result)}}
 warnings<-character();start<-proc.time()[['elapsed']]
 log(paste(scale,name,'starting; elapsed-time limit',seconds,'seconds'))
 setTimeLimit(cpu=Inf,elapsed=seconds,transient=TRUE)
 value<-tryCatch(withCallingHandlers(code,warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart('muffleWarning')}),error=function(e)e)
 setTimeLimit(cpu=Inf,elapsed=Inf,transient=FALSE)
 error<-if(inherits(value,'error'))conditionMessage(value)else''
 if(nzchar(error)){value<-NULL;log(paste(scale,name,'UNAVAILABLE:',error))}
 for(w in unique(warnings))log(paste(scale,name,'WARNING:',w))
 result<-list(value=value,error=error,warnings=paste(unique(warnings),collapse=' | '),seconds=proc.time()[['elapsed']]-start)
 saveRDS(list(key=key,result=result),path)
 log(paste(scale,name,'finished in',round(result$seconds,2),'seconds'))
 result
}
getnum <- function(x,n)if(!is.null(x)&&n%in%names(x))as.numeric(x[[n]][1])else NA_real_
# Self-contained schema matching workplace columns; no workplace output is needed.
workplace_template <- data.frame(scale=NA_character_,analysis=NA_character_,n_respondents=NA_integer_,n_items=NA_integer_,n_missing=NA_integer_,n_invalid=NA_integer_,respondents_removed=NA_integer_,items_removed=NA_integer_,category_collapsing=NA_character_,pa_method=NA_character_,pa_repetitions=NA_integer_,pa_original_seed=NA_integer_,pa_binary_seed=NA_integer_,pa_original_leading=NA_integer_,pa_original_total_exceedances=NA_integer_,pa_original_eigenvalues=NA_character_,pa_original_null95=NA_character_,pa_original_status=NA_character_,pa_binary_leading=NA_integer_,pa_binary_total_exceedances=NA_integer_,pa_binary_eigenvalues=NA_character_,pa_binary_null95=NA_character_,pa_binary_status=NA_character_,irt_seed=NA_integer_,irt_converged=NA,irt_em_iterations=NA_integer_,irt_status=NA_character_,M2=NA_real_,df=NA_real_,p=NA_real_,RMSEA=NA_real_,SRMSR=NA_real_,CFI=NA_real_,TLI=NA_real_,global_fit_status=NA_character_,item_fit_status=NA_character_,item_fit_holm_family_n=NA_integer_,item_fit_holm_significant_n=NA_integer_,warnings=NA_character_)
summary_rows<-item_rows<-freq_rows<-sample_rows<-list()
for(scale in selected){
 idx<-match(scale,scales);log(paste('\nSCALE:',scale))
 input<-file.path(root,'data',tolower(scale),'human_responses','human_train_responses.csv')
 mp<-file.path(root,'scales_info',paste0(scale,'_info'),'scale_items.csv')
 meta<-read.csv(mp,stringsAsFactors=FALSE);ids<-meta$item_code[1:60]
 if(nrow(meta)!=64L||anyDuplicated(ids)||any(grepl('_d[A-Z]$',ids)))stop('Unexpected target bank: ',scale)
 header<-names(read.csv(input,nrows=0));classes<-rep('NULL',length(header));classes[match(ids,header)]<-'numeric'
 if(anyNA(match(ids,header)))stop('Missing target columns.')
 original_all<-as.matrix(read.csv(input,colClasses=classes,check.names=FALSE));storage.mode(original_all)<-'numeric'
 original_all<-original_all[,ids,drop=FALSE]
 invalid<-!is.na(original_all)&!(original_all%in%1:5);n_invalid<-sum(invalid);n_missing<-sum(is.na(original_all))
 clean<-original_all;clean[invalid]<-NA_real_;eligible<-which(complete.cases(clean))
 if(length(eligible)<sample_n)stop('Fewer than 5000 eligible respondents; no silent smaller sample.')
 set.seed(base_seed+idx);rows<-sort(sample(eligible,sample_n,replace=FALSE));x<-clean[rows,,drop=FALSE]
 set.seed(base_seed+300L+idx);pa_positions<-sort(sample.int(sample_n,pa_sample_n))
 sample_rows[[scale]]<-data.frame(scale=scale,training_csv_row=rows,sampling_seed=base_seed+idx,used_in_parallel_analysis=seq_len(sample_n)%in%pa_positions,pa_subsampling_seed=base_seed+300L+idx)
 log(sprintf('Training N=%d; eligible on targets=%d; excluded for target missingness=%d; analysed=%d; input missing/invalid cells=%d/%d.',nrow(clean),length(eligible),nrow(clean)-length(eligible),nrow(x),n_missing,n_invalid))
 log(paste('Input:',input,'MD5:',unname(tools::md5sum(input))))
 result<-workplace_template[1,,drop=FALSE];result[1,]<-NA
 result$scale<-scale;result$analysis<-'Retrospective 5000-person diagnostic subsample; full 60-target bank'
 result$n_respondents<-nrow(x);result$n_items<-60L;result$n_missing<-0L;result$n_invalid<-0L
 result$respondents_removed<-nrow(clean)-length(eligible);result$items_removed<-0L
 result$training_input_n<-nrow(clean);result$training_eligible_n<-length(eligible)
 result$eligible_not_sampled_n<-length(eligible)-sample_n;result$training_missing_cells<-n_missing;result$training_invalid_cells<-n_invalid
 result$sampling_seed<-base_seed+idx;result$pa_repetitions<-pa_reps;result$pa_method<-'Pearson PCA; within-item permutations; ordered null 95th percentiles'
 result$pa_n_respondents<-pa_sample_n;result$pa_subsampling_seed<-base_seed+300L+idx
 result$pa_original_seed<-base_seed+100L+idx;result$pa_binary_status<-'Not applicable: GRM uses original ordinal responses'
 result$irt_seed<-base_seed+200L+idx;result$global_fit_statistic<-'C2';result$M2<-NA_real_;result$C2<-NA_real_
 result$global_fit_status<-result$item_fit_status<-result$irt_status<-'not_run';result$warnings<-''
 result$category_collapsing<-'None'
 counts<-sapply(1:5,function(k)colSums(x==k));colnames(counts)<-as.character(1:5)
 constant<-ids[apply(x,2,sd)==0]
 collapsed<-x;changed<-character()
 for(j in 1:60){present<-which(counts[j,]>0);if(length(present)<5){changed<-c(changed,paste0(ids[j],': observed ',paste(present,collapse=',')));collapsed[,j]<-match(x[,j],present)}}
 if(length(changed)){result$category_collapsing<-paste(changed,collapse='; ');log(paste('GRM observed-category recoding:',result$category_collapsing))}
 freq_rows[[scale]]<-do.call(rbind,lapply(1:60,function(j)data.frame(scale=scale,item=ids[j],reverse_keyed=as.logical(meta$reverse_coded[j]),potentially_weak=FALSE,category=1:5,count=counts[j,],percent_of_all_respondents=100*counts[j,]/sample_n,n_respondents=sample_n,n_missing=0L,n_invalid=0L,response_coding='Already keyed IPIP categories; diagnostic subsample')))
 items<-data.frame(scale=scale,item=ids,reverse_keyed=as.logical(meta$reverse_coded[1:60]),potentially_weak=FALSE,n_respondents=sample_n,binary_n0=NA_integer_,binary_n1=NA_integer_,S_X2=NA_real_,df_S_X2=NA_real_,p_S_X2=NA_real_,p_holm=NA_real_,status='not_run',diagnostic_warnings='',stringsAsFactors=FALSE)
 key<-list(version='big_five_full60_v1',input_md5=unname(tools::md5sum(input)),meta_md5=unname(tools::md5sum(mp)),rows=rows,pa_reps=pa_reps,seed=base_seed,mirt=as.character(packageVersion('mirt')),R=R.version.string)
 if(length(constant)){
  result$irt_status<-result$global_fit_status<-result$item_fit_status<-result$pa_original_status<-paste('Unavailable: constant items retained:',paste(constant,collapse=','));items$status<-result$irt_status;log(result$irt_status)
 }else{
  key_pa<-c(key,list(pa_rows=rows[pa_positions],pa_sample_n=pa_sample_n))
  p<-stage('parallel_analysis',scale,key_pa,120,pa(x[pa_positions,,drop=FALSE],result$pa_original_seed))
  result$pa_original_status<-if(is.null(p$value))p$error else'ok';result$pa_seconds<-p$seconds
  if(!is.null(p$value)){result$pa_original_leading<-p$value$leading;result$pa_original_total_exceedances<-p$value$total;result$pa_original_eigenvalues<-encode(p$value$ev);result$pa_original_null95<-encode(p$value$q);log(paste('PA leading/total retained:',p$value$leading,p$value$total))}
  set.seed(result$irt_seed)
  fit<-stage('grm_model',scale,key,180,mirt::mirt(collapsed,1,itemtype='graded',method='EM',verbose=FALSE,technical=list(NCYCLES=5000)))
  result$irt_seconds<-fit$seconds;result$warnings<-fit$warnings
  if(is.null(fit$value)){result$irt_status<-result$global_fit_status<-result$item_fit_status<-items$status<-fit$error}else{
   model<-fit$value;result$irt_converged<-isTRUE(model@OptimInfo$converged);result$irt_em_iterations<-model@OptimInfo$iter
   result$irt_status<-if(result$irt_converged)'ok'else'NONCONVERGED; diagnostics not computed';log(paste('GRM converged:',result$irt_converged,'iterations:',result$irt_em_iterations))
   if(!result$irt_converged){result$global_fit_status<-result$item_fit_status<-items$status<-result$irt_status}else{
    global<-stage('C2_global_fit',scale,key,120,mirt::M2(model,type='C2',calcNull=TRUE))
    if(is.null(global$value)&&!grepl('time limit',global$error,ignore.case=TRUE))global<-stage('C2_no_null',scale,key,120,mirt::M2(model,type='C2',calcNull=FALSE))
    result$global_fit_status<-if(is.null(global$value))global$error else'ok';result$global_fit_seconds<-global$seconds
    if(!is.null(global$value)){result$C2<-getnum(global$value,'M2');for(n in c('df','p','RMSEA','SRMSR','CFI','TLI'))result[[n]]<-getnum(global$value,n);log(paste('C2:',result$C2,'df:',result$df,'p:',result$p,'RMSEA:',result$RMSEA))}
    sx<-stage('S_X2_item_fit',scale,key,120,mirt::itemfit(model,fit_stats='S_X2',na.rm=FALSE,mincell=1,p.adjust='none'))
    result$item_fit_status<-if(is.null(sx$value))sx$error else'ok';result$item_fit_seconds<-sx$seconds
    if(!is.null(sx$value)){
     pos<-match(ids,sx$value$item);fields<-c(S_X2='S_X2',df_S_X2='df.S_X2',p_S_X2='p.S_X2')
     for(n in names(fields))if(fields[n]%in%names(sx$value))items[[n]]<-sx$value[[fields[n]]][pos]
     valid<-is.finite(items$p_S_X2)&items$p_S_X2>=0&items$p_S_X2<=1
     items$p_holm[valid]<-p.adjust(items$p_S_X2[valid],method='holm',n=60)
     items$status<-ifelse(valid,'ok','Unavailable/nonfinite S-X2');items$diagnostic_warnings<-sx$warnings
     result$item_fit_holm_family_n<-60L;result$item_fit_holm_significant_n<-if(any(valid))sum(items$p_holm<.05,na.rm=TRUE)else NA_integer_
     log(paste('S-X2 finite:',sum(valid),'Holm significant:',result$item_fit_holm_significant_n))
    }else items$status<-sx$error
   }
  }
 }
 result$global_fit_log_p<-if(is.finite(result$C2)&&is.finite(result$df))pchisq(result$C2,result$df,lower.tail=FALSE,log.p=TRUE)else NA_real_
 summary_rows[[scale]]<-result;item_rows[[scale]]<-items
 # Save a complete checkpoint after each scale; interrupted runs remain reviewable.
 write.csv(do.call(rbind,summary_rows),file.path(out,'dimensionality_global_fit.csv'),row.names=FALSE,na='NA')
 write.csv(do.call(rbind,item_rows),file.path(out,'item_fit.csv'),row.names=FALSE,na='NA')
 write.csv(do.call(rbind,freq_rows),file.path(out,'original_category_frequencies.csv'),row.names=FALSE,na='NA')
 write.csv(do.call(rbind,sample_rows),file.path(out,'diagnostic_sample_rows.csv'),row.names=FALSE)
 writeLines(c(notes,'',capture.output(sessionInfo())),file.path(out,'diagnostic_report.txt'))
}
writeLines(c(notes,'',capture.output(print(do.call(rbind,summary_rows)[c('scale','n_respondents','pa_n_respondents','pa_original_leading','C2','df','RMSEA','SRMSR','CFI','TLI','item_fit_holm_significant_n')],row.names=FALSE)),'',capture.output(sessionInfo())),file.path(out,'diagnostic_report.txt'))
cat('\nOutputs saved under:',out,'\n')
