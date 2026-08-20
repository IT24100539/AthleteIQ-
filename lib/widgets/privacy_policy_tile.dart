import 'package:flutter/material.dart';

import '../constants/legal_urls.dart';
import '../theme/app_theme.dart';
import '../utils/open_external_url.dart';

/// Opens the hosted privacy policy in the device browser.
class PrivacyPolicyTile extends StatelessWidget {
  final EdgeInsetsGeometry contentPadding;

  const PrivacyPolicyTile({
    super.key,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: contentPadding,
      leading: Icon(
        Icons.policy_outlined,
        color: AppColors.textSecondary,
        size: 20,
      ),
      title: const Text('Privacy Policy'),
      subtitle: const Text(
        'How AthleteIQ uses and protects your data',
        style: TextStyle(fontSize: 12),
      ),
      trailing: Icon(Icons.open_in_new, color: AppColors.textFaint, size: 18),
      onTap: () => openExternalUrl(context, kPrivacyPolicyUrl),
    );
  }
}
