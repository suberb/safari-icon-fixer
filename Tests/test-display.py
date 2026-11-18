# Exercise the style assignments emitted by the actual Swift helper against a synthetic cache.
import sqlite3, subprocess, tempfile
from pathlib import Path
with tempfile.TemporaryDirectory() as temp:
    main = Path(temp)/'main.swift'
    main.write_text('print(iconDisplayAssignment(.fullTile)); print(iconDisplayAssignment(.systemTile)); print("preserve=" + iconDisplayAssignment(nil))')
    binary = Path(temp)/'test'
    subprocess.run(['swiftc','Localization.swift','IconPixels.swift',str(main),'-o',str(binary)],check=True)
    full, system, preserve = subprocess.check_output([str(binary)],text=True).splitlines()
    assert preserve == 'preserve='
    for flag in ['icon_is_in_cache','touch_icon_is_in_cache']:
        db=sqlite3.connect(':memory:')
        db.execute(f'CREATE TABLE cache_settings(host TEXT, {flag} INT, download_status_flags INT, transparency_analysis_result INT, other TEXT)')
        db.executemany('INSERT INTO cache_settings VALUES(?,?,?,?,?)',[('google.com',1,1,0,'a'),('example.com',1,1,3,'b'),("o'neil.com",1,1,3,'c'),('other.test',0,0,3,'d')]);db.commit()
        for host, assignment in [('google.com',full),("o'neil.com",system),('other.test','')]:
            db.execute(f'UPDATE cache_settings SET {flag}=1, download_status_flags=1{assignment} WHERE host=?',(host,))
        assert list(db.execute('SELECT * FROM cache_settings ORDER BY host'))==[('example.com',1,1,3,'b'),('google.com',1,1,1,'a'),("o'neil.com",1,1,0,'c'),('other.test',1,1,3,'d')]
        db.close()
source=Path('SafariCache.swift').read_text()
assert 'iconDisplayAssignment(pending[host]?.display)' in source
assert 'if !supportsDisplay && pending.values.contains' in source
assert 'if byHost[host]?.existing != item.png' in source
print('OK: scoped style change / preserve unspecified style / both schemas / unchanged PNGs skip write')
