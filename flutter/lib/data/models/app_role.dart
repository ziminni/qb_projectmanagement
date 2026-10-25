import 'json_utils.dart';

/// Roles from the `user_roles.role` column.
enum AppRole implements JsonEnum {
  admin('admin', 'System admin'),
  owner('owner', 'Owner / general manager'),
  pm('pm', 'Project manager'),
  siteEngineer('site_engineer', 'Site engineer / foreman'),
  purchasing('purchasing', 'Purchasing officer'),
  accountant('accountant', 'Accountant / finance'),
  client('client', 'Client');

  const AppRole(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static AppRole fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}
