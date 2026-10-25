import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/supplier.dart';
import '../../../data/repositories/master_data_repository.dart';

class SuppliersViewModel extends ChangeNotifier with ActionRunner {
  SuppliersViewModel({required MasterDataRepository masterData})
    : _masterData = masterData;

  final MasterDataRepository _masterData;

  bool _loading = true;
  List<Supplier> _items = const [];

  bool get isLoading => _loading;
  List<Supplier> get items => _items;

  Future<void> load() async {
    _items = await _masterData.getSuppliers();
    _loading = false;
    notifyListeners();
  }

  Future<String?> save(Supplier s) => runAction(() async {
    await _masterData.saveSupplier(s);
    _items = await _masterData.getSuppliers();
  });
}
