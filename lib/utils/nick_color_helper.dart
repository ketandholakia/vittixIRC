import 'package:flutter/material.dart';

class NickColorHelper {
  static const List<Color> _palette = <Color>[
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.redAccent,
    Colors.indigo,
    Colors.cyan,
    Colors.deepOrange,
  ];

  static Color forNick(BuildContext context, String nick) {
    final key = nick.trim().toLowerCase();
    final index = key.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % _palette.length;
    final base = _palette[index];
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? Color.lerp(base, Colors.white, 0.12) ?? base
        : Color.lerp(base, Colors.black, 0.08) ?? base;
  }
}
