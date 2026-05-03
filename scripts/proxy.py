#!/usr/bin/env python
"""Reasoning-extraction proxy for mlx_vlm.server.

Listens on :8081 (override with PORT), forwards to UPSTREAM
(default http://127.0.0.1:8080). For /v1/chat/completions:

  1. Injects `enable_thinking=true` if the client didn't set it (mlx-vlm
     defaults thinking off; standard OpenAI clients don't know to opt in).
  2. Extracts `<think>...</think>` from `content` into `reasoning_content`
     for both streaming and non-streaming responses.
  3. Strips `<tool_call>...</tool_call>` Qwen-XML from `content`. mlx-vlm
     streaming emits the structured `tool_calls` delta correctly AND
     duplicates the raw XML into `content`; the XML is noise the client
     already has parsed. Verified on Qwen3.6-35B-A3B-4bit.
  4. Coerces empty `tool_calls[].function.arguments` to `"{}"`. Zed runs
     `serde_json::from_str` on this field and silently fails to execute
     the call when it's empty (zed-industries/zed#48955).
  5. Rewrites SSE events for Zed/opencode/pi-mono compatibility — see
     `_normalize_usage`, `_is_noop_delta`, `_format_chunk`, and
     `_split_mixed_delta` for the per-issue rationale.

Upstream non-2xx responses are mirrored verbatim so the client sees the
real status, content-type, and message instead of a mangled SSE stream.

A second mount under `/quiet/*` runs the same extraction but drops
`reasoning_content` instead of emitting it. The model still thinks
(`enable_thinking=true` is injected regardless), the client just doesn't
see thinking deltas — for harnesses like opencode whose openai-compatible
adapter renders one "Thinking:" line per delta and has no opt-out
(anomalyco/opencode#10470).

Other paths pass through.
"""
from __future__ import annotations

import json
import logging
import os
import sys
from collections import defaultdict
from typing import TypedDict

import aiohttp
from aiohttp import web


class TagState(TypedDict):
    inside: bool
    buffer: str


log = logging.getLogger("proxy")

UPSTREAM = os.environ.get("UPSTREAM", "http://127.0.0.1:8080")
PORT = int(os.environ.get("PORT", "8081"))

TAG_THINK_OPEN = "<think>"
TAG_THINK_CLOSE = "</think>"
TAG_TOOL_CALL_OPEN = "<tool_call>"
TAG_TOOL_CALL_CLOSE = "</tool_call>"

SSE_PREFIX = b"data: "

# Long enough for slow generations on cold load; short enough to surface a wedged upstream.
SOCKET_READ_TIMEOUT_S = 600

SESSION = web.AppKey("session", aiohttp.ClientSession)

QUIET_PREFIX = "/quiet"


def _strip_quiet(path_qs: str) -> tuple[str, bool]:
    """If `path_qs` starts with `/quiet`, strip it and signal hide_reasoning.
    Returns (upstream_path, hide_reasoning). Empty paths normalize to "/"."""
    if path_qs.startswith(QUIET_PREFIX):
        return path_qs[len(QUIET_PREFIX):] or "/", True
    return path_qs, False


def _partial_tag_suffix_len(text: str, tag: str) -> int:
    """Length of the longest suffix of `text` that is a non-empty prefix of `tag`."""
    n = min(len(text), len(tag) - 1)
    while n > 0:
        if tag.startswith(text[-n:]):
            return n
        n -= 1
    return 0


def _split_by_tags(text: str, state: TagState, open_tag: str, close_tag: str) -> tuple[str, str]:
    """Split `text` into (outside, inside) using `open_tag` / `close_tag`.

    `state` carries `inside` and `buffer` across calls so a tag split
    across two streamed chunks is still detected. Mutated in place.
    """
    text = state["buffer"] + text
    state["buffer"] = ""
    outside_parts: list[str] = []
    inside_parts: list[str] = []
    pos = 0
    while pos < len(text):
        if state["inside"]:
            target, sink, on_found = close_tag, inside_parts, False
        else:
            target, sink, on_found = open_tag, outside_parts, True
        idx = text.find(target, pos)
        if idx >= 0:
            sink.append(text[pos:idx])
            pos = idx + len(target)
            state["inside"] = on_found
            continue
        tail = text[pos:]
        hold = _partial_tag_suffix_len(tail, target)
        if hold:
            sink.append(tail[:-hold])
            state["buffer"] = tail[-hold:]
        else:
            sink.append(tail)
        pos = len(text)
    return "".join(outside_parts), "".join(inside_parts)


def split_chunk(text: str, state: TagState) -> tuple[str, str]:
    """Split `text` into (content, reasoning) using `<think>` tags."""
    return _split_by_tags(text, state, TAG_THINK_OPEN, TAG_THINK_CLOSE)


def strip_tool_call_xml(text: str, state: TagState) -> str:
    """Drop `<tool_call>...</tool_call>` blocks from text. mlx-vlm streaming
    duplicates the parsed call as raw Qwen-XML in `content`; clients render
    it as text alongside the structured tool-call card."""
    outside, _ = _split_by_tags(text, state, TAG_TOOL_CALL_OPEN, TAG_TOOL_CALL_CLOSE)
    return outside


def make_state(inside: bool = False) -> TagState:
    return {"inside": inside, "buffer": ""}


def rewrite_content(text: str, think_state: TagState, strip_state: TagState) -> tuple[str, str]:
    """Apply both content rewrites in the order they must run: extract
    `<think>` into reasoning, then drop `<tool_call>` XML from what
    remains. Both passes carry per-choice state across streamed chunks."""
    content, reasoning = split_chunk(text, think_state)
    content = strip_tool_call_xml(content, strip_state)
    return content, reasoning


def _normalize_usage(obj: dict) -> None:
    """Rename mlx-vlm's Anthropic-style usage keys to OpenAI's. Zed's
    `Usage` struct requires `prompt_tokens` and `completion_tokens` as
    non-optional u64s, so without this every streaming event fails its
    untagged-enum match (zed-industries/zed#42584)."""
    usage = obj.get("usage")
    if not isinstance(usage, dict):
        return
    if "input_tokens" in usage:
        usage["prompt_tokens"] = usage.pop("input_tokens")
    if "output_tokens" in usage:
        usage["completion_tokens"] = usage.pop("output_tokens")


def _coerce_empty_tool_arguments(tool_calls) -> None:
    """mlx-vlm emits `arguments: ""` for no-arg tool calls; Zed then runs
    `serde_json::from_str("")` on it, fails silently, and the call is never
    executed (zed-industries/zed#48955). Coerce to `"{}"`. Safe to apply
    per-delta because mlx-vlm emits the entire tool_call in one streaming
    delta — verified on Qwen3.6-35B-A3B-4bit — so we never overwrite a
    legitimately-empty first chunk of a streamed argument string."""
    if not tool_calls:
        return
    for tc in tool_calls:
        fn = tc.get("function") if isinstance(tc, dict) else None
        if isinstance(fn, dict) and fn.get("arguments") == "":
            fn["arguments"] = "{}"


def _is_noop_delta(obj: dict) -> bool:
    """A chunk is a no-op when no choice carries content, reasoning,
    tool_calls, or finish_reason. mlx-vlm emits these for held-back
    tokens (split_chunk or strip_tool_call_xml buffering a partial tag),
    for content deltas fully consumed by the tool-call XML stripper, and
    for filler updates that only bump usage. We deliberately don't check
    `role` — mlx-vlm stamps `role:"assistant"` onto every chunk, so
    checking it would never drop anything."""
    for ch in obj.get("choices", []):
        if ch.get("finish_reason") is not None:
            return False
        d = ch.get("delta") or {}
        if d.get("content") or d.get("reasoning_content") or d.get("tool_calls"):
            return False
    return True


def _serialize(obj: dict) -> bytes:
    return SSE_PREFIX + json.dumps(obj, separators=(",", ":")).encode("utf-8") + b"\n"


def _split_mixed_delta(obj: dict, deltas: list[dict]) -> bytes:
    """When a delta carries both `reasoning_content` and `content` (the
    `</think>` boundary), emit it as two events — reasoning-only first,
    then content-only — so pi-mono (which processes content before
    reasoning within a single delta) keeps order intact. Pop+restore
    avoids deepcopying the surrounding obj."""
    contents = [d.pop("content", None) for d in deltas]
    # Extra `\n` promotes the `data:` line terminator into a full SSE event
    # boundary (`\n\n`) so downstream sees two events, not one with a multi-
    # line data field.
    reasoning_event = _serialize(obj) + b"\n"
    for d, c in zip(deltas, contents):
        d.pop("reasoning_content", None)
        if c is not None:
            d["content"] = c
    return reasoning_event + _serialize(obj)


def _format_chunk(obj: dict, first_chunk_sent: bool) -> bytes:
    """Serialize an SSE chunk with the harness fixups. Returns b"" to
    drop a fully no-op chunk, otherwise the bytes to write. The very
    first chunk is preserved even if it's a no-op so clients see the
    initial `delta.role` (Vercel AI SDK and others depend on it)."""
    if first_chunk_sent and _is_noop_delta(obj):
        return b""

    deltas = [ch.get("delta") or {} for ch in obj.get("choices", [])]

    if any(d.get("reasoning_content") and d.get("content") for d in deltas):
        return _split_mixed_delta(obj, deltas)

    # Drop empty `content: ""` when reasoning is present so opencode's
    # AI SDK doesn't oscillate between text and reasoning Parts
    # (anomalyco/opencode#22241).
    for d in deltas:
        if d.get("reasoning_content") and d.get("content") == "":
            del d["content"]

    return _serialize(obj)


def _forward_headers(headers) -> dict:
    # Drop accept-encoding so aiohttp can't transparently gunzip a response we
    # then re-emit as raw bytes — keeping the original content-encoding header
    # would lie about the body. Drop content-length because aiohttp recomputes it.
    return {k: v for k, v in headers.items() if k.lower() not in ("host", "content-length", "accept-encoding")}


class _StreamState:
    """Mutable per-response state for the streaming rewriter."""

    __slots__ = ("think_states", "strip_states", "hide_reasoning", "first_chunk_sent")

    def __init__(self, hide_reasoning: bool, starts_in_think: bool) -> None:
        self.think_states: dict[int, TagState] = defaultdict(lambda: make_state(starts_in_think))
        self.strip_states: dict[int, TagState] = defaultdict(make_state)
        self.hide_reasoning = hide_reasoning
        self.first_chunk_sent = False


def _rewrite_message(
    msg: dict,
    think_state: TagState,
    strip_state: TagState,
    hide_reasoning: bool,
) -> None:
    """Apply the per-message rewrite invariant in place: lift `<think>`
    into reasoning, strip `<tool_call>` XML from content, coerce empty
    tool_call arguments. Used by both streaming (per delta) and non-
    streaming (per message); only the state lifetime differs."""
    text = msg.get("content")
    if text:
        new_content, reasoning = rewrite_content(text, think_state, strip_state)
        msg["content"] = new_content
        if reasoning and not hide_reasoning:
            msg["reasoning_content"] = reasoning
    _coerce_empty_tool_arguments(msg.get("tool_calls"))


def _process_sse_line(raw_line: bytes, state: _StreamState) -> bytes:
    """Process one SSE line through the rewriter. Returns the bytes to
    write (empty bytes = drop). The same helper handles in-stream lines
    and the final partial line on EOF, so a stream that ends without a
    trailing `\\n` doesn't bypass the rewriter."""
    if not raw_line.startswith(SSE_PREFIX):
        return raw_line + b"\n"
    try:
        obj = json.loads(raw_line[len(SSE_PREFIX):])
    except json.JSONDecodeError:
        # Covers `[DONE]` and any other non-JSON payload mlx-vlm emits.
        return raw_line + b"\n"
    for choice in obj.get("choices", []):
        delta = choice.get("delta") or {}
        idx = choice.get("index", 0)
        _rewrite_message(delta, state.think_states[idx], state.strip_states[idx], state.hide_reasoning)
    _normalize_usage(obj)
    out = _format_chunk(obj, state.first_chunk_sent)
    if out:
        state.first_chunk_sent = True
    return out


async def _proxy_chat_completions(request: web.Request) -> web.StreamResponse:
    body = await request.read()
    streaming = False
    # mlx-vlm's chat template prepends `<think>\n` to the assistant turn when
    # enable_thinking is true, so the streamed output starts INSIDE the think
    # block and the model only emits `</think>` to close it. Inject the flag
    # if the client didn't set it — that's what makes harnesses like Zed,
    # pi, and opencode actually see reasoning through this proxy.
    # Default False: if body parse fails we forward unchanged, mlx-vlm runs
    # with thinking off (its default), and output won't start in `<think>`.
    starts_in_think = False
    try:
        req = json.loads(body or b"{}")
        if isinstance(req, dict):
            streaming = bool(req.get("stream", False))
            if "enable_thinking" not in req:
                req["enable_thinking"] = True
                # ensure_ascii=False keeps Umlauts/CJK as one byte each instead
                # of expanding to `ü` etc; harmless on the wire and ~30%
                # smaller for non-ASCII prompts.
                body = json.dumps(req, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            starts_in_think = bool(req["enable_thinking"])
    except json.JSONDecodeError:
        log.warning("could not parse request body; forwarding as-is, enable_thinking not injected")

    session = request.app[SESSION]
    upstream_path, hide_reasoning = _strip_quiet(request.path_qs)
    upstream_url = f"{UPSTREAM}{upstream_path}"
    headers = _forward_headers(request.headers)

    async with session.post(upstream_url, data=body, headers=headers) as upstream:
        if upstream.status >= 400:
            # Don't try to rewrite an error body as SSE — mirror it verbatim
            # so the client sees the real status, content-type, and message.
            # Other upstream headers are intentionally dropped; mlx-vlm errors
            # are short JSON payloads and Content-Type is the only one clients
            # actually need.
            return web.Response(
                status=upstream.status,
                body=await upstream.read(),
                content_type=upstream.headers.get("Content-Type", "text/plain"),
            )

        if not streaming:
            data = await upstream.json()
            for choice in data.get("choices", []):
                msg = choice.get("message") or {}
                _rewrite_message(msg, make_state(starts_in_think), make_state(), hide_reasoning)
            _normalize_usage(data)
            return web.json_response(data, status=upstream.status)

        response = web.StreamResponse(
            status=upstream.status,
            headers={
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
            },
        )
        await response.prepare(request)

        state = _StreamState(hide_reasoning=hide_reasoning, starts_in_think=starts_in_think)
        line_buffer = b""
        async for chunk in upstream.content.iter_any():
            line_buffer += chunk
            if b"\n" not in line_buffer:
                continue
            # One split per upstream chunk; the trailing partial line (if any)
            # carries forward. Coalesce all rewritten lines into one write,
            # so we don't pay an await + flush per SSE event.
            lines = line_buffer.split(b"\n")
            line_buffer = lines.pop()
            out = bytearray()
            for raw_line in lines:
                out += _process_sse_line(raw_line, state)
            if out:
                await response.write(out)
        if line_buffer:
            # Upstream ended mid-line (no trailing `\n`). Treat as a complete
            # event so the rewriter sees it instead of forwarding raw.
            tail = _process_sse_line(line_buffer, state)
            if tail:
                await response.write(tail)
        await response.write_eof()
        return response


async def _passthrough(request: web.Request) -> web.StreamResponse:
    body = await request.read() if request.can_read_body else None
    session = request.app[SESSION]
    upstream_path, _ = _strip_quiet(request.path_qs)
    upstream_url = f"{UPSTREAM}{upstream_path}"
    headers = _forward_headers(request.headers)

    async with session.request(request.method, upstream_url, data=body, headers=headers) as upstream:
        response = web.StreamResponse(
            status=upstream.status,
            headers={
                k: v for k, v in upstream.headers.items()
                if k.lower() not in ("transfer-encoding", "content-length", "content-encoding")
            },
        )
        await response.prepare(request)
        async for chunk in upstream.content.iter_any():
            await response.write(chunk)
        await response.write_eof()
        return response


async def _on_startup(app: web.Application) -> None:
    app[SESSION] = aiohttp.ClientSession(
        timeout=aiohttp.ClientTimeout(total=None, sock_read=SOCKET_READ_TIMEOUT_S)
    )


async def _on_cleanup(app: web.Application) -> None:
    await app[SESSION].close()


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("PROXY_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    app = web.Application(client_max_size=128 * 1024 * 1024)
    app.on_startup.append(_on_startup)
    app.on_cleanup.append(_on_cleanup)
    app.router.add_post("/v1/chat/completions", _proxy_chat_completions)
    app.router.add_post("/quiet/v1/chat/completions", _proxy_chat_completions)
    app.router.add_route("*", "/{tail:.*}", _passthrough)
    print(f"→ proxy on http://127.0.0.1:{PORT} → {UPSTREAM}", file=sys.stderr)
    web.run_app(app, host="127.0.0.1", port=PORT, access_log=None, print=lambda _: None)


if __name__ == "__main__":
    main()
