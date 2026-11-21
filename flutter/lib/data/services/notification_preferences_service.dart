import 'package:flutter/foundation.dart' show ChangeNotifier;

/// Controls in-app notification & sidebar badge visibility.
class NotificationPreferencesService extends ChangeNotifier {
  bool _showSidebarRequestBadges = true;
  bool _showBellBadge = true;

  bool get showSidebarRequestBadges => _showSidebarRequestBadges;
  bool get showBellBadge => _showBellBadge;

  void setShowSidebarRequestBadges(bool value) {
    if (_showSidebarRequestBadges == value) return;
    _showSidebarRequestBadges = value;
    notifyListeners();
  }

  void setShowBellBadge(bool value) {
    if (_showBellBadge == value) return;
    _showBellBadge = value;
    notifyListeners();
  }
}
