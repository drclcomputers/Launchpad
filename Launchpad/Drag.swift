// Copyright (c) 2026 @drclcomputers. All rights reserved.
//
// This work is licensed under the terms of the MIT license.
// For a copy, see <https://opensource.org/licenses/MIT>.
//
// Drag.swift
// Launchpad
//
// Created by Dorneanu Denis on 30/10/2026.
//

import SwiftUI
import Combine

let launchpadSpace = "launchpad"

struct TileFramesKey: PreferenceKey {
	static let defaultValue: [String: CGRect] = [:]
	static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
		value.merge(nextValue()) { $1 }
	}
}

struct DropTarget: Equatable {
	let id: String
	let zone: DropZone
}

@MainActor
final class DragPointer: ObservableObject {
	@Published var location: CGPoint = .zero
}

@MainActor
final class DragCoordinator: ObservableObject {
	enum Context { case grid, folder }
	enum Outcome { case none, removedFromFolder }

	@Published private(set) var draggingID: String?
	@Published private(set) var target: DropTarget?
	@Published private(set) var edge = 0

	let pointer = DragPointer()
	var frames: [String: CGRect] = [:]
	var viewWidth: CGFloat = 1440
	private(set) var iconSize: CGFloat = 96

	private var context: Context = .grid
	private var dragKey = ""
	private var suppressTapUntil = Date.distantPast
	private weak var store: AppStore?

	var suppressTap: Bool { draggingID != nil || Date() < suppressTapUntil }

	func update(id: String, frameKey: String, context: Context,
				iconSize: CGFloat, location: CGPoint, store: AppStore) {
		if draggingID == nil {
			self.context = context
			self.dragKey = frameKey
			self.iconSize = iconSize
			self.store = store
			draggingID = id
		}
		pointer.location = location

		let t = hitTest(location)
		if t != target { target = t }

		let e = self.context == .grid
			? (location.x < 80 ? -1 : (location.x > viewWidth - 80 ? 1 : 0))
			: 0
		if e != edge { edge = e }
	}

	@discardableResult
	func end() -> Outcome {
		guard let id = draggingID else { return .none }
		let t = target
		let loc = pointer.location
		var outcome = Outcome.none

		if let store {
			switch context {
			case .grid:
				if let t {
					animated {
						store.drop(id, on: t.id, zone: t.zone)
					}
				}
			case .folder:
				let path = String(id.dropFirst(4))
				if let panel = frames["panel"], !panel.contains(loc) {
					store.removeFromFolder(path)
					outcome = .removedFromFolder
				} else if let t, t.id.hasPrefix("f:") {
					animated {
						store.moveInFolder(path, onto: String(t.id.dropFirst(2)))
					}
				}
			}
		}

		draggingID = nil
		target = nil
		edge = 0
		suppressTapUntil = Date().addingTimeInterval(0.25)
		return outcome
	}

	private func hitTest(_ p: CGPoint) -> DropTarget? {
		for (key, rect) in frames where rect.contains(p) {
			if key == dragKey || key == "panel" { continue }
			switch context {
			case .grid:   if key.hasPrefix("f:") { continue }
			case .folder: if !key.hasPrefix("f:") { continue }
			}
			let rel = (p.x - rect.minX) / max(rect.width, 1)
			let zone: DropZone = context == .folder ? .onto
				: (rel < 0.25 ? .before : (rel > 0.75 ? .after : .onto))
			return DropTarget(id: key, zone: zone)
		}
		return nil
	}
}

struct DragSource: ViewModifier {
	let id: String
	let frameKey: String
	let context: DragCoordinator.Context
	let iconSize: CGFloat
	let enabled: Bool
	var onMovedOut: () -> Void = {}

	@EnvironmentObject private var drag: DragCoordinator
	@EnvironmentObject private var store: AppStore

	func body(content: Content) -> some View {
		content
			.opacity(drag.draggingID == id ? 0.25 : 1)
			.overlay {
				DropIndicator(zone: drag.target?.id == frameKey ? drag.target?.zone : nil,
							  height: iconSize)
			}
			.background {
				GeometryReader { g in
					Color.clear.preference(
						key: TileFramesKey.self,
						value: [frameKey: g.frame(in: .named(launchpadSpace))])
				}
			}
			.simultaneousGesture(
				DragGesture(minimumDistance: 8, coordinateSpace: .named(launchpadSpace))
					.onChanged {
						drag.update(id: id, frameKey: frameKey, context: context,
									iconSize: iconSize, location: $0.location, store: store)
					}
					.onEnded { _ in
						if drag.end() == .removedFromFolder { onMovedOut() }
					},
				including: enabled ? .all : .subviews
			)
	}
}

struct DropIndicator: View {
	let zone: DropZone?
	let height: CGFloat

	var body: some View {
		Color.clear
			.overlay {
				if zone == .onto {
					RoundedRectangle(cornerRadius: 22, style: .continuous)
						.fill(.white.opacity(0.16))
				}
			}
			.overlay(alignment: .leading) { if zone == .before { bar } }
			.overlay(alignment: .trailing) { if zone == .after { bar } }
			.allowsHitTesting(false)
	}

	private var bar: some View {
		Capsule().fill(.white.opacity(0.9)).frame(width: 4, height: height)
	}
}

struct DragPreview: View {
	@ObservedObject var pointer: DragPointer
	@EnvironmentObject private var drag: DragCoordinator
	@EnvironmentObject private var store: AppStore

	var body: some View {
		if let id = drag.draggingID {
			preview(id)
				.scaleEffect(1.1)
				.shadow(color: .black.opacity(0.35), radius: 12, y: 6)
				.position(pointer.location)
				.allowsHitTesting(false)
		}
	}

	@ViewBuilder private func preview(_ id: String) -> some View {
		if id.hasPrefix("app:"), let app = store.app(String(id.dropFirst(4))) {
			Image(nsImage: app.icon)
				.resizable()
				.interpolation(.high)
				.frame(width: drag.iconSize, height: drag.iconSize)
		} else if id.hasPrefix("folder:"),
				  let uuid = UUID(uuidString: String(id.dropFirst(7))),
				  let folder = store.folder(uuid) {
			FolderIcon(apps: Array(store.visibleApps(in: folder).prefix(9)), size: drag.iconSize)
		}
	}
}

struct EdgeFlipper: View {
	let go: (Int) -> Void
	@EnvironmentObject private var drag: DragCoordinator

	var body: some View {
		Color.clear
			.allowsHitTesting(false)
			.task(id: drag.edge) {
				let dir = drag.edge
				guard dir != 0 else { return }
				while !Task.isCancelled {
					do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
					go(dir)
				}
			}
	}
}
