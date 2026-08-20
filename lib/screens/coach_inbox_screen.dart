import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/athlete.dart';
import '../models/chat_message.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/coach_inbox.dart';
import '../widgets/async_body.dart';
import '../widgets/empty_state.dart';
import 'coach_message_thread_screen.dart';

/// Coach inbox — one row per roster athlete, unread when the last message
/// is from the athlete and newer than `coaches/{uid}/inboxRead/{athleteUid}`.
class CoachInboxScreen extends StatefulWidget {
  final String coachUid;

  const CoachInboxScreen({super.key, required this.coachUid});

  @override
  State<CoachInboxScreen> createState() => _CoachInboxScreenState();
}

class _CoachInboxScreenState extends State<CoachInboxScreen> {
  final _fs = FirestoreService();
  List<AthleteProfile> _athletes = [];
  final Map<String, ChatMessage?> _latestByUid = {};
  final Map<String, DateTime?> _lastReadByUid = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _resubscribe(List<AthleteProfile> athletes) {
    if (_sameAthleteSet(athletes, _athletes)) return;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _athletes = athletes;
    _latestByUid.clear();
    _lastReadByUid.clear();

    for (final athlete in athletes) {
      _subscriptions.add(
        _fs.streamLatestCoachMessage(athlete.uid).listen((msg) {
          if (mounted) setState(() => _latestByUid[athlete.uid] = msg);
        }, onError: ignoreStreamError),
      );
      _subscriptions.add(
        _fs.streamInboxLastRead(widget.coachUid, athlete.uid).listen((at) {
          if (mounted) setState(() => _lastReadByUid[athlete.uid] = at);
        }, onError: ignoreStreamError),
      );
    }
  }

  bool _sameAthleteSet(List<AthleteProfile> a, List<AthleteProfile> b) {
    if (a.length != b.length) return false;
    final ids = a.map((x) => x.uid).toSet();
    return b.every((x) => ids.contains(x.uid));
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  String _timeLabel(DateTime ts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(ts.year, ts.month, ts.day);
    if (day == today) return DateFormat('h:mm a').format(ts);
    if (today.difference(day).inDays == 1) return 'Yesterday';
    return DateFormat('M/d').format(ts);
  }

  int get _unreadCount {
    return _athletes.where((a) {
      return coachThreadIsUnread(_latestByUid[a.uid], _lastReadByUid[a.uid]);
    }).length;
  }

  List<AthleteProfile> _sorted(List<AthleteProfile> athletes) {
    final copy = List<AthleteProfile>.from(athletes);
    copy.sort((a, b) {
      final aUnread = coachThreadIsUnread(_latestByUid[a.uid], _lastReadByUid[a.uid]);
      final bUnread = coachThreadIsUnread(_latestByUid[b.uid], _lastReadByUid[b.uid]);
      if (aUnread != bUnread) return aUnread ? -1 : 1;
      final aTs = _latestByUid[a.uid]?.timestamp;
      final bTs = _latestByUid[b.uid]?.timestamp;
      if (aTs == null && bTs == null) return a.name.compareTo(b.name);
      if (aTs == null) return 1;
      if (bTs == null) return -1;
      return bTs.compareTo(aTs);
    });
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<AthleteProfile>>(
        stream: _fs.rosterForCoach(widget.coachUid),
        builder: (context, snap) {
          final blocked = asyncBody(
            snap,
            heading: 'Could not load inbox',
          );
          if (blocked != null) return blocked;

          final athletes = snap.data ?? [];
          _resubscribe(athletes);

          if (athletes.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.chat_bubble_outline,
                heading: 'No athletes yet',
                subtext:
                    'When athletes join your roster, their messages will appear here. Nothing is seeded.',
              ),
            );
          }

          final rows = _sorted(athletes);

          return Column(
            children: [
              if (_unreadCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$_unreadCount unread',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mint,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final athlete = rows[i];
                    final last = _latestByUid[athlete.uid];
                    final unread = coachThreadIsUnread(last, _lastReadByUid[athlete.uid]);
                    return _ThreadRow(
                      athlete: athlete,
                      last: last,
                      unread: unread,
                      initials: _initials(athlete.name),
                      timeLabel: last == null ? '' : _timeLabel(last.timestamp),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CoachMessageThreadScreen(
                            athlete: athlete,
                            coachUid: widget.coachUid,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  final AthleteProfile athlete;
  final ChatMessage? last;
  final bool unread;
  final String initials;
  final String timeLabel;
  final VoidCallback onTap;

  const _ThreadRow({
    required this.athlete,
    required this.last,
    required this.unread,
    required this.initials,
    required this.timeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = last == null
        ? 'No messages yet'
        : (last!.isCoach ? 'You: ${last!.text}' : last!.text);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.mint.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.mint.withValues(alpha: 0.5)),
            ),
            child: Text(
              initials,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.mint,
              ),
            ),
          ),
          if (unread)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.coral,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        athlete.name.isNotEmpty ? athlete.name : 'Athlete',
        style: TextStyle(
          fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: unread ? AppColors.textPrimary : AppColors.textMuted,
          fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (timeLabel.isNotEmpty)
            Text(
              timeLabel,
              style: TextStyle(
                fontSize: 11,
                color: unread ? AppColors.mint : AppColors.textMuted,
                fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          if (unread) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'NEW',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: AppColors.mintDark,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
