//
//  ZakladkaAplikacji.swift
//  Tyflocentrum
//
//  Tożsamość zakładek głównych i przekazanie aktywnej zakładki w dół drzewa widoków.
//

import SwiftUI

/// Zakładki paska głównego.
///
/// PO CO JAWNY TYP, skoro `TabView` działał wcześniej bez niego: odświeżanie po
/// powrocie z tła musi wiedzieć, KTÓRY ekran jest widoczny. `TabView` nie
/// odmontowuje raz odwiedzonych zakładek, więc zdarzenie „aplikacja wróciła na
/// wierzch” dociera do wszystkich naraz. Bez tożsamości zakładki każda z nich
/// sięgnęłaby do sieci — pięć równoległych pobrań w chwili, gdy użytkownik patrzy
/// na jeden ekran. To jest różnica mierzalna w baterii, nie kwestia elegancji.
enum ZakladkaAplikacji: String, Hashable {
	case nowosci = "News"
	case podcasty = "Podcasts"
	case artykuly = "Articles"
	case szukaj = "Search"
	case tyfloradio = "Tyfloradio"
}

private struct KluczAktywnejZakladki: EnvironmentKey {
	/// Wartość domyślna to zakładka startowa, bo taką `TabView` pokazuje przy
	/// pierwszym uruchomieniu. Dzięki temu widok nie musi obsługiwać „nie wiem,
	/// która zakładka jest aktywna” jako trzeciego stanu.
	static let defaultValue: ZakladkaAplikacji = .nowosci
}

extension EnvironmentValues {
	var aktywnaZakladka: ZakladkaAplikacji {
		get { self[KluczAktywnejZakladki.self] }
		set { self[KluczAktywnejZakladki.self] = newValue }
	}
}
