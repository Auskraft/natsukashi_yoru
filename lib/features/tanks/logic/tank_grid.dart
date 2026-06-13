import 'tank_geometry.dart';

/// Тип тайла терреина.
enum TerrainType { empty, brick, steel, water, forest, ice, base }

/// Сетка терреина 13×13. Каждый тайл упакован в один int:
///   биты 0–2 — [TerrainType];
///   биты 3–6 — маска уцелевших квадрантов кирпича (TL=1, TR=2, BL=4, BR=8).
/// Кирпич рушится поквадрантно (квадрант = 4×4 суб-клетки), что даёт классический
/// «откусывающий» вид и позволяет проезжать в пробитую дыру.
class TerrainGrid {
  TerrainGrid() : _tiles = List<int>.filled(_count, 0);

  TerrainGrid.fromTiles(List<int> tiles)
      : assert(tiles.length == _count, 'ожидается $_count тайлов'),
        _tiles = List<int>.of(tiles);

  static const int _count = TankGeo.tiles * TankGeo.tiles;
  static const int _typeMask = 0x7;
  static const int _quadShift = 3;
  static const int _fullQuad = 0xF;

  final List<int> _tiles;

  int _idx(int tx, int ty) => ty * TankGeo.tiles + tx;

  bool inBounds(int tx, int ty) =>
      tx >= 0 && tx < TankGeo.tiles && ty >= 0 && ty < TankGeo.tiles;

  /// Тип тайла. За границей поля — несокрушимая сталь (стена).
  TerrainType typeAt(int tx, int ty) {
    if (!inBounds(tx, ty)) return TerrainType.steel;
    return TerrainType.values[_tiles[_idx(tx, ty)] & _typeMask];
  }

  /// Маска уцелевших квадрантов кирпича в тайле (0..15). Для рендера.
  int quadMaskAt(int tx, int ty) {
    if (!inBounds(tx, ty)) return 0;
    return (_tiles[_idx(tx, ty)] >> _quadShift) & _fullQuad;
  }

  /// Установить тайл. Для кирпича можно задать маску уцелевших квадрантов.
  void setTile(int tx, int ty, TerrainType type, {int quad = _fullQuad}) {
    if (!inBounds(tx, ty)) return;
    final q = type == TerrainType.brick ? quad : 0;
    _tiles[_idx(tx, ty)] = type.index | (q << _quadShift);
  }

  /// Индекс квадранта (0=TL,1=TR,2=BL,3=BR) для суб-точки внутри её тайла.
  int _quadIndex(int subX, int subY) {
    final qx = (subX % TankGeo.sub) ~/ TankGeo.half;
    final qy = (subY % TankGeo.sub) ~/ TankGeo.half;
    return qy * 2 + qx;
  }

  /// Блокирует ли суб-точка движение танка.
  bool solidForTank(int subX, int subY) {
    if (subX < 0 ||
        subX >= TankGeo.field ||
        subY < 0 ||
        subY >= TankGeo.field) {
      return true;
    }
    final tx = subX ~/ TankGeo.sub;
    final ty = subY ~/ TankGeo.sub;
    switch (typeAt(tx, ty)) {
      case TerrainType.empty:
      case TerrainType.forest:
      case TerrainType.ice:
        return false;
      case TerrainType.water:
      case TerrainType.steel:
      case TerrainType.base:
        return true;
      case TerrainType.brick:
        final bit = 1 << _quadIndex(subX, subY);
        return (quadMaskAt(tx, ty) & bit) != 0;
    }
  }

  /// Сколоть квадрант кирпича в суб-точке. true — там был кирпич (пуля гибнет);
  /// false — там уже дыра (пуля пролетает дальше).
  bool chipBrick(int subX, int subY) {
    final tx = subX ~/ TankGeo.sub;
    final ty = subY ~/ TankGeo.sub;
    if (typeAt(tx, ty) != TerrainType.brick) return false;
    final bit = 1 << _quadIndex(subX, subY);
    final cur = quadMaskAt(tx, ty);
    if ((cur & bit) == 0) return false;
    final next = cur & ~bit;
    if (next == 0) {
      _tiles[_idx(tx, ty)] = TerrainType.empty.index;
    } else {
      _tiles[_idx(tx, ty)] = TerrainType.brick.index | (next << _quadShift);
    }
    return true;
  }

  /// Снести стальной тайл (пуля достаточной силы). true — была сталь.
  bool breakSteel(int tx, int ty) {
    if (typeAt(tx, ty) != TerrainType.steel) return false;
    setTile(tx, ty, TerrainType.empty);
    return true;
  }
}
