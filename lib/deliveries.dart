import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core.dart';

const _rotulos = {
  'pendente': 'Pendente',
  'aceita': 'Aceita',
  'concluida': 'Concluída',
  'cancelada': 'Cancelada',
};

const _nomesStatus = {
  'abertas': 'Abertas',
  'concluidas': 'Concluídas',
  'canceladas': 'Canceladas',
};

DateTime _dia(DateTime base, int delta) =>
    DateTime(base.year, base.month, base.day + delta);

/// Intervalo [início, fim) do período escolhido, calculado pelo calendário de hoje.
(DateTime, DateTime)? _intervalo(String? p, DateTime agora) {
  if (p == null) return null;
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final segunda = _dia(hoje, -(hoje.weekday - 1)); // segunda-feira desta semana
  switch (p) {
    case 'hoje':
      return (hoje, _dia(hoje, 1));
    case 'ontem':
      return (_dia(hoje, -1), hoje);
    case 'semana': // segunda até hoje
      return (segunda, _dia(hoje, 1));
    case 'semana_passada': // segunda a domingo da semana anterior
      return (_dia(segunda, -7), segunda);
    case 'mes': // mês inteiro
      return (
        DateTime(agora.year, agora.month, 1),
        DateTime(agora.year, agora.month + 1, 1)
      );
  }
  return null;
}

/// Rótulos dos botões de período, com as datas reais de hoje.
Map<String, String> _rotulosPeriodo(DateTime agora) {
  final f = DateFormat('dd/MM', 'pt_BR');
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final segunda = _dia(hoje, -(hoje.weekday - 1));
  final segPassada = _dia(segunda, -7);
  final domPassado = _dia(segunda, -1);
  final mes = DateFormat('MMMM', 'pt_BR').format(agora);
  final mesCap = mes[0].toUpperCase() + mes.substring(1);
  final semana = f.format(segunda) == f.format(hoje)
      ? f.format(hoje)
      : '${f.format(segunda)} a ${f.format(hoje)}';
  return {
    'hoje': 'Hoje (${f.format(hoje)})',
    'ontem': 'Ontem (${f.format(_dia(hoje, -1))})',
    'semana': 'Essa semana ($semana)',
    'semana_passada':
        'Semana passada (${f.format(segPassada)} a ${f.format(domPassado)})',
    'mes': 'Este mês ($mesCap)',
  };
}

String _mensagemWhatsApp(Map<String, dynamic> d) {
  final itens = List<Map<String, dynamic>>.from(d['delivery_items'] ?? []);
  final tel = (d['telefone'] ?? '') as String;
  final obs = (d['observacoes'] ?? '') as String;
  final b = StringBuffer()
    ..writeln('🧁 *Bolaria Beatriz*')
    ..writeln('📦 *Entrega #${d['numero']}*')
    ..writeln()
    ..writeln('👤 *Cliente:* ${d['cliente']}')
    ..writeln('📍 *Endereço:* ${d['endereco']}');
  if (tel.isNotEmpty) b.writeln('📞 *Telefone:* $tel');
  b
    ..writeln('🗓️ *Entregar em:* ${dh(d['scheduled_at'])}')
    ..writeln('📝 *Solicitado em:* ${dh(d['requested_at'])}')
    ..writeln()
    ..writeln('🛒 *Itens:*');
  for (final i in itens) {
    final sub = brl.format((i['preco_unit'] as num) * (i['quantidade'] as num));
    b.writeln('• ${i['quantidade']}x ${i['nome']} — $sub');
  }
  b
    ..writeln()
    ..writeln('💰 *Total:* ${brl.format(d['total'] as num)}');
  if (obs.isNotEmpty) b.writeln('🗒️ *Obs:* $obs');
  return b.toString().trim();
}

/// Lista de entregas. Usada pelo dono (admin: true) e pelo entregador.
class DeliveriesList extends StatefulWidget {
  final bool admin;
  const DeliveriesList({super.key, required this.admin});

  @override
  State<DeliveriesList> createState() => DeliveriesListState();
}

class DeliveriesListState extends State<DeliveriesList> {
  List<Map<String, dynamic>> _entregas = [];
  int _realizadas = 0;
  bool _carregando = true;
  String _status = 'abertas';
  String? _periodo; // null = sem filtro de data
  int _req = 0;
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    reload();
    _canal = sb
        .channel('entregas-canal')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deliveries',
          callback: (_) => reload(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_canal != null) sb.removeChannel(_canal!);
    super.dispose();
  }

  Future<void> reload() async {
    final req = ++_req;
    final iv = _intervalo(_periodo, DateTime.now());
    try {
      var q = sb.from('deliveries').select('*, delivery_items(*)');
      switch (_status) {
        case 'abertas':
          q = q.inFilter('status', ['pendente', 'aceita']);
          break;
        case 'concluidas':
          q = q.eq('status', 'concluida');
          break;
        default:
          q = q.eq('status', 'cancelada');
      }
      if (iv != null) {
        q = q
            .gte('scheduled_at', iv.$1.toUtc().toIso8601String())
            .lt('scheduled_at', iv.$2.toUtc().toIso8601String());
      }
      final data = await q
          .order('scheduled_at', ascending: _status == 'abertas')
          .limit(1000);

      var realizadas = 0;
      if (!widget.admin) {
        var c = sb.from('deliveries').select('id').eq('status', 'concluida');
        if (iv != null) {
          c = c
              .gte('scheduled_at', iv.$1.toUtc().toIso8601String())
              .lt('scheduled_at', iv.$2.toUtc().toIso8601String());
        }
        realizadas = (await c.limit(1000)).length;
      }

      if (!mounted || req != _req) return; // resposta antiga: ignora
      setState(() {
        _entregas = List<Map<String, dynamic>>.from(data);
        _realizadas = realizadas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() => _carregando = false);
      aviso(context, 'Erro ao carregar: $e');
    }
  }

  void _trocarStatus(String s) {
    setState(() {
      _status = s;
      _carregando = true;
    });
    reload();
  }

  void _trocarPeriodo(String? p) {
    setState(() {
      _periodo = p;
      _carregando = true;
    });
    reload();
  }

  Future<void> _rpc(String fn, String id) async {
    try {
      await sb.rpc(fn, params: {'p_id': id});
      await reload();
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  Future<bool> _confirmar(String titulo, String botao) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: Text(botao)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _cancelar(Map<String, dynamic> d) async {
    if (!await _confirmar('Cancelar a entrega #${d['numero']}?', 'Cancelar entrega')) {
      return;
    }
    try {
      await sb
          .from('deliveries')
          .update({'status': 'cancelada'}).eq('id', d['id'] as String);
      await reload();
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  Future<void> _excluir(Map<String, dynamic> d) async {
    if (!await _confirmar(
        'Excluir a entrega #${d['numero']}? Não dá para desfazer.', 'Excluir')) {
      return;
    }
    try {
      await sb.from('deliveries').delete().eq('id', d['id'] as String);
      await reload();
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  Future<void> _enviarWhatsApp(Map<String, dynamic> d) async {
    final texto = Uri.encodeComponent(_mensagemWhatsApp(d));
    final destino = whatsappEntregador.isEmpty ? '' : whatsappEntregador;
    final uri = Uri.parse('https://wa.me/$destino?text=$texto');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) aviso(context, 'Não foi possível abrir o WhatsApp.');
    } catch (_) {
      if (mounted) aviso(context, 'Não foi possível abrir o WhatsApp.');
    }
  }

  Widget _cartao(Map<String, dynamic> d) {
    final itens = List<Map<String, dynamic>>.from(d['delivery_items'] ?? []);
    final status = d['status'] as String;
    final tel = (d['telefone'] ?? '') as String;
    final obs = (d['observacoes'] ?? '') as String;
    final endereco = d['endereco'] as String;
    final tema = Theme.of(context).textTheme;
    final aberta = status == 'pendente' || status == 'aceita';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('#${d['numero']}',
                      style: tema.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary)),
                ),
                Chip(label: Text(_rotulos[status] ?? status)),
              ],
            ),
            Text(d['cliente'] as String,
                style: tema.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Entregar em: ${dh(d['scheduled_at'])}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Solicitado em: ${dh(d['requested_at'])}'),
            const SizedBox(height: 4),
            Text(endereco),
            if (tel.isNotEmpty) Text('Tel: $tel'),
            if (obs.isNotEmpty) Text('Obs: $obs'),
            const Divider(),
            for (final i in itens)
              Text(
                  '${i['quantidade']}x ${i['nome']}  —  ${brl.format((i['preco_unit'] as num) * (i['quantidade'] as num))}'),
            const SizedBox(height: 4),
            Text('Total: ${brl.format(d['total'] as num)}',
                style: tema.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('Mapa'),
                  onPressed: () => launchUrl(
                    Uri.parse('geo:0,0?q=${Uri.encodeComponent(endereco)}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                if (tel.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.call),
                    label: const Text('Ligar'),
                    onPressed: () => launchUrl(Uri.parse('tel:$tel')),
                  ),
                if (widget.admin && aberta)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366)),
                    icon: const Icon(Icons.send),
                    label: const Text('WhatsApp'),
                    onPressed: () => _enviarWhatsApp(d),
                  ),
                if (!widget.admin && status == 'pendente')
                  FilledButton(
                    onPressed: () => _rpc('aceitar_entrega', d['id'] as String),
                    child: const Text('Aceitar'),
                  ),
                if (!widget.admin && status == 'aceita')
                  FilledButton(
                    onPressed: () =>
                        _rpc('concluir_entrega', d['id'] as String),
                    child: const Text('Marcar como concluída'),
                  ),
                if (widget.admin && aberta)
                  TextButton(
                    onPressed: () => _cancelar(d),
                    child: const Text('Cancelar'),
                  ),
                if (widget.admin && status == 'cancelada')
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error),
                    icon: const Icon(Icons.delete),
                    label: const Text('Excluir'),
                    onPressed: () => _excluir(d),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dado(String rotulo, String valor) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: Theme.of(context).textTheme.bodySmall),
          Text(valor,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      );

  Widget _resumo(Map<String, String> rotulosPeriodo) {
    final periodoTxt =
        _periodo == null ? 'Todas as datas' : rotulosPeriodo[_periodo]!;
    final valor = _entregas.fold<double>(
        0, (s, d) => s + (d['total'] as num).toDouble());
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.admin
                  ? '${_nomesStatus[_status]} • $periodoTxt'
                  : periodoTxt,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            if (widget.admin)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _dado('Entregas', '${_entregas.length}'),
                  _dado(_status == 'concluidas' ? 'Arrecadado' : 'Valor total',
                      brl.format(valor)),
                ],
              )
            else
              _dado('Entregas realizadas', '$_realizadas'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rp = _rotulosPeriodo(DateTime.now());
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in _nomesStatus.entries)
                  ChoiceChip(
                    label: Text(f.value),
                    selected: _status == f.key,
                    onSelected: (_) => _trocarStatus(f.key),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final p in rp.entries)
                  FilterChip(
                    label: Text(p.value),
                    selected: _periodo == p.key,
                    onSelected: (sel) => _trocarPeriodo(sel ? p.key : null),
                  ),
              ],
            ),
          ),
          _resumo(rp),
          if (_carregando)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_entregas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nenhuma entrega aqui.')),
            )
          else
            for (final d in _entregas) _cartao(d),
        ],
      ),
    );
  }
}
