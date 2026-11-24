import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'theme.dart';

enum ViewMode { browse, player, fullscreen, mini }

/// Pencere durumları: önde kalma, mini oynatıcı, tam ekran.
class WindowCtl extends ChangeNotifier {
  ViewMode mode = ViewMode.browse;
  ViewMode _beforeMini = ViewMode.browse;
  ViewMode _beforeFull = ViewMode.player;
  bool pinned = false;
  Rect? _savedBounds;

  Future<void> setPinned(bool v) async {
    pinned = v;
    await windowManager.setAlwaysOnTop(v || mode == ViewMode.mini);
    notifyListeners();
  }

  void openPlayer() {
    if (mode == ViewMode.browse) {
      mode = ViewMode.player;
      notifyListeners();
    }
  }

  Future<void> closePlayer() async {
    if (mode == ViewMode.fullscreen) await windowManager.setFullScreen(false);
    if (mode == ViewMode.mini) await exitMini();
    mode = ViewMode.browse;
    notifyListeners();
  }

  Future<void> toggleFullscreen() async {
    if (mode == ViewMode.mini) await exitMini();
    if (mode == ViewMode.fullscreen) {
      await windowManager.setFullScreen(false);
      mode = _beforeFull;
    } else {
      _beforeFull = mode == ViewMode.browse ? ViewMode.browse : ViewMode.player;
      mode = ViewMode.fullscreen;
      await windowManager.setFullScreen(true);
    }
    notifyListeners();
  }

  Future<void> exitFullscreen() async {
    if (mode == ViewMode.fullscreen) await toggleFullscreen();
  }

  Future<void> enterMini() async {
    if (mode == ViewMode.mini) return;
    if (mode == ViewMode.fullscreen) {
      await windowManager.setFullScreen(false);
      mode = _beforeFull;
    }
    _beforeMini = mode;
    _savedBounds = await windowManager.getBounds();
    mode = ViewMode.mini;
    notifyListeners();
    await windowManager.setMinimumSize(const Size(240, 135));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(const Size(480, 270));
    await windowManager.setAlignment(Alignment.bottomRight);
  }

  Future<void> exitMini() async {
    if (mode != ViewMode.mini) return;
    mode = _beforeMini;
    notifyListeners();
    await windowManager.setAlwaysOnTop(pinned);
    await windowManager.setMinimumSize(kMinWindow);
    if (_savedBounds != null) await windowManager.setBounds(_savedBounds!);
  }
}

final windowCtl = WindowCtl();
