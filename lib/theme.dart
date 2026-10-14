import 'package:flutter/material.dart';

/// Signal palette — dark olive with a lime accent.
class C {
  static const bg = Color(0xFF0A0B09);
  static const surface = Color(0xFF151613);
  static const olive1 = Color(0xFF34341F);
  static const olive2 = Color(0xFF181913);
  static const lime = Color(0xFFD3F08A);
  static const yellow = Color(0xFFE6D84A);
  static const text = Color(0xFFEDEDE4);
  static const muted = Color(0xFF8E9084);
  static const line = Color(0x1AFFFFFF);
  static const faint = Color(0x0DFFFFFF);
}

const kFont = 'Outfit';

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final text = base.textTheme.apply(
    fontFamily: kFont,
    bodyColor: C.text,
    displayColor: C.text,
  );
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.lime,
      secondary: C.yellow,
      surface: C.surface,
      onPrimary: Colors.black,
    ),
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    dividerColor: Colors.transparent,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.olive1,
      contentTextStyle: const TextStyle(color: C.text, fontFamily: kFont),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

/// A translucent, gradient card used across the app.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.olive = false,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.radius = 26,
  });
  final Widget child;
  final bool olive;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: C.line),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: olive
                ? [C.olive1, C.olive2]
                : [const Color(0xFF1D1E1A), const Color(0xFF121310)],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// A rounded pill-shaped button.
class PillButton extends StatelessWidget {
  const PillButton(
    this.label, {
    super.key,
    this.icon,
    this.filled = false,
    this.danger = false,
    this.onTap,
    this.busy = false,
  });
  final String label;
  final IconData? icon;
  final bool filled;
  final bool danger;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.black : (danger ? const Color(0xFFFF9E80) : C.text);
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: filled ? C.lime : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: filled
              ? null
              : Border.all(
                  color: danger ? const Color(0x55FF9E80) : const Color(0x33FFFFFF)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: C.lime),
            )
          else if (icon != null)
            Icon(icon, size: 18, color: fg),
          if (busy || icon != null) const SizedBox(width: 8),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}
