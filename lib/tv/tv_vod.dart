import 'package:flutter/material.dart';

import '../api.dart';
import '../player.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'tv_live.dart';
import 'tv_player.dart';
import 'tv_widgets.dart';

final Map<Section, String?> _catSel = {};
final Map<String, SeriesInfo> _seriesCache = {};

Future<void> _openPlayer(BuildContext context) => openNativePlayer();

Future<void> playMovieTv(BuildContext context, Item m, {bool resume = true}) async {
  await playback.playMovie(m, resume: resume);
  if (context.mounted) await _openPlayer(context);
}

Future<void> playEpisodeTv(BuildContext context, Item s, Episode e, {bool resume = true}) async {
  await playback.playEpisode(s, e, resume: resume);
  if (context.mounted) await _openPlayer(context);
}

/// Bir öğeyi aç: film → detay, dizi → bölümler, kanal → oynat.
void openItemTv(BuildContext context, Item it, {List<Item>? list}) {
  switch (it.section) {
    case Section.live:
      openLive(context, it, list ?? [it]);
    case Section.movies:
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvMovieDetail(it)));
    case Section.series:
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvSeriesDetail(it)));
  }
}

// ============================ Film / Dizi listesi ============================
class TvVod extends StatefulWidget {
  final Section section;
  const TvVod({super.key, required this.section});
  @override
  State<TvVod> createState() => _TvVodState();
}

class _TvVodState extends State<TvVod> {
  late Future<void> loading = store.load(widget.section);
  late String? cat = _catSel[widget.section] ?? '+';

  List<Item> _list() {
    final all = store.items[widget.section] ?? [];
    if (cat == '★') return all.where(store.isFav).toList();
    if (cat == '+') {
      final l = [...all]..sort((a, b) => b.added.compareTo(a.added));
      return l.take(300).toList();
    }
    if (cat == null) return all;
    return all.where((x) => x.categoryId == cat).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    return FutureBuilder<void>(
      future: loading,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView('${s.title} yüklenemedi.\n${snap.error}', () => setState(() => loading = store.load(s, force: true)));
        }
        if (snap.connectionState != ConnectionState.done) return LoadingView('${s.title} yükleniyor…');
        final cats = store.cats[s] ?? [];
        final list = _list();
        return Row(
          children: [
            SizedBox(
              width: 220,
              child: FocusTraversalGroup(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 14, 6, 20),
                  children: [
                    TvTitle(s.title),
                    for (final (id, name) in [
                      ('+', 'Yeni eklenenler'),
                      (null, 'Tümü'),
                      ('★', '★ Favoriler'),
                      for (final c in cats) (c.id, c.name),
                    ])
                      TvRow(
                        selected: cat == id,
                        onFocus: (f) {
                          if (f && cat != id) setState(() => cat = _catSel[s] = id);
                        },
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: FocusTraversalGroup(
                child: list.isEmpty ? const EmptyView('Bu kategoride içerik yok') : PosterGrid(key: ValueKey('$s$cat'), items: list),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PosterGrid extends StatelessWidget {
  final List<Item> items;
  const PosterGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 128,
      mainAxisSpacing: 14,
      crossAxisSpacing: 12,
      childAspectRatio: 0.58,
    ),
    itemCount: items.length,
    itemBuilder: (context, i) => TvPoster(items[i], onTap: () => openItemTv(context, items[i], list: items)),
  );
}

class TvPoster extends StatelessWidget {
  final Item it;
  final VoidCallback onTap;
  final double progress;
  const TvPoster(this.it, {super.key, required this.onTap, this.progress = 0});

  @override
  Widget build(BuildContext context) => TvFocus(
    onTap: onTap,
    radius: 10,
    scale: 1.08,
    builder: (_, f) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(
                  it.image,
                  label: it.name,
                  fit: it.section == Section.live ? BoxFit.contain : BoxFit.cover,
                  icon: it.section == Section.live ? Icons.live_tv_rounded : Icons.movie_rounded,
                ),
                if (it.rating > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .7), borderRadius: BorderRadius.circular(5)),
                      child: Text(
                        '★ ${(it.rating * 2).toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 9.5, color: kGold, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                if (store.isFav(it)) const Positioned(top: 3, left: 4, child: Icon(Icons.star_rounded, color: kGold, size: 16)),
                if (progress > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(value: progress, minHeight: 3, color: kFire, backgroundColor: Colors.black54),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          it.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: f ? FontWeight.w700 : FontWeight.w500, color: f ? Colors.white : kDim),
        ),
      ],
    ),
  );
}

// ============================ Film detayı ============================
class TvMovieDetail extends StatelessWidget {
  final Item m;
  const TvMovieDetail(this.m, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: store.api!.vodInfo(m.id),
        builder: (context, snap) {
          final info = (snap.data?['info'] is Map ? snap.data!['info'] as Map : const {}).cast<String, dynamic>();
          String f(String k) => info[k] == null ? '' : '${info[k]}';
          final backdrop = (info['backdrop_path'] is List && (info['backdrop_path'] as List).isNotEmpty)
              ? '${(info['backdrop_path'] as List).first}'
              : '';
          final meta = [
            if (m.year.isNotEmpty) m.year,
            if (f('genre').isNotEmpty) f('genre'),
            if (f('duration').isNotEmpty) f('duration'),
            if (m.rating > 0) '★ ${(m.rating * 2).toStringAsFixed(1)}',
          ].join('  ·  ');
          return Stack(
            fit: StackFit.expand,
            children: [
              if (backdrop.isNotEmpty) Opacity(opacity: .2, child: NetImage(backdrop)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kBg, kBg.withValues(alpha: .6)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 30, 40, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 190,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: NetImage(m.image, label: m.name),
                        ),
                      ),
                    ),
                    const SizedBox(width: 30),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: store,
                        builder: (context, _) {
                          final resume = store.resumeOf(m.key);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name, maxLines: 2, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              if (meta.isNotEmpty) Text(meta, style: const TextStyle(color: kDim, fontSize: 13)),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  if (resume != null)
                                    TvButton(
                                      'Devam et (${fmtDur(resume)})',
                                      Icons.play_arrow_rounded,
                                      () => playMovieTv(context, m),
                                      autofocus: true,
                                      primary: true,
                                    ),
                                  TvButton(
                                    resume != null ? 'Baştan izle' : 'İzle',
                                    resume != null ? Icons.replay_rounded : Icons.play_arrow_rounded,
                                    () => playMovieTv(context, m, resume: false),
                                    autofocus: resume == null,
                                    primary: resume == null,
                                  ),
                                  TvButton(
                                    store.isFav(m) ? 'Favorilerden çıkar' : 'Favorilere ekle',
                                    store.isFav(m) ? Icons.star_rounded : Icons.star_border_rounded,
                                    () => store.toggleFav(m),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (snap.connectionState != ConnectionState.done)
                                const Text('Bilgiler yükleniyor…', style: TextStyle(color: kDim))
                              else
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (f('plot').isNotEmpty)
                                          Text(f('plot'), style: const TextStyle(height: 1.5, fontSize: 13.5, color: Color(0xFFD8D4E0))),
                                        if (f('cast').isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          Text('Oyuncular: ${f('cast')}', style: const TextStyle(color: kDim, fontSize: 12.5)),
                                        ],
                                        if (f('director').isNotEmpty)
                                          Text('Yönetmen: ${f('director')}', style: const TextStyle(color: kDim, fontSize: 12.5)),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================ Dizi detayı ============================
class TvSeriesDetail extends StatefulWidget {
  final Item series;
  const TvSeriesDetail(this.series, {super.key});
  @override
  State<TvSeriesDetail> createState() => _TvSeriesDetailState();
}

class _TvSeriesDetailState extends State<TvSeriesDetail> {
  late Future<SeriesInfo> info;
  int? season;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final id = widget.series.id;
    final c = _seriesCache[id];
    info = c != null ? Future.value(c) : store.api!.seriesInfo(id).then((v) => _seriesCache[id] = v);
  }

  /// En son izlenen bölümü bul (sezon seçimi ve "devam" düğmesi için)
  Episode? _lastWatched(SeriesInfo d) {
    Episode? best;
    num bestT = 0;
    for (final eps in d.seasons.values) {
      for (final e in eps) {
        final p = store.progress['ep:${e.id}'];
        final t = (p?['t'] as num?) ?? 0;
        if (p != null && t > bestT) {
          bestT = t;
          best = e;
        }
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.series;
    return Scaffold(
      body: FutureBuilder<SeriesInfo>(
        future: info,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorView('Dizi bilgisi alınamadı.\n${snap.error}', () => setState(_load));
          }
          if (!snap.hasData) return const LoadingView('Bölümler yükleniyor…');
          final d = snap.data!;
          final seasons = d.seasons.keys.toList()..sort();
          final last = _lastWatched(d);
          season ??= last?.season ?? (seasons.isEmpty ? 1 : seasons.first);
          final eps = [...(d.seasons[season] ?? const <Episode>[])]..sort((a, b) => a.number.compareTo(b.number));
          return ListenableBuilder(
            listenable: store,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                Opacity(opacity: .14, child: NetImage(d.cover.isNotEmpty ? d.cover : s.image)),
                DecoratedBox(decoration: BoxDecoration(color: kBg.withValues(alpha: .55))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 24, 30, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 150,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: NetImage(s.image, label: s.name),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  [if (d.year.isNotEmpty) d.year, if (d.genre.isNotEmpty) d.genre, '${seasons.length} sezon'].join('  ·  '),
                                  style: const TextStyle(color: kDim, fontSize: 12.5),
                                ),
                                const SizedBox(height: 6),
                                if (d.plot.isNotEmpty)
                                  Text(
                                    d.plot,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                                  ),
                                const SizedBox(height: 10),
                                FocusTraversalGroup(
                                  child: Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      if (last != null)
                                        TvButton(
                                          'Devam: S${last.season} B${last.number}',
                                          Icons.play_arrow_rounded,
                                          () => playEpisodeTv(context, s, last),
                                          autofocus: true,
                                          primary: true,
                                        ),
                                      TvButton(
                                        store.isFav(s) ? 'Favorilerden çıkar' : 'Favorilere ekle',
                                        store.isFav(s) ? Icons.star_rounded : Icons.star_border_rounded,
                                        () => store.toggleFav(s),
                                        autofocus: last == null,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 44,
                        child: FocusTraversalGroup(
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final n in seasons)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: TvFocus(
                                    radius: 20,
                                    scale: 1.0,
                                    onFocus: (f) {
                                      if (f && season != n) setState(() => season = n);
                                    },
                                    onTap: () => setState(() => season = n),
                                    builder: (_, f) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                      decoration: BoxDecoration(
                                        gradient: season == n ? kFireGradient : null,
                                        color: season == n ? null : kCard,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text('$n. Sezon', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: FocusTraversalGroup(
                          child: ListView.builder(
                            key: ValueKey(season),
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: eps.length,
                            itemBuilder: (context, i) {
                              final e = eps[i];
                              final key = 'ep:${e.id}';
                              final prog = store.progressOf(key);
                              final watched = store.progress[key] != null && store.resumeOf(key) == null && prog > 0.9;
                              return TvRow(
                                onTap: () => playEpisodeTv(context, s, e),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 120,
                                      height: 66,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            NetImage(e.image.isNotEmpty ? e.image : s.image, icon: Icons.play_circle_outline_rounded),
                                            if (prog > 0)
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                bottom: 0,
                                                child: LinearProgressIndicator(
                                                  value: prog,
                                                  minHeight: 3,
                                                  color: kFire,
                                                  backgroundColor: Colors.black54,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${e.number}. Bölüm${e.title.isNotEmpty && !e.title.contains(s.name) ? ' — ${e.title}' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                          if (e.plot.isNotEmpty)
                                            Text(
                                              e.plot,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: kDim, fontSize: 11.5, fontWeight: FontWeight.w400),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (e.durationSecs > 0)
                                      Text(
                                        fmtDur(Duration(seconds: e.durationSecs)),
                                        style: const TextStyle(color: kDim, fontSize: 12),
                                      ),
                                    if (watched)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Icon(Icons.check_circle_rounded, color: kFire, size: 18),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================ Favoriler + İzlemeye devam ============================
class TvFavorites extends StatelessWidget {
  const TvFavorites({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cw = store.continueWatching;
        final favs = store.favorites.values.toList();
        if (cw.isEmpty && favs.isEmpty) {
          return const EmptyView('Henüz favori yok.\nBir film/dizi detayında "Favorilere ekle"yi seç.', icon: Icons.star_border_rounded);
        }
        Widget row(String title, List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8), child: TvTitle(title)),
            SizedBox(
              height: 210,
              child: FocusTraversalGroup(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  children: [
                    for (final c in children)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: SizedBox(width: 112, child: c),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
        final live = favs.where((x) => x.section == Section.live).toList();
        final movies = favs.where((x) => x.section == Section.movies).toList();
        final series = favs.where((x) => x.section == Section.series).toList();
        return ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            if (cw.isNotEmpty) row('İzlemeye devam et', [for (final e in cw) _cwPoster(context, e)]),
            if (live.isNotEmpty)
              row('Favori kanallar', [for (final it in live) TvPoster(it, onTap: () => openItemTv(context, it, list: live))]),
            if (movies.isNotEmpty) row('Favori filmler', [for (final it in movies) TvPoster(it, onTap: () => openItemTv(context, it))]),
            if (series.isNotEmpty) row('Favori diziler', [for (final it in series) TvPoster(it, onTap: () => openItemTv(context, it))]),
          ],
        );
      },
    );
  }

  Widget _cwPoster(BuildContext context, Map<String, dynamic> e) {
    final it = Item.fromStore((e['item'] as Map).cast<String, dynamic>());
    final ep = e['ep'] is Map ? (e['ep'] as Map).cast<String, dynamic>() : null;
    final prog = store.progressOf(e['key'] as String);
    return TvPoster(
      it,
      progress: prog,
      onTap: () {
        if (ep != null) {
          final episode = Episode(
            '${ep['id']}',
            (ep['s'] as num?)?.toInt() ?? 1,
            (ep['n'] as num?)?.toInt() ?? 1,
            '${ep['t'] ?? ''}',
            '${ep['e'] ?? ''}',
            '',
            '',
            0,
          );
          playEpisodeTv(context, it, episode);
        } else {
          playMovieTv(context, it);
        }
      },
    );
  }
}

// ============================ Arama ============================
class TvSearch extends StatefulWidget {
  const TvSearch({super.key});
  @override
  State<TvSearch> createState() => _TvSearchState();
}

class _TvSearchState extends State<TvSearch> {
  final q = TextEditingController();
  String query = '';
  late final Future<void> loading = Future.wait([for (final s in Section.values) store.load(s)]);

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: TvTextField(
            child: TextField(
              controller: q,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'Kanal, film veya dizi ara… (OK → klavye)',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onSubmitted: (v) => setState(() => query = v.trim()),
              onChanged: (v) {
                final t = v.trim();
                if (t.length >= 3 || t.isEmpty) setState(() => query = t);
              },
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<void>(
            future: loading,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const LoadingView('İçerik listesi hazırlanıyor…');
              if (query.length < 2) {
                return const EmptyView('En az 2 harf yaz ve klavyede Ara/Tamam\'a bas.', icon: Icons.keyboard_rounded);
              }
              final nq = norm(query);
              final results = <Section, List<Item>>{};
              for (final s in Section.values) {
                results[s] = (store.items[s] ?? []).where((x) => norm(x.name).contains(nq)).take(60).toList();
              }
              if (results.values.every((l) => l.isEmpty)) return EmptyView('"$query" için sonuç yok');
              return FocusTraversalGroup(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 30),
                  children: [
                    for (final s in Section.values)
                      if (results[s]!.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: TvTitle(s.title, sub: '${results[s]!.length} sonuç'),
                        ),
                        SizedBox(
                          height: 210,
                          child: FocusTraversalGroup(
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              itemCount: results[s]!.length,
                              itemBuilder: (context, i) {
                                final it = results[s]![i];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 14),
                                  child: SizedBox(
                                    width: 112,
                                    child: TvPoster(it, onTap: () => openItemTv(context, it, list: results[s])),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
