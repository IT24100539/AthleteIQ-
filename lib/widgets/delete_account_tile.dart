import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';

/// Irreversible delete-account control. Confirmation requires typing DELETE.
class DeleteAccountTile extends StatefulWidget {
  final bool isCoach;

  const DeleteAccountTile({super.key, this.isCoach = false});

  @override
  State<DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends State<DeleteAccountTile> {
  bool _deleting = false;

  Future<void> _onTap() async {
    if (_deleting) return;
    final confirmed = await showDeleteAccountDialog(
      context,
      isCoach: widget.isCoach,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await AuthService().deleteAccount();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: widget.isCoach
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16),
      leading: const Icon(
        Icons.delete_forever_outlined,
        color: AppColors.coral,
        size: 20,
      ),
      title: Text(
        _deleting ? 'Deleting account…' : 'Delete account',
        style: const TextStyle(
          color: AppColors.coral,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        widget.isCoach
            ? 'Permanently erase this coach account. Athletes are unlinked, not deleted.'
            : 'Permanently erase your data and sign-in. This cannot be undone.',
        style: const TextStyle(fontSize: 12),
      ),
      enabled: !_deleting,
      onTap: _onTap,
    );
  }
}

Future<bool?> showDeleteAccountDialog(
  BuildContext context, {
  required bool isCoach,
}) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this account?'),
      content: Text(
        isCoach
            ? 'This permanently deletes your coach profile, team settings, '
                'alerts, and sign-in.\n\nAthletes on your roster stay in the app '
                'and are unlinked from you. They can connect to another coach.'
            : 'This permanently deletes your check-ins, devices, pain reports, '
                'messages, alerts, and sign-in.\n\nThis cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return false;

  final typed = TextEditingController();
  try {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final matches = typed.text.trim() == 'DELETE';
          return AlertDialog(
            title: const Text('Type DELETE to confirm'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This is irreversible. Type DELETE in all caps to continue.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: typed,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'DELETE',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child: const Text(
                  'Delete account',
                  style: TextStyle(
                    color: AppColors.coral,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    typed.dispose();
  }
}
