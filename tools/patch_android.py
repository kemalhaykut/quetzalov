# -*- coding: utf-8 -*-
"""CI: 'flutter create --platforms android' sonrası Android TV (Mi Box) ayarları."""
import re, pathlib, shutil

man = pathlib.Path("android/app/src/main/AndroidManifest.xml")
s = man.read_text(encoding="utf-8")
s = re.sub(r'android:label="[^"]*"', 'android:label="Quetzalov"', s, count=1)

head = ""
if "android.permission.INTERNET" not in s:
    head += '    <uses-permission android:name="android.permission.INTERNET" />\n'
if "android.permission.WAKE_LOCK" not in s:
    head += '    <uses-permission android:name="android.permission.WAKE_LOCK" />\n'
if "android.software.leanback" not in s:
    head += '    <uses-feature android:name="android.software.leanback" android:required="false" />\n'
    head += '    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />\n'
s = s.replace("<application", head + "    <application", 1)

# IPTV sunucuları çoğunlukla http:// (şifresiz) — Android varsayılan olarak engeller
if "usesCleartextTraffic" not in s:
    s = s.replace("<application", '<application\n        android:usesCleartextTraffic="true"\n        android:banner="@drawable/banner"', 1)

# Android TV ana ekranında görünmesi için LEANBACK_LAUNCHER
if "LEANBACK_LAUNCHER" not in s:
    s = re.sub(r'(\s*)(<category\s+android:name="android\.intent\.category\.LAUNCHER"\s*/>)',
               r'\1\2\1<category android:name="android.intent.category.LEANBACK_LAUNCHER"/>', s, count=1)
# Video üstüne menü/duraklatma ekranı çizilirken beyaz ekran oluyordu (Impeller + video dokusu sorunu).
# Klasik çiziciyi (Skia/OpenGL) kullan.
if "EnableImpeller" not in s:
    s = s.replace("</application>",
                  '    <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />\n    </application>', 1)
# Yerel tam ekran oynatıcı ekranı
if "PlayerActivity" not in s:
    s = s.replace("</application>",
                  '    <activity android:name=".PlayerActivity" android:exported="false"\n'
                  '            android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen"\n'
                  '            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|screenLayout|uiMode|navigation" />\n'
                  '    </application>', 1)
man.write_text(s, encoding="utf-8")
assert "LEANBACK_LAUNCHER" in s, "LEANBACK_LAUNCHER eklenemedi"

d = pathlib.Path("android/app/src/main/res/drawable-xhdpi")
d.mkdir(parents=True, exist_ok=True)
shutil.copy("assets/tv_banner.png", d / "banner.png")

for name in ["android/app/build.gradle.kts", "android/app/build.gradle"]:
    p = pathlib.Path(name)
    if not p.exists():
        continue
    g = p.read_text(encoding="utf-8")
    g = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', g)
    g = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24', g)
    if "checkReleaseBuilds" not in g:
        if name.endswith(".kts"):
            block = "android {\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }\n"
        else:
            block = "android {\n    lintOptions {\n        checkReleaseBuilds false\n        abortOnError false\n    }\n"
        g = g.replace("android {\n", block, 1)
    p.write_text(g, encoding="utf-8")
        # ExoPlayer (Media3): Android TV oynatıcısı
    if "media3-exoplayer" not in g:
        q = '"' if name.endswith(".kts") else "'"
        dep = "implementation(" + q + "{}" + q + ")"
        libs = ["androidx.media3:media3-exoplayer:1.9.2", "androidx.media3:media3-exoplayer-hls:1.9.2", "androidx.media3:media3-ui:1.9.2"]
        g += "\ndependencies {\n" + "".join("    " + dep.format(l) + "\n" for l in libs) + "}\n"
        p.write_text(g, encoding="utf-8")
    print("gradle güncellendi:", name)

# Kotlin tarafı: MainActivity + QzPlayer (ExoPlayer köprüsü)
acts = list(pathlib.Path("android/app/src/main").rglob("MainActivity.kt"))
assert acts, "MainActivity.kt bulunamadı"
act = acts[0]
pkg = re.search(r"^package\s+([\w.]+)", act.read_text(encoding="utf-8"), re.M).group(1)
for f in ["MainActivity.kt", "QzPlayer.kt", "PlayerActivity.kt"]:
    src = pathlib.Path("tools") / f
    (act.parent / f).write_text(src.read_text(encoding="utf-8").replace("package PKG", "package " + pkg, 1), encoding="utf-8")
print("Kotlin dosyaları eklendi:", act.parent, pkg)
print(s)
