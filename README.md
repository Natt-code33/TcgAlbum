# 🃏 TcgAlbum - Escáner y Gestor Inteligente Multi-TCG

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.5+-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Android-SDK%2021+-3DDC84?logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/ML%20Kit-Text%20Recognition-4285F4?logo=google&logoColor=white" alt="Google ML Kit">
  <img src="https://img.shields.io/badge/License-MIT-purple.svg" alt="License">
</p>

**TcgAlbum** es una aplicación móvil moderna desarrollada en **Flutter** diseñada para coleccionistas y jugadores de cartas coleccionables (TCG). Permite escanear, identificar con inteligencia visual/OCR, catalogar, valorar con precios oficiales de mercado y gestionar múltiples álbumes sin perder datos.

---

## 🚀 Juegos Soportados (Multi-TCG)

La aplicación integra APIs oficiales y de comunidad especializadas para cada juego de cartas:

| Juego | Base de Datos Principal | Precios y Mercado |
| :--- | :--- | :--- |
| ⚡ **Pokémon TCG** | TCGdex API + Pokémon TCG IO | Cardmarket (€) & PSA 10 |
| 🔮 **Magic: The Gathering** | Scryfall API | Cardmarket (€), TCGplayer |
| 👁️ **Yu-Gi-Oh!** | YGOPRODeck API | Cardmarket (€) |
| 🦖 **Digimon Card Game** | DigimonCard.io | Precios de referencia |
| 🏴‍☠️ **One Piece Card Game** | OPTCG API | Precios de referencia |
| ✨ **Disney Lorcana** | Lorcana API | Precios de referencia |

---

## ✨ Características Principales

### 📸 1. Escaneo Inteligente Dual (OCR + Reconocimiento Visual)
- **OCR Multilingüe con Google ML Kit:** Reconoce números de coleccionista, numeración fraccionaria (`025/165`), códigos de expansión y nombres en:
  - 🇪🇸 Español / 🇬🇧 Inglés
  - 🇯🇵 Japonés (Kanji / Hiragana / Katakana)
  - 🇰🇷 Coreano (Hangul)
  - 🇨🇳 Chino (Simplificado y Tradicional)
- **Comparación Visual Perceptual (dHash + Cuadrantes Cromáticos):**
  - Cuando el código OCR produce múltiples resultados o ambigüedad, la app compara el arte recortado de tu foto con las imágenes de las cartas candidatas usando un hash perceptual de 256 bits y pesos de colorimetría para seleccionar la variante exacta.

### 📚 2. Sistema Multi-Álbum
- Crea todos los álbumes que desees (ej: *Mi Colección Vintage*, *Mazo Competitivo*, *Para Intercambios*, *Sets Japoneses*).
- Cambia fácilmente de álbum desde la barra superior.
- Métricas independientes por álbum: total de cartas, valor estimado en euros y desglose por juego.

### 💾 3. Copia de Seguridad y Migración Segura (Anti-Pérdida)
- **100% Offline y Privado:** Tus cartas se guardan en el almacenamiento local persistente del dispositivo.
- **Exportar Backup (JSON):** Exporta tus álbumes completos con un toque para guardarlos o transferirlos a otro móvil.
- **Importar Backup:** Restaura tu colección en cualquier momento o actualiza la app sin miedo a perder tus datos.

### ✍️ 4. Editor Manual y Modo Personalizado
- Añade cartas manualmente buscando por nombre o número de referencia.
- Edita cartas ya añadidas: modifica el nombre, precio Cardmarket, precio PSA 10 o cámbiale la foto por una tomada directamente desde tu cámara o galería.

### 🎨 5. Diseño y Ergonomía
- Interfaz moderna en Modo Oscuro optimizada con Material Design 3.
- Espaciado ergonómico inferior para que ningún botón ni dato quede cortado detrás de la barra de navegación del sistema Android.
- Selector rápido de TCG para evitar confusiones de numeración entre diferentes juegos.

---

## 🛠️ Tecnologías y Librerías

- **Framework:** [Flutter](https://flutter.dev) (Dart 3)
- **Visión y OCR:** `google_mlkit_text_recognition` (modelos latino, japonés, coreano y chino)
- **Cámara:** `camera` + `image_picker`
- **Procesamiento de Imagen:** `image` (dHash, redimensión y normalización de imagen)
- **Almacenamiento Local:** `shared_preferences` con serialización JSON estructurada
- **Red y Caché:** `http`, `cached_network_image`
- **Utilidades:** `intl`, `path_provider`, `share_plus`, `file_picker`

---

## 📥 Instalación y Desarrollo

### Requisitos Previos
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.5 o superior
- [Android Studio](https://developer.android.com/studio) con SDK 21 o superior
- Dispositivo físico Android o emulador con cámara habilitada

### Pasos para compilar:

1. **Clonar el repositorio:**
   ```bash
   git clone https://github.com/Natt-code33/TcgAlbum.git
   cd TcgAlbum
   ```

2. **Instalar dependencias:**
   ```bash
   flutter pub get
   ```

3. **Ejecutar en modo depuración:**
   ```bash
   flutter run
   ```

4. **Compilar APK de lanzamiento:**
   ```bash
   flutter build apk --release
   ```
   El APK resultante estará disponible en `build/app/outputs/flutter-apk/app-release.apk`.

---

## 📱 Guía de Uso Rápido

1. **Selecciona tu Álbum:** En la pantalla principal, pulsa sobre el nombre del álbum actual para cambiarlo o crear uno nuevo con el botón `+`.
2. **Escanea una Carta:** Pulsa el botón flotante con el icono de cámara.
   - Selecciona el TCG correspondiente (Pokémon, MTG, Yu-Gi-Oh!, etc.).
   - Ajusta la carta dentro del marco guía y presiona el obturador.
   - La app detectará el código, comparará el arte visual y te mostrará la mejor coincidencia junto con las alternativas.
3. **Consulta Precios:** Revisa el valor estimado en Cardmarket y el precio PSA 10.
4. **Haz Copias de Seguridad:** Desde el menú de opciones del álbum, exporta tu copia de seguridad periódicamente para mantener tus cartas a salvo.

---

## 🤝 Contribuciones

¡Las contribuciones, sugerencias y reportes de errores son bienvenidos!
1. Haz un Fork del proyecto.
2. Crea una rama para tu función (`git checkout -b feature/NuevaMejora`).
3. Haz commit de tus cambios (`git commit -m 'Añade nueva funcionalidad'`).
4. Haz push a la rama (`git push origin feature/NuevaMejora`).
5. Abre un Pull Request.

---

## 📄 Licencia

Este proyecto está bajo la Licencia MIT. Consulta el archivo `LICENSE` para más información.
