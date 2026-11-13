import '../../../data/repositories/procurement_repository.dart';

/// One editable line on a request, an own-store order or a logged purchase.
class LineDraft {
  LineDraft({
    this.materialId,
    this.description = '',
    this.unit = '',
    this.quantity = 0,
    this.unitPrice = 0,
  });

  int? materialId;
  String description;
  String unit;
  double quantity;
  double unitPrice;

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
