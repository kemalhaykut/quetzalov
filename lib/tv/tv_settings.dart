import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../player.dart';
import '../store.dart';
import '../theme.dart';
import 'tv_widgets.dart';

class TvSettings extends StatefulWidget {
  const TvSettings({super.key});
  @override
  State<TvSettings> createState() => _TvSettingsState();
}

class _TvSettingsState extends State<TvSettings> {
  String msg = '';

  @override
  void initState() {
    super.initState();
    if (store.account == null) store.refreshAccount();
  }

  /// OK / ◀ ▶ ile değerler arasında gezilen ayar satırı.
  Widget _choice<T>(String title, String hint, T value, List<(T, String)> opts, void Function(T) set) {
    final i = opts.indexWhere((o) => o.$1 == value);
    void step(int d) {
      final n = ((i < 0 ? 0 : i) + d) % opts.length;
      set(opts[(n + opts.length) % opts.length].$1);
      store.saveConfig();
      setState(() {});
    }

    return TvRow(
      onTap: () => step(1),
      onKey: (e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
          step(1);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowLeft && i > 0) {
          step(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14)),
                Text(
                  hint,
                  style: const TextStyle(color: kDim, fontSize: 11.5, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.chevron_left_rounded, color: kDim),
          Container(
            constraints: const BoxConstraints(minWidth: 110),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(gradient: kFireGradient, borderRadius: BorderRadius.circular(16)),
            child: Text(i < 0 ? '—' : opts[i].$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const Icon(Icons.chevron_right_rounded, color: kDim),
        ],
      ),
    );
  }

  Widget _info(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
    child: Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(k, style: const TextStyle(color: kDim, fontSize: 13)),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final a = store.account;
        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
          children: [
            const TvTitle('Ayarlar'),
            const SizedBox(height: 6),
            _info('Sunucu', store.server),
            _info('Kullanıcı', store.user),
            if (a != null) ...[
              _info('Durum', a.status),
              _info('Abonelik bitişi', a.expires == null ? 'Süresiz' : '${a.expires!.day}.${a.expires!.month}.${a.expires!.year}'),
              _info('Bağlantı', '${a.activeConnections} / ${a.maxConnections} aktif'),
            ],
            const SizedBox(height: 16),
            const Text(
              'YAYIN',
              style: TextStyle(color: kDim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            _choice<int>('Önbellek (donma önleme)', 'Yayın donuyorsa büyüt.', store.bufferLevel, const [
              (0, 'Normal'),
              (1, 'Büyük'),
              (2, 'Çok büyük'),
            ], (v) => store.bufferLevel = v),
            _choice<String>('Canlı yayın biçimi', 'Kanal açılmıyorsa diğerini dene.', store.liveFormat, const [
              ('ts', 'MPEG-TS'),
              ('m3u8', 'HLS'),
            ], (v) => store.liveFormat = v),
            _choice<bool>('Donanım hızlandırma', 'Görüntü bozulursa kapat, uygulamayı yeniden aç.', store.hwdec, const [
              (true, 'Açık'),
              (false, 'Kapalı'),
            ], (v) => store.hwdec = v),
            const SizedBox(height: 14),
            const Text(
              'ALTYAZI VE SES',
              style: TextStyle(color: kDim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            _choice<String>('Altyazı dili', 'Varsa otomatik seçilir.', store.subLang, const [
              ('tur', 'Türkçe'),
              ('eng', 'İngilizce'),
              ('no', 'Kapalı'),
            ], (v) => store.subLang = v),
            _choice<String>('Ses dili', 'Birden fazla dublaj varsa.', store.audioLang, const [
              ('', 'Varsayılan'),
              ('tur', 'Türkçe'),
              ('eng', 'Orijinal'),
            ], (v) => store.audioLang = v),
            _choice<double>('Altyazı boyutu', 'Televizyonda okunabilirlik için.', store.subSize, const [
              (36.0, 'Küçük'),
              (44.0, 'Orta'),
              (54.0, 'Büyük'),
              (66.0, 'Çok büyük'),
            ], (v) => store.subSize = v),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                TvButton('Listeleri yenile', Icons.refresh_rounded, () {
                  for (final s in Section.values) {
                    store.load(s, force: true).catchError((_) {});
                  }
                  setState(() => msg = 'Listeler yenileniyor…');
                }),
                TvButton('Çıkış yap', Icons.logout_rounded, () async {
                  await playback.stop();
                  store.logout();
                }),
              ],
            ),
            if (msg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(msg, style: const TextStyle(color: kGold)),
              ),
            const SizedBox(height: 20),
            const Text('Kumanda: OK seç · ◀ ▶ değer değiştir · Geri: önceki ekran', style: TextStyle(color: kDim, fontSize: 12)),
            const SizedBox(height: 6),
            const Text('Quetzalov TV 1.0', style: TextStyle(color: kDim, fontSize: 12)),
          ],
        );
      },
    );
  }
}
