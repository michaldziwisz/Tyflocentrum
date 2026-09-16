//
//  StrategiaOdswiezania.swift
//  Tyflocentrum
//
//  Decyzja „czy odświeżyć listę po powrocie aplikacji do pierwszego planu”.
//

import Foundation

/// Powód, dla którego pytamy o odświeżenie. Rozróżnienie jest istotne, bo
/// wymagania są różne: automat MUSI oszczędzać baterię, a ręczne żądanie
/// użytkownika ma zadziałać ZAWSZE i natychmiast.
enum PowodOdswiezenia {
	/// Aplikacja wróciła do pierwszego planu (scenePhase → .active).
	case powrotZTla
	/// Użytkownik wszedł na ekran, który był już wcześniej wypełniony danymi.
	case wejscieNaEkran
	/// Jawne żądanie: pull-to-refresh albo przycisk „Odśwież”.
	case zadanieUzytkownika
}

/// Czysta, bezstanowa reguła progowa — świadomie wydzielona z widoków, bo
/// „kiedy wolno pobrać” jest logiką biznesową, a nie szczegółem SwiftUI, i musi
/// dać się zmierzyć testem jednostkowym bez uruchamiania interfejsu.
///
/// DLACZEGO PRÓG LICZYMY OD DWÓCH ZNACZNIKÓW, NIE OD JEDNEGO. Pierwsza wersja
/// tej reguły patrzyła wyłącznie na wiek ostatniego UDANEGO pobrania. To wygląda
/// poprawnie i jest pułapką: przy martwej sieci znacznik sukcesu nigdy się nie
/// odświeża, więc KAŻDY powrót do aplikacji wystrzeliwał kolejne żądanie, które
/// dobijało do timeoutu. Czyli reguła mająca chronić baterię zamieniała słaby
/// zasięg w pętlę nieudanych połączeń — dokładnie odwrotnie do celu.
///
/// Dlatego decyzja bierze pod uwagę też czas ostatniej PRÓBY (udanej lub nie)
/// i po nieudanej próbie odczekuje `progPoBledzie`, zanim pozwoli na następną.
/// Żądanie użytkownika omija oba progi: skoro człowiek sam nacisnął, czekanie
/// byłoby wyłącznie szkodą.
struct StrategiaOdswiezania {
	/// Minimalny wiek danych, przy którym automat sięga do sieci.
	///
	/// 120 sekund to kompromis: krótkie przełączenie do innej aplikacji (odczyt
	/// kodu 2FA, odpisanie na wiadomość) nie generuje ruchu, a treści w tych
	/// serwisach pojawiają się w odstępach godzinowych, więc dwie minuty
	/// opóźnienia są dla użytkownika niewidoczne.
	static let progSwiezosci: TimeInterval = 120

	/// Karencja po nieudanej próbie — chroni przed pętlą żądań przy słabej sieci.
	static let progPoBledzie: TimeInterval = 30

	var progSwiezosci: TimeInterval = StrategiaOdswiezania.progSwiezosci
	var progPoBledzie: TimeInterval = StrategiaOdswiezania.progPoBledzie

	/// - Parameters:
	///   - powod: skąd przyszło pytanie.
	///   - ostatniSukces: kiedy ostatnio udało się pobrać dane; `nil` = nigdy.
	///   - ostatniaProba: kiedy ostatnio cokolwiek próbowaliśmy; `nil` = nigdy.
	///   - trwaPobieranie: czy w tej chwili leci już żądanie.
	///   - teraz: wstrzykiwany zegar, żeby test nie musiał czekać w realnym czasie.
	func czyOdswiezyc(
		powod: PowodOdswiezenia,
		ostatniSukces: Date?,
		ostatniaProba: Date?,
		trwaPobieranie: Bool,
		teraz: Date = Date()
	) -> Bool {
		// Drugie równoległe żądanie nie doda żadnej informacji, a na pewno
		// zapłaci za nią baterią i ryzykiem wyścigu o stan listy.
		if trwaPobieranie {
			return false
		}

		// Człowiek nacisnął — żadne progi go nie dotyczą.
		if powod == .zadanieUzytkownika {
			return true
		}

		// Pusto: nigdy nie udało się nic pobrać. Wtedy jedynym ogranicznikiem
		// jest karencja po błędzie, bo bez niej ekran bez sieci bombardowałby
		// serwer przy każdym powrocie.
		guard let ostatniSukces else {
			guard let ostatniaProba else { return true }
			return teraz.timeIntervalSince(ostatniaProba) >= progPoBledzie
		}

		// Dane są świeże — nie ruszamy sieci, niezależnie od liczby powrotów.
		guard teraz.timeIntervalSince(ostatniSukces) >= progSwiezosci else {
			return false
		}

		// Dane są stare, ale ostatnia próba mogła właśnie polec. Odczekaj.
		if let ostatniaProba, teraz.timeIntervalSince(ostatniaProba) < progPoBledzie {
			return false
		}

		return true
	}
}

/// Znaczniki czasu jednego strumienia danych. Trzymane osobno od modelu widoku,
/// żeby ta sama para pól obsłużyła listę Nowości i listy kategorii bez kopiowania
/// logiki progowej do każdej z nich.
struct StanSwiezosci {
	private(set) var ostatniSukces: Date?
	private(set) var ostatniaProba: Date?

	mutating func zanotujProbe(teraz: Date = Date()) {
		ostatniaProba = teraz
	}

	mutating func zanotujSukces(teraz: Date = Date()) {
		ostatniSukces = teraz
		ostatniaProba = teraz
	}

	/// Wiek danych — do etykiet diagnostycznych i testów.
	func wiekDanych(teraz: Date = Date()) -> TimeInterval? {
		guard let ostatniSukces else { return nil }
		return teraz.timeIntervalSince(ostatniSukces)
	}
}
