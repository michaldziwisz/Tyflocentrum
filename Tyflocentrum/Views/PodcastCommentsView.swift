//
//  PodcastCommentsView.swift
//  Tyflocentrum
//

import SwiftUI

struct PodcastCommentsView: View {
	let postID: Int
	let postTitle: String

	@EnvironmentObject private var api: TyfloAPI
	@StateObject private var viewModel = AsyncListViewModel<Comment>()

	private var requestTimeoutSeconds: TimeInterval {
		if ProcessInfo.processInfo.arguments.contains("UI_TESTING_FAST_TIMEOUTS") {
			return 2
		}
		return 15
	}

	var body: some View {
		VStack(spacing: 0) {
			if viewModel.items.isEmpty || viewModel.errorMessage != nil {
				AsyncListStatusSection(
					errorMessage: viewModel.errorMessage,
					isLoading: viewModel.isLoading,
					hasLoaded: viewModel.hasLoaded,
					isEmpty: viewModel.items.isEmpty,
					emptyMessage: "Brak komentarzy.",
					retryAction: { await viewModel.refresh(fetchComments, timeoutSeconds: requestTimeoutSeconds) },
					retryIdentifier: "comments.retry",
					isRetryDisabled: viewModel.isLoading,
					retryHint: "Ponawia pobieranie komentarzy."
				)
				.padding()
			}

			if !viewModel.items.isEmpty {
				SafeHTMLView(
					htmlBody: CommentHTMLDocument.body(comments: viewModel.items),
					baseURL: URL(string: "https://tyflopodcast.net"),
					accessibilityIdentifier: "comments.content"
				)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityIdentifier("comments.list")
		.task {
			await viewModel.loadIfNeeded(fetchComments, timeoutSeconds: requestTimeoutSeconds)
		}
		.toolbar {
			Button {
				Task { await viewModel.refresh(fetchComments, timeoutSeconds: requestTimeoutSeconds) }
			} label: {
				Label("Odśwież komentarze", systemImage: "arrow.clockwise")
			}
			.accessibilityIdentifier("comments.refresh")
			.disabled(viewModel.isLoading)
		}
		.navigationTitle("Komentarze")
		.navigationBarTitleDisplayMode(.inline)
		.accessibilityHint("Komentarze do wpisu: \(postTitle)")
	}

	private func fetchComments() async throws -> [Comment] {
		try await api.fetchComments(forPostID: postID)
	}
}
