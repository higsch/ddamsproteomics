#!/usr/bin/env Rscript
library(ggplot2)
library(reshape2)
args = commandArgs(trailingOnly=TRUE)
nrsets = as.numeric(args[1])
has_fractions = args[2] == TRUE
plateids = args[3:length(args)]

feats = read.table("psms", header=T, sep="\t", comment.char = "", quote = "")
ycol = 'value'
if (has_fractions) {
  width = 480
  xcol ='plateID'
  feats$plateID = paste(feats$Biological.set, feats$Strip, sep='_')
  amount_ms2 = read.table("scans")
  feats$Fraction = as.factor(feats$Fraction)
} else {
  width = 800
  xcol ='SpectraFile'
  amount_ms2 = read.table("scans", sep="|", header=F)
}


##### PSM-scans
set_amount_psms = aggregate(SpecID~Biological.set, feats, length)
names(set_amount_psms) = c('Set', 'psmcount')
write.table(set_amount_psms, 'summary.txt', row.names=F, quote=F, sep='\t')

amount_psms = aggregate(SpecID~get(xcol), feats, length)
mscol = 'MS2 scans'
psmcol = 'PSMs IDed'
names(amount_ms2) = c(xcol, mscol)
names(amount_psms) = c(xcol, psmcol)
amount_id=merge.data.frame(amount_ms2[c(xcol, mscol)], amount_psms[c(xcol, psmcol)], by.x=xcol, by.y=xcol, all=T)
amount_id = melt(amount_id, measure.vars=c(mscol, psmcol))
procents = dcast(amount_id, get(xcol)~variable, value.var=ycol)
procents$p = procents$`PSMs IDed` / procents$`MS2 scans`
png('psm-scans', width=width, height=(3 * nrsets + 2) * 72)
print(ggplot(amount_id) +
  geom_bar(aes_string(x=xcol, y=ycol, fill='variable'), stat='identity', position='dodge') + coord_flip() +
    xlab('Plate') + theme_bw() + theme(axis.title=element_text(size=20), axis.text=element_text(size=15), legend.position="top", legend.text=element_text(size=15), legend.title=element_blank()) +
  geom_text(data=subset(amount_id, variable==psmcol), aes(y=value * 1.5, x=!!ensym(xcol), label=paste(100*round(procents$p, 2), '%')), nudge_x=.25, colour="black", size=8))
dev.off()

if (length(grep('plex', names(feats)))) {
  channels = names(feats)[grepl('plex', names(feats))]
  psm_empty = melt(feats[c(xcol, channels)], id.vars=xcol)
  psm_empty = psm_empty[psm_empty$value==0,]
  psm_empty$value = 1
  psm_empty = aggregate(value~get(xcol)+ variable, psm_empty, sum)
  names(psm_empty) = c(xcol, 'channels', 'nr_missing_values')
  psm_empty$channels = sub('.*plex_', '', psm_empty$channels)
  png('missing-tmt', width=width, height=(3 * nrsets + 2) * 72)
  print(ggplot(psm_empty) + 
    geom_bar(aes_string(x=xcol, y='nr_missing_values', fill='channels'), stat='identity', position="dodge") + ylab('# PSMs without quant') + xlab('Plate') + coord_flip() + theme_bw() + theme(axis.title=element_text(size=20), axis.text=element_text(size=15), legend.position="top", legend.text=element_text(size=15), legend.title=element_text(size=15)))
  dev.off()
}

mcl = aggregate(as.formula(paste('SpecID~', xcol, '+ missed_cleavage')), feats, length)
mcl$missed_cleavage = as.factor(mcl$missed_cleavage)
png('miscleav', width=width, height=(3 * nrsets + 2) * 72)
mcplot = ggplot(subset(mcl, missed_cleavage %in% c(1,2,3)), aes_string(xcol, 'SpecID')) + geom_bar(aes(fill=missed_cleavage), position='dodge', stat='identity') + coord_flip() + ylab('# PSMs') + xlab('Plate') + theme_bw() + theme(axis.title=element_text(size=20), axis.text=element_text(size=15), legend.position="top", legend.text=element_text(size=15), legend.title=element_text(size=15)) + scale_fill_discrete(name="Nr missed cleavages")

if (nrow(subset(mcl, missed_cleavage == 1))) {
  procents = subset(mcl, missed_cleavage == 1)$SpecID / sum(mcl$SpecID)
  mcplot = mcplot + geom_text(data=subset(mcl, missed_cleavage == 1), aes(x=!!ensym(xcol), y=SpecID/2, label=paste(100*round(procents, 2), '%')), nudge_x=-0.333, colour="white", size=8)
}
print(mcplot)
dev.off()


# Now the per-fraction or per-file stats
if (has_fractions) {
  xcol = 'Fraction'
} else { 
  xcol = 'SpectraFile'
}
  
ptypes = list(retentiontime=c('Retention.time.min.', 'time(min)'), precerror=c('PrecursorError.ppm.', 'Precursor error (ppm)'), 
              fryield=c('SpecID', '# PSMs'), msgfscore=c('MSGFScore', 'MSGF Score'))
fryield_form = paste('SpecID ~', xcol)
for (plateid in plateids) {
  if (has_fractions) {
    subfeats = subset(feats, plateID==plateid) 
    fryield_form = paste(fryield_form, '+ plateID')
    h = 4 * 72
    w = 30 * 72
  } else { 
    subfeats = feats
    h = (2 * nrow(unique(feats[xcol])) + 1) * 72
    w = 1200
  }
  for (ptype in names(ptypes)) {
    fn = paste('PLATE', plateid, ptype, sep="___")
    if (ptype == 'fryield') {
      plotdata = aggregate(as.formula(fryield_form), subfeats, length)
      p = ggplot(plotdata) + geom_bar(aes_string(x=xcol, y=ptypes[[ptype]][1]), stat='identity')
    } else {
      plotdata = subfeats
      p = ggplot(plotdata, aes_string(x=xcol, y=ptypes[[ptype]][1])) + geom_violin(trim=F) 
    }
    if (ptype == 'precerror') {
      p = p + geom_hline(yintercept=0, size=2)
    }
    png(fn, height=h, width=w)
    p = p + ylab(ptypes[[ptype]][2]) + theme_bw() + theme(axis.title=element_text(size=30), axis.text=element_text(size=20))
    if(!has_fractions) p = p + xlab('Sample') + coord_flip()
    print(p)
    dev.off()
  }
}
