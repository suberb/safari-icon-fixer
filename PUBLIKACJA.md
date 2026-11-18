# Pierwsza publikacja na GitHubie

Repozytorium docelowe: `suberb/safari-icon-fixer`. Przed publikacją wybierz widoczność. Wersje automatycznie wykrywane bez klucza API wymagają publicznych wydań. Publiczne repo ujawnia kod; prywatne wydania wymagają zalogowania w przeglądarce i nie są wykrywane automatycznie. Aplikacja nigdy nie prosi o token.

1. Rozpakuj paczkę 0.3.2. Zbuduj aplikację `bash Zbuduj.command` i sprawdź okno O aplikacji.
2. Jeśli nie masz narzędzia GitHub CLI, zainstaluj je `brew install gh` lub z https://cli.github.com/.
3. W Terminalu wpisz `bash ` i przeciągnij `Opublikuj.command`. Zaloguj się na konto `suberb` w oficjalnym oknie GitHub, jeśli skrypt tego wymaga. Wybierz PUBLICZNE albo PRYWATNE. W przypadku braku zakresu workflow: `gh auth refresh -h github.com -s workflow`, potem ponów skrypt.
4. Sprawdź zakładkę Actions. Po udanej kompilacji i testach tag `v0.3.2` uruchamia release ze skompilowaną aplikacją Apple Silicon, ZIP źródeł i SHA256SUMS. Jeżeli workflow nie działa, sprawdź dostępność Actions, limity i logi. Prywatne repo może zużywać płatne minuty. Paczka aplikacji jest podpisana ad hoc i nie jest notaryzowana.

Plik history.bundle zawiera rzeczywiste zachowane snapshoty od 0.1 do 0.3.2, z odtworzonymi commitami i tagami (nie jest to pierwotna historia Git). Skrypt nie wymusza push, nie zmienia widoczności istniejącego repozytorium, nie zapisuje tokenów. Repozytorium nie zawiera zakładek, cache, ustawień ani zrzutów ekranu. Przed upublicznieniem możesz obejrzeć kod.

## Kolejne wydania (od 0.3.3)

Zwiększ wersję i numer kompilacji w Info.plist, zaktualizuj RELEASE.md i CHANGELOG.md, uruchom testy i wypchnij commit na main. GitHub Actions po udanych testach zbuduje DMG dla Apple Silicon, zweryfikuje obraz i opublikuje wydanie z SHA256SUMS. Ręcznie można też wysłać tag `vX.Y.Z` zgodny z Info.plist lub uruchomić workflow z opcją publish na main. Istniejące tagi i wydania nie są nadpisywane. GitHub dodaje własne archiwa źródłowe automatycznie. Dla dystrybucji publicznej zalecany jest Developer ID i notaryzacja Apple; nie zostały skonfigurowane.

## Sparkle (od 0.5.0)

Publikacja podpisanego DMG i appcast.xml odbywa się wyłącznie z zaufanego main. Wymagany GitHub Actions secret SPARKLE_PRIVATE_KEY, zgodny z SUPublicEDKey w Info.plist. Nie umieszczaj prywatnego klucza w repozytorium ani w logach. Skrypt sprawdza podpis DMG niezależnie z publicznym kluczem przed publikacją. Kopię prywatnego klucza przechowuj bezpiecznie poza GitHub. Nie zmieniaj klucza publicznego bez planu migracji. Nie publikuj nowszych wydań bez appcast.xml.
