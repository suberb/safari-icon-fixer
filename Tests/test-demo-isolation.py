# Static integration guard; native launching and UI testing remain macOS smoke tests.
from pathlib import Path
s=Path('SafariIconFixer.swift').read_text()
demo=s.split('private struct DemoWorkspace:',1)[1].split('private struct WorkspaceRoot:',1)[0]
model=Path('DemoModel.swift').read_text()
art=Path('DemoArtwork.swift').read_text()
for text in (demo,model,art):
    for forbidden in ('Cache(', 'store.', 'FileManager.', 'URLSession', 'fetchIcon(', 'UserDefaults.', 'NSOpenPanel', 'NSSavePanel', 'IconSearchView('):
        assert forbidden not in text, forbidden
assert 'InlineIconStudio(' in demo and 'demo: true' in demo
assert 'if demoOnly { DemoWorkspace' in s and 'else if completed { MainView() }' in s
assert 'guard !showDemo else { return false }' in s
assert 'if !showDemo { undoDraft() }' in s
assert 'if !showDemo && !busy && iconEditor == nil' in s
print('OK: demo uses in-memory model and editor; live view only opens explicitly, demo blocks live commands')
