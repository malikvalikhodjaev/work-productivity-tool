import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Uri? modelLinkUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  return uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

class ModelLink extends StatelessWidget {
  final String value;
  const ModelLink({super.key, required this.value});
  @override
  Widget build(BuildContext context) {
    final uri = modelLinkUri(value);
    if (uri == null) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () async {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
            context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось открыть ссылку на модель.'),
            ),
          );
        }
      },
      icon: const Icon(Icons.open_in_new, size: 18),
      label: const Text('Открыть модель'),
    );
  }
}
