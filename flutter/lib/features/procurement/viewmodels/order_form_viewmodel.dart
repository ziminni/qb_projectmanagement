import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/network/api_config.dart';
import '../../../core/platform/desktop_files.dart';
import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
import '../../../data/models/material_item.dart';
import '../../../data/models/material_request.dart';
import '../../../data/models/material_source.dart';
import '../../../data/models/project.dart';
import '../../../data/models/store_product.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/repositories/store_catalog_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/procurement_rules.dart';
import '../../../data/services/session_service.dart';
import 'line_draft.dart';
import 'procurement_lookups.dart';

/// The owner's answer to a material request. With [MaterialSource.ownStore]
/// the owner picks products from the hardware store catalog and sets where
/// to deliver; with [MaterialSource.external] the owner logs what was bought
/// at another store, with its OR number and a photo of the receipt.
class OrderFormViewModel extends ChangeNotifier with ActionRunner {
  OrderFormViewModel({
    required this.requestId,
    required this.source,
    required SessionService session,
    required ProcurementRepository procurement,
    required StoreCatalogRepository catalog,
    required this.lookups,
  }) : _session = session,
       _procurement = procurement,
       _catalog = catalog;

  final int requestId;
  final MaterialSource source;
  final SessionService _session;
  final ProcurementRepository _procurement;
  final StoreCatalogRepository _catalog;
  final ProcurementLookups lookups;

  bool _loading = true;
  String? _error;
  MaterialRequestDetail? _detail;
  BudgetCheck? _budget;
  int? _savedId;

  final lines = <LineDraft>[];

  /// Requested items this order covers.
  final covers = <int>{};
  Map<int, String> _orderNos = const {};

  /// The budget category the owner charges this order to.
  int? categoryId;

  // Own store
  List<String> catalogCategories = const [];
  List<StoreProduct> products = const [];
  String query = '';
  String? categoryFilter;
  String deliveryAddress = '';

  // Other store
  String storeName = '';
  String orNumber = '';
  String? receiptPhotoPath;

  bool get isLoading => _loading;
  String? get error => _error;
  MaterialRequestDetail? get detail => _detail;
  MaterialRequest? get request => _detail?.request;
  Project? get project =>
      request == null ? null : lookups.projects[request!.projectId];
  int? get savedId => _savedId;
  bool get isOwnStore => source == MaterialSource.ownStore;

  List<MaterialItem> get priceList => lookups.materials.values.toList();

  List<Category> get categoryOptions =>
      lookups.categories.values
          .where((c) => c.projectId == request?.projectId)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  double get total => lines.fold(0, (s, l) => s + l.amount);

  String orderNo(int orderId) => _orderNos[orderId] ?? 'PO #$orderId';

  /// Every requested item is covered once this order is saved.
  bool get coversAll =>
      _detail!.items.every((i) => i.isCovered || covers.contains(i.id));

  void toggleCover(int itemId) {
    if (!covers.remove(itemId)) covers.add(itemId);
    notifyListeners();
  }

  /// The category budget against this order's total.
  BudgetCheck? get budget => _budget == null
      ? null
      : BudgetCheck(
          budget: _budget!.budget,
          committed: _budget!.committed,
          requestCost: total,
        );

  Future<void> load() async {
    try {
      if (_session.activeRole != AppRole.owner) {
        _error = 'Only the owner orders materials.';
        return;
      }
      await lookups.load(_session.user!.id, AppRole.owner);
      _detail = await _procurement.getRequest(requestId);
      if (_detail == null || project == null) {
        _error = 'Request not found.';
        return;
      }
      if (request!.status == MaterialRequestStatus.rejected) {
        _error = '${request!.number} was rejected.';
        return;
      }
      _orderNos = {
        for (final o in await _procurement.getPurchaseOrders(
          projectIds: [request!.projectId],
        ))
          o.id: o.poNo,
      };
      // Older requests already name a category.
      categoryId = request!.categoryId;
      await _refreshBudget();
      if (isOwnStore) {
        deliveryAddress = project!.location;
        catalogCategories = await _catalog.getCategories();
        await _search();
      } else {
        lines.add(LineDraft());
      }
    } catch (e) {
      _error = 'Could not load the request. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshBudget() async {
    _budget = categoryId == null
        ? null
        : await _procurement.checkBudget(categoryId!, 0);
  }

  Future<void> setCategory(int? id) async {
    categoryId = id;
    await _refreshBudget();
    notifyListeners();
  }

  Future<void> _search() async {
    products = await _catalog.getProducts(
      query: query,
      category: categoryFilter,
    );
    notifyListeners();
  }

  Future<void> setQuery(String q) {
    query = q;
    return _search();
  }

  Future<void> setCategoryFilter(String? c) {
    categoryFilter = c;
    return _search();
  }

  bool isPicked(StoreProduct p) =>
      lines.any((l) => l.materialId == p.materialId);

  void addProduct(StoreProduct p) {
    if (isPicked(p)) return;
    lines.add(
      LineDraft(
        materialId: p.materialId,
        description: p.name,
        unit: p.unit,
        unitPrice: p.price,
      ),
    );
    notifyListeners();
  }

  void addLine() {
    lines.add(LineDraft());
    notifyListeners();
  }

  void removeLine(LineDraft line) {
    lines.remove(line);
    notifyListeners();
  }

  void useSiteAddress() {
    deliveryAddress = project!.location;
    notifyListeners();
  }

  void setReceiptPhoto(String? path) {
    receiptPhotoPath = path;
    notifyListeners();
  }

  void changed() => notifyListeners();

  Future<String?> submit() => runAction(() async {
    if (lines.isEmpty) {
      throw BusinessRuleException(
        isOwnStore
            ? 'Pick at least one product from the catalog.'
            : 'Add at least one material.',
      );
    }
    if (categoryId == null) {
      throw const BusinessRuleException('Choose the budget category.');
    }
    if (covers.isEmpty) {
      throw const BusinessRuleException(
        'Tick the requested items this order covers.',
      );
    }
    final orderLines = [for (final l in lines) l.toOrderLine()];
    // The server stores the receipt file, never a path (Phase 3 decision 2):
    // the bytes of the picked photo travel with the order in API mode.
    final receiptBytes = useApi && receiptPhotoPath != null
        ? await readFileBytes(receiptPhotoPath!)
        : null;
    final draft = isOwnStore
        ? OrderDraft.ownStore(
            requestId: requestId,
            categoryId: categoryId!,
            lines: orderLines,
            coversItemIds: covers.toList(),
            deliveryAddress: deliveryAddress,
          )
        : OrderDraft.otherStore(
            requestId: requestId,
            categoryId: categoryId!,
            lines: orderLines,
            coversItemIds: covers.toList(),
            storeName: storeName,
            orNumber: orNumber,
            receiptPhotoUrl: receiptPhotoPath ?? '',
            receiptPhotoBytes: receiptBytes,
          );
    final order = await _procurement.placeOrder(
      draft,
      userId: _session.user!.id,
    );
    _savedId = order.id;
  });
}
