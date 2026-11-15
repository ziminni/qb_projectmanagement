import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../data/services/business_rule_exception.dart';

/// Runs view-model actions with a shared busy flag and turns failures into a
/// message for the UI. Actions return null on success.
mixin ActionRunner on ChangeNotifier {
  bool _busy = false;

  /// True while an action is in flight.
  bool get isBusy => _busy;

  Future<String?> runAction(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
      return null;
    } on BusinessRuleException catch (e) {
      return e.message;
    } catch (e) {
      return 'Something went wrong. $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
