import '../../data/models/app_role.dart';
import '../../data/services/session_service.dart';
import '../di/service_locator.dart';

/// Whether the signed-in role may see peso amounts. See [AppRole.seesFinance].
bool canSeeFinance() =>
    getIt<SessionService>().activeRole?.seesFinance ?? false;

/// Whether the signed-in role may record or change money.
/// See [AppRole.managesFinance].
bool canManageFinance() =>
    getIt<SessionService>().activeRole?.managesFinance ?? false;
