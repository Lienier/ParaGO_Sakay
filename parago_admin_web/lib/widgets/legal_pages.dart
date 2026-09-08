import 'package:flutter/material.dart';

// Admin presentation. Policy text follows tools/legal/legal_pages.dart; retain this layout when syncing text.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, this.foregroundColor});

  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          for (final privacy in [false, true])
            TextButton(
              style: TextButton.styleFrom(foregroundColor: foregroundColor),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => LegalPolicyPage(privacy: privacy),
                ),
              ),
              child: Text(privacy ? 'Privacy Policy' : 'Terms & Conditions'),
            ),
        ],
      );
}

class LegalPolicyPage extends StatelessWidget {
  const LegalPolicyPage({super.key, required this.privacy});

  final bool privacy;

  static const _terms = <(String, String)>[
    (
      'Using SakayGaray',
      'SakayGaray helps passengers, drivers and administrators coordinate '
          'jeepney trips, pickups, live tracking and stop alerts. Provide accurate '
          'account information and keep your sign-in details private.',
    ),
    (
      'Trips and estimates',
      'Check the jeepney, route and pickup point before boarding. Arrival '
          'times are estimates, not guarantees. Traffic, GPS accuracy, connectivity, '
          'departure delays and stops can affect them. Confirm important pickup '
          'and unloading instructions with the driver.',
    ),
    (
      'Safe and responsible use',
      'Drivers should interact with the app only when safe and lawful. Do not '
          'submit false requests, harass others, impersonate someone, interfere '
          'with the service or access accounts without permission. Supply only '
          'documents and contact details you are authorized to share. The app is '
          'not an emergency service.',
    ),
    (
      'Accounts and support',
      'Accounts may be restricted through the administration process for '
          'misuse. Passengers and drivers can use in-app Support to ask about '
          'account restrictions or service concerns. Staff should contact their '
          'service administrator.',
    ),
    (
      'Your information',
      'Read the Privacy Policy for how the service handles information. '
          'Opening a policy does not record acceptance or grant permission for '
          'unrelated processing.',
    ),
  ];

  static const _privacy = <(String, String)>[
    (
      'Information the service handles',
      'Depending on your role and the features you use, the service handles '
          'account and sign-in information, phone and profile details, optional '
          'emergency contacts, shared locations, pickup and destination points, '
          'trip and ride records, stop alerts, support messages and notifications. '
          'Driver records also include license information, uploaded license '
          'documents and vehicle assignments. Administration creates operational '
          'logs and reports.',
    ),
    (
      'How it is used',
      'Information supports sign-in, account administration, driver and '
          'vehicle assignments, trip coordination, pickups, boarding, unloading, '
          'arrival estimates and support requests.',
    ),
    (
      'Location and visibility',
      'Shared locations support live vehicle maps and transportation '
          'features. Passengers can view active jeepney locations. Drivers and '
          'administrators receive operational information through their '
          'authorized workflows. Device location permissions can be changed in '
          'device settings; disabling them can limit location-based features.',
    ),
    (
      'Service providers',
      'Features use database and hosting providers, configured sign-in and '
          'SMS services, mapping and routing services, and document storage. '
          'Traffic ETA requests send the vehicle and target coordinates to Google '
          'Routes. Driver license documents use private storage and temporary '
          'access links.',
    ),
    (
      'Storage and requests',
      'Account, trip, communication and operational records are stored by '
          'the service. Some technical records expire automatically; this does '
          'not mean all personal information is deleted automatically. Passengers '
          'and drivers can raise access, correction or deletion requests through '
          'in-app Support. Staff should contact their service administrator. '
          'Identity verification and applicable legal requirements may affect '
          'how a request is handled.',
    ),
    (
      'Policy status',
      'This draft describes the current software. The operator identity, '
          'public privacy contact, retention periods and applicable legal details '
          'are still being finalized before publication.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final sections = privacy ? _privacy : _terms;
    return Scaffold(
      appBar: AppBar(
        title: Text(privacy ? 'Privacy Policy' : 'Terms & Conditions'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      privacy ? 'Privacy Policy' : 'Terms & Conditions',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Draft for review — not yet an effective policy.',
                    ),
                    const SizedBox(height: 32),
                    for (final section in sections) ...[
                      Text(
                        section.$1,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        section.$2,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.7),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
