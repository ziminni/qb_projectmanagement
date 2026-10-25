abstract final class AuthRules {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email.';
    if (!_email.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  static String? validatePasswordPresent(String? value) =>
      (value == null || value.isEmpty) ? 'Enter your password.' : null;

  /// At least 8 characters with a letter and a number.
  static String? validateNewPassword(String? value) {
    final v = value ?? '';
    if (v.length < 8) return 'Use at least 8 characters.';
    if (!RegExp('[A-Za-z]').hasMatch(v) || !RegExp('[0-9]').hasMatch(v)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }
}
