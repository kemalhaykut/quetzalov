import 'package:flutter/material.dart';
import 'api.dart';
import 'store.dart';
import 'theme.dart';

/// İnternetten resim; yüklenemezse şık bir yer tutucu.
class NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final IconData icon;
  final String? label;
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.icon = Icons.movie_rounded, this.label});

  Widget _ph() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF24202E), Color(0xFF15131C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: label == null
            ? Icon(icon, color: kDim, size: 30)
            : Text(label!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kDim, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty || !url.startsWith('http')) return _ph();
    return Image.network(
      url,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => _ph(),
      loadingBuilder: (c, child, prog) => prog == null ? child : _ph(),
    );
  }
}

/// Sol taraftaki kategori listesi.
class CategoryList extends StatelessWidget {
  final List<Cat> cats;
  final Map<String, int> counts;
  final String? selected; // null = tümü, '★' = favoriler
  final ValueChanged<String?> onSelect;
  final String filter;
  final int total;
  final int favCount;
  const CategoryList({
    super.key,
    required this.cats,
    required this.counts,
    required this.selected,
    required this.onSelect,
    required this.total,
    required this.favCount,
    this.filter = '',
  });

  @override
  Widget build(BuildContext context) {
    final f = filter.toLowerCase();
    final list = cats.where((c) => f.isEmpty || c.name.toLowerCase().contains(f)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
      children: [
        _tile(null, 'Tümü', total, Icons.apps_rounded),
        _tile('★', 'Favoriler', favCount, Icons.star_rounded),
        const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1)),
        for (final c in list) _tile(c.id, c.name, counts[c.id] ?? 0, null),
      ],
    );
  }

  Widget _tile(String? id, String name, int count, IconData? icon) {
    final on = selected == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: on ? kFire.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelect(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: on ? kFire : kDim), const SizedBox(width: 8)],
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? kText : const Color(0xFFCFCDDA))),
              ),
              Text('$count', style: TextStyle(fontSize: 11.5, color: on ? kFire : kDim, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
      ),
    );
  }
}

class FavButton extends StatelessWidget {
  final Item item;
  final double size;
  const FavButton(this.item, {super.key, this.size = 22});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) {
          final on = store.isFav(item);
          return IconButton(
            tooltip: on ? 'Favorilerden çıkar' : 'Favorilere ekle',
            iconSize: size,
            onPressed: () => store.toggleFav(item),
            icon: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded, color: on ? kGold : kDim),
          );
        },
      );
}

class LoadingView extends StatelessWidget {
  final String text;
  const LoadingView(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: kFire, strokeWidth: 3)),
          const SizedBox(height: 14),
          Text(text, style: const TextStyle(color: kDim)),
        ]),
      );
}

class ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const ErrorView(this.error, this.onRetry, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded, color: kDim, size: 42),
          const SizedBox(height: 10),
          Text(error, textAlign: TextAlign.center, style: const TextStyle(color: kDim)),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kFire),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tekrar dene'),
          ),
        ]),
      );
}

class EmptyView extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyView(this.text, {super.key, this.icon = Icons.search_off_rounded});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: kDim, size: 40),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: kDim)),
        ]),
      );
}

/// Arama: Türkçe karakterleri sadeleştirerek eşleştirir.
String norm(String s) => s
    .replaceAll('İ', 'i')
    .replaceAll('I', 'ı')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');
