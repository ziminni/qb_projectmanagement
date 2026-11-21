import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// What the accounting screens say while the ledger that owns POS debt is
/// undecided (phase-3 contract, blockers 1 and 2).
const supplierAccountingUnavailable =
    'Supplier accounting is not available yet. It is waiting on the ledger '
    'decision.';

/// Shows a short message at the bottom of the screen.
void showAppMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Shows a green confirmation alert at the bottom of the screen.
void showSuccessAlert(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
