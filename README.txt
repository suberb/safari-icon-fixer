SAFARI ICON FIXER 0.1 — prototyp lokalny

Cel: duże ikony Ulubionych na stronie startowej Safari. Nie dotyczy ikon kart.
Wymagania: macOS 13+; Apple Silicon lub Intel; Apple Command Line Tools.

INSTALACJA
1. Rozpakuj ZIP w wybranym folderze.
2. Otwórz Terminal; wpisz „bash ” (ze spacją), przeciągnij plik Zbuduj.command na okno Terminala i naciśnij Enter.
3. Gdy brakuje narzędzi Apple, wykonaj xcode-select --install i po ich instalacji wróć do kroku 2.
4. Skrypt kompiluje aplikację lokalnie z dostarczonego kodu i podpisuje ją podpisem ad hoc. Nie pobiera zależności, nie używa sudo.
5. Finder pokaże aplikację w folderze build. Przenieś ją do Aplikacji i otwórz.
6. Jeśli skan zgłasza brak uprawnień, otwórz Ustawienia systemowe > Prywatność i ochrona > Pełny dostęp do dysku. Dodaj Safari Icon Fixer.app, zakończ aplikację i otwórz ją ponownie. Cofnij uprawnienie, kiedy nie jest potrzebne. Nie wyłączaj SIP ani Gatekeepera.

OBSŁUGA
- Skanuj: odczyt zakładek z wewnętrznego folderu BookmarksBar, odczyt bazy i obrazów cache. Grupowanie według domeny (wspólna ikona dla wielu zakładek tej samej domeny).
- Pobierz brakujące: pobiera ikony ze stron przez HTTPS (bez pośrednika, ciasteczek Safari i telemetrii); używa domyślnych ścieżek i wybranych linków rel=icon / apple-touch-icon na stronie głównej. Nie podąża poza domenę, z wyjątkiem wariantu z/bez www. Wymaga dostępu do internetu. Istniejącej ikonie nieaktywnej proponuje ponowną aktywację. W tej fazie nie modyfikuje Safari.
- Wybierz własną ikonę: pliki graficzne dekodowane przez ImageIO, konwertowane do PNG 256x256. Nie każdy format (w tym SVG) musi być obsługiwany przez ImageIO. Sprawdź podgląd.
- Zastosuj: zamknij Safari (Cmd+Q), zatwierdź. Wykonana zostaje kopia samego Touch Icons Cache; zapis dotyczy wyłącznie przygotowanych domen. Nie otwieraj Safari podczas zapisu.
- Otwórz Safari i sprawdź, czy ikony rzeczywiście są widoczne. Sam zapis nie gwarantuje efektu w Safari.
- Przywróć kopię: po zamknięciu Safari wybierz katalog kopii z aplikacji. Obecna pamięć ikon zostanie również zachowana. Przywrócenie całego cache usuwa z aktywnego cache późniejsze zmiany ikon, nie zakładki. Kopie przechowywane w ~/Library/Application Support/Safari Icon Fixer/Backups. Można też odzyskać je ręcznie po zamknięciu Safari.

OGRANICZENIA / BEZPIECZEŃSTWO
- Wersja 0.1 nie została skompilowana ani przetestowana na macOS. Sprawdzono składnię Swift, skrypt bash i Info.plist w środowisku Linux. Nie wykonywano zmian na komputerze użytkownika. Pierwszy test zalecany na jednej ikonie, po potwierdzeniu poprawności skanu.
- Safari używa wewnętrznego, niepublicznego formatu, który może się zmienić. Rozpoznawane: TouchIconCacheSettings.db, tabela cache_settings, klucze host i download_status_flags oraz icon_is_in_cache lub touch_icon_is_in_cache, pliki MD5 domeny. Zapis wymaga m.in. dopasowania co najmniej jednej istniejącej aktywnej ikony i jednoznacznego rekordu zmienianej domeny. Nie dodajemy nieznanych wierszy i nie resetujemy całej bazy.
- Ścieżka Safari: ~/Library/Safari. Obsługa niestandardowych profili i niestandardowych folderów Ulubione nie jest potwierdzona.
- Automatyczne przywracanie ikon po nadpisaniu przez Safari, ikony folderów, ikony kart, manifesty web app, zewnętrzne usługi ikon i pełne wsparcie SVG nie należą do tej wersji.
- Brak pełnej atomowości pomiędzy SQLite a systemem plików w przypadku awarii zasilania; pliki są zapisywane atomowo, SQL w transakcji, a rollback jest wykonywany przy zgłoszonym błędzie. W razie awarii użyj kopii.
- Aplikacja nie modyfikuje Bookmarks.plist, historii, haseł i ustawień iCloud. Nie blokuje cache atrybutami chflags, nie wyłącza zabezpieczeń. Safari może ponownie nadpisać ikony.
- Bezpośrednie żądania sieciowe do domen są wysyłane dopiero po kliknięciu Pobierz brakujące. Strony mogą rejestrować żądania jak normalny ruch internetowy.

REFERENCJE TECHNICZNE
Publiczne opisy mechanizmu: https://gist.github.com/dardo82/f7cc7c5c864fb5afa04bb12ecbcf3a9f oraz https://github.com/Franvy/Tabnook. Kod aplikacji jest napisany od podstaw.
