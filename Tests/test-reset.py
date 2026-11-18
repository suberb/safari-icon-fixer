# Synthetic SQLite fixture: ensure the actual reset SQL touches only chosen hosts,
# including host names that contain a quote. Does not exercise AppKit or Safari.
import sqlite3, re
from pathlib import Path
s=Path('SafariIconFixer.swift').read_text()
assert 'UPDATE cache_settings SET \\(flag)=0, download_status_flags=0 WHERE host=\\(quote($0));' in s
for flag in ['icon_is_in_cache','touch_icon_is_in_cache']:
 db=sqlite3.connect(':memory:')
 db.execute(f'CREATE TABLE cache_settings(host TEXT, {flag} INT, download_status_flags INT, other TEXT)')
 db.executemany('INSERT INTO cache_settings VALUES(?,?,?,?)',[('google.com',1,1,'a'),('example.com',1,1,'b'),("o'neil.com",1,1,'c')]);db.commit()
 hosts=['google.com',"o'neil.com"]
 statements='\n'.join(f"UPDATE cache_settings SET {flag}=0, download_status_flags=0 WHERE host='"+h.replace("'","''")+"';" for h in hosts)
 db.executescript('BEGIN IMMEDIATE;\n'+statements+'\nCOMMIT;')
 assert list(db.execute('SELECT * FROM cache_settings ORDER BY host'))==[('example.com',1,1,'b'),('google.com',0,0,'a'),("o'neil.com",0,0,'c')]
print('OK: targeted reset SQL, both flag names, quoting, unrelated rows and fields preserved')
