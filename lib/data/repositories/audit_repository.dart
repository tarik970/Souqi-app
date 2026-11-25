import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/voucher.dart';

/// The log of sensitive actions: revealing a code, reprinting an invoice
/// that carries codes, voiding, returning to stock, loading and exporting.
///
/// Written through whatever executor the action itself runs on, so a logged
/// action and its log line land in the same transaction — a void that was
/// rolled back leaves no line saying it happened, and one that went through
/// cannot lose its line.
///
/// The details are a small JSON map of facts (a count, an invoice number,
/// the reason typed). A code never goes in here, in any form but the last
/// characters the screens already show.
class AuditRepository {
  AuditRepository(this._db);

  final DatabaseExecutor _db;

  /// Rows the screen loads at once.
  static const int pageSize = 200;

  Future<void> log(
    AuditAction action, {
    int? productId,
    String? productName,
    String? entityType,
    int? entityId,
    Map<String, Object?> details = const {},
    DateTime? at,
  }) async {
    final clean = <String, Object?>{
      for (final entry in details.entries)
        if (entry.value != null) entry.key: entry.value,
    };
    await _db.insert('audit_log', {
      'created_at': (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
      'action': action.db,
      'entity_type': entityType,
      'entity_id': entityId,
      'details': clean.isEmpty ? null : jsonEncode(clean),
      'product_id': productId,
      'product_name': productName,
    });
  }

  /// Newest first. [from] inclusive, [to] exclusive; [beforeId] continues a
  /// list below the last row already shown.
  Future<List<AuditEntry>> list({
    DateTime? from,
    DateTime? to,
    int? beforeId,
    int limit = pageSize,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from.toUtc().millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('created_at < ?');
      args.add(to.toUtc().millisecondsSinceEpoch);
    }
    if (beforeId != null) {
      where.add('id < ?');
      args.add(beforeId);
    }
    final rows = await _db.query(
      'audit_log',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(_entry).toList();
  }

  static AuditEntry _entry(Map<String, Object?> row) {
    var details = const <String, Object?>{};
    final raw = row['details'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          details = {
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          };
        }
      } on FormatException {
        // A line written by hand or by an older build: list it without
        // details rather than not at all.
      }
    }
    return AuditEntry(
      id: row['id'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
        isUtc: true,
      ),
      action: row['action'] as String,
      productId: row['product_id'] as int?,
      productName: row['product_name'] as String?,
      details: details,
    );
  }
}
