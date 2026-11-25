import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Kumandayla seçilebilen kutu: odaklanınca büyür, turuncu çerçeve alır.
/// Orta tuş (OK) ve Enter onTap'i çalıştırır.
class TvFocus extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onFocus;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final double scale;
  final KeyEventResult Function(KeyEvent e)? onKey;
  const TvFocus({
    super.key,
    required this.builder,
    this.onTap,
    this.onFocus,
    this.autofocus = false,
    this.focusNode,
    this.radius = 14,
    this.scale = 1.05,
    this.onKey,
  });

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => focused = f);
        widget.onFocus?.call(f);
        if (f) {
          Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
        }
      },
      onKeyEvent: (node, e) {
        if (widget.onKey != null) {
          final r = widget.onKey!(e);
          if (r == KeyEventResult.handled) return r;
        }
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.numpadEnter ||
                e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap?.call();
          return widget.onTap == null ? KeyEventResult.ignored : KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: focused ? widget.scale : 1,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(color: focused ? kGold : Colors.transparent, width: 2.5),
              boxShadow: focused ? [BoxShadow(color: kFire.withValues(alpha: .45), blurRadius: 16)] : null,
            ),
            child: widget.builder(context, focused),
          ),
        ),
      ),
    );
  }
}

/// Basit TV düğmesi.
class TvButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;
  final bool primary;
  const TvButton(this.label, this.icon, this.onTap, {super.key, this.autofocus = false, this.primary = false});

  @override
  Widget build(BuildContext context) => TvFocus(
    autofocus: autofocus,
    onTap: onTap,
    radius: 12,
    builder: (_, f) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        gradient: f || primary ? kFireGradient : null,
        color: f || primary ? null : kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

/// Liste satırı (kategori, kanal, ayar).
class TvRow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onFocus;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent e)? onKey;
  const TvRow({
    super.key,
    required this.child,
    this.onTap,
    this.onFocus,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.onKey,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: TvFocus(
      autofocus: autofocus,
      focusNode: focusNode,
      onTap: onTap,
      onFocus: onFocus,
      onKey: onKey,
      scale: 1.0,
      radius: 10,
      builder: (_, f) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: f ? kFire.withValues(alpha: .28) : (selected ? kFire.withValues(alpha: .12) : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(fontWeight: f || selected ? FontWeight.w700 : FontWeight.w500),
          child: child,
        ),
      ),
    ),
  );
}

class TvTitle extends StatelessWidget {
  final String text;
  final String? sub;
  const TvTitle(this.text, {super.key, this.sub});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        if (sub != null) ...[
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(sub!, style: const TextStyle(color: kDim, fontSize: 12)),
          ),
        ],
      ],
    ),
  );
}

/// Kumanda için metin kutusu sarmalayıcısı: ▲▼ odak değiştirir, OK ekran klavyesini açar.
class TvTextField extends StatelessWidget {
  final Widget child;
  const TvTextField({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
      SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
    },
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.select || e.logicalKey == LogicalKeyboardKey.enter)) {
          SystemChannels.textInput.invokeMethod<void>('TextInput.show');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    ),
  );
}
