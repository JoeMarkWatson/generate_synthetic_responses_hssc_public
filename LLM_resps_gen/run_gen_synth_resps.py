import csv
import json
import os
import re
import inspect
import argparse
from pathlib import Path

from config import DATA_DIR, SCALES_INFO_DIR
from io_utils import (
    read_items_from_ipip_dat,
    read_items_from_test_info_csv,
    write_jsonl,
    write_csv,
    read_txt_config,
)
from persona_generator import (
    generate_base_personas,
    generate_trait_percentiles,
    percentile_label,
)
from prompt_builder import (
    build_prompt_full,
    build_prompt_fullV1_2,
    build_prompt_fullV2,
    build_prompt_fullV2_1,
    build_prompt_fullV2_1_1,
    build_prompt_fullV2_1_1_no_probabilities,
    build_prompt_fullV2_1_no_trait,
    build_prompt_fullV2_1_1_no_trait,
    build_prompt_fullV2_1_no_demogs,
    build_prompt_fullV2_1_1_no_demogs,
    build_prompt_fullV2_1_no_detail_variation,
    build_prompt_fullV2_1_1_no_detail_variation,
    build_prompt_fullV2_1_no_assoc_explan,
    build_prompt_fullV2_1_1_no_assoc_explan,
    build_prompt_fullV2_2,
    build_prompt_fullV2_3,
    build_prompt_single_answer_demogs,
    build_prompt_single_answer_trait,
)
from response_generator_dist import (
    generate_distribution_responses_for_jobs,
    generate_responses_full_legacy,
    generate_responses_full,
    generate_responses_fullV2,
    generate_responses_fullV2_1,
    generate_responses_fullV2_1_1,
    generate_responses_fullV2_1_1_no_probabilities,
    generate_responses_fullV2_2,
    generate_responses_fullV2_3,
    generate_responses_fullV2_1_no_trait,
    generate_responses_fullV2_1_1_no_trait,
    generate_responses_fullV2_1_no_demogs,
    generate_responses_fullV2_1_1_no_demogs,
    generate_responses_fullV2_1_no_detail_variation,
    generate_responses_fullV2_1_1_no_detail_variation,
    generate_responses_fullV2_1_no_assoc_explan,
    generate_responses_fullV2_1_1_no_assoc_explan,
    generate_responses_single_answer_demogs,
    generate_responses_single_answer_trait,
)

# Persona selection supports:
# - "all"
# - "first:n" or "1:n"
# - "last:n"
# - "start:end" (inclusive, 1-based)
MAX_WORKERS = 38 #  38 seems stable for DeepSeek (and OpenAI when not rate limited) # 10 maybe better for Mistral
ALLOWED_SCALES = (
    "Extraversion",
    "Openness",
    "Neuroticism",
    "Agreeableness",
    "Conscientiousness",
    "Work_conscientiousness",
    "Work_honesty_humility",
)
ALLOWED_PROMPT_TYPES = (
    "single_answer_demogs",
    "single_answer_trait",
    "full",
    "fullV1.2",
    "fullV2",
    "fullV2.1",
    "fullV2.1_no_trait",
    "fullV2.1_no_demogs",
    "fullV2.1_no_detail_variation",
    "fullV2.1_no_assoc_explan",
    "fullV2.1.1",
    "fullV2.1.1_no_probabilities",
    "fullV2.1.1_no_trait",
    "fullV2.1.1_no_demogs",
    "fullV2.1.1_no_detail_variation",
    "fullV2.1.1_no_assoc_explan",
    "fullV2.2",
    "fullV2.3",
)


# WHICH_PERSONAS = "first:3"
WHICH_PERSONAS = "all"
SCALES_TO_RUN = [
    "Openness",
    "Neuroticism",
    "Agreeableness",
    "Conscientiousness",
    "Work_conscientiousness",
    "Work_honesty_humility",
]
PROMPT_TYPES_TO_RUN = ["fullV2.1.1_no_detail_variation"]
MODULE_DIR = Path(__file__).resolve().parent
DEFAULT_MODEL = os.getenv("OPENROUTER_MODEL", "deepseek/deepseek-v4-flash")
DEFAULT_TEMPERATURE = float(os.getenv("OPENROUTER_TEMPERATURE", "0"))
STANDARD_MODEL = "deepseek/deepseek-v4-flash"
STANDARD_TEMPERATURE = 0.0
MODEL_OUTPUT_LABELS = {
    "nvidia/nemotron-3-nano-30b-a3b": "nvidia",
    "openai/gpt-5.6-luna": "openai",
    "anthropic/claude-haiku-5.5": "anthropic_claude_haiku_5_5",
    "qwen/qwen3.8-27b:floor": "qwen_qwen3_8_27b",
    "mistralai/mistral-small-2603:floor": "mistralai_mistral_small_2603",
    "mistralai/mistral-small-2603:nitro": "mistralai_mistral_small_2603_nitro",
    "xiaomi/mimo-v2.6-flash": "xiaomi_mimo_v2_6_flash",
    "z-ai/glm-5.3-flash": "glm_5_3_flash",
    "z-ai/glm-5.3-flash:floor": "glm_5_3_flash",
}
RUN_CONFIGS = [
    {
        "model": "xiaomi/mimo-v2.6-flash",
        "temperature": 0,
    },
]


def _prompt_output_name(prompt_type):
    if prompt_type == "full":
        return "synth_item_responses_full.csv"
    if prompt_type == "fullV1.2":
        return "synth_item_responses_fullV1.2.csv"
    if prompt_type == "fullV2":
        return "synth_item_responses_fullV2.csv"
    if prompt_type == "fullV2.1":
        return "synth_item_responses_fullV2.1.csv"
    if prompt_type == "fullV2.1.1":
        return "synth_item_responses_fullV2.1.1.csv"
    if prompt_type == "fullV2.1.1_no_probabilities":
        return "synth_item_responses_fullV2.1.1_no_probabilities.csv"
    if prompt_type == "fullV2.2":
        return "synth_item_responses_fullV2.2.csv"
    if prompt_type == "fullV2.3":
        return "synth_item_responses_fullV2.3.csv"
    if prompt_type == "fullV2.1_no_trait":
        return "synth_item_responses_fullV2.1_no_trait.csv"
    if prompt_type == "fullV2.1.1_no_trait":
        return "synth_item_responses_fullV2.1.1_no_trait.csv"
    if prompt_type == "fullV2.1_no_demogs":
        return "synth_item_responses_fullV2.1_no_demogs.csv"
    if prompt_type == "fullV2.1.1_no_demogs":
        return "synth_item_responses_fullV2.1.1_no_demogs.csv"
    if prompt_type == "fullV2.1_no_detail_variation":
        return "synth_item_responses_fullV2.1_no_detail_variation.csv"
    if prompt_type == "fullV2.1.1_no_detail_variation":
        return "synth_item_responses_fullV2.1.1_no_detail_variation.csv"
    if prompt_type == "fullV2.1_no_assoc_explan":
        return "synth_item_responses_fullV2.1_no_assoc_explan.csv"
    if prompt_type == "fullV2.1.1_no_assoc_explan":
        return "synth_item_responses_fullV2.1.1_no_assoc_explan.csv"
    if prompt_type == "single_answer_demogs":
        return "synth_item_responses_single_answer_demogs.csv"
    if prompt_type == "single_answer_trait":
        return "synth_item_responses_single_answer_trait.csv"
    return f"synth_item_responses_{prompt_type}V1.2.csv"


def _slugify_run_token(value):
    return re.sub(r"[^a-z0-9]+", "_", str(value).lower()).strip("_") or "value"


def _format_temperature(temperature):
    numeric = float(temperature)
    if numeric.is_integer():
        return str(int(numeric))
    return str(numeric).rstrip("0").rstrip(".")


def _run_label(model, temperature):
    suffix_parts = []
    if model != STANDARD_MODEL:
        suffix_parts.append(MODEL_OUTPUT_LABELS.get(model, _slugify_run_token(model)))
    if float(temperature) != STANDARD_TEMPERATURE:
        suffix_parts.append(f"temp{_slugify_run_token(_format_temperature(temperature))}")
    return "__".join(suffix_parts)


def _output_path_for_run(output_dir, prompt_type, model, temperature):
    base_name = PROMPT_SPECS[prompt_type]["output_name"]
    run_label = _run_label(model, temperature)
    if not run_label:
        return output_dir / base_name

    path = Path(base_name)
    return output_dir / f"{path.stem}__{run_label}{path.suffix}"

PROMPT_SPECS = {
    "full": {
        "builder": build_prompt_full,
        "generator": generate_responses_full_legacy,
        "output_name": _prompt_output_name("full"),
        "header": ["persona_id", "item_id", "response", "dist_1", "dist_2", "dist_3", "dist_4", "dist_5", "dist_6", "dist_7", "dist_8", "dist_9", "dist_10"],
        "uses_dist_columns": True,
    },
    "fullV1.2": {
        "builder": build_prompt_fullV1_2,
        "generator": generate_responses_full,
        "output_name": _prompt_output_name("fullV1.2"),
        "header": ["persona_id", "item_id", "response", "dist_1", "dist_2", "dist_3", "dist_4", "dist_5", "dist_6", "dist_7", "dist_8", "dist_9", "dist_10"],
        "uses_dist_columns": True,
    },
    "fullV2": {
        "builder": build_prompt_fullV2,
        "generator": generate_responses_fullV2,
        "output_name": _prompt_output_name("fullV2"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1": {
        "builder": build_prompt_fullV2_1,
        "generator": generate_responses_fullV2_1,
        "output_name": _prompt_output_name("fullV2.1"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1.1": {
        "builder": build_prompt_fullV2_1_1,
        "generator": generate_responses_fullV2_1_1,
        "output_name": _prompt_output_name("fullV2.1.1"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1.1_no_probabilities": {
        "builder": build_prompt_fullV2_1_1_no_probabilities,
        "generator": generate_responses_fullV2_1_1_no_probabilities,
        "output_name": _prompt_output_name("fullV2.1.1_no_probabilities"),
        "header": ["persona_id", "item_id", "response"],
        "uses_dist_columns": False,
    },
    "fullV2.1_no_trait": {
        "builder": build_prompt_fullV2_1_no_trait,
        "generator": generate_responses_fullV2_1_no_trait,
        "output_name": _prompt_output_name("fullV2.1_no_trait"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1.1_no_trait": {
        "builder": build_prompt_fullV2_1_1_no_trait,
        "generator": generate_responses_fullV2_1_1_no_trait,
        "output_name": _prompt_output_name("fullV2.1.1_no_trait"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1_no_demogs": {
        "builder": build_prompt_fullV2_1_no_demogs,
        "generator": generate_responses_fullV2_1_no_demogs,
        "output_name": _prompt_output_name("fullV2.1_no_demogs"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1.1_no_demogs": {
        "builder": build_prompt_fullV2_1_1_no_demogs,
        "generator": generate_responses_fullV2_1_1_no_demogs,
        "output_name": _prompt_output_name("fullV2.1.1_no_demogs"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1_no_detail_variation": {
        "builder": build_prompt_fullV2_1_no_detail_variation,
        "generator": generate_responses_fullV2_1_no_detail_variation,
        "output_name": _prompt_output_name("fullV2.1_no_detail_variation"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1.1_no_detail_variation": {
        "builder": build_prompt_fullV2_1_1_no_detail_variation,
        "generator": generate_responses_fullV2_1_1_no_detail_variation,
        "output_name": _prompt_output_name("fullV2.1.1_no_detail_variation"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1_no_assoc_explan": {
        "builder": build_prompt_fullV2_1_no_assoc_explan,
        "generator": generate_responses_fullV2_1_no_assoc_explan,
        "output_name": _prompt_output_name("fullV2.1_no_assoc_explan"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.1.1_no_assoc_explan": {
        "builder": build_prompt_fullV2_1_1_no_assoc_explan,
        "generator": generate_responses_fullV2_1_1_no_assoc_explan,
        "output_name": _prompt_output_name("fullV2.1.1_no_assoc_explan"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.2": {
        "builder": build_prompt_fullV2_2,
        "generator": generate_responses_fullV2_2,
        "output_name": _prompt_output_name("fullV2.2"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "fullV2.3": {
        "builder": build_prompt_fullV2_3,
        "generator": generate_responses_fullV2_3,
        "output_name": _prompt_output_name("fullV2.3"),
        "header": ["persona_id", "item_id", "response", "prob_1", "prob_2", "prob_3", "prob_4", "prob_5"],
        "uses_dist_columns": False,
    },
    "single_answer_demogs": {
        "builder": build_prompt_single_answer_demogs,
        "generator": generate_responses_single_answer_demogs,
        "output_name": _prompt_output_name("single_answer_demogs"),
        "header": ["persona_id", "item_id", "response"],
        "uses_dist_columns": False,
    },
    "single_answer_trait": {
        "builder": build_prompt_single_answer_trait,
        "generator": generate_responses_single_answer_trait,
        "output_name": _prompt_output_name("single_answer_trait"),
        "header": ["persona_id", "item_id", "response"],
        "uses_dist_columns": False,
    },
}


def _first_existing_path(candidates):
    for candidate in candidates:
        if candidate is not None and candidate.exists():
            return candidate
    return None


def _slugify_construct_name(construct_name):
    slug = re.sub(r"[^a-z0-9]+", "_", construct_name.lower()).strip("_")
    slug = slug.replace("judgement", "judgment")
    return slug or "construct"


def _normalize_scale_selector(value):
    token = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    token = token.removesuffix("_info")
    token = token.replace("judgement", "judgment")
    return token


def _is_reverse_coded_item(item):
    raw = item.get("reverse_coded", 0)
    if isinstance(raw, str):
        token = raw.strip().lower()
        if token in {"1", "true", "yes", "y"}:
            return True
        if token in {"0", "false", "no", "n", ""}:
            return False
        try:
            return float(token) != 0
        except Exception:
            return False
    try:
        return float(raw) != 0
    except Exception:
        return bool(raw)


def _load_construct_info_entries():
    env_dir = os.getenv("SCALES_INFO_DIR")
    scales_info_root = Path(env_dir).expanduser().resolve() if env_dir else SCALES_INFO_DIR
    if not scales_info_root.exists():
        raise FileNotFoundError(
            f"Scales info directory not found: {scales_info_root}. "
            "Provide SCALES_INFO_DIR or create scales_info with *_info subdirectories."
        )

    construct_dirs = sorted(
        p
        for p in scales_info_root.iterdir()
        if p.is_dir() and p.name.endswith("_info")
    )
    if not construct_dirs:
        raise FileNotFoundError(
            f"No '*_info' construct directories found under {scales_info_root}."
        )

    entries = []
    for construct_dir in construct_dirs:
        name_path = _first_existing_path([
            construct_dir / "construct_name.txt",
            construct_dir / "construct_name",
        ])
        desc_path = _first_existing_path([
            construct_dir / "construct_desc.txt",
            construct_dir / "construct_desc",
        ])
        items_path = _first_existing_path([
            construct_dir / "scale_items.csv",
            construct_dir / "test_items.csv",
        ])

        if construct_dir.name == "Extraversion_info":
            ipip_dat_path = DATA_DIR / "human_data_details" / "ipip" / "IPIP300.dat"
            if ipip_dat_path.exists():
                items_path = ipip_dat_path

        if name_path is not None:
            construct_name = read_txt_config(name_path).strip()
        else:
            inferred = construct_dir.name
            if inferred.endswith("_info"):
                inferred = inferred.removesuffix("_info")
            construct_name = inferred.replace("_", " ")
            print(
                f"Warning: no construct_name file found in {construct_dir}. "
                f"Using inferred name '{construct_name}'."
            )

        if desc_path is not None:
            construct_description = read_txt_config(desc_path).strip()
        else:
            construct_description = (
                "No construct description provided in scales_info for this construct."
            )

        entries.append({
            "construct_name": construct_name,
            "construct_description": construct_description,
            "construct_slug": _slugify_construct_name(construct_name),
            "construct_dir": construct_dir,
            "name_path": name_path,
            "desc_path": desc_path,
            "items_path": items_path,
        })

    return entries, scales_info_root


def _filter_construct_entries(construct_entries, scales_to_run):
    if not scales_to_run:
        return construct_entries

    wanted = [_normalize_scale_selector(name) for name in scales_to_run]
    filtered = []
    for requested in wanted:
        for entry in construct_entries:
            entry_aliases = {
                _normalize_scale_selector(entry["construct_name"]),
                _normalize_scale_selector(entry["construct_slug"]),
                _normalize_scale_selector(entry["construct_dir"].name),
            }
            if requested in entry_aliases:
                filtered.append(entry)
                break

    if not filtered:
        available = ", ".join(sorted(entry["construct_slug"] for entry in construct_entries))
        raise ValueError(
            f"No requested scales were found for {sorted(wanted)}. Available scales: {available}"
        )
    return filtered


def _validate_prompt_types(prompt_types):
    alias_map = {prompt_type.lower(): prompt_type for prompt_type in ALLOWED_PROMPT_TYPES}
    selected = []
    for prompt_type in prompt_types:
        normalized = prompt_type.strip().lower()
        canonical = alias_map.get(normalized)
        if canonical not in ALLOWED_PROMPT_TYPES:
            raise ValueError(
                f"Unsupported prompt type '{prompt_type}'. "
                f"Allowed: {', '.join(ALLOWED_PROMPT_TYPES)}"
            )
        if canonical not in selected:
            selected.append(canonical)
    if not selected:
        raise ValueError("PROMPT_TYPES_TO_RUN must include at least one prompt type.")
    return selected


def _persona_id_sort_key(persona_id):
    token = str(persona_id).strip().lower()
    match = re.fullmatch(r"p(\d+)", token)
    if match:
        return (0, int(match.group(1)))
    return (1, token)


def _parse_persona_selection(selector, total_personas):
    token = str(selector).strip().lower()
    if not token:
        raise ValueError("WHICH_PERSONAS must not be empty.")

    if token == "all":
        return list(range(total_personas))

    first_match = re.fullmatch(r"first\s*:?\s*(\d+)", token)
    if first_match:
        count = int(first_match.group(1))
        if count < 1:
            raise ValueError("first:n must use n >= 1.")
        return list(range(0, min(count, total_personas)))

    last_match = re.fullmatch(r"last\s*:?\s*(\d+)", token)
    if last_match:
        count = int(last_match.group(1))
        if count < 1:
            raise ValueError("last:n must use n >= 1.")
        start = max(0, total_personas - count)
        return list(range(start, total_personas))

    range_match = re.fullmatch(r"(\d+)\s*[:\-]\s*(\d+)", token)
    if range_match:
        start = int(range_match.group(1))
        end = int(range_match.group(2))
        if start < 1 or end < 1:
            raise ValueError("Persona ranges are 1-based and must start at 1 or later.")
        if end < start:
            raise ValueError("Persona range end must be >= start.")
        if end > total_personas:
            raise ValueError(
                f"Persona range {start}:{end} exceeds available personas ({total_personas})."
            )
        return list(range(start - 1, end))

    raise ValueError(
        "Unsupported WHICH_PERSONAS value. Use 'all', 'first:n', 'last:n', or 'start:end'."
    )


def _select_personas(personas, selector):
    indices = _parse_persona_selection(selector, len(personas))
    return [personas[idx] for idx in indices]


def _load_existing_csv_rows(path):
    path = Path(path)
    if not path.exists() or path.stat().st_size == 0:
        return []

    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _merge_response_rows(existing_rows, new_rows):
    merged = {}
    for row in existing_rows:
        persona_id = row.get("persona_id")
        item_id = row.get("item_id")
        if persona_id is None or item_id is None:
            continue
        merged[(persona_id, item_id)] = row

    for row in new_rows:
        persona_id = row.get("persona_id")
        item_id = row.get("item_id")
        if persona_id is None or item_id is None:
            raise ValueError("Response rows must include persona_id and item_id.")
        merged[(persona_id, item_id)] = row

    return list(merged.values())


def _sort_response_rows(rows, item_order):
    def sort_key(row):
        return (
            _persona_id_sort_key(row.get("persona_id")),
            item_order.get(row.get("item_id"), len(item_order)),
        )

    return sorted(rows, key=sort_key)


def _filter_missing_response_jobs(personas, items, existing_rows):
    """Return personas needing at least one response, plus already-complete rows.

    The caller uses this to exclude fully completed persona-item grids while
    scheduling only the missing item jobs for incomplete personas.
    """
    expected_items = {str(item["item_id"]) for item in items}
    existing_by_persona = {}
    for row in existing_rows:
        persona_id = row.get("persona_id")
        item_id = row.get("item_id")
        if persona_id is not None and item_id is not None:
            existing_by_persona.setdefault(str(persona_id), set()).add(str(item_id))

    complete_ids = {
        str(persona["persona_id"])
        for persona in personas
        if expected_items.issubset(existing_by_persona.get(str(persona["persona_id"]), set()))
    }
    return complete_ids, existing_by_persona


def _first_option_number(options_text):
    first_option = options_text.split(";")[0].strip()
    if ")" not in first_option:
        return 1
    token = first_option.split(")", 1)[0].strip()
    try:
        return int(token)
    except Exception:
        return 1


def _load_global_synth_sample_config():
    candidates = [
        MODULE_DIR / "synth_sample_config.json",
        MODULE_DIR / "synth_sample_config",
    ]
    config_path = _first_existing_path(candidates)
    if config_path is None:
        raise FileNotFoundError(
            "Could not find global synth sample config. Expected one of: "
            f"{MODULE_DIR / 'synth_sample_config.json'} or "
            f"{MODULE_DIR / 'synth_sample_config'}."
        )

    with open(config_path, encoding="utf-8") as f:
        config = json.load(f)

    missing_keys = [k for k in ("n", "theta", "demographics") if k not in config]
    if missing_keys:
        raise KeyError(f"{config_path} missing required keys: {missing_keys}")
    return config, config_path


def _load_scale_synth_config(construct_dir, global_synth_config, global_synth_config_path):
    candidates = [
        construct_dir / "synth_sample_config.json",
        construct_dir / "synth_sample_config",
    ]
    config_path = _first_existing_path(candidates)
    if config_path is None:
        return global_synth_config, global_synth_config_path

    with open(config_path, encoding="utf-8") as f:
        config = json.load(f)

    merged = dict(global_synth_config)
    merged.update(config)

    missing_keys = [k for k in ("theta",) if k not in merged]
    if missing_keys:
        raise KeyError(f"{config_path} missing required keys: {missing_keys}")
    return merged, config_path


def _load_jsonl(path):
    with open(path, "r", encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def _base_personas_match_demographics(base_personas, expected_keys):
    if not base_personas:
        return False

    for persona in base_personas:
        if set(persona.keys()) != expected_keys:
            return False
    return True


def _load_or_generate_base_personas(base_persona_path, n, synth_config, construct_dir):
    demogs = synth_config["demographics"]
    expected_keys = {"persona_id", *demogs.keys()}

    if base_persona_path.exists():
        print(f"Loading existing base personas from {base_persona_path}...")
        personas = _load_jsonl(base_persona_path)
        if _base_personas_match_demographics(personas, expected_keys):
            return personas

        print(
            "Existing base personas do not match the current demographic schema; "
            "regenerating them."
        )

    print(f"Generating {n} base personas...")
    personas = generate_base_personas(n, demogs)
    write_jsonl(base_persona_path, personas)
    return personas


def _load_or_generate_trait_personas(trait_persona_path, n, theta_conf):
    if trait_persona_path.exists():
        print(f"Loading existing trait personas from {trait_persona_path}...")
        return _load_jsonl(trait_persona_path)

    print(f"Generating {n} trait percentiles...")
    trait_personas = generate_trait_percentiles(n, theta_conf)
    write_jsonl(trait_persona_path, trait_personas)
    return trait_personas


def _merge_base_and_trait_personas(base_personas, trait_personas, trait_name):
    trait_by_id = {}
    for row in trait_personas:
        persona_id = row.get("persona_id")
        if persona_id is not None:
            trait_by_id[persona_id] = row

    merged = []
    for base in base_personas:
        persona_id = base.get("persona_id")
        trait_row = trait_by_id.get(persona_id)
        if trait_row is None:
            raise ValueError(
                f"Trait personas are missing persona_id '{persona_id}'. "
                "Delete synth_personas_trait to regenerate it."
            )
        percentile = int(trait_row["trait_percentile"])
        percentile = max(1, min(99, percentile))
        label = percentile_label(percentile)

        merged_row = dict(base)
        merged_row["trait_percentile"] = percentile
        merged_row["theta_description"] = (
            f"A level of '{trait_name}' higher than {percentile}% of the population ({label})."
        )
        merged.append(merged_row)
    return merged


def _get_construct_output_paths(output_dir):
    return {
        prompt_type: output_dir / spec["output_name"]
        for prompt_type, spec in PROMPT_SPECS.items()
    }


def _write_empty_construct_outputs(output_dir, prompt_types):
    output_paths = _get_construct_output_paths(output_dir)
    saved_paths = []

    for prompt_type in prompt_types:
        write_csv(output_paths[prompt_type], [], header=PROMPT_SPECS[prompt_type]["header"])
        saved_paths.append(output_paths[prompt_type])

    return saved_paths


def _print_sample_prompt(
    prompt_type,
    prompt_builder,
    persona,
    item,
    construct_name,
    construct_description,
    extra_prompt_kwargs=None,
):
    builder_params = inspect.signature(prompt_builder).parameters
    prompt_kwargs = {
        "persona": persona,
        "item": item,
        "construct_name": construct_name,
        "retry_suffix": "",
    }
    if "construct_description" in builder_params:
        prompt_kwargs["construct_description"] = construct_description
    for key, value in (extra_prompt_kwargs or {}).items():
        if key in builder_params:
            prompt_kwargs[key] = value
    prompt = prompt_builder(**prompt_kwargs)
    print("")
    print(f"--- BEGIN SAMPLE PROMPT [{construct_name} | {prompt_type}] ---")
    print(prompt)
    print(f"--- END SAMPLE PROMPT [{construct_name} | {prompt_type}] ---")
    print("")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        default=None,
        help=(
            "Run one OpenRouter model instead of RUN_CONFIGS, e.g. "
            "deepseek/deepseek-v4-flash, openai/gpt-5.6-luna, "
            "nvidia/nemotron-3-nano-30b-a3b, z-ai/glm-5.3-flash:floor, "
            "anthropic/claude-haiku-5.5, qwen/qwen3.8-27b:floor, "
            "mistralai/mistral-small-2603:floor, "
            "mistralai/mistral-small-2603:nitro, "
            "xiaomi/mimo-v2.6-flash"
        ),
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=DEFAULT_TEMPERATURE,
        help="Temperature to use with --model. Ignored for the default RUN_CONFIGS.",
    )
    parser.add_argument(
        "--scale",
        nargs="+",
        choices=ALLOWED_SCALES,
        default=SCALES_TO_RUN,
        help="One or more scales to run in the supplied order.",
    )
    parser.add_argument(
        "--prompt-type",
        default=None,
        help="Run one allowed prompt type instead of PROMPT_TYPES_TO_RUN.",
    )
    parser.add_argument(
        "--personas",
        default=None,
        help="Select personas (all, first:n, last:n, or start:end) instead of WHICH_PERSONAS.",
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=MAX_WORKERS,
        help=f"Maximum concurrent API workers (default: {MAX_WORKERS}).",
    )
    args = parser.parse_args()

    if args.max_workers < 1:
        parser.error("--max-workers must be at least 1.")

    if args.model:
        run_configs = [{
            "model": args.model.strip(),
            "temperature": args.temperature,
        }]
    else:
        run_configs = RUN_CONFIGS

    print("Loading configuration and input files...")
    selected_prompt_types = _validate_prompt_types(
        [args.prompt_type] if args.prompt_type else PROMPT_TYPES_TO_RUN
    )
    persona_selector = args.personas or WHICH_PERSONAS
    construct_entries, scales_info_root = _load_construct_info_entries()
    construct_entries = _filter_construct_entries(construct_entries, args.scale)
    global_synth_config, global_synth_config_path = _load_global_synth_sample_config()

    print(f"Using scales info root: {scales_info_root}")
    print(f"Using global synth sample config: {global_synth_config_path}")
    construct_names = [entry["construct_name"] for entry in construct_entries]

    max_workers = args.max_workers

    print(f"Scales to process: {', '.join(construct_names)}")
    print(f"Prompt types to generate: {', '.join(selected_prompt_types)}")
    print(f"Persona selection: {persona_selector}")
    print(f"Max API workers: {max_workers}")
    print("OpenRouter runs:")
    for run_config in run_configs:
        print(
            f" - model={run_config['model']}, "
            f"temperature={_format_temperature(run_config['temperature'])}"
        )

    all_saved_paths = []
    all_persona_paths = []

    for construct_entry in construct_entries:
        construct_name = construct_entry["construct_name"]
        construct_description = construct_entry["construct_description"]
        construct_slug = construct_entry["construct_slug"]
        scale_name = construct_entry["construct_dir"].name.removesuffix("_info")
        construct_output_dir = DATA_DIR / scale_name.lower() / "llm_responses"
        construct_output_dir.mkdir(parents=True, exist_ok=True)

        print("")
        print(f"=== Construct: {construct_name} ===")
        print(f"Output directory: {construct_output_dir}")
        if construct_entry["name_path"] is not None:
            print(f"Using construct name file: {construct_entry['name_path']}")
        if construct_entry["desc_path"] is not None:
            print(f"Using construct desc file: {construct_entry['desc_path']}")

        synth_config, synth_config_path = _load_scale_synth_config(
            construct_entry["construct_dir"],
            global_synth_config=global_synth_config,
            global_synth_config_path=global_synth_config_path,
        )
        if synth_config_path.parent == construct_entry["construct_dir"]:
            print(f"Using synth config file: {synth_config_path}")
        else:
            print(
                "No scale-specific synth config found; using global synth config: "
                f"{synth_config_path}"
            )

        base_persona_path = construct_output_dir / "synth_personas_base"
        base_personas = _load_or_generate_base_personas(
            base_persona_path=base_persona_path,
            n=int(synth_config["n"]),
            synth_config=synth_config,
            construct_dir=construct_entry["construct_dir"],
        )
        all_persona_paths.append(base_persona_path)

        item_info_path = construct_entry["items_path"]
        if item_info_path is not None:
            print(f"Using item info file: {item_info_path}")
            if item_info_path.suffix.lower() == ".dat":
                items = read_items_from_ipip_dat(
                    item_info_path,
                    metadata_path=construct_entry["construct_dir"] / "scale_items.csv",
                )
            else:
                items = read_items_from_test_info_csv(item_info_path)
            original_item_count = len(items)
            items = [item for item in items if "i" not in str(item.get("item_id", ""))]
            excluded_count = original_item_count - len(items)
            if excluded_count > 0:
                print(
                    f"Excluded {excluded_count} item(s) with lowercase 'i' in item_code before response generation."
                )
        else:
            print(
                f"Warning: no scale-items CSV found in {construct_entry['construct_dir']}. "
                "Response CSVs will be written with headers only."
            )
            items = []

        theta_conf = synth_config["theta"]
        configured_n = synth_config.get("n")
        if configured_n is not None and int(configured_n) != len(base_personas):
            print(
                "Warning: scale-specific synth config n="
                f"{configured_n} differs from base persona count={len(base_personas)}. "
                "Using base persona count."
            )

        trait_persona_path = construct_output_dir / "synth_personas_trait"
        trait_personas = _load_or_generate_trait_personas(
            trait_persona_path=trait_persona_path,
            n=len(base_personas),
            theta_conf=theta_conf,
        )
        personas = _merge_base_and_trait_personas(
            base_personas=base_personas,
            trait_personas=trait_personas,
            trait_name=construct_name,
        )
        all_persona_paths.append(trait_persona_path)
        selected_personas = _select_personas(personas, persona_selector)
        if not selected_personas:
            raise ValueError(f"Persona selector '{persona_selector}' selected no personas.")
        print(
            f"Selected personas: {len(selected_personas)} "
            f"(from {selected_personas[0]['persona_id']} to {selected_personas[-1]['persona_id']})"
        )

        if not items:
            for run_config in run_configs:
                for prompt_type in selected_prompt_types:
                    output_path = _output_path_for_run(
                        output_dir=construct_output_dir,
                        prompt_type=prompt_type,
                        model=run_config["model"],
                        temperature=run_config["temperature"],
                    )
                    write_csv(
                        output_path,
                        [],
                        header=PROMPT_SPECS[prompt_type]["header"],
                    )
                    all_saved_paths.append(output_path)
            print("No items found; wrote header-only response CSVs.")
            continue

        print("Generating synthetic responses...")
        for run_config in run_configs:
            selected_model = run_config["model"]
            selected_temperature = run_config["temperature"]
            print(
                f"Running OpenRouter model: {selected_model} "
                f"(temperature={_format_temperature(selected_temperature)})"
            )
            for prompt_type in selected_prompt_types:
                spec = PROMPT_SPECS[prompt_type]
                output_path = _output_path_for_run(
                    output_dir=construct_output_dir,
                    prompt_type=prompt_type,
                    model=selected_model,
                    temperature=selected_temperature,
                )
                print(f"Running prompt type: {prompt_type}")
                existing_rows = _load_existing_csv_rows(output_path)
                complete_persona_ids, existing_by_persona = _filter_missing_response_jobs(
                    selected_personas,
                    items,
                    existing_rows,
                )
                missing_jobs = [
                    (persona, item)
                    for persona in selected_personas
                    for item in items
                    if str(item["item_id"])
                    not in existing_by_persona.get(str(persona["persona_id"]), set())
                ]
                if not missing_jobs:
                    print(
                        f"All {len(selected_personas)} selected personas already have "
                        "responses for every item; skipping API generation."
                    )
                    all_saved_paths.append(output_path)
                    continue

                print(
                    f"Resume status: {len(complete_persona_ids)} complete personas skipped; "
                    f"{len(missing_jobs)} missing persona-item response(s) queued."
                )
                _print_sample_prompt(
                    prompt_type=prompt_type,
                    prompt_builder=spec["builder"],
                    persona=missing_jobs[0][0],
                    item=missing_jobs[0][1],
                    construct_name=construct_name,
                    construct_description=construct_description,
                )
                responses = generate_distribution_responses_for_jobs(
                    missing_jobs,
                    construct_name,
                    construct_description,
                    prompt_builder=spec["builder"],
                    prompt_label=prompt_type,
                    max_workers=max_workers,
                    model=selected_model,
                    temperature=selected_temperature,
                )
                merged_rows = _merge_response_rows(existing_rows, responses)
                merged_rows = _sort_response_rows(
                    merged_rows,
                    item_order={item["item_id"]: idx for idx, item in enumerate(items)},
                )
                write_csv(output_path, merged_rows, header=spec["header"])
                print(f"Saved: {output_path}")
                all_saved_paths.append(output_path)

    print("")
    print("Files saved:")
    for output_path in all_saved_paths + all_persona_paths:
        print(f" - {output_path.resolve()} (Exists: {output_path.exists()})")
