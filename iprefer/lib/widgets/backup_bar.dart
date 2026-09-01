import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/session.dart';
import '../data/sync/auth_client.dart';
import '../data/sync/sync_config.dart';
import '../data/sync/sync_service.dart';
import '../theme.dart';

/// One quiet line telling you whether your archive is actually safe.
///
/// The account's entire promise is "this survives losing the phone", and a
/// backup you cannot see is a backup you cannot trust — so unlike the rest of
/// the app's status text, this stays visible when everything is fine. It costs
/// one muted line; not knowing costs the whole reason to sign in.
///
/// Takes zero height for a guest: nothing has been promised, so there is
/// nothing to report.
class BackupBar extends StatefulWidget {
  const BackupBar({super.key});

  @override
  State<BackupBar> createState() => _BackupBarState();
}

class _BackupBarState extends State<BackupBar> {
  bool _signingIn = false;

  Future<void> _signInAgain() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);

    final session = context.read<Session>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.signInWithApple();
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("couldn't sign in — try again")),
      );
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    // Either source is enough. The persisted flag is what survives a relaunch;
    // the service's own flag covers the window before that write lands — and
    // if the write ever fails, without this the bar would fall back to
    // "couldn't reach your backup", which is exactly the indistinguishable-
    // from-offline behaviour this whole change exists to remove.
    final expired = context.watch<Session>().syncTokenExpired || sync.needsReauth;

    // Nothing to promise if the app was built without a backend at all.
    if (!syncConfigured) return const SizedBox.shrink();
    if (!sync.enabled && !expired) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Icon(
            expired ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
            size: 14,
            color: expired ? context.colors.accentInk : context.colors.muted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _message(sync, expired),
              style: TextStyle(
                color: expired ? context.colors.accentInk : context.colors.muted,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (expired)
            TextButton(
              onPressed: _signingIn ? null : _signInAgain,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(48, 36),
              ),
              child: Text(
                _signingIn ? 'signing in' : 'sign in',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  static String _message(SyncService sync, bool expired) {
    if (expired) return 'sign in again to keep backing up';
    if (sync.syncing) return 'backing up…';

    final pending = sync.pendingCount;
    if (pending > 0) {
      // Plain about the risk without alarming: these are safe on the phone,
      // just not anywhere else yet.
      return pending == 1
          ? '1 entry not backed up yet'
          : '$pending entries not backed up yet';
    }

    if (sync.lastError != null) return "couldn't reach your backup";
    final at = sync.lastSyncedAt;
    // Never claim safety we can't evidence: before the first completed sync
    // there is nothing backed up, and saying so is the honest reading.
    return at == null ? 'not backed up yet' : 'backed up ${_ago(at)}';
  }

  static String _ago(DateTime when) {
    final gap = DateTime.now().difference(when);
    if (gap.inMinutes < 1) return 'just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
    if (gap.inHours < 24) return '${gap.inHours}h ago';
    return '${gap.inDays}d ago';
  }
}
