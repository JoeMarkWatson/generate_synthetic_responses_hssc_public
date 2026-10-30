"""
llm_client.py

OpenRouter client for DeepSeek V4 Flash with reasoning disabled.

Required config.py values, or equivalent environment variables:
    OPENROUTER_API_KEY
Optional config.py values:
    OPENROUTER_API_URL
    OPENROUTER_MODEL

Default model:
    deepseek/deepseek-v4-flash

Cost-control note:
    OpenRouter reasoning tokens are billed as output tokens. This client sends
    reasoning={"effort": "none", "exclude": True} on every request.
"""

from __future__ import annotations

import json
import os
import random
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Dict, Iterable, List, Mapping, Optional, Tuple

import requests

try:
    from config import OPENROUTER_API_KEY as CONFIG_OPENROUTER_API_KEY
except Exception:
    CONFIG_OPENROUTER_API_KEY = None

try:
    from config import OPENROUTER_API_URL as CONFIG_OPENROUTER_API_URL
except Exception:
    CONFIG_OPENROUTER_API_URL = None

try:
    from config import OPENROUTER_MODEL as CONFIG_OPENROUTER_MODEL
except Exception:
    CONFIG_OPENROUTER_MODEL = None


OPENROUTER_API_KEY = (
    os.getenv("OPENROUTER_API_KEY")
    or CONFIG_OPENROUTER_API_KEY
    or ""
)

OPENROUTER_API_URL = (
    os.getenv("OPENROUTER_API_URL")
    or CONFIG_OPENROUTER_API_URL
    or "https://openrouter.ai/api/v1/chat/completions"
)

OPENROUTER_MODEL = (
    os.getenv("OPENROUTER_MODEL")
    or CONFIG_OPENROUTER_MODEL
    or "deepseek/deepseek-v4-flash"
)

TRANSIENT_STATUS_CODES = {408, 409, 425, 429, 500, 502, 503, 504}

DEFAULT_TIMEOUT_SECONDS = float(os.getenv("OPENROUTER_TIMEOUT_SECONDS", "60"))

MAX_ATTEMPTS = max(1, int(os.getenv("OPENROUTER_MAX_ATTEMPTS", "5")))
INITIAL_BACKOFF_SECONDS = float(os.getenv("OPENROUTER_INITIAL_BACKOFF", "1.0"))
MAX_BACKOFF_SECONDS = float(os.getenv("OPENROUTER_MAX_BACKOFF", "20.0"))

DEFAULT_MAX_TOKENS = int(os.getenv("OPENROUTER_MAX_TOKENS", "96"))
DEFAULT_MAX_TOKENS_LOGPROBS = int(os.getenv("OPENROUTER_MAX_TOKENS_LOGPROBS", "50"))

DEFAULT_TEMPERATURE = 0.0

PROVIDER_ORDER_RAW = os.getenv("OPENROUTER_PROVIDER_ORDER", "").strip()
PROVIDER_ALLOW_FALLBACKS = os.getenv(
    "OPENROUTER_ALLOW_FALLBACKS", "false"
).strip().lower() in {"1", "true", "yes", "y"}


def _headers() -> Dict[str, str]:
    if not OPENROUTER_API_KEY:
        raise RuntimeError("Missing OPENROUTER_API_KEY.")

    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
    }

    referer = os.getenv("OPENROUTER_HTTP_REFERER", "").strip()
    title = os.getenv("OPENROUTER_APP_TITLE", "").strip()

    if referer:
        headers["HTTP-Referer"] = referer
    if title:
        headers["X-OpenRouter-Title"] = title

    return headers


def _reasoning_disabled(model: Optional[str] = None) -> Dict[str, Any]:
    """
    Disable reasoning rather than merely hiding it.

    "effort": "none" is the cost-control setting used by existing models.
    "exclude": True is defensive: if a provider still emits reasoning metadata,
    do not return it in the response payload.
    """
    if model and model in {
        "mistralai/mistral-small-2603",
        "mistralai/mistral-small-2603:floor",
        "mistralai/mistral-small-2603:nitro",
    }:
        # OpenRouter documents reasoning as opt-in for Mistral Small 4.
        return {}

    if model in {
        "anthropic/claude-haiku-5.5",
        "qwen/qwen3.8-27b:floor",
        "xiaomi/mimo-v2.6-flash",
    }:
        # OpenRouter's enabled=False explicitly disables model reasoning for
        # Claude, Qwen, and MiMo.
        return {
            "reasoning": {
                "enabled": False,
                "exclude": True,
            },
            "include_reasoning": False,
        }

    return {
        "reasoning": {
            "effort": "none",
            "exclude": True,
        },
        # Legacy compatibility. OpenRouter recommends the unified `reasoning`
        # object, but this remains harmless for older routing layers.
        "include_reasoning": False,
    }


def _provider_routing(model: Optional[str] = None) -> Dict[str, Any]:
    if model and model.startswith("mistralai/mistral-small-2603"):
        # Leave Mistral routing unrestricted so OpenRouter can use its full
        # provider pool and automatic failover.
        return {}

    if not PROVIDER_ORDER_RAW:
        return {}

    provider_order = [
        provider.strip()
        for provider in PROVIDER_ORDER_RAW.split(",")
        if provider.strip()
    ]

    if not provider_order:
        return {}

    return {
        "provider": {
            "order": provider_order,
            "allow_fallbacks": PROVIDER_ALLOW_FALLBACKS,
        }
    }


def _sleep_before_retry(attempt_index: int, retry_after: Optional[str] = None) -> None:
    if retry_after is not None:
        try:
            delay = float(retry_after)
        except (TypeError, ValueError):
            try:
                retry_at = parsedate_to_datetime(retry_after)
                if retry_at.tzinfo is None:
                    retry_at = retry_at.replace(tzinfo=timezone.utc)
                delay = (retry_at - datetime.now(timezone.utc)).total_seconds()
            except (TypeError, ValueError, OverflowError):
                delay = None
        if delay is not None and delay >= 0:
            time.sleep(delay)
            return

    backoff = min(
        MAX_BACKOFF_SECONDS,
        INITIAL_BACKOFF_SECONDS * (2 ** attempt_index),
    )
    jitter = random.uniform(0, 0.25 * backoff)
    time.sleep(backoff + jitter)


def _extract_error_text(response: requests.Response) -> str:
    try:
        payload = response.json()
    except Exception:
        return response.text

    if isinstance(payload, dict):
        error = payload.get("error")
        if isinstance(error, dict):
            message = error.get("message")
            if message:
                return str(message)
        if error:
            return str(error)

    return json.dumps(payload, ensure_ascii=False)


def _request_json(payload: Mapping[str, Any]) -> Dict[str, Any]:
    last_error: Optional[BaseException] = None

    for attempt in range(MAX_ATTEMPTS):
        try:
            response = requests.post(
                OPENROUTER_API_URL,
                headers=_headers(),
                json=payload,
                timeout=DEFAULT_TIMEOUT_SECONDS,
            )
        except requests.RequestException as exc:
            last_error = exc
            if attempt < MAX_ATTEMPTS - 1:
                _sleep_before_retry(attempt)
                continue
            break

        if response.status_code == 200:
            try:
                return response.json()
            except ValueError as exc:
                raise RuntimeError("OpenRouter returned invalid JSON.") from exc

        if response.status_code in TRANSIENT_STATUS_CODES and attempt < MAX_ATTEMPTS - 1:
            _sleep_before_retry(
                attempt,
                retry_after=(
                    response.headers.get("Retry-After")
                    if response.status_code == 429
                    else None
                ),
            )
            continue

        raise RuntimeError(
            f"OpenRouter API error {response.status_code}: "
            f"{_extract_error_text(response)}"
        )

    raise RuntimeError(
        f"OpenRouter API request failed after {MAX_ATTEMPTS} attempts: {last_error}"
    )


def _stream_text(payload: Mapping[str, Any]) -> str:
    last_error: Optional[BaseException] = None

    for attempt in range(MAX_ATTEMPTS):
        try:
            with requests.post(
                OPENROUTER_API_URL,
                headers=_headers(),
                json={**payload, "stream": True},
                timeout=DEFAULT_TIMEOUT_SECONDS,
                stream=True,
            ) as response:
                if response.status_code != 200:
                    if (
                        response.status_code in TRANSIENT_STATUS_CODES
                        and attempt < MAX_ATTEMPTS - 1
                    ):
                        _sleep_before_retry(
                            attempt,
                            retry_after=(
                                response.headers.get("Retry-After")
                                if response.status_code == 429
                                else None
                            ),
                        )
                        continue

                    raise RuntimeError(
                        f"OpenRouter API error {response.status_code}: "
                        f"{_extract_error_text(response)}"
                    )

                chunks: List[str] = []

                for raw_line in response.iter_lines(decode_unicode=True):
                    if not raw_line or not raw_line.startswith("data:"):
                        continue

                    event_text = raw_line.removeprefix("data:").strip()
                    if event_text == "[DONE]":
                        break

                    try:
                        event = json.loads(event_text)
                    except ValueError:
                        continue

                    choice = (event.get("choices") or [{}])[0]
                    delta = choice.get("delta") or {}

                    # Deliberately ignore reasoning / reasoning_details deltas.
                    content_piece = delta.get("content")
                    if isinstance(content_piece, str):
                        chunks.append(content_piece)

                text = "".join(chunks).strip()
                if text:
                    return text

                if attempt < MAX_ATTEMPTS - 1:
                    _sleep_before_retry(attempt)
                    continue

                raise RuntimeError("Streaming response returned no text content.")

        except requests.RequestException as exc:
            last_error = exc
            if attempt < MAX_ATTEMPTS - 1:
                _sleep_before_retry(attempt)
                continue
            break

    raise RuntimeError(
        f"OpenRouter streaming request failed after {MAX_ATTEMPTS} attempts: {last_error}"
    )


def _extract_message_text(data: Mapping[str, Any]) -> str:
    try:
        choice = data["choices"][0]
    except Exception as exc:
        raise RuntimeError(f"Unexpected OpenRouter response format: {data}") from exc

    message = choice.get("message") or {}
    content = message.get("content")

    if isinstance(content, str):
        text = content.strip()
        if text:
            return text

    if isinstance(content, list):
        parts: List[str] = []
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") == "text" and isinstance(item.get("text"), str):
                parts.append(item["text"])
        text = "".join(parts).strip()
        if text:
            return text

    finish_reason = choice.get("finish_reason")
    reasoning = message.get("reasoning") or message.get("reasoning_details")

    if reasoning:
        raise RuntimeError(
            "OpenRouter returned reasoning but no final content. "
            "The request was configured with reasoning disabled; check model/provider routing."
        )

    raise RuntimeError(
        f"OpenRouter returned no text content. finish_reason={finish_reason!r}; "
        f"response={data}"
    )


def _base_payload(
    prompt: str,
    *,
    model: Optional[str] = None,
    temperature: Optional[float] = None,
    max_tokens: Optional[int] = None,
    extra_messages: Optional[Iterable[Mapping[str, str]]] = None,
    extra_body: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("prompt must be a non-empty string.")

    messages: List[Mapping[str, str]] = []
    if extra_messages:
        messages.extend(extra_messages)
    messages.append({"role": "user", "content": prompt})

    effective_model = model or OPENROUTER_MODEL
    payload: Dict[str, Any] = {
        "model": effective_model,
        "messages": messages,
        "temperature": DEFAULT_TEMPERATURE if temperature is None else temperature,
        "max_tokens": DEFAULT_MAX_TOKENS if max_tokens is None else max_tokens,
        **_reasoning_disabled(effective_model),
        **_provider_routing(effective_model),
    }

    if extra_body:
        forbidden_reasoning = {
            "reasoning",
            "reasoning_effort",
            "include_reasoning",
        }
        overlap = forbidden_reasoning.intersection(extra_body.keys())
        if overlap:
            raise ValueError(
                "extra_body must not override reasoning controls. "
                f"Forbidden keys: {sorted(overlap)}"
            )
        payload.update(extra_body)

    return payload


def query_deepseek(
    prompt: str,
    *,
    stream: bool = True,
    model: Optional[str] = None,
    temperature: Optional[float] = None,
    max_tokens: Optional[int] = None,
    system_prompt: Optional[str] = None,
) -> str:
    """
    Query an OpenRouter chat model with reasoning disabled.

    By default this streams for lower latency, then falls back to a non-streaming
    request if streaming fails.
    """
    extra_messages = None
    if system_prompt:
        extra_messages = [{"role": "system", "content": system_prompt}]

    payload = _base_payload(
        prompt,
        model=model,
        temperature=temperature,
        max_tokens=max_tokens,
        extra_messages=extra_messages,
    )

    if stream:
        try:
            return _stream_text(payload)
        except RuntimeError:
            # Fall back to non-streaming so callers do not fail on providers
            # with transient streaming problems.
            pass

    data = _request_json({k: v for k, v in payload.items() if k != "stream"})
    return _extract_message_text(data)


def query_deepseek_logprobs(
    prompt: str,
    *,
    model: Optional[str] = None,
    max_tokens: Optional[int] = None,
    top_logprobs: int = 4,
    system_prompt: Optional[str] = None,
) -> Tuple[str, Dict[str, Any]]:
    """
    Query an OpenRouter chat model and return text plus provider logprobs.

    Not every OpenRouter provider/model route returns logprobs. In that case,
    the second return value may be an empty dict.
    """
    if top_logprobs < 0:
        raise ValueError("top_logprobs must be >= 0.")

    extra_messages = None
    if system_prompt:
        extra_messages = [{"role": "system", "content": system_prompt}]

    payload = _base_payload(
        prompt,
        model=model,
        temperature=0,
        max_tokens=max_tokens or DEFAULT_MAX_TOKENS_LOGPROBS,
        extra_messages=extra_messages,
        extra_body={
            "top_p": 1,
            "logprobs": True,
            "top_logprobs": top_logprobs,
        },
    )

    data = _request_json(payload)
    text = _extract_message_text(data)

    try:
        logprobs = data["choices"][0].get("logprobs") or {}
    except Exception:
        logprobs = {}

    return text, logprobs


def query_llm(prompt: str, **kwargs: Any) -> str:
    """
    Backward-compatible generic alias.
    """
    return query_deepseek(prompt, **kwargs)


if __name__ == "__main__":
    demo_prompt = "Reply with exactly five words."
    print(query_deepseek(demo_prompt, stream=True))
