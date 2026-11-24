import 'package:flutter/material.dart';
import 'api.dart';
import 'favorites_page.dart';
import 'live_page.dart';
import 'player.dart';
import 'settings_page.dart';
import 'store.dart';
import 'theme.dart';
import 'title_bar.dart';
import 'vod_page.dart';

/// Ana çerçeve: başlık çubuğu + arama + sol menü + içerik.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

/// Başka sayfalardan sekme değiştirmek için.
void Function(int)? shellGoTo;

int _lastTab = 0; // oynatıcıdan dönünce aynı sekme açılsın
final _queries = <int, String>{};

class _ShellState extends State<Shell> {
  int tab = _lastTab;
  late final search = TextEditingController(text: _queries[tab] ?? '');

  static const tabs = [
    (Icons.live_tv_rounded, 'Canlı TV'),
    (Icons.movie_rounded, 'Filmler'),
    (Icons.video_library_rounded, 'Diziler'),
    (Icons.star_rounded, 'Favoriler'),
    (Icons.settings_rounded, 'Ayarlar'),
  ];

  @override
  void initState() {
    super.initState();
    shellGoTo = _go;
  }

  @override
  void dispose() {
    if (shellGoTo == _go) shellGoTo = null;
    search.dispose();
    super.dispose();
  }

  void _go(int i) {
    // Canlı TV'den başka sekmeye geçince önizleme sesi arkada çalmasın
    if (tab == 0 && i != 0 && playback.isLive) playback.stop();
    _queries[tab] = search.text;
    setState(() {
      tab = i;
      _lastTab = i;
      search.text = _queries[i] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = search.text;
    return Scaffold(
      body: Column(children: [
        TitleBar(
          center: tab == 4
              ? null
              : SizedBox(
                  width: 420,
                  height: 34,
                  child: TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      hintText: 'Ara: ${tabs[tab].$2.toLowerCase()} içinde…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              iconSize: 16,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(search.clear),
                            ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kLine)),
                      enabledBorder:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kLine)),
                    ),
                  ),
                ),
        ),
        Expanded(
          child: Row(children: [
            _NavRail(index: tab, onTap: _go),
            const VerticalDivider(width: 1),
            Expanded(
              child: switch (tab) {
                0 => LivePage(query: q),
                1 => VodPage(key: const ValueKey('movies'), section: Section.movies, query: q),
                2 => VodPage(key: const ValueKey('series'), section: Section.series, query: q),
                3 => FavoritesPage(query: q),
                _ => const SettingsPage(),
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

class _NavRail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _NavRail({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      color: kSurface,
      child: Column(children: [
        const SizedBox(height: 10),
        for (var i = 0; i < _ShellState.tabs.length; i++) ...[
          if (i == 4) const Spacer(),
          _NavItem(icon: _ShellState.tabs[i].$1, label: _ShellState.tabs[i].$2, on: index == i, onTap: () => onTap(i)),
        ],
        ListenableBuilder(
          listenable: store,
          builder: (_, __) {
            final exp = store.account?.expires;
            if (exp == null) return const SizedBox(height: 12);
            final days = exp.difference(DateTime.now()).inDays;
            return Tooltip(
              message: 'Abonelik bitişi: ${exp.day}.${exp.month}.${exp.year}',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 14),
                child: Text('$days gün',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: days < 7 ? kEmber : kDim, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            );
          },
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: on ? kFireGradient : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Icon(icon, color: on ? Colors.white : kDim, size: 24),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : kDim)),
          ]),
        ),
      ),
    );
  }
}
