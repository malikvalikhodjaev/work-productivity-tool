import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'domain.dart';
import 'repository.dart';

final questionLibrary = rootBundle
    .loadString('assets/reflection-hints.json')
    .then((s) => rows(jsonDecode(s)));
Future<void> openSource(String? value) async {
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class ReflectionHints extends StatelessWidget {
  final DashboardRepository repo;
  const ReflectionHints({super.key, required this.repo});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Json>>(
    future: questionLibrary,
    builder: (context, snapshot) {
      final sources = object(repo.cache('hints')['sources']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final block in snapshot.data ?? <Json>[])
            ExpansionTile(
              title: Text(block['title'].toString()),
              subtitle: Text((block['caption'] ?? '').toString()),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((block['intro'] ?? '').toString()),
                      for (final step in rows(block['steps']))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (step['title'] ?? '').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                (step['question'] ?? '').toString(),
                                style: const TextStyle(fontSize: 16),
                              ),
                              Text((step['description'] ?? '').toString()),
                              for (final question
                                  in (step['more'] as List? ?? []))
                                Text('• $question'),
                            ],
                          ),
                        ),
                      for (final question in (block['checks'] as List? ?? []))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text((question as List).join('\n')),
                        ),
                      if (sources[block['id']] != null)
                        TextButton(
                          onPressed: () =>
                              openSource(sources[block['id']]?.toString()),
                          child: const Text('Открыть источник ↗'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      );
    },
  );
}
