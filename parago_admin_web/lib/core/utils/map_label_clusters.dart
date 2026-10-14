class MapLabelPoint<T> {
  const MapLabelPoint(this.x, this.y, this.value);
  final double x, y;
  final T value;
}

class MapLabelCluster<T> {
  MapLabelCluster(this.points);
  final List<MapLabelPoint<T>> points;
  double get x => points.fold<double>(0, (sum, p) => sum + p.x) / points.length;
  double get y => points.fold<double>(0, (sum, p) => sum + p.y) / points.length;
}

/// Recompute in screen pixels at every camera change. Merge until the final
/// label rectangles no longer intersect, including transitive overlaps.
List<MapLabelCluster<T>> clusterMapLabels<T>(Iterable<MapLabelPoint<T>> points,
    {double width = 140, double height = 82}) {
  final groups = [
    for (final p in points) MapLabelCluster<T>([p])
  ];
  var merged = true;
  while (merged) {
    merged = false;
    for (var i = 0; i < groups.length && !merged; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        if ((groups[i].x - groups[j].x).abs() < width &&
            (groups[i].y - groups[j].y).abs() < height) {
          groups[i].points.addAll(groups.removeAt(j).points);
          merged = true;
          break;
        }
      }
    }
  }
  return groups;
}
