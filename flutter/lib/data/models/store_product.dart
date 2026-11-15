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
}
