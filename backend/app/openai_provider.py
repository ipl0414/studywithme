from __future__ import annotations

import base64
import json
import mimetypes
import os
from pathlib import Path
import re
import urllib.error
import urllib.request
from uuid import uuid4
from typing import Any, Callable, Dict


JsonTransport = Callable[[str, Dict[str, Any], Dict[str, str], int], Dict[str, Any]]
MultipartTransport = Callable[[str, bytes, Dict[str, str], int], Dict[str, Any]]


class OpenAIProviderError(RuntimeError):
    pass


_REASONING_BLOCK_RE = re.compile(
    r"<(think|thinking|reasoning|analysis)[^>]*>.*?</\1>",
    re.IGNORECASE | re.DOTALL,
)
_FINAL_LABEL_RE = re.compile(
    r"(?:^|\n)\s*(?:final answer|final|answer|답변|최종 답변)\s*:\s*",
    re.IGNORECASE,
)


def _strip_reasoning_trace(text: str) -> str:
    cleaned = _REASONING_BLOCK_RE.sub("", text).strip()
    match = _FINAL_LABEL_RE.search(cleaned)
    if match and (
        match.start() == 0
        or re.search(r"\b(reasoning|analysis|thought|think)\b|추론|분석", cleaned[: match.start()], re.IGNORECASE)
    ):
        cleaned = cleaned[match.end() :].strip()
    cleaned = _FINAL_LABEL_RE.sub("", cleaned, count=1).strip()
    return cleaned


def _gemini_response_schema(schema: Any) -> Any:
    if isinstance(schema, dict):
        return {
            key: _gemini_response_schema(value)
            for key, value in schema.items()
            if key != "additionalProperties"
        }
    if isinstance(schema, list):
        return [_gemini_response_schema(item) for item in schema]
    return schema


class OpenAITextClient:
    default_responses_url = "https://api.openai.com/v1/responses"

    def __init__(
        self,
        api_key: str | None,
        transport: JsonTransport | None = None,
        timeout: int = 60,
        responses_url: str | None = None,
        provider_name: str = "openai",
        default_model: str = "gpt-5.2",
    ):
        self.api_key = api_key
        self.transport = transport or self._urllib_transport
        self.timeout = timeout
        self.responses_url = responses_url or self.default_responses_url
        self.provider_name = provider_name
        self.default_model = default_model

    @classmethod
    def from_env(cls) -> "OpenAITextClient":
        provider = os.environ.get("TEXT_API_PROVIDER", "gemma").strip().lower()
        if provider in {"gemma", "google_gemma", "google", "gemini", "google_gemini"}:
            return GoogleGemmaTextClient.from_env(provider_name=provider)

        if provider in {"local", "local_lmstudio", "lmstudio", "lm_studio", "local_openai"}:
            return LocalLMStudioTextClient.from_env()

        if provider in {"openai_compatible", "poe", "openrouter"}:
            base_url = _normalize_base_url(
                os.environ.get("GEMMA_API_BASE_URL")
                or os.environ.get("TEXT_API_BASE_URL")
                or "https://openrouter.ai/api/v1"
            )
            return cls(
                api_key=(
                    os.environ.get("GEMMA_API_KEY")
                    or os.environ.get("TEXT_API_KEY")
                ),
                timeout=_timeout_from_env("OPENAI_TEXT_TIMEOUT", 180),
                responses_url=f"{base_url}/responses",
                provider_name=provider,
                default_model=os.environ.get("GEMMA_TEXT_MODEL") or "google/gemma-4-31b-it",
            )

        base_url = _normalize_base_url(
            os.environ.get("OPENAI_API_BASE_URL")
            or os.environ.get("TEXT_API_BASE_URL")
            or "https://api.openai.com/v1"
        )
        return cls(
            api_key=os.environ.get("OPENAI_API_KEY"),
            timeout=_timeout_from_env("OPENAI_TEXT_TIMEOUT", 180),
            responses_url=f"{base_url}/responses",
            provider_name="openai",
            default_model=os.environ.get("OPENAI_PREMIUM_MODEL") or "gpt-5.2",
        )

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key)

    def generate_text(
        self,
        model: str,
        instructions: str,
        input_text: str,
        max_output_tokens: int = 700,
        text_format: Dict[str, Any] | None = None,
    ) -> str:
        if not self.api_key:
            raise OpenAIProviderError("OPENAI_API_KEY is not configured.")

        payload: Dict[str, Any] = {
            "model": model,
            "instructions": instructions,
            "input": input_text,
            "max_output_tokens": max_output_tokens,
        }
        if text_format is not None:
            payload["text"] = {"format": text_format}
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        try:
            response = self.transport(self.responses_url, payload, headers, self.timeout)
        except TimeoutError as exc:
            raise OpenAIProviderError(f"OpenAI API request timed out: {exc}") from exc
        text = self._extract_text(response)
        if not text:
            raise OpenAIProviderError("OpenAI response did not include text output.")
        return text

    def _urllib_transport(
        self,
        url: str,
        payload: Dict[str, Any],
        headers: Dict[str, str],
        timeout: int,
    ) -> Dict[str, Any]:
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise OpenAIProviderError(f"OpenAI API returned HTTP {exc.code}: {body}") from exc
        except urllib.error.URLError as exc:
            raise OpenAIProviderError(f"OpenAI API request failed: {exc.reason}") from exc

    def _extract_text(self, response: Dict[str, Any]) -> str:
        output_text = response.get("output_text")
        if isinstance(output_text, str) and output_text.strip():
            return _strip_reasoning_trace(output_text)

        parts: list[str] = []
        for item in response.get("output", []):
            if not isinstance(item, dict):
                continue
            for content in item.get("content", []):
                if not isinstance(content, dict):
                    continue
                if content.get("type") == "output_text" and isinstance(content.get("text"), str):
                    parts.append(content["text"])
        return _strip_reasoning_trace("\n".join(part.strip() for part in parts if part.strip()))


class LocalLMStudioTextClient:
    default_base_url = "http://127.0.0.1:1234"

    def __init__(
        self,
        base_url: str | None = None,
        api_key: str | None = None,
        transport: JsonTransport | None = None,
        timeout: int = 60,
        default_model: str = "gemma-4-e4b",
        min_output_tokens: int = 900,
        disable_reasoning: bool = True,
    ):
        self.api_key = api_key
        self.transport = transport or self._urllib_transport
        self.timeout = timeout
        self.chat_completions_url = _chat_completions_url(
            base_url or self.default_base_url
        )
        self.default_model = default_model
        self.min_output_tokens = max(0, min_output_tokens)
        self.disable_reasoning = disable_reasoning
        self.provider_name = "local_lmstudio"

    @classmethod
    def from_env(cls) -> "LocalLMStudioTextClient":
        return cls(
            base_url=(
                os.environ.get("LOCAL_LLM_BASE_URL")
                or os.environ.get("LM_STUDIO_BASE_URL")
                or os.environ.get("TEXT_API_BASE_URL")
                or cls.default_base_url
            ),
            api_key=(
                os.environ.get("LOCAL_LLM_API_KEY")
                or os.environ.get("TEXT_API_KEY")
            ),
            timeout=_timeout_from_env(
                "LOCAL_LLM_TIMEOUT",
                _timeout_from_env("OPENAI_TEXT_TIMEOUT", 180),
            ),
            default_model=os.environ.get("LOCAL_LLM_MODEL") or "gemma-4-e4b",
            min_output_tokens=_timeout_from_env("LOCAL_LLM_MIN_OUTPUT_TOKENS", 900),
            disable_reasoning=_bool_from_env("LOCAL_LLM_DISABLE_REASONING", True),
        )

    @property
    def is_configured(self) -> bool:
        return bool(self.chat_completions_url)

    def generate_text(
        self,
        model: str,
        instructions: str,
        input_text: str,
        max_output_tokens: int = 700,
        text_format: Dict[str, Any] | None = None,
    ) -> str:
        system_content = instructions
        payload: Dict[str, Any] = {
            "model": model or self.default_model,
            "messages": [
                {"role": "system", "content": system_content},
                {"role": "user", "content": input_text},
            ],
            "max_tokens": max(max_output_tokens, self.min_output_tokens),
        }
        if self.disable_reasoning:
            payload["reasoning_effort"] = "none"
            payload["reasoning"] = {"effort": "none"}
            payload["chat_template_kwargs"] = {"enable_thinking": False}
        if text_format is not None:
            schema = text_format.get("schema")
            if isinstance(schema, dict):
                payload["messages"][0]["content"] = (
                    f"{system_content}\n\n"
                    "Return only valid JSON matching this JSON Schema. "
                    "Do not wrap it in Markdown code fences and do not include commentary.\n"
                    f"{json.dumps(schema, ensure_ascii=False)}"
                )
            else:
                payload["messages"][0]["content"] = (
                    f"{system_content}\n\n"
                    "Return only valid JSON. Do not wrap it in Markdown code fences "
                    "and do not include commentary."
                )
            payload["response_format"] = {"type": "json_object"}

        headers = {
            "Content-Type": "application/json",
        }
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"

        try:
            response = self.transport(
                self.chat_completions_url,
                payload,
                headers,
                self.timeout,
            )
        except TimeoutError as exc:
            raise OpenAIProviderError(f"Local LM Studio request timed out: {exc}") from exc
        text = self._extract_text(response)
        if not text:
            if self._has_reasoning_only_response(response):
                raise OpenAIProviderError(
                    "Local LM Studio returned only reasoning_content and no final "
                    "assistant content. In LM Studio, disable separate/thinking "
                    "reasoning for this model, or increase LOCAL_LLM_MIN_OUTPUT_TOKENS."
                )
            raise OpenAIProviderError("Local LM Studio response did not include text output.")
        return text

    def _urllib_transport(
        self,
        url: str,
        payload: Dict[str, Any],
        headers: Dict[str, str],
        timeout: int,
    ) -> Dict[str, Any]:
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise OpenAIProviderError(
                f"Local LM Studio returned HTTP {exc.code}: {body}"
            ) from exc
        except urllib.error.URLError as exc:
            raise OpenAIProviderError(f"Local LM Studio request failed: {exc.reason}") from exc

    def _extract_text(self, response: Dict[str, Any]) -> str:
        choices = response.get("choices")
        if isinstance(choices, list) and choices:
            first = choices[0]
            if isinstance(first, dict):
                message = first.get("message")
                if isinstance(message, dict) and isinstance(message.get("content"), str):
                    return _strip_reasoning_trace(message["content"])
                if isinstance(first.get("text"), str):
                    return _strip_reasoning_trace(first["text"])
        return ""

    def _has_reasoning_only_response(self, response: Dict[str, Any]) -> bool:
        choices = response.get("choices")
        if not isinstance(choices, list) or not choices:
            return False
        first = choices[0]
        if not isinstance(first, dict):
            return False
        message = first.get("message")
        if not isinstance(message, dict):
            return False
        content = message.get("content")
        reasoning_content = message.get("reasoning_content")
        return (
            isinstance(reasoning_content, str)
            and bool(reasoning_content.strip())
            and (not isinstance(content, str) or not content.strip())
        )


class GoogleGemmaTextClient:
    default_generate_content_base_url = "https://generativelanguage.googleapis.com/v1beta"

    def __init__(
        self,
        api_key: str | None,
        transport: JsonTransport | None = None,
        timeout: int = 60,
        generate_content_base_url: str | None = None,
        default_model: str = "gemma-4-31b-it",
        provider_name: str = "gemma",
    ):
        self.api_key = api_key
        self.transport = transport or self._urllib_transport
        self.timeout = timeout
        self.generate_content_base_url = (
            generate_content_base_url or self.default_generate_content_base_url
        )
        self.default_model = default_model
        self.provider_name = provider_name

    @classmethod
    def from_env(cls, provider_name: str = "gemma") -> "GoogleGemmaTextClient":
        if provider_name in {"gemini", "google_gemini"}:
            default_model = (
                os.environ.get("GEMINI_TEXT_MODEL")
                or os.environ.get("GEMMA_TEXT_MODEL")
                or "gemini-3-flash-preview"
            )
        else:
            default_model = (
                os.environ.get("GEMMA_TEXT_MODEL")
                or "gemma-4-31b-it"
            )
        return cls(
            api_key=(
                os.environ.get("GEMINI_API_KEY")
                or os.environ.get("GOOGLE_API_KEY")
                or os.environ.get("GEMMA_API_KEY")
                or os.environ.get("TEXT_API_KEY")
            ),
            timeout=_timeout_from_env("OPENAI_TEXT_TIMEOUT", 180),
            generate_content_base_url=_normalize_base_url(
                os.environ.get("GEMINI_API_BASE_URL")
                or "https://generativelanguage.googleapis.com/v1beta"
            ),
            default_model=default_model,
            provider_name=provider_name,
        )

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key)

    def generate_text(
        self,
        model: str,
        instructions: str,
        input_text: str,
        max_output_tokens: int = 700,
        text_format: Dict[str, Any] | None = None,
    ) -> str:
        if not self.api_key:
            raise OpenAIProviderError("GEMINI_API_KEY is not configured.")

        generation_config: Dict[str, Any] = {
            "maxOutputTokens": max_output_tokens,
        }
        if model.startswith("gemini-3-"):
            thinking_level = os.environ.get("GEMINI_THINKING_LEVEL") or "minimal"
            generation_config["thinkingConfig"] = {
                "thinkingLevel": thinking_level.strip().lower() or "minimal"
            }
        if text_format is not None:
            generation_config["responseMimeType"] = "application/json"
            schema = text_format.get("schema")
            if isinstance(schema, dict):
                generation_config["responseSchema"] = _gemini_response_schema(schema)

        payload: Dict[str, Any] = {
            "system_instruction": {
                "parts": [{"text": instructions}],
            },
            "contents": [
                {
                    "role": "user",
                    "parts": [{"text": input_text}],
                }
            ],
            "generationConfig": generation_config,
        }
        url = (
            f"{self.generate_content_base_url}/models/{model}:generateContent"
            f"?key={self.api_key}"
        )
        headers = {
            "Content-Type": "application/json",
        }
        try:
            response = self.transport(url, payload, headers, self.timeout)
        except TimeoutError as exc:
            raise OpenAIProviderError(f"Gemini API request timed out: {exc}") from exc
        text = self._extract_text(response)
        if not text:
            raise OpenAIProviderError("Gemini API response did not include text output.")
        return text

    def _urllib_transport(
        self,
        url: str,
        payload: Dict[str, Any],
        headers: Dict[str, str],
        timeout: int,
    ) -> Dict[str, Any]:
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise OpenAIProviderError(f"Gemini API returned HTTP {exc.code}: {body}") from exc
        except urllib.error.URLError as exc:
            raise OpenAIProviderError(f"Gemini API request failed: {exc.reason}") from exc

    def _extract_text(self, response: Dict[str, Any]) -> str:
        parts: list[str] = []
        for candidate in response.get("candidates", []):
            if not isinstance(candidate, dict):
                continue
            content = candidate.get("content")
            if not isinstance(content, dict):
                continue
            for part in content.get("parts", []):
                if (
                    isinstance(part, dict)
                    and not part.get("thought")
                    and part.get("type") not in {"thought", "reasoning", "analysis"}
                    and isinstance(part.get("text"), str)
                ):
                    parts.append(part["text"])
        return _strip_reasoning_trace("\n".join(part.strip() for part in parts if part.strip()))


class OpenAIImageClient:
    images_url = "https://api.openai.com/v1/images/generations"
    edits_url = "https://api.openai.com/v1/images/edits"

    def __init__(
        self,
        api_key: str | None,
        transport: JsonTransport | None = None,
        multipart_transport: MultipartTransport | None = None,
        timeout: int = 120,
    ):
        self.api_key = api_key
        self.transport = transport or self._urllib_transport
        self.multipart_transport = multipart_transport or self._urllib_multipart_transport
        self.timeout = timeout

    @classmethod
    def from_env(cls) -> "OpenAIImageClient | GeminiImageClient":
        provider = os.environ.get("IMAGE_API_PROVIDER", "openai").strip().lower()
        if provider in {"gemini", "google", "nano_banana", "nano_banana_2"}:
            return GeminiImageClient.from_env()
        return cls(
            api_key=os.environ.get("OPENAI_API_KEY"),
            timeout=_timeout_from_env("OPENAI_IMAGE_TIMEOUT", 180),
        )

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key)

    def generate_image(
        self,
        model: str,
        prompt: str,
        output_path: Path,
        size: str = "1024x1024",
        quality: str = "low",
    ) -> str:
        if not self.api_key:
            raise OpenAIProviderError("OPENAI_API_KEY is not configured.")

        payload: Dict[str, Any] = {
            "model": model,
            "prompt": prompt,
            "size": size,
            "quality": quality,
            "n": 1,
        }
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        try:
            response = self.transport(self.images_url, payload, headers, self.timeout)
        except TimeoutError as exc:
            raise OpenAIProviderError(f"OpenAI Image API request timed out: {exc}") from exc
        image_b64 = self._extract_b64(response)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(base64.b64decode(image_b64))
        return output_path.as_posix()

    def generate_image_edit(
        self,
        model: str,
        prompt: str,
        reference_image_path: Path,
        output_path: Path,
        size: str = "1024x1024",
        quality: str = "low",
        input_fidelity: str | None = None,
    ) -> str:
        if not self.api_key:
            raise OpenAIProviderError("OPENAI_API_KEY is not configured.")
        if not reference_image_path.exists():
            raise OpenAIProviderError(f"Reference image not found: {reference_image_path}")

        fields = {
            "model": model,
            "prompt": prompt,
            "size": size,
            "quality": quality,
            "n": "1",
        }
        if input_fidelity:
            fields["input_fidelity"] = input_fidelity
        body, content_type = _build_multipart_body(
            fields=fields,
            file_field="image",
            file_path=reference_image_path,
        )
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": content_type,
        }
        try:
            response = self.multipart_transport(self.edits_url, body, headers, self.timeout)
        except TimeoutError as exc:
            raise OpenAIProviderError(f"OpenAI Image Edit API request timed out: {exc}") from exc
        image_b64 = self._extract_b64(response)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(base64.b64decode(image_b64))
        return output_path.as_posix()

    def _urllib_transport(
        self,
        url: str,
        payload: Dict[str, Any],
        headers: Dict[str, str],
        timeout: int,
    ) -> Dict[str, Any]:
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise OpenAIProviderError(f"OpenAI Image API returned HTTP {exc.code}: {body}") from exc
        except urllib.error.URLError as exc:
            raise OpenAIProviderError(f"OpenAI Image API request failed: {exc.reason}") from exc

    def _urllib_multipart_transport(
        self,
        url: str,
        body: bytes,
        headers: Dict[str, str],
        timeout: int,
    ) -> Dict[str, Any]:
        request = urllib.request.Request(
            url,
            data=body,
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            response_body = exc.read().decode("utf-8", errors="replace")
            raise OpenAIProviderError(
                f"OpenAI Image Edit API returned HTTP {exc.code}: {response_body}"
            ) from exc
        except urllib.error.URLError as exc:
            raise OpenAIProviderError(f"OpenAI Image Edit API request failed: {exc.reason}") from exc

    def _extract_b64(self, response: Dict[str, Any]) -> str:
        data = response.get("data")
        if isinstance(data, list) and data:
            first = data[0]
            if isinstance(first, dict) and isinstance(first.get("b64_json"), str):
                return first["b64_json"]
        raise OpenAIProviderError("OpenAI image response did not include b64_json.")


class GeminiImageClient:
    default_generate_content_base_url = "https://generativelanguage.googleapis.com/v1beta"

    def __init__(
        self,
        api_key: str | None,
        transport: JsonTransport | None = None,
        timeout: int = 120,
        generate_content_base_url: str | None = None,
        default_model: str = "gemini-3.1-flash-image-preview",
        grounding: str = "off",
    ):
        self.api_key = api_key
        self.transport = transport or self._urllib_transport
        self.timeout = timeout
        self.generate_content_base_url = (
            generate_content_base_url or self.default_generate_content_base_url
        )
        self.default_model = default_model
        self.grounding = grounding.strip().lower()
        self.provider_name = "gemini_image"

    @classmethod
    def from_env(cls) -> "GeminiImageClient":
        return cls(
            api_key=(
                os.environ.get("GEMINI_API_KEY")
                or os.environ.get("GOOGLE_API_KEY")
                or os.environ.get("GEMMA_API_KEY")
                or os.environ.get("TEXT_API_KEY")
            ),
            timeout=_timeout_from_env("GEMINI_IMAGE_TIMEOUT", _timeout_from_env("OPENAI_IMAGE_TIMEOUT", 180)),
            generate_content_base_url=_normalize_base_url(
                os.environ.get("GEMINI_API_BASE_URL")
                or "https://generativelanguage.googleapis.com/v1beta"
            ),
            default_model=os.environ.get("GEMINI_IMAGE_MODEL") or "gemini-3.1-flash-image-preview",
            grounding=os.environ.get("GEMINI_IMAGE_GROUNDING") or "off",
        )

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key)

    def generate_image(
        self,
        model: str,
        prompt: str,
        output_path: Path,
        size: str = "1024x1024",
        quality: str = "low",
    ) -> str:
        if not self.api_key:
            raise OpenAIProviderError("GEMINI_API_KEY is not configured.")

        payload: Dict[str, Any] = {
            "contents": [
                {
                    "parts": [{"text": prompt}],
                }
            ],
            "generationConfig": {
                "responseModalities": ["IMAGE"],
            },
        }
        grounding_tool = self._grounding_tool()
        if grounding_tool:
            payload["tools"] = [grounding_tool]
        response = self._generate_content(model, payload)
        image_b64 = self._extract_b64(response)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(base64.b64decode(image_b64))
        return output_path.as_posix()

    def generate_image_edit(
        self,
        model: str,
        prompt: str,
        reference_image_path: Path,
        output_path: Path,
        size: str = "1024x1024",
        quality: str = "low",
        input_fidelity: str | None = None,
    ) -> str:
        if not self.api_key:
            raise OpenAIProviderError("GEMINI_API_KEY is not configured.")
        if not reference_image_path.exists():
            raise OpenAIProviderError(f"Reference image not found: {reference_image_path}")

        mime_type = mimetypes.guess_type(reference_image_path.name)[0] or "image/png"
        reference_b64 = base64.b64encode(reference_image_path.read_bytes()).decode("ascii")
        payload: Dict[str, Any] = {
            "contents": [
                {
                    "parts": [
                        {"text": prompt},
                        {
                            "inlineData": {
                                "mimeType": mime_type,
                                "data": reference_b64,
                            }
                        },
                    ],
                }
            ],
            "generationConfig": {
                "responseModalities": ["IMAGE"],
            },
        }
        response = self._generate_content(model, payload)
        image_b64 = self._extract_b64(response)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(base64.b64decode(image_b64))
        return output_path.as_posix()

    def _generate_content(self, model: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        url = (
            f"{self.generate_content_base_url}/models/{model or self.default_model}:generateContent"
            f"?key={self.api_key}"
        )
        headers = {
            "Content-Type": "application/json",
        }
        try:
            return self.transport(url, payload, headers, self.timeout)
        except TimeoutError as exc:
            raise OpenAIProviderError(f"Gemini Image API request timed out: {exc}") from exc

    def _urllib_transport(
        self,
        url: str,
        payload: Dict[str, Any],
        headers: Dict[str, str],
        timeout: int,
    ) -> Dict[str, Any]:
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise OpenAIProviderError(f"Gemini Image API returned HTTP {exc.code}: {body}") from exc
        except urllib.error.URLError as exc:
            raise OpenAIProviderError(f"Gemini Image API request failed: {exc.reason}") from exc

    def _extract_b64(self, response: Dict[str, Any]) -> str:
        for candidate in response.get("candidates", []):
            if not isinstance(candidate, dict):
                continue
            content = candidate.get("content")
            if not isinstance(content, dict):
                continue
            for part in content.get("parts", []):
                if not isinstance(part, dict):
                    continue
                inline_data = part.get("inlineData") or part.get("inline_data")
                if isinstance(inline_data, dict) and isinstance(inline_data.get("data"), str):
                    return inline_data["data"]
        raise OpenAIProviderError("Gemini image response did not include inline image data.")

    def _grounding_tool(self) -> Dict[str, Any] | None:
        if self.grounding in {"", "0", "false", "no", "off", "none"}:
            return None
        if self.grounding in {"image", "image_search"}:
            return {"google_search": {"searchTypes": {"imageSearch": {}}}}
        if self.grounding in {"web", "google", "google_search"}:
            return {"google_search": {}}
        if self.grounding in {"both", "all", "web_image", "web_and_image"}:
            return {
                "google_search": {
                    "searchTypes": {
                        "webSearch": {},
                        "imageSearch": {},
                    }
                }
            }
        return None


def _timeout_from_env(name: str, default: int) -> int:
    raw_value = os.environ.get(name)
    if raw_value is None or not raw_value.strip():
        return default
    try:
        return int(raw_value)
    except ValueError:
        return default


def _bool_from_env(name: str, default: bool) -> bool:
    raw_value = os.environ.get(name)
    if raw_value is None or not raw_value.strip():
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "y", "on"}


def _normalize_base_url(url: str) -> str:
    return url.rstrip("/")


def _chat_completions_url(base_url: str) -> str:
    normalized = _normalize_base_url(base_url)
    if normalized.endswith("/chat/completions"):
        return normalized
    if normalized.endswith("/v1"):
        return f"{normalized}/chat/completions"
    return f"{normalized}/v1/chat/completions"


def _build_multipart_body(
    *,
    fields: Dict[str, str],
    file_field: str,
    file_path: Path,
) -> tuple[bytes, str]:
    boundary = f"----studywithme-{uuid4().hex}"
    body = bytearray()
    for name, value in fields.items():
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
        body.extend(str(value).encode("utf-8"))
        body.extend(b"\r\n")

    mime_type = mimetypes.guess_type(file_path.name)[0] or "image/png"
    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(
        (
            f'Content-Disposition: form-data; name="{file_field}"; '
            f'filename="{file_path.name}"\r\n'
        ).encode("utf-8")
    )
    body.extend(f"Content-Type: {mime_type}\r\n\r\n".encode("utf-8"))
    body.extend(file_path.read_bytes())
    body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode("utf-8"))
    return bytes(body), f"multipart/form-data; boundary={boundary}"
