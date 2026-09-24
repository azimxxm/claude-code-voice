# Model roadmap: rubaiSTT v2 → ovoz-stt-uz v3, v4 …

## Maqsad (o'zbekcha, qisqacha)

Dasturchi nutqini tushunadigan o'zbek STT modeli: texnik atamalar (Claude Code, GitHub, Swift,
commit), uz/ru/en aralash gaplar, sizning ovozingiz va shevangiz. Har yangi versiya (v3, v4 …)
o'lchanadigan tarzda avvalgisidan yaxshi bo'lishi, takrorlanadigan (data ro'yxati + skript + config
ochiq) va `ovoz setup` bir qatorda yuklab oladigan ggml fayl bo'lib chiqishi shart. Eski versiyalar
o'chirilmaydi, `ovoz` istalganiga qaytishi mumkin.

Yo'l: **v3.0** — o'z ovozimiz + texnik lug'at bilan LoRA (arzon, eng katta foyda) → **v3.x** — ochiq
o'zbek datasetlar bilan to'liq fine-tune (GPU ijara, ~$10–30 bir yurish) → **v4** — kattaroq asos
(large-v3-turbo) bilan tajriba; faqat o'lchov yutsa chiqadi.

### Nima qilamiz (tartib bilan)

| # | Ish | Kim | Vaqt |
| --- | --- | --- | --- |
| 1 | `training/` toolkit: `collect.sh`, `prepare.py`, `train.py`, `eval.py`, `export.sh`, configlar | Claude Code | 1 sessiya |
| 2 | `training/sentences/dev-uz.txt` — 200 dasturchi gapi (uz/ru/en aralash) + `terms.txt` atamalar | Claude Code, siz tekshirasiz | 1 soat |
| 3 | Yozuv: `collect.sh` gaplarni birma-bir ko'rsatadi, siz o'qiysiz (mikrofon kerak); 200 test gap + 1–3 soat erkin nutq | siz | 2–4 soat, bir necha kunga bo'lib |
| 4 | v2 ni bizning test to'plamlarimizda o'lchash (baseline qatori) | Claude Code | 1 soat |
| 5 | v3.0: LoRA o'qitish → eval → ggml → HF `azimxxm/ovoz-stt-uz-v3` → `ovoz setup` yangi URL | Claude Code (+ GPU akkaunt kerak bo'lsa siz) | 1 kun |
| 6 | Kundalik ishlatish; `ovoz log` dagi xatolarni yangi gaplar sifatida yig'ish | siz | doimiy |
| 7 | v3.1: ochiq datasetlar bilan to'liq fine-tune (ijara GPU) | Claude Code + siz | 1–2 kun |
| 8 | v4: kattaroq asos bilan tajriba | Claude Code | v3.x to'xtab qolganda |

### Qayerdan nima olamiz

| Manba | Nima | Qayerdan / qanday |
| --- | --- | --- |
| Asos model | rubaiSTT v2 (Whisper medium, Apache-2.0) | `hf download islomov/rubaistt_v2_medium` |
| Bizning ggml | v2 tayyor fayl | https://huggingface.co/azimxxm/rubaistt-v2-medium-ggml |
| O'z ovozimiz | 200 test gap + erkin nutq | `training/collect.sh` (SoX `rec`, 16 kHz WAV + matn) |
| Common Voice uz | ~1 400 soat hissa (validated qismi kamroq), CC0 | HF `mozilla-foundation/common_voice_17_0`, config `uz` — gated: HF login + shartlarni qabul qilish |
| uzbekvoice | 503K klip (uzbekvoice.ai crowdsourcing) | HF dataset `ai4uz/uzbekvoice-filtered` |
| FLEURS uz | ~10 soat, CC-BY-4.0 | HF `google/fleurs`, config `uz_uz` — **test split faqat baholash uchun** |
| USC | 105 soat, 958 so'zlovchi, CC-BY-4.0 | arXiv 2107.14419 sahifasidagi havola (ISSAI) |
| FeruzaSpeech | 60 soat, bitta ayol ovozi | arXiv 2410.00035 sahifasidagi havola |
| Podkast/YouTube dev suhbatlar | cheksiz, huquq turlicha | yt-dlp → Gemini pseudo-transkript → WER filtri; faqat shaxsiy foydalanish |
| Normalizator | Kirill→Lotin, raqamlar | https://github.com/NavAI-pro/uzbek-text-norm |
| Baholash klipi | real podkast, 5 daqiqa, reference bilan | https://github.com/avazibra/uzbek-stt-bench |
| O'qitish retsepti | Whisper fine-tune (Seq2SeqTrainer) + LoRA | `transformers`, `peft`, `datasets`, `evaluate` (jiwer) |
| GPU | A100 80GB / L4, soatbay | RunPod, Vast.ai, Lambda — ~$1–3/soat |
| ggml konversiya | HF → whisper.cpp | `convert-h5-to-ggml.py` + `whisper-quantize` (docs/models.md) |

---

## 1. Where we start (baseline, 2026-09-24)

| Item | Value |
| --- | --- |
| Current model | [`islomov/rubaistt_v2_medium`](https://huggingface.co/islomov/rubaistt_v2_medium) — Whisper medium, 769M params, Apache-2.0; author-reported WER ≈ 17 %, CER ≈ 5.5 % |
| Shipped as | [`azimxxm/rubaistt-v2-medium-ggml`](https://huggingface.co/azimxxm/rubaistt-v2-medium-ggml) — ggml q5_0, 516 MB, whisper-server ≈ 0.6 s per sentence on Apple Silicon |
| Training data of v2 (per the card) | podcasts, Tashkent-dialect podcasts, news, FLEURS, USC, Common Voice 17; 50 % human transcripts, 50 % Gemini 2.5 Pro pseudo-labels, WER-filtered |
| Known weaknesses | English tech terms spelled phonetically or replaced (`iOS` → `yos` in sibling models); no punctuation/casing; Russian transliterated to Latin |
| Reference points | GigaAM Multilingual: 7.3 % WER on FLEURS uz (read speech); Gemini 3 Flash: 15.3 % on real podcast speech ([uzbek-stt-bench](https://github.com/avazibra/uzbek-stt-bench)) |

The first task of v3 is to **measure v2 ourselves** on the test sets below, so every later number has a
baseline from the same script.

## 2. Success criteria (a version ships only if all hold)

1. **Developer test set** (`dev-uz-200`: 200 held-out sentences, own recordings, tech vocabulary,
   uz/ru/en mixed): word accuracy ≥ 95 % after normalization (v2 to be measured; expected ≈ 85–90 %).
2. **FLEURS uz test**: WER ≤ v2's measured WER − 2 points (no regression on general speech).
3. **uzbek-stt-bench ep40**: WER not worse than v2 by more than 1 point.
4. **Latency**: same size class as v2 (medium) → whisper-server timing unchanged; a larger base (v4)
   must document its cost per sentence.
5. **Reproducible**: dataset manifest, training config and seed committed; eval row in `docs/models.md`.

## 3. Data

### Sources and licenses

| Source | Hours | License | Use |
| --- | --- | --- | --- |
| Own recordings (`training/collect.sh`) | 1–3 h to start | ours | v3.0 core; `dev-uz-200` held out, never trained on |
| Own free speech (voice notes; `ovoz` can keep clips on request) | grows | ours | v3.x |
| Common Voice uz 17/18 | large | CC0 | v3.x general |
| `ai4uz/uzbekvoice-filtered` | 503K clips | per card | v3.x general |
| FLEURS uz — train split | ~10 h | CC-BY-4.0 | v3.x; test split = eval only |
| USC | 105 h, 958 speakers | CC-BY-4.0 | v3.x |
| FeruzaSpeech | 60 h, one speaker | per card | v3.x |
| Podcasts / dev talks | open-ended | rights vary | pseudo-labeled + WER-agreement filtered; private use unless cleared |
| edge-tts synthetic audio | — | — | **tests only, never training** (one voice, no noise) |

### Preparation (`training/prepare.py`)

- 16 kHz mono, silence-trimmed, clips ≤ 30 s (Whisper window).
- One normalizer for training and scoring: Latin script; apostrophes `ʻ`, `’`, `'` → `'`; lowercase
  only when scoring; numbers as spoken words; `uzbek-text-norm` for Cyrillic → Latin and digits.
- Tech terms keep their real spelling (`GitHub`, `Swift`, `iOS`) — that is the point of v3.
- Dedupe against every test set by text and audio hash. Manifest = JSONL
  `{audio, text, source, speaker, license, split}`.

## 4. Training

| Stage | What | Where | Cost | Output |
| --- | --- | --- | --- | --- |
| **v3.0** | LoRA (r=32 on attention + MLP) over `rubaistt_v2_medium`; own recordings + ≥ 30 % public data; 3–5 epochs, lr 1e-4; language token `uz`, no timestamps | Mac (PyTorch MPS, slow but fine for ≤ 3 h audio) or 1 rented GPU hour | ≈ $0–5 | merged weights → ggml |
| **v3.1+** | full fine-tune from v2 with the public sets (200–500 h); lr 1e-5, warmup 500, effective batch 32, bf16, SpecAugment; eval every 1 000 steps; keep best by FLEURS WER | rented A100 80 GB / L4 | ≈ $10–30, 2–6 h | new checkpoint |
| **v4** | same data on `openai/whisper-large-v3-turbo` (809M, fast decoder), maybe `large-v3` | rented GPU | ≈ $20–60 | ships only if §2 passes with acceptable latency |

Recipe: Hugging Face `transformers` `Seq2SeqTrainer` (standard Whisper fine-tuning) + `peft` for LoRA.
One YAML per run in `training/configs/` (`v3.0-lora.yaml`, `v3.1-full.yaml`);
`python training/train.py training/configs/v3.0-lora.yaml` is the whole command.

## 5. Evaluation (`training/eval.py`)

- Inputs: a checkpoint (HF, or ggml through `whisper-cli`) + test sets `dev-uz-200`,
  `fleurs-uz-test`, `uzbek-stt-bench/ep40`.
- Metrics: WER and CER after the same normalization uzbek-stt-bench uses (lowercase, apostrophes
  folded, punctuation dropped) + **term accuracy** on `training/sentences/terms.txt`.
- Output: one Markdown row per model appended to `docs/models.md`, with config and seed.
- Rule: v2 is re-scored with the same script before any comparison.

## 6. Packaging and release (`training/export.sh`)

1. Merge LoRA → HF checkpoint dir.
2. `convert-h5-to-ggml.py` → f16 → `whisper-quantize … q5_0`; verify q5_0 == q8_0 on `dev-uz-200`
   (else ship q8_0).
3. Upload to **`azimxxm/ovoz-stt-uz-v3`**: `ggml-ovoz-uz-v3-q5_0.bin`, model card with the eval table,
   `training-config.yaml`, manifest hash.
4. `ovoz`: default `OVOZ_UZ_GGML_URL` → the new file; `docs/models.md` updated; new CLI switch
   `ovoz model uz v3|v2`.
5. Git tag `model-v3.0`; `CHANGELOG.md`: data added, config, numbers, known issues.

Versioning: **v3.x** = same base (medium), more or better data; **v4** = new base architecture.
Model repos stay online; `ovoz` can pin any version.

## 7. Risks

| Risk | Mitigation |
| --- | --- |
| Over-fitting to one voice (v3.0) | FLEURS + bench clip in the gate; ≥ 30 % public data even in v3.0 |
| Test-set leakage | `dev-uz-200` never enters training; dedupe by text and audio hash |
| Pseudo-label noise | WER-agreement between two ASR outputs; manual spot check of 5 % |
| Apostrophe / script inconsistency | one normalizer, unit-tested |
| Licenses | per-clip license in the manifest; podcasts private unless cleared |
| Synthetic audio in training | forbidden |
| Russian regressions | Russian never goes through the Uzbek model (`stt.models` routing) |

First concrete task: the `training/` toolkit and `training/sentences/dev-uz.txt` — then recording can start.
