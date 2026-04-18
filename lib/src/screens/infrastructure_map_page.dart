import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/map_tile_providers.dart';
import '../core/project_scope.dart';

class InfrastructureSignalTraceRequest {
  const InfrastructureSignalTraceRequest({
    required this.cabinetId,
    required this.switchId,
    required this.portIndex,
  });

  final int cabinetId;
  final int switchId;
  final int portIndex;
}

class InfrastructureMapPage extends StatefulWidget {
  const InfrastructureMapPage({
    super.key,
    required this.controller,
    this.initialTraceRequest,
    this.initialRouteId,
  });

  final AuthController controller;
  final InfrastructureSignalTraceRequest? initialTraceRequest;
  final int? initialRouteId;

  @override
  State<InfrastructureMapPage> createState() => _InfrastructureMapPageState();
}

enum _InfrastructureEntityType { muff, ponBox, cabinet }

class _InfrastructureEntity {
  const _InfrastructureEntity({
    required this.type,
    required this.id,
    required this.key,
    required this.name,
    required this.location,
    required this.point,
    required this.subtitle,
    required this.meta,
  });

  final _InfrastructureEntityType type;
  final int id;
  final String key;
  final String name;
  final String location;
  final LatLng point;
  final String subtitle;
  final Map<String, String> meta;
}

class _CableRoute {
  const _CableRoute({
    required this.id,
    required this.name,
    required this.points,
    double? lengthMeters,
    required this.meta,
    required this.raw,
  }) : _lengthMeters = lengthMeters;

  final int id;
  final String name;
  final List<LatLng> points;
  final double? _lengthMeters;
  double get lengthMeters {
    final length = _lengthMeters;
    if (length != null) {
      return length;
    }
    if (points.length < 2) {
      return 0;
    }

    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      total += _InfrastructureMapPageState._geoDistance(
        points[i],
        points[i + 1],
      );
    }
    return total;
  }
  final Map<String, String> meta;
  final Map<String, dynamic> raw;
}

class _RouteCableChoice {
  const _RouteCableChoice({
    required this.entity,
    required this.cableId,
    required this.cableName,
    required this.fibers,
  });

  final _InfrastructureEntity entity;
  final int cableId;
  final String cableName;
  final int fibers;
}

enum _TraceEndpointKind { cabinetPort, cableFiber, splitterPort }

class _TraceEndpoint {
  const _TraceEndpoint.cabinetPort({
    required this.entityTypeCode,
    required this.entityId,
    required this.switchId,
    required this.portIndex,
  }) : kind = _TraceEndpointKind.cabinetPort,
       cableId = null,
       fiberIndex = null,
       splitterId = null,
       splitterPortType = null,
       splitterPortIndex = null;

  const _TraceEndpoint.cableFiber({
    required this.entityTypeCode,
    required this.entityId,
    required this.cableId,
    required this.fiberIndex,
  }) : kind = _TraceEndpointKind.cableFiber,
       switchId = null,
       portIndex = null,
       splitterId = null,
       splitterPortType = null,
       splitterPortIndex = null;

  const _TraceEndpoint.splitterPort({
    required this.entityTypeCode,
    required this.entityId,
    required this.splitterId,
    required this.splitterPortType,
    required this.splitterPortIndex,
  }) : kind = _TraceEndpointKind.splitterPort,
       switchId = null,
       portIndex = null,
       cableId = null,
       fiberIndex = null;

  final _TraceEndpointKind kind;
  final String entityTypeCode;
  final int entityId;
  final int? switchId;
  final int? portIndex;
  final int? cableId;
  final int? fiberIndex;
  final int? splitterId;
  final String? splitterPortType;
  final int? splitterPortIndex;

  String get visitKey {
    return switch (kind) {
      _TraceEndpointKind.cabinetPort =>
        '$entityTypeCode:$entityId:port:$switchId:$portIndex',
      _TraceEndpointKind.cableFiber =>
        '$entityTypeCode:$entityId:fiber:$cableId:$fiberIndex',
      _TraceEndpointKind.splitterPort =>
        '$entityTypeCode:$entityId:splitter:$splitterId:$splitterPortType:$splitterPortIndex',
    };
  }
}

class _TraceTransition {
  const _TraceTransition(this.endpoint, {this.routeId});

  final _TraceEndpoint endpoint;
  final int? routeId;
}

class _TraceStep {
  const _TraceStep({
    required this.endpoint,
    this.color,
  });

  final _TraceEndpoint endpoint;
  final Color? color;
}

class _TraceResult {
  const _TraceResult({
    required this.entityKeys,
    required this.routeIds,
    required this.routeColors,
    required this.visitedEndpoints,
  });

  final Set<String> entityKeys;
  final Set<int> routeIds;
  final Map<int, Color> routeColors;
  final Set<String> visitedEndpoints;
}

class _InfrastructureMapPageState extends State<InfrastructureMapPage> {
  static const _muffsCacheKey = 'muff_notebook.muffs.v3';
  static const _cabinetsCacheKey = 'network_cabinet.cabinets.v1';
  static const _routesCacheKey = 'cable_lines.routes.v1';
  static const _muffsModuleKey = 'muff_notebook';
  static const _cabinetsModuleKey = 'network_cabinet';
  static const _routesModuleKey = 'cable_lines';
  static const Distance _geoDistance = Distance();
  static const Map<String, List<Color>> _fiberSchemes = {
    'default': [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.brown,
      Colors.grey,
      Colors.white,
      Colors.red,
      Colors.black,
      Colors.yellow,
      Colors.purple,
      Colors.pink,
      Colors.cyan,
    ],
    'odessa': [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.yellow,
      Colors.white,
      Colors.grey,
      Colors.brown,
      Colors.purple,
      Colors.orange,
      Colors.black,
      Colors.pink,
      Colors.cyan,
    ],
  };
  final MapController _mapController = MapController();
  late final CompanyModuleSyncRepository _syncRepository;

  bool _loading = true;
  bool _syncingRoutes = false;
  bool _routeEditMode = false;
  bool _routeCreateMode = false;
  String? _errorMessage;
  double _mapZoom = 13;
  String _selectedTileLayerId = 'osm';
  List<Map<String, dynamic>> _muffRecords = const [];
  List<Map<String, dynamic>> _cabinetRecords = const [];
  List<_InfrastructureEntity> _entities = const [];
  List<Map<String, dynamic>> _routeRecords = const [];
  List<_CableRoute> _routes = const [];
  int? _projectFilterId;
  ProjectSelection? _activeProject;
  int? _selectedRouteId;
  String? _pendingStartEntityKey;
  int? _pendingStartCableId;
  int? _pendingRequiredFibers;
  InfrastructureSignalTraceRequest? _activeTraceRequest;
  Set<String> _highlightedEntityKeys = const {};
  Set<int> _highlightedRouteIds = const {};
  Map<int, Color> _highlightedRouteColors = const {};
  String? _traceSummary;

  @override
  void initState() {
    super.initState();
    _selectedRouteId = widget.initialRouteId;
    _activeTraceRequest = widget.initialTraceRequest;
    _syncRepository = CompanyModuleSyncRepository(
      client: widget.controller.client,
    );
    _loadMapData();
  }

  String get _actorEmail => widget.controller.currentUser?.email?.trim() ?? '';

  String get _actorUserId => widget.controller.currentUser?.id ?? '';

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

  Future<void> _loadMapData() async {
    final companyId = widget.controller.membership?.companyId;
    _activeProject = await _syncRepository.readActiveProject();
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
      var muffs = await _syncRepository.readCache(_muffsCacheKey);
      var cabinets = await _syncRepository.readCache(_cabinetsCacheKey);
      var routes = await _syncRepository.readCache(_routesCacheKey);

      try {
        muffs = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: 'muff_notebook',
          localRecords: muffs,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Не удалось обновить муфты для карты.',
          source: 'infrastructure_map.muffs',
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
          'Не удалось обновить шкафы для карты.',
          source: 'infrastructure_map.cabinets',
          error: error,
          stackTrace: stackTrace,
        );
      }

      try {
        routes = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: _routesModuleKey,
          localRecords: routes,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Не удалось обновить кабельные маршруты для карты.',
          source: 'infrastructure_map.routes',
          error: error,
          stackTrace: stackTrace,
        );
      }

      await _syncRepository.writeCache(_routesCacheKey, routes);

      final nextEntities = <_InfrastructureEntity>[
        ..._muffEntities(muffs),
        ..._cabinetEntities(cabinets),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final nextRouteRecords = routes
          .map((record) => _syncRepository.clone(record))
          .toList(growable: true);
      final nextRoutes =
          nextRouteRecords
              .where((record) => record['deleted'] != true)
              .map(_routeFromRecord)
              .whereType<_CableRoute>()
              .toList(growable: false)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _muffRecords = muffs
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true);
        _cabinetRecords = cabinets
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true);
        _entities = nextEntities;
        _routeRecords = nextRouteRecords;
        _routes = nextRoutes;
        if (!_routes.any((route) => route.id == _selectedRouteId)) {
          _selectedRouteId = _routes.isEmpty ? null : _routes.first.id;
        }
        _loading = false;
      });
      _refreshTraceHighlight();
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось загрузить сущности инфраструктуры.',
        source: 'infrastructure_map.load',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Не удалось загрузить карту инфраструктуры.';
      });
    }
  }

  List<_InfrastructureEntity> _muffEntities(
    List<Map<String, dynamic>> records,
  ) {
    return records
        .where((record) => record['deleted'] != true)
        .where(
          (record) =>
              record['location_lat'] is double &&
              record['location_lng'] is double,
        )
        .map((record) {
          final cables = List<Map<String, dynamic>>.from(
            record['cables'] ?? const [],
          );
          final connections = List<Map<String, dynamic>>.from(
            record['connections'] ?? const [],
          );
          final isPonBox = record['is_pon_box'] == true;
          final district = (record['district'] as String?)?.trim() ?? '';
          final type = isPonBox
              ? _InfrastructureEntityType.ponBox
              : _InfrastructureEntityType.muff;
          final id = (record['id'] as int?) ?? 0;

          return _InfrastructureEntity(
            type: type,
            id: id,
            key: _entityKey(type, id),
            name: (record['name'] as String?)?.trim().isNotEmpty == true
                ? (record['name'] as String).trim()
                : 'Без названия',
            location: (record['location'] as String?)?.trim() ?? '',
            point: LatLng(
              record['location_lat'] as double,
              record['location_lng'] as double,
            ),
            subtitle: isPonBox ? 'PON бокс' : 'Муфта',
            meta: {
              if (projectNameOf(record) != null)
                'Задача': projectNameOf(record)!,
              if (district.isNotEmpty) 'Район': district,
              'Кабели': '${cables.length}',
              'Соединения': '${connections.length}',
            },
          );
        })
        .toList(growable: false);
  }

  List<_InfrastructureEntity> _cabinetEntities(
    List<Map<String, dynamic>> records,
  ) {
    return records
        .where((record) => record['deleted'] != true)
        .where(
          (record) =>
              record['location_lat'] is double &&
              record['location_lng'] is double,
        )
        .map((record) {
          final switches = List<Map<String, dynamic>>.from(
            record['switches'] ?? const [],
          );
          final cables = List<Map<String, dynamic>>.from(
            record['cables'] ?? const [],
          );
          final id = (record['id'] as int?) ?? 0;

          return _InfrastructureEntity(
            type: _InfrastructureEntityType.cabinet,
            id: id,
            key: _entityKey(_InfrastructureEntityType.cabinet, id),
            name: (record['name'] as String?)?.trim().isNotEmpty == true
                ? (record['name'] as String).trim()
                : 'Без названия',
            location: (record['location'] as String?)?.trim() ?? '',
            point: LatLng(
              record['location_lat'] as double,
              record['location_lng'] as double,
            ),
            subtitle: 'Сетевой шкаф',
            meta: {
              if (projectNameOf(record) != null)
                'Задача': projectNameOf(record)!,
              'Коммутаторы': '${switches.length}',
              'Кабели': '${cables.length}',
            },
          );
        })
        .toList(growable: false);
  }

  _CableRoute? _routeFromRecord(Map<String, dynamic> record) {
    final points = _extractRoutePoints(record);
    if (points.length < 2) {
      return null;
    }

    final name = (record['name'] as String?)?.trim();
    final note = (record['note'] as String?)?.trim();
    final startAnchor = _extractAnchor(record['start_anchor']);
    final endAnchor = _extractAnchor(record['end_anchor']);
    final lengthMeters = _routeLengthMeters(points);

    return _CableRoute(
      id: (record['id'] as int?) ?? 0,
      name: name?.isNotEmpty == true ? name! : 'Кабельная линия',
      points: points,
      lengthMeters: lengthMeters,
      meta: {
        if (projectNameOf(record) != null) 'Задача': projectNameOf(record)!,
        'Длина': _formatRouteLength(lengthMeters),
        'Точек': '${points.length}',
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
      final lat = _asDouble(item['lat'] ?? item['latitude']);
      final lng = _asDouble(item['lng'] ?? item['lon'] ?? item['longitude']);
      if (lat == null || lng == null) {
        continue;
      }
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  Map<String, dynamic>? _extractAnchor(dynamic value) {
    if (value is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(value);
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

  double _routeLengthMeters(List<LatLng> points) {
    if (points.length < 2) {
      return 0;
    }

    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      total += _geoDistance(points[i], points[i + 1]);
    }
    return total;
  }

  String _formatRouteLength(double lengthMeters) {
    if (lengthMeters >= 1000) {
      final kilometers = lengthMeters / 1000;
      return '${kilometers.toStringAsFixed(kilometers >= 10 ? 1 : 2)} км';
    }
    return '${lengthMeters.toStringAsFixed(lengthMeters >= 100 ? 0 : 1)} м';
  }

  String _entityKey(_InfrastructureEntityType type, int entityId) {
    final typeCode = switch (type) {
      _InfrastructureEntityType.muff => 'muff',
      _InfrastructureEntityType.ponBox => 'pon_box',
      _InfrastructureEntityType.cabinet => 'cabinet',
    };
    return '$typeCode:$entityId';
  }

  String _entityTypeCode(_InfrastructureEntityType type) {
    return switch (type) {
      _InfrastructureEntityType.muff => 'muff',
      _InfrastructureEntityType.ponBox => 'pon_box',
      _InfrastructureEntityType.cabinet => 'cabinet',
    };
  }

  _InfrastructureEntity? _entityByKey(String? key) {
    if (key == null) {
      return null;
    }
    for (final entity in _entities) {
      if (entity.key == key) {
        return entity;
      }
    }
    return null;
  }

  _CableRoute? get _selectedRoute {
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

  _InfrastructureEntity? _entityByTypeAndId(String typeCode, int entityId) {
    for (final entity in _entities) {
      if (_entityTypeCode(entity.type) == typeCode && entity.id == entityId) {
        return entity;
      }
    }
    return null;
  }

  void _clearTraceHighlight() {
    if (_highlightedEntityKeys.isEmpty &&
        _highlightedRouteIds.isEmpty &&
        _traceSummary == null &&
        _activeTraceRequest == null) {
      return;
    }
    setState(() {
      _activeTraceRequest = null;
      _highlightedEntityKeys = const {};
      _highlightedRouteIds = const {};
      _highlightedRouteColors = const {};
      _traceSummary = null;
    });
  }

  void _refreshTraceHighlight() {
    final request = _activeTraceRequest;
    if (request == null) {
      if (_highlightedEntityKeys.isEmpty &&
          _highlightedRouteIds.isEmpty &&
          _traceSummary == null) {
        return;
      }
      setState(() {
        _highlightedEntityKeys = const {};
        _highlightedRouteIds = const {};
        _highlightedRouteColors = const {};
        _traceSummary = null;
      });
      return;
    }

    final result = _buildTraceFromRequest(request);
    final cabinet = _entityByTypeAndId('cabinet', request.cabinetId);
    final portLabel = request.portIndex + 1;
    final summary = result == null
        ? 'Трассу от порта $portLabel построить не удалось.'
        : 'Трасса от ${cabinet?.name ?? 'шкафа'} порт $portLabel: объектов ${result.entityKeys.length}, маршрутов ${result.routeIds.length}.';

    if (!mounted) {
      return;
    }

    setState(() {
      _highlightedEntityKeys = result?.entityKeys ?? const {};
      _highlightedRouteIds = result?.routeIds ?? const {};
      _highlightedRouteColors = result?.routeColors ?? const {};
      _traceSummary = summary;
    });

    if (result != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _focusTrace(result);
      });
    }
  }

  _TraceResult? _buildTraceFromRequest(InfrastructureSignalTraceRequest request) {
    final cabinet = _entityByTypeAndId('cabinet', request.cabinetId);
    if (cabinet == null) {
      return null;
    }

    final start = _TraceEndpoint.cabinetPort(
      entityTypeCode: 'cabinet',
      entityId: request.cabinetId,
      switchId: request.switchId,
      portIndex: request.portIndex,
    );

    final queue = <_TraceStep>[_TraceStep(endpoint: start)];
    final visited = <String>{};
    final entityKeys = <String>{};
    final routeIds = <int>{};
    final routeColors = <int, Color>{};

    while (queue.isNotEmpty) {
      final step = queue.removeAt(0);
      final current = step.endpoint;
      if (!visited.add(current.visitKey)) {
        continue;
      }

      entityKeys.add('${current.entityTypeCode}:${current.entityId}');
      final currentColor = step.color ?? _traceColorForEndpoint(current);

      for (final transition in _traceNeighbors(current)) {
        if (transition.routeId != null) {
          routeIds.add(transition.routeId!);
          routeColors.putIfAbsent(transition.routeId!, () {
            return currentColor ?? const Color(0xFFFFB347);
          });
        }
        if (!visited.contains(transition.endpoint.visitKey)) {
          queue.add(
            _TraceStep(
              endpoint: transition.endpoint,
              color: currentColor,
            ),
          );
        }
      }
    }

    return _TraceResult(
      entityKeys: entityKeys,
      routeIds: routeIds,
      routeColors: routeColors,
      visitedEndpoints: visited,
    );
  }

  Iterable<_TraceTransition> _traceNeighbors(_TraceEndpoint endpoint) sync* {
    switch (endpoint.entityTypeCode) {
      case 'cabinet':
        yield* _traceCabinetNeighbors(endpoint);
      case 'muff':
      case 'pon_box':
        yield* _traceMuffNeighbors(endpoint);
    }

    if (endpoint.kind == _TraceEndpointKind.cableFiber) {
      final routeTransition = _traceRouteNeighbor(endpoint);
      if (routeTransition != null) {
        yield routeTransition;
      }
    }
  }

  Iterable<_TraceTransition> _traceCabinetNeighbors(
    _TraceEndpoint endpoint,
  ) sync* {
    final record = _recordByTypeAndId(endpoint.entityTypeCode, endpoint.entityId);
    if (record == null) {
      return;
    }

    final connections = List<Map<String, dynamic>>.from(
      record['connections'] ?? const [],
    );

    for (final connection in connections) {
      final left = _cabinetEndpointFromConnection(
        endpoint.entityTypeCode,
        endpoint.entityId,
        connection,
        true,
      );
      final right = _cabinetEndpointFromConnection(
        endpoint.entityTypeCode,
        endpoint.entityId,
        connection,
        false,
      );
      if (left != null && right != null && _traceEndpointEquals(left, endpoint)) {
        yield _TraceTransition(right);
      } else if (left != null &&
          right != null &&
          _traceEndpointEquals(right, endpoint)) {
        yield _TraceTransition(left);
      }
    }
  }

  Iterable<_TraceTransition> _traceMuffNeighbors(_TraceEndpoint endpoint) sync* {
    final record = _recordByTypeAndId(endpoint.entityTypeCode, endpoint.entityId);
    if (record == null) {
      return;
    }

    final connections = List<Map<String, dynamic>>.from(
      record['connections'] ?? const [],
    );
    for (final connection in connections) {
      if (connection['endpoint1'] is! Map || connection['endpoint2'] is! Map) {
        continue;
      }
      final left = _muffEndpointFromMap(
        endpoint.entityTypeCode,
        endpoint.entityId,
        Map<String, dynamic>.from(connection['endpoint1'] as Map),
      );
      final right = _muffEndpointFromMap(
        endpoint.entityTypeCode,
        endpoint.entityId,
        Map<String, dynamic>.from(connection['endpoint2'] as Map),
      );
      if (left != null && right != null && _traceEndpointEquals(left, endpoint)) {
        yield _TraceTransition(right);
      } else if (left != null &&
          right != null &&
          _traceEndpointEquals(right, endpoint)) {
        yield _TraceTransition(left);
      }
    }

    if (endpoint.kind == _TraceEndpointKind.splitterPort) {
      final splitters = List<Map<String, dynamic>>.from(
        record['splitters'] ?? const [],
      );
      final splitter = splitters.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['id'] == endpoint.splitterId,
        orElse: () => null,
      );
      if (splitter == null) {
        return;
      }
      final ratio = (splitter['ratio'] as int?) ?? 8;
      if (endpoint.splitterPortType == 'input') {
        for (var index = 0; index < ratio; index++) {
          yield _TraceTransition(
            _TraceEndpoint.splitterPort(
              entityTypeCode: endpoint.entityTypeCode,
              entityId: endpoint.entityId,
              splitterId: endpoint.splitterId!,
              splitterPortType: 'output',
              splitterPortIndex: index,
            ),
          );
        }
      } else {
        yield _TraceTransition(
          _TraceEndpoint.splitterPort(
            entityTypeCode: endpoint.entityTypeCode,
            entityId: endpoint.entityId,
            splitterId: endpoint.splitterId!,
            splitterPortType: 'input',
            splitterPortIndex: 0,
          ),
        );
      }
    }
  }

  _TraceTransition? _traceRouteNeighbor(_TraceEndpoint endpoint) {
    final record = _recordByTypeAndId(endpoint.entityTypeCode, endpoint.entityId);
    if (record == null) {
      return null;
    }

    final cable = _cableById(record, endpoint.cableId!);
    if (cable == null) {
      return null;
    }

    final routeId = cable['route_id'] as int?;
    final peerEntityType = cable['peer_entity_type'] as String?;
    final peerEntityId = cable['peer_entity_id'] as int?;
    final peerCableId = cable['peer_cable_id'] as int?;
    if (routeId == null ||
        peerEntityType == null ||
        peerEntityId == null ||
        peerCableId == null) {
      return null;
    }

    return _TraceTransition(
      _TraceEndpoint.cableFiber(
        entityTypeCode: peerEntityType,
        entityId: peerEntityId,
        cableId: peerCableId,
        fiberIndex: endpoint.fiberIndex!,
      ),
      routeId: routeId,
    );
  }

  _TraceEndpoint? _cabinetEndpointFromConnection(
    String entityTypeCode,
    int entityId,
    Map<String, dynamic> connection,
    bool first,
  ) {
    final switchId = connection[first ? 'switch1' : 'switch2'] as int?;
    final portIndex = connection[first ? 'port1' : 'port2'] as int?;
    if (switchId != null && portIndex != null) {
      return _TraceEndpoint.cabinetPort(
        entityTypeCode: entityTypeCode,
        entityId: entityId,
        switchId: switchId,
        portIndex: portIndex,
      );
    }

    final cableId = connection[first ? 'cable1' : 'cable2'] as int?;
    final fiberIndex = connection[first ? 'fiber1' : 'fiber2'] as int?;
    if (cableId != null && fiberIndex != null) {
      return _TraceEndpoint.cableFiber(
        entityTypeCode: entityTypeCode,
        entityId: entityId,
        cableId: cableId,
        fiberIndex: fiberIndex,
      );
    }

    return null;
  }

  _TraceEndpoint? _muffEndpointFromMap(
    String entityTypeCode,
    int entityId,
    Map<String, dynamic> endpoint,
  ) {
    if (endpoint['type'] == 'splitter') {
      final splitterId = endpoint['splitterId'] as int?;
      final portType = endpoint['portType'] as String?;
      final portIndex = endpoint['portIndex'] as int?;
      if (splitterId == null || portType == null || portIndex == null) {
        return null;
      }
      return _TraceEndpoint.splitterPort(
        entityTypeCode: entityTypeCode,
        entityId: entityId,
        splitterId: splitterId,
        splitterPortType: portType,
        splitterPortIndex: portIndex,
      );
    }

    final cableId = endpoint['cableId'] as int?;
    final fiberIndex = endpoint['fiberIndex'] as int?;
    if (cableId == null || fiberIndex == null) {
      return null;
    }
    return _TraceEndpoint.cableFiber(
      entityTypeCode: entityTypeCode,
      entityId: entityId,
      cableId: cableId,
      fiberIndex: fiberIndex,
    );
  }

  bool _traceEndpointEquals(_TraceEndpoint left, _TraceEndpoint right) {
    return left.visitKey == right.visitKey;
  }

  Map<String, dynamic>? _recordByTypeAndId(String typeCode, int entityId) {
    final records = typeCode == 'cabinet' ? _cabinetRecords : _muffRecords;
    for (final record in records) {
      if ((record['id'] as int?) == entityId && record['deleted'] != true) {
        return record;
      }
    }
    return null;
  }

  Map<String, dynamic>? _cableById(Map<String, dynamic> record, int cableId) {
    final cables = List<Map<String, dynamic>>.from(record['cables'] ?? const []);
    for (final cable in cables) {
      if ((cable['id'] as int?) == cableId && cable['deleted'] != true) {
        return cable;
      }
    }
    return null;
  }

  Color? _traceColorForEndpoint(_TraceEndpoint endpoint) {
    if (endpoint.kind != _TraceEndpointKind.cableFiber) {
      return null;
    }
    final record = _recordByTypeAndId(endpoint.entityTypeCode, endpoint.entityId);
    if (record == null) {
      return null;
    }
    final cable = _cableById(record, endpoint.cableId!);
    if (cable == null) {
      return null;
    }
    final scheme = (cable['color_scheme'] as String?) ?? 'default';
    final colors = _fiberSchemes[scheme] ?? _fiberSchemes.values.first;
    if (colors.isEmpty) {
      return null;
    }
    final fiberIndex = endpoint.fiberIndex ?? 0;
    return colors[fiberIndex % colors.length];
  }

  void _focusTrace(_TraceResult result) {
    final points = <LatLng>[];
    for (final key in result.entityKeys) {
      final entity = _entityByKey(key);
      if (entity != null) {
        points.add(entity.point);
      }
    }
    for (final routeId in result.routeIds) {
      for (final route in _routes) {
        if (route.id == routeId) {
          points.addAll(route.points);
        }
      }
    }
    if (points.isEmpty) {
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  List<_InfrastructureEntity> get _visibleEntities {
    final visible = _entities.where((entity) {
      final record = _entityRecord(entity);
      return record != null && matchesProjectFilter(record, _projectFilterId);
    }).toList(growable: false);
    if (!_routeCreateMode) {
      return visible;
    }

    if (_pendingStartEntityKey == null) {
      return _routeCandidateEntities;
    }

    return visible;
  }

  List<_CableRoute> get _filteredRoutesByProject => _routes
      .where((route) => matchesProjectFilter(route.raw, _projectFilterId))
      .toList(growable: false);

  Map<int, String> get _projectOptions {
    final options = <int, String>{};
    for (final record in [..._muffRecords, ..._cabinetRecords, ..._routeRecords]) {
      final id = projectIdOf(record);
      final name = projectNameOf(record);
      if (id != null && name != null) {
        options[id] = name;
      }
    }
    return options;
  }

  List<_InfrastructureEntity> get _routeCandidateEntities {
    final visible = _entities.where((entity) {
      final record = _entityRecord(entity);
      return record != null && matchesProjectFilter(record, _projectFilterId);
    }).toList(growable: false);
    if (!_routeCreateMode) {
      return const [];
    }

    if (_pendingStartEntityKey == null) {
      return visible.where(_hasAnyFreeCable).toList(growable: false);
    }

    final fibers = _pendingRequiredFibers;
    if (fibers == null) {
      return const [];
    }

    return visible.where((entity) {
      if (entity.key == _pendingStartEntityKey) {
        return true;
      }
      return _freeCableChoicesForEntity(entity, fibers: fibers).isNotEmpty;
    }).toList(growable: false);
  }

  void _applyProjectFilter(String value) {
    final nextFilter = value == '__all_projects__' ? null : int.tryParse(value);
    setState(() {
      _projectFilterId = nextFilter;
      if (_selectedRoute != null &&
          !matchesProjectFilter(_selectedRoute!.raw, _projectFilterId)) {
        _selectedRouteId = null;
      }
    });
  }

  bool _hasAnyFreeCable(_InfrastructureEntity entity) =>
      _freeCableChoicesForEntity(entity).isNotEmpty;

  bool _isEntityCandidateForCurrentStep(_InfrastructureEntity entity) {
    if (!_routeCreateMode) {
      return true;
    }

    if (_pendingStartEntityKey == null) {
      return _hasAnyFreeCable(entity);
    }

    if (entity.key == _pendingStartEntityKey) {
      return true;
    }

    final fibers = _pendingRequiredFibers;
    if (fibers == null) {
      return false;
    }
    return _freeCableChoicesForEntity(entity, fibers: fibers).isNotEmpty;
  }

  Map<String, dynamic>? _entityRecord(_InfrastructureEntity entity) {
    final records = entity.type == _InfrastructureEntityType.cabinet
        ? _cabinetRecords
        : _muffRecords;

    for (final record in records) {
      if ((record['id'] as int?) == entity.id && record['deleted'] != true) {
        return record;
      }
    }
    return null;
  }

  List<_RouteCableChoice> _freeCableChoicesForEntity(
    _InfrastructureEntity entity, {
    int? fibers,
  }) {
    final record = _entityRecord(entity);
    if (record == null) {
      return const [];
    }

    final cables = List<Map<String, dynamic>>.from(record['cables'] ?? const []);
    return cables.where((cable) {
      if (cable['deleted'] == true) {
        return false;
      }
      final cableFibers = (cable['fibers'] as int?) ?? 1;
      if (fibers != null && cableFibers != fibers) {
        return false;
      }
      return cable['route_id'] == null;
    }).map((cable) {
      final cableId = (cable['id'] as int?) ?? 0;
      final cableFibers = (cable['fibers'] as int?) ?? 1;
      final cableName = (cable['name'] as String?)?.trim();
      return _RouteCableChoice(
        entity: entity,
        cableId: cableId,
        cableName: cableName?.isNotEmpty == true ? cableName! : 'Кабель #$cableId',
        fibers: cableFibers,
      );
    }).toList(growable: false);
  }

  Future<_RouteCableChoice?> _pickCableForEntity(
    _InfrastructureEntity entity, {
    required String title,
    int? fibers,
  }) async {
    final choices = _freeCableChoicesForEntity(entity, fibers: fibers);
    if (choices.isEmpty) {
      return null;
    }

    return showModalBottomSheet<_RouteCableChoice>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(entity.name),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: choices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final choice = choices[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(choice.cableName),
                        subtitle: Text('Волокон: ${choice.fibers}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(choice),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _touchRecord(Map<String, dynamic> record) {
    record['updated_at'] = DateTime.now();
    record['dirty'] = true;
    record['deleted'] = false;
  }

  void _bindCableToRoute(
    Map<String, dynamic> record, {
    required int cableId,
    required int routeId,
    required _InfrastructureEntity peerEntity,
    required _RouteCableChoice peerCable,
    required String role,
  }) {
    final cables = List<Map<String, dynamic>>.from(record['cables'] ?? const []);
    final index = cables.indexWhere((cable) => cable['id'] == cableId);
    if (index == -1) {
      return;
    }

    final cable = Map<String, dynamic>.from(cables[index]);
    cable['route_id'] = routeId;
    cable['route_role'] = role;
    cable['peer_entity_type'] = _entityTypeCode(peerEntity.type);
    cable['peer_entity_id'] = peerEntity.id;
    cable['peer_entity_name'] = peerEntity.name;
    cable['peer_cable_id'] = peerCable.cableId;
    cable['peer_cable_name'] = peerCable.cableName;
    cables[index] = cable;
    record['cables'] = cables;
    _touchRecord(record);
  }

  void _unbindCableFromRoute(
    Map<String, dynamic> record, {
    required int cableId,
    required int routeId,
  }) {
    final cables = List<Map<String, dynamic>>.from(record['cables'] ?? const []);
    final index = cables.indexWhere((cable) => cable['id'] == cableId);
    if (index == -1) {
      return;
    }

    final cable = Map<String, dynamic>.from(cables[index]);
    if (cable['route_id'] != routeId) {
      return;
    }
    cable.remove('route_id');
    cable.remove('route_role');
    cable.remove('peer_entity_type');
    cable.remove('peer_entity_id');
    cable.remove('peer_entity_name');
    cable.remove('peer_cable_id');
    cable.remove('peer_cable_name');
    cables[index] = cable;
    record['cables'] = cables;
    _touchRecord(record);
  }

  bool _anchorMatchesEntity(Map<String, dynamic>? anchor, _InfrastructureEntity entity) {
    if (anchor == null) {
      return false;
    }
    return anchor['type'] == _entityTypeCode(entity.type) &&
        anchor['entity_id'] == entity.id;
  }

  List<_CableRoute> _routesForEntity(_InfrastructureEntity entity) {
    return _routes.where((route) {
      final startAnchor = _extractAnchor(route.raw['start_anchor']);
      final endAnchor = _extractAnchor(route.raw['end_anchor']);
      return _anchorMatchesEntity(startAnchor, entity) ||
          _anchorMatchesEntity(endAnchor, entity);
    }).toList(growable: false);
  }

  void _showEntitySheet(_InfrastructureEntity entity) {
    final relatedRoutes = _routesForEntity(entity);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final initialSize = relatedRoutes.isEmpty ? 0.34 : 0.5;
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: initialSize,
            minChildSize: 0.28,
            maxChildSize: 0.8,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    SliverToBoxAdapter(
                      child: Row(
                        children: [
                          _entityChip(entity),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entity.name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    if (entity.location.isNotEmpty)
                      SliverToBoxAdapter(child: Text(entity.location)),
                    const SliverToBoxAdapter(child: SizedBox(height: 6)),
                    SliverToBoxAdapter(
                      child: Text(
                        '${entity.point.latitude.toStringAsFixed(6)}, ${entity.point.longitude.toStringAsFixed(6)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 14)),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final entry = entity.meta.entries.elementAt(index);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _MapMetaRow(label: entry.key, value: entry.value),
                        );
                      }, childCount: entity.meta.length),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 10)),
                    SliverToBoxAdapter(
                      child: Text(
                        relatedRoutes.isEmpty
                            ? 'У этого объекта пока нет привязанных маршрутов.'
                            : 'Маршруты от этого объекта',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 10)),
                    if (relatedRoutes.isEmpty)
                      const SliverToBoxAdapter(
                        child: Text(
                          'Список пуст. Когда маршрут будет начинаться или заканчиваться на этом объекте, он появится здесь.',
                        ),
                      )
                    else
                      SliverList.separated(
                        itemCount: relatedRoutes.length,
                        itemBuilder: (context, index) {
                          final route = relatedRoutes[index];
                          final startAnchor = _extractAnchor(
                            route.raw['start_anchor'],
                          );
                          final endAnchor = _extractAnchor(route.raw['end_anchor']);
                          final role = _anchorMatchesEntity(startAnchor, entity)
                              ? 'Начало'
                              : _anchorMatchesEntity(endAnchor, entity)
                                  ? 'Конец'
                                  : 'Маршрут';

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  (route.id == _selectedRouteId
                                          ? const Color(0xFF1EDDC5)
                                          : const Color(0xFF60A5FA))
                                      .withValues(alpha: 0.16),
                              child: Icon(
                                Icons.timeline_rounded,
                                color: route.id == _selectedRouteId
                                    ? const Color(0xFF1EDDC5)
                                    : const Color(0xFF60A5FA),
                              ),
                            ),
                            title: Text(
                              route.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$role • ${_formatRouteLength(route.lengthMeters)} • Точек: ${route.points.length}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: route.id == _selectedRouteId
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF1EDDC5),
                                  )
                                : const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.of(context).pop();
                              _selectRoute(route);
                            },
                          );
                        },
                        separatorBuilder: (_, _) => const Divider(height: 1),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Color _entityColor(_InfrastructureEntityType type) {
    switch (type) {
      case _InfrastructureEntityType.ponBox:
        return const Color(0xFF29D39A);
      case _InfrastructureEntityType.cabinet:
        return const Color(0xFF60A5FA);
      case _InfrastructureEntityType.muff:
        return const Color(0xFFFF7A59);
    }
  }

  IconData _entityIcon(_InfrastructureEntityType type) {
    switch (type) {
      case _InfrastructureEntityType.ponBox:
        return Icons.hub_outlined;
      case _InfrastructureEntityType.cabinet:
        return Icons.dns_rounded;
      case _InfrastructureEntityType.muff:
        return Icons.scatter_plot_outlined;
    }
  }

  Widget _entityChip(_InfrastructureEntity entity) {
    final color = _entityColor(entity.type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_entityIcon(entity.type), size: 16, color: color),
          const SizedBox(width: 6),
          Text(entity.subtitle, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  void _selectRoute(_CableRoute route) {
    setState(() {
      _selectedRouteId = route.id;
      _routeCreateMode = false;
      _pendingStartEntityKey = null;
      _pendingStartCableId = null;
      _pendingRequiredFibers = null;
    });
    _mapController.move(route.points.first, _mapZoom < 15 ? 15 : _mapZoom);
  }

  void _toggleRouteCreateMode() {
    setState(() {
      _routeCreateMode = !_routeCreateMode;
      _routeEditMode = false;
      _pendingStartEntityKey = null;
      _pendingStartCableId = null;
      _pendingRequiredFibers = null;
    });
  }

  void _toggleRouteEditMode() {
    if (_selectedRoute == null) {
      return;
    }
    setState(() {
      _routeEditMode = !_routeEditMode;
      _routeCreateMode = false;
      _pendingStartEntityKey = null;
      _pendingStartCableId = null;
      _pendingRequiredFibers = null;
    });
  }

  void handleEntityTapLegacy(_InfrastructureEntity entity) {
    if (_routeCreateMode) {
      if (_pendingStartEntityKey == null) {
        setState(() {
          _pendingStartEntityKey = entity.key;
        });
        _showSnackBar('Начало выбрано. Теперь выберите конец маршрута.');
        return;
      }

      if (_pendingStartEntityKey == entity.key) {
        _showSnackBar('Начало и конец маршрута должны быть разными.');
        return;
      }

      final start = _entityByKey(_pendingStartEntityKey);
      if (start == null) {
        _showSnackBar('Не удалось найти начальную точку маршрута.');
        setState(() {
          _pendingStartEntityKey = null;
        });
        return;
      }

      _createRouteBetween(start, entity);
      return;
    }

    _showEntitySheet(entity);
  }

  void _handleEntityTapV2(_InfrastructureEntity entity) {
    if (_routeCreateMode) {
      if (_pendingStartEntityKey == null) {
        unawaited(() async {
          final startCable = await _pickCableForEntity(
            entity,
            title: 'Выберите свободный кабель начала маршрута',
          );
          if (startCable == null || !mounted) {
            return;
          }
          setState(() {
            _pendingStartEntityKey = entity.key;
            _pendingStartCableId = startCable.cableId;
            _pendingRequiredFibers = startCable.fibers;
          });
          _showSnackBar(
            'Начало и кабель выбраны. Теперь выберите объект с таким же количеством волокон.',
          );
        }());
        return;
      }

      if (_pendingStartEntityKey == entity.key) {
        _showSnackBar('Начало и конец маршрута должны быть разными.');
        return;
      }

      final start = _entityByKey(_pendingStartEntityKey);
      if (start == null) {
        _showSnackBar('Не удалось найти начальную точку маршрута.');
        setState(() {
          _pendingStartEntityKey = null;
          _pendingStartCableId = null;
          _pendingRequiredFibers = null;
        });
        return;
      }

      final requiredFibers = _pendingRequiredFibers;
      final startCableId = _pendingStartCableId;
      if (requiredFibers == null || startCableId == null) {
        _showSnackBar('Сначала выберите стартовый кабель.');
        return;
      }

      _RouteCableChoice? startCable;
      for (final choice
          in _freeCableChoicesForEntity(start, fibers: requiredFibers)) {
        if (choice.cableId == startCableId) {
          startCable = choice;
          break;
        }
      }
      if (startCable == null) {
        _showSnackBar(
          'Стартовый кабель больше недоступен. Выберите начало маршрута заново.',
        );
        setState(() {
          _pendingStartEntityKey = null;
          _pendingStartCableId = null;
          _pendingRequiredFibers = null;
        });
        return;
      }

      if (_freeCableChoicesForEntity(entity, fibers: requiredFibers).isEmpty) {
        _showSnackBar(
          'У этого объекта нет свободных кабелей на $requiredFibers волокон.',
        );
        return;
      }

      unawaited(() async {
        final endCable = await _pickCableForEntity(
          entity,
          title: 'Выберите свободный кабель конца маршрута',
          fibers: requiredFibers,
        );
        if (endCable == null) {
          return;
        }
        await _createRouteBetweenWithBindings(start, entity, startCable!, endCable);
      }());
      return;
    }

    _showEntitySheet(entity);
  }

  int _nextRouteId() {
    var maxId = 0;
    for (final record in _routeRecords) {
      final id = record['id'];
      if (id is int && id > maxId) {
        maxId = id;
      } else if (id is num && id.toInt() > maxId) {
        maxId = id.toInt();
      }
    }
    return maxId + 1;
  }

  Future<void> _createRouteBetween(
    _InfrastructureEntity start,
    _InfrastructureEntity end,
  ) async {
    final routeId = _nextRouteId();
    final now = DateTime.now();
    final routeRecord = <String, dynamic>{
      'id': routeId,
      'name': '${start.name} - ${end.name}',
      'note': '',
      'start_anchor': {
        'type': _entityTypeCode(start.type),
        'entity_id': start.id,
        'name': start.name,
        'subtitle': start.subtitle,
        'location': start.location,
        'lat': start.point.latitude,
        'lng': start.point.longitude,
      },
      'end_anchor': {
        'type': _entityTypeCode(end.type),
        'entity_id': end.id,
        'name': end.name,
        'subtitle': end.subtitle,
        'location': end.location,
        'lat': end.point.latitude,
        'lng': end.point.longitude,
      },
      'route_points': [
        {'lat': start.point.latitude, 'lng': start.point.longitude},
        {'lat': end.point.latitude, 'lng': end.point.longitude},
      ],
      'updated_at': now,
      'dirty': true,
      'deleted': false,
    };
    applyProjectSelection(routeRecord, _activeProject);

    final nextRecords =
        _routeRecords
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true)
          ..add(routeRecord);

    await _persistRoutes(
      nextRecords,
      selectedRouteId: routeId,
      preserveModes: false,
    );
    await _recordTaskAddition(
      kind: 'Добавлен маршрут',
      summary: [
        routeRecord['name']?.toString() ?? 'Маршрут',
        if ((start.location).trim().isNotEmpty) 'старт: ${start.location}',
        if ((end.location).trim().isNotEmpty) 'финиш: ${end.location}',
      ].join(' • '),
      targetRecordId: routeId,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _routeCreateMode = false;
      _routeEditMode = true;
      _pendingStartEntityKey = null;
      _selectedRouteId = routeId;
    });
    _showSnackBar('Маршрут создан. Тапните по сегменту, чтобы добавить точку.');
  }

  Future<void> _createRouteBetweenWithBindings(
    _InfrastructureEntity start,
    _InfrastructureEntity end,
    _RouteCableChoice startCable,
    _RouteCableChoice endCable,
  ) async {
    final startSource = _entityRecord(start);
    final endSource = _entityRecord(end);
    if (startSource == null || endSource == null) {
      _showSnackBar('Не удалось найти записи объектов для привязки кабелей.');
      return;
    }

    final routeId = _nextRouteId();
    final now = DateTime.now();
    final routeRecord = <String, dynamic>{
      'id': routeId,
      'name': '${start.name} - ${end.name}',
      'note': '',
      'start_anchor': {
        'type': _entityTypeCode(start.type),
        'entity_id': start.id,
        'name': start.name,
        'subtitle': start.subtitle,
        'location': start.location,
        'lat': start.point.latitude,
        'lng': start.point.longitude,
      },
      'end_anchor': {
        'type': _entityTypeCode(end.type),
        'entity_id': end.id,
        'name': end.name,
        'subtitle': end.subtitle,
        'location': end.location,
        'lat': end.point.latitude,
        'lng': end.point.longitude,
      },
      'start_cable': {
        'id': startCable.cableId,
        'name': startCable.cableName,
        'fibers': startCable.fibers,
      },
      'end_cable': {
        'id': endCable.cableId,
        'name': endCable.cableName,
        'fibers': endCable.fibers,
      },
      'route_points': [
        {'lat': start.point.latitude, 'lng': start.point.longitude},
        {'lat': end.point.latitude, 'lng': end.point.longitude},
      ],
      'updated_at': now,
      'dirty': true,
      'deleted': false,
    };
    applyProjectSelection(routeRecord, _activeProject);

    final nextRouteRecords =
        _routeRecords
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true)
          ..add(routeRecord);
    final nextMuffRecords = _muffRecords
        .map((record) => _syncRepository.clone(record))
        .toList(growable: true);
    final nextCabinetRecords = _cabinetRecords
        .map((record) => _syncRepository.clone(record))
        .toList(growable: true);

    void replaceEntityRecord(
      _InfrastructureEntity entity,
      Map<String, dynamic> record,
    ) {
      final records = entity.type == _InfrastructureEntityType.cabinet
          ? nextCabinetRecords
          : nextMuffRecords;
      final index = records.indexWhere((item) => item['id'] == entity.id);
      if (index != -1) {
        records[index] = record;
      }
    }

    final startRecord = _syncRepository.clone(startSource);
    final endRecord = _syncRepository.clone(endSource);
    _bindCableToRoute(
      startRecord,
      cableId: startCable.cableId,
      routeId: routeId,
      peerEntity: end,
      peerCable: endCable,
      role: 'start',
    );
    _bindCableToRoute(
      endRecord,
      cableId: endCable.cableId,
      routeId: routeId,
      peerEntity: start,
      peerCable: startCable,
      role: 'end',
    );
    replaceEntityRecord(start, startRecord);
    replaceEntityRecord(end, endRecord);

    await _persistAllRecords(
      nextRouteRecords: nextRouteRecords,
      nextMuffRecords: nextMuffRecords,
      nextCabinetRecords: nextCabinetRecords,
      selectedRouteId: routeId,
      preserveModes: false,
    );
    await _recordTaskAddition(
      kind: 'Добавлен маршрут',
      summary: [
        routeRecord['name']?.toString() ?? 'Маршрут',
        'кабель старта: ${startCable.cableName} (${startCable.fibers} вол.)',
        'кабель финиша: ${endCable.cableName} (${endCable.fibers} вол.)',
      ].join(' • '),
      targetRecordId: routeId,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _routeEditMode = true;
      _selectedRouteId = routeId;
    });
    _showSnackBar('Маршрут и привязки кабелей созданы.');
  }

  Future<void> _deleteSelectedRoute() async {
    final route = _selectedRoute;
    if (route == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить маршрут'),
        content: Text('Маршрут "${route.name}" будет удалён.'),
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
        _routeRecords
            .where((record) => record['id'] != route.id)
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true)
          ..add({
            'id': route.id,
            'updated_at': now,
            'dirty': true,
            'deleted': true,
          });
    final nextMuffRecords = _muffRecords
        .map((record) => _syncRepository.clone(record))
        .toList(growable: true);
    final nextCabinetRecords = _cabinetRecords
        .map((record) => _syncRepository.clone(record))
        .toList(growable: true);

    void unbindFromEntity(Map<String, dynamic>? anchor, Map<String, dynamic>? cable) {
      if (anchor == null || cable == null) {
        return;
      }
      final entityId = anchor['entity_id'] as int?;
      final cableId = cable['id'] as int?;
      if (entityId == null || cableId == null) {
        return;
      }
      final entityType = anchor['type'];
      final records = entityType == _entityTypeCode(_InfrastructureEntityType.cabinet)
          ? nextCabinetRecords
          : nextMuffRecords;
      final index = records.indexWhere((record) => record['id'] == entityId);
      if (index == -1) {
        return;
      }
      final record = _syncRepository.clone(records[index]);
      _unbindCableFromRoute(record, cableId: cableId, routeId: route.id);
      records[index] = record;
    }

    unbindFromEntity(
      _extractAnchor(route.raw['start_anchor']),
      _extractAnchor(route.raw['start_cable']),
    );
    unbindFromEntity(
      _extractAnchor(route.raw['end_anchor']),
      _extractAnchor(route.raw['end_cable']),
    );

    await _persistAllRecords(
      nextRouteRecords: nextRecords,
      nextMuffRecords: nextMuffRecords,
      nextCabinetRecords: nextCabinetRecords,
      selectedRouteId: null,
      preserveModes: false,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedRouteId = _routes.isEmpty ? null : _routes.first.id;
      _routeEditMode = false;
    });
  }

  Future<void> _persistRoutes(
    List<Map<String, dynamic>> records, {
    required int? selectedRouteId,
    required bool preserveModes,
    bool forceSync = true,
  }) async {
    final companyId = widget.controller.membership?.companyId;
    if (companyId == null) {
      return;
    }

    setState(() {
      _syncingRoutes = true;
      _errorMessage = null;
    });

    try {
      var nextRecords = records;
      await _syncRepository.writeCache(_routesCacheKey, nextRecords);

      if (forceSync || nextRecords.any((record) => record['dirty'] == true)) {
        nextRecords = await _syncRepository.syncAll(
          companyId: companyId,
          moduleKey: _routesModuleKey,
          cacheKey: _routesCacheKey,
          localRecords: nextRecords,
        );
      }

      final nextRoutes =
          nextRecords
              .where((record) => record['deleted'] != true)
              .map(_routeFromRecord)
              .whereType<_CableRoute>()
              .toList(growable: false)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _routeRecords = nextRecords
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true);
        _routes = nextRoutes;
        _selectedRouteId = selectedRouteId;
        _syncingRoutes = false;
        if (!preserveModes) {
          _routeCreateMode = false;
          _routeEditMode = false;
          _pendingStartEntityKey = null;
          _pendingStartCableId = null;
          _pendingRequiredFibers = null;
        }
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось сохранить кабельный маршрут.',
        source: 'infrastructure_map.persist_routes',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _syncingRoutes = false;
      });
      _showSnackBar('Не удалось сохранить маршрут.');
    }
  }

  Future<void> _persistAllRecords({
    required List<Map<String, dynamic>> nextRouteRecords,
    required List<Map<String, dynamic>> nextMuffRecords,
    required List<Map<String, dynamic>> nextCabinetRecords,
    required int? selectedRouteId,
    required bool preserveModes,
  }) async {
    final companyId = widget.controller.membership?.companyId;
    if (companyId == null) {
      return;
    }

    setState(() {
      _syncingRoutes = true;
      _errorMessage = null;
    });

    try {
      var routes = nextRouteRecords;
      var muffs = nextMuffRecords;
      var cabinets = nextCabinetRecords;

      await _syncRepository.writeCache(_routesCacheKey, routes);
      await _syncRepository.writeCache(_muffsCacheKey, muffs);
      await _syncRepository.writeCache(_cabinetsCacheKey, cabinets);

      if (routes.any((record) => record['dirty'] == true)) {
        routes = await _syncRepository.syncAll(
          companyId: companyId,
          moduleKey: _routesModuleKey,
          cacheKey: _routesCacheKey,
          localRecords: routes,
        );
      }
      if (muffs.any((record) => record['dirty'] == true)) {
        muffs = await _syncRepository.syncAll(
          companyId: companyId,
          moduleKey: _muffsModuleKey,
          cacheKey: _muffsCacheKey,
          localRecords: muffs,
        );
      }
      if (cabinets.any((record) => record['dirty'] == true)) {
        cabinets = await _syncRepository.syncAll(
          companyId: companyId,
          moduleKey: _cabinetsModuleKey,
          cacheKey: _cabinetsCacheKey,
          localRecords: cabinets,
        );
      }

      final nextEntities = <_InfrastructureEntity>[
        ..._muffEntities(muffs),
        ..._cabinetEntities(cabinets),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final nextRoutes =
          routes
              .where((record) => record['deleted'] != true)
              .map(_routeFromRecord)
              .whereType<_CableRoute>()
              .toList(growable: false)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _routeRecords = routes
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true);
        _muffRecords = muffs
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true);
        _cabinetRecords = cabinets
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true);
        _entities = nextEntities;
        _routes = nextRoutes;
        _selectedRouteId = selectedRouteId;
        _syncingRoutes = false;
        if (!preserveModes) {
          _routeCreateMode = false;
          _routeEditMode = false;
          _pendingStartEntityKey = null;
          _pendingStartCableId = null;
          _pendingRequiredFibers = null;
        }
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось сохранить маршрут и привязки кабелей.',
        source: 'infrastructure_map.persist_all',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _syncingRoutes = false;
      });
      _showSnackBar('Не удалось сохранить маршрут и привязки.');
    }
  }

  void _replaceRoutePointsLocally(int routeId, List<LatLng> points) {
    final nextRecords = _routeRecords
        .map((record) => _syncRepository.clone(record))
        .toList(growable: true);
    final index = nextRecords.indexWhere((record) => record['id'] == routeId);
    if (index == -1) {
      return;
    }

    nextRecords[index]['route_points'] = points
        .map(
          (point) => <String, double>{
            'lat': point.latitude,
            'lng': point.longitude,
          },
        )
        .toList(growable: false);
    nextRecords[index]['updated_at'] = DateTime.now();
    nextRecords[index]['dirty'] = true;

    final nextRoutes =
        nextRecords
            .where((record) => record['deleted'] != true)
            .map(_routeFromRecord)
            .whereType<_CableRoute>()
            .toList(growable: false)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    setState(() {
      _routeRecords = nextRecords;
      _routes = nextRoutes;
      _selectedRouteId = routeId;
    });
  }

  Future<void> _syncSelectedRoutePoints() async {
    final route = _selectedRoute;
    if (route == null) {
      return;
    }
    await _persistRoutes(
      _routeRecords.map((record) => _syncRepository.clone(record)).toList(),
      selectedRouteId: route.id,
      preserveModes: true,
    );
  }

  void _insertPointIntoSelectedRoute(int insertIndex, LatLng point) {
    final route = _selectedRoute;
    if (route == null) {
      return;
    }

    final points = List<LatLng>.from(route.points)..insert(insertIndex, point);
    _replaceRoutePointsLocally(route.id, points);
    _syncSelectedRoutePoints();
  }

  int? _segmentInsertIndexForTap(_CableRoute route, Offset tapOffset) {
    var bestDistance = double.infinity;
    int? bestIndex;

    for (var i = 0; i < route.points.length - 1; i++) {
      final start = _mapController.camera.latLngToScreenPoint(route.points[i]);
      final end = _mapController.camera.latLngToScreenPoint(
        route.points[i + 1],
      );
      final distance = _distanceToSegment(
        tapOffset,
        Offset(start.x, start.y),
        Offset(end.x, end.y),
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i + 1;
      }
    }

    return bestDistance <= 18 ? bestIndex : null;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) {
      return (p - a).distance;
    }

    final t =
        (((p.dx - a.dx) * dx) + ((p.dy - a.dy) * dy)) / ((dx * dx) + (dy * dy));
    final clamped = t.clamp(0.0, 1.0);
    final projection = Offset(a.dx + dx * clamped, a.dy + dy * clamped);
    return (p - projection).distance;
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    if (!_routeEditMode || _selectedRoute == null) {
      return;
    }
    final relative = tapPosition.relative;
    if (relative == null) {
      return;
    }

    final insertIndex = _segmentInsertIndexForTap(_selectedRoute!, relative);
    if (insertIndex == null) {
      return;
    }

    _insertPointIntoSelectedRoute(insertIndex, point);
  }

  void _dragIntermediatePoint(
    int routeId,
    int pointIndex,
    DragUpdateDetails details,
  ) {
    final route = _selectedRoute;
    if (route == null || route.id != routeId) {
      return;
    }

    final current = route.points[pointIndex];
    final screen = _mapController.camera.latLngToScreenPoint(current);
    final nextScreen = math.Point<double>(
      screen.x + details.delta.dx,
      screen.y + details.delta.dy,
    );
    final nextLatLng = _mapController.camera.pointToLatLng(nextScreen);
    final points = List<LatLng>.from(route.points);
    points[pointIndex] = nextLatLng;
    _replaceRoutePointsLocally(routeId, points);
  }

  Widget _buildLegendCard() {
    final selectedRoute = _selectedRoute;

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
                    'Карта инфраструктуры',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LegendRow(
                    color: _entityColor(_InfrastructureEntityType.muff),
                    icon: _entityIcon(_InfrastructureEntityType.muff),
                    label: 'Муфты',
                  ),
                  const SizedBox(height: 8),
                  _LegendRow(
                    color: _entityColor(_InfrastructureEntityType.ponBox),
                    icon: _entityIcon(_InfrastructureEntityType.ponBox),
                    label: 'PON боксы',
                  ),
                  const SizedBox(height: 8),
                  _LegendRow(
                    color: _entityColor(_InfrastructureEntityType.cabinet),
                    icon: _entityIcon(_InfrastructureEntityType.cabinet),
                    label: 'Сетевые шкафы',
                  ),
                  const SizedBox(height: 8),
                  const _LegendRow(
                    color: Color(0xFF1EDDC5),
                    icon: Icons.timeline_rounded,
                    label: 'Кабельные маршруты',
                  ),
                  const SizedBox(height: 12),
                  if (_routeCreateMode)
                    Text(
                      _pendingStartEntityKey == null
                          ? 'Выберите начало маршрута по муфте или шкафу.'
                          : 'Теперь выберите конец маршрута.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else if (_routeEditMode && _selectedRoute != null)
                    Text(
                      'Тапните рядом с линией, чтобы вставить точку. Промежуточные точки можно перетаскивать.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (_routeEditMode && selectedRoute != null)
                    Text(
                      'Длина маршрута: ${_formatRouteLength(selectedRoute.lengthMeters)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  if (_routeEditMode && selectedRoute != null)
                    const SizedBox(height: 10),
                  if (_routeCreateMode || _routeEditMode)
                    const SizedBox(height: 10),
                  if (_traceSummary != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB347).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFFB347).withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        _traceSummary!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Text(
                    'Точек: ${_entities.length} • Маршрутов: ${_routes.length}',
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

  /*
  Widget _buildSelectedRouteCard(_CableRoute route) {
    return _buildRouteListCard(route, selected: true, dense: true);
  }

  Widget _buildRouteListCard(
    _CableRoute route, {
    required bool selected,
    bool dense = false,
  }) {
    final color = selected
        ? const Color(0xFF1EDDC5)
        : const Color(0xFF60A5FA);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _selectRoute(route),
      child: Ink(
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: color.withValues(alpha: selected ? 0.55 : 0.24),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(dense ? 14 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.timeline_rounded, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      route.name,
                      maxLines: dense ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (selected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Активный',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final entry in route.meta.entries.take(dense ? 2 : 3)) ...[
                _MapMetaRow(label: entry.key, value: entry.value),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoutePanel() {
    if (_routes.isEmpty) {
      return DraggableScrollableSheet(
        initialChildSize: 0.22,
        minChildSize: 0.18,
        maxChildSize: 0.4,
        builder: (context, scrollController) {
          return _RoutePanelShell(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: const [
                Text(
                  'Маршрутов пока нет. Нажмите "+" и выберите сначала начало, затем конец по существующим муфтам или шкафам.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      );
    }

    final filteredRoutes = _filteredRoutesByProject;
    final selectedRoute = _selectedRoute;

    return DraggableScrollableSheet(
      initialChildSize: 0.26,
      minChildSize: 0.18,
      maxChildSize: 0.72,
      snap: true,
      snapSizes: const [0.26, 0.5, 0.72],
      builder: (context, scrollController) {
        return _RoutePanelShell(
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Маршруты',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text(
                            '${filteredRoutes.length} из ${_routes.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _routeSearchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText:
                              'Поиск по названию, началу, концу, примечанию',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _routeSearchQuery.trim().isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Очистить поиск',
                                  onPressed: _clearRouteSearch,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          filled: true,
                          fillColor: const Color(0xFF0B1D31),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFF1D3F63),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: Color(0xFF1D3F63),
                            ),
                          ),
                        ),
                      ),
                      if (selectedRoute != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Выбранный маршрут',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        _buildSelectedRouteCard(selectedRoute),
                      ],
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              if (filteredRoutes.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: Center(
                      child: Text(
                        'По этому запросу маршруты не найдены.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: filteredRoutes.length,
                    itemBuilder: (context, index) {
                      final route = filteredRoutes[index];
                      return _buildRouteListCard(
                        route,
                        selected: route.id == _selectedRouteId,
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget buildRouteListLegacy() {
    if (_routes.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFF071526),
          border: Border(top: BorderSide(color: Color(0xFF1D3F63))),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Маршрутов пока нет. Нажмите "+" и выберите сначала начало, затем конец по существующим муфтам или шкафам.',
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
          final selected = route.id == _selectedRouteId;
          final color = selected
              ? const Color(0xFF1EDDC5)
              : const Color(0xFF60A5FA);

          return SizedBox(
            width: 320,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _selectRoute(route),
              child: Ink(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: color.withValues(alpha: selected ? 0.55 : 0.24),
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
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final entry in route.meta.entries.take(3)) ...[
                        _MapMetaRow(label: entry.key, value: entry.value),
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

  */
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

    final visibleRoutes = _filteredRoutesByProject;
    if (_visibleEntities.isEmpty && visibleRoutes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'На карте пока нет сущностей с координатами и кабельных маршрутов.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final center = _visibleEntities.isNotEmpty
        ? _visibleEntities.first.point
        : visibleRoutes.first.points.first;
    final visibleEntities = _visibleEntities;
    final selectedRoute = _selectedRoute;
    final dragMarkers =
        _routeEditMode &&
            selectedRoute != null &&
            selectedRoute.points.length > 2
        ? List.generate(selectedRoute.points.length - 2, (index) {
            final pointIndex = index + 1;
            final point = selectedRoute.points[pointIndex];
            return Marker(
              point: point,
              width: 26,
              height: 26,
              child: GestureDetector(
                onPanUpdate: (details) => _dragIntermediatePoint(
                  selectedRoute.id,
                  pointIndex,
                  details,
                ),
                onPanEnd: (_) => _syncSelectedRoutePoints(),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA629),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.drag_indicator_rounded,
                    size: 14,
                    color: Color(0xFF071526),
                  ),
                ),
              ),
            );
          })
        : const <Marker>[];

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              crs: mapCrsById(_selectedTileLayerId),
              initialCenter: center,
              initialZoom: _mapZoom,
              maxZoom: 19,
              onTap: _handleMapTap,
              onPositionChanged: (position, _) {
                _mapZoom = position.zoom;
              },
            ),
            children: [
              tileLayerById(_selectedTileLayerId),
              if (visibleRoutes.isNotEmpty)
                PolylineLayer(
                  polylines: visibleRoutes
                      .map(
                        (route) {
                          final isSelected = route.id == _selectedRouteId;
                          final isTraced = _highlightedRouteIds.contains(route.id);
                          final traceColor = _highlightedRouteColors[route.id];
                          final color = isTraced
                              ? (traceColor ?? const Color(0xFFFFB347))
                              : isSelected
                                  ? const Color(0xFF1EDDC5)
                                  : const Color(0xFF60A5FA);
                          return Polyline(
                            points: route.points,
                            strokeWidth: isTraced ? 6 : (isSelected ? 5 : 3),
                            color: color.withValues(
                              alpha: isTraced ? 0.98 : (isSelected ? 0.95 : 0.72),
                            ),
                          );
                        },
                      )
                      .toList(growable: false),
                ),
              MarkerLayer(
                markers: [
                  ...visibleEntities.map((entity) {
                    final color = _entityColor(entity.type);
                    final isPending = entity.key == _pendingStartEntityKey;
                    final isCandidate = _isEntityCandidateForCurrentStep(entity);
                    final isTraced = _highlightedEntityKeys.contains(entity.key);
                    final isDimmed =
                        _routeCreateMode &&
                        _pendingStartEntityKey != null &&
                        !isCandidate;
                    final borderColor = isPending
                        ? const Color(0xFFFFA629)
                        : isTraced
                            ? const Color(0xFFFFB347)
                        : isCandidate
                            ? color.withValues(alpha: 0.8)
                            : Colors.white24;
                    return Marker(
                      point: entity.point,
                      width: 46,
                      height: 46,
                      child: GestureDetector(
                        onTap: () => _handleEntityTapV2(entity),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isTraced
                                ? const Color(0xFFFFB347).withValues(alpha: 0.22)
                                : isDimmed
                                ? const Color(0xFF6B7280).withValues(alpha: 0.18)
                                : color.withValues(alpha: isCandidate ? 0.22 : 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: borderColor,
                              width: isPending ? 3 : 2,
                            ),
                            boxShadow: isPending ||
                                    isTraced ||
                                    (_routeCreateMode && isCandidate && !isDimmed)
                                ? [
                                    BoxShadow(
                                      color: (isPending
                                              ? const Color(0xFFFFA629)
                                              : isTraced
                                                  ? const Color(0xFFFFB347)
                                              : color)
                                          .withValues(alpha: 0.35),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : const [],
                          ),
                          child: Icon(
                            _entityIcon(entity.type),
                            color: isPending
                                ? const Color(0xFFFFA629)
                                : isTraced
                                    ? const Color(0xFFFFB347)
                                : isDimmed
                                    ? Colors.white38
                                    : (_routeCreateMode && isCandidate
                                        ? color.withValues(alpha: 0.95)
                                        : color),
                          ),
                        ),
                      ),
                    );
                  }),
                  ...dragMarkers,
                ],
              ),
            ],
          ),
        ),
        _buildLegendCard(),
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
        title: const Text('Карта инфраструктуры'),
        actions: [
          if (_activeTraceRequest != null)
            IconButton(
              tooltip: 'Очистить подсветку трассы',
              onPressed: _clearTraceHighlight,
              icon: const Icon(Icons.alt_route_rounded),
            ),
          IconButton(
            tooltip: _routeCreateMode
                ? 'Отменить создание маршрута'
                : 'Новый маршрут',
            onPressed: _loading || _syncingRoutes
                ? null
                : _toggleRouteCreateMode,
            icon: Icon(
              _routeCreateMode ? Icons.close_rounded : Icons.add_road_rounded,
            ),
          ),
          IconButton(
            tooltip: _routeEditMode
                ? 'Завершить редактирование маршрута'
                : 'Редактировать выбранный маршрут',
            onPressed: _loading || _syncingRoutes || _selectedRoute == null
                ? null
                : _toggleRouteEditMode,
            icon: Icon(
              _routeEditMode ? Icons.check_rounded : Icons.edit_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Удалить выбранный маршрут',
            onPressed: _loading || _syncingRoutes || _selectedRoute == null
                ? null
                : _deleteSelectedRoute,
            icon: const Icon(Icons.delete_outline_rounded),
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
          PopupMenuButton<String>(
            tooltip: 'Фильтр по задаче',
            icon: Icon(
              _projectFilterId == null
                  ? Icons.workspaces_outline
                  : Icons.workspaces_rounded,
            ),
            onSelected: _applyProjectFilter,
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: '__all_projects__',
                checked: _projectFilterId == null,
                child: const Text('Все задачи'),
              ),
              ..._projectOptions.entries.map(
                (entry) => CheckedPopupMenuItem<String>(
                  value: '${entry.key}',
                  checked: _projectFilterId == entry.key,
                  child: Text(entry.value),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading || _syncingRoutes ? null : _loadMapData,
            icon: _syncingRoutes
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }
}

/*
class _RoutePanelShell extends StatelessWidget {
  const _RoutePanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF071526),
        border: Border(top: BorderSide(color: Color(0xFF1D3F63))),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

*/
class _MapMetaRow extends StatelessWidget {
  const _MapMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}
