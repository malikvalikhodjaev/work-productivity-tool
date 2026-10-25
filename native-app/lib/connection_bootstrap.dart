import 'dart:convert';
import 'dart:io';

import 'domain.dart';
import 'local_database.dart';

/// Provisioning file is in the app's own directory, never in the public assets.
/// No database reset or change of archive identity is permitted here.
Future<bool> applyConnectionBootstrap(LocalDatabase local, File file) async {
  if (!await file.exists()) return false;
  final data = object(jsonDecode(await file.readAsString()));
  final uri = Uri.tryParse(data['origin']?.toString() ?? '');
  final serverId = local.get('serverId');
  if (data['version'] != 1 ||
      serverId is! String ||
      serverId.isEmpty ||
      data['serverId'] != serverId ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.host.isEmpty ||
      !['', '/'].contains(uri.path) ||
      uri.hasQuery ||
      uri.hasFragment ||
      data['authorization'] is! String ||
      !RegExp(r'^Basic [A-Za-z0-9+/]+=*$').hasMatch(data['authorization'])) {
    throw const FormatException('Invalid connection provisioning file');
  }
  local.atomic(() {
    local.set('baseUrl', uri.origin);
    local.set('serverAuth', {
      'origin': uri.origin,
      'authorization': data['authorization'],
    });
  });
  await file.delete();
  return true;
}
