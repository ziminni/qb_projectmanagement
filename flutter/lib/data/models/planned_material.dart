import 'json_utils.dart';

/// A planned Bill-of-Materials row under a project's Item of Work (DUPA Section C).
class PlannedMaterial {
  const PlannedMaterial({
    required this.id,
    required this.projectId,
    this.categoryId,
    this.categoryName,
    this.materialItemId,
    required this.name,
    required this.unit,
    required this.plannedQty,
    this.unitCost = 0,
    this.requestedQty = 0,
    this.deliveredQty = 0,
    this.sortOrder = 1,
    this.costHidden = false,
  });

  final int id;
  final int projectId;
  final int? categoryId;
  final String? categoryName;
  final int? materialItemId;
  final String name;
  final String unit;
  final double plannedQty;
  final double unitCost;
  final double requestedQty;
  final double deliveredQty;
  final int sortOrder;
  final bool costHidden;

  double get amount => plannedQty * unitCost;
  double get remainingQty => plannedQty - requestedQty;
  bool get isOverPlan => requestedQty > plannedQty + 0.0001;

  PlannedMaterial copyWith({
    int? id,
    int? Function()? categoryId,
    String? Function()? categoryName,
    int? Function()? materialItemId,
    String? name,
    String? unit,
    double? plannedQty,
    double? unitCost,
    double? requestedQty,
    double? deliveredQty,
    int? sortOrder,
    bool? costHidden,
  }) => PlannedMaterial(
    id: id ?? this.id,
    projectId: projectId,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    categoryName: categoryName != null ? categoryName() : this.categoryName,
    materialItemId: materialItemId != null
        ? materialItemId()
        : this.materialItemId,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    plannedQty: plannedQty ?? this.plannedQty,
    unitCost: unitCost ?? this.unitCost,
    requestedQty: requestedQty ?? this.requestedQty,
    deliveredQty: deliveredQty ?? this.deliveredQty,
    sortOrder: sortOrder ?? this.sortOrder,
    costHidden: costHidden ?? this.costHidden,
  );

  factory PlannedMaterial.fromJson(
    Map<String, dynamic> json, {
    bool costHidden = false,
  }) => PlannedMaterial(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    categoryId: json['category_id'] as int?,
    categoryName: json['category_name'] as String?,
    materialItemId: json['material_item_id'] as int?,
    name: json['name'] as String,
    unit: (json['unit'] as String?) ?? 'pcs',
    plannedQty: JsonUtils.toDouble(json['planned_qty']),
    unitCost: costHidden ? 0 : JsonUtils.toDouble(json['unit_cost']),
    requestedQty: JsonUtils.toDouble(json['requested_qty']),
    deliveredQty: JsonUtils.toDouble(json['delivered_qty']),
    sortOrder: json['sort_order'] as int? ?? 1,
    costHidden: costHidden,
  );
}

/// Existing project Item of Work returned alongside a DUPA import preview
/// so the PM can verify exact matching or manually link unmatched sheets.
class DupaTargetCategory {
  const DupaTargetCategory({
    required this.id,
    required this.itemNo,
    required this.name,
    this.hasDupa = false,
  });

  final int id;
  final String itemNo;
  final String name;
  final bool hasDupa;

  factory DupaTargetCategory.fromJson(Map<String, dynamic> json) =>
      DupaTargetCategory(
        id: json['id'] as int,
        itemNo: (json['item_no'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        hasDupa: json['has_dupa'] as bool? ?? false,
      );
}

/// Preview of a parsed DPWH DUPA `.xlsx` workbook before committing to the DB.
class DupaImportPreview {
  const DupaImportPreview({
    required this.items,
    required this.totalItems,
    required this.totalMaterials,
    required this.totalBudget,
    this.sheet,
    this.sheets = const [],
    this.projectCategories = const [],
    this.matchedCount = 0,
  });

  final List<DupaPreviewItem> items;
  final int totalItems;
  final int totalMaterials;
  final double totalBudget;
  final String? sheet;
  final List<String> sheets;
  final List<DupaTargetCategory> projectCategories;
  final int matchedCount;

  factory DupaImportPreview.fromJson(Map<String, dynamic> json) =>
      DupaImportPreview(
        items: [
          for (final raw in (json['items'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) DupaPreviewItem.fromJson(raw),
        ],
        totalItems: json['total_items'] as int? ?? 0,
        totalMaterials: json['total_materials'] as int? ?? 0,
        totalBudget: JsonUtils.toDouble(json['total_budget']),
        sheet: json['sheet'] as String?,
        sheets: [
          for (final s in (json['sheets'] as List<dynamic>? ?? const []))
            if (s is String && s.isNotEmpty) s,
        ],
        projectCategories: [
          for (final raw
              in (json['project_categories'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) DupaTargetCategory.fromJson(raw),
        ],
        matchedCount: json['matched_count'] as int? ?? 0,
      );
}

class DupaPreviewItem {
  const DupaPreviewItem({
    required this.sheet,
    required this.itemNo,
    required this.name,
    this.budget,
    this.laborBudget,
    this.equipmentBudget,
    this.materialBudget,
    this.dupaBreakdown,
    this.matchedCategoryId,
    this.matchedCategoryName,
    this.matchedItemNo,
    required this.materials,
  });

  final String sheet;
  final String itemNo;
  final String name;
  final double? budget;
  final double? laborBudget;
  final double? equipmentBudget;
  final double? materialBudget;
  final Map<String, dynamic>? dupaBreakdown;
  final int? matchedCategoryId;
  final String? matchedCategoryName;
  final String? matchedItemNo;
  final List<DupaPreviewMaterial> materials;

  factory DupaPreviewItem.fromJson(Map<String, dynamic> json) =>
      DupaPreviewItem(
        sheet: (json['sheet'] as String?) ?? '',
        itemNo: (json['item_no'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        budget: json['budget'] == null
            ? null
            : JsonUtils.toDouble(json['budget']),
        laborBudget: json['labor_budget'] == null
            ? null
            : JsonUtils.toDouble(json['labor_budget']),
        equipmentBudget: json['equipment_budget'] == null
            ? null
            : JsonUtils.toDouble(json['equipment_budget']),
        materialBudget: json['material_budget'] == null
            ? null
            : JsonUtils.toDouble(json['material_budget']),
        dupaBreakdown: json['dupa_breakdown'] is Map<String, dynamic>
            ? json['dupa_breakdown'] as Map<String, dynamic>
            : null,
        matchedCategoryId: json['matched_category_id'] as int?,
        matchedCategoryName: json['matched_category_name'] as String?,
        matchedItemNo: json['matched_item_no'] as String?,
        materials: [
          for (final raw in (json['materials'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) DupaPreviewMaterial.fromJson(raw),
        ],
      );
}

class DupaPreviewMaterial {
  const DupaPreviewMaterial({
    required this.name,
    required this.unit,
    required this.plannedQty,
    required this.unitCost,
    required this.amount,
  });

  final String name;
  final String unit;
  final double plannedQty;
  final double unitCost;
  final double amount;

  factory DupaPreviewMaterial.fromJson(Map<String, dynamic> json) =>
      DupaPreviewMaterial(
        name: (json['name'] as String?) ?? '',
        unit: (json['unit'] as String?) ?? 'pcs',
        plannedQty: JsonUtils.toDouble(json['planned_qty']),
        unitCost: JsonUtils.toDouble(json['unit_cost']),
        amount: JsonUtils.toDouble(json['amount']),
      );
}

class DupaImportResult {
  const DupaImportResult({
    required this.itemsImported,
    required this.materialsImported,
    required this.totalBudget,
  });

  final int itemsImported;
  final int materialsImported;
  final double totalBudget;

  factory DupaImportResult.fromJson(Map<String, dynamic> json) =>
      DupaImportResult(
        itemsImported: json['items_imported'] as int? ?? 0,
        materialsImported: json['materials_imported'] as int? ?? 0,
        totalBudget: JsonUtils.toDouble(json['total_budget']),
      );
}

/// Preview response from `POST /projects/{id}/import-items/?dry_run=true`
/// or `POST /projects/preview-items/`.
class ItemsExcelPreview {
  const ItemsExcelPreview({
    required this.items,
    this.sheet,
    this.sheets = const [],
    this.format = 'simple',
    this.targetEndDate,
    this.totalDays,
    this.totalBudget,
  });

  final List<ItemsExcelRow> items;
  final String? sheet;
  final List<String> sheets;
  final String format;
  final DateTime? targetEndDate;
  final int? totalDays;
  final double? totalBudget;

  factory ItemsExcelPreview.fromJson(Map<String, dynamic> json) =>
      ItemsExcelPreview(
        items: [
          for (final raw in (json['items'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) ItemsExcelRow.fromJson(raw),
        ],
        sheet: json['sheet'] as String?,
        sheets: [
          for (final s in (json['sheets'] as List<dynamic>? ?? const []))
            if (s is String && s.isNotEmpty) s,
        ],
        format: (json['format'] as String?) ?? 'simple',
        targetEndDate: JsonUtils.toDateOrNull(json['target_end_date']),
        totalDays: json['total_days'] as int?,
        totalBudget: json['total_budget'] == null
            ? null
            : JsonUtils.toDouble(json['total_budget']),
      );
}

/// One row from either a DPWH SF-INFR-41 Bar Chart or a 3-column schedule Excel.
class ItemsExcelRow {
  const ItemsExcelRow({
    this.itemNo = '',
    required this.name,
    this.budget,
    required this.plannedWeeks,
    this.plannedDays,
    this.dayToStart,
    this.startDate,
    this.endDate,
  });

  final String itemNo;
  final String name;
  final double? budget;
  final String plannedWeeks;
  final int? plannedDays;
  final int? dayToStart;
  final DateTime? startDate;
  final DateTime? endDate;

  factory ItemsExcelRow.fromJson(Map<String, dynamic> json) => ItemsExcelRow(
    itemNo: (json['item_no'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    budget: json['budget'] == null ? null : JsonUtils.toDouble(json['budget']),
    plannedWeeks: (json['planned_weeks'] as String?) ?? '',
    plannedDays: json['planned_days'] as int?,
    dayToStart: json['day_to_start'] as int?,
    startDate: JsonUtils.toDateOrNull(json['start_date']),
    endDate: JsonUtils.toDateOrNull(json['end_date']),
  );
}
