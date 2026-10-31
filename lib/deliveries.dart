import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core.dart';
import 'delivery_details.dart';

const _nomesStatus = {
  'abertas': 'Abertas',
  'concluidas': 'Concluídas',
  'canceladas': 'Canceladas',
};

const _nomesPeriodo = {
  'hoje': 'Hoje',
  'ontem': 'Ontem',
  'semana': 'Essa semana',
  'semana_passada': 'Semana passada',
  'mes': 'Este mês',
  'mes_passado': 'Mês passado',
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
    case 'mes_passado':
      return (
        DateTime(agora.year, agora.month - 1, 1),
        DateTime(agora.year, agora.month, 1)
      );
  }
  return null;
}

String _nomeMes(DateTime d) {
  final m = DateFormat('MMMM', 'pt_BR').format(d);
  return m[0].toUpperCase() + m.substring(1);
}

/// Datas reais de cada período (mostradas no resumo, abaixo dos botões).
Map<String, String> _datasPeriodo(DateTime agora) {
  final f = DateFormat('dd/MM', 'pt_BR');
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final segunda = _dia(hoje, -(hoje.weekday - 1));
  final semana = segunda == hoje
      ? f.format(hoje)
      : '${f.format(segunda)} a ${f.format(hoje)}';
  return {
    'hoje': f.format(hoje),
    'ontem': f.format(_dia(hoje, -1)),
    'semana': semana,
    'semana_passada':
        '${f.format(_dia(segunda, -7))} a ${f.format(_dia(segunda, -1))}',
    'mes': _nomeMes(agora),
    'mes_passado': _nomeMes(DateTime(agora.year, agora.month - 1, 1)),
  };
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
      var q = sb.from('deliveries').select();
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
    if (!await _confirmar(
        'Cancelar a entrega #${d['numero']}?', 'Cancelar entrega')) {
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

  Future<void> _detalhes(Map<String, dynamic> d) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => DeliveryDetailsPage(id: d['id'] as String)),
    );
    reload();
  }

  Widget _cartao(Map<String, dynamic> d) {
    final status = d['status'] as String;
    final tel = (d['telefone'] ?? '') as String;
    final obs = (d['observacoes'] ?? '') as String;
    final endereco = d['endereco'] as String;
    final tema = Theme.of(context).textTheme;
    final aberta = status == 'pendente' || status == 'aceita';
    final id = d['id'] as String;

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
                Chip(label: Text(rotulosStatus[status] ?? status)),
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
            Text(
                'Produtos ${brl.format(num2(d['subtotal']))} + Taxa ${brl.format(num2(d['taxa_entrega']))}'),
            Text('Total: ${brl.format(num2(d['total']))}',
                style: tema.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Ver detalhes'),
                  onPressed: () => _detalhes(d),
                ),
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
                    onPressed: () async {
                      await encaminharEntrega(context, id);
                      reload();
                    },
                  ),
                if (!widget.admin && status == 'pendente')
                  FilledButton(
                    onPressed: () async {
                      await aceitarEntrega(context, id);
                      reload();
                    },
                    child: const Text('Aceitar'),
                  ),
                if (!widget.admin && status == 'aceita')
                  FilledButton(
                    onPressed: () async {
                      try {
                        await sb.rpc('concluir_entrega', params: {'p_id': id});
                      } catch (e) {
                        if (mounted) aviso(context, 'Erro: $e');
                      }
                      reload();
                    },
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rotulo, style: Theme.of(context).textTheme.bodySmall),
          Text(valor,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      );

  Widget _resumo(Map<String, String> datas) {
    final periodoTxt = _periodo == null
        ? 'Todas as datas'
        : '${_nomesPeriodo[_periodo]} (${datas[_periodo]})';
    final produtos = _entregas.fold<double>(0, (s, d) => s + num2(d['subtotal']));
    final taxas = _entregas.fold<double>(0, (s, d) => s + num2(d['taxa_entrega']));
    final total = _entregas.fold<double>(0, (s, d) => s + num2(d['total']));
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
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            if (widget.admin)
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _dado('Entregas', '${_entregas.length}'),
                  _dado('Produtos', brl.format(produtos)),
                  _dado('Taxas', brl.format(taxas)),
                  _dado('Total geral', brl.format(total)),
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
    final datas = _datasPeriodo(DateTime.now());
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
                for (final p in _nomesPeriodo.entries)
                  FilterChip(
                    label: Text(p.value),
                    selected: _periodo == p.key,
                    onSelected: (sel) => _trocarPeriodo(sel ? p.key : null),
                  ),
              ],
            ),
          ),
          _resumo(datas),
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
