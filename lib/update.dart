import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core.dart';

/// Consulta a última "Release" do GitHub. Se o número da versão publicada for
/// maior que o do app instalado, oferece baixar e instalar o novo APK.
Future<void> verificarAtualizacao(BuildContext context) async {
  if (githubRepo.isEmpty) return;
  try {
    final r = await http
        .get(
          Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return;

    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] ?? '') as String;
    final ultima = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final atual =
        int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    if (ultima <= atual) return;

    String? url;
    for (final a in (j['assets'] as List? ?? [])) {
      final m = a as Map<String, dynamic>;
      if ((m['name'] as String).endsWith('.apk')) {
        url = m['browser_download_url'] as String;
        break;
      }
    }
    if (url == null || !context.mounted) return;

    final apk = url;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nova versão disponível'),
        content: const Text(
            'Toque em "Baixar" e, ao terminar, abra o arquivo para instalar a atualização.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Depois')),
          FilledButton(
            onPressed: () {
              launchUrl(Uri.parse(apk), mode: LaunchMode.externalApplication);
              Navigator.pop(c);
            },
            child: const Text('Baixar'),
          ),
        ],
      ),
    );
  } catch (_) {
    // Sem internet ou limite da API do GitHub: ignora silenciosamente.
  }
}
