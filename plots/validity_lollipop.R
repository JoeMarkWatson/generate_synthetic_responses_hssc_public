#!/usr/bin/env Rscript
# Run from any directory: Rscript /path/to/plots/validity_lollipop.R
# Base R only; reads existing checkpoints, never sources simulation code.
arg <- grep('^--file=', commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub('^--file=', '', arg[1])), '..'))
outdir <- file.path(root, 'plots')
scales <- c('Extraversion','Openness','Neuroticism','Agreeableness',
            'Conscientiousness','Work_conscientiousness','Work_honesty_humility')
labels <- c(scales[1:5], 'Work Conscientiousness', 'Work Honesty–Humility')
models <- c('OpenAI GPT-5.6 Luna','Claude Haiku 5.5','Xiaomi MiMo-V2.6-Flash','DeepSeek Flash v4.1')
methods <- c('openai_no_detail_variation','claude_no_detail_variation',
             'xiaomi_no_detail_variation','v2.1.1_no_detail_variation')
files <- c('evaluate_resps/monte_carlo_study1_output/monte_carlo_results.csv',
           file.path('evaluate_resps/monte_carlo_study2a_output',scales[2:5],'monte_carlo_results.csv'),
           file.path('evaluate_resps/monte_carlo_study2b_output',scales[6:7],'monte_carlo_results.csv'))
# Huge CSVs contain serialized respondent vectors. Project only the needed prefix
# fields while streaming with system Perl. The retained fields are numeric or
# simple identifiers, without embedded quotes or newlines (validated below).
read_projection <- function(path) {
  header <- names(read.csv(path, nrows = 0, check.names = FALSE))
  wanted <- intersect(c('repetition','attempt','seed','split_seed','stage','method',
                       'scoring_method','pearson_r','spearman_r','fit_n','eval_n'),header)
  wanted <- wanted[match(wanted, header) < match("eval_short_sum", header)]
  idx <- match(wanted, header)
  parser <- sprintf('BEGIN{@keep=(%s); $last=%d;} next if $.==1; @v=(); pos($_)=0; for my $field (1..$last){ /\\G("[^"\n]*"|[^,\\n]*)(?:,|\\r?\\n|$)/gc or die "Invalid CSV prefix at line $."; push @v,$1; } print join(",",@v[@keep]),"\\n";',
                    paste(idx-1,collapse=','),max(idx))
  con <- pipe(paste('perl -ne', shQuote(parser), shQuote(path)), 'r')
  on.exit(close(con))
  read.csv(con, header = FALSE, col.names = wanted, stringsAsFactors = FALSE)
}
# --from-csv redraws the already extracted values without rescanning large files.
if ("--from-csv" %in% commandArgs(TRUE)) {
  v <- read.csv(file.path(outdir, "validity_lollipop_values.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(v) == 32, length(unique(v$scale)) == 7)
} else {
rows <- list(); audit <- character()
for (i in seq_along(scales)) {
  message('Reading ', files[i])
  d <- read_projection(file.path(root,files[i]))
  if ('stage' %in% names(d)) d <- d[d$stage == 'short_form_evaluation',]
  stopifnot(nrow(d)>0, all(d$scoring_method %in% c('SUM_SCORE','RAW_SUM')))
  ref_method <- if(i<=5) 'reference' else 'human224'
  use <- if(i==1) seq_along(methods) else c(1,3)
  d <- d[d$method %in% c(ref_method,methods[use]),]
  stopifnot(!anyDuplicated(d[c('repetition','method')]))
  ref <- d[d$method==ref_method,]
  if ('fit_n' %in% names(ref)) audit <- c(audit,paste(scales[i], 'reference fit_n:',paste(unique(ref$fit_n),collapse=',')))
  for (j in use) {
    s <- d[d$method==methods[j],]
    stopifnot(nrow(s)>0,nrow(ref)>0)
    paired <- merge(s,ref,by='repetition',suffixes=c('_synthetic','_reference'))
    for (key in intersect(c('seed','split_seed'),names(d)))
      stopifnot(all(paired[[paste0(key,'_synthetic')]]==paired[[paste0(key,'_reference')]]))
    for (metric in c('pearson_r','spearman_r')) {
      a <- paired[[paste0(metric,'_synthetic')]]; b <- paired[[paste0(metric,'_reference')]]
      ok <- is.finite(a)&is.finite(b); a<-a[ok]; b<-b[ok]; delta<-a-b; n<-length(delta)
      stopifnot(n>1)
      half <- qt(.975,n-1)*sd(delta)/sqrt(n)
      rows[[length(rows)+1]] <- data.frame(scale=scales[i],scale_label=labels[i],
        panel=if(i<=5)'Big Five' else 'Workplace scales',model=models[j],method=methods[j],
        condition='no_detail_variation',scoring='RAW_SUM (stored as SUM_SCORE)',
        criterion=if(i<=5)'Held-out same-trait item sum' else if(i==6)'IPIP60 Conscientiousness sum' else 'HEXACO Honesty–Humility sum',
        metric=if(metric=='pearson_r')'Pearson' else 'Spearman',reference_method=ref_method,
        reference_calibration_n=if('fit_n'%in%names(ref)) paste(unique(ref$fit_n),collapse=';') else NA,
        synthetic_mean=mean(a),reference_mean=mean(b),difference=mean(delta),
        ci_lower=mean(delta)-half,ci_upper=mean(delta)+half,n_paired=n,
        synthetic_available=sum(is.finite(s[[metric]])),reference_available=sum(is.finite(ref[[metric]])),
        inference='Paired mean difference; pointwise 95% Student t CI across repetitions',source_file=files[i])
    }
  }
}
v <- do.call(rbind,rows)
stopifnot(nrow(v)==32,length(unique(v$scale))==7,all(is.finite(v$difference)))
write.csv(v,file.path(outdir,'validity_lollipop_values.csv'),row.names=FALSE,na='')
writeLines(c('Source and statistical notes', '',
 'Only no_detail_variation; unnamed v2.1.1_no_detail_variation is DeepSeek Flash v4.1.',
 'All estimates recomputed from repetition-level RAW_SUM/SUM_SCORE correlations.',
 'Pairs join on repetition within scale; available seed/split_seed fields must agree.',
 'Means are calculated over the same finite pairs as the differences. No imputation.',
 '95% pointwise t intervals describe uncertainty in the Monte Carlo mean difference,',
 'not a population validity interval; no multiplicity adjustment.',
 'Big Five reference is the stored full-training reference, not a small-sample baseline.',
 'Training input has 153,570 respondents; Study 1 fit_n is 122,969 after complete-case filtering.',
 'Study 2 results are read from the corresponding saved result directories.',
 'Workplace: raw binary selected-item sums versus external convergent sums.',
 'Base R used because ggplot2 is not installed. No packages installed.', '',audit,'',files),
 file.path(outdir,'validity_lollipop_notes.txt'))
}
colors <- c('#0072B2','#B07C35','#009E73','#9A6898')
# Fixed shared manuscript scale; estimates and intervals are unchanged.
xlimits <- c(-.04,.12)
xticks <- seq(-.04,.12,by=.02)
stopifnot(all(v$ci_lower >= xlimits[1]), all(v$ci_upper <= xlimits[2]))
presentation_notes <- c(
 'Presentation revision: point estimates and horizontal 95% CIs only; zero-to-point stems removed.',
 'Pearson uses smaller filled circles; Spearman uses smaller open triangles (cex=0.8), distinguishable in grayscale.',
 'A single seven-entry stacked legend sits inside the upper-right of Panel A, clear of estimates.',
 'Panel layout heights are 5.3:3.5 (previously 5.3:2.5), increasing the physical gap between workplace scales.',
 'Both panels share fixed x-axis limits of -0.04 to 0.12; model and metric inclusion are unchanged.',
 'Panel headings use cex.main=1.0; all axis labels, tick labels and legend text are black.',
 'Figure 2 uses Helvetica, uppercase panel headings, no main title and no bottom directional annotations.',
 'Regenerated from the existing values CSV using --from-csv; numerical values were not modified.'
)
notes_path <- file.path(outdir, 'validity_lollipop_notes.txt')
existing_notes <- readLines(notes_path, warn = FALSE)
marker <- match('Presentation revision', existing_notes)
if (!is.na(marker)) existing_notes <- existing_notes[seq_len(marker - 1L)]
writeLines(c(existing_notes, '', 'Presentation revision', presentation_notes), notes_path)
draw <- function() {
  layout(matrix(1:2,2,1),heights=c(5.3,3.5))
  par(family='Helvetica',las=1,fg='black',col.axis='black',col.lab='black',col.main='black',oma=c(0,0,2.5,0))
  for (panel in 1:2) {
    ids <- if(panel==1)1:5 else 6:7
    par(mar=c(if(panel==2)4.8 else 1.1,12.1,2.1,1.3),mgp=c(2.5,.7,0))
    plot(NA,xlim=xlimits,ylim=c(.45,length(ids)+.55),axes=FALSE,xlab='',ylab='',xaxs='i',yaxs='i')
    abline(h=seq_along(ids),col='#EEEEEE',lwd=.7)
    abline(v=xticks,col='#F1F1F1',lwd=.6);abline(v=0,col='#666666',lwd=1,lty=2)
    axis(2,at=rev(seq_along(ids)),labels=labels[ids],tick=FALSE,cex.axis=.92)
    axis(1,at=xticks,labels=if(panel==2)formatC(xticks,format='f',digits=2) else FALSE,
         col='#AAAAAA',col.ticks='#AAAAAA',cex.axis=.86,tck=-.018)
    title(main=if(panel==1)'A. BIG FIVE-BASED SCALES' else 'B. WORKPLACE SCALES',adj=0,cex.main=1.0,line=.7)
    for (k in seq_along(ids)) {
      z<-v[v$scale==scales[ids[k]],]; ms<-unique(z$model)
      for (r in seq_len(nrow(z))) {
        j<-match(z$model[r],models)
        offset <- if(length(ms)==4)c(.28,.09,-.09,-.28)[j] else c(.16,-.16)[match(z$model[r],ms)]
        y<-length(ids)-k+1+offset+if(z$metric[r]=='Pearson').05 else -.05
        segments(z$ci_lower[r],y,z$ci_upper[r],y,col=colors[j],lwd=1.1)
        segments(c(z$ci_lower[r],z$ci_upper[r]),y-.018,c(z$ci_lower[r],z$ci_upper[r]),y+.018,col=colors[j],lwd=.8)
        points(z$difference[r],y,pch=if(z$metric[r]=='Pearson')16 else 2,col=colors[j],cex=.8,lwd=1.1)
      }
    }
    if(panel==1) {
      legend(.118,5.46,xjust=1,
             legend=c(models,'Pearson','Spearman','95% CI'),
             col=c(colors,rep('#333333',3)),pch=c(rep(15,4),16,2,NA),
             lty=c(rep(NA,6),1),pt.cex=.8,pt.lwd=1.1,
             ncol=1,bty='n',text.col='black',cex=.82,x.intersp=.7,y.intersp=1.15)
    }
    if(panel==2) {
      mtext(expression(paste('Difference in validity (',Delta,'r or ',Delta,rho,')')),1,line=2.25,cex=.97)
    }
  }
}
pdf(file.path(outdir,'validity_lollipop.pdf'),width=10,height=8.5,useDingbats=FALSE,family='Helvetica',encoding="WinAnsi.enc")
draw();dev.off()
png(file.path(outdir,'validity_lollipop.png'),width=10,height=8.5,units='in',res=400,type=if(Sys.info()[['sysname']]=='Darwin')'quartz' else 'cairo')
draw();dev.off()
# Quartz writes 72-dpi metadata despite using res for the pixel dimensions.
if (Sys.info()[["sysname"]] == "Darwin") {
  status <- system2("sips", c("-s", "dpiWidth", "400", "-s", "dpiHeight", "400",
                            shQuote(file.path(outdir, "validity_lollipop.png"))), stdout = FALSE)
  stopifnot(status == 0L)
}
message('Saved PDF and 400 dpi PNG (',nrow(v),' points) in ',outdir)
print(v[c('scale','model','metric','difference','n_paired')],row.names=FALSE)
