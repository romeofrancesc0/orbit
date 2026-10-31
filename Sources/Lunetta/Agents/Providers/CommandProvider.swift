import Foundation

/// Provider generico: esegue un comando e legge le sessioni dal suo stdout JSON.
///
/// È il punto di aggancio per qualunque altro agent — basta uno script che stampi
/// un array di sessioni nello schema documentato nel README.
actor CommandProvider: SessionProvider {
    nonisolated let id: String
    nonisolated let displayName: String
    nonisolated let accentHex: String?

    private let command: String
    private let args: [String]?
    private let workingDirectory: URL?
    private let timeout: TimeInterval = 8

    private enum RunOutcome: Sendable {
        case success(Data)
        case failure(String)
    }

    init(config: ProviderConfig) {
        id = config.id
        displayName = config.name ?? config.id
        accentHex = config.accent
        command = config.command ?? ""
        args = config.args
        workingDirectory = config.path.map(AppPaths.expand)
    }

    func fetch(config: AgentsConfig) async -> ProviderResult {
        guard !command.isEmpty else {
            return ProviderResult(error: "nessun comando configurato")
        }

        let outcome = await run()
        switch outcome {
        case .failure(let message):
            return ProviderResult(error: message)
        case .success(let data):
            guard !data.isEmpty else { return ProviderResult() }
            do {
                let payloads = try SessionPayload.decodeList(from: data)
                let sessions = payloads.enumerated().map { index, payload in
                    payload.session(
                        providerID: id,
                        providerName: displayName,
                        accentHex: accentHex,
                        fallbackID: "\(index)",
                        config: config
                    )
                }
                return ProviderResult(sessions: sessions)
            } catch {
                return ProviderResult(error: "JSON non valido")
            }
        }
    }

    private func run() async -> RunOutcome {
        let command = self.command
        let args = self.args
        let workingDirectory = self.workingDirectory
        let timeout = self.timeout

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                if let args {
                    // Eseguibile esplicito: `env` risolve anche i nomi non assoluti nel PATH.
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = [command] + args
                } else {
                    // Riga di comando completa: la interpreta la shell.
                    process.executableURL = URL(fileURLWithPath: "/bin/sh")
                    process.arguments = ["-lc", command]
                }
                if let workingDirectory { process.currentDirectoryURL = workingDirectory }

                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(error.localizedDescription))
                    return
                }

                let watchdog = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                guard process.terminationStatus == 0 else {
                    let message = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: .failure(
                        message.isEmpty ? "uscita con codice \(process.terminationStatus)" : String(message.prefix(140))
                    ))
                    return
                }
                continuation.resume(returning: .success(data))
            }
        }
    }
}
