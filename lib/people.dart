import 'package:flutter/material.dart';

import 'core.dart';

/// Aba da dona para editar nome e telefone.
/// entregador: true  -> dados do entregador
/// entregador: false -> dados da própria dona (e a taxa de entrega)
class PerfilTab extends StatefulWidget {
  final bool entregador;
  const PerfilTab({super.key, required this.entregador});

  @override
  State<PerfilTab> createState() => _PerfilTabState();
}

class _PerfilTabState extends State<PerfilTab> {
  final _nome = TextEditingController();
  final _tel = TextEditingController();
  final _taxa = TextEditingController();
  Map<String, dynamic>? _p;
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      Map<String, dynamic>? p;
      if (widget.entregador) {
        p = await sb
            .from('profiles')
            .select()
            .eq('papel', 'courier')
            .limit(1)
            .maybeSingle();
      } else {
        p = await sb
            .from('profiles')
            .select()
            .eq('id', sb.auth.currentUser!.id)
            .maybeSingle();
        final cfg = await sb
            .from('config')
            .select()
            .eq('chave', 'taxa_entrega')
            .maybeSingle();
        final t = double.tryParse((cfg?['valor'] ?? '2') as String) ?? 2.0;
        _taxa.text = t.toStringAsFixed(2).replaceAll('.', ',');
      }
      if (!mounted) return;
      setState(() {
        _p = p;
        _nome.text = (p?['nome'] ?? '') as String;
        _tel.text = telParaExibir(p?['telefone'] as String?);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      aviso(context, 'Erro ao carregar: $e');
    }
  }

  Future<void> _salvar() async {
    final p = _p;
    if (p == null) return;
    if (_nome.text.trim().isEmpty) {
      aviso(context, 'Informe o nome.');
      return;
    }
    final whats = telParaWhats(_tel.text);
    if (whats.isNotEmpty && whats.length != 12 && whats.length != 13) {
      aviso(context, 'Telefone inválido. Use DDD + número (ex.: 88 99999-9999).');
      return;
    }
    double? taxa;
    if (!widget.entregador) {
      taxa = double.tryParse(_taxa.text.trim().replaceAll(',', '.'));
      if (taxa == null || taxa < 0) {
        aviso(context, 'Informe uma taxa de entrega válida.');
        return;
      }
    }
    setState(() => _salvando = true);
    try {
      final r = await sb
          .from('profiles')
          .update({'nome': _nome.text.trim(), 'telefone': whats})
          .eq('id', p['id'] as String)
          .select();
      if (r.isEmpty) throw 'Sem permissão para salvar (rode a migração v4).';
      if (taxa != null) {
        final c = await sb
            .from('config')
            .update({'valor': taxa.toStringAsFixed(2)})
            .eq('chave', 'taxa_entrega')
            .select();
        if (c.isEmpty) throw 'Não foi possível salvar a taxa (rode a migração v4).';
      }
      if (mounted) aviso(context, 'Dados salvos.');
    } catch (e) {
      if (mounted) aviso(context, 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_p == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.entregador
                ? 'Nenhum entregador cadastrado.\nCrie o usuário no Supabase (Authentication) e rode o criar_perfis.sql.'
                : 'Perfil não encontrado.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.entregador ? 'Dados do entregador' : 'Meus dados',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _nome,
          decoration: const InputDecoration(
              labelText: 'Nome', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tel,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
              labelText: 'Telefone com DDD (WhatsApp)',
              helperText: 'Ex.: 88 99999-9999 (o 55 é adicionado sozinho)',
              border: OutlineInputBorder()),
        ),
        if (!widget.entregador) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _taxa,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Taxa de entrega (R\$)',
                helperText: 'Vale para as próximas entregas cadastradas',
                border: OutlineInputBorder()),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          child: Text(_salvando ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }
}
