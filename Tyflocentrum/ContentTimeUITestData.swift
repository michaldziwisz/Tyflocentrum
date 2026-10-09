#if DEBUG
	import AVFoundation
	import Foundation
	import SwiftUI

	/// Wyłącznie syntetyczne dane scenariuszy XCTest, nigdy transport produkcyjny.
	enum ContentTimeUITestData {
		static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("UI_TESTING_CONTENT_TIMES") }
		static var refreshScenario: Bool { ProcessInfo.processInfo.arguments.contains("UI_TESTING_TIME_REFRESH") }
		private static let lock = NSLock()
		private static var storedStage = 0
		static var stage: Int {
			get { lock.lock(); defer { lock.unlock() }; return storedStage }
			set { lock.lock(); defer { lock.unlock() }; storedStage = newValue }
		}

		static var longList: Bool { ProcessInfo.processInfo.arguments.contains("UI_TESTING_TIME_LONG_LIST") }
		static var playback: Bool { ProcessInfo.processInfo.arguments.contains("UI_TESTING_TIME_PLAYBACK") }

		static var failed: Bool { ProcessInfo.processInfo.arguments.contains("UI_TESTING_METADATA_FAILURE") }

		static func response(_ request: URLRequest) -> (Int, Data)? {
			guard enabled, let url = request.url,
			      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
			if refreshScenario { NSLog("TIME_REFRESH stage=%d url=%@", stage, url.absoluteString) }
			if refreshScenario, url.path == "/wp-json/wp/v2/posts",
			   !query.contains(where: { $0.name == "include" }),
			   url.host == "tyflopodcast.net" || url.host == "tyfloswiat.pl"
			{
				// Nie korzystamy z dawnych fixture zmieniających ID według liczby żądań.
				let podcast = url.host == "tyflopodcast.net"
				let id = podcast ? 1 : 2
				let item: [String: Any] = ["id": id, "date": "2026-01-20T00:59:40",
				                           "modified_gmt": "2026-01-20T00:59:40", "title": ["rendered": podcast ? "Test podcast" : "Test artykuł"],
				                           "excerpt": ["rendered": "Excerpt"], "link": "https://\(url.host!)/?p=\(id)",
				                           "tyflocentrum": metadata]
				let page = Int(query.first { $0.name == "page" }?.value ?? "1") ?? 1
				if longList {
					let perPage = Int(query.first { $0.name == "per_page" }?.value ?? "20") ?? 20
					let entries: [[String: Any]] = (1 ... 80).reversed().map { index in
						var entry = item
						let identity = index * 2 + (podcast ? 0 : 1)
						entry["id"] = identity
						entry["title"] = ["rendered": "Stały \(podcast ? "podcast" : "artykuł") \(identity)"]
						entry["link"] = "https://\(url.host!)/?p=\(identity)"
						return entry
					}
					return (200, (try? JSONSerialization.data(withJSONObject: Array(entries.dropFirst((page - 1) * perPage).prefix(perPage)))) ?? Data())
				}
				return (200, (try? JSONSerialization.data(withJSONObject: page == 1 ? [item] : [])) ?? Data())
			}
			let isReading = url.host == "tyflocentrum.tyflo.eu.org"
			let include = query.first { $0.name == "include" }?.value
			guard isReading || (url.host == "tyflopodcast.net" && include != nil) else { return nil }
			if failed { return (503, Data("{}".utf8)) }
			let ids = (include ?? query.first { $0.name == "ids" }?.value ?? "").split(separator: ",").compactMap { Int($0) }
			let items: [[String: Any]] = ids.map { id in
				["id": id, "freshness": "fresh", "checked_at": ISO8601DateFormatter().string(from: Date()),
				 "modified_gmt": "2026-01-20T00:59:40", "tyflocentrum": metadata]
			}
			let object: Any = isReading
				? ["schema_version": 1, "source": "tyfloswiat.pl", "type": query.first { $0.name == "type" }?.value ?? "posts", "items": items]
				: items
			return (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
		}

		static var metadata: [String: Any] {
			if refreshScenario {
				switch stage {
				case 0, 3: return ["schema_version": 1, "text_status": "missing", "audio_status": "missing"]
				case 2: return ["schema_version": 1, "word_count": 1201, "reading_minutes": 7, "text_status": "ready", "audio_status": "ready", "duration_seconds": 60]
				case 4: return ["schema_version": 1, "text_status": "ready", "word_count": true, "audio_status": "ready", "duration_seconds": true]
				default: break
				}
			}
			return ["schema_version": 1, "word_count": 1001, "reading_minutes": 6, "text_status": "ready", "audio_status": "ready", "duration_seconds": 4983.1]
		}

		static func decorate(_ data: Data, request: URLRequest) -> Data {
			guard enabled, request.url?.host == "tyflopodcast.net", request.url?.path.contains("/wp/v2/posts") == true,
			      let value = try? JSONSerialization.jsonObject(with: data) else { return data }
			func decorateItem(_ item: [String: Any]) -> [String: Any] {
				var item = item
				item["tyflocentrum"] = failed ? ["duration_seconds": true] : metadata
				return item
			}
			let result: Any
			if let items = value as? [[String: Any]] { result = items.map(decorateItem) }
			else if let item = value as? [String: Any] { result = decorateItem(item) }
			else { return data }
			return (try? JSONSerialization.data(withJSONObject: result)) ?? data
		}
	}

	/// Pomiar prawdziwego AVPlayer z lokalnym PCM, wyłącznie w scenariuszu XCTest.
	@MainActor
	final class ContentTimePlaybackProbe {
		static let shared = ContentTimePlaybackProbe()
		let player = AVPlayer()
		private var statusObservation: NSKeyValueObservation?
		private var itemObservation: NSKeyValueObservation?
		private var samples: Any?
		private(set) var changes = 0
		private(set) var interruptions = 0
		private(set) var ticks = 0
		private var measuring = false
		private var lastTime: Double = 0
		private(set) var regressions = 0
		private(set) var maxGap: Double = 0

		func begin() {
			changes = 0; interruptions = 0; ticks = 0; regressions = 0; maxGap = 0
			lastTime = player.currentTime().seconds
			measuring = true
			statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
				let interrupted = player.timeControlStatus != .playing
				Task { @MainActor in if interrupted, self?.measuring == true { self?.interruptions += 1 } }
			}
			itemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
				Task { @MainActor in if self?.measuring == true { self?.changes += 1 } }
			}
			if let samples { player.removeTimeObserver(samples) }
			samples = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
				Task { @MainActor in
					guard let self, measuring else { return }
					let current = time.seconds
					if current < lastTime { regressions += 1 }
					maxGap = max(maxGap, current - lastTime)
					lastTime = current; ticks += 1
				}
			}
		}

		var snapshot: String {
			"time=\(player.currentTime().seconds);playing=\(player.timeControlStatus == .playing);changes=\(changes);interruptions=\(interruptions);ticks=\(ticks);regressions=\(regressions);gap=\(maxGap);item=\(player.currentItem.map { String(describing: ObjectIdentifier($0)) } ?? "nil")"
		}

		func makeAudio() throws -> URL {
			let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("test-tone.wav")
			let rate: UInt32 = 8000
			let count = Int(rate) * 600
			var data = Data()
			func text(_ value: String) { data.append(Data(value.utf8)) }
			func number<T: FixedWidthInteger>(_ value: T) {
				var little = value.littleEndian
				withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
			}
			text("RIFF"); number(UInt32(36 + count * 2)); text("WAVEfmt ")
			number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(rate)
			number(rate * 2); number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(count * 2))
			for index in 0 ..< count {
				number(Int16(sin(Double(index) * 2 * .pi * 440 / Double(rate)) * 1200))
			}
			try data.write(to: url, options: .atomic)
			NSLog("TIME_AUDIO fixture=%@ bytes=%d", url.lastPathComponent, data.count)
			return url
		}
	}

	struct ContentTimePlaybackControl: View {
		@ObservedObject var audio: AudioPlayer
		@State private var snapshot = "idle"
		var body: some View {
			if ContentTimeUITestData.playback {
				HStack {
					Button("Audio") {
						do { try audio.play(url: ContentTimePlaybackProbe.shared.makeAudio(), title: "Lokalny ton kontrolny") }
						catch { snapshot = "error=\(error)" }
					}.accessibilityIdentifier("timeTest.audio")
					Button("Pomiar") { ContentTimePlaybackProbe.shared.begin() }.accessibilityIdentifier("timeTest.measure")
					Button("Odczyt") {
						snapshot = ContentTimePlaybackProbe.shared.snapshot
						NSLog("TIME_AUDIO %@", snapshot)
					}.accessibilityIdentifier("timeTest.sample").accessibilityValue(snapshot)
					Text(audio.isPlaying ? "Gra" : "Stop").accessibilityIdentifier("timeTest.playing")
				}
				.font(.caption)
				.background(.regularMaterial)
			}
		}
	}

	/// Steruje wyłącznie atrapą serwera. Nie unieważnia cache i nie odświeża widoku listy.
	struct ContentTimeServerControl: View {
		@State private var stage = 0
		var body: some View {
			if ContentTimeUITestData.refreshScenario {
				Button("Serwer: \(stage), proces: \(ProcessInfo.processInfo.processIdentifier)") {
					stage = (stage + 1) % 5
					ContentTimeUITestData.stage = stage
				}
				.accessibilityIdentifier("timeTest.server")
				.padding(4)
				.background(.regularMaterial)
			}
		}
	}
#endif
