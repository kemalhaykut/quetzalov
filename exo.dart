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
  static const _e = EventChannel('qz/player/events');

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
  StreamSubscription<dynamic>? _sub;

  void init() {
    _sub = _e.receiveBroadcastStream().listen(_on, onError: (Object e) => debugPrint('exo olay: $e'));
  }

  void _on(dynamic ev) {
    if (ev is! Map) return;
    switch (ev['t']) {
      case 'pos':
        position = Duration(milliseconds: (ev['pos'] as num?)?.toInt() ?? 0);
        duration = Duration(milliseconds: (ev['dur'] as num?)?.toInt() ?? 0);
        buffered = Duration(milliseconds: (ev['buf'] as num?)?.toInt() ?? 0);
        playing = ev['playing'] == true;
        buffering = ev['buffering'] == true;
      case 'tracks':
        subOff = ev['subOff'] == true;
        tracks = [
          for (final t in (ev['list'] as List? ?? const []))
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
      case 'error':
        _errors.add('${ev['msg']}');
      case 'ended':
        _ended.add(null);
    }
    notifyListeners();
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
  Future<void> selectTrack(String type, String id) => _call('track', {'type': type, 'id': id});
  Future<void> setSubSize(double sp) => _call('subSize', {'size': sp});
  Future<void> setFit(String mode) => _call('fit', {'mode': mode});

  @override
  void dispose() {
    _sub?.cancel();
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
