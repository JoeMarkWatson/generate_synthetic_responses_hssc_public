from collections import OrderedDict
import csv
import struct
import argparse
from pathlib import Path


HERE = Path(__file__).resolve().parent
DATA_DIR = HERE.parents[1]
IPIP_DIR = HERE
IPIP_DAT_PATH = IPIP_DIR / "IPIP300.dat"
IPIP_ITEM_KEY_PATH = IPIP_DIR / "IPIP-NEO-ItemKey.xls"

ALLOWED_SCALES = {
    "Extraversion": "E",
    "Openness": "O",
    "Neuroticism": "N",
    "Agreeableness": "A",
    "Conscientiousness": "C",
}


def _ole_sector_offset(sector_size, sector_index):
    return sector_size * (sector_index + 1)


def _read_ole_stream(path, stream_name):
    data = path.read_bytes()

    if data[:8] != b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1":
        raise ValueError(f"{path} is not an OLE compound file")

    sector_shift = struct.unpack_from("<H", data, 30)[0]
    sector_size = 1 << sector_shift
    num_fat_sectors = struct.unpack_from("<I", data, 44)[0]
    first_dir_sector = struct.unpack_from("<I", data, 48)[0]
    first_difat_sector = struct.unpack_from("<I", data, 68)[0]
    num_difat_sectors = struct.unpack_from("<I", data, 72)[0]

    difat = list(struct.unpack_from("<109I", data, 76))
    fat_sectors = [
        sector for sector in difat
        if sector != 0xFFFFFFFF
    ]

    next_difat_sector = first_difat_sector

    for _ in range(num_difat_sectors):
        if next_difat_sector in (0xFFFFFFFE, 0xFFFFFFFF):
            break

        sector_start = _ole_sector_offset(
            sector_size,
            next_difat_sector,
        )
        entries_per_sector = sector_size // 4

        sector_entries = struct.unpack_from(
            f"<{entries_per_sector}I",
            data,
            sector_start,
        )

        fat_sectors.extend(
            sector
            for sector in sector_entries[:-1]
            if sector != 0xFFFFFFFF
        )

        next_difat_sector = sector_entries[-1]

    fat = []

    for sector in fat_sectors[:num_fat_sectors]:
        sector_start = _ole_sector_offset(sector_size, sector)

        fat.extend(
            struct.unpack_from(
                f"<{sector_size // 4}I",
                data,
                sector_start,
            )
        )

    def sector_chain(start_sector):
        chain = []
        sector = start_sector

        while sector not in (0xFFFFFFFE, 0xFFFFFFFF):
            chain.append(sector)

            if sector >= len(fat):
                raise ValueError(
                    f"Invalid OLE FAT sector reference: {sector}"
                )

            sector = fat[sector]

        return chain

    directory_data = bytearray()

    for sector in sector_chain(first_dir_sector):
        sector_start = _ole_sector_offset(sector_size, sector)

        directory_data.extend(
            data[sector_start:sector_start + sector_size]
        )

    entries = []

    for offset in range(0, len(directory_data), 128):
        entry = directory_data[offset:offset + 128]

        if len(entry) < 128:
            continue

        name_length = struct.unpack_from("<H", entry, 64)[0]

        if name_length < 2:
            continue

        name = entry[:name_length - 2].decode(
            "utf-16le",
            errors="ignore",
        )

        obj_type = entry[66]
        start_sector = struct.unpack_from("<I", entry, 116)[0]
        stream_size = struct.unpack_from("<Q", entry, 120)[0]

        entries.append(
            {
                "name": name,
                "type": obj_type,
                "start_sector": start_sector,
                "stream_size": stream_size,
            }
        )

    target_entry = None

    for entry in entries:
        if entry["name"] == stream_name and entry["type"] == 2:
            target_entry = entry
            break

    if target_entry is None:
        raise FileNotFoundError(
            f"Could not find {stream_name!r} stream in {path}"
        )

    stream = bytearray()

    for sector in sector_chain(target_entry["start_sector"]):
        sector_start = _ole_sector_offset(sector_size, sector)

        stream.extend(
            data[sector_start:sector_start + sector_size]
        )

    return bytes(stream[:target_entry["stream_size"]])


def _read_biff_records(stream):
    offset = 0

    while offset + 4 <= len(stream):
        opcode, size = struct.unpack_from("<HH", stream, offset)
        offset += 4

        payload = stream[offset:offset + size]
        offset += size

        yield opcode, payload


def _read_biff_sst(workbook_stream):
    records = list(_read_biff_records(workbook_stream))
    sst_chunks = []

    for idx, (opcode, payload) in enumerate(records):
        if opcode != 0x00FC:  # SST
            continue

        sst_chunks.append(payload)

        for next_opcode, next_payload in records[idx + 1:]:
            if next_opcode == 0x003C:  # CONTINUE
                sst_chunks.append(next_payload)
                continue

            break

        break

    if not sst_chunks:
        return []

    chunk_idx = 0
    chunk_pos = 0

    def read_bytes(size, continued=False):
        nonlocal chunk_idx, chunk_pos

        parts = bytearray()
        remaining = size

        while remaining > 0 and chunk_idx < len(sst_chunks):
            chunk = sst_chunks[chunk_idx]

            if chunk_pos >= len(chunk):
                chunk_idx += 1
                chunk_pos = 0

                if continued and chunk_idx < len(sst_chunks):
                    # A continued BIFF string begins with a new
                    # string-encoding option byte.
                    chunk_pos = 1

                continue

            take = min(remaining, len(chunk) - chunk_pos)

            parts.extend(
                chunk[chunk_pos:chunk_pos + take]
            )

            chunk_pos += take
            remaining -= take

        if remaining > 0:
            raise ValueError(
                "Unexpected end of SST payload while decoding strings"
            )

        return bytes(parts)

    shared_strings = []

    _total_count, unique_count = struct.unpack(
        "<II",
        read_bytes(8),
    )

    for _ in range(unique_count):
        char_count = struct.unpack("<H", read_bytes(2))[0]
        options = read_bytes(1)[0]

        if options & 0x04:
            rich_text_runs = struct.unpack("<H", read_bytes(2))[0]
        else:
            rich_text_runs = 0

        if options & 0x08:
            asian_phonetic_size = struct.unpack(
                "<I",
                read_bytes(4),
            )[0]
        else:
            asian_phonetic_size = 0

        is_16bit = bool(options & 0x01)

        if is_16bit:
            string = read_bytes(
                char_count * 2,
                continued=True,
            ).decode("utf-16le")
        else:
            string = read_bytes(
                char_count,
                continued=True,
            ).decode("latin1")

        if rich_text_runs:
            read_bytes(
                rich_text_runs * 4,
                continued=True,
            )

        if asian_phonetic_size:
            read_bytes(
                asian_phonetic_size,
                continued=True,
            )

        shared_strings.append(string)

    return shared_strings


def _coerce_item_number(value, row_idx):
    if value is None:
        raise ValueError(
            f"Missing Full# value in item-key row {row_idx + 1}"
        )

    try:
        number = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(
            f"Invalid Full# value {value!r} in item-key "
            f"row {row_idx + 1}"
        ) from exc

    if isinstance(value, float) and not value.is_integer():
        raise ValueError(
            f"Non-integer Full# value {value!r} in item-key "
            f"row {row_idx + 1}"
        )

    if not 1 <= number <= 300:
        raise ValueError(
            f"Full# value {number} is outside the expected range 1–300"
        )

    return number


def _decode_biff_rk(raw_value):
    """Decode a BIFF RK numeric value."""
    multiply_by_100 = bool(raw_value & 0x01)
    is_integer = bool(raw_value & 0x02)

    if is_integer:
        signed_value = struct.unpack(
            "<i",
            struct.pack("<I", raw_value),
        )[0]
        value = signed_value >> 2
    else:
        ieee_bits = (raw_value & 0xFFFFFFFC) << 32
        value = struct.unpack(
            "<d",
            struct.pack("<Q", ieee_bits),
        )[0]

    if multiply_by_100:
        value /= 100

    return value


def _read_response_positions(scale):
    target_trait = ALLOWED_SCALES[scale]
    workbook_stream = _read_ole_stream(
        IPIP_ITEM_KEY_PATH,
        "Workbook",
    )

    shared_strings = _read_biff_sst(workbook_stream)

    sheet_offsets = []

    for opcode, payload in _read_biff_records(workbook_stream):
        if opcode == 0x0085:  # BOUNDSHEET
            sheet_offsets.append(
                struct.unpack_from("<I", payload, 0)[0]
            )

    if not sheet_offsets:
        raise ValueError(
            f"Could not locate worksheet data in "
            f"{IPIP_ITEM_KEY_PATH}"
        )

    selected_rows = None
    header_row = None
    key_col = None
    full_number_col = None

    for sheet_offset in sheet_offsets:
        row_values = {}

        for opcode, payload in _read_biff_records(
            workbook_stream[sheet_offset:]
        ):
            if opcode == 0x0809:  # BOF
                continue

            if opcode == 0x000A:  # EOF
                break

            if opcode == 0x0203:  # NUMBER
                row, col = struct.unpack_from("<HH", payload, 0)
                value = struct.unpack_from("<d", payload, 6)[0]

                row_values.setdefault(row, {})[col] = value

            elif opcode == 0x027E:  # RK
                row, col = struct.unpack_from("<HH", payload, 0)
                raw_value = struct.unpack_from("<I", payload, 6)[0]
                value = _decode_biff_rk(raw_value)

                row_values.setdefault(row, {})[col] = value

            elif opcode == 0x00BD:  # MULRK
                row, first_col = struct.unpack_from("<HH", payload, 0)
                last_col = struct.unpack_from(
                    "<H",
                    payload,
                    len(payload) - 2,
                )[0]

                number_of_cells = last_col - first_col + 1

                for cell_idx in range(number_of_cells):
                    record_offset = 4 + (cell_idx * 6)

                    # The first two bytes are the formatting index.
                    raw_value = struct.unpack_from(
                        "<I",
                        payload,
                        record_offset + 2,
                    )[0]

                    col = first_col + cell_idx
                    value = _decode_biff_rk(raw_value)

                    row_values.setdefault(row, {})[col] = value

            elif opcode == 0x00FD:  # LABELSST
                row, col = struct.unpack_from("<HH", payload, 0)
                sst_index = struct.unpack_from("<I", payload, 6)[0]

                row_values.setdefault(row, {})[col] = (
                    shared_strings[sst_index]
                )

            elif opcode == 0x0204:  # LABEL
                row, col = struct.unpack_from("<HH", payload, 0)
                text = payload[8:].decode(
                    "latin1",
                    errors="replace",
                )

                row_values.setdefault(row, {})[col] = text

        current_header_row = None
        current_key_col = None
        current_full_number_col = None

        for row_idx in sorted(row_values):
            cells = row_values[row_idx]

            for col_idx, value in cells.items():
                header_text = str(value).strip()

                if header_text == "Key":
                    current_key_col = col_idx
                elif header_text == "Full#":
                    current_full_number_col = col_idx

            if (
                current_key_col is not None
                and current_full_number_col is not None
            ):
                current_header_row = row_idx
                break

        if current_header_row is not None:
            selected_rows = row_values
            header_row = current_header_row
            key_col = current_key_col
            full_number_col = current_full_number_col
            break

    if (
        selected_rows is None
        or header_row is None
        or key_col is None
        or full_number_col is None
    ):
        raise ValueError(
            f"Could not find both 'Key' and 'Full#' columns in "
            f"{IPIP_ITEM_KEY_PATH}"
        )

    ext_items = []
    nuisance_items = {}

    valid_target_keys = {f"{target_trait}{facet}" for facet in range(1, 7)}
    nuisance_traits = tuple(
        trait for trait in ("N", "E", "O", "A", "C")
        if trait != target_trait
    )
    nuisance_keys = {trait: f"{trait}1" for trait in nuisance_traits}

    for row_idx in sorted(selected_rows):
        if row_idx <= header_row:
            continue

        cells = selected_rows[row_idx]

        key_value = cells.get(key_col)
        full_number_value = cells.get(full_number_col)

        if key_value is None or full_number_value is None:
            continue

        key_text = str(key_value).strip().upper()

        full_number = _coerce_item_number(
            full_number_value,
            row_idx,
        )

        if key_text in valid_target_keys:
            ext_items.append(
                {
                    "full_number": full_number,
                    "key": key_text,
                }
            )

        for trait, target_key in nuisance_keys.items():
            if (
                key_text == target_key
                and trait not in nuisance_items
            ):
                nuisance_items[trait] = {
                    "full_number": full_number,
                    "key": key_text,
                }

    if len(ext_items) != 60:
        raise ValueError(
            f"Expected 60 {scale} items from "
            f"{IPIP_ITEM_KEY_PATH}, got {len(ext_items)}."
        )

    ext_items.sort(
        key=lambda item: item["full_number"]
    )

    ext_positions = [
        item["full_number"]
        for item in ext_items
    ]

    if len(set(ext_positions)) != 60:
        raise ValueError(
            f"The {scale} Full# mapping contains duplicate positions."
        )

    if set(nuisance_items) != set(nuisance_traits):
        raise ValueError(
            "Expected to find the first nuisance items for "
            f"{', '.join(nuisance_traits)}, but found "
            f"{sorted(nuisance_items)}."
        )

    return ext_positions, {
        trait: nuisance_items[trait]["full_number"]
        for trait in nuisance_traits
    }


def _read_scale_response_fields(scale):
    scale_items_path = DATA_DIR.parent / "scales_info" / f"{scale}_info" / "scale_items.csv"
    with scale_items_path.open(newline="", encoding="utf-8") as file:
        rows = list(csv.DictReader(file))

    if len(rows) != 64:
        raise ValueError(f"Expected 64 items in {scale_items_path}, got {len(rows)}.")

    target_fields = [row["item_code"] for row in rows[:60]]
    nuisance_fields = [row["item_code"] for row in rows[60:]]
    return target_fields, nuisance_fields


def _parse_row(raw_line, target_positions, nuisance_positions, target_fields, nuisance_fields):
    raw = raw_line.rstrip("\r\n")

    if len(raw) < 33:
        return None

    sex_raw = raw[6:7].strip()
    age_raw = raw[7:9].strip()
    country_raw = raw[22:33].strip()
    responses_raw = raw[33:]

    if sex_raw == "1":
        gender = "M"
    elif sex_raw == "2":
        gender = "F"
    else:
        return None

    try:
        age = int(age_raw)
    except (TypeError, ValueError):
        return None

    if not country_raw:
        return None

    if len(responses_raw) < 300:
        return None

    responses = list(responses_raw[:300])

    if len(responses) != 300:
        return None

    if any(value.strip() == "" for value in responses):
        return None

    target_responses = [
        responses[position - 1]
        for position in target_positions
    ]

    if len(target_responses) != 60:
        raise ValueError(
            f"Expected 60 target responses, got {len(target_responses)}."
        )

    nuisance_responses = [
        responses[nuisance_positions[trait] - 1]
        for trait in nuisance_positions
    ]

    if len(nuisance_responses) != 4:
        raise ValueError(
            f"Expected 4 nuisance responses, "
            f"got {len(nuisance_responses)}."
        )

    row = OrderedDict()
    row["gender"] = gender
    row["age"] = age
    row["country"] = country_raw

    for field_name, value in zip(
        target_fields,
        target_responses,
    ):
        row[field_name] = value

    for field_name, value in zip(
        nuisance_fields,
        nuisance_responses,
    ):
        row[field_name] = value

    return row


def _write_csv(path, rows, target_fields, nuisance_fields):
    path.parent.mkdir(parents=True, exist_ok=True)

    if not rows:
        raise ValueError(f"No rows available for {path}")

    fieldnames = (
        ["gender", "age", "country"]
        + target_fields
        + nuisance_fields
    )

    with path.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as file:
        writer = csv.DictWriter(
            file,
            fieldnames=fieldnames,
        )

        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scale", choices=tuple(ALLOWED_SCALES), default="Extraversion")
    args = parser.parse_args()
    scale = args.scale

    if not IPIP_DAT_PATH.exists():
        raise FileNotFoundError(
            f"Missing IPIP source: {IPIP_DAT_PATH}"
        )

    if not IPIP_ITEM_KEY_PATH.exists():
        raise FileNotFoundError(
            f"Missing IPIP item key: {IPIP_ITEM_KEY_PATH}"
        )

    target_positions, nuisance_positions = _read_response_positions(scale)
    target_fields, nuisance_fields = _read_scale_response_fields(scale)

    print(f"{scale} source positions:", target_positions)

    print(
        "Nuisance source positions:",
        nuisance_positions,
    )

    parsed_rows = []

    with IPIP_DAT_PATH.open(
        "r",
        encoding="latin1",
        errors="replace",
    ) as file:
        for raw_line in file:
            parsed = _parse_row(
                raw_line,
                target_positions,
                nuisance_positions,
                target_fields,
                nuisance_fields,
            )

            if parsed is not None:
                parsed_rows.append(parsed)

    if not parsed_rows:
        raise ValueError(
            f"No usable rows were parsed from {IPIP_DAT_PATH}"
        )

    split_idx = len(parsed_rows) // 2

    training_rows = parsed_rows[:split_idx]
    test_rows = parsed_rows[split_idx:]

    output_dir = DATA_DIR / scale.lower() / "human_responses"
    train_path = output_dir / "human_train_responses.csv"
    test_path = output_dir / "human_test_responses.csv"

    _write_csv(train_path, training_rows, target_fields, nuisance_fields)
    _write_csv(test_path, test_rows, target_fields, nuisance_fields)

    print(
        f"Wrote {len(training_rows)} training rows to {train_path}"
    )

    print(
        f"Wrote {len(test_rows)} test rows to {test_path}"
    )


if __name__ == "__main__":
    main()
