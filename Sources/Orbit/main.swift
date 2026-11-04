import AppKit

// Orbit vive nella notch: nessuna icona nel Dock, nessuna finestra principale.
// Il codice top-level gira già sul main thread: lo dichiariamo al compilatore.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let arguments = CommandLine.arguments

    if arguments.contains("--selftest") {
        Diagnostics.selfTest()
        exit(0)
    }

    if arguments.contains("--probe-controls") {
        Diagnostics.probeControls()
        exit(0)
    }

    // Modalità diagnostica: stampa ciò che vedono i provider e termina.
    if arguments.contains("--dump") {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await Diagnostics.dump()
            done.signal()
        }
        done.wait()
        exit(0)
    }

    // L'installazione attiva l'avvio al login una volta sola, come faceva già AgentBar.
    if arguments.contains("--enable-login-item") {
        print(LoginItem.set(true) ? tr("avvio al login attivo") : tr("avvio al login non disponibile"))
        exit(0)
    }

    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
