import 'json_utils.dart';

/// What a project owes the company hardware store, exactly as the store's own
/// record says. The store holds the debt and records its payments; CPMS only
/// reads it, so there is nothing here to edit and nothing to add up locally.
class StoreBalance {
  const StoreBalance({
    required this.total,
    required this.paid,
    required this.balance,
    required this.atStore,
    required this.fetchedAt,
    this.byCategory = const {},
  });

  /// A wire answer. A missing or unreadable amount is an error, never a zero:
  /// a debt that reads ₱0.00 because a field was absent would be a lie.
  factory StoreBalance.fromJson(Map<String, dynamic> json) {
    double amount(String key) {
      if (json[key] == null) throw FormatException('Missing $key');
      return JsonUtils.toDouble(json[key]);
    }

    final rawByCat = json['by_category'];
    final byCategory = <int, double>{};
    if (rawByCat is Map) {
      for (final entry in rawByCat.entries) {
        final catId = int.tryParse(entry.key.toString());
        if (catId != null) {
          byCategory[catId] = JsonUtils.toDouble(entry.value);
        }
      }
    }

    return StoreBalance(
      total: amount('total'),
      paid: amount('paid'),
      balance: amount('balance'),
      atStore: json['at_store'] as bool,
      fetchedAt: DateTime.parse(json['fetched_at'] as String),
      byCategory: byCategory,
    );
  }

  final double total;
  final double paid;
  final double balance;

  /// False when the store has never been sent this project, so nothing is owed
  /// yet (the amounts are then genuinely zero).
  final bool atStore;

  /// When CPMS asked the store; the figure is only as fresh as this.
  final DateTime fetchedAt;

  /// Own-store material cost attributed by CPMS category ID when known.
  final Map<int, double> byCategory;
}

/// Online payment proof submitted to the company hardware store (Phase 1c).
class StorePaymentReceipt {
  const StorePaymentReceipt({
    required this.id,
    required this.cpmsPaymentId,
    required this.amount,
    this.approvedAmount,
    required this.paymentMethod,
    required this.referenceNo,
    required this.notes,
    required this.status,
    required this.declineReason,
    required this.createdAt,
  });

  factory StorePaymentReceipt.fromJson(Map<String, dynamic> json) =>
      StorePaymentReceipt(
        id: json['id'] as int,
        cpmsPaymentId: json['cpms_payment_id'] as String,
        amount: JsonUtils.toDouble(json['amount']),
        approvedAmount: JsonUtils.toDoubleOrNull(json['approved_amount']),
        paymentMethod: json['payment_method'] as String? ?? 'BANK_TRANSFER',
        referenceNo: json['reference_no'] as String,
        notes: json['notes'] as String? ?? '',
        status: json['status'] as String,
        declineReason: json['decline_reason'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final String cpmsPaymentId;
  final double amount;
  final double? approvedAmount;
  final String paymentMethod;
  final String referenceNo;
  final String notes;
  final String status;
  final String declineReason;
  final DateTime createdAt;
}
