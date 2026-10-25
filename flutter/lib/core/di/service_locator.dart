import 'package:get_it/get_it.dart';

import '../../data/repositories/audit_log_repository.dart';
import '../../data/repositories/auth_repository.dart';
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
import '../../data/repositories/mock_user_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/procurement_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/approval_inbox.dart';
import '../../data/services/approval_sources.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/project_cost_service.dart';
import '../../data/services/session_service.dart';

final getIt = GetIt.instance;

/// Registers services and repositories. Mock implementations are used until
/// the API client in `core/network` exists.
void setupServiceLocator() {
  getIt
    ..registerLazySingleton<NotificationRepository>(
      MockNotificationRepository.new,
    )
    ..registerLazySingleton<NotificationService>(
      () => NotificationService(notifications: getIt()),
    )
    ..registerLazySingleton<SessionService>(SessionService.new)
    ..registerLazySingleton<UserRepository>(MockUserRepository.new)
    ..registerLazySingleton<AuthRepository>(
      () => MockAuthRepository(users: getIt<UserRepository>()),
    )
    ..registerLazySingleton<ProjectRepository>(() {
      final repo = MockProjectRepository(
        users: getIt<UserRepository>(),
        auditLog: getIt<AuditLogRepository>(),
        notifications: getIt<NotificationService>(),
      );
      getIt<NotificationService>().projects = repo;
      return repo;
    })
    ..registerLazySingleton<CompanyRepository>(MockCompanyRepository.new)
    ..registerLazySingleton<MasterDataRepository>(MockMasterDataRepository.new)
    ..registerLazySingleton<ClientRepository>(MockClientRepository.new)
    ..registerLazySingleton<AuditLogRepository>(MockAuditLogRepository.new)
    ..registerLazySingleton<ScheduleRepository>(
      () => MockScheduleRepository(
        projects: getIt<ProjectRepository>(),
        auditLog: getIt<AuditLogRepository>(),
        notifications: getIt<NotificationService>(),
      ),
    )
    ..registerLazySingleton<ApprovalInbox>(
      () => ApprovalInbox([
        BidApprovalSource(projects: getIt()),
        TodoVerificationSource(projects: getIt(), schedule: getIt()),
        DailyReportApprovalSource(projects: getIt(), reports: getIt()),
        MaterialRequestApprovalSource(projects: getIt(), procurement: getIt()),
        PurchaseOrderApprovalSource(projects: getIt(), procurement: getIt()),
        PayrollVerificationSource(projects: getIt(), labor: getIt()),
        BillingApprovalSource(projects: getIt(), billing: getIt()),
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
      () => MockDocumentRepository(projects: getIt(), users: getIt()),
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
      () => MockProcurementRepository(
        projects: getIt(),
        schedule: getIt(),
        masterData: getIt(),
        company: getIt(),
        reports: getIt(),
        users: getIt(),
        auditLog: getIt(),
        notifications: getIt(),
      ),
    )
    ..registerLazySingleton<DailyReportRepository>(
      () => MockDailyReportRepository(
        projects: getIt(),
        schedule: getIt(),
        auditLog: getIt(),
        notifications: getIt(),
      ),
    );
}
