import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'login_page.dart';
import 'player.dart';
import 'player_screen.dart';
import 'shell.dart';
import 'store.dart';
import 'theme.dart';
import 'tv/tv_app.dart';
import 'window_ctl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android TV (Mi Box): kumandayla kullanılan ayrı arayüz
  if (Platform.isAndroid) {
    final d = await getApplicationSupportDirectory();
    await store.init(dataDir: d.path);
    playback.init();
    runApp(const TvApp());
    return;
  }
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await store.init();
  playback.init();
  startWindowDrag = windowManager.startDragging;

  const options = WindowOptions(
    size: Size(1320, 800),
    minimumSize: kMinWindow,
    center: true,
    title: 'Quetzalov',
    backgroundColor: kBg,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const QuetzalovApp());
}

class QuetzalovApp extends StatefulWidget {
  const QuetzalovApp({super.key});
  @override
  State<QuetzalovApp> createState() => _QuetzalovAppState();
}

class _QuetzalovAppState extends State<QuetzalovApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Kapanırken izleme konumunu kaydet
    try {
      await playback.stop();
    } catch (_) {}
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quetzalov',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: Listenable.merge([store, windowCtl]),
        builder: (context, _) {
          if (!store.hasAccount || store.api == null) return const LoginPage();
          return windowCtl.mode == ViewMode.browse ? const Shell() : const PlayerScreen();
        },
      ),
    );
  }
}
