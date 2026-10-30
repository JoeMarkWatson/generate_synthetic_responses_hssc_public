from concurrent.futures import ThreadPoolExecutor, as_completed
import inspect
import json
import random
import re
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
    extract_response_option_labels,
    build_prompt_single_answer_demogs,
    build_prompt_single_answer_trait,
)
from llm_client import query_deepseek

RETRY_SUFFIX_DIST = """
Your previous output did not match the required format.
Return ONLY a comma-separated list of exactly 10 integers.
Each integer must be one of the option numbers shown in Options.
No extra text or symbols.
"""

RETRY_SUFFIX_SINGLE = """
Your previous output did not match the required format.
Return ONLY a single integer.
The integer must be one of the option numbers shown in Options.
No extra text or symbols.
"""

RETRY_SUFFIX_SINGLE_LABEL_TEMPLATE = """
Your previous output did not match the required format.
Return ONLY one of these literal response-option labels: {option_labels}.
No extra text or symbols.
"""

RETRY_SUFFIX_PROBS = """
Your previous output did not match the required format.
Return ONLY five probabilities, separated by commas.
Use exactly two decimal places for each probability.
The five probabilities must sum to exactly 1.00.
No extra text or symbols.
"""

RETRY_SUFFIX_PROBS_JSON_TEMPLATE = """
Your previous output did not match the required format.
Return ONLY one JSON object with exactly these keys in this order:
{option_example}
Use exactly two decimal places for every probability.
The five probabilities must sum to exactly 1.00.
No extra text or symbols.
"""

PROBABILITY_OUTPUT_MAX_TOKENS = 128


def extract_10_integers(text):
    cleaned = (text or "").strip()
    match = re.match(r"^\s*((?:-?\d+\s*,\s*){9}-?\d+)(?:\s*[^0-9,].*)?$", cleaned)
    if not match:
        return None
    try:
        values = [int(x.strip()) for x in match.group(1).split(",")]
    except Exception:
        return None
    return values if len(values) == 10 else None


def extract_single_integer(text):
    token = (text or "").strip()
    if not re.fullmatch(r"-?\d+", token):
        return None
    try:
        return int(token)
    except Exception:
        return None


def extract_single_option_label(text, option_labels):
    token = (text or "").strip()
    return token if token in option_labels else None


def parse_option_numbers(options_text):
    return [int(opt.strip().split(")")[0]) for opt in options_text.split(";")]


def parse_five_probabilities(text, option_labels):
    cleaned = (text or "").strip()
    if not cleaned:
        return None

    def _normalize_values(values):
        if len(values) != 5:
            return None
        try:
            numeric_values = [float(value) for value in values]
        except Exception:
            return None
        if any(v < 0 for v in numeric_values):
            return None
        total = sum(numeric_values)
        if total <= 0:
            return None
        return [value / total for value in numeric_values]

    def _from_mapping(mapping):
        if set(mapping.keys()) != set(option_labels):
            return None
        values = []
        for key in option_labels:
            values.append(mapping[key])
        return _normalize_values(values)

    def _from_fragment(fragment):
        matches = re.findall(
            r'"(?:' + "|".join(re.escape(label) for label in option_labels) + r')"\s*:\s*(-?\d+(?:\.\d+)?)',
            fragment,
        )
        return _normalize_values(matches)

    try:
        parsed = json.loads(cleaned)
    except Exception:
        parsed = None

    if isinstance(parsed, dict):
        values = _from_mapping(parsed)
        if values is not None:
            return values

    fragment_values = _from_fragment(cleaned)
    if fragment_values is not None:
        return fragment_values

    matches = re.findall(r"(?<!\d)(?:0(?:\.\d+)?|1(?:\.0+)?)", cleaned)
    if len(matches) != 5:
        return None
    return _normalize_values(matches)


def _retry_suffix_probs_json(options_text):
    labels = extract_response_option_labels(options_text)
    example = "{" + ",".join(f"{json.dumps(label)}:0.00" for label in labels) + "}"
    return RETRY_SUFFIX_PROBS_JSON_TEMPLATE.format(option_example=example)


def _build_prompt_with_supported_args(
    prompt_builder,
    persona,
    item,
    construct_name,
    construct_description,
    retry_suffix,
    extra_kwargs=None,
):
    builder_params = inspect.signature(prompt_builder).parameters
    kwargs = {
        "persona": persona,
        "item": item,
        "construct_name": construct_name,
    }
    if "construct_description" in builder_params:
        kwargs["construct_description"] = construct_description
    if "retry_suffix" in builder_params:
        kwargs["retry_suffix"] = retry_suffix
    for key, value in (extra_kwargs or {}).items():
        if key in builder_params:
            kwargs[key] = value
    return prompt_builder(**kwargs)


def query_distribution_with_retry(
    persona,
    item,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    model=None,
    temperature=None,
    max_attempts=3,
    extra_prompt_kwargs=None,
):
    option_numbers = parse_option_numbers(item["options"])
    option_labels = extract_response_option_labels(item["options"])
    retry_suffix = ""

    for attempt in range(max_attempts):
        prompt = _build_prompt_with_supported_args(
            prompt_builder=prompt_builder,
            persona=persona,
            item=item,
            construct_name=construct_name,
            construct_description=construct_description,
            retry_suffix=retry_suffix,
            extra_kwargs=extra_prompt_kwargs,
        )
        try:
            response_text = query_deepseek(prompt, model=model, temperature=temperature)
        except Exception as exc:
            print(f"⚠️ API call failed ({prompt_label}, attempt {attempt + 1}/{max_attempts}): {exc}")
            retry_suffix = RETRY_SUFFIX_DIST
            continue
        responses = extract_10_integers(response_text)

        if responses is None:
            print(f"⚠️ Failed to parse 10 integer responses: {response_text}")
            retry_suffix = RETRY_SUFFIX_DIST
            continue

        invalid_values = [v for v in responses if v not in option_numbers]
        if invalid_values:
            print(f"⚠️ Found out-of-range options {invalid_values} in: {response_text}")
            retry_suffix = RETRY_SUFFIX_DIST
            continue

        return responses

    return ["NA"] * 10


def query_single_with_retry(
    persona,
    item,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    model=None,
    temperature=None,
    max_attempts=3,
    response_mode="integer",
):
    option_numbers = parse_option_numbers(item["options"])
    option_labels = extract_response_option_labels(item["options"])
    retry_suffix = ""

    for attempt in range(max_attempts):
        prompt = _build_prompt_with_supported_args(
            prompt_builder=prompt_builder,
            persona=persona,
            item=item,
            construct_name=construct_name,
            construct_description=construct_description,
            retry_suffix=retry_suffix,
        )
        try:
            response_text = query_deepseek(prompt, model=model, temperature=temperature)
        except Exception as exc:
            print(f"⚠️ API call failed ({prompt_label}, attempt {attempt + 1}/{max_attempts}): {exc}")
            retry_suffix = (
                RETRY_SUFFIX_SINGLE
                if response_mode == "integer"
                else RETRY_SUFFIX_SINGLE_LABEL_TEMPLATE.format(
                    option_labels=", ".join(option_labels)
                )
            )
            continue

        if response_mode == "integer":
            response = extract_single_integer(response_text)
        elif response_mode == "literal_label":
            label = extract_single_option_label(response_text, option_labels)
            response = option_numbers[option_labels.index(label)] if label is not None else None
        else:
            raise ValueError(f"Unsupported single-response mode: {response_mode}")
        if response is None:
            if response_mode == "integer":
                print(f"⚠️ Failed to parse single integer response: {response_text}")
                retry_suffix = RETRY_SUFFIX_SINGLE
            else:
                print(f"⚠️ Failed to parse literal response option label: {response_text}")
                retry_suffix = RETRY_SUFFIX_SINGLE_LABEL_TEMPLATE.format(
                    option_labels=", ".join(option_labels)
                )
            continue
        if response not in option_numbers:
            print(f"⚠️ Found out-of-range option {response} in: {response_text}")
            retry_suffix = (
                RETRY_SUFFIX_SINGLE
                if response_mode == "integer"
                else RETRY_SUFFIX_SINGLE_LABEL_TEMPLATE.format(
                    option_labels=", ".join(option_labels)
                )
            )
            continue

        return response

    return "NA"


def query_distribution_probs_with_retry(
    persona,
    item,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    model=None,
    temperature=None,
    max_attempts=3,
):
    option_numbers = parse_option_numbers(item["options"])
    option_labels = extract_response_option_labels(item["options"])
    if len(option_numbers) != 5:
        raise ValueError(
            f"{prompt_label} expects exactly 5 response options, got {len(option_numbers)}."
        )

    retry_suffix = ""

    for attempt in range(max_attempts):
        prompt = _build_prompt_with_supported_args(
            prompt_builder=prompt_builder,
            persona=persona,
            item=item,
            construct_name=construct_name,
            construct_description=construct_description,
            retry_suffix=retry_suffix,
        )
        try:
            response_text = query_deepseek(
                prompt,
                model=model,
                temperature=temperature,
                max_tokens=PROBABILITY_OUTPUT_MAX_TOKENS,
            )
        except Exception as exc:
            print(f"⚠️ API call failed ({prompt_label}, attempt {attempt + 1}/{max_attempts}): {exc}")
            retry_suffix = _retry_suffix_probs_json(item["options"]) if prompt_label.startswith("fullV2.1") or prompt_label in {"fullV2.2", "fullV2.3"} else RETRY_SUFFIX_PROBS
            continue

        probs = parse_five_probabilities(response_text, option_labels)
        if probs is None:
            print(f"⚠️ Failed to parse five probabilities: {response_text}")
            retry_suffix = _retry_suffix_probs_json(item["options"]) if prompt_label.startswith("fullV2.1") or prompt_label in {"fullV2.2", "fullV2.3"} else RETRY_SUFFIX_PROBS
            continue

        return probs

    return None


def _generate_row_for_job(
    persona,
    item,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    model=None,
    temperature=None,
):
    responses = query_distribution_with_retry(
        persona=persona,
        item=item,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=prompt_builder,
        prompt_label=prompt_label,
        model=model,
        temperature=temperature,
    )

    selected = random.choice(responses) if responses else "NA"
    row = {
        "persona_id": persona["persona_id"],
        "item_id": item["item_id"],
        "response": selected,
    }
    for i, val in enumerate(responses):
        row[f"dist_{i + 1}"] = val
    return row


def _generate_single_row_for_job(
    persona,
    item,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    model=None,
    temperature=None,
    response_mode="integer",
):
    response = query_single_with_retry(
        persona=persona,
        item=item,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=prompt_builder,
        prompt_label=prompt_label,
        model=model,
        temperature=temperature,
        response_mode=response_mode,
    )

    return {
        "persona_id": persona["persona_id"],
        "item_id": item["item_id"],
        "response": response,
    }


def _generate_distribution_row_for_job(
    persona,
    item,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    model=None,
    temperature=None,
):
    probs = query_distribution_probs_with_retry(
        persona=persona,
        item=item,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=prompt_builder,
        prompt_label=prompt_label,
        model=model,
        temperature=temperature,
    )

    if probs is None:
        row = {
            "persona_id": persona["persona_id"],
            "item_id": item["item_id"],
            "response": "NA",
        }
        for i in range(5):
            row[f"prob_{i + 1}"] = "NA"
        return row

    option_numbers = parse_option_numbers(item["options"])
    selected = random.choices(option_numbers, weights=probs, k=1)[0]
    row = {
        "persona_id": persona["persona_id"],
        "item_id": item["item_id"],
        "response": selected,
    }
    for i, val in enumerate(probs):
        row[f"prob_{i + 1}"] = round(float(val), 4)
    return row


def _generate_responses(
    personas,
    items,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    model=None,
    temperature=None,
    max_personas=None,
    max_workers=1,
):
    selected_personas = personas
    if max_personas is not None:
        selected_personas = personas[:max_personas]

    jobs = []
    for p_idx, persona in enumerate(selected_personas):
        for i_idx, item in enumerate(items):
            jobs.append((p_idx, i_idx, persona, item))

    rows = []
    if not jobs:
        return rows

    max_workers = max(1, int(max_workers))
    total_jobs = len(jobs)
    print(
        f"Generating {prompt_label} responses with {max_workers} worker(s) "
        f"for {len(selected_personas)} personas x {len(items)} items ({total_jobs} API jobs)..."
    )

    if max_workers == 1:
        for idx, (_, _, persona, item) in enumerate(jobs, start=1):
            rows.append(
                _generate_row_for_job(
                    persona=persona,
                    item=item,
                    construct_name=construct_name,
                    construct_description=construct_description,
                    prompt_builder=prompt_builder,
                    prompt_label=prompt_label,
                    model=model,
                    temperature=temperature,
                )
            )
            if idx % 25 == 0 or idx == total_jobs:
                print(f"{prompt_label}: completed {idx}/{total_jobs} jobs")
        return rows

    indexed_rows = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_idx = {
            executor.submit(
                _generate_row_for_job,
                persona,
                item,
                construct_name,
                construct_description,
                prompt_builder,
                prompt_label,
                model,
                temperature,
            ): (p_idx, i_idx)
            for p_idx, i_idx, persona, item in jobs
        }

        done_count = 0
        for future in as_completed(future_to_idx):
            p_idx, i_idx = future_to_idx[future]
            row = future.result()
            indexed_rows.append((p_idx, i_idx, row))
            done_count += 1
            if done_count % 25 == 0 or done_count == total_jobs:
                print(f"{prompt_label}: completed {done_count}/{total_jobs} jobs")

    indexed_rows.sort(key=lambda x: (x[0], x[1]))
    rows.extend(row for _, _, row in indexed_rows)

    return rows


def generate_distribution_responses_for_jobs(
    jobs,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    max_workers=1,
    model=None,
    temperature=None,
):
    """Generate an explicit set of persona-item jobs with scale-wide progress."""
    jobs = list(jobs)
    total_jobs = len(jobs)
    if total_jobs == 0:
        return []

    max_workers = max(1, int(max_workers))
    progress_interval = max(25, (total_jobs + 99) // 100)
    print(
        f"Generating {prompt_label} responses with {max_workers} worker(s) "
        f"for {total_jobs} missing persona-item response(s) ({total_jobs} API jobs)..."
    )

    indexed_rows = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_idx = {
            executor.submit(
                _generate_distribution_row_for_job,
                persona,
                item,
                construct_name,
                construct_description,
                prompt_builder,
                prompt_label,
                model,
                temperature,
            ): idx
            for idx, (persona, item) in enumerate(jobs)
        }

        done_count = 0
        for future in as_completed(future_to_idx):
            idx = future_to_idx[future]
            indexed_rows.append((idx, future.result()))
            done_count += 1
            if done_count % progress_interval == 0 or done_count == total_jobs:
                print(f"{prompt_label}: completed {done_count}/{total_jobs} jobs")

    indexed_rows.sort(key=lambda row: row[0])
    return [row for _, row in indexed_rows]


def _generate_distribution_responses(
    personas,
    items,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    model=None,
    temperature=None,
    max_personas=None,
    max_workers=1,
):
    selected_personas = personas
    if max_personas is not None:
        selected_personas = personas[:max_personas]

    jobs = []
    for p_idx, persona in enumerate(selected_personas):
        for i_idx, item in enumerate(items):
            jobs.append((p_idx, i_idx, persona, item))

    rows = []
    if not jobs:
        return rows

    max_workers = max(1, int(max_workers))
    total_jobs = len(jobs)
    print(
        f"Generating {prompt_label} responses with {max_workers} worker(s) "
        f"for {len(selected_personas)} personas x {len(items)} items ({total_jobs} API jobs)..."
    )

    if max_workers == 1:
        for idx, (_, _, persona, item) in enumerate(jobs, start=1):
            rows.append(
                _generate_distribution_row_for_job(
                    persona=persona,
                    item=item,
                    construct_name=construct_name,
                    construct_description=construct_description,
                    prompt_builder=prompt_builder,
                    prompt_label=prompt_label,
                    model=model,
                    temperature=temperature,
                )
            )
            if idx % 25 == 0 or idx == total_jobs:
                print(f"{prompt_label}: completed {idx}/{total_jobs} jobs")
        return rows

    indexed_rows = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_idx = {
            executor.submit(
                _generate_distribution_row_for_job,
                persona,
                item,
                construct_name,
                construct_description,
                prompt_builder,
                prompt_label,
                model,
                temperature,
            ): (p_idx, i_idx)
            for p_idx, i_idx, persona, item in jobs
        }

        done_count = 0
        for future in as_completed(future_to_idx):
            p_idx, i_idx = future_to_idx[future]
            row = future.result()
            indexed_rows.append((p_idx, i_idx, row))
            done_count += 1
            if done_count % 25 == 0 or done_count == total_jobs:
                print(f"{prompt_label}: completed {done_count}/{total_jobs} jobs")

    indexed_rows.sort(key=lambda x: (x[0], x[1]))
    rows.extend(row for _, _, row in indexed_rows)

    return rows


def _generate_single_responses(
    personas,
    items,
    construct_name,
    construct_description,
    prompt_builder,
    prompt_label,
    model=None,
    temperature=None,
    max_personas=None,
    max_workers=1,
    response_mode="integer",
):
    selected_personas = personas
    if max_personas is not None:
        selected_personas = personas[:max_personas]

    jobs = []
    for p_idx, persona in enumerate(selected_personas):
        for i_idx, item in enumerate(items):
            jobs.append((p_idx, i_idx, persona, item))

    rows = []
    if not jobs:
        return rows

    max_workers = max(1, int(max_workers))
    total_jobs = len(jobs)
    print(
        f"Generating {prompt_label} responses with {max_workers} worker(s) "
        f"for {len(selected_personas)} personas x {len(items)} items ({total_jobs} API jobs)..."
    )

    if max_workers == 1:
        for idx, (_, _, persona, item) in enumerate(jobs, start=1):
            rows.append(
                _generate_single_row_for_job(
                    persona=persona,
                    item=item,
                    construct_name=construct_name,
                    construct_description=construct_description,
                    prompt_builder=prompt_builder,
                    prompt_label=prompt_label,
                    model=model,
                    temperature=temperature,
                    response_mode=response_mode,
                )
            )
            if idx % 25 == 0 or idx == total_jobs:
                print(f"{prompt_label}: completed {idx}/{total_jobs} jobs")
        return rows

    indexed_rows = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_idx = {
            executor.submit(
                _generate_single_row_for_job,
                persona,
                item,
                construct_name,
                construct_description,
                prompt_builder,
                prompt_label,
                model,
                temperature,
                response_mode,
            ): (p_idx, i_idx)
            for p_idx, i_idx, persona, item in jobs
        }
        done_count = 0
        for future in as_completed(future_to_idx):
            p_idx, i_idx = future_to_idx[future]
            row = future.result()
            indexed_rows.append((p_idx, i_idx, row))
            done_count += 1
            if done_count % 25 == 0 or done_count == total_jobs:
                print(f"{prompt_label}: completed {done_count}/{total_jobs} jobs")

    indexed_rows.sort(key=lambda x: (x[0], x[1]))
    rows.extend(row for _, _, row in indexed_rows)

    return rows


def generate_responses_full(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV1_2,
        prompt_label="full",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_full_legacy(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_full,
        prompt_label="full",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2,
        prompt_label="fullV2",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1,
        prompt_label="fullV2.1",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_1(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_1,
        prompt_label="fullV2.1.1",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_2(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_2,
        prompt_label="fullV2.2",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_3(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_3,
        prompt_label="fullV2.3",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_no_trait(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_no_trait,
        prompt_label="fullV2.1_no_trait",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_1_no_trait(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_1_no_trait,
        prompt_label="fullV2.1.1_no_trait",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_no_demogs(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_no_demogs,
        prompt_label="fullV2.1_no_demogs",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_1_no_demogs(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_1_no_demogs,
        prompt_label="fullV2.1.1_no_demogs",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_no_detail_variation(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_no_detail_variation,
        prompt_label="fullV2.1_no_detail_variation",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_1_no_detail_variation(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_1_no_detail_variation,
        prompt_label="fullV2.1.1_no_detail_variation",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_no_assoc_explan(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_no_assoc_explan,
        prompt_label="fullV2.1_no_assoc_explan",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_1_no_assoc_explan(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_distribution_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_1_no_assoc_explan,
        prompt_label="fullV2.1.1_no_assoc_explan",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_single_answer_demogs(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_single_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_single_answer_demogs,
        prompt_label="single_answer_demogs",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_single_answer_trait(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_single_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_single_answer_trait,
        prompt_label="single_answer_trait",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
    )


def generate_responses_fullV2_1_1_no_probabilities(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    return _generate_single_responses(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        prompt_builder=build_prompt_fullV2_1_1_no_probabilities,
        prompt_label="fullV2.1.1_no_probabilities",
        model=model,
        temperature=temperature,
        max_personas=max_personas,
        max_workers=max_workers,
        response_mode="literal_label",
    )


generate_responses_dist_many = generate_responses_full
generate_responses_dist_many2 = generate_responses_fullV2_1_no_trait
generate_responses_dist_many3 = generate_responses_fullV2_1_no_demogs
generate_responses_dist_many4 = generate_responses_fullV2_1_no_detail_variation
generate_responses_dist_many5 = generate_responses_fullV2_1_no_assoc_explan
generate_responses_dist_single = generate_responses_fullV2_1_no_detail_variation
generate_responses_dist_single_mood = generate_responses_fullV2_1_no_detail_variation
generate_responses_single_pt1_dist_pt2 = generate_responses_fullV2_1_no_assoc_explan


def generate_responses(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
    temperature=None,
):
    """
    Backward-compatible alias preserving previous behavior.
    """
    return generate_responses_full(
        personas,
        items,
        construct_name,
        construct_description,
        max_personas=max_personas,
        max_workers=max_workers,
        model=model,
        temperature=temperature,
    )
