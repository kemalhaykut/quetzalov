import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'theme.dart';
import 'window_ctl.dart';

/// Özel başlık çubuğu: sürükleme alanı + önde kalma + pencere düğmeleri.
class TitleBar extends StatelessWidget {
  final Widget? center;
  const TitleBar({super.key, this.center});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(color: kSurface, border: Border(bottom: BorderSide(color: kLine))),
      child: Row(children: [
        Expanded(
          child: DragToMoveArea(
            child: Row(children: [
              const SizedBox(width: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset('assets/icon.png', width: 26, height: 26),
              ),
              const SizedBox(width: 10),
              ShaderMask(
                shaderCallback: (r) => kFireGradient.createShader(r),
                child: const Text('Quetzalov',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: .4)),
              ),
              const SizedBox(width: 18),
              if (center != null) Flexible(child: Align(alignment: Alignment.centerLeft, child: center!)),
              const SizedBox(width: 12),
            ]),
          ),
        ),
        ListenableBuilder(
          listenable: windowCtl,
          builder: (_, __) => _WinBtn(
            windowCtl.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            windowCtl.pinned ? 'Önde kalmayı kapat' : 'Pencere önde kalsın',
            () => windowCtl.setPinned(!windowCtl.pinned),
            color: windowCtl.pinned ? kGold : null,
          ),
        ),
        _WinBtn(Icons.remove_rounded, 'Küçült', () => windowManager.minimize()),
        _WinBtn(Icons.crop_square_rounded, 'Büyüt / Eski boyut', () async {
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        }),
        _WinBtn(Icons.close_rounded, 'Kapat', () => windowManager.close(), danger: true),
      ]),
    );
  }
}

class _WinBtn extends StatefulWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool danger;
  final Color? color;
  const _WinBtn(this.icon, this.tip, this.onTap, {this.danger = false, this.color});
  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 48,
            height: 46,
            color: hover ? (widget.danger ? const Color(0xFFE81123) : kCard) : Colors.transparent,
            child: Icon(widget.icon, size: 19, color: widget.color ?? (hover && widget.danger ? Colors.white : kDim)),
          ),
        ),
      ),
    );
  }
}
