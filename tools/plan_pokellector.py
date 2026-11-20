"""Calcula qué sets de Pokellector JP faltan de verdad (los que están vacíos).

Imprime una lista de slugs para PL_ONLY:
    $env:PL_ONLY = (python tools/plan_pokellector.py)
    python tools/scrape_pokellector_jp.py

Uso:
    python tools/plan_pokellector.py
"""
from __future__ import annotations

import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_pricecharting_catalog import (  # noqa: E402
    DB_PATH, PL_ALIASES, SetIndex, norm,
)
from scrape_pokellector_jp import load_set_list  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')


def main() -> None:
    db = sqlite3.connect(DB_PATH)
    counts = {sid.lower(): n for sid, n in db.execute(
        'SELECT set_id, COUNT(*) FROM cards GROUP BY set_id')}
    empty = []
    for sid, name, en, ja, zh, official in db.execute(
        'SELECT id,name,name_en,name_ja,name_zh,official_count FROM sets'
    ):
        if counts.get(sid.lower(), 0) > 0:
            continue
        empty.append([sid, name, None, en, ja, zh, official])
    index = SetIndex(empty)
    empty_ids = {row[0].lower() for row in empty}

    sets = load_set_list()
    needed = []
    for slug, (name, _url) in sorted(sets.items()):
        alias = PL_ALIASES.get(norm(name))
        if isinstance(alias, list):
            hit = any(a in empty_ids for a in alias)
        else:
            hit = alias in empty_ids if alias else False
        if not hit:
            score, candidate = index.best(name)
            hit = score >= 0.78 and candidate in empty_ids
        if hit:
            needed.append(slug)
    print(','.join(needed))


if __name__ == '__main__':
    main()
