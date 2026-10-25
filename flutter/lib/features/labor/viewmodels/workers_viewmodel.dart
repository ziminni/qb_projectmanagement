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
  List<Worker> _items = const [];
  List<Trade> trades = const [];
  String _query = '';

  bool get isLoading => _loading;

  List<Worker> get items {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where(
          (w) =>
              w.fullName.toLowerCase().contains(q) ||
              w.trade.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> load() async {
    _items = await _labor.getWorkers();
    trades = await _masterData.getTrades();
    _loading = false;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  Future<String?> save(Worker w) => runAction(() async {
    await _labor.saveWorker(w);
    _items = await _labor.getWorkers();
  });
}
