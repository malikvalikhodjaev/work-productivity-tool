import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'domain.dart';
import 'focus_theme.dart';
import 'focus_rotation.dart';
import 'repository.dart';

class FocusGallerySettings extends StatefulWidget {
  final DashboardRepository repo;
  const FocusGallerySettings({super.key, required this.repo});
  @override
  State<FocusGallerySettings> createState() => _FocusGallerySettingsState();
}

class _FocusGallerySettingsState extends State<FocusGallerySettings> {
  late final TextEditingController minutes;
  String? error;
  DashboardRepository get repo => widget.repo;
  Map<String, dynamic> get rotation => object(repo.local.get('focusRotation'));
  String get manual => (repo.local.get('theme') ?? 'green').toString();
  @override
  void initState() {
    super.initState();
    minutes = TextEditingController(text: '${rotationMinutes(rotation)}');
  }

  @override
  void dispose() {
    minutes.dispose();
    super.dispose();
  }

  void select(String theme) {
    final old = rotation;
    final pool = rotationPool(old);
    final painting = focusArtworks.where((a) => a.id == theme).firstOrNull;
    if (painting != null && !pool.contains(theme)) {
      pool.addAll(
        focusArtworks
            .where((a) => a.artist == painting.artist)
            .map((a) => a.id),
      );
    }
    repo.setUiPreferences({
      'theme': theme,
      'focusRotation': {
        ...restartRotation(old, nowMs: DateTime.now().millisecondsSinceEpoch),
        'pool': pool.toSet().toList(),
        if (painting == null) 'enabled': false,
      },
    });
    setState(() {});
  }

  void configure({bool? enabled, List<String>? pool, int? interval}) {
    final value = interval ?? int.tryParse(minutes.text.trim());
    if (value == null || value < 1 || value > 10080) {
      setState(() => error = 'Укажи от 1 до 10080 минут');
      return;
    }
    final old = rotation, now = DateTime.now().millisecondsSinceEpoch;
    final choices = pool ?? rotationPool(old);
    if (choices.isEmpty) {
      setState(() => error = 'Выбери хотя бы одного художника');
      return;
    }
    final current = focusThemeAt(manual, old, now);
    repo.setUiPreferences({
      'theme': (enabled ?? old['enabled'] == true)
          ? (choices.contains(current) ? current : choices.first)
          : current,
      'focusRotation': {
        'enabled': enabled ?? old['enabled'] == true,
        'pool': choices,
        'minutes': value,
        'anchorMs': now,
      },
    });
    setState(() {
      minutes.text = '$value';
      error = null;
    });
  }

  Future<void> gallery() async {
    var artist =
        focusArtworks.where((a) => a.id == manual).firstOrNull?.artist ??
        'monet';
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 740,
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Картины · по пять у каждого художника',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть библиотеку картин',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  DropdownButton<String>(
                    value: artist,
                    isExpanded: true,
                    items: focusArtists.entries
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.key,
                            child: Text(a.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) refresh(() => artist = value);
                    },
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: LayoutBuilder(
                        builder: (context, box) => Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final art in focusArtworks.where(
                              (a) => a.artist == artist,
                            ))
                              SizedBox(
                                width: box.maxWidth < 350
                                    ? box.maxWidth
                                    : (box.maxWidth - 12) / 2,
                                child: Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: manual == art.id
                                          ? const Color(0xff347558)
                                          : const Color(0xffe7e9ed),
                                      width: manual == art.id ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          select(art.id);
                                          refresh(() {});
                                        },
                                        child: Semantics(
                                          button: true,
                                          label: art.label,
                                          child: Image.asset(
                                            'assets/art/${art.file}',
                                            height: 160,
                                            fit: BoxFit.contain,
                                            cacheWidth: 480,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(art.label),
                                      ),
                                      Wrap(
                                        children: [
                                          TextButton(
                                            onPressed: () {
                                              select(art.id);
                                              refresh(() {});
                                            },
                                            child: Text(
                                              manual == art.id
                                                  ? 'Выбрано'
                                                  : 'Выбрать',
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => launchUrl(
                                              Uri.parse(art.source),
                                              mode: LaunchMode
                                                  .externalApplication,
                                            ),
                                            child: const Text('Источник'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = rotation;
    final pool = rotationPool(config);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final key in ['green', 'evening', 'desert', 'lofi'])
              ChoiceChip(
                label: Text(focusThemes[key]!),
                selected: manual == key && config['enabled'] != true,
                onSelected: (_) => select(key),
              ),
          ],
        ),
        TextButton.icon(
          onPressed: gallery,
          icon: const Icon(Icons.collections_outlined, color: Colors.white),
          label: const Text(
            'Библиотека картин · 35',
            style: TextStyle(color: Colors.white),
          ),
        ),
        Text(
          'Выбрано: ${focusThemes[manual] ?? 'Своя картина'}',
          style: const TextStyle(color: Colors.white70),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Автоматически менять картины',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: const Text(
            'Без интернета. Выбранные художники чередуются по порядку; звук и таймер продолжаются.',
            style: TextStyle(color: Colors.white70),
          ),
          value: config['enabled'] == true,
          onChanged: (value) => configure(enabled: value),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final pair in [(10, '10 минут'), (240, '4 часа')])
              ActionChip(
                label: Text(pair.$2),
                onPressed: () => configure(interval: pair.$1),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('focus-rotation-minutes'),
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Частота смены · минут',
                  errorText: error,
                ),
                onSubmitted: (_) => configure(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => configure(),
              child: const Text('Применить'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Художники для автосмены',
          style: TextStyle(color: Colors.white70),
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final artist in focusArtists.entries)
              FilterChip(
                label: Text(artist.value),
                selected: focusArtworks.any(
                  (a) => a.artist == artist.key && pool.contains(a.id),
                ),
                onSelected: (value) {
                  final next = [
                    ...pool.where(
                      (id) => !focusArtworks.any(
                        (a) => a.artist == artist.key && a.id == id,
                      ),
                    ),
                  ];
                  if (value) {
                    next.addAll(
                      focusArtworks
                          .where((a) => a.artist == artist.key)
                          .map((a) => a.id),
                    );
                  }
                  configure(pool: next);
                },
              ),
          ],
        ),
      ],
    );
  }
}
