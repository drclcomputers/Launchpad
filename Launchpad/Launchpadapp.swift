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

	override init() {
		super.init()
		Self.shared = self
	}

	func applicationWillFinishLaunching(_ notification: Notification) {
		launchedAtLogin = Self.wasLaunchedAsLoginItem()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.accessory)

		NotificationCenter.default.addObserver(
			forName: NSApplication.didBecomeActiveNotification,
			object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.showWindow() }
		}

		if !launchedAtLogin { showWindow() }
	}

	func showWindow() {
		guard let screen = NSScreen.main else { return }
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

	func hideWindow() {
		window?.orderOut(nil)
		window?.contentView = nil
		if NSApp.isActive { NSApp.hide(nil) }   
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		showWindow()
		return true
	}

	private static func wasLaunchedAsLoginItem() -> Bool {
		guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
		return event.eventID == AEEventID(kAEOpenApplication) &&
			event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
				== AEKeyword(keyAELaunchedAsLogInItem)
	}
}
