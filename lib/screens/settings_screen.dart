import 'package:flutter/material.dart';

import 'package:vittix_irc/models/app_backup.dart';
import 'package:vittix_irc/models/app_settings.dart';
import 'package:vittix_irc/services/app_settings_service.dart';
import 'package:vittix_irc/services/backup_service.dart';
import 'package:vittix_irc/services/history_cleanup_service.dart';
import 'package:vittix_irc/services/sqlite_message_storage_service.dart';
import 'package:vittix_irc/state/session_manager.dart';
import 'package:vittix_irc/utils/history_retention_helper.dart';
import 'package:vittix_irc/screens/settings/friends_screen.dart';
import 'package:vittix_irc/screens/settings/file_upload_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ValueChanged<AppSettings>? onSettingsChanged;

  const SettingsScreen({
    super.key,
    this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = AppSettingsService();
  final _backupService = BackupService();
  final _cleanupService = HistoryCleanupService();

  AppSettings _settings = const AppSettings();
  bool _loading = true;

  double _clampChatFontSize(double size) {
    return size
        .clamp(
          AppSettings.minChatFontSize,
          AppSettings.maxChatFontSize,
        )
        .toDouble();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _service.getSettings();

    if (!mounted) return;

    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _update(AppSettings settings) async {
    setState(() => _settings = settings);

    await _service.saveSettings(settings);

    widget.onSettingsChanged?.call(settings);
    SessionManager.instance.reloadSettingsForAll();
  }

  Future<void> _manageBlockedNicks() async {
    final controller = TextEditingController();

    final result = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                final blocked = _settings.blockedNicks;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: 'Block rule',
                        hintText: 'baduser, bad*, or baduser!*@*',
                        helperText:
                            'Use nicknames, wildcard masks, or full hostmasks.',
                        suffixIcon: IconButton(
                          tooltip: 'Add',
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final nick = controller.text.trim();
                            if (nick.isEmpty) return;
                            Navigator.pop(context, nick);
                          },
                        ),
                      ),
                      onSubmitted: (value) {
                        final nick = value.trim();
                        if (nick.isEmpty) return;
                        Navigator.pop(context, nick);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (blocked.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('No block rules yet'),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: blocked.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final nick = blocked[index];
                            return ListTile(
                              leading: const Icon(Icons.block),
                              title: Text(nick),
                              trailing: IconButton(
                                tooltip: 'Unblock',
                                icon: const Icon(Icons.close),
                                onPressed: () async {
                                  await _service.saveSettings(
                                    _settings.copyWith(
                                      blockedNicks: _settings.blockedNicks
                                          .where((item) =>
                                              item.toLowerCase() !=
                                              nick.toLowerCase())
                                          .toList(),
                                    ),
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    _settings = _settings.copyWith(
                                      blockedNicks: _settings.blockedNicks
                                          .where((item) =>
                                              item.toLowerCase() !=
                                              nick.toLowerCase())
                                          .toList(),
                                    );
                                  });
                                  widget.onSettingsChanged?.call(_settings);
                                  SessionManager.instance
                                      .reloadSettingsForAll();
                                  setSheetState(() {});
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    controller.dispose();

    if (result == null || result.trim().isEmpty) return;

    final nick = result.trim();
    final exists = _settings.blockedNicks
        .any((item) => item.toLowerCase() == nick.toLowerCase());
    if (exists) return;

    await _update(
      _settings.copyWith(
        blockedNicks: [..._settings.blockedNicks, nick],
      ),
    );
  }

  Future<String?> _askBackupPassword({
    required String title,
  }) async {
    final controller = TextEditingController();

    final password = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Backup Password',
            helperText: 'Keep this password safe. It cannot be recovered.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context, text);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (!context.mounted) return null;
    controller.dispose();
    return password;
  }

  Future<void> _exportEncryptedBackup() async {
    final password = await _askBackupPassword(
      title: 'Encrypt Backup',
    );

    if (password == null) return;

    await _backupService.shareBackup(
      includePasswords: true,
      encryptionPassword: password,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Encrypted backup exported'),
      ),
    );
  }

  Future<void> _importBackup() async {
    AppBackup? backup;

    try {
      backup = await _backupService.pickBackupFile();
    } catch (_) {
      final password = await _askBackupPassword(
        title: 'Decrypt Backup',
      );

      if (password == null) return;

      try {
        backup = await _backupService.pickBackupFile(
          encryptionPassword: password,
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
          ),
        );
        return;
      }
    }

    if (backup == null) return;
    if (!mounted) return;

    final replaceExisting = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Import Backup'),
            content: Text(
              'Backup contains ${backup!.servers.length} server profiles.\n\n'
              'Do you want to replace existing profiles or merge them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Merge'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        ) ??
        false;

    if (!context.mounted) return;
    await _backupService.importBackup(
      backup: backup,
      replaceExisting: replaceExisting,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Backup imported successfully'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Use dark theme'),
                  value: _settings.darkMode,
                  onChanged: (value) {
                    _update(_settings.copyWith(darkMode: value));
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Show Message Timestamps'),
                  subtitle: const Text('Display time below each chat message'),
                  value: _settings.showTimestamps,
                  onChanged: (value) {
                    _update(_settings.copyWith(showTimestamps: value));
                  },
                ),
                SwitchListTile(
                  title: const Text('Show Media Previews'),
                  subtitle: const Text('Display image and link previews in chat'),
                  value: _settings.showMediaPreviews,
                  onChanged: (value) {
                    _update(_settings.copyWith(showMediaPreviews: value));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Friends'),
                  subtitle: Text(
                    _settings.friendNicks.isEmpty
                        ? 'No friends tracked'
                        : '${_settings.friendNicks.length} tracked friend(s)',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FriendsScreen(),
                      ),
                    ).then((_) => _load());
                  },
                ),
                SwitchListTile(
                  title: const Text('Show Join/Part Messages'),
                  subtitle: const Text('Display user joined/left messages'),
                  value: _settings.showJoinPartMessages,
                  onChanged: (value) {
                    _update(
                      _settings.copyWith(showJoinPartMessages: value),
                    );
                  },
                ),
                SwitchListTile(
                  title: const Text('Show Private System Messages'),
                  subtitle: const Text(
                    'Display system notices inside private chats',
                  ),
                  value: _settings.showPrivateSystemMessages,
                  onChanged: (value) {
                    _update(
                      _settings.copyWith(showPrivateSystemMessages: value),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.format_size),
                  title: const Text('Chat Text Size'),
                  subtitle: Text(
                    '${_settings.chatFontSize.toStringAsFixed(0)} pt',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Decrease',
                        onPressed: _settings.chatFontSize <=
                                AppSettings.minChatFontSize
                            ? null
                            : () {
                                _update(
                                  _settings.copyWith(
                                    chatFontSize: _clampChatFontSize(
                                      _settings.chatFontSize - 1,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        tooltip: 'Increase',
                        onPressed: _settings.chatFontSize >=
                                AppSettings.maxChatFontSize
                            ? null
                            : () {
                                _update(
                                  _settings.copyWith(
                                    chatFontSize: _clampChatFontSize(
                                      _settings.chatFontSize + 1,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Volume Keys Change Chat Text'),
                  subtitle: const Text(
                    'Use volume up/down to change chat text size while a chat is open',
                  ),
                  value: _settings.volumeKeysAdjustChatFont,
                  onChanged: (value) {
                    _update(
                      _settings.copyWith(volumeKeysAdjustChatFont: value),
                    );
                  },
                ),
                SwitchListTile(
                  title: const Text('Keep Hot Buffers in Place'),
                  subtitle: const Text(
                    'Do not move unread servers or chats to the top of the list',
                  ),
                  value: !_settings.hotBuffersMoveToTop,
                  onChanged: (value) {
                    _update(
                      _settings.copyWith(hotBuffersMoveToTop: !value),
                    );
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Mention Notifications'),
                  subtitle: const Text('Notify when your nick is mentioned'),
                  value: _settings.mentionNotifications,
                  onChanged: (value) {
                    _update(
                      _settings.copyWith(mentionNotifications: value),
                    );
                  },
                ),
                SwitchListTile(
                  title: const Text('Private Message Notifications'),
                  subtitle: const Text('Notify for private messages'),
                  value: _settings.privateMessageNotifications,
                  onChanged: (value) {
                    _update(
                      _settings.copyWith(
                        privateMessageNotifications: value,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('Ignore / Block List'),
                  subtitle: Text(
                    _settings.blockedNicks.isEmpty
                        ? 'No block rules'
                        : '${_settings.blockedNicks.length} block rule(s)',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _manageBlockedNicks,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Message History'),
                  subtitle: Text(_settings.historyRetention.label),
                  trailing: DropdownButton<MessageHistoryRetention>(
                    value: _settings.historyRetention,
                    items: MessageHistoryRetention.values.map((retention) {
                      return DropdownMenuItem(
                        value: retention,
                        child: Text(retention.label),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      if (value == null) return;

                      final updated = _settings.copyWith(
                        historyRetention: value,
                      );

                      await _update(updated);

                      final deleted = await _cleanupService.cleanupNow();

                      if (!context.mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            deleted == 0
                                ? 'History setting updated'
                                : 'History setting updated. Deleted $deleted old messages.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep),
                  title: const Text('Clear All Message History'),
                  subtitle: const Text('Delete all locally stored messages'),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Clear History?'),
                            content: const Text(
                              'This will delete all locally stored IRC messages. This cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        ) ??
                        false;

                    if (!confirm) return;

                    final deleted =
                        await SqliteMessageStorageService().clearAllMessages();

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Deleted $deleted messages'),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cloud_upload),
                  title: const Text('File Upload'),
                  subtitle: const Text('Configure HTTP POST upload server'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FileUploadSettingsScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption),
                  title: const Text('Export Encrypted Backup'),
                  subtitle: const Text(
                      'Includes passwords, protected by backup password'),
                  onTap: _exportEncryptedBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.file_open),
                  title: const Text('Import Backup'),
                  subtitle: const Text('Restore settings and server profiles'),
                  onTap: _importBackup,
                ),
              ],
            ),
    );
  }
}
