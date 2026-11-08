import sqlite3
import json
import urllib.request
import os

DB_DIR = os.path.join('assets', 'database')
os.makedirs(DB_DIR, exist_ok=True)
DB_PATH = os.path.join(DB_DIR, 'tcg_catalog.db')
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# 1. Crear tablas optimizadas
cursor.execute('''
CREATE TABLE sets (
    id TEXT PRIMARY KEY,
    name TEXT,
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
    image_url TEXT,
    cardmarket_id INTEGER,
    game TEXT DEFAULT 'pokemon'
)
''')

cursor.execute('CREATE INDEX idx_cards_set_local ON cards(set_id, local_id)')
cursor.execute('CREATE INDEX idx_cards_total_num ON cards(total_in_set, number_int)')
cursor.execute('CREATE INDEX idx_cards_name_ja ON cards(name_ja)')
cursor.execute('CREATE INDEX idx_cards_name_en ON cards(name_en)')
cursor.execute('CREATE INDEX idx_cards_name_es ON cards(name_es)')
cursor.execute('CREATE INDEX idx_sets_count ON sets(official_count)')

# 2. Descargar e indexar sets de TCGdex (JA, EN, ES)
headers = {'User-Agent': 'Mozilla/5.0'}

def fetch_json(url):
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=8) as res:
            return json.loads(res.read().decode())
    except Exception as e:
        return None

print("Descargando listado de colecciones...")
sets_ja = fetch_json('https://api.tcgdex.net/v2/ja/sets') or []
sets_en = fetch_json('https://api.tcgdex.net/v2/en/sets') or []
sets_es = fetch_json('https://api.tcgdex.net/v2/es/sets') or []

inserted_sets = set()
for lang, s_list in [('ja', sets_ja), ('en', sets_en), ('es', sets_es)]:
    for s in s_list:
        s_id = s.get('id', '')
        clean_id = s_id.lower().strip()
        if not clean_id or clean_id in inserted_sets:
            continue
        c_count = s.get('cardCount', {})
        off = c_count.get('official') or c_count.get('total') or 0
        tot = c_count.get('total') or off
        cursor.execute(
            'INSERT OR REPLACE INTO sets (id, name, code, official_count, total_count, language) VALUES (?, ?, ?, ?, ?, ?)',
            (clean_id, s.get('name', ''), clean_id, off, tot, lang)
        )
        inserted_sets.add(clean_id)

print(f"Total colecciones indexadas: {len(inserted_sets)}")

# 3. Seed de S8a (Celebraciones Japón - 28 cartas exactas)
s8a_cards = [
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
    ('028', 28, '基本エネルギー', 'Basic Energy', 'Energía Básica', 'https://assets.tcgdex.net/zh-tw/S/S8a/028/high.webp', 576779)
]

for loc_id, n_int, n_ja, n_en, n_es, img, cm_id in s8a_cards:
    card_id = f"s8a-{loc_id}"
    cursor.execute('''
    INSERT OR REPLACE INTO cards 
    (id, set_id, local_id, number_int, total_in_set, name_ja, name_en, name_es, image_url, cardmarket_id)
    VALUES (?, 's8a', ?, ?, 28, ?, ?, ?, ?, ?)
    ''', (card_id, loc_id, n_int, n_ja, n_en, n_es, img, cm_id))

# 4. Celebrations EN / cel25 (25 cartas)
for loc_id, n_int, n_ja, n_en, n_es, img, cm_id in s8a_cards[:25]:
    c_id = f"cel25-{int(loc_id)}"
    cursor.execute('''
    INSERT OR REPLACE INTO cards 
    (id, set_id, local_id, number_int, total_in_set, name_ja, name_en, name_es, image_url, cardmarket_id)
    VALUES (?, 'cel25', ?, ?, 25, ?, ?, ?, ?, ?)
    ''', (c_id, str(n_int), n_int, n_ja, n_en, n_es, f"https://images.pokemontcg.io/cel25/{n_int}.png", cm_id))

# 5. Descargar cartas de sets asiáticos/japoneses populares
asian_sets = ['S8a', 'S8b', 'S12a', 'SV2a', 'SV4a', 'SV1S', 'SV1V', 'SV3', 'SV5K', 'SV5M', 'SV6', 'SV7', 'SV8']
print(f"Descargando cartas de sets japoneses/asiáticos...")
for s_id in asian_sets:
    data = fetch_json(f"https://api.tcgdex.net/v2/zh-tw/sets/{s_id}")
    if not data or 'cards' not in data:
        continue
    c_count = data.get('cardCount', {})
    tot = c_count.get('official') or c_count.get('total') or 0
    cards = data.get('cards', [])
    for c in cards:
        c_id = c.get('id', '')
        l_id = c.get('localId', '')
        raw_num = ''.join(ch for ch in l_id if ch.isdigit())
        num_int = int(raw_num) if raw_num else None
        c_name = c.get('name', '')
        img = c.get('image', '')
        if img:
            img = f"{img}/high.webp"
        cursor.execute('''
        INSERT OR IGNORE INTO cards
        (id, set_id, local_id, number_int, total_in_set, name_ja, name_en, name_es, image_url)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (c_id.lower(), s_id.lower(), l_id, num_int, tot, c_name, None, None, img))

# 6. Descargar cartas de sets occidentales populares (Inglés y Español)
western_sets = [
    # ── Era Escarlata y Púrpura (Scarlet & Violet) ──
    'sv01', 'sv02', 'sv03', 'sv03.5', 'sv04', 'sv04.5', 'sv05', 'sv06', 'sv06.5', 'sv07', 'sv08', 'sv08.5',
    'svp',
    # ── Mega Evolution (me) ──
    'me01', 'me02', 'me02.5', 'me03', 'me04', 'me05', 'me06', 'mep',
    # ── Era Espada y Escudo (Sword & Shield) ──
    'swsh1', 'swsh2', 'swsh3', 'swsh3.5', 'swsh4', 'swsh4.5', 'swsh5', 'swsh6', 'swsh7', 'swsh8',
    'swsh9', 'swsh10', 'swsh11', 'swsh12', 'swsh12.5', 'crz', 'swshp',
    # ── Sub-sets Trainer Gallery (TG) y Galarian Gallery (GG) ──
    'swsh9tg', 'swsh10tg', 'swsh11tg', 'swsh12tg', 'swsh12.5gg',
    # ── Era Sol y Luna (Sun & Moon) y XY ──
    'sm1', 'sm2', 'sm3', 'sm3.5', 'sm4', 'sm5', 'sm6', 'sm7', 'sm7.5', 'sm8', 'sm9', 'sm10', 'sm11', 'sm115', 'sm12',
    'xy1', 'xy2', 'xy3', 'xy4', 'xy5', 'xy6', 'xy7', 'xy8', 'xy9', 'xy10', 'xy11', 'xy12',
    # ── Sets clásicos Blanco y Negro ──
    'bw1', 'bw2', 'bw3', 'bw4', 'bw5', 'bw6', 'bw7', 'bw8', 'bw9', 'bw10', 'bw11'
]
print(f"Descargando cartas de sets occidentales (EN / ES)...")
for s_id in western_sets:
    # Intentar obtener primero en español
    data_es = fetch_json(f"https://api.tcgdex.net/v2/es/sets/{s_id}")
    data_en = fetch_json(f"https://api.tcgdex.net/v2/en/sets/{s_id}")

    cards_es = {c.get('localId', ''): c for c in (data_es.get('cards', []) if data_es else [])}
    cards_en = {c.get('localId', ''): c for c in (data_en.get('cards', []) if data_en else [])}

    all_local_ids = set(cards_es.keys()).union(set(cards_en.keys()))
    if not all_local_ids:
        continue

    c_count = (data_es or data_en or {}).get('cardCount', {})
    tot = c_count.get('official') or c_count.get('total') or 0

    for l_id in all_local_ids:
        c_es = cards_es.get(l_id)
        c_en = cards_en.get(l_id)

        c_id = (c_es or c_en).get('id', f"{s_id}-{l_id}")
        raw_num = ''.join(ch for ch in l_id if ch.isdigit())
        num_int = int(raw_num) if raw_num else None

        name_es = c_es.get('name') if c_es else None
        name_en = c_en.get('name') if c_en else None

        # Para la imagen, si hay en español usarla, sino en inglés
        img = (c_es or {}).get('image') or (c_en or {}).get('image') or ''
        if img:
            img = f"{img}/high.webp"

        cursor.execute('''
        INSERT OR REPLACE INTO cards
        (id, set_id, local_id, number_int, total_in_set, name_ja, name_en, name_es, image_url)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (c_id.lower(), s_id.lower(), l_id, num_int, tot, None, name_en or name_es, name_es or name_en, img))

conn.commit()

# Estadísticas finales
cursor.execute('SELECT COUNT(*) FROM sets')
num_sets = cursor.fetchone()[0]
cursor.execute('SELECT COUNT(*) FROM cards')
num_cards = cursor.fetchone()[0]

db_size_mb = os.path.getsize(DB_PATH) / (1024 * 1024)

print(f"Catálogo generado con éxito en: {DB_PATH} ({db_size_mb:.2f} MB)")
print(f"Total colecciones: {num_sets}")
print(f"Total cartas precargadas: {num_cards}")

conn.close()
