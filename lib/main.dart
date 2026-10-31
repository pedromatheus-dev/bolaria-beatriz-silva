import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';
import 'core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const BolariaApp());
  _iniciarLinks();
}

void _tratarLink(Uri? uri) {
  if (uri == null) return;
  if (uri.scheme == 'bolaria' &&
      uri.host == 'entrega' &&
      uri.pathSegments.isNotEmpty) {
    linkPendente.value = uri.pathSegments.first;
  }
}

Future<void> _iniciarLinks() async {
  try {
    final links = AppLinks();
    _tratarLink(await links.getInitialLink());
    links.uriLinkStream.listen(_tratarLink);
  } catch (_) {}
}

class BolariaApp extends StatelessWidget {
  const BolariaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bolaria Beatriz',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
      ),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Qualquer rota (inclusive a de um link externo) cai na mesma tela inicial.
      onGenerateInitialRoutes: (_) =>
          [MaterialPageRoute(builder: (_) => const AuthGate())],
      onGenerateRoute: (_) =>
          MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }
}
