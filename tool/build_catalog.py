import sqlite3
import json
import urllib.request
import csv
import io
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor

sys.stdout.reconfigure(encoding='utf-8')

DB_DIR = os.path.join('assets', 'database')
os.makedirs(DB_DIR, exist_ok=True)
DB_PATH = os.path.join(DB_DIR, 'tcg_catalog.db')
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# Optimización de escritura en SQLite durante construcción
cursor.execute('PRAGMA synchronous = OFF')
cursor.execute('PRAGMA journal_mode = MEMORY')

# 1. Crear tablas con soporte multilingüe completo (10 idiomas)
cursor.execute('''
CREATE TABLE sets (
    id TEXT PRIMARY KEY,
    name TEXT,
    name_es TEXT,
    name_en TEXT,
    name_ja TEXT,
    name_ko TEXT,
    name_zh TEXT,
    name_fr TEXT,
    name_de TEXT,
    name_it TEXT,
    name_pt TEXT,
    name_th TEXT,
    name_id TEXT,
    code TEXT,
    official_count INTEGER,
    total_count INTEGER,
    language TEXT
)
''')

cursor.execute('''
CREATE TABLE cards (
    id TEXT PRIMARY KEY,
    set_id TEXT,
    local_id TEXT,
    number_int INTEGER,
    total_in_set INTEGER,
    name_ja TEXT,
    name_en TEXT,
    name_es TEXT,
    name_ko TEXT,
    name_zh TEXT,
    name_fr TEXT,
    name_de TEXT,
    name_it TEXT,
    name_pt TEXT,
    name_th TEXT,
    name_id TEXT,
    image_url TEXT,
    cardmarket_id INTEGER,
    game TEXT DEFAULT 'pokemon'
)
''')

cursor.execute('''
CREATE TABLE species_translations (
    species_id INTEGER PRIMARY KEY,
    name_es TEXT,
    name_en TEXT,
    name_ja TEXT,
    name_ko TEXT,
    name_zh_tw TEXT,
    name_zh_cn TEXT,
    name_fr TEXT,
    name_de TEXT,
    name_it TEXT
)
''')

headers = {'User-Agent': 'Mozilla/5.0 (TcgAlbum Catalog Builder)'}

def fetch_json(url):
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=25) as res:
            return json.loads(res.read().decode('utf-8'))
    except Exception as e:
        print(f"  [Aviso] Fallo al descargar {url}: {e}")
        return None

def fetch_text(url):
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=25) as res:
            return res.read().decode('utf-8')
    except Exception as e:
        print(f"  [Aviso] Fallo al descargar texto {url}: {e}")
        return None

# 2. Descargar las 1.025 especies oficiales de Pokémon desde PokeAPI para traducción cruzada
print("1/4 Descargando diccionario oficial de las 1.025 especies Pokémon (PokeAPI)...")
species_csv = fetch_text('https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon_species_names.csv')
by_species = {}
if species_csv:
    reader = csv.DictReader(io.StringIO(species_csv))
    # local_language_id: 1=ja, 3=ko, 4=zh-tw, 5=fr, 6=de, 7=es, 8=it, 9=en, 12=zh-cn
    for row in reader:
        sid = int(row['pokemon_species_id'])
        lid = int(row['local_language_id'])
        by_species.setdefault(sid, {})[lid] = row['name'].strip()

species_rows = []
# Mapas de búsqueda exacta de nombre de especie (en minúsculas) -> diccionario de traducciones
name_to_species = {}

for sid, lmap in sorted(by_species.items()):
    n_es = lmap.get(7) or lmap.get(9)
    n_en = lmap.get(9)
    n_ja = lmap.get(1)
    n_ko = lmap.get(3)
    n_zh_tw = lmap.get(4)
    n_zh_cn = lmap.get(12) or n_zh_tw
    n_fr = lmap.get(5)
    n_de = lmap.get(6)
    n_it = lmap.get(8)

    species_rows.append((sid, n_es, n_en, n_ja, n_ko, n_zh_tw, n_zh_cn, n_fr, n_de, n_it))

    entry = {
        'es': n_es,
        'en': n_en,
        'ja': n_ja,
        'ko': n_ko,
        'zh': n_zh_tw or n_zh_cn,
        'fr': n_fr,
        'de': n_de,
        'it': n_it,
    }
    for val in [n_en, n_es, n_ja, n_ko, n_zh_tw, n_zh_cn, n_fr, n_de, n_it]:
        if val:
            name_to_species[val.lower()] = entry

cursor.executemany('''
INSERT OR REPLACE INTO species_translations
(species_id, name_es, name_en, name_ja, name_ko, name_zh_tw, name_zh_cn, name_fr, name_de, name_it)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''', species_rows)
print(f"  -> {len(species_rows)} especies Pokémon indexadas en todos los idiomas.")

# Función para traducir nombres de cartas con sufijos comunes (ex, EX, GX, V, VMAX, VSTAR, LV.X, δ)
SUFFIX_RE = re.compile(
    r'^(.+?)\s*(ex|EX|GX|VMAX|VSTAR|V-UNION|V|BREAK|LV\.X|Prime|LEGEND|δ|（デルタ種）|\(Delta\))?$'
)

def translate_card_name(raw_name):
    if not raw_name:
        return None
    clean = raw_name.strip()
    lower = clean.lower()
    if lower in name_to_species:
        return (name_to_species[lower], '')

    # Probar separando sufijos como "ピカチュウVMAX", "リザードンex", "Charizard ex"
    m = SUFFIX_RE.match(clean)
    if m and m.group(2):
        base = m.group(1).strip().lower()
        suffix = m.group(2).strip()
        if suffix in ('（デルタ種）', '(Delta)'):
            suffix = 'δ'
        if base in name_to_species:
            return (name_to_species[base], suffix)

    # Prefijos Mega en japonés ("MリザードンEX" -> "M Charizard EX")
    if clean.startswith('M') and len(clean) > 2:
        rem = clean[1:].strip()
        m2 = SUFFIX_RE.match(rem)
        if m2:
            base = m2.group(1).strip().lower()
            suffix = m2.group(2) or ''
            if base in name_to_species:
                return (name_to_species[base], f"M|{suffix}")

    return None

def format_translated(species_dict, lang_key, suffix_info):
    base_name = species_dict.get(lang_key)
    if not base_name:
        return None
    if not suffix_info:
        return base_name
    if suffix_info.startswith('M|'):
        suf = suffix_info.split('|', 1)[1]
        if lang_key == 'ja':
            return f"M{base_name}{suf}"
        return f"M {base_name} {suf}".strip()
    if lang_key in ('ja', 'zh') and suffix_info in ('V', 'VMAX', 'VSTAR', 'ex', 'EX', 'GX'):
        return f"{base_name}{suffix_info}"
    return f"{base_name} {suffix_info}"

# 3. Descargar TODAS las colecciones (sets) en los 15 idiomas oficiales de TCGdex
ALL_LANGS = ['en', 'es', 'ja', 'ko', 'zh-tw', 'zh-cn', 'fr', 'de', 'it', 'pt', 'th', 'id', 'nl', 'pl', 'ru']
print("2/4 Descargando todas las colecciones (sets) en 15 idiomas...")

with ThreadPoolExecutor(max_workers=10) as pool:
    sets_by_lang = dict(zip(ALL_LANGS, pool.map(lambda l: fetch_json(f"https://api.tcgdex.net/v2/{l}/sets") or [], ALL_LANGS)))

sets_catalog = {}
for lang in ALL_LANGS:
    for s in sets_by_lang.get(lang, []):
        s_id = (s.get('id') or '').lower().strip()
        if not s_id:
            continue
        c_count = s.get('cardCount') or {}
        off = c_count.get('official') or c_count.get('total') or 0
        tot = c_count.get('total') or off
        s_name = (s.get('name') or '').strip()

        if s_id not in sets_catalog:
            sets_catalog[s_id] = {
                'id': s_id,
                'code': s_id,
                'official_count': off,
                'total_count': tot,
                'primary_lang': lang,
                'names': {},
            }
        else:
            if off > 0 and sets_catalog[s_id]['official_count'] == 0:
                sets_catalog[s_id]['official_count'] = off
            if tot > 0 and sets_catalog[s_id]['total_count'] == 0:
                sets_catalog[s_id]['total_count'] = tot

        if s_name:
            sets_catalog[s_id]['names'][lang] = s_name

# Enriquecer nombres oficiales en español (incluyendo sets LATAM) e inglés para sets japoneses y asiáticos
MASTER_SET_NAMES = {
    # Sets occidentales con traducción oficial en España / LATAM
    'base1': {'es': 'Base Set (Edición Básica)', 'en': 'Base Set'},
    'base2': {'es': 'Jungla', 'en': 'Jungle'},
    'base3': {'es': 'Fósil', 'en': 'Fossil'},
    'ex1': {'es': 'EX Rubí y Zafiro', 'en': 'EX Ruby & Sapphire'},
    'ex10': {'es': 'EX Fuerzas Ocultas', 'en': 'EX Unseen Forces'},
    'dp1': {'es': 'Diamante y Perla', 'en': 'Diamond & Pearl'},
    'dp2': {'es': 'Tesoros Misteriosos', 'en': 'Mysterious Treasures'},
    'dp3': {'es': 'Maravillas Secretas', 'en': 'Secret Wonders'},
    'dp4': {'es': 'Grandes Encuentros', 'en': 'Great Encounters'},
    'dp6': {'es': 'Despertar de las Leyendas', 'en': 'Legends Awakened'},
    'dp7': {'es': 'Frente Tormentoso', 'en': 'Stormfront'},
    'pl1': {'es': 'Platino', 'en': 'Platinum'},
    'pl3': {'es': 'Platino-Victorias Supremas', 'en': 'Supreme Victors'},
    'pl4': {'es': 'Platino-Arceus', 'en': 'Arceus'},
    'hgss1': {'es': 'HeartGold & SoulSilver', 'en': 'HeartGold & SoulSilver'},
    'hgss2': {'es': 'HS-Liberados', 'en': 'HS—Unleashed'},
    'bw1': {'es': 'Negro y Blanco', 'en': 'Black & White'},
    'bw2': {'es': 'Negro y Blanco-Fuerzas Emergentes', 'en': 'Emerging Powers'},
    'bw3': {'es': 'Negro y Blanco-Nobles Victorias', 'en': 'Noble Victories'},
    'bw4': {'es': 'Negro y Blanco-Próximos Destinos', 'en': 'Next Destinies'},
    'bw6': {'es': 'Negro y Blanco-Dragones Majestuosos', 'en': 'Dragons Exalted'},
    'bw7': {'es': 'Negro y Blanco-Fronteras Cruzadas', 'en': 'Boundaries Crossed'},
    'bw8': {'es': 'Negro y Blanco-Tormenta Plasma', 'en': 'Plasma Storm'},
    'bw9': {'es': 'Negro y Blanco-Glaciación Plasma', 'en': 'Plasma Freeze'},
    'me03': {'es': 'Megaevolución-Orden Perfecto', 'en': 'ME—Perfect Order'},
    'me04': {'es': 'Megaevolución-Caos Creciente', 'en': 'ME—Chaos Rising'},
    'me05': {'es': 'Megaevolución-Oscuridad Absoluta', 'en': 'ME—Pitch Black'},
    'me06': {'es': 'Megaevolución-Dominio Delta', 'en': 'ME—Delta Reign'},
    '30th': {'es': 'Celebración 30.º Aniversario', 'en': '30th Celebration'},
    # Eras Clásicas a MEGA en Japón (nombres internacionales de referencia)
    'pmcg1': {'en': 'Expansion Pack (Base Set JP)'},
    'pmcg2': {'en': 'Pokémon Jungle (JP)'},
    'pmcg3': {'en': 'Mystery of the Fossils (JP)'},
    'pmcg4': {'en': 'Rocket Gang (JP)'},
    'pmcg5': {'en': "Leaders' Stadium (JP)"},
    'pmcg6': {'en': 'Challenge from the Darkness (JP)'},
    'vs1': {'en': 'Pokémon VS'},
    'web1': {'en': 'Pokémon Web'},
    'e1': {'en': 'Base Expansion Pack (e-Card)'},
    'e2': {'en': 'The Town on No Map'},
    'e3': {'en': 'Wind from the Sea'},
    'e4': {'en': 'Split Earth'},
    'e5': {'en': 'Mysterious Mountains'},
    'adv1': {'en': 'ADV Expansion Pack'},
    'adv2': {'en': 'Miracle of the Desert'},
    'adv3': {'en': 'Rulers of the Heavens'},
    'adv4': {'en': 'Magma VS Aqua: Two Ambitions'},
    'adv5': {'en': 'Undone Seal'},
    'pcg1': {'en': 'Flight of Legends'},
    'pcg2': {'en': 'Clash of the Blue Sky'},
    'pcg3': {'en': 'Rocket Gang Strikes Back'},
    'pcg4': {'en': 'Golden Sky, Silvery Ocean'},
    'pcg5': {'en': 'Mirage Forest'},
    'pcg6': {'en': 'Holon Research Tower'},
    'pcg7': {'en': 'Holon Phantom'},
    'pcg8': {'en': 'Miracle Crystal'},
    'pcg9': {'en': 'Offense and Defense of the Furthest Ends'},
    'pcg10': {'en': 'World Champions Pack'},
    's6a': {'en': 'Eevee Heroes'},
    's8a': {'en': '25th Anniversary Collection'},
    's8b': {'en': 'VMAX Climax'},
    's12a': {'en': 'VSTAR Universe'},
    'sv2a': {'en': 'Pokémon Card 151'},
    'sv4a': {'en': 'Shiny Treasure ex'},
    'sv8a': {'en': 'Terastal Festival ex'},
    'sv9': {'en': 'Battle Partners'},
    'sv9a': {'en': 'Heat Wave Arena'},
    'sv10': {'en': 'The Glory of Team Rocket'},
    'sv11b': {'en': 'Black Bolt (JP)'},
    'sv11w': {'en': 'White Flare (JP)'},
    'm1l': {'en': 'Mega Brave'},
    'm1s': {'en': 'Mega Symphonia'},
    'm2': {'en': 'Inferno X'},
    'm2a': {'en': 'MEGA Dream ex'},
    'm3': {'en': 'Nihil Zero'},
    'm4': {'en': 'Ninja Spinner'},
    'm5': {'en': 'Abyss Eye'},
    'm6': {'en': 'Storm Emeralda'},
    'm6a': {'en': '30th CELEBRATION (JP)'},
    'm7': {'en': 'Aura Seeker', 'ja': 'オーラシーカー'},
    # Sets exclusivos de Chino Tradicional y Simplificado
    'ac1a': {'en': 'All Stars Collection Set A', 'zh-tw': '眾星雲集組合篇 SET A'},
    'ac1b': {'en': 'All Stars Collection Set B', 'zh-tw': '眾星雲集組合篇 SET B'},
    'ac2a': {'en': 'Dreams Come True Collection Set A', 'zh-tw': '美夢成真組合篇 SET A'},
    'ac2b': {'en': 'Dreams Come True Collection Set B', 'zh-tw': '美夢成真組合篇 SET B'},
    'csm1ac': {'en': 'Across Horizons A (CN)'},
    'csm1bc': {'en': 'Across Horizons B (CN)'},
    'csm1cc': {'en': 'Across Horizons C (CN)'},
    'csm2ac': {'en': 'Shadows of Radiance A (CN)'},
    'csm2bc': {'en': 'Shadows of Radiance B (CN)'},
    'csm2cc': {'en': 'Shadows of Radiance C (CN)'},
    'csm2.5c': {'en': 'Shining Synergy (CN)'},
    'cs1ac': {'en': 'Final Impact A (CN)'},
    'cs1bc': {'en': 'Final Impact B (CN)'},
    'cs2ac': {'en': 'Mirage Journey A (CN)'},
    'cs2bc': {'en': 'Mirage Journey B (CN)'},
    'cs3ac': {'en': 'Primordial Arts A (CN)'},
    'cs3bc': {'en': 'Primordial Arts B (CN)'},
    'cs4ac': {'en': 'Nine Colors Gathering Friend (CN)'},
    'cs4bc': {'en': 'Nine Colors Gathering Origin (CN)'},
    'cs5ac': {'en': 'Brave Stars A (CN)'},
    'cs5bc': {'en': 'Brave Stars B (CN)'},
    'cs6ac': {'en': 'Shadow of the Blue Sea A (CN)'},
    'cs6bc': {'en': 'Shadow of the Blue Sea B (CN)'},
    'csv1c': {'en': 'First Step (CN)'},
    'csv3c': {'en': 'Fearless Terastal (CN)'},
}

for s_id, overrides in MASTER_SET_NAMES.items():
    if s_id not in sets_catalog:
        sets_catalog[s_id] = {
            'id': s_id,
            'code': s_id,
            'official_count': 0,
            'total_count': 0,
            'primary_lang': 'ja' if 'ja' in overrides else ('zh-tw' if 'zh-tw' in overrides else 'en'),
            'names': {},
        }
    for k, v in overrides.items():
        if not sets_catalog[s_id]['names'].get(k):
            sets_catalog[s_id]['names'][k] = v

set_rows = []
for s_id, info in sets_catalog.items():
    names = info['names']
    n_es = names.get('es')
    n_en = names.get('en')
    n_ja = names.get('ja')
    n_ko = names.get('ko')
    n_zh = names.get('zh-tw') or names.get('zh-cn')
    n_fr = names.get('fr')
    n_de = names.get('de')
    n_it = names.get('it')
    n_pt = names.get('pt')
    n_th = names.get('th')
    n_id = names.get('id')
    display_name = n_es or n_en or n_ja or n_zh or n_ko or n_fr or n_th or n_id or s_id.upper()
    primary_lang = 'es' if n_es else ('en' if n_en else ('ja' if n_ja else info['primary_lang']))

    set_rows.append((
        s_id,
        display_name,
        n_es,
        n_en,
        n_ja,
        n_ko,
        n_zh,
        n_fr,
        n_de,
        n_it,
        n_pt,
        n_th,
        n_id,
        s_id,
        info['official_count'],
        info['total_count'],
        primary_lang,
    ))

cursor.executemany('''
INSERT OR REPLACE INTO sets
(id, name, name_es, name_en, name_ja, name_ko, name_zh, name_fr, name_de, name_it, name_pt, name_th, name_id, code, official_count, total_count, language)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''', set_rows)
print(f"  -> {len(set_rows)} colecciones únicas indexadas.")

# 4. Descargar TODAS las cartas de todos los idiomas en paralelo desde TCGdex
print("3/4 Descargando todas las cartas de todos los idiomas desde TCGdex...")
with ThreadPoolExecutor(max_workers=10) as pool:
    cards_by_lang = dict(zip(ALL_LANGS, pool.map(lambda l: fetch_json(f"https://api.tcgdex.net/v2/{l}/cards") or [], ALL_LANGS)))

for lang in ALL_LANGS:
    print(f"  -> [{lang}] {len(cards_by_lang.get(lang, []))} cartas recibidas")

cards_catalog = {}

for lang in ALL_LANGS:
    for c in cards_by_lang.get(lang, []):
        raw_id = (c.get('id') or '').strip()
        if not raw_id:
            continue
        cid = raw_id.lower()
        local_id = str(c.get('localId') or '').strip()
        local_lower = local_id.lower()

        if local_lower and cid.endswith('-' + local_lower):
            set_id = cid[:-len(local_lower) - 1]
        elif '-' in cid:
            set_id = cid.rsplit('-', 1)[0]
        else:
            set_id = cid

        entry = cards_catalog.get(cid)
        if entry is None:
            raw_digits = ''.join(ch for ch in local_id if ch.isdigit())
            num_int = int(raw_digits) if raw_digits else None
            set_info = sets_catalog.get(set_id, {})
            tot = set_info.get('official_count') or set_info.get('total_count') or 0

            entry = {
                'id': cid,
                'set_id': set_id,
                'local_id': local_id,
                'number_int': num_int,
                'total_in_set': tot,
                'names': {},
                'images': {},
                'cardmarket_id': None,
            }
            cards_catalog[cid] = entry

        c_name = (c.get('name') or '').strip()
        if c_name:
            entry['names'][lang] = c_name

        c_img = (c.get('image') or '').strip()
        if c_img:
            entry['images'][lang] = f"{c_img}/high.webp"

# 5. Seed explícito de S8a (25th Anniversary Japón) y cel25 con sus cardmarket_id
s8a_seed = [
    ('001', 1, 'ホウオウ', 'Ho-Oh', 'Ho-Oh', 'https://assets.tcgdex.net/zh-tw/S/S8a/001/high.webp', 576752),
    ('002', 2, 'レシラム', 'Reshiram', 'Reshiram', 'https://assets.tcgdex.net/zh-tw/S/S8a/002/high.webp', 576753),
    ('003', 3, 'カイオーガ', 'Kyogre', 'Kyogre', 'https://assets.tcgdex.net/zh-tw/S/S8a/003/high.webp', 576754),
    ('004', 4, 'パルキア', 'Palkia', 'Palkia', 'https://assets.tcgdex.net/zh-tw/S/S8a/004/high.webp', 576755),
    ('005', 5, 'ピカチュウ', 'Pikachu', 'Pikachu', 'https://assets.tcgdex.net/zh-tw/S/S8a/005/high.webp', 576756),
    ('006', 6, 'なみのりピカチュウV', 'Surfing Pikachu V', 'Pikachu Surfista V', 'https://assets.tcgdex.net/zh-tw/S/S8a/006/high.webp', 576757),
    ('007', 7, 'なみのりピカチュウVMAX', 'Surfing Pikachu VMAX', 'Pikachu Surfista VMAX', 'https://assets.tcgdex.net/zh-tw/S/S8a/007/high.webp', 576758),
    ('008', 8, 'そらをとぶピカチュウV', 'Flying Pikachu V', 'Pikachu Vuelo V', 'https://assets.tcgdex.net/zh-tw/S/S8a/008/high.webp', 576759),
    ('009', 9, 'そらをとぶピカチュウVMAX', 'Flying Pikachu VMAX', 'Pikachu Vuelo VMAX', 'https://assets.tcgdex.net/zh-tw/S/S8a/009/high.webp', 576760),
    ('010', 10, 'ゼクロム', 'Zekrom', 'Zekrom', 'https://assets.tcgdex.net/zh-tw/S/S8a/010/high.webp', 576761),
    ('011', 11, 'ミュウ', 'Mew', 'Mew', 'https://assets.tcgdex.net/zh-tw/S/S8a/011/high.webp', 576762),
    ('012', 12, 'ゼルネアス', 'Xerneas', 'Xerneas', 'https://assets.tcgdex.net/zh-tw/S/S8a/012/high.webp', 576763),
    ('013', 13, 'イベルタル', 'Yveltal', 'Yveltal', 'https://assets.tcgdex.net/zh-tw/S/S8a/013/high.webp', 576764),
    ('014', 14, 'ディアルガ', 'Dialga', 'Dialga', 'https://assets.tcgdex.net/zh-tw/S/S8a/014/high.webp', 576765),
    ('015', 15, 'コスモッグ', 'Cosmog', 'Cosmog', 'https://assets.tcgdex.net/zh-tw/S/S8a/015/high.webp', 576766),
    ('016', 16, 'コスモウム', 'Cosmoem', 'Cosmoem', 'https://assets.tcgdex.net/zh-tw/S/S8a/016/high.webp', 576767),
    ('017', 17, 'ソルガレオ', 'Solgaleo', 'Solgaleo', 'https://assets.tcgdex.net/zh-tw/S/S8a/017/high.webp', 576768),
    ('018', 18, 'ルナアーラ', 'Lunala', 'Lunala', 'https://assets.tcgdex.net/zh-tw/S/S8a/018/high.webp', 576769),
    ('019', 19, 'ザシアンV', 'Zacian V', 'Zacian V', 'https://assets.tcgdex.net/zh-tw/S/S8a/019/high.webp', 576770),
    ('020', 20, 'ザマゼンタV', 'Zamazenta V', 'Zamazenta V', 'https://assets.tcgdex.net/zh-tw/S/S8a/020/high.webp', 576771),
    ('021', 21, 'グラードン', 'Groudon', 'Groudon', 'https://assets.tcgdex.net/zh-tw/S/S8a/021/high.webp', 576772),
    ('022', 22, 'カプ・コケコ', 'Tapu Koko', 'Tapu Koko', 'https://assets.tcgdex.net/zh-tw/S/S8a/022/high.webp', 576773),
    ('023', 23, 'ネクロズマ', 'Necrozma', 'Necrozma', 'https://assets.tcgdex.net/zh-tw/S/S8a/023/high.webp', 576774),
    ('024', 24, 'ルギア', 'Lugia', 'Lugia', 'https://assets.tcgdex.net/zh-tw/S/S8a/024/high.webp', 576775),
    ('025', 25, 'オーキド博士の研究', "Professor's Research", 'Investigación de Profesores', 'https://assets.tcgdex.net/zh-tw/S/S8a/025/high.webp', 576776),
    ('026', 26, 'オーキド博士の研究', "Professor's Research", 'Investigación de Profesores', 'https://assets.tcgdex.net/zh-tw/S/S8a/026/high.webp', 576777),
    ('027', 27, 'ミュウ', 'Mew UR', 'Mew Dorado', 'https://assets.tcgdex.net/zh-tw/S/S8a/027/high.webp', 576778),
    ('028', 28, '基本エネルギー', 'Basic Energy', 'Energía Básica', 'https://assets.tcgdex.net/zh-tw/S/S8a/028/high.webp', 576779),
]

for loc_id, n_int, n_ja, n_en, n_es, img, cm_id in s8a_seed:
    cid = f"s8a-{loc_id}"
    entry = cards_catalog.setdefault(cid, {
        'id': cid,
        'set_id': 's8a',
        'local_id': loc_id,
        'number_int': n_int,
        'total_in_set': 28,
        'names': {},
        'images': {},
        'cardmarket_id': cm_id,
    })
    entry['names']['ja'] = n_ja
    entry['names']['en'] = n_en
    entry['names']['es'] = n_es
    entry['images'].setdefault('ja', img)
    entry['cardmarket_id'] = cm_id

# 6. Enriquecer nombres multilingües e imágenes y guardar en SQLite
print("4/4 Enriqueciendo traducciones cruzadas y construyendo tabla de cartas...")
card_rows = []
enriched_count = 0

for cid, entry in cards_catalog.items():
    names = entry['names']
    images = entry['images']

    n_ja = names.get('ja')
    n_en = names.get('en')
    n_es = names.get('es')
    n_ko = names.get('ko')
    n_zh = names.get('zh-tw') or names.get('zh-cn')
    n_fr = names.get('fr')
    n_de = names.get('de')
    n_it = names.get('it')
    n_pt = names.get('pt')
    n_th = names.get('th')
    n_id = names.get('id')

    # Intentar traducir automáticamente cualquier idioma faltante usando las 1.025 especies Pokémon
    source_name = n_en or n_ja or n_es or n_zh or n_ko or n_fr or n_de or n_th or n_id
    tr = translate_card_name(source_name)
    if tr:
        sp_dict, suffix = tr
        enriched_count += 1
        if not n_en:
            n_en = format_translated(sp_dict, 'en', suffix)
        if not n_es:
            n_es = format_translated(sp_dict, 'es', suffix)
        if not n_ja:
            n_ja = format_translated(sp_dict, 'ja', suffix)
        if not n_ko:
            n_ko = format_translated(sp_dict, 'ko', suffix)
        if not n_zh:
            n_zh = format_translated(sp_dict, 'zh', suffix)
        if not n_fr:
            n_fr = format_translated(sp_dict, 'fr', suffix)
        if not n_de:
            n_de = format_translated(sp_dict, 'de', suffix)
        if not n_it:
            n_it = format_translated(sp_dict, 'it', suffix)

    # Si sigue faltando español pero hay inglés (o viceversa) en sets occidentales
    if not n_es and n_en:
        n_es = n_en
    if not n_en and n_es:
        n_en = n_es

    # Selección de URL de imagen con fallback a pokemontcg.io para sets occidentales
    img_url = (
        images.get('es')
        or images.get('en')
        or images.get('ja')
        or images.get('zh-tw')
        or images.get('fr')
        or images.get('de')
        or images.get('it')
        or images.get('pt')
        or images.get('ko')
        or images.get('zh-cn')
        or images.get('th')
        or images.get('id')
        or ''
    )

    if not img_url and (names.get('en') or names.get('es')):
        # Fallback para sub-sets occidentales como swsh11tg, swsh12tg, sm6, etc.
        set_id_clean = entry['set_id'].replace('.', 'pt')
        loc_clean = entry['local_id']
        img_url = f"https://images.pokemontcg.io/{set_id_clean}/{loc_clean}_hires.png"

    card_rows.append((
        entry['id'],
        entry['set_id'],
        entry['local_id'],
        entry['number_int'],
        entry['total_in_set'],
        n_ja,
        n_en,
        n_es,
        n_ko,
        n_zh,
        n_fr,
        n_de,
        n_it,
        n_pt,
        n_th,
        n_id,
        img_url,
        entry['cardmarket_id'],
    ))

cursor.executemany('''
INSERT OR REPLACE INTO cards
(id, set_id, local_id, number_int, total_in_set, name_ja, name_en, name_es, name_ko, name_zh, name_fr, name_de, name_it, name_pt, name_th, name_id, image_url, cardmarket_id)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''', card_rows)

print("Creando índices de alta velocidad y compactando base de datos...")
cursor.execute('CREATE INDEX idx_cards_set_local ON cards(set_id, local_id)')
cursor.execute('CREATE INDEX idx_cards_total_num ON cards(total_in_set, number_int)')
cursor.execute('CREATE INDEX idx_cards_name_ja ON cards(name_ja)')
cursor.execute('CREATE INDEX idx_cards_name_en ON cards(name_en)')
cursor.execute('CREATE INDEX idx_cards_name_es ON cards(name_es)')
cursor.execute('CREATE INDEX idx_cards_name_ko ON cards(name_ko)')
cursor.execute('CREATE INDEX idx_cards_name_zh ON cards(name_zh)')
cursor.execute('CREATE INDEX idx_sets_count ON sets(official_count)')
cursor.execute('CREATE INDEX idx_species_ja ON species_translations(name_ja)')
cursor.execute('CREATE INDEX idx_species_ko ON species_translations(name_ko)')
cursor.execute('CREATE INDEX idx_species_zh_tw ON species_translations(name_zh_tw)')
cursor.execute('CREATE INDEX idx_species_zh_cn ON species_translations(name_zh_cn)')

conn.commit()
cursor.execute('VACUUM')
cursor.execute('ANALYZE')
conn.commit()

# Estadísticas finales
cursor.execute('SELECT COUNT(*) FROM sets')
num_sets = cursor.fetchone()[0]
cursor.execute('SELECT COUNT(*) FROM cards')
num_cards = cursor.fetchone()[0]
cursor.execute('SELECT COUNT(*) FROM cards WHERE name_es IS NOT NULL')
num_es = cursor.fetchone()[0]
cursor.execute('SELECT COUNT(*) FROM cards WHERE name_en IS NOT NULL')
num_en = cursor.fetchone()[0]
cursor.execute('SELECT COUNT(*) FROM cards WHERE name_ja IS NOT NULL')
num_ja = cursor.fetchone()[0]
cursor.execute('SELECT COUNT(*) FROM cards WHERE name_ko IS NOT NULL')
num_ko = cursor.fetchone()[0]
cursor.execute('SELECT COUNT(*) FROM cards WHERE name_zh IS NOT NULL')
num_zh = cursor.fetchone()[0]
cursor.execute('SELECT COUNT(*) FROM cards WHERE name_fr IS NOT NULL')
num_fr = cursor.fetchone()[0]

db_size_mb = os.path.getsize(DB_PATH) / (1024 * 1024)

print("============================================================")
print(f"Catálogo generado con éxito en: {DB_PATH} ({db_size_mb:.2f} MB)")
print(f"Total colecciones (sets): {num_sets}")
print(f"Total cartas únicas:      {num_cards} ({enriched_count} enriquecidas entre idiomas)")
print(f"  - Con nombre Español:   {num_es}")
print(f"  - Con nombre Inglés:    {num_en}")
print(f"  - Con nombre Japonés:   {num_ja}")
print(f"  - Con nombre Coreano:   {num_ko}")
print(f"  - Con nombre Chino:     {num_zh}")
print(f"  - Con nombre Francés:   {num_fr}")
print("============================================================")

conn.close()
