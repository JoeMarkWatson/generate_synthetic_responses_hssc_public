from collections import Counter
import json
from pathlib import Path

from config import BASE_DIR, DATA_DIR
from io_utils import read_ipip_demographic_rows


OUTPUT_PATH = BASE_DIR / "scales_info" / "Extraversion_info" / "synth_sample_config.json"
IPIP_DAT_PATH = (
    DATA_DIR
    / "human_data_details"
    / "ipip"
    / "IPIP300.dat"
)


def _distribution_from_counter(counter, *, sort_numeric=False):
    if sort_numeric:
        items = sorted(counter.items(), key=lambda item: item[0])
    else:
        items = sorted(counter.items(), key=lambda item: (-item[1], str(item[0])))

    total = sum(counter.values())
    if total <= 0:
        raise ValueError("Cannot build a distribution from an empty counter.")

    return {
        str(key): f"{(count / total) * 100:.6f}%"
        for key, count in items
    }


def build_config():
    demographic_rows = read_ipip_demographic_rows(
        IPIP_DAT_PATH,
        fraction=0.5,
        from_end=False,
    )

    if not demographic_rows:
        raise ValueError(f"No demographic rows were parsed from {IPIP_DAT_PATH}")

    gender_counts = Counter(row["gender"] for row in demographic_rows)
    age_counts = Counter(row["age"] for row in demographic_rows)
    country_counts = Counter(row["country"] for row in demographic_rows)

    return {
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


def main():
    config = build_config()
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
