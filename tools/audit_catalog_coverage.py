"""Informe de cobertura del catálogo.

Uso:
    python tools/audit_catalog_coverage.py
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(ROOT, 'assets', 'database', 'tcg_catalog.db')
PC_PATH = os.path.join(ROOT, 'assets', 'data', 'catalog_pricecharting.json')
EXTRAS_PATH = os.path.join(ROOT, 'assets', 'data', 'catalog_extras.json')


def main() -> None:
    db = sqlite3.connect(DB_PATH)
    counts = {}
    for set_id, total in db.execute(
        'SELECT set_id, COUNT(*) FROM cards GROUP BY set_id'
    ):
        counts[set_id.lower()] = total

    extras_cards = {}
    if os.path.exists(EXTRAS_PATH):
        data = json.load(open(EXTRAS_PATH, encoding='utf-8'))
        for card in data.get('cards', []):
            sid = (card.get('set_id') or '').lower()
            if sid:
                extras_cards[sid] = extras_cards.get(sid, 0) + 1

    pc_cards = {}
    pc_sets = set()
    if os.path.exists(PC_PATH):
        data = json.load(open(PC_PATH, encoding='utf-8'))
        for card in data.get('cards', []):
            sid = (card.get('set_id') or '').lower()
            if sid:
                pc_cards[sid] = pc_cards.get(sid, 0) + 1
        for s in data.get('sets', []):
            pc_sets.add((s.get('id') or '').lower())

    sets = db.execute(
        'SELECT id, name, name_en, name_ja, name_zh, official_count FROM sets'
    ).fetchall()

    remaining = []
    covered = 0
    for sid, name, en, ja, zh, official in sets:
        sid = sid.lower()
        total = (counts.get(sid, 0) + extras_cards.get(sid, 0)
                 + pc_cards.get(sid, 0))
        if total == 0:
            remaining.append((sid, en or ja or zh or name, official))
        else:
            covered += 1

    print(f'Sets en catálogo base: {len(sets)}')
    print(f'Sets con al menos una carta: {covered}')
    print(f'Sets todavía vacíos: {len(remaining)}')
    for row in remaining:
        print('  ', row)
    print(f'\nSets nuevos aportados por PriceCharting: {len(pc_sets)}')
    for sid in sorted(pc_sets):
        print('  ', sid, pc_cards.get(sid, 0), 'cartas')
    print(f'\nCartas PriceCharting: {sum(pc_cards.values())}')


if __name__ == '__main__':
    main()
