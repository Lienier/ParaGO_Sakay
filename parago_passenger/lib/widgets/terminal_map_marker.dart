import 'package:flutter/material.dart';

/// Upright labelled marker; the containing map Marker uses rotate: true.
class TerminalMapMarker extends StatelessWidget {
  const TerminalMapMarker(
      {super.key,
      required this.name,
      this.isEnd = false,
      this.isCombined = false});
  final String name;
  final bool isEnd;
  final bool isCombined;

  @override
  Widget build(BuildContext context) {
    final label = isCombined
        ? 'TERMINAL / ROUTE END'
        : isEnd
            ? 'END TERMINAL'
            : 'DEPARTURE TERMINAL';
    final color = isEnd ? const Color(0xFF334155) : const Color(0xFF075E54);
    return Semantics(
      label: '$label: $name',
      child: Tooltip(
        message: '$label: $name',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 2)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 3),
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 2)),
              child: Icon(isEnd ? Icons.flag : Icons.local_parking,
                  color: Colors.white, size: 22)),
        ]),
      ),
    );
  }
}

class TerminalMapBanner extends StatelessWidget {
  const TerminalMapBanner({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xF2FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x22075E54)),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.local_parking, color: Color(0xFF075E54), size: 18),
          const SizedBox(width: 7),
          Flexible(
            child: Text('Terminal · $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFF123B38), fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}
