import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../player.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'exo.dart';
import 'tv_widgets.dart';

Exo get _exo => playback.exo!;

/// Mi Box: oynatmayı Android'in kendi tam ekran oynatıcısında açar (üstüne Flutter çizilmez → beyaz ekran olmaz).
/// Oynatma playback.play* ile başlatılmış olmalı. Ekran kapanınca konum kaydedilir ve oynatma durur.
Future<void> openNativePlayer() async {
  final e = _exo;
  final live = playback.isLive;
  var list = live ? playback.liveList : <Item>[];
  var idx = live ? list.indexWhere((x) => x.key == playback.item?.key) : 0;
  if (live && idx < 0 && playback.item != null) {
    list = [playback.item!];
    idx = 0;
  }
  final alt = store.liveFormat == 'ts' ? 'm3u8' : 'ts';
  final api = store.api!;
  final r = await e.launch(
    live: live,
    index: idx < 0 ? 0 : idx,
    title: playback.title,
    subtitle: playback.subtitle,
    names: [for (final x in list) x.name],
    urls: [for (final x in list) api.liveUrl(x.id, ext: store.liveFormat)],
    alts: [for (final x in list) api.liveUrl(x.id, ext: alt)],
  );
  if (r != null) {
    e.position = Duration(milliseconds: (r['pos'] as num?)?.toInt() ?? 0);
    e.duration = Duration(milliseconds: (r['dur'] as num?)?.toInt() ?? 0);
    final i = (r['index'] as num?)?.toInt() ?? 0;
    if (live && i >= 0 && i < list.length) playback.item = list[i];
  }
  await playback.stop();
}

/// Tam ekran oynatıcı — kumanda tuşları:
/// Canlı: ▲▼ kanal · ◀ kanal listesi · ▶ ses/altyazı · OK bilgi
/// Film/dizi: ◀▶ 10 sn sar (basılı tut: hızlanır) · OK oynat/duraklat · ▲ ses/altyazı · ▼ bilgi
class TvPlayer extends StatefulWidget {
  const TvPlayer({super.key});
  @override
  State<TvPlayer> createState() => _TvPlayerState();
}

enum _Panel { none, channels, tracks }

class _TvPlayerState extends State<TvPlayer> {
  final focus = FocusNode();
  bool osd = true;
  Timer? _osdTimer;
  _Panel panel = _Panel.none;
  int _repeat = 0;
  Duration? _seekTarget;
  Timer? _seekTimer;

  @override
  void initState() {
    super.initState();
    _showOsd();
  }

  @override
  void dispose() {
    _osdTimer?.cancel();
    _seekTimer?.cancel();
    focus.dispose();
    super.dispose();
  }

  void _showOsd() {
    setState(() => osd = true);
    _osdTimer?.cancel();
    _osdTimer = Timer(const Duration(seconds: 5), () {
      // duraklatılmışken kontroller ekranda kalsın
      if (!mounted) return;
      if (!playback.isLive && !_exo.playing) return;
      setState(() => osd = false);
    });
  }

  void _closePanel() {
    setState(() => panel = _Panel.none);
    focus.requestFocus();
  }

  /// İleri/geri sarma: tuşa her basışta hedef birikir, kısa bekleme sonrası tek seferde atlar (sunucuyu yormaz).
  void _seek(int dir, bool repeat) {
    final p = _exo;
    _repeat = repeat ? _repeat + 1 : 0;
    final step = _repeat > 20 ? 60 : (_repeat > 8 ? 30 : 10);
    final base = _seekTarget ?? p.position;
    var t = base + Duration(seconds: step * dir);
    if (t < Duration.zero) t = Duration.zero;
    if (p.duration > Duration.zero && t > p.duration) t = p.duration - const Duration(seconds: 2);
    setState(() => _seekTarget = t);
    _showOsd();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 650), () async {
      final target = _seekTarget;
      if (target != null) await p.seek(target);
      if (mounted) setState(() => _seekTarget = null);
    });
  }

  void _toggle() {
    _exo.toggle();
    _showOsd();
  }

  void _seekTo(Duration t) {
    _seekTimer?.cancel();
    setState(() => _seekTarget = null);
    _exo.seek(t);
    _showOsd();
  }

  KeyEventResult _key(FocusNode n, KeyEvent e) {
    if (panel != _Panel.none) return KeyEventResult.ignored;
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final live = playback.isLive;
    final rep = e is KeyRepeatEvent;
    final p = _exo;
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.mediaPlayPause) {
      if (!live && !rep) _toggle();
      _showOsd();
    } else if (k == LogicalKeyboardKey.mediaPlay) {
      p.play();
    } else if (k == LogicalKeyboardKey.mediaPause) {
      p.pause();
    } else if (k == LogicalKeyboardKey.arrowUp) {
      if (live) {
        if (!rep) playback.nextChannel(-1);
        _showOsd();
      } else {
        setState(() => panel = _Panel.tracks);
      }
    } else if (k == LogicalKeyboardKey.arrowDown) {
      if (live) {
        if (!rep) playback.nextChannel(1);
      }
      _showOsd();
    } else if (k == LogicalKeyboardKey.channelUp) {
      playback.nextChannel(-1);
    } else if (k == LogicalKeyboardKey.channelDown) {
      playback.nextChannel(1);
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      if (live) {
        setState(() => panel = _Panel.channels);
      } else {
        _seek(-1, rep);
      }
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      if (live) {
        setState(() => panel = _Panel.tracks);
      } else {
        _seek(1, rep);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: panel == _Panel.none,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closePanel();
        } else {
          // canlıdan çıkınca durdur; film/dizide konum kaydedilir
          playback.stop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: focus,
          autofocus: true,
          onKeyEvent: _key,
          child: MouseRegion(
            onHover: (_) {
              if (!osd) _showOsd();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => osd ? setState(() => osd = false) : _showOsd(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ExoView(),
                  ListenableBuilder(
                    listenable: Listenable.merge([playback, _exo]),
                    builder: (context, _) => Stack(
                      fit: StackFit.expand,
                      children: [
                        const _Buffering(),
                        // Not: video üstünde saydamlık animasyonu (Opacity) bazı kutularda ekranı beyaz yapıyor;
                        // bu yüzden kontroller doğrudan açılıp kapanıyor.
                        if (osd || _seekTarget != null)
                          _Osd(
                            seekTarget: _seekTarget,
                            onToggle: _toggle,
                            onSeekBy: (s) => _seekTo(_exo.position + Duration(seconds: s)),
                            onSeekTo: _seekTo,
                            onTracks: () => setState(() => panel = _Panel.tracks),
                            onChannels: () => setState(() => panel = _Panel.channels),
                            onBack: () => Navigator.of(context).maybePop(),
                          ),
                        if (panel == _Panel.channels) _ChannelPanel(onClose: _closePanel),
                        if (panel == _Panel.tracks) _TrackPanel(onClose: _closePanel),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Buffering extends StatelessWidget {
  const _Buffering();
  @override
  Widget build(BuildContext context) => Builder(
    builder: (_) {
      if (_exo.playing || (!_exo.buffering && playback.status.isEmpty)) return const SizedBox.shrink();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: kFire, strokeWidth: 3.5)),
            if (playback.status.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(playback.status, style: const TextStyle(color: Colors.white)),
            ],
          ],
        ),
      );
    },
  );
}

class _Osd extends StatelessWidget {
  final Duration? seekTarget;
  final VoidCallback onToggle, onTracks, onChannels, onBack;
  final ValueChanged<int> onSeekBy;
  final ValueChanged<Duration> onSeekTo;
  const _Osd({
    this.seekTarget,
    required this.onToggle,
    required this.onSeekBy,
    required this.onSeekTo,
    required this.onTracks,
    required this.onChannels,
    required this.onBack,
  });

  Widget _btn(IconData i, String tip, VoidCallback f, {double size = 28}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: f,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(i, size: size, semanticLabel: tip),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = _exo;
    final live = playback.isLive;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
          color: const Color(0xFF0B0B10),
          child: Row(
            children: [
              if (live)
                Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: kLive, borderRadius: BorderRadius.circular(5)),
                  child: const Text('CANLI', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
              if (live && playback.item != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 54,
                    height: 36,
                    child: NetImage(playback.item!.image, fit: BoxFit.contain, icon: Icons.live_tv_rounded),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playback.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    if (playback.subtitle.isNotEmpty)
                      Text(
                        playback.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                  ],
                ),
              ),
              StreamBuilder<Duration>(
                stream: Stream.periodic(const Duration(seconds: 15)),
                builder: (_, __) {
                  final n = DateTime.now();
                  return Text(
                    '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  );
                },
              ),
            ],
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
          color: const Color(0xFF0B0B10),
          child: live
              ? Row(
                  children: [
                    _btn(Icons.arrow_back_rounded, 'Çıkış', onBack),
                    _btn(Icons.list_rounded, 'Kanal listesi', onChannels),
                    _btn(Icons.subtitles_rounded, 'Ses / altyazı / kalite', onTracks),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '▲ ▼ kanal  ·  ◀ kanal listesi  ·  ▶ ses / altyazı / kalite  ·  Geri: çıkış',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ),
                  ],
                )
              : Builder(
                  builder: (_) {
                    final dur = p.duration;
                    final pos = seekTarget ?? p.position;
                    final frac = dur.inMilliseconds <= 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
                    final buf = dur.inMilliseconds <= 0 ? 0.0 : p.buffered.inMilliseconds / dur.inMilliseconds;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LayoutBuilder(
                          builder: (context, c) {
                            void jump(double x) {
                              if (dur <= Duration.zero) return;
                              onSeekTo(Duration(milliseconds: (dur.inMilliseconds * (x / c.maxWidth).clamp(0.0, 1.0)).round()));
                            }

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (d) => jump(d.localPosition.dx),
                              onHorizontalDragEnd: null,
                              onHorizontalDragUpdate: (d) => jump(d.localPosition.dx),
                              child: SizedBox(
                                height: 22,
                                child: Center(
                                  child: SizedBox(
                                    height: 6,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)),
                                        ),
                                        FractionallySizedBox(
                                          widthFactor: buf.clamp(0, 1),
                                          child: Container(
                                            decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(3)),
                                          ),
                                        ),
                                        FractionallySizedBox(
                                          widthFactor: frac.clamp(0, 1),
                                          child: Container(
                                            decoration: BoxDecoration(gradient: kFireGradient, borderRadius: BorderRadius.circular(3)),
                                          ),
                                        ),
                                        Positioned(
                                          left: (c.maxWidth * frac.clamp(0, 1)) - 7,
                                          top: -4,
                                          child: Container(
                                            width: 14,
                                            height: 14,
                                            decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _btn(Icons.replay_10_rounded, '10 sn geri', () => onSeekBy(-10)),
                            _btn(
                              p.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                              p.playing ? 'Duraklat' : 'Oynat',
                              onToggle,
                              size: 40,
                            ),
                            _btn(Icons.forward_10_rounded, '10 sn ileri', () => onSeekBy(10)),
                            _btn(Icons.forward_30_rounded, '30 sn ileri', () => onSeekBy(30)),
                            const SizedBox(width: 10),
                            Text(
                              '${fmtDur(pos)} / ${fmtDur(dur)}',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: seekTarget != null ? kGold : Colors.white,
                              ),
                            ),
                            const Spacer(),
                            const Text('◀ ▶ sar · OK duraklat · ▲ menü', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                            const SizedBox(width: 8),
                            _btn(Icons.subtitles_rounded, 'Ses / altyazı / kalite', onTracks),
                            _btn(Icons.arrow_back_rounded, 'Çıkış', onBack),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Soldan açılan kanal listesi
class _ChannelPanel extends StatelessWidget {
  final VoidCallback onClose;
  const _ChannelPanel({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final list = playback.liveList;
    final cur = list.indexWhere((x) => x.key == playback.item?.key);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 330,
        color: const Color(0xFF101016),
        child: FocusScope(
          autofocus: true,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final it = list[i];
              return TvRow(
                autofocus: i == (cur < 0 ? 0 : cur),
                selected: i == cur,
                onTap: () {
                  playback.playLive(it);
                  onClose();
                },
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text('${i + 1}', style: const TextStyle(color: kDim, fontSize: 11)),
                    ),
                    SizedBox(
                      width: 40,
                      height: 28,
                      child: NetImage(it.image, fit: BoxFit.contain, icon: Icons.live_tv_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Sağdan açılan ses / altyazı / kalite menüsü
class _TrackPanel extends StatelessWidget {
  final VoidCallback onClose;
  const _TrackPanel({required this.onClose});

  String _label(ExoTrack t, int i) {
    final parts = <String>[];
    if ((t.label ?? '').isNotEmpty) parts.add(t.label!);
    if ((t.lang ?? '').isNotEmpty && t.lang != 'und') parts.add(langName(t.lang!));
    if (t.h != null) parts.add('${t.h}p');
    if (t.ch != null) parts.add(t.ch == 6 ? '5.1' : (t.ch == 2 ? 'Stereo' : '${t.ch} kanal'));
    if ((t.codec ?? '').isNotEmpty) parts.add(t.codec!.split('/').last.toUpperCase());
    return parts.isEmpty ? '${t.type == 'sub' ? 'Altyazı' : 'İz'} ${i + 1}' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final e = _exo;
    Widget row(String text, bool sel, VoidCallback f) => TvRow(
      selected: sel,
      onTap: () {
        f();
        onClose();
      },
      child: Row(
        children: [
          Icon(Icons.check_rounded, size: 18, color: sel ? kFire : Colors.transparent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
    Widget section(String title, String type) {
      final list = e.tracks.where((t) => t.type == type).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Text(
              title,
              style: const TextStyle(color: kDim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
          if (type == 'sub') row('Kapalı', e.subOff || !list.any((t) => t.sel), () => e.selectTrack('sub', 'off')),
          if (type == 'video' && list.length > 1) row('Otomatik', false, () => e.selectTrack('video', 'auto')),
          if (list.isEmpty && type != 'sub')
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Seçenek yok', style: TextStyle(color: kDim)),
            )
          else
            for (var i = 0; i < list.length; i++)
              row(_label(list[i], i), list[i].sel && !(type == 'sub' && e.subOff), () => e.selectTrack(type, list[i].id)),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 340,
        color: const Color(0xFF101016),
        child: FocusScope(
          autofocus: true,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              section('SES', 'audio'),
              section('ALTYAZI', 'sub'),
              section('KALİTE / GÖRÜNTÜ', 'video'),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 14, 8, 6),
                child: Text(
                  'GÖRÜNTÜ ORANI',
                  style: TextStyle(color: kDim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
              row('Sığdır', false, () => e.setFit('fit')),
              row('Ekranı doldur (kırp)', false, () => e.setFit('zoom')),
              row('Uzat', false, () => e.setFit('fill')),
            ],
          ),
        ),
      ),
    );
  }
}
