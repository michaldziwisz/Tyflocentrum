# CI: self-hosted Mac z fallbackiem na GitHub macOS

Workflow `iOS (unsigned IPA)` jest skonfigurowany tak, żeby:

1) **Domyślnie zbudować** aplikację na **self-hosted runnerze macOS** z etykietą `tyflocentrum`,
2) jeśli build na self-hosted się nie uda, zrobić **fallback na GitHub-hosted `macos-14`**.

Dodatkowo workflow ma opcję `workflow_dispatch` z parametrem `force_github_hosted=true`, żeby ręcznie wymusić build na GitHub-hosted (np. gdy Mac jest offline).

Artefakt jest zawsze pod tą samą nazwą: `Tyflocentrum-unsigned-ipa`.

## Jak dodać self-hosted runner na zdalnym Macu (bez dodawania właściciela do repo)

Właściciel komputera **nie musi mieć dostępu** do repo na GitHubie. Runner łączy się z repo na podstawie tokena generowanego w ustawieniach repo, a checkout robi Actions.

1) Na GitHubie wejdź w repo → **Settings → Actions → Runners → New self-hosted runner**.
2) Wybierz **macOS** i wykonaj komendy instalacji na zdalnym Macu (pobranie `actions-runner`, `./config.sh`, `./run.sh` albo instalacja jako serwis przez `./svc.sh`).
3) Na Macu upewnij się, że jest:
   - Xcode (najlepiej zgodny z CI, obecnie GitHub używa `macos-14`),
   - zaakceptowana licencja (`sudo xcodebuild -license accept`),
   - dostępne narzędzia buildowe (`xcodebuild` w PATH),
   - Homebrew + SwiftFormat (workflow próbuje doinstalować SwiftFormat przez `brew`, jeśli brakuje `swiftformat`).

## Jak to działa w workflow

- Job `Runner health` sprawdza przez GitHub API, czy jest dostępny self-hosted runner z `os == "macos"` oraz `status == "online"` i `busy == false`.
- Jeśli tak: odpala `Build (self-hosted)` na `runs-on: [self-hosted, macOS]`.
- Jeśli nie (albo build się nie uda): odpala `Build (GitHub-hosted)` na `runs-on: macos-14`.

## Wskazówki prywatności / bezpieczeństwa

- Self-hosted runner wykonuje kod z workflowów repo — używaj go tylko dla zaufanych branchy/workflowów (u nas jest trigger na `push` do `master`).
- Kod repo będzie checkoutowany na dysk tego Maca podczas joba, więc właściciel komputera **technicznie może go podejrzeć**, jeśli ma dostęp do systemu plików.
