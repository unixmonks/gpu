"""Measure time to first token and decode tokens/sec of a streamed /v1/messages endpoint.

Works against Claude (directly or through a proxy) and against Maya/Strata, which serve the
same Anthropic Messages API, so the numbers are comparable.

usage: tps.py BASE_URL MODEL [--api anthropic|openai] [--runs N] [--max-tokens N] [--effort low|medium|high]
auth:  ANTHROPIC_API_KEY (x-api-key) and/or BEARER_TOKEN (Authorization: Bearer)
"""
import argparse
import json
import os
import statistics
import time
import urllib.request

PROMPT = (
    "Write a complete, well-commented Python module implementing an LRU cache with TTL expiry, "
    "thread safety, and a small CLI demo. Output only the code."
)

ap = argparse.ArgumentParser()
ap.add_argument("base_url")
ap.add_argument("model")
ap.add_argument("--runs", type=int, default=3)
ap.add_argument("--max-tokens", type=int, default=4000)
ap.add_argument("--effort", default=None, help="Claude only; engines ignore or reject it")
ap.add_argument("--api", choices=["anthropic", "openai"], default="anthropic",
                help="/v1/messages or /v1/chat/completions")
args = ap.parse_args()

headers = {
    "content-type": "application/json",
    "anthropic-version": "2026-10-21",
    "user-agent": "gpu-tps/1",
}
if os.environ.get("ANTHROPIC_API_KEY"):
    headers["x-api-key"] = os.environ["ANTHROPIC_API_KEY"]
if os.environ.get("BEARER_TOKEN"):
    headers["authorization"] = f"Bearer {os.environ['BEARER_TOKEN']}"


def events(path, body):
    """Yield (arrival time, parsed SSE data) for a streamed POST."""
    req = urllib.request.Request(
        args.base_url.rstrip("/") + path, json.dumps(body).encode(), headers
    )
    with urllib.request.urlopen(req, timeout=600) as resp:
        for raw in resp:
            line = raw.decode().strip()
            if line.startswith("data:") and line[5:].strip() != "[DONE]":
                yield time.monotonic(), json.loads(line[5:])


def stream_messages():
    body = {
        "model": args.model,
        "max_tokens": args.max_tokens,
        "stream": True,
        "messages": [{"role": "user", "content": PROMPT}],
    }
    if args.effort:
        body["output_config"] = {"effort": args.effort}
    first = first_text = None  # first content of any kind (thinking or text) / first answer text
    out_tokens = 0
    for t, ev in events("/v1/messages", body):
        if ev["type"] in ("content_block_start", "content_block_delta") and first is None:
            first = t
        if ev["type"] == "content_block_delta" and ev["delta"].get("type") == "text_delta":
            first_text = first_text or t
        if ev["type"] == "message_delta":
            out_tokens = ev.get("usage", {}).get("output_tokens", out_tokens)
        if ev["type"] == "error":
            raise SystemExit(f"stream error: {ev}")
    return first, first_text, out_tokens


def stream_chat():
    body = {
        "model": args.model,
        "max_tokens": args.max_tokens,
        "stream": True,
        "stream_options": {"include_usage": True},
        "messages": [{"role": "user", "content": PROMPT}],
    }
    first = first_text = None
    out_tokens = chunks = 0
    for t, ev in events("/v1/chat/completions", body):
        if "error" in ev:
            raise SystemExit(f"stream error: {ev}")
        for choice in ev.get("choices") or []:
            delta = choice.get("delta") or {}
            # Servers name the thinking field differently.
            if delta.get("reasoning_content") or delta.get("reasoning"):
                first = first or t
                chunks += 1
            if delta.get("content"):
                first = first or t
                first_text = first_text or t
                chunks += 1
        if ev.get("usage"):
            out_tokens = ev["usage"].get("completion_tokens", out_tokens)
    # Without a usage report, one chunk is usually one token.
    return first, first_text, out_tokens or chunks


def run():
    t0 = time.monotonic()
    first, first_text, out_tokens = (stream_chat if args.api == "openai" else stream_messages)()
    end = time.monotonic()
    # output_tokens includes any thinking tokens, which stream before the text.
    return {
        "ttft_s": round((first or end) - t0, 2),
        "first_text_s": round((first_text or end) - t0, 2),
        "total_s": round(end - t0, 2),
        "output_tokens": out_tokens,
        "decode_tps": round(out_tokens / max(end - (first or t0), 1e-6), 1),
    }


results = []
for i in range(args.runs):
    r = run()
    results.append(r)
    print(f"run {i + 1}: {json.dumps(r)}", flush=True)

tps = [r["decode_tps"] for r in results]
print(
    f"\n{args.model}: decode {statistics.median(tps)} tok/s median "
    f"(min {min(tps)}, max {max(tps)}), "
    f"TTFT {statistics.median(r['ttft_s'] for r in results)} s median over {len(results)} runs"
)
