/// Where the sync backend lives.
///
/// Overridable at build time so a device can be pointed at a local worker:
///   flutter run --dart-define=IPREFER_SYNC_URL=http://192.168.1.5:8787
///
/// An empty value turns sync off entirely and the app is local-only, which is
/// still a first-class way to use it — signing in is optional, not a gate.
const String kSyncBaseUrl = String.fromEnvironment(
  'IPREFER_SYNC_URL',
  defaultValue: 'https://iprefer-sync.alex-apps.workers.dev',
);

bool get syncConfigured => kSyncBaseUrl.isNotEmpty;
