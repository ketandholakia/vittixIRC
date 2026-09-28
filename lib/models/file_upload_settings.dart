enum UploadAuthType {
  none,
  basic,
}

class FileUploadSettings {
  final String uploadUrl;
  final String fileField;
  final String responseRegex;
  final String additionalHeaders;
  final String additionalFields;
  final UploadAuthType authType;
  final String? username;
  final String? password;
  final int rememberUploadsHours;
  final int maxFileSizeMb;

  const FileUploadSettings({
    this.uploadUrl = '',
    this.fileField = 'file',
    this.responseRegex = '',
    this.additionalHeaders = '',
    this.additionalFields = '',
    this.authType = UploadAuthType.none,
    this.username,
    this.password,
    this.rememberUploadsHours = 24,
    this.maxFileSizeMb = 25,
  });

  bool get isConfigured => uploadUrl.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'uploadUrl': uploadUrl,
      'fileField': fileField,
      'responseRegex': responseRegex,
      'additionalHeaders': additionalHeaders,
      'additionalFields': additionalFields,
      'authType': authType.name,
      'username': username,
      'password': password,
      'rememberUploadsHours': rememberUploadsHours,
      'maxFileSizeMb': maxFileSizeMb,
    };
  }

  factory FileUploadSettings.fromJson(Map<String, dynamic> json) {
    return FileUploadSettings(
      uploadUrl: json['uploadUrl'] as String? ?? '',
      fileField: json['fileField'] as String? ?? 'file',
      responseRegex: json['responseRegex'] as String? ?? '',
      additionalHeaders: json['additionalHeaders'] as String? ?? '',
      additionalFields: json['additionalFields'] as String? ?? '',
      authType: UploadAuthType.values.firstWhere(
        (e) => e.name == json['authType'],
        orElse: () => UploadAuthType.none,
      ),
      username: json['username'] as String?,
      password: json['password'] as String?,
      rememberUploadsHours: json['rememberUploadsHours'] as int? ?? 24,
      maxFileSizeMb: json['maxFileSizeMb'] as int? ?? 25,
    );
  }

  FileUploadSettings copyWith({
    String? uploadUrl,
    String? fileField,
    String? responseRegex,
    String? additionalHeaders,
    String? additionalFields,
    UploadAuthType? authType,
    String? username,
    String? password,
    int? rememberUploadsHours,
    int? maxFileSizeMb,
  }) {
    return FileUploadSettings(
      uploadUrl: uploadUrl ?? this.uploadUrl,
      fileField: fileField ?? this.fileField,
      responseRegex: responseRegex ?? this.responseRegex,
      additionalHeaders: additionalHeaders ?? this.additionalHeaders,
      additionalFields: additionalFields ?? this.additionalFields,
      authType: authType ?? this.authType,
      username: username ?? this.username,
      password: password ?? this.password,
      rememberUploadsHours:
          rememberUploadsHours ?? this.rememberUploadsHours,
      maxFileSizeMb: maxFileSizeMb ?? this.maxFileSizeMb,
    );
  }
}
