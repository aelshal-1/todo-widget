import AVFoundation
import Foundation
import Speech

/// Live speech-to-text in Arabic or English.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(localeID: String) async {
        error = nil
        guard await Self.authorize() else {
            error = "Allow Microphone and Speech Recognition for Todo in Settings."
            return
        }
        let fallback = localeID.hasPrefix("ar") ? SFSpeechRecognizer(locale: Locale(identifier: "ar-SA")) : nil
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) ?? fallback, recognizer.isAvailable else {
            error = "Speech recognition isn't available for this language right now."
            return
        }
        finish()
        transcript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            self.request = request

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tapBlock(request))
            engine.prepare()
            try engine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(self))
        } catch {
            self.error = error.localizedDescription
            finish()
        }
    }

    /// Stop listening; the final text arrives a moment later.
    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.finish()
        }
    }

    fileprivate func receive(text: String?, isFinal: Bool, failed: Bool) {
        if let text, !text.isEmpty { transcript = text }
        if isFinal || failed { finish() }
    }

    private func finish() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request = nil
        task = nil
        if isRecording {
            isRecording = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated private static func tapBlock(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        return { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func resultHandler(_ owner: SpeechRecognizer) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        return { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                owner?.receive(text: text, isFinal: isFinal, failed: failed)
            }
        }
    }

    nonisolated static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }
}
