#!/bin/bash
# Publishes the prepared, versioned code using the user's own GitHub CLI account.
set -euo pipefail
cd "$(dirname "$0")"
repo='suberb/safari-icon-fixer'
[[ "$(uname -s)" == Darwin ]] || { echo 'Uruchom na swoim Macu.'; exit 1; }
if ! command -v gh >/dev/null; then
  echo 'Zainstaluj GitHub CLI: brew install gh (lub https://cli.github.com/). Następnie uruchom ten skrypt ponownie.'
  exit 1
fi
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  gh auth login --hostname github.com --web --git-protocol https --scopes workflow
fi
login=$(gh api user --hostname github.com --jq .login)
[[ "$login" == suberb ]] || { echo "Zalogowano jako $login, a oczekiwane konto to suberb. Przełącz konto w gh auth switch."; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Niepoprawna wersja w Info.plist.'; exit 1; }
tag="v$version"
# The bundle contains reconstructed commits, not user data or credentials.
if [[ ! -d .git ]]; then
  [[ -f history.bundle ]] || { echo 'Brak historii Git. Sklonuj repozytorium zamiast publikować ZIP.'; exit 1; }
  git init -b main
  git bundle verify history.bundle
  git fetch --tags history.bundle refs/heads/main:refs/remotes/import/main
  git reset --mixed refs/remotes/import/main
  git config core.filemode false
fi
[[ -z "$(git status --porcelain)" ]] || { echo 'Są niezapisane zmiany. Zweryfikuj git status; skrypt ich nie opublikuje automatycznie.'; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "$tag^{commit}")" ]] || { echo "HEAD nie odpowiada tagowi $tag. Przerwano."; exit 1; }
# Do not expose code publicly without explicit consent.
if visibility=$(gh repo view "$repo" --json visibility --jq .visibility 2>/dev/null); then
  echo "Repozytorium istnieje: $repo ($visibility). Jego widoczność nie zostanie zmieniona."
  read -r -p 'Wpisz PUBLIKUJ, aby przesłać kod do istniejącego repozytorium: ' consent
  [[ "$consent" == PUBLIKUJ ]] || exit 0
else
  echo 'PUBLICZNE: każdy może zobaczyć kod i pobrać program, automatyczne aktualizacje działają bez logowania.'
  echo 'PRYWATNE: kod dostępny tylko uprawnionym; aplikacja kieruje do wydań po zalogowaniu. Actions może zużywać minuty planu.'
  read -r -p 'Wpisz PUBLICZNE lub PRYWATNE (Enter = anuluj): ' visibility_choice
  case "$visibility_choice" in
    PUBLICZNE) gh repo create "$repo" --public --description 'Safari Icon Fixer for macOS — Ana × ChatGPT';;
    PRYWATNE) gh repo create "$repo" --private --description 'Safari Icon Fixer for macOS — Ana × ChatGPT';;
    *) exit 0;;
  esac
fi
remote="https://github.com/$repo.git"
if git remote get-url origin >/dev/null 2>&1; then
  [[ "$(git remote get-url origin)" == "$remote" ]] || { echo 'Inny remote origin — przerwano bez nadpisywania.'; exit 1; }
else
  git remote add origin "$remote"
fi
# Use gh credentials without storing a token in project files or changing global git config.
gitgh() { git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"; }
echo 'W razie błędu dostępu do .github/workflows nadaj zakres workflow: gh auth refresh -h github.com -s workflow, a następnie ponów.'
gitgh push -u origin HEAD:refs/heads/main
# Send historical tags separately from the new tag; GitHub can suppress events for bulk tag pushes.
oldtags=()
while IFS= read -r t; do
  [[ "$t" == "$tag" ]] || oldtags+=("refs/tags/$t")
done < <(git tag --list 'v*')
if (( ${#oldtags[@]} )); then gitgh push origin "${oldtags[@]}"; fi
gitgh push origin "refs/tags/$tag"
echo "Kod i tag przesłane: https://github.com/$repo"
echo "Status kompilacji: https://github.com/$repo/actions"
echo "Wydanie po udanych testach: https://github.com/$repo/releases"
echo 'Jeśli tag został już wcześniej przesłany, sprawdź Actions i ponów nieudany workflow ręcznie. Skrypt nie nadpisuje tagów ani historii.'
open "https://github.com/$repo/actions"
