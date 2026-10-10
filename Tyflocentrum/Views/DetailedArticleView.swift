//
//  DetailedArticleView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 13/11/2022.
//

import Foundation
import SwiftUI
import UIKit

/// Tytuł i data są odrębnymi elementami, również podczas pobierania detalu.
struct ArticleHeaderView: View {
	let title: String
	let date: String

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title)
				.font(.title3.weight(.semibold))
				.fixedSize(horizontal: false, vertical: true)
				.accessibilityAddTraits(.isHeader)
				.accessibilityIdentifier("articleDetail.header")
			Text(date)
				.font(.subheadline)
				.foregroundColor(.secondary)
				.accessibilityIdentifier("articleDetail.date")
		}
		.padding([.horizontal, .top])
	}
}

struct DetailedArticleView: View {
	let article: Podcast
	let favoriteOrigin: FavoriteArticleOrigin
	@EnvironmentObject private var favorites: FavoritesStore

	init(article: Podcast, favoriteOrigin: FavoriteArticleOrigin = .post) {
		self.article = article
		self.favoriteOrigin = favoriteOrigin
	}

	private var favoriteItem: FavoriteItem {
		let summary = WPPostSummary(
			id: article.id,
			date: article.date,
			title: article.title,
			excerpt: article.excerpt,
			link: article.guid.plainText
		)
		return .article(summary: summary, origin: favoriteOrigin)
	}

	private func announceIfVoiceOver(_ message: String) {
		guard UIAccessibility.isVoiceOverRunning else { return }
		UIAccessibility.post(notification: .announcement, argument: message)
	}

	private func toggleFavorite() {
		favorites.toggle(favoriteItem)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			ArticleHeaderView(title: article.title.plainText, date: article.formattedDate)

			ShareLink(
				item: article.guid.plainText,
				subject: Text(article.title.plainText),
				message: Text("Udostępnione przy pomocy aplikacji Tyflocentrum")
			) {
				Label("Udostępnij", systemImage: "square.and.arrow.up")
			}
			.padding(.horizontal)
			.accessibilityIdentifier("articleDetail.share")

			SafeHTMLView(
				htmlBody: article.content.rendered,
				baseURL: URL(string: "https://tyfloswiat.pl"),
				accessibilityIdentifier: "articleDetail.content"
			)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.navigationTitle("")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				Button {
					toggleFavorite()
				} label: {
					Image(systemName: favorites.isFavorite(favoriteItem) ? "star.fill" : "star")
				}
				.accessibilityLabel(favorites.isFavorite(favoriteItem) ? "Usuń z ulubionych" : "Dodaj do ulubionych")
				.accessibilityIdentifier("articleDetail.favorite")
			}
		}
	}
}
