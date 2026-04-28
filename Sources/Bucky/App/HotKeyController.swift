import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class HotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    let configuration: HotKeyConfiguration
    private let hotKeyIdentifier: UInt32
    private let onHotKey: () -> Void

    init(
        configuration: HotKeyConfiguration,
        identifier: UInt32 = 1,
        onHotKey: @escaping () -> Void
    ) throws {
        self.configuration = configuration
        hotKeyIdentifier = identifier
        self.onHotKey = onHotKey
        try install()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func install() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard parameterStatus == noErr,
                      hotKeyID.signature == "Bcky".fourCharCode,
                      hotKeyID.id == controller.hotKeyIdentifier else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    controller.onHotKey()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            throw HotKeyError.installHandler(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: "Bcky".fourCharCode, id: hotKeyIdentifier)
        let registrationStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registrationStatus == noErr else {
            throw HotKeyError.register(registrationStatus)
        }
    }
}
enum HotKeyError: LocalizedError {
    case installHandler(OSStatus)
    case register(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandler(let status):
            return "Could not install hotkey handler. OSStatus \(status)."
        case .register(let status):
            return "Could not register hotkey. OSStatus \(status)."
        }
    }
}
