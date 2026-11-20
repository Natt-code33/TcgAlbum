// ============================================================
// services/name_matcher.dart
// Normalización y fuzzy matching de nombres de carta.
//
// Regla principal: el nombre puntúa, no filtra. Nunca se usa
// contains() para decidir que dos nombres son la misma carta.
// ============================================================

import 'dart:math';

String normalizeName(String input) {
  var value = input.toLowerCase().trim();

  const accents = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
    'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
  };
  accents.forEach((key, replacement) {
    value = value.replaceAll(key, replacement);
  });

  value = value.replaceAll(RegExp(r"[’'`´]"), '');
  // Ruido típico del OCR junto al nombre: "Pikachu LV", "40 HP", "PS 40".
  value = value.replaceAll(RegExp(r'\b(?:lv|hp|ps)\b\.?'), ' ');
  value = value.replaceAll(
    RegExp(
      r'\b(?:ex|gx|v|vmax|vstar|break|radiant|prime|star|lv\.?\s*x)\b',
      caseSensitive: false,
    ),
    ' ',
  );
  value = value.replaceAll(
    RegExp(r'[^a-z0-9\u3040-\u30ff\uac00-\ud7af\u4e00-\u9fff]+'),
    ' ',
  );
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Distancia de Damerau-Levenshtein con corte temprano.
int damerauLevenshtein(String a, String b, {int maxDist = 2}) {
  if ((a.length - b.length).abs() > maxDist) return maxDist + 1;

  var prev2 = List<int>.filled(b.length + 1, 0);
  var prev = List<int>.generate(b.length + 1, (j) => j);
  var curr = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    var rowMin = curr[0];

    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var value = min(
        min(curr[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );

      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        value = min(value, prev2[j - 2] + cost);
      }

      curr[j] = value;
      rowMin = min(rowMin, value);
    }

    if (rowMin > maxDist) return maxDist + 1;

    final tmp = prev2;
    prev2 = prev;
    prev = curr;
    curr = tmp;
  }

  return prev[b.length];
}

double nameSimilarity(String a, String b) {
  final left = normalizeName(a);
  final right = normalizeName(b);
  if (left.isEmpty || right.isEmpty) return 0;
  if (left == right) return 1;

  // Evita Mew -> Mewtwo, Porygon -> Porygon2, etc.
  final minLength = min(left.length, right.length);
  if (minLength < 5) return 0;
  if (RegExp(r'\d$').hasMatch(left) != RegExp(r'\d$').hasMatch(right)) {
    return 0;
  }

  final maxDist = minLength >= 8 ? 2 : 1;
  final distance = damerauLevenshtein(left, right, maxDist: maxDist);
  if (distance > maxDist) return 0;

  return (1 - distance / max(left.length, right.length))
      .clamp(0.0, 1.0)
      .toDouble();
}

double nameConfidence(String ocrName, Map<String, dynamic> row) {
  final target = normalizeName(ocrName);
  if (target.isEmpty) return 0;

  var best = 0.0;
  for (final column in const [
    'name_ja',
    'name_en',
    'name_es',
    'name_ko',
    'name_zh',
    'name_fr',
    'name_de',
    'name_it',
    'name_pt',
    'name_th',
    'name_id',
  ]) {
    final value = normalizeName((row[column] as String?) ?? '');
    if (value.isEmpty) continue;
    if (value == target) return 1;

    final similarity = nameSimilarity(target, value);
    if (similarity > best) best = similarity;
  }

  return best;
}
