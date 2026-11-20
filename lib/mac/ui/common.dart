import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:macos_ui/macos_ui.dart';

/// System-like palette, resolved for light / dark appearance.
class Pal {
  Pal._(this.dark);
  final bool dark;

  static Pal of(BuildContext c) => Pal._(MacosTheme.of(c).brightness == Brightness.dark);

  Color get label => dark ? const Color(0xFFFFFFFF) : const Color(0xD9000000);
  Color get secondary => dark ? const Color(0x8CFFFFFF) : const Color(0x80000000);
  Color get tertiary => dark ? const Color(0x40FFFFFF) : const Color(0x40000000);
  Color get separator => dark ? const Color(0x1AFFFFFF) : const Color(0x1A000000);
  Color get content => dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  Color get card => dark ? const Color(0xFF2A2A2C) : const Color(0xFFF5F5F7);
  Color get hover => dark ? const Color(0x14FFFFFF) : const Color(0x0A000000);
  Color get selection => const Color(0xFF0A84FF);
  Color get bubbleIn => dark ? const Color(0xFF3A3A3C) : const Color(0xFFE9E9EB);
  Color get bubbleOut => const Color(0xFF0A84FF);
  static const blue = Color(0xFF0A84FF);
  static const green = Color(0xFF30D158);
  static const red = Color(0xFFFF453A);
  static const orange = Color(0xFFFF9F0A);
}

TextStyle txt(BuildContext c, {double size = 13, FontWeight w = FontWeight.w400, Color? color}) =>
    MacosTheme.of(c).typography.body.copyWith(fontSize: size, fontWeight: w, color: color ?? Pal.of(c).label);

/// Circle avatar with initials, colour derived from the name (like Contacts.app).
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 36});
  final String name;
  final double size;

  static const _colors = [
    Color(0xFFFF6B6B), Color(0xFFFFA94D), Color(0xFF51CF66), Color(0xFF339AF0),
    Color(0xFF845EF7), Color(0xFFF06595), Color(0xFF20C997), Color(0xFF868E96),
  ];

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final isNumber = RegExp(r'^[+\d\s()-]+$').hasMatch(t);
    final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = isNumber || parts.isEmpty
        ? ''
        : (parts.first.characters.first + (parts.length > 1 ? parts[1].characters.first : '')).toUpperCase();
    final base = isNumber ? const Color(0xFF8E8E93) : _colors[t.hashCode.abs() % _colors.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(base, const Color(0xFFFFFFFF), 0.15)!, base],
        ),
      ),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(CupertinoIcons.person_fill, size: size * 0.55, color: const Color(0xFFFFFFFF))
          : Text(initials,
              style: TextStyle(
                  fontSize: size * 0.4, fontWeight: FontWeight.w600, color: const Color(0xFFFFFFFF))),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: p.tertiary),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: txt(context, size: 17, w: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(subtitle!, textAlign: TextAlign.center, style: txt(context, color: p.secondary)),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      ),
    );
  }
}

/// Rounded grouped section like System Settings.
class Section extends StatelessWidget {
  const Section({super.key, this.title, required this.children, this.footer});
  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title!, style: txt(context, size: 13, w: FontWeight.w600)),
        ),
      Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.separator),
        ),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: 1, margin: const EdgeInsets.only(left: 12), color: p.separator),
            children[i],
          ],
        ]),
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6),
          child: Text(footer!, style: txt(context, size: 11, color: p.secondary)),
        ),
    ]);
  }
}

class Row2 extends StatelessWidget {
  const Row2({super.key, required this.title, this.subtitle, this.trailing, this.leading});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: txt(context)),
            if (subtitle != null) Text(subtitle!, style: txt(context, size: 11, color: p.secondary)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Small hover highlight used for list rows.
class HoverTile extends StatefulWidget {
  const HoverTile({super.key, required this.child, this.onTap, this.selected = false, this.radius = 8});
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final double radius;

  @override
  State<HoverTile> createState() => _HoverTileState();
}

class _HoverTileState extends State<HoverTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: widget.selected ? p.selection : (_hover ? p.hover : const Color(0x00000000)),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          child: DefaultTextStyle.merge(
            style: widget.selected ? const TextStyle(color: Color(0xFFFFFFFF)) : const TextStyle(),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ── formatting ──

String shortTime(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  if (d == today) return DateFormat.Hm('ru').format(t);
  if (today.difference(d).inDays == 1) return 'Вчера';
  if (today.difference(d).inDays < 7) return DateFormat.E('ru').format(t);
  if (t.year == now.year) return DateFormat('d MMM', 'ru').format(t);
  return DateFormat('dd.MM.yy', 'ru').format(t);
}

String dayHeader(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  final hm = DateFormat.Hm('ru').format(t);
  if (d == today) return 'Сегодня $hm';
  if (today.difference(d).inDays == 1) return 'Вчера $hm';
  if (t.year == now.year) return '${DateFormat('EEEE, d MMMM', 'ru').format(t)}, $hm';
  return '${DateFormat('d MMMM y', 'ru').format(t)}, $hm';
}

String duration(int sec) {
  if (sec <= 0) return '';
  final m = sec ~/ 60, s = sec % 60;
  if (m >= 60) return '${m ~/ 60} ч ${m % 60} мин';
  return m > 0 ? '$m мин ${s.toString().padLeft(2, '0')} с' : '$s с';
}

String bytes(int b) {
  if (b < 0) return '—';
  if (b < 1024) return '$b Б';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} КБ';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
}
