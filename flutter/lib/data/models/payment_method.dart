import 'json_utils.dart';

enum PaymentMethod implements JsonEnum {
  cash('cash', 'Cash'),
  check('check', 'Check'),
  bankTransfer('bank_transfer', 'Bank transfer'),
  eWallet('e_wallet', 'GCash / e-wallet');

  const PaymentMethod(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static PaymentMethod fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}
