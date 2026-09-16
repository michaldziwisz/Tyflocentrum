//
//  ContentView.swift
//  Tyflocentrum
//
//  Created by Arkadiusz Świętnicki on 02/10/2022.
//
import SwiftUI

struct ContentView: View {
	/// Aktywna zakładka jest teraz JAWNYM stanem, nie wewnętrznym sekretem `TabView`.
	///
	/// Powód: odświeżanie po powrocie aplikacji z tła musi dotyczyć tylko widocznego
	/// ekranu. `TabView` trzyma raz odwiedzone zakładki zamontowane, więc bez tej
	/// informacji jedno przełączenie z app switchera uruchamiałoby pobieranie we
	/// wszystkich odwiedzonych zakładkach równolegle.
	///
	/// Sama selekcja nie zmienia semantyki dostępności paska zakładek — VoiceOver
	/// nadal ogłasza je jako karty, bo tagi odpowiadają dotychczasowym wartościom.
	@State private var zakladka: ZakladkaAplikacji = .nowosci

	var body: some View {
		TabView(selection: $zakladka) {
			NewsView().tabItem {
				Text("Nowości")
				Image(systemName: "newspaper")
			}.tag(ZakladkaAplikacji.nowosci)
			PodcastCategoriesView().tabItem {
				Text("Podcasty")
				Image(systemName: "radio")
			}.tag(ZakladkaAplikacji.podcasty)
			ArticlesCategoriesView().tabItem {
				Text("Artykuły")
				Image(systemName: "book")
			}.tag(ZakladkaAplikacji.artykuly)
			SearchView().tabItem {
				Text("Szukaj")
				Image(systemName: "magnifyingglass")
			}.tag(ZakladkaAplikacji.szukaj)
			MoreView().tabItem {
				Text("Tyfloradio")
				Image(systemName: "dot.radiowaves.left.and.right")
			}.tag(ZakladkaAplikacji.tyfloradio)
		}
		.environment(\.aktywnaZakladka, zakladka)
	}
}
