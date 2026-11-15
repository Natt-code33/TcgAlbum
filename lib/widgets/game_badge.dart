import 'package:flutter/material.dart';
import '../models/pokemon_card.dart';

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
    this.iconSize = 13,
  });

  (String flag, String code, Color color) _resolveLangInfo(String? lang) {
    switch (lang?.toLowerCase()) {
      case 'es':
        return ('🇪🇸', 'ES', const Color(0xFFFFB800));
      case 'en':
        return ('🇬🇧', 'EN', const Color(0xFF00E5FF));
      case 'ja':
        return ('🇯🇵', 'JA', const Color(0xFFFF6B6B));
      case 'ko':
        return ('🇰🇷', 'KO', const Color(0xFF9B59B6));
      case 'zh':
      case 'zh-tw':
      case 'zh-cn':
        return ('🇨🇳', 'ZH', const Color(0xFF4CD97B));
      default:
        return ('⚡', 'PKM', Color(game.colorHex));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (flag, code, color) = _resolveLangInfo(language);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showLabel ? 7 : 5,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: TextStyle(fontSize: iconSize - 2)),
          if (showLabel) ...[
            const SizedBox(width: 4),
            Text(
              code,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
