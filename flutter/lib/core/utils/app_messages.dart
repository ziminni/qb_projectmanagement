import 'package:flutter/material.dart';

/// Shows a short message at the bottom of the screen.
void showAppMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Awaits a view-model action and shows its error, or [success] if given.
Future<bool> reportAction(
  BuildContext context,
  Future<String?> action, {
  String? success,
}) async {
  final error = await action;
  if (!context.mounted) return error == null;
  if (error != null) {
    showAppMessage(context, error);
  } else if (success != null) {
    showAppMessage(context, success);
  }
  return error == null;
}
