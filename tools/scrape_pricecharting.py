"""Descarga todas las colecciones de PriceCharting y extrae sus cartas.

Cachea el markdown de cada set en tools/pc_sets/.cache/ y escribe un JSON por
set en tools/pc_sets/. Se reanuda solo si se interrumpe.

Uso:
    python tools/scrape_pricecharting.py
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get('PC_SETS_DIR', os.path.join(BASE, 'pc_sets'))
CACHE = os.path.join(OUT, '.cache')
os.makedirs(CACHE, exist_ok=True)

CATEGORY = 'https://www.pricecharting.com/es/category/pokemon-cards'


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


def load_set_list() -> dict[str, str]:
    path = os.path.join(CACHE, '_category.md')
    if os.path.exists(path) and os.path.getsize(path) > 10_000:
        text = open(path, encoding='utf-8').read()
    else:
        text = fetch(CATEGORY)
        open(path, 'w', encoding='utf-8').write(text)
    pairs: dict[str, str] = {}
    for m in re.finditer(
        r'\[([^\]]+)\]\(https://www\.pricecharting\.com/es/console/(pokemon-[a-z0-9-]+)',
        text,
    ):
        pairs.setdefault(m.group(2), m.group(1).strip())
    return pairs


CARD_RE = re.compile(
    r'\[!\[Image \d+\]\((https://storage\.googleapis\.com/images\.pricecharting\.com/([^/]+)/\d+\.jpg)\)\]'
    r'\(https://www\.pricecharting\.com/es/game/[^)]+\)'
    r'\s*\|\s*\[([^\]]+)\]\(https://www\.pricecharting\.com/es/game/[^)]+\)'
)

NUMBER_RE = re.compile(r'#([A-Za-z0-9][A-Za-z0-9._-]*)\s*$')


def number_key(number: str) -> str:
    cleaned = re.sub(r'[^a-z0-9]', '', number.lower())
    return str(int(cleaned)) if cleaned.isdigit() else cleaned


def parse_cards(text: str) -> list[dict]:
    cards: dict[str, dict] = {}
    for m in CARD_RE.finditer(text):
        image_url = m.group(1)
        image_id = m.group(2)
        label = m.group(3).strip()
        nm = NUMBER_RE.search(label)
        if not nm:
            continue
        number = nm.group(1)
        name = re.sub(r'\s*\[[^\]]*\]\s*$', '', label[:nm.start()].strip()).strip()
        if not name:
            continue
        key = number_key(number)
        previous = cards.get(key)
        if previous is None or len(name) < len(previous['name']):
            cards[key] = {
                'name': name,
                'number': number,
                'image_id': image_id,
                'image_url': image_url,
            }
    return list(cards.values())


def main() -> None:
    sets = load_set_list()
    print(f'Colecciones PriceCharting: {len(sets)}', flush=True)
    done = 0
    for slug, name in sorted(sets.items()):
        out = os.path.join(OUT, slug + '.json')
        if os.path.exists(out):
            done += 1
            continue
        cache = os.path.join(CACHE, slug + '.md')
        try:
            if os.path.exists(cache) and os.path.getsize(cache) > 2_000:
                text = open(cache, encoding='utf-8').read()
            else:
                text = fetch('https://www.pricecharting.com/es/console/' + slug)
                open(cache, 'w', encoding='utf-8').write(text)
        except Exception as exc:  # noqa: BLE001
            print('FALLO', slug, exc, flush=True)
            continue
        cards = parse_cards(text)
        json.dump(
            {
                'slug': slug,
                'name': name,
                'url': 'https://www.pricecharting.com/es/console/' + slug,
                'cards': cards,
            },
            open(out, 'w', encoding='utf-8'),
            ensure_ascii=False,
        )
        done += 1
        print(f'[{done}/{len(sets)}] {slug}: {len(cards)} cartas', flush=True)
        time.sleep(1.2)


if __name__ == '__main__':
    main()
