import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart';

class SignInScreen extends StatefulWidget {
  // NEW: lets callers (e.g. OnboardingScreen's caller) land directly in
  // sign-up mode with the right role tab pre-selected.
  final bool initialIsSignUp;
  final String initialRole;

  const SignInScreen({
    super.key,
    this.initialIsSignUp = false,
    this.initialRole = 'athlete',
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _auth = AuthService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  // CHANGED: these now seed from the widget's initial values instead of
  // being hardcoded, and are set in initState (widget isn't available
  // at field-initializer time).
  late bool _isSignUp;
  late String _role; // 'athlete' | 'coach'
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.initialIsSignUp;
    _role = widget.initialRole;
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    if (_isSignUp && _name.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isSignUp) {
        await _auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
          role: _role,
        );
      } else {
        final cred = await _auth.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );

        // Verify that user role in Firestore matches selected tab
        final userRole = await _auth.getRole(cred.user!.uid);
        if (userRole != null && userRole != _role) {
          await _auth.signOut();
          if (!mounted) return;
          setState(() {
            _error =
                'This account is registered as a ${userRole.toUpperCase()}. Please switch to the ${userRole == 'coach' ? 'Coach Login' : 'Athlete Login'} tab.';
          });
          return;
        }
      }
      // Navigation is handled by the auth-state StreamBuilder in main.dart.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'Authentication failed');
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // NEW: routes a new user through the onboarding intro slides before
  // flipping the form into sign-up mode. Existing users toggling back
  // to sign-in skip straight there — no onboarding needed.
  void _handleCreateAccountTap() {
    if (!_isSignUp) {
      Navigator.of(context)
          .push(
              MaterialPageRoute(builder: (_) => OnboardingScreen(role: _role)))
          .then((_) {
        if (!mounted) return;
        setState(() {
          _isSignUp = true;
          _error = null;
        });
      });
    } else {
      setState(() {
        _isSignUp = false;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAthlete = _role == 'athlete';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.mint,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.mint.withValues(alpha: 0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.bolt,
                        color: AppColors.mintDark, size: 28),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isSignUp
                      ? (isAthlete
                          ? 'Create Athlete Account'
                          : 'Create Coach Account')
                      : (isAthlete ? 'Athlete Sign In' : 'Coach Sign In'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  isAthlete
                      ? 'Track load, catch injury risk early, and train smart.'
                      : 'Monitor team risk, review AI calls, and approve training plans.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),

                // SEPARATE ROLE LOGIN SELECTOR TABS
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _RoleTab(
                          label: 'Athlete Login',
                          icon: Icons.person_outline,
                          selected: isAthlete,
                          onTap: () => setState(() {
                            _role = 'athlete';
                            _error = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _RoleTab(
                          label: 'Coach Login',
                          icon: Icons.sports_outlined,
                          selected: !isAthlete,
                          onTap: () => setState(() {
                            _role = 'coach';
                            _error = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_isSignUp) ...[
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      hintText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline,
                          size: 20, color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined,
                        size: 20, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline,
                        size: 20, color: AppColors.textMuted),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.riskHighBg,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppColors.coral.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.coral, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                                color: AppColors.coral, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: Text(
                    _loading
                        ? 'Please wait…'
                        : (_isSignUp
                            ? (isAthlete
                                ? 'Create Athlete Account'
                                : 'Create Coach Account')
                            : (isAthlete
                                ? 'Sign in as Athlete'
                                : 'Sign in as Coach')),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  // CHANGED: was an inline setState toggle, now routes
                  // through onboarding first when moving into sign-up.
                  onPressed: _handleCreateAccountTap,
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : (isAthlete
                            ? 'New Athlete? Create an account'
                            : 'New Coach? Create an account'),
                    style: const TextStyle(
                        color: AppColors.mint,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.mintDark : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.mintDark : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}
