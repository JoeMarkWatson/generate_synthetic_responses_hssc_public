# Synthetic Responses for Psychometric Item Pre-Testing

Code, data and results accompanying *Synthetic Responses for Psychometric Item Pre-Testing*, submitted to *Humanities and Social Sciences Communications*.

The study examines whether LLM-generated responses can support questionnaire item selection before human calibration. It compares prompting approaches across four LLMs and evaluates item selection across five Big Five-based scales and two newly developed workplace scales.

## Repository contents

- `LLM_resps_gen/` — Synthetic persona generation and LLM prompting.
- `data/` — Human and synthetic responses, item specifications and preprocessing.
- `evaluate_resps/` — IRT calibration, Monte Carlo analyses and statistical comparisons.
- `tables/` — Results tables and psychometric diagnostics.
- `plots/` — Figure generation.

## Reproducing the results

The repository includes the aggregate results used in the manuscript. Most tables and figures can therefore be reproduced without rerunning the Monte Carlo simulations.

The main reporting scripts are:

```bash
Rscript evaluate_resps/export_table1_sample_sizes.R
Rscript evaluate_resps/export_study1_prompt_ablation_tables.R
Rscript plots/validity_lollipop.R --from-csv
Rscript evaluate_resps/build_retrospective_diagnostic_appendix_tables.R
python scripts/create_table_g1.py
```

Table 1 is calculated from the human-response datasets. Table 2 summarises the prompting conditions implemented in Study 1; the full prompt and component definitions are provided in Appendix B. Tables 3 and F1 are generated from the saved Study 1 summary. Results for Tables 4 and 5 are available in the corresponding Study 1 and Study 2 summary files. Figure 2 uses `plots/validity_lollipop_values.csv`.

Table G1 contains the saved paired synthetic-versus-human validity comparisons and is exported to `tables/table_g1_validity.xlsx` and `tables/table_g1_validity.csv`.

For full reanalysis, run commands from the repository root. The supplied workplace exports and demographic configurations can be rebuilt from the approved reduced source:

```bash
workplace_source=data/human_data_details/new_scales/new_scales_public_candidate.csv
python data/human_data_details/new_scales/build_new_scale_human_data.py --scale Work_conscientiousness --source "$workplace_source"
python data/human_data_details/new_scales/build_new_scale_human_data.py --scale Work_honesty_humility --source "$workplace_source"
python LLM_resps_gen/build_new_scales_sample_config.py --source "$workplace_source"
```

The Monte Carlo analyses use the supplied human data and saved LLM outputs; no new API calls are needed. Use **500 repetitions and seed 1**, with fresh output directories rather than the retained aggregate-result directories. Choose unused paths if these example directories already contain results:

```bash
Rscript evaluate_resps/monte_carlo_study1.R --reps=500 --seed=1 --output-dir=../hssc_reanalysis/study1
Rscript evaluate_resps/monte_carlo_study2a.R --reps=500 --seed=1 --output-dir=../hssc_reanalysis/study2a
Rscript evaluate_resps/monte_carlo_study2b.R --reps=500 --seed=1 --output-dir=../hssc_reanalysis/study2b
```

To rerun the retrospective diagnostics, regenerate the Big Five caches and sample-row indices, then the workplace diagnostics, before the parallel-analysis sensitivity check:

```bash
Rscript evaluate_resps/retrospective_big_five_item_bank_diagnostics.R
Rscript evaluate_resps/retrospective_workplace_item_bank_diagnostics.R
Rscript evaluate_resps/retrospective_parallel_analysis_sensitivity.R
```

These diagnostic runs are unnecessary when reproducing the appendix tables from the saved aggregate outputs with `build_retrospective_diagnostic_appendix_tables.R`.

## Data availability

The Big Five analyses use the [IPIP-NEO-300 dataset](https://osf.io/wxvth/files/jdu2v) (Johnson, 2014). The original data and scoring materials are also available through [PsychArchives](https://doi.org/10.23668/psycharchives.2448). The repository includes the training and evaluation datasets used in our analyses.

For the two workplace scales, the repository includes responses from 324 participants to Work Conscientiousness, Work Honesty–Humility, IPIP Conscientiousness and HEXACO Honesty–Humility. The shared dataset contains only the questionnaire responses, age, gender and country of residence, with original participant IDs replaced by arbitrary identifiers.

Large intermediate Monte Carlo results and fitted-model caches are excluded because of their size and the potential presence of individual-level information. These files can be regenerated using the supplied scripts. The aggregate results underlying the manuscript's tables and figures are retained.

## Requirements

The analyses use R and Python. R dependencies are listed in `install.R`, and Python dependencies in `requirements.txt`. R packages are `mirt`, `openxlsx`, `digest` and `jsonlite`.

Full reanalysis requires substantially more computation and storage than reproducing the tables and figures from saved results.
