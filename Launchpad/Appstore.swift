// Copyright (c) 2026 @drclcomputers. All rights reserved.
//
// This work is licensed under the terms of the MIT license.
// For a copy, see <https://opensource.org/licenses/MIT>.
//
// Appstore.swift
// Launchpad
//
// Created by Dorneanu Denis on 30/10/2026.
//

import SwiftUI
import Combine

struct AppItem: Identifiable, Hashable {
	let url: URL
	let name: String
	var id: URL { url }
	var path: String { url.path }

	private static let iconCache = NSCache<NSURL, NSImage>()
	var icon: NSImage {
		if let c = Self.iconCache.object(forKey: url as NSURL) { return c }
		let img = NSWorkspace.shared.icon(forFile: url.path)
		Self.iconCache.setObject(img, forKey: url as NSURL)
		return img
	}

	func launch() {
		NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
	}
}

struct Folder: Identifiable, Hashable, Codable {
	var id = UUID()
	var name: String
	var apps: [String]
}

enum Entry: Identifiable, Hashable, Codable {
	case app(String)
	case folder(Folder)

	var id: String {
		switch self {
		case .app(let path): return "app:" + path
		case .folder(let f): return "folder:" + f.id.uuidString
		}
	}
}

enum DropZone { case before, onto, after }

@MainActor
final class AppStore: ObservableObject {
	@Published private(set) var installed: [String: AppItem] = [:]
	@Published private(set) var entries: [Entry] = []
	@Published private(set) var hidden: Set<String> = []

	private var alphabetical: [String] = []
	private var savedEntries: [Entry] = []
	private let defaults = UserDefaults.standard

	init() {
		hidden = Set(load([String].self, key: Keys.hidden) ?? [])
		savedEntries = load([Entry].self, key: Keys.layout) ?? []
		Task {
			let found = await Task.detached(priority: .userInitiated) { Self.scan() }.value
			self.install(found)
		}
	}

	func app(_ path: String) -> AppItem? { installed[path] }

	func folder(_ id: UUID) -> Folder? {
		for case .folder(let f) in entries where f.id == id { return f }
		return nil
	}

	func visibleApps(in folder: Folder) -> [AppItem] {
		folder.apps.compactMap { hidden.contains($0) ? nil : installed[$0] }
	}

	var visibleEntries: [Entry] {
		entries.filter { entry in
			switch entry {
			case .app(let p): return !hidden.contains(p) && installed[p] != nil
			case .folder(let f): return !visibleApps(in: f).isEmpty
			}
		}
	}

	var allVisibleApps: [AppItem] {
		installed.values
			.filter { !hidden.contains($0.path) }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	var hiddenApps: [AppItem] {
		hidden.compactMap { installed[$0] }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	func hide(_ path: String) { hidden.insert(path); save() }
	func unhide(_ path: String) { hidden.remove(path); save() }

	func drop(_ dragID: String, on targetID: String, zone: DropZone) {
		switch zone {
		case .onto where dragID.hasPrefix("app:"): merge(dragID, onto: targetID)
		case .onto, .after: move(dragID, near: targetID, after: true)
		case .before: move(dragID, near: targetID, after: false)
		}
	}

	private func move(_ dragID: String, near targetID: String, after: Bool) {
		guard dragID != targetID, let item = detach(dragID) else { return }
		if let t = entries.firstIndex(where: { $0.id == targetID }) {
			entries.insert(item, at: after ? t + 1 : t)
		} else {
			entries.append(item)
		}
		save()
	}

	private func merge(_ dragID: String, onto targetID: String) {
		guard dragID != targetID, let item = detach(dragID), case .app(let dragged) = item else { return }
		guard let t = entries.firstIndex(where: { $0.id == targetID }) else {
			entries.append(item); save(); return
		}
		switch entries[t] {
		case .app(let other):
			entries[t] = .folder(Folder(name: tr("Folder"), apps: [other, dragged]))
		case .folder(var f):
			f.apps.append(dragged)
			entries[t] = .folder(f)
		}
		save()
	}

	private func detach(_ id: String) -> Entry? {
		if let i = entries.firstIndex(where: { $0.id == id }) {
			return entries.remove(at: i)
		}
		guard id.hasPrefix("app:") else { return nil }
		let path = String(id.dropFirst(4))
		guard let i = folderIndex(containing: path), case .folder(var f) = entries[i] else { return nil }
		f.apps.removeAll { $0 == path }
		switch f.apps.count {
		case 0: entries.remove(at: i)
		case 1: entries[i] = .app(f.apps[0])
		default: entries[i] = .folder(f)
		}
		return .app(path)
	}

	private func folderIndex(containing path: String) -> Int? {
		entries.firstIndex { entry in
			if case .folder(let f) = entry { return f.apps.contains(path) }
			return false
		}
	}

	func removeFromFolder(_ path: String) {
		guard let i = folderIndex(containing: path), case .folder(var f) = entries[i] else { return }
		f.apps.removeAll { $0 == path }
		var replacement: [Entry] = []
		switch f.apps.count {
		case 0: break
		case 1: replacement = [.app(f.apps[0])]
		default: replacement = [.folder(f)]
		}
		entries.replaceSubrange(i...i, with: replacement + [.app(path)])
		save()
	}

	func moveInFolder(_ path: String, onto target: String) {
		guard path != target,
			  let i = folderIndex(containing: path),
			  case .folder(var f) = entries[i],
			  let from = f.apps.firstIndex(of: path),
			  let to = f.apps.firstIndex(of: target) else { return }
		f.apps.remove(at: from)
		f.apps.insert(path, at: to)
		entries[i] = .folder(f)
		save()
	}

	func rename(_ id: UUID, to name: String) {
		guard let i = entries.firstIndex(where: { $0.id == "folder:" + id.uuidString }),
			  case .folder(var f) = entries[i] else { return }
		f.name = name
		entries[i] = .folder(f)
		save()
	}

	func resetLayout() {
		entries = alphabetical.map { Entry.app($0) }
		save()
	}

	private func install(_ found: [AppItem]) {
		installed = Dictionary(found.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
		alphabetical = found.map(\.path)

		var known = Set<String>()
		var result: [Entry] = []
		for entry in savedEntries {
			switch entry {
			case .app(let p):
				if installed[p] != nil, known.insert(p).inserted { result.append(.app(p)) }
			case .folder(var f):
				f.apps = f.apps.filter { installed[$0] != nil && known.insert($0).inserted }
				if f.apps.count > 1 { result.append(.folder(f)) }
				else if let only = f.apps.first { result.append(.app(only)) }
			}
		}
		for p in alphabetical where !known.contains(p) { result.append(.app(p)) }

		entries = result
		save()
	}

	private func save() {
		if let d = try? JSONEncoder().encode(entries) { defaults.set(d, forKey: Keys.layout) }
		if let d = try? JSONEncoder().encode(hidden.sorted()) { defaults.set(d, forKey: Keys.hidden) }
	}

	private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
		guard let d = defaults.data(forKey: key) else { return nil }
		return try? JSONDecoder().decode(type, from: d)
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
					visit(u, depth: depth + 1)   
				}
			}
		}
		roots.forEach { visit($0, depth: 0) }
		return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}
}
