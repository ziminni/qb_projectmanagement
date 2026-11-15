import '../../../data/repositories/procurement_repository.dart';

/// One editable line on a request, an own-store order or a logged purchase.
class LineDraft {
  LineDraft({
    this.materialId,
    this.description = '',
    this.unit = '',
    this.quantity = 0,
    this.unitPrice = 0,
    this.priceHidden = false,
  });

  int? materialId;
  String description;
  String unit;
  double quantity;
  double unitPrice;

  /// The source hides this line's price (a role without the money view), so
  /// the field stays blank for the owner to type instead of showing a
  /// misleading ₱0.
  bool priceHidden;

  double get amount => quantity * unitPrice;

  RequestLine toRequestLine() =>
      (description: description, unit: unit, quantity: quantity);

  OrderLine toOrderLine() => (
    materialId: materialId,
    description: description,
    unit: unit,
    quantity: quantity,
    unitPrice: unitPrice,
  );
}
