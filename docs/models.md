# Models

## Speech-to-text

Measured on this project's synthesized test clips (edge-tts Uzbek voices, 16 kHz), Apple Silicon:

| Model | "Assalomu alaykum. Men Jarvis. Bugun qanday vazifani bajaramiz?" | "Jarvis, iOS ilovada login ekranini Swift bilan yoz, keyin testlarni ishga tushir va GitHub'ga push qil." |
| --- | --- | --- |
| **rubaiSTT v2 medium q5_0** (default for `uz`) | assalomu alaykum men jarvis bugun qanday vazifani bajaramiz | jarvis ios ilovada login ekranini swift bilan yoz, keyin testlarni ishga tushir va githubga push qil. |
| Kotib/uzbek_stt_v1 q5_0 | assalomu alaykum. men jervis. bugun qanday vazifani bajaramiz? | jarvis **yoz** ilovada … va **youtube** ga push qil. |
| GigaAM Multilingual int8 | assalomu alaykum men jarves bugun qanday vazifani bajaramiz | jarvis **yos** ilovada … va **youtubega** push qil |
| Whisper large-v3-turbo | Assalamualaikum. Min Jarvis. Bugun kandai vazifani bajaramis. | Jarvis, IAS ilawada login ekranini Swift bilan IAS, ki in testlarni iške tshirva githubke pushkul. |

Published numbers (different test sets, not directly comparable):

- `islomov/rubaistt_v2_medium` (Whisper-medium fine-tune, Apache-2.0): ~17 % WER / 5.5 % CER on the author's set.
- `Kotib/uzbek_stt_v1` (Whisper-medium fine-tune, Apache-2.0): 16.7 % WER over eight of the author's sets.
- GigaAM Multilingual (Conformer, MIT MLX port): **7.3 % WER on FLEURS Uzbek**, Whisper large-v3 on the same set ≈ 88–105 % — [benchmark](https://github.com/ai-babai/gigaam-multilingual-mlx/blob/main/docs/benchmark-multilingual-v1.md).
- Real conversational Uzbek podcast audio ([uzbek-stt-bench](https://github.com/avazibra/uzbek-stt-bench), Sept 2026): Gemini 3 Flash 15.3 %, Muxlisa 22.2 %, ElevenLabs Scribe 24.9 %, uzbekvoice 28.1 %.

Take-away: plain Whisper is unusable for Uzbek; any Uzbek fine-tune is a different world; GigaAM
is the best-measured on read speech and worth trying with a real microphone (`ovoz engine gigaam`).
The default stays rubaiSTT because it won on the tech sentence and speaks proper Latin Uzbek.

## How the Uzbek ggml is made

`ovoz setup` first tries a ready ggml copy; if that mirror is missing it builds one:

```bash
python3 -m venv venv && venv/bin/pip install torch transformers numpy safetensors huggingface_hub
venv/bin/hf download islomov/rubaistt_v2_medium --local-dir hf/rubaistt_v2_medium
git clone --depth 1 https://github.com/openai/whisper build/whisper      # mel filters + tokenizer assets
curl -O https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/models/convert-h5-to-ggml.py
venv/bin/python convert-h5-to-ggml.py hf/rubaistt_v2_medium build/whisper out/   # → out/ggml-model.bin (f16, 1.5 GB)
whisper-quantize out/ggml-model.bin ggml-rubaistt-medium-q5_0.bin q5_0            # → 516 MB, same words as q8_0
```

Any Hugging Face Whisper fine-tune converts the same way. Point `stt.models.<lang>` in
`~/.claude/ovoz/config.json` at the file and that language uses it.

## Text-to-speech

| Engine | Uzbek | Free | Notes |
| --- | --- | --- | --- |
| **edge-tts** (default) | `uz-UZ-MadinaNeural`, `uz-UZ-SardorNeural` | yes, no key | Microsoft's Azure neural voices through the Edge read-aloud endpoint; unofficial, breaks now and then (`pipx upgrade edge-tts`) |
| Azure AI Speech | same two voices | 0.5 M chars/month free | official, needs a key |
| Aisha AI, UzbekVoiceAI, Muxlisa | yes (Gulnoza; shoira/lola/kamola/jasur/sevinch; two voices) | trial only | the natural Uzbek voices you hear in viral clips; regional APIs |
| ElevenLabs, Google Cloud TTS, macOS `say`, Kokoro | **no Uzbek voice** | — | Russian and English work (`say -v Milena`) |
| facebook/mms-tts-uzb, uzlm/sayro-tts-1.7B | yes | open weights | robotic or heavy; offline options if you need them |
