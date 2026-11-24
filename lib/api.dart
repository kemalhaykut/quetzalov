import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Xtream Codes uyumlu IPTV sunucusu ile konuşur (player_api.php).
class XtreamApi {
  final String server; // ör. http://ornek.com:8080
  final String user;
  final String pass;
  XtreamApi(String server, this.user, this.pass) : server = normalizeServer(server);

  static String normalizeServer(String s) {
    var t = s.trim();
    if (t.isEmpty) return t;
    if (!t.startsWith('http://') && !t.startsWith('https://')) t = 'http://$t';
    // Kullanıcı tam bir get.php / player_api.php linki yapıştırdıysa sadece adres kısmını al
    final u = Uri.tryParse(t);
    if (u != null && u.host.isNotEmpty) {
      return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
    }
    while (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  /// get.php?username=..&password=.. linkinden bilgileri çıkarır.
  static ({String server, String user, String pass})? parseFullLink(String link) {
    final u = Uri.tryParse(link.trim());
    if (u == null || u.host.isEmpty) return null;
    final user = u.queryParameters['username'];
    final pass = u.queryParameters['password'];
    if (user == null || pass == null) return null;
    return (server: '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}', user: user, pass: pass);
  }

  static const userAgent = 'Quetzalov/1.0 (Windows) VLC/3.0.20 LibVLC/3.0.20';

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = userAgent;

  Future<dynamic> _get(Map<String, String> params) async {
    final uri = Uri.parse('$server/player_api.php')
        .replace(queryParameters: {'username': user, 'password': pass, ...params});
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final req = await _http.getUrl(uri);
        final res = await req.close().timeout(const Duration(seconds: 40));
        final body = await res.transform(utf8.decoder).join();
        if (res.statusCode != 200) throw HttpException('Sunucu yanıtı: ${res.statusCode}');
        if (body.trim().isEmpty) return null;
        return jsonDecode(body);
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
    throw Exception('Sunucuya bağlanılamadı: $lastError');
  }

  Future<AccountInfo> login() async {
    final j = await _get({});
    if (j is! Map || j['user_info'] == null) throw Exception('Beklenmeyen sunucu yanıtı');
    final ui = j['user_info'] as Map;
    if ('${ui['auth']}' != '1') throw Exception('Kullanıcı adı veya şifre hatalı');
    return AccountInfo.fromJson(j.cast<String, dynamic>());
  }

  Future<List<Cat>> categories(Section s) async {
    final j = await _get({'action': 'get_${s.apiName}_categories'});
    if (j is! List) return [];
    return [for (final c in j) Cat.fromJson((c as Map).cast<String, dynamic>())];
  }

  Future<List<Item>> items(Section s) async {
    final action = switch (s) {
      Section.live => 'get_live_streams',
      Section.movies => 'get_vod_streams',
      Section.series => 'get_series',
    };
    final j = await _get({'action': action});
    if (j is! List) return [];
    return [for (final c in j) Item.fromJson(s, (c as Map).cast<String, dynamic>())];
  }

  Future<Map<String, dynamic>> vodInfo(String id) async {
    final j = await _get({'action': 'get_vod_info', 'vod_id': id});
    return j is Map ? j.cast<String, dynamic>() : {};
  }

  Future<SeriesInfo> seriesInfo(String id) async {
    final j = await _get({'action': 'get_series_info', 'series_id': id});
    return SeriesInfo.fromJson(j is Map ? j.cast<String, dynamic>() : {});
  }

  /// Şimdi / sonra yayın akışı (EPG). Başlıklar base64 gelir.
  Future<List<EpgEntry>> shortEpg(String streamId) async {
    try {
      final j = await _get({'action': 'get_short_epg', 'stream_id': streamId, 'limit': '4'});
      final list = (j is Map ? j['epg_listings'] : null) as List? ?? const [];
      return [for (final e in list) EpgEntry.fromJson((e as Map).cast<String, dynamic>())];
    } catch (_) {
      return [];
    }
  }

  String liveUrl(String id, {String ext = 'ts'}) => '$server/live/$user/$pass/$id.$ext';
  String movieUrl(String id, String ext) => '$server/movie/$user/$pass/$id.${ext.isEmpty ? 'mp4' : ext}';
  String episodeUrl(String id, String ext) => '$server/series/$user/$pass/$id.${ext.isEmpty ? 'mp4' : ext}';
}

enum Section {
  live('live', 'Canlı TV'),
  movies('vod', 'Filmler'),
  series('series', 'Diziler');

  final String apiName;
  final String title;
  const Section(this.apiName, this.title);
}

String _s(dynamic v) => v == null ? '' : '$v';

class AccountInfo {
  final String status;
  final DateTime? expires;
  final int maxConnections;
  final int activeConnections;
  final String serverUrl;
  AccountInfo(this.status, this.expires, this.maxConnections, this.activeConnections, this.serverUrl);

  factory AccountInfo.fromJson(Map<String, dynamic> j) {
    final ui = (j['user_info'] as Map).cast<String, dynamic>();
    final si = (j['server_info'] as Map? ?? const {}).cast<String, dynamic>();
    final exp = int.tryParse(_s(ui['exp_date']));
    return AccountInfo(
      _s(ui['status']),
      exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      int.tryParse(_s(ui['max_connections'])) ?? 0,
      int.tryParse(_s(ui['active_cons'])) ?? 0,
      _s(si['url']),
    );
  }
}

class Cat {
  final String id;
  final String name;
  Cat(this.id, this.name);
  factory Cat.fromJson(Map<String, dynamic> j) => Cat(_s(j['category_id']), _s(j['category_name']).trim());
}

/// Kanal, film ya da dizi.
class Item {
  final Section section;
  final String id;
  final String name;
  final String image;
  final String categoryId;
  final String ext;
  final double rating;
  final String year;
  final int added;
  Item(this.section, this.id, this.name, this.image, this.categoryId, this.ext, this.rating, this.year, this.added);

  String get key => '${section.name}:$id';

  factory Item.fromJson(Section s, Map<String, dynamic> j) {
    final id = _s(s == Section.series ? j['series_id'] : j['stream_id']);
    final img = _s(s == Section.series ? j['cover'] : j['stream_icon']);
    final rating = double.tryParse(_s(j['rating_5based'])) ?? ((double.tryParse(_s(j['rating'])) ?? 0) / 2);
    var year = _s(j['year']);
    if (year.isEmpty) {
      final rd = _s(j['releaseDate'] ?? j['release_date']);
      if (rd.length >= 4) year = rd.substring(0, 4);
    }
    return Item(s, id, _s(j['name']).trim(), img, _s(j['category_id']), _s(j['container_extension']), rating, year,
        int.tryParse(_s(j['added'] ?? j['last_modified'])) ?? 0);
  }

  Map<String, dynamic> toJson() => {
        's': section.name, 'id': id, 'n': name, 'i': image, 'c': categoryId, 'e': ext, 'r': rating, 'y': year,
      };
  factory Item.fromStore(Map<String, dynamic> j) => Item(
        Section.values.firstWhere((x) => x.name == j['s'], orElse: () => Section.live),
        _s(j['id']), _s(j['n']), _s(j['i']), _s(j['c']), _s(j['e']),
        (j['r'] as num?)?.toDouble() ?? 0, _s(j['y']), 0);
}

class Episode {
  final String id;
  final int season;
  final int number;
  final String title;
  final String ext;
  final String plot;
  final String image;
  final int durationSecs;
  Episode(this.id, this.season, this.number, this.title, this.ext, this.plot, this.image, this.durationSecs);
}

class SeriesInfo {
  final String plot;
  final String cover;
  final String genre;
  final String cast;
  final String year;
  final String rating;
  final Map<int, List<Episode>> seasons;
  SeriesInfo(this.plot, this.cover, this.genre, this.cast, this.year, this.rating, this.seasons);

  factory SeriesInfo.fromJson(Map<String, dynamic> j) {
    final info = (j['info'] is Map ? j['info'] as Map : const {}).cast<String, dynamic>();
    final seasons = <int, List<Episode>>{};
    final eps = j['episodes'];
    void addEp(dynamic e, int fallbackSeason) {
      if (e is! Map) return;
      final m = e.cast<String, dynamic>();
      final inf = (m['info'] is Map ? m['info'] as Map : const {}).cast<String, dynamic>();
      final season = int.tryParse(_s(m['season'])) ?? fallbackSeason;
      seasons.putIfAbsent(season, () => []).add(Episode(
            _s(m['id']),
            season,
            int.tryParse(_s(m['episode_num'])) ?? 0,
            _s(m['title']),
            _s(m['container_extension']),
            _s(inf['plot']),
            _s(inf['movie_image']),
            int.tryParse(_s(inf['duration_secs'])) ?? 0,
          ));
    }

    if (eps is Map) {
      eps.forEach((k, v) {
        if (v is List) {
          for (final e in v) {
            addEp(e, int.tryParse('$k') ?? 1);
          }
        }
      });
    } else if (eps is List) {
      for (final group in eps) {
        if (group is List) {
          for (final e in group) {
            addEp(e, 1);
          }
        }
      }
    }
    for (final l in seasons.values) {
      l.sort((a, b) => a.number.compareTo(b.number));
    }
    return SeriesInfo(_s(info['plot']), _s(info['cover']), _s(info['genre']), _s(info['cast']),
        _s(info['releaseDate']).length >= 4 ? _s(info['releaseDate']).substring(0, 4) : '', _s(info['rating']), seasons);
  }
}

class EpgEntry {
  final String title;
  final String description;
  final DateTime? start;
  final DateTime? end;
  EpgEntry(this.title, this.description, this.start, this.end);

  static String _b64(String s) {
    try {
      return utf8.decode(base64.decode(s));
    } catch (_) {
      return s;
    }
  }

  factory EpgEntry.fromJson(Map<String, dynamic> j) {
    DateTime? ts(String k) {
      final v = int.tryParse(_s(j[k]));
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }

    return EpgEntry(_b64(_s(j['title'])), _b64(_s(j['description'])), ts('start_timestamp'), ts('stop_timestamp'));
  }
}
