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
	@State private var query = ""
	@State private var page = 0
	@State private var drag: CGFloat = 0
	@State private var scroll = ScrollState()
	@State private var monitorsInstalled = false
	@State private var appeared = false
	@FocusState private var searchFocused: Bool

	private let columns = 7
	private let rows = 5
	private var perPage: Int { columns * rows }

	private var filtered: [AppItem] {
		query.isEmpty ? store.apps
					  : store.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
	}
	private var pages: [[AppItem]] {
		stride(from: 0, to: filtered.count, by: perPage).map {
			Array(filtered[$0..<min($0 + perPage, filtered.count)])
		}
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
				searchBar
				pager
				dots
			}
			.padding(.vertical, 40)
			.scaleEffect(appeared ? 1 : 1.12)
		}
		.opacity(appeared ? 1 : 0)
		.environment(\.dismissLaunchpad, { dismiss() })
		.onChange(of: query) { page = 0 }
		.onAppear {
			installMonitors()
			withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
				appeared = true
			}
		}
	}

	private var searchBar: some View {
		HStack(spacing: 10) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 17, weight: .medium))
				.foregroundStyle(.white.opacity(0.7))
			
			NativeSearchField(text: $query) {
				if let first = filtered.first {
					first.launch()
					dismiss()
				}
			}
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

	private var pager: some View {
		GeometryReader { geo in
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 0) {
					ForEach(pages.indices, id: \.self) { i in
						PageGrid(items: pages[i], columns: columns)
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
		}
	}

	private var dots: some View {
		HStack(spacing: 10) {
			ForEach(pages.indices, id: \.self) { i in
				Circle()
					.fill(.white.opacity(i == page ? 0.95 : 0.35))
					.frame(width: 8, height: 8)
					.onTapGesture {
						withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
							page = i
						}
					}
			}
		}
		.frame(height: 12)
	}

	private func dismiss() {
		guard appeared else { return }
		withAnimation(.spring(response: 0.28, dampingFraction: 0.90)) {
			appeared = false
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
			NSApp.terminate(nil)
		}
	}

	private func go(_ delta: Int) {
		page = min(max(page + delta, 0), max(pages.count - 1, 0))
	}

	private func installMonitors() {
			guard !monitorsInstalled else { return }
			monitorsInstalled = true

			NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
				switch e.keyCode {
				case 53:  dismiss(); return nil               // Esc
				case 123 where query.isEmpty: go(-1); return nil   // ←
				case 124 where query.isEmpty: go(1);  return nil   // →
				default:  break
				}
				return e
			}

		NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
			if e.momentumPhase != [] { return e }

			let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY

			if e.phase == .mayBegin || e.phase == .began {
				scroll.accumulated = 0
				scroll.consumed = false
			}

			if e.phase != [] {
				if !scroll.consumed, abs(dx) > abs(dy) {
					scroll.accumulated += dx
					if abs(scroll.accumulated) > 60 {
						go(scroll.accumulated < 0 ? 1 : -1)
						scroll.consumed = true
					}
				}
				if e.phase == .ended || e.phase == .cancelled {
					scroll.accumulated = 0
					scroll.consumed = false
				}
			} else if abs(dx) > abs(dy), abs(dx) > 4,
					  Date().timeIntervalSince(scroll.lastWheel) > 0.3 {
				scroll.lastWheel = Date()
				go(dx < 0 ? 1 : -1)
			}
			return e
		}
	}
}

struct PageGrid: View {
	let items: [AppItem]
	let columns: Int

	var body: some View {
		LazyVGrid(
			columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: columns),
			spacing: 28
		) {
			ForEach(items) { AppTile(item: $0) }
		}
		.padding(.horizontal, 140)
		.padding(.top, 20)
		.frame(maxHeight: .infinity, alignment: .top)
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
		searchField.placeholderString = "Căutare"
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

struct AppTile: View {
	let item: AppItem
	@Environment(\.dismissLaunchpad) private var dismiss
	@State private var hovering = false

	var body: some View {
		Button { open() } label: {
			VStack(spacing: 8) {
				Image(nsImage: item.icon)
					.resizable()
					.interpolation(.high)
					.frame(width: 96, height: 96)
					.scaleEffect(hovering ? 1.06 : 1)
					.shadow(color: .black.opacity(0.25), radius: 6, y: 3)
				Text(item.name)
					.font(.system(size: 13))
					.foregroundStyle(.white)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
		.contextMenu {
			Button("Open") { open() }
			Button("Show in Finder") {
				item.showInFinder()
				dismiss()
			}
			Button("Get Info") {
				item.getInfo()
				dismiss()
			}
		}
	}

	private func open() {
		item.launch()
		dismiss()
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
	var lastWheel = Date.distantPast
}
