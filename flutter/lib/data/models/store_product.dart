/// One item in the company hardware store's catalog, as its POS will
/// return it. [materialId] links it to the price list so site inventory and
/// daily reports can track it.
class StoreProduct {
  const StoreProduct({
    required this.sku,
    required this.name,
    required this.unit,
    required this.price,
    required this.category,
    required this.stock,
    this.materialId,
  });

  final String sku;
  final String name;
  final String unit;
  final double price;
  final String category;

  /// Units on the store's shelf. Shown only; ordering does not reserve.
  final double stock;
  final int? materialId;
}
