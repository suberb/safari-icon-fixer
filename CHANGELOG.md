# Historia wersji

## 0.6.5 — Design Refinement
- Native Quick Look for icon graphics (Command-Y; Space when the library has focus on macOS 14+). Compare before/after remains available with Shift-Command-Y.
- Keyboard navigation in the icon library, search (Command-F), rescan (Command-R), hover and drop feedback, clearer selection and VoiceOver values. Animations respect Reduce Motion.
- Color Studio highlights the chosen swatch; all edits still enter the local draft before manual Apply.
- Fix the backup test’s equivalent temporary path spelling on macOS. Includes the unreleased 0.6.4 improvements below.

## 0.6.4 — Performance & Reliability
- Live appearance edits stage automatically; a single undo point per editing session and debounced local draft writes, flushed at normal quit.
- Background Favorites scanning with cancellation and thumbnail-only cache validation; cancel bulk icon downloads without discarding completed work.
- Backup manager with dates, logical sizes, restore and confirmed Trash action; newest valid backup is protected.

## 0.6.3 — Icon Protection
- Locally protect applied custom icon artwork and display style independently of Safari; detect changes on scans and stage restoration for review.
- Complete cache backups now include matching personalization metadata; older backups retain the existing protected collection.
- Legacy digest registry migration only imports matching artwork. No automatic Safari writes.

## 0.6.2 — Clean inspector
- One live icon preview, compact appearance controls, advanced Safari style disclosure, contextual actions and a clear staged-change indicator.
- Infer the initial logo margin and display style from the current icon; no automatic cache writes.

## 0.6.1 — Refined identity
- New graphite and amethyst app icon, refreshed product website and marketing graphics.
- Live Safari open/closed status, Cmd-Q guidance and preflight checks before applying, resetting or restoring icons.
- All six interface languages; existing cache safeguards and signed Sparkle pipeline retained.

## 0.6.0 — Amethyst
- Resizable, hideable sidebar and inspector; visual icon library with modifier selection, smart filters and remembered layout preferences.
- Inline Color Studio, batch presets, file/image drag and drop, simulated Safari preview, individual icon history from local backups and one-step undo of staged changes.
- Local staged-icon recovery with cache digest validation; signed Sparkle pipeline remains unchanged. Product site in docs/, plus a GitHub Pages and topics setup command.

## 0.5.0
Sparkle 2.10.1: signed updates, optional automatic installation, and automatic checks at launch.

## 0.4.2
Clearer repair, customization and restore-default actions in all six languages. Preserve cached PNG bytes and existing display style when repairing; keep prepared changes.

## 0.4.1
Styled purple DMG with real Applications shortcut, installation instructions and launch-time update checks (manual installation).

## 0.4.0
Sześć języków interfejsu (EN/DE/FR/UK/PL/ES), wybór automatyczny i ręczny, testy lokalizacji, nowy README produktu i grafiki poglądowe.

## 0.3.3
Instalator DMG dla Apple Silicon, instalacja przez przeciągnięcie do Applications, aktualizator preferuje DMG (obsługuje starsze ZIP), publikacja nowych wersji z main po testach.

## 0.3.2
O aplikacji (Ana × ChatGPT), sprawdzanie GitHub Releases, wersjonowanie Git, test aktualizatora, GitHub Actions i paczki do pobrania.

## 0.3.1
Pełny kafelek Safari; zmiana trybu wyświetlania cache.

## 0.3.0
Nowy interfejs biblioteki i edytora.

## 0.2.9
Reset ikon i poprawki importu Google Grafika.

## 0.2.8
Osadzona Google Grafika, niezależne skalowanie logo i tła, kolor z ikony.

## 0.2.7
Fioletowa ikona, wyszukiwanie, edycja tła.

## 0.2.6
Dialog uprawnień.

## 0.2.5
Poprawiony rozmiar ikony i okno.

## 0.2.4
Wymuszona naprawa i diagnostyka cache.

## 0.2.3 – 0.2.1
Ikona aplikacji i poprawki kompilatora.

## 0.2 / 0.1
Zakres folderów i pierwszy prototyp.

Szczegóły wcześniejszych wersji: README.txt. Tagi historii odtworzono z faktycznych archiwów źródłowych, nie z oryginalnych commitów.
