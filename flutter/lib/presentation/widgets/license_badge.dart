import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/license_coordinator.dart';
import '../../domain/license.dart';

/// Бейдж лицензии — показывает текущий режим (Basic / PRO Trial / PRO).
///
/// Подписывается на [LicenseCoordinator.licenseChanges] и автоматически
/// обновляется при смене лицензии.
class LicenseBadge extends StatefulWidget {
  final LicenseCoordinator licenseCoordinator;

  const LicenseBadge({super.key, required this.licenseCoordinator});

  @override
  State<LicenseBadge> createState() => _LicenseBadgeState();
}

class _LicenseBadgeState extends State<LicenseBadge> {
  StreamSubscription<License>? _sub;
  late License _license;

  @override
  void initState() {
    super.initState();
    _license = widget.licenseCoordinator.currentLicense;
    _sub = widget.licenseCoordinator.licenseChanges.listen((license) {
      if (mounted) {
        setState(() => _license = license);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConstrained = widget.licenseCoordinator.isHardwareConstrained;

    final (label, color, textColor) = switch (_license.mode) {
      LicenseMode.pro => (
        'PRO',
        Colors.blueGrey.shade700,
        Colors.white,
      ),
      LicenseMode.proTrial => () {
        final remaining = widget.licenseCoordinator.trialTimeRemaining;
        final days = (remaining?.inDays ?? 0) + 1;
        return (
          'PRO Trial · осталось $days дн.',
          Colors.orange.shade700,
          Colors.white,
        );
      }(),
      LicenseMode.basic => (
        'Basic',
        Colors.transparent,
        theme.colorScheme.outline,
      ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (isConstrained) ...[
          const SizedBox(width: 4),
          Text(
            '(мало ОЗУ)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
