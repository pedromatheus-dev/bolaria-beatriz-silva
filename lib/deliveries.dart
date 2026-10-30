import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core.dart';

const _rotulos = {
  'pendente': 'Pendente',
  'aceita': 'Aceita',
  'concluida': 'Concluída',
  'cancelada': 'Cancelada',
};

/// Lista de entregas. Usada pelo dono (admin: true) e pelo entregador.
class DeliveriesList extends StatefulWidget {
  final bool admin;
  const DeliveriesList({super.key, required this.admin});

  @override
  State<DeliveriesList> createState() => DeliveriesListState();
}

class DeliveriesListState extends State<DeliveriesList> {
  List<Map<String, dynamic>> _todas = [];
  bool _carregando = true;
  String _filtro = 'abertas';
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
    try {
      final data = await sb
          .from('deliveries')
          .select('*, delivery_items(*)')
          .order('scheduled_at', ascending: false)
          .limit(300);
      if (!mounted) return;
      setState(() {
        _todas = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      aviso(context, 'Erro ao carregar: $e');
    }
  }

  List<Map<String, dynamic>> get _visiveis {
    final l = _todas.where((d) {
      final s = d['status'];
      switch (_filtro) {
        case 'abertas':
          return s == 'pendente' || s == 'aceita';
        case 'concluidas':
          return s == 'concluida';
        default:
          return s == 'cancelada';
      }
    }).toList();
    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) =>
        DateTime.parse(a['scheduled_at'] as String)
            .compareTo(DateTime.parse(b['scheduled_at'] as String));
    l.sort((a, b) => _filtro == 'abertas' ? cmp(a, b) : cmp(b, a));
    return l;
  }

  Future<void> _rpc(String fn, String id) async {
    try {
      await sb.rpc(fn, params: {'p_id': id});
      await reload();
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  Future<void> _cancelar(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancelar entrega?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Não')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Cancelar entrega')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sb.from('deliveries').update({'status': 'cancelada'}).eq('id', id);
      await reload();
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  Widget _cartao(Map<String, dynamic> d) {
    final itens = List<Map<String, dynamic>>.from(d['delivery_items'] ?? []);
    final status = d['status'] as String;
    final tel = (d['telefone'] ?? '') as String;
    final obs = (d['observacoes'] ?? '') as String;
    final endereco = d['endereco'] as String;
    final tema = Theme.of(context).textTheme;

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
                  child: Text(d['cliente'] as String,
                      style: tema.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Chip(label: Text(_rotulos[status] ?? status)),
              ],
            ),
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
                if (!widget.admin && status == 'pendente')
                  FilledButton(
                    onPressed: () =>
                        _rpc('aceitar_entrega', d['id'] as String),
                    child: const Text('Aceitar'),
                  ),
                if (!widget.admin && status == 'aceita')
                  FilledButton(
                    onPressed: () =>
                        _rpc('concluir_entrega', d['id'] as String),
                    child: const Text('Marcar como concluída'),
                  ),
                if (widget.admin &&
                    (status == 'pendente' || status == 'aceita'))
                  TextButton(
                    onPressed: () => _cancelar(d['id'] as String),
                    child: const Text('Cancelar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    final lista = _visiveis;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final f in const {
                'abertas': 'Abertas',
                'concluidas': 'Concluídas',
                'canceladas': 'Canceladas',
              }.entries)
                ChoiceChip(
                  label: Text(f.value),
                  selected: _filtro == f.key,
                  onSelected: (_) => setState(() => _filtro = f.key),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: reload,
            child: lista.isEmpty
                ? ListView(children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Nenhuma entrega aqui.')),
                    ),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: lista.length,
                    itemBuilder: (_, i) => _cartao(lista[i]),
                  ),
          ),
        ),
      ],
    );
  }
}
