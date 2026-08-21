import 'dart:io';

import 'package:auto_updater/auto_updater.dart';

enum UpdateCheckResult { started, notConfigured, unsupported }

abstract class UpdateService {
  bool get isSupported;

  bool get isConfigured;

  Future<void> initialize();

  Future<UpdateCheckResult> checkForUpdates();
}

abstract class AutoUpdaterClient {
  Future<void> setFeedURL(String feedUrl);

  Future<void> checkForUpdates({required bool inBackground});

  Future<void> setScheduledCheckInterval(int interval);
}

class WinSparkleAutoUpdaterClient implements AutoUpdaterClient {
  @override
  Future<void> setFeedURL(String feedUrl) {
    return autoUpdater.setFeedURL(feedUrl);
  }

  @override
  Future<void> checkForUpdates({required bool inBackground}) {
    return autoUpdater.checkForUpdates(inBackground: inBackground);
  }

  @override
  Future<void> setScheduledCheckInterval(int interval) {
    return autoUpdater.setScheduledCheckInterval(interval);
  }
}

class AutoUpdateService implements UpdateService {
  static const int _minimumCheckIntervalSeconds = 3600;
  static const int _defaultCheckIntervalSeconds = 6 * 60 * 60;

  final String feedUrl;
  final int checkIntervalSeconds;
  final AutoUpdaterClient _client;
  final bool _isSupported;

  bool _isConfiguredOnPlatform = false;
  bool _startupCheckRequested = false;
  Future<void>? _configuration;

  AutoUpdateService({
    String feedUrl = const String.fromEnvironment('JSON_LAYER_UPDATE_FEED_URL'),
    int checkIntervalSeconds = const int.fromEnvironment(
      'JSON_LAYER_UPDATE_CHECK_INTERVAL_SECONDS',
      defaultValue: _defaultCheckIntervalSeconds,
    ),
    AutoUpdaterClient? client,
    bool? isSupported,
  }) : feedUrl = feedUrl.trim(),
       checkIntervalSeconds =
           checkIntervalSeconds == 0 ||
               checkIntervalSeconds >= _minimumCheckIntervalSeconds
           ? checkIntervalSeconds
           : _defaultCheckIntervalSeconds,
       _client = client ?? WinSparkleAutoUpdaterClient(),
       _isSupported = isSupported ?? Platform.isWindows;

  @override
  bool get isSupported => _isSupported;

  @override
  bool get isConfigured {
    final uri = Uri.tryParse(feedUrl);
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    return uri.scheme == 'http' &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1');
  }

  @override
  Future<void> initialize() async {
    if (!isSupported || !isConfigured || _startupCheckRequested) return;

    _startupCheckRequested = true;
    try {
      await _ensureConfigured();
      await _client.checkForUpdates(inBackground: true);
    } catch (_) {
      _startupCheckRequested = false;
      rethrow;
    }
  }

  @override
  Future<UpdateCheckResult> checkForUpdates() async {
    if (!isSupported) return UpdateCheckResult.unsupported;
    if (!isConfigured) return UpdateCheckResult.notConfigured;

    await _ensureConfigured();
    await _client.checkForUpdates(inBackground: false);
    return UpdateCheckResult.started;
  }

  Future<void> _ensureConfigured() async {
    if (_isConfiguredOnPlatform) return;

    final pending = _configuration;
    if (pending != null) {
      await pending;
      return;
    }

    final operation = _configurePlatform();
    _configuration = operation;
    try {
      await operation;
      _isConfiguredOnPlatform = true;
    } finally {
      _configuration = null;
    }
  }

  Future<void> _configurePlatform() async {
    await _client.setFeedURL(feedUrl);
    await _client.setScheduledCheckInterval(checkIntervalSeconds);
  }
}
