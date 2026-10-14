import 'package:flutter_test/flutter_test.dart';
import 'package:parago_admin_web/core/utils/map_label_clusters.dart';

void main() {
  test('nearby locations merge without losing labels or values', () {
    final groups = clusterMapLabels([
      const MapLabelPoint(100, 100, 'Market'),
      const MapLabelPoint(102, 105, 'Nearby Stop'),
      const MapLabelPoint(500, 100, 'College'),
    ]);
    expect(groups.length, 2);
    expect(groups.first.points.map((p) => p.value), ['Market', 'Nearby Stop']);
  });
  test('zoomed apart locations separate; exact shared positions remain grouped',
      () {
    expect(
        clusterMapLabels([
          const MapLabelPoint(0, 0, 'a'),
          const MapLabelPoint(0, 200, 'b')
        ]).length,
        2);
    expect(
        clusterMapLabels([
          const MapLabelPoint(0, 0, 'boarding'),
          const MapLabelPoint(0, 0, 'unloading')
        ]).length,
        1);
    expect(clusterMapLabels<String>([]), isEmpty);
  });
  test('final cluster label rectangles do not intersect after chain merges',
      () {
    final groups = clusterMapLabels([
      for (var i = 0; i < 20; i++) MapLabelPoint(i * 55.0, (i % 3) * 35.0, i)
    ]);
    expect(groups.fold<int>(0, (n, g) => n + g.points.length), 20);
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        expect(
            (groups[i].x - groups[j].x).abs() >= 140 ||
                (groups[i].y - groups[j].y).abs() >= 82,
            isTrue);
      }
    }
  });
}
