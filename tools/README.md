# Catálogo de cartas

La app usa tres capas, en este orden:

1. **`assets/database/tcg_catalog.db`** — catálogo base (TCGdex + pokemontcg.io).
2. **`assets/data/catalog_extras.json`** — productos especiales que ninguna API
   indexa (Golden Box, promos raras, etc.). Se puede editar a mano.
3. **`assets/data/catalog_pricecharting.json`** — relleno generado a partir de
   PriceCharting. Incluye todas las colecciones que lista su categoría de
   Pokémon, con nombres traducidos a japonés/chino/coreano cuando la especie
   existe en `species_translations`.

Los tres se aplican sobre una copia local de SQLite. El catálogo base nunca se
modifica: las capas 2 y 3 sólo insertan sets/cartas que faltan.

## Actualizar el catálogo

```bash
python tools/scrape_pricecharting.py     # inglés, chino, productos especiales
python tools/scrape_pokellector_jp.py    # sets japoneses antiguos completos
python tools/build_pricecharting_catalog.py
```

Cada scraper tarda ~30-40 minutos y tiene caché reanudable.
El generador produce `assets/data/catalog_pricecharting.json`.

El workflow `.github/workflows/update-catalog.yml` lo ejecuta automáticamente
cada lunes y hace commit del JSON si cambia.

## En la app

- La capa 3 se aplica una vez por versión (`_currentPcVersion`).
- Además, la app descarga `catalog_pricecharting.json` del repositorio como
  máximo una vez al día y aplica versiones nuevas sin actualizar la APK.
- Los sets nuevos de TCGdex se descubren con `CatalogSyncService`
  (cada 12 h o desde Ajustes → «Buscar nuevas colecciones»).
- **Índice visual**: `assets/data/card_hashes.json` (37.290 dHash de 256 bits)
  permite proponer candidatas por la imagen aunque el OCR no lea nada. El
  botón **Catálogo** permite elegir set y número de forma determinista.

## Añadir un set manualmente

Edita `catalog_extras.json` y sube `version`. Estructura:

```json
{
  "version": 2,
  "sets": [
    {"id": "s8a-g", "name": "25th Anniversary Golden Box", "official_count": 15,
     "total_count": 15, "language": "ja"}
  ],
  "cards": [
    {"id": "s8a-g-003", "set_id": "s8a-g", "local_id": "003", "number_int": 3,
     "total_in_set": 15, "name_ja": "ピカチュウ", "name_en": "Pikachu",
     "image_url": "https://..."}
  ]
}
```
