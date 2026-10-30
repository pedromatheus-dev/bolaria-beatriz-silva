import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core.dart';
import 'home.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (context, _) {
        final session = sb.auth.currentSession;
        if (session == null) return const LoginPage();
        return RoleRouter(key: ValueKey(session.user.id));
      },
    );
  }
}

/// Lê o papel do usuário (admin ou courier) e abre a tela certa.
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  late final Future<Map<String, dynamic>?> _perfil = sb
      .from('profiles')
      .select()
      .eq('id', sb.auth.currentUser!.id)
      .maybeSingle();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _perfil,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final papel = snap.data?['papel'];
        if (papel == 'admin') return const AdminHome();
        if (papel == 'courier') return const CourierHome();
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Seu usuário ainda não tem perfil configurado.\nFale com o administrador.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => sb.auth.signOut(),
                    child: const Text('Sair'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _entrando = false;

  Future<void> _entrar() async {
    setState(() => _entrando = true);
    try {
      await sb.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _senha.text,
      );
    } on AuthException {
      if (mounted) aviso(context, 'E-mail ou senha incorretos.');
    } catch (_) {
      if (mounted) aviso(context, 'Não foi possível entrar. Verifique a internet.');
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cake, size: 64),
                  const SizedBox(height: 8),
                  Text('Bolaria Entregas',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'E-mail', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senha,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Senha', border: OutlineInputBorder()),
                    onSubmitted: (_) => _entrar(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _entrando ? null : _entrar,
                      child: Text(_entrando ? 'Entrando...' : 'Entrar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
