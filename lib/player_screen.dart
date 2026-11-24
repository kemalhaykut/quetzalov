import 'package:flutter/material.dart';
import 'api.dart';
import 'player.dart';
import 'store.dart';
import 'theme.dart';
import 'title_bar.dart';
import 'widgets.dart';
import 'window_ctl.dart';

/// Pencereyi kaplayan oynatıcı (normal / tam ekran / mini). Canlıda yan kanal listesi açılabilir.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool channels = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([windowCtl, playback]),
      builder: (context, _) {
        final mode = windowCtl.mode;
        final bare = mode == ViewMode.fullscreen || mode == ViewMode.mini;
        final showList = channels && playback.isLive && mode != ViewMode.mini && playback.liveList.isNotEmpty;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Column(children: [
            if (!bare) const TitleBar(),
            Expanded(
              child: Row(children: [
                Expanded(
                  child: Stack(children: [
                    const Positioned.fill(child: PlayerSurface()),
                    if (playback.isLive && mode != ViewMode.mini)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                          onPressed: () => setState(() => channels = !channels),
                          icon: Icon(channels ? Icons.close_rounded : Icons.list_rounded),
                          label: const Text('Kanallar'),
                        ),
                      ),
                  ]),
                ),
                if (showList) SizedBox(width: 320, child: _SideChannels(onPick: (_) {})),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _SideChannels extends StatefulWidget {
  final ValueChanged<Item> onPick;
  const _SideChannels({required this.onPick});
  @override
  State<_SideChannels> createState() => _SideChannelsState();
}

class _SideChannelsState extends State<_SideChannels> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final all = playback.liveList;
    final list = q.isEmpty ? all : all.where((x) => norm(x.name).contains(norm(q))).toList();
    return Container(
      color: kSurface,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: const InputDecoration(isDense: true, hintText: 'Kanal ara…', prefixIcon: Icon(Icons.search_rounded, size: 18)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemExtent: 54,
            itemBuilder: (_, i) {
              final it = list[i];
              final on = playback.item?.key == it.key;
              return InkWell(
                onTap: () => playback.playLive(it),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: on ? kFire.withValues(alpha: .16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    SizedBox(width: 46, height: 32, child: NetImage(it.image, fit: BoxFit.contain, icon: Icons.live_tv_rounded)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                    if (store.isFav(it)) const Icon(Icons.star_rounded, size: 16, color: kGold),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
