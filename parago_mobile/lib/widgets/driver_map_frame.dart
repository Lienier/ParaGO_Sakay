import 'package:flutter/material.dart';

/// Map labels cannot sit behind these controls: they occupy separate layout.
class DriverMapFrame extends StatelessWidget {
  const DriverMapFrame(
      {super.key,
      required this.map,
      required this.followControl,
      required this.tripControl});
  final Widget map, followControl, tripControl;
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(child: ClipRect(child: map)),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                  flex: 2,
                  child: Align(
                      alignment: Alignment.centerLeft, child: followControl)),
              const SizedBox(width: 12),
              Flexible(child: tripControl),
            ])),
      ]);
}
