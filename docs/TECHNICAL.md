# Safari Icon Fixer

**hempbiscuit & the machine** · macOS · Bez abonamentu.

Naprawa i personalizacja ikon Ulubionych Safari — wybór folderów, wyszukiwanie, własne tło, skalowanie logo, reset, kopie zapasowe. Nie modyfikuje zakładek, haseł ani historii Safari.

## Instalacja

- [Wydania i pobieranie](https://github.com/suberb/safari-icon-fixer/releases): pobierz instalator `.dmg` dla Apple Silicon, otwórz go i przeciągnij aplikację do Applications (Aplikacje). Kod źródłowy pozostaje dostępny przez GitHub.
- Wersję źródłową kompiluj na Macu: `bash Build.command` (Apple Command Line Tools). Przenieś plik .app do Aplikacji.
- W razie potrzeby nadaj pełny dostęp do dysku w ustawieniach macOS.
- Przed zapisem/resetem ikon zamknij Safari. Program tworzy lokalne kopie cache.

Aplikacja jest podpisywana ad hoc, nie notaryzowana. Używa niepublicznego formatu cache Safari; działanie po aktualizacji Safari nie jest gwarantowane. Nie wyłączaj SIP ani Gatekeepera.

## Aktualizacje

Od 0.5.0 aplikacja korzysta ze Sparkle 2.10.1. Menu aplikacji → Sprawdź aktualizacje, lub O aplikacji. Automatyczne sprawdzanie jest domyślnie włączone; automatyczne pobieranie i instalacja wymagają świadomego włączenia w ustawieniach. Sparkle weryfikuje podpis EdDSA zarówno instalatora DMG, jak i appcast.xml. Podpisy nie zastępują notaryzacji Apple. Pierwsza instalacja 0.5.0 wymaga DMG. Przed aktualizacją najlepiej zastosować przygotowane ikony. Od 0.6.0 kolejka jest lokalnie zapisywana jako PreparedIcons.json i przy następnym odczycie Safari przywracana tylko dla domen o pasującym skrócie grafiki. Nie jest to gwarancja odzyskania po awarii; niedopasowane wpisy są pomijane. Podczas pracy z anomaliami cache zachowaj kopie zapasowe. W razie problemów z aktualizacją pobierz DMG ręcznie. Nowe wydania podpisuje wyłącznie GitHub Actions ze stabilnej gałęzi main przy użyciu sekretu SPARKLE_PRIVATE_KEY; prywatny klucz nigdy nie trafia do projektu.

## Rozwijanie

Szczegóły i historia funkcji: [README.txt](../README.txt), [CHANGELOG.md](../CHANGELOG.md). Wersja pochodzi z Info.plist. `bash TestRendering.command` uruchamia testy grafiki na Macu. Workflow GitHub Actions kompiluje na Apple Silicon po pushu. Nowa wersja Info.plist na main jest publikowana po przejściu testów; ręcznie można też uruchomić workflow z opcją publish na main. Tagi i PR nie otrzymują klucza prywatnego. Istniejące tagi i wydania nie są nadpisywane. Prywatne repozytoria mogą zużywać płatne minuty Actions; przed publikacją sprawdź limit na koncie.

## Prywatność

Brak telemetrii. Żądania wysyłane są podczas wyszukiwania/pobierania ikon i sprawdzania aktualizacji. Repozytorium nie zawiera prawdziwych zakładek, danych Safari ani tokenów. Dane i cache pozostają na komputerze. Szczegóły w README.txt.

## Amethyst 0.6.0

⌘/⇧: zaznaczanie; ⌘⇧A: zaznacz widoczne; ⌘Y: porównanie wybranej ikony; ⌘⌥Z: cofnij ostatni krok kolejki. Podgląd Safari jest symulacją w kolejności biblioteki. Szybka naprawa przygotowuje wykryte brakujące lub nieaktywne ikony, nie wykrywa rzeczywistego wyświetlania. Color Studio pomija złożone tła w operacji zbiorczej. Historia pokazuje unikatowe obrazy z do 40 najnowszych lokalnych kopii; przywrócenie obrazu jest przygotowywane w kolejce, a nie wykonywane bezpośrednio. Przeciąganie obsługuje pliki lokalne i kompatybilne reprezentacje obrazu (nie każde źródło internetowe). Projekt strony w docs/index.html, uruchomienie Pages po publikacji przez ConfigureGitHubPages.command.

### Color Studio+ i kolekcje ikon (0.6.6)
Inteligentne tło porównuje jasność nieprzezroczystych pikseli wydzielonego znaku z jasnymi i ciemnymi tłami; to heurystyka, nie gwarancja kontrastu dla każdego fragmentu. Soft Brand pozostawia osobny mechanizm rozjaśniania o 30–50%. Motyw można przygotować dla zaznaczonych lub widocznych ikon (złożone tła są pomijane); zmiany trafiają do szkicu.

Kolekcja JSON w wersji formatu 1 zawiera tylko domenę, PNG (normalizowane przy eksporcie i imporcie) oraz opcjonalny styl Safari. Eksport obejmuje zapisane chronione ikony w zaznaczeniu albo bieżącym zakresie, nie historię, tytuły ani foldery zakładek. Domeny mogą ujawniać zainteresowania: udostępniaj plik tylko świadomie. Limit 500 ikon i 64 MB pliku; obrazy wejściowe muszą mieć prawidłowy nagłówek PNG, maks. 1024 × 1024 i 8 MB na ikonę. Import nie dodaje zakładek, nie pobiera ikon z sieci, pomija niedopasowane domeny i istniejące szkice. Przed zapisem wymagany jest zwykły krok Zastosuj przy zamkniętym Safari.

## Demo Mode (0.7.0)

`WorkspaceRoot` selects an isolated `DemoWorkspace` before constructing `MainView` when launched with `--demo` or before the user chooses to open real Favorites. `DemoSession` holds sample state only in memory, while the shared `InlineIconStudio` supplies the real image renderer. No Safari access, cache operations, file imports, web searches or actual writes are available in this workspace. In an already opened live session, the demo sheet does not operate on the live library. Closing it discards demo edits.

For native promotional captures see [CAPTURE.md](CAPTURE.md). Website illustrations are not native screenshots.

## Recovery and compatibility (0.7.1)

Before apply, reset or restore, the cache engine creates a complete snapshot, checks its SQLite layout and `quick_check`, verifies protected icon digests, synchronizes files and records the snapshot UUID in `RecoveryJournal.json`. An exclusive process lock prevents concurrent application transactions. The marker is removed only after the resulting cache and personalization files are synchronized. This is a crash-recovery protocol, not a hardware power-loss guarantee. It does not lock out Safari itself.

If a marker remains, rescanning prompts for explicit recovery with Safari closed. The pre-operation snapshot is kept; any displaced cache is preserved under `RecoveryArtifacts`. Other cache writes and backup deletion are blocked while recovery is pending. Recovery may revert later cache changes, not bookmarks. A second interruption leaves the marker available for another attempt. Corrupt journals, incompatible readable schemas and invalid snapshots fail closed; do not remove the marker or backups merely to bypass an error.

The recognized layouts use exactly one of `icon_is_in_cache` or `touch_icon_is_in_cache`, plus `host` and `download_status_flags`, with or without `transparency_analysis_result`. Normal full restore requires matching SQLite schema and user version as well as integrity checks. Older snapshots without personalization metadata retain the current protected collection; newer snapshots restore matching metadata. Unknown or ambiguous layouts are blocked, not guessed.

CI tests the four synthetic layouts, malformed schemas, legacy and modern snapshots, interrupted operations, and repeated recovery. `Tests/CacheIntegration/main.swift` exercises the production cache engine against temporary synthetic directories only, including abrupt child process exit. A successful fixture run does not establish compatibility with particular installed Safari releases. Record actual macOS and Safari versions and use a disposable macOS user profile for manual apply/reset/restore testing before declaring broader compatibility.

The source is organized into `SafariCache.swift`, `CacheRecovery.swift`, `CacheModels.swift`, `IconImageSupport.swift`, and the existing SwiftUI workspace. Build scripts now use English names.
