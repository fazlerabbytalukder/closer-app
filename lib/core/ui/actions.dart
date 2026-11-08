import 'package:closer_app/core/models/models.dart';
import 'package:closer_app/core/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Runs a user action: shows friendly errors as a toast and opens the paywall
/// when a free limit is hit. Returns true on success.
Future<bool> runAction(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on LimitReachedException catch (e) {
    if (context.mounted) {
      showToast(context, e.message, icon: Icons.workspace_premium_rounded);
      await context.push('/paywall?from=${e.limit}');
    }
  } on CloserException catch (e) {
    if (context.mounted) showToast(context, e.message, icon: Icons.info_outline_rounded);
  } on Object catch (e) {
    debugPrint('Action failed: $e');
    if (context.mounted) {
      showToast(context, 'Something went wrong. Please try again.', icon: Icons.error_outline_rounded);
    }
  }
  return false;
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  String ok = 'OK',
  bool destructive = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive ? TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error) : null,
          child: Text(ok),
        ),
      ],
    ),
  );
  return res ?? false;
}
