import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Valores injetados na compilação (--dart-define). Não coloque chaves no código.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const githubRepo = String.fromEnvironment('GITHUB_REPO'); // "usuario/repositorio"

SupabaseClient get sb => Supabase.instance.client;

final navigatorKey = GlobalKey<NavigatorState>();

/// Id da entrega recebido por link (bolaria://entrega/<id>), esperando ser aberto.
final linkPendente = ValueNotifier<String?>(null);

const rotulosStatus = {
  'pendente': 'Pendente',
  'aceita': 'Aceita',
  'concluida': 'Concluída',
  'cancelada': 'Cancelada',
};

final brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

/// Converte um timestamp ISO do banco para texto local.
String dh(dynamic iso) =>
    _fmtDataHora.format(DateTime.parse(iso as String).toLocal());

double num2(dynamic v) => ((v ?? 0) as num).toDouble();

void aviso(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

Future<DateTime?> escolherDataHora(BuildContext c, DateTime inicial) async {
  final d = await showDatePicker(
    context: c,
    initialDate: inicial,
    firstDate: DateTime(2024),
    lastDate: DateTime(2100),
  );
  if (d == null || !c.mounted) return null;
  final t = await showTimePicker(
    context: c,
    initialTime: TimeOfDay.fromDateTime(inicial),
  );
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

/// Telefone digitado -> só dígitos com DDI 55 (formato do wa.me).
String telParaWhats(String t) {
  final d = t.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '';
  return d.length <= 11 ? '55$d' : d;
}

/// Telefone guardado -> texto para exibir/editar (sem o 55).
String telParaExibir(String? t) {
  var d = (t ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('55') && d.length > 11) d = d.substring(2);
  return d;
}

/// Link clicável (GitHub Pages) que abre a entrega dentro do app.
String linkEntrega(String id) {
  final partes = githubRepo.split('/');
  if (partes.length != 2) return '';
  return 'https://${partes[0].toLowerCase()}.github.io/${partes[1]}/entrega.html?id=$id';
}

/// Abre o WhatsApp já no número informado, com a mensagem pronta.
Future<void> abrirWhatsApp(BuildContext c, String telefone, String texto) async {
  final destino = telParaWhats(telefone);
  final uri =
      Uri.parse('https://wa.me/$destino?text=${Uri.encodeComponent(texto)}');
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && c.mounted) aviso(c, 'Não foi possível abrir o WhatsApp.');
  } catch (_) {
    if (c.mounted) aviso(c, 'Não foi possível abrir o WhatsApp.');
  }
}
