import 'json_utils.dart';

/// Roles from the `user_roles.role` column.
enum AppRole implements JsonEnum {
  admin('admin', 'System admin'),

  /// The contractor who owns the firm and runs its projects.
  owner('owner', 'Owner / Project manager'),
  siteEngineer('site_engineer', 'Site engineer / foreman'),
  accountant('accountant', 'Accountant / finance'),
  client('client', 'Client');

  const AppRole(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  /// Company finances are confidential: only the owner and the accountant
  /// see contract amounts, budgets, costs, prices, rates and pay. Clients
  /// see only what they are billed, in the client portal.
  bool get seesFinance => this == AppRole.owner || this == AppRole.accountant;

  static AppRole fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}
