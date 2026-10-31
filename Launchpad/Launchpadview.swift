// Copyright (c) 2026 @drclcomputers. All rights reserved.
//
// This work is licensed under the terms of the MIT license.
// For a copy, see <https://opensource.org/licenses/MIT>.
//
// Launchpadview.swift
// Launchpad
//
// Created by Dorneanu Denis on 30/10/2026.
//

import SwiftUI

private struct DismissKey: EnvironmentKey {
	static let defaultValue: () -> Void = { NSApp.terminate(nil) }
}
extension EnvironmentValues {
	var dismissLaunchpad: () -> Void {
		get { self[DismissKey.self] }
		set { self[DismissKey.self] = newValue }
	}
}

struct VisualEffect: NSViewRepresentable {
	func makeNSView(context: Context) -> NSVisualEffectView {
		let v = NSVisualEffectView()
		v.material = .hudWindow
		v.blendingMode = .behindWindow
		v.state = .active
		return v
	}
	func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct LaunchpadView: View {
	@StateObject private var store = AppStore()
	@State private var drag = DragCoordinator()
	@State private var query = ""
	@State private var page = 0
	@State private var scroll = ScrollState()
	@State private var monitors: [Any] = []
	@State private var appeared = false
	@State private var showSettings = false
	@State private var openFolderID: UUID?
	@State private var selectedID: String?

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	@AppStorage(Keys.columns) private var columns = Defaults.columns
	@AppStorage(Keys.rows) private var rows = Defaults.rows

	private var perPage: Int { max(columns * rows, 1) }

	private var gridEntries: [Entry] {
		if query.isEmpty { return store.visibleEntries }
		return store.allVisibleApps
			.filter { $0.name.localizedCaseInsensitiveContains(query) }
			.map { Entry.app($0.path) }
	}
	private var pages: [[Entry]] {
		let all = gridEntries
		return stride(from: 0, to: all.count, by: perPage).map {
			Array(all[$0..<min($0 + perPage, all.count)])
		}
	}

	private var appearAnimation: Animation {
		reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.82)
	}

	private var dismissAnimation: Animation {
		reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.90)
	}

	private var openFolder: Folder? {
		guard let id = openFolderID,
			  let f = store.folder(id),
			  !store.visibleApps(in: f).isEmpty else { return nil }
		return f
	}

	var body: some View {
		ZStack {
			Group {
				if #available(macOS 26.0, *) {
					Rectangle()
						.glassEffect(.clear.interactive(), in: .rect)
						.ignoresSafeArea()
						.padding(.top, -10)
						.padding(.bottom, -10)

					Color.black.opacity(0.35)
						.ignoresSafeArea()
				} else {
					VisualEffect()
						.ignoresSafeArea()
					Color.black.opacity(0.25)
						.ignoresSafeArea()
				}
			}
			.contentShape(Rectangle())
			.onTapGesture { dismiss() }

			VStack(spacing: 24) {
				topBar
				pager
				dots
			}
			.padding(.vertical, 40)
			.scaleEffect(appeared || reduceMotion ? 1 : 1.12)

			if let folder = openFolder {
				FolderOverlay(folder: folder, selectedID: selectedID) { openFolderID = nil }
					.transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
			}

			if showSettings {
				SettingsPanel { showSettings = false }
					.transition(.opacity)
			}

			DragPreview(pointer: drag.pointer)
			EdgeFlipper { go($0) }
		}
		.coordinateSpace(.named(launchpadSpace))
		.onPreferenceChange(TileFramesKey.self) { frames in
			MainActor.assumeIsolated { drag.frames = frames }
		}
		.animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: openFolderID)
		.animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: showSettings)
		.opacity(appeared ? 1 : 0)
		.environmentObject(store)
		.environmentObject(drag)
		.environment(\.dismissLaunchpad, { dismiss() })
		.onChange(of: query) {
			page = 0
			selectedID = query.isEmpty ? nil : gridEntries.first?.id
		}
		.onChange(of: openFolderID) { selectedID = nil }
		.onChange(of: pages.count) { page = min(page, max(pages.count - 1, 0)) }
		.onAppear {
			installMonitors()
			withAnimation(appearAnimation) {
				appeared = true
			}
		}
		.onDisappear { removeMonitors() }
		.onReceive(NotificationCenter.default.publisher(for: .dismissLaunchpad)) { _ in dismiss() }
	}

	private var topBar: some View {
		ZStack {
			searchBar
			HStack {
				Spacer()
				settingsButton
			}
			.padding(.trailing, 48)
		}
	}

	private var searchBar: some View {
		HStack(spacing: 10) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 17, weight: .medium))
				.foregroundStyle(.white.opacity(0.7))

			NativeSearchField(text: $query) { activateSelected() }
				.font(.system(size: 18))
				.frame(height: 24)
		}
		.padding(.horizontal, 20)
		.padding(.vertical, 12)
		.frame(width: 400)
		.background {
			if #available(macOS 26.0, *) {
				Capsule()
					.glassEffect(.regular.interactive(), in: .capsule)
			} else {
				Capsule()
					.fill(.white.opacity(0.15))
			}
		}
	}

	private var settingsButton: some View {
		Button { showSettings = true } label: {
			Image(systemName: "gearshape.fill")
				.font(.system(size: 16, weight: .medium))
				.foregroundStyle(.white.opacity(0.85))
				.frame(width: 44, height: 44)
				.glassCard(Circle())
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.help("Settings")
	}

	private var pager: some View {
		GeometryReader { geo in
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 0) {
					ForEach(pages.indices, id: \.self) { i in
						PageGrid(entries: pages[i],
								 columns: columns,
								 rows: rows,
								 size: geo.size,
								 reorderable: query.isEmpty,
								 selectedID: selectedID,
								 onOpenFolder: { openFolderID = $0 })
							.frame(width: geo.size.width, height: geo.size.height, alignment: .top)
							.id(i)
					}
				}
				.scrollTargetLayout()
			}
			.scrollTargetBehavior(.paging)
			.scrollPosition(id: Binding(
				get: { page },
				set: { page = $0 ?? 0 }
			))
			.contentShape(Rectangle())
			.onTapGesture { }
			.onChange(of: geo.size.width, initial: true) { drag.viewWidth = geo.size.width }
		}
	}

	private var dots: some View {
		HStack(spacing: 10) {
			ForEach(pages.indices, id: \.self) { i in
				Circle()
					.fill(.white.opacity(i == page ? 0.95 : 0.35))
					.frame(width: 8, height: 8)
					.onTapGesture {
						animated(.spring(response: 0.4, dampingFraction: 0.85)) {
							page = i
						}
					}
			}
		}
		.frame(height: 12)
	}

	private func activateSelected() {
		if let folder = openFolder {
			let match = store.visibleApps(in: folder).first { "app:" + $0.path == selectedID }
			if let match {
				match.launch()
				dismiss()
			}
			return
		}

		let selected = gridEntries.first { $0.id == selectedID }
		guard let entry = selected ?? (query.isEmpty ? nil : gridEntries.first) else { return }

		switch entry {
		case .app(let path):
			store.app(path)?.launch()
			dismiss()
		case .folder(let folder):
			openFolderID = folder.id
		}
	}

	private func moveSelection(_ key: UInt16) {
		if let folder = openFolder {
			let ids = store.visibleApps(in: folder).map { "app:" + $0.path }
			guard !ids.isEmpty else { return }
			let current = selectedID.flatMap { ids.firstIndex(of: $0) }
			let next = current.map {
				neighbor(of: $0, key: key, columns: max(1, min(ids.count, 4)),
						 horizontal: 0..<ids.count, vertical: 0..<ids.count)
			} ?? 0
			selectedID = ids[next]
			return
		}

		let all = gridEntries
		let pageStart = page * perPage
		guard pageStart < all.count else { return }
		let pageEnd = min(pageStart + perPage, all.count)

		let current = selectedID
			.flatMap { id in all.firstIndex { $0.id == id } }
			.flatMap { (pageStart..<pageEnd).contains($0) ? $0 : nil }
		let next = current.map {
			neighbor(of: $0, key: key, columns: max(columns, 1),
					 horizontal: 0..<all.count, vertical: pageStart..<pageEnd)
		} ?? pageStart

		selectedID = all[next].id
		let newPage = next / perPage
		if newPage != page {
			animated(.spring(response: 0.4, dampingFraction: 0.85)) { page = newPage }
		}
	}

	private func neighbor(of i: Int, key: UInt16, columns: Int,
						  horizontal: Range<Int>, vertical: Range<Int>) -> Int {
		switch key {
		case 123:
			return i > horizontal.lowerBound ? i - 1 : i
		case 124:
			return i + 1 < horizontal.upperBound ? i + 1 : i
		case 126:
			return i - columns >= vertical.lowerBound ? i - columns : i
		case 125:
			let row = (i - vertical.lowerBound) / columns
			let lastRow = (vertical.upperBound - 1 - vertical.lowerBound) / columns
			return row < lastRow ? min(i + columns, vertical.upperBound - 1) : i
		default:
			return i
		}
	}

	private func changePage(_ delta: Int) {
		let target = min(max(page + delta, 0), max(pages.count - 1, 0))
		guard target != page else { return }
		go(delta)
		if selectedID != nil {
			let all = gridEntries
			selectedID = all.indices.contains(target * perPage) ? all[target * perPage].id : nil
		}
	}

	private func dismiss() {
		guard appeared else { return }
		removeMonitors()
		withAnimation(dismissAnimation) {
			appeared = false
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.15 : 0.32)) {
			AppDelegate.shared?.hideWindow()
		}
	}

	private func go(_ delta: Int) {
		let target = min(max(page + delta, 0), max(pages.count - 1, 0))
		animated(.spring(response: 0.4, dampingFraction: 0.85)) {
			page = target
		}
	}

	private func installMonitors() {
		guard monitors.isEmpty else { return }

		let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
			if ShortcutRecording.isActive { return e }

			if e.keyCode == 53 {
				if showSettings { showSettings = false }
				else if openFolderID != nil { openFolderID = nil }
				else { dismiss() }
				return nil
			}

			if showSettings { return e }

			if let editor = e.window?.firstResponder as? NSTextView,
			   editor.isFieldEditor, !(editor.delegate is NSSearchField) {
				return e
			}

			if (123...126).contains(e.keyCode) {
				moveSelection(e.keyCode)
				return nil
			}

			if openFolderID == nil, query.isEmpty,
			   e.modifierFlags.intersection([.command, .control, .option]).isEmpty {
				switch e.charactersIgnoringModifiers {
				case ",", "<": changePage(-1); return nil
				case ".", ">": changePage(1); return nil
				default: break
				}
			}

			return e
		}

		let wheel = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
			if showSettings || openFolderID != nil { return e }

			let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
			let delta = abs(dx) >= abs(dy) ? dx : dy
			let now = Date()

			if e.hasPreciseScrollingDeltas {
				if e.phase == .began || e.phase == .mayBegin
					|| now.timeIntervalSince(scroll.lastEvent) > 0.2 {
					scroll.accumulated = 0
					scroll.consumed = false
				}
				scroll.lastEvent = now

				if !scroll.consumed, e.momentumPhase == [] {
					scroll.accumulated += delta
					if abs(scroll.accumulated) > 35 {
						go(scroll.accumulated < 0 ? 1 : -1)
						scroll.consumed = true
					}
				}
			} else if abs(delta) > 0.5,
					  now.timeIntervalSince(scroll.lastWheel) > 0.25 {
				scroll.lastWheel = now
				go(delta < 0 ? 1 : -1)
			}
			return nil
		}

		monitors = [key, wheel].compactMap { $0 }
	}

	private func removeMonitors() {
		monitors.forEach { NSEvent.removeMonitor($0) }
		monitors = []
	}
}

struct PageGrid: View {
	let entries: [Entry]
	let columns: Int
	let rows: Int
	let size: CGSize
	let reorderable: Bool
	let selectedID: String?
	let onOpenFolder: (UUID) -> Void

	@AppStorage(Keys.iconSize) private var iconSize = Defaults.iconSize
	@AppStorage(Keys.showLabels) private var showLabels = true

	private let hPadding: CGFloat = 140
	private let hSpacing: CGFloat = 24
	private let vSpacing: CGFloat = 28

	var body: some View {
		let colCount = max(columns, 1)
		let cols = CGFloat(colCount)
		let rws = CGFloat(max(rows, 1))
		let cellW = max((size.width - hPadding * 2 - hSpacing * (cols - 1)) / cols, 1)
		let cellH = (size.height - 20 - vSpacing * (rws - 1)) / rws
		let labelH: CGFloat = showLabels ? 24 : 0
		let icon = max(32, min(iconSize, cellW - 12, cellH - labelH))
		let rowStarts = Array(stride(from: 0, to: entries.count, by: colCount))

		Grid(horizontalSpacing: hSpacing, verticalSpacing: vSpacing) {
			ForEach(rowStarts, id: \.self) { start in
				GridRow {
					ForEach(entries[start..<min(start + colCount, entries.count)]) { entry in
						EntryTile(entry: entry,
								  iconSize: icon,
								  showLabel: showLabels,
								  reorderable: reorderable,
								  selected: entry.id == selectedID,
								  onOpenFolder: onOpenFolder)
							.frame(width: cellW)
					}
				}
			}
		}
		.padding(.horizontal, hPadding)
		.padding(.top, 20)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
	}
}

struct EntryTile: View {
	let entry: Entry
	let iconSize: CGFloat
	let showLabel: Bool
	let reorderable: Bool
	let selected: Bool
	let onOpenFolder: (UUID) -> Void
	@EnvironmentObject private var store: AppStore

	var body: some View {
		tile
			.background {
				RoundedRectangle(cornerRadius: 22, style: .continuous)
					.fill(.white.opacity(selected ? 0.18 : 0))
			}
			.modifier(DragSource(id: entry.id,
								 frameKey: entry.id,
								 context: .grid,
								 iconSize: iconSize,
								 enabled: reorderable))
	}

	@ViewBuilder private var tile: some View {
		switch entry {
		case .app(let path):
			if let app = store.app(path) {
				AppTile(item: app, iconSize: iconSize, showLabel: showLabel)
			}
		case .folder(let folder):
			FolderTile(folder: folder, iconSize: iconSize, showLabel: showLabel) {
				onOpenFolder(folder.id)
			}
		}
	}
}

struct AppTile: View {
	let item: AppItem
	var iconSize: CGFloat = 96
	var showLabel = true
	var inFolder = false

	@EnvironmentObject private var store: AppStore
	@EnvironmentObject private var drag: DragCoordinator
	@Environment(\.dismissLaunchpad) private var dismiss
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		VStack(spacing: 8) {
			Image(nsImage: item.icon)
				.resizable()
				.interpolation(.high)
				.frame(width: iconSize, height: iconSize)
				.overlay(alignment: .bottom) {
					if store.isRunning(item) {
						Circle()
							.fill(.white.opacity(0.9))
							.frame(width: 5, height: 5)
							.offset(y: 6)
					}
				}
				.scaleEffect(hovering && !reduceMotion ? 1.06 : 1)
				.shadow(color: .black.opacity(0.25), radius: 6, y: 3)
			if showLabel {
				Text(verbatim: item.name)
					.font(.system(size: 13))
					.foregroundStyle(.white)
					.lineLimit(1)
			}
		}
		.frame(maxWidth: .infinity)
		.contentShape(Rectangle())
		.onTapGesture { open() }
		.accessibilityAddTraits(.isButton)
		.accessibilityLabel(item.name)
		.onHover { hovering = $0 }
		.animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
		.contextMenu {
			Button("Open") { item.launch(); dismiss() }
			Button("Show in Finder") {
				item.showInFinder()
				dismiss()
			}
			Button("Get Info") {
				item.getInfo()
				dismiss()
			}
			Divider()
			if inFolder {
				Button("Remove from Folder") { store.removeFromFolder(item.path) }
			}
			Button("Hide") { store.hide(item.path) }
		}
	}

	private func open() {
		guard !drag.suppressTap else { return }
		item.launch()
		dismiss()
	}
}

struct FolderTile: View {
	let folder: Folder
	let iconSize: CGFloat
	let showLabel: Bool
	let onOpen: () -> Void

	@EnvironmentObject private var store: AppStore
	@EnvironmentObject private var drag: DragCoordinator
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var hovering = false

	var body: some View {
		let apps = Array(store.visibleApps(in: folder).prefix(9))
		VStack(spacing: 8) {
			FolderIcon(apps: apps, size: iconSize)
				.scaleEffect(hovering && !reduceMotion ? 1.06 : 1)
			if showLabel {
				Text(verbatim: folder.name)
					.font(.system(size: 13))
					.foregroundStyle(.white)
					.lineLimit(1)
			}
		}
		.frame(maxWidth: .infinity)
		.contentShape(Rectangle())
		.onTapGesture {
			guard !drag.suppressTap else { return }
			onOpen()
		}
		.accessibilityAddTraits(.isButton)
		.accessibilityLabel(folder.name)
		.onHover { hovering = $0 }
		.animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
	}
}

struct FolderIcon: View {
	let apps: [AppItem]
	let size: CGFloat

	var body: some View {
		let pad = size * 0.12
		let gap: CGFloat = 4
		let cell = max((size - pad * 2 - gap * 2) / 3, 1)

		ZStack {
			RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
				.fill(.white.opacity(0.22))
			LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 3),
					  spacing: gap) {
				ForEach(apps) { app in
					Image(nsImage: app.icon)
						.resizable()
						.interpolation(.high)
						.frame(width: cell, height: cell)
				}
			}
			.padding(pad)
			.frame(width: size, height: size, alignment: .top)
		}
		.frame(width: size, height: size)
		.shadow(color: .black.opacity(0.25), radius: 6, y: 3)
	}
}

struct FolderOverlay: View {
	let folder: Folder
	let selectedID: String?
	let close: () -> Void
	@EnvironmentObject private var store: AppStore

	var body: some View {
		let apps = store.visibleApps(in: folder)

		ZStack {
			Color.black.opacity(0.25)
				.ignoresSafeArea()
				.contentShape(Rectangle())
				.onTapGesture(perform: close)

			VStack(spacing: 20) {
				TextField("", text: Binding(
					get: { folder.name },
					set: { store.rename(folder.id, to: $0) }
				))
				.textFieldStyle(.plain)
				.multilineTextAlignment(.center)
				.font(.system(size: 26, weight: .semibold))
				.foregroundStyle(.white)

				ViewThatFits(in: .vertical) {
					grid(apps)
					ScrollView(showsIndicators: false) { grid(apps) }
				}
				.frame(maxHeight: 460)
			}
			.padding(36)
			.frame(maxWidth: 720)
			.background {
				GeometryReader { g in
					Color.clear.preference(
						key: TileFramesKey.self,
						value: ["panel": g.frame(in: .named(launchpadSpace))])
				}
			}
			.glassCard(RoundedRectangle(cornerRadius: 36, style: .continuous))
			.contentShape(Rectangle())
			.onTapGesture { }
		}
	}

	private func grid(_ apps: [AppItem]) -> some View {
		LazyVGrid(
			columns: Array(repeating: GridItem(.fixed(130), spacing: 16),
						   count: max(1, min(apps.count, 4))),
			spacing: 20
		) {
			ForEach(apps) { app in
				AppTile(item: app, iconSize: 72, showLabel: true, inFolder: true)
					.background {
						RoundedRectangle(cornerRadius: 18, style: .continuous)
							.fill(.white.opacity(selectedID == "app:" + app.path ? 0.18 : 0))
					}
					.modifier(DragSource(id: "app:" + app.path,
										 frameKey: "f:" + app.path,
										 context: .folder,
										 iconSize: 72,
										 enabled: true,
										 onMovedOut: close))
			}
		}
	}
}

struct NativeSearchField: NSViewRepresentable {
	@Binding var text: String
	var onSubmit: () -> Void

	func makeNSView(context: Context) -> NSSearchField {
		let searchField = NSSearchField()
		searchField.delegate = context.coordinator
		searchField.focusRingType = .none
		searchField.isBordered = false
		searchField.drawsBackground = false
		searchField.placeholderString = tr("Search")
		searchField.cell?.usesSingleLineMode = true
		searchField.cell?.isScrollable = true
		if let cell = searchField.cell as? NSSearchFieldCell {
			cell.searchButtonCell = nil
		}

		DispatchQueue.main.async {
			searchField.window?.makeFirstResponder(searchField)
		}
		return searchField
	}

	func updateNSView(_ nsView: NSSearchField, context: Context) {
		if nsView.stringValue != text {
			nsView.stringValue = text
		}
		nsView.placeholderString = tr("Search")
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	class Coordinator: NSObject, NSSearchFieldDelegate {
		var parent: NativeSearchField

		init(_ parent: NativeSearchField) {
			self.parent = parent
		}

		func controlTextDidChange(_ obj: Notification) {
			if let field = obj.object as? NSSearchField {
				parent.text = field.stringValue
			}
		}

		func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
			if commandSelector == #selector(NSResponder.insertNewline(_:)) {
				parent.onSubmit()
				return true
			}
			return false
		}
	}
}

extension AppItem {
	func showInFinder() {
		NSWorkspace.shared.activateFileViewerSelecting([url])
	}

	@discardableResult
	func getInfo() -> Bool {
		let path = url.path
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
		let source = """
		tell application "Finder"
			set theItem to POSIX file "\(path)" as alias
			open information window of theItem
			activate
		end tell
		"""
		var error: NSDictionary?
		NSAppleScript(source: source)?.executeAndReturnError(&error)
		if let error {
			let code = error[NSAppleScript.errorNumber] as? Int ?? 0
			let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
			print("Get Info failed (\(code)): \(msg)")
			if code == -1743 {
				NSWorkspace.shared.open(URL(string:
					"x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
			}
			return false
		}
		return true
	}
}

final class ScrollState {
	var accumulated: CGFloat = 0
	var consumed = false
	var lastEvent = Date.distantPast
	var lastWheel = Date.distantPast
}
