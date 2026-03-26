//
//  SpeechRecognizerAudioHelpers.swift
//  Foundation Lab
//
//  Created by Rudrank Riyam on 10/27/25.
//

import Foundation
import Speech
import AVFoundation
import AVFAudio
import Accelerate
import OSLog

private func copyAudioBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copiedBuffer = AVAudioPCMBuffer(
        pcmFormat: buffer.format,
        frameCapacity: buffer.frameCapacity
    ) else {
        return nil
    }

    copiedBuffer.frameLength = buffer.frameLength

    guard let sourceChannels = buffer.floatChannelData,
          let destChannels = copiedBuffer.floatChannelData else {
        return nil
    }

    let channelCount = Int(buffer.format.channelCount)
    let frameLength = Int(buffer.frameLength)
    let bytesPerChannel = frameLength * MemoryLayout<Float>.stride

    for channel in 0..<channelCount {
        memcpy(destChannels[channel], sourceChannels[channel], bytesPerChannel)
    }

    return copiedBuffer
}

extension SpeechRecognizer {
    nonisolated func configureAudioSessionIfNeeded() throws {
        logger.debug("Configuring audio session for speech recognition")

        #if os(iOS)
        var lastError: Error?

        for attempt in 1...2 {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .measurement,
                    options: [.duckOthers, .defaultToSpeaker]
                )
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                logger.debug("Audio session configured successfully")
                lastError = nil
                break

            } catch {
                lastError = error
                logger.error("Audio session configuration failed (attempt \(attempt)): \(error.localizedDescription, privacy: .public)")

                if attempt == 1 {
                    usleep(100_000)
                }
            }
        }

        if lastError != nil {
            logger.error("Audio session configuration failed after all attempts")
            Task { @MainActor [weak self] in
                self?.state = .error(.audioSessionFailed)
            }
            throw SpeechRecognitionError.audioSessionFailed
        }
        #endif
    }

    nonisolated func prepareAudioEngine() throws {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()

        let inputNode = audioEngine.inputNode
        let tapFormat = try determineTapFormat(for: inputNode)

        if inputNode.numberOfInputs > 0 {
            inputNode.removeTap(onBus: 0)
        }

        audioBufferCount = 0
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: tapFormat
        ) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            guard let self else { return }
            guard !self.hasProcessedFinalResult else { return }

            guard let bufferCopy = copyAudioBuffer(buffer) else {
                self.logger.error("Failed to copy audio buffer")
                return
            }

            self.recognitionRequest?.append(bufferCopy)
            self.processAudioBuffer(bufferCopy)

            if VoiceLogging.isVerboseEnabled {
                self.audioBufferCount += 1
                if self.audioBufferCount % 200 == 0 {
                    let frameLength = buffer.frameLength
                    self.logger.debug("Processed \(self.audioBufferCount) audio buffers (frameLength=\(frameLength))")
                }
            }
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            logger.debug("Audio engine started successfully")
        } catch {
            logger.error("Audio engine start failed: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor [weak self] in
                self?.state = .error(.audioSessionFailed)
            }
            throw SpeechRecognitionError.audioSessionFailed
        }
    }

    nonisolated func determineTapFormat(for inputNode: AVAudioInputNode) throws -> AVAudioFormat {
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        if VoiceLogging.isVerboseEnabled {
            logger.debug("Hardware sampleRate=\(recordingFormat.sampleRate, format: .fixed(precision: 2))")
            logger.debug("Hardware channels=\(recordingFormat.channelCount)")
        }

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            guard let fallbackFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) else {
                Task { @MainActor [weak self] in
                    self?.state = .error(.audioSessionFailed)
                }
                throw SpeechRecognitionError.audioSessionFailed
            }
            logger.debug("Installing tap with fallback sampleRate=16000 channels=1")
            return fallbackFormat
        }

        logger.debug("Installing tap with hardware format")
        return recordingFormat
    }

    nonisolated func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else {
            return
        }
        let frameLength = Int(buffer.frameLength)

        // Only process if we have valid audio data
        guard frameLength > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

        // Ensure we don't get NaN or invalid values
        guard !rms.isNaN && !rms.isInfinite && rms >= 0 else { return }

        let normalizedAmplitude = Double(min(log10(1 + rms * 9), 1.0))
        let smoothedAmplitude = smoothAmplitude(normalizedAmplitude)

        Task { @MainActor [weak self] in
            self?.currentAmplitude = smoothedAmplitude
        }
    }

    nonisolated func smoothAmplitude(_ newAmplitude: Double) -> Double {
        amplitudeHistory.append(newAmplitude)
        if amplitudeHistory.count > historySize {
            amplitudeHistory.removeFirst()
        }

        var smoothed = amplitudeHistory[0]
        for index in 1..<amplitudeHistory.count {
            smoothed = smoothed * smoothingFactor + amplitudeHistory[index] * (1 - smoothingFactor)
        }

        return smoothed
    }

    nonisolated func prepareRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()

        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false

        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }

        if #available(iOS 13.0, *) {
            request.taskHint = .dictation
        }

        logger.debug("Recognition request prepared")
        return request
    }

    nonisolated func configureRecognitionTask(with request: SFSpeechAudioBufferRecognitionRequest) {
        logger.debug("Starting recognition task")

        guard let recognizer = speechRecognizer else {
            logger.error("Cannot create recognition task: speechRecognizer is nil")
            Task { @MainActor [weak self] in
                self?.state = .error(.recognizerNotAvailable)
            }
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            guard !self.hasProcessedFinalResult else {
                if VoiceLogging.isVerboseEnabled {
                    if let error {
                        VoiceLogging.recognition.debug("Callback ignored (already processed) error: \(error.localizedDescription, privacy: .public)")
                    } else if let result {
                        VoiceLogging.recognition.debug("Callback ignored (already processed) result final=\(result.isFinal)")
                    } else {
                        VoiceLogging.recognition.debug("Callback ignored (already processed) unknown payload")
                    }
                }
                return
            }

            if let error {
                self.handleRecognitionError(error)
                return
            }

            if let result {
                self.processRecognitionResult(result)
            }
        }
    }

    nonisolated func handleRecognitionError(_ error: Error) {
        logger.error("Speech recognition error: \(error.localizedDescription, privacy: .public)")

        Task { @MainActor [weak self] in
            guard let self else { return }

            if case .listening(let partialText) = self.state,
               !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if VoiceLogging.isVerboseEnabled {
                    logger.debug("Ignoring error due to partial text: \(partialText, privacy: .private)")
                }
                self.hasProcessedFinalResult = true
                self.state = .completed(finalText: partialText)
            } else {
                self.hasProcessedFinalResult = true
                self.state = .error(.recognitionFailed(error.localizedDescription))
            }
        }
    }

    nonisolated func processRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let transcription = result.bestTranscription.formattedString
        let isFinal = result.isFinal

        Task { @MainActor [weak self] in
            guard let self else { return }

            if isFinal {
                if VoiceLogging.isVerboseEnabled {
                    logger.debug("Final result: \(transcription, privacy: .private)")
                }
                self.hasProcessedFinalResult = true
                self.state = .completed(finalText: transcription)
            } else if !self.hasProcessedFinalResult {
                if VoiceLogging.isVerboseEnabled {
                    logger.debug("Partial result: \(transcription, privacy: .private)")
                }
                self.state = .listening(partialText: transcription)
            }
        }
    }
}
