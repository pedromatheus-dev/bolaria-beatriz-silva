import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'combo_form.dart';
import 'core.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _aba = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  List<Map<String, dynamic>> _produtos = [];
  List<Map<String, dynamic>> _combos = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _aba.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final p = await sb.from('products').select().order('nome');
      final c = await sb
          .from('combos')
          .select(
              '*, combo_items(product_id, quantidade, products(nome, preco))')
          .order('nome');
      if (!mounted) return;
      setState(() {
        _produtos = List<Map<String, dynamic>>.from(p);
        _combos = List<Map<String, dynamic>>.from(c);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      aviso(context, 'Erro ao carregar: $e');
    }
  }

  Future<bool> _confirmar(String titulo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    return ok == true;
  }

  // ---------- produtos ----------
  Future<void> _editar([Map<String, dynamic>? p]) async {
    final nome = TextEditingController(text: (p?['nome'] ?? '') as String);
    final preco = TextEditingController(
        text: p == null
            ? ''
            : (p['preco'] as num).toStringAsFixed(2).replaceAll('.', ','));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(p == null ? 'Novo produto' : 'Editar produto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nome,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: preco,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço (R\$)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final valor = double.tryParse(preco.text.trim().replaceAll(',', '.'));
    if (nome.text.trim().isEmpty || valor == null || valor < 0) {
      if (mounted) aviso(context, 'Informe um nome e um preço válidos.');
      return;
    }
    try {
      final dados = {'nome': nome.text.trim(), 'preco': valor};
      if (p == null) {
        await sb.from('products').insert(dados);
      } else {
        await sb.from('products').update(dados).eq('id', p['id'] as String);
      }
      await _carregar();
    } catch (e) {
      if (mounted) aviso(context, 'Erro ao salvar: $e');
    }
  }

  Future<void> _alternarProduto(Map<String, dynamic> p, bool ativo) async {
    try {
      await sb
          .from('products')
          .update({'ativo': ativo}).eq('id', p['id'] as String);
      await _carregar();
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  Future<void> _excluirProduto(Map<String, dynamic> p) async {
    if (!await _confirmar('Excluir "${p['nome']}"?')) return;
    try {
      await sb.from('products').delete().eq('id', p['id'] as String);
      await _carregar();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      aviso(
          context,
          e.code == '23503'
              ? 'Este produto faz parte de um combo. Edite ou exclua o combo antes.'
              : 'Erro: ${e.message}');
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  // ---------- combos ----------
  Future<void> _editarCombo([Map<String, dynamic>? c]) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ComboFormPage(combo: c)),
    );
    if (ok == true) _carregar();
  }

  Future<void> _alternarCombo(Map<String, dynamic> c, bool ativo) async {
    try {
      await sb
          .from('combos')
          .update({'ativo': ativo}).eq('id', c['id'] as String);
      await _carregar();
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  Future<void> _excluirCombo(Map<String, dynamic> c) async {
    if (!await _confirmar('Excluir o combo "${c['nome']}"?')) return;
    try {
      await sb.from('combos').delete().eq('id', c['id'] as String);
      await _carregar();
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  Widget _abaProdutos() {
    if (_produtos.isEmpty) {
      return ListView(children: const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('Nenhum produto cadastrado.')),
        ),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _produtos.length,
      itemBuilder: (_, i) {
        final p = _produtos[i];
        final ativo = p['ativo'] as bool;
        return ListTile(
          title: Text(p['nome'] as String,
              style: TextStyle(color: ativo ? null : Colors.grey)),
          subtitle: Text(brl.format(p['preco'] as num)),
          onTap: () => _editar(p),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: ativo, onChanged: (v) => _alternarProduto(p, v)),
              IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _excluirProduto(p),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _abaCombos() {
    if (_combos.isEmpty) {
      return ListView(children: const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(
              child: Text(
                  'Nenhum combo. Toque em "Novo combo" para criar.')),
        ),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _combos.length,
      itemBuilder: (_, i) {
        final c = _combos[i];
        final ativo = c['ativo'] as bool;
        final itens = List<Map<String, dynamic>>.from(c['combo_items'] ?? []);
        final desc = itens
            .map((x) => '${x['quantidade']}x ${x['products']?['nome'] ?? '?'}')
            .join(' + ');
        final avulso = itens.fold<double>(
            0, (s, x) => s + num2(x['products']?['preco']) * (x['quantidade'] as num));
        final eco = avulso - num2(c['preco']);
        return ListTile(
          isThreeLine: true,
          title: Text(c['nome'] as String,
              style: TextStyle(color: ativo ? null : Colors.grey)),
          subtitle: Text(
              '$desc\nCombo ${brl.format(num2(c['preco']))} • avulso ${brl.format(avulso)} • economia ${brl.format(eco)}'),
          onTap: () => _editarCombo(c),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: ativo, onChanged: (v) => _alternarCombo(c, v)),
              IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _excluirCombo(c),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final emCombos = _aba.index == 1;
    return Scaffold(
      appBar: TabBar(
        controller: _aba,
        tabs: const [Tab(text: 'Produtos'), Tab(text: 'Combos')],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: TabBarView(
                controller: _aba,
                children: [_abaProdutos(), _abaCombos()],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => emCombos ? _editarCombo() : _editar(),
        icon: const Icon(Icons.add),
        label: Text(emCombos ? 'Novo combo' : 'Novo produto'),
      ),
    );
  }
}
