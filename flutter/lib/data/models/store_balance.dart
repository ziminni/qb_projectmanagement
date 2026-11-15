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
  });

  /// A wire answer. A missing or unreadable amount is an error, never a zero:
  /// a debt that reads ₱0.00 because a field was absent would be a lie.
  factory StoreBalance.fromJson(Map<String, dynamic> json) {
    double amount(String key) {
      if (json[key] == null) throw FormatException('Missing $key');
      return JsonUtils.toDouble(json[key]);
    }

    return StoreBalance(
      total: amount('total'),
      paid: amount('paid'),
      balance: amount('balance'),
      atStore: json['at_store'] as bool,
      fetchedAt: DateTime.parse(json['fetched_at'] as String),
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
}
