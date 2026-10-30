import csv
import json
from pathlib import Path


def _parse_reverse_coded_flag(raw_value):
    if raw_value is None:
        return 0
    if isinstance(raw_value, str):
        token = raw_value.strip().lower()
        if token in {"", "0", "false", "no", "n"}:
            return 0
        if token in {"1", "true", "yes", "y"}:
            return 1
        try:
            return 1 if float(token) != 0 else 0
        except Exception:
            return 0
    try:
        return 1 if float(raw_value) != 0 else 0
    except Exception:
        return 0


def read_items_from_test_info_csv(path):
    items = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for idx, row in enumerate(reader, start=1):
            item_id = (row.get("item_code") or f"item_{idx}").strip()
            item_stem = (row.get("item_stem") or "").strip()
            item_text = (row.get("item_text") or "").strip()
            question = f"{item_stem} {item_text}".strip()

            option_labels = []
            for i in range(1, 6):
                label = (row.get(f"response_{i}") or "").strip()
                if label:
                    option_labels.append(f"{i}) {label}")

            items.append({
                "item_id": item_id,
                "item_stem": item_stem,
                "item_text": item_text,
                "question": question,
                "options": "; ".join(option_labels),
                "reverse_coded": _parse_reverse_coded_flag(row.get("reverse_coded")),
            })
    return items


def read_items_from_ipip_dat(dat_path, metadata_path=None):
    """
    Load IPIP item metadata while using the .dat file as the canonical data source.

    The .dat file is a respondent response matrix and does not itself carry the
    item stems/text needed for prompt construction, so this loader validates the
    .dat source exists and then reuses the curated item metadata file.
    """
    dat_path = Path(dat_path)
    if not dat_path.exists():
        raise FileNotFoundError(f"IPIP data file not found: {dat_path}")

    if metadata_path is None:
        metadata_path = dat_path.with_name("scale_items.csv")

    metadata_path = Path(metadata_path)
    if not metadata_path.exists():
        raise FileNotFoundError(
            f"IPIP item metadata file not found: {metadata_path}. "
            "Need a CSV with item stems/text alongside the .dat response matrix."
        )

    return read_items_from_test_info_csv(metadata_path)


def read_ipip_demographic_rows(dat_path, fraction=0.5, from_end=True):
    """
    Read a fraction of IPIP-NEO-300 rows and extract demographics.

    The raw file is fixed-width. The documented layout is:
    - SEX at column 7
    - AGE at columns 8-9
    - COUNTRY at columns 23-33
    """
    dat_path = Path(dat_path)
    if not dat_path.exists():
        raise FileNotFoundError(f"IPIP data file not found: {dat_path}")

    if not (0 < fraction <= 1):
        raise ValueError("fraction must be in the interval (0, 1].")

    total_rows = 0
    with open(dat_path, "r", encoding="latin1", errors="replace") as f:
        for _ in f:
            total_rows += 1

    if from_end:
        start_row = int(total_rows * (1 - fraction))
        end_row = total_rows
    else:
        start_row = 0
        end_row = int(total_rows * fraction)
    start_row = max(0, min(total_rows, start_row))
    end_row = max(start_row, min(total_rows, end_row))

    rows = []
    with open(dat_path, "r", encoding="latin1", errors="replace") as f:
        for idx, line in enumerate(f):
            if idx < start_row or idx >= end_row:
                continue
            raw = line.rstrip("\r\n")
            if len(raw) < 33:
                continue

            sex_raw = raw[6:7].strip()
            age_raw = raw[7:9].strip()
            country_raw = raw[22:33].strip()

            if sex_raw == "1":
                gender = "M"
            elif sex_raw == "2":
                gender = "F"
            else:
                continue

            try:
                age = int(age_raw)
            except Exception:
                continue

            if not country_raw:
                continue

            rows.append({
                "gender": gender,
                "age": age,
                "country": country_raw,
            })

    if not rows:
        raise ValueError(f"No demographic rows could be parsed from {dat_path}")

    return rows

def read_txt_config(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

def write_jsonl(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for item in data:
            f.write(json.dumps(item) + "\n")

def write_csv(path, rows, header):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=header)
        writer.writeheader()
        writer.writerows(rows)
