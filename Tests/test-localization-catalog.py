import json, re
from pathlib import Path
catalog=json.loads(Path('Resources/Translations.json').read_text())
keys=set(catalog['pl'])
assert set(catalog)=={'en','de','fr','uk','pl','es'}
for language, entries in catalog.items():
    assert set(entries)==keys
    for key,value in entries.items():
        assert value and set(re.findall(r'\{\d+\}',key))==set(re.findall(r'\{\d+\}',value)), (language,key)
for p in Path('.').glob('*.swift'):
    for raw in re.findall(r'l10n\(("(?:[^"\\]|\\.)*")',p.read_text()):
        key=json.loads(raw)
        assert key in keys,(p,key)
print(f'OK: {len(keys)} translation keys, 6 locales, placeholders and source coverage')
