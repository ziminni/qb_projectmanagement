/// How much the store has of an item, as coarsely as the store tells us: enough
/// to judge whether an order is sensible, never a count.
enum StoreStock {
  inStock('in_stock', 'In stock'),
  low('low', 'Low stock'),
  out('out', 'Out of stock');

  const StoreStock(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Null for anything the store did not say: unknown is not "in stock".
  static StoreStock? fromApi(Object? raw) {
    for (final value in values) {
      if (value.apiValue == raw) return value;
    }
    return null;
  }
}

/// One item in the company hardware store's catalog, as its POS will
/// return it. [materialId] links it to the price list so site inventory and
/// daily reports can track it.
class StoreProduct {
  const StoreProduct({
    required this.sku,
    required this.name,
    required this.unit,
    this.price,
    this.category,
    this.stock,
    this.materialId,
    this.stockStatus,
    this.fromStore = true,
  });

  final String sku;
  final String name;
  final String unit;

  /// The store's price per [unit], or null when the source does not show it
  /// (the server hides a cost from a role without the money view). A hidden
  /// price is *unavailable*, never zero.
  final double? price;

  /// The store's own grouping; null when the source keeps none (the server's
  /// master list has no category yet).
  final String? category;

  /// Units on the store's shelf, when the source knows them. Shown only;
  /// ordering does not reserve.
  final double? stock;

  /// The price-list material this product is, in the source's own ids.
  final int? materialId;

  /// The store's own coarse stock status; null when the store was not asked or
  /// did not say.
  final StoreStock? stockStatus;

  /// False when the store could not be reached and this row comes from the
  /// CPMS material list: its price and stock are then unavailable, never a
  /// CPMS figure passed off as the store's.
  final bool fromStore;
}
