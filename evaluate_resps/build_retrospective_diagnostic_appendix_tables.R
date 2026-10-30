#!/usr/bin/env Rscript
# Assemble existing diagnostics only; no model fitting or parallel analysis.
a <- grep('^--file=',commandArgs(FALSE),value=TRUE)
stopifnot(length(a)==1L)
root <- normalizePath(file.path(dirname(sub('^--file=','',a)),'..'))
base <- file.path(root,'tables')
out <- file.path(base,'retrospective_diagnostic_appendix_tables')
read <- function(folder,file)read.csv(file.path(base,folder,file),stringsAsFactors=FALSE,check.names=FALSE)
bf <- 'retrospective_big_five_item_bank_diagnostics'
wp <- 'retrospective_workplace_item_bank_diagnostics'
b <- read(bf,'dimensionality_global_fit.csv'); w <- read(wp,'dimensionality_global_fit.csv')
ib <- read(bf,'item_fit.csv'); iw <- read(wp,'item_fit.csv')
s <- read('retrospective_parallel_analysis_sensitivity','parallel_analysis_comparison.csv')
labels <- c(Extraversion='Extraversion',Openness='Openness',Neuroticism='Neuroticism',Agreeableness='Agreeableness',Conscientiousness='Conscientiousness',Work_conscientiousness='Work Conscientiousness',Work_honesty_humility='Work Honesty–Humility')
global <- items <- list()
for(scale in names(labels)){
 workplace <- startsWith(scale,'Work_')
 d <- if(workplace)w[w$scale==scale,,drop=FALSE]else b[b$scale==scale,,drop=FALSE]
 it <- if(workplace)iw[iw$scale==scale,,drop=FALSE]else ib[ib$scale==scale,,drop=FALSE]
 stopifnot(nrow(d)==1L,isTRUE(d$irt_converged),d$global_fit_status=='ok',d$item_fit_status=='ok',nrow(it)==d$n_items,!anyDuplicated(it$item),all(it$n_respondents==d$n_respondents))
 valid <- is.finite(it$p_S_X2)&is.finite(it$p_holm)&is.finite(it$S_X2)&is.finite(it$df_S_X2)
 significant <- sum(it$p_holm[valid]<.05)
 stopifnot(all(valid),all(it$status=='ok'),significant==d$item_fit_holm_significant_n,d$item_fit_holm_family_n==nrow(it))
 # Cross-check saved PA counts/N against independently saved sensitivity summary.
 ss <- s[s$scale==scale & s$response_coding=='Original keyed 1-5',,drop=FALSE]
 pan <- if(workplace)d$n_respondents else d$pa_n_respondents
 stopifnot(nrow(ss)==1L,ss$n_respondents==pan,ss$existing_PCA_components==d$pa_original_leading,ss$PCA_reproduction_max_abs_error==0)
 if(workplace){sb<-s[s$scale==scale & startsWith(s$response_coding,'Keyed binary'),,drop=FALSE];stopifnot(nrow(sb)==1L,sb$existing_PCA_components==d$pa_binary_leading)}
 global[[scale]] <- data.frame(Scale=unname(labels[scale]),PA_N=pan,PCA_components_original=d$pa_original_leading,PCA_components_dichotomised=if(workplace)d$pa_binary_leading else NA_integer_,IRT_N=d$n_respondents,Model=if(workplace)'Unidimensional 2PL'else'Unidimensional GRM',Global_fit_statistic=if(workplace)'M2'else'C2',Statistic=if(workplace)d$M2 else d$C2,df=d$df,p_value=d$p,RMSEA=d$RMSEA,SRMSR=d$SRMSR,CFI=d$CFI,TLI=d$TLI,check.names=FALSE)
 items[[scale]] <- data.frame(Scale=unname(labels[scale]),Items_in_bank=nrow(it),Items_assessed=sum(valid),Holm_significant_S_X2=significant,Unavailable_item_diagnostics=sum(!valid),check.names=FALSE)
}
global <- do.call(rbind,global);items <- do.call(rbind,items)
notes <- c(
 'These are retrospective full-item-bank diagnostics, not Monte Carlo short-form results or calibration-reference estimates.',
 'Big Five: all 60 target-trait items per scale; the four deliberately introduced nuisance items are excluded. IRT uses a fixed 5,000-person training-data diagnostic subsample; PA uses its saved nested 1,000-person subset. These are not the full-human calibration reference samples.',
 'Workplace: all 324 available human respondents; all 19 Work Conscientiousness and 20 Work Honesty–Humility items, including every researcher-flagged potentially weak item. PA uses both original keyed five-category and dichotomised responses. The two codings give identical PCA counts within each workplace scale.',
 'PCA PA uses Pearson correlations and independent within-item permutations, retaining leading consecutive observed eigenvalues above ordered null 95th percentiles: 200 permutations per Big Five scale and 1,000 per workplace coding. It is an exploratory dimensionality screen, not an estimate of the exact number of latent factors.',
 'IRT: one-factor GRM for original keyed Big Five ordinal responses; one-factor 2PL for workplace responses, reversed where required and dichotomised as keyed categories 4/5 = 1 and 1/2/3 = 0. Models were fitted using mirt EM with NCYCLES=5000. All seven saved fits converged; no diagnostic-sample item or respondent exclusions or additional category collapsing occurred.',
 'Global fit uses C2 for Big Five and M2 for workplace. CSV p-values preserve the saved numeric values; Big Five p=0 reflects numerical underflow and is displayed as p<.001, not interpreted as an exactly zero probability. Markdown rounds statistics to two decimals and fit indices to three; CSVs retain source precision.',
 'S-X² uses mincell=1 and no automatic respondent deletion. Holm adjustment is separate within each complete item bank (60, 19 or 20 tests). Misfit is defined as saved Holm-adjusted p<.05. All requested item diagnostics are available. Score groups may be merged internally for sparse expected cells; this does not remove items.',
 'The additional Pearson SMC-based common-factor PA sensitivity check produced substantially different, unstable retention counts, including nonconsecutive threshold crossings in eight of nine analyses. These counts are not definitive latent-factor estimates. It used reduced-correlation eigenvalues with squared-multiple-correlation communalities, not minimum-residual extraction; polychoric/tetrachoric PA was not performed.',
 'The CSV contains both workplace PCA codings explicitly; NA for Big Five dichotomised PA means not applicable/not performed. C2/M2 and S-X² results describe the full banks, not individual selected short forms.',
 'Verification: every global value is copied from the saved summary CSVs; item counts and Holm-significant totals match both the saved item-level CSVs and summary totals; PA counts and sample sizes also match the saved sensitivity comparison. No new psychometric analyses were run.')
mdtable <- function(d){c(paste0('| ',paste(names(d),collapse=' | '),' |'),paste0('| ',paste(rep('---',ncol(d)),collapse=' | '),' |'),apply(d,1,function(z)paste0('| ',paste(z,collapse=' | '),' |')))}
shown <- global
shown$Statistic <- sprintf('%.2f',global$Statistic)
shown$p_value <- ifelse(global$p_value<.001,'<.001',sprintf('%.3f',global$p_value))
for(n in c('RMSEA','SRMSR','CFI','TLI'))shown[[n]]<-sprintf('%.3f',global[[n]])
shown$PCA_components_dichotomised <- ifelse(is.na(global$PCA_components_dichotomised),'—',global$PCA_components_dichotomised)
names(shown)<-c('Scale','PA N','PCA components: original','PCA components: dichotomised','IRT N','Model','Global fit','Statistic','df','p','RMSEA','SRMSR','CFI','TLI')
shownitems <- items;names(shownitems)<-c('Scale','Items in bank','Items assessed','Holm-significant S-X²','Unavailable')
sources <- c(file.path(bf,c('dimensionality_global_fit.csv','item_fit.csv','diagnostic_report.txt')),file.path(wp,c('dimensionality_global_fit.csv','item_fit.csv','diagnostic_report.txt')),'retrospective_parallel_analysis_sensitivity/parallel_analysis_comparison.csv','retrospective_parallel_analysis_sensitivity/diagnostic_report.txt')
# Read the existing reports too, checking that the documented methods agree.
br <- readLines(file.path(base,bf,'diagnostic_report.txt'));wr <- readLines(file.path(base,wp,'diagnostic_report.txt'));sr <- readLines(file.path(base,'retrospective_parallel_analysis_sensitivity','diagnostic_report.txt'))
stopifnot(any(grepl('NCYCLES=5000',br,fixed=TRUE)),any(grepl('NCYCLES=5000',wr,fixed=TRUE)),any(grepl('Nonconsecutive',sr,fixed=TRUE)))
dir.create(out,recursive=TRUE,showWarnings=FALSE)
write.csv(global,file.path(out,'global_fit_and_dimensionality.csv'),row.names=FALSE,na='NA')
write.csv(items,file.path(out,'item_fit_summary.csv'),row.names=FALSE,na='NA')
# Ensure numeric values survive CSV round-trip at the source-file precision.
reread<-read.csv(file.path(out,'global_fit_and_dimensionality.csv'),check.names=FALSE)
stopifnot(isTRUE(all.equal(unname(as.matrix(global[vapply(global,is.numeric,logical(1))])),unname(as.matrix(reread[vapply(reread,is.numeric,logical(1))])),tolerance=1e-14)))
writeLines(c('# Retrospective full-item-bank diagnostics','','## Table A. Dimensionality screen and global fit','',mdtable(shown),'','## Table B. Item-fit summary','',mdtable(shownitems),'','## Table notes','',paste0(seq_along(notes),'. ',notes),'','## Sources','',paste0('- `tables/',sources,'`')),file.path(out,'appendix_tables.md'),useBytes=TRUE)
cat('Verified all seven scales against saved summaries and item-level outputs. No analyses rerun.\n')
print(items,row.names=FALSE)
cat('Outputs:',out,'\n')
