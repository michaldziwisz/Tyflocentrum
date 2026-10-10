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

	func testTimeOnlyRefreshRetainsRowsAndRejectsOldPagination() async {
		let model = PagedFeedViewModel<StubItem>(perPage: 1)
		await model.loadIfNeeded { _, _ in TyfloAPI.WPPage(items: [StubItem(id: 1)], total: 3, totalPages: 3) }
		let entered = expectation(description: "Stara druga strona oczekuje")
		var release: CheckedContinuation<Void, Never>?
		let old = Task {
			await model.loadMore { _, _ in
				await withCheckedContinuation { release = $0; entered.fulfill() }
				return TyfloAPI.WPPage(items: [StubItem(id: 99)], total: 3, totalPages: 3)
			}
		}
		await fulfillment(of: [entered], timeout: 5)
		await model.refresh { _, _ in
			XCTAssertEqual(model.items.map(\.id), [1], "Wiersz pozostaje na ekranie podczas transportu")
			return TyfloAPI.WPPage(items: [StubItem(id: 1)], total: 3, totalPages: 3)
		}
		release?.resume()
		await old.value
		XCTAssertEqual(model.items.map(\.id), [1])
		XCTAssertNil(model.loadMoreErrorMessage)
		await model.loadMore { page, _ in
			XCTAssertEqual(page, 2)
			return TyfloAPI.WPPage(items: [StubItem(id: 2)], total: 3, totalPages: 3)
		}
		XCTAssertEqual(model.items.map(\.id), [1, 2])
	}

	func testManualRefreshDuringLoadIsCoalescedNotLost() async {
		let model = PagedFeedViewModel<StubItem>(perPage: 1)
		let gate = FirstPageGate()
		let initial = Task { await model.loadIfNeeded(fetchPage: gate.fetch) }
		await fulfillment(of: [gate.started], timeout: 5)
		let entered = expectation(description: "Ręczne odświeżenia weszły")
		entered.expectedFulfillmentCount = 3
		let pending = (0 ..< 3).map { _ in Task {
			entered.fulfill()
			await model.refresh(fetchPage: gate.fetch)
		} }
		await fulfillment(of: [entered], timeout: 5)
		XCTAssertEqual(gate.requestedPages, [1])
		gate.finish(.success(TyfloAPI.WPPage(items: [StubItem(id: 7)], total: nil, totalPages: 1)))
		await initial.value
		for task in pending {
			await task.value
		}
		XCTAssertEqual(gate.requestedPages, [1, 1], "Jedno wspólne ponowienie po starym żądaniu")
		XCTAssertEqual(model.items.map(\.id), [20])
	}

	// MARK: - Przejęcie pierwszego ładowania po anulowaniu

	@MainActor
	private final class FirstPageGate {
		let started = XCTestExpectation(description: "Pierwsze żądanie zawieszone")
		private(set) var requestedPages: [Int] = []
		private var continuation: CheckedContinuation<TyfloAPI.WPPage<StubItem>, Error>?

		func fetch(page: Int, perPage _: Int) async throws -> TyfloAPI.WPPage<StubItem> {
			requestedPages.append(page)
			if requestedPages.count == 1 {
				return try await withCheckedThrowingContinuation { continuation in
					self.continuation = continuation
					started.fulfill()
				}
			}
			return TyfloAPI.WPPage(items: [StubItem(id: 20)], total: nil, totalPages: 1)
		}

		func finish(_ result: Result<TyfloAPI.WPPage<StubItem>, Error>) {
			guard let continuation else {
				XCTFail("Brak zawieszonego pierwszego żądania")
				return
			}
			self.continuation = nil
			continuation.resume(with: result)
		}
	}

	func testLoadIfNeededTakesOverCancelledRequestBeforeItFinishes() async {
		let model = PagedFeedViewModel<StubItem>(perPage: 2)
		let gate = FirstPageGate()
		let first = Task { await model.loadIfNeeded(fetchPage: gate.fetch) }
		await fulfillment(of: [gate.started], timeout: 5)
		first.cancel()

		let replacementEntered = expectation(description: "Następne zadanie weszło w model")
		var replacementFinished = false
		let replacement = Task {
			replacementEntered.fulfill()
			await model.loadIfNeeded(fetchPage: gate.fetch)
			replacementFinished = true
		}
		await fulfillment(of: [replacementEntered], timeout: 5)
		XCTAssertTrue(model.isLoading, "Pierwsze żądanie wciąż trzyma blokadę")
		XCTAssertFalse(replacementFinished, "Następne zadanie ma poczekać, nie zgubić ładowanie")
		XCTAssertEqual(gate.requestedPages, [1], "Nie wysyłamy równoległego żądania")

		gate.finish(.failure(CancellationError()))
		await first.value
		await replacement.value
		XCTAssertEqual(gate.requestedPages, [1, 1])
		XCTAssertEqual(model.items.map(\.id), [20])
		XCTAssertTrue(model.hasLoaded)
		XCTAssertFalse(model.isLoading)
		XCTAssertNil(model.errorMessage)
	}

	func testCancelledWaiterReturnsBeforeOwnerAndDoesNotFetch() async {
		let model = PagedFeedViewModel<StubItem>(perPage: 2)
		let gate = FirstPageGate()
		let first = Task { await model.loadIfNeeded(fetchPage: gate.fetch) }
		await fulfillment(of: [gate.started], timeout: 5)
		let entered = expectation(description: "Oczekujący wszedł w model")
		let finished = expectation(description: "Anulowany oczekujący zakończył się")
		let waiter = Task {
			entered.fulfill()
			await model.loadIfNeeded(fetchPage: gate.fetch)
			finished.fulfill()
		}
		await fulfillment(of: [entered], timeout: 5)
		waiter.cancel()
		await fulfillment(of: [finished], timeout: 5)
		XCTAssertTrue(model.isLoading, "Anulowanie oczekującego nie anuluje właściciela")
		XCTAssertEqual(gate.requestedPages, [1])

		gate.finish(.success(TyfloAPI.WPPage(items: [StubItem(id: 7)], total: nil, totalPages: 1)))
		await first.value
		await waiter.value
		XCTAssertEqual(gate.requestedPages, [1])
		XCTAssertEqual(model.items.map(\.id), [7])
		XCTAssertTrue(model.hasLoaded)
	}

	func testConcurrentLoadersShareSuccessfulFirstRequest() async {
		let model = PagedFeedViewModel<StubItem>(perPage: 2)
		let gate = FirstPageGate()
		let first = Task { await model.loadIfNeeded(fetchPage: gate.fetch) }
		await fulfillment(of: [gate.started], timeout: 5)
		let entered = expectation(description: "Wszyscy oczekujący weszli w model")
		entered.expectedFulfillmentCount = 3
		var finished = 0
		let waiters = (0 ..< 3).map { _ in
			Task {
				entered.fulfill()
				await model.loadIfNeeded(fetchPage: gate.fetch)
				finished += 1
			}
		}
		await fulfillment(of: [entered], timeout: 5)
		XCTAssertEqual(finished, 0)
		XCTAssertEqual(gate.requestedPages, [1])
		gate.finish(.success(TyfloAPI.WPPage(items: [StubItem(id: 7)], total: nil, totalPages: 1)))
		await first.value
		for waiter in waiters {
			await waiter.value
		}
		XCTAssertEqual(finished, 3)
		XCTAssertEqual(gate.requestedPages, [1], "Udana odpowiedź wystarcza wszystkim zadaniom")
		XCTAssertEqual(model.items.map(\.id), [7])
		XCTAssertTrue(model.hasLoaded)
	}

	func testCancelledOwnerDoesNotPublishLateResponse() async {
		let model = PagedFeedViewModel<StubItem>(perPage: 2)
		let gate = FirstPageGate()
		let first = Task { await model.loadIfNeeded(fetchPage: gate.fetch) }
		await fulfillment(of: [gate.started], timeout: 5)
		first.cancel()
		gate.finish(.success(TyfloAPI.WPPage(items: [StubItem(id: 99)], total: nil, totalPages: 1)))
		await first.value
		XCTAssertTrue(model.items.isEmpty, "Spóźniona odpowiedź anulowanego zadania nie zmienia listy")
		XCTAssertFalse(model.hasLoaded)
		XCTAssertFalse(model.isLoading)
		XCTAssertNil(model.errorMessage)
		XCTAssertEqual(gate.requestedPages, [1], "Bez nowego zadania nie ma samoczynnego pobrania")

		await model.loadIfNeeded(fetchPage: gate.fetch)
		XCTAssertEqual(model.items.map(\.id), [20])
		XCTAssertTrue(model.hasLoaded)
		XCTAssertEqual(gate.requestedPages, [1, 1])
	}

	func testAlreadyCancelledRefreshPreservesLoadedStateWithoutRequest() async {
		let model = PagedFeedViewModel<StubItem>(perPage: 2)
		var requests = 0
		let fetch: (Int, Int) async throws -> TyfloAPI.WPPage<StubItem> = { _, _ in
			requests += 1
			return TyfloAPI.WPPage(items: [StubItem(id: requests)], total: nil, totalPages: 1)
		}
		await model.loadIfNeeded(fetchPage: fetch)
		let cancelled = Task {
			withUnsafeCurrentTask { $0?.cancel() }
			await model.refresh(fetchPage: fetch)
		}
		await cancelled.value
		XCTAssertEqual(requests, 1)
		XCTAssertEqual(model.items.map(\.id), [1])
		XCTAssertTrue(model.hasLoaded)
		XCTAssertFalse(model.isLoading)
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
