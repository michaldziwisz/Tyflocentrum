//
//  LazyDetailedArticleView.swift
//  Tyflocentrum
//

import Foundation
import SwiftUI

private enum DetailLoadError: Error {
	case staleResult
}

struct DetailLoaderView: View {
	let summary: WPPostSummary
	let favoriteOrigin: FavoriteArticleOrigin
	let fetch: (Int, URLRequest.CachePolicy) async throws -> Podcast

	@State private var article: Podcast?
	@State private var isLoading = false
	@State private var errorMessage: String?
	@State private var retryCount = 0
	@State private var activeRequestID: UUID?

	var body: some View {
		ZStack {
			if let article {
				DetailedArticleView(article: article, favoriteOrigin: favoriteOrigin)
			} else {
				VStack(alignment: .leading, spacing: 16) {
					ArticleHeaderView(title: summary.title.plainText, date: summary.asPodcastStub().formattedDate)
					pendingContent
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			}
		}
		.navigationTitle("")
		.navigationBarTitleDisplayMode(.inline)
		.task(id: taskID) {
			await load(triggeringTaskID: taskID, manualRetry: retryCount > 0)
		}
		.onDisappear {
			activeRequestID = nil
			isLoading = false
		}
	}

	@ViewBuilder
	private var pendingContent: some View {
		if let message = errorMessage {
			VStack(alignment: .leading, spacing: 12) {
				Text(message)
					.foregroundColor(.secondary)

				Button("Spróbuj ponownie") {
					errorMessage = nil
					retryCount += 1
				}
				.accessibilityHint("Ponawia pobieranie danych.")
				.accessibilityIdentifier("postDetail.retry")
				.disabled(isLoading)
				.accessibilityHidden(isLoading)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding()
		} else {
			ProgressView("Ładowanie…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	private var taskID: String {
		"\(summary.id)-\(retryCount)"
	}

	@MainActor
	private func load(triggeringTaskID: String, manualRetry: Bool) async {
		guard article == nil else { return }
		guard !isLoading else { return }
		isLoading = true
		errorMessage = nil
		let requestID = UUID()
		activeRequestID = requestID
		defer {
			if activeRequestID == requestID {
				activeRequestID = nil
				isLoading = false
			}
		}

		do {
			let cachePolicy: URLRequest.CachePolicy = manualRetry ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
			#if DEBUG
				// Tylko aparatura UI: nie uruchamia zegara API przed jawnym zwolnieniem.
				if ArticleTitleRequestGate.enabled { try await ArticleTitleRequestGate.shared.waitOnce() }
			#endif
			let loaded = try await fetch(summary.id, cachePolicy)
			guard !Task.isCancelled else { return }
			guard activeRequestID == requestID, taskID == triggeringTaskID else {
				throw DetailLoadError.staleResult
			}
			article = loaded
		} catch is CancellationError {
			return
		} catch DetailLoadError.staleResult {
			return
		} catch {
			guard !Task.isCancelled else { return }
			guard activeRequestID == requestID, taskID == triggeringTaskID else { return }
			if error is AsyncTimeoutError {
				errorMessage = "Ładowanie trwa zbyt długo. Spróbuj ponownie."
			} else {
				errorMessage = "Nie udało się pobrać danych. Spróbuj ponownie."
			}
		}
	}
}

struct LazyDetailedArticleView: View {
	let summary: WPPostSummary

	@EnvironmentObject private var api: TyfloAPI

	var body: some View {
		DetailLoaderView(summary: summary, favoriteOrigin: .post) { id, cachePolicy in
			try await api.fetchArticle(id: id, cachePolicy: cachePolicy)
		}
		.id("post-\(summary.id)")
	}
}
