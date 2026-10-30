import 'package:flutter/material.dart';

import 'core.dart';
import 'deliveries.dart';
import 'new_delivery.dart';
import 'products.dart';
import 'update.dart';

Widget _botaoSair() => IconButton(
      tooltip: 'Sair',
      icon: const Icon(Icons.logout),
      onPressed: () => sb.auth.signOut(),
    );

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _aba = 0;
  final _lista = GlobalKey<DeliveriesListState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => verificarAtualizacao(context));
  }

  Future<void> _nova() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NewDeliveryPage()),
    );
    if (ok == true) _lista.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_aba == 0 ? 'Entregas' : 'Produtos'),
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
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: (i) => setState(() => _aba = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_shipping), label: 'Entregas'),
          NavigationDestination(icon: Icon(Icons.cake), label: 'Produtos'),
        ],
      ),
    );
  }
}

class CourierHome extends StatefulWidget {
  const CourierHome({super.key});

  @override
  State<CourierHome> createState() => _CourierHomeState();
}

class _CourierHomeState extends State<CourierHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => verificarAtualizacao(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas entregas'),
        actions: [_botaoSair()],
      ),
      body: const DeliveriesList(admin: false),
    );
  }
}
