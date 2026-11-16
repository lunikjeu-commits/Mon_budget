import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═════════════════════════ Utilitaires ═════════════════════════

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

String _monthKey([DateTime? d]) {
  final n = d ?? DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

String _nowKey() => _monthKey();

const List<String> _monthNames = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

const List<String> _monthShort = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

int _keyYear(String k) => int.parse(k.substring(0, 4));
int _keyMonth(String k) => int.parse(k.substring(5, 7));
String _keyOf(int y, int m) => '$y-${m.toString().padLeft(2, '0')}';
String _monthLabel(String k) => '${_monthNames[_keyMonth(k) - 1]} ${_keyYear(k)}';
String _monthLabelLower(String k) =>
    '${_monthNames[_keyMonth(k) - 1].toLowerCase()} ${_keyYear(k)}';

String _addMonths(String k, int n) {
  final total = _keyYear(k) * 12 + (_keyMonth(k) - 1) + n;
  return _keyOf(total ~/ 12, total % 12 + 1);
}

int _monthDiff(String a, String b) =>
    (_keyYear(b) - _keyYear(a)) * 12 + (_keyMonth(b) - _keyMonth(a));

String _dateFr(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
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

String _hashPin(String pin) {
  var h = 0x811c9dc5;
  for (final c in 'mb${pin}budget'.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

// ═════════════════════════ Modèles ═════════════════════════

class Income {
  Income({
    required this.id,
    required this.name,
    required this.amount,
    this.month,
  });
  final String id;
  String name;
  double amount;

  /// null = chaque mois ; sinon "AAAA-MM" = ce mois uniquement.
  String? month;

  bool appliesTo(String key) => month == null || month == key;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'amount': amount, 'month': month};

  factory Income.fromJson(Map<String, dynamic> j) => Income(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: (j['amount'] as num).toDouble(),
        month: j['month'] as String?,
      );
}

class Charge {
  Charge({
    required this.id,
    required this.name,
    required this.amount,
    this.day = 0,
  });
  final String id;
  String name;
  double amount;
  int day;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'amount': amount, 'day': day};

  factory Charge.fromJson(Map<String, dynamic> j) => Charge(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: (j['amount'] as num).toDouble(),
        day: ((j['day'] ?? 0) as num).toInt(),
      );
}

class Deposit {
  Deposit({
    required this.id,
    required this.month,
    required this.date,
    required this.amount,
    required this.kind,
  });
  final String id;
  final String month;
  final String date;
  double amount;

  /// 'mensuel' ou 'libre'
  final String kind;

  bool get isMonthly => kind == 'mensuel';

  Map<String, dynamic> toJson() => {
        'id': id,
        'month': month,
        'date': date,
        'amount': amount,
        'kind': kind,
      };

  factory Deposit.fromJson(Map<String, dynamic> j) => Deposit(
        id: j['id'] as String,
        month: j['month'] as String,
        date: j['date'] as String,
        amount: (j['amount'] as num).toDouble(),
        kind: (j['kind'] ?? 'libre') as String,
      );
}

class Snapshot {
  const Snapshot(
      {required this.income, required this.charges, required this.saved});
  final double income;
  final double charges;
  final double saved;
  double get rest => income - charges - saved;
}

class Livret {
  Livret({
    required this.id,
    required this.name,
    required this.goal,
    required this.monthly,
    required this.saved,
    this.target,
    List<Deposit>? history,
  }) : history = history ?? [];

  final String id;
  String name;
  double goal;
  double monthly;
  double saved;

  /// Mois d'objectif "AAAA-MM" (facultatif).
  String? target;
  final List<Deposit> history;

  double get remaining => (goal - saved) < 0 ? 0 : goal - saved;
  double get progress =>
      goal <= 0 ? 0 : (saved / goal).clamp(0.0, 1.0).toDouble();
  bool get goalReached => goal > 0 && saved >= goal;

  Deposit? get monthlyDepositThisMonth {
    final key = _nowKey();
    for (final d in history) {
      if (d.isMonthly && d.month == key) return d;
    }
    return null;
  }

  bool get validatedThisMonth => monthlyDepositThisMonth != null;

  /// Montant qui sera réellement versé ce mois-ci (plafonné à ce qui reste).
  double get nextPayment {
    if (goal <= 0) return monthly;
    return monthly < remaining ? monthly : remaining;
  }

  /// Nombre de versements mensuels possibles jusqu'à la date d'objectif.
  int? get monthsLeftToTarget {
    if (target == null) return null;
    var n = _monthDiff(_nowKey(), target!) + 1;
    if (validatedThisMonth) n -= 1;
    return n;
  }

  bool get targetPassed {
    final n = monthsLeftToTarget;
    return n != null && n <= 0 && remaining > 0;
  }

  double? get requiredMonthly {
    final n = monthsLeftToTarget;
    if (n == null || n <= 0 || remaining <= 0) return null;
    return remaining / n;
  }

  String? get estimatedEnd {
    if (monthly <= 0 || remaining <= 0) return null;
    final payments = (remaining / monthly - 1e-9).ceil();
    final offset = validatedThisMonth ? payments : payments - 1;
    return _addMonths(_nowKey(), offset < 0 ? 0 : offset);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goal': goal,
        'monthly': monthly,
        'saved': saved,
        'target': target,
        'history': history.map((d) => d.toJson()).toList(),
      };

  factory Livret.fromJson(Map<String, dynamic> j) {
    final history = <Deposit>[];
    if (j['history'] != null) {
      for (final e in j['history'] as List) {
        history.add(Deposit.fromJson(e as Map<String, dynamic>));
      }
    } else {
      // Ancien format : un seul versement validé était mémorisé.
      final vm = j['validatedMonth'] as String?;
      final va = ((j['validatedAmount'] ?? 0) as num).toDouble();
      if (vm != null && va > 0) {
        history.add(Deposit(
          id: _newId(),
          month: vm,
          date: '$vm-01T00:00:00',
          amount: va,
          kind: 'mensuel',
        ));
      }
    }
    return Livret(
      id: j['id'] as String,
      name: j['name'] as String,
      goal: (j['goal'] as num).toDouble(),
      monthly: (j['monthly'] as num).toDouble(),
      saved: (j['saved'] as num).toDouble(),
      target: j['target'] as String?,
      history: history,
    );
  }
}

// ═════════════════════════ Stockage / état ═════════════════════════

class BudgetStore extends ChangeNotifier {
  BudgetStore._(this._prefs);

  static const _key = 'budget_data_v1';
  final SharedPreferences _prefs;

  final List<Income> incomes = [];
  final List<Charge> charges = [];
  final List<Livret> livrets = [];
  final Map<String, Snapshot> snapshots = {};
  ThemeMode themeMode = ThemeMode.system;
  String? pinHash;
  int reminderDay = 0;

  static Future<BudgetStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final store = BudgetStore._(prefs);
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        store._apply(j);
        final t = ((j['theme'] ?? 0) as num).toInt();
        store.themeMode = ThemeMode.values[t < 0 || t > 2 ? 0 : t];
        store.pinHash = j['pin'] as String?;
        store.reminderDay = ((j['reminderDay'] ?? 0) as num).toInt();
      } catch (_) {
        // Données illisibles : on repart de zéro.
      }
    }
    store._rollover();
    return store;
  }

  void _apply(Map<String, dynamic> j) {
    final newIncomes = <Income>[];
    final newCharges = <Charge>[];
    final newLivrets = <Livret>[];
    final newSnaps = <String, Snapshot>{};

    if (j['incomes'] != null) {
      for (final e in j['incomes'] as List) {
        newIncomes.add(Income.fromJson(e as Map<String, dynamic>));
      }
    } else {
      // Ancien format : un seul salaire.
      final oldSalary = ((j['salary'] ?? 0) as num).toDouble();
      if (oldSalary > 0) {
        newIncomes
            .add(Income(id: _newId(), name: 'Salaire', amount: oldSalary));
      }
    }
    for (final e in (j['charges'] ?? []) as List) {
      newCharges.add(Charge.fromJson(e as Map<String, dynamic>));
    }
    for (final e in (j['livrets'] ?? []) as List) {
      newLivrets.add(Livret.fromJson(e as Map<String, dynamic>));
    }
    final rawSnaps = (j['snapshots'] ?? <String, dynamic>{}) as Map;
    rawSnaps.forEach((k, v) {
      final m = v as Map;
      newSnaps[k as String] = Snapshot(
        income: (m['income'] as num).toDouble(),
        charges: (m['charges'] as num).toDouble(),
        saved: (m['saved'] as num).toDouble(),
      );
    });

    incomes
      ..clear()
      ..addAll(newIncomes);
    charges
      ..clear()
      ..addAll(newCharges);
    livrets
      ..clear()
      ..addAll(newLivrets);
    snapshots
      ..clear()
      ..addAll(newSnaps);
  }

  Map<String, dynamic> _data() => {
        'version': 2,
        'incomes': incomes.map((e) => e.toJson()).toList(),
        'charges': charges.map((e) => e.toJson()).toList(),
        'livrets': livrets.map((e) => e.toJson()).toList(),
        'snapshots': snapshots.map((k, v) => MapEntry(k, {
              'income': v.income,
              'charges': v.charges,
              'saved': v.saved,
            })),
      };

  Future<void> _save() async {
    await _prefs.setString(
      _key,
      jsonEncode({
        ..._data(),
        'theme': themeMode.index,
        'pin': pinHash,
        'reminderDay': reminderDay,
      }),
    );
  }

  void _rollover() {
    final now = _nowKey();
    incomes.removeWhere((i) => i.month != null && i.month!.compareTo(now) < 0);
    _updateSnapshot();
  }

  void _updateSnapshot() {
    final key = _nowKey();
    final inc = incomeThisMonth;
    final ch = totalCharges;
    final sv = depositsThisMonth;
    if (inc == 0 && ch == 0 && sv == 0) {
      snapshots.remove(key);
    } else {
      snapshots[key] = Snapshot(income: inc, charges: ch, saved: sv);
    }
  }

  void _changed() {
    _updateSnapshot();
    notifyListeners();
    _save();
  }

  void refresh() {
    _rollover();
    notifyListeners();
    _save();
  }

  // ───── Calculs ─────

  List<Income> get incomesThisMonth {
    final k = _nowKey();
    return incomes.where((i) => i.appliesTo(k)).toList();
  }

  double get incomeThisMonth =>
      incomesThisMonth.fold(0.0, (s, i) => s + i.amount);

  double get totalCharges => charges.fold(0.0, (s, c) => s + c.amount);

  List<Charge> get sortedCharges {
    final list = [...charges];
    list.sort((a, b) {
      if (a.day == 0 && b.day == 0) return a.name.compareTo(b.name);
      if (a.day == 0) return 1;
      if (b.day == 0) return -1;
      return a.day.compareTo(b.day);
    });
    return list;
  }

  double get chargesStillToCome {
    final today = DateTime.now().day;
    return charges
        .where((c) => c.day > today)
        .fold(0.0, (s, c) => s + c.amount);
  }

  bool get hasDatedCharges => charges.any((c) => c.day > 0);

  double get depositsThisMonth {
    final k = _nowKey();
    var s = 0.0;
    for (final l in livrets) {
      for (final d in l.history) {
        if (d.month == k) s += d.amount;
      }
    }
    return s;
  }

  double get totalSaved => livrets.fold(0.0, (s, l) => s + l.saved);
  double get totalGoals => livrets.fold(0.0, (s, l) => s + l.goal);

  double get plannedSavings => livrets
      .where((l) => !l.validatedThisMonth && !l.goalReached)
      .fold(0.0, (s, l) => s + l.nextPayment);

  double get remainingToSplit =>
      incomeThisMonth - totalCharges - depositsThisMonth;

  int get pendingPaymentsCount => livrets
      .where((l) => !l.validatedThisMonth && !l.goalReached && l.nextPayment > 0)
      .length;

  bool get needsReminder =>
      reminderDay > 0 &&
      DateTime.now().day >= reminderDay &&
      pendingPaymentsCount > 0;

  Map<String, double> depositsByLivret(String month) {
    final m = <String, double>{};
    for (final l in livrets) {
      var s = 0.0;
      for (final d in l.history) {
        if (d.month == month) s += d.amount;
      }
      if (s != 0) m[l.name] = s;
    }
    return m;
  }

  // ───── Réglages ─────

  bool get hasPin => pinHash != null;
  bool checkPin(String pin) => pinHash == _hashPin(pin);

  void setPin(String? pin) {
    pinHash = pin == null ? null : _hashPin(pin);
    _changed();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _changed();
  }

  void setReminderDay(int d) {
    reminderDay = d;
    _changed();
  }

  // ───── Sauvegarde ─────

  String exportBackup() =>
      jsonEncode({..._data(), 'reminderDay': reminderDay});

  bool importBackup(String raw) {
    try {
      final j = jsonDecode(raw.trim());
      if (j is! Map<String, dynamic>) return false;
      if (!j.containsKey('version') || !j.containsKey('livrets')) return false;
      _apply(j);
      if (j['reminderDay'] != null) {
        reminderDay = (j['reminderDay'] as num).toInt();
      }
      _rollover();
      _changed();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ───── Revenus ─────

  void addIncome(String name, double amount, String? month) {
    incomes.add(Income(id: _newId(), name: name, amount: amount, month: month));
    _changed();
  }

  void updateIncome(Income i, String name, double amount, String? month) {
    i.name = name;
    i.amount = amount;
    i.month = month;
    _changed();
  }

  void deleteIncome(Income i) {
    incomes.remove(i);
    _changed();
  }

  // ───── Charges ─────

  void addCharge(String name, double amount, int day) {
    charges.add(Charge(id: _newId(), name: name, amount: amount, day: day));
    _changed();
  }

  void updateCharge(Charge c, String name, double amount, int day) {
    c.name = name;
    c.amount = amount;
    c.day = day;
    _changed();
  }

  void deleteCharge(Charge c) {
    charges.remove(c);
    _changed();
  }

  // ───── Livrets ─────

  void addLivret(String name, double goal, double monthly, double saved,
      String? target) {
    livrets.add(Livret(
      id: _newId(),
      name: name,
      goal: goal,
      monthly: monthly,
      saved: saved,
      target: target,
    ));
    _changed();
  }

  void updateLivret(Livret l, String name, double goal, double monthly,
      double saved, String? target) {
    l.name = name;
    l.goal = goal;
    l.monthly = monthly;
    l.saved = saved;
    l.target = target;
    _changed();
  }

  void deleteLivret(Livret l) {
    livrets.remove(l);
    _changed();
  }

  void addDeposit(Livret l, double amount, String kind) {
    final now = DateTime.now();
    l.history.add(Deposit(
      id: _newId(),
      month: _monthKey(now),
      date: now.toIso8601String(),
      amount: amount,
      kind: kind,
    ));
    l.saved += amount;
    _changed();
  }

  void removeDeposit(Livret l, Deposit d) {
    l.history.remove(d);
    l.saved -= d.amount;
    if (l.saved < 0) l.saved = 0;
    _changed();
  }

  void editDeposit(Livret l, Deposit d, double amount) {
    l.saved += amount - d.amount;
    if (l.saved < 0) l.saved = 0;
    d.amount = amount;
    _changed();
  }

  /// Retourne le montant versé (0 si rien n'a été fait).
  double validatePayment(Livret l) {
    if (l.validatedThisMonth) return 0;
    final amount = l.nextPayment;
    if (amount <= 0) return 0;
    addDeposit(l, amount, 'mensuel');
    return amount;
  }

  void undoPayment(Livret l) {
    final d = l.monthlyDepositThisMonth;
    if (d != null) removeDeposit(l, d);
  }
}

// ═════════════════════════ Application ═════════════════════════

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
        builder: (context, child) =>
            _LockGate(store: store, child: child ?? const SizedBox.shrink()),
        home: HomePage(store: store),
      ),
    );
  }
}

// ═════════════════════════ Verrouillage par code PIN ═════════════════════════

class _LockGate extends StatefulWidget {
  const _LockGate({required this.store, required this.child});
  final BudgetStore store;
  final Widget child;

  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> with WidgetsBindingObserver {
  late bool _locked;

  @override
  void initState() {
    super.initState();
    _locked = widget.store.hasPin;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.store.hasPin) {
      setState(() => _locked = true);
    }
    if (state == AppLifecycleState.resumed) {
      widget.store.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showLock = _locked && widget.store.hasPin;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showLock)
          Positioned.fill(
            child: _LockScreen(
              store: widget.store,
              onUnlock: () => setState(() => _locked = false),
            ),
          ),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.store, required this.onUnlock});
  final BudgetStore store;
  final VoidCallback onUnlock;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: PinPad(
            title: 'Saisissez votre code',
            error: _error,
            onCompleted: (v) {
              if (widget.store.checkPin(v)) {
                widget.onUnlock();
              } else {
                setState(() => _error = 'Code incorrect');
              }
            },
          ),
        ),
      ),
    );
  }
}

class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onCompleted,
    this.subtitle,
    this.error,
  });
  final String title;
  final String? subtitle;
  final String? error;
  final void Function(String pin) onCompleted;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _value = '';

  void _tap(String d) {
    if (_value.length >= 4) return;
    setState(() => _value += d);
    if (_value.length == 4) {
      final v = _value;
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _value = '');
        widget.onCompleted(v);
      });
    }
  }

  void _back() {
    if (_value.isEmpty || _value.length >= 4) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  Widget _key(String label) {
    final tt = Theme.of(context).textTheme;
    if (label.isEmpty) return const SizedBox(width: 76, height: 76);
    final style = FilledButton.styleFrom(
      shape: const CircleBorder(),
      minimumSize: const Size(76, 76),
      padding: EdgeInsets.zero,
    );
    if (label == 'x') {
      return FilledButton.tonal(
        onPressed: _back,
        style: style,
        child: const Icon(Icons.backspace_outlined),
      );
    }
    return FilledButton.tonal(
      onPressed: () => _tap(label),
      style: style,
      child: Text(label, style: tt.headlineSmall),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'x'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, size: 40, color: cs.primary),
        const SizedBox(height: 12),
        Text(widget.title, style: tt.titleLarge),
        const SizedBox(height: 8),
        SizedBox(
          height: 22,
          child: Text(
            widget.error ?? widget.subtitle ?? '',
            style: tt.bodyMedium?.copyWith(
                color: widget.error != null ? cs.error : cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            4,
            (i) => Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _value.length ? cs.primary : Colors.transparent,
                border: Border.all(color: cs.primary, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final k in r)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _key(k),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

enum PinMode { setup, change, remove }

class PinFlowPage extends StatefulWidget {
  const PinFlowPage({super.key, required this.store, required this.mode});
  final BudgetStore store;
  final PinMode mode;

  @override
  State<PinFlowPage> createState() => _PinFlowPageState();
}

class _PinFlowPageState extends State<PinFlowPage> {
  late int _step; // 0 = ancien code, 1 = nouveau code, 2 = confirmation
  String _first = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _step = widget.mode == PinMode.setup ? 1 : 0;
  }

  String get _title {
    switch (_step) {
      case 0:
        return 'Saisissez votre code actuel';
      case 1:
        return 'Choisissez un nouveau code';
      default:
        return 'Confirmez le code';
    }
  }

  void _onCompleted(String v) {
    if (_step == 0) {
      if (widget.store.checkPin(v)) {
        if (widget.mode == PinMode.remove) {
          widget.store.setPin(null);
          Navigator.of(context).pop(true);
        } else {
          setState(() {
            _step = 1;
            _error = null;
          });
        }
      } else {
        setState(() => _error = 'Code incorrect');
      }
    } else if (_step == 1) {
      setState(() {
        _first = v;
        _step = 2;
        _error = null;
      });
    } else {
      if (v == _first) {
        widget.store.setPin(v);
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _step = 1;
          _error = 'Les codes ne correspondent pas';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Code PIN')),
      body: SafeArea(
        child: Center(
          child: PinPad(
            title: _title,
            subtitle: _step == 1 ? '4 chiffres' : null,
            error: _error,
            onCompleted: _onCompleted,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ Outils d'interface ═════════════════════════

Future<void> _sheet(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => child,
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Supprimer',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

Widget _moneyField(
  TextEditingController c,
  String label, {
  bool required = false,
  bool autofocus = false,
  bool last = false,
  VoidCallback? onSubmit,
}) {
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: c,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
      ],
      decoration: InputDecoration(labelText: label, suffixText: '€'),
      validator: required
          ? (v) => _parse(v ?? '') > 0 ? null : 'Saisissez un montant'
          : null,
      onFieldSubmitted: last && onSubmit != null ? (_) => onSubmit() : null,
    ),
  );
}

Widget _kv(BuildContext context, String label, String value,
    {bool bold = false, Color? color}) {
  final tt = Theme.of(context).textTheme;
  final style = tt.bodyLarge?.copyWith(
    color: color,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
  );
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    ),
  );
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, required this.initial});
  final String title;
  final double initial;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _num(widget.initial));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final v = _parse(_c.text);
    if (v <= 0) {
      setState(() => _error = 'Saisissez un montant');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
        ],
        decoration: InputDecoration(
            labelText: 'Montant', suffixText: '€', errorText: _error),
        onSubmitted: (_) => _ok(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(onPressed: _ok, child: const Text('Valider')),
      ],
    );
  }
}

Future<double?> _askAmount(BuildContext context,
    {required String title, double initial = 0}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _AmountDialog(title: title, initial: initial),
  );
}

// ═════════════════════════ Page d'accueil ═════════════════════════

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});
  final BudgetStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  BudgetStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const titles = ['Mon budget', 'Mes livrets', 'Historique'];
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        Widget body;
        if (_tab == 0) {
          body = _BudgetTab(
              store: store, onOpenLivrets: () => setState(() => _tab = 1));
        } else if (_tab == 1) {
          body = _LivretsTab(store: store);
        } else {
          body = _HistoryTab(store: store);
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(titles[_tab]),
            actions: [
              IconButton(
                tooltip: dark ? 'Mode clair' : 'Mode sombre',
                icon: Icon(
                    dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                onPressed: () =>
                    store.setTheme(dark ? ThemeMode.light : ThemeMode.dark),
              ),
              IconButton(
                tooltip: 'Réglages',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(store: store)),
                ),
              ),
            ],
          ),
          body: body,
          floatingActionButton: _tab == 1
              ? FloatingActionButton.extended(
                  onPressed: () => _sheet(context, _LivretForm(store: store)),
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
              NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: 'Historique'),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════ Onglet Budget ═════════════════════════

class _BudgetTab extends StatelessWidget {
  const _BudgetTab({required this.store, required this.onOpenLivrets});
  final BudgetStore store;
  final VoidCallback onOpenLivrets;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final incomes = store.incomesThisMonth;
    final charges = store.sortedCharges;
    final today = DateTime.now().day;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (store.needsReminder) ...[
          Card(
            color: cs.tertiaryContainer,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(Icons.notifications_active_outlined,
                  color: cs.onTertiaryContainer),
              title: Text('Versements du mois à valider',
                  style: tt.titleMedium
                      ?.copyWith(color: cs.onTertiaryContainer)),
              subtitle: Text(
                  '${store.pendingPaymentsCount} livret(s) en attente. Touchez pour ouvrir.',
                  style: tt.bodyMedium?.copyWith(color: cs.onTertiaryContainer)),
              onTap: onOpenLivrets,
            ),
          ),
          const SizedBox(height: 16),
        ],
        _ResteCard(store: store),
        const SizedBox(height: 24),

        // ───── Revenus ─────
        Row(
          children: [
            Expanded(child: Text('Revenus', style: tt.titleLarge)),
            FilledButton.tonalIcon(
              onPressed: () => _sheet(context, _IncomeForm(store: store)),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Total ce mois-ci : ${_eur(store.incomeThisMonth)}',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (incomes.isEmpty)
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Aucun revenu.\nAjoutez votre salaire, une prime, des allocations…',
                textAlign: TextAlign.center,
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          ...incomes.map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card.filled(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
                  title: Text(i.name, style: tt.titleMedium),
                  subtitle: Text(
                    '${_eur(i.amount)} · ${i.month == null ? 'chaque mois' : 'ce mois-ci seulement'}',
                    style: tt.bodyLarge?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.w600),
                  ),
                  onTap: () =>
                      _sheet(context, _IncomeForm(store: store, income: i)),
                  trailing: IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => store.deleteIncome(i),
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 24),

        // ───── Charges fixes ─────
        Row(
          children: [
            Expanded(child: Text('Charges fixes', style: tt.titleLarge)),
            FilledButton.tonalIcon(
              onPressed: () => _sheet(context, _ChargeForm(store: store)),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          store.hasDatedCharges
              ? 'Total : ${_eur(store.totalCharges)} · encore à venir : ${_eur(store.chargesStillToCome)}'
              : 'Total : ${_eur(store.totalCharges)}',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (charges.isEmpty)
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
          ...charges.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card.filled(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                  leading: CircleAvatar(
                    backgroundColor: c.day > 0 && c.day <= today
                        ? cs.surfaceContainerHighest
                        : cs.secondaryContainer,
                    foregroundColor: cs.onSurface,
                    child: c.day > 0
                        ? Text('${c.day}')
                        : const Icon(Icons.autorenew, size: 20),
                  ),
                  title: Text(c.name, style: tt.titleMedium),
                  subtitle: Text(
                    c.day > 0
                        ? '${_eur(c.amount)} · le ${c.day} du mois'
                        : _eur(c.amount),
                    style: tt.bodyLarge?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.w600),
                  ),
                  onTap: () =>
                      _sheet(context, _ChargeForm(store: store, charge: c)),
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
}

// ═════════════════════════ Carte « reste à répartir » ═════════════════════════

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

    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final disposable = reste - store.plannedSavings;

    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                  child: Text(label, style: tt.bodyMedium?.copyWith(color: fg))),
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
            Text(_monthLabel(_nowKey()),
                style: tt.labelLarge?.copyWith(color: fg)),
            const SizedBox(height: 2),
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
            line('Revenus', _eur(store.incomeThisMonth)),
            line('Charges fixes', '- ${_eur(store.totalCharges)}'),
            line('Épargne versée', '- ${_eur(store.depositsThisMonth)}'),
            if (store.plannedSavings > 0)
              line('Épargne encore prévue', _eur(store.plannedSavings)),
            if (disposable > 0.004) ...[
              const SizedBox(height: 8),
              Divider(color: fg.withAlpha(60), height: 1),
              const SizedBox(height: 8),
              line('Reste par jour (épargne prévue déduite)',
                  '≈ ${_eur(disposable / daysLeft)}'),
            ],
            if (negative) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: fg, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Vos dépenses dépassent vos revenus.',
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

// ═════════════════════════ Onglet Livrets ═════════════════════════

class _LivretsTab extends StatelessWidget {
  const _LivretsTab({required this.store});
  final BudgetStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _ResteCard(store: store),
        const SizedBox(height: 16),
        if (store.livrets.isNotEmpty) ...[
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total épargné',
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(_eur(store.totalSaved),
                              style: tt.titleLarge?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Objectifs cumulés',
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(_eur(store.totalGoals),
                              style: tt.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
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
    final req = l.requiredMonthly;
    final est = l.estimatedEnd;
    final info = tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant);

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.name,
                      style:
                          tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      _sheet(context, _LivretForm(store: store, livret: l));
                    } else {
                      final ok = await _confirm(
                        context,
                        title: 'Supprimer ce livret ?',
                        message:
                            '« ${l.name} » et son historique seront définitivement supprimés.',
                      );
                      if (ok) store.deleteLivret(l);
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
                  Text('$pct %',
                      style: tt.titleMedium?.copyWith(
                          color: cs.primary, fontWeight: FontWeight.bold)),
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
                  if (l.target != null || est != null) ...[
                    const SizedBox(height: 12),
                    if (l.target != null)
                      Text('Objectif visé : ${_monthLabelLower(l.target!)}',
                          style: info),
                    if (l.targetPassed)
                      Text('La date d’objectif est dépassée.',
                          style: tt.bodyMedium?.copyWith(color: cs.error)),
                    if (req != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                                'Pour y arriver : ${_eur(req)} / mois',
                                style: info),
                          ),
                          if ((req - l.monthly).abs() > 0.005)
                            TextButton(
                              onPressed: () => store.updateLivret(
                                  l,
                                  l.name,
                                  l.goal,
                                  (req * 100).ceil() / 100,
                                  l.saved,
                                  l.target),
                              child: const Text('Appliquer'),
                            ),
                        ],
                      ),
                    if (est != null)
                      Text(
                          'Fin estimée au rythme actuel : ${_monthLabelLower(est)}',
                          style: info),
                  ],
                  const SizedBox(height: 16),
                  _action(context),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final v = await _askAmount(context,
                              title: 'Versement libre');
                          if (v != null) {
                            store.addDeposit(l, v, 'libre');
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Versement libre'),
                      ),
                      TextButton.icon(
                        onPressed: () => _sheet(
                            context, _HistorySheet(store: store, livret: l)),
                        icon: const Icon(Icons.history),
                        label: const Text('Historique'),
                      ),
                    ],
                  ),
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
    final d = l.monthlyDepositThisMonth;
    if (d != null) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: null,
              icon: const Icon(Icons.check_circle),
              label: Text('${_eur(d.amount)} validés ce mois-ci'),
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
                        label: 'Annuler',
                        onPressed: () => store.undoPayment(l)),
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
        Text(label, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
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
    );
  }
}

// ═════════════════════════ Historique d'un livret ═════════════════════════

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.store, required this.livret});
  final BudgetStore store;
  final Livret livret;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = [...livret.history]
          ..sort((a, b) => b.date.compareTo(a.date));
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Historique · ${livret.name}', style: tt.titleLarge),
              const SizedBox(height: 4),
              Text('Épargné : ${_eur(livret.saved)}',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Aucun versement enregistré.',
                      style: tt.bodyLarge
                          ?.copyWith(color: cs.onSurfaceVariant)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_eur(d.amount), style: tt.titleMedium),
                          subtitle: Text(
                              '${_dateFr(d.date)} · ${d.isMonthly ? 'Versement du mois' : 'Versement libre'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Corriger',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  final v = await _askAmount(context,
                                      title: 'Corriger le montant',
                                      initial: d.amount);
                                  if (v != null) {
                                    store.editDeposit(livret, d, v);
                                  }
                                },
                              ),
                              IconButton(
                                tooltip: 'Supprimer',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await _confirm(
                                    context,
                                    title: 'Supprimer ce versement ?',
                                    message:
                                        '${_eur(d.amount)} seront retirés du montant épargné.',
                                  );
                                  if (ok) store.removeDeposit(livret, d);
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════ Onglet Historique ═════════════════════════

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.store});
  final BudgetStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final entries = store.snapshots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'L’historique se construit tout seul au fil des mois.\nAjoutez vos revenus et vos charges pour commencer.',
            textAlign: TextAlign.center,
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final last6 =
        entries.length > 6 ? entries.sublist(entries.length - 6) : entries;
    final avgSaved =
        entries.fold(0.0, (s, e) => s + e.value.saved) / entries.length;
    final currentKey = _nowKey();
    final descending = entries.reversed.toList();

    Widget legend(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: tt.bodyMedium),
          ],
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Derniers mois', style: tt.titleLarge),
                const SizedBox(height: 16),
                _MonthChart(entries: last6),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    legend(cs.primary, 'Revenus'),
                    legend(cs.error, 'Charges'),
                    legend(cs.tertiary, 'Épargne'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Épargne moyenne / mois',
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(_eur(avgSaved),
                            style: tt.titleLarge?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total épargné',
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(_eur(store.totalSaved),
                            style: tt.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final e in descending)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MonthCard(
              store: store,
              monthKey: e.key,
              snap: e.value,
              isCurrent: e.key == currentKey,
            ),
          ),
      ],
    );
  }
}

class _MonthChart extends StatelessWidget {
  const _MonthChart({required this.entries});
  final List<MapEntry<String, Snapshot>> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    var maxV = 1.0;
    for (final e in entries) {
      for (final v in [e.value.income, e.value.charges, e.value.saved]) {
        if (v > maxV) maxV = v;
      }
    }
    const barArea = 150.0;

    Widget bar(double v, Color c) {
      final h = v <= 0 ? 2.0 : (barArea * v / maxV).clamp(2.0, barArea);
      return Container(
        width: 10,
        height: h.toDouble(),
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          color: c,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      );
    }

    return SizedBox(
      height: barArea + 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in entries)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      bar(e.value.income, cs.primary),
                      bar(e.value.charges, cs.error),
                      bar(e.value.saved, cs.tertiary),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_monthShort[_keyMonth(e.key) - 1],
                      style: tt.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.store,
    required this.monthKey,
    required this.snap,
    required this.isCurrent,
  });
  final BudgetStore store;
  final String monthKey;
  final Snapshot snap;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final details = store.depositsByLivret(monthKey);
    final rate = snap.income > 0 ? snap.saved / snap.income * 100 : null;
    final restColor = snap.rest < -0.004 ? cs.error : cs.primary;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCurrent
                  ? '${_monthLabel(monthKey)} (en cours)'
                  : _monthLabel(monthKey),
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            _kv(context, 'Revenus', _eur(snap.income)),
            _kv(context, 'Charges fixes', _eur(snap.charges)),
            _kv(context, 'Épargne versée', _eur(snap.saved)),
            const SizedBox(height: 6),
            Divider(color: cs.outlineVariant, height: 1),
            _kv(context, 'Reste', _eur(snap.rest),
                bold: true, color: restColor),
            if (rate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Taux d’épargne : ${rate.toStringAsFixed(1)} %',
                    style:
                        tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Détail de l’épargne',
                  style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
              for (final d in details.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${d.key} : ${_eur(d.value)}',
                      style: tt.bodyMedium),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════ Formulaires ═════════════════════════

class _IncomeForm extends StatefulWidget {
  const _IncomeForm({required this.store, this.income});
  final BudgetStore store;
  final Income? income;

  @override
  State<_IncomeForm> createState() => _IncomeFormState();
}

class _IncomeFormState extends State<_IncomeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late bool _oneTime;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.income?.name ?? '');
    _amount = TextEditingController(text: _num(widget.income?.amount ?? 0));
    _oneTime = widget.income?.month != null;
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
    final i = widget.income;
    if (i == null) {
      widget.store.addIncome(name, amount, _oneTime ? _nowKey() : null);
    } else {
      widget.store.updateIncome(
          i, name, amount, _oneTime ? (i.month ?? _nowKey()) : null);
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
              Text(widget.income == null ? 'Nouveau revenu' : 'Modifier le revenu',
                  style: tt.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofocus: widget.income == null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Nom (ex. Salaire, Prime, CAF)'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Saisissez un nom' : null,
              ),
              _moneyField(_amount, 'Montant', required: true, last: true,
                  onSubmit: _submit),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Seulement ce mois-ci'),
                subtitle: const Text(
                    'Sinon ce revenu est compté chaque mois.'),
                value: _oneTime,
                onChanged: (v) => setState(() => _oneTime = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(widget.income == null ? 'Ajouter' : 'Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  late final TextEditingController _day;

  @override
  void initState() {
    super.initState();
    final c = widget.charge;
    _name = TextEditingController(text: c?.name ?? '');
    _amount = TextEditingController(text: _num(c?.amount ?? 0));
    _day = TextEditingController(
        text: (c != null && c.day > 0) ? '${c.day}' : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final amount = _parse(_amount.text);
    final day = int.tryParse(_day.text.trim()) ?? 0;
    final c = widget.charge;
    if (c == null) {
      widget.store.addCharge(name, amount, day);
    } else {
      widget.store.updateCharge(c, name, amount, day);
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
                autofocus: widget.charge == null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nom (ex. Loyer)'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Saisissez un nom' : null,
              ),
              _moneyField(_amount, 'Montant mensuel', required: true),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextFormField(
                  controller: _day,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Jour de prélèvement (facultatif)',
                    helperText: 'De 1 à 31',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    if (n == null || n < 1 || n > 31) return 'Entre 1 et 31';
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
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
  late bool _hasTarget;
  late int _tMonth;
  late int _tYear;

  @override
  void initState() {
    super.initState();
    final l = widget.livret;
    _name = TextEditingController(text: l?.name ?? '');
    _goal = TextEditingController(text: _num(l?.goal ?? 0));
    _monthly = TextEditingController(text: _num(l?.monthly ?? 0));
    _saved = TextEditingController(text: _num(l?.saved ?? 0));
    _hasTarget = l?.target != null;
    final base = l?.target ?? _addMonths(_nowKey(), 12);
    _tMonth = _keyMonth(base);
    _tYear = _keyYear(base);
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
    final target = _hasTarget ? _keyOf(_tYear, _tMonth) : null;
    final l = widget.livret;
    if (l == null) {
      widget.store.addLivret(name, goal, monthly, saved, target);
    } else {
      widget.store.updateLivret(l, name, goal, monthly, saved, target);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final nowYear = DateTime.now().year;
    final firstYear = _tYear < nowYear ? _tYear : nowYear;
    final lastYear = _tYear > nowYear + 30 ? _tYear : nowYear + 30;
    final years = [for (var y = firstYear; y <= lastYear; y++) y];

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
                decoration: const InputDecoration(labelText: 'Nom du livret'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Saisissez un nom' : null,
              ),
              _moneyField(_goal, 'Objectif financier total', required: true),
              _moneyField(_monthly, 'Versement mensuel prévu', required: true),
              _moneyField(_saved, 'Montant déjà épargné',
                  last: true, onSubmit: _submit),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date d’objectif'),
                subtitle: const Text(
                    'L’app calcule le versement mensuel nécessaire.'),
                value: _hasTarget,
                onChanged: (v) => setState(() => _hasTarget = v),
              ),
              if (_hasTarget)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Mois'),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: _tMonth,
                              items: [
                                for (var i = 0; i < 12; i++)
                                  DropdownMenuItem<int>(
                                      value: i + 1, child: Text(_monthNames[i])),
                              ],
                              onChanged: (v) =>
                                  setState(() => _tMonth = v ?? _tMonth),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Année'),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: _tYear,
                              items: [
                                for (final y in years)
                                  DropdownMenuItem<int>(
                                      value: y, child: Text('$y')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _tYear = v ?? _tYear),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(
                    widget.livret == null ? 'Créer le livret' : 'Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ Réglages ═════════════════════════

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});
  final BudgetStore store;

  Widget _title(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openPin(BuildContext context, PinMode mode, String done) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
          builder: (_) => PinFlowPage(store: store, mode: mode)),
    );
    if (ok == true && context.mounted) _snack(context, done);
  }

  Future<void> _pinTap(BuildContext context) async {
    if (!store.hasPin) {
      await _openPin(context, PinMode.setup, 'Code PIN activé');
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Code PIN'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child: const Text('Changer le code')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Désactiver le code')),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'change') {
      await _openPin(context, PinMode.change, 'Code PIN modifié');
    } else if (choice == 'remove') {
      await _openPin(context, PinMode.remove, 'Code PIN désactivé');
    }
  }

  Future<void> _reminderTap(BuildContext context) async {
    final v = await showDialog<int>(
      context: context,
      builder: (_) => _ReminderDialog(initial: store.reminderDay),
    );
    if (v != null) store.setReminderDay(v);
  }

  Future<void> _copyBackup(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: store.exportBackup()));
    if (context.mounted) {
      _snack(context,
          'Sauvegarde copiée. Collez-la dans vos notes ou un message à vous-même.');
    }
  }

  Future<void> _restore(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RestoreDialog(store: store),
    );
    if (ok == true && context.mounted) {
      _snack(context, 'Données restaurées');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Réglages')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            _title(context, 'APPARENCE'),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
              ],
              selected: {store.themeMode},
              onSelectionChanged: (s) => store.setTheme(s.first),
            ),
            _title(context, 'SÉCURITÉ'),
            Card.filled(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Code PIN'),
                subtitle: Text(store.hasPin
                    ? 'Activé : l’app se verrouille quand vous la quittez'
                    : 'Désactivé'),
                onTap: () => _pinTap(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                'Le code PIN empêche un simple curieux d’ouvrir l’app, mais il ne chiffre pas les données. Si vous l’oubliez, il faudra réinstaller l’app : faites une sauvegarde avant.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            _title(context, 'RAPPEL'),
            Card.filled(
              child: ListTile(
                leading: const Icon(Icons.notifications_none),
                title: const Text('Rappel des versements'),
                subtitle: Text(store.reminderDay == 0
                    ? 'Désactivé'
                    : 'Bandeau dans l’app à partir du ${store.reminderDay} du mois'),
                onTap: () => _reminderTap(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                'Le rappel s’affiche en haut de l’onglet Budget tant que des versements ne sont pas validés. Ce n’est pas une notification système.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            _title(context, 'DONNÉES'),
            Card.filled(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.copy_all_outlined),
                    title: const Text('Copier ma sauvegarde'),
                    subtitle: const Text(
                        'Copie toutes vos données sous forme de texte'),
                    onTap: () => _copyBackup(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.restore_outlined),
                    title: const Text('Restaurer une sauvegarde'),
                    subtitle: const Text('Remplace les données actuelles'),
                    onTap: () => _restore(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Text(
                'Toutes vos données restent sur ce téléphone. Aucune connexion Internet n’est utilisée.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.initial});
  final int initial;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late bool _on;
  late double _day;

  @override
  void initState() {
    super.initState();
    _on = widget.initial > 0;
    _day = widget.initial > 0 ? widget.initial.toDouble() : 1;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rappel des versements'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activer le rappel'),
            value: _on,
            onChanged: (v) => setState(() => _on = v),
          ),
          if (_on) ...[
            Text('À partir du ${_day.round()} du mois'),
            Slider(
              min: 1,
              max: 28,
              divisions: 27,
              value: _day,
              label: '${_day.round()}',
              onChanged: (v) => setState(() => _day = v),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _on ? _day.round() : 0),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.store});
  final BudgetStore store;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _c.text = data!.text!;
        _error = null;
      });
    }
  }

  Future<void> _restore() async {
    final text = _c.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Collez d’abord votre sauvegarde');
      return;
    }
    final ok = await _confirm(
      context,
      title: 'Remplacer les données ?',
      message:
          'Vos revenus, charges, livrets et historique actuels seront remplacés par la sauvegarde.',
      action: 'Restaurer',
    );
    if (!ok || !mounted) return;
    if (widget.store.importBackup(text)) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Sauvegarde invalide ou incomplète');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restaurer une sauvegarde'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Collez ici le texte de votre sauvegarde.'),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: '{"version":2,…',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.paste),
              label: const Text('Coller depuis le presse-papiers'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(onPressed: _restore, child: const Text('Restaurer')),
      ],
    );
  }
}
