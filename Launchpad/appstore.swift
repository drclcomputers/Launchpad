//
//  appstore.swift
//  Launchpad
//
//  Created by Dorneanu Denis on 30/10/2026.
//

import SwiftUI
import Combine

struct AppItem: Identifiable, Hashable {
	let url: URL
	let name: String
	var id: URL { url }

	private static let iconCache = NSCache<NSURL, NSImage>()
	var icon: NSImage {
		if let c = Self.iconCache.object(forKey: url as NSURL) { return c }
		let img = NSWorkspace.shared.icon(forFile: url.path)
		Self.iconCache.setObject(img, forKey: url as NSURL)
		return img
	}

	func launch() {
		NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in
			DispatchQueue.main.async { NSApp.terminate(nil) }
		}
	}
}

@MainActor
final class AppStore: ObservableObject {
	@Published var apps: [AppItem] = []

	init() {
		Task {
			let found = await Task.detached(priority: .userInitiated) { Self.scan() }.value
			self.apps = found
		}
	}

	nonisolated private static func scan() -> [AppItem] {
		let fm = FileManager.default
		let roots = [
			URL(fileURLWithPath: "/Applications"),
			URL(fileURLWithPath: "/System/Applications"),
			fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
		]
		var result: [AppItem] = []
		var seen = Set<String>()

		func visit(_ dir: URL, depth: Int) {
			guard let items = try? fm.contentsOfDirectory(
				at: dir, includingPropertiesForKeys: [.isDirectoryKey],
				options: [.skipsHiddenFiles]) else { return }
			for u in items {
				if u.pathExtension == "app" {
					let name = fm.displayName(atPath: u.path)
						.replacingOccurrences(of: ".app", with: "")
					if seen.insert(name).inserted {
						result.append(AppItem(url: u, name: name))
					}
				} else if depth < 1,
						  (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
					visit(u, depth: depth + 1)   // ex: /Applications/Utilities
				}
			}
		}
		roots.forEach { visit($0, depth: 0) }
		return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}
}
