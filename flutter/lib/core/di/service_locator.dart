import 'package:get_it/get_it.dart';

import '../../data/repositories/audit_log_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/http_audit_log_repository.dart';
import '../../data/repositories/http_auth_repository.dart';
import '../../data/repositories/http_billing_repository.dart';
import '../../data/repositories/http_client_repository.dart';
import '../../data/repositories/http_company_repository.dart';
import '../../data/repositories/http_daily_report_repository.dart';
import '../../data/repositories/http_document_repository.dart';
import '../../data/repositories/http_labor_repository.dart';
import '../../data/repositories/http_master_data_repository.dart';
import '../../data/repositories/http_notification_repository.dart';
import '../../data/repositories/http_procurement_repository.dart';
import '../../data/repositories/http_project_repository.dart';
import '../../data/repositories/http_schedule_repository.dart';
import '../../data/repositories/http_store_catalog_repository.dart';
import '../../data/repositories/http_system_admin_repository.dart';
import '../../data/repositories/http_user_repository.dart';
import '../../data/repositories/mock_auth_repository.dart';
import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/client_repository.dart';
import '../../data/repositories/company_repository.dart';
import '../../data/repositories/daily_report_repository.dart';
import '../../data/repositories/document_repository.dart';
import '../../data/repositories/labor_repository.dart';
import '../../data/repositories/master_data_repository.dart';
import '../../data/repositories/mock_daily_report_repository.dart';
import '../../data/repositories/mock_document_repository.dart';
import '../../data/repositories/mock_audit_log_repository.dart';
import '../../data/repositories/mock_billing_repository.dart';
import '../../data/repositories/mock_client_repository.dart';
import '../../data/repositories/mock_company_repository.dart';
import '../../data/repositories/mock_master_data_repository.dart';
import '../../data/repositories/mock_project_repository.dart';
import '../../data/repositories/mock_schedule_repository.dart';
import '../../data/repositories/mock_labor_repository.dart';
import '../../data/repositories/mock_notification_repository.dart';
import '../../data/repositories/mock_procurement_repository.dart';
import '../../data/repositories/mock_store_catalog_repository.dart';
import '../../data/repositories/mock_system_admin_repository.dart';
import '../../data/repositories/mock_user_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/procurement_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/store_catalog_repository.dart';
import '../../data/repositories/system_admin_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/approval_inbox.dart';
import '../../data/services/approval_sources.dart';
import '../../data/services/category_catalog_service.dart';
import '../../data/services/local_settings_service.dart';
import '../../data/services/notification_preferences_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/project_cost_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/workspace_preferences_service.dart';
import '../network/api_client.dart';
import '../network/api_config.dart';
import '../network/private_file_loader.dart';
import '../network/token_store.dart';

final getIt = GetIt.instance;

/// Registers services and repositories. Mocks by default so tests and the
/// offline demo keep working; run with `--dart-define=USE_API=true` to talk to
/// the backend (task 5.2 makes that the default).
void setupServiceLocator() {
  getIt
    ..registerLazySingleton<NotificationService>(
      () => NotificationService(notifications: getIt()),
    )
    ..registerLazySingleton<NotificationPreferencesService>(
      NotificationPreferencesService.new,
    )
    ..registerLazySingleton<WorkspacePreferencesService>(
      WorkspacePreferencesService.new,
    )
    ..registerLazySingleton<LocalSettingsService>(
      () => LocalSettingsService()..load(),
    )
    ..registerLazySingleton<SessionService>(SessionService.new)
    ..registerLazySingleton<CategoryCatalogService>(
      () => CategoryCatalogService(
        projects: getIt<ProjectRepository>(),
        schedule: getIt<ScheduleRepository>(),
      ),
    );
  _registerAccountRepositories();
  getIt
    ..registerLazySingleton<ProjectRepository>(() {
      if (useApi) {
        final repo = HttpProjectRepository(getIt<ApiClient>());
        // Still-mocked Phase 3/4 repositories find recipients through this.
        getIt<NotificationService>().projects = repo;
        return repo;
      }
      final repo = MockProjectRepository(
        users: getIt<UserRepository>(),
        auditLog: getIt<AuditLogRepository>(),
        notifications: getIt<NotificationService>(),
      );
      getIt<NotificationService>().projects = repo;
      return repo;
    })
    ..registerLazySingleton<CompanyRepository>(
      () => useApi
          ? HttpCompanyRepository(getIt<ApiClient>())
          : MockCompanyRepository(),
    )
    ..registerLazySingleton<SystemAdminRepository>(
      () => useApi
          ? HttpSystemAdminRepository(getIt<ApiClient>())
          : MockSystemAdminRepository(),
    )
    ..registerLazySingleton<MasterDataRepository>(
      () => useApi
          ? HttpMasterDataRepository(getIt<ApiClient>())
          : MockMasterDataRepository(),
    )
    ..registerLazySingleton<StoreCatalogRepository>(
      // The own store's catalogue is the server's master data (only materials
      // with a POS code), so an own-store line carries a material id the
      // server can resolve.
      () => useApi
          ? HttpStoreCatalogRepository(getIt<ApiClient>())
          : MockStoreCatalogRepository(),
    )
    ..registerLazySingleton<PrivateFileLoader>(
      () => PrivateFileLoader(useApi ? getIt<ApiClient>() : null),
    )
    ..registerLazySingleton<ClientRepository>(
      () => useApi
          ? HttpClientRepository(getIt<ApiClient>())
          : MockClientRepository(),
    )
    ..registerLazySingleton<ScheduleRepository>(
      () => useApi
          ? HttpScheduleRepository(getIt<ApiClient>())
          : MockScheduleRepository(
              projects: getIt<ProjectRepository>(),
              auditLog: getIt<AuditLogRepository>(),
              notifications: getIt<NotificationService>(),
            ),
    )
    ..registerLazySingleton<ApprovalInbox>(
      () => ApprovalInbox([
        TodoVerificationSource(projects: getIt(), schedule: getIt()),
        DailyReportApprovalSource(projects: getIt(), reports: getIt()),
        MaterialRequestApprovalSource(projects: getIt(), procurement: getIt()),
        PayrollVerificationSource(projects: getIt(), labor: getIt()),
        VariationOrderApprovalSource(projects: getIt(), billing: getIt()),
      ]),
    )
    ..registerLazySingleton<BillingRepository>(
      // In API mode the server owns every billing status, amount, VO pricing
      // and audit row: every method has a route (slice 4.2a), so the mock's
      // local ledgers never run.
      () => useApi
          ? HttpBillingRepository(getIt<ApiClient>())
          : MockBillingRepository(
              projects: getIt(),
              schedule: getIt(),
              users: getIt(),
              auditLog: getIt(),
              notifications: getIt(),
            ),
    )
    ..registerLazySingleton<DocumentRepository>(
      () => useApi
          ? HttpDocumentRepository(getIt<ApiClient>())
          : MockDocumentRepository(projects: getIt()),
    )
    ..registerLazySingleton<ProjectCostService>(
      () => ProjectCostService(
        procurement: getIt(),
        labor: getIt(),
        reports: getIt(),
        masterData: getIt(),
      ),
    )
    ..registerLazySingleton<LaborRepository>(
      // In API mode the server owns workers, attendance and every rule: the
      // mock's local payroll never runs, and payroll methods refuse instead
      // of inventing periods or costs.
      () => useApi
          ? HttpLaborRepository(getIt<ApiClient>())
          : MockLaborRepository(
              projects: getIt(),
              users: getIt(),
              auditLog: getIt(),
              notifications: getIt(),
            ),
    )
    ..registerLazySingleton<ProcurementRepository>(
      // In API mode the server owns every rule and every amount: the mock's
      // local approval and payment paths never run, and the financially
      // blocked methods refuse instead of faking a ledger.
      () => useApi
          ? HttpProcurementRepository(getIt<ApiClient>())
          : MockProcurementRepository(
              projects: getIt(),
              schedule: getIt(),
              masterData: getIt(),
              reports: getIt(),
              users: getIt(),
              auditLog: getIt(),
              notifications: getIt(),
            ),
    )
    ..registerLazySingleton<DailyReportRepository>(
      // In API mode the report IS the server's: the mock's to-do linking and
      // its unsupported `setReportLink` call never run.
      () => useApi
          ? HttpDailyReportRepository(getIt<ApiClient>())
          : MockDailyReportRepository(
              projects: getIt(),
              schedule: getIt(),
              auditLog: getIt(),
              notifications: getIt(),
            ),
    );
}

/// The four repositories phase 1 swaps for HTTP implementations. Everything
/// else stays mocked until its own phase ships endpoints.
void _registerAccountRepositories() {
  if (useApi) {
    getIt
      ..registerLazySingleton<TokenStore>(SecureTokenStore.new)
      ..registerLazySingleton<ApiClient>(
        () => ApiClient(tokens: getIt(), session: getIt()),
      )
      ..registerLazySingleton<UserRepository>(() => HttpUserRepository(getIt()))
      ..registerLazySingleton<AuthRepository>(() => HttpAuthRepository(getIt()))
      ..registerLazySingleton<NotificationRepository>(
        () => HttpNotificationRepository(getIt()),
      )
      ..registerLazySingleton<AuditLogRepository>(
        () => HttpAuditLogRepository(getIt()),
      );
    return;
  }
  getIt
    ..registerLazySingleton<NotificationRepository>(
      MockNotificationRepository.new,
    )
    ..registerLazySingleton<UserRepository>(MockUserRepository.new)
    ..registerLazySingleton<AuthRepository>(
      () => MockAuthRepository(users: getIt<UserRepository>()),
    )
    ..registerLazySingleton<AuditLogRepository>(MockAuditLogRepository.new);
}
