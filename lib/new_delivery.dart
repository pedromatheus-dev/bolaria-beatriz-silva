import 'package:flutter/material.dart';

import 'core.dart';

class NewDeliveryPage extends StatefulWidget {
  const NewDeliveryPage({super.key});

  @override
  State<NewDeliveryPage> createState() => _NewDeliveryPageState();
}

class _NewDeliveryPageState extends State<NewDeliveryPage> {
  final _form = GlobalKey<FormState>();
  final _cliente = TextEditingController();
  final _endereco = TextEditingController();
  final _telefone = TextEditingController();
  final _obs = TextEditingController();
  DateTime _solicitado = DateTime.now();
  DateTime? _entrega;
  List<Map<String, dynamic>> _todos = []; // todos os produtos (para preço)
  List<Map<String, dynamic>> _combos = []; // combos ativos, com itens
  final Map<String, int> _qtd = {};
  double _taxa = 2.0;
  bool _auto = true; // agrupar combos automaticamente
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final prods = await sb.from('products').select().order('nome');
      final combos = await sb
          .from('combos')
          .select('*, combo_items(product_id, quantidade)')
          .eq('ativo', true)
          .order('nome');
      final cfg =
          await sb.from('config').select().eq('chave', 'taxa_entrega').maybeSingle();
      if (!mounted) return;
      setState(() {
        _todos = List<Map<String, dynamic>>.from(prods);
        _combos = List<Map<String, dynamic>>.from(combos);
        _taxa = double.tryParse((cfg?['valor'] ?? '2') as String) ?? 2.0;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      aviso(context, 'Erro ao carregar: $e');
    }
  }

  // ---------- preços e combos ----------
  Map<String, Map<String, dynamic>> get _porId =>
      {for (final p in _todos) p['id'] as String: p};

  double _preco(String id) => num2(_porId[id]?['preco']);

  List<Map<String, dynamic>> _itensDe(Map<String, dynamic> c) =>
      List<Map<String, dynamic>>.from(c['combo_items'] ?? []);

  double _somaAvulsa(Map<String, dynamic> c) => _itensDe(c).fold<double>(
      0, (s, i) => s + _preco(i['product_id'] as String) * (i['quantidade'] as num));

  double _economia(Map<String, dynamic> c) => _somaAvulsa(c) - num2(c['preco']);

  String _descCombo(Map<String, dynamic> c) => _itensDe(c)
      .map((i) => '${i['quantidade']}x ${_porId[i['product_id']]?['nome'] ?? '?'}')
      .join(' + ');

  /// Junta os produtos escolhidos em combos (o de maior economia primeiro)
  /// e devolve o que sobra como produtos avulsos.
  ({Map<String, int> combos, Map<String, int> resto}) _agrupar() {
    final resto = Map<String, int>.from(_qtd)..removeWhere((_, v) => v <= 0);
    final aplicados = <String, int>{};
    if (_auto) {
      final ordem = _combos.where((c) => _economia(c) >= 0).toList()
        ..sort((a, b) => _economia(b).compareTo(_economia(a)));
      for (final c in ordem) {
        final itens = _itensDe(c);
        if (itens.isEmpty) continue;
        var k = 1 << 30;
        for (final i in itens) {
          final n = (i['quantidade'] as num).toInt();
          final q = (resto[i['product_id']] ?? 0) ~/ n;
          if (q < k) k = q;
        }
        if (k > 0) {
          for (final i in itens) {
            final pid = i['product_id'] as String;
            resto[pid] = resto[pid]! - k * (i['quantidade'] as num).toInt();
          }
          aplicados[c['id'] as String] = k;
        }
      }
    }
    resto.removeWhere((_, v) => v <= 0);
    return (combos: aplicados, resto: resto);
  }

  double _subtotal(({Map<String, int> combos, Map<String, int> resto}) g) {
    var s = 0.0;
    g.resto.forEach((id, q) => s += _preco(id) * q);
    for (final c in _combos) {
      s += num2(c['preco']) * (g.combos[c['id']] ?? 0);
    }
    return s;
  }

  void _mudar(String id, int delta) {
    setState(() {
      final novo = (_qtd[id] ?? 0) + delta;
      _qtd[id] = novo < 0 ? 0 : novo;
    });
  }

  void _addCombo(Map<String, dynamic> c) {
    setState(() {
      for (final i in _itensDe(c)) {
        final pid = i['product_id'] as String;
        _qtd[pid] = (_qtd[pid] ?? 0) + (i['quantidade'] as num).toInt();
      }
    });
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    if (_entrega == null) {
      aviso(context, 'Escolha o dia e o horário da entrega.');
      return;
    }
    final g = _agrupar();
    if (g.combos.isEmpty && g.resto.isEmpty) {
      aviso(context, 'Adicione ao menos um produto.');
      return;
    }
    setState(() => _salvando = true);
    try {
      await sb.rpc('criar_entrega', params: {
        'p_cliente': _cliente.text.trim(),
        'p_endereco': _endereco.text.trim(),
        'p_telefone': _telefone.text.trim(),
        'p_obs': _obs.text.trim(),
        'p_requested_at': _solicitado.toUtc().toIso8601String(),
        'p_scheduled_at': _entrega!.toUtc().toIso8601String(),
        'p_itens': g.resto.entries
            .map((e) => {'product_id': e.key, 'qtd': e.value})
            .toList(),
        'p_combos': g.combos.entries
            .map((e) => {'combo_id': e.key, 'qtd': e.value})
            .toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      aviso(context, 'Erro ao salvar: $e');
    }
  }

  String? _obrigatorio(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

  Widget _resumoPedido(({Map<String, int> combos, Map<String, int> resto}) g) {
    final linhas = <Widget>[];
    for (final c in _combos) {
      final k = g.combos[c['id']] ?? 0;
      if (k == 0) continue;
      linhas.add(ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.card_giftcard, color: Colors.deepOrange),
        title: Text('${k}x ${c['nome']}'),
        subtitle: Text(
            'Combo identificado automaticamente • ${_descCombo(c)}\nEconomia: ${brl.format(_economia(c) * k)}'),
        isThreeLine: true,
        trailing: Text(brl.format(num2(c['preco']) * k)),
      ));
    }
    g.resto.forEach((id, q) {
      linhas.add(ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text('${q}x ${_porId[id]?['nome'] ?? ''}'),
        trailing: Text(brl.format(_preco(id) * q)),
      ));
    });
    if (linhas.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumo do pedido',
                style: Theme.of(context).textTheme.titleMedium),
            ...linhas,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _agrupar();
    final sub = _subtotal(g);
    final ativos = _todos.where((p) => p['ativo'] == true).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Nova entrega')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _cliente,
                    decoration: const InputDecoration(
                        labelText: 'Cliente', border: OutlineInputBorder()),
                    validator: _obrigatorio,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _endereco,
                    decoration: const InputDecoration(
                        labelText: 'Endereço', border: OutlineInputBorder()),
                    validator: _obrigatorio,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _telefone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Telefone', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _obs,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Observações', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_note),
                    title: const Text('Data da solicitação'),
                    subtitle: Text(dh(_solicitado.toUtc().toIso8601String())),
                    onTap: () async {
                      final d = await escolherDataHora(context, _solicitado);
                      if (d != null) setState(() => _solicitado = d);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('Dia e horário da entrega'),
                    subtitle: Text(_entrega == null
                        ? 'Toque para escolher'
                        : dh(_entrega!.toUtc().toIso8601String())),
                    onTap: () async {
                      final d = await escolherDataHora(
                          context, _entrega ?? DateTime.now());
                      if (d != null) setState(() => _entrega = d);
                    },
                  ),
                  const Divider(),
                  if (_combos.isNotEmpty) ...[
                    Text('Adicionar combo',
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final c in _combos)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.card_giftcard),
                        title: Text(c['nome'] as String),
                        subtitle: Text(
                            '${_descCombo(c)} • ${brl.format(num2(c['preco']))}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle),
                          onPressed: () => _addCombo(c),
                        ),
                      ),
                    const Divider(),
                  ],
                  Text('Produtos',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (ativos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                          'Nenhum produto ativo. Cadastre na aba Produtos.'),
                    ),
                  for (final p in ativos)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p['nome'] as String),
                      subtitle: Text(brl.format(p['preco'] as num)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _mudar(p['id'] as String, -1),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${_qtd[p['id'] as String] ?? 0}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle),
                            onPressed: () => _mudar(p['id'] as String, 1),
                          ),
                        ],
                      ),
                    ),
                  if (_combos.isNotEmpty)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Agrupar combos automaticamente'),
                      value: _auto,
                      onChanged: (v) => setState(() => _auto = v),
                    ),
                  _resumoPedido(g),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        'Produtos ${brl.format(sub)} + Taxa ${brl.format(_taxa)}',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text('Total: ${brl.format(sub + _taxa)}',
                        style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _salvando ? null : _salvar,
                child: Text(_salvando ? 'Salvando...' : 'Salvar entrega'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
