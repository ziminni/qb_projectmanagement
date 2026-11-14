import 'package:get_it/get_it.dart';

import '../../data/repositories/audit_log_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/http_audit_log_repository.dart';
import '../../data/repositories/http_auth_repository.dart';
import '../../data/repositories/http_client_repository.dart';
import '../../data/repositories/http_company_repository.dart';
import '../../data/repositories/http_daily_report_repository.dart';
import '../../data/repositories/http_document_repository.dart';
import '../../data/repositories/http_master_data_repository.dart';
import '../../data/repositories/http_notification_repository.dart';
import '../../data/repositories/http_procurement_repository.dart';
import '../../data/repositories/http_project_repository.dart';
import '../../data/repositories/http_schedule_repository.dart';
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
import '../../data/repositories/mock_user_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/procurement_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/store_catalog_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/approval_inbox.dart';
import '../../data/services/approval_sources.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/project_cost_service.dart';
import '../../data/services/session_service.dart';
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
    ..registerLazySingleton<SessionService>(SessionService.new);
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
    ..registerLazySingleton<MasterDataRepository>(
      () => useApi
          ? HttpMasterDataRepository(getIt<ApiClient>())
          : MockMasterDataRepository(),
    )
    ..registerLazySingleton<StoreCatalogRepository>(
      MockStoreCatalogRepository.new,
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
      () => MockBillingRepository(
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
      () => MockLaborRepository(
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
