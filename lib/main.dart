import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kAppName = 'Mon budget';
const String kVersion = '2.0.0';
const String kCreator = 'lunikapp';

// ═════════════════════════ Palette ═════════════════════════

const Color _cIncome = Color(0xFF2563EB);
const Color _cFixed = Color(0xFF64748B);
const Color _cVar = Color(0xFFF59E0B);
const Color _cCredit = Color(0xFF8B5CF6);
const Color _cSave = Color(0xFF10B981);
const Color _cOut = Color(0xFFEF4444);

// ═════════════════════════ Utilitaires ═════════════════════════

int _seq = 0;
String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

String _monthKey([DateTime? d]) {
  final n = d ?? DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

String _nowKey() => _monthKey();

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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

const List<String> _weekdaysFr = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
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

int _daysInMonth(String monthKey) =>
    DateTime(_keyYear(monthKey), _keyMonth(monthKey) + 1, 0).day;

String _dateFr(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _dayLabel(String dayKey) {
  final d = DateTime.tryParse(dayKey);
  if (d == null) return dayKey;
  return '${_weekdaysFr[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1].toLowerCase()}';
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

String _pct(double v, double base) {
  if (base <= 0) return '';
  return '${(v / base * 100).round()} %';
}

TextStyle _tnum(TextStyle? s) => (s ?? const TextStyle())
    .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

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

// ───── Dépenses variables ─────

const List<String> _varCategories = [
  'Courses',
  'Carburant',
  'Restaurants & sorties',
  'Santé',
  'Loisirs',
  'Autres frais',
];

const List<Color> _varPalette = [
  Color(0xFF16A34A),
  Color(0xFFEA580C),
  Color(0xFFDB2777),
  Color(0xFF0891B2),
  Color(0xFF7C3AED),
  Color(0xFF64748B),
];

IconData _varIcon(String c) {
  if (c == 'Courses') return Icons.shopping_cart_outlined;
  if (c == 'Carburant') return Icons.local_gas_station_outlined;
  if (c == 'Restaurants & sorties') return Icons.restaurant_outlined;
  if (c == 'Santé') return Icons.medical_services_outlined;
  if (c == 'Loisirs') return Icons.sports_esports_outlined;
  return Icons.more_horiz;
}

Color _varColor(String c) {
  final i = _varCategories.indexOf(c);
  return _varPalette[i < 0 ? _varPalette.length - 1 : i];
}

class VarExpense {
  VarExpense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.note = '',
  });
  final String id;

  /// "AAAA-MM-JJ"
  String date;
  String category;
  double amount;
  String note;

  String get month => date.length >= 7 ? date.substring(0, 7) : _nowKey();

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'category': category,
        'amount': amount,
        'note': note,
      };

  factory VarExpense.fromJson(Map<String, dynamic> j) {
    final cat = (j['category'] ?? 'Autres frais') as String;
    return VarExpense(
      id: j['id'] as String,
      date: (j['date'] ?? _dayKey(DateTime.now())) as String,
      category: _varCategories.contains(cat) ? cat : 'Autres frais',
      amount: (j['amount'] as num).toDouble(),
      note: (j['note'] ?? '') as String,
    );
  }
}

// ───── Crédits ─────

const List<String> _creditKinds = ['fois', 'perso', 'auto', 'immo', 'autre'];

String _creditKindLabel(String k) {
  if (k == 'fois') return 'Paiement en plusieurs fois';
  if (k == 'perso') return 'Crédit personnel';
  if (k == 'auto') return 'Crédit auto';
  if (k == 'immo') return 'Crédit immobilier';
  return 'Autre crédit';
}

IconData _creditKindIcon(String k) {
  if (k == 'fois') return Icons.credit_card;
  if (k == 'perso') return Icons.person_outline;
  if (k == 'auto') return Icons.directions_car_outlined;
  if (k == 'immo') return Icons.home_outlined;
  return Icons.receipt_long_outlined;
}

class Credit {
  Credit({
    required this.id,
    required this.kind,
    required this.name,
    required this.total,
    required this.months,
    required this.monthly,
    required this.start,
  });
  final String id;
  String kind;
  String name;

  /// Montant total à rembourser.
  double total;
  int months;
  double monthly;

  /// Mois du premier prélèvement "AAAA-MM".
  String start;

  String get endMonth => _addMonths(start, months - 1);

  bool dueIn(String key) =>
      key.compareTo(start) >= 0 && key.compareTo(endMonth) <= 0;

  double amountDue(String key) => dueIn(key) ? monthly : 0;

  /// Numéro de la mensualité du mois donné (0 si pas commencé).
  int indexIn(String key) {
    if (key.compareTo(start) < 0) return 0;
    final d = _monthDiff(start, key) + 1;
    return d > months ? months : d;
  }

  int countAfter(String key) => months - indexIn(key);
  double remainingAfter(String key) => countAfter(key) * monthly;
  bool finished(String key) => key.compareTo(endMonth) > 0;
  bool notStarted(String key) => key.compareTo(start) < 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'total': total,
        'months': months,
        'monthly': monthly,
        'start': start,
      };

  factory Credit.fromJson(Map<String, dynamic> j) => Credit(
        id: j['id'] as String,
        kind: (j['kind'] ?? 'autre') as String,
        name: (j['name'] ?? '') as String,
        total: ((j['total'] ?? 0) as num).toDouble(),
        months: ((j['months'] ?? 1) as num).toInt(),
        monthly: ((j['monthly'] ?? 0) as num).toDouble(),
        start: (j['start'] ?? _nowKey()) as String,
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
  const Snapshot({
    required this.income,
    required this.charges,
    required this.saved,
    this.variable = 0,
    this.credits = 0,
  });
  final double income;
  final double charges;
  final double variable;
  final double credits;
  final double saved;

  double get outflow => charges + variable + credits;
  double get balance => income - outflow - saved;
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
  final List<VarExpense> variables = [];
  final List<Credit> credits = [];
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
    final newVars = <VarExpense>[];
    final newCredits = <Credit>[];
    final newLivrets = <Livret>[];
    final newSnaps = <String, Snapshot>{};

    if (j['incomes'] != null) {
      for (final e in j['incomes'] as List) {
        newIncomes.add(Income.fromJson(e as Map<String, dynamic>));
      }
    } else {
      final oldSalary = ((j['salary'] ?? 0) as num).toDouble();
      if (oldSalary > 0) {
        newIncomes
            .add(Income(id: _newId(), name: 'Salaire', amount: oldSalary));
      }
    }
    for (final e in (j['charges'] ?? []) as List) {
      newCharges.add(Charge.fromJson(e as Map<String, dynamic>));
    }
    for (final e in (j['variables'] ?? []) as List) {
      newVars.add(VarExpense.fromJson(e as Map<String, dynamic>));
    }
    for (final e in (j['credits'] ?? []) as List) {
      newCredits.add(Credit.fromJson(e as Map<String, dynamic>));
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
        variable: ((m['variable'] ?? 0) as num).toDouble(),
        credits: ((m['credits'] ?? 0) as num).toDouble(),
      );
    });

    incomes
      ..clear()
      ..addAll(newIncomes);
    charges
      ..clear()
      ..addAll(newCharges);
    variables
      ..clear()
      ..addAll(newVars);
    credits
      ..clear()
      ..addAll(newCredits);
    livrets
      ..clear()
      ..addAll(newLivrets);
    snapshots
      ..clear()
      ..addAll(newSnaps);
  }

  Map<String, dynamic> _data() => {
        'version': 3,
        'incomes': incomes.map((e) => e.toJson()).toList(),
        'charges': charges.map((e) => e.toJson()).toList(),
        'variables': variables.map((e) => e.toJson()).toList(),
        'credits': credits.map((e) => e.toJson()).toList(),
        'livrets': livrets.map((e) => e.toJson()).toList(),
        'snapshots': snapshots.map((k, v) => MapEntry(k, {
              'income': v.income,
              'charges': v.charges,
              'variable': v.variable,
              'credits': v.credits,
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
    final va = variableThisMonth;
    final cr = creditsThisMonth;
    final sv = depositsThisMonth;
    if (inc == 0 && ch == 0 && va == 0 && cr == 0 && sv == 0) {
      snapshots.remove(key);
    } else {
      snapshots[key] = Snapshot(
          income: inc, charges: ch, variable: va, credits: cr, saved: sv);
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

  // Dépenses variables
  List<VarExpense> get variablesThisMonth {
    final k = _nowKey();
    final list = variables.where((v) => v.month == k).toList();
    list.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
    return list;
  }

  double get variableThisMonth {
    final k = _nowKey();
    return variables
        .where((v) => v.month == k)
        .fold(0.0, (s, v) => s + v.amount);
  }

  Map<String, double> variableByCategory(String month) {
    final m = <String, double>{};
    for (final v in variables) {
      if (v.month == month) {
        m[v.category] = (m[v.category] ?? 0) + v.amount;
      }
    }
    return m;
  }

  // Crédits
  double creditsDueIn(String month) =>
      credits.fold(0.0, (s, c) => s + c.amountDue(month));

  double get creditsThisMonth => creditsDueIn(_nowKey());

  double get totalCreditLeft {
    final k = _nowKey();
    return credits.fold(0.0, (s, c) => s + c.remainingAfter(k));
  }

  String? get lastCreditEnd {
    final k = _nowKey();
    String? m;
    for (final c in credits) {
      if (!c.finished(k)) {
        if (m == null || c.endMonth.compareTo(m) > 0) m = c.endMonth;
      }
    }
    return m;
  }

  List<Credit> get sortedCredits {
    final k = _nowKey();
    final list = [...credits];
    list.sort((a, b) {
      final fa = a.finished(k) ? 1 : 0;
      final fb = b.finished(k) ? 1 : 0;
      if (fa != fb) return fa.compareTo(fb);
      return a.endMonth.compareTo(b.endMonth);
    });
    return list;
  }

  // Épargne
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

  double get outflowThisMonth =>
      totalCharges + variableThisMonth + creditsThisMonth + depositsThisMonth;

  /// Solde disponible = revenus − charges fixes − dépenses variables − crédits − épargne versée.
  double get balance => incomeThisMonth - outflowThisMonth;

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

  // ───── Charges fixes ─────

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

  // ───── Dépenses variables ─────

  void addVariable(String date, String category, double amount, String note) {
    variables.add(VarExpense(
        id: _newId(),
        date: date,
        category: category,
        amount: amount,
        note: note));
    _changed();
  }

  void updateVariable(VarExpense v, String date, String category,
      double amount, String note) {
    v.date = date;
    v.category = category;
    v.amount = amount;
    v.note = note;
    _changed();
  }

  void deleteVariable(VarExpense v) {
    variables.remove(v);
    _changed();
  }

  // ───── Crédits ─────

  void addCredit(Credit c) {
    credits.add(c);
    _changed();
  }

  void updateCredit(Credit c, String kind, String name, double total,
      int months, double monthly, String start) {
    c.kind = kind;
    c.name = name;
    c.total = total;
    c.months = months;
    c.monthly = monthly;
    c.start = start;
    _changed();
  }

  void deleteCredit(Credit c) {
    credits.remove(c);
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
    final dark = b == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E5AA8),
      brightness: b,
    );
    final scheme = base.copyWith(
      surface: dark ? const Color(0xFF0F1419) : const Color(0xFFF3F5F9),
    );
    final cardColor = dark ? const Color(0xFF182029) : Colors.white;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withAlpha(140)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: scheme.primaryContainer,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withAlpha(120),
        thickness: 1,
        space: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: kAppName,
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
  String? helper,
  VoidCallback? onSubmit,
  VoidCallback? onChanged,
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
      decoration:
          InputDecoration(labelText: label, suffixText: '€', helperText: helper),
      validator: required
          ? (v) => _parse(v ?? '') > 0 ? null : 'Saisissez un montant'
          : null,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      onFieldSubmitted: last && onSubmit != null ? (_) => onSubmit() : null,
    ),
  );
}

Widget _kv(BuildContext context, String label, String value,
    {bool bold = false, Color? color}) {
  final tt = Theme.of(context).textTheme;
  final style = _tnum(tt.bodyLarge).copyWith(
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

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withAlpha(34),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.amount,
    this.onTap,
    this.onDelete,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? amount;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      leading: _IconBadge(icon: icon, color: color),
      title: Text(title,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (amount != null)
            Text(amount!,
                style: _tnum(tt.titleSmall)
                    .copyWith(fontWeight: FontWeight.w700)),
          if (onDelete != null)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: _tnum(tt.bodySmall)
                          .copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (actionLabel != null)
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: const Icon(Icons.add, size: 18),
              label: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 40, color: cs.primary),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Seg {
  const _Seg(this.color, this.label, this.value);
  final Color color;
  final String label;
  final double value;
}

/// Barre empilée proportionnelle.
Widget _stackedBar(List<_Seg> segs, double base, {double height = 14}) {
  final shown = segs.where((s) => s.value > 0.004).toList();
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      height: height,
      child: Row(
        children: [
          for (final s in shown)
            Expanded(
              flex: (s.value / base * 1000).round().clamp(1, 1000).toInt(),
              child: Container(color: s.color),
            ),
        ],
      ),
    ),
  );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    this.percent = '',
    this.bold = false,
  });
  final Color color;
  final String label;
  final String value;
  final String percent;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final w = bold ? FontWeight.w700 : FontWeight.w500;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: tt.bodyMedium?.copyWith(fontWeight: w))),
          Text(value, style: _tnum(tt.bodyMedium).copyWith(fontWeight: w)),
          SizedBox(
            width: 52,
            child: Text(percent,
                textAlign: TextAlign.right,
                style: _tnum(tt.bodySmall)
                    .copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
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
    const titles = ['Synthèse', 'Dépenses', 'Crédits', 'Livrets', 'Historique'];
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        Widget body;
        Widget? fab;
        switch (_tab) {
          case 0:
            body = _BudgetTab(
                store: store, onOpenLivrets: () => setState(() => _tab = 3));
            break;
          case 1:
            body = _VariablesTab(store: store);
            fab = FloatingActionButton.extended(
              onPressed: () => _sheet(context, VarForm(store: store)),
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle dépense'),
            );
            break;
          case 2:
            body = _CreditsTab(store: store);
            fab = FloatingActionButton.extended(
              onPressed: () => _sheet(context, CreditForm(store: store)),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau crédit'),
            );
            break;
          case 3:
            body = _LivretsTab(store: store);
            fab = FloatingActionButton.extended(
              onPressed: () => _sheet(context, _LivretForm(store: store)),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau livret'),
            );
            break;
          default:
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
          floatingActionButton: fab,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet),
                  label: 'Budget'),
              NavigationDestination(
                  icon: Icon(Icons.shopping_cart_outlined),
                  selectedIcon: Icon(Icons.shopping_cart),
                  label: 'Dépenses'),
              NavigationDestination(
                  icon: Icon(Icons.credit_card_outlined),
                  selectedIcon: Icon(Icons.credit_card),
                  label: 'Crédits'),
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

// ═════════════════════════ Synthèse : solde disponible ═════════════════════════

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.store});
  final BudgetStore store;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final balance = store.balance;
    final negative = balance < -0.004;
    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final disposable = balance - store.plannedSavings;
    final white70 = Colors.white.withAlpha(185);

    Widget stat(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: tt.bodySmall?.copyWith(color: white70)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: _tnum(tt.titleMedium).copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: negative
              ? const [Color(0xFF7F1D1D), Color(0xFFB91C1C)]
              : const [Color(0xFF0B2A4A), Color(0xFF1D5C9E)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _monthLabel(_nowKey()).toUpperCase(),
                  style: tt.labelMedium
                      ?.copyWith(color: white70, letterSpacing: 1.2),
                ),
              ),
              Icon(Icons.account_balance_wallet_outlined, color: white70),
            ],
          ),
          const SizedBox(height: 14),
          Text('Solde disponible',
              style: tt.titleMedium?.copyWith(color: white70)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _eur(balance),
              style: _tnum(tt.displaySmall).copyWith(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              stat('Revenus du mois', _eur(store.incomeThisMonth)),
              stat('Sorties du mois', _eur(store.outflowThisMonth)),
            ],
          ),
          if (!negative && disposable > 0.004) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.today_outlined, size: 18, color: white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Disponible par jour',
                        style: tt.bodyMedium?.copyWith(color: white70)),
                  ),
                  Text('≈ ${_eur(disposable / daysLeft)}',
                      style: _tnum(tt.titleSmall).copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          if (negative) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Vos sorties dépassent vos revenus.',
                      style: tt.bodyMedium?.copyWith(color: Colors.white)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RepartitionCard extends StatelessWidget {
  const _RepartitionCard({required this.store});
  final BudgetStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final income = store.incomeThisMonth;
    final fixed = store.totalCharges;
    final variable = store.variableThisMonth;
    final credits = store.creditsThisMonth;
    final saved = store.depositsThisMonth;
    final outflow = store.outflowThisMonth;
    final balance = store.balance;
    final base = income > outflow ? income : outflow;

    final segs = <_Seg>[
      _Seg(_cFixed, 'Charges fixes', fixed),
      _Seg(_cVar, 'Dépenses variables', variable),
      _Seg(_cCredit, 'Crédits', credits),
      _Seg(_cSave, 'Épargne versée', saved),
      if (balance > 0.004) _Seg(cs.outlineVariant, 'Solde disponible', balance),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Répartition du mois',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            if (base <= 0)
              Text('Ajoutez vos revenus et vos dépenses pour voir la répartition.',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
            else ...[
              _stackedBar(segs, base),
              const SizedBox(height: 12),
              _LegendRow(
                  color: _cIncome,
                  label: 'Revenus',
                  value: _eur(income),
                  bold: true),
              const Divider(height: 8),
              _LegendRow(
                  color: _cFixed,
                  label: 'Charges fixes',
                  value: _eur(fixed),
                  percent: _pct(fixed, income)),
              _LegendRow(
                  color: _cVar,
                  label: 'Dépenses variables',
                  value: _eur(variable),
                  percent: _pct(variable, income)),
              _LegendRow(
                  color: _cCredit,
                  label: 'Crédits',
                  value: _eur(credits),
                  percent: _pct(credits, income)),
              _LegendRow(
                  color: _cSave,
                  label: 'Épargne versée',
                  value: _eur(saved),
                  percent: _pct(saved, income)),
              const Divider(height: 8),
              _LegendRow(
                  color: balance < -0.004 ? _cOut : cs.primary,
                  label: 'Solde disponible',
                  value: _eur(balance),
                  percent: _pct(balance, income),
                  bold: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bandeau compact « solde disponible » affiché dans les autres onglets.
class _SoldeBar extends StatelessWidget {
  const _SoldeBar({required this.store});
  final BudgetStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final b = store.balance;
    final neg = b < -0.004;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Solde disponible',
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Text(_eur(b),
                style: _tnum(tt.titleMedium).copyWith(
                    fontWeight: FontWeight.w800,
                    color: neg ? cs.error : cs.primary)),
          ],
        ),
      ),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (store.needsReminder) ...[
          Card(
            color: cs.tertiaryContainer,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(Icons.notifications_active_outlined,
                  color: cs.onTertiaryContainer),
              title: Text('Versements du mois à valider',
                  style: tt.titleSmall?.copyWith(
                      color: cs.onTertiaryContainer,
                      fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${store.pendingPaymentsCount} livret(s) en attente. Touchez pour ouvrir.',
                  style: tt.bodyMedium?.copyWith(color: cs.onTertiaryContainer)),
              onTap: onOpenLivrets,
            ),
          ),
          const SizedBox(height: 16),
        ],
        _BalanceHero(store: store),
        const SizedBox(height: 16),
        _RepartitionCard(store: store),
        const SizedBox(height: 28),

        // ───── Revenus ─────
        _SectionHeader(
          title: 'Revenus',
          subtitle: 'Total ce mois-ci : ${_eur(store.incomeThisMonth)}',
          actionLabel: 'Ajouter',
          onAction: () => _sheet(context, _IncomeForm(store: store)),
        ),
        if (incomes.isEmpty)
          const _EmptyCard(
            icon: Icons.trending_up,
            text:
                'Aucun revenu.\nAjoutez votre salaire, une prime, des allocations…',
          )
        else
          _Group(
            children: [
              for (final i in incomes)
                _Tile(
                  icon: Icons.trending_up,
                  color: _cIncome,
                  title: i.name,
                  subtitle: i.month == null ? 'Chaque mois' : 'Ce mois-ci seulement',
                  amount: _eur(i.amount),
                  onTap: () =>
                      _sheet(context, _IncomeForm(store: store, income: i)),
                  onDelete: () => store.deleteIncome(i),
                ),
            ],
          ),
        const SizedBox(height: 28),

        // ───── Charges fixes ─────
        _SectionHeader(
          title: 'Charges fixes',
          subtitle: store.hasDatedCharges
              ? 'Total : ${_eur(store.totalCharges)} · encore à venir : ${_eur(store.chargesStillToCome)}'
              : 'Total : ${_eur(store.totalCharges)}',
          actionLabel: 'Ajouter',
          onAction: () => _sheet(context, _ChargeForm(store: store)),
        ),
        if (charges.isEmpty)
          const _EmptyCard(
            icon: Icons.receipt_long_outlined,
            text:
                'Aucune charge fixe pour le moment.\nAjoutez votre loyer, abonnements, assurances…',
          )
        else
          _Group(
            children: [
              for (final c in charges)
                _Tile(
                  icon: Icons.receipt_long_outlined,
                  color: _cFixed,
                  title: c.name,
                  subtitle: c.day > 0 ? 'Le ${c.day} du mois' : 'Chaque mois',
                  amount: _eur(c.amount),
                  onTap: () =>
                      _sheet(context, _ChargeForm(store: store, charge: c)),
                  onDelete: () => store.deleteCharge(c),
                ),
            ],
          ),
        const SizedBox(height: 28),
        Center(
          child: Text('$kAppName · v$kVersion · $kCreator',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ],
    );
  }
}

// ═════════════════════════ Onglet Dépenses variables ═════════════════════════

class _VariablesTab extends StatelessWidget {
  const _VariablesTab({required this.store});
  final BudgetStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final list = store.variablesThisMonth;
    final total = store.variableThisMonth;
    final byCat = store.variableByCategory(_nowKey());
    final cats = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Regroupement par jour
    final days = <String, List<VarExpense>>{};
    for (final v in list) {
      days.putIfAbsent(v.date, () => []).add(v);
    }
    final dayKeys = days.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _SoldeBar(store: store),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dépenses variables · ${_monthLabelLower(_nowKey())}',
                    style:
                        tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_eur(total),
                      style: _tnum(tt.headlineMedium)
                          .copyWith(fontWeight: FontWeight.w800)),
                ),
                if (cats.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _stackedBar([
                    for (final e in cats) _Seg(_varColor(e.key), e.key, e.value),
                  ], total),
                  const SizedBox(height: 10),
                  for (final e in cats)
                    _LegendRow(
                      color: _varColor(e.key),
                      label: e.key,
                      value: _eur(e.value),
                      percent: _pct(e.value, total),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Ajout rapide',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _varCategories)
              ActionChip(
                avatar: Icon(_varIcon(c), size: 18, color: _varColor(c)),
                label: Text(c),
                onPressed: () =>
                    _sheet(context, VarForm(store: store, category: c)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (list.isEmpty)
          const _EmptyCard(
            icon: Icons.shopping_cart_outlined,
            text:
                'Aucune dépense ce mois-ci.\nNotez vos courses, carburant et autres frais.',
          )
        else
          for (final k in dayKeys) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(_dayLabel(k),
                  style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            ),
            _Group(
              children: [
                for (final v in days[k]!)
                  _Tile(
                    icon: _varIcon(v.category),
                    color: _varColor(v.category),
                    title: v.note.isEmpty ? v.category : v.note,
                    subtitle: v.note.isEmpty ? null : v.category,
                    amount: '- ${_eur(v.amount)}',
                    onTap: () =>
                        _sheet(context, VarForm(store: store, expense: v)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class VarForm extends StatefulWidget {
  const VarForm({super.key, required this.store, this.expense, this.category});
  final BudgetStore store;
  final VarExpense? expense;
  final String? category;

  @override
  State<VarForm> createState() => _VarFormState();
}

class _VarFormState extends State<VarForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _category;
  late String _month;
  late int _day;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _amount = TextEditingController(text: _num(e?.amount ?? 0));
    _note = TextEditingController(text: e?.note ?? '');
    _category = e?.category ?? widget.category ?? _varCategories.first;
    if (e != null) {
      _month = e.month;
      _day = e.date.length >= 10 ? (int.tryParse(e.date.substring(8, 10)) ?? 1) : 1;
    } else {
      _month = _nowKey();
      _day = DateTime.now().day;
    }
    final max = _daysInMonth(_month);
    if (_day > max) _day = max;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final date = _dayKey(DateTime(_keyYear(_month), _keyMonth(_month), _day));
    final amount = _parse(_amount.text);
    final note = _note.text.trim();
    final e = widget.expense;
    if (e == null) {
      widget.store.addVariable(date, _category, amount, note);
    } else {
      widget.store.updateVariable(e, date, _category, amount, note);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isNew = widget.expense == null;
    final maxDay = _daysInMonth(_month);
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
              Text(isNew ? 'Nouvelle dépense' : 'Modifier la dépense',
                  style: tt.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _varCategories)
                    ChoiceChip(
                      avatar: Icon(_varIcon(c), size: 18, color: _varColor(c)),
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              _moneyField(_amount, 'Montant',
                  required: true, autofocus: isNew),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Note (facultatif, ex. Leclerc)'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: 'Jour · ${_monthLabelLower(_month)}'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _day,
                      items: [
                        for (var d = 1; d <= maxDay; d++)
                          DropdownMenuItem<int>(value: d, child: Text('$d')),
                      ],
                      onChanged: (v) => setState(() => _day = v ?? _day),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(isNew ? 'Ajouter' : 'Enregistrer'),
              ),
              if (!isNew) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    widget.store.deleteVariable(widget.expense!);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer la dépense'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ Onglet Crédits ═════════════════════════

class _CreditsTab extends StatelessWidget {
  const _CreditsTab({required this.store});
  final BudgetStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = _nowKey();
    final next = _addMonths(now, 1);
    final credits = store.sortedCredits;
    final end = store.lastCreditEnd;

    final upcoming = [for (var i = 1; i <= 6; i++) _addMonths(now, i)];
    final amounts = upcoming.map((m) => store.creditsDueIn(m)).toList();
    var maxAmount = 0.0;
    for (final a in amounts) {
      if (a > maxAmount) maxAmount = a;
    }

    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: _tnum(tt.titleMedium).copyWith(
                        fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _SoldeBar(store: store),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vue d’ensemble',
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    stat('Ce mois-ci', _eur(store.creditsThisMonth),
                        color: _cCredit),
                    stat('Mois prochain', _eur(store.creditsDueIn(next))),
                    stat('Reste à rembourser', _eur(store.totalCreditLeft)),
                  ],
                ),
                if (end != null) ...[
                  const SizedBox(height: 12),
                  Text('Dernier crédit terminé en ${_monthLabelLower(end)}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 4),
                Text('« Reste à rembourser » exclut la mensualité du mois en cours.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        if (credits.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mensualités à venir',
                      style: tt.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < upcoming.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 76,
                            child: Text(
                                '${_monthShort[_keyMonth(upcoming[i]) - 1]} ${_keyYear(upcoming[i])}',
                                style: tt.bodyMedium),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value:
                                    maxAmount > 0 ? amounts[i] / maxAmount : 0,
                                minHeight: 10,
                                color: _cCredit,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 92,
                            child: Text(_eur(amounts[i]),
                                textAlign: TextAlign.right,
                                style: _tnum(tt.bodyMedium)
                                    .copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (credits.isEmpty)
          const _EmptyCard(
            icon: Icons.credit_card_outlined,
            text:
                'Aucun crédit.\nAjoutez un paiement en plusieurs fois, un crédit perso, auto ou immobilier.',
          )
        else
          for (final c in credits)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _CreditCard(store: store, credit: c),
            ),
      ],
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.store, required this.credit});
  final BudgetStore store;
  final Credit credit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = credit;
    final now = _nowKey();
    final finished = c.finished(now);
    final idx = c.indexIn(now);
    final progress = c.months > 0 ? idx / c.months : 0.0;
    final status = finished
        ? 'Terminé'
        : c.notStarted(now)
            ? 'Débute en ${_monthLabelLower(c.start)}'
            : 'Mensualité $idx / ${c.months}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconBadge(
                    icon: _creditKindIcon(c.kind),
                    color: finished ? cs.outline : _cCredit),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_creditKindLabel(c.kind),
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      _sheet(context, CreditForm(store: store, credit: c));
                    } else {
                      final ok = await _confirm(
                        context,
                        title: 'Supprimer ce crédit ?',
                        message: '« ${c.name} » sera définitivement supprimé.',
                      );
                      if (ok) store.deleteCredit(c);
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
              padding: const EdgeInsets.only(right: 12, top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0).toDouble(),
                      minHeight: 12,
                      color: finished ? cs.outline : _cCredit,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(status,
                      style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: finished ? cs.onSurfaceVariant : _cCredit)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _Stat('Mensualité', _eur(c.monthly))),
                      Expanded(
                          child: _Stat('Montant total', _eur(c.total))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          'Reste à payer',
                          finished ? _eur(0) : _eur(c.remainingAfter(now)),
                          highlight: true,
                        ),
                      ),
                      Expanded(
                        child: _Stat(
                          'Dernière échéance',
                          _monthLabelLower(c.endMonth),
                        ),
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
}

class CreditForm extends StatefulWidget {
  const CreditForm({super.key, required this.store, this.credit});
  final BudgetStore store;
  final Credit? credit;

  @override
  State<CreditForm> createState() => _CreditFormState();
}

class _CreditFormState extends State<CreditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _total;
  late final TextEditingController _monthsCtl;
  late final TextEditingController _monthlyCtl;
  late String _kind;
  late int _fois;
  late int _sMonth;
  late int _sYear;

  @override
  void initState() {
    super.initState();
    final c = widget.credit;
    _name = TextEditingController(text: c?.name ?? '');
    _total = TextEditingController(text: _num(c?.total ?? 0));
    _kind = c?.kind ?? 'fois';
    _fois = (c != null && c.kind == 'fois') ? c.months.clamp(2, 10).toInt() : 3;
    _monthsCtl = TextEditingController(
        text: (c != null && c.kind != 'fois') ? '${c.months}' : '12');
    var monthlyText = '';
    if (c != null && c.months > 0) {
      final auto = (c.total / c.months * 100).round() / 100;
      if ((c.monthly - auto).abs() > 0.011) monthlyText = _num(c.monthly);
    }
    _monthlyCtl = TextEditingController(text: monthlyText);
    final start = c?.start ?? _nowKey();
    _sMonth = _keyMonth(start);
    _sYear = _keyYear(start);
  }

  @override
  void dispose() {
    _name.dispose();
    _total.dispose();
    _monthsCtl.dispose();
    _monthlyCtl.dispose();
    super.dispose();
  }

  int get _curMonths =>
      _kind == 'fois' ? _fois : (int.tryParse(_monthsCtl.text.trim()) ?? 0);

  double get _autoMonthly {
    final m = _curMonths;
    if (m <= 0) return 0;
    return (_parse(_total.text) / m * 100).round() / 100;
  }

  double get _finalMonthly {
    final o = _parse(_monthlyCtl.text);
    return o > 0 ? o : _autoMonthly;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final total = _parse(_total.text);
    final months = _curMonths;
    final start = _keyOf(_sYear, _sMonth);
    final c = widget.credit;
    if (c == null) {
      widget.store.addCredit(Credit(
        id: _newId(),
        kind: _kind,
        name: _name.text.trim(),
        total: total,
        months: months,
        monthly: _finalMonthly,
        start: start,
      ));
    } else {
      widget.store.updateCredit(
          c, _kind, _name.text.trim(), total, months, _finalMonthly, start);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isNew = widget.credit == null;
    final nowYear = DateTime.now().year;
    final firstYear = _sYear < nowYear - 1 ? _sYear : nowYear - 1;
    final lastYear = _sYear > nowYear + 3 ? _sYear : nowYear + 3;
    final years = [for (var y = firstYear; y <= lastYear; y++) y];
    final months = _curMonths;
    final end = months > 0 ? _addMonths(_keyOf(_sYear, _sMonth), months - 1) : null;

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
              Text(isNew ? 'Nouveau crédit' : 'Modifier le crédit',
                  style: tt.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in _creditKinds)
                    ChoiceChip(
                      avatar: Icon(_creditKindIcon(k), size: 18),
                      label: Text(_creditKindLabel(k)),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextFormField(
                  controller: _name,
                  autofocus: isNew,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Nom (ex. Canapé, Voiture, Maison)'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Saisissez un nom'
                      : null,
                ),
              ),
              _moneyField(_total, 'Montant total à rembourser',
                  required: true, onChanged: () => setState(() {})),
              const SizedBox(height: 12),
              if (_kind == 'fois') ...[
                Row(
                  children: [
                    Expanded(
                      child: Text('Nombre de paiements',
                          style: tt.bodyLarge),
                    ),
                    Text('$_fois fois',
                        style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700, color: cs.primary)),
                  ],
                ),
                Slider(
                  min: 2,
                  max: 10,
                  divisions: 8,
                  value: _fois.toDouble(),
                  label: '$_fois fois',
                  onChanged: (v) => setState(() => _fois = v.round()),
                ),
              ] else
                TextFormField(
                  controller: _monthsCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Durée',
                    suffixText: 'mois',
                    helperText: 'Ex. 60 mois pour un crédit auto sur 5 ans',
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim()) ?? 0;
                    if (n < 1 || n > 480) return 'Entre 1 et 480 mois';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: 12),
              Card(
                color: cs.primaryContainer,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.calculate_outlined,
                          color: cs.onPrimaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Mensualité',
                            style: tt.bodyLarge
                                ?.copyWith(color: cs.onPrimaryContainer)),
                      ),
                      Text(_eur(_finalMonthly),
                          style: _tnum(tt.titleMedium).copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onPrimaryContainer)),
                    ],
                  ),
                ),
              ),
              _moneyField(
                _monthlyCtl,
                'Mensualité réelle (facultatif)',
                helper: 'À remplir si elle diffère (intérêts, assurance…)',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration:
                    const InputDecoration(labelText: 'Première mensualité'),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _sMonth,
                          items: [
                            for (var i = 0; i < 12; i++)
                              DropdownMenuItem<int>(
                                  value: i + 1, child: Text(_monthNames[i])),
                          ],
                          onChanged: (v) =>
                              setState(() => _sMonth = v ?? _sMonth),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _sYear,
                          items: [
                            for (final y in years)
                              DropdownMenuItem<int>(
                                  value: y, child: Text('$y')),
                          ],
                          onChanged: (v) =>
                              setState(() => _sYear = v ?? _sYear),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (end != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Dernière mensualité : ${_monthLabelLower(end)}',
                      style:
                          tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(isNew ? 'Ajouter le crédit' : 'Enregistrer'),
              ),
            ],
          ),
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
        _SoldeBar(store: store),
        const SizedBox(height: 12),
        if (store.livrets.isNotEmpty) ...[
          Card(
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
                              style: _tnum(tt.titleLarge).copyWith(
                                  color: _cSave,
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
                              style: _tnum(tt.titleLarge)
                                  .copyWith(fontWeight: FontWeight.bold)),
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
          const _EmptyCard(
            icon: Icons.savings_outlined,
            text:
                'Aucun livret.\nAppuyez sur « Nouveau livret » pour commencer.',
          )
        else
          for (final l in store.livrets)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _LivretCard(store: store, livret: l),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _IconBadge(icon: Icons.savings_outlined, color: _cSave),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(l.name,
                      style:
                          tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: l.progress,
                      minHeight: 12,
                      color: _cSave,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('$pct %',
                      style: tt.titleSmall?.copyWith(
                          color: _cSave, fontWeight: FontWeight.bold)),
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
                            child: Text('Pour y arriver : ${_eur(req)} / mois',
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
              style: _tnum(tt.titleMedium).copyWith(
                  fontWeight: FontWeight.w700,
                  color: highlight ? cs.primary : cs.onSurface)),
        ),
      ],
    );
  }
}

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
                      style:
                          tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
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
            'L’historique se construit tout seul au fil des mois.\nAjoutez vos revenus et vos dépenses pour commencer.',
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Derniers mois',
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                _MonthChart(entries: last6),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    legend(_cIncome, 'Revenus'),
                    legend(_cOut, 'Dépenses'),
                    legend(_cSave, 'Épargne'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
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
                            style: _tnum(tt.titleLarge).copyWith(
                                color: _cSave, fontWeight: FontWeight.bold)),
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
                            style: _tnum(tt.titleLarge)
                                .copyWith(fontWeight: FontWeight.bold)),
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
    final tt = Theme.of(context).textTheme;
    var maxV = 1.0;
    for (final e in entries) {
      for (final v in [e.value.income, e.value.outflow, e.value.saved]) {
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
                      bar(e.value.income, _cIncome),
                      bar(e.value.outflow, _cOut),
                      bar(e.value.saved, _cSave),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_monthShort[_keyMonth(e.key) - 1], style: tt.bodySmall),
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
    final deposits = store.depositsByLivret(monthKey);
    final varCats = store.variableByCategory(monthKey).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rate = snap.income > 0 ? snap.saved / snap.income * 100 : null;
    final balColor = snap.balance < -0.004 ? cs.error : cs.primary;

    return Card(
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
            _kv(context, 'Dépenses variables', _eur(snap.variable)),
            _kv(context, 'Crédits', _eur(snap.credits)),
            _kv(context, 'Épargne versée', _eur(snap.saved)),
            const SizedBox(height: 6),
            Divider(color: cs.outlineVariant, height: 1),
            _kv(context, 'Solde du mois', _eur(snap.balance),
                bold: true, color: balColor),
            if (rate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Taux d’épargne : ${rate.toStringAsFixed(1)} %',
                    style:
                        tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
            if (varCats.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Détail des dépenses variables',
                  style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
              for (final d in varCats)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${d.key} : ${_eur(d.value)}',
                      style: tt.bodyMedium),
                ),
            ],
            if (deposits.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Détail de l’épargne',
                  style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
              for (final d in deposits.entries)
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
              _moneyField(_amount, 'Montant',
                  required: true, last: true, onSubmit: _submit),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Seulement ce mois-ci'),
                subtitle: const Text('Sinon ce revenu est compté chaque mois.'),
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
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
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
            Card(
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
            Card(
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
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.copy_all_outlined),
                    title: const Text('Copier ma sauvegarde'),
                    subtitle:
                        const Text('Copie toutes vos données sous forme de texte'),
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
            _title(context, 'À PROPOS'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF0B2A4A), Color(0xFF1D5C9E)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.account_balance_wallet,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(kAppName,
                                  style: tt.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              Text('Version $kVersion',
                                  style: tt.bodyMedium
                                      ?.copyWith(color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.verified_outlined, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: tt.bodyLarge,
                              children: [
                                const TextSpan(text: 'Conçu et développé par '),
                                TextSpan(
                                  text: kCreator,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: cs.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('© 2026 $kCreator. Tous droits réservés.',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
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
          'Vos revenus, charges, dépenses, crédits, livrets et historique actuels seront remplacés par la sauvegarde.',
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
                hintText: '{"version":3,…',
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
