# Retrospective full-item-bank diagnostics

## Table A. Dimensionality screen and global fit

| Scale | PA N | PCA components: original | PCA components: dichotomised | IRT N | Model | Global fit | Statistic | df | p | RMSEA | SRMSR | CFI | TLI |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Extraversion | 1000 | 7 | — | 5000 | Unidimensional GRM | C2 | 117666.00 | 1710 | <.001 | 0.116 | 0.092 | 0.796 | 0.789 |
| Openness | 1000 | 9 | — | 5000 | Unidimensional GRM | C2 | 112092.56 | 1710 | <.001 | 0.114 | 0.100 | 0.632 | 0.619 |
| Neuroticism | 1000 | 7 | — | 5000 | Unidimensional GRM | C2 | 122760.58 | 1710 | <.001 | 0.119 | 0.087 | 0.839 | 0.833 |
| Agreeableness | 1000 | 8 | — | 5000 | Unidimensional GRM | C2 | 117487.72 | 1710 | <.001 | 0.116 | 0.097 | 0.698 | 0.688 |
| Conscientiousness | 1000 | 7 | — | 5000 | Unidimensional GRM | C2 | 120823.36 | 1710 | <.001 | 0.118 | 0.094 | 0.781 | 0.774 |
| Work Conscientiousness |  324 | 3 | 3 |  324 | Unidimensional 2PL | M2 | 285.44 |  152 | <.001 | 0.052 | 0.069 | 0.929 | 0.920 |
| Work Honesty–Humility |  324 | 2 | 2 |  324 | Unidimensional 2PL | M2 | 233.05 |  170 | <.001 | 0.034 | 0.067 | 0.975 | 0.972 |

## Table B. Item-fit summary

| Scale | Items in bank | Items assessed | Holm-significant S-X² | Unavailable |
| --- | --- | --- | --- | --- |
| Extraversion | 60 | 60 |  4 | 0 |
| Openness | 60 | 60 |  3 | 0 |
| Neuroticism | 60 | 60 |  2 | 0 |
| Agreeableness | 60 | 60 | 11 | 0 |
| Conscientiousness | 60 | 60 |  1 | 0 |
| Work Conscientiousness | 19 | 19 |  0 | 0 |
| Work Honesty–Humility | 20 | 20 |  0 | 0 |

## Table notes

1. These are retrospective full-item-bank diagnostics, not Monte Carlo short-form results or calibration-reference estimates.
2. Big Five: all 60 target-trait items per scale; the four deliberately introduced nuisance items are excluded. IRT uses a fixed 5,000-person training-data diagnostic subsample; PA uses its saved nested 1,000-person subset. These are not the full-human calibration reference samples.
3. Workplace: all 324 available human respondents; all 19 Work Conscientiousness and 20 Work Honesty–Humility items, including every researcher-flagged potentially weak item. PA uses both original keyed five-category and dichotomised responses. The two codings give identical PCA counts within each workplace scale.
4. PCA PA uses Pearson correlations and independent within-item permutations, retaining leading consecutive observed eigenvalues above ordered null 95th percentiles: 200 permutations per Big Five scale and 1,000 per workplace coding. It is an exploratory dimensionality screen, not an estimate of the exact number of latent factors.
5. IRT: one-factor GRM for original keyed Big Five ordinal responses; one-factor 2PL for workplace responses, reversed where required and dichotomised as keyed categories 4/5 = 1 and 1/2/3 = 0. Models were fitted using mirt EM with NCYCLES=5000. All seven saved fits converged; no diagnostic-sample item or respondent exclusions or additional category collapsing occurred.
6. Global fit uses C2 for Big Five and M2 for workplace. CSV p-values preserve the saved numeric values; Big Five p=0 reflects numerical underflow and is displayed as p<.001, not interpreted as an exactly zero probability. Markdown rounds statistics to two decimals and fit indices to three; CSVs retain source precision.
7. S-X² uses mincell=1 and no automatic respondent deletion. Holm adjustment is separate within each complete item bank (60, 19 or 20 tests). Misfit is defined as saved Holm-adjusted p<.05. All requested item diagnostics are available. Score groups may be merged internally for sparse expected cells; this does not remove items.
8. The additional Pearson SMC-based common-factor PA sensitivity check produced substantially different, unstable retention counts, including nonconsecutive threshold crossings in eight of nine analyses. These counts are not definitive latent-factor estimates. It used reduced-correlation eigenvalues with squared-multiple-correlation communalities, not minimum-residual extraction; polychoric/tetrachoric PA was not performed.
9. The CSV contains both workplace PCA codings explicitly; NA for Big Five dichotomised PA means not applicable/not performed. C2/M2 and S-X² results describe the full banks, not individual selected short forms.
10. Verification: every global value is copied from the saved summary CSVs; item counts and Holm-significant totals match both the saved item-level CSVs and summary totals; PA counts and sample sizes also match the saved sensitivity comparison. No new psychometric analyses were run.

## Sources

- `tables/retrospective_big_five_item_bank_diagnostics/dimensionality_global_fit.csv`
- `tables/retrospective_big_five_item_bank_diagnostics/item_fit.csv`
- `tables/retrospective_big_five_item_bank_diagnostics/diagnostic_report.txt`
- `tables/retrospective_workplace_item_bank_diagnostics/dimensionality_global_fit.csv`
- `tables/retrospective_workplace_item_bank_diagnostics/item_fit.csv`
- `tables/retrospective_workplace_item_bank_diagnostics/diagnostic_report.txt`
- `tables/retrospective_parallel_analysis_sensitivity/parallel_analysis_comparison.csv`
- `tables/retrospective_parallel_analysis_sensitivity/diagnostic_report.txt`
