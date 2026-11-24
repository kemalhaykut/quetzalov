import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'api.dart';

/// Ayarlar, hesap, favoriler ve izleme ilerlemesi. %APPDATA%\Quetzalov altında JSON olarak saklanır.
class Store extends ChangeNotifier {
  late final Directory dir;

  String server = '';
  String user = '';
  String pass = '';
  bool get hasAccount => server.isNotEmpty && user.isNotEmpty;

  // Ayarlar
  String liveFormat = 'ts'; // ts | m3u8
  int bufferLevel = 1; // 0 normal, 1 büyük, 2 çok büyük
  bool hwdec = true;
  double volume = 80;
  String subLang = 'tur';
  String audioLang = '';
  double subSize = 44;

  final Map<String, Item> favorites = {}; // key → item
  final Map<String, Map<String, dynamic>> progress = {}; // key → {pos, dur, t, item, ep}
  final List<String> recentSearches = [];

  XtreamApi? api;
  AccountInfo? account;

  // Bellek önbelleği
  final Map<Section, List<Cat>> cats = {};
  final Map<Section, List<Item>> items = {};
  final Map<Section, Future<void>> _loading = {};

  /// [dataDir] verilirse (Android TV) oraya, yoksa %APPDATA%\Quetzalov altına kaydeder.
  Future<void> init({String? dataDir}) async {
    if (dataDir != null) {
      dir = Directory(dataDir);
    } else {
      final base = Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
      dir = Directory('$base${Platform.pathSeparator}Quetzalov');
    }
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final j = _read('config.json');
    if (j is Map) {
      server = '${j['server'] ?? ''}';
      user = '${j['user'] ?? ''}';
      pass = '${j['pass'] ?? ''}';
      liveFormat = '${j['liveFormat'] ?? 'ts'}';
      bufferLevel = (j['bufferLevel'] as num?)?.toInt() ?? 1;
      hwdec = j['hwdec'] as bool? ?? true;
      volume = (j['volume'] as num?)?.toDouble() ?? 80;
      subLang = '${j['subLang'] ?? 'tur'}';
      audioLang = '${j['audioLang'] ?? ''}';
      subSize = (j['subSize'] as num?)?.toDouble() ?? 44;
    }
    final f = _read('favorites.json');
    if (f is List) {
      for (final e in f) {
        if (e is Map) {
          final it = Item.fromStore(e.cast<String, dynamic>());
          favorites[it.key] = it;
        }
      }
    }
    final p = _read('progress.json');
    if (p is Map) {
      p.forEach((k, v) {
        if (v is Map) progress['$k'] = v.cast<String, dynamic>();
      });
    }
    if (hasAccount) api = XtreamApi(server, user, pass);
  }

  dynamic _read(String name) {
    try {
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      if (!f.existsSync()) return null;
      return jsonDecode(f.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  void _write(String name, Object data) {
    try {
      File('${dir.path}${Platform.pathSeparator}$name').writeAsStringSync(jsonEncode(data));
    } catch (e) {
      debugPrint('Kaydedilemedi: $e');
    }
  }

  void saveConfig() {
    _write('config.json', {
      'server': server, 'user': user, 'pass': pass, 'liveFormat': liveFormat, 'bufferLevel': bufferLevel,
      'hwdec': hwdec, 'volume': volume, 'subLang': subLang, 'audioLang': audioLang, 'subSize': subSize,
    });
    notifyListeners();
  }

  Future<void> login(String srv, String u, String p) async {
    final a = XtreamApi(srv, u, p);
    final info = await a.login();
    server = a.server;
    user = u;
    pass = p;
    api = a;
    account = info;
    cats.clear();
    items.clear();
    _loading.clear();
    saveConfig();
  }

  Future<void> refreshAccount() async {
    try {
      account = await api?.login();
      notifyListeners();
    } catch (_) {}
  }

  void logout() {
    user = '';
    pass = '';
    api = null;
    account = null;
    cats.clear();
    items.clear();
    _loading.clear();
    saveConfig();
  }

  /// Bir bölümün kategori ve içeriklerini (bir kez) yükler.
  Future<void> load(Section s, {bool force = false}) {
    if (force) {
      _loading.remove(s);
      cats.remove(s);
      items.remove(s);
    }
    return _loading.putIfAbsent(s, () async {
      try {
        final r = await Future.wait([api!.categories(s), api!.items(s)]);
        cats[s] = r[0] as List<Cat>;
        final list = r[1] as List<Item>;
        items[s] = list;
        notifyListeners();
      } catch (e) {
        _loading.remove(s);
        rethrow;
      }
    });
  }

  // ---------------- favoriler ----------------
  bool isFav(Item it) => favorites.containsKey(it.key);
  void toggleFav(Item it) {
    if (favorites.remove(it.key) == null) favorites[it.key] = it;
    _write('favorites.json', [for (final f in favorites.values) f.toJson()]);
    notifyListeners();
  }

  // ---------------- kaldığın yerden devam ----------------
  Duration? resumeOf(String key) {
    final p = progress[key];
    if (p == null) return null;
    final pos = (p['pos'] as num?)?.toInt() ?? 0;
    final dur = (p['dur'] as num?)?.toInt() ?? 0;
    if (pos < 30 || (dur > 0 && pos > dur - 60)) return null;
    return Duration(seconds: pos);
  }

  double progressOf(String key) {
    final p = progress[key];
    if (p == null) return 0;
    final pos = (p['pos'] as num?)?.toDouble() ?? 0;
    final dur = (p['dur'] as num?)?.toDouble() ?? 0;
    return dur <= 0 ? 0 : (pos / dur).clamp(0, 1);
  }

  void saveProgress(String key, Duration pos, Duration dur, Map<String, dynamic> meta) {
    if (dur.inSeconds < 60) return;
    progress[key] = {'pos': pos.inSeconds, 'dur': dur.inSeconds, 't': DateTime.now().millisecondsSinceEpoch, ...meta};
    if (progress.length > 300) {
      final keys = progress.keys.toList()
        ..sort((a, b) => ((progress[a]!['t'] as num?) ?? 0).compareTo((progress[b]!['t'] as num?) ?? 0));
      for (final k in keys.take(progress.length - 300)) {
        progress.remove(k);
      }
    }
    _write('progress.json', progress);
  }

  /// "İzlemeye devam et" listesi.
  List<Map<String, dynamic>> get continueWatching {
    final l = progress.entries
        .where((e) => resumeOf(e.key) != null && e.value['item'] is Map)
        .map((e) => {'key': e.key, ...e.value})
        .toList()
      ..sort((a, b) => ((b['t'] as num?) ?? 0).compareTo((a['t'] as num?) ?? 0));
    return l.take(20).toList();
  }
}

final store = Store();
