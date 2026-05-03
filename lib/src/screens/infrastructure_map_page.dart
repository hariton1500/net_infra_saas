import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_controller.dart';
import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/map_tile_providers.dart';
import '../core/project_scope.dart';
import '../widgets/responsive_app_bar_actions.dart';
import '../widgets/screen_instruction.dart';

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

class _EntityCluster {
  const _EntityCluster({
    required this.entities,
    required this.center,
    required this.dominantType,
  });

  final List<_InfrastructureEntity> entities;
  final LatLng center;
  final _InfrastructureEntityType dominantType;

  bool get isSingle => entities.length == 1;
}

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

class _RouteSplitTarget {
  const _RouteSplitTarget({required this.insertIndex, required this.point});

  final int insertIndex;
  final LatLng point;
}

class _RouteSplitDialogResult {
  const _RouteSplitDialogResult({
    required this.name,
    required this.comment,
    required this.fiberMap,
  });

  final String name;
  final String comment;
  final List<int?> fiberMap;
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
  const _TraceStep({required this.endpoint, this.color});

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
  static const _instructionDismissedKey =
      'infrastructure_map.instruction_dismissed.v1';
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
  bool _routeSplitMode = false;
  bool _legendExpanded = false;
  bool _showInstructionBanner = true;
  bool _showCableRoutes = true;
  bool _mapReady = false;
  Set<_InfrastructureEntityType> _visibleEntityTypes = {
    _InfrastructureEntityType.muff,
    _InfrastructureEntityType.ponBox,
    _InfrastructureEntityType.cabinet,
  };
  String? _errorMessage;
  double _mapZoom = 13;
  String _selectedTileLayerId = 'osm';
  List<Map<String, dynamic>> _muffRecords = const [];
  List<Map<String, dynamic>> _cabinetRecords = const [];
  final List<Map<String, dynamic>> _projectRecords = const [];
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
  Set<int> _inspectedEntityRouteIds = const {};

  @override
  void initState() {
    super.initState();
    _selectedRouteId = widget.initialRouteId;
    _activeTraceRequest = widget.initialTraceRequest;
    _syncRepository = CompanyModuleSyncRepository(
      client: widget.controller.client,
    );
    unawaited(_loadInstructionBannerPreference());
    _loadMapData();
  }

  String get _actorEmail => widget.controller.currentUser?.email?.trim() ?? '';

  String get _actorUserId => widget.controller.currentUser?.id ?? '';

  Future<void> _loadInstructionBannerPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _showInstructionBanner =
          !(prefs.getBool(_instructionDismissedKey) ?? false);
    });
  }

  Future<void> _dismissInstructionBanner() async {
    setState(() {
      _showInstructionBanner = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_instructionDismissedKey, true);
  }

  String? _projectNameFor(Map<String, dynamic> record) {
    final projectId = projectIdOf(record);
    if (projectId == null) {
      return null;
    }
    return _projectOptions[projectId];
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

  Future<void> _loadMapData() async {
    final companyId = widget.controller.membership?.companyId;
    _activeProject = await _syncRepository.readActiveProject();
    if (companyId == null) {
      setState(() {
        _loading = false;
        _errorMessage = 'Company was not found for the current user.';
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
      var projects = await _syncRepository.readCache(projectsCacheKey);
      var routes = await _syncRepository.readCache(_routesCacheKey);

      try {
        muffs = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: 'muff_notebook',
          localRecords: muffs,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Failed to refresh closures for the map.',
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
          'Failed to refresh cabinets for the map.',
          source: 'infrastructure_map.cabinets',
          error: error,
          stackTrace: stackTrace,
        );
      }

      try {
        projects = await _syncRepository.pullMerge(
          companyId: companyId,
          moduleKey: projectsModuleKey,
          localRecords: projects,
        );
      } catch (error, stackTrace) {
        logUserFacingError(
          'Failed to refresh map tasks.',
          source: 'infrastructure_map.projects',
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
          'Failed to refresh cable routes for the map.',
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
        'Failed to load infrastructure entities.',
        source: 'infrastructure_map.load',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Failed to load the infrastructure map.';
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
                : 'Untitled',
            location: (record['location'] as String?)?.trim() ?? '',
            point: LatLng(
              record['location_lat'] as double,
              record['location_lng'] as double,
            ),
            subtitle: isPonBox ? 'PON box' : 'Closure',
            meta: {
              if (_projectNameFor(record) != null)
                'Task': _projectNameFor(record)!,
              if (district.isNotEmpty) 'Area': district,
              'Cables': '${cables.length}',
              'Connections': '${connections.length}',
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
                : 'Untitled',
            location: (record['location'] as String?)?.trim() ?? '',
            point: LatLng(
              record['location_lat'] as double,
              record['location_lng'] as double,
            ),
            subtitle: 'Network cabinet',
            meta: {
              if (_projectNameFor(record) != null)
                'Task': _projectNameFor(record)!,
              'Switches': '${switches.length}',
              'Cables': '${cables.length}',
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
      name: name?.isNotEmpty == true ? name! : 'Cable line',
      points: points,
      lengthMeters: lengthMeters,
      meta: {
        if (_projectNameFor(record) != null) 'Task': _projectNameFor(record)!,
        'Length': _formatRouteLength(lengthMeters),
        'Points': '${points.length}',
        if (startAnchor != null) 'Start': startAnchor['name'] ?? 'Linked',
        if (endAnchor != null) 'End': endAnchor['name'] ?? 'Linked',
        if (note != null && note.isNotEmpty) 'Note': note,
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
      return '${kilometers.toStringAsFixed(kilometers >= 10 ? 1 : 2)} km';
    }
    return '${lengthMeters.toStringAsFixed(lengthMeters >= 100 ? 0 : 1)} m';
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
        ? 'Failed to build trace from port $portLabel.'
        : 'Trace from ${cabinet?.name ?? 'cabinet'} port $portLabel: objects ${result.entityKeys.length}, routes ${result.routeIds.length}.';

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

  _TraceResult? _buildTraceFromRequest(
    InfrastructureSignalTraceRequest request,
  ) {
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
            _TraceStep(endpoint: transition.endpoint, color: currentColor),
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
    final record = _recordByTypeAndId(
      endpoint.entityTypeCode,
      endpoint.entityId,
    );
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
      if (left != null &&
          right != null &&
          _traceEndpointEquals(left, endpoint)) {
        yield _TraceTransition(right);
      } else if (left != null &&
          right != null &&
          _traceEndpointEquals(right, endpoint)) {
        yield _TraceTransition(left);
      }
    }
  }

  Iterable<_TraceTransition> _traceMuffNeighbors(
    _TraceEndpoint endpoint,
  ) sync* {
    final record = _recordByTypeAndId(
      endpoint.entityTypeCode,
      endpoint.entityId,
    );
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
      if (left != null &&
          right != null &&
          _traceEndpointEquals(left, endpoint)) {
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
    final record = _recordByTypeAndId(
      endpoint.entityTypeCode,
      endpoint.entityId,
    );
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
    final cables = List<Map<String, dynamic>>.from(
      record['cables'] ?? const [],
    );
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
    final record = _recordByTypeAndId(
      endpoint.entityTypeCode,
      endpoint.entityId,
    );
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
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  List<_InfrastructureEntity> get _visibleEntities {
    final visible = _entities
        .where((entity) {
          final record = _entityRecord(entity);
          return record != null &&
              matchesProjectFilter(record, _projectFilterId) &&
              _visibleEntityTypes.contains(entity.type);
        })
        .toList(growable: false);
    if (!_routeCreateMode) {
      return visible;
    }

    if (_pendingStartEntityKey == null) {
      return _routeCandidateEntities
          .where((entity) => _visibleEntityTypes.contains(entity.type))
          .toList(growable: false);
    }

    return visible;
  }

  List<_CableRoute> get _filteredRoutesByProject => _showCableRoutes
      ? _routes
            .where((route) => matchesProjectFilter(route.raw, _projectFilterId))
            .toList(growable: false)
      : const [];

  Map<int, String> get _projectOptions {
    final options = <int, String>{};
    for (final project in _projectRecords) {
      if (project['deleted'] == true || project['archived'] == true) {
        continue;
      }
      final id = projectIdOf(project);
      final name = projectNameOf(project);
      if (id != null && name != null) {
        options[id] = name;
      }
    }
    return options;
  }

  List<_InfrastructureEntity> get _routeCandidateEntities {
    final visible = _entities
        .where((entity) {
          final record = _entityRecord(entity);
          return record != null &&
              matchesProjectFilter(record, _projectFilterId);
        })
        .toList(growable: false);
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

    return visible
        .where((entity) {
          if (entity.key == _pendingStartEntityKey) {
            return true;
          }
          return _freeCableChoicesForEntity(entity, fibers: fibers).isNotEmpty;
        })
        .toList(growable: false);
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

    final cables = List<Map<String, dynamic>>.from(
      record['cables'] ?? const [],
    );
    return cables
        .where((cable) {
          if (cable['deleted'] == true) {
            return false;
          }
          final cableFibers = (cable['fibers'] as int?) ?? 1;
          if (fibers != null && cableFibers != fibers) {
            return false;
          }
          return cable['route_id'] == null;
        })
        .map((cable) {
          final cableId = (cable['id'] as int?) ?? 0;
          final cableFibers = (cable['fibers'] as int?) ?? 1;
          final cableName = (cable['name'] as String?)?.trim();
          return _RouteCableChoice(
            entity: entity,
            cableId: cableId,
            cableName: cableName?.isNotEmpty == true
                ? cableName!
                : 'Cable #$cableId',
            fibers: cableFibers,
          );
        })
        .toList(growable: false);
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
                        subtitle: Text(
                          tr('Fibers: {value}', {'value': '${choice.fibers}'}),
                        ),
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
    final cables = List<Map<String, dynamic>>.from(
      record['cables'] ?? const [],
    );
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
    final cables = List<Map<String, dynamic>>.from(
      record['cables'] ?? const [],
    );
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

  bool _anchorMatchesEntity(
    Map<String, dynamic>? anchor,
    _InfrastructureEntity entity,
  ) {
    if (anchor == null) {
      return false;
    }
    return anchor['type'] == _entityTypeCode(entity.type) &&
        anchor['entity_id'] == entity.id;
  }

  List<_CableRoute> _routesForEntity(_InfrastructureEntity entity) {
    return _routes
        .where((route) {
          final startAnchor = _extractAnchor(route.raw['start_anchor']);
          final endAnchor = _extractAnchor(route.raw['end_anchor']);
          return _anchorMatchesEntity(startAnchor, entity) ||
              _anchorMatchesEntity(endAnchor, entity);
        })
        .toList(growable: false);
  }

  void _showEntitySheet(_InfrastructureEntity entity) {
    final relatedRoutes = _routesForEntity(entity);
    final metaSummary = entity.meta.entries
        .map((entry) => '${_metaLabel(entry.key)}: ${entry.value}')
        .join(' • ');
    setState(() {
      _inspectedEntityRouteIds = relatedRoutes.map((route) => route.id).toSet();
    });
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) {
        final initialSize = relatedRoutes.isEmpty ? 0.28 : 0.4;
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: initialSize,
            minChildSize: 0.24,
            maxChildSize: 0.72,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
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
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _entityChip(entity),
                          const SizedBox(height: 10),
                          Text(
                            entity.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (entity.location.isNotEmpty) entity.location,
                              '${entity.point.latitude.toStringAsFixed(6)}, ${entity.point.longitude.toStringAsFixed(6)}',
                            ].join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          if (metaSummary.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              metaSummary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 14)),
                    SliverToBoxAdapter(
                      child: Text(
                        relatedRoutes.isEmpty
                            ? tr('This object has no linked routes yet.')
                            : tr('Routes from this object'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 10)),
                    if (relatedRoutes.isEmpty)
                      SliverToBoxAdapter(
                        child: Text(
                          tr(
                            'The list is empty. When a route starts or ends at this object, it will appear here.',
                          ),
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
                          final endAnchor = _extractAnchor(
                            route.raw['end_anchor'],
                          );
                          final role = _anchorMatchesEntity(startAnchor, entity)
                              ? tr('Start')
                              : _anchorMatchesEntity(endAnchor, entity)
                              ? tr('End')
                              : tr('Route');

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
                              '$role • ${_formatRouteLength(route.lengthMeters)} • ${tr('Points: {count}', {'count': '${route.points.length}'})}',
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
    ).whenComplete(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _inspectedEntityRouteIds = const {};
      });
    });
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

  String _entityTypeLabel(_InfrastructureEntityType type) {
    switch (type) {
      case _InfrastructureEntityType.ponBox:
        return tr('PON boxes');
      case _InfrastructureEntityType.cabinet:
        return tr('Network cabinets');
      case _InfrastructureEntityType.muff:
        return tr('Closures');
    }
  }

  String _entitySubtitleLabel(_InfrastructureEntity entity) {
    return switch (entity.type) {
      _InfrastructureEntityType.ponBox => tr('PON box'),
      _InfrastructureEntityType.cabinet => tr('Network cabinet'),
      _InfrastructureEntityType.muff => tr('Closure'),
    };
  }

  String _metaLabel(String label) {
    return tr(label);
  }

  void _toggleEntityType(_InfrastructureEntityType type) {
    setState(() {
      final next = Set<_InfrastructureEntityType>.from(_visibleEntityTypes);
      if (next.contains(type)) {
        if (next.length == 1) {
          return;
        }
        next.remove(type);
      } else {
        next.add(type);
      }
      _visibleEntityTypes = next;
    });
  }

  bool get _shouldClusterEntities =>
      !_routeCreateMode && !_routeEditMode && !_routeSplitMode && _mapZoom < 16;

  bool get _useCompactEntityMarkers =>
      _mapZoom < 15 && !_routeCreateMode && !_routeEditMode && !_routeSplitMode;

  double get _clusterCellSize {
    if (_mapZoom < 13.5) {
      return 94;
    }
    if (_mapZoom < 15) {
      return 72;
    }
    return 58;
  }

  int _zoomDensityBand(double zoom) {
    if (zoom < 13.5) {
      return 0;
    }
    if (zoom < 15) {
      return 1;
    }
    if (zoom < 16) {
      return 2;
    }
    return 3;
  }

  void _handleMapPositionChanged(MapCamera position) {
    final previousBand = _zoomDensityBand(_mapZoom);
    final nextBand = _zoomDensityBand(position.zoom);
    if (previousBand == nextBand && (_mapZoom - position.zoom).abs() < 0.35) {
      _mapZoom = position.zoom;
      return;
    }
    setState(() {
      _mapZoom = position.zoom;
    });
  }

  _InfrastructureEntityType _dominantType(List<_InfrastructureEntity> items) {
    final counts = <_InfrastructureEntityType, int>{};
    for (final entity in items) {
      counts[entity.type] = (counts[entity.type] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<_EntityCluster> _entityClusters(List<_InfrastructureEntity> entities) {
    if (!_mapReady || !_shouldClusterEntities || entities.length < 2) {
      return entities
          .map(
            (entity) => _EntityCluster(
              entities: [entity],
              center: entity.point,
              dominantType: entity.type,
            ),
          )
          .toList(growable: false);
    }

    final camera = _mapController.camera;
    final cellSize = _clusterCellSize;
    final buckets = <String, List<_InfrastructureEntity>>{};
    for (final entity in entities) {
      final screenPoint = camera.latLngToScreenPoint(entity.point);
      final x = (screenPoint.x / cellSize).floor();
      final y = (screenPoint.y / cellSize).floor();
      (buckets['$x:$y'] ??= []).add(entity);
    }

    return buckets.values
        .map((items) {
          final latitude =
              items.fold<double>(
                0,
                (sum, entity) => sum + entity.point.latitude,
              ) /
              items.length;
          final longitude =
              items.fold<double>(
                0,
                (sum, entity) => sum + entity.point.longitude,
              ) /
              items.length;
          return _EntityCluster(
            entities: List<_InfrastructureEntity>.unmodifiable(items),
            center: LatLng(latitude, longitude),
            dominantType: _dominantType(items),
          );
        })
        .toList(growable: false);
  }

  void _focusCluster(_EntityCluster cluster) {
    if (cluster.isSingle) {
      _handleEntityTapV2(cluster.entities.first);
      return;
    }

    final bounds = LatLngBounds.fromPoints(
      cluster.entities.map((entity) => entity.point).toList(growable: false),
    );
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(72)),
    );
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
          Text(_entitySubtitleLabel(entity), style: TextStyle(color: color)),
        ],
      ),
    );
  }

  void _selectRoute(_CableRoute route, {bool focus = true}) {
    setState(() {
      _selectedRouteId = route.id;
      _routeCreateMode = false;
      _routeSplitMode = false;
      _pendingStartEntityKey = null;
      _pendingStartCableId = null;
      _pendingRequiredFibers = null;
    });
    if (focus) {
      _mapController.move(route.points.first, _mapZoom < 15 ? 15 : _mapZoom);
    }
  }

  void _clearSelectedRoute() {
    setState(() {
      _selectedRouteId = null;
      _routeEditMode = false;
      _routeSplitMode = false;
      _pendingStartEntityKey = null;
      _pendingStartCableId = null;
      _pendingRequiredFibers = null;
    });
  }

  void _toggleRouteCreateMode() {
    setState(() {
      _routeCreateMode = !_routeCreateMode;
      _routeEditMode = false;
      _routeSplitMode = false;
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
      _routeSplitMode = false;
      _pendingStartEntityKey = null;
      _pendingStartCableId = null;
      _pendingRequiredFibers = null;
    });
  }

  void _toggleRouteSplitMode() {
    if (_selectedRoute == null) {
      return;
    }
    setState(() {
      _routeSplitMode = !_routeSplitMode;
      _routeCreateMode = false;
      _routeEditMode = false;
      _pendingStartEntityKey = null;
      _pendingStartCableId = null;
      _pendingRequiredFibers = null;
    });
    if (_routeSplitMode) {
      _showSnackBar(
        tr('Tap the selected route where the closure must be installed.'),
      );
    }
  }

  void handleEntityTapLegacy(_InfrastructureEntity entity) {
    if (_routeCreateMode) {
      if (_pendingStartEntityKey == null) {
        setState(() {
          _pendingStartEntityKey = entity.key;
        });
        _showSnackBar(tr('Start selected. Now choose the route end.'));
        return;
      }

      if (_pendingStartEntityKey == entity.key) {
        _showSnackBar('The route start and end must be different.');
        return;
      }

      final start = _entityByKey(_pendingStartEntityKey);
      if (start == null) {
        _showSnackBar('Failed to find the route start point.');
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
            title: tr('Select a free cable for the route start'),
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
            tr(
              'Start and cable selected. Now choose an object with the same fiber count.',
            ),
          );
        }());
        return;
      }

      if (_pendingStartEntityKey == entity.key) {
        _showSnackBar(tr('The route start and end must be different.'));
        return;
      }

      final start = _entityByKey(_pendingStartEntityKey);
      if (start == null) {
        _showSnackBar(tr('Failed to find the route start point.'));
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
        _showSnackBar(tr('Select the start cable first.'));
        return;
      }

      _RouteCableChoice? startCable;
      for (final choice in _freeCableChoicesForEntity(
        start,
        fibers: requiredFibers,
      )) {
        if (choice.cableId == startCableId) {
          startCable = choice;
          break;
        }
      }
      if (startCable == null) {
        _showSnackBar(
          tr(
            'The start cable is no longer available. Select the route start again.',
          ),
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
          tr('This object has no free cables with {count} fibers.', {
            'count': '$requiredFibers',
          }),
        );
        return;
      }

      unawaited(() async {
        final endCable = await _pickCableForEntity(
          entity,
          title: tr('Select a free cable for the route end'),
          fibers: requiredFibers,
        );
        if (endCable == null) {
          return;
        }
        await _createRouteBetweenWithBindings(
          start,
          entity,
          startCable!,
          endCable,
        );
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
      kind: 'Route added',
      summary: [
        routeRecord['name']?.toString() ?? 'Route',
        if ((start.location).trim().isNotEmpty) 'start: ${start.location}',
        if ((end.location).trim().isNotEmpty) 'end: ${end.location}',
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
    _showSnackBar('Route created. Tap a segment to add a point.');
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
      _showSnackBar('Failed to find object records for cable bindings.');
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
      kind: 'Route added',
      summary: [
        routeRecord['name']?.toString() ?? 'Route',
        'start cable: ${startCable.cableName} (${startCable.fibers} fibers)',
        'end cable: ${endCable.cableName} (${endCable.fibers} fibers)',
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
    _showSnackBar('Route and cable bindings have been created.');
  }

  int _nextMuffId(List<Map<String, dynamic>> records) {
    var maxId = 0;
    for (final record in records) {
      final id = record['id'];
      if (id is int && id > maxId) {
        maxId = id;
      } else if (id is num && id.toInt() > maxId) {
        maxId = id.toInt();
      }
    }
    return maxId + 1;
  }

  Map<String, dynamic> _anchorForMuffRecord(Map<String, dynamic> muff) {
    return {
      'type': 'muff',
      'entity_id': muff['id'],
      'name': muff['name'],
      'subtitle': 'Closure',
      'location': muff['location'] ?? '',
      'lat': muff['location_lat'],
      'lng': muff['location_lng'],
    };
  }

  List<Map<String, double>> _routePointMaps(List<LatLng> points) {
    return points
        .map(
          (point) => <String, double>{
            'lat': point.latitude,
            'lng': point.longitude,
          },
        )
        .toList(growable: false);
  }

  String _anchorTitle(Map<String, dynamic>? anchor) {
    final name = (anchor?['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return tr('Linked object');
  }

  int? _anchorEntityId(Map<String, dynamic>? anchor) =>
      anchor?['entity_id'] as int?;

  Future<void> _confirmAndSplitSelectedRoute(_RouteSplitTarget target) async {
    final route = _selectedRoute;
    if (route == null || _syncingRoutes) {
      return;
    }

    final startAnchor = _extractAnchor(route.raw['start_anchor']);
    final endAnchor = _extractAnchor(route.raw['end_anchor']);
    final startCable = _extractAnchor(route.raw['start_cable']);
    final endCable = _extractAnchor(route.raw['end_cable']);
    final startCableId = startCable?['id'] as int?;
    final endCableId = endCable?['id'] as int?;
    final fibers = startCable?['fibers'] as int?;
    final endFibers = endCable?['fibers'] as int?;
    if (startAnchor == null ||
        endAnchor == null ||
        startCableId == null ||
        endCableId == null ||
        fibers == null ||
        endFibers == null) {
      _showSnackBar(
        tr(
          'This route has no cable bindings. Create or relink the route first.',
        ),
      );
      return;
    }
    if (fibers != endFibers) {
      _showSnackBar(
        tr('The route endpoint cables have different fiber counts.'),
      );
      return;
    }
    if (target.insertIndex <= 0 || target.insertIndex >= route.points.length) {
      _showSnackBar(tr('Select a point between the route endpoints.'));
      return;
    }

    final boundStartCable = startCable!;
    final boundEndCable = endCable!;
    final startEntityId = _anchorEntityId(startAnchor);
    final endEntityId = _anchorEntityId(endAnchor);
    final startEntityType = startAnchor['type'] as String?;
    final endEntityType = endAnchor['type'] as String?;
    if (startEntityId == null ||
        endEntityId == null ||
        startEntityType == null ||
        endEntityType == null) {
      _showSnackBar(tr('Failed to read route endpoint anchors.'));
      return;
    }

    final startName = _anchorTitle(startAnchor);
    final endName = _anchorTitle(endAnchor);
    final muffId = _nextMuffId(_muffRecords);
    final suggestedName = 'M-$muffId';
    final now = DateTime.now();
    final comment = [
      'Automatically created when marking the break point of route "${route.name}" #${route.id}.',
      'Original route: $startName -> $endName.',
      'After installing the closure, route #${route.id} was changed to $startName -> $suggestedName, and a new route was created: $suggestedName -> $endName.',
      'Operation date: ${now.toIso8601String()}.',
    ].join('\n');

    final result = await _showRouteSplitConfirmationDialog(
      route: route,
      splitPoint: target.point,
      muffName: suggestedName,
      comment: comment,
      fibers: fibers,
      startCableName: (boundStartCable['name'] as String?) ?? tr('Cable'),
      endCableName: (boundEndCable['name'] as String?) ?? tr('Cable'),
    );
    if (result == null || !mounted) {
      return;
    }

    await _splitSelectedRouteAt(
      route: route,
      target: target,
      muffId: muffId,
      muffName: result.name,
      comment: result.comment,
      fiberMap: result.fiberMap,
      startAnchor: startAnchor,
      endAnchor: endAnchor,
      startCable: boundStartCable,
      endCable: boundEndCable,
      startEntityType: startEntityType,
      endEntityType: endEntityType,
      startEntityId: startEntityId,
      endEntityId: endEntityId,
      fibers: fibers,
    );
  }

  Future<_RouteSplitDialogResult?> _showRouteSplitConfirmationDialog({
    required _CableRoute route,
    required LatLng splitPoint,
    required String muffName,
    required String comment,
    required int fibers,
    required String startCableName,
    required String endCableName,
  }) async {
    final nameController = TextEditingController(text: muffName);
    final commentController = TextEditingController(text: comment);
    final fiberMap = List<int?>.generate(fibers, (index) => index);
    String? errorText;

    final result = await showDialog<_RouteSplitDialogResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final usedOutputs = <int>{};
            var hasDuplicate = false;
            for (final output in fiberMap.whereType<int>()) {
              if (!usedOutputs.add(output)) {
                hasDuplicate = true;
              }
            }

            return AlertDialog(
              title: Text(tr('Install closure on route')),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: tr('Closure name'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${route.name}\n${splitPoint.latitude.toStringAsFixed(6)}, ${splitPoint.longitude.toStringAsFixed(6)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commentController,
                        decoration: InputDecoration(labelText: tr('Comment')),
                        minLines: 3,
                        maxLines: 6,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr('Fiber connections'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (var index = 0; index < fibers; index++) ...[
                        Row(
                          children: [
                            Text(
                              '${tr('fiber')} ${index + 1}',
                              //'$startCableName ${tr('fiber')} ${index + 1}',
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<int?>(
                                initialValue: fiberMap[index],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(tr('Not connected')),
                                  ),
                                  ...List.generate(
                                    fibers,
                                    (fiberIndex) => DropdownMenuItem<int?>(
                                      value: fiberIndex,
                                      child: Text(
                                        '$endCableName ${fiberIndex + 1}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setStateDialog(() {
                                    fiberMap[index] = value;
                                    errorText = null;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (errorText != null || hasDuplicate) ...[
                        const SizedBox(height: 4),
                        Text(
                          errorText ??
                              tr(
                                'One output fiber is selected more than once.',
                              ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setStateDialog(() {
                        errorText = tr('Enter a closure name.');
                      });
                      return;
                    }
                    if (hasDuplicate) {
                      setStateDialog(() {
                        errorText = tr(
                          'One output fiber is selected more than once.',
                        );
                      });
                      return;
                    }
                    Navigator.of(context).pop(
                      _RouteSplitDialogResult(
                        name: name,
                        comment: commentController.text.trim(),
                        fiberMap: List<int?>.from(fiberMap),
                      ),
                    );
                  },
                  icon: const Icon(Icons.call_split_rounded),
                  label: Text(tr('Confirm')),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    commentController.dispose();
    return result;
  }

  Future<void> _splitSelectedRouteAt({
    required _CableRoute route,
    required _RouteSplitTarget target,
    required int muffId,
    required String muffName,
    required String comment,
    required List<int?> fiberMap,
    required Map<String, dynamic> startAnchor,
    required Map<String, dynamic> endAnchor,
    required Map<String, dynamic> startCable,
    required Map<String, dynamic> endCable,
    required String startEntityType,
    required String endEntityType,
    required int startEntityId,
    required int endEntityId,
    required int fibers,
  }) async {
    final now = DateTime.now();
    final newRouteId = _nextRouteId();
    final muffAnchorName = muffName.trim().isEmpty
        ? 'M-$muffId'
        : muffName.trim();
    final muffRecord = <String, dynamic>{
      'id': muffId,
      'name': muffAnchorName,
      'district': '',
      'location': '',
      'comment': comment,
      'is_pon_box': false,
      'location_lat': target.point.latitude,
      'location_lng': target.point.longitude,
      'updated_at': now,
      'updated_by': _actorEmail,
      'created_by': _actorEmail,
      'deleted': false,
      'dirty': true,
      'splitters': <Map<String, dynamic>>[],
      'cables': [
        {
          'id': 1,
          'name': '${route.name} / ${_anchorTitle(startAnchor)}',
          'fibers': fibers,
          'side': 0,
          'color_scheme': (startCable['color_scheme'] as String?) ?? 'default',
          'fiber_comments': List<String>.filled(fibers, ''),
        },
        {
          'id': 2,
          'name': '${route.name} / ${_anchorTitle(endAnchor)}',
          'fibers': fibers,
          'side': 1,
          'color_scheme': (endCable['color_scheme'] as String?) ?? 'default',
          'fiber_comments': List<String>.filled(fibers, ''),
        },
      ],
      'connections': [
        for (var index = 0; index < fiberMap.length; index++)
          if (fiberMap[index] != null)
            {
              'id': index + 1,
              'endpoint1': {'type': 'cable', 'cableId': 1, 'fiberIndex': index},
              'endpoint2': {
                'type': 'cable',
                'cableId': 2,
                'fiberIndex': fiberMap[index],
              },
            },
      ],
    };
    applyProjectSelection(muffRecord, _activeProject);
    final muffAnchor = _anchorForMuffRecord(muffRecord);

    final firstPoints = [
      ...route.points.take(target.insertIndex),
      target.point,
    ];
    final secondPoints = [
      target.point,
      ...route.points.skip(target.insertIndex),
    ];

    final nextRouteRecords = _routeRecords
        .map((record) => _syncRepository.clone(record))
        .toList(growable: true);
    final routeIndex = nextRouteRecords.indexWhere(
      (record) => record['id'] == route.id,
    );
    if (routeIndex == -1) {
      _showSnackBar(tr('Failed to find the selected route record.'));
      return;
    }

    final updatedOldRoute = _syncRepository.clone(nextRouteRecords[routeIndex]);
    updatedOldRoute['name'] = '${_anchorTitle(startAnchor)} - $muffAnchorName';
    updatedOldRoute['end_anchor'] = muffAnchor;
    updatedOldRoute['end_cable'] = {
      'id': 1,
      'name': '${route.name} / ${_anchorTitle(startAnchor)}',
      'fibers': fibers,
    };
    updatedOldRoute['route_points'] = _routePointMaps(firstPoints);
    updatedOldRoute['updated_at'] = now;
    updatedOldRoute['dirty'] = true;
    nextRouteRecords[routeIndex] = updatedOldRoute;

    final newRouteRecord = <String, dynamic>{
      'id': newRouteId,
      'name': '$muffAnchorName - ${_anchorTitle(endAnchor)}',
      'note': route.raw['note'] ?? '',
      'start_anchor': muffAnchor,
      'end_anchor': endAnchor,
      'start_cable': {
        'id': 2,
        'name': '${route.name} / ${_anchorTitle(endAnchor)}',
        'fibers': fibers,
      },
      'end_cable': endCable,
      'route_points': _routePointMaps(secondPoints),
      'updated_at': now,
      'dirty': true,
      'deleted': false,
    };
    applyProjectSelection(newRouteRecord, _activeProject);
    nextRouteRecords.add(newRouteRecord);

    final nextMuffRecords =
        _muffRecords
            .map((record) => _syncRepository.clone(record))
            .toList(growable: true)
          ..add(muffRecord);
    final nextCabinetRecords = _cabinetRecords
        .map((record) => _syncRepository.clone(record))
        .toList(growable: true);

    void updateEndpointCable({
      required String entityType,
      required int entityId,
      required int cableId,
      required int routeId,
      required Map<String, dynamic> peerAnchor,
      required int peerCableId,
      required String role,
    }) {
      final records = entityType == 'cabinet'
          ? nextCabinetRecords
          : nextMuffRecords;
      final index = records.indexWhere((record) => record['id'] == entityId);
      if (index == -1) {
        return;
      }
      final record = _syncRepository.clone(records[index]);
      final cables = List<Map<String, dynamic>>.from(
        record['cables'] ?? const [],
      );
      final cableIndex = cables.indexWhere((cable) => cable['id'] == cableId);
      if (cableIndex == -1) {
        return;
      }
      final cable = Map<String, dynamic>.from(cables[cableIndex]);
      cable['route_id'] = routeId;
      cable['route_role'] = role;
      cable['peer_entity_type'] = peerAnchor['type'];
      cable['peer_entity_id'] = peerAnchor['entity_id'];
      cable['peer_entity_name'] = peerAnchor['name'];
      cable['peer_cable_id'] = peerCableId;
      cable['peer_cable_name'] = peerCableId == 1
          ? '${route.name} / ${_anchorTitle(startAnchor)}'
          : '${route.name} / ${_anchorTitle(endAnchor)}';
      cables[cableIndex] = cable;
      record['cables'] = cables;
      _touchRecord(record);
      records[index] = record;
    }

    void updateMuffCable({
      required int cableId,
      required int routeId,
      required Map<String, dynamic> peerAnchor,
      required Map<String, dynamic> peerCable,
      required String role,
    }) {
      final index = nextMuffRecords.indexWhere(
        (record) => record['id'] == muffId,
      );
      if (index == -1) {
        return;
      }
      final record = _syncRepository.clone(nextMuffRecords[index]);
      final cables = List<Map<String, dynamic>>.from(
        record['cables'] ?? const [],
      );
      final cableIndex = cables.indexWhere((cable) => cable['id'] == cableId);
      if (cableIndex == -1) {
        return;
      }
      final cable = Map<String, dynamic>.from(cables[cableIndex]);
      cable['route_id'] = routeId;
      cable['route_role'] = role;
      cable['peer_entity_type'] = peerAnchor['type'];
      cable['peer_entity_id'] = peerAnchor['entity_id'];
      cable['peer_entity_name'] = peerAnchor['name'];
      cable['peer_cable_id'] = peerCable['id'];
      cable['peer_cable_name'] = peerCable['name'];
      cables[cableIndex] = cable;
      record['cables'] = cables;
      _touchRecord(record);
      nextMuffRecords[index] = record;
    }

    updateEndpointCable(
      entityType: startEntityType,
      entityId: startEntityId,
      cableId: startCable['id'] as int,
      routeId: route.id,
      peerAnchor: muffAnchor,
      peerCableId: 1,
      role: 'start',
    );
    updateEndpointCable(
      entityType: endEntityType,
      entityId: endEntityId,
      cableId: endCable['id'] as int,
      routeId: newRouteId,
      peerAnchor: muffAnchor,
      peerCableId: 2,
      role: 'end',
    );
    updateMuffCable(
      cableId: 1,
      routeId: route.id,
      peerAnchor: startAnchor,
      peerCable: startCable,
      role: 'end',
    );
    updateMuffCable(
      cableId: 2,
      routeId: newRouteId,
      peerAnchor: endAnchor,
      peerCable: endCable,
      role: 'start',
    );

    await _persistAllRecords(
      nextRouteRecords: nextRouteRecords,
      nextMuffRecords: nextMuffRecords,
      nextCabinetRecords: nextCabinetRecords,
      selectedRouteId: newRouteId,
      preserveModes: false,
    );
    await _recordTaskAddition(
      kind: 'Route split by closure',
      summary:
          '${route.name} -> $muffAnchorName (${fiberMap.whereType<int>().length}/$fibers splices)',
      targetRecordId: muffId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _routeSplitMode = false;
      _routeEditMode = true;
      _selectedRouteId = newRouteId;
    });
    _showSnackBar(tr('Closure installed and route split.'));
  }

  Future<void> _deleteSelectedRoute() async {
    final route = _selectedRoute;
    if (route == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete route')),
        content: Text(
          tr('Route "{name}" will be deleted.', {'name': route.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
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

    void unbindFromEntity(
      Map<String, dynamic>? anchor,
      Map<String, dynamic>? cable,
    ) {
      if (anchor == null || cable == null) {
        return;
      }
      final entityId = anchor['entity_id'] as int?;
      final cableId = cable['id'] as int?;
      if (entityId == null || cableId == null) {
        return;
      }
      final entityType = anchor['type'];
      final records =
          entityType == _entityTypeCode(_InfrastructureEntityType.cabinet)
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
      await _refreshActiveProject();
      _hydrateDirtyRouteRecordsWithActiveProject(nextRecords);
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
          _routeSplitMode = false;
          _pendingStartEntityKey = null;
          _pendingStartCableId = null;
          _pendingRequiredFibers = null;
        }
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Failed to save the cable route.',
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
      _showSnackBar('Failed to save the route.');
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
      await _refreshActiveProject();
      _hydrateDirtyRouteRecordsWithActiveProject(routes);
      _hydrateDirtyEntityRecordsWithActiveProject(muffs);
      _hydrateDirtyEntityRecordsWithActiveProject(cabinets);
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
          _routeSplitMode = false;
          _pendingStartEntityKey = null;
          _pendingStartCableId = null;
          _pendingRequiredFibers = null;
        }
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Failed to save the route and cable bindings.',
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
      _showSnackBar('Failed to save the route and bindings.');
    }
  }

  Future<void> _refreshActiveProject() async {
    _activeProject = await _syncRepository.readActiveProject();
  }

  void _hydrateDirtyRouteRecordsWithActiveProject(
    List<Map<String, dynamic>> records,
  ) {
    final activeProject = _activeProject;
    if (activeProject == null) {
      return;
    }

    for (final record in records) {
      if (record['dirty'] == true && projectIdOf(record) == null) {
        applyProjectSelection(record, activeProject);
      }
    }
  }

  void _hydrateDirtyEntityRecordsWithActiveProject(
    List<Map<String, dynamic>> records,
  ) {
    final activeProject = _activeProject;
    if (activeProject == null) {
      return;
    }

    for (final record in records) {
      if (record['dirty'] == true && projectIdOf(record) == null) {
        applyProjectSelection(record, activeProject);
      }
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
    return _routeSplitTargetForTap(route, tapOffset)?.insertIndex;
  }

  _RouteSplitTarget? _routeSplitTargetForTap(
    _CableRoute route,
    Offset tapOffset,
  ) {
    var bestDistance = double.infinity;
    int? bestIndex;
    LatLng? bestPoint;

    for (var i = 0; i < route.points.length - 1; i++) {
      final start = _mapController.camera.latLngToScreenPoint(route.points[i]);
      final end = _mapController.camera.latLngToScreenPoint(
        route.points[i + 1],
      );
      final projected = _projectPointToSegment(
        tapOffset,
        Offset(start.x, start.y),
        Offset(end.x, end.y),
      );
      final distance = _distanceToSegment(
        tapOffset,
        Offset(start.x, start.y),
        Offset(end.x, end.y),
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i + 1;
        bestPoint = _mapController.camera.pointToLatLng(
          math.Point<double>(projected.dx, projected.dy),
        );
      }
    }

    if (bestDistance > 18 || bestIndex == null || bestPoint == null) {
      return null;
    }
    return _RouteSplitTarget(insertIndex: bestIndex, point: bestPoint);
  }

  double _routeDistanceToTap(_CableRoute route, Offset tapOffset) {
    var bestDistance = double.infinity;
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
      }
    }
    return bestDistance;
  }

  _CableRoute? _routeForTap(Offset tapOffset) {
    const tapTolerance = 18.0;
    _CableRoute? bestRoute;
    var bestDistance = double.infinity;

    for (final route in _filteredRoutesByProject) {
      if (route.points.length < 2) {
        continue;
      }
      final distance = _routeDistanceToTap(route, tapOffset);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestRoute = route;
      }
    }

    if (bestDistance > tapTolerance) {
      return null;
    }
    return bestRoute;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    return (p - _projectPointToSegment(p, a, b)).distance;
  }

  Offset _projectPointToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) {
      return a;
    }

    final t =
        (((p.dx - a.dx) * dx) + ((p.dy - a.dy) * dy)) / ((dx * dx) + (dy * dy));
    final clamped = t.clamp(0.0, 1.0);
    return Offset(a.dx + dx * clamped, a.dy + dy * clamped);
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    final relative = tapPosition.relative;
    if (relative == null) {
      return;
    }

    final route = _selectedRoute;
    if (_routeSplitMode) {
      if (route == null) {
        return;
      }
      final target = _routeSplitTargetForTap(route, relative);
      if (target == null) {
        _showSnackBar(tr('Tap closer to the selected route line.'));
        return;
      }
      unawaited(_confirmAndSplitSelectedRoute(target));
      return;
    }

    if (!_routeEditMode) {
      final tappedRoute = _routeForTap(relative);
      if (tappedRoute != null) {
        if (tappedRoute.id == _selectedRouteId) {
          _clearSelectedRoute();
        } else {
          _selectRoute(tappedRoute, focus: false);
        }
      }
      return;
    }

    if (route == null) {
      return;
    }
    final insertIndex = _segmentInsertIndexForTap(route, relative);
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _legendExpanded
              ? ConstrainedBox(
                  key: const ValueKey('expanded-map-legend'),
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.layers_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  tr('Map legend'),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                tooltip: tr('Hide map legend'),
                                onPressed: () {
                                  setState(() {
                                    _legendExpanded = false;
                                  });
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _LegendRow(
                            color: _entityColor(_InfrastructureEntityType.muff),
                            icon: _entityIcon(_InfrastructureEntityType.muff),
                            label: tr('Closures'),
                          ),
                          const SizedBox(height: 8),
                          _LegendRow(
                            color: _entityColor(
                              _InfrastructureEntityType.ponBox,
                            ),
                            icon: _entityIcon(_InfrastructureEntityType.ponBox),
                            label: tr('PON boxes'),
                          ),
                          const SizedBox(height: 8),
                          _LegendRow(
                            color: _entityColor(
                              _InfrastructureEntityType.cabinet,
                            ),
                            icon: _entityIcon(
                              _InfrastructureEntityType.cabinet,
                            ),
                            label: tr('Network cabinets'),
                          ),
                          const SizedBox(height: 8),
                          _LegendRow(
                            color: const Color(0xFF1EDDC5),
                            icon: Icons.timeline_rounded,
                            label: tr('Cable routes'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr('Show on map'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final type
                                  in _InfrastructureEntityType.values)
                                FilterChip(
                                  selected: _visibleEntityTypes.contains(type),
                                  avatar: Icon(
                                    _entityIcon(type),
                                    size: 16,
                                    color: _entityColor(type),
                                  ),
                                  label: Text(_entityTypeLabel(type)),
                                  onSelected: (_) => _toggleEntityType(type),
                                ),
                              FilterChip(
                                selected: _showCableRoutes,
                                avatar: const Icon(
                                  Icons.timeline_rounded,
                                  size: 16,
                                  color: Color(0xFF1EDDC5),
                                ),
                                label: Text(tr('Routes')),
                                onSelected: (selected) {
                                  setState(() {
                                    _showCableRoutes = selected;
                                  });
                                },
                              ),
                            ],
                          ),
                          if (_routeCreateMode ||
                              _routeEditMode ||
                              _routeSplitMode ||
                              _traceSummary != null ||
                              (_routeEditMode && selectedRoute != null))
                            const SizedBox(height: 12),
                          if (_routeCreateMode)
                            Text(
                              _pendingStartEntityKey == null
                                  ? tr(
                                      'Select the route start from a closure or cabinet.',
                                    )
                                  : tr('Now choose the route end.'),
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          else if (_routeSplitMode && _selectedRoute != null)
                            Text(
                              tr(
                                'Tap the selected route where the closure must be installed.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          else if (_routeEditMode && _selectedRoute != null)
                            Text(
                              tr(
                                'Tap near the line to insert a point. Intermediate points can be dragged.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (_routeEditMode && selectedRoute != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                tr('Route length: {value}', {
                                  'value': _formatRouteLength(
                                    selectedRoute.lengthMeters,
                                  ),
                                }),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          if (_traceSummary != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFB347,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFB347,
                                  ).withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                _traceSummary!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            tr('Points: {points} • Routes: {routes}', {
                              'points': '${_entities.length}',
                              'routes': '${_routes.length}',
                            }),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : FloatingActionButton.small(
                  key: const ValueKey('collapsed-map-legend'),
                  heroTag: 'infrastructure-map-legend',
                  tooltip: tr('Show map legend'),
                  onPressed: () {
                    setState(() {
                      _legendExpanded = true;
                    });
                  },
                  child: const Icon(Icons.layers_outlined),
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
                        'Active',
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
                  'There are no routes yet. Press "+" and select the start first, then the end from existing closures or cabinets.',
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
                            'Routes',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text(
                            '${filteredRoutes.length} of ${_routes.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _routeSearchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: tr(
                            'Search by name, start, end, or note',
                          ),
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _routeSearchQuery.trim().isEmpty
                              ? null
                              : IconButton(
                                  tooltip: tr('Clear search'),
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
                          'Selected route',
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
                        'No routes match this search.',
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
              'There are no routes yet. Press "+" and select the start first, then the end from existing closures or cabinets.',
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
  Marker _buildEntityMarker(_InfrastructureEntity entity) {
    final color = _entityColor(entity.type);
    final isPending = entity.key == _pendingStartEntityKey;
    final isCandidate = _isEntityCandidateForCurrentStep(entity);
    final isTraced = _highlightedEntityKeys.contains(entity.key);
    final isDimmed =
        _routeCreateMode && _pendingStartEntityKey != null && !isCandidate;
    final compact = _useCompactEntityMarkers && !isPending && !isTraced;
    final size = compact ? 30.0 : 46.0;
    final borderColor = isPending
        ? const Color(0xFFFFA629)
        : isTraced
        ? const Color(0xFFFFB347)
        : isCandidate
        ? color.withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: compact ? 0.72 : 0.45);
    final fillColor = isTraced
        ? const Color(0xFFFFB347).withValues(alpha: 0.34)
        : isDimmed
        ? const Color(0xFF6B7280).withValues(alpha: 0.2)
        : color.withValues(alpha: compact ? 0.72 : (isCandidate ? 0.28 : 0.2));

    return Marker(
      point: entity.point,
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => _handleEntityTapV2(entity),
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: borderColor,
              width: isPending || isTraced ? 3 : (compact ? 1.5 : 2),
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (isPending
                            ? const Color(0xFFFFA629)
                            : isTraced
                            ? const Color(0xFFFFB347)
                            : color)
                        .withValues(alpha: compact ? 0.22 : 0.32),
                blurRadius: compact ? 8 : 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            _entityIcon(entity.type),
            size: compact ? 15 : 24,
            color: isPending
                ? const Color(0xFFFFA629)
                : isTraced
                ? const Color(0xFFFFB347)
                : isDimmed
                ? Colors.white38
                : (_routeCreateMode && isCandidate ? color : Colors.white),
          ),
        ),
      ),
    );
  }

  Marker _buildClusterMarker(_EntityCluster cluster) {
    if (cluster.isSingle) {
      return _buildEntityMarker(cluster.entities.first);
    }

    final color = _entityColor(cluster.dominantType);
    final count = cluster.entities.length;
    final size = math.min(64.0, 42.0 + count.toString().length * 7);

    return Marker(
      point: cluster.center,
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => _focusCluster(cluster),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
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

    final visibleRoutes = _filteredRoutesByProject;
    final visibleEntities = _visibleEntities;
    if (visibleEntities.isEmpty && visibleRoutes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'There are no mapped entities with coordinates or cable routes yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final center = visibleEntities.isNotEmpty
        ? visibleEntities.first.point
        : visibleRoutes.first.points.first;
    final entityClusters = _entityClusters(visibleEntities);
    final displayRoutes = visibleRoutes
        .where(
          (route) =>
              _mapZoom >= 12.5 ||
              route.id == _selectedRouteId ||
              _highlightedRouteIds.contains(route.id),
        )
        .toList(growable: false);
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
              onMapReady: () {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _mapReady = true;
                });
              },
              onTap: _handleMapTap,
              onPositionChanged: (position, _) =>
                  _handleMapPositionChanged(position),
            ),
            children: [
              tileLayerById(_selectedTileLayerId),
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: const Color(0xFF071526).withValues(alpha: 0.12),
                  ),
                ),
              ),
              if (displayRoutes.isNotEmpty)
                PolylineLayer(
                  polylines: displayRoutes
                      .map((route) {
                        final isSelected = route.id == _selectedRouteId;
                        final isTraced = _highlightedRouteIds.contains(
                          route.id,
                        );
                        final isRelatedToInspectedEntity =
                            _inspectedEntityRouteIds.contains(route.id);
                        final hasInspectedEntityRoutes =
                            _inspectedEntityRouteIds.isNotEmpty;
                        final traceColor = _highlightedRouteColors[route.id];
                        final color = isTraced
                            ? (traceColor ?? const Color(0xFFFFB347))
                            : isSelected
                            ? const Color(0xFF1EDDC5)
                            : isRelatedToInspectedEntity
                            ? const Color(0xFFFFB347)
                            : const Color(0xFF60A5FA);
                        return Polyline(
                          points: route.points,
                          strokeWidth: isTraced
                              ? 6
                              : (isSelected || isRelatedToInspectedEntity
                                    ? 5
                                    : (_mapZoom < 14 ? 2.5 : 3)),
                          color: color.withValues(
                            alpha: isTraced
                                ? 0.98
                                : (isSelected
                                      ? 0.95
                                      : isRelatedToInspectedEntity
                                      ? 0.9
                                      : hasInspectedEntityRoutes
                                      ? 0.22
                                      : (_mapZoom < 14 ? 0.48 : 0.68)),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              MarkerLayer(
                markers: [
                  ...entityClusters.map(_buildClusterMarker),
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

  Widget _buildActiveProjectBanner() {
    final activeProject = _activeProject;
    final hasActiveProject =
        activeProject != null && activeProject.name.trim().isNotEmpty;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: hasActiveProject
            ? const Color(0xFF123524)
            : theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: hasActiveProject
                ? const Color(0xFF35C886)
                : theme.dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasActiveProject
                ? Icons.task_alt_rounded
                : Icons.workspaces_outline,
            size: 18,
            color: hasActiveProject
                ? const Color(0xFF8BF0B8)
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasActiveProject
                  ? tr('Active task: {name}', {'name': activeProject.name})
                  : tr('No active task selected'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: hasActiveProject
                    ? const Color(0xFFE9FFF1)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfrastructureHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => const _InfrastructureHelpDialog(),
    );
  }

  Widget _buildMapLayerMenu() {
    return PopupMenuButton<String>(
      tooltip: tr('Map layer'),
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
    );
  }

  Widget _buildProjectFilterMenu() {
    return PopupMenuButton<String>(
      tooltip: tr('Task filter'),
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
          child: Text(tr('All tasks')),
        ),
        ..._projectOptions.entries.map(
          (entry) => CheckedPopupMenuItem<String>(
            value: '${entry.key}',
            checked: _projectFilterId == entry.key,
            child: Text(entry.value),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Infrastructure map')),
        actions: [
          ResponsiveAppBarActions(
            actions: [
              if (_activeTraceRequest != null)
                IconButton(
                  tooltip: tr('Clear route highlight'),
                  onPressed: _clearTraceHighlight,
                  icon: const Icon(Icons.alt_route_rounded),
                ),
              IconButton(
                tooltip: _routeCreateMode
                    ? tr('Cancel route creation')
                    : tr('New route'),
                onPressed: _loading || _syncingRoutes
                    ? null
                    : _toggleRouteCreateMode,
                icon: Icon(
                  _routeCreateMode
                      ? Icons.close_rounded
                      : Icons.add_road_rounded,
                ),
              ),
              IconButton(
                tooltip: _routeEditMode
                    ? tr('Finish route editing')
                    : tr('Edit selected route'),
                onPressed: _loading || _syncingRoutes || _selectedRoute == null
                    ? null
                    : _toggleRouteEditMode,
                icon: Icon(
                  _routeEditMode ? Icons.check_rounded : Icons.edit_rounded,
                ),
              ),
              IconButton(
                tooltip: _routeSplitMode
                    ? tr('Cancel closure installation')
                    : tr('Mark break / install closure'),
                onPressed: _loading || _syncingRoutes || _selectedRoute == null
                    ? null
                    : _toggleRouteSplitMode,
                icon: Icon(
                  _routeSplitMode
                      ? Icons.close_rounded
                      : Icons.call_split_rounded,
                ),
              ),
              IconButton(
                tooltip: tr('Delete selected route'),
                onPressed: _loading || _syncingRoutes || _selectedRoute == null
                    ? null
                    : _deleteSelectedRoute,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              _buildMapLayerMenu(),
              _buildProjectFilterMenu(),
              IconButton(
                tooltip: tr('Refresh'),
                onPressed: _loading || _syncingRoutes ? null : _loadMapData,
                icon: _syncingRoutes
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: tr('Screen guide'),
                onPressed: _showInfrastructureHelp,
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ],
            compactActions: [
              IconButton(
                tooltip: _routeCreateMode
                    ? tr('Cancel route creation')
                    : tr('New route'),
                onPressed: _loading || _syncingRoutes
                    ? null
                    : _toggleRouteCreateMode,
                icon: Icon(
                  _routeCreateMode
                      ? Icons.close_rounded
                      : Icons.add_road_rounded,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Actions'),
                onSelected: (value) {
                  if (value == 'clear_trace') {
                    _clearTraceHighlight();
                  } else if (value == 'edit_route') {
                    _toggleRouteEditMode();
                  } else if (value == 'split_route') {
                    _toggleRouteSplitMode();
                  } else if (value == 'delete_route') {
                    _deleteSelectedRoute();
                  } else if (value == 'refresh') {
                    _loadMapData();
                  } else if (value == 'help') {
                    _showInfrastructureHelp();
                  } else if (value.startsWith('layer:')) {
                    setState(() {
                      _selectedTileLayerId = value.substring(6);
                    });
                  } else if (value.startsWith('project:')) {
                    _applyProjectFilter(value.substring(8));
                  }
                },
                itemBuilder: (context) => [
                  if (_activeTraceRequest != null)
                    PopupMenuItem(
                      value: 'clear_trace',
                      child: Text(tr('Clear route highlight')),
                    ),
                  PopupMenuItem(
                    value: 'edit_route',
                    enabled:
                        !_loading && !_syncingRoutes && _selectedRoute != null,
                    child: Text(
                      _routeEditMode
                          ? tr('Finish route editing')
                          : tr('Edit selected route'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'split_route',
                    enabled:
                        !_loading && !_syncingRoutes && _selectedRoute != null,
                    child: Text(
                      _routeSplitMode
                          ? tr('Cancel closure installation')
                          : tr('Mark break / install closure'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete_route',
                    enabled:
                        !_loading && !_syncingRoutes && _selectedRoute != null,
                    child: Text(tr('Delete selected route')),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    enabled: !_loading && !_syncingRoutes,
                    child: Text(tr('Refresh')),
                  ),
                  PopupMenuItem(value: 'help', child: Text(tr('Screen guide'))),
                  const PopupMenuDivider(),
                  ...mapTileOptions.map(
                    (option) => CheckedPopupMenuItem<String>(
                      value: 'layer:${option.id}',
                      checked: option.id == _selectedTileLayerId,
                      child: Text(option.label),
                    ),
                  ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem<String>(
                    value: 'project:__all_projects__',
                    checked: _projectFilterId == null,
                    child: Text(tr('All tasks')),
                  ),
                  ..._projectOptions.entries.map(
                    (entry) => CheckedPopupMenuItem<String>(
                      value: 'project:${entry.key}',
                      checked: _projectFilterId == entry.key,
                      child: Text(entry.value),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildActiveProjectBanner(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _showInstructionBanner
                ? ScreenInstruction(
                    key: const ValueKey('infrastructure-map-instruction'),
                    text: tr(
                      'Use the road button to draw a cable route, select routes or map objects to inspect them, and use edit tools for route changes.',
                    ),
                    margin: const EdgeInsets.all(12),
                    dismissTooltip: tr('Hide hint'),
                    onDismiss: () {
                      unawaited(_dismissInstructionBanner());
                    },
                  )
                : const SizedBox.shrink(
                    key: ValueKey('infrastructure-map-instruction-hidden'),
                  ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

class _InfrastructureHelpDialog extends StatelessWidget {
  const _InfrastructureHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(tr('Infrastructure map guide'))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HelpSection(
                icon: Icons.workspaces_outline,
                title: tr('Active task'),
                body: tr(
                  'The banner under the app bar shows the active task. New map changes are linked to this task when one is selected on the main screen.',
                ),
                image: const _TaskHelpPicture(),
              ),
              _HelpSection(
                icon: Icons.add_road_rounded,
                title: tr('Create cable route'),
                body: tr(
                  'Press the road button, tap a start point, add intermediate points on the map, then tap the end point. Confirm the route name and parameters in the route panel.',
                ),
                image: const _RouteHelpPicture(),
              ),
              _HelpSection(
                icon: Icons.edit_rounded,
                title: tr('Edit selected route'),
                body: tr(
                  'Select a route on the map, press edit, then drag orange intermediate points to adjust the route. Press the check button to finish editing.',
                ),
                image: const _EditRouteHelpPicture(),
              ),
              _HelpSection(
                icon: Icons.call_split_rounded,
                title: tr('Install closure on route'),
                body: tr(
                  'Select a route and press the split button. Tap the route where the break or closure should be installed, choose the closure data, then confirm.',
                ),
                image: const _ClosureHelpPicture(),
              ),
              _HelpSection(
                icon: Icons.touch_app_rounded,
                title: tr('Inspect objects'),
                body: tr(
                  'Tap closures, PON boxes, cabinets, connection points, or routes to open details. Selected routes unlock edit, split, and delete actions.',
                ),
                image: const _InspectHelpPicture(),
              ),
              _HelpSection(
                icon: Icons.layers_outlined,
                title: tr('Map layer'),
                body: tr(
                  'Use the layers button to switch between available map providers. The selected layer affects only the map background.',
                ),
                image: const _LayerHelpPicture(),
              ),
              _HelpSection(
                icon: Icons.workspaces_rounded,
                title: tr('Task filter'),
                body: tr(
                  'Use the task filter to show all infrastructure or only objects and routes connected with one task.',
                ),
                image: const _FilterHelpPicture(),
              ),
              _HelpSection(
                icon: Icons.delete_outline_rounded,
                title: tr('Delete selected route'),
                body: tr(
                  'Select a route and press the delete button. The app asks for confirmation before removing the route.',
                ),
                image: const _DeleteHelpPicture(),
              ),
              _HelpSection(
                icon: Icons.refresh_rounded,
                title: tr('Refresh and trace'),
                body: tr(
                  'Refresh reloads map data and route state from storage/cloud. If a signal trace is opened from a cabinet port, the highlight button clears that trace.',
                ),
                image: const _RefreshHelpPicture(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Close')),
        ),
      ],
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.image,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget image;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 720;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(body),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [image, const SizedBox(height: 12), text],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 170, child: image),
                const SizedBox(width: 14),
                Expanded(child: text),
              ],
            ),
    );
  }
}

class _HelpPictureFrame extends StatelessWidget {
  const _HelpPictureFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.7,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1D33),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1E466A)),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class _TaskHelpPicture extends StatelessWidget {
  const _TaskHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _HelpPictureFrame(
      child: Center(
        child: Icon(Icons.task_alt_rounded, color: Color(0xFF8BF0B8), size: 46),
      ),
    );
  }
}

class _RouteHelpPicture extends StatelessWidget {
  const _RouteHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _HelpPictureFrame(child: CustomPaint(painter: _RouteHelpPainter()));
  }
}

class _EditRouteHelpPicture extends StatelessWidget {
  const _EditRouteHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _HelpPictureFrame(
      child: CustomPaint(painter: _EditRouteHelpPainter()),
    );
  }
}

class _ClosureHelpPicture extends StatelessWidget {
  const _ClosureHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _HelpPictureFrame(
      child: Center(
        child: Icon(
          Icons.call_split_rounded,
          color: Color(0xFFFFA629),
          size: 48,
        ),
      ),
    );
  }
}

class _InspectHelpPicture extends StatelessWidget {
  const _InspectHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _HelpPictureFrame(
      child: Center(
        child: Icon(
          Icons.touch_app_rounded,
          color: Color(0xFF53B6D9),
          size: 48,
        ),
      ),
    );
  }
}

class _LayerHelpPicture extends StatelessWidget {
  const _LayerHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _HelpPictureFrame(
      child: Center(
        child: Icon(Icons.layers_outlined, color: Color(0xFFA6F6E8), size: 48),
      ),
    );
  }
}

class _FilterHelpPicture extends StatelessWidget {
  const _FilterHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _HelpPictureFrame(
      child: Center(
        child: Icon(
          Icons.workspaces_rounded,
          color: Color(0xFF8BF0B8),
          size: 48,
        ),
      ),
    );
  }
}

class _DeleteHelpPicture extends StatelessWidget {
  const _DeleteHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _HelpPictureFrame(
      child: Center(
        child: Icon(
          Icons.delete_outline_rounded,
          color: Colors.redAccent,
          size: 48,
        ),
      ),
    );
  }
}

class _RefreshHelpPicture extends StatelessWidget {
  const _RefreshHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _HelpPictureFrame(
      child: Center(
        child: Icon(Icons.refresh_rounded, color: Color(0xFF53B6D9), size: 48),
      ),
    );
  }
}

class _RouteHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pathPaint = Paint()
      ..color = const Color(0xFF35C886)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final pointPaint = Paint()..color = const Color(0xFFF2F7FA);
    final points = [
      Offset(size.width * 0.18, size.height * 0.68),
      Offset(size.width * 0.38, size.height * 0.42),
      Offset(size.width * 0.64, size.height * 0.56),
      Offset(size.width * 0.82, size.height * 0.28),
    ];
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, pathPaint);
    for (final point in points) {
      canvas.drawCircle(point, 6, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EditRouteHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pathPaint = Paint()
      ..color = const Color(0xFF53B6D9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final dragPaint = Paint()..color = const Color(0xFFFFA629);
    final points = [
      Offset(size.width * 0.18, size.height * 0.62),
      Offset(size.width * 0.44, size.height * 0.36),
      Offset(size.width * 0.68, size.height * 0.64),
      Offset(size.width * 0.84, size.height * 0.36),
    ];
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, pathPaint);
    for (final point in points.skip(1).take(2)) {
      canvas.drawCircle(point, 8, dragPaint);
      canvas.drawCircle(point, 3, Paint()..color = const Color(0xFF071526));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
