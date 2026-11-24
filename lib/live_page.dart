import 'package:flutter/material.dart';
import 'api.dart';
import 'player.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';
import 'window_ctl.dart';

String? _liveCat; // seçili kategori (sekme değişince hatırlansın)

/// Canlı TV: kategoriler | kanal listesi | önizleme oynatıcı + yayın akışı
class LivePage extends StatefulWidget {
  final String query;
  const LivePage({super.key, required this.query});
  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  String? cat = _liveCat;
  Future<void>? loading;

  @override
  void initState() {
    super.initState();
    loading = store.load(Section.live);
  }

  List<Item> _filtered() {
    final all = store.items[Section.live] ?? [];
    final q = norm(widget.query.trim());
    Iterable<Item> l = all;
    if (q.isNotEmpty) {
      l = l.where((x) => norm(x.name).contains(q));
    } else if (cat == '★') {
      l = l.where(store.isFav);
    } else if (cat != null) {
      l = l.where((x) => x.categoryId == cat);
    }
    return l.toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: loading,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView('Kanallar yüklenemedi.\n${snap.error}', () => setState(() => loading = store.load(Section.live, force: true)));
        }
        if (snap.connectionState != ConnectionState.done) return const LoadingView('Kanallar yükleniyor…');
        return ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final all = store.items[Section.live] ?? [];
            final counts = <String, int>{};
            for (final it in all) {
              counts[it.categoryId] = (counts[it.categoryId] ?? 0) + 1;
            }
            final list = _filtered();
            return LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth > 1050;
              return Row(children: [
                SizedBox(
                  width: wide ? 250 : 200,
                  child: CategoryList(
                    cats: store.cats[Section.live] ?? [],
                    counts: counts,
                    selected: widget.query.isNotEmpty ? '' : cat,
                    total: all.length,
                    favCount: all.where(store.isFav).length,
                    onSelect: (id) => setState(() => cat = _liveCat = id),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(width: wide ? 360 : 300, child: _ChannelList(list: list)),
                const VerticalDivider(width: 1),
                const Expanded(child: _PreviewPanel()),
              ]);
            });
          },
        );
      },
    );
  }
}

class _ChannelList extends StatelessWidget {
  final List<Item> list;
  const _ChannelList({required this.list});

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) return const EmptyView('Kanal bulunamadı');
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) => Scrollbar(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: list.length,
          itemExtent: 58,
          itemBuilder: (context, i) {
            final it = list[i];
            final on = playback.item?.key == it.key;
            return InkWell(
              onTap: () => playback.playLive(it, list: list),
              onDoubleTap: () async {
                if (!on) await playback.playLive(it, list: list);
                windowCtl.openPlayer();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: on ? kFire.withValues(alpha: .14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: on ? Border.all(color: kFire.withValues(alpha: .5)) : null,
                ),
                child: Row(children: [
                  SizedBox(
                    width: 30,
                    child: Text('${i + 1}',
                        style: const TextStyle(color: kDim, fontSize: 11.5, fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                  Container(
                    width: 54,
                    height: 40,
                    decoration: BoxDecoration(color: const Color(0xFF1F1D2A), borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.all(4),
                    child: NetImage(it.image, fit: BoxFit.contain, icon: Icons.live_tv_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(it.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, height: 1.25)),
                  ),
                  if (on)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.graphic_eq_rounded, color: kFire, size: 18),
                    ),
                  FavButton(it, size: 19),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final it = playback.isLive ? playback.item : null;
        return ListView(padding: const EdgeInsets.all(18), children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: it == null
                  ? Container(
                      color: const Color(0xFF07070A),
                      alignment: Alignment.center,
                      child: const Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.live_tv_rounded, color: kDim, size: 46),
                        SizedBox(height: 10),
                        Text('İzlemek için soldan bir kanal seç', style: TextStyle(color: kDim)),
                        SizedBox(height: 4),
                        Text('Çift tıkla: büyük ekran', style: TextStyle(color: kDim, fontSize: 12)),
                      ]),
                    )
                  : const PlayerSurface(compact: true),
            ),
          ),
          if (it != null) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Text(it.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              FavButton(it),
              const SizedBox(width: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kFire, foregroundColor: Colors.white),
                onPressed: windowCtl.openPlayer,
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: const Text('Büyük ekran'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: windowCtl.enterMini,
                icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 18),
                label: const Text('Mini'),
              ),
            ]),
            const SizedBox(height: 14),
            _Epg(key: ValueKey(it.id), item: it),
          ],
        ]);
      },
    );
  }
}

class _Epg extends StatelessWidget {
  final Item item;
  const _Epg({super.key, required this.item});

  String _t(DateTime? d) => d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EpgEntry>>(
      future: store.api!.shortEpg(item.id),
      builder: (context, snap) {
        final list = snap.data ?? const <EpgEntry>[];
        if (snap.connectionState != ConnectionState.done) {
          return const Text('Yayın akışı yükleniyor…', style: TextStyle(color: kDim));
        }
        if (list.isEmpty) return const Text('Bu kanal için yayın akışı yok.', style: TextStyle(color: kDim));
        final now = DateTime.now();
        // başlığı kontrollerde de göster
        final cur = list.where((e) => e.start != null && e.end != null && !now.isBefore(e.start!) && now.isBefore(e.end!));
        if (cur.isNotEmpty && playback.subtitle != cur.first.title) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            playback.subtitle = cur.first.title;
          });
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final e in list)
            Builder(builder: (_) {
              final live = e.start != null && e.end != null && !now.isBefore(e.start!) && now.isBefore(e.end!);
              final frac = live
                  ? now.difference(e.start!).inSeconds / e.end!.difference(e.start!).inSeconds.clamp(1, 1 << 30)
                  : 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: live ? kCard : kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: live ? kFire.withValues(alpha: .5) : kLine),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${_t(e.start)} – ${_t(e.end)}', style: const TextStyle(color: kDim, fontSize: 12)),
                    const SizedBox(width: 8),
                    if (live)
                      const Text('ŞİMDİ', style: TextStyle(color: kFire, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ]),
                  const SizedBox(height: 2),
                  Text(e.title, style: TextStyle(fontWeight: live ? FontWeight.w700 : FontWeight.w500)),
                  if (live && e.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(e.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kDim, fontSize: 12.5)),
                  ],
                  if (live) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: frac.clamp(0, 1), minHeight: 4, color: kFire, backgroundColor: kLine),
                    ),
                  ],
                ]),
              );
            }),
        ]);
      },
    );
  }
}
