import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/session.dart';
import '../theme.dart';

/// Stubbed first screen. "Continue" mints a local user id — no real auth.
///
/// TODO(firebase): this is where Google sign-in goes for v2. Replace the
/// single "continue" button with the real auth buttons; on success call into
/// [Session] (which will hold the Firebase uid instead of a local one). The
/// rest of the app reads `Session.signedIn` / `Session.userId` and needs no
/// change.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(36),
          // Deliberately top-and-bottom: the lockup opens the page like a
          // title page, the action stays at the thumb. (No mainAxisAlignment —
          // it fought the Spacer and lost, leaving the lockup adrift.)
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Text(
                'I prefer',
                style: TextStyle(
                  fontFamily: AppTheme.serif,
                  fontStyle: FontStyle.italic,
                  fontSize: 44,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'a quiet record of the things you like.\none photo, one line, at a time.',
                style: TextStyle(
                    color: AppTheme.mutedText, fontSize: 16, height: 1.5),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.read<Session>().continueAsGuest(),
                  child: const Text('continue'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'no account needed for now.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
