import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

/// A clipped blur with enough tint to keep text readable over a busy map.
class GlassSurface extends StatelessWidget {
  const GlassSurface(
      {super.key,
      required this.child,
      this.borderRadius = const BorderRadius.all(Radius.circular(24)),
      this.padding = EdgeInsets.zero,
      this.tint = const Color(0xFF0D4E47)});
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color tint;
  static const ink = Colors.white;

  /// Local contrast settings, so ordinary screens retain their light theme.
  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        surface: const Color(0xFF0D4E47),
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFFE0EEEB),
        outline: const Color(0xFFE0EEEB),
        primary: const Color(0xFFB8EFE0),
        onPrimary: const Color(0xFF103F39),
      ),
      textTheme: base.textTheme
          .apply(bodyColor: Colors.white, displayColor: Colors.white)
          .copyWith(
            bodySmall: base.textTheme.bodySmall
                ?.copyWith(color: Colors.white, fontSize: 14, height: 1.5),
            bodyMedium: base.textTheme.bodyMedium
                ?.copyWith(color: Colors.white, fontSize: 15, height: 1.5),
            labelLarge: base.textTheme.labelLarge
                ?.copyWith(color: Colors.white, fontSize: 16, height: 1.4),
          ),
      iconTheme: const IconThemeData(color: Colors.white),
      listTileTheme: const ListTileThemeData(
          textColor: Colors.white, iconColor: Colors.white),
      dividerColor: Colors.white24,
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: const TextStyle(
                  fontSize: 16, height: 1.4, fontWeight: FontWeight.w600))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: base.outlinedButtonTheme.style?.copyWith(
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
              minimumSize: const WidgetStatePropertyAll(Size.fromHeight(56)),
              padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
              textStyle: const WidgetStatePropertyAll(TextStyle(
                  fontSize: 16, height: 1.4, fontWeight: FontWeight.w600)),
              side: const WidgetStatePropertyAll(
                  BorderSide(color: Colors.white54)))),
      popupMenuTheme: base.popupMenuTheme.copyWith(
          labelTextStyle: const WidgetStatePropertyAll(
              TextStyle(color: Colors.white, fontSize: 14))),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
          fillColor: Colors.white.withValues(alpha: .10),
          labelStyle: const TextStyle(color: Colors.white),
          hintStyle: const TextStyle(color: Colors.white70)),
    );
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: const [
        BoxShadow(
            color: Color(0x20173033), blurRadius: 24, offset: Offset(0, 8))
      ]),
      child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      // Nested notice cards should not turn the sheet opaque.
                      color: tint.withValues(
                          alpha: context.findAncestorWidgetOfExactType<
                                      GlassSurface>() ==
                                  null
                              ? .74
                              : .10),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .24))),
                  child: Padding(
                      padding: padding,
                      child: Theme(
                          data: theme(context),
                          child: DefaultTextStyle.merge(
                              style: const TextStyle(color: ink),
                              child: IconTheme.merge(
                                  data: const IconThemeData(color: ink),
                                  child: child))))))));
}

/// Stacks labels above values when large text leaves too little room in a row.
class ReadableDetailRow extends StatelessWidget {
  const ReadableDetailRow(
      {super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: LayoutBuilder(builder: (context, constraints) {
          final labelText = Text(label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant));
          final valueText = Text(value,
              softWrap: true,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.5));
          if (constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(14) > 18) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 6), valueText]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 80, child: labelText),
            const SizedBox(width: 16),
            Expanded(child: valueText)
          ]);
        }),
      );
}

// Reuse Flutter's dialog layout, scrolling, keyboard insets and semantics.
// Only the dialog's surface is replaced; the blur stays inside its bounds.
Widget _glassDialog(Dialog dialog) => Dialog(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    insetPadding: dialog.insetPadding,
    insetAnimationDuration: dialog.insetAnimationDuration,
    insetAnimationCurve: dialog.insetAnimationCurve,
    alignment: dialog.alignment,
    constraints: dialog.constraints,
    semanticsRole: dialog.semanticsRole,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24))),
    child: GlassSurface(child: dialog.child!));

class GlassAlertDialog extends AlertDialog {
  const GlassAlertDialog(
      {super.key,
      super.icon,
      super.iconPadding,
      super.iconColor,
      super.title,
      super.titlePadding,
      super.titleTextStyle,
      super.content,
      super.contentPadding,
      super.contentTextStyle,
      super.actions,
      super.actionsPadding,
      super.actionsAlignment,
      super.actionsOverflowAlignment,
      super.actionsOverflowDirection,
      super.actionsOverflowButtonSpacing,
      super.buttonPadding,
      super.semanticLabel,
      super.insetPadding,
      super.alignment,
      super.constraints,
      super.scrollable,
      super.backgroundColor,
      super.elevation,
      super.surfaceTintColor,
      super.shape,
      super.clipBehavior});
  @override
  Widget build(BuildContext context) => Theme(
      data: GlassSurface.theme(context),
      child: Builder(
          builder: (context) => _glassDialog(super.build(context) as Dialog)));
}

class GlassSimpleDialog extends SimpleDialog {
  const GlassSimpleDialog(
      {super.key,
      super.title,
      super.titlePadding,
      super.titleTextStyle,
      super.children,
      super.contentPadding,
      super.semanticLabel,
      super.insetPadding,
      super.alignment,
      super.constraints});
  @override
  Widget build(BuildContext context) => Theme(
      data: GlassSurface.theme(context),
      child: Builder(
          builder: (context) => _glassDialog(super.build(context) as Dialog)));
}

class GlassSnackBar extends SnackBar {
  GlassSnackBar(
      {super.key,
      required Widget content,
      SnackBarAction? action,
      super.duration = const Duration(seconds: 5),
      super.onVisible,
      DismissDirection dismissDirection = DismissDirection.horizontal,
      bool showCloseIcon = false,
      Color? backgroundColor,
      SnackBarBehavior? behavior,
      super.margin})
      : super(
            backgroundColor: Colors.transparent,
            elevation: 0,
            padding: EdgeInsets.zero,
            behavior: SnackBarBehavior.floating,
            dismissDirection: dismissDirection,
            content: GlassSurface(
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                // Keep popup text white on the translucent green surface.
                child: DefaultTextStyle(
                    style: const TextStyle(
                        color: GlassSurface.ink, fontSize: 14, height: 1.4),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: content),
                                if (showCloseIcon)
                                  Builder(
                                      builder: (context) => IconButton(
                                          tooltip: 'Close',
                                          icon: const Icon(Icons.close),
                                          onPressed: () =>
                                              ScaffoldMessenger.of(context)
                                                  .hideCurrentSnackBar()))
                              ]),
                          if (action != null)
                            Align(
                                alignment: Alignment.centerRight,
                                child: SnackBarAction(
                                    label: action.label,
                                    onPressed: action.onPressed,
                                    textColor: Colors.white))
                        ]))));
}

class GlassPopupMenuItem<T> extends PopupMenuItem<T> {
  const GlassPopupMenuItem(
      {super.key,
      super.value,
      super.onTap,
      super.enabled,
      super.height,
      super.padding,
      super.textStyle,
      super.labelTextStyle,
      super.mouseCursor,
      required super.child});
  @override
  PopupMenuItemState<T, GlassPopupMenuItem<T>> createState() =>
      _GlassPopupMenuItemState<T>();
}

class _GlassPopupMenuItemState<T>
    extends PopupMenuItemState<T, GlassPopupMenuItem<T>> {
  @override
  Widget build(BuildContext context) => GlassSurface(
      borderRadius: BorderRadius.zero,
      child: Builder(builder: (context) => super.build(context)));
}

class GlassCard extends StatelessWidget {
  const GlassCard(
      {super.key,
      required this.child,
      this.margin = EdgeInsets.zero,
      this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry margin, padding;
  @override
  Widget build(BuildContext context) => Padding(
      padding: margin,
      child: GlassSurface(
          padding: padding,
          child: Material(type: MaterialType.transparency, child: child)));
}

/// Dismisses a displayed notice without deleting its database record.
class SwipeNotice extends StatefulWidget {
  const SwipeNotice(
      {super.key, required this.child, required this.onDismiss, this.duration});
  final Widget child;
  final VoidCallback onDismiss;
  final Duration? duration;
  @override
  State<SwipeNotice> createState() => _SwipeNoticeState();
}

class _SwipeNoticeState extends State<SwipeNotice> {
  bool _hidden = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    if (widget.duration != null) _timer = Timer(widget.duration!, _dismiss);
  }

  void _dismiss() {
    if (!mounted || _hidden) return;
    _timer?.cancel();
    setState(() => _hidden = true);
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _hidden
      ? const SizedBox.shrink()
      : Dismissible(
          key: const ValueKey('notice'),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => _dismiss(),
          child: widget.child,
        );
}

Future<T?> showGlassBottomSheet<T>(
        {required BuildContext context,
        required WidgetBuilder builder,
        bool isScrollControlled = false,
        bool showDragHandle = false,
        bool useSafeArea = false,
        bool useRootNavigator = false,
        bool isDismissible = true,
        bool enableDrag = true,
        Color? backgroundColor,
        RouteSettings? routeSettings}) =>
    showModalBottomSheet<T>(
        context: context,
        backgroundColor: Colors.transparent,
        elevation: 0,
        isScrollControlled: isScrollControlled,
        showDragHandle: false,
        useSafeArea: useSafeArea,
        useRootNavigator: useRootNavigator,
        isDismissible: isDismissible,
        enableDrag: enableDrag,
        routeSettings: routeSettings,
        builder: (context) => GlassSurface(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            child: Stack(children: [
              Padding(
                  padding: EdgeInsets.only(top: showDragHandle ? 28 : 0),
                  child: Builder(builder: builder)),
              if (showDragHandle)
                Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                        child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.white54,
                                borderRadius: BorderRadius.circular(4)))))
            ])));
