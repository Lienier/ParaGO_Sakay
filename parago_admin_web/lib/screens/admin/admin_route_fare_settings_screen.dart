import '../../widgets/operations_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';
import '../../models/transport/route_summary.dart';

class AdminRouteFareSettingsScreen extends StatefulWidget {
  const AdminRouteFareSettingsScreen({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<AdminRouteFareSettingsScreen> createState() =>
      _AdminRouteFareSettingsScreenState();
}

class _AdminRouteFareSettingsScreenState
    extends State<AdminRouteFareSettingsScreen> {
  List<RouteSummaryModel> _routes = [];
  bool _loading = false;
  bool _saving = false;
  bool _loadFailed = false;
  String? _message;

  late TextEditingController _fareBaseAmountCtrl;
  late TextEditingController _fareBaseDistanceCtrl;
  late TextEditingController _fareAdditionalPerKmCtrl;

  @override
  void initState() {
    super.initState();
    _fareBaseAmountCtrl = TextEditingController(text: '17');
    _fareBaseDistanceCtrl = TextEditingController(text: '4');
    _fareAdditionalPerKmCtrl = TextEditingController(text: '2');
    _loadRoutes();
  }

  @override
  void dispose() {
    _fareBaseAmountCtrl.dispose();
    _fareBaseDistanceCtrl.dispose();
    _fareAdditionalPerKmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);

    setState(() => _loading = true);

    try {
      final routes = await routeService.getRoutes();
      if (!mounted) return;

      setState(() {
        _loadFailed = false;
        _routes = routes;
        if (routes.isNotEmpty) {
          _applyFareConfig(routes.first.fareConfig);
        }
        _message = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _message = ActionFeedback.messageOf(error);
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyFareConfig(RouteFareConfig config) {
    _fareBaseAmountCtrl.text = _formatNumericInput(config.baseAmount);
    _fareBaseDistanceCtrl.text = _formatNumericInput(config.baseDistanceKm);
    _fareAdditionalPerKmCtrl.text =
        _formatNumericInput(config.additionalAmountPerKm);
  }

  String _formatNumericInput(double value) {
    return value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  double _parseFareInput(TextEditingController controller, double fallback) {
    return double.tryParse(controller.text.trim()) ?? fallback;
  }

  String _fareRuleSummary() {
    final baseAmount = _parseFareInput(_fareBaseAmountCtrl, 17);
    final baseDistanceKm = _parseFareInput(_fareBaseDistanceCtrl, 4);
    final additionalAmount = _parseFareInput(_fareAdditionalPerKmCtrl, 2);
    return 'First ${_formatNumericInput(baseDistanceKm)} km = PHP ${_formatNumericInput(baseAmount)}, then PHP ${_formatNumericInput(additionalAmount)} per succeeding kilometer.';
  }

  String? _validateNonNegativeNumber(String? value, String label) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) {
      return '$label must be a valid number.';
    }
    if (parsed < 0) {
      return '$label must be 0 or higher.';
    }
    return null;
  }

  Future<void> _saveFareSettings() async {
    if (_routes.isEmpty) {
      setState(() => _message = 'No routes available to update.');
      return;
    }

    final baseAmount = _fareBaseAmountCtrl.text.trim();
    final baseDistance = _fareBaseDistanceCtrl.text.trim();
    final additionalAmount = _fareAdditionalPerKmCtrl.text.trim();

    final baseAmountError = _validateNonNegativeNumber(baseAmount, 'Base fare');
    final baseDistanceError =
        _validateNonNegativeNumber(baseDistance, 'Base distance');
    final additionalAmountError =
        _validateNonNegativeNumber(additionalAmount, 'Additional fare');

    if (baseAmountError != null ||
        baseDistanceError != null ||
        additionalAmountError != null) {
      setState(() => _message =
          baseAmountError ?? baseDistanceError ?? additionalAmountError);
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);
    final payload = {
      'baseAmount': _parseFareInput(_fareBaseAmountCtrl, 17),
      'baseDistanceKm': _parseFareInput(_fareBaseDistanceCtrl, 4),
      'additionalAmountPerKm': _parseFareInput(_fareAdditionalPerKmCtrl, 2),
    };

    setState(() {
      _saving = true;
      _message =
          'Updating universal fare settings for ${_routes.length} routes...';
    });

    try {
      await Future.wait(
        _routes.map(
          (route) => routeService.updateRoute(
            route.id,
            {'fareConfig': payload},
          ),
        ),
      );

      if (!mounted) return;

      setState(() {
        _message =
            'Universal fare settings updated for ${_routes.length} routes. Changes will apply to new passenger bookings.';
      });

      await _loadRoutes();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = ActionFeedback.messageOf(error));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OperationsCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Universal fare settings',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(
                    'These values are applied to every route in the system.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _routes.isEmpty
                        ? (_loading
                            ? 'Loading route fare settings...'
                            : _loadFailed
                                ? 'Route fare settings could not be loaded. Displayed values are defaults.'
                                : 'No routes are available yet.')
                        : '${_routes.length} routes will use these fare rules.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 780;
                        final fields = [
                          TextFormField(
                            controller: _fareBaseAmountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Base fare',
                              prefixText: 'PHP ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                _validateNonNegativeNumber(value, 'Base fare'),
                            onChanged: (_) => setState(() {}),
                          ),
                          TextFormField(
                            controller: _fareBaseDistanceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Base distance',
                              suffixText: 'km',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => _validateNonNegativeNumber(
                                value, 'Base distance'),
                            onChanged: (_) => setState(() {}),
                          ),
                          TextFormField(
                            controller: _fareAdditionalPerKmCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Additional per km',
                              prefixText: 'PHP ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => _validateNonNegativeNumber(
                                value, 'Additional fare'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ];

                        if (stacked) {
                          return Column(
                            children: [
                              for (var index = 0;
                                  index < fields.length;
                                  index += 1) ...[
                                fields[index],
                                if (index < fields.length - 1)
                                  const SizedBox(height: 12),
                              ],
                            ],
                          );
                        }

                        return Row(
                          children: [
                            for (var index = 0;
                                index < fields.length;
                                index += 1) ...[
                              Expanded(child: fields[index]),
                              if (index < fields.length - 1)
                                const SizedBox(width: 12),
                            ],
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF102725).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _fareRuleSummary(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_saving)
                    const LinearProgressIndicator()
                  else
                    FilledButton(
                      onPressed: _saveFareSettings,
                      child: const Text('Save Fare Settings'),
                    ),
                ],
              ),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF102725).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
