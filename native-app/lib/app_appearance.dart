import 'dart:io';

import 'package:flutter/material.dart';

import 'interaction_theme.dart';
import 'repository.dart';

const appearanceLabels = {
  'neutral': 'Нейтральная · серый минимализм',
  'pomodoro': 'Pomodoro · коралловая',
  'green': 'Зелёная · классическая',
  'blue': 'Синяя',
  'dark': 'Тёмная',
  'system': 'Как в системе',
};

const appearanceFonts = {
  'system': 'Системный',
  'NotoSans': 'Noto Sans · без засечек',
  'NotoSerif': 'Noto Serif · с засечками',
};

ThemeData dashboardTheme(
  String style, {
  Brightness? brightness,
  String font = 'system',
}) {
  final dark = brightness == Brightness.dark || style == 'dark';
  final seed = switch (style) {
    'pomodoro' => const Color(0xffb8493c),
    'green' => const Color(0xff37594b),
    'blue' => const Color(0xff355da2),
    _ => const Color(0xff55565b),
  };
  var scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  if (style == 'neutral' || style == 'dark' || style == 'system') {
    scheme = scheme.copyWith(
      primary: dark ? const Color(0xffe0e0e4) : const Color(0xff45464c),
      onPrimary: dark ? const Color(0xff202124) : Colors.white,
      primaryContainer: dark
          ? const Color(0xff3a3b40)
          : const Color(0xffe8e8ed),
      onPrimaryContainer: dark ? Colors.white : const Color(0xff24252a),
      secondaryContainer: dark
          ? const Color(0xff34353a)
          : const Color(0xffe8e8ed),
      onSecondaryContainer: dark ? Colors.white : const Color(0xff24252a),
      surface: dark ? const Color(0xff17181b) : const Color(0xfff5f5f7),
      surfaceContainer: dark
          ? const Color(0xff222327)
          : const Color(0xffefeff2),
      surfaceContainerLow: dark ? const Color(0xff1e1f23) : Colors.white,
      surfaceContainerHigh: dark
          ? const Color(0xff2c2d32)
          : const Color(0xffe9e9ee),
    );
  }
  final panel = dark ? scheme.surfaceContainerLow : Colors.white;
  return interactionTheme(
    ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: font == 'NotoSans' || font == 'NotoSerif'
          ? font
          : Platform.isWindows
          ? 'Segoe UI'
          : null,
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: panel,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
      ),
    ),
  );
}

double appearanceTextScale(DashboardRepository repo) =>
    (repo.local.get('appTextScale') as num? ?? 1).toDouble().clamp(1, 1.3);

class AppearanceSettings extends StatelessWidget {
  final DashboardRepository repo;
  const AppearanceSettings({super.key, required this.repo});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final saved = repo.local.get('appAppearance')?.toString();
      final style = appearanceLabels.containsKey(saved) ? saved! : 'neutral';
      final scale = appearanceTextScale(repo);
      final font = repo.local.get('appFont')?.toString() ?? 'system';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('app-appearance:$style'),
            initialValue: style,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Оформление приложения',
            ),
            items: [
              for (final entry in appearanceLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => repo.setUiPreference('appAppearance', value),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('app-font:$font'),
            initialValue: appearanceFonts.containsKey(font) ? font : 'system',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Шрифт'),
            items: [
              for (final entry in appearanceFonts.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => repo.setUiPreference('appFont', value),
          ),
          const SizedBox(height: 16),
          Text('Размер текста · ${(scale * 100).round()}%'),
          Slider(
            key: const ValueKey('app-text-scale'),
            min: 1,
            max: 1.3,
            divisions: 3,
            value: scale,
            label: '${(scale * 100).round()}%',
            onChanged: (value) => repo.setUiPreference('appTextScale', value),
          ),
          const Text(
            'Увеличение добавляется к размеру текста в настройках устройства. '
            'Выбор сохраняется на этом устройстве; картины таймера настраиваются отдельно.',
          ),
        ],
      );
    },
  );
}
