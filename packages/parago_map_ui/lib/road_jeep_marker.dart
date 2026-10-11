import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Display footprint only. Never modifies GPS used for trip automation.
double roadJeepWidth({required double zoom, required double latitude}) {
  final metresPerPixel = 156543.03392 *
      math.cos(latitude.clamp(-85.0, 85.0) * math.pi / 180) /
      math.pow(2, zoom);
  // An eight-metre road footprint; bound the symbol at extreme zoom levels.
  return (8 / metresPerPixel).clamp(8.0, 48.0);
}

class RoadJeepMarker extends StatelessWidget {
  const RoadJeepMarker(
      {super.key,
      required this.latitude,
      required this.label,
      this.headingDegrees,
      this.selected = false,
      this.onTap,
      this.color = const Color(0xFF0F6A5F),
      this.tooltip});
  static const double extent = 96;
  final double latitude;
  final String label;
  final double? headingDegrees;
  final bool selected;
  final VoidCallback? onTap;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final width = roadJeepWidth(zoom: camera.zoom, latitude: latitude);
    final heading = headingDegrees?.isFinite == true ? headingDegrees! : 0.0;
    return Semantics(
      container: true,
      label: label,
      button: onTap != null,
      child: Tooltip(
        message: tooltip ?? label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: extent,
            height: extent,
            child: Center(
                child: Transform.rotate(
              // Marker.rotate keeps the hit area upright; rotate only the jeep.
              angle: (heading + camera.rotation) * math.pi / 180,
              child: CustomPaint(
                  size: Size(width, width * 1.65),
                  painter: _JeepPainter(color, selected)),
            )),
          ),
        ),
      ),
    );
  }
}

class _JeepPainter extends CustomPainter {
  const _JeepPainter(this.color, this.selected);
  final Color color;
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stroke = (w * .07).clamp(1.0, 2.5);
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, h - stroke),
        Radius.circular(w * .2));
    canvas.drawRRect(body, Paint()..color = color);
    canvas.drawRRect(
        body,
        Paint()
          ..color = selected ? const Color(0xFFFFC107) : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    final window = Paint()..color = Colors.white;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * .2, h * .15, w * .6, h * .2),
            Radius.circular(w * .08)),
        window);
    canvas.drawRect(Rect.fromLTWH(w * .23, h * .76, w * .54, h * .07), window);
    // Front point makes direction visible without a face-on bus icon.
    canvas.drawLine(
        Offset(w * .38, h * .08),
        Offset(w * .62, h * .08),
        Paint()
          ..color = Colors.white
          ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_JeepPainter old) =>
      old.color != color || old.selected != selected;
}
