"""Prompt builders for the six-condition prompt-component ablation study."""

import json
import re
from typing import Any, Mapping


__all__ = [
    "build_prompt_fullV1_2",
    "build_prompt_full",
    "build_prompt_fullV2",
    "build_prompt_fullV2_1",
    "build_prompt_fullV2_1_1",
    "build_prompt_fullV2_1_1_no_probabilities",
    "build_prompt_fullV2_1_no_trait",
    "build_prompt_fullV2_1_1_no_trait",
    "build_prompt_fullV2_1_no_demogs",
    "build_prompt_fullV2_1_1_no_demogs",
    "build_prompt_fullV2_1_no_detail_variation",
    "build_prompt_fullV2_1_1_no_detail_variation",
    "build_prompt_fullV2_1_no_assoc_explan",
    "build_prompt_fullV2_1_1_no_assoc_explan",
    "build_prompt_fullV2_2",
    "build_prompt_fullV2_3",
    "build_prompt_single_answer_demogs",
    "build_prompt_single_answer_trait",
]


_RESERVED_PERSONA_KEYS = {
    "persona_id",
    "theta_description",
    "trait_percentile",
    "response_style_ctb",
    "response_style_acq",
}

_NON_FOCAL_BIG5_PERCENTILE_KEYS = {
    "openness_percentile",
    "conscientiousness_percentile",
    "extraversion_percentile",
    "agreeableness_percentile",
    "neuroticism_percentile",
}

PROMPT_VERSION = "V1.2"

_VARIABILITY_INFORMATION = (
    "Responses are not fully determined by the characteristics described above. "
    "They may also be affected by context, interpretation, momentary state, "
    "attention and effort, and ordinary self-report variability."
)


def build_prompt_fullV1_2(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Full prompt V1.2: all five prompt components are included."""
    return _build_prompt(
        persona,
        item,
        construct_name,
        construct_description,
        include_construct_definition=True,
        include_demographics=True,
        multiple_responses=True,
        multiple_people=True,
        include_variability_information=True,
        retry_suffix=retry_suffix,
    )


def build_prompt_full(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Legacy full prompt used before V1.2."""
    question = _required_text(item, "question")
    options = _required_text(item, "options")
    theta_description = _required_text(persona, "theta_description")
    allowed_numbers = _extract_option_numbers(options)
    allowed_numbers_text = ", ".join(str(number) for number in allowed_numbers)

    parts = [
        "A survey question is being completed by 10 people who share the same described profile.",
        "",
        "Shared profile:",
        f"- {_format_construct_level(construct_name, theta_description)}",
    ]

    parts.append(f"- Construct definition: {_clean_inline(construct_description)}")

    demographic_lines = _build_demographic_lines(persona)
    if demographic_lines:
        parts.extend(f"- {line}" for line in demographic_lines)

    parts.extend(
        [
            "",
            f'Survey question: "{question}"',
            f"Response options: {options}",
            "",
            _VARIABILITY_INFORMATION,
            "",
            "What would the 10 people's responses to the survey question be?",
            "Provide exactly one response per person.",
        ]
    )
    parts.extend(_multiple_response_rules(allowed_numbers_text, response_unit="person"))

    suffix = str(retry_suffix or "").strip()
    if suffix:
        parts.extend(["", suffix])

    return "\n".join(parts)


def build_prompt_fullV2(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Distribution prompt: estimate response probabilities across option categories."""
    question = _required_text(item, "question")
    options = _required_text(item, "options")
    theta_description = _required_text(persona, "theta_description")
    allowed_numbers = _extract_option_numbers(options)
    if len(allowed_numbers) != 5:
        raise ValueError(
            f"build_prompt_fullV2 expects exactly 5 response options, got {len(allowed_numbers)}."
        )

    demographic_lines = _build_v2_demographic_lines(persona)
    parts = [
        "Estimate the proportions of responses expected across many different people who share the following described profile.",
        "",
        f'Survey question: "{question}"',
        "",
        f"Response options: {options}",
        "",
        "Shared profile:",
        _format_construct_level(construct_name, theta_description),
        f"{construct_name} definition: {_clean_inline(construct_description)}",
    ]

    if demographic_lines:
        parts.extend(demographic_lines)

    parts.extend(
        [
            "",
            f"Consider the precise meaning of the statement and how each characteristic in the shared profile may affect responses. Determine from the statement itself whether agreement reflects higher {construct_name}, lower {construct_name}, or neither. Higher {construct_name} should make higher-numbered responses more likely in the first case, lower-numbered responses more likely in the second, and should not systematically shift responses in the third.",
            "",
            "Although these people share the described profile, they differ in other personal characteristics, context, interpretation, momentary state, attention and effort, and ordinary response tendencies. Reflect these differences in a realistic distribution across the five response options. The amount of variation should depend on the particular statement, with some statements producing more consistent responses than others.",
            "",
            "Output rules:",
            "",
            "Write exactly five probabilities, corresponding in order to response options 1, 2, 3, 4 and 5.",
            "Use exactly two decimal places for every probability.",
            "The five probabilities must sum to exactly 1.00.",
            "Format: 0.00, 0.00, 0.00, 0.00, 0.00",
            "Do not add any words, labels, or explanation.",
        ]
    )

    suffix = str(retry_suffix or "").strip()
    if suffix:
        parts.extend(["", suffix])

    return "\n".join(parts)


def _build_prompt_fullV2_1_variant(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    *,
    retry_suffix: str = "",
    include_trait_level: bool = True,
    include_trait_definition: bool = True,
    include_demographics: bool = True,
    include_detail_variation: bool = True,
    include_assoc_explan: bool = True,
    include_literal_estimation_sentence: bool = True,
) -> str:
    question = _required_text(item, "question")
    options = _required_text(item, "options")
    theta_description = _required_text(persona, "theta_description")
    allowed_numbers = _extract_option_numbers(options)
    if len(allowed_numbers) != 5:
        raise ValueError(
            f"build_prompt_fullV2_1 expects exactly 5 response options, got {len(allowed_numbers)}."
        )

    parts = [
        "Estimate the proportions of responses expected across many different people who share the following described profile.",
        "",
        f'Survey question: "{question}"',
        "",
        "Response options:",
        "",
        _format_v21_response_options(options),
        "",
        "Shared profile:",
    ]

    profile_lines = []
    if include_trait_level:
        profile_lines.append(f"* {_format_construct_level(construct_name, theta_description)}")
    if include_trait_definition:
        profile_lines.append(f"* {construct_name} definition: {_clean_inline(construct_description)}")

    demographic_lines = _build_v2_demographic_lines(persona)
    if include_demographics and demographic_lines:
        profile_lines.extend(f"* {line}" for line in demographic_lines)

    if profile_lines:
        parts.append("")
        parts.extend(profile_lines)

    instruction_lines = []
    if include_detail_variation:
        variation_instruction = (
            "Although they share the described profile, they differ in other personal characteristics, context, interpretation, momentary state, attention and effort, and ordinary response tendencies, so allow realistic, item-specific variation."
        )
        if include_literal_estimation_sentence:
            variation_instruction = (
                "Using the statement's precise meaning and all the shared-profile characteristics, estimate the proportion of people who would select each literal response option. "
                f"{variation_instruction}"
            )
        instruction_lines.append(variation_instruction)
    if include_assoc_explan:
        instruction_lines.append(
            f"The statement may be associated with higher {construct_name}, lower {construct_name}, or neither; do not reverse or recode the response options, or assume that larger response values indicate higher {construct_name}."
        )

    if instruction_lines:
        parts.append("")
        parts.extend(instruction_lines)

    parts.extend(
        [
            "",
            "Output rules:",
            "",
            "* Return exactly one JSON object containing the probabilities for the five literal response options.",
            "* Use exactly two decimal places for every probability.",
            "* The five probabilities must sum to exactly 1.00.",
            f"* Use exactly this format: {_format_probability_json_example(options)}",
            "* Do not add anything before or after the JSON object.",
        ]
    )

    suffix = str(retry_suffix or "").strip()
    if suffix:
        parts.extend(["", suffix])

    return "\n".join(parts)


def build_prompt_fullV2_1(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Distribution prompt V2.1: JSON probabilities with an explicit profile block."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
    )


def build_prompt_fullV2_1_1(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Distribution prompt V2.1.1: V2.1 without the literal-estimation sentence."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
        include_literal_estimation_sentence=False,
    )


def build_prompt_fullV2_1_1_no_probabilities(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Ablation: V2.1.1 with probability elicitation replaced by one literal response."""
    question = _required_text(item, "question")
    options = _required_text(item, "options")
    theta_description = _required_text(persona, "theta_description")
    allowed_numbers = _extract_option_numbers(options)
    if len(allowed_numbers) != 5:
        raise ValueError(
            "build_prompt_fullV2_1_1_no_probabilities expects exactly 5 response options, "
            f"got {len(allowed_numbers)}."
        )
    option_labels = extract_response_option_labels(options)

    parts = [
        "Answer the following survey question as a person with the described profile.",
        "",
        f'Survey question: "{question}"',
        "",
        "Response options:",
        "",
        _format_v21_response_options(options),
        "",
        "Profile:",
        "",
        f"* {_format_construct_level(construct_name, theta_description)}",
        f"* {construct_name} definition: {_clean_inline(construct_description)}",
    ]

    demographic_lines = _build_v2_demographic_lines(persona)
    if demographic_lines:
        parts.extend(f"* {line}" for line in demographic_lines)

    parts.extend(
        [
            "",
            f"The statement may be associated with higher {construct_name}, lower {construct_name}, or neither; do not reverse or recode the response options, or assume that larger response values indicate higher {construct_name}.",
            "",
            "Output rules:",
            "",
            "* Return exactly one of the five literal response options.",
            f"* The response must be exactly one of: {', '.join(option_labels)}.",
            "* Do not add anything before or after the response.",
        ]
    )

    suffix = str(retry_suffix or "").strip()
    if suffix:
        parts.extend(["", suffix])

    return "\n".join(parts)


def build_prompt_fullV2_1_no_trait(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Ablation: remove the construct level and construct definition only."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
        include_trait_level=False,
        include_trait_definition=False,
    )


def build_prompt_fullV2_1_1_no_trait(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Ablation: V2.1.1 with construct level and definition removed."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
        include_trait_level=False,
        include_trait_definition=False,
        include_literal_estimation_sentence=False,
    )


def build_prompt_fullV2_1_no_demogs(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Ablation: remove the demographic characteristics only."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
        include_demographics=False,
    )


def build_prompt_fullV2_1_1_no_demogs(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Ablation: V2.1.1 with demographic characteristics removed."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
        include_demographics=False,
        include_literal_estimation_sentence=False,
    )


def build_prompt_fullV2_1_no_detail_variation(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Ablation: remove the literal-response and variation guidance only."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
        include_detail_variation=False,
    )


def build_prompt_fullV2_1_1_no_detail_variation(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Ablation: V2.1.1 with literal-response and variation guidance removed."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
        include_detail_variation=False,
        include_literal_estimation_sentence=False,
    )


def build_prompt_fullV2_1_no_assoc_explan(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Ablation: remove the trait-direction and recoding instruction only."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
        include_assoc_explan=False,
    )


def build_prompt_fullV2_1_1_no_assoc_explan(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Ablation: V2.1.1 with trait-direction and recoding instruction removed."""
    return _build_prompt_fullV2_1_variant(
        persona,
        item,
        construct_name,
        construct_description,
        retry_suffix=retry_suffix,
        include_assoc_explan=False,
        include_literal_estimation_sentence=False,
    )


def build_prompt_fullV2_2(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Distribution prompt V2.2: JSON probabilities with bulleted options and profile."""
    question = _required_text(item, "question")
    options = _required_text(item, "options")
    theta_description = _required_text(persona, "theta_description")
    allowed_numbers = _extract_option_numbers(options)
    if len(allowed_numbers) != 5:
        raise ValueError(
            f"build_prompt_fullV2_2 expects exactly 5 response options, got {len(allowed_numbers)}."
        )

    parts = [
        "Estimate the proportions of responses expected across many different people who share the following profile.",
        "",
        f'Survey question: "{question}"',
        "",
        "Response options:",
        "",
        _format_v22_response_options(options),
        "",
        "Shared profile:",
        "",
        f"* {_format_construct_level(construct_name, theta_description)}",
        f"* {construct_name} definition: {_clean_inline(construct_description)}",
    ]

    demographic_lines = _build_v2_demographic_lines(persona)
    if demographic_lines:
        parts.extend(f"* {line}" for line in demographic_lines)

    parts.extend(
        [
            "",
            f"Base the proportions on the statement exactly as written and the whole shared profile. The statement may relate to {construct_name} in either direction or not at all. Treat the response options as literal judgements of the statement's accuracy only, and do not recode them.",
            "",
            "People sharing this profile still differ because of unmeasured characteristics, context, interpretation, momentary state, attention and effort, and response tendencies. Allow a realistic amount of variation suited to the particular statement.",
            "",
            "Output rules:",
            "",
            "* Return exactly one JSON object containing the probabilities for the five response options.",
            "* Use exactly two decimal places for every probability.",
            "* The five probabilities must sum to exactly 1.00.",
            "* Use exactly this format: {\"Inaccurate\":0.00,\"Moderately Inaccurate\":0.00,\"Neither\":0.00,\"Moderately Accurate\":0.00,\"Accurate\":0.00}",
            "* Do not add anything before or after the JSON object.",
        ]
    )

    suffix = str(retry_suffix or "").strip()
    if suffix:
        parts.extend(["", suffix])

    return "\n".join(parts)


def build_prompt_fullV2_3(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Distribution prompt V2.3: same as V2.2 with a shorter variability statement."""
    question = _required_text(item, "question")
    options = _required_text(item, "options")
    theta_description = _required_text(persona, "theta_description")
    allowed_numbers = _extract_option_numbers(options)
    if len(allowed_numbers) != 5:
        raise ValueError(
            f"build_prompt_fullV2_3 expects exactly 5 response options, got {len(allowed_numbers)}."
        )

    parts = [
        "Estimate the proportions of responses expected across many different people who share the following profile.",
        "",
        f'Survey question: "{question}"',
        "",
        "Response options:",
        "",
        _format_v22_response_options(options),
        "",
        "Shared profile:",
        "",
        f"* {_format_construct_level(construct_name, theta_description)}",
        f"* {construct_name} definition: {_clean_inline(construct_description)}",
    ]

    demographic_lines = _build_v2_demographic_lines(persona)
    if demographic_lines:
        parts.extend(f"* {line}" for line in demographic_lines)

    parts.extend(
        [
            "",
            f"Base the proportions on the statement exactly as written and the whole shared profile. The statement may relate to {construct_name} in either direction or not at all. Treat the response options as literal judgements of the statement's accuracy only, and do not recode them.",
            "",
            "People sharing this profile still differ because of unmeasured characteristics and circumstances, so allow a realistic amount of variation suited to the particular statement.",
            "",
            "Output rules:",
            "",
            "* Return exactly one JSON object containing the probabilities for the five response options.",
            "* Use exactly two decimal places for every probability.",
            "* The five probabilities must sum to exactly 1.00.",
            "* Use exactly this format: {\"Inaccurate\":0.00,\"Moderately Inaccurate\":0.00,\"Neither\":0.00,\"Moderately Accurate\":0.00,\"Accurate\":0.00}",
            "* Do not add anything before or after the JSON object.",
        ]
    )

    suffix = str(retry_suffix or "").strip()
    if suffix:
        parts.extend(["", suffix])

    return "\n".join(parts)


def build_prompt_single_answer_demogs(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Single-answer prompt using only the demographic profile."""
    question = _required_text(item, "question")
    options = _required_text(item, "options")
    allowed_numbers = _extract_option_numbers(options)
    if len(allowed_numbers) != 5:
        raise ValueError(
            f"build_prompt_single_answer_demogs expects exactly 5 response options, got {len(allowed_numbers)}."
        )

    parts = [
        "Answer the following survey question as a person with the described profile.",
        "",
        f'Survey question: "{question}"',
        "",
        "Response options:",
        "",
        _format_v21_response_options(options),
        "",
        "Profile:",
        "",
    ]

    demographic_lines = _build_v2_demographic_lines(persona)
    if demographic_lines:
        parts.extend(f"* {line}" for line in demographic_lines)

    parts.extend(
        [
            "",
            "Taking the perspective of this person, select the response option that best describes you.",
            "",
            "Output rules:",
            "",
            "* Return exactly one integer corresponding to the selected response option.",
            f"* The integer must be {', '.join(str(number) for number in allowed_numbers[:-1])}, or {allowed_numbers[-1]}.",
            "* Do not add anything before or after the integer.",
        ]
    )

    suffix = str(retry_suffix or "").strip()
    if suffix:
        parts.extend(["", suffix])

    return "\n".join(parts)


def build_prompt_single_answer_trait(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    retry_suffix: str = "",
) -> str:
    """Single-answer prompt using the trait level and construct definition."""
    question = _required_text(item, "question")
    options = _required_text(item, "options")
    theta_description = _required_text(persona, "theta_description")
    allowed_numbers = _extract_option_numbers(options)
    if len(allowed_numbers) != 5:
        raise ValueError(
            f"build_prompt_single_answer_trait expects exactly 5 response options, got {len(allowed_numbers)}."
        )

    parts = [
        "Answer the following survey question as a person with the described profile.",
        "",
        f'Survey question: "{question}"',
        "",
        "Response options:",
        "",
        _format_v21_response_options(options),
        "",
        "Profile:",
        "",
        f"* {_format_construct_level(construct_name, theta_description)}",
        f"* {construct_name} definition: {_clean_inline(construct_description)}",
    ]

    demographic_lines = _build_v2_demographic_lines(persona)
    if demographic_lines:
        parts.extend(f"* {line}" for line in demographic_lines)

    parts.extend(
        [
            "",
            "Taking the perspective of this person, select the response option that best describes you.",
            "",
            "Output rules:",
            "",
            "* Return exactly one integer corresponding to the selected response option.",
            f"* The integer must be {', '.join(str(number) for number in allowed_numbers[:-1])}, or {allowed_numbers[-1]}.",
            "* Do not add anything before or after the integer.",
        ]
    )

    suffix = str(retry_suffix or "").strip()
    if suffix:
        parts.extend(["", suffix])

    return "\n".join(parts)


def _build_v2_demographic_lines(persona: Mapping[str, Any]) -> list[str]:
    ordered_keys = ("gender", "age", "country")
    lines = []
    seen_keys = set()

    for key in ordered_keys:
        value = persona.get(key)
        if value is None or (isinstance(value, str) and not value.strip()):
            continue
        label = str(key).replace("_", " ").strip().title()
        display_value = _format_demographic_value(str(key), value)
        lines.append(f"{label}: {display_value}")
        seen_keys.add(key)

    for key, value in persona.items():
        if key in seen_keys or key in _RESERVED_PERSONA_KEYS or key in _NON_FOCAL_BIG5_PERCENTILE_KEYS:
            continue
        if value is None or (isinstance(value, str) and not value.strip()):
            continue
        label = str(key).replace("_", " ").strip().title()
        display_value = _format_demographic_value(str(key), value)
        lines.append(f"{label}: {display_value}")

    return lines


def _format_v21_response_options(options: str) -> str:
    numbered_options = []
    for raw_option in str(options).split(";"):
        token = raw_option.strip()
        if not token:
            continue
        match = re.match(r"^(\d+)\s*[\)\].:;-]?\s*(.*)$", token)
        if not match:
            raise ValueError(f"Could not parse response option: {raw_option!r}")
        number = int(match.group(1))
        label = match.group(2).strip()
        if not label:
            raise ValueError(f"Missing response option label for option {number}.")
        numbered_options.append(f"{number}. {label}")

    if len(numbered_options) != 5:
        raise ValueError(f"build_prompt_fullV2_1 expects exactly 5 response options, got {len(numbered_options)}.")

    return "\n".join(numbered_options)


def extract_response_option_labels(options: str) -> list[str]:
    labels = []
    for raw_option in str(options).split(";"):
        token = raw_option.strip()
        if not token:
            continue
        match = re.match(r"^(\d+)\s*[\)\].:;-]?\s*(.*)$", token)
        if not match:
            raise ValueError(f"Could not parse response option: {raw_option!r}")
        label = match.group(2).strip()
        if not label:
            raise ValueError(f"Missing response option label for option {match.group(1)}.")
        labels.append(label)

    if len(labels) != 5:
        raise ValueError(
            f"Expected exactly 5 response option labels, got {len(labels)}."
        )
    return labels


def _format_probability_json_example(options: str) -> str:
    labels = extract_response_option_labels(options)
    entries = [f"{json.dumps(label)}:0.00" for label in labels]
    return "{" + ",".join(entries) + "}"


def _format_v22_response_options(options: str) -> str:
    bullet_options = []
    for raw_option in str(options).split(";"):
        token = raw_option.strip()
        if not token:
            continue
        match = re.match(r"^(\d+)\s*[\)\].:;-]?\s*(.*)$", token)
        if not match:
            raise ValueError(f"Could not parse response option: {raw_option!r}")
        number = int(match.group(1))
        label = match.group(2).strip()
        if not label:
            raise ValueError(f"Missing response option label for option {number}.")
        bullet_options.append(f"* {label}")

    if len(bullet_options) != 5:
        raise ValueError(f"build_prompt_fullV2_2 expects exactly 5 response options, got {len(bullet_options)}.")

    return "\n".join(bullet_options)


def _build_prompt(
    persona: Mapping[str, Any],
    item: Mapping[str, Any],
    construct_name: str,
    construct_description: str,
    *,
    include_construct_definition: bool,
    include_demographics: bool,
    multiple_responses: bool,
    multiple_people: bool,
    include_variability_information: bool,
    retry_suffix: str,
) -> str:
    """Build a prompt from the five binary experimental components."""
    question = _required_text(item, "question")
    options = _required_text(item, "options")
    theta_description = _required_text(persona, "theta_description")
    allowed_numbers = _extract_option_numbers(options)
    allowed_numbers_text = ", ".join(str(number) for number in allowed_numbers)

    if multiple_people:
        intro = "Ten different people who share the same described profile answer the following survey question:"
        profile_label = "Described profile:"
    else:
        intro = "One person answers the following survey question on 10 separate occasions:"
        profile_label = "Profile:"

    parts = [
        intro,
        f'- Survey question: "{question}"',
        f"- Response options: {options}",
        "",
        profile_label,
        f"- {_format_construct_level(construct_name, theta_description)}",
    ]

    if include_construct_definition:
        parts.append(f"- {construct_name} definition: {_clean_inline(construct_description)}")

    if include_demographics:
        demographic_lines = _build_demographic_lines(persona)
        if demographic_lines:
            parts.extend(f"- {line}" for line in demographic_lines)

    if include_variability_information:
        parts.extend(_simulation_constraints_lines(multiple_people=multiple_people))

    parts.append("")
    if multiple_responses and multiple_people:
        parts.append("What would the 10 people's responses to the survey question be?")
    elif multiple_responses:
        parts.append("What would this person's responses on the 10 occasions be?")
    else:
        parts.append(
            "Consider one person selected at random from the group. What would this "
            "person's response to the survey question be?"
        )

    parts.extend(
        _multiple_response_rules(
            allowed_numbers_text,
            response_unit="person" if multiple_people else "occasion",
        )
        if multiple_responses
        else _single_response_rules(allowed_numbers_text)
    )
    retry_suffix = str(retry_suffix or "").strip()
    if retry_suffix:
        parts.extend(["", retry_suffix])

    return "\n".join(parts)


def _build_demographic_lines(persona: Mapping[str, Any]) -> list[str]:
    """Return demographics while excluding response styles and Big Five traits."""
    lines = []
    for key, value in persona.items():
        if key in _RESERVED_PERSONA_KEYS:
            continue
        if key in _NON_FOCAL_BIG5_PERCENTILE_KEYS:
            continue
        if value is None or (isinstance(value, str) and not value.strip()):
            continue

        label = str(key).replace("_", " ").strip().title()
        display_value = _format_demographic_value(str(key), value)
        lines.append(f"{label}: {display_value}")
    return lines


def _format_demographic_value(key: str, value: Any) -> Any:
    if key.lower() != "gender" or not isinstance(value, str):
        return value

    token = value.strip().lower()
    if token in {"m", "male"}:
        return "Male"
    if token in {"f", "female"}:
        return "Female"
    return value.strip()


def _format_construct_level(construct_name: str, theta_description: str) -> str:
    parsed = _extract_percentile_from_theta(theta_description)
    if parsed is None:
        return f"{construct_name} level: {theta_description}"

    percentile, label = parsed
    return f"{construct_name} level: {_ordinal(percentile)} percentile ({label})."


def _extract_percentile_from_theta(theta_description: str) -> tuple[int, str] | None:
    match = re.search(
        r"higher\s+than\s+(\d{1,3})\s*%.*?\(([^)]+)\)",
        str(theta_description),
        flags=re.IGNORECASE,
    )
    if not match:
        return None

    percentile = max(1, min(99, int(match.group(1))))
    return percentile, match.group(2).strip()


def _extract_option_numbers(options: str) -> list[int]:
    """Extract ordered option numbers, e.g. from ``1) No; 2) Yes``."""
    matches = re.findall(r"(?<!\d)(\d+)\s*(?=[)\].:;-])", str(options))
    numbers = list(dict.fromkeys(int(match) for match in matches))
    if not numbers:
        raise ValueError(f"Could not extract option numbers from options: {options!r}")
    return numbers


def _multiple_response_rules(allowed_numbers_text: str, response_unit: str) -> list[str]:
    return [
        "",
        "Output rules:",
        f"- Write exactly 10 integers on one line - one response for each {response_unit} - separated by exactly 9 commas.",
        "- Format: n, n, n, n, n, n, n, n, n, n",
        f"- Each integer must be one of the permitted option numbers: {allowed_numbers_text}.",
        "- Do not add anything before or after the integers, including words, labels, bullets, explanations, or extra values.",
    ]


def _single_response_rules(allowed_numbers_text: str) -> list[str]:
    return [
        "",
        "Output rules:",
        "- Write only one integer.",
        f"- The integer must be one of the permitted option numbers: {allowed_numbers_text}.",
        "- Do not add anything before or after the integer, including words, labels, bullets, explanations, or extra values.",
    ]


def _simulation_constraints_lines(*, multiple_people: bool) -> list[str]:
    if multiple_people:
        return [
            "",
            "Simulation Constraints:",
            "- Determine Directionality: First, evaluate the relationship between the survey statement and the "
            "described profile. Determine whether the different parts of the described profile (including trait "
            "level) shift the likely response toward higher numbers, lower numbers, or are irrelevant.",
            "- Simulate Realistic Variance: Do not output 10 identical responses. Generate a realistic distribution "
            "of integers. While these 10 individuals share the same base profile, you must simulate natural human "
            "variability by factoring in unmeasured personal traits, subjective interpretation, varying attention "
            "to the question, and individual response biases (such as extreme response styles, neutral tendencies, "
            "or acquiescence bias).",
        ]

    return [
        "",
        "Simulation Constraints:",
        "- Determine Directionality: First, evaluate the relationship between the survey statement and the "
        "described profile. Determine whether the different parts of the described profile (including trait "
        "level) shift the likely response toward higher numbers, lower numbers, or are irrelevant for this one person.",
        "- Simulate Realistic Variance: Do not output 10 identical responses. Generate a realistic sequence of "
        "integers across the 10 occasions for this one person. Even with a single person, you must simulate "
        "natural within-person variability by factoring in momentary state, subjective interpretation, and varying "
        "attention to the question.",
    ]


def _required_text(mapping: Mapping[str, Any], key: str) -> str:
    value = mapping.get(key)
    if value is None or not str(value).strip():
        raise ValueError(f"Missing required value: {key}")
    return str(value).strip()


def _clean_inline(value: Any) -> str:
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    if not text:
        raise ValueError("construct_description must not be empty")
    return text


def _ordinal(number: int) -> str:
    number = int(number)
    if 10 <= number % 100 <= 20:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(number % 10, "th")
    return f"{number}{suffix}"
