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
	var window: OverlayWindow?

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.accessory)
		showWindow()
	}

	func showWindow() {
		if let w = window {
			w.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		guard let screen = NSScreen.main else { return }
			
		let w = OverlayWindow(contentRect: screen.frame,
							styleMask: [.borderless],
							backing: .buffered, defer: false)
			
		w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
		w.backgroundColor = .clear
		w.isOpaque = false
		w.hasShadow = false
		w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		w.contentView = NSHostingView(rootView: LaunchpadView())
		w.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
			
		window = w
	}

	func hideWindow() {
		window?.orderOut(nil)
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		showWindow()
		return true
	}
}
