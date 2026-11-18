// The download link remains functional without JS; resolve the latest Apple Silicon DMG when available.
(async () => {
  try {
    const response = await fetch('https://api.github.com/repos/suberb/safari-icon-fixer/releases/latest', {cache:'no-store',credentials:'omit'});
    if (!response.ok) return;
    const data = await response.json();
    if (data.draft || data.prerelease || !/^v\d+\.\d+\.\d+$/.test(data.tag_name)) return;
    const version = data.tag_name.substring(1);
    const filename = `SafariIconFixer-${version}-macOS-arm64.dmg`;
    const expected = `https://github.com/suberb/safari-icon-fixer/releases/download/${data.tag_name}/${filename}`;
    if (!Array.isArray(data.assets) || !data.assets.some(asset => asset.name === filename && asset.browser_download_url === expected)) return;
    document.querySelectorAll('[data-download]').forEach(a => { a.href = expected; });
    document.getElementById('release-label').textContent = `v${version} · Apple Silicon · macOS 13+ · Free`;
  } catch (_) { /* The standard releases link is always available. */ }
})();
// Demo only: never reads bookmarks or contacts Safari.
(() => {
  const root = document.documentElement;
  const theme = document.getElementById('theme');
  const media = window.matchMedia('(prefers-color-scheme: dark)');
  let saved;
  try { saved = localStorage.getItem('sif-site-theme'); } catch (_) {}
  const applyTheme = value => { root.dataset.theme = value; theme.setAttribute('aria-label', value === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'); };
  applyTheme(saved === 'light' || saved === 'dark' ? saved : media.matches ? 'dark' : 'light');
  theme.addEventListener('click', () => { const next = root.dataset.theme === 'dark' ? 'light' : 'dark'; applyTheme(next); saved = next; try { localStorage.setItem('sif-site-theme',next); } catch (_) {} });
  const demo = document.getElementById('demo'), before = document.querySelector('[data-before]'), after = document.querySelector('[data-after]');
  const setRestored = restored => { demo.dataset.restored = String(restored); before.setAttribute('aria-pressed', String(!restored)); after.setAttribute('aria-pressed', String(restored)); document.getElementById('demo-status').textContent = restored ? '✦ Restored' : 'Generic letters'; };
  before.addEventListener('click',()=>setRestored(false)); after.addEventListener('click',()=>setRestored(true));
  const palettes = [...document.querySelectorAll('[data-palette][type="button"]')];
  for (const palette of palettes) palette.addEventListener('click', () => {
    demo.dataset.palette = palette.dataset.palette;
    palettes.forEach(other => other.setAttribute('aria-pressed', String(other === palette)));
    setRestored(true);
  });
  media.addEventListener?.('change', event => { if (!saved) applyTheme(event.matches ? 'dark' : 'light'); });
  const studio = document.getElementById('studio-icon');
  const swatches = [...document.querySelectorAll('.swatch')];
  for (const btn of swatches) btn.addEventListener('click',()=> { studio.style.setProperty('--studio-color',btn.dataset.color); studio.style.setProperty('--studio-ink',btn.dataset.ink); swatches.forEach(other=>other.setAttribute('aria-pressed',String(btn===other))); });
  const range=document.getElementById('logo-size');range.addEventListener('input',()=>{ studio.style.setProperty('--studio-size',range.value+'%'); document.getElementById('size-label').textContent=range.value+'%'; });
})();
