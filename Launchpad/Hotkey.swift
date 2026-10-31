// Copyright (c) 2026 @drclcomputers. All rights reserved.
//
// This work is licensed under the terms of the MIT license.
// For a copy, see <https://opensource.org/licenses/MIT>.
//
// HotKey.swift
// Launchpad
//
//  Created by Dorneanu Denis on 31/10/2026.
//

import SwiftUI
import Carbon.HIToolbox

extension Notification.Name {
	static let dismissLaunchpad = Notification.Name("dismissLaunchpad")
}

enum ShortcutRecording {
	static var isActive = false
}

final class HotKeyManager {
	static let shared = HotKeyManager()

	var onTrigger: () -> Void = {}

	private var ref: EventHotKeyRef?
	private var handler: EventHandlerRef?
	private var code: UInt32 = 0
	private var mods: UInt32 = 0
	private var wanted = false

	func register(keyCode: UInt32, modifiers: UInt32) {
		code = keyCode
		mods = modifiers
		wanted = true
		install()
	}

	func unregister() {
		wanted = false
		remove()
	}

	func suspend() { remove() }

	func resume() { if wanted { install() } }

	private func install() {
		remove()
		installHandlerIfNeeded()
		let id = EventHotKeyID(signature: OSType(0x4C504144), id: 1)
		RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &ref)
	}

	private func remove() {
		if let ref { UnregisterEventHotKey(ref) }
		ref = nil
	}

	private func installHandlerIfNeeded() {
		guard handler == nil else { return }
		var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
								 eventKind: UInt32(kEventHotKeyPressed))
		InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
			Task { @MainActor in HotKeyManager.shared.onTrigger() }
			return noErr
		}, 1, &spec, nil, &handler)
	}
}

func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
	var m = 0
	if flags.contains(.command) { m |= cmdKey }
	if flags.contains(.shift) { m |= shiftKey }
	if flags.contains(.option) { m |= optionKey }
	if flags.contains(.control) { m |= controlKey }
	return m
}

func shortcutDescription(mods: Int, label: String) -> String {
	var s = ""
	if mods & controlKey != 0 { s += "⌃" }
	if mods & optionKey != 0 { s += "⌥" }
	if mods & shiftKey != 0 { s += "⇧" }
	if mods & cmdKey != 0 { s += "⌘" }
	return s + label
}

private func keyLabel(for event: NSEvent) -> String {
	switch Int(event.keyCode) {
	case kVK_Space: return "Space"
	case kVK_Return: return "↩"
	case kVK_Tab: return "⇥"
	case kVK_LeftArrow: return "←"
	case kVK_RightArrow: return "→"
	case kVK_UpArrow: return "↑"
	case kVK_DownArrow: return "↓"
	default: break
	}
	let s = (event.charactersIgnoringModifiers ?? "").uppercased()
	let isFunctionKey = s.unicodeScalars.first.map { (0xF700...0xF8FF).contains($0.value) } ?? false
	return s.isEmpty || isFunctionKey ? "Key \(event.keyCode)" : s
}

struct ShortcutField: View {
	@AppStorage(Keys.hotkeyCode) private var code = Defaults.hotkeyCode
	@AppStorage(Keys.hotkeyMods) private var mods = Defaults.hotkeyMods
	@AppStorage(Keys.hotkeyLabel) private var label = Defaults.hotkeyLabel

	@State private var recording = false
	@State private var monitor: Any?

	var body: some View {
		Button {
			if recording { stop() } else { start() }
		} label: {
			if recording {
				Text("Press keys…")
			} else {
				Text(verbatim: shortcutDescription(mods: mods, label: label))
			}
		}
		.buttonStyle(.bordered)
		.onDisappear { stop() }
	}

	private func start() {
		recording = true
		ShortcutRecording.isActive = true
		HotKeyManager.shared.suspend()

		monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
			if event.keyCode == 53 {
				stop()
				return nil
			}
			let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
			guard !flags.intersection([.command, .option, .control]).isEmpty else {
				NSSound.beep()
				return nil
			}
			code = Int(event.keyCode)
			mods = carbonModifiers(flags)
			label = keyLabel(for: event)
			stop()
			return nil
		}
	}

	private func stop() {
		if let monitor { NSEvent.removeMonitor(monitor) }
		monitor = nil
		guard recording else { return }
		recording = false
		ShortcutRecording.isActive = false
		HotKeyManager.shared.resume()
	}
}
