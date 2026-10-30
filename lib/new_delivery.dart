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
  List<Map<String, dynamic>> _produtos = [];
  final Map<String, int> _qtd = {};
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarProdutos();
  }

  Future<void> _carregarProdutos() async {
    try {
      final data =
          await sb.from('products').select().eq('ativo', true).order('nome');
      if (!mounted) return;
      setState(() {
        _produtos = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      aviso(context, 'Erro ao carregar produtos: $e');
    }
  }

  double get _total => _produtos.fold(
      0.0,
      (s, p) =>
          s + (p['preco'] as num).toDouble() * (_qtd[p['id'] as String] ?? 0));

  void _mudar(String id, int delta) {
    setState(() {
      final novo = (_qtd[id] ?? 0) + delta;
      _qtd[id] = novo < 0 ? 0 : novo;
    });
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    if (_entrega == null) {
      aviso(context, 'Escolha o dia e o horário da entrega.');
      return;
    }
    final itens = _qtd.entries
        .where((e) => e.value > 0)
        .map((e) => {'product_id': e.key, 'qtd': e.value})
        .toList();
    if (itens.isEmpty) {
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
        'p_itens': itens,
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

  @override
  Widget build(BuildContext context) {
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
                  Text('Produtos',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_produtos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                          'Nenhum produto ativo. Cadastre na aba Produtos.'),
                    ),
                  for (final p in _produtos)
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
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text('Total: ${brl.format(_total)}',
                    style: Theme.of(context).textTheme.titleLarge),
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
