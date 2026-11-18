import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'state/session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  Intl.defaultLocale = 'pt_BR';

  final session = Session();
  await session.restore();

  runApp(ChangeNotifierProvider.value(value: session, child: const SewWalletApp()));
}

class SewWalletApp extends StatelessWidget {
  const SewWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SewWallet',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => PhoneFrame(child: child!),
      home: Consumer<Session>(
        // Troca a chave ao entrar/sair para descartar o estado da sessão anterior.
        builder: (_, s, _) => s.isLoggedIn
            ? HomeShell(key: ValueKey(s.token))
            : const LoginScreen(),
      ),
    );
  }
}
