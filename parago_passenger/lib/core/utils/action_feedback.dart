import '../../widgets/glass_surface.dart';
import 'dart:async';
import '../exceptions/api_exception.dart';

import 'package:flutter/material.dart';

class ActionFeedback {
  static Future<T?> run<T>({
    required BuildContext context,
    required String loadingMessage,
    required Future<T> Function() action,
    Future<void> Function(T result)? onSuccess,
    Future<void> Function(Object error)? onError,
    String? successMessage,
    String successTitle = 'Success',
    String errorTitle = 'Action failed',
    bool showSuccess = true,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var loadingVisible = true;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: GlassAlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(loadingMessage)),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    try {
      final result = await action();
      if (loadingVisible && navigator.mounted) {
        navigator.pop();
        loadingVisible = false;
      }
      if (onSuccess != null) {
        await onSuccess(result);
      }
      if (showSuccess && successMessage != null && context.mounted) {
        await showSuccessDialog(
          context,
          title: successTitle,
          message: successMessage,
        );
      }
      return result;
    } catch (error) {
      if (loadingVisible && navigator.mounted) {
        navigator.pop();
        loadingVisible = false;
      }
      if (onError != null) {
        await onError(error);
      }
      if (context.mounted) {
        await showErrorDialog(
          context,
          title: errorTitle,
          message: _messageOf(error),
        );
      }
      return null;
    }
  }

  static Future<void> showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return _showDialog(
      context,
      title: title,
      message: message,
      icon: Icons.info_outline,
    );
  }

  static Future<void> showSuccessDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return _showDialog(
      context,
      title: title,
      message: message,
      icon: Icons.check_circle_outline,
    );
  }

  static Future<void> showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return _showDialog(
      context,
      title: title,
      message: message,
      icon: Icons.error_outline,
    );
  }

  static Future<void> _showDialog(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
  }) {
    final controller = ScaffoldMessenger.of(context).showSnackBar(GlassSnackBar(
      showCloseIcon: true,
      content: Row(children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(child: Text('$title: $message'))
      ]),
    ));
    return controller.closed.then((_) {});
  }

  static String messageOf(Object error) => _messageOf(error);

  static String _messageOf(Object error) {
    if (error is ApiException) return error.message;
    return 'We could not complete this action. Refresh your booking or ride status and try again.';
  }
}
