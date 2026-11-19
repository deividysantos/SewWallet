import 'package:flutter/material.dart';

import '../state/notification_reader.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Configuração da leitura das notificações dos bancos (Android): permissão, apps lidos,
/// fila de envio e as últimas notificações capturadas.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()));

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> with WidgetsBindingObserver {
  bool _loading = true;
  bool _granted = false;
  bool _enabled = false;
  Set<String> _apps = {};
  Map<String, String> _seen = {};
  int _queue = 0;
  List<CapturedNotification> _log = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Volta das configurações do Android: confere de novo a permissão.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (!NotificationReader.supported) {
      setState(() => _loading = false);
      return;
    }
    final r = await Future.wait([
      NotificationReader.isGranted(),
      NotificationReader.enabled(),
      NotificationReader.apps(),
      NotificationReader.seenApps(),
      NotificationReader.queueSize(),
      NotificationReader.log(),
    ]);
    if (!mounted) return;
    setState(() {
      _granted = r[0] as bool;
      _enabled = r[1] as bool;
      _apps = r[2] as Set<String>;
      _seen = r[3] as Map<String, String>;
      _queue = r[4] as int;
      _log = r[5] as List<CapturedNotification>;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool v) async {
    await NotificationReader.setEnabled(v);
    // O serviço nativo só lê o que está salvo: grava a lista (na primeira vez, os bancos conhecidos).
    await NotificationReader.setApps(_apps);
    setState(() => _enabled = v);
  }

  Future<void> _toggleApp(String pkg, bool on) async {
    final next = {..._apps};
    on ? next.add(pkg) : next.remove(pkg);
    await NotificationReader.setApps(next);
    setState(() => _apps = next);
  }

  Future<void> _flush() async {
    setState(() => _sending = true);
    final sent = await NotificationReader.flush();
    await _load();
    if (!mounted) return;
    setState(() => _sending = false);
    showSnack(context, sent == 0 ? 'Nada enviado (fila vazia ou sem conexão)' : '$sent enviada(s)');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!NotificationReader.supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notificações dos bancos')),
        body: const EmptyView(
          icon: Icons.phone_android,
          message: 'A leitura de notificações funciona só no app Android (o celular lê as notificações dos bancos).',
        ),
      );
    }
    final names = {...knownBankApps, ..._seen};
    final ordered = names.keys.toList()
      ..sort((a, b) {
        final sel = (_apps.contains(b) ? 1 : 0) - (_apps.contains(a) ? 1 : 0);
        return sel != 0 ? sel : names[a]!.toLowerCase().compareTo(names[b]!.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Notificações dos bancos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'O SewWallet lê as notificações dos apps marcados abaixo. Cada uma vai para o servidor, '
                      'onde uma IA entende o valor, a conta ou o cartão e a categoria: se o lançamento já '
                      'existe e está pendente, ele é marcado como pago; se não existe, vira uma sugestão.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: Icon(
                        _granted ? Icons.verified_outlined : Icons.lock_outline,
                        color: _granted ? FinanceColors.of(context).income : theme.colorScheme.error,
                      ),
                      title: Text(_granted ? 'Acesso às notificações liberado' : 'Acesso às notificações bloqueado'),
                      subtitle: Text(
                        _granted
                            ? 'Tudo certo.'
                            : 'Toque para abrir o Android e ligar o SewWallet em "Acesso a notificações".',
                      ),
                      onTap: _granted ? null : NotificationReader.openSettings,
                      trailing: _granted ? null : const Icon(Icons.open_in_new),
                    ),
                  ),
                  if (!_granted)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                        'O Android não deixa ligar? Como o app não veio da Play Store, abra "Informações do app", '
                        'toque em ⋮ e em "Permitir configurações restritas", e tente de novo.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: NotificationReader.openAppDetails,
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('Informações do app'),
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    key: const ValueKey('notifEnabled'),
                    value: _enabled,
                    onChanged: _setEnabled,
                    title: const Text('Ler notificações dos bancos'),
                    subtitle: const Text(
                      'Para não perder notificações com o app fechado, tire o SewWallet da economia de bateria '
                      '(Informações do app → Bateria → Sem restrições).',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.outbox_outlined),
                    title: Text(_queue == 0 ? 'Nada esperando envio' : '$_queue esperando envio'),
                    subtitle: const Text('Sem conexão com o servidor, ficam guardadas e vão depois'),
                    trailing: _queue == 0
                        ? null
                        : (_sending
                              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : TextButton(onPressed: _flush, child: const Text('Enviar'))),
                  ),
                  _section(theme, 'Apps lidos'),
                  for (final pkg in ordered)
                    CheckboxListTile(
                      value: _apps.contains(pkg),
                      onChanged: (v) => _toggleApp(pkg, v ?? false),
                      title: Text(names[pkg]!),
                      subtitle: Text(
                        knownBankApps.containsKey(pkg) && !_seen.containsKey(pkg) ? '$pkg · banco conhecido' : pkg,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Outros apps aparecem aqui depois de mandarem uma notificação com valor em R\$.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  _section(theme, 'Últimas enviadas'),
                  if (_log.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Nenhuma ainda.', style: theme.textTheme.bodySmall),
                    ),
                  for (final n in _log)
                    ListTile(
                      dense: true,
                      title: Text('${n.appName}${n.title == null ? '' : ' · ${n.title}'}'),
                      subtitle: Text(n.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(n.result, style: theme.textTheme.labelSmall),
                          if (n.postedAt != null)
                            Text(
                              '${shortDate(n.postedAt!)} ${n.postedAt!.hour.toString().padLeft(2, '0')}:'
                              '${n.postedAt!.minute.toString().padLeft(2, '0')}',
                              style: theme.textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _section(ThemeData theme, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
  );
}
