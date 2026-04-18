import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/map_tile_providers.dart';
import '../core/project_scope.dart';

class CableLinesPage extends StatefulWidget {
  const CableLinesPage({
    super.key,
    required this.controller,
    this.initialRouteId,
  });

  final AuthController controller;
  final int? initialRouteId;

  @override
  State<CableLinesPage> createState() => _CableLinesPageState();
}

class _CableLineRoute {
  const _CableLineRoute({
    required this.id,
    required this.name,
    required this.points,
    required this.meta,
    required this.raw,
  });

  final int id;
  final String name;
  final List<LatLng> points;
  final Map<String, String> meta;
  final Map<String, dynamic> raw;
}

enum _CableAnchorType { muff, ponBox, cabinet }

class _CableAnchorOption {
  const _CableAnchorOption({
    required this.key,
    required this.type,
    required this.entityId,
    required this.name,
    required this.subtitle,
    required this.location,
    required this.point,
  });

  final String key;
  final _CableAnchorType type;
  final int entityId;
  final String name;
  final String subtitle;
  final String location;
  final LatLng point;
}

class _CableLinesPageState extends State<CableLinesPage> {
  static const String _moduleKey = 'cable_lines';
  static const String _cacheKey = 'cable_lines.routes.v1';
  static const String _muffsCacheKey = 'muff_notebook.muffs.v3';
  static const String _cabinetsCacheKey = 'network_cabinet.cabinets.v1';
  static const LatLng _fallbackCenter = LatLng(44.9521, 34.1024);

  final MapController _mapController = MapController();
  late final CompanyModuleSyncRepository _syncRepository;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool _loading = true;
  bool _syncing = false;
  bool _editing = false;
  String? _errorMessage;
  double _mapZoom = 13;
  String _selectedTileLayerId = 'osm';
  List<Map<String, dynamic>> _records = const [];
  List<_CableLineRoute> _routes = const [];
  List<_CableAnchorOption> _anchorOptions = const [];
  List<LatLng> _draftPoints = const [];
  int? _selectedRouteId;
  int? _editingRouteId;
  ProjectSelection? _activeProject;
  String? _draftStartAnchorKey;
  String? _draftEndAnchorKey;

  String get _actorEmail => widget.controller.currentUser?.email?.trim() ?? '';

  String get _actorUserId => widget.controller.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _syncRepository = CompanyModuleSyncRepository(
      client: widget.controller.client,
    );
    _loadRoutes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _recordTaskAddition({
    required String kind,
    required String summary,
    int? targetRecordId,
  }) async {
    final companyId = widget.controller.membership?.companyId;
    if (companyId == null || _activeProject == null) {
      return;
    }
    await _syncRepository.appendTaskWorkLog(
      companyId: companyId,
      activeProject: _activeProject!,
      actorUserId: _actorUserId,
      actorEmail: _actorEmail,
      kind: kind,
      summary: summary,
      targetScreen: 'infrastructure_map',
      targetRecordId: targetRecordId,
    );
  }

  Future<void> _loadRoutes() async {
    final companyId = widget.controller.membership?.companyId;
    if (companyId == null) {
      setState(() {
        _loading = false;
        _errorMessage = 'Компания не найдена для текущего пользователя.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      _activeProject = await _syncRepository.readActiveProject();
      var records = await _syncRepository.readCache(_cacheKey);
      var muffs = await _syncRepository.readCache(_muffsCacheKey);
      var cabinets = await _syncRepository.readCache(_cabinetsCacheKey);

      try {
        records = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: _moduleKey,
          localRecords: records,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Не удалось обновить кабельные линии из Supabase.',
          source: 'cable_lines.pull_merge',
          error: error,
          stackTrace: stackTrace,
        );
      }

      try {
        muffs = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: 'muff_notebook',
          localRecords: muffs,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Не удалось обновить муфты для привязки маршрутов.',
          source: 'cable_lines.muffs',
          error: error,
          stackTrace: stackTrace,
        );
      }

      try {
        cabinets = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: 'network_cabinet',
          localRecords: cabinets,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Не удалось обновить шкафы для привязки маршрутов.',
          source: 'cable_lines.cabinets',
          error: error,
          stackTrace: stackTrace,
        );
      }

      await _syncRepository.writeCache(_cacheKey, records);

      if (!mounted) {
        return;
      }

      _applyRecords(records, preserveSelection: false);
      setState(() {
        _anchorOptions = _buildAnchorOptions(muffs: muffs, cabinets: cabinets);
        _loading = false;
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось загрузить кабельные линии.',
        source: 'cable_lines.load',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Не удалось открыть раздел кабельных линий.';
      });
    }
  }

  void _applyRecords(
    List<Map<String, dynamic>> records, {
    required bool preserveSelection,
  }) {
    final nextRecords = records
        .map((record) => _syncRepository.clone(record))
        .toList(growable: true);

    final nextRoutes =
        nextRecords
            .where((record) => record['deleted'] != true)
            .map(_routeFromRecord)
            .whereType<_CableLineRoute>()
            .toList(growable: false)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    final previousSelected = preserveSelection ? _selectedRouteId : null;
    final previousEditing = preserveSelection ? _editingRouteId : null;

    final initialSelected =
        !preserveSelection &&
            widget.initialRouteId != null &&
            nextRoutes.any((route) => route.id == widget.initialRouteId)
        ? widget.initialRouteId
        : null;
    final nextSelected =
        initialSelected ??
        (nextRoutes.any((route) => route.id == previousSelected)
            ? previousSelected
            : (nextRoutes.isEmpty ? null : nextRoutes.first.id));

    final nextEditing = nextRoutes.any((route) => route.id == previousEditing)
        ? previousEditing
        : null;

    _records = nextRecords;
    _routes = nextRoutes;
    _selectedRouteId = nextSelected;
    if (!_editing || nextEditing != null) {
      _editingRouteId = nextEditing;
    }
  }

  _CableLineRoute? _routeFromRecord(Map<String, dynamic> record) {
    final points = _extractRoutePoints(record);
    if (points.length < 2) {
      return null;
    }

    final name = (record['name'] as String?)?.trim();
    final note = (record['note'] as String?)?.trim();
    final startAnchor = _extractAnchor(record['start_anchor']);
    final endAnchor = _extractAnchor(record['end_anchor']);

    return _CableLineRoute(
      id: (record['id'] as int?) ?? 0,
      name: name?.isNotEmpty == true ? name! : 'Кабельная линия',
      points: points,
      meta: {
        'Точек маршрута': '${points.length}',
        if (startAnchor != null) 'Начало': startAnchor['name'] ?? 'Привязано',
        if (endAnchor != null) 'Конец': endAnchor['name'] ?? 'Привязано',
        if (note != null && note.isNotEmpty) 'Примечание': note,
      },
      raw: _syncRepository.clone(record),
    );
  }

  List<LatLng> _extractRoutePoints(Map<String, dynamic> record) {
    final rawPoints =
        record['route_points'] ??
        record['points'] ??
        record['coordinates'] ??
        record['route'] ??
        record['path'];

    if (rawPoints is! List) {
      return const [];
    }

    final points = <LatLng>[];
    for (final item in rawPoints) {
      if (item is! Map) {
        continue;
      }

      final rawLat = item['lat'] ?? item['latitude'];
      final rawLng = item['lng'] ?? item['lon'] ?? item['longitude'];
      final lat = _asDouble(rawLat);
      final lng = _asDouble(rawLng);
      if (lat == null || lng == null) {
        continue;
      }

      points.add(LatLng(lat, lng));
    }

    return points;
  }

  double? _asDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  Map<String, dynamic>? _extractAnchor(dynamic value) {
    if (value is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(value);
  }

  List<_CableAnchorOption> _buildAnchorOptions({
    required List<Map<String, dynamic>> muffs,
    required List<Map<String, dynamic>> cabinets,
  }) {
    final options = <_CableAnchorOption>[
      ...muffs
          .where((record) => record['deleted'] != true)
          .where(
            (record) =>
                record['location_lat'] is double &&
                record['location_lng'] is double,
          )
          .map((record) {
            final isPonBox = record['is_pon_box'] == true;
            final type = isPonBox
                ? _CableAnchorType.ponBox
                : _CableAnchorType.muff;
            final id = (record['id'] as int?) ?? 0;
            return _CableAnchorOption(
              key: _anchorKey(type, id),
              type: type,
              entityId: id,
              name: (record['name'] as String?)?.trim().isNotEmpty == true
                  ? (record['name'] as String).trim()
                  : 'Без названия',
              subtitle: isPonBox ? 'PON бокс' : 'Муфта',
              location: (record['location'] as String?)?.trim() ?? '',
              point: LatLng(
                record['location_lat'] as double,
                record['location_lng'] as double,
              ),
            );
          }),
      ...cabinets
          .where((record) => record['deleted'] != true)
          .where(
            (record) =>
                record['location_lat'] is double &&
                record['location_lng'] is double,
          )
          .map((record) {
            final id = (record['id'] as int?) ?? 0;
            return _CableAnchorOption(
              key: _anchorKey(_CableAnchorType.cabinet, id),
              type: _CableAnchorType.cabinet,
              entityId: id,
              name: (record['name'] as String?)?.trim().isNotEmpty == true
                  ? (record['name'] as String).trim()
                  : 'Без названия',
              subtitle: 'Сетевой шкаф',
              location: (record['location'] as String?)?.trim() ?? '',
              point: LatLng(
                record['location_lat'] as double,
                record['location_lng'] as double,
              ),
            );
          }),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return options;
  }

  String _anchorKey(_CableAnchorType type, int entityId) {
    final typeCode = switch (type) {
      _CableAnchorType.muff => 'muff',
      _CableAnchorType.ponBox => 'pon_box',
      _CableAnchorType.cabinet => 'cabinet',
    };
    return '$typeCode:$entityId';
  }

  _CableAnchorType? _anchorTypeFromCode(String? value) {
    switch (value) {
      case 'muff':
        return _CableAnchorType.muff;
      case 'pon_box':
        return _CableAnchorType.ponBox;
      case 'cabinet':
        return _CableAnchorType.cabinet;
      default:
        return null;
    }
  }

  _CableAnchorOption? _anchorByKey(String? key) {
    if (key == null) {
      return null;
    }
    for (final option in _anchorOptions) {
      if (option.key == key) {
        return option;
      }
    }
    return null;
  }

  String? _anchorKeyFromStored(dynamic value) {
    final anchor = _extractAnchor(value);
    if (anchor == null) {
      return null;
    }
    final type = _anchorTypeFromCode(anchor['type']?.toString());
    final entityId = anchor['entity_id'];
    if (type == null || entityId is! num) {
      return null;
    }
    final key = _anchorKey(type, entityId.toInt());
    return _anchorByKey(key) == null ? null : key;
  }

  Map<String, dynamic>? _serializeAnchor(String? key) {
    final option = _anchorByKey(key);
    if (option == null) {
      return null;
    }
    final typeCode = switch (option.type) {
      _CableAnchorType.muff => 'muff',
      _CableAnchorType.ponBox => 'pon_box',
      _CableAnchorType.cabinet => 'cabinet',
    };
    return <String, dynamic>{
      'type': typeCode,
      'entity_id': option.entityId,
      'name': option.name,
      'subtitle': option.subtitle,
      'location': option.location,
      'lat': option.point.latitude,
      'lng': option.point.longitude,
    };
  }

  List<LatLng> _pointsWithAnchors() {
    final points = List<LatLng>.from(_draftPoints);
    final startAnchor = _anchorByKey(_draftStartAnchorKey);
    final endAnchor = _anchorByKey(_draftEndAnchorKey);

    if (startAnchor != null) {
      if (points.isEmpty) {
        points.add(startAnchor.point);
      } else {
        points[0] = startAnchor.point;
      }
    }

    if (endAnchor != null) {
      if (points.isEmpty) {
        points.add(endAnchor.point);
      } else if (points.length == 1) {
        points.add(endAnchor.point);
      } else {
        points[points.length - 1] = endAnchor.point;
      }
    }

    return points;
  }

  _CableLineRoute? get _selectedRoute {
    if (_selectedRouteId == null) {
      return null;
    }

    for (final route in _routes) {
      if (route.id == _selectedRouteId) {
        return route;
      }
    }

    return null;
  }

  void _selectRoute(_CableLineRoute route) {
    setState(() {
      _selectedRouteId = route.id;
      if (!_editing) {
        _editingRouteId = null;
      }
    });
    _mapController.move(route.points.first, _mapZoom < 15 ? 15 : _mapZoom);
  }

  void _startCreateRoute() {
    setState(() {
      _editing = true;
      _editingRouteId = null;
      _selectedRouteId = null;
      _draftPoints = <LatLng>[];
      _draftStartAnchorKey = null;
      _draftEndAnchorKey = null;
      _nameController.text = '';
      _noteController.text = '';
    });
  }

  void _startEditRoute(_CableLineRoute route) {
    setState(() {
      _editing = true;
      _editingRouteId = route.id;
      _selectedRouteId = route.id;
      _draftPoints = List<LatLng>.from(route.points);
      _draftStartAnchorKey = _anchorKeyFromStored(route.raw['start_anchor']);
      _draftEndAnchorKey = _anchorKeyFromStored(route.raw['end_anchor']);
      _nameController.text = route.raw['name']?.toString() ?? route.name;
      _noteController.text = route.raw['note']?.toString() ?? '';
      _draftPoints = _pointsWithAnchors();
    });
    if (_draftPoints.isNotEmpty) {
      _mapController.move(_draftPoints.first, _mapZoom < 15 ? 15 : _mapZoom);
    }
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
      _editingRouteId = null;
      _draftPoints = const [];
      _draftStartAnchorKey = null;
      _draftEndAnchorKey = null;
      _nameController.clear();
      _noteController.clear();
      if (_routes.isNotEmpty && _selectedRouteId == null) {
        _selectedRouteId = _routes.first.id;
      }
    });
  }

  void _addDraftPoint(LatLng point) {
    if (!_editing) {
      return;
    }

    setState(() {
      _draftPoints = [..._draftPoints, point];
      _draftPoints = _pointsWithAnchors();
    });
  }

  void _undoDraftPoint() {
    if (!_editing || _draftPoints.isEmpty) {
      return;
    }

    setState(() {
      _draftPoints = _draftPoints.sublist(0, _draftPoints.length - 1);
      _draftPoints = _pointsWithAnchors();
    });
  }

  void _clearDraftPoints() {
    if (!_editing) {
      return;
    }

    setState(() {
      _draftPoints = const [];
      _draftPoints = _pointsWithAnchors();
    });
  }

  void _setDraftStartAnchor(String? key) {
    setState(() {
      _draftStartAnchorKey = key;
      _draftPoints = _pointsWithAnchors();
    });
  }

  void _setDraftEndAnchor(String? key) {
    setState(() {
      _draftEndAnchorKey = key;
      _draftPoints = _pointsWithAnchors();
    });
  }

  int _nextRecordId() {
    var maxId = 0;
    for (final record in _records) {
      final id = record['id'];
      if (id is int && id > maxId) {
        maxId = id;
      } else if (id is num && id.toInt() > maxId) {
        maxId = id.toInt();
      }
    }
    return maxId + 1;
  }

  Future<void> _saveDraft() async {
    final companyId = widget.controller.membership?.companyId;
    if (companyId == null) {
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('Укажите название линии.');
      return;
    }
    if (_draftStartAnchorKey != null &&
        _draftStartAnchorKey == _draftEndAnchorKey) {
      _showSnackBar('Начало и конец маршрута должны быть разными точками.');
      return;
    }

    final routePoints = _pointsWithAnchors();
    if (routePoints.length < 2) {
      _showSnackBar('Для маршрута нужно минимум две точки.');
      return;
    }

    final now = DateTime.now();
    final recordId = _editingRouteId ?? _nextRecordId();
    final routeRecord = <String, dynamic>{
      'id': recordId,
      'name': name,
      'note': _noteController.text.trim(),
      'start_anchor': _serializeAnchor(_draftStartAnchorKey),
      'end_anchor': _serializeAnchor(_draftEndAnchorKey),
      'route_points': routePoints
          .map(
            (point) => <String, double>{
              'lat': point.latitude,
              'lng': point.longitude,
            },
          )
          .toList(growable: false),
      'updated_at': now,
      'dirty': true,
      'deleted': false,
    };
    if (_editingRouteId == null) {
      applyProjectSelection(routeRecord, _activeProject);
    } else {
      final current = _selectedRoute?.raw;
      if (current != null) {
        routeRecord['project_id'] = current['project_id'];
        routeRecord['project_name'] = current['project_name'];
      }
    }

    final nextRecords =
        _records
            .where((record) => record['id'] != recordId)
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true)
          ..add(routeRecord);

    await _persistRecords(nextRecords, selectId: recordId, keepEditing: false);
    if (_editingRouteId == null) {
      await _recordTaskAddition(
        kind: 'Добавлен маршрут',
        summary: [
          routeRecord['name']?.toString() ?? 'Маршрут',
          if ((_anchorByKey(_draftStartAnchorKey)?.location ?? '')
              .trim()
              .isNotEmpty)
            'старт: ${_anchorByKey(_draftStartAnchorKey)!.location}',
          if ((_anchorByKey(_draftEndAnchorKey)?.location ?? '')
              .trim()
              .isNotEmpty)
            'финиш: ${_anchorByKey(_draftEndAnchorKey)!.location}',
          if (_noteController.text.trim().isNotEmpty)
            'примечание: ${_noteController.text.trim()}',
        ].join(' • '),
        targetRecordId: recordId,
      );
    }
  }

  Future<void> _deleteRoute(_CableLineRoute route) async {
    final companyId = widget.controller.membership?.companyId;
    if (companyId == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить маршрут'),
        content: Text('Маршрут "${route.name}" будет удалён из списка и sync.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final now = DateTime.now();
    final nextRecords =
        _records
            .where((record) => record['id'] != route.id)
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true)
          ..add({
            'id': route.id,
            'updated_at': now,
            'dirty': true,
            'deleted': true,
          });

    await _persistRecords(nextRecords, selectId: null, keepEditing: false);
  }

  Future<void> _syncNow() async {
    await _persistRecords(
      _records.map((record) => _syncRepository.clone(record)).toList(),
      selectId: _selectedRouteId,
      keepEditing: _editing,
      forceSync: true,
    );
  }

  Future<void> _persistRecords(
    List<Map<String, dynamic>> records, {
    required int? selectId,
    required bool keepEditing,
    bool forceSync = false,
  }) async {
    final companyId = widget.controller.membership?.companyId;
    if (companyId == null) {
      return;
    }

    setState(() {
      _syncing = true;
      _errorMessage = null;
    });

    try {
      var nextRecords = records;
      await _syncRepository.writeCache(_cacheKey, nextRecords);

      final shouldSync =
          forceSync || nextRecords.any((record) => record['dirty'] == true);
      if (shouldSync) {
        nextRecords = await _syncRepository.syncAll(
          companyId: companyId,
          moduleKey: _moduleKey,
          cacheKey: _cacheKey,
          localRecords: nextRecords,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _applyRecords(nextRecords, preserveSelection: true);
        _selectedRouteId = selectId ?? _selectedRouteId;
        _syncing = false;
        if (!keepEditing) {
          _editing = false;
          _editingRouteId = null;
          _draftPoints = const [];
          _draftStartAnchorKey = null;
          _draftEndAnchorKey = null;
          _nameController.clear();
          _noteController.clear();
        }
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось сохранить кабельный маршрут.',
        source: 'cable_lines.persist',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
      });
      _showSnackBar('Не удалось сохранить маршрут.');
    }
  }

  Color _routeColor(_CableLineRoute route) {
    if (route.id == _selectedRouteId) {
      return const Color(0xFF1EDDC5);
    }

    return const Color(0xFF60A5FA);
  }

  Color get _draftColor => const Color(0xFFFFA629);

  Widget _buildLegendCard() {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _editing ? 'Построение маршрута' : 'Кабельные линии',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _LegendLineRow(
                    color: Color(0xFF1EDDC5),
                    label: 'Выбранная линия',
                  ),
                  const SizedBox(height: 8),
                  const _LegendLineRow(
                    color: Color(0xFF60A5FA),
                    label: 'Остальные маршруты',
                  ),
                  if (_editing) ...[
                    const SizedBox(height: 8),
                    const _LegendLineRow(
                      color: Color(0xFFFFA629),
                      label: 'Черновик маршрута',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Начало и конец можно привязать к муфтам или шкафам. Тап по карте добавляет промежуточные точки.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Всего линий: ${_routes.length}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final routeForCenter = _editing && _draftPoints.isNotEmpty
        ? _draftPoints.first
        : _selectedRoute?.points.first;
    final initialPoint =
        routeForCenter ??
        (_routes.isNotEmpty ? _routes.first.points.first : _fallbackCenter);

    final routeMarkers = _routes.expand((route) {
      final color = _routeColor(route);
      final first = route.points.first;
      final last = route.points.last;
      return [
        Marker(
          point: first,
          width: 20,
          height: 20,
          child: _RouteEndpointMarker(color: color, filled: true),
        ),
        Marker(
          point: last,
          width: 20,
          height: 20,
          child: _RouteEndpointMarker(color: color, filled: false),
        ),
      ];
    });

    final draftMarkers = _editing
        ? _pointsWithAnchors().map(
            (point) => Marker(
              point: point,
              width: 16,
              height: 16,
              child: _RouteEndpointMarker(color: _draftColor, filled: true),
            ),
          )
        : const Iterable<Marker>.empty();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            crs: mapCrsById(_selectedTileLayerId),
            initialCenter: initialPoint,
            initialZoom: _mapZoom,
            maxZoom: 19,
            onTap: (_, point) => _addDraftPoint(point),
            onPositionChanged: (position, _) {
              _mapZoom = position.zoom;
            },
          ),
          children: [
            tileLayerById(_selectedTileLayerId),
            PolylineLayer(
              polylines: [
                ..._routes.map(
                  (route) => Polyline(
                    points: route.points,
                    strokeWidth: route.id == _selectedRouteId ? 5 : 3,
                    color: _routeColor(route).withValues(
                      alpha: route.id == _selectedRouteId ? 0.95 : 0.72,
                    ),
                  ),
                ),
                if (_editing && _pointsWithAnchors().length >= 2)
                  Polyline(
                    points: _pointsWithAnchors(),
                    strokeWidth: 4,
                    color: _draftColor,
                    pattern: StrokePattern.dashed(segments: [10, 8]),
                  ),
              ],
            ),
            MarkerLayer(markers: [...routeMarkers, ...draftMarkers]),
          ],
        ),
        _buildLegendCard(),
      ],
    );
  }

  Widget _buildRouteList() {
    final selectedRoute = _selectedRoute;

    if (_routes.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFF071526),
          border: Border(top: BorderSide(color: Color(0xFF1D3F63))),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _editing
                  ? 'Добавьте точки на карте и сохраните первый маршрут.'
                  : 'Маршрутов пока нет. Нажмите "Новый маршрут", чтобы начать.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF071526),
        border: Border(top: BorderSide(color: Color(0xFF1D3F63))),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        scrollDirection: Axis.horizontal,
        itemCount: _routes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final route = _routes[index];
          final isSelected = route.id == selectedRoute?.id;
          final color = _routeColor(route);

          return SizedBox(
            width: 300,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _selectRoute(route),
              child: Ink(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isSelected ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: color.withValues(alpha: isSelected ? 0.55 : 0.24),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timeline_rounded, color: color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              route.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Действия',
                            onSelected: (value) {
                              if (value == 'edit') {
                                _startEditRoute(route);
                              } else if (value == 'delete') {
                                _deleteRoute(route);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Редактировать'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Удалить'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final entry in route.meta.entries.take(3)) ...[
                        _CableLineMetaRow(label: entry.key, value: entry.value),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditorPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height * 0.7;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF071526).withValues(alpha: 0.94),
            border: const Border(
              left: BorderSide(color: Color(0xFF1D3F63)),
              top: BorderSide(color: Color(0xFF1D3F63)),
            ),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(24)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _editingRouteId == null
                              ? 'Новый маршрут'
                              : 'Редактирование маршрута',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть редактор',
                        onPressed: _syncing ? null : _cancelEditing,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название линии',
                      hintText: 'Например: Магистраль Север-12',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _draftStartAnchorKey,
                    decoration: const InputDecoration(
                      labelText: 'Начало маршрута',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Без привязки'),
                      ),
                      ..._anchorOptions.map(
                        (option) => DropdownMenuItem<String?>(
                          value: option.key,
                          child: Text('${option.name} · ${option.subtitle}'),
                        ),
                      ),
                    ],
                    onChanged: _syncing ? null : _setDraftStartAnchor,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _draftEndAnchorKey,
                    decoration: const InputDecoration(
                      labelText: 'Конец маршрута',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Без привязки'),
                      ),
                      ..._anchorOptions.map(
                        (option) => DropdownMenuItem<String?>(
                          value: option.key,
                          child: Text('${option.name} · ${option.subtitle}'),
                        ),
                      ),
                    ],
                    onChanged: _syncing ? null : _setDraftEndAnchor,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Примечание'),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _EditorStatChip(
                        icon: Icons.alt_route_rounded,
                        label: 'Точек: ${_pointsWithAnchors().length}',
                      ),
                      const _EditorStatChip(
                        icon: Icons.touch_app_outlined,
                        label: 'Тап по карте добавляет промежуточную точку',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _syncing || _draftPoints.isEmpty
                            ? null
                            : _undoDraftPoint,
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('Отменить точку'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _syncing ? null : _clearDraftPoints,
                        icon: const Icon(Icons.clear_all_rounded),
                        label: const Text('Очистить маршрут'),
                      ),
                      FilledButton.icon(
                        onPressed: _syncing ? null : _saveDraft,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(
                          _editingRouteId == null ? 'Создать' : 'Сохранить',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_errorMessage!),
        ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: _buildMap()),
            SizedBox(height: 180, child: _buildRouteList()),
          ],
        ),
        if (_editing)
          Align(
            alignment: Alignment.bottomRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: MediaQuery.sizeOf(context).height - 220,
              ),
              child: Padding(
                padding: const EdgeInsets.only(
                  right: 16,
                  left: 16,
                  top: 16,
                  bottom: 196,
                ),
                child: _buildEditorPanel(),
              ),
            ),
          ),
      ],
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кабельные линии'),
        actions: [
          IconButton(
            tooltip: 'Новый маршрут',
            onPressed: _syncing ? null : _startCreateRoute,
            icon: const Icon(Icons.add_road_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Слой карты',
            initialValue: _selectedTileLayerId,
            onSelected: (value) {
              setState(() {
                _selectedTileLayerId = value;
              });
            },
            icon: const Icon(Icons.layers_outlined),
            itemBuilder: (context) => mapTileOptions
                .map(
                  (option) => CheckedPopupMenuItem<String>(
                    value: option.id,
                    checked: option.id == _selectedTileLayerId,
                    child: Text(option.label),
                  ),
                )
                .toList(growable: false),
          ),
          IconButton(
            tooltip: 'Синхронизировать',
            onPressed: _loading || _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading || _syncing ? null : _loadRoutes,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class _LegendLineRow extends StatelessWidget {
  const _LegendLineRow({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }
}

class _RouteEndpointMarker extends StatelessWidget {
  const _RouteEndpointMarker({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: filled ? color : const Color(0xFF071526),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}

class _CableLineMetaRow extends StatelessWidget {
  const _CableLineMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}

class _EditorStatChip extends StatelessWidget {
  const _EditorStatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2743),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF1D3F63)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF1EDDC5)),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
