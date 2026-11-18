#!/usr/bin/env python3
"""Generate a single-item appcast from the tested release artifact. No private key input."""
import base64
import email.utils
import pathlib
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ROOT_URL = 'https://github.com/suberb/safari-icon-fixer'
ET.register_namespace('sparkle', NS)

def make(plist, archive, signature, notes, output):
    version = plist['CFBundleShortVersionString']
    build = plist['CFBundleVersion']
    assert re.fullmatch(r'\d+\.\d+\.\d+', version)
    assert re.fullmatch(r'[1-9]\d*', build)
    assert archive.name == f'SafariIconFixer-{version}-macOS-arm64.dmg'
    assert len(base64.b64decode(signature, validate=True)) == 64
    assert archive.stat().st_size > 0
    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Safari Icon Fixer'
    ET.SubElement(channel, 'link').text = ROOT_URL + '/releases'
    ET.SubElement(channel, 'description').text = 'Stable updates for Safari Icon Fixer'
    ET.SubElement(channel, 'language').text = 'en'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Safari Icon Fixer {version}'
    ET.SubElement(item, 'link').text = ROOT_URL + '/releases/tag/v' + version
    ET.SubElement(item, f'{{{NS}}}version').text = build
    ET.SubElement(item, f'{{{NS}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = plist['LSMinimumSystemVersion'] + '.0' if plist['LSMinimumSystemVersion'].count('.') == 1 else plist['LSMinimumSystemVersion']
    ET.SubElement(item, f'{{{NS}}}hardwareRequirements').text = 'arm64'
    ET.SubElement(item, 'pubDate').text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, 'description', {f'{{{NS}}}format': 'markdown'}).text = notes
    ET.SubElement(item, f'{{{NS}}}fullReleaseNotesLink').text = ROOT_URL + '/releases'
    ET.SubElement(item, 'enclosure', {'url': ROOT_URL + '/releases/download/v' + version + '/' + archive.name, f'{{{NS}}}edSignature': signature, 'length': str(archive.stat().st_size), 'type': 'application/octet-stream'})
    ET.indent(rss)
    ET.ElementTree(rss).write(output, encoding='utf-8', xml_declaration=True)

if __name__ == '__main__':
    archive, signature, output = sys.argv[1:]
    with open('Info.plist', 'rb') as f:
        plist = plistlib.load(f)
    make(plist, pathlib.Path(archive), signature, pathlib.Path('RELEASE.md').read_text(), pathlib.Path(output))
