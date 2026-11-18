# Safari Icon Fixer

**Ana × ChatGPT** · macOS · Bez abonamentu.

Naprawa i personalizacja ikon Ulubionych Safari — wybór folderów, wyszukiwanie, własne tło, skalowanie logo, reset, kopie zapasowe. Nie modyfikuje zakładek, haseł ani historii Safari.

## Instalacja

- [Wydania i pobieranie](https://github.com/suberb/safari-icon-fixer/releases): pobierz instalator `.dmg` dla Apple Silicon, otwórz go i przeciągnij aplikację do Applications (Aplikacje). Kod źródłowy pozostaje dostępny przez GitHub.
- Wersję źródłową kompiluj na Macu: `bash Zbuduj.command` (Apple Command Line Tools). Przenieś plik .app do Aplikacji.
- W razie potrzeby nadaj pełny dostęp do dysku w ustawieniach macOS.
- Przed zapisem/resetem ikon zamknij Safari. Program tworzy lokalne kopie cache.

Aplikacja jest podpisywana ad hoc, nie notaryzowana. Używa niepublicznego formatu cache Safari; działanie po aktualizacji Safari nie jest gwarantowane. Nie wyłączaj SIP ani Gatekeepera.

## Aktualizacje

Od 0.5.0 aplikacja korzysta ze Sparkle 2.10.1. Menu aplikacji → Sprawdź aktualizacje, lub O aplikacji. Automatyczne sprawdzanie jest domyślnie włączone; automatyczne pobieranie i instalacja wymagają świadomego włączenia w ustawieniach. Sparkle weryfikuje podpis EdDSA zarówno instalatora DMG, jak i appcast.xml. Podpisy nie zastępują notaryzacji Apple. Pierwsza instalacja 0.5.0 wymaga DMG. Przed aktualizacją zastosuj przygotowane ikony, ponieważ niezapisana kolejka jest w pamięci. W razie problemów z aktualizacją pobierz DMG ręcznie. Nowe wydania podpisuje wyłącznie GitHub Actions ze stabilnej gałęzi main przy użyciu sekretu SPARKLE_PRIVATE_KEY; prywatny klucz nigdy nie trafia do projektu.

## Rozwijanie

Szczegóły i historia funkcji: [README.txt](../README.txt), [CHANGELOG.md](../CHANGELOG.md). Wersja pochodzi z Info.plist. `bash Testuj-renderowanie.command` uruchamia testy grafiki na Macu. Workflow GitHub Actions kompiluje na Apple Silicon po pushu. Nowa wersja Info.plist na main jest publikowana po przejściu testów; ręcznie można też uruchomić workflow z opcją publish na main. Tagi i PR nie otrzymują klucza prywatnego. Istniejące tagi i wydania nie są nadpisywane. Prywatne repozytoria mogą zużywać płatne minuty Actions; przed publikacją sprawdź limit na koncie.

## Prywatność

Brak telemetrii. Żądania wysyłane są podczas wyszukiwania/pobierania ikon i sprawdzania aktualizacji. Repozytorium nie zawiera prawdziwych zakładek, danych Safari ani tokenów. Dane i cache pozostają na komputerze. Szczegóły w README.txt.
