from collections import Counter
import argparse
import csv
import json
from pathlib import Path

from config import BASE_DIR, DATA_DIR


SOURCE_PATH = (
    DATA_DIR
    / "human_data_details"
    / "new_scales"
    / "new_scales_cleaned.csv"
)
OUTPUT_PATHS = (
    BASE_DIR / "scales_info" / "Work_conscientiousness_info" / "synth_sample_config.json",
    BASE_DIR / "scales_info" / "Work_honesty_humility_info" / "synth_sample_config.json",
)


def _distribution_from_counter(counter, *, sort_numeric=False):
    if sort_numeric:
        items = sorted(counter.items(), key=lambda item: int(item[0]))
    else:
        items = sorted(counter.items(), key=lambda item: (-item[1], str(item[0])))

    total = sum(counter.values())
    if total <= 0:
        raise ValueError("Cannot build a distribution from an empty counter.")

    return {
        str(key): f"{(count / total) * 100:.6f}%"
        for key, count in items
    }


def _read_demographic_counters(source=SOURCE_PATH):
    with source.open(newline="", encoding="utf-8-sig") as file:
        reader = csv.DictReader(file)
        required_columns = {
            "Age_survey1",
            "Sex_survey1",
            "Country of residence_survey1",
        }
        missing_columns = required_columns - set(reader.fieldnames or [])
        if missing_columns:
            raise ValueError(
                f"Missing required columns in {source}: "
                f"{sorted(missing_columns)}"
            )

        rows = list(reader)

    if not rows:
        raise ValueError(f"No cleaned respondents found in {source}")

    age_values = [row["Age_survey1"].strip() for row in rows]
    gender_values = [row["Sex_survey1"].strip() for row in rows]
    country_values = [row["Country of residence_survey1"].strip() for row in rows]

    if any(not value for value in age_values + gender_values + country_values):
        raise ValueError("Demographic columns contain blank values.")

    for age in age_values:
        if not age.isdigit():
            raise ValueError(f"Age_survey1 contains a non-integer value: {age!r}")

    return (
        Counter(age_values),
        Counter(gender_values),
        Counter(country_values),
        len(rows),
    )


def build_config(source=SOURCE_PATH):
    age_counts, gender_counts, country_counts, n_used = _read_demographic_counters(source)

    config = {
        "n": 1000,
        "theta": {
            "distribution": "normal",
            "mean": 0.0,
            "sd": 1.0,
            "bounds": [-3.0, 3.0],
        },
        "demographics": {
            "gender": {
                "type": "categorical",
                "distribution": _distribution_from_counter(gender_counts),
            },
            "age": {
                "type": "categorical",
                "distribution": _distribution_from_counter(
                    age_counts,
                    sort_numeric=True,
                ),
            },
            "country": {
                "type": "categorical",
                "distribution": _distribution_from_counter(country_counts),
            },
        },
    }
    return config, age_counts, gender_counts, country_counts, n_used


def _print_counter_summary(label, counter, *, sort_numeric=False):
    if sort_numeric:
        items = sorted(counter.items(), key=lambda item: int(item[0]))
    else:
        items = sorted(counter.items(), key=lambda item: (-item[1], str(item[0])))

    total = sum(counter.values())
    print(f"{label} counts/proportions:")
    for value, count in items:
        print(f"  {value}: {count} ({count / total:.6%})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SOURCE_PATH,
                        help="Input CSV; defaults to new_scales_cleaned.csv.")
    args = parser.parse_args()
    config, age_counts, gender_counts, country_counts, n_used = build_config(args.source)

    print(f"N used: {n_used}")
    print(
        "Age distribution summary: "
        f"{len(age_counts)} unique ages, "
        f"range {min(map(int, age_counts))}-{max(map(int, age_counts))}"
    )
    _print_counter_summary("Age", age_counts, sort_numeric=True)
    _print_counter_summary("Sex", gender_counts)
    _print_counter_summary("Country", country_counts)

    for output_path in OUTPUT_PATHS:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote: {output_path}")


if __name__ == "__main__":
    main()
