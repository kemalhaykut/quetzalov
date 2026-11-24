import 'package:flutter/material.dart';

const kMinWindow = Size(760, 480);

// Anka kuşu renkleri: koyu gece zemini üstünde ateş turuncusu ve altın
const kBg = Color(0xFF0B0B10);
const kSurface = Color(0xFF13131B);
const kCard = Color(0xFF1B1B26);
const kLine = Color(0xFF2A2A38);
const kText = Color(0xFFF2F1F7);
const kDim = Color(0xFF9A98AB);
const kFire = Color(0xFFFF6A1A);
const kGold = Color(0xFFFFC145);
const kEmber = Color(0xFFE0342B);
const kLive = Color(0xFFFF3B47);

const kFireGradient = LinearGradient(colors: [kEmber, kFire, kGold], begin: Alignment.bottomLeft, end: Alignment.topRight);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    canvasColor: kBg,
    colorScheme: const ColorScheme.dark(primary: kFire, secondary: kGold, surface: kSurface, onSurface: kText),
    textTheme: base.textTheme.apply(fontFamily: 'Poppins', bodyColor: kText, displayColor: kText),
    dividerColor: kLine,
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.all(Radius.circular(8))),
      textStyle: TextStyle(color: kText, fontFamily: 'Poppins', fontSize: 12),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kLine)),
      textStyle: const TextStyle(color: kText, fontFamily: 'Poppins', fontSize: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      hintStyle: const TextStyle(color: kDim),
      labelStyle: const TextStyle(color: kDim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLine)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLine)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kFire, width: 1.6)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(kLine),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: kFire,
      inactiveTrackColor: Color(0x55FFFFFF),
      thumbColor: kGold,
      overlayColor: Color(0x33FF6A1A),
      trackHeight: 3,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kCard,
      contentTextStyle: TextStyle(color: kText, fontFamily: 'Poppins'),
    ),
  );
}
