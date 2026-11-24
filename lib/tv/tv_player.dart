import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../player.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'tv_widgets.dart';

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
    _osdTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => osd = false);
    });
  }

  void _closePanel() {
    setState(() => panel = _Panel.none);
    focus.requestFocus();
  }

  /// İleri/geri sarma: tuşa her basışta hedef birikir, kısa bekleme sonrası tek seferde atlar (sunucuyu yormaz).
  void _seek(int dir, bool repeat) {
    final p = playback.player;
    _repeat = repeat ? _repeat + 1 : 0;
    final step = _repeat > 20 ? 60 : (_repeat > 8 ? 30 : 10);
    final base = _seekTarget ?? p.state.position;
    var t = base + Duration(seconds: step * dir);
    if (t < Duration.zero) t = Duration.zero;
    if (p.state.duration > Duration.zero && t > p.state.duration) t = p.state.duration - const Duration(seconds: 2);
    setState(() => _seekTarget = t);
    _showOsd();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 650), () async {
      final target = _seekTarget;
      if (target != null) await p.seek(target);
      if (mounted) setState(() => _seekTarget = null);
    });
  }

  KeyEventResult _key(FocusNode n, KeyEvent e) {
    if (panel != _Panel.none) return KeyEventResult.ignored;
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final live = playback.isLive;
    final rep = e is KeyRepeatEvent;
    final p = playback.player;
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.mediaPlayPause) {
      if (!live && !rep) p.playOrPause();
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
          child: ListenableBuilder(
            listenable: playback,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: playback.video,
                  controls: NoVideoControls,
                  fill: Colors.black,
                  subtitleViewConfiguration: SubtitleViewConfiguration(
                    style: TextStyle(
                      fontSize: store.subSize * 0.75,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black),
                        Shadow(offset: Offset(1, 1), blurRadius: 2),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 36),
                  ),
                ),
                const _Buffering(),
                AnimatedOpacity(
                  opacity: osd || _seekTarget != null ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: _Osd(seekTarget: _seekTarget),
                ),
                if (panel == _Panel.channels) _ChannelPanel(onClose: _closePanel),
                if (panel == _Panel.tracks) _TrackPanel(onClose: _closePanel),
              ],
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
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: playback.player.stream.buffering,
    initialData: playback.player.state.buffering,
    builder: (_, s) {
      if (s.data != true && playback.status.isEmpty) return const SizedBox.shrink();
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
  const _Osd({this.seekTarget});

  @override
  Widget build(BuildContext context) {
    final p = playback.player;
    final live = playback.isLive;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 30),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xDD000000), Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
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
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Color(0xDD000000)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: live
              ? const Text(
                  '▲ ▼ kanal  ·  ◀ kanal listesi  ·  ▶ ses / altyazı / kalite  ·  Geri: çıkış',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                )
              : StreamBuilder<Duration>(
                  stream: p.stream.position,
                  builder: (_, __) {
                    final dur = p.state.duration;
                    final pos = seekTarget ?? p.state.position;
                    final frac = dur.inMilliseconds <= 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
                    final buf = dur.inMilliseconds <= 0 ? 0.0 : p.state.buffer.inMilliseconds / dur.inMilliseconds;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 6,
                          child: Stack(
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            StreamBuilder<bool>(
                              stream: p.stream.playing,
                              initialData: p.state.playing,
                              builder: (_, s) => Icon(s.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 26),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${fmtDur(pos)} / ${fmtDur(dur)}',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: seekTarget != null ? kGold : Colors.white,
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              '◀ ▶ sar  ·  OK oynat/duraklat  ·  ▲ ses / altyazı / kalite',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
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
        color: const Color(0xF0101016),
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

  @override
  Widget build(BuildContext context) {
    final p = playback.player;
    final t = p.state.tracks;
    final sel = p.state.track;
    Widget section(String title, List<Object> list, String curId, void Function(Object) pick, String kind) {
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
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Seçenek yok', style: TextStyle(color: kDim)),
            )
          else
            for (var i = 0; i < list.length; i++)
              TvRow(
                selected: trackInfo(list[i]).id == curId,
                onTap: () {
                  pick(list[i]);
                  onClose();
                },
                child: Row(
                  children: [
                    Icon(Icons.check_rounded, size: 18, color: trackInfo(list[i]).id == curId ? kFire : Colors.transparent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(trackLabel(list[i], i, kind), style: const TextStyle(fontSize: 13.5))),
                  ],
                ),
              ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 340,
        color: const Color(0xF0101016),
        child: FocusScope(
          autofocus: true,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              section('SES', t.audio, sel.audio.id, (x) => p.setAudioTrack(x as AudioTrack), 'audio'),
              section('ALTYAZI', t.subtitle, sel.subtitle.id, (x) => p.setSubtitleTrack(x as SubtitleTrack), 'sub'),
              section('KALİTE / GÖRÜNTÜ', t.video, sel.video.id, (x) => p.setVideoTrack(x as VideoTrack), 'video'),
            ],
          ),
        ),
      ),
    );
  }
}
