#!/usr/bin/env python
"""Reasoning-extraction proxy for mlx_vlm.server.

Listens on :8081 (override with PORT), forwards to UPSTREAM
(default http://127.0.0.1:8080). For /v1/chat/completions, extracts
<think>...</think> from `content` into `reasoning_content` for both
streaming and non-streaming responses. Other paths pass through.
"""
from __future__ import annotations

import json
import os
import sys
from collections import defaultdict
from typing import TypedDict

import aiohttp
from aiohttp import web


class ThinkState(TypedDict):
    in_think: bool
    buffer: str

UPSTREAM = os.environ.get("UPSTREAM", "http://127.0.0.1:8080")
PORT = int(os.environ.get("PORT", "8081"))

TAG_OPEN = "<think>"
TAG_CLOSE = "</think>"

# Long enough for slow generations on cold load; short enough to surface a wedged upstream.
SOCKET_READ_TIMEOUT_S = 600


def _partial_tag_suffix_len(text: str, tag: str) -> int:
    """Length of the longest suffix of `text` that is a non-empty prefix of `tag`."""
    n = min(len(text), len(tag) - 1)
    while n > 0:
        if tag.startswith(text[-n:]):
            return n
        n -= 1
    return 0


def split_chunk(text: str, state: ThinkState) -> tuple[str, str]:
    """Split `text` into (content, reasoning) using `<think>` tags.

    `state` carries `in_think` and `buffer` across calls so a tag split
    across two streamed chunks is still detected. Mutated in place.
    """
    text = state["buffer"] + text
    state["buffer"] = ""
    content_parts: list[str] = []
    reasoning_parts: list[str] = []
    pos = 0
    while pos < len(text):
        if state["in_think"]:
            target, sink = TAG_CLOSE, reasoning_parts
            on_found = False
        else:
            target, sink = TAG_OPEN, content_parts
            on_found = True
        idx = text.find(target, pos)
        if idx >= 0:
            sink.append(text[pos:idx])
            pos = idx + len(target)
            state["in_think"] = on_found
            continue
        tail = text[pos:]
        hold = _partial_tag_suffix_len(tail, target)
        if hold:
            sink.append(tail[:-hold])
            state["buffer"] = tail[-hold:]
        else:
            sink.append(tail)
        pos = len(text)
    return "".join(content_parts), "".join(reasoning_parts)


def _forward_headers(headers) -> dict:
    return {k: v for k, v in headers.items() if k.lower() not in ("host", "content-length")}


async def _proxy_chat_completions(request: web.Request) -> web.StreamResponse:
    body = await request.read()
    streaming = False
    # Qwen3.6's chat template puts the opening `<think>` in the prompt prefix
    # when thinking is enabled, so the model output starts INSIDE the think
    # block and only emits `</think>` to close it. Default is enabled.
    starts_in_think = True
    try:
        req = json.loads(body or b"{}")
        streaming = bool(req.get("stream", False))
        if req.get("enable_thinking") is False:
            starts_in_think = False
        kw = req.get("chat_template_kwargs") or {}
        if kw.get("enable_thinking") is False:
            starts_in_think = False
    except json.JSONDecodeError:
        pass

    def make_state() -> ThinkState:
        return {"in_think": starts_in_think, "buffer": ""}

    upstream_url = f"{UPSTREAM}{request.path_qs}"
    headers = _forward_headers(request.headers)
    timeout = aiohttp.ClientTimeout(total=None, sock_read=SOCKET_READ_TIMEOUT_S)

    async with aiohttp.ClientSession(timeout=timeout) as session:
        async with session.post(upstream_url, data=body, headers=headers) as upstream:
            if not streaming:
                data = await upstream.json()
                for choice in data.get("choices", []):
                    msg = choice.get("message") or {}
                    text = msg.get("content") or ""
                    if not text:
                        continue
                    state = make_state()
                    new_content, reasoning = split_chunk(text, state)
                    msg["content"] = new_content
                    if reasoning:
                        msg["reasoning_content"] = reasoning
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

            states: dict[int, ThinkState] = defaultdict(make_state)
            line_buffer = b""
            async for chunk in upstream.content.iter_any():
                line_buffer += chunk
                # Coalesce all rewritten lines from this upstream chunk into one
                # write, so we don't pay an await + flush per SSE event.
                out = bytearray()
                while b"\n" in line_buffer:
                    raw_line, line_buffer = line_buffer.split(b"\n", 1)
                    line = raw_line.decode("utf-8", errors="replace").rstrip("\r")
                    if not line.startswith("data: "):
                        out += raw_line + b"\n"
                        continue
                    try:
                        obj = json.loads(line[len("data: "):])
                    except json.JSONDecodeError:
                        # Covers `[DONE]` and any other non-JSON payload mlx-vlm emits.
                        out += raw_line + b"\n"
                        continue
                    for choice in obj.get("choices", []):
                        delta = choice.get("delta") or {}
                        text = delta.get("content")
                        if text is None:
                            continue
                        new_content, reasoning = split_chunk(text, states[choice.get("index", 0)])
                        delta["content"] = new_content
                        if reasoning:
                            delta["reasoning_content"] = reasoning
                    out += b"data: " + json.dumps(obj, separators=(",", ":")).encode("utf-8") + b"\n"
                if out:
                    await response.write(bytes(out))
            if line_buffer:
                await response.write(line_buffer)
            await response.write_eof()
            return response


async def _passthrough(request: web.Request) -> web.StreamResponse:
    body = await request.read() if request.can_read_body else None
    upstream_url = f"{UPSTREAM}{request.path_qs}"
    headers = _forward_headers(request.headers)
    timeout = aiohttp.ClientTimeout(total=None, sock_read=SOCKET_READ_TIMEOUT_S)

    async with aiohttp.ClientSession(timeout=timeout) as session:
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


def main() -> None:
    app = web.Application(client_max_size=128 * 1024 * 1024)
    app.router.add_post("/v1/chat/completions", _proxy_chat_completions)
    app.router.add_route("*", "/{tail:.*}", _passthrough)
    print(f"→ proxy on http://127.0.0.1:{PORT} → {UPSTREAM}", file=sys.stderr)
    web.run_app(app, host="127.0.0.1", port=PORT, access_log=None, print=lambda _: None)


if __name__ == "__main__":
    main()
