// ============================================================
// services/card_matcher.dart
// Puntuación de candidatas de carta.
//
// Clave fuerte: set_id + local_id. Después total + número.
// El nombre y la similitud visual puntúan; no descartan por sí solos.
// ============================================================

import '../models/card_number.dart';
import '../models/pokemon_card.dart';
import 'name_matcher.dart';

class ScoredCard {
  final PokemonCard card;
  final double score;

  const ScoredCard({required this.card, required this.score});
}

class CardMatcher {
  static double scoreRow({
    required Map<String, dynamic> row,
    CardNumber? number,
    String? ocrName,
    double visualScore = 0,
  }) {
    var identity = 0.0;

    final nameScore = (ocrName == null || ocrName.trim().isEmpty)
        ? 0.0
        : nameConfidence(ocrName, row);

    if (number != null) {
      final rowLocal = (row['local_id'] as String? ?? '').toLowerCase();
      final rowNumber = row['number_int'] as int?;
      final rowSet = (row['set_id'] as String? ?? '').toLowerCase();
      final rowTotal =
          (row['total_in_set'] as int?) ?? (row['set_official_count'] as int?);

      final localMatch = rowLocal == number.localId.toLowerCase() ||
          rowLocal == number.number.toLowerCase() ||
          (number.numberInt != null && rowNumber == number.numberInt);
      final setMatches = number.setCode != null &&
          number.setCode!.isNotEmpty &&
          rowSet == number.setCode!.toLowerCase();

      // Si el OCR leyó mal un dígito del número, el set + nombre exacto
      // siguen identificando la carta (104 -> 100 en una carta japonesa).
      // Solo se acepta un número a distancia 1 para no abrir la puerta a
      // cartas de otro número completamente distinto.
      if (!localMatch) {
        final closeNumber = rowLocal.isNotEmpty &&
            number.localId.isNotEmpty &&
            damerauLevenshtein(
                  rowLocal,
                  number.localId.toLowerCase(),
                  maxDist: 1,
                ) <=
                1;
        if (!(setMatches && nameScore >= 0.90 && closeNumber)) {
          return 0;
        }

        if (number.totalInt != null &&
            rowTotal != null &&
            rowTotal != number.totalInt) {
          return 0;
        }

        identity = 0.75;
        final fallback =
            (identity + 0.25 * nameScore).clamp(0.0, 1.0).toDouble();
        return fallback;
      }

      // Si el OCR leyó un total, una fila con otro total no es la misma carta.
      // (Los secret rares siguen funcionando porque total_in_set es el total base.)
      if (number.totalInt != null &&
          rowTotal != null &&
          rowTotal != number.totalInt) {
        return 0;
      }

      identity = 0.45;

      if (number.totalInt != null && rowTotal == number.totalInt) {
        identity += 0.20;
      }

      if (number.setCode != null && number.setCode!.isNotEmpty) {
        if (rowSet != number.setCode!.toLowerCase()) return 0;
        identity += 0.20;
      } else {
        identity += 0.10;
      }
    }

    // Número sin set: el nombre debe corroborar la identidad. Sin esto,
    // "#58/102" puede colar una carta de otro set con el mismo número
    // (p. ej. Litwick #58 en un set de 102) aunque el OCR leyera "Pikachu".
    if (number != null &&
        number.setCode == null &&
        ocrName != null &&
        ocrName.trim().isNotEmpty &&
        nameScore == 0) {
      return 0;
    }

    final namePart = number == null ? 0.90 * nameScore : 0.25 * nameScore;
    final visualPart = 0.15 * visualScore.clamp(0.0, 1.0).toDouble();

    return (identity + namePart + visualPart).clamp(0.0, 1.0).toDouble();
  }

  /// Solo se auto-selecciona si hay una candidata claramente por delante.
  /// Si hay empate o margen pequeño, la UI debe mostrar la lista.
  static bool shouldAutoSelect(List<ScoredCard> ranked) {
    if (ranked.isEmpty) return false;

    final best = ranked.first;
    if (best.score < 0.80) return false;

    if (ranked.length > 1 && best.score - ranked[1].score < 0.12) {
      return false;
    }

    return true;
  }
}
