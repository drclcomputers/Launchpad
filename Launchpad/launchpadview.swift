//
//  launchpadview.swift
//  Launchpad
//
//  Created by Dorneanu Denis on 30/10/2026.
//

import SwiftUI

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
			VisualEffect().ignoresSafeArea()
			Color.black.opacity(0.15).ignoresSafeArea()
				.onTapGesture { NSApp.terminate(nil) }

			VStack(spacing: 24) {
				searchBar
				pager
				dots
			}
			.padding(.vertical, 40)
		}
		.onChange(of: query) { page = 0 }
		.onAppear {
			searchFocused = true
			installMonitors()
		}
	}

	// MARK: - Parts

	private var searchBar: some View {
		HStack(spacing: 6) {
			Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
			TextField("Căutare", text: $query)
				.textFieldStyle(.plain)
				.foregroundStyle(.white)
				.focused($searchFocused)
				.onSubmit { filtered.first?.launch() }
		}
		.padding(.horizontal, 12).padding(.vertical, 6)
		.frame(width: 260)
		.background(.white.opacity(0.15), in: Capsule())
	}

	private var pager: some View {
		GeometryReader { geo in
			let w = geo.size.width
			HStack(spacing: 0) {
				ForEach(pages.indices, id: \.self) { i in
					PageGrid(items: pages[i], columns: columns)
						.frame(width: w, height: geo.size.height, alignment: .top)
				}
			}
			.offset(x: -CGFloat(page) * w + drag)
			.animation(.interpolatingSpring(stiffness: 220, damping: 28), value: page)
			.gesture(
				DragGesture()
					.onChanged { drag = $0.translation.width }
					.onEnded { v in
						if v.translation.width < -w * 0.15 { go(1) }
						else if v.translation.width > w * 0.15 { go(-1) }
						withAnimation(.easeOut(duration: 0.25)) { drag = 0 }
					}
			)
		}
		.clipped()
	}

	private var dots: some View {
		HStack(spacing: 10) {
			ForEach(pages.indices, id: \.self) { i in
				Circle()
					.fill(.white.opacity(i == page ? 0.95 : 0.35))
					.frame(width: 8, height: 8)
					.onTapGesture { page = i }
			}
		}
		.frame(height: 12)
	}

	// MARK: - Logic

	private func go(_ delta: Int) {
		page = min(max(page + delta, 0), max(pages.count - 1, 0))
	}

	private func installMonitors() {
		guard !monitorsInstalled else { return }
		monitorsInstalled = true

		NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
			switch e.keyCode {
			case 53:  NSApp.terminate(nil); return nil   // Esc
			case 123: go(-1); return nil                  // ←
			case 124: go(1);  return nil                  // →
			default:  return e
			}
		}

		NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
			// Ignoră complet inerția (momentum) de după ridicarea degetelor
			if e.momentumPhase != [] { return e }

			let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY

			if e.phase == .mayBegin || e.phase == .began {
				scroll.accumulated = 0
				scroll.consumed = false
			}

			// Trackpad: o singură schimbare de pagină per gest
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
				// Mouse cu rotiță (fără faze)
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

struct AppTile: View {
	let item: AppItem
	@State private var hovering = false

	var body: some View {
		Button { item.launch() } label: {
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
		.animation(.easeOut(duration: 0.15), value: hovering)
	}
}

final class ScrollState {
	var accumulated: CGFloat = 0
	var consumed = false
	var lastWheel = Date.distantPast
}
