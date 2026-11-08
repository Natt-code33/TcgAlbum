import 'package:flutter/material.dart';
import '../models/pokemon_card.dart';

class GameBadge extends StatelessWidget {
  final TcgGame game;
  final bool showLabel;
  final double fontSize;
  final double iconSize;

  const GameBadge({
    super.key,
    required this.game,
    this.showLabel = true,
    this.fontSize = 10,
    this.iconSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(game.colorHex);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showLabel ? 7 : 5,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(game.iconData, size: iconSize, color: color),
          if (showLabel) ...[
            const SizedBox(width: 4),
            Text(
              game.label,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
