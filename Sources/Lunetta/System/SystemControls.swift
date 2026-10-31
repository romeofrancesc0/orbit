import AppKit
import ApplicationServices
import AudioToolbox
import AVFoundation
import Carbon.HIToolbox
import Combine
import CoreAudio
import IOBluetooth

// MARK: - Volume

/// Volume dell'uscita predefinita via CoreAudio.
@MainActor
final class VolumeController: ObservableObject {
    @Published private(set) var level: Double = 0
    @Published private(set) var isMuted = false

    init() { refresh() }

    func refresh() {
        guard let device = Self.defaultOutputDevice else { return }
        level = Double(Self.readVolume(device) ?? Float(level))
        isMuted = Self.readMute(device) ?? false
    }

    func change(by delta: Double) {
        refresh()
        set(level: level + delta)
    }

    func set(level newLevel: Double) {
        guard let device = Self.defaultOutputDevice else { return }
        let clamped = min(1, max(0, newLevel))
        Self.writeVolume(device, Float(clamped))
        // Alzare il volume da muto toglie il muto, come fa il sistema.
        if isMuted, clamped > 0 { Self.writeMute(device, false) }
        refresh()
    }

    func toggleMute() {
        guard let device = Self.defaultOutputDevice else { return }
        refresh()
        Self.writeMute(device, !isMuted)
        refresh()
    }

    // MARK: CoreAudio

    private static var defaultOutputDevice: AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func readVolume(_ device: AudioDeviceID) -> Float? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress()
        if AudioObjectHasProperty(device, &address),
           AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
            return value
        }
        // Dispositivi senza volume virtuale: si legge il primo canale.
        address.mSelector = kAudioDevicePropertyVolumeScalar
        address.mElement = 1
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func writeVolume(_ device: AudioDeviceID, _ newValue: Float) {
        var value = newValue
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress()
        if AudioObjectHasProperty(device, &address),
           AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr {
            return
        }
        address.mSelector = kAudioDevicePropertyVolumeScalar
        for channel: UInt32 in [1, 2] {
            address.mElement = channel
            _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        }
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func readMute(_ device: AudioDeviceID) -> Bool? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress()
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static func writeMute(_ device: AudioDeviceID, _ muted: Bool) {
        var value = UInt32(muted ? 1 : 0)
        var address = muteAddress()
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

// MARK: - Luminosità

/// Luminosità dello schermo e della tastiera. Non esiste un'API pubblica: si passa
/// dagli stessi framework privati che usa il sistema, caricati a runtime. Se un
/// giorno sparissero, i controlli si limitano a non fare nulla.
@MainActor
final class BrightnessController {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?
    private let keyboardClient: NSObject?

    private let keyboardID: UInt64 = 1
    private let keyboardGet = NSSelectorFromString("brightnessForKeyboard:")
    private let keyboardSet = NSSelectorFromString("setBrightness:forKeyboard:")

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        getFn = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
        setFn = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }

        _ = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework")?.load()
        keyboardClient = (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }

    var screenLevel: Double? {
        var value: Float = 0
        guard let getFn, getFn(CGMainDisplayID(), &value) == 0 else { return nil }
        return Double(value)
    }

    @discardableResult
    func changeScreen(by delta: Double) -> Double? {
        guard let current = screenLevel, let setFn else { return nil }
        let next = min(1, max(0, current + delta))
        return setFn(CGMainDisplayID(), Float(next)) == 0 ? next : nil
    }

    var keyboardLevel: Double? {
        guard let client = keyboardClient, let method = class_getInstanceMethod(type(of: client), keyboardGet) else { return nil }
        typealias Getter = @convention(c) (NSObject, Selector, UInt64) -> Float
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return Double(getter(client, keyboardGet, keyboardID))
    }

    @discardableResult
    func changeKeyboard(by delta: Double) -> Double? {
        guard let client = keyboardClient,
              let current = keyboardLevel,
              let method = class_getInstanceMethod(type(of: client), keyboardSet)
        else { return nil }
        let next = min(1, max(0, current + delta))
        typealias Setter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        return setter(client, keyboardSet, Float(next), keyboardID).boolValue ? next : nil
    }
}

// MARK: - Tasti multimediali

/// Intercetta i tasti di volume e luminosità per sostituire l'indicatore di sistema
/// con quello nella notch. Richiede il permesso di Accessibilità.
final class MediaKeyTap: @unchecked Sendable {
    enum Key: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
        case keyboardUp = 21, keyboardDown = 22
    }

    /// Riceve il tasto e il moltiplicatore del passo (⌥⇧ per i passi fini).
    var onKey: ((Key, Bool) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.isTrusted else { return false }

        // NSEvent.EventType.systemDefined: CGEventType non ha una costante per questo.
        let mask = CGEventMask(1 << 14)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(info).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }
        guard let created = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tap = created
        source = runLoopSource
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Il sistema spegne le tap lente: basta riaccenderle.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = (ns.data1 & 0xFFFF_0000) >> 16
        let state = (ns.data1 & 0xFF00) >> 8
        guard let key = Key(rawValue: keyCode) else { return Unmanaged.passUnretained(event) }

        // Il rilascio del tasto va assorbito anche lui, o il sistema mostra il suo indicatore.
        if state == 0xA {
            let fine = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)
            onKey?(key, fine)
        }
        return nil
    }
}

// MARK: - Scorciatoie globali

/// Scorciatoie di sistema con le API Carbon: sono ancora l'unico modo che non
/// richiede permessi speciali.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: HotkeyAction] = [:]
    private var handlerInstalled = false
    private var applied: [HotkeyBinding]?

    var perform: ((HotkeyAction) -> Void)?

    func apply(_ bindings: [HotkeyBinding]) {
        guard bindings != applied else { return }
        applied = bindings
        installHandlerIfNeeded()
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()

        for (index, binding) in bindings.enumerated() {
            guard let keyCode = binding.keyCode else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            // 'LUNT'
            let hotKeyID = EventHotKeyID(signature: 0x4C55_4E54, id: id)
            let status = RegisterEventHotKey(keyCode, binding.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = binding.action
            }
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            Task { @MainActor in HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func fire(_ id: UInt32) {
        guard let action = actions[id] else { return }
        perform?(action)
    }

    /// Descrizione leggibile, come "⌃⌥N".
    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName(keyCode)
    }

    /// Converte i modificatori di AppKit in quelli di Carbon.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        // I codici dei tasti funzione non sono in ordine: niente intervalli qui.
        if let function = functionKeys[Int(keyCode)] { return function }
        switch Int(keyCode) {
        case kVK_Space:         return "Spazio"
        case kVK_Return:        return "↩"
        case kVK_Tab:           return "⇥"
        case kVK_Escape:        return "⎋"
        case kVK_Delete:        return "⌫"
        case kVK_LeftArrow:     return "←"
        case kVK_RightArrow:    return "→"
        case kVK_UpArrow:       return "↑"
        case kVK_DownArrow:     return "↓"
        default:
            break
        }
        // La lettera giusta dipende dalla tastiera dell'utente.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]
}

// MARK: - Fotocamera

/// Lo specchio: una sessione di cattura che gira solo mentre lo si guarda.
@MainActor
final class CameraMirror: ObservableObject {
    enum Access: Equatable {
        case undetermined, granted, denied
    }

    @Published private(set) var access: Access = .undetermined
    @Published private(set) var isRunning = false

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "lunetta.camera")
    private var configured = false

    init() { refreshAccess() }

    func refreshAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    access = .granted
        case .notDetermined: access = .undetermined
        default:             access = .denied
        }
    }

    func requestAccess() {
        guard access != .denied else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor in self?.refreshAccess() }
        }
    }

    func start() {
        refreshAccess()
        guard access == .granted, !isRunning else { return }
        isRunning = true
        let session = session
        let needsConfiguration = !configured
        configured = true
        queue.async {
            if needsConfiguration {
                session.beginConfiguration()
                session.sessionPreset = .medium
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
            }
            session.startRunning()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let session = session
        queue.async { session.stopRunning() }
    }
}

// MARK: - Bluetooth

/// Avvisa quando un dispositivo Bluetooth si collega o si scollega.
final class BluetoothMonitor: NSObject {
    var onChange: ((_ name: String, _ symbol: String, _ connected: Bool, _ battery: Int?) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [ObjectIdentifier: IOBluetoothUserNotification] = [:]
    private var startedAt = Date()

    func start() {
        guard connectNotification == nil else { return }
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let identifier = ObjectIdentifier(device)
        if disconnectNotifications[identifier] == nil {
            disconnectNotifications[identifier] = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        }
        // All'avvio il sistema annuncia tutto ciò che è già collegato: non è una novità.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        onChange?(device.name ?? "Dispositivo", Self.symbol(for: device), true, Self.battery(of: device))
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        disconnectNotifications[ObjectIdentifier(device)]?.unregister()
        disconnectNotifications[ObjectIdentifier(device)] = nil
        onChange?(device.name ?? "Dispositivo", Self.symbol(for: device), false, nil)
    }

    private static func battery(of device: IOBluetoothDevice) -> Int? {
        for key in ["batteryPercentSingle", "batteryPercentCombined"] {
            let selector = NSSelectorFromString(key)
            guard device.responds(to: selector),
                  let value = device.value(forKey: key) as? Int, value > 0
            else { continue }
            return value
        }
        return nil
    }

    private static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") || name.contains("headphone") || name.contains("cuffie") { return "headphones" }
        if name.contains("keyboard") || name.contains("tastiera") { return "keyboard" }
        if name.contains("mouse") { return "magicmouse" }
        if name.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if name.contains("speaker") || name.contains("homepod") { return "hifispeaker.fill" }
        // Classi Bluetooth standard: 0x04 audio, 0x05 periferiche.
        switch device.deviceClassMajor {
        case 0x04: return "headphones"
        case 0x05: return "keyboard"
        default:   return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - Tutto schermo

/// Dice se sullo schermo è in primo piano uno spazio a tutto schermo. L'informazione
/// sta solo in un'API privata di Spaces; se mancasse, la notch resta semplicemente visibile.
enum FullscreenDetector {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias SpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let symbols: (ConnectionFn, SpacesFn)? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let connection = dlsym(handle, "_CGSDefaultConnection"),
              let spaces = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        return (unsafeBitCast(connection, to: ConnectionFn.self), unsafeBitCast(spaces, to: SpacesFn.self))
    }()

    static func isFullscreen(displayID: CGDirectDisplayID) -> Bool {
        guard let (connection, copySpaces) = symbols,
              let raw = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]]
        else { return false }

        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        let identifier = uuid.map { CFUUIDCreateString(nil, $0) as String }

        for display in raw {
            let name = display["Display Identifier"] as? String
            // Con "spazi separati" disattivati l'identificativo è il generico "Main".
            guard name == identifier || name == "Main" || raw.count == 1 else { continue }
            let type = (display["Current Space"] as? [String: Any])?["type"] as? Int
            return type == 4
        }
        return false
    }
}

// MARK: - Schermata di blocco

/// Per comparire sopra la schermata di blocco una finestra deve stare in uno spazio
/// dedicato di livello altissimo. Lo gestisce SkyLight, il framework privato del window
/// server: caricato a runtime, e usato solo se l'utente attiva l'opzione.
@MainActor
final class LockScreenSpace {
    static let shared = LockScreenSpace()

    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias CreateFn = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias LevelFn = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowFn = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddFn = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32
    private typealias RemoveFn = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private var connection: Int32 = 0
    private var space: UInt64 = 0
    private var addFn: AddFn?
    private var removeFn: RemoveFn?
    private var windows: Set<Int> = []

    var hasWindows: Bool { !windows.isEmpty }

    private func prepare() -> Bool {
        if space != 0 { return true }
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
              let createSymbol = dlsym(handle, "SLSSpaceCreate"),
              let levelSymbol = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let showSymbol = dlsym(handle, "SLSShowSpaces"),
              let addSymbol = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces"),
              let removeSymbol = dlsym(handle, "SLSRemoveWindowsFromSpaces")
        else { return false }

        connection = unsafeBitCast(connectionSymbol, to: ConnectionFn.self)()
        space = unsafeBitCast(createSymbol, to: CreateFn.self)(connection, 1, nil)
        guard space != 0 else { return false }
        // 400 è sopra la schermata di blocco, che sta a 300.
        _ = unsafeBitCast(levelSymbol, to: LevelFn.self)(connection, space, 400)
        _ = unsafeBitCast(showSymbol, to: ShowFn.self)(connection, [space] as CFArray)
        addFn = unsafeBitCast(addSymbol, to: AddFn.self)
        removeFn = unsafeBitCast(removeSymbol, to: RemoveFn.self)
        return true
    }

    func add(_ window: NSWindow) {
        guard prepare() else { return }
        window.canBecomeVisibleWithoutLogin = true
        _ = addFn?(connection, space, [window.windowNumber] as CFArray, 7)
        windows.insert(window.windowNumber)
        window.orderFrontRegardless()
    }

    func remove(_ window: NSWindow) {
        guard windows.remove(window.windowNumber) != nil else { return }
        _ = removeFn?(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
