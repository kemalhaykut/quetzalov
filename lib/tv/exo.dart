import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Android TV oynatıcısı (ExoPlayer). Yerel taraf: android_src/QzPlayer.kt
class ExoTrack {
  final String type; // audio | sub | video
  final String id;
  final String? label;
  final String? lang;
  final int? h;
  final String? codec;
  final int? ch;
  final bool sel;
  ExoTrack(this.type, this.id, this.label, this.lang, this.h, this.codec, this.ch, this.sel);
}

class Exo extends ChangeNotifier {
  static const _m = MethodChannel('qz/player');

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration buffered = Duration.zero;
  bool playing = false;
  bool buffering = false;
  List<ExoTrack> tracks = [];
  bool subOff = false;

  final _errors = StreamController<String>.broadcast();
  final _ended = StreamController<void>.broadcast();
  Stream<String> get errors => _errors.stream;
  Stream<void> get ended => _ended.stream;

  Timer? _poll;
  int _errSeq = 0, _endSeq = 0, _trkSeq = -1;
  bool _polling = false;

  /// Oynatıcı durumunu 400 ms'de bir yerel taraftan sorar.
  void init() {
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_polling) return;
    _polling = true;
    try {
      final st = await _m.invokeMethod<Map<Object?, Object?>>('state');
      if (st == null) return;
      Duration ms(Object? v) => Duration(milliseconds: (v as num?)?.toInt() ?? 0);
      final np = ms(st['pos']), nd = ms(st['dur']), nb = ms(st['buf']);
      final npl = st['playing'] == true, nbu = st['buffering'] == true;
      final changed = np != position || nd != duration || nb != buffered || npl != playing || nbu != buffering;
      position = np;
      duration = nd;
      buffered = nb;
      playing = npl;
      buffering = nbu;
      final es = (st['errorSeq'] as num?)?.toInt() ?? 0;
      if (es != _errSeq) {
        _errSeq = es;
        _errors.add('${st['error']}');
      }
      final en = (st['endedSeq'] as num?)?.toInt() ?? 0;
      if (en != _endSeq) {
        _endSeq = en;
        _ended.add(null);
      }
      final ts = (st['tracksSeq'] as num?)?.toInt() ?? 0;
      if (ts != _trkSeq) {
        _trkSeq = ts;
        await refreshTracks();
      }
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('exo durum: $e');
    } finally {
      _polling = false;
    }
  }

  Future<void> refreshTracks() async {
    try {
      final r = await _m.invokeMethod<Map<Object?, Object?>>('tracks');
      if (r == null) return;
      subOff = r['subOff'] == true;
      tracks = [
        for (final t in (r['list'] as List? ?? const []))
          if (t is Map)
            ExoTrack(
              '${t['type']}',
              '${t['id']}',
              t['label'] as String?,
              t['lang'] as String?,
              (t['h'] as num?)?.toInt(),
              t['codec'] as String?,
              (t['ch'] as num?)?.toInt(),
              t['sel'] == true,
            ),
      ];
      notifyListeners();
    } catch (e) {
      debugPrint('exo izler: $e');
    }
  }

  Future<void> _call(String m, [Map<String, Object?>? a]) async {
    try {
      await _m.invokeMethod<void>(m, a);
    } catch (e) {
      debugPrint('exo $m: $e');
    }
  }

  Future<void> open(
    String url, {
    Duration? start,
    required int buffer,
    required String ua,
    required String subLang,
    required String audioLang,
    required double subSize,
  }) {
    position = Duration.zero;
    duration = Duration.zero;
    buffered = Duration.zero;
    tracks = [];
    buffering = true;
    notifyListeners();
    return _call('open', {
      'url': url,
      'start': start?.inMilliseconds,
      'buffer': buffer,
      'ua': ua,
      'subLang': subLang,
      'audioLang': audioLang,
      'subSize': subSize,
    });
  }

  Future<void> play() => _call('play');
  Future<void> pause() => _call('pause');
  Future<void> toggle() {
    playing = !playing;
    notifyListeners();
    return _call('toggle');
  }

  Future<void> seek(Duration d) {
    position = d;
    notifyListeners();
    return _call('seek', {'ms': d.inMilliseconds});
  }

  Future<void> stop() => _call('stop');
  Future<void> selectTrack(String type, String id) async {
    await _call('track', {'type': type, 'id': id});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await refreshTracks();
  }

  Future<void> setSubSize(double sp) => _call('subSize', {'size': sp});
  Future<void> setFit(String mode) => _call('fit', {'mode': mode});

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

/// Yerel video yüzeyi (karma birleştirme: menüler video üstünde beyaz ekran yapmadan çizilir).
class ExoView extends StatelessWidget {
  const ExoView({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: 'qz/video',
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (params) {
        final c = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: 'qz/video',
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: const StandardMessageCodec(),
        );
        c.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
        c.create();
        return c;
      },
    );
  }
}
