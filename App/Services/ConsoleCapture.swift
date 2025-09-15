import Foundation
import Combine

@MainActor
final class ConsoleCapture: ObservableObject {
    static let shared = ConsoleCapture()

    @Published private(set) var lines: [String] = []
    private var partialBuffer = Data()
    private let maxLines = 5000

    private var pipe: Pipe?
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let pipe = Pipe()
        self.pipe = pipe

        // Save originals
        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)

        // Redirect stdout and stderr to pipe writer
        let writerFD = pipe.fileHandleForWriting.fileDescriptor
        fflush(stdout)
        fflush(stderr)
        dup2(writerFD, STDOUT_FILENO)
        dup2(writerFD, STDERR_FILENO)

        // Read from pipe and append lines
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            Task { @MainActor in
                self.partialBuffer.append(data)
                self.flushLines()
            }
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
        // Restore originals
        if originalStdout >= 0 { dup2(originalStdout, STDOUT_FILENO); close(originalStdout) }
        if originalStderr >= 0 { dup2(originalStderr, STDERR_FILENO); close(originalStderr) }
    }

    func clear() {
        lines.removeAll(keepingCapacity: true)
    }

    private func flushLines() {
        // Split on newlines, keep last partial
        while let range = partialBuffer.firstRange(of: Data([0x0A])) { // \n
            let lineData = partialBuffer.subdata(in: partialBuffer.startIndex..<range.lowerBound)
            partialBuffer.removeSubrange(partialBuffer.startIndex...range.lowerBound)
            if let line = String(data: lineData, encoding: .utf8) {
                appendLine(line)
            } else if !lineData.isEmpty {
                appendLine("<binary> \(lineData.count) bytes")
            }
        }
    }

    private func appendLine(_ line: String) {
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}

