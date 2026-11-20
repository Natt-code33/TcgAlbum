"""Sugiere alias para sets nuevos (pc-*/pl-*) comparándolos con sets vacíos.

Uso:
    python tools/suggest_aliases.py
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_pricecharting_catalog import (  # noqa: E402
    DB_PATH, OUT_PATH, SetIndex, norm,
)
import sqlite3  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')


def main() -> None:
    if not os.path.exists(OUT_PATH):
        print('Falta el JSON generado.')
        return
    data = json.load(open(OUT_PATH, encoding='utf-8'))
    db = sqlite3.connect(DB_PATH)
    counts = {sid.lower(): n for sid, n in db.execute(
        'SELECT set_id, COUNT(*) FROM cards GROUP BY set_id')}
    empty = []
    for sid, name, en, ja, zh, official in db.execute(
        'SELECT id,name,name_en,name_ja,name_zh,official_count FROM sets'
    ):
        if counts.get(sid.lower(), 0) == 0:
            empty.append((sid.lower(), en or ja or zh or name, official))
    index = SetIndex([
        [sid, name, None, name, None, None, official]
        for sid, name, official in empty
    ])
    print('Sets nuevos y mejor candidato vacío:')
    for s in data.get('sets', []):
        sid = (s.get('id') or '').lower()
        if not sid.startswith(('pc-', 'pl-')):
            continue
        name = s.get('name') or ''
        score, candidate = index.best(name)
        if score >= 0.45:
            print(f'  {sid} | {name} -> {candidate} ({score:.2f})')
        else:
            print(f'  {sid} | {name} -> (sin candidato)')


if __name__ == '__main__':
    main()
