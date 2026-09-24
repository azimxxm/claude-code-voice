# claude-code-voice (`ovoz`)

**Claude Code bilan o'zbekcha gaplashing va javobini eshiting.** Plugin, skill va buyruq nomi `ovoz`.

O'zbek modeli, whisper.cpp uchun tayyor: **https://huggingface.co/azimxxm/rubaistt-v2-medium-ggml** (516 MB, Apache-2.0). Bepul, internetga deyarli bog'liq emas, bitta buyruq.

```bash
claude plugin marketplace add azimxxm/claude-code-voice && claude plugin install ovoz@ovoz
# Claude Code ichida:        /ovoz setup        (vositalar + modellar, ~10 daqiqa, bir marta)
# loyiha papkasida:          claude-voice       (tepada Claude, pastda quloq — gapiravering)
```

Claude Code'ning o'z `/voice` diktovkasi bor (Space'ni bosib turasiz), lekin u 20 tilni biladi, o'zbekcha ular orasida yo'q, va u hech qachon javob qaytarib gapirmaydi. ovoz ikkala kamchilikni yopadi: siz tanlagan tilda, o'zbekchani chindan tushunadigan model bilan eshitadi, aytganingizni Claude'ga yozib beradi va javobni tabiiy neyron ovoz bilan o'qib beradi. Cloud engine'ni o'zingiz tanlamasangiz, hech narsa Mac'dan chiqmaydi.

## Nima beradi

| Qism | Nima | Qayerda |
| --- | --- | --- |
| **quloq** | default: tugma rejimi — **⌥ Space** ni bosib turasiz (Hammerspoon) yoki quloq oynasida ⏎ bosasiz; boshqa vaqt hech narsa yozilmaydi, ofisdagi gaplar Claude'ga bormaydi. Qo'lsiz rejim (`ovoz mode vad`) jim bo'lguningizcha yozadi. → whisper.cpp matnga o'giradi (Metal; `whisper-server` modelni xotirada tutadi, gap boshiga ≈ 1 s). O'zbekcha uchun fine-tune qilingan Whisper ([`islomov/rubaistt_v2_medium`](https://huggingface.co/islomov/rubaistt_v2_medium), Apache-2.0, ≈ 17 % WER); boshqa tillar `large-v3-turbo`. | Mac'da |
| **ovoz** | [`edge-tts`](https://github.com/rany2/edge-tts) — Microsoft neyron ovozlari `uz-UZ-MadinaNeural` / `uz-UZ-SardorNeural` (bepul va odamdek eshitiladigan yagona o'zbek ovozlari), ru/en/tr/kk/de ham bor. Claude har javobini tugatadigan `🔊` qatorini o'qiydi. | internet, kalitsiz |
| **yelim** | tmux matnni Claude oynasiga yozib Enter bosadi. Ikki hook: `UserPromptSubmit` Claude'ga suhbat og'zaki ekanini aytadi; `Stop` javobni gapiradi. | plugin |
| **`/ovoz`** | skill: holat, setup, til, ovoz, engine, sky, test — `ovoz` buyrug'ini Claude o'zi ishga tushiradi. | plugin |
| **`agent-sky`** | agentlar jamoangiz 3D galaktika ko'rinishida ([agent-galaxy](https://github.com/taehyeonglim/agent-galaxy)); `--live`: sessiyalar, subagentlar va tool chaqiruvlari yonib turgan tugunlar ([Agent Flow](https://github.com/patoles/agent-flow)). | brauzer, lokal |
| **hotkey** (ixtiyoriy) | Hammerspoon: **⌥ Space** bosib turing, gapiring, qo'yib yuboring → matn kursor turgan joyga yoziladi. | Mac'da |

## O'rnatish

**Plugin (tavsiya)** — skill va hook'lar o'zi ro'yxatdan o'tadi, boshqa hech narsa tegilmaydi:

```bash
claude plugin marketplace add azimxxm/claude-code-voice
claude plugin install ovoz@ovoz
```

**Oddiy fayllar** — o'sha skriptlar `~/.claude/ovoz/bin` ga ko'chiriladi, hook'lar `~/.claude/settings.json` ga qo'shiladi (backup qoladi), `./uninstall.sh` qaytaradi:

```bash
git clone https://github.com/azimxxm/claude-code-voice && cd claude-code-voice && ./install.sh
```

Keyin bir marta:

```bash
ovoz setup              # brew: sox, whisper.cpp, edge-tts; modellar: large-v3-turbo 1.6 GB + o'zbek 0.5 GB (tayyor ggml, Hugging Face)
ovoz hotkey             # gapirish tugmasi (Hammerspoon, ⌥ Space) — tavsiya
```

Talablar: Apple Silicon Mac (Metal), Homebrew, `python3`, `tmux`, **mikrofon** (Mac mini'da yo'q — USB mikrofon, AirPods yoki iPhone Continuity), loyiha papkasidagi Claude Code sessiyasi. Birinchi yozuvda terminal ilovangiz uchun Mikrofon ruxsati so'raladi.

## Ishlatish

```bash
cd ~/code/my-project
claude-voice                 # tmux: tepada Claude, pastda quloq. ⌥ Space ni bosib turib gapiring, qo'yib yuboring — yuboriladi.
claude-voice --ear my-sess   # ishlab turgan tmux sessiyasiga quloq qo'shish
claude-voice --stop
```

Claude Code ichida yoki istalgan terminalda:

```
/ovoz                 holat                    ovoz status
/ovoz uz | ru | en    suhbat tili              ovoz lang tr
/ovoz speak off       jim rejim                ovoz speak on
/ovoz voice sardor    erkak o'zbek ovozi       ovoz voice list tr-TR
/ovoz engine gigaam   boshqa quloq             ovoz engine gemini   (GEMINI_API_KEY kerak)
/ovoz sky             agentlar galaktikasi     ovoz sky live · ovoz sky off
/ovoz mode vad        qo'lsiz quloq            ovoz mode ptt   (default: tugma)
/ovoz test            mikrofonsiz o'z-o'zini tekshirish     ovoz say "Salom"
```

Read-aloud yoqiq bo'lsa Claude sizning tilingizda, qisqa javob beradi, ko'p qadamli topshiriqni ishdan oldin bir qatorda qayta aytadi (`Maqsad: …`) va har javobni bitta `🔊 …` qator bilan tugatadi — siz eshitadigan qism shu. Yozish va gapirish bir sessiyada aralashib ketaveradi.

## Boshqa tillar

`ovoz lang <kod>` va `ovoz voice list <locale>` + `ovoz voice <nom>`. Tanib olish `config.json` dagi `stt.models` da alohida modeli bo'lmagan barcha tillar uchun `large-v3-turbo` orqali. O'z tilingiz uchun fine-tune qo'shish — ggml fayl bo'lsa, bitta config qatori; konversiya [docs/models.md](docs/models.md) da.

Batafsil: [docs/architecture.md](docs/architecture.md), [docs/engines.md](docs/engines.md), [docs/troubleshooting.md](docs/troubleshooting.md). O'zbek modelining keyingi versiyalari (v3, v4: nima qilamiz, qayerdan nima olamiz): [docs/roadmap-model-v3.md](docs/roadmap-model-v3.md). Litsenziya: MIT.
