import 'package:flutter/material.dart';

import 'core.dart';

/// Criar ou editar um combo: nome, produtos (com quantidades) e preço final.
class ComboFormPage extends StatefulWidget {
  final Map<String, dynamic>? combo;
  const ComboFormPage({super.key, this.combo});

  @override
  State<ComboFormPage> createState() => _ComboFormPageState();
}

class _ComboFormPageState extends State<ComboFormPage> {
  final _nome = TextEditingController();
  final _preco = TextEditingController();
  List<Map<String, dynamic>> _produtos = [];
  final Map<String, int> _qtd = {};
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final c = widget.combo;
    if (c != null) {
      _nome.text = c['nome'] as String;
      _preco.text = num2(c['preco']).toStringAsFixed(2).replaceAll('.', ',');
      for (final i in List<Map<String, dynamic>>.from(c['combo_items'] ?? [])) {
        _qtd[i['product_id'] as String] = (i['quantidade'] as num).toInt();
      }
    }
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final p = await sb.from('products').select().eq('ativo', true).order('nome');
      if (!mounted) return;
      setState(() {
        _produtos = List<Map<String, dynamic>>.from(p);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      aviso(context, 'Erro ao carregar produtos: $e');
    }
  }

  double? get _valor => double.tryParse(_preco.text.trim().replaceAll(',', '.'));

  double get _avulso => _produtos.fold<double>(
      0, (s, p) => s + num2(p['preco']) * (_qtd[p['id'] as String] ?? 0));

  int get _unidades => _qtd.values.fold(0, (s, v) => s + v);

  void _mudar(String id, int delta) {
    setState(() {
      final n = (_qtd[id] ?? 0) + delta;
      _qtd[id] = n < 0 ? 0 : n;
    });
  }

  Future<void> _salvar() async {
    final valor = _valor;
    if (_nome.text.trim().isEmpty) {
      aviso(context, 'Dê um nome ao combo.');
      return;
    }
    if (valor == null || valor < 0) {
      aviso(context, 'Informe o preço final do combo.');
      return;
    }
    if (_unidades < 2) {
      aviso(context, 'Escolha pelo menos 2 itens para o combo.');
      return;
    }
    setState(() => _salvando = true);
    try {
      await sb.rpc('salvar_combo', params: {
        'p_id': widget.combo?['id'],
        'p_nome': _nome.text.trim(),
        'p_preco': valor,
        'p_itens': _qtd.entries
            .where((e) => e.value > 0)
            .map((e) => {'product_id': e.key, 'qtd': e.value})
            .toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      aviso(context, 'Erro ao salvar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final valor = _valor;
    final economia = valor == null ? null : _avulso - valor;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.combo == null ? 'Novo combo' : 'Editar combo')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nome,
                  decoration: const InputDecoration(
                      labelText: 'Nome do combo (ex.: Combo 1)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _preco,
                  onChanged: (_) => setState(() {}),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Preço final do combo (R\$)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Text('Produtos do combo',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_produtos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Cadastre os produtos antes de criar o combo.'),
                  ),
                for (final p in _produtos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p['nome'] as String),
                    subtitle: Text(brl.format(num2(p['preco']))),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _mudar(p['id'] as String, -1),
                        ),
                        SizedBox(
                          width: 28,
                          child: Text('${_qtd[p['id'] as String] ?? 0}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle),
                          onPressed: () => _mudar(p['id'] as String, 1),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Itens: $_unidades'),
                        Text('Preço avulso: ${brl.format(_avulso)}'),
                        if (economia != null)
                          Text(
                            economia >= 0
                                ? 'Desconto do combo: ${brl.format(economia)}'
                                : 'Atenção: o combo está mais caro que os itens avulsos '
                                    '(não será agrupado automaticamente).',
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: Text(_salvando ? 'Salvando...' : 'Salvar combo'),
          ),
        ),
      ),
    );
  }
}
