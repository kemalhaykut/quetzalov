import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'api.dart';
import 'store.dart';
import 'theme.dart';
import 'tv/exo.dart';
import 'window_ctl.dart';

/// Tek bir oynatıcı (mpv) tüm uygulamada paylaşılır.
/// Android TV'de donanım çözücü MediaCodec, Windows'ta otomatik (güvenli).
String get _hw => Platform.isAndroid ? 'mediacodec-copy' : 'auto-safe';

class Playback extends ChangeNotifier {
  late final Player player;
  late final VideoController video;

  /// Android TV'de mpv yerine ExoPlayer kullanılır (donanım çözme, akıcı canlı yayın).
  Exo? exo;

  Duration get pos => exo?.position ?? player.state.position;
  Duration get dur => exo?.duration ?? player.state.duration;

  Item? item; // kanal / film / dizi
  Episode? episode;
  String title = '';
  String subtitle = '';
  String url = '';
  bool get isLive => item?.section == Section.live;
  bool get active => url.isNotEmpty;

  // Canlı yayın için kanal listesi (önceki / sonraki kanal)
  List<Item> liveList = [];

  String status = ''; // "Yeniden bağlanıyor…" gibi
  int _retries = 0;
  bool _userStopped = false;
  Timer? _saveTimer;
  Duration _lastPos = Duration.zero;
  final _subs = <StreamSubscription>[];

  void init() {
    if (Platform.isAndroid) {
      final e = exo = Exo()..init();
      e.addListener(() {
        if ((e.position - _lastPos).inSeconds.abs() >= 1) {
          _lastPos = e.position;
          if (_retries > 0 || status.isNotEmpty) {
            _retries = 0;
            status = '';
            notifyListeners();
          }
        }
      });
      _subs.add(
        e.errors.listen((msg) {
          debugPrint('exo hata: $msg');
          if (!active || _userStopped) return;
          if (isLive) {
            _reconnect('Yayın kesildi, yeniden bağlanıyor…');
          } else {
            status = 'Oynatılamadı: $msg';
            notifyListeners();
          }
        }),
      );
      _subs.add(e.ended.listen((_) => _onEnded()));
      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
      return;
    }
    player = Player(
      configuration: const PlayerConfiguration(title: 'Quetzalov', bufferSize: 64 * 1024 * 1024, logLevel: MPVLogLevel.warn),
    );
    video = VideoController(
      player,
      configuration: VideoControllerConfiguration(hwdec: store.hwdec ? _hw : 'no', enableHardwareAcceleration: store.hwdec),
    );
    player.setVolume(store.volume);
    _subs.add(
      player.stream.completed.listen((done) {
        if (done) _onEnded();
      }),
    );
    _subs.add(
      player.stream.error.listen((e) {
        debugPrint('mpv hata: $e');
        // mpv bazı önemsiz uyarıları da "hata" olarak bildirir (özellikle Android'de).
        // Bu yüzden hemen yeniden bağlanmıyoruz: birkaç saniye bekleyip yayın gerçekten durduysa bağlanıyoruz.
        if (isLive && !_userStopped) _checkStall();
      }),
    );
    _subs.add(
      player.stream.position.listen((p) {
        // ilerleme varsa yeniden deneme sayacını sıfırla
        if ((p - _lastPos).inSeconds.abs() >= 1) {
          _lastPos = p;
          if (_retries > 0 || status.isNotEmpty) {
            _retries = 0;
            status = '';
            notifyListeners();
          }
        }
      }),
    );
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
  }

  Future<void> _set(String k, String v) async {
    final p = player.platform;
    if (p is NativePlayer) {
      try {
        await p.setProperty(k, v);
      } catch (e) {
        debugPrint('mpv ayarı $k: $e');
      }
    }
  }

  /// Donmayı azaltan ağ ve önbellek ayarları.
  Future<void> _configure({required bool live}) async {
    const sizes = ['96MiB', '256MiB', '512MiB'];
    final lvl = store.bufferLevel.clamp(0, 2);
    await _set('user-agent', XtreamApi.userAgent);
    await _set('network-timeout', '30');
    await _set('tls-verify', 'no');
    await _set('cache', 'yes');
    await _set('demuxer-max-bytes', sizes[lvl]);
    await _set('demuxer-max-back-bytes', live ? '32MiB' : '128MiB');
    await _set('cache-pause-initial', 'yes');
    await _set('cache-pause-wait', live ? ['1', '2', '4'][lvl] : '2');
    await _set('demuxer-readahead-secs', live ? ['4', '8', '15'][lvl] : ['20', '60', '120'][lvl]);
    await _set('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=6');
    await _set('hwdec', store.hwdec ? _hw : 'no');
    if (store.subLang == 'no') {
      await _set('sid', 'no');
    } else {
      await _set('sid', 'auto');
      await _set('slang', '${store.subLang},tr,tur,en,eng');
    }
    if (store.audioLang.isNotEmpty) await _set('alang', store.audioLang);
    await _set('sub-font-size', store.subSize.round().toString());
    await _set('sub-border-size', '2.5');
    await _set('sub-ass-override', 'force');
    await _set('demuxer-lavf-probe-info', live ? 'nostreams' : 'auto');
  }

  Future<void> _open(String u, {Duration? start}) async {
    url = u;
    _userStopped = false;
    _lastPos = Duration.zero;
    status = '';
    notifyListeners();
    final e = exo;
    if (e != null) {
      await e.open(
        u,
        start: start,
        buffer: store.bufferLevel,
        ua: XtreamApi.userAgent,
        subLang: store.subLang,
        audioLang: store.audioLang,
        subSize: store.subSize * 0.5,
      );
      return;
    }
    await _configure(live: isLive);
    await player.open(Media(u, start: start, httpHeaders: const {'User-Agent': XtreamApi.userAgent}));
  }

  Future<void> playLive(Item ch, {List<Item>? list, String nowShowing = ''}) async {
    await _saveProgress();
    item = ch;
    episode = null;
    title = ch.name;
    subtitle = nowShowing;
    if (list != null) liveList = list;
    _retries = 0;
    await _open(store.api!.liveUrl(ch.id, ext: store.liveFormat));
  }

  Future<void> playMovie(Item m, {bool resume = true}) async {
    await _saveProgress();
    item = m;
    episode = null;
    title = m.name;
    subtitle = m.year;
    await _open(store.api!.movieUrl(m.id, m.ext), start: resume ? store.resumeOf(m.key) : null);
  }

  Future<void> playEpisode(Item series, Episode e, {bool resume = true}) async {
    await _saveProgress();
    item = series;
    episode = e;
    title = series.name;
    subtitle = '${e.season}. Sezon · ${e.number}. Bölüm${e.title.isNotEmpty ? ' — ${e.title}' : ''}';
    await _open(store.api!.episodeUrl(e.id, e.ext), start: resume ? store.resumeOf('ep:${e.id}') : null);
  }

  String? get progressKey => episode != null ? 'ep:${episode!.id}' : (item?.section == Section.movies ? item!.key : null);

  Future<void> _saveProgress() async {
    final key = progressKey;
    if (key == null || !active) return;
    final pos = this.pos, dur = this.dur;
    if (pos.inSeconds < 5) return;
    store.saveProgress(key, pos, dur, {
      'item': item!.toJson(),
      if (episode != null) 'ep': {'id': episode!.id, 's': episode!.season, 'n': episode!.number, 'e': episode!.ext, 't': episode!.title},
    });
  }

  Future<void> stop() async {
    await _saveProgress();
    _userStopped = true;
    url = '';
    item = null;
    episode = null;
    status = '';
    notifyListeners();
    if (exo != null) {
      await exo!.stop();
    } else {
      await player.stop();
    }
  }

  void _onEnded() {
    if (_userStopped) return;
    if (isLive) {
      _reconnect('Yayın durdu, yeniden bağlanıyor…');
    } else {
      final key = progressKey;
      if (key != null) store.progress.remove(key);
    }
  }

  Timer? _stallTimer;

  /// Yayın gerçekten durdu mu? 6 sn içinde görüntü ilerlemediyse yeniden bağlan.
  void _checkStall() {
    if (_stallTimer?.isActive ?? false) return;
    final u = url;
    final before = pos;
    _stallTimer = Timer(const Duration(seconds: 6), () {
      if (_userStopped || url != u || !isLive) return;
      final moved = (pos - before).inMilliseconds.abs() > 1500;
      if (!moved) _reconnect('Yayın kesildi, yeniden bağlanıyor…');
    });
  }

  Future<void> _reconnect(String msg) async {
    if (!active || _retries >= 8) {
      if (_retries >= 8) {
        status = 'Yayına ulaşılamıyor. Başka bir kanal deneyin.';
        notifyListeners();
      }
      return;
    }
    _retries++;
    status = msg;
    notifyListeners();
    await Future<void>.delayed(Duration(milliseconds: 800 + 700 * _retries));
    if (_userStopped || !active) return;
    // Sırayla iki formatı dene: ts ↔ m3u8
    final alt = _retries.isEven ? (store.liveFormat == 'ts' ? 'm3u8' : 'ts') : store.liveFormat;
    await _open(store.api!.liveUrl(item!.id, ext: alt));
  }

  Future<void> nextChannel(int dir) async {
    if (liveList.isEmpty || item == null) return;
    final i = liveList.indexWhere((x) => x.id == item!.id);
    final n = liveList[(i + dir + liveList.length) % liveList.length];
    await playLive(n);
  }

  Future<void> setVolume(double v) async {
    store.volume = v.clamp(0, 100);
    if (exo == null) await player.setVolume(store.volume);
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _stallTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _saveProgress();
    if (exo == null) player.dispose();
    exo?.dispose();
    super.dispose();
  }
}

final playback = Playback();

String fmtDur(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Ses / altyazı / görüntü izlerinin ortak alanları.
({String id, String? title, String? lang, String? codec, int? h, double? fps, String? channels}) trackInfo(Object t) {
  return switch (t) {
    VideoTrack v => (id: v.id, title: v.title, lang: v.language, codec: v.codec, h: v.h, fps: v.fps, channels: null),
    AudioTrack a => (id: a.id, title: a.title, lang: a.language, codec: a.codec, h: null, fps: null, channels: a.channels),
    SubtitleTrack s => (id: s.id, title: s.title, lang: s.language, codec: s.codec, h: null, fps: null, channels: null),
    _ => (id: '', title: null, lang: null, codec: null, h: null, fps: null, channels: null),
  };
}

String trackLabel(Object track, int i, String kind) {
  final t = trackInfo(track);
  if (t.id == 'auto') return 'Otomatik';
  if (t.id == 'no') return kind == 'sub' ? 'Kapalı' : 'Yok';
  final parts = <String>[];
  if ((t.title ?? '').isNotEmpty) parts.add(t.title!);
  if ((t.lang ?? '').isNotEmpty) parts.add(langName(t.lang!));
  if (t.h != null) parts.add('${t.h}p${t.fps != null ? ' ${t.fps!.round()}fps' : ''}');
  if ((t.channels ?? '').isNotEmpty) parts.add(t.channels!);
  if (t.codec != null) parts.add(t.codec!.toUpperCase());
  return parts.isEmpty ? '${kind == 'sub' ? 'Altyazı' : 'İz'} ${i + 1}' : parts.join(' · ');
}

String langName(String code) =>
    const {
      'tur': 'Türkçe',
      'tr': 'Türkçe',
      'eng': 'İngilizce',
      'en': 'İngilizce',
      'ger': 'Almanca',
      'deu': 'Almanca',
      'de': 'Almanca',
      'fre': 'Fransızca',
      'fra': 'Fransızca',
      'fr': 'Fransızca',
      'spa': 'İspanyolca',
      'es': 'İspanyolca',
      'ara': 'Arapça',
      'ar': 'Arapça',
      'rus': 'Rusça',
      'ru': 'Rusça',
      'bul': 'Bulgarca',
      'bg': 'Bulgarca',
      'ita': 'İtalyanca',
      'it': 'İtalyanca',
      'jpn': 'Japonca',
      'ja': 'Japonca',
      'kor': 'Korece',
      'ko': 'Korece',
      'por': 'Portekizce',
      'pt': 'Portekizce',
      'und': 'Belirsiz',
    }[code.toLowerCase()] ??
    code.toUpperCase();

// =====================================================================
// Oynatıcı yüzeyi + kontroller
// =====================================================================
class PlayerSurface extends StatefulWidget {
  /// compact: canlı TV önizlemesi gibi küçük alanlar için
  final bool compact;
  const PlayerSurface({super.key, this.compact = false});
  @override
  State<PlayerSurface> createState() => _PlayerSurfaceState();
}

class _PlayerSurfaceState extends State<PlayerSurface> {
  bool _show = true;
  Timer? _hide;
  BoxFit _fit = BoxFit.contain;
  final _focus = FocusNode();
  double _seekPreview = -1;

  @override
  void initState() {
    super.initState();
    _poke();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _poke() {
    if (!_show) setState(() => _show = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && playback.player.state.playing) setState(() => _show = false);
    });
  }

  KeyEventResult _key(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final p = playback.player;
    final k = e.logicalKey;
    _poke();
    if (k == LogicalKeyboardKey.space) {
      p.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowRight && !playback.isLive) {
      p.seek(p.state.position + const Duration(seconds: 10));
    } else if (k == LogicalKeyboardKey.arrowLeft && !playback.isLive) {
      p.seek(p.state.position - const Duration(seconds: 10));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      if (playback.isLive && HardwareKeyboard.instance.isControlPressed) {
        playback.nextChannel(-1);
      } else {
        playback.setVolume(store.volume + 5);
      }
    } else if (k == LogicalKeyboardKey.arrowDown) {
      if (playback.isLive && HardwareKeyboard.instance.isControlPressed) {
        playback.nextChannel(1);
      } else {
        playback.setVolume(store.volume - 5);
      }
    } else if (k == LogicalKeyboardKey.pageUp && playback.isLive) {
      playback.nextChannel(-1);
    } else if (k == LogicalKeyboardKey.pageDown && playback.isLive) {
      playback.nextChannel(1);
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.enter) {
      windowCtl.toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyM) {
      playback.setVolume(store.volume > 0 ? 0 : 80);
    } else if (k == LogicalKeyboardKey.escape) {
      if (windowCtl.mode == ViewMode.fullscreen) {
        windowCtl.exitFullscreen();
      } else if (windowCtl.mode == ViewMode.mini) {
        windowCtl.exitMini();
      } else {
        return KeyEventResult.ignored;
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final mini = windowCtl.mode == ViewMode.mini;
    final compact = widget.compact || mini;
    return Focus(
      focusNode: _focus,
      autofocus: !widget.compact,
      onKeyEvent: _key,
      child: MouseRegion(
        cursor: _show ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onHover: (_) => _poke(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _focus.requestFocus();
            _poke();
            if (!compact) playback.player.playOrPause();
          },
          onDoubleTap: () {
            if (mini) {
              windowCtl.exitMini();
            } else if (widget.compact) {
              windowCtl.openPlayer();
            } else {
              windowCtl.toggleFullscreen();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: Video(
                  controller: playback.video,
                  controls: NoVideoControls,
                  fit: _fit,
                  fill: Colors.black,
                  subtitleViewConfiguration: SubtitleViewConfiguration(
                    style: TextStyle(
                      fontSize: compact ? 22 : store.subSize,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black),
                        Shadow(offset: Offset(1, 1), blurRadius: 2),
                      ],
                    ),
                    padding: EdgeInsets.fromLTRB(24, 0, 24, compact ? 18 : 64),
                  ),
                  onEnterFullscreen: () async => windowCtl.toggleFullscreen(),
                  onExitFullscreen: () async => windowCtl.exitFullscreen(),
                ),
              ),
              _BufferingLayer(),
              if (mini)
                _MiniBar(visible: _show)
              else
                AnimatedOpacity(
                  opacity: _show ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_show,
                    child: _Controls(
                      compact: widget.compact,
                      fit: _fit,
                      onFit: (f) => setState(() => _fit = f),
                      seekPreview: _seekPreview,
                      onSeekPreview: (v) => setState(() => _seekPreview = v),
                      onInteract: _poke,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BufferingLayer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) => StreamBuilder<bool>(
        stream: playback.player.stream.buffering,
        initialData: playback.player.state.buffering,
        builder: (context, snap) {
          final buffering = snap.data == true;
          final msg = playback.status;
          if (!buffering && msg.isEmpty) return const SizedBox.shrink();
          return IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 46, height: 46, child: CircularProgressIndicator(strokeWidth: 3.5, color: kFire)),
                  if (msg.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                      child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Mini oynatıcıda sadece sürükleme alanı ve birkaç küçük düğme.
class _MiniBar extends StatelessWidget {
  final bool visible;
  const _MiniBar({required this.visible});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: Column(
        children: [
          Container(
            height: 34,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black87, Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: DragArea(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text(
                        playback.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                _SmallBtn(Icons.open_in_full_rounded, 'Büyüt', windowCtl.exitMini),
                _SmallBtn(Icons.close_rounded, 'Kapat', () async {
                  await windowCtl.exitMini();
                  await playback.stop();
                  await windowCtl.closePlayer();
                }),
              ],
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (playback.isLive) _SmallBtn(Icons.skip_previous_rounded, 'Önceki kanal', () => playback.nextChannel(-1)),
              StreamBuilder<bool>(
                stream: playback.player.stream.playing,
                initialData: playback.player.state.playing,
                builder: (_, s) => _SmallBtn(
                  s.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  'Oynat / Duraklat',
                  () => playback.player.playOrPause(),
                ),
              ),
              if (playback.isLive) _SmallBtn(Icons.skip_next_rounded, 'Sonraki kanal', () => playback.nextChannel(1)),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class DragArea extends StatelessWidget {
  final Widget child;
  const DragArea({super.key, required this.child});
  @override
  Widget build(BuildContext context) =>
      GestureDetector(behavior: HitTestBehavior.translucent, onPanStart: (_) => startWindowDrag(), child: child);
}

/// window_manager'ı bu dosyaya bağlamamak için ana dosyada atanır.
late Future<void> Function() startWindowDrag;

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _SmallBtn(this.icon, this.tip, this.onTap);
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tip,
    onPressed: onTap,
    iconSize: 22,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, color: Colors.white),
  );
}

class _Controls extends StatelessWidget {
  final bool compact;
  final BoxFit fit;
  final ValueChanged<BoxFit> onFit;
  final double seekPreview;
  final ValueChanged<double> onSeekPreview;
  final VoidCallback onInteract;
  const _Controls({
    required this.compact,
    required this.fit,
    required this.onFit,
    required this.seekPreview,
    required this.onSeekPreview,
    required this.onInteract,
  });

  @override
  Widget build(BuildContext context) {
    final p = playback.player;
    return ListenableBuilder(
      listenable: Listenable.merge([playback, windowCtl]),
      builder: (context, _) {
        final live = playback.isLive;
        final full = windowCtl.mode == ViewMode.fullscreen;
        return Column(
          children: [
            // ---- üst şerit
            Container(
              padding: EdgeInsets.fromLTRB(8, compact ? 4 : 10, 12, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xCC000000), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  if (!compact)
                    IconButton(
                      tooltip: full ? 'Tam ekrandan çık' : 'Geri',
                      icon: Icon(full ? Icons.fullscreen_exit_rounded : Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () async {
                        if (full) {
                          await windowCtl.exitFullscreen();
                        } else {
                          if (!live) await playback.stop();
                          await windowCtl.closePlayer();
                        }
                      },
                    ),
                  if (live) ...[
                    Container(
                      margin: const EdgeInsets.only(left: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: kLive, borderRadius: BorderRadius.circular(5)),
                      child: const Text(
                        'CANLI',
                        style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1),
                      ),
                    ),
                  ] else
                    const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          playback.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: compact ? 13 : 17, fontWeight: FontWeight.w700),
                        ),
                        if (playback.subtitle.isNotEmpty && !compact)
                          Text(
                            playback.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // ---- alt şerit
            Container(
              padding: EdgeInsets.fromLTRB(10, 26, 10, compact ? 4 : 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xDD000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!live) _SeekBar(preview: seekPreview, onPreview: onSeekPreview, onInteract: onInteract),
                  Row(
                    children: [
                      if (live) _Btn(Icons.skip_previous_rounded, 'Önceki kanal (PgUp)', () => playback.nextChannel(-1)),
                      if (!live && !compact)
                        _Btn(Icons.replay_10_rounded, '10 sn geri (←)', () => p.seek(p.state.position - const Duration(seconds: 10))),
                      StreamBuilder<bool>(
                        stream: p.stream.playing,
                        initialData: p.state.playing,
                        builder: (_, s) => _Btn(
                          s.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          'Oynat / Duraklat (Boşluk)',
                          () => p.playOrPause(),
                          big: true,
                        ),
                      ),
                      if (!live && !compact)
                        _Btn(Icons.forward_10_rounded, '10 sn ileri (→)', () => p.seek(p.state.position + const Duration(seconds: 10))),
                      if (live) _Btn(Icons.skip_next_rounded, 'Sonraki kanal (PgDn)', () => playback.nextChannel(1)),
                      _VolumeControl(compact: compact),
                      if (!live)
                        StreamBuilder<Duration>(
                          stream: p.stream.position,
                          builder: (_, __) => Text(
                            '${fmtDur(p.state.position)} / ${fmtDur(p.state.duration)}',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ),
                      const Spacer(),
                      if (!compact) ...[
                        _TrackMenu(kind: 'audio'),
                        _TrackMenu(kind: 'sub'),
                        _TrackMenu(kind: 'video'),
                        _FitMenu(fit: fit, onFit: onFit),
                        if (!live) _SpeedMenu(),
                      ],
                      _Btn(
                        windowCtl.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        windowCtl.pinned ? 'Önde kalmayı kapat' : 'Pencere önde kalsın',
                        () => windowCtl.setPinned(!windowCtl.pinned),
                        active: windowCtl.pinned,
                      ),
                      _Btn(Icons.picture_in_picture_alt_rounded, 'Mini oynatıcı', windowCtl.enterMini),
                      _Btn(full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, 'Tam ekran (F)', windowCtl.toggleFullscreen),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool big;
  final bool active;
  const _Btn(this.icon, this.tip, this.onTap, {this.big = false, this.active = false});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tip,
    onPressed: onTap,
    iconSize: big ? 34 : 24,
    icon: Icon(icon, color: active ? kGold : Colors.white),
  );
}

class _SeekBar extends StatelessWidget {
  final double preview;
  final ValueChanged<double> onPreview;
  final VoidCallback onInteract;
  const _SeekBar({required this.preview, required this.onPreview, required this.onInteract});

  @override
  Widget build(BuildContext context) {
    final p = playback.player;
    return StreamBuilder<Duration>(
      stream: p.stream.position,
      builder: (context, _) {
        final dur = p.state.duration.inMilliseconds.toDouble();
        final pos = p.state.position.inMilliseconds.toDouble();
        final buf = p.state.buffer.inMilliseconds.toDouble();
        final max = dur <= 0 ? 1.0 : dur;
        final value = preview >= 0 ? preview : pos.clamp(0, max).toDouble();
        return SizedBox(
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // tamponlanmış kısım
              Positioned.fill(
                left: 24,
                right: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: dur <= 0 ? 0 : (buf / max).clamp(0, 1),
                    child: Container(height: 3, color: Colors.white38),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  inactiveTrackColor: Colors.white24,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  showValueIndicator: ShowValueIndicator.onDrag,
                  valueIndicatorColor: kCard,
                ),
                child: Slider(
                  value: value.clamp(0, max).toDouble(),
                  max: max,
                  label: fmtDur(Duration(milliseconds: value.round())),
                  onChanged: dur <= 0
                      ? null
                      : (v) {
                          onInteract();
                          onPreview(v);
                        },
                  onChangeEnd: (v) async {
                    await p.seek(Duration(milliseconds: v.round()));
                    onPreview(-1);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VolumeControl extends StatelessWidget {
  final bool compact;
  const _VolumeControl({required this.compact});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final v = store.volume;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Btn(
              v == 0 ? Icons.volume_off_rounded : (v < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              'Ses (M: sessiz)',
              () => playback.setVolume(v > 0 ? 0 : 80),
            ),
            if (!compact)
              SizedBox(
                width: 100,
                child: Slider(value: v.clamp(0, 100), max: 100, onChanged: playback.setVolume, onChangeEnd: (_) => store.saveConfig()),
              ),
          ],
        );
      },
    );
  }
}

class _TrackMenu extends StatelessWidget {
  final String kind; // audio | sub | video
  const _TrackMenu({required this.kind});

  @override
  Widget build(BuildContext context) {
    final p = playback.player;
    final icon = {'audio': Icons.audiotrack_rounded, 'sub': Icons.subtitles_rounded, 'video': Icons.high_quality_rounded}[kind]!;
    final tip = {'audio': 'Ses dili', 'sub': 'Altyazı', 'video': 'Kalite / görüntü izi'}[kind]!;
    return StreamBuilder<Tracks>(
      stream: p.stream.tracks,
      initialData: p.state.tracks,
      builder: (context, snap) {
        final t = snap.data ?? p.state.tracks;
        final List<Object> list = switch (kind) {
          'audio' => t.audio,
          'sub' => t.subtitle,
          _ => t.video,
        };
        final real = list.where((x) => trackInfo(x).id != 'auto' && trackInfo(x).id != 'no').length;
        return PopupMenuButton<Object>(
          tooltip: tip,
          icon: Badge(
            isLabelVisible: real > 1 || (kind == 'sub' && real > 0),
            backgroundColor: kFire,
            label: Text('$real', style: const TextStyle(fontSize: 9)),
            child: Icon(icon, color: Colors.white),
          ),
          onSelected: (tr) {
            if (tr is AudioTrack) p.setAudioTrack(tr);
            if (tr is SubtitleTrack) p.setSubtitleTrack(tr);
            if (tr is VideoTrack) p.setVideoTrack(tr);
          },
          itemBuilder: (_) {
            final cur = switch (kind) {
              'audio' => p.state.track.audio.id,
              'sub' => p.state.track.subtitle.id,
              _ => p.state.track.video.id,
            };
            if (list.isEmpty) {
              return [
                PopupMenuItem<Object>(
                  enabled: false,
                  child: Text('$tip seçeneği yok', style: const TextStyle(color: kDim)),
                ),
              ];
            }
            return [
              PopupMenuItem<Object>(
                enabled: false,
                height: 32,
                child: Text(
                  tip.toUpperCase(),
                  style: const TextStyle(color: kDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
              ),
              for (var i = 0; i < list.length; i++)
                PopupMenuItem<Object>(
                  value: list[i],
                  child: Row(
                    children: [
                      Icon(Icons.check_rounded, size: 18, color: trackInfo(list[i]).id == cur ? kFire : Colors.transparent),
                      const SizedBox(width: 8),
                      Flexible(child: Text(trackLabel(list[i], i, kind))),
                    ],
                  ),
                ),
            ];
          },
        );
      },
    );
  }
}

class _FitMenu extends StatelessWidget {
  final BoxFit fit;
  final ValueChanged<BoxFit> onFit;
  const _FitMenu({required this.fit, required this.onFit});
  @override
  Widget build(BuildContext context) => PopupMenuButton<BoxFit>(
    tooltip: 'Görüntü oranı',
    icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
    onSelected: onFit,
    itemBuilder: (_) => [
      for (final (f, n) in [(BoxFit.contain, 'Orijinal'), (BoxFit.cover, 'Ekranı doldur (kırp)'), (BoxFit.fill, 'Uzat')])
        PopupMenuItem(
          value: f,
          child: Row(
            children: [
              Icon(Icons.check_rounded, size: 18, color: f == fit ? kFire : Colors.transparent),
              const SizedBox(width: 8),
              Text(n),
            ],
          ),
        ),
    ],
  );
}

class _SpeedMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = playback.player;
    return PopupMenuButton<double>(
      tooltip: 'Oynatma hızı',
      icon: const Icon(Icons.speed_rounded, color: Colors.white),
      onSelected: p.setRate,
      itemBuilder: (_) => [
        for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          PopupMenuItem(
            value: r,
            child: Row(
              children: [
                Icon(Icons.check_rounded, size: 18, color: p.state.rate == r ? kFire : Colors.transparent),
                const SizedBox(width: 8),
                Text(r == 1.0 ? 'Normal' : '${r}x'),
              ],
            ),
          ),
      ],
    );
  }
}
