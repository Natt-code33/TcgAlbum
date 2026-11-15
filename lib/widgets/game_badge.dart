import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pokemon_card.dart';
import '../theme/app_theme.dart';

class GameBadge extends StatelessWidget {
  final TcgGame game;
  final String? language;
  final bool showLabel;
  final double fontSize;
  final double iconSize;

  const GameBadge({
    super.key,
    this.game = TcgGame.pokemon,
    this.language,
    this.showLabel = true,
    this.fontSize = 10,
    this.iconSize = 12,
  });

  (String code, Color color) _resolveLangInfo(String? lang) {
    switch (lang?.toLowerCase()) {
      case 'es':
        return ('ES', AppTheme.cyanAccent);
      case 'en':
        return ('EN', const Color(0xFF38BDF8));
      case 'ja':
        return ('JA', const Color(0xFF60A5FA));
      case 'ko':
        return ('KO', const Color(0xFF818CF8));
      case 'zh':
      case 'zh-tw':
      case 'zh-cn':
        return ('ZH', const Color(0xFF2DD4BF));
      default:
        return ('TCG', AppTheme.cyanAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (code, color) = _resolveLangInfo(language);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showLabel ? 8 : 6,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: const Color(0xD90A1428),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.65), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.language_rounded,
            size: iconSize,
            color: color,
          ),
          if (showLabel) ...[
            const SizedBox(width: 4),
            Text(
              code,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
