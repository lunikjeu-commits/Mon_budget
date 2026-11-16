import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ───────────────────────── Utilitaires ─────────────────────────

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

String _monthKey([DateTime? d]) {
  final n = d ?? DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

double _parse(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.')) ?? 0;

String _eur(double v) {
  final neg = v < -0.004;
  final parts = v.abs().toStringAsFixed(2).split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('\u202F');
    buf.write(digits[i]);
  }
  return '${neg ? '-' : ''}$buf,${parts[1]}\u00A0€';
}

String _num(double v) {
  if (v == 0) return '';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString().replaceAll('.', ',');
}

// ───────────────────────── Modèles ─────────────────────────

class Charge {
  Charge({required this.id, required this.name, required this.amount});
  final String id;
  String name;
  double amount;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'amount': amount};
  factory Charge.fromJson(Map<String, dynamic> j) => Charge(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: (j['amount'] as num).toDouble(),
      );
}

class Livret {
  Livret({
    required this.id,
    required this.name,
    required this.goal,
    required this.monthly,
    required this.saved,
    this.validatedMonth,
    this.validatedAmount = 0,
  });

  final String id;
  String name;
  double goal;
  double monthly;
  double saved;
  String? validatedMonth;
  double validatedAmount;

  double get remaining => (goal - saved) < 0 ? 0 : goal - saved;
  double get progress =>
      goal <= 0 ? 0 : (saved / goal).clamp(0.0, 1.0).toDouble();
  bool get goalReached => goal > 0 && saved >= goal;
  bool get validatedThisMonth => validatedMonth == _monthKey();

  /// Montant qui sera réellement versé ce mois-ci (plafonné à ce qui reste).
  double get nextPayment {
    if (goal <= 0) return monthly;
    return monthly < remaining ? monthly : remaining;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goal': goal,
        'monthly': monthly,
        'saved': saved,
        'validatedMonth': validatedMonth,
        'validatedAmount': validatedAmount,
      };

  factory Livret.fromJson(Map<String, dynamic> j) => Livret(
        id: j['id'] as String,
        name: j['name'] as String,
        goal: (j['goal'] as num).toDouble(),
        monthly: (j['monthly'] as num).toDouble(),
        saved: (j['saved'] as num).toDouble(),
        validatedMonth: j['validatedMonth'] as String?,
        validatedAmount: ((j['validatedAmount'] ?? 0) as num).toDouble(),
      );
}

// ───────────────────────── Stockage / état ─────────────────────────

class BudgetStore extends ChangeNotifier {
  BudgetStore._(this._prefs);

  static const _key = 'budget_data_v1';
  final SharedPreferences _prefs;

  double salary = 0;
  final List<Charge> charges = [];
  final List<Livret> livrets = [];
  ThemeMode themeMode = ThemeMode.system;

  static Future<BudgetStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final store = BudgetStore._(prefs);
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        store.salary = ((j['salary'] ?? 0) as num).toDouble();
        store.charges.addAll(((j['charges'] ?? []) as List)
            .map((e) => Charge.fromJson(e as Map<String, dynamic>)));
        store.livrets.addAll(((j['livrets'] ?? []) as List)
            .map((e) => Livret.fromJson(e as Map<String, dynamic>)));
        final t = (j['theme'] ?? 0) as int;
        store.themeMode = ThemeMode.values[t.clamp(0, 2)];
      } catch (_) {
        // Données corrompues : on repart de zéro.
      }
    }
    return store;
  }

  Future<void> _save() async {
    await _prefs.setString(
      _key,
      jsonEncode({
        'salary': salary,
        'charges': charges.map((e) => e.toJson()).toList(),
        'livrets': livrets.map((e) => e.toJson()).toList(),
        'theme': themeMode.index,
      }),
    );
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  // Calculs
  double get totalCharges => charges.fold(0.0, (s, c) => s + c.amount);

  double get totalSavedThisMonth => livrets
      .where((l) => l.validatedThisMonth)
      .fold(0.0, (s, l) => s + l.validatedAmount);

  double get plannedSavings => livrets
      .where((l) => !l.validatedThisMonth && !l.goalReached)
      .fold(0.0, (s, l) => s + l.nextPayment);

  double get remainingToSplit => salary - totalCharges - totalSavedThisMonth;

  // Salaire
  void setSalary(double v) {
    salary = v;
    _changed();
  }

  // Thème
  void setTheme(ThemeMode m) {
    themeMode = m;
    _changed();
  }

  // Charges
  void addCharge(String name, double amount) {
    charges.add(Charge(id: _newId(), name: name, amount: amount));
    _changed();
  }

  void updateCharge(Charge c, String name, double amount) {
    c.name = name;
    c.amount = amount;
    _changed();
  }

  void deleteCharge(Charge c) {
    charges.remove(c);
    _changed();
  }

  // Livrets
  void addLivret(String name, double goal, double monthly, double saved) {
    livrets.add(Livret(
        id: _newId(), name: name, goal: goal, monthly: monthly, saved: saved));
    _changed();
  }

  void updateLivret(
      Livret l, String name, double goal, double monthly, double saved) {
    l.name = name;
    l.goal = goal;
    l.monthly = monthly;
    l.saved = saved;
    _changed();
  }

  void deleteLivret(Livret l) {
    livrets.remove(l);
    _changed();
  }

  /// Retourne le montant versé (0 si rien n'a été fait).
  double validatePayment(Livret l) {
    if (l.validatedThisMonth) return 0;
    final amount = l.nextPayment;
    if (amount <= 0) return 0;
    l.saved += amount;
    l.validatedMonth = _monthKey();
    l.validatedAmount = amount;
    _changed();
    return amount;
  }

  void undoPayment(Livret l) {
    if (!l.validatedThisMonth) return;
    l.saved -= l.validatedAmount;
    if (l.saved < 0) l.saved = 0;
    l.validatedMonth = null;
    l.validatedAmount = 0;
    _changed();
  }
}

// ───────────────────────── Application ─────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await BudgetStore.load();
  runApp(BudgetApp(store: store));
}

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key, required this.store});
  final BudgetStore store;

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00796B),
      brightness: b,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: false,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'Mon budget',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: store.themeMode,
        home: HomePage(store: store),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});
  final BudgetStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  late final TextEditingController _salaryCtrl;

  BudgetStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _salaryCtrl = TextEditingController(text: _num(store.salary));
  }

  @override
  void dispose() {
    _salaryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_tab == 0 ? 'Mon budget' : 'Mes livrets'),
          actions: [
            IconButton(
              tooltip: dark ? 'Mode clair' : 'Mode sombre',
              icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              onPressed: () =>
                  store.setTheme(dark ? ThemeMode.light : ThemeMode.dark),
            ),
          ],
        ),
        body: _tab == 0 ? _budgetTab(context) : _livretsTab(context),
        floatingActionButton: _tab == 1
            ? FloatingActionButton.extended(
                onPressed: () => _showLivretSheet(context, store),
                icon: const Icon(Icons.add),
                label: const Text('Nouveau livret'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Budget'),
            NavigationDestination(
                icon: Icon(Icons.savings_outlined),
                selectedIcon: Icon(Icons.savings),
                label: 'Livrets'),
          ],
        ),
      ),
    );
  }

  // ───────── Onglet Budget ─────────

  Widget _budgetTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _ResteCard(store: store),
        const SizedBox(height: 16),
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _salaryCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              style: tt.titleLarge,
              decoration: const InputDecoration(
                labelText: 'Salaire mensuel net',
                suffixText: '€',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onChanged: (v) => store.setSalary(_parse(v)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text('Charges fixes', style: tt.titleLarge),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _showChargeSheet(context, store),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Total : ${_eur(store.totalCharges)}',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (store.charges.isEmpty)
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Aucune charge fixe pour le moment.\nAjoutez votre loyer, abonnements, assurances…',
                textAlign: TextAlign.center,
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          ...store.charges.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card.filled(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
                  title: Text(c.name, style: tt.titleMedium),
                  subtitle: Text(_eur(c.amount),
                      style: tt.bodyLarge?.copyWith(
                          color: cs.primary
, fontWeight: FontWeight.w600)),
                  onTap: () => _showChargeSheet(context, store, charge: c),
                  trailing: IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => store.deleteCharge(c),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ───────── Onglet Livrets ─────────

  Widget _livretsTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _ResteCard(store: store),
        const SizedBox(height: 16),
        if (store.livrets.isEmpty)
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.savings_outlined, size: 48, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Aucun livret.\nAppuyez sur « Nouveau livret » pour commencer.',
                    textAlign: TextAlign.center,
                    style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        else
          ...store.livrets.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _LivretCard(store: store, livret: l),
            ),
          ),
      ],
    );
  }
}

// ───────────────────────── Carte « reste à répartir » ─────────────────────────

class _ResteCard extends StatelessWidget {
  const _ResteCard({required this.store});
  final BudgetStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reste = store.remainingToSplit;
    final negative = reste < -0.004;
    final bg = negative ? cs.errorContainer : cs.primaryContainer;
    final fg = negative ? cs.onErrorContainer : cs.onPrimaryContainer;

    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: tt.bodyMedium?.copyWith(color: fg))),
              Text(value,
                  style: tt.bodyMedium
                      ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reste à répartir ce mois-ci',
                style: tt.titleMedium?.copyWith(color: fg)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_eur(reste),
                  style: tt.displaySmall
                      ?.copyWith(color: fg, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            Divider(color: fg.withAlpha(60), height: 1),
            const SizedBox(height: 8),
            line('Salaire', _eur(store.salary)),
            line('Charges fixes', '- ${_eur(store.totalCharges)}'),
            line('Versements validés', '- ${_eur(store.totalSavedThisMonth)}'),
            if (store.plannedSavings > 0)
              line('Versements encore prévus', _eur(store.plannedSavings)),
            if (negative) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: fg, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Vos dépenses dépassent votre salaire.',
                        style: tt.bodyMedium?.copyWith(color: fg)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Carte livret ─────────────────────────

class _LivretCard extends StatelessWidget {
  const _LivretCard({required this.store, required this.livret});
  final BudgetStore store;
  final Livret livret;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = livret;
    final pct = (l.progress * 100).toStringAsFixed(l.progress >= 1 ? 0 : 1);
    final monthsLeft = (l.monthly > 0 && l.remaining > 0)
        ? (l.remaining / l.monthly).ceil()
        : null;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.name,
                      style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      _showLivretSheet(context, store, livret: l);
                    } else {
                      _confirmDelete(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Modifier'))),
                    PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Supprimer'))),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: l.progress,
                      minHeight: 14,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('$pct %',
                          style: tt.titleMedium?.copyWith(
                              color: cs.primary, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (monthsLeft != null)
                        Text(
                            monthsLeft == 1
                                ? '≈ 1 mois restant'
                                : '≈ $monthsLeft mois restants',
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _Stat('Épargné', _eur(l.saved))),
                      Expanded(child: _Stat('Objectif', _eur(l.goal))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _Stat('Reste à mettre', _eur(l.remaining),
                              highlight: true)),
                      Expanded(
                          child: _Stat('Versement / mois', _eur(l.monthly))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _action(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context) {
    final l = livret;
    if (l.validatedThisMonth) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: null,
              icon: const Icon(Icons.check_circle),
              label: Text('${_eur(l.validatedAmount)} validés ce mois-ci'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => store.undoPayment(l),
              icon: const Icon(Icons.undo),
              label: const Text('Annuler le versement'),
            ),
          ),
        ],
      );
    }
    if (l.goalReached) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: null,
          icon: const Icon(Icons.emoji_events_outlined),
          label: const Text('Objectif atteint 🎉'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: l.nextPayment <= 0
            ? null
            : () {
                final amount = store.validatePayment(l);
                if (amount <= 0) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content: Text('${_eur(amount)} ajoutés à « ${l.name} »'),
                    action: SnackBarAction(
                        label: 'Annuler', onPressed: () => store.undoPayment(l)),
                  ));
              },
        icon: const Icon(Icons.add_task),
        label: Text(l.nextPayment > 0
            ? 'Valider le versement du mois (${_eur(l.nextPayment)})'
            : 'Valider le versement du mois'),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce livret ?'),
        content: Text('« ${livret.name} » sera définitivement supprimé.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) store.deleteLivret(livret);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: highlight ? cs.primary : cs.onSurface)),
        ),
      ],

      // ───────────────────────── Formulaire charge ─────────────────────────

Future<void> _showChargeSheet(BuildContext context, BudgetStore store,
    {Charge? charge}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ChargeForm(store: store, charge: charge),
  );
}

class _ChargeForm extends StatefulWidget {
  const _ChargeForm({required this.store, this.charge});
  final BudgetStore store;
  final Charge? charge;

  @override
  State<_ChargeForm> createState() => _ChargeFormState();
}

class _ChargeFormState extends State<_ChargeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.charge?.name ?? '');
    _amount = TextEditingController(text: _num(widget.charge?.amount ?? 0));
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final amount = _parse(_amount.text);
    if (widget.charge == null) {
      widget.store.addCharge(name, amount);
    } else {
      widget.store.updateCharge(widget.charge!, name, amount);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.charge == null ? 'Nouvelle charge' : 'Modifier la charge',
                  style: tt.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nom (ex. Loyer)'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Saisissez un nom' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                ],
                decoration: const InputDecoration(
                    labelText: 'Montant mensuel', suffixText: '€'),
                validator: (v) =>
                    _parse(v ?? '') > 0 ? null : 'Saisissez un montant',
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(widget.charge == null ? 'Ajouter' : 'Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

      // ───────────────────────── Formulaire livret ─────────────────────────

Future<void> _showLivretSheet(BuildContext context, BudgetStore store,
    {Livret? livret}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _LivretForm(store: store, livret: livret),
  );
}

class _LivretForm extends StatefulWidget {
  const _LivretForm({required this.store, this.livret});
  final BudgetStore store;
  final Livret? livret;

  @override
  State<_LivretForm> createState() => _LivretFormState();
}

class _LivretFormState extends State<_LivretForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _goal;
  late final TextEditingController _monthly;
  late final TextEditingController _saved;

  @override
  void initState() {
    super.initState();
    final l = widget.livret;
    _name = TextEditingController(text: l?.name ?? '');
    _goal = TextEditingController(text: _num(l?.goal ?? 0));
    _monthly = TextEditingController(text: _num(l?.monthly ?? 0));
    _saved = TextEditingController(text: _num(l?.saved ?? 0));
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    _monthly.dispose();
    _saved.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final goal = _parse(_goal.text);
    final monthly = _parse(_monthly.text);
    final saved = _parse(_saved.text);
    if (widget.livret == null) {
      widget.store.addLivret(name, goal, monthly, saved);
    } else {
      widget.store.updateLivret(widget.livret!, name, goal, monthly, saved);
    }
    Navigator.pop(context);
  }

  Widget _money(TextEditingController c, String label,
      {bool required = false, bool last = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
        ],
        decoration: InputDecoration(labelText: label, suffixText: '€'),
        validator: required
            ? (v) => _parse(v ?? '') > 0 ? null : 'Saisissez un montant'
            : null,
        onFieldSubmitted: last ? (_) => _submit() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.livret == null ? 'Nouveau livret' : 'Modifier le livret',
                  style: tt.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofocus: widget.livret == null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration:
                    const InputDecoration(labelText: 'Nom du livret'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Saisissez un nom' : null,
              ),
              _money(_goal, 'Objectif financier total', required: true),
              _money(_monthly, 'Versement mensuel prévu', required: true),
              _money(_saved, 'Montant déjà épargné', last: true),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(widget.livret == null ? 'Créer le livret' : 'Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
