import 'package:flutter/material.dart';

import '../components/tetris_logic.dart';

/// Цвета фигур в палитре проекта (яркие, со свечением в рендере).
Color tetrominoColor(Tetromino t) {
  switch (t) {
    case Tetromino.i:
      return const Color(0xFF4ECDC4); // бирюзовый
    case Tetromino.o:
      return const Color(0xFFFFD54F); // жёлтый
    case Tetromino.t:
      return const Color(0xFF7C5CFF); // фиолетовый
    case Tetromino.s:
      return const Color(0xFF5CE08A); // зелёный
    case Tetromino.z:
      return const Color(0xFFFF6FAE); // розовый
    case Tetromino.j:
      return const Color(0xFF5C8CFF); // синий
    case Tetromino.l:
      return const Color(0xFFFF9F45); // оранжевый
  }
}
