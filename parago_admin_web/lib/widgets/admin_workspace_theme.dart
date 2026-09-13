import 'package:flutter/material.dart';

/// Applied only inside the signed-in workspace; authentication keeps its theme.
class AdminWorkspaceTheme extends StatelessWidget {
  const AdminWorkspaceTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    const navy = Color(0xFF142C46);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    final focusSide = WidgetStateProperty.resolveWith<BorderSide?>((states) {
      if (states.contains(WidgetState.focused)) {
        return const BorderSide(color: navy, width: 2);
      }
      return const BorderSide(color: Color(0xFFCBD5E1));
    });
    final common = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
      shape: WidgetStatePropertyAll(shape),
      side: focusSide,
    );
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFFEDF1F5),
        textTheme: base.textTheme.copyWith(
          headlineMedium: base.textTheme.headlineMedium
              ?.copyWith(color: navy, fontWeight: FontWeight.w700),
          titleLarge: base.textTheme.titleLarge
              ?.copyWith(color: navy, fontWeight: FontWeight.w700),
          titleMedium: base.textTheme.titleMedium
              ?.copyWith(color: navy, fontWeight: FontWeight.w600),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: base.filledButtonTheme.style?.merge(common.copyWith(
            side: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: navy, width: 2) : BorderSide.none),
          )),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(style: base.outlinedButtonTheme.style?.merge(common)),
        textButtonTheme: TextButtonThemeData(style: base.textButtonTheme.style?.merge(common.copyWith(
          side: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
              ? const BorderSide(color: navy, width: 2) : BorderSide.none),
        ))),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF0F766E), width: 2)),
        ),
        hoverColor: const Color(0x0C0F766E),
        focusColor: const Color(0x260F766E),
        dataTableTheme: DataTableThemeData(
          headingRowColor: const WidgetStatePropertyAll(Color(0xFFF3F6F9)),
          headingTextStyle: base.textTheme.labelLarge
              ?.copyWith(color: navy, fontWeight: FontWeight.w700),
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFE1EEEB);
            }
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFFF3F8F7);
            }
            return Colors.white;
          }),
          dividerThickness: 0.7,
        ),
      ),
      child: ColoredBox(color: const Color(0xFFEDF1F5), child: child),
    );
  }
}
