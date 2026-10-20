import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'focus_home.dart';
import 'focus_repository.dart';
import 'local_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final folder = Directory(
    Platform.isWindows ? p.join(support.path, 'focus-norms') : support.path,
  );
  await folder.create(recursive: true);
  final repo = FocusRepository(
    LocalDatabase(p.join(folder.path, 'focus-norms.sqlite')),
  );
  runApp(FocusNormsApp(repo: repo, folder: folder.path));
}

class FocusNormsApp extends StatelessWidget {
  final FocusRepository repo;
  final String folder;
  final bool backgroundEnabled;
  const FocusNormsApp({
    super.key,
    required this.repo,
    required this.folder,
    this.backgroundEnabled = true,
  });
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Focus & Norms',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff37594b)),
      scaffoldBackgroundColor: const Color(0xfff6f7f8),
      fontFamily: 'Segoe UI',
    ),
    home: FocusHome(
      repo: repo,
      folder: folder,
      backgroundEnabled: backgroundEnabled,
    ),
  );
}
