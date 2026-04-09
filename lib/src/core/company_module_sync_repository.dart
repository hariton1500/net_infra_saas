import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotebookRecord = Map<String, dynamic>;

class CompanyModuleSyncRepository {
  const CompanyModuleSyncRepository({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  Future<List<NotebookRecord>> readCache(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey);
    if (raw == null || raw.isEmpty) {
      return <NotebookRecord>[];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => _normalizeStoredRecord(Map<String, dynamic>.from(item)))
        .toList(growable: true);
  }

  Future<void> writeCache(String cacheKey, List<NotebookRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheKey, jsonEncode(_jsonSafe(records)));
  }

  Future<List<NotebookRecord>> pullMerge({
    required String companyId,
    required String moduleKey,
    required List<NotebookRecord> localRecords,
    Set<int>? skipReplaceIds,
  }) async {
    final merged = localRecords.map(_cloneRecord).toList(growable: true);
    final response = await _client
        .from('company_module_records')
        .select('record_id, payload, deleted, updated_at')
        .eq('company_id', companyId)
        .eq('module_key', moduleKey);

    final rows = (response as List<dynamic>).cast<Map<String, dynamic>>();

    for (final row in rows) {
      final recordId = _asInt(row['record_id']);
      final deleted = row['deleted'] == true;
      final serverUpdatedAt = _parseTime(row['updated_at']);
      final index = merged.indexWhere((record) => record['id'] == recordId);

      if (index == -1) {
        if (deleted) {
          continue;
        }

        final payload = _normalizeRemotePayload(row['payload']);
        if (payload.isEmpty) {
          continue;
        }

        payload['id'] = recordId;
        merged.add(payload);
        continue;
      }

      final local = merged[index];
      if (local['dirty'] == true) {
        continue;
      }

      if (deleted) {
        merged.removeAt(index);
        continue;
      }

      if (skipReplaceIds?.contains(recordId) == true) {
        continue;
      }

      final localUpdatedAt = _parseTime(local['updated_at']);
      if (serverUpdatedAt.isAfter(localUpdatedAt)) {
        final payload = _normalizeRemotePayload(row['payload']);
        if (payload.isEmpty) {
          continue;
        }
        payload['id'] = recordId;
        merged[index] = payload;
      }
    }

    return merged;
  }

  Future<List<NotebookRecord>> syncAll({
    required String companyId,
    required String moduleKey,
    required String cacheKey,
    required List<NotebookRecord> localRecords,
  }) async {
    final merged = localRecords.map(_cloneRecord).toList(growable: true);
    final dirtyRecords = merged
        .where((record) => record['dirty'] == true)
        .toList(growable: false);
    final justUpsertedIds = <int>{};

    for (final record in dirtyRecords) {
      final recordId = _asInt(record['id']);
      final updatedAt = _parseTime(record['updated_at']).toUtc();
      final timestamp = updatedAt.toIso8601String();

      if (record['deleted'] == true) {
        await _client.from('company_module_records').upsert({
          'company_id': companyId,
          'module_key': moduleKey,
          'record_id': recordId,
          'payload': null,
          'deleted': true,
          'updated_at': timestamp,
          'synced_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by_user_id': _client.auth.currentUser?.id,
        }, onConflict: 'company_id,module_key,record_id').select();
        merged.removeWhere((entry) => entry['id'] == recordId);
        continue;
      }

      await _client.from('company_module_records').upsert({
        'company_id': companyId,
        'module_key': moduleKey,
        'record_id': recordId,
        'payload': _payloadForDb(record),
        'deleted': false,
        'updated_at': timestamp,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by_user_id': _client.auth.currentUser?.id,
      }, onConflict: 'company_id,module_key,record_id').select();

      final index = merged.indexWhere((entry) => entry['id'] == recordId);
      if (index != -1) {
        merged[index]['dirty'] = false;
      }
      justUpsertedIds.add(recordId);
    }

    final unresolvedDirty = merged.any((record) => record['dirty'] == true);
    final next = unresolvedDirty
        ? merged
        : await pullMerge(
            companyId: companyId,
            moduleKey: moduleKey,
            localRecords: merged,
            skipReplaceIds: justUpsertedIds,
          );

    await writeCache(cacheKey, next);
    return next;
  }

  NotebookRecord clone(NotebookRecord source) => _cloneRecord(source);

  NotebookRecord normalize(NotebookRecord source) =>
      _normalizeStoredRecord(source);

  DateTime parseTime(dynamic value) => _parseTime(value);

  dynamic _jsonSafe(dynamic value) {
    if (value is DateTime) {
      return value.toIso8601String();
    }

    if (value is Map) {
      return value.map((key, entry) => MapEntry('$key', _jsonSafe(entry)));
    }

    if (value is List) {
      return value.map(_jsonSafe).toList(growable: false);
    }

    return value;
  }

  NotebookRecord _cloneRecord(NotebookRecord source) =>
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(_jsonSafe(source))) as Map,
      );

  NotebookRecord _normalizeStoredRecord(NotebookRecord source) {
    final record = Map<String, dynamic>.from(source);
    record['updated_at'] = _parseTime(record['updated_at']);
    record['dirty'] = record['dirty'] == true;
    record['deleted'] = record['deleted'] == true;
    return record;
  }

  NotebookRecord _normalizeRemotePayload(dynamic payload) {
    if (payload is! Map) {
      return <String, dynamic>{};
    }

    final record = Map<String, dynamic>.from(payload);
    record['updated_at'] = _parseTime(record['updated_at']);
    record['dirty'] = false;
    record['deleted'] = false;
    return record;
  }

  NotebookRecord _payloadForDb(NotebookRecord record) {
    final payload = _cloneRecord(record);
    payload.remove('dirty');
    payload.remove('deleted');
    return payload;
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.parse(value.toString());
  }

  DateTime _parseTime(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
  }
}
