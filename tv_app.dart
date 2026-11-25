import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../store.dart';
import '../theme.dart';
import 'tv_live.dart';
import 'tv_settings.dart';
import 'tv_vod.dart';
import 'tv_widgets.dart';

/// Android TV / Mi Box arayüzü (kumanda ile).
class TvApp extends StatelessWidget {
  const TvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent()},
      child: MaterialApp(
        title: 'Quetzalov',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ListenableBuilder(
          listenable: store,
          builder: (context, _) => (!store.hasAccount || store.api == null) ? const TvLogin() : const TvHome(),
        ),
      ),
    );
  }
}

// ============================ Giriş ============================
class TvLogin extends StatefulWidget {
  const TvLogin({super.key});
  @override
  State<TvLogin> createState() => _TvLoginState();
}

class _TvLoginState extends State<TvLogin> {
  final server = TextEditingController(text: store.server);
  final user = TextEditingController(text: store.user);
  final pass = TextEditingController();
  bool busy = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    server.addListener(() {
      final p = XtreamApi.parseFullLink(server.text);
      if (p != null) {
        server.text = p.server;
        user.text = p.user;
        pass.text = p.pass;
      }
    });
  }

  Future<void> _login() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await store.login(server.text, user.text.trim(), pass.text.trim());
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, IconData icon, {bool secret = false, bool auto = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TvTextField(
      child: TextField(
        controller: c,
        autofocus: auto,
        obscureText: secret,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), isDense: true),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0.6, -0.8), radius: 1.4, colors: [Color(0xFF3A1A10), kBg]),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/icon.png', width: 56, height: 56)),
                      const SizedBox(width: 12),
                      ShaderMask(
                        shaderCallback: (r) => kFireGradient.createShader(r),
                        child: const Text(
                          'Quetzalov',
                          style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _field(server, 'Sunucu adresi (http://…:8080)', Icons.dns_rounded, auto: true),
                  _field(user, 'Kullanıcı adı', Icons.person_rounded),
                  _field(pass, 'Şifre', Icons.lock_rounded, secret: true),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(error, style: const TextStyle(color: Color(0xFFFFB4A8))),
                    ),
                  const SizedBox(height: 6),
                  Center(
                    child: busy
                        ? const CircularProgressIndicator(color: kFire)
                        : TvButton('Giriş yap', Icons.login_rounded, _login, primary: true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================ Ana ekran ============================
class TvHome extends StatefulWidget {
  const TvHome({super.key});
  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  int tab = 0;
  static const items = [
    (Icons.live_tv_rounded, 'Canlı TV'),
    (Icons.movie_rounded, 'Filmler'),
    (Icons.video_library_rounded, 'Diziler'),
    (Icons.star_rounded, 'Favoriler'),
    (Icons.search_rounded, 'Ara'),
    (Icons.settings_rounded, 'Ayarlar'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          FocusTraversalGroup(
            child: Container(
              width: 84,
              color: kSurface,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/icon.png', width: 40, height: 40)),
                  const SizedBox(height: 14),
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: TvFocus(
                        autofocus: i == 0,
                        radius: 12,
                        scale: 1.0,
                        onFocus: (f) {
                          if (f && tab != i) setState(() => tab = i);
                        },
                        onTap: () => setState(() => tab = i),
                        builder: (_, f) => Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(gradient: tab == i ? kFireGradient : null, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              Icon(items[i].$1, color: tab == i || f ? Colors.white : kDim, size: 22),
                              const SizedBox(height: 2),
                              Text(
                                items[i].$2,
                                style: TextStyle(fontSize: 10.5, color: tab == i || f ? Colors.white : kDim, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FocusTraversalGroup(
              child: switch (tab) {
                0 => const TvLive(),
                1 => const TvVod(key: ValueKey('m'), section: Section.movies),
                2 => const TvVod(key: ValueKey('s'), section: Section.series),
                3 => const TvFavorites(),
                4 => const TvSearch(),
                _ => const TvSettings(),
              },
            ),
          ),
        ],
      ),
    );
  }
}
