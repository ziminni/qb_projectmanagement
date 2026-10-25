/// Thrown by repositories when a business rule from the design document is
/// broken. [message] is written for the person who triggered it.
class BusinessRuleException implements Exception {
  const BusinessRuleException(this.message);

  final String message;

  @override
  String toString() => message;
}
