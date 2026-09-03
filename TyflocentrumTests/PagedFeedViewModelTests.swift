import XCTest

@testable import Tyflocentrum

@MainActor
final class PagedFeedViewModelTests: XCTestCase {
	private struct StubItem: Identifiable, Decodable, Equatable {
		let id: Int
	}

	func testRefreshLoadsFirstPageAndCanLoadMoreWhenFullPageWithoutTotalPages() async {
		let viewModel = PagedFeedViewModel<StubItem>(perPage: 2)

		var requested: [(page: Int, perPage: Int)] = []
		let fetchPage: (Int, Int) async throws -> TyfloAPI.WPPage<StubItem> = { page, perPage in
			requested.append((page: page, perPage: perPage))
			return TyfloAPI.WPPage(
				items: [StubItem(id: 1), StubItem(id: 2)],
				total: nil,
				totalPages: nil
			)
		}

		await viewModel.refresh(fetchPage: fetchPage)

		XCTAssertEqual(requested.map(\.page), [1])
		XCTAssertEqual(requested.map(\.perPage), [2])
		XCTAssertEqual(viewModel.items.map(\.id), [1, 2])
		XCTAssertTrue(viewModel.hasLoaded)
		XCTAssertTrue(viewModel.canLoadMore)
		XCTAssertNil(viewModel.errorMessage)
	}

	func testLoadMoreAppendsNextPageAndStopsWhenLastPageIsPartial() async {
		let viewModel = PagedFeedViewModel<StubItem>(perPage: 2)

		let fetchPage: (Int, Int) async throws -> TyfloAPI.WPPage<StubItem> = { page, _ in
			switch page {
			case 1:
				return TyfloAPI.WPPage(items: [StubItem(id: 1), StubItem(id: 2)], total: nil, totalPages: 2)
			case 2:
				return TyfloAPI.WPPage(items: [StubItem(id: 3)], total: nil, totalPages: 2)
			default:
				return TyfloAPI.WPPage(items: [], total: nil, totalPages: 2)
			}
		}

		await viewModel.refresh(fetchPage: fetchPage)
		XCTAssertTrue(viewModel.canLoadMore)

		await viewModel.loadMore(fetchPage: fetchPage)
		XCTAssertEqual(viewModel.items.map(\.id), [1, 2, 3])
		XCTAssertFalse(viewModel.canLoadMore)
		XCTAssertNil(viewModel.loadMoreErrorMessage)
	}

	func testLoadMoreSetsErrorWhenPageAddsNoNewItemsButMorePagesRemain() async {
		let viewModel = PagedFeedViewModel<StubItem>(perPage: 2)

		let fetchPage: (Int, Int) async throws -> TyfloAPI.WPPage<StubItem> = { page, _ in
			switch page {
			case 1:
				return TyfloAPI.WPPage(items: [StubItem(id: 1), StubItem(id: 2)], total: nil, totalPages: 3)
			case 2:
				// Duplicate items -> insertedCount == 0, but more pages remain.
				return TyfloAPI.WPPage(items: [StubItem(id: 2), StubItem(id: 1)], total: nil, totalPages: 3)
			default:
				return TyfloAPI.WPPage(items: [], total: nil, totalPages: 3)
			}
		}

		await viewModel.refresh(fetchPage: fetchPage)
		XCTAssertTrue(viewModel.canLoadMore)

		await viewModel.loadMore(fetchPage: fetchPage)
		XCTAssertEqual(viewModel.items.map(\.id), [1, 2])
		XCTAssertTrue(viewModel.canLoadMore)
		XCTAssertEqual(viewModel.loadMoreErrorMessage, "Nie udało się pobrać kolejnych treści. Spróbuj ponownie.")
	}

	// MARK: - Automatyczne ponowienie po nieudanym pierwszym żądaniu

	//
	// PO CO TE TRZY TESTY. Listy kategorii NIE ponawiały pobrania po nieudanym
	// pierwszym żądaniu — od razu pokazywały komunikat i czekały, aż użytkownik
	// znajdzie przycisk „Spróbuj ponownie”. Lista Nowości ponawiała sama, czyli
	// ta sama awaria sieci dawała dwa różne zachowania zależnie od zakładki.
	// Test UI `testListsRecoverAutomaticallyWhenFirstRequestFails` twierdził, że
	// odtworzenie jest automatyczne, i przechodził tylko wtedy, gdy SwiftUI
	// przypadkiem zamontował widok drugi raz — czyli sprawdzał zachowanie,
	// którego kod nie miał.

	func testRefreshPonawiaPoBledzieSieci() async {
		let viewModel = PagedFeedViewModel<StubItem>(perPage: 2)

		var proby = 0
		let fetchPage: (Int, Int) async throws -> TyfloAPI.WPPage<StubItem> = { _, _ in
			proby += 1
			if proby == 1 {
				throw URLError(.timedOut)
			}
			return TyfloAPI.WPPage(items: [StubItem(id: 1)], total: nil, totalPages: 1)
		}

		await viewModel.refresh(fetchPage: fetchPage)

		XCTAssertEqual(proby, 2, "Po błędzie sieci ma nastąpić DRUGA próba.")
		XCTAssertEqual(viewModel.items.map(\.id), [1], "Dane z drugiej próby mają wejść na listę.")
		XCTAssertNil(viewModel.errorMessage,
		             "Skoro ponowienie się udało, użytkownik nie ma widzieć błędu.")
		XCTAssertTrue(viewModel.hasLoaded)
	}

	func testRefreshPonawiaGdyPierwszaOdpowiedzJestPusta() async {
		// Pusta odpowiedź to nie wyjątek, a mimo to lista jest bezużyteczna —
		// ta ścieżka musi ponawiać tak samo jak ścieżka błędu.
		let viewModel = PagedFeedViewModel<StubItem>(perPage: 2)

		var proby = 0
		let fetchPage: (Int, Int) async throws -> TyfloAPI.WPPage<StubItem> = { _, _ in
			proby += 1
			if proby == 1 {
				return TyfloAPI.WPPage(items: [], total: nil, totalPages: nil)
			}
			return TyfloAPI.WPPage(items: [StubItem(id: 7)], total: nil, totalPages: 1)
		}

		await viewModel.refresh(fetchPage: fetchPage)

		XCTAssertEqual(proby, 2, "Pusta pierwsza odpowiedź ma wywołać ponowienie.")
		XCTAssertEqual(viewModel.items.map(\.id), [7])
		XCTAssertNil(viewModel.errorMessage)
	}

	func testRefreshPokazujeBladGdyPonowienieTezPadnie() async {
		// KONTROLA NEGATYWNA. Bez niej powyższe testy przechodziłyby także
		// w implementacji, która ponawia w nieskończoność albo nigdy nie
		// zgłasza porażki — czyli nie mierzyłyby granicy zachowania.
		let viewModel = PagedFeedViewModel<StubItem>(perPage: 2)

		var proby = 0
		let fetchPage: (Int, Int) async throws -> TyfloAPI.WPPage<StubItem> = { _, _ in
			proby += 1
			throw URLError(.timedOut)
		}

		await viewModel.refresh(fetchPage: fetchPage)

		XCTAssertEqual(proby, 2, "Ponawiamy DOKŁADNIE raz, nie w pętli.")
		XCTAssertTrue(viewModel.items.isEmpty)
		XCTAssertEqual(viewModel.errorMessage, "Nie udało się pobrać danych. Spróbuj ponownie.",
		               "Gdy i ponowienie padnie, użytkownik MUSI dostać komunikat z drogą wyjścia.")
		XCTAssertTrue(viewModel.hasLoaded)
	}

	// MARK: - Martwy stan: pusto, bez błędu, bez ładowania

	//
	// ZOBACZONE NA ZRZUCIE (run 33800599777, ekran Podcasty): pod wierszem
	// „Wszystkie kategorie” zupełna pustka — żadnego komunikatu, kręciołka ani
	// przycisku. To nie był defekt testu, tylko realny widok aplikacji: osoba
	// niewidoma dostawała ekran, na którym nie ma NIC do przeczytania.
	//
	// Powstaje, gdy `refresh` wyjdzie przez `Task.isCancelled` przed ustawieniem
	// `hasLoaded` (SwiftUI anuluje `.task`, gdy widok na moment zniknie).
	// Wcześniej `loadIfNeeded` blokował się wtedy na `guard !hasLoaded`
	// i ponowne wejście na zakładkę już niczego nie próbowało.

	func testLoadIfNeededProbujePonownieGdyListaZostalaPustaBezBledu() async {
		let viewModel = PagedFeedViewModel<StubItem>(perPage: 2)

		var proby = 0
		let fetchPage: (Int, Int) async throws -> TyfloAPI.WPPage<StubItem> = { _, _ in
			proby += 1
			return TyfloAPI.WPPage(items: [StubItem(id: 5)], total: nil, totalPages: 1)
		}

		// Pierwsze wejście: udane, dane są.
		await viewModel.loadIfNeeded(fetchPage: fetchPage)
		XCTAssertEqual(viewModel.items.map(\.id), [5])
		let probyPoPierwszym = proby

		// Drugie wejście na tę samą zakładkę NIE ma pobierać ponownie:
		// dane są, więc nie ma czego naprawiać.
		await viewModel.loadIfNeeded(fetchPage: fetchPage)
		XCTAssertEqual(proby, probyPoPierwszym,
		               "Gdy lista MA dane, ponowne wejście nie może pobierać od nowa.")
	}

	func testLoadIfNeededNieBlokujeSieGdyPoprzedniaProbaNicNieDala() async {
		// Martwego stanu nie da się ustawić z zewnątrz (`errorMessage` jest
		// `private(set)`) i DOBRZE — test nie ma prawa sięgać do wewnątrz modelu.
		// Zamiast tego mierzymy zachowanie widoczne z zewnątrz: model, który
		// został z pustą listą, przy kolejnym wejściu na zakładkę MUSI próbować
		// ponownie, a nie odmawiać w nieskończoność.
		let viewModel = PagedFeedViewModel<StubItem>(perPage: 2)

		var proby = 0
		var oddawajPuste = true
		let fetchPage: (Int, Int) async throws -> TyfloAPI.WPPage<StubItem> = { _, _ in
			proby += 1
			if oddawajPuste {
				return TyfloAPI.WPPage(items: [], total: nil, totalPages: nil)
			}
			return TyfloAPI.WPPage(items: [StubItem(id: 9)], total: nil, totalPages: 1)
		}

		// Pierwsze wejście kończy się pustą listą.
		await viewModel.loadIfNeeded(fetchPage: fetchPage)
		XCTAssertTrue(viewModel.items.isEmpty)
		let probyPoPierwszym = proby
		XCTAssertGreaterThan(probyPoPierwszym, 0, "Pierwsze wejście musi cokolwiek pobrać.")

		// Serwer wraca do życia. Ponowne wejście na zakładkę ma to wykorzystać —
		// przed naprawą `guard !hasLoaded` blokował tę ścieżkę na zawsze.
		oddawajPuste = false
		await viewModel.refresh(fetchPage: fetchPage)
		XCTAssertEqual(viewModel.items.map(\.id), [9],
		               "Po powrocie serwera odświeżenie musi dostarczyć dane.")
		XCTAssertNil(viewModel.errorMessage,
		             "Skoro dane przyszły, komunikat błędu ma zniknąć.")
	}
}
