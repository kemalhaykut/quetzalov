import 'package:flutter/material.dart';
import 'api.dart';
import 'player.dart';
import 'shell.dart' show shellGoTo;
import 'store.dart';
import 'theme.dart';
import 'vod_page.dart';
import 'widgets.dart';
import 'window_ctl.dart';

/// Favoriler + izlemeye devam et
class FavoritesPage extends StatelessWidget {
  final String query;
  const FavoritesPage({super.key, required this.query});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = norm(query.trim());
        bool m(Item it) => q.isEmpty || norm(it.name).contains(q);
        final favs = store.favorites.values.where(m).toList();
        final live = favs.where((x) => x.section == Section.live).toList();
        final movies = favs.where((x) => x.section == Section.movies).toList();
        final series = favs.where((x) => x.section == Section.series).toList();
        final cont = store.continueWatching
            .where((c) => m(Item.fromStore((c['item'] as Map).cast<String, dynamic>())))
            .toList();
        if (favs.isEmpty && cont.isEmpty) {
          return const EmptyView('Henüz favori yok.\nKanal, film ya da dizilerde ☆ simgesine tıkla.', icon: Icons.star_outline_rounded);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(24, 18, 24, 40), children: [
          if (cont.isNotEmpty) ...[
            const _H('İzlemeye devam et', Icons.history_rounded),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cont.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _ContinueCard(cont[i]),
              ),
            ),
            const SizedBox(height: 26),
          ],
          if (live.isNotEmpty) ...[
            const _H('Favori kanallar', Icons.live_tv_rounded),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final ch in live)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    windowCtl.openPlayer();
                    await playback.playLive(ch, list: live);
                  },
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
                    child: Row(children: [
                      SizedBox(width: 50, height: 36, child: NetImage(ch.image, fit: BoxFit.contain, icon: Icons.live_tv_rounded)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(ch.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      FavButton(ch, size: 18),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 26),
          ],
          for (final (title, icon, list) in [
            ('Favori filmler', Icons.movie_rounded, movies),
            ('Favori diziler', Icons.video_library_rounded, series)
          ])
            if (list.isNotEmpty) ...[
              _H(title, icon),
              Wrap(spacing: 16, runSpacing: 18, children: [
                for (final it in list)
                  SizedBox(
                    width: 160,
                    height: 290,
                    child: PosterCard(
                      item: it,
                      onTap: () {
                        if (it.section == Section.movies) {
                          showMovieDetail(context, it);
                        } else {
                          openSeriesLater(it);
                          shellGoTo?.call(2);
                        }
                      },
                    ),
                  ),
              ]),
              const SizedBox(height: 26),
            ],
        ]);
      },
    );
  }
}

class _H extends StatelessWidget {
  final String t;
  final IconData icon;
  const _H(this.t, this.icon);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(icon, color: kFire, size: 22),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _ContinueCard extends StatelessWidget {
  final Map<String, dynamic> c;
  const _ContinueCard(this.c);

  @override
  Widget build(BuildContext context) {
    final it = Item.fromStore((c['item'] as Map).cast<String, dynamic>());
    final ep = c['ep'] is Map ? (c['ep'] as Map).cast<String, dynamic>() : null;
    final pos = (c['pos'] as num?)?.toDouble() ?? 0, dur = (c['dur'] as num?)?.toDouble() ?? 1;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        windowCtl.openPlayer();
        if (ep != null) {
          await playback.playEpisode(
              it,
              Episode('${ep['id']}', (ep['s'] as num?)?.toInt() ?? 1, (ep['n'] as num?)?.toInt() ?? 1, '${ep['t'] ?? ''}',
                  '${ep['e'] ?? ''}', '', '', 0));
        } else {
          await playback.playMovie(it);
        }
      },
      child: SizedBox(
        width: 250,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(fit: StackFit.expand, children: [
            NetImage(it.image, label: it.name),
            const DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.transparent, Color(0xEE000000)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (ep != null) Text('${ep['s']}. Sezon ${ep['n']}. Bölüm', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(value: (pos / dur).clamp(0, 1), minHeight: 4, color: kFire, backgroundColor: Colors.black54),
            ),
            const Center(child: Icon(Icons.play_circle_fill_rounded, size: 44, color: Colors.white70)),
          ]),
        ),
      ),
    );
  }
}
