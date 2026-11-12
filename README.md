# Veil

A native macOS menubar app (SwiftUI `MenuBarExtra`) that does locally what AgentCloak does in the browser:
**cloak** PII in your clipboard with consistent synthetic "twins" before you paste into an AI chatbot, then
**uncloak** the reply to restore the real values. Nothing leaves your Mac.

Detection is [Rampart](https://github.com/nationaldesignstudio/rampart) by National Design Studio
([HF: nationaldesignstudio/rampart](https://huggingface.co/nationaldesignstudio/rampart), CC BY 4.0):
a deterministic validator/regex layer plus a q4-quantized MiniLM-L6 BERT token classifier (~14.7 MB ONNX).

## Usage
| Action | Hotkey | |
|---|---|---|
| Cloak clipboard | ⌃⌥⌘C | detect → replace with twins → write back to clipboard |
| Uncloak clipboard | ⌃⌥⌘U | replace every known twin with its original |
| Clear session | ⌃⌥⌘K | forget the twin map (and re-salt) |

The session twin map is in-memory only and shown in the menu.

## Build
Requirements: macOS 13+, Xcode 15+ (Swift 5.9).

```bash
./scripts/download-model.sh            # → ~/Library/Application Support/Veil/rampart
swift test                             # VeilCore unit tests (regex layer, twin map, tokenizer, BIO decode)
swift run Veil                         # runs as a menubar accessory
./scripts/bundle-app.sh                # → build/Veil.app (EMBED_MODEL=1 to bundle the model)
```
Or `open Package.swift` in Xcode and run the `Veil` scheme. Model lookup order: `$VEIL_MODEL_DIR`,
`~/Library/Application Support/Veil/rampart`, `Veil.app/Contents/Resources/rampart`. Without a model Veil runs regex-only.

## Pipeline (mirrors Rampart)
1. **Heuristics** (`Heuristics.swift`, port of `src/heuristics.ts` + `validators.ts`): digit runs joined by single
   space/dash/dot → 16/15/14 digits + Luhn = `CREDIT_CARD`, 9 digits + SSN rules = `SSN`; regex `EMAIL`, `URL`
   (scheme and `www.`), IPv4/IPv6/MAC → `IP_ADDRESS`. **Veil addition:** NANP `PHONE` regex (Rampart leaves phones to the model).
2. **Premask** (`premask.ts`): heuristic spans → `[SSN]`, `[EMAIL]`… sentinels (model was trained on this), with a
   per-UTF-16-unit map back to raw offsets.
3. **NER**: `-`→space (1:1), BERT uncased WordPiece (lowercase + accent strip + punctuation split; custom 19,730 vocab,
   `[PAD]=0 [UNK]=1 [CLS]=2 [SEP]=3`), windows of 500 tokens with 64 overlap, ONNX inputs `input_ids`/`attention_mask`/`token_type_ids`
   (int64 `[1, seq]`), output `logits [1, seq, 35]`.
4. **Decode** (`mergeBioTokens`): softmax/argmax over 35 BIO labels; `##` pieces always continue the same base label;
   anchor score 0.4, weaker (≥0.15) spans kept only if bridged to an anchor by connector chars.
5. **Policy** (`policy.ts`): merge overlaps (higher score → longer → heuristic), default keep-set `CITY/STATE/ZIP_CODE`.
6. **Twins**: deterministic per session salt, format-preserving, from reserved/fictional ranges
   (555-01xx phones, `example.com`, 9xx SSN area, Visa test BIN with valid Luhn, RFC 5737/3849 IPs).

## Why ONNX Runtime, not Core ML
The shipped `onnx/model_q4.onnx` (opset 18) uses the `com.microsoft::MatMulNBits` contrib op, which coremltools
cannot convert. We use Microsoft's `onnxruntime-swift-package-manager` (CPU EP; Core ML EP optional).
**Core ML path**, if wanted later: export the fp32 checkpoint (not published on HF — would need the training
weights or a dequantization of the q4 graph) with `transformers` → `torch.jit.trace` → `coremltools.convert(
..., inputs=[ct.TensorType(shape=(1, ct.RangeDim(1,512)), dtype=np.int32)]*3)`, then swap `RampartONNXDetector`
for a Core ML `NERDetector`; the rest of the pipeline is unchanged.

## Attribution
Rampart model and pipeline © National Design Studio, CC BY 4.0. Veil's Swift port of the heuristics/premask/policy logic follows that source.
