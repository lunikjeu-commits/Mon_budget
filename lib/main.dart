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
