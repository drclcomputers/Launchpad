//
//  launchpadapp.swift
//  Launchpad
//
//  Created by Dorneanu Denis on 30/10/2026.
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
		guard let screen = NSScreen.main else { return }
		let w = OverlayWindow(contentRect: screen.frame,
							  styleMask: [.borderless],
							  backing: .buffered, defer: false)
		w.level = .popUpMenu
		w.backgroundColor = .clear
		w.isOpaque = false
		w.hasShadow = false
		w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
		w.contentView = NSHostingView(rootView: LaunchpadView())
		w.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		NSApp.presentationOptions = [.hideDock, .hideMenuBar]
		window = w
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
