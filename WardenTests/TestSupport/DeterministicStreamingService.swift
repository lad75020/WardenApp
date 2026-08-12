import Foundation

/// Credential-free stream fixture. It has no transport, endpoint, or provider dependency.
actor DeterministicStreamingService {
    enum Terminal: Error, Sendable, Equatable {
        case success
        case failure
        case cancelled
    }

    private let chunks: [String]
    private let delay: Duration
    private let terminal: Terminal

    init(chunks: [String], delay: Duration = .zero, terminal: Terminal = .success) {
        self.chunks = chunks
        self.delay = delay
        self.terminal = terminal
    }

    func run(onChunk: @escaping @Sendable (String) async -> Void) async throws {
        for chunk in chunks {
            try Task.checkCancellation()
            if delay != .zero { try await Task.sleep(for: delay) }
            try Task.checkCancellation()
            await onChunk(chunk)
        }
        switch terminal {
        case .success: return
        case .failure: throw FixtureError.controlledFailure
        case .cancelled: throw CancellationError()
        }
    }

    enum FixtureError: Error { case controlledFailure }
}
