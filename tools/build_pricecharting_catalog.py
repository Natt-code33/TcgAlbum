"""Genera assets/data/catalog_pricecharting.json a partir de pc_sets/*.json.

- Empareja cada set de PriceCharting con el set local (TCGdex) por nombre.
- Sólo añade cartas que falten (por set_id + número): nunca pisa datos TCGdex.
- Traduce los nombres ingleses a japonés/chino/coreano con species_translations.
- Los sets de PriceCharting sin equivalente local se añaden con id `pc-<slug>`.

Uso:
    python tools/build_pricecharting_catalog.py
"""
from __future__ import annotations

import json
import os
import re
import sqlite3
import sys
import time
import unicodedata
from difflib import SequenceMatcher

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PC_DIR = os.environ.get('PC_SETS_DIR', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pc_sets'))
PL_DIR = os.environ.get('PL_SETS_DIR', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pl_sets'))
DB_PATH = os.path.join(ROOT, 'assets', 'database', 'tcg_catalog.db')
EXTRAS_PATH = os.path.join(ROOT, 'assets', 'data', 'catalog_extras.json')
OUT_PATH = os.path.join(ROOT, 'assets', 'data', 'catalog_pricecharting.json')

STOP_WORDS = {
    'pokemon', 'japanese', 'chinese', 'korean', 'english', 'spanish', 'french',
    'german', 'italian', 'portuguese', 'cards', 'card', 'set', 'sets',
    'collection', 'collections', 'the', 'of', 'and', 'series', 'edition',
    'tcg', 'trading', 'ccg', 'game', 'expansion', 'pack',
}

LANG_PREFIXES = ['japanese', 'chinese', 'korean', 'english', 'spanish',
                 'french', 'german', 'italian', 'portuguese']

# Traducción de palabras que aparecen en los títulos japoneses de los sets.
JA_WORDS = {
    'コレクション': 'collection',
    'ブラック': 'black',
    'ホワイト': 'white',
    'サイコドライブ': 'psycho drive',
    'ヘイルブリザード': 'hail blizzard',
    'リューズブラスト': 'dragon blade',
    'リューノブレード': 'dragon blast',
    'フリーズボルト': 'freeze bolt',
    'コールドフレア': 'cold flare',
    'ライデンナックル': 'thunder knuckle',
    'ハートゴールド': 'heartgold',
    'ソウルシルバー': 'soulsilver',
    'よみがえる': 'reviving',
    '伝説': 'legend',
    '頂上': 'summit',
    '大激突': 'clash',
    'ロストリンク': 'lost link',
    '拡張パック': 'expansion pack',
    '天空': 'heavens',
    '覇者': 'ruler',
    '砂漠': 'desert',
    'きせき': 'miracle',
    'とかれた': 'undone',
    '封印': 'seal',
    'マグマ': 'magma',
    'アクア': 'aqua',
    'ふたつの': 'two',
    '野望': 'ambitions',
    'ライジング': 'rising',
    'シールド': 'shield',
    'ソード': 'sword',
    '反逆': 'rebellion',
    'クラッシュ': 'crash',
    '爆炎': 'explosive',
    'ウォーカー': 'walker',
    'ムゲンゾーン': 'infinity zone',
    '鼓動': 'heartbeat',
    'ガイアボルケーノ': 'gaia volcano',
    'タイダルストーム': 'tidal storm',
    '青い': 'blue',
    '衝撃': 'shock',
    '赤い': 'red',
    '閃光': 'flash',
    '爆熱': 'fever burst',
    '闘士': 'fighter',
    '冷酷': 'cruel',
    '反逆者': 'traitor',
    '新たなる': 'new',
    '試練': 'challenge',
    '向こう': 'beyond',
    'ひかる': 'shining',
    'バトルブースト': 'battle boost',
    'ウルトラフォース': 'ultra force',
    'サン': 'sun',
    'ムーン': 'moon',
    'ピカチュウ': 'pikachu',
    '新しい': 'new',
    '仲間': 'friends',
    'ドラゴンセレクション': 'dragon selection',
    'バトル': 'battle',
    'ポケキュン': 'pokekyun',
    'プレミアム': 'premium',
    'チャンピオン': 'champion',
    'ワールド': 'world',
    'チャンピオンズ': 'champions',
    'シャイニー': 'shiny',
    '名探偵': 'detective',
    'トリプレットビート': 'triplet beat',
    'ポケモンカードゲーム': 'pokemon card game',
    'アニバーサリー': 'anniversary',
    'ゴールデン': 'golden',
    'ボックス': 'box',
}

# Alias manuales para los casos que el texto no resuelve.
ALIASES = {
    'pokemon-japanese-yamabuki-city-gym': 'gym2',
    'pokemon-japanese-poke-kyun-collection': 'cp3',
    'pokemon-japanese-premium-champion-pack': 'cp4',
    'pokemon-japanese-cruel-traitor': 'cp5',
    'pokemon-japanese-20th-anniversary': 'cp6',
    'pokemon-japanese-25th-anniversary-collection': 's8a',
    'pokemon-japanese-25th-anniversary-golden-box': 's8a-g',
    'pokemon-japanese-25th-anniversary-promo': 's8a-p',
    'pokemon-japanese-detective-pikachu': 'smp2',
    'pokemon-detective-pikachu': 'smp2',
    'pokemon-japanese-dragon-selection': 'ds',
    'pokemon-japanese-ex-battle-boost': 'ebb',
    'pokemon-japanese-shiny-collection': 'sc',
    'pokemon-japanese-world-champions-pack': 'pcg10',
    'pokemon-japanese-heartgold-collection': 'l1a',
    'pokemon-japanese-soulsilver-collection': 'l1b',
    'pokemon-japanese-reviving-legends': 'l2',
    'pokemon-japanese-clash-at-the-summit': 'l3',
    'pokemon-japanese-lost-link': 'll',
    'pokemon-japanese-vmax-rising': 's1a',
    'pokemon-japanese-shield': 's1h',
    'pokemon-japanese-sword': 's1w',
    'pokemon-japanese-rebellion-crash': 's2',
    'pokemon-japanese-explosive-walker': 's2a',
    'pokemon-japanese-infinity-zone': 's3',
    'pokemon-japanese-legendary-heartbeat': 's3a',
    'pokemon-japanese-triplet-beat': 'cs1a',
    'pokemon-japanese-sun-moon': 'sm1',
    'pokemon-japanese-beyond-a-new-challenge': 'sm2',
    'pokemon-japanese-shining-legends': 'sm3',
    'pokemon-japanese-gx-battle-boost': 'sm4',
    'pokemon-japanese-ultra-force': 'sm5',
    'pokemon-japanese-pikachu-and-new-friends': 'sm0',
    'pokemon-japanese-collection-x': 'xy1a',
    'pokemon-japanese-collection-y': 'xy1b',
    'pokemon-japanese-gaia-volcano': 'xy5a',
    'pokemon-japanese-tidal-storm': 'xy5b',
    'pokemon-japanese-blue-shock': 'xy8a',
    'pokemon-japanese-red-flash': 'xy8b',
    'pokemon-japanese-fever-burst-fighter': 'xy11a',
    'pokemon-japanese-cruel-traitor-xy': 'xy11b',
    'pokemon-japanese-black-collection': 'bw1a',
    'pokemon-japanese-white-collection': 'bw1b',
    'pokemon-japanese-psycho-drive': 'bw3a',
    'pokemon-japanese-hail-blizzard': 'bw3b',
    'pokemon-japanese-dragon-blade': 'bw5a',
    'pokemon-japanese-dragon-blast': 'bw5b',
    'pokemon-japanese-freeze-bolt': 'bw6a',
    'pokemon-japanese-cold-flare': 'bw6b',
    'pokemon-japanese-thunder-knuckle': 'bw8b',
    'pokemon-japanese-magma-vs-aqua': 'adv4',
    'pokemon-japanese-miracle-of-the-desert': 'adv2',
    'pokemon-japanese-rulers-of-the-heavens': 'adv3',
    'pokemon-japanese-undone-seal': 'adv5',
    'pokemon-japanese-expansion-pack': 'adv1',
    'pokemon-expedition': 'ecard1',
    'pokemon-chinese-gem-pack-2': 'cbb2c',
    'pokemon-chinese-gem-pack-3': 'cbb3c',
    'pokemon-chinese-gem-pack-4': 'cbb4c',
    'pokemon-chinese-gem-pack-5': 'cbb5c',
    'pokemon-chinese-gem-pack-6': 'cbb6c',
    'pokemon-chinese-gem-pack-7': 'cbb7c',
    'pokemon-chinese-gem-pack': 'cbb1c',
    'pokemon-chinese-csv10c': 'csv10c',
    'pokemon-chinese-csv105c': 'csv10.5c',
}

# Alias por nombre (Pokellector JP usa títulos en inglés; muchos sets antiguos
# del catálogo sólo tienen nombre japonés).
PL_ALIASES = {
    'miracle of the desert': 'adv2',
    'rulers of the heavens': 'adv3',
    'magma vs aqua two ambitions': 'adv4',
    'magma vs aqua': 'adv4',
    'undone seal': 'adv5',
    'black collection': 'bw1a',
    'white collection': 'bw1b',
    'psycho drive': 'bw3a',
    'hail blizzard': 'bw3b',
    'dragon blade': 'bw5a',
    'dragon blast': 'bw5b',
    'freeze bolt': 'bw6a',
    'cold flare': 'bw6b',
    'thunder knuckle': 'bw8b',
    'heartgold collection': 'l1a',
    'soulsilver collection': 'l1b',
    'reviving legends': 'l2',
    'clash at the summit': 'l3',
    'lost link': 'll',
    'shiny collection': 'sc',
    'dragon selection': 'ds',
    'ex battle boost': 'ebb',
    'collection x': 'xy1a',
    'collection y': 'xy1b',
    'gaia volcano': 'xy5a',
    'tidal storm': 'xy5b',
    'blue shock': 'xy8a',
    'red flash': 'xy8b',
    'fever burst fighter': 'xy11a',
    'cruel traitor': ['xy11b', 'cp5'],
    'pokekyun collection': 'cp3',
    'premium champion pack': 'cp4',
    'world champions pack': 'pcg10',
    'vmax rising': 's1a',
    'shield': 's1h',
    'sword': 's1w',
    'rebellion crash': 's2',
    'explosive walker': 's2a',
    'infinity zone': 's3',
    'legendary heartbeat': 's3a',
    'sun & moon': 'sm1+',
    'sun and moon': 'sm1+',
    'beyond a new challenge': 'sm2+',
    'shining legends': 'sm3+',
    'gx battle boost': 'sm4+',
    'ultra force': 'sm5+',
    'triple beat': 'cs1a',
    'pikachu and new friends': 'sm0',
    'pikachu new friends': 'sm0',
    'detective pikachu': 'smp2',
    'japanese detective pikachu': 'smp2',
    '20th anniversary collection': 'cp6',
    'sun moon strengthening expansion': 'sm1+',
    'explosive flame walker': 's2a',
    'japanese sun moon promos': 'sm-p',
    'sun moon promos': 'sm-p',
    'strengthening expansion shining legends': 'sm3+',
    'strengthening expansion pack beyond a new challeng': 'sm2+',
    'strengthening expansion pack beyond a new challenge': 'sm2+',
}

# Normalizar las claves igual que los nombres de set ("the"/"of" se eliminan).
# Se hace tras definir norm(), más abajo.

# Agregados de promos que ya están repartidos en los sets de promo locales.
SKIP_SLUGS = {'pokemon-promo', 'pokemon-japanese-promo', 'pokemon-korean-promo'}

# Prefijos de variantes que sí se traducen a los idiomas asiáticos.
JA_PREFIXES = {
    'dark': 'わるい',
    'light': 'ひかる',
    'shining': 'ひかる',
    'radiant': 'かがやく',
    'mega': 'メガ',
    'hisuian': 'ヒスイ',
    'galarian': 'ガラル',
    'alolan': 'アローラ',
    'paldean': 'パルデア',
    'team rocket\'s': 'ロケット団の',
    'team aqua\'s': 'アクア団の',
    'team magma\'s': 'マグマ団の',
}
ZH_PREFIXES = {
    'dark': '邪恶',
    'light': '光明',
    'shining': '闪耀',
    'radiant': '光辉',
    'mega': '超级',
    'hisuian': '洗翠',
    'galarian': '伽勒尔',
    'alolan': '阿罗拉',
    'paldean': '帕底亚',
    "team rocket's": '火箭队的',
    "team aqua's": '水舰队的',
    "team magma's": '火岩队的',
}

SUFFIX_RE = re.compile(
    r'^(.*?)\s*(EX|ex|GX|V|VMAX|VSTAR|V-UNION|BREAK|LV\.X|δ|Prime|Star|'
    r'Radiant|Gold|Full Art|Special Illustration Rare|Illustration Rare)$',
    re.IGNORECASE,
)


def norm(text: str) -> str:
    text = unicodedata.normalize('NFKD', text or '')
    text = text.encode('ascii', 'ignore').decode()
    text = text.lower().replace('&', ' and ')
    text = re.sub(r'[^a-z0-9]+', ' ', text)
    return ' '.join(w for w in text.split() if w and w not in STOP_WORDS)


PL_ALIASES = {norm(key): value for key, value in PL_ALIASES.items()}


def strip_lang(name: str) -> str:
    words = name.split()
    out = []
    for word in words:
        low = word.lower().strip('.,:')
        if low == 'pokemon':
            continue
        out.append(word)
    while out and out[0].lower().strip('.,:') in LANG_PREFIXES:
        out = out[1:]
    return ' '.join(out)


def ja_to_en(text: str) -> str:
    out = text
    for ja, en in sorted(JA_WORDS.items(), key=lambda x: -len(x[0])):
        out = out.replace(ja, f' {en} ')
    out = re.sub(r'[ぁ-んァ-ヶー]', ' ', out)
    return out


def similarity(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    at, bt = set(a.split()), set(b.split())
    jac = len(at & bt) / len(at | bt) if at and bt else 0.0
    # El bonus por subconjunto sólo vale para marcas de idioma/edición
    # ("Black Bolt (JP)" ↔ "Black Bolt"), no para palabras cualesquiera
    # ("Glory of Team Rocket" ≠ "Team Rocket").
    allowed_extra = {
        'jp', 'cn', 'kr', 'en', 'english', 'japanese', 'chinese', 'korean',
        'set', 'edition',
    }
    extra = (at ^ bt)
    if (at and bt and (at <= bt or bt <= at) and len(extra) <= 2
            and extra <= allowed_extra and len(at & bt) >= 2):
        jac = max(jac, 0.9)
    return max(jac, 0.85 * SequenceMatcher(None, a, b).ratio())


class SetIndex:
    def __init__(self, rows):
        # rows: (id, name, name_es, name_en, name_ja, name_zh, official)
        self.rows = rows
        self.entries = []
        for row in rows:
            sid, name, es, en, ja, zh, official = row
            names = [x for x in (name, es, en, ja, zh) if x]
            variants = set()
            for value in names + [sid]:
                variants.add(norm(value))
                variants.add(norm(strip_lang(value)))
                if value and re.search(r'[ぁ-んァ-ヶー]', value):
                    variants.add(norm(ja_to_en(value)))
            variants.discard('')
            self.entries.append({'id': sid, 'names': variants, 'official': official,
                                 'raw': names})

    def best(self, pc_name: str):
        pc_variants = {norm(pc_name), norm(strip_lang(pc_name))}
        pc_variants.discard('')
        best_score, best_id = 0.0, None
        for entry in self.entries:
            score = 0.0
            for pv in pc_variants:
                for lv in entry['names']:
                    score = max(score, similarity(pv, lv))
            if score > best_score:
                best_score, best_id = score, entry['id']
        return best_score, best_id


def load_species(db):
    rows = db.execute(
        'SELECT name_en, name_ja, name_ko, name_zh_cn, name_zh_tw '
        'FROM species_translations'
    ).fetchall()
    table = {}
    for en, ja, ko, zh_cn, zh_tw in rows:
        if not en:
            continue
        table.setdefault(en.strip().lower(), {
            'ja': ja, 'ko': ko, 'zh_cn': zh_cn, 'zh_tw': zh_tw,
        })
    return table


def split_suffix(name: str):
    m = SUFFIX_RE.match(name.strip())
    if m and m.group(1).strip():
        return m.group(1).strip(), m.group(2).strip()
    return name.strip(), ''


def translate_card(name: str, species) -> dict:
    """Devuelve {ja, ko, zh} aproximados para un nombre inglés de carta."""
    base, suffix = split_suffix(name)
    out = {}

    # 1) Nombre completo exacto (Pikachu, Mewtwo...).
    lookup = species.get(base.lower())
    if lookup:
        out = {
            'ja': _join(lookup.get('ja'), suffix),
            'ko': _join(lookup.get('ko'), suffix),
            'zh': _join(lookup.get('zh_cn') or lookup.get('zh_tw'), suffix),
        }
        return {k: v for k, v in out.items() if v}

    # 2) Varios Pokémon unidos con &: "Reshiram & Charizard".
    if '&' in base:
        parts = [p.strip() for p in base.split('&') if p.strip()]
        translated = []
        for part in parts:
            sub = species.get(part.lower())
            if not sub:
                translated = []
                break
            translated.append(sub)
        if translated:
            ja = '&'.join(_join(s.get('ja'), '') for s in translated)
            zh = '&'.join(
                _join(s.get('zh_cn') or s.get('zh_tw'), '') for s in translated
            )
            ko = '&'.join(_join(s.get('ko'), '') for s in translated)
            return {
                'ja': _join(ja, suffix),
                'ko': _join(ko, suffix),
                'zh': _join(zh, suffix),
            }

    # 3) Prefijo de variante + especie: "Dark Charizard".
    words = base.split()
    for i in range(1, min(4, len(words))):
        prefix = ' '.join(words[:i]).lower()
        rest = ' '.join(words[i:])
        sub = species.get(rest.lower())
        if sub and (prefix in JA_PREFIXES or prefix in ZH_PREFIXES):
            ja_pre = JA_PREFIXES.get(prefix, '')
            zh_pre = ZH_PREFIXES.get(prefix, '')
            ja = _join(ja_pre + (sub.get('ja') or ''), suffix)
            zh_base = sub.get('zh_cn') or sub.get('zh_tw') or ''
            zh = _join(zh_pre + zh_base, suffix)
            ko = _join(sub.get('ko'), suffix)
            return {k: v for k, v in {'ja': ja, 'ko': ko, 'zh': zh}.items() if v}

    return {}


def _join(base, suffix):
    if not base:
        return None
    if not suffix:
        return base
    # Los sufijos japoneses/chinos van pegados al nombre.
    if re.search(r'[ぁ-んァ-ヶ一-龯]', base):
        return f'{base}{suffix}'
    return f'{base} {suffix}'


def card_local_id(number: str) -> str:
    value = re.sub(r'\s+', '', number.strip())
    if value.isdigit() and len(value) < 3:
        return value.zfill(3)
    return value


def number_key(value: str) -> str:
    cleaned = re.sub(r'[^a-z0-9]', '', (value or '').lower())
    if cleaned.isdigit():
        return str(int(cleaned))
    return cleaned


def name_key(value: str) -> str:
    """Normaliza un nombre de carta para comparar entre idiomas."""
    value = (value or '').lower()
    value = re.sub(r'\b(?:ex|gx|v|vmax|vstar|v-?union|break|radiant)\b', ' ', value)
    value = re.sub(r'[^a-z0-9\u3040-\u30ff\u4e00-\u9fff]+', '', value)
    return value


def main():
    db = sqlite3.connect(DB_PATH)
    species = load_species(db)

    ja_sets: dict[str, set[str]] = {}
    for name_ja, set_id in db.execute(
        "SELECT name_ja, set_id FROM cards "
        "WHERE name_ja IS NOT NULL AND TRIM(name_ja) <> ''"
    ):
        key = name_key(name_ja)
        if key:
            ja_sets.setdefault(key, set()).add((set_id or '').lower())

    rows = db.execute(
        'SELECT id, name, name_es, name_en, name_ja, name_zh, official_count '
        'FROM sets'
    ).fetchall()
    rows = [list(r) for r in rows]
    db_set_ids = {(row[0] or '').lower() for row in rows}

    # Añadir los sets de extras al índice de emparejamiento.
    if os.path.exists(EXTRAS_PATH):
        extras = json.load(open(EXTRAS_PATH, encoding='utf-8'))
        for s in extras.get('sets', []):
            rows.append([s.get('id'), s.get('name'), s.get('name_es'),
                         s.get('name_en'), s.get('name_ja'), s.get('name_zh'),
                         s.get('official_count')])
    index = SetIndex(rows)

    existing = {}
    for set_id, local_id in db.execute('SELECT set_id, local_id FROM cards'):
        existing.setdefault(set_id.lower(), set()).add(number_key(local_id))
    local_counts = {sid: len(keys) for sid, keys in existing.items()}
    extras_numbers = {}
    if os.path.exists(EXTRAS_PATH):
        extras = json.load(open(EXTRAS_PATH, encoding='utf-8'))
        for c in extras.get('cards', []):
            sid = (c.get('set_id') or '').lower()
            if sid:
                extras_numbers.setdefault(sid, set()).add(
                    number_key(c.get('local_id')))

    out_sets = []
    out_cards = []
    report = []
    seen_card_ids = set()
    known_set_ids = {(r[0] or '').lower() for r in rows}

    def resolve(source, slug, name, cards):
        numbers = [int(re.sub(r'[^0-9]', '', c['number']) or 0) for c in cards]
        max_num = max(numbers) if numbers else 0
        if source == 'pc' and slug in ALIASES:
            return 1.0, ALIASES[slug]
        if source == 'pl':
            entry = PL_ALIASES.get(norm(name))
            if entry is not None:
                if isinstance(entry, list):
                    def closeness(sid):
                        off = next(
                            (r[6] for r in rows
                             if (r[0] or '').lower() == sid), 0) or 0
                        return abs(off - max_num) if off else 999
                    return 1.0, min(entry, key=closeness)
                return 1.0, entry
        score, set_id = index.best(name)
        if score >= 0.80:
            return score, set_id

        # Desempate por contenido: traducir los nombres al japonés y ver en qué
        # set local aparecen. Sólo para sets japoneses y exigiendo que el
        # tamaño del set coincida; así no se confunden reprints ni agregados.
        is_japanese = source == 'pl' or 'japanese' in slug
        if any(k in slug for k in (
                'carddass', 'topps', 'topsun', 'burger-king', 'old-maid',
                'classic-', 'premium-file', 'starter-deck', 'start-deck')):
            is_japanese = False
        is_promo_aggregate = slug in {
            'pokemon-promo', 'pokemon-japanese-promo',
            'pokemon-chinese-promo', 'pokemon-korean-promo',
        } 
        if not is_japanese or is_promo_aggregate:
            return score, set_id

        hits: dict[str, int] = {}
        sampled = 0
        for card in cards[:80]:
            translated = translate_card(card['name'], species).get('ja')
            if not translated:
                continue
            sampled += 1
            for sid in ja_sets.get(name_key(translated), ()):
                hits[sid] = hits.get(sid, 0) + 1

        tolerance = 2
        candidates = [
            (count, sid) for sid, count in hits.items()
            if abs(local_counts.get(sid, 0) - len(cards)) <= tolerance
        ]
        if candidates:
            count, sid = max(candidates)
            if count >= 6 and count >= sampled * 0.35:
                return 0.85, sid

        return score, set_id

    def source_files(directory, prefix):
        if not os.path.isdir(directory):
            return []
        return [(prefix, os.path.join(directory, f))
                for f in sorted(os.listdir(directory)) if f.endswith('.json')]

    files = source_files(PC_DIR, 'pc') + source_files(PL_DIR, 'pl')
    for source, path in files:
        data = json.load(open(path, encoding='utf-8'))
        slug = data['slug']
        pc_name = data['name']
        cards = data.get('cards') or []
        if not cards or slug in SKIP_SLUGS:
            continue

        score, set_id = resolve(source, slug, pc_name, cards)

        # Umbral alto: preferimos no añadir nada antes que contaminar un set.
        if score < 0.80 or set_id is None:
            set_id = ('pc-' if source == 'pc' else 'pl-') + re.sub(r'^pokemon-', '', slug)
            score = 0.0

        set_id = set_id.lower()
        new_set = set_id not in known_set_ids
        if new_set:
            known_set_ids.add(set_id)
        known = existing.get(set_id, set()) | extras_numbers.get(set_id, set())
        official = next((r[6] for r in rows if (r[0] or '').lower() == set_id), None)
        if not official:
            numbers = [int(re.sub(r'[^0-9]', '', c['number']) or 0) for c in cards]
            official = max(numbers) if numbers else len(cards)

        added = 0
        max_number = official or 0
        for card in cards:
            local_id = card_local_id(card['number'])
            key = number_key(local_id)
            if not key or key in known:
                continue
            known.add(key)

            card_id = f'{set_id}-{key}'
            if card_id in seen_card_ids:
                continue
            seen_card_ids.add(card_id)

            number_int = int(re.sub(r'[^0-9]', '', local_id) or 0)
            names = translate_card(card['name'], species)
            image_url = (card.get('image_url') or '').replace('/60.jpg', '/1600.jpg')
            row = {
                'id': card_id,
                'set_id': set_id,
                'local_id': local_id,
                'number_int': number_int,
                'total_in_set': official,
                'name_en': card['name'],
                'game': 'pokemon',
            }
            if image_url:
                row['image_url'] = image_url
            if names.get('ja'):
                row['name_ja'] = names['ja']
            if names.get('zh'):
                row['name_zh'] = names['zh']
            if names.get('ko'):
                row['name_ko'] = names['ko']
            out_cards.append(row)
            added += 1
            if number_int > max_number:
                max_number = number_int

        if added:
            if new_set:
                if source == 'pl':
                    lang = 'ja'
                else:
                    lang = ('ja' if 'japanese' in slug else
                            'zh' if 'chinese' in slug else
                            'ko' if 'korean' in slug else 'en')
                out_sets.append({
                    'id': set_id,
                    'name': pc_name,
                    'name_en': pc_name,
                    'code': set_id,
                    'official_count': max_number,
                    'total_count': max_number,
                    'language': lang,
                })
            report.append(
                (f'{source}:{slug}', set_id, score, added,
                 'NEW' if new_set else 'MERGE'))

    total = sum(r[3] for r in report)

    # Garantizar que toda carta tenga su set, aunque venga de extras o de un
    # alias. Así el JSON es autocontenido.
    base_set_ids = db_set_ids
    emitted = {s['id'] for s in out_sets}
    extras_rows = {}
    if os.path.exists(EXTRAS_PATH):
        extras_data = json.load(open(EXTRAS_PATH, encoding='utf-8'))
        for s in extras_data.get('sets', []):
            extras_rows[(s.get('id') or '').lower()] = s
    for card in out_cards:
        sid = card['set_id']
        if sid in base_set_ids or sid in emitted:
            continue
        row = extras_rows.get(sid)
        if row is None:
            total_in_set = card.get('total_in_set') or 0
            row = {
                'id': sid,
                'name': sid,
                'name_en': sid,
                'code': sid,
                'official_count': total_in_set,
                'total_count': total_in_set,
                'language': 'ja' if sid.startswith('pl-') else 'en',
            }
        out_sets.append(row)
        emitted.add(sid)

    payload = {
        # Versión monótona: la app aplica el JSON si es más nuevo que el suyo.
        'version': int(time.time()),
        'source': 'pricecharting+pokellector-jp',
        'sets': out_sets,
        'cards': out_cards,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, 'w', encoding='utf-8') as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(',', ':'))

    print(f'Sets de origen procesados: {len(files)}')
    print(f'Sets con cartas nuevas: {len(report)} (nuevos: {len(out_sets)})')
    print(f'Cartas añadidas: {total}')
    print(f'JSON: {OUT_PATH} ({os.path.getsize(OUT_PATH)} bytes)')
    print('\n-- Sets nuevos --')
    for slug, sid, score, added, kind in report:
        if kind == 'NEW':
            print(f'  {slug} -> {sid} ({added})')
    print('\n-- Fusiones con score bajo --')
    for slug, sid, score, added, kind in report:
        if kind == 'MERGE' and score < 0.92:
            print(f'  {slug} -> {sid} score={score:.2f} ({added})')


if __name__ == '__main__':
    main()
