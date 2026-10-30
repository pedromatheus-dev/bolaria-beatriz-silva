import 'package:flutter/material.dart';

import 'core.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  List<Map<String, dynamic>> _itens = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final data = await sb.from('products').select().order('nome');
      if (!mounted) return;
      setState(() {
        _itens = List<Map<String, dynamic>>.from(data);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      aviso(context, 'Erro ao carregar produtos: $e');
    }
  }

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

  Future<void> _alternar(Map<String, dynamic> p, bool ativo) async {
    try {
      await sb
          .from('products')
          .update({'ativo': ativo}).eq('id', p['id'] as String);
      await _carregar();
    } catch (e) {
      if (mounted) aviso(context, 'Erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: _itens.isEmpty
                  ? ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('Nenhum produto cadastrado.')),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: _itens.length,
                      itemBuilder: (_, i) {
                        final p = _itens[i];
                        final ativo = p['ativo'] as bool;
                        return ListTile(
                          title: Text(p['nome'] as String,
                              style: TextStyle(
                                  color: ativo ? null : Colors.grey)),
                          subtitle: Text(brl.format(p['preco'] as num)),
                          onTap: () => _editar(p),
                          trailing: Switch(
                            value: ativo,
                            onChanged: (v) => _alternar(p, v),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Novo produto'),
      ),
    );
  }
}
