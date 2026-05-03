"""Unit tests for the rewriter helpers in scripts/proxy.py.

Focused on the load-bearing pure functions: tag splitting, tool-call
arg coercion, no-op detection, single-line SSE processing. The async
HTTP handler is exercised end-to-end by the wire tests in dev (curl +
the real upstream); pytest here covers the parts that have edge cases.
"""
from __future__ import annotations

from scripts.proxy import (
    SSE_PREFIX,
    TAG_THINK_CLOSE,
    TAG_THINK_OPEN,
    TAG_TOOL_CALL_CLOSE,
    TAG_TOOL_CALL_OPEN,
    _coerce_empty_tool_arguments,
    _is_noop_delta,
    _partial_tag_suffix_len,
    _process_sse_line,
    _split_by_tags,
    _StreamState,
    make_state,
    rewrite_content,
    strip_tool_call_xml,
)


def _think(text: str, state) -> tuple[str, str]:
    return _split_by_tags(text, state, TAG_THINK_OPEN, TAG_THINK_CLOSE)


def _tool(text: str, state) -> str:
    return strip_tool_call_xml(text, state)


# ---------- _split_by_tags / _partial_tag_suffix_len ----------


def test_split_by_tags_chunked_open_tag():
    """Tag split across two chunks: `<th` + `ink>x</think>b` → ('b', 'x')."""
    state = make_state()
    out1, in1 = _think("a<th", state)
    out2, in2 = _think("ink>x</think>b", state)
    assert out1 + out2 == "ab"
    assert in1 + in2 == "x"


def test_split_by_tags_consecutive():
    """Back-to-back tags with no separation: outsides empty, insides concat."""
    state = make_state()
    outside, inside = _think("<think>a</think><think>b</think>", state)
    assert outside == ""
    assert inside == "ab"


def test_split_by_tags_starts_inside():
    """When the stream begins inside a tag (mlx-vlm with enable_thinking=true),
    text before the close tag is reasoning, content starts after."""
    state = make_state(inside=True)
    outside, inside = _think("reasoning</think>visible", state)
    assert outside == "visible"
    assert inside == "reasoning"


def test_split_by_tags_no_tags_passthrough():
    state = make_state()
    outside, inside = _think("plain content with no tags", state)
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
    out1 = _tool("\n\n<tool_call>\n<func", state)
    out2 = _tool("tion=x>\n</function>\n</tool_call>after", state)
    assert out1 + out2 == "\n\nafter"


def test_strip_tool_call_xml_no_tags():
    state = make_state()
    assert _tool("plain content", state) == "plain content"


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
