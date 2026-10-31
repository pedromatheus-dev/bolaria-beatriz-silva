import 'package:flutter/material.dart';

import 'core.dart';
import 'deliveries.dart';
import 'delivery_details.dart';
import 'new_delivery.dart';
import 'people.dart';
import 'products.dart';
import 'update.dart';

Widget _botaoSair() => IconButton(
      tooltip: 'Sair',
      icon: const Icon(Icons.logout),
      onPressed: () => sb.auth.signOut(),
    );

/// Abre a entrega quando o app é aberto por um link (bolaria://entrega/<id>).
class LinkOuvinte extends StatefulWidget {
  final Widget child;
  const LinkOuvinte({super.key, required this.child});

  @override
  State<LinkOuvinte> createState() => _LinkOuvinteState();
}

class _LinkOuvinteState extends State<LinkOuvinte> {
  @override
  void initState() {
    super.initState();
    linkPendente.addListener(_abrir);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _abrir();
      verificarAtualizacao(context);
    });
  }

  @override
  void dispose() {
    linkPendente.removeListener(_abrir);
    super.dispose();
  }

  void _abrir() {
    final id = linkPendente.value;
    if (id == null || !mounted) return;
    linkPendente.value = null;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeliveryDetailsPage(id: id)),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  static const _titulos = ['Entregas', 'Produtos', 'Entregador', 'Meus dados'];
  int _aba = 0;
  final _lista = GlobalKey<DeliveriesListState>();

  Future<void> _nova() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NewDeliveryPage()),
    );
    if (ok == true) _lista.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return LinkOuvinte(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titulos[_aba]),
          actions: [_botaoSair()],
        ),
        body: IndexedStack(
          index: _aba,
          children: [
            Scaffold(
              body: DeliveriesList(key: _lista, admin: true),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: _nova,
                icon: const Icon(Icons.add),
                label: const Text('Nova entrega'),
              ),
            ),
            const ProductsPage(),
            const PerfilTab(entregador: true),
            const PerfilTab(entregador: false),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _aba,
          onDestinationSelected: (i) => setState(() => _aba = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.local_shipping), label: 'Entregas'),
            NavigationDestination(icon: Icon(Icons.cake), label: 'Produtos'),
            NavigationDestination(icon: Icon(Icons.two_wheeler), label: 'Entregador'),
            NavigationDestination(icon: Icon(Icons.person), label: 'Meus dados'),
          ],
        ),
      ),
    );
  }
}

class CourierHome extends StatelessWidget {
  const CourierHome({super.key});

  @override
  Widget build(BuildContext context) {
    return LinkOuvinte(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Minhas entregas'),
          actions: [_botaoSair()],
        ),
        body: const DeliveriesList(admin: false),
      ),
    );
  }
}
