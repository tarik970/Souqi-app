import '../../../core/constants/settings_keys.dart';
import 'report_schedule.dart';

enum ReportFormat {
  xlsx(
    'XLSX',
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  pdf('PDF', 'pdf', 'application/pdf');

  const ReportFormat(this.db, this.extension, this.mimeType);

  final String db;
  final String extension;
  final String mimeType;
}

/// Where the chosen folder is, as far as Android can tell — for the warning
/// that a folder on the phone itself does not survive the phone.
enum FolderKind {
  phone('PHONE'),
  removable('REMOVABLE'),
  cloud('CLOUD'),
  other('OTHER');

  const FolderKind(this.db);

  final String db;

  static FolderKind fromDb(String? value) => values.firstWhere(
        (kind) => kind.db == value,
        orElse: () => FolderKind.other,
      );
}

/// Settings → Debts → "Daily debt report". Stored in the `settings` table
/// (so they travel with a backup); the folder's PERMISSION does not — on a
/// restored phone the folder is "not available" until chosen again, and
/// the report goes to Downloads meanwhile.
class DebtReportSettings {
  const DebtReportSettings({
    this.enabled = false,
    this.minuteOfDay = defaultReportMinuteOfDay,
    this.formats = const {ReportFormat.xlsx, ReportFormat.pdf},
    this.folderUri,
    this.folderName,
    this.folderKind = FolderKind.other,
    this.keepDays = 30,
    this.notify = true,
    this.enabledAt,
  });

  final bool enabled;
  final int minuteOfDay;

  /// Never empty.
  final Set<ReportFormat> formats;

  /// A Storage Access Framework tree; null = Download/Souqi/Reports.
  final String? folderUri;
  final String? folderName;
  final FolderKind folderKind;

  /// How many days' reports stay in the folder (keep-N).
  final int keepDays;
  final bool notify;

  /// When it was last turned on — reports due before that were never owed
  /// (see [needsCatchUp]).
  final DateTime? enabledAt;

  static const List<int> keepChoices = [7, 14, 30, 60, 90, 180, 365];

  bool get usesDownloads => folderUri == null;

  /// The reports stay on the phone itself: Downloads, or a folder on its
  /// internal storage.
  bool get staysOnPhone => usesDownloads || folderKind == FolderKind.phone;

  List<ReportFormat> get orderedFormats => [
        for (final format in ReportFormat.values)
          if (formats.contains(format)) format,
      ];

  static DebtReportSettings fromMap(Map<String, String> stored) {
    String get(String key) =>
        stored[key] ?? SettingsKeys.defaults[key] ?? '';
    final minute = int.tryParse(get(SettingsKeys.debtReportMinute));
    final keep = int.tryParse(get(SettingsKeys.debtReportKeepDays));
    final formats = {
      for (final part in get(SettingsKeys.debtReportFormats).split(','))
        for (final format in ReportFormat.values)
          if (format.db == part.trim()) format,
    };
    final uri = get(SettingsKeys.debtReportFolderUri).trim();
    final enabledAt = int.tryParse(get(SettingsKeys.debtReportEnabledAt)) ?? 0;
    return DebtReportSettings(
      enabled: get(SettingsKeys.debtReportEnabled) == '1',
      minuteOfDay: minute == null || minute < 0 || minute >= 24 * 60
          ? defaultReportMinuteOfDay
          : minute,
      formats: formats.isEmpty ? const {ReportFormat.xlsx, ReportFormat.pdf} : formats,
      folderUri: uri.isEmpty ? null : uri,
      folderName: uri.isEmpty ? null : get(SettingsKeys.debtReportFolderName),
      folderKind: FolderKind.fromDb(get(SettingsKeys.debtReportFolderKind)),
      keepDays: keep == null || keep < 1 ? 30 : keep,
      notify: get(SettingsKeys.debtReportNotify) != '0',
      enabledAt: enabledAt <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(enabledAt, isUtc: true),
    );
  }

  Map<String, String> toMap() => {
        SettingsKeys.debtReportEnabled: enabled ? '1' : '0',
        SettingsKeys.debtReportMinute: '$minuteOfDay',
        SettingsKeys.debtReportFormats:
            orderedFormats.map((f) => f.db).join(','),
        SettingsKeys.debtReportFolderUri: folderUri ?? '',
        SettingsKeys.debtReportFolderName: folderUri == null ? '' : (folderName ?? ''),
        SettingsKeys.debtReportFolderKind: folderUri == null ? '' : folderKind.db,
        SettingsKeys.debtReportKeepDays: '$keepDays',
        SettingsKeys.debtReportNotify: notify ? '1' : '0',
        SettingsKeys.debtReportEnabledAt:
            '${enabledAt?.toUtc().millisecondsSinceEpoch ?? 0}',
      };

  DebtReportSettings copyWith({
    bool? enabled,
    int? minuteOfDay,
    Set<ReportFormat>? formats,
    String? folderUri,
    String? folderName,
    FolderKind? folderKind,
    bool clearFolder = false,
    int? keepDays,
    bool? notify,
    DateTime? enabledAt,
  }) =>
      DebtReportSettings(
        enabled: enabled ?? this.enabled,
        minuteOfDay: minuteOfDay ?? this.minuteOfDay,
        formats: formats ?? this.formats,
        folderUri: clearFolder ? null : (folderUri ?? this.folderUri),
        folderName: clearFolder ? null : (folderName ?? this.folderName),
        folderKind:
            clearFolder ? FolderKind.other : (folderKind ?? this.folderKind),
        keepDays: keepDays ?? this.keepDays,
        notify: notify ?? this.notify,
        enabledAt: enabledAt ?? this.enabledAt,
      );
}

enum ReportOutcome {
  /// Written to the chosen folder (or to Downloads when none is chosen).
  ok('OK'),

  /// The chosen folder was not available: written to Downloads instead.
  fallback('FALLBACK'),
  failed('FAILED');

  const ReportOutcome(this.wire);

  final String wire;

  static ReportOutcome? fromWire(Object? value) {
    for (final outcome in values) {
      if (outcome.wire == value) return outcome;
    }
    return null;
  }
}

enum ReportProblem {
  folderUnavailable('FOLDER_UNAVAILABLE'),
  writeFailed('WRITE_FAILED'),
  unknown('UNKNOWN');

  const ReportProblem(this.wire);

  final String wire;

  static ReportProblem? fromWire(Object? value) {
    for (final problem in values) {
      if (problem.wire == value) return problem;
    }
    return value == null ? null : ReportProblem.unknown;
  }
}

/// What the last run did — kept by Android next to the schedule, shown
/// under the setting ("Last report: today 22:01 ✓").
class DebtReportStatus {
  const DebtReportStatus({
    this.lastAttemptAt,
    this.lastSuccessAt,
    this.outcome,
    this.problem,
    this.location,
    this.savedToFolderUri,
    this.files = const [],
    this.debtors,
    this.outstandingBaseMinor,
  });

  final DateTime? lastAttemptAt;

  /// The last run that wrote its files somewhere (fallback included) — what
  /// the catch-up rule compares with.
  final DateTime? lastSuccessAt;
  final ReportOutcome? outcome;
  final ReportProblem? problem;

  /// Where the last files went, as shown to the user.
  final String? location;

  /// The folder the last files went to; null = Downloads.
  final String? savedToFolderUri;

  /// The app's own copies of the last files — what "Share" hands over.
  final List<String> files;
  final int? debtors;
  final int? outstandingBaseMinor;

  static DateTime? _date(Object? ms) => ms is int && ms > 0
      ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
      : null;

  static DebtReportStatus fromJson(Map<String, Object?>? json) {
    if (json == null) return const DebtReportStatus();
    return DebtReportStatus(
      lastAttemptAt: _date(json['attemptAt']),
      lastSuccessAt: _date(json['successAt']),
      outcome: ReportOutcome.fromWire(json['outcome']),
      problem: ReportProblem.fromWire(json['problem']),
      location: json['location'] as String?,
      savedToFolderUri: json['folderUri'] as String?,
      files: [
        for (final path in (json['files'] as List<Object?>?) ?? const [])
          if (path is String) path,
      ],
      debtors: json['debtors'] as int?,
      outstandingBaseMinor: json['outstanding'] as int?,
    );
  }

  Map<String, Object?> toJson() => {
        'attemptAt': lastAttemptAt?.toUtc().millisecondsSinceEpoch,
        'successAt': lastSuccessAt?.toUtc().millisecondsSinceEpoch,
        'outcome': outcome?.wire,
        'problem': problem?.wire,
        'location': location,
        'folderUri': savedToFolderUri,
        'files': files,
        'debtors': debtors,
        'outstanding': outstandingBaseMinor,
      };
}
