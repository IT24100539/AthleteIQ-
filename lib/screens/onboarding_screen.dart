import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class _OnboardingSlideData {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingSlideData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

/// Shown when a new user taps "Create an account" on the sign-in screen,
/// before they land on the sign-up form. Pops itself when done, letting
/// the caller (SignInScreen) flip into sign-up mode.
class OnboardingScreen extends StatefulWidget {
  final String role; // 'athlete' | 'coach' — passed through for future use

  const OnboardingScreen({super.key, required this.role});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  static const List<_OnboardingSlideData> _slides = [
    _OnboardingSlideData(
      icon: Icons.psychology_alt_outlined,
      title: 'See risk before it\nbecomes injury',
      description:
          'AthleteIQ watches your training load and\nrecovery every day, not just at check-ins.',
    ),
    _OnboardingSlideData(
      icon: Icons.shield_outlined,
      title: 'Your coach always\ndecides',
      description:
          'AthleteIQ recommends. Your coach reviews\nand approves every change before you see it.',
    ),
    _OnboardingSlideData(
      icon: Icons.chat_bubble_outline,
      title: 'Grounded in sports\nscience',
      description:
          'Every explanation is backed by real\nresearch, not just a black-box number.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() => Navigator.of(context).pop();

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isLastPage)
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        'Skip',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) {
                  final slide = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: SingleChildScrollView(
                      child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.mint.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(slide.icon, color: AppColors.mint, size: 32),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.description,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? AppColors.mint : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(isLastPage ? 'Get Started' : 'Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}