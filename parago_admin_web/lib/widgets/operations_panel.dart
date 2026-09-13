import 'package:flutter/material.dart';

/// Restrained depth for the operations workspace, independent of the login theme.
class OperationsPanel extends StatelessWidget {
  const OperationsPanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDCE3EB)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x08182840), blurRadius: 16, offset: Offset(0, 5))
          ],
        ),
        child: child,
      );
}

/// Material surface for tables and split panes, with visible ink feedback.
class OperationsCard extends StatelessWidget {
  const OperationsCard(
      {super.key,
      required this.child,
      this.margin = EdgeInsets.zero,
      this.clipBehavior = Clip.none});
  final Widget child;
  final EdgeInsetsGeometry margin;
  final Clip clipBehavior;
  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: OperationsPanel(
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: clipBehavior,
            child: child,
          ),
        ),
      );
}
