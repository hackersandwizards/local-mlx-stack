"""Unit tests for the rewriter helpers in scripts/proxy.py.

Focused on the load-bearing pure functions: tag splitting, tool-call
arg coercion, no-op detection, single-line SSE processing. The async
HTTP handler is exercised end-to-end by the wire tests in dev (curl +
the real upstream); pytest here covers the parts that have edge cases.
"""
from __future__ import annotations

from scripts.proxy import (
    SSE_PREFIX,
    _coerce_empty_tool_arguments,
    _forward_headers,
    _is_noop_delta,
    _partial_tag_suffix_len,
    _process_sse_line,
    _strip_quiet,
    _StreamState,
    make_state,
    rewrite_content,
    split_chunk,
    strip_tool_call_xml,
)


# ---------- _split_by_tags / _partial_tag_suffix_len ----------


def test_split_by_tags_chunked_open_tag():
    """Tag split across two chunks: `<th` + `ink>x</think>b` → ('b', 'x')."""
    state = make_state()
    out1, in1 = split_chunk("a<th", state)
    out2, in2 = split_chunk("ink>x</think>b", state)
    assert out1 + out2 == "ab"
    assert in1 + in2 == "x"


def test_split_by_tags_consecutive():
    """Back-to-back tags with no separation: outsides empty, insides concat."""
    state = make_state()
    outside, inside = split_chunk("<think>a</think><think>b</think>", state)
    assert outside == ""
    assert inside == "ab"


def test_split_by_tags_starts_inside():
    """When the stream begins inside a tag (mlx-vlm with enable_thinking=true),
    text before the close tag is reasoning, content starts after."""
    state = make_state(inside=True)
    outside, inside = split_chunk("reasoning</think>visible", state)
    assert outside == "visible"
    assert inside == "reasoning"


def test_split_by_tags_no_tags_passthrough():
    state = make_state()
    outside, inside = split_chunk("plain content with no tags", state)
    assert outside == "plain content with no tags"
    assert inside == ""


def test_partial_tag_suffix_overlapping_prefix():
    """`<<think` against `<think>`: the inner `<think` (6 chars) is the
    longest suffix that prefixes the tag — the leading `<` is not."""
    assert _partial_tag_suffix_len("<<think", "<think>") == 6


def test_partial_tag_suffix_no_overlap():
    assert _partial_tag_suffix_len("hello world", "<think>") == 0


def test_partial_tag_suffix_full_tag_does_not_match():
    """A complete tag is consumed by the splitter, so the suffix-len helper
    only matches strict prefixes (length < len(tag))."""
    assert _partial_tag_suffix_len("<think>", "<think>") == 0


# ---------- strip_tool_call_xml ----------


def test_strip_tool_call_xml_chunked():
    state = make_state()
    out1 = strip_tool_call_xml("\n\n<tool_call>\n<func", state)
    out2 = strip_tool_call_xml("tion=x>\n</function>\n</tool_call>after", state)
    assert out1 + out2 == "\n\nafter"


def test_strip_tool_call_xml_no_tags():
    state = make_state()
    assert strip_tool_call_xml("plain content", state) == "plain content"


# ---------- rewrite_content (combined think + tool_call passes) ----------


def test_rewrite_content_combined():
    """Combined: <think>x</think>y<tool_call>z</tool_call>w → ('yw', 'x')."""
    think_state = make_state()
    strip_state = make_state()
    content, reasoning = rewrite_content(
        "<think>x</think>y<tool_call>z</tool_call>w", think_state, strip_state
    )
    assert content == "yw"
    assert reasoning == "x"


# ---------- _coerce_empty_tool_arguments ----------


def test_coerce_empty_arguments_to_object():
    """Zed bug: empty arguments string fails serde_json::from_str silently.
    Coerce to '{}' so the no-arg call actually executes."""
    tool_calls = [{"function": {"name": "now", "arguments": ""}}]
    _coerce_empty_tool_arguments(tool_calls)
    assert tool_calls[0]["function"]["arguments"] == "{}"


def test_coerce_preserves_non_empty_arguments():
    tool_calls = [{"function": {"name": "x", "arguments": '{"k":"v"}'}}]
    _coerce_empty_tool_arguments(tool_calls)
    assert tool_calls[0]["function"]["arguments"] == '{"k":"v"}'


def test_coerce_tolerates_none_and_malformed():
    _coerce_empty_tool_arguments(None)
    _coerce_empty_tool_arguments([])
    _coerce_empty_tool_arguments([None, {"function": None}, "string-not-dict"])


# ---------- _is_noop_delta ----------


def test_noop_delta_role_only_is_noop():
    """mlx-vlm stamps role:assistant on every chunk; alone it's no-op."""
    assert _is_noop_delta({"choices": [{"delta": {"role": "assistant"}}]}) is True


def test_noop_delta_with_content_is_not_noop():
    assert _is_noop_delta({"choices": [{"delta": {"content": "hi"}}]}) is False


def test_noop_delta_with_finish_reason_is_not_noop():
    assert _is_noop_delta({"choices": [{"delta": {}, "finish_reason": "stop"}]}) is False


def test_noop_delta_with_tool_calls_is_not_noop():
    assert _is_noop_delta({"choices": [{"delta": {"tool_calls": [{"id": "x"}]}}]}) is False


# ---------- _process_sse_line ----------


def _state(hide_reasoning: bool = False, starts_in_think: bool = False) -> _StreamState:
    return _StreamState(hide_reasoning=hide_reasoning, starts_in_think=starts_in_think)


def test_process_sse_line_done_passthrough():
    """`data: [DONE]` is non-JSON; forward verbatim with trailing newline."""
    out = _process_sse_line(SSE_PREFIX + b"[DONE]", _state())
    assert out == SSE_PREFIX + b"[DONE]" + b"\n"


def test_process_sse_line_blank_passthrough():
    """SSE event boundary — preserve as a blank line."""
    assert _process_sse_line(b"", _state()) == b"\n"


def test_process_sse_line_strips_tool_call_xml():
    """The tool_call XML duplicated into content gets stripped, leaving only
    the surrounding whitespace mlx-vlm emits before the call."""
    raw = (
        SSE_PREFIX
        + b'{"choices":[{"index":0,"delta":{"role":"assistant","content":"\\n<tool_call>x</tool_call>"}}]}'
    )
    out = _process_sse_line(raw, _state())
    assert b"<tool_call>" not in out
    # `\n` becomes JSON-escaped `\\n` after re-serialization.
    assert b'"content":"\\n"' in out


def test_process_sse_line_extracts_think_into_reasoning():
    """`<think>...</think>` content moves into reasoning_content."""
    raw = SSE_PREFIX + b'{"choices":[{"index":0,"delta":{"content":"<think>r</think>visible"}}]}'
    out = _process_sse_line(raw, _state())
    assert b'"reasoning_content":"r"' in out
    assert b'"content":"visible"' in out


def test_process_sse_line_quiet_mode_drops_reasoning():
    """In hide_reasoning mode the reasoning_content key is suppressed."""
    raw = SSE_PREFIX + b'{"choices":[{"index":0,"delta":{"content":"<think>r</think>visible"}}]}'
    out = _process_sse_line(raw, _state(hide_reasoning=True))
    assert b"reasoning_content" not in out
    assert b'"content":"visible"' in out


def test_process_sse_line_normalizes_usage_keys():
    """input_tokens/output_tokens → prompt_tokens/completion_tokens for Zed."""
    raw = (
        SSE_PREFIX
        + b'{"choices":[{"index":0,"delta":{"content":"x"}}],"usage":{"input_tokens":3,"output_tokens":4}}'
    )
    out = _process_sse_line(raw, _state())
    assert b"prompt_tokens" in out
    assert b"completion_tokens" in out
    assert b"input_tokens" not in out


def test_process_sse_line_coerces_empty_tool_args():
    raw = (
        SSE_PREFIX
        + b'{"choices":[{"index":0,"delta":{"tool_calls":[{"id":"a","function":{"name":"now","arguments":""}}]}}]}'
    )
    out = _process_sse_line(raw, _state())
    assert b'"arguments":"{}"' in out
    assert b'"arguments":""' not in out


def test_process_sse_line_drops_noop_after_first():
    """Second-and-later no-op chunks (role-only) are dropped to keep
    downstream clients from oscillating on empty deltas."""
    state = _state()
    state.first_chunk_sent = True
    raw = SSE_PREFIX + b'{"choices":[{"delta":{"role":"assistant"}}]}'
    assert _process_sse_line(raw, state) == b""


def test_process_sse_line_keeps_first_role_only_chunk():
    """The very first chunk (role:assistant only) must survive even though
    it's a no-op — Vercel AI SDK and others key on it."""
    state = _state()
    raw = SSE_PREFIX + b'{"choices":[{"delta":{"role":"assistant"}}]}'
    out = _process_sse_line(raw, state)
    assert b'"role":"assistant"' in out
    assert state.first_chunk_sent is True


def test_process_sse_line_splits_mixed_delta_into_two_events():
    """`</think>` boundary delta carries both reasoning and content. pi-mono
    processes content before reasoning within one delta, so we emit two
    SSE events (reasoning first, then content) to keep order intact."""
    raw = SSE_PREFIX + b'{"choices":[{"index":0,"delta":{"content":"r</think>v"}}]}'
    out = _process_sse_line(raw, _state(starts_in_think=True))
    events = [e for e in out.split(b"\n\n") if e.strip()]
    assert len(events) == 2
    assert b'"reasoning_content":"r"' in events[0]
    assert b'"content":"v"' in events[1]
    assert b"reasoning_content" not in events[1]


def test_process_sse_line_drops_empty_content_when_reasoning_present():
    """When a delta has reasoning_content + content:"", strip the empty
    content so opencode's AI SDK doesn't oscillate text/reasoning Parts."""
    raw = SSE_PREFIX + b'{"choices":[{"index":0,"delta":{"content":"<think>r</think>"}}]}'
    out = _process_sse_line(raw, _state())
    assert b'"reasoning_content":"r"' in out
    # content key should be absent (not just empty)
    assert b'"content":""' not in out
    assert b'"content"' not in out


# ---------- _strip_quiet ----------


def test_strip_quiet_removes_prefix():
    assert _strip_quiet("/quiet/v1/chat/completions") == ("/v1/chat/completions", True)


def test_strip_quiet_passthrough_when_absent():
    assert _strip_quiet("/v1/chat/completions") == ("/v1/chat/completions", False)


def test_strip_quiet_normalizes_bare_quiet_to_root():
    """`/quiet` alone (no trailing path) becomes `/` — defensive against a
    misconfigured client base URL."""
    assert _strip_quiet("/quiet") == ("/", True)


# ---------- _forward_headers ----------


def test_forward_headers_drops_hop_by_hop_and_encoding():
    """host, content-length, accept-encoding all stripped; aiohttp recomputes
    the first two and the third would let aiohttp gunzip a body we then
    re-emit raw."""
    out = _forward_headers({
        "Host": "x",
        "Content-Length": "10",
        "Accept-Encoding": "gzip",
        "Authorization": "Bearer k",
        "Content-Type": "application/json",
    })
    assert "Authorization" in out
    assert "Content-Type" in out
    assert "Host" not in out
    assert "Content-Length" not in out
    assert "Accept-Encoding" not in out


def test_forward_headers_is_case_insensitive():
    """Real HTTP headers come in any case; the filter must match regardless."""
    out = _forward_headers({"HOST": "x", "accept-ENCODING": "gzip"})
    assert out == {}
