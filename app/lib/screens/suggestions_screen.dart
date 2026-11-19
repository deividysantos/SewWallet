import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger.dart';
import '../state/catalog.dart';
import '../state/notification_reader.dart';
import '../state/session.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'notification_settings_screen.dart';
import 'transaction_form.dart';

/// Sugestões de lançamento vindas das notificações dos bancos.
/// "Pendentes": criar o lançamento ou descartar. "Processadas": o que foi feito sozinho
/// (baixa, já existia, ignorada) ou decidido, com opção de desfazer.
class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SuggestionsScreen()));

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  List<SuggestionItem>? _pending;
  List<SuggestionItem>? _processed;
  bool _aiConfigured = true;
  String? _error;
  String? _busyId;

  late final Catalog _catalog;
  int _seenRevision = -1;

  @override
  void initState() {
    super.initState();
    _catalog = context.read<Catalog>();
    _seenRevision = _catalog.revision;
    _catalog.addListener(_onCatalog);
    _load(flush: true);
  }

  void _onCatalog() {
    if (_catalog.revision == _seenRevision) return;
    _seenRevision = _catalog.revision;
    _load();
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalog);
    super.dispose();
  }

  Future<void> _load({bool flush = false}) async {
    // Antes de listar, manda o que estava na fila do celular.
    // Sem esperar demais: a lista abre mesmo se o servidor estiver lento.
    if (flush) await NotificationReader.flush().timeout(const Duration(seconds: 8), onTimeout: () => 0);
    if (!mounted) return;
    final api = context.read<Session>().api;
    try {
      final r = await Future.wait([
        api.get('/suggestions'),
        api.get('/suggestions', query: {'view': 'processed'}),
      ]);
      List<SuggestionItem> items(dynamic j) => [
        for (final i in (j['items'] as List)) SuggestionItem.fromJson(i as Map<String, dynamic>),
      ];
      if (!mounted) return;
      setState(() {
        _pending = items(r[0]);
        _processed = items(r[1]);
        _aiConfigured = r[0]['aiConfigured'] as bool? ?? true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _act(SuggestionItem s, String action, String done) async {
    setState(() => _busyId = s.id);
    try {
      await context.read<Session>().api.post('/suggestions/${s.id}/$action');
      // Desfazer uma baixa muda saldos: recarrega tudo.
      await _catalog.refresh();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _create(SuggestionItem s) async {
    final saved = await TransactionForm.open(context, suggestion: s);
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sugestões'),
          actions: [
            IconButton(
              tooltip: 'Configurar leitura de notificações',
              onPressed: () => NotificationSettingsScreen.open(context),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: _pending == null || _pending!.isEmpty ? 'Pendentes' : 'Pendentes (${_pending!.length})'),
              const Tab(text: 'Processadas'),
            ],
          ),
        ),
        body: _error != null && _pending == null
            ? ErrorView(message: _error!, onRetry: _load)
            : _pending == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_pendingList(), _processedList()]),
      ),
    );
  }

  Widget _pendingList() {
    final items = _pending!;
    return RefreshIndicator(
      onRefresh: () => _load(flush: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (!_aiConfigured)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('A IA não está configurada no servidor (AI_API_KEY): as notificações ficam com erro.'),
            ),
          if (items.isEmpty)
            EmptyView(
              icon: Icons.mark_email_read_outlined,
              message: NotificationReader.supported
                  ? 'Nenhuma sugestão. Quando um banco mandar notificação de um lançamento que não está no app, '
                        'ele aparece aqui.'
                  : 'Nenhuma sugestão. As notificações são lidas pelo app Android.',
            ),
          for (final s in items)
            _SuggestionCard(
              s: s,
              busy: _busyId == s.id,
              actions: s.status == SuggestionStatus.error
                  ? [
                      TextButton(onPressed: () => _act(s, 'dismiss', 'Descartada'), child: const Text('Descartar')),
                      FilledButton.tonal(
                        onPressed: () => _act(s, 'retry', 'Notificação processada de novo'),
                        child: const Text('Tentar de novo'),
                      ),
                    ]
                  : [
                      TextButton(onPressed: () => _act(s, 'dismiss', 'Descartada'), child: const Text('Descartar')),
                      FilledButton(onPressed: () => _create(s), child: const Text('Criar lançamento')),
                    ],
            ),
        ],
      ),
    );
  }

  Widget _processedList() {
    final items = _processed!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (items.isEmpty) const EmptyView(icon: Icons.history, message: 'Nada processado nos últimos 30 dias.'),
          for (final s in items)
            _SuggestionCard(
              s: s,
              busy: _busyId == s.id,
              actions: [
                if (s.status != SuggestionStatus.accepted)
                  TextButton(
                    onPressed: () => _act(
                      s,
                      'undo',
                      s.status == SuggestionStatus.autoPaid
                          ? 'Baixa desfeita: o lançamento voltou a pendente'
                          : 'Voltou para as sugestões',
                    ),
                    child: Text(s.status == SuggestionStatus.autoPaid ? 'Desfazer baixa' : 'Voltar para sugestões'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.s, required this.busy, required this.actions});
  final SuggestionItem s;
  final bool busy;
  final List<Widget> actions;

  String _statusText() => switch (s.status) {
    SuggestionStatus.pending => s.reason ?? 'Não encontrado no app',
    SuggestionStatus.error => 'Erro: ${s.reason ?? 'não processada'}',
    SuggestionStatus.autoPaid => 'Baixa automática: ${s.transactionDescription ?? 'lançamento'} marcado como pago',
    SuggestionStatus.alreadyExists => 'Já existia: ${s.transactionDescription ?? 'lançamento'}',
    SuggestionStatus.ignored => 'Ignorada: ${s.reason ?? 'não é movimentação'}',
    SuggestionStatus.accepted =>
      'Lançamento criado${s.transactionDescription == null ? '' : ': ${s.transactionDescription}'}',
    SuggestionStatus.dismissed => 'Descartada',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FinanceColors.of(context);
    final catalog = context.watch<Catalog>();
    final where = s.cardId != null
        ? catalog.card(s.cardId)?.name
        : s.accountId != null
        ? catalog.account(s.accountId)?.name
        : null;
    final category = catalog.categories.where((c) => c.id == s.categoryId).firstOrNull;
    final color = s.type == TxType.income ? colors.income : colors.expense;
    final hasData = s.amount != null;
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: category != null
                      ? categoryIcon(category.icon)
                      : s.cardId != null
                      ? Icons.credit_card
                      : Icons.notifications_outlined,
                  color: category != null ? hexColor(category.color) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.description ?? s.title ?? s.appName ?? s.app,
                        style: theme.textTheme.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [
                          if (s.date != null) shortDate(s.date!),
                          ?where,
                          ?category?.name,
                          if (s.installments != null) '${s.installments}x',
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                ),
                if (hasData)
                  Text(
                    '${s.type == TxType.income ? '+' : '-'}${money(s.amount!)}',
                    style: SewFonts.mono(
                      theme.textTheme.bodyMedium,
                    ).copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${s.appName ?? s.app}${s.title == null ? '' : ' · ${s.title}'}\n${s.text}',
                style: theme.textTheme.bodySmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _statusText(),
              style: muted?.copyWith(color: s.status == SuggestionStatus.error ? theme.colorScheme.error : null),
            ),
            if (busy)
              const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
            else if (actions.isNotEmpty)
              OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}
