import argparse
import csv
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SOURCE_PATH = Path(__file__).resolve().parent / "new_scales_cleaned.csv"
SCALES_INFO_DIR = REPO_ROOT / "scales_info"
CODEBOOK_PATH = SOURCE_PATH.with_name("new_scales_cleaned_codebook.csv")
OPTIONAL_GROUPS = {"Work performance item", "Workplace deviance item"}

SCALE_SOURCE_PREFIXES = {
    "Work_conscientiousness": "C_W_N_",
    "Work_honesty_humility": "HH_W_N_",
}

ADDITIONAL_DATASETS = {
    "Work_conscientiousness": {
        "output_dir": "work_conscientiousness_conv_crit",
        "datasets": {
            "Conscientiousness_IPIP60": "General C item",
            "work_performance": "Work performance item",
        },
    },
    "Work_honesty_humility": {
        "output_dir": "work_honesty_humility_conv_crit",
        "datasets": {
            "HH_Hexaco": "General HH item",
            "workplace_deviance": "Workplace deviance item",
        },
    },
}


def _read_item_codes(scale):
    metadata_path = SCALES_INFO_DIR / f"{scale}_info" / "scale_items.csv"
    if not metadata_path.exists():
        raise FileNotFoundError(f"Missing scale metadata: {metadata_path}")

    with metadata_path.open(newline="", encoding="utf-8") as file:
        rows = list(csv.DictReader(file))

    item_codes = [row.get("item_code", "").strip() for row in rows]
    if not item_codes or any(not item_code for item_code in item_codes):
        raise ValueError(f"Expected non-empty item_code values in {metadata_path}")
    if len(set(item_codes)) != len(item_codes):
        raise ValueError(f"Duplicate item_code values found in {metadata_path}")
    return item_codes


def _read_source_rows(scale, item_codes):
    if not SOURCE_PATH.exists():
        raise FileNotFoundError(f"Missing cleaned human data: {SOURCE_PATH}")

    prefix = SCALE_SOURCE_PREFIXES[scale]
    with SOURCE_PATH.open(newline="", encoding="utf-8-sig") as file:
        reader = csv.DictReader(file)
        source_fields = reader.fieldnames or []
        source_item_fields = [field for field in source_fields if field.startswith(prefix)]
        if len(source_item_fields) != len(item_codes):
            raise ValueError(
                f"Expected {len(item_codes)} {prefix} source columns, "
                f"found {len(source_item_fields)} in {SOURCE_PATH}"
            )

        rows = []
        for row in reader:
            rows.append({
                "participant_id": row["Participant id"],
                **{
                    item_code: row[source_field]
                    for item_code, source_field in zip(item_codes, source_item_fields)
                },
            })

    if not rows:
        raise ValueError(f"No human rows found in {SOURCE_PATH}")
    return rows


def _read_codebook():
    codebook_path = CODEBOOK_PATH
    if not codebook_path.exists():
        raise FileNotFoundError(f"Missing cleaned data codebook: {codebook_path}")

    with codebook_path.open(newline="", encoding="utf-8-sig") as file:
        rows = list(csv.DictReader(file))

    required_fields = {"variable_name", "group", "reverse_keyed"}
    if not rows or not required_fields.issubset(rows[0]):
        raise ValueError(f"Missing required fields in {codebook_path}")
    return rows


def _read_all_source_rows():
    if not SOURCE_PATH.exists():
        raise FileNotFoundError(f"Missing cleaned human data: {SOURCE_PATH}")

    with SOURCE_PATH.open(newline="", encoding="utf-8-sig") as file:
        reader = csv.DictReader(file)
        fieldnames = reader.fieldnames or []
        rows = list(reader)

    if "Participant id" not in fieldnames:
        raise ValueError(f"Missing Participant id column in {SOURCE_PATH}")
    if not rows:
        raise ValueError(f"No human rows found in {SOURCE_PATH}")
    return rows


def _parse_reverse_keyed(raw_value):
    return str(raw_value or "").strip().lower() in {"1", "true", "yes", "y"}


def _reverse_aware_sum(row, item_metadata, response_min, response_max):
    total = 0
    for metadata in item_metadata:
        raw_value = str(row.get(metadata["variable_name"], "")).strip()
        if not raw_value:
            continue
        try:
            value = int(float(raw_value))
        except ValueError as exc:
            raise ValueError(
                f"Non-numeric response {raw_value!r} for {metadata['variable_name']}"
            ) from exc
        if value < response_min or value > response_max:
            raise ValueError(
                f"Expected a {response_min}–{response_max} response for "
                f"{metadata['variable_name']}, got {value}"
            )
        reverse_value = response_min + response_max - value
        total += reverse_value if metadata["reverse_keyed"] else value
    return total


def _build_additional_dataset(source_rows, codebook_rows, group):
    item_metadata = [
        {
            "variable_name": row["variable_name"],
            "reverse_keyed": _parse_reverse_keyed(row["reverse_keyed"]),
        }
        for row in codebook_rows
        if row["group"] == group
    ]
    if not item_metadata:
        raise ValueError(f"No codebook items found for group {group!r}")

    item_codes = [metadata["variable_name"] for metadata in item_metadata]
    observed_values = [
        int(float(row[item_code]))
        for row in source_rows
        for item_code in item_codes
        if str(row.get(item_code, "")).strip()
    ]
    if not observed_values:
        raise ValueError(f"No numeric responses found for group {group!r}")
    response_min = min(observed_values)
    response_max = max(observed_values)
    return [
        {
            "participant_id": row["Participant id"],
            **{item_code: row.get(item_code, "") for item_code in item_codes},
            "sum_score": _reverse_aware_sum(
                row, item_metadata, response_min, response_max
            ),
        }
        for row in source_rows
    ], item_codes


def _write_additional_datasets(source_rows):
    codebook_rows = _read_codebook()
    for scale, config in ADDITIONAL_DATASETS.items():
        output_dir = (
            REPO_ROOT
            / "data"
            / "human_data_details"
            / "new_scales"
            / config["output_dir"]
        )
        output_dir.mkdir(parents=True, exist_ok=True)
        for dataset_name, group in config["datasets"].items():
            item_fields = [row["variable_name"] for row in codebook_rows if row["group"] == group]
            if not item_fields:
                raise ValueError(f"No codebook items found for group {group!r}")
            present = set(source_rows[0])
            missing = set(item_fields) - present
            if missing == set(item_fields) and group in OPTIONAL_GROUPS:
                print(f"Skipping optional {dataset_name}: all source columns absent.")
                continue
            if missing:
                raise ValueError(f"Missing source columns for {group!r}: {sorted(missing)}")
            dataset_rows, item_codes = _build_additional_dataset(
                source_rows, codebook_rows, group
            )
            output_path = output_dir / f"{dataset_name}.csv"
            with output_path.open("w", newline="", encoding="utf-8") as file:
                fieldnames = ["participant_id", *item_codes, "sum_score"]
                writer = csv.DictWriter(file, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(dataset_rows)
            print(
                f"Wrote {len(dataset_rows)} rows and {len(item_codes)} items "
                f"to {output_path}"
            )


def build_human_data(scale):
    item_codes = _read_item_codes(scale)
    rows = _read_source_rows(scale, item_codes)
    output_path = (
        REPO_ROOT
        / "data"
        / scale.lower()
        / "human_responses"
        / "human_responses.csv"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=["participant_id", *item_codes])
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows and {len(item_codes)} items to {output_path}")

    _write_additional_datasets(_read_all_source_rows())


def main():
    global SOURCE_PATH, REPO_ROOT, CODEBOOK_PATH
    parser = argparse.ArgumentParser()
    parser.add_argument("--scale", choices=tuple(SCALE_SOURCE_PREFIXES), required=True)
    parser.add_argument("--source", type=Path, default=SOURCE_PATH,
                        help="Cleaned original or reduced candidate CSV.")
    parser.add_argument("--output-root", type=Path, default=REPO_ROOT,
                        help="Root for generated data/ outputs; use a separate directory to preserve existing outputs.")
    parser.add_argument("--codebook", type=Path, default=CODEBOOK_PATH)
    args = parser.parse_args()
    SOURCE_PATH = args.source.resolve()
    REPO_ROOT = args.output_root.resolve()
    CODEBOOK_PATH = args.codebook.resolve()
    build_human_data(args.scale)


if __name__ == "__main__":
    main()
