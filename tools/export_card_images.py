"""Exporta {id, image_url} de todas las cartas con imagen a tools/card_images.json.

Lo consume tools/build_visual_index.dart (que se ejecuta en CI).
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, 'assets', 'database', 'tcg_catalog.db')
PC = os.path.join(ROOT, 'assets', 'data', 'catalog_pricecharting.json')
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'card_images.json')

rows = {}
conn = sqlite3.connect(DB)
for card_id, url in conn.execute(
    "SELECT id, image_url FROM cards "
    "WHERE image_url IS NOT NULL AND TRIM(image_url) <> ''"
):
    rows[card_id] = url

if os.path.exists(PC):
    data = json.load(open(PC, encoding='utf-8'))
    for card in data.get('cards', []):
        url = card.get('image_url')
        if url:
            rows[card['id']] = url

json.dump(
    [{'id': key, 'image_url': value} for key, value in sorted(rows.items())],
    open(OUT, 'w', encoding='utf-8'),
    ensure_ascii=False,
)
print(f'{len(rows)} cartas con imagen -> {OUT}')
