import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/trade.dart';
import '../../../data/models/worker.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/repositories/master_data_repository.dart';

class WorkersViewModel extends ChangeNotifier with ActionRunner {
  WorkersViewModel({
    required LaborRepository labor,
    required MasterDataRepository masterData,
  }) : _labor = labor,
       _masterData = masterData;

  final LaborRepository _labor;
  final MasterDataRepository _masterData;

  bool _loading = true;
  String? _error;
  List<Worker> _items = const [];
  List<Trade> trades = const [];
  String _query = '';
  String? _tradeFilter;
  bool? _activeFilter;

  bool get isLoading => _loading;
  String? get error => _error;
  String? get tradeFilter => _tradeFilter;
  bool? get activeFilter => _activeFilter;

  int get totalCount => _items.length;
  int get activeCount => _items.where((w) => w.isActive).length;
  int get inactiveCount => _items.where((w) => !w.isActive).length;

  List<String> get availableTrades {
    final names = <String>{
      for (final t in trades) t.name,
      for (final w in _items)
        if (w.trade.trim().isNotEmpty) w.trade.trim(),
    }.toList()..sort();
    return names;
  }

  int get distinctTradeCount =>
      _items.map((w) => w.trade.trim()).where((t) => t.isNotEmpty).toSet().length;

  bool get ratesVisible =>
      _items.isNotEmpty && _items.any((w) => !w.dailyRateHidden);

  double get averageDailyRate {
    final rated = _items.where((w) => w.isActive && !w.dailyRateHidden).toList();
    if (rated.isEmpty) return 0;
    return rated.fold<double>(0, (s, w) => s + w.dailyRate) / rated.length;
  }

  double get totalCashAdvanceBalance =>
      _items.fold<double>(0, (s, w) => s + w.cashAdvanceBalance);

  int get workersWithAdvanceCount =>
      _items.where((w) => w.cashAdvanceBalance > 0).length;

  List<Worker> get items {
    final q = _query.trim().toLowerCase();
    return _items.where((w) {
      if (_tradeFilter != null && w.trade != _tradeFilter) return false;
      if (_activeFilter != null && w.isActive != _activeFilter) return false;
      if (q.isNotEmpty &&
          !w.fullName.toLowerCase().contains(q) &&
          !w.trade.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _labor.getWorkers();
      trades = await _masterData.getTrades();
    } catch (e) {
      _error = 'Could not load workers. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setTradeFilter(String? trade) {
    if (_tradeFilter == trade) return;
    _tradeFilter = trade;
    notifyListeners();
  }

  void setActiveFilter(bool? active) {
    if (_activeFilter == active) return;
    _activeFilter = active;
    notifyListeners();
  }

  Future<String?> save(Worker w) => runAction(() async {
    await _labor.saveWorker(w);
    _items = await _labor.getWorkers();
  });

  Future<String?> toggleActive(Worker w) => save(w.copyWith(isActive: !w.isActive));

  Future<String?> recordCashAdvance(int workerId, double amount) =>
      runAction(() async {
        await _labor.addWorkerCashAdvance(workerId, amount);
        _items = await _labor.getWorkers();
      });
}
