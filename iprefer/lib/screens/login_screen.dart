import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../data/session.dart';
import '../data/sync/auth_client.dart';
import '../data/sync/sync_config.dart';
import '../theme.dart';

/// The way in. Two of them, and neither is a gate.
///
/// Signing in with Apple exists for one reason: an archive you might lose is
/// one you don't invest in, and this app is betting on the recording habit.
/// But the app has always been complete without an account, so continuing
/// without one stays a real choice rather than a hidden escape hatch.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _signInWithApple() async {
    if (_busy) return;
    setState(() => _busy = true);

    final session = context.read<Session>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await session.signInWithApple();
      // A cancelled sign-in returns false and says nothing — backing out of a
      // system sheet is a decision, not an error worth a message.
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("couldn't sign in — try again")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(36),
          // Deliberately top-and-bottom: the lockup opens the page like a
          // title page, the actions stay at the thumb.
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
              if (syncConfigured) ...[
                SignInWithAppleButton(
                  onPressed: _busy ? () {} : _signInWithApple,
                  text: 'sign in with apple',
                  height: 48,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 10),
                const Text(
                  'keeps your archive if you lose or change your phone.',
                  style: TextStyle(color: AppTheme.mutedText, fontSize: 12),
                ),
                const SizedBox(height: 18),
              ],
              SizedBox(
                width: double.infinity,
                child: syncConfigured
                    // Once there is a better-supported path, staying local is
                    // the quieter of the two rather than the loud primary.
                    ? OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => context.read<Session>().continueAsGuest(),
                        child: const Text('continue without an account'),
                      )
                    : FilledButton(
                        onPressed: () =>
                            context.read<Session>().continueAsGuest(),
                        child: const Text('continue'),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                syncConfigured
                    ? 'without an account everything stays on this phone.'
                    : 'no account needed for now.',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
