import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../player.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'tv_player.dart';
import 'tv_widgets.dart';

String? _tvLiveCat;

/// Canlı TV: kategoriler | kanallar | seçili kanal bilgisi
class TvLive extends StatefulWidget {
  const TvLive({super.key});
  @override
  State<TvLive> createState() => _TvLiveState();
}

class _TvLiveState extends State<TvLive> {
  late Future<void> loading = store.load(Section.live);
  String? cat = _tvLiveCat;
  Item? focused;
  Timer? _deb;

  @override
  void dispose() {
    _deb?.cancel();
    super.dispose();
  }

  List<Item> _list() {
    final all = store.items[Section.live] ?? [];
    if (cat == '★') return all.where(store.isFav).toList();
    if (cat == null) return all;
    return all.where((x) => x.categoryId == cat).toList();
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
        final cats = store.cats[Section.live] ?? [];
        final list = _list();
        return Row(
          children: [
            SizedBox(
              width: 210,
              child: FocusTraversalGroup(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 14, 6, 20),
                  children: [
                    const TvTitle('Kategoriler'),
                    for (final (id, name) in [(null, 'Tümü'), ('★', '★ Favoriler'), for (final c in cats) (c.id, c.name)])
                      TvRow(
                        selected: cat == id,
                        onFocus: (f) {
                          if (f && cat != id) setState(() => cat = _tvLiveCat = id);
                        },
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 300,
              child: FocusTraversalGroup(
                child: list.isEmpty
                    ? const EmptyView('Bu kategoride kanal yok')
                    : ListView.builder(
                        key: ValueKey(cat),
                        padding: const EdgeInsets.fromLTRB(8, 14, 8, 20),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final it = list[i];
                          return TvRow(
                            onFocus: (f) {
                              if (!f) return;
                              _deb?.cancel();
                              _deb = Timer(const Duration(milliseconds: 350), () {
                                if (mounted) setState(() => focused = it);
                              });
                            },
                            onTap: () => openLive(context, it, list),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text('${i + 1}', style: const TextStyle(color: kDim, fontSize: 11)),
                                ),
                                SizedBox(
                                  width: 44,
                                  height: 30,
                                  child: NetImage(it.image, fit: BoxFit.contain, icon: Icons.live_tv_rounded),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    it.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5),
                                  ),
                                ),
                                if (store.isFav(it)) const Icon(Icons.star_rounded, color: kGold, size: 16),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: focused == null ? const _Hint() : _ChannelInfo(key: ValueKey(focused!.id), item: focused!),
            ),
          ],
        );
      },
    );
  }
}

Future<void> openLive(BuildContext context, Item it, List<Item> list) async {
  playback.liveList = list;
  await playback.playLive(it, list: list);
  await openNativePlayer();
}

class _Hint extends StatelessWidget {
  const _Hint();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Bir kanal seç ve OK tuşuna bas.\n\nİzlerken: ▲ ▼ kanal değiştir · ◀ kanal listesi · ▶ ses/altyazı · OK bilgi · Geri çıkış',
        textAlign: TextAlign.center,
        style: TextStyle(color: kDim, height: 1.6),
      ),
    ),
  );
}

class _ChannelInfo extends StatelessWidget {
  final Item item;
  const _ChannelInfo({super.key, required this.item});

  String _t(DateTime? d) => d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Container(
              width: 90,
              height: 60,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10)),
              child: NetImage(item.image, fit: BoxFit.contain, icon: Icons.live_tv_rounded),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FutureBuilder<List<EpgEntry>>(
          future: store.api!.shortEpg(item.id),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Text('Yayın akışı yükleniyor…', style: TextStyle(color: kDim));
            }
            final l = snap.data ?? const <EpgEntry>[];
            if (l.isEmpty) return const Text('Yayın akışı yok.', style: TextStyle(color: kDim));
            final now = DateTime.now();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in l)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kLine),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_t(e.start)} – ${_t(e.end)}${e.start != null && e.end != null && !now.isBefore(e.start!) && now.isBefore(e.end!) ? '   ŞİMDİ' : ''}',
                          style: const TextStyle(color: kFire, fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
