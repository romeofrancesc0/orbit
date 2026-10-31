import AppKit

// AgentBar vive solo nella barra di stato: nessuna icona nel Dock, nessuna finestra principale.
// Il codice top-level gira già sul main thread: lo dichiariamo al compilatore.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    // Modalità di sviluppo: rende i pannelli in PNG e termina.
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--render") {
        let destination = index + 1 < arguments.count ? arguments[index + 1] : "."
        PreviewRenderer.run(outputDirectory: destination)
        exit(0)
    }

    if arguments.contains("--selftest") {
        Diagnostics.selfTest()
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

    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
