SAFARI ICON FIXER 0.2.4 — prototyp lokalny

Cel: duże ikony Ulubionych na stronie startowej Safari. Nie dotyczy ikon kart.
Wymagania: macOS 13+; Apple Silicon lub Intel; Apple Command Line Tools.

ZMIANA 0.2.4: stan „W cache” nie jest potwierdzeniem wyświetlania w Safari. Skan odczytuje także download_status_flags i pokazuje diagnostykę pliku. Zaznacz pojedynczą stronę lub kilka stron w wybranym zakresie i wybierz „Napraw zaznaczone” (albo „Wymuś naprawę tej ikony”). Istniejące grafiki są ponownie kodowane do PNG 256 × 256 i przygotowywane do ustawienia flag aktywacji/pobrania na 1 przy zapisie; jeżeli grafiki brakuje, program próbuje ją pobrać. Przygotowanie nie zmienia Safari. Po zamknięciu Safari kliknij Zastosuj i sprawdź efekt. Nie można automatycznie odczytać rzeczywistego renderowania strony startowej z niepublicznego cache. Status pobierania 1 jest konwencją przyjętą w publicznych skryptach naprawczych, nie oficjalną specyfikacją Apple. Nie zmieniamy pozostałych metadanych. Wersja wymaga weryfikacji na macOS.

ZMIANA 0.2.3: podmieniono ikonę na zaakceptowany wariant z szarym tłem, kompasem i limonkową różdżką. Funkcjonalność bez zmian.

ZMIANA 0.2.2: dodano własną ikonę macOS (.icns) do pakietu aplikacji, z zachowaniem kodu Swift z 0.2.1. Sprawdzono strukturę pliku ICNS, przezroczystość, wpis Info.plist oraz skrypt budowania; wyświetlanie w Finderze i Docku wymaga sprawdzenia na macOS.

ZMIANA 0.2.1: rozbito złożone wyrażenia map/sort w skanie oraz filtrowaniu, aby ograniczyć pracę kompilatora Swift. Zachowano zakres folderów i zasady zapisu.

INSTALACJA
1. Rozpakuj ZIP w wybranym folderze.
2. Otwórz Terminal; wpisz „bash ” (ze spacją), przeciągnij plik Zbuduj.command na okno Terminala i naciśnij Enter.
3. Gdy brakuje narzędzi Apple, wykonaj xcode-select --install i po ich instalacji wróć do kroku 2.
4. Skrypt kompiluje aplikację lokalnie z dostarczonego kodu i podpisuje ją podpisem ad hoc. Nie pobiera zależności, nie używa sudo.
5. Finder pokaże aplikację w folderze build. Przenieś ją do Aplikacji i otwórz.
6. Jeśli skan zgłasza brak uprawnień, otwórz Ustawienia systemowe > Prywatność i ochrona > Pełny dostęp do dysku. Dodaj Safari Icon Fixer.app, zakończ aplikację i otwórz ją ponownie. Cofnij uprawnienie, kiedy nie jest potrzebne. Nie wyłączaj SIP ani Gatekeepera.

OBSŁUGA
- Skanuj: tylko zakładki z wewnętrznego folderu BookmarksBar, odczyt bazy i obrazów cache. Foldery służą jako filtry, aplikacja nie modyfikuje ich ikon. Grupowanie według domeny (wspólna ikona dla wielu zakładek tej samej domeny).
- Zakres: domyślnie Bez folderu (wyłącznie linki bezpośrednio w Ulubionych), następnie dowolny folder wraz z podfolderami, konkretny podfolder albo Wszystkie Ulubione. Pobieranie i zapisywanie obejmują tylko wybrany zakres; filtr statusu i wyszukiwarka ograniczają jedynie widok. Przygotowane ikony innych domen pozostają w kolejce. Ikona domeny może być współdzielona poza zakresem, również przez zakładki spoza Ulubionych; nie można zagwarantować rozdzielenia tych ikon. Przywrócenie kopii dotyczy całego Touch Icons Cache, nie wybranego zakresu.
- Pobierz brakujące: pobiera ikony ze stron przez HTTPS (bez pośrednika, ciasteczek Safari i telemetrii); używa domyślnych ścieżek i wybranych linków rel=icon / apple-touch-icon na stronie głównej. Nie podąża poza domenę, z wyjątkiem wariantu z/bez www. Wymaga dostępu do internetu. Istniejącej ikonie nieaktywnej proponuje ponowną aktywację. W tej fazie nie modyfikuje Safari.
- Wybierz własną ikonę: pliki graficzne dekodowane przez ImageIO, konwertowane do PNG 256x256. Nie każdy format (w tym SVG) musi być obsługiwany przez ImageIO. Sprawdź podgląd.
- Zastosuj: zamknij Safari (Cmd+Q), zatwierdź. Wykonana zostaje kopia samego Touch Icons Cache; zapis dotyczy wyłącznie przygotowanych domen. Nie otwieraj Safari podczas zapisu.
- Otwórz Safari i sprawdź, czy ikony rzeczywiście są widoczne. Sam zapis nie gwarantuje efektu w Safari.
- Przywróć kopię: po zamknięciu Safari wybierz katalog kopii z aplikacji. Obecna pamięć ikon zostanie również zachowana. Przywrócenie całego cache usuwa z aktywnego cache późniejsze zmiany ikon, nie zakładki. Kopie przechowywane w ~/Library/Application Support/Safari Icon Fixer/Backups. Można też odzyskać je ręcznie po zamknięciu Safari.

OGRANICZENIA / BEZPIECZEŃSTWO
- Wersja 0.2.1 nie została skompilowana ani przetestowana na macOS. Sprawdzono składnię Swift, skrypt bash i Info.plist w środowisku Linux. Skompilowano i uruchomiono testy indeksu Ulubionych na syntetycznej binarnej plist (Tests/main.swift): zakres bez folderu, wszystkie, zagnieżdżenia, identyczne nazwy folderów, puste foldery, wspólna domena, zakres kolejki i brak standardowego folderu. Nie testowano interfejsu SwiftUI ani zapisu prawdziwego cache Safari. Nie wykonywano zmian na komputerze użytkownika. Pierwszy test zalecany na jednej ikonie, po potwierdzeniu poprawności skanu.
- Safari używa wewnętrznego, niepublicznego formatu, który może się zmienić. Rozpoznawane: TouchIconCacheSettings.db, tabela cache_settings, klucze host i download_status_flags oraz icon_is_in_cache lub touch_icon_is_in_cache, pliki MD5 domeny. Zapis wymaga m.in. dopasowania co najmniej jednej istniejącej aktywnej ikony i jednoznacznego rekordu zmienianej domeny. Nie dodajemy nieznanych wierszy i nie resetujemy całej bazy.
- Ścieżka Safari: ~/Library/Safari. Obsługa niestandardowych profili i niestandardowych folderów Ulubione nie jest potwierdzona.
- Automatyczne przywracanie ikon po nadpisaniu przez Safari, ikony folderów, ikony kart, manifesty web app, zewnętrzne usługi ikon i pełne wsparcie SVG nie należą do tej wersji.
- Brak pełnej atomowości pomiędzy SQLite a systemem plików w przypadku awarii zasilania; pliki są zapisywane atomowo, SQL w transakcji, a rollback jest wykonywany przy zgłoszonym błędzie. W razie awarii użyj kopii.
- Aplikacja nie modyfikuje Bookmarks.plist, historii, haseł i ustawień iCloud. Nie blokuje cache atrybutami chflags, nie wyłącza zabezpieczeń. Safari może ponownie nadpisać ikony.
- Bezpośrednie żądania sieciowe do domen są wysyłane dopiero po kliknięciu Pobierz brakujące. Strony mogą rejestrować żądania jak normalny ruch internetowy.

REFERENCJE TECHNICZNE
Publiczne opisy mechanizmu: https://gist.github.com/dardo82/f7cc7c5c864fb5afa04bb12ecbcf3a9f oraz https://github.com/Franvy/Tabnook. Kod aplikacji jest napisany od podstaw.
