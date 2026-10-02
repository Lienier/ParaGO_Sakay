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
