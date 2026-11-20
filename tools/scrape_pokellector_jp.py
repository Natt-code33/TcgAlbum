"""Descarga las colecciones japonesas de Pokellector (listas completas).

Pokellector sí indexa los sets japoneses antiguos que PriceCharting no tiene.
Salida: tools/pl_sets/<slug>.json con {slug, name, cards:[{name, number, image_url}]}.

Uso:
    python tools/scrape_pokellector_jp.py
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import unicodedata
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get('PL_SETS_DIR', os.path.join(BASE, 'pl_sets'))
CACHE = os.path.join(OUT, '.cache')
os.makedirs(CACHE, exist_ok=True)

LIST_URL = 'https://jp.pokellector.com/sets'


def fetch(url: str, tries: int = 4, timeout: int = 90) -> str:
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(
                'https://r.jina.ai/' + url,
                headers={
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                                  'AppleWebKit/537.36 (KHTML, like Gecko) '
                                  'Chrome/124.0 Safari/537.36',
                    'Accept': 'text/plain',
                },
            )
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read().decode('utf-8', 'replace')
        except Exception as exc:  # noqa: BLE001
            last = exc
            time.sleep(3 + i * 3)
    raise last  # type: ignore[misc]


def load_set_list() -> dict[str, tuple[str, str]]:
    """Devuelve slug -> (nombre, url)."""
    path = os.path.join(CACHE, '_sets.md')
    if os.path.exists(path) and os.path.getsize(path) > 10_000:
        text = open(path, encoding='utf-8').read()
    else:
        text = fetch(LIST_URL)
        open(path, 'w', encoding='utf-8').write(text)

    pairs: dict[str, tuple[str, str]] = {}
    for m in re.finditer(
        r'\((https://jp\.pokellector\.com/[^)\s]+-Expansion/)',
        text,
    ):
        url = m.group(1)
        slug = url.rstrip('/').split('/')[-1]
        name = slug[:-len('-Expansion')].replace('-', ' ').strip()
        pairs.setdefault(slug, (name, url))
    return pairs


LINE_RE = re.compile(
    r'#([A-Za-z0-9]+)\s*-\s*(.+?)\s*$',
    re.MULTILINE,
)
IMG_RE = re.compile(
    r'\((https://den-cards\.pokellector\.com/[^)]+?)(\.thumb)?\.png\)'
    r'\]\((https://jp\.pokellector\.com/[^)]+)\)'
)


def parse_cards(text: str) -> list[dict]:
    cards: dict[str, dict] = {}
    for m in LINE_RE.finditer(text):
        number = m.group(1).strip()
        name = m.group(2).strip()
        name = re.sub(r'\s+', ' ', name)
        if not name or len(name) > 60:
            continue
        cards[number.lower()] = {
            'name': name,
            'number': number,
            'image_url': None,
        }

    # Asociar imágenes: cada imagen precede a la línea "#N - Nombre".
    lines = text.splitlines()
    pending: list[tuple[str, str]] = []
    for line in lines:
        for m in IMG_RE.finditer(line):
            url = m.group(1)
            if not url.endswith('.png'):
                url += '.png'
            pending.append((url, line))
        lm = LINE_RE.search(line)
        if lm and pending:
            number = lm.group(1).strip().lower()
            url = pending.pop(0)[0]
            if number in cards:
                cards[number]['image_url'] = url

    return list(cards.values())


def main() -> None:
    sets = load_set_list()
    only = {s.strip() for s in os.environ.get('PL_ONLY', '').split(',') if s.strip()}
    if only:
        sets = {slug: value for slug, value in sets.items() if slug in only}
    print(f'Colecciones japonesas Pokellector: {len(sets)}', flush=True)
    done = 0
    for slug, (name, url) in sorted(sets.items()):
        out = os.path.join(OUT, slug + '.json')
        if os.path.exists(out):
            done += 1
            continue
        cache = os.path.join(CACHE, slug + '.md')
        try:
            if os.path.exists(cache) and os.path.getsize(cache) > 2_000:
                text = open(cache, encoding='utf-8').read()
            else:
                text = fetch(url)
                open(cache, 'w', encoding='utf-8').write(text)
        except Exception as exc:  # noqa: BLE001
            print('FALLO', slug, exc, flush=True)
            continue
        cards = parse_cards(text)
        json.dump(
            {'slug': slug, 'name': name, 'url': url, 'cards': cards},
            open(out, 'w', encoding='utf-8'),
            ensure_ascii=False,
        )
        done += 1
        print(f'[{done}/{len(sets)}] {slug}: {len(cards)} cartas', flush=True)
        time.sleep(1.2)


if __name__ == '__main__':
    main()
