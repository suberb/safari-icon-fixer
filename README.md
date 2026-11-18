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

Menu aplikacji → Sprawdź aktualizacje, lub O aplikacji. Automatyczne sprawdzanie można wyłączyć. Publiczne wydania nie wymagają tokena. Prywatne wydania są dostępne przez stronę GitHub po zalogowaniu; aplikacja nie przechowuje hasła ani tokena, więc nie sprawdza ich automatycznie. Nowy DMG (lub ZIP ze starszych wydań) jest pobierany w przeglądarce, instalacja jest ręczna.

## Rozwijanie

Szczegóły i historia funkcji: [README.txt](README.txt), [CHANGELOG.md](CHANGELOG.md). Wersja pochodzi z Info.plist. `bash Testuj-renderowanie.command` uruchamia testy grafiki na Macu. Workflow GitHub Actions kompiluje na Apple Silicon po pushu. Nowa wersja Info.plist na main jest publikowana po przejściu testów; można także użyć tagu zgodnego z Info.plist albo ręcznie uruchomić workflow z opcją publish. Istniejące tagi i wydania nie są nadpisywane. Prywatne repozytoria mogą zużywać płatne minuty Actions; przed publikacją sprawdź limit na koncie.

## Prywatność

Brak telemetrii. Żądania wysyłane są podczas wyszukiwania/pobierania ikon i sprawdzania aktualizacji. Repozytorium nie zawiera prawdziwych zakładek, danych Safari ani tokenów. Dane i cache pozostają na komputerze. Szczegóły w README.txt.
