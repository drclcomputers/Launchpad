// Copyright (c) 2026 @drclcomputers. All rights reserved.
//
// This work is licensed under the terms of the MIT license.
// For a copy, see <https://opensource.org/licenses/MIT>.
//
// Launchpadapp.swift
// Launchpad
//
// Created by Dorneanu Denis on 30/10/2026.
//

import SwiftUI

@main
struct LaunchpadApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
	var body: some Scene { Settings { EmptyView() } }
}

final class OverlayWindow: NSWindow {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	static weak var shared: AppDelegate?

	var window: OverlayWindow?
	private var launchedAtLogin = false
	private var statusItem: NSStatusItem?
	private var appliedSignature = ""

	override init() {
		super.init()
		Self.shared = self
	}

	func applicationWillFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [
			Keys.menuBar: true,
			Keys.hotkeyEnabled: true,
			Keys.hotkeyCode: Defaults.hotkeyCode,
			Keys.hotkeyMods: Defaults.hotkeyMods,
			Keys.hotkeyLabel: Defaults.hotkeyLabel
		])
		launchedAtLogin = Self.wasLaunchedAsLoginItem()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.accessory)

		HotKeyManager.shared.onTrigger = { [weak self] in self?.toggleWindow() }
		PinchDetector.shared.onPinch = { Task { @MainActor in AppDelegate.shared?.showWindow() } }
		PinchDetector.shared.onSpread = { Task { @MainActor in AppDelegate.shared?.closeWindow() } }
		applySettings()

		NotificationCenter.default.addObserver(
			forName: UserDefaults.didChangeNotification,
			object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.applySettings() }
		}

		NotificationCenter.default.addObserver(
			forName: NSApplication.didBecomeActiveNotification,
			object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.showWindow() }
		}

		if !launchedAtLogin { showWindow() }
	}

	func showWindow() {
		guard let screen = screenUnderCursor() else { return }
		if let w = window, w.isVisible { return }

		let w: OverlayWindow
		if let existing = window {
			w = existing
		} else {
			w = OverlayWindow(contentRect: screen.frame,
							  styleMask: [.borderless],
							  backing: .buffered, defer: false)
			w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
			w.backgroundColor = .clear
			w.isOpaque = false
			w.hasShadow = false
			w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
			window = w
		}

		w.setFrame(screen.frame, display: true)
		w.contentView = NSHostingView(rootView: RootView())
		NSApp.unhide(nil)
		w.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	private func screenUnderCursor() -> NSScreen? {
		let mouse = NSEvent.mouseLocation
		return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
	}

	func hideWindow() {
		window?.orderOut(nil)
		window?.contentView = nil
		if NSApp.isActive { NSApp.hide(nil) }
	}

	func closeWindow() {
		if window?.isVisible == true {
			NotificationCenter.default.post(name: .dismissLaunchpad, object: nil)
		}
	}

	func toggleWindow() {
		if window?.isVisible == true {
			NotificationCenter.default.post(name: .dismissLaunchpad, object: nil)
		} else {
			showWindow()
		}
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		showWindow()
		return true
	}

	private func applySettings() {
		let d = UserDefaults.standard
		let menuBar = d.bool(forKey: Keys.menuBar)
		let hotkeyOn = d.bool(forKey: Keys.hotkeyEnabled)
		let code = d.integer(forKey: Keys.hotkeyCode)
		let mods = d.integer(forKey: Keys.hotkeyMods)
		let pinch = d.bool(forKey: Keys.pinch)
		let language = d.string(forKey: Keys.language) ?? ""

		let signature = "\(menuBar)|\(hotkeyOn)|\(code)|\(mods)|\(pinch)|\(language)"
		guard signature != appliedSignature else { return }
		appliedSignature = signature

		if hotkeyOn {
			HotKeyManager.shared.register(keyCode: UInt32(code), modifiers: UInt32(mods))
		} else {
			HotKeyManager.shared.unregister()
		}

		if menuBar { installStatusItem() } else { removeStatusItem() }

		if pinch { PinchDetector.shared.start() } else { PinchDetector.shared.stop() }
	}

	private func installStatusItem() {
		removeStatusItem()
		let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill",
									 accessibilityDescription: "Launchpad")

		let menu = NSMenu()
		let open = NSMenuItem(title: tr("Open Launchpad"), action: #selector(openFromMenu), keyEquivalent: "")
		open.target = self
		menu.addItem(open)
		menu.addItem(.separator())
		let quit = NSMenuItem(title: tr("Quit Launchpad"), action: #selector(quitFromMenu), keyEquivalent: "q")
		quit.target = self
		menu.addItem(quit)

		item.menu = menu
		statusItem = item
	}

	private func removeStatusItem() {
		if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
		statusItem = nil
	}

	@objc private func openFromMenu() { showWindow() }

	@objc private func quitFromMenu() { NSApp.terminate(nil) }

	private static func wasLaunchedAsLoginItem() -> Bool {
		guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
		return event.eventID == AEEventID(kAEOpenApplication) &&
			event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
				== AEKeyword(keyAELaunchedAsLogInItem)
	}
}
