#!/usr/bin/env python3
"""omnivoice.py — local OmniVoice text-to-speech for ovoz (Apple Silicon, mlx-audio).

  omnivoice.py download [--model ID]                 fetch the weights into the Hugging Face cache
  omnivoice.py synth --text T --out F.wav [opts]     one shot: load, speak, exit
  omnivoice.py serve --port 8179 [--idle 600]        keep the model in memory; POST /synth, GET /health
  omnivoice.py normalize --text T [--lang uz]        print the text the model would read (for tests)

  opts: --lang uz  --ref ref.wav  --ref-text "exact words of ref.wav"  --steps 32  --speed 1.2  --model ID

Run with the ovoz venv (voice-omnivoice.sh does that). Long text is split on sentence
boundaries and every chunk uses the SAME reference voice, so the tone does not drift.
Each chunk gets the model's own length estimate (natural pace, no padding — extra time
turns into pauses inside the sentence), divided by --speed.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

DEFAULT_MODEL = "mlx-community/OmniVoice-bf16"
MAX_CHUNK_CHARS = 300  # whole sentences are joined up to this; every chunk boundary is a pause
PAUSE_BETWEEN_CHUNKS_S = 0.25
MIN_SPEED, MAX_SPEED = 0.7, 1.6  # outside this range the voice breaks up
TOKENS_PER_SECOND = 25  # OmniVoice audio tokens (24 kHz / 960)
ESTIMATE_MARGIN = 1.15  # the same margin mlx-audio adds to its own estimate
TARGET_RMS_DBFS = -18.0
PEAK_LIMIT = 0.97

# --- text normalization (pure Python, no model needed) -----------------------------

APOSTROPHES = re.compile(r"[‘’ʻʼ`´]")

UZ_ONES = [
    "nol",
    "bir",
    "ikki",
    "uch",
    "to'rt",
    "besh",
    "olti",
    "yetti",
    "sakkiz",
    "to'qqiz",
]
UZ_TENS = [
    "",
    "o'n",
    "yigirma",
    "o'ttiz",
    "qirq",
    "ellik",
    "oltmish",
    "yetmish",
    "sakson",
    "to'qson",
]
UZ_SCALES = [(10**9, "milliard"), (10**6, "million"), (1000, "ming")]


def uz_number(n: int) -> str:
    """Integer → Uzbek words (0 … 999 999 999 999)."""
    if n < 10:
        return UZ_ONES[n]
    words = []
    for value, name in UZ_SCALES:
        if n >= value:
            head = n // value
            # "ming", not "bir ming"; but "bir million"
            words.append(
                name if (head == 1 and value == 1000) else f"{uz_number(head)} {name}"
            )
            n %= value
    if n >= 100:
        head = n // 100
        words.append("yuz" if head == 1 else f"{UZ_ONES[head]} yuz")
        n %= 100
    if n >= 10:
        words.append(UZ_TENS[n // 10])
        n %= 10
    if n:
        words.append(UZ_ONES[n])
    return " ".join(words)


def normalize(text: str, lang: str) -> str:
    text = APOSTROPHES.sub("'", text)
    text = re.sub(r"\s+", " ", text).strip()
    if lang == "uz":
        text = re.sub(r"(\d+)\s*%", lambda m: f"{m.group(1)} foiz", text)
        text = re.sub(r"\d{1,12}", lambda m: uz_number(int(m.group(0))), text)
    return text


def estimate_seconds(text: str) -> float:
    """OmniVoice's own rule-based length estimate (what it uses when no duration is given)."""
    from mlx_audio.tts.models.omnivoice.duration import RuleDurationEstimator

    tokens = RuleDurationEstimator().estimate_duration(text, "Nice to meet you.", TOKENS_PER_SECOND)
    return max(10, int(tokens * ESTIMATE_MARGIN)) / TOKENS_PER_SECOND


def split_chunks(text: str) -> list[str]:
    """Whole sentences joined greedily up to MAX_CHUNK_CHARS (fewer joins = fewer pauses)."""
    sentences = [s.strip() for s in re.split(r"(?<=[.!?…])\s+", text) if s.strip()]
    chunks: list[str] = []
    for sentence in sentences:
        # very long sentence → split on commas so no chunk gets too long
        parts = (
            [sentence]
            if len(sentence) <= MAX_CHUNK_CHARS
            else re.split(r"(?<=[,;:])\s+", sentence)
        )
        for part in parts:
            if (
                chunks
                and len(chunks[-1]) + len(part) + 1 <= MAX_CHUNK_CHARS
            ):
                chunks[-1] = f"{chunks[-1]} {part}"
            else:
                chunks.append(part)
    return chunks


# --- synthesis ---------------------------------------------------------------------


class Speaker:
    def __init__(self, model_id: str):
        from mlx_audio.tts.utils import load_model

        started = time.time()
        self.model = load_model(model_id)
        self.sample_rate = self.model.sample_rate
        log(f"model {model_id} loaded in {time.time() - started:.1f}s")

    def synth(
        self,
        text: str,
        out: str,
        lang: str = "uz",
        ref: str | None = None,
        ref_text: str | None = None,
        steps: int = 32,
        speed: float = 1.0,
    ) -> float:
        import numpy as np
        import soundfile as sf

        clean = normalize(text, lang)
        if not clean:
            raise ValueError("empty text")
        if ref and not ref_text:
            raise ValueError(
                "ref_text is required with ref (exact words of the reference clip)"
            )
        pause = np.zeros(
            int(PAUSE_BETWEEN_CHUNKS_S * self.sample_rate), dtype=np.float32
        )
        pieces = []
        for chunk in split_chunks(clean):
            kwargs = {
                "text": chunk,
                "language": lang,
                "num_steps": steps,
                # speed > 1 → shorter target → faster speech (same voice, no pitch change)
                "duration_s": estimate_seconds(chunk) / speed,
            }
            if ref:
                kwargs.update(ref_audio=ref, ref_text=ref_text)
            audio = np.concatenate(
                [
                    np.asarray(r.audio, dtype=np.float32)
                    for r in self.model.generate(**kwargs)
                ]
            )
            pieces.extend([fade(audio, self.sample_rate), pause])
        audio = level(np.concatenate(pieces[:-1]))
        sf.write(out, audio, self.sample_rate)
        return len(audio) / self.sample_rate


def clamp_speed(speed: float) -> float:
    return min(MAX_SPEED, max(MIN_SPEED, speed))


def fade(audio, sample_rate, ms: int = 12):
    import numpy as np

    n = min(len(audio) // 2, int(sample_rate * ms / 1000))
    if n > 0:
        ramp = np.linspace(0.0, 1.0, n, dtype=np.float32)
        audio[:n] *= ramp
        audio[-n:] *= ramp[::-1]
    return audio


def level(audio):
    """Same loudness for every clip: RMS to TARGET_RMS_DBFS, peaks kept under PEAK_LIMIT."""
    import numpy as np

    rms = float(np.sqrt(np.mean(audio**2))) if len(audio) else 0.0
    if rms > 1e-6:
        audio = audio * (10 ** (TARGET_RMS_DBFS / 20) / rms)
    peak = float(np.max(np.abs(audio))) if len(audio) else 0.0
    if peak > PEAK_LIMIT:
        audio = audio * (PEAK_LIMIT / peak)
    return audio.astype(np.float32)


def log(message: str) -> None:
    print(f"[omnivoice] {message}", file=sys.stderr, flush=True)


# --- commands ----------------------------------------------------------------------


def cmd_download(args) -> int:
    from huggingface_hub import snapshot_download

    path = snapshot_download(args.model)
    print(path)
    return 0


def cmd_synth(args) -> int:
    speaker = Speaker(args.model)
    started = time.time()
    seconds = speaker.synth(
        args.text, args.out, args.lang, args.ref, args.ref_text, args.steps, clamp_speed(args.speed)
    )
    log(f"{seconds:.1f}s of audio in {time.time() - started:.1f}s → {args.out}")
    return 0


def cmd_serve(args) -> int:
    speaker = Speaker(args.model)
    state = {"last": time.time()}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):  # keep stderr for our own lines
            pass

        def reply(self, code: int, body: dict) -> None:
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            state["last"] = time.time()
            self.reply(
                200, {"ok": True, "model": args.model}
            ) if self.path == "/health" else self.reply(404, {"ok": False})

        def do_POST(self):
            state["last"] = time.time()
            if self.path != "/synth":
                return self.reply(404, {"ok": False})
            try:
                req = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", "0")))
                    or b"{}"
                )
                started = time.time()
                seconds = speaker.synth(
                    req["text"],
                    req["out"],
                    req.get("lang", "uz"),
                    req.get("ref") or None,
                    req.get("ref_text") or None,
                    int(req.get("steps", 32)),
                    clamp_speed(float(req.get("speed", 1.0))),
                )
                self.reply(
                    200,
                    {
                        "ok": True,
                        "seconds": round(seconds, 2),
                        "took": round(time.time() - started, 2),
                    },
                )
            except Exception as exc:  # report to the caller, keep serving
                log(f"synth failed: {exc}")
                self.reply(500, {"ok": False, "error": str(exc)})
            state["last"] = time.time()

    server = HTTPServer(("127.0.0.1", args.port), Handler)
    server.timeout = 5
    log(f"serving on 127.0.0.1:{args.port}, exits after {args.idle}s idle")
    while time.time() - state["last"] < args.idle:
        server.handle_request()
    log("idle — exiting to free memory")
    return 0


def cmd_normalize(args) -> int:
    print(" | ".join(split_chunks(normalize(args.text, args.lang))))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="local OmniVoice TTS for ovoz")
    sub = parser.add_subparsers(dest="cmd", required=True)

    def common(p, needs_text=True):
        p.add_argument("--model", default=DEFAULT_MODEL)
        p.add_argument("--lang", default="uz")
        if needs_text:
            p.add_argument("--text", required=True)

    p = sub.add_parser("download")
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.set_defaults(fn=cmd_download)
    p = sub.add_parser("synth")
    common(p)
    p.add_argument("--out", required=True)
    p.add_argument("--ref")
    p.add_argument("--ref-text")
    p.add_argument("--steps", type=int, default=32)
    p.add_argument("--speed", type=float, default=1.0)
    p.set_defaults(fn=cmd_synth)
    p = sub.add_parser("serve")
    common(p, needs_text=False)
    p.add_argument("--port", type=int, default=8179)
    p.add_argument("--idle", type=int, default=600)
    p.set_defaults(fn=cmd_serve)
    p = sub.add_parser("normalize")
    common(p)
    p.set_defaults(fn=cmd_normalize)

    args = parser.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
