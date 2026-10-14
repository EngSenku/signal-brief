import 'package:flutter/material.dart';

import 'theme.dart';

/// Small label above a value, used in the header stats.
class StatBox extends StatelessWidget {
  const StatBox(this.label, this.value, {super.key, this.accent = false});
  final String label, value;
  final bool accent;

  @override
  Widget build(BuildContext context) => Glass(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  color: accent ? C.lime : C.text)),
        ]),
      );
}

/// A horizontal row of selectable filter chips.
class ChipRow extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final c in options)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onChanged(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == c ? C.lime : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                      border: value == c
                          ? null
                          : Border.all(color: const Color(0x33FFFFFF)),
                    ),
                    child: Text(c,
                        style: TextStyle(
                            color: value == c ? Colors.black : C.text,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// A titled settings section with an optional subtitle.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, this.sub, required this.child});
  final String title;
  final String? sub;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Glass(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(sub!,
                    style: const TextStyle(color: C.muted, fontSize: 13, height: 1.35)),
              ),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

/// A slim progress bar used for goals and streaks.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.height = 8});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Stack(children: [
          Container(height: height, color: const Color(0x1AFFFFFF)),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(height: height, color: C.lime),
          ),
        ]),
      );
}

/// Placeholder shown when a list has no content yet.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Glass(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Icon(icon, color: C.muted, size: 30),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: C.muted, height: 1.5)),
        ]),
      );
}

/// A tiny pill label.
class TagChip extends StatelessWidget {
  const TagChip(this.label,
      {super.key, this.onDeleted, this.color = C.lime, this.outlined = true});
  final String label;
  final VoidCallback? onDeleted;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.only(
            left: 12, right: onDeleted != null ? 6 : 12, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: color, fontSize: 12.5)),
          if (onDeleted != null) ...[
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onDeleted,
              child: Icon(Icons.close_rounded, size: 15, color: color),
            ),
          ],
        ]),
      );
}
