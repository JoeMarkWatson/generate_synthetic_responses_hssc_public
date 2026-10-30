from concurrent.futures import ThreadPoolExecutor, as_completed
import random
import json
from prompt_builder import (
    build_prompt_fullV1_2 as build_prompt_logprob,
    build_prompt_fullV2_1_no_trait as build_prompt_logprob2,
    build_prompt_fullV2_1_no_demogs as build_prompt_naive_logprob,
)
from llm_client import query_deepseek_logprobs


def parse_logprobs(logprobs_dict, option_numbers):
    option_strs = [str(o) for o in option_numbers]

    content_entries = (logprobs_dict or {}).get("content", [])
    token_probs = content_entries[0].get("top_logprobs", []) if content_entries else []

    prob_dict = {}
    for entry in token_probs:
        token = (entry.get("token") or "").strip()
        if token not in option_strs:
            continue
        try:
            prob_dict[int(token)] = round(pow(10, entry["logprob"]), 4)
        except Exception:
            continue

    total = sum(prob_dict.values())
    if total > 0:
        prob_dict = {k: v / total for k, v in prob_dict.items()}
        most_likely = max(prob_dict, key=prob_dict.get)
        sampled = random.choices(list(prob_dict.keys()), weights=prob_dict.values())[0]
    else:
        most_likely = sampled = "NA"

    return most_likely, sampled, prob_dict


def _generate_logprob_rows_for_job(
    persona,
    item,
    construct_name,
    construct_description,
    prompt_builder=build_prompt_logprob,
    model=None,
):
    option_numbers = [int(opt.strip().split(")")[0]) for opt in item["options"].split(";")]
    prompt = prompt_builder(persona, item, construct_name, construct_description)

    try:
        _, logprobs_dict = query_deepseek_logprobs(prompt, model=model)
        most_likely, sampled, probs = parse_logprobs(logprobs_dict, option_numbers)
    except Exception as exc:
        print(f"⚠️ Logprob API call failed for {persona['persona_id']} / {item['item_id']}: {exc}")
        most_likely, sampled, probs = "NA", "NA", {}

    row_single = {
        "persona_id": persona["persona_id"],
        "item_id": item["item_id"],
        "response": most_likely,
    }
    row_logprob = {
        "persona_id": persona["persona_id"],
        "item_id": item["item_id"],
        "response": sampled,
        "logprobs": json.dumps(probs),
    }
    return row_single, row_logprob


def generate_responses_logprob(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    prompt_builder=build_prompt_logprob,
    prompt_label="logprob",
    model=None,
):
    selected_personas = personas
    if max_personas is not None:
        selected_personas = personas[:max_personas]

    jobs = []
    for p_idx, persona in enumerate(selected_personas):
        for i_idx, item in enumerate(items):
            jobs.append((p_idx, i_idx, persona, item))

    rows_single = []
    rows_logprob = []
    if not jobs:
        return rows_single, rows_logprob

    max_workers = max(1, int(max_workers))
    total_jobs = len(jobs)
    print(
        f"Generating {prompt_label} responses with {max_workers} worker(s) "
        f"for {len(selected_personas)} personas x {len(items)} items ({total_jobs} API jobs)..."
    )

    if max_workers == 1:
        for idx, (_, _, persona, item) in enumerate(jobs, start=1):
            row_single, row_logprob = _generate_logprob_rows_for_job(
                persona,
                item,
                construct_name,
                construct_description,
                prompt_builder,
                model,
            )
            rows_single.append(row_single)
            rows_logprob.append(row_logprob)
            if idx % 25 == 0 or idx == total_jobs:
                print(f"{prompt_label}: completed {idx}/{total_jobs} jobs")
        return rows_single, rows_logprob

    indexed_rows = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_idx = {
            executor.submit(
                _generate_logprob_rows_for_job,
                persona,
                item,
                construct_name,
                construct_description,
                prompt_builder,
                model,
            ): (p_idx, i_idx)
            for p_idx, i_idx, persona, item in jobs
        }
        done_count = 0
        for future in as_completed(future_to_idx):
            p_idx, i_idx = future_to_idx[future]
            row_single, row_logprob = future.result()
            indexed_rows.append((p_idx, i_idx, row_single, row_logprob))
            done_count += 1
            if done_count % 25 == 0 or done_count == total_jobs:
                print(f"{prompt_label}: completed {done_count}/{total_jobs} jobs")

    indexed_rows.sort(key=lambda x: (x[0], x[1]))
    rows_single.extend(row_single for _, _, row_single, _ in indexed_rows)
    rows_logprob.extend(row_logprob for _, _, _, row_logprob in indexed_rows)

    return rows_single, rows_logprob


def generate_responses_logprob2(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
):
    _, rows_logprob2 = generate_responses_logprob(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        max_personas=max_personas,
        max_workers=max_workers,
        prompt_builder=build_prompt_logprob2,
        prompt_label="logprob2",
        model=model,
    )
    return rows_logprob2


def generate_responses_naive_logprob(
    personas,
    items,
    construct_name,
    construct_description,
    max_personas=None,
    max_workers=1,
    model=None,
):
    _, rows_naive_logprob = generate_responses_logprob(
        personas=personas,
        items=items,
        construct_name=construct_name,
        construct_description=construct_description,
        max_personas=max_personas,
        max_workers=max_workers,
        prompt_builder=build_prompt_naive_logprob,
        prompt_label="naive_logprob",
        model=model,
    )
    return rows_naive_logprob
