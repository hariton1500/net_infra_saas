import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'project_scope.dart';

typedef NotebookRecord = Map<String, dynamic>;

class CompanyModuleSyncRepository {
  static const String _lastLocationLatKey = 'map.last_location.lat.v1';
  static const String _lastLocationLngKey = 'map.last_location.lng.v1';
  static const String _activeProjectIdKey = 'projects.active.id.v1';
  static const String _activeProjectNameKey = 'projects.active.name.v1';
  static const String _activeProjectAuthorUserIdKey =
      'projects.active.author_user_id.v1';
  static const String _activeProjectAuthorEmailKey =
      'projects.active.author_email.v1';

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

  Future<void> removeCache(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
  }

  Future<LatLng?> readLastPickedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_lastLocationLatKey);
    final lng = prefs.getDouble(_lastLocationLngKey);
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  Future<void> writeLastPickedLocation(LatLng point) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lastLocationLatKey, point.latitude);
    await prefs.setDouble(_lastLocationLngKey, point.longitude);
  }

  Future<ProjectSelection?> readActiveProject() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_activeProjectIdKey);
    final name = prefs.getString(_activeProjectNameKey)?.trim();
    if (id == null || name == null || name.isEmpty) {
      return null;
    }
    return ProjectSelection(
      id: id,
      name: name,
      authorUserId: prefs.getString(_activeProjectAuthorUserIdKey)?.trim(),
      authorEmail:
          prefs.getString(_activeProjectAuthorEmailKey)?.trim().toLowerCase(),
    );
  }

  Future<void> writeActiveProject(ProjectSelection project) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeProjectIdKey, project.id);
    await prefs.setString(_activeProjectNameKey, project.name);
    if ((project.authorUserId ?? '').trim().isNotEmpty) {
      await prefs.setString(
        _activeProjectAuthorUserIdKey,
        project.authorUserId!.trim(),
      );
    } else {
      await prefs.remove(_activeProjectAuthorUserIdKey);
    }
    final normalizedAuthorEmail =
        project.authorEmail?.trim().toLowerCase() ?? '';
    if (normalizedAuthorEmail.isNotEmpty) {
      await prefs.setString(_activeProjectAuthorEmailKey, normalizedAuthorEmail);
    } else {
      await prefs.remove(_activeProjectAuthorEmailKey);
    }
  }

  Future<void> clearActiveProject() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeProjectIdKey);
    await prefs.remove(_activeProjectNameKey);
    await prefs.remove(_activeProjectAuthorUserIdKey);
    await prefs.remove(_activeProjectAuthorEmailKey);
  }

  Future<bool> appendTaskWorkLog({
    required String companyId,
    required ProjectSelection activeProject,
    required String actorUserId,
    required String actorEmail,
    required String kind,
    required String summary,
    String? targetScreen,
    int? targetRecordId,
  }) async {
    final records = await readCache(projectsCacheKey);
    final index = records.indexWhere((record) => record['id'] == activeProject.id);
    if (index == -1) {
      return false;
    }

    final task = _cloneRecord(records[index]);
    if (task['deleted'] == true || task['archived'] == true) {
      return false;
    }

    final normalizedActorEmail = actorEmail.trim().toLowerCase();
    final normalizedAuthorUserId =
        (activeProject.authorUserId?.trim().isNotEmpty == true
                ? activeProject.authorUserId
                : task['created_by_user_id']?.toString())
            ?.trim() ??
        '';
    final normalizedAuthorEmail =
        (activeProject.authorEmail?.trim().isNotEmpty == true
                ? activeProject.authorEmail
                : task['created_by_email']?.toString())
            ?.trim()
            .toLowerCase() ??
        '';
    final matchesAuthor =
        (normalizedAuthorUserId.isNotEmpty &&
            normalizedAuthorUserId == actorUserId.trim()) ||
        (normalizedAuthorEmail.isNotEmpty &&
            normalizedAuthorEmail == normalizedActorEmail);
    if (!matchesAuthor) {
      return false;
    }

    if ((activeProject.authorUserId?.trim().isEmpty ?? true) ||
        (activeProject.authorEmail?.trim().isEmpty ?? true)) {
      await writeActiveProject(
        ProjectSelection(
          id: activeProject.id,
          name: activeProject.name,
          authorUserId:
              normalizedAuthorUserId.isEmpty ? null : normalizedAuthorUserId,
          authorEmail:
              normalizedAuthorEmail.isEmpty ? null : normalizedAuthorEmail,
        ),
      );
    }

    final normalizedTargetScreen = targetScreen?.trim();
    final workLog = List<Map<String, dynamic>>.from(task['work_log'] ?? const []);
    workLog.add({
      'at': DateTime.now(),
      'kind': kind,
      'summary': summary.trim(),
      if (normalizedTargetScreen?.isNotEmpty == true)
        'target_screen': normalizedTargetScreen,
      ...?targetRecordId == null
          ? null
          : <String, dynamic>{'target_record_id': targetRecordId},
    });
    task['work_log'] = workLog;
    task['updated_at'] = DateTime.now();
    task['updated_by'] = actorEmail.trim();
    task['dirty'] = true;
    records[index] = task;

    await syncAll(
      companyId: companyId,
      moduleKey: projectsModuleKey,
      cacheKey: projectsCacheKey,
      localRecords: records,
    );
    return true;
  }

  Future<List<NotebookRecord>> pullMerge({
    required String companyId,
    required String moduleKey,
    required List<NotebookRecord> localRecords,
    Set<int>? skipReplaceIds,
  }) async {
    final merged = localRecords.map(_cloneRecord).toList(growable: true);
    final response = await _runWithRetry(
      () => _client
          .from('company_module_records')
          .select('record_id, payload, deleted, updated_at')
          .eq('company_id', companyId)
          .eq('module_key', moduleKey),
    );

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
        await _runWithRetry(
          () => _client.from('company_module_records').upsert({
            'company_id': companyId,
            'module_key': moduleKey,
            'record_id': recordId,
            'payload': null,
            'deleted': true,
            'updated_at': timestamp,
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'updated_by_user_id': _client.auth.currentUser?.id,
          }, onConflict: 'company_id,module_key,record_id').select(),
        );
        merged.removeWhere((entry) => entry['id'] == recordId);
        continue;
      }

      await _runWithRetry(
        () => _client.from('company_module_records').upsert({
          'company_id': companyId,
          'module_key': moduleKey,
          'record_id': recordId,
          'payload': _payloadForDb(record),
          'deleted': false,
          'updated_at': timestamp,
          'synced_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by_user_id': _client.auth.currentUser?.id,
        }, onConflict: 'company_id,module_key,record_id').select(),
      );

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

  Future<T> _runWithRetry<T>(
    Future<T> Function() action, {
    int attempts = 3,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await action();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final shouldRetry =
            attempt < attempts - 1 && _isTransientNetworkError(error);
        if (!shouldRetry) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  bool _isTransientNetworkError(Object error) {
    return error is HandshakeException ||
        error is SocketException ||
        error is HttpException ||
        error is TimeoutException;
  }
}
