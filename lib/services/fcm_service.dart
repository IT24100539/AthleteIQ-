import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'firestore_service.dart';

/// Requests notification permission and stores the FCM token on users/{uid}.
class FcmService {
  static String? _registeredUid;

  static Future<void> registerForUser(String uid) async {
    if (kIsWeb) return;
    if (_registeredUid == uid) return;
    _registeredUid = uid;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await FirestoreService().saveFcmToken(uid, token);
      }
      messaging.onTokenRefresh.listen((newToken) {
        final current = FirebaseAuth.instance.currentUser?.uid;
        if (current == null) return;
        FirestoreService().saveFcmToken(current, newToken);
      });
    } catch (e) {
      debugPrint('FCM registration skipped: $e');
    }
  }
}
