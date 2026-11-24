import 'package:flutter/material.dart';
import 'api.dart';
import 'player.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';
import 'window_ctl.dart';

final _vodCat = <Section, String?>{};
final _vodSort = <Section, int>{};
final _openSeries = <Section, Item?>{};

/// Favorilerden bir diziyi Diziler sekmesinde açmak için.
void openSeriesLater(Item series) => _openSeries[Section.series] = series;

/// Filmler ve Diziler: kategoriler | afiş ızgarası
class VodPage extends StatefulWidget {
  final Section section;
  final String query;
  const VodPage({super.key, required this.section, required this.query});
  @override
  State<VodPage> createState() => _VodPageState();
}

class _VodPageState extends State<VodPage> {
  late String? cat = _vodCat[widget.section];
  late int sort = _vodSort[widget.section] ?? 0;
  Future<void>? loading;
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    loading = store.load(widget.section);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  List<Item> _filtered() {
    final all = store.items[widget.section] ?? [];
    final q = norm(widget.query.trim());
    Iterable<Item> l = all;
    if (q.isNotEmpty) {
      l = l.where((x) => norm(x.name).contains(q));
    } else if (cat == '★') {
      l = l.where(store.isFav);
    } else if (cat != null) {
      l = l.where((x) => x.categoryId == cat);
    }
    final r = l.toList();
    switch (sort) {
      case 1:
        r.sort((a, b) => b.added.compareTo(a.added));
      case 2:
        r.sort((a, b) => norm(a.name).compareTo(norm(b.name)));
      case 3:
        r.sort((a, b) => b.rating.compareTo(a.rating));
      case 4:
        r.sort((a, b) => b.year.compareTo(a.year));
    }
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    final opened = _openSeries[s];
    if (opened != null) {
      return SeriesDetail(series: opened, onBack: () => setState(() => _openSeries[s] = null));
    }
    return FutureBuilder<void>(
      future: loading,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView('${s.title} yüklenemedi.\n${snap.error}', () => setState(() => loading = store.load(s, force: true)));
        }
        if (snap.connectionState != ConnectionState.done) return LoadingView('${s.title} yükleniyor…');
        return ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final all = store.items[s] ?? [];
            final counts = <String, int>{};
            for (final it in all) {
              counts[it.categoryId] = (counts[it.categoryId] ?? 0) + 1;
            }
            final list = _filtered();
            final cats = store.cats[s] ?? [];
            final catName = widget.query.isNotEmpty
                ? '"${widget.query}" için sonuçlar'
                : cat == null
                    ? 'Tüm ${s.title.toLowerCase()}'
                    : cat == '★'
                        ? 'Favoriler'
                        : cats.firstWhere((c) => c.id == cat, orElse: () => Cat('', s.title)).name;
            return Row(children: [
              SizedBox(
                width: 250,
                child: CategoryList(
                  cats: cats,
                  counts: counts,
                  selected: widget.query.isNotEmpty ? '' : cat,
                  total: all.length,
                  favCount: all.where(store.isFav).length,
                  onSelect: (id) {
                    setState(() => cat = _vodCat[s] = id);
                    if (scroll.hasClients) scroll.jumpTo(0);
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 16, 8),
                    child: Row(children: [
                      Expanded(
                        child: Text(catName,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
                      Text('${list.length} içerik', style: const TextStyle(color: kDim)),
                      const SizedBox(width: 12),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: sort,
                          dropdownColor: kCard,
                          borderRadius: BorderRadius.circular(12),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Sunucu sırası')),
                            DropdownMenuItem(value: 1, child: Text('En yeni eklenen')),
                            DropdownMenuItem(value: 2, child: Text('A → Z')),
                            DropdownMenuItem(value: 3, child: Text('En yüksek puan')),
                            DropdownMenuItem(value: 4, child: Text('Yıla göre')),
                          ],
                          onChanged: (v) => setState(() => sort = _vodSort[s] = v ?? 0),
                        ),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? const EmptyView('İçerik bulunamadı')
                        : Scrollbar(
                            controller: scroll,
                            child: GridView.builder(
                              controller: scroll,
                              padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 178,
                                childAspectRatio: 0.56,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 18,
                              ),
                              itemCount: list.length,
                              itemBuilder: (_, i) => PosterCard(
                                item: list[i],
                                onTap: () {
                                  if (s == Section.series) {
                                    setState(() => _openSeries[s] = list[i]);
                                  } else {
                                    showMovieDetail(context, list[i]);
                                  }
                                },
                              ),
                            ),
                          ),
                  ),
                ]),
              ),
            ]);
          },
        );
      },
    );
  }
}

class PosterCard extends StatefulWidget {
  final Item item;
  final VoidCallback onTap;
  const PosterCard({super.key, required this.item, required this.onTap});
  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final prog = store.progressOf(it.key);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AnimatedScale(
              scale: hover ? 1.04 : 1,
              duration: const Duration(milliseconds: 160),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: hover ? [BoxShadow(color: kFire.withValues(alpha: .35), blurRadius: 18)] : null,
                  border: Border.all(color: hover ? kFire : kLine, width: hover ? 1.6 : 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(fit: StackFit.expand, children: [
                    NetImage(it.image, label: it.name),
                    if (it.rating > 0)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: .7), borderRadius: BorderRadius.circular(6)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.star_rounded, size: 12, color: kGold),
                            const SizedBox(width: 2),
                            Text((it.rating * 2).toStringAsFixed(1),
                                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    if (store.isFav(it))
                      const Positioned(top: 6, right: 6, child: Icon(Icons.star_rounded, color: kGold, size: 22)),
                    if (prog > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(value: prog, minHeight: 4, color: kFire, backgroundColor: Colors.black54),
                      ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25)),
          if (it.year.isNotEmpty) Text(it.year, style: const TextStyle(fontSize: 11.5, color: kDim)),
        ]),
      ),
    );
  }
}

// ============================ Film ayrıntısı ============================
Future<void> showMovieDetail(BuildContext context, Item m) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: kSurface,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820, maxHeight: 560), child: _MovieDetail(m)),
    ),
  );
}

class _MovieDetail extends StatelessWidget {
  final Item m;
  const _MovieDetail(this.m);

  Future<void> _play(BuildContext context, {required bool resume}) async {
    Navigator.of(context).pop();
    windowCtl.openPlayer();
    await playback.playMovie(m, resume: resume);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: store.api!.vodInfo(m.id),
      builder: (context, snap) {
        final info = (snap.data?['info'] is Map ? snap.data!['info'] as Map : const {}).cast<String, dynamic>();
        String f(String k) => info[k] == null ? '' : '${info[k]}';
        final backdrop = (info['backdrop_path'] is List && (info['backdrop_path'] as List).isNotEmpty)
            ? '${(info['backdrop_path'] as List).first}'
            : '';
        final resume = store.resumeOf(m.key);
        return Stack(children: [
          if (backdrop.isNotEmpty)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Opacity(opacity: .22, child: NetImage(backdrop)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(26),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 230,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(borderRadius: BorderRadius.circular(16), child: NetImage(m.image, label: m.name)),
                ),
              ),
              const SizedBox(width: 26),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(m.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2))),
                    FavButton(m, size: 26),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: kDim)),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 10, runSpacing: 6, children: [
                    for (final t in [
                      if (m.year.isNotEmpty) m.year,
                      if (f('duration').isNotEmpty) f('duration'),
                      if (f('genre').isNotEmpty) f('genre'),
                      if (m.rating > 0) '★ ${(m.rating * 2).toStringAsFixed(1)}',
                    ])
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
                        child: Text(t, style: const TextStyle(fontSize: 12.5)),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (snap.connectionState != ConnectionState.done)
                          const Text('Bilgiler yükleniyor…', style: TextStyle(color: kDim))
                        else
                          Text(f('plot').isEmpty ? (f('description').isEmpty ? 'Açıklama yok.' : f('description')) : f('plot'),
                              style: const TextStyle(height: 1.55, color: Color(0xFFD6D4E0))),
                        if (f('director').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('Yönetmen: ${f('director')}', style: const TextStyle(color: kDim, fontSize: 13)),
                        ],
                        if (f('cast').isNotEmpty || f('actors').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Oyuncular: ${f('cast').isNotEmpty ? f('cast') : f('actors')}',
                              style: const TextStyle(color: kDim, fontSize: 13)),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    DecoratedBox(
                      decoration: BoxDecoration(gradient: kFireGradient, borderRadius: BorderRadius.circular(12)),
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
                        onPressed: () => _play(context, resume: true),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(resume == null ? 'İzle' : 'Devam et (${fmtDur(resume)})',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    if (resume != null) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
                        onPressed: () => _play(context, resume: false),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Baştan başla'),
                      ),
                    ],
                  ]),
                ]),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}

// ============================ Dizi ayrıntısı ============================
class SeriesDetail extends StatefulWidget {
  final Item series;
  final VoidCallback onBack;
  const SeriesDetail({super.key, required this.series, required this.onBack});
  @override
  State<SeriesDetail> createState() => _SeriesDetailState();
}

final _seriesCache = <String, SeriesInfo>{};
final _seasonSel = <String, int>{};

class _SeriesDetailState extends State<SeriesDetail> {
  late Future<SeriesInfo> info;

  @override
  void initState() {
    super.initState();
    final c = _seriesCache[widget.series.id];
    info = c != null ? Future.value(c) : store.api!.seriesInfo(widget.series.id).then((v) => _seriesCache[widget.series.id] = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.series;
    return FutureBuilder<SeriesInfo>(
      future: info,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView('Dizi bilgisi alınamadı.\n${snap.error}', () => setState(() {
                info = store.api!.seriesInfo(s.id);
              }));
        }
        if (!snap.hasData) return const LoadingView('Bölümler yükleniyor…');
        final d = snap.data!;
        final seasons = d.seasons.keys.toList()..sort();
        var season = _seasonSel[s.id] ?? (seasons.isEmpty ? 1 : seasons.first);
        if (!seasons.contains(season) && seasons.isNotEmpty) season = seasons.first;
        final eps = d.seasons[season] ?? const <Episode>[];
        return ListenableBuilder(
          listenable: store,
          builder: (context, _) => CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Stack(children: [
                Positioned.fill(child: Opacity(opacity: .18, child: NetImage(d.cover.isNotEmpty ? d.cover : s.image))),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [kBg.withValues(alpha: .3), kBg], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 24, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextButton.icon(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Dizilere dön'),
                    ),
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 170,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(borderRadius: BorderRadius.circular(14), child: NetImage(s.image, label: s.name)),
                        ),
                      ),
                      const SizedBox(width: 22),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(s.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
                            FavButton(s, size: 26),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                              [if (d.year.isNotEmpty) d.year, if (d.genre.isNotEmpty) d.genre, '${seasons.length} sezon']
                                  .join(' · '),
                              style: const TextStyle(color: kDim)),
                          const SizedBox(height: 10),
                          Text(d.plot.isEmpty ? 'Açıklama yok.' : d.plot,
                              maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5, color: Color(0xFFD6D4E0))),
                          if (d.cast.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('Oyuncular: ${d.cast}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kDim, fontSize: 13)),
                          ],
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final n in seasons)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('$n. Sezon'),
                              selected: n == season,
                              selectedColor: kFire,
                              labelStyle: TextStyle(color: n == season ? Colors.white : kText, fontWeight: FontWeight.w600),
                              onSelected: (_) => setState(() => _seasonSel[s.id] = n),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 24, 30),
              sliver: SliverList.builder(
                itemCount: eps.length,
                itemBuilder: (context, i) => _EpisodeTile(series: s, ep: eps[i]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final Item series;
  final Episode ep;
  const _EpisodeTile({required this.series, required this.ep});

  @override
  Widget build(BuildContext context) {
    final key = 'ep:${ep.id}';
    final prog = store.progressOf(key);
    final resume = store.resumeOf(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            windowCtl.openPlayer();
            await playback.playEpisode(series, ep);
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              SizedBox(
                width: 170,
                height: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(fit: StackFit.expand, children: [
                    NetImage(ep.image.isNotEmpty ? ep.image : series.image, icon: Icons.play_circle_rounded),
                    const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 38)),
                    if (prog > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(value: prog, minHeight: 4, color: kFire, backgroundColor: Colors.black54),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${ep.number}. Bölüm${ep.title.isNotEmpty && !ep.title.contains(series.name) ? ' · ${ep.title}' : ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(ep.plot.isEmpty ? (ep.durationSecs > 0 ? '${(ep.durationSecs / 60).round()} dk' : '') : ep.plot,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kDim, fontSize: 13, height: 1.4)),
                  if (resume != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Kaldığın yer: ${fmtDur(resume)}', style: const TextStyle(color: kFire, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: kDim),
            ]),
          ),
        ),
      ),
    );
  }
}
