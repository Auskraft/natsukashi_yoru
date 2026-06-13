import 'package:flutter_test/flutter_test.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_geometry.dart';
import 'package:natsukashi_yoru/features/tanks/logic/tank_grid.dart';

void main() {
  group('TerrainGrid — базовые тайлы', () {
    test('пустой грид: всё empty и не блокирует танк', () {
      final g = TerrainGrid();
      expect(g.typeAt(0, 0), TerrainType.empty);
      expect(g.solidForTank(0, 0), isFalse);
      expect(g.solidForTank(50, 50), isFalse);
    });

    test('за границей поля — несокрушимая стена', () {
      final g = TerrainGrid();
      expect(g.solidForTank(-1, 0), isTrue);
      expect(g.solidForTank(TankGeo.field, 0), isTrue);
      expect(g.typeAt(-1, 0), TerrainType.steel);
      expect(g.typeAt(TankGeo.tiles, 0), TerrainType.steel);
    });

    test('сталь блокирует и ломается; вода блокирует танк', () {
      final g = TerrainGrid();
      g.setTile(2, 2, TerrainType.steel);
      expect(g.solidForTank(2 * 8 + 1, 2 * 8 + 1), isTrue);
      expect(g.breakSteel(2, 2), isTrue);
      expect(g.typeAt(2, 2), TerrainType.empty);
      expect(g.breakSteel(2, 2), isFalse, reason: 'стали уже нет');

      g.setTile(3, 3, TerrainType.water);
      expect(g.solidForTank(3 * 8 + 1, 3 * 8 + 1), isTrue);
    });

    test('лес и лёд не блокируют танк', () {
      final g = TerrainGrid();
      g.setTile(4, 4, TerrainType.forest);
      g.setTile(5, 5, TerrainType.ice);
      expect(g.solidForTank(4 * 8 + 2, 4 * 8 + 2), isFalse);
      expect(g.solidForTank(5 * 8 + 2, 5 * 8 + 2), isFalse);
    });
  });

  group('TerrainGrid — поквадрантный кирпич', () {
    test('кирпич блокирует; скол убирает только один квадрант', () {
      final g = TerrainGrid();
      g.setTile(6, 6, TerrainType.brick);
      expect(g.quadMaskAt(6, 6), 0xF);
      // Левый-верхний квадрант (суб 48..51).
      expect(g.solidForTank(6 * 8 + 1, 6 * 8 + 1), isTrue);
      expect(g.chipBrick(6 * 8 + 1, 6 * 8 + 1), isTrue);
      // Этот квадрант стал дырой…
      expect(g.solidForTank(6 * 8 + 1, 6 * 8 + 1), isFalse);
      // …а соседний (правый-верхний) ещё цел.
      expect(g.solidForTank(6 * 8 + 5, 6 * 8 + 1), isTrue);
    });

    test('повторный скол по дыре — пуля пролетает (false)', () {
      final g = TerrainGrid();
      g.setTile(6, 6, TerrainType.brick);
      expect(g.chipBrick(6 * 8 + 1, 6 * 8 + 1), isTrue);
      expect(g.chipBrick(6 * 8 + 1, 6 * 8 + 1), isFalse);
    });

    test('после скола всех 4 квадрантов тайл становится пустым', () {
      final g = TerrainGrid();
      g.setTile(6, 6, TerrainType.brick);
      g.chipBrick(6 * 8 + 1, 6 * 8 + 1); // TL
      g.chipBrick(6 * 8 + 5, 6 * 8 + 1); // TR
      g.chipBrick(6 * 8 + 1, 6 * 8 + 5); // BL
      g.chipBrick(6 * 8 + 5, 6 * 8 + 5); // BR
      expect(g.typeAt(6, 6), TerrainType.empty);
      expect(g.quadMaskAt(6, 6), 0);
    });

    test('скол по не-кирпичу — false', () {
      final g = TerrainGrid();
      g.setTile(7, 7, TerrainType.steel);
      expect(g.chipBrick(7 * 8 + 1, 7 * 8 + 1), isFalse);
    });
  });

  group('TankGeo — выравнивание', () {
    test('alignToHalf снапит к ближайшему кратному half', () {
      expect(TankGeo.alignToHalf(0), 0);
      expect(TankGeo.alignToHalf(1), 0);
      expect(TankGeo.alignToHalf(2), 4);
      expect(TankGeo.alignToHalf(4), 4);
      expect(TankGeo.alignToHalf(5), 4);
      expect(TankGeo.alignToHalf(6), 8);
    });
  });
}
