import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String)>[
      (Icons.watch, 'Connected devices'),
      (Icons.notifications_none, 'Notifications'),
      (Icons.lock_outline, 'Data privacy'),
      (Icons.groups_outlined, 'Coach access'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          for (final row in rows)
            ListTile(
              leading: Icon(row.$1, color: AppColors.textSecondary, size: 20),
              title: Text(row.$2),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textFaint),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.coral, size: 20),
            title: const Text('Log out', style: TextStyle(color: AppColors.coral)),
            onTap: () => AuthService().signOut(),
          ),
        ],
      ),
    );
  }
}
