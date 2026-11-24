import 'package:flutter/material.dart';
import 'api.dart';
import 'player.dart';
import 'store.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    if (store.account == null) store.refreshAccount();
  }

  Widget _card(String title, IconData icon, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18), border: Border.all(color: kLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: kFire),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _row(String label, String help, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (help.isNotEmpty) Text(help, style: const TextStyle(color: kDim, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 16),
          control,
        ]),
      );

  Widget _seg<T>(T value, List<(T, String)> opts, ValueChanged<T> onChanged) => SegmentedButton<T>(
        segments: [for (final o in opts) ButtonSegment<T>(value: o.$1, label: Text(o.$2))],
        selected: {value},
        showSelectedIcon: false,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kFire : kCard),
          foregroundColor: WidgetStateProperty.all(kText),
        ),
        onSelectionChanged: (s) => onChanged(s.first),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final a = store.account;
        return ListView(padding: const EdgeInsets.fromLTRB(28, 22, 28, 40), children: [
          const Text('Ayarlar', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          _card('Hesap', Icons.account_circle_rounded, [
            _row('Sunucu', store.server, const SizedBox()),
            _row('Kullanıcı', store.user, const SizedBox()),
            if (a != null) ...[
              _row('Durum', a.status, const SizedBox()),
              _row('Abonelik bitişi', a.expires == null ? 'Süresiz' : '${a.expires!.day}.${a.expires!.month}.${a.expires!.year}',
                  const SizedBox()),
              _row('Bağlantı', '${a.activeConnections} / ${a.maxConnections} aktif bağlantı', const SizedBox()),
            ],
            const SizedBox(height: 6),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () {
                  for (final s in Section.values) {
                    store.load(s, force: true).catchError((_) {});
                  }
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listeler yenileniyor…')));
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Listeleri yenile'),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: kEmber),
                onPressed: () async {
                  await playback.stop();
                  store.logout();
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Çıkış yap'),
              ),
            ]),
          ]),
          _card('Yayın ve donma önleme', Icons.speed_rounded, [
            _row('Önbellek (tampon)', 'Yayın donuyorsa büyüt. Büyük önbellek daha akıcıdır ama kanal açılışı 1–2 sn uzayabilir.',
                _seg<int>(store.bufferLevel, const [(0, 'Normal'), (1, 'Büyük'), (2, 'Çok büyük')], (v) {
              store.bufferLevel = v;
              store.saveConfig();
            })),
            _row('Canlı yayın biçimi', 'Bir kanal açılmıyor ya da donuyorsa diğerini dene.',
                _seg<String>(store.liveFormat, const [('ts', 'MPEG-TS'), ('m3u8', 'HLS')], (v) {
              store.liveFormat = v;
              store.saveConfig();
            })),
            _row('Donanım hızlandırma', 'Ekran kartıyla çözme; işlemciyi rahatlatır. Görüntü bozulursa kapat (yeniden başlatınca geçerli).',
                Switch(
                  value: store.hwdec,
                  activeThumbColor: kFire,
                  onChanged: (v) {
                    store.hwdec = v;
                    store.saveConfig();
                  },
                )),
          ]),
          _card('Altyazı ve ses', Icons.subtitles_rounded, [
            _row('Tercih edilen altyazı dili', 'Varsa otomatik seçilir.',
                _seg<String>(store.subLang, const [('tur', 'Türkçe'), ('eng', 'İngilizce'), ('no', 'Kapalı')], (v) {
              store.subLang = v;
              store.saveConfig();
            })),
            _row('Tercih edilen ses dili', 'Birden fazla dublaj varsa.',
                _seg<String>(store.audioLang, const [('', 'Varsayılan'), ('tur', 'Türkçe'), ('eng', 'Orijinal / İng.')], (v) {
              store.audioLang = v;
              store.saveConfig();
            })),
            _row('Altyazı boyutu', '${store.subSize.round()}',
                SizedBox(
                  width: 240,
                  child: Slider(
                    value: store.subSize,
                    min: 24,
                    max: 72,
                    onChanged: (v) => setState(() => store.subSize = v),
                    onChangeEnd: (_) => store.saveConfig(),
                  ),
                )),
          ]),
          _card('Kısayollar', Icons.keyboard_rounded, const [
            Text('Boşluk: oynat/duraklat · ← →: 10 sn geri/ileri · ↑ ↓: ses · M: sessiz\n'
                'F veya Enter: tam ekran · Esc: tam ekrandan / mini oynatıcıdan çık\n'
                'PgUp / PgDn (ya da Ctrl + ↑ ↓): önceki / sonraki kanal · Çift tık: büyüt',
                style: TextStyle(color: kDim, height: 1.7)),
          ]),
          const Center(child: Text('Quetzalov 1.0', style: TextStyle(color: kDim, fontSize: 12))),
        ]);
      },
    );
  }
}
