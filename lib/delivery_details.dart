import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core.dart';

Future<Map<String, dynamic>?> carregarEntrega(String id) => sb
    .from('deliveries')
    .select('*, delivery_items(*)')
    .eq('id', id)
    .maybeSingle();

String linhaItem(Map<String, dynamic> i) {
  final sub = brl.format((i['preco_unit'] as num) * (i['quantidade'] as num));
  final combo = i['tipo'] == 'combo';
  final desc = (i['descricao'] ?? '') as String;
  final marca = combo ? '🎁 ' : '';
  final comp = (combo && desc.isNotEmpty) ? ' ($desc)' : '';
  return '• ${i['quantidade']}x $marca${i['nome']}$comp — $sub';
}

/// Texto enviado ao entregador pelo WhatsApp (com o link que abre o app).
String mensagemEntregador(Map<String, dynamic> d) {
  final itens = List<Map<String, dynamic>>.from(d['delivery_items'] ?? []);
  final tel = (d['telefone'] ?? '') as String;
  final obs = (d['observacoes'] ?? '') as String;
  final link = linkEntrega(d['id'] as String);
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
    b.writeln(linhaItem(i));
  }
  b
    ..writeln()
    ..writeln('🧾 *Produtos:* ${brl.format(num2(d['subtotal']))}')
    ..writeln('🛵 *Taxa de entrega:* ${brl.format(num2(d['taxa_entrega']))}')
    ..writeln('💰 *Total:* ${brl.format(num2(d['total']))}');
  if (obs.isNotEmpty) b.writeln('🗒️ *Obs:* $obs');
  if (link.isNotEmpty) {
    b
      ..writeln()
      ..writeln('🔗 *Ver detalhes e aceitar no app:*')
      ..writeln(link);
  }
  return b.toString().trim();
}

/// Dona: abre o WhatsApp do entregador cadastrado com a entrega pronta.
Future<void> encaminharEntrega(BuildContext c, String id) async {
  try {
    final d = await carregarEntrega(id);
    final ent = await sb
        .from('profiles')
        .select()
        .eq('papel', 'courier')
        .limit(1)
        .maybeSingle();
    final tel = (ent?['telefone'] ?? '') as String;
    if (d == null) return;
    if (tel.isEmpty) {
      if (c.mounted) {
        aviso(c, 'Cadastre o telefone do entregador na aba Entregador.');
      }
      return;
    }
    if (!c.mounted) return;
    await abrirWhatsApp(c, tel, mensagemEntregador(d));
    await sb.from('delivery_events').insert({
      'delivery_id': id,
      'tipo': 'encaminhada',
      'descricao': 'Encaminhada ao entregador pelo WhatsApp',
    });
  } catch (e) {
    if (c.mounted) aviso(c, 'Erro: $e');
  }
}

/// Entregador: avisa a dona pelo WhatsApp que recebeu e fará a entrega.
Future<void> avisarDona(BuildContext c, String id) async {
  try {
    final d = await carregarEntrega(id);
    final dona = await sb
        .from('profiles')
        .select()
        .eq('papel', 'admin')
        .limit(1)
        .maybeSingle();
    final tel = (dona?['telefone'] ?? '') as String;
    if (d == null) return;
    if (tel.isEmpty) {
      if (c.mounted) aviso(c, 'A dona ainda não cadastrou o telefone dela.');
      return;
    }
    final nome = ((dona?['nome'] ?? '') as String).trim().split(' ').first;
    final texto = '''Olá${nome.isEmpty ? '' : ', $nome'}! 👋
📦 Recebi a entrega *#${d['numero']}* (${d['cliente']}) e *aceitei* ✅
🗓️ Vou fazer a entrega em ${dh(d['scheduled_at'])}.
📍 ${d['endereco']}''';
    if (c.mounted) await abrirWhatsApp(c, tel, texto);
  } catch (e) {
    if (c.mounted) aviso(c, 'Erro: $e');
  }
}

/// Entregador: aceita a entrega e oferece avisar a dona.
Future<bool> aceitarEntrega(BuildContext c, String id) async {
  try {
    await sb.rpc('aceitar_entrega', params: {'p_id': id});
  } catch (e) {
    if (c.mounted) aviso(c, 'Erro: $e');
    return false;
  }
  if (!c.mounted) return true;
  final avisar = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: const Text('Entrega aceita!'),
      content: const Text('Quer avisar a dona pelo WhatsApp que você vai fazer a entrega?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Agora não')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Avisar a dona')),
      ],
    ),
  );
  if (avisar == true && c.mounted) await avisarDona(c, id);
  return true;
}

const _iconesEvento = {
  'solicitada': Icons.shopping_bag,
  'cadastrada': Icons.edit_note,
  'encaminhada': Icons.send,
  'aceita': Icons.thumb_up,
  'concluida': Icons.check_circle,
  'cancelada': Icons.cancel,
};

class DeliveryDetailsPage extends StatefulWidget {
  final String id;
  const DeliveryDetailsPage({super.key, required this.id});

  @override
  State<DeliveryDetailsPage> createState() => _DeliveryDetailsPageState();
}

class _DeliveryDetailsPageState extends State<DeliveryDetailsPage> {
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _eventos = [];
  bool _admin = false;
  bool _carregando = true;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final perfil = await sb
          .from('profiles')
          .select('papel')
          .eq('id', sb.auth.currentUser!.id)
          .maybeSingle();
      final d = await carregarEntrega(widget.id);
      final ev = await sb
          .from('delivery_events')
          .select()
          .eq('delivery_id', widget.id)
          .order('ocorrido_em', ascending: true);
      if (!mounted) return;
      setState(() {
        _admin = perfil?['papel'] == 'admin';
        _d = d;
        _eventos = List<Map<String, dynamic>>.from(ev);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      aviso(context, 'Erro ao carregar: $e');
    }
  }

  Future<void> _executar(Future<void> Function() acao) async {
    setState(() => _ocupado = true);
    try {
      await acao();
      await _carregar();
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _concluir() async {
    try {
      await sb.rpc('concluir_entrega', params: {'p_id': widget.id});
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  Widget _secao(String titulo, List<Widget> filhos) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...filhos,
            ],
          ),
        ),
      );

  Widget _linhaValor(String r, double v, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(r,
                style: TextStyle(
                    fontWeight: forte ? FontWeight.bold : FontWeight.normal)),
            Text(brl.format(v),
                style: TextStyle(
                    fontWeight: forte ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: Text(d == null ? 'Entrega' : 'Entrega #${d['numero']}')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? const Center(child: Text('Entrega não encontrada.'))
              : _corpo(d),
    );
  }

  Widget _corpo(Map<String, dynamic> d) {
    final itens = List<Map<String, dynamic>>.from(d['delivery_items'] ?? []);
    final status = d['status'] as String;
    final tel = (d['telefone'] ?? '') as String;
    final obs = (d['observacoes'] ?? '') as String;
    final endereco = d['endereco'] as String;
    final aberta = status == 'pendente' || status == 'aceita';

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _secao('Entrega', [
          Row(
            children: [
              Expanded(
                child: Text(d['cliente'] as String,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Chip(label: Text(rotulosStatus[status] ?? status)),
            ],
          ),
          Text('Entregar em: ${dh(d['scheduled_at'])}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Solicitado em: ${dh(d['requested_at'])}'),
          const SizedBox(height: 4),
          Text(endereco),
          if (tel.isNotEmpty) Text('Tel: $tel'),
          if (obs.isNotEmpty) Text('Obs: $obs'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
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
          ]),
        ]),
        _secao('Pedido', [
          for (final i in itens)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${i['quantidade']}x ${i['tipo'] == 'combo' ? '🎁 ' : ''}${i['nome']}'),
                        if (i['tipo'] == 'combo' &&
                            ((i['descricao'] ?? '') as String).isNotEmpty)
                          Text(i['descricao'] as String,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(brl.format(
                      (i['preco_unit'] as num) * (i['quantidade'] as num))),
                ],
              ),
            ),
          const Divider(),
          _linhaValor('Produtos', num2(d['subtotal'])),
          _linhaValor('Taxa de entrega', num2(d['taxa_entrega'])),
          _linhaValor('Total', num2(d['total']), forte: true),
        ]),
        _secao('Histórico', [
          if (_eventos.isEmpty) const Text('Sem eventos registrados.'),
          for (final e in _eventos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_iconesEvento[e['tipo']] ?? Icons.circle,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((e['descricao'] ?? '') as String),
                        Text(dh(e['ocorrido_em']),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (_admin && aberta)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366)),
                icon: const Icon(Icons.send),
                label: const Text('Enviar ao entregador (WhatsApp)'),
                onPressed: _ocupado
                    ? null
                    : () => _executar(() => encaminharEntrega(context, widget.id)),
              ),
            if (!_admin && status == 'pendente')
              FilledButton(
                onPressed: _ocupado
                    ? null
                    : () => _executar(() async {
                          await aceitarEntrega(context, widget.id);
                        }),
                child: const Text('Aceitar entrega'),
              ),
            if (!_admin && status == 'aceita') ...[
              FilledButton.tonalIcon(
                icon: const Icon(Icons.chat),
                label: const Text('Avisar a dona (WhatsApp)'),
                onPressed: _ocupado ? null : () => avisarDona(context, widget.id),
              ),
              FilledButton(
                onPressed: _ocupado ? null : () => _executar(_concluir),
                child: const Text('Marcar como concluída'),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}
