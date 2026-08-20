import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'demo_accounts.dart';

/// True when a debug demo account is signed in. Streams then fall back to
/// [DemoData] if Firestore is empty or permission-denied.
class DemoOverlay {
  static bool get enabled {
    if (!kDebugMode) return false;
    return DemoAccounts.isDemoEmail(FirebaseAuth.instance.currentUser?.email);
  }
}
