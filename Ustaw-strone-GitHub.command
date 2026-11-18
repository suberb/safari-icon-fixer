#!/bin/bash
set -euo pipefail
cd "$HOME/Documents/GitHub/safari-icon-fixer"
repo=suberb/safari-icon-fixer
[[ "$(gh api user --jq .login)" == suberb ]] || { echo 'Zaloguj się jako suberb: gh auth login'; exit 1; }
# Confirm the published site exists BEFORE enabling Pages or setting a homepage.
gh api "repos/$repo/contents/docs/index.html?ref=main" --silent || { echo 'Najpierw Commit to main oraz Push origin w GitHub Desktop.'; exit 1; }
# Use all 18 agreed relevant topics; preserve any manually added topics up to GitHub's limit.
gh repo edit "$repo" --description 'Fix missing Safari Favorites icons, restore favicons, and customize your Safari start page. Free native macOS app.' --add-topic safari-icon-fixer,safari,safari-icons,safari-favorites,safari-start-page,macos,macos-app,macos-utility,favicon,favicons,apple-touch-icon,bookmark-icons,icon-customization,swift,swiftui,appkit,apple-silicon,mac-app
if gh api "repos/$repo/pages" --silent 2>/dev/null; then
    echo 'GitHub Pages już istnieje; nie zmieniam istniejącej konfiguracji.'
    gh api "repos/$repo/pages" --jq '{html_url,source,build_type}'
    echo 'Sprawdź, czy źródłem jest main /docs. Jeśli nie, ustaw to ręcznie w Settings → Pages.'
else
    gh api -X POST "repos/$repo/pages" -f 'source[branch]=main' -f 'source[path]=/docs' --jq .html_url
fi
gh repo edit "$repo" --homepage 'https://suberb.github.io/safari-icon-fixer/'
echo 'Strona: https://suberb.github.io/safari-icon-fixer/ (GitHub musi najpierw zakończyć wdrożenie).'
open "https://github.com/$repo/settings/pages"
