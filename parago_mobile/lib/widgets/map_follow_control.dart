import 'package:flutter/material.dart';

/// Compact map status and recenter action that stays in place in either mode.
class MapFollowControl extends StatelessWidget {
  const MapFollowControl({
    super.key,
    required this.status,
    required this.onRecenter,
  });

  final String status;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Material(
          color: const Color(0xF7FFFFFF),
          elevation: 3,
          shadowColor: const Color(0x33000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0x22075E54)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF19363A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              IconButton(
                tooltip: 'Recenter',
                onPressed: onRecenter,
                color: const Color(0xFF0F6A5F),
                icon: const Icon(Icons.my_location_rounded, size: 22),
              ),
            ],
          ),
        ),
      );
}
