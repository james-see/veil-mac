import Foundation
import OnnxRuntimeBindings
import VeilCore

/// Runs nationaldesignstudio/rampart (onnx/model_q4.onnx) with ONNX Runtime.
/// Graph (verified): inputs input_ids / attention_mask / token_type_ids  [batch, seq] int64,
/// output `logits` [batch, seq, 35]. Uses com.microsoft MatMulNBits (q4), so ORT — not Core ML — is required.
final class RampartONNXDetector: NERDetector, @unchecked Sendable {
    private let env: ORTEnv
    private let session: ORTSession
    private let tokenizer: WordPieceTokenizer
    private let queue = DispatchQueue(label: "veil.rampart")  // one session, sequential inference (as Rampart does)

    init(modelDir: URL) throws {
        env = try ORTEnv(loggingLevel: .warning)
        let opts = try ORTSessionOptions()
        try opts.setIntraOpNumThreads(2)
        try opts.setGraphOptimizationLevel(.all)
        // Optional: try opts.appendCoreMLExecutionProvider(with: ORTCoreMLExecutionProviderOptions())
        // CoreML EP will fall back to CPU for MatMulNBits nodes; measure before enabling.
        session = try ORTSession(env: env, modelPath: modelDir.appendingPathComponent("onnx/model_q4.onnx").path, sessionOptions: opts)
        tokenizer = try WordPieceTokenizer(vocabURL: modelDir.appendingPathComponent("vocab.txt"))
    }

    func detect(_ text: String) async throws -> [Span] {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do { cont.resume(returning: try self.detectSync(text)) } catch { cont.resume(throwing: error) }
            }
        }
    }

    private func detectSync(_ text: String) throws -> [Span] {
        let tokens = tokenizer.tokenize(text)
        var spans: [Span] = []
        for w in NERWindowing.windows(count: tokens.count) {
            let slice = Array(tokens[w])
            let logits = try run(slice)
            spans += BIODecoder.decode(tokens: slice, logits: logits, text: text)
        }
        return mergeSpans(spans)
    }

    /// Returns per-content-token logits (CLS/SEP rows dropped).
    private func run(_ toks: [Token]) throws -> [[Float]] {
        let ids: [Int64] = [Int64(tokenizer.clsId)] + toks.map { Int64($0.id) } + [Int64(tokenizer.sepId)]
        let n = ids.count
        func tensor(_ v: [Int64]) throws -> ORTValue {
            let data = NSMutableData(bytes: v, length: v.count * MemoryLayout<Int64>.size)
            return try ORTValue(tensorData: data, elementType: .int64, shape: [1, NSNumber(value: n)])
        }
        let out = try session.run(
            withInputs: [
                "input_ids": try tensor(ids),
                "attention_mask": try tensor([Int64](repeating: 1, count: n)),
                "token_type_ids": try tensor([Int64](repeating: 0, count: n)),
            ],
            outputNames: ["logits"], runOptions: nil)
        guard let value = out["logits"] else { return [] }
        let data = try value.tensorData() as Data
        let labels = rampartId2Label.count
        let floats: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard floats.count == n * labels else { return [] }
        return (1..<(n - 1)).map { i in Array(floats[(i * labels)..<((i + 1) * labels)]) }
    }
}

enum ModelLocator {
    /// Search order: $VEIL_MODEL_DIR, ~/Library/Application Support/Veil/rampart, bundled Resources/rampart.
    static func find() -> URL? {
        let fm = FileManager.default
        var c: [URL] = []
        if let e = ProcessInfo.processInfo.environment["VEIL_MODEL_DIR"] { c.append(URL(fileURLWithPath: e)) }
        if let s = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            c.append(s.appendingPathComponent("Veil/rampart"))
        }
        if let r = Bundle.main.resourceURL { c.append(r.appendingPathComponent("rampart")) }
        return c.first { fm.fileExists(atPath: $0.appendingPathComponent("onnx/model_q4.onnx").path) }
    }
}
