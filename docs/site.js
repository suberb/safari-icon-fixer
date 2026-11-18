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
