import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Valores injetados na compilação (--dart-define). Não coloque chaves no código.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const githubRepo = String.fromEnvironment('GITHUB_REPO'); // "usuario/repositorio"

// Número do WhatsApp do entregador, só dígitos com DDI+DDD (ex.: '5588999999999').
// Se ficar vazio, o WhatsApp abre para você escolher o contato.
const whatsappEntregador = '';

SupabaseClient get sb => Supabase.instance.client;

final brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

/// Converte um timestamp ISO do banco para texto local.
String dh(dynamic iso) =>
    _fmtDataHora.format(DateTime.parse(iso as String).toLocal());

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
