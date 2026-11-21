import 'package:flutter/foundation.dart' show ChangeNotifier, VoidCallback;

import '../models/app_role.dart';

/// Per-workspace display, notification, branding, and role defaults.
class WorkspacePreferencesService extends ChangeNotifier {
  // --- Shared display & startup ---
  bool compactDensity = false;
  String dateFormat = 'MMM d, yyyy';
  AppRole? defaultStartupRole;

  // --- Shared granular notification filters ---
  bool notifyDailyReports = true;
  bool notifyMaterialRequests = true;
  bool notifyDeliveries = true;
  bool notifyBillings = true;
  bool notifyVariationOrders = true;

  // --- Admin: documents, audit & PDF branding ---
  int maxUploadSizeMb = 10;
  int auditRetentionDays = 365;
  String pdfFooterText = 'Queen Builders Construction';
  String pdfSignatoryName = '';
  String pdfSignatoryTitle = 'Authorized Signatory';
  bool showPcabOnPdf = true;

  // --- Project Manager ---
  String defaultProjectTab = 'overview';
  String defaultGanttZoom = 'week';
  String defaultPoSource = 'own_store';
  int approvalReminderDays = 3;
  bool lowBudgetAlerts = true;

  // --- Foreman ---
  int? defaultSiteProjectId;
  String defaultWeather = 'Sunny';
  bool remindMissingDailyReport = true;
  bool remindMissingAttendance = true;
  String photoQuality = 'standard';

  // --- Accountant ---
  String defaultPayrollCycle = 'semi_monthly';
  int overdueBillingDays = 15;
  bool retentionMilestoneAlerts = true;
  String expenseGrouping = 'project';
  bool includeDraftsInPreview = false;

  // --- Client ---
  bool alertProgressMilestones = true;
  bool alertApprovedPhotos = true;
  bool alertNewBillings = true;
  bool alertVariationOrders = true;
  String statementFormat = 'itemized';

  void update(VoidCallback mutate) {
    mutate();
    notifyListeners();
  }
}
