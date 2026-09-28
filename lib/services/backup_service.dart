import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vittix_irc/models/app_backup.dart';
import 'package:vittix_irc/models/server_config.dart';
import 'package:vittix_irc/services/app_settings_service.dart';
import 'package:vittix_irc/services/server_storage_service.dart';
import 'package:vittix_irc/utils/backup_crypto.dart';

class BackupService {
  final _serverStorage = ServerStorageService();
  final _settingsService = AppSettingsService();

  Future<File> exportBackup({
    bool includePasswords = false,
    String? encryptionPassword,
  }) async {
    final servers = await _serverStorage.getServers();
    final settings = await _settingsService.getSettings();

    final cleanServers = servers.map((server) {
      if (includePasswords) return server;
      return server.copyWith(password: null);
    }).toList();

    final backup = AppBackup(
      createdAt: DateTime.now(),
      settings: settings,
      servers: cleanServers,
    );

    final dir = await getTemporaryDirectory();

    final encrypted = includePasswords &&
        encryptionPassword != null &&
        encryptionPassword.isNotEmpty;

    final file = File(
      '${dir.path}/irc_mobile_backup_${DateTime.now().millisecondsSinceEpoch}'
      '${encrypted ? "_encrypted" : ""}.json',
    );

    final backupJson = backup.toJson();

    final content = encrypted
        ? BackupCrypto.encryptJson(
            json: backupJson,
            password: encryptionPassword,
          )
        : const JsonEncoder.withIndent('  ').convert(backupJson);

    await file.writeAsString(content);

    return file;
  }

  Future<void> shareBackup({
    bool includePasswords = false,
    String? encryptionPassword,
  }) async {
    final file = await exportBackup(
      includePasswords: includePasswords,
      encryptionPassword: encryptionPassword,
    );

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'IRC Mobile Backup',
      text: includePasswords
          ? 'Encrypted IRC Mobile backup'
          : 'IRC Mobile server profiles and settings backup',
    );
  }

  Future<AppBackup?> pickBackupFile({
    String? encryptionPassword,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open IRC backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null || path.isEmpty) return null;

    final backupText = await File(path).readAsString();

    final raw = jsonDecode(backupText) as Map<String, dynamic>;

    final decoded = raw['encrypted'] == true
        ? BackupCrypto.decryptJson(
            encryptedText: backupText,
            password: encryptionPassword ?? '',
          )
        : raw;

    return AppBackup.fromJson(decoded);
  }

  Future<void> importBackup({
    required AppBackup backup,
    required bool replaceExisting,
  }) async {
    await _settingsService.saveSettings(backup.settings);

    final existing = replaceExisting ? [] : await _serverStorage.getServers();
    final mergedById = {
      for (final server in existing) server.id: server,
      for (final server in backup.servers) server.id: server,
    };

    await _serverStorage.saveServers(
      mergedById.values.toList().cast<ServerConfig>(),
    );
  }
}
