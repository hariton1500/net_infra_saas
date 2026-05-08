import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../auth/auth_controller.dart';
import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/map_tile_providers.dart';
import '../core/project_scope.dart';
import '../widgets/responsive_app_bar_actions.dart';
import '../widgets/screen_instruction.dart';
import 'infrastructure_map_page.dart';
import 'muff_location_picker.dart';

class CabinetNotebookPage extends StatefulWidget {
  const CabinetNotebookPage({
    super.key,
    required this.controller,
    this.initialCabinetId,
  });

  final AuthController controller;
  final int? initialCabinetId;

  @override
  State<CabinetNotebookPage> createState() => _CabinetNotebookPageState();
}

class _EndpointChoice {
  const _EndpointChoice({
    required this.key,
    required this.label,
    required this.endpoint,
  });

  final String key;
  final String label;
  final Map<String, dynamic> endpoint;
}

class _CabinetNotebookPageState extends State<CabinetNotebookPage> {
  static const String _moduleKey = 'network_cabinet';
  static const String _cacheKey = 'network_cabinet.cabinets.v1';
  static const String _portTypeCopper = 'copper';
  static const String _portTypeOptical = 'optical';
  static const String _portTypePon = 'pon';

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

  static const Map<String, String> _portTypeLabels = {
    _portTypeCopper: 'Copper',
    _portTypeOptical: 'Optical',
    _portTypePon: 'PON',
  };

  final List<Map<String, dynamic>> _cabinets = [];
  List<Map<String, dynamic>> _projectRecords = const [];
  final MapController _mapController = MapController();
  late final CompanyModuleSyncRepository _syncRepository;
  final _ConnectionAnchorRegistry _connectionAnchors =
      _ConnectionAnchorRegistry();
  bool _loading = true;
  bool _syncing = false;
  bool _mapView = false;
  Map<String, dynamic>? _selectedCabinet;
  int? _selectedCableId;
  int? _projectFilterId;
  ProjectSelection? _activeProject;
  double _mapZoom = 14;
  final double _portSize = 26;
  final double _fiberSize = 24;
  String _selectedTileLayerId = 'osm';
  Timer? _syncTimer;

  static int _nextCabinetId = 1;

  String get _actorLabel =>
      widget.controller.profile?.email ??
      widget.controller.currentUser?.email ??
      widget.controller.currentUser?.id ??
      'current_user';

  String? get _companyId => widget.controller.membership?.companyId;

  String get _actorEmail =>
      widget.controller.currentUser?.email?.trim() ??
      widget.controller.profile?.email ??
      '';

  String get _actorUserId => widget.controller.currentUser?.id ?? '';

  bool get _hasDirtyRecords => _cabinets.any(
    (cabinet) => cabinet['deleted'] != true && cabinet['dirty'] == true,
  );

  String _fiberKey(int cableId, int fiberIndex) => '$cableId:$fiberIndex';

  String _portKey(int switchId, int portIndex) => 's$switchId:$portIndex';

  String _splitterPortKey(int splitterId, String portType, int portIndex) =>
      'splitter:$splitterId:$portType:$portIndex';

  Map<String, dynamic> _cableEndpoint(int cableId, int fiberIndex) => {
    'type': 'cable',
    'cableId': cableId,
    'fiberIndex': fiberIndex,
  };

  Map<String, dynamic> _switchEndpoint(int switchId, int portIndex) => {
    'type': 'switch',
    'switchId': switchId,
    'portIndex': portIndex,
  };

  Map<String, dynamic> _splitterEndpoint(
    int splitterId,
    String portType,
    int portIndex,
  ) => {
    'type': 'splitter',
    'splitterId': splitterId,
    'portType': portType,
    'portIndex': portIndex,
  };

  String _endpointKey(Map<String, dynamic> endpoint) {
    if (endpoint['type'] == 'switch') {
      return _portKey(
        endpoint['switchId'] as int,
        (endpoint['portIndex'] as int?) ?? 0,
      );
    }
    if (endpoint['type'] == 'splitter') {
      return _splitterPortKey(
        endpoint['splitterId'] as int,
        (endpoint['portType'] as String?) ?? 'output',
        (endpoint['portIndex'] as int?) ?? 0,
      );
    }
    return _fiberKey(
      endpoint['cableId'] as int,
      (endpoint['fiberIndex'] as int?) ?? 0,
    );
  }

  bool _sameEndpoint(Map<String, dynamic> left, Map<String, dynamic> right) =>
      _endpointKey(left) == _endpointKey(right);

  Future<void> _recordTaskAddition({
    required String kind,
    required String summary,
    int? targetRecordId,
  }) async {
    if (_companyId == null || _activeProject == null) {
      return;
    }
    await _syncRepository.appendTaskWorkLog(
      companyId: _companyId!,
      activeProject: _activeProject!,
      actorUserId: _actorUserId,
      actorEmail: _actorEmail,
      kind: kind,
      summary: summary,
      targetScreen: 'network_cabinet',
      targetRecordId: targetRecordId,
    );
  }

  Future<void> _openPortTraceOnMap({
    required int switchId,
    required int portIndex,
  }) async {
    final cabinetId = _selectedCabinet?['id'] as int?;
    if (cabinetId == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InfrastructureMapPage(
          controller: widget.controller,
          initialTraceRequest: InfrastructureSignalTraceRequest(
            cabinetId: cabinetId,
            switchId: switchId,
            portIndex: portIndex,
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _syncRepository = CompanyModuleSyncRepository(
      client: widget.controller.client,
      companyId: widget.controller.membership?.companyId,
    );
    _loadFromStorage();
    _startAutoSync();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_syncAll());
    });
  }

  Future<void> _loadFromStorage() async {
    final selectedCabinetId =
        (_selectedCabinet?['id'] as int?) ?? widget.initialCabinetId;
    final selectedCableId = _selectedCableId;
    _activeProject = await _syncRepository.readActiveProject();
    _projectRecords = await _syncRepository.readCache(projectsCacheKey);

    _cabinets
      ..clear()
      ..addAll(await _syncRepository.readCache(_cacheKey));
    if (_cleanupLegacyCabinetTopology(_cabinets)) {
      await _syncRepository.writeCache(_cacheKey, _cabinets);
    }
    _nextCabinetId = _maxId(_cabinets) + 1;
    _rebuildView(
      selectedCabinetId: selectedCabinetId,
      selectedCableId: selectedCableId,
    );

    try {
      if (!_cabinets.any((record) => record['dirty'] == true) &&
          _companyId != null) {
        _projectRecords = await _syncRepository.pullMerge(
          companyId: _companyId!,
          moduleKey: projectsModuleKey,
          localRecords: _projectRecords,
        );
        await _syncRepository.writeCache(projectsCacheKey, _projectRecords);
        final merged = await _syncRepository.pullMerge(
          companyId: _companyId!,
          moduleKey: _moduleKey,
          localRecords: _cabinets,
        );
        _cabinets
          ..clear()
          ..addAll(merged);
        if (_cleanupLegacyCabinetTopology(_cabinets)) {
          final cleaned = await _syncRepository.syncAll(
            companyId: _companyId!,
            moduleKey: _moduleKey,
            cacheKey: _cacheKey,
            localRecords: _cabinets,
          );
          _cabinets
            ..clear()
            ..addAll(cleaned);
        } else {
          await _syncRepository.writeCache(_cacheKey, _cabinets);
        }
        _nextCabinetId = _maxId(_cabinets) + 1;
      }
    } catch (error, stackTrace) {
      logUserFacingError(
        'Failed to load cabinets from Supabase.',
        source: 'network_cabinet.load',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnack('Failed to load cabinets from the cloud.');
    }

    _rebuildView(
      selectedCabinetId: selectedCabinetId,
      selectedCableId: selectedCableId,
      loading: false,
    );
  }

  void _applyProjectFilter(String value) {
    final nextFilter = value == '__all_projects__' ? null : int.tryParse(value);
    setState(() {
      _projectFilterId = nextFilter;
      _selectedCableId = null;
      if (_selectedCabinet != null &&
          !matchesProjectFilter(_selectedCabinet!, _projectFilterId)) {
        _selectedCabinet = null;
      }
    });
  }

  Future<void> _persist() async {
    await _refreshActiveProject();
    _hydrateDirtyCabinetsWithActiveProject();
    await _syncRepository.writeCache(_cacheKey, _cabinets);
  }

  Future<void> _refreshActiveProject() async {
    _activeProject = await _syncRepository.readActiveProject();
  }

  void _hydrateDirtyCabinetsWithActiveProject() {
    final activeProject = _activeProject;
    if (activeProject == null) {
      return;
    }

    for (final cabinet in _cabinets) {
      if (cabinet['dirty'] == true && projectIdOf(cabinet) == null) {
        applyProjectSelection(cabinet, activeProject);
      }
    }
  }

  Future<void> _syncAll() async {
    if (_syncing || _companyId == null) {
      return;
    }

    final selectedCabinetId = _selectedCabinet?['id'] as int?;
    final selectedCableId = _selectedCableId;

    setState(() {
      _syncing = true;
    });

    try {
      await _refreshActiveProject();
      _hydrateDirtyCabinetsWithActiveProject();
      _cleanupLegacyCabinetTopology(_cabinets);
      var merged = await _syncRepository.syncAll(
        companyId: _companyId!,
        moduleKey: _moduleKey,
        cacheKey: _cacheKey,
        localRecords: _cabinets,
      );
      if (_cleanupLegacyCabinetTopology(merged)) {
        merged = await _syncRepository.syncAll(
          companyId: _companyId!,
          moduleKey: _moduleKey,
          cacheKey: _cacheKey,
          localRecords: merged,
        );
      }
      _cabinets
        ..clear()
        ..addAll(merged);
      _nextCabinetId = _maxId(_cabinets) + 1;
      _rebuildView(
        selectedCabinetId: selectedCabinetId,
        selectedCableId: selectedCableId,
      );
    } catch (error, stackTrace) {
      logUserFacingError(
        'Failed to synchronize cabinets.',
        source: 'network_cabinet.sync',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnack('Cabinet sync error.');
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  int _maxId(List<Map<String, dynamic>> items) {
    return items
        .map((item) => (item['id'] as int?) ?? 0)
        .fold(0, (current, next) => current > next ? current : next);
  }

  int? _nullableInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  bool _cleanupLegacyCabinetTopology(List<Map<String, dynamic>> cabinets) {
    var changed = false;
    for (final cabinet in cabinets) {
      if (cabinet['deleted'] == true) {
        continue;
      }

      if (_cleanupLegacyCabinetPayload(cabinet)) {
        cabinet['updated_at'] = DateTime.now();
        cabinet['dirty'] = true;
        changed = true;
      }
    }
    return changed;
  }

  bool _cleanupLegacyCabinetPayload(Map<String, dynamic> cabinet) {
    final rawCables = List<dynamic>.from(cabinet['cables'] ?? const []);
    final splitterFiberKeys = <String>{};
    final cleanedCables = <Map<String, dynamic>>[];
    var changed = false;

    for (final rawCable in rawCables) {
      if (rawCable is! Map) {
        continue;
      }

      final cable = Map<String, dynamic>.from(rawCable);
      final cableId = _nullableInt(cable['id']);
      final splitterValues = List<dynamic>.from(
        cable['spliters'] ?? cable['splitters'] ?? const [],
      );
      if (cableId != null) {
        for (var index = 0; index < splitterValues.length; index++) {
          final value = _nullableInt(splitterValues[index]) ?? 0;
          if (value > 0) {
            splitterFiberKeys.add('$cableId:$index');
          }
        }
      }

      if (cable.containsKey('spliters')) {
        cable.remove('spliters');
        changed = true;
      }
      if (cable.containsKey('splitters')) {
        cable.remove('splitters');
        changed = true;
      }
      cleanedCables.add(cable);
    }

    if (changed) {
      cabinet['cables'] = cleanedCables;
    }

    final connections = List<Map<String, dynamic>>.from(
      cabinet['connections'] ?? const [],
    );
    final cleanedConnections = connections
        .where((connection) {
          if (connection['endpoint1'] is! Map ||
              connection['endpoint2'] is! Map) {
            return false;
          }
          if (splitterFiberKeys.isEmpty) {
            return true;
          }
          return !_connectionTouchesEndpointWhere(connection, (endpoint) {
            if (endpoint['type'] != 'cable') {
              return false;
            }
            final cableId = _nullableInt(endpoint['cableId']);
            final fiberIndex = _nullableInt(endpoint['fiberIndex']);
            if (cableId == null || fiberIndex == null) {
              return false;
            }
            return splitterFiberKeys.contains('$cableId:$fiberIndex');
          });
        })
        .toList(growable: false);
    if (cleanedConnections.length != connections.length) {
      cabinet['connections'] = cleanedConnections;
      changed = true;
    }

    return changed;
  }

  bool _connectionTouchesEndpointWhere(
    Map<String, dynamic> connection,
    bool Function(Map<String, dynamic> endpoint) matches,
  ) {
    if (connection['endpoint1'] is Map) {
      final endpoint = Map<String, dynamic>.from(
        connection['endpoint1'] as Map,
      );
      if (matches(endpoint)) {
        return true;
      }
    }
    if (connection['endpoint2'] is Map) {
      final endpoint = Map<String, dynamic>.from(
        connection['endpoint2'] as Map,
      );
      if (matches(endpoint)) {
        return true;
      }
    }
    return false;
  }

  void _rebuildView({
    int? selectedCabinetId,
    int? selectedCableId,
    bool loading = false,
  }) {
    _cabinets.sort((a, b) {
      final at = _syncRepository.parseTime(a['updated_at']);
      final bt = _syncRepository.parseTime(b['updated_at']);
      return bt.compareTo(at);
    });

    if (selectedCabinetId != null) {
      _selectedCabinet = _cabinets.cast<Map<String, dynamic>?>().firstWhere(
        (cabinet) =>
            cabinet?['deleted'] != true && cabinet?['id'] == selectedCabinetId,
        orElse: () => null,
      );
    } else {
      _selectedCabinet = null;
    }

    if (_selectedCabinet != null &&
        selectedCableId != null &&
        List<Map<String, dynamic>>.from(
          _selectedCabinet!['cables'] ?? const [],
        ).any((cable) => cable['id'] == selectedCableId)) {
      _selectedCableId = selectedCableId;
    } else {
      _selectedCableId = null;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = loading;
    });
  }

  List<Map<String, dynamic>> get _visibleCabinets => _cabinets
      .where((cabinet) => cabinet['deleted'] != true)
      .where((cabinet) => matchesProjectFilter(cabinet, _projectFilterId))
      .toList(growable: false);

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

  void _touchCabinet(Map<String, dynamic> cabinet) {
    if (projectIdOf(cabinet) == null && _activeProject != null) {
      applyProjectSelection(cabinet, _activeProject);
    }
    cabinet['updated_at'] = DateTime.now();
    cabinet['dirty'] = true;
  }

  String? _projectNameFor(Map<String, dynamic> record) {
    final projectId = projectIdOf(record);
    if (projectId == null) {
      return null;
    }
    return _projectOptions[projectId];
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }

    debugPrint(message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scheduleRebuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _scheduleAddConnectionBetweenEndpoints({
    required Map<String, dynamic> endpoint1,
    required Map<String, dynamic> endpoint2,
  }) {
    final first = Map<String, dynamic>.from(endpoint1);
    final second = Map<String, dynamic>.from(endpoint2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _addConnectionBetweenEndpoints(endpoint1: first, endpoint2: second);
      }
    });
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

  Future<void> _showCabinetEditor({Map<String, dynamic>? cabinet}) async {
    final nameController = TextEditingController(text: cabinet?['name'] ?? '');
    final locationController = TextEditingController(
      text: cabinet?['location'] ?? '',
    );
    final commentController = TextEditingController(
      text: cabinet?['comment'] ?? '',
    );
    double? lat = cabinet?['location_lat'] as double?;
    double? lng = cabinet?['location_lng'] as double?;
    if (lat == null || lng == null) {
      final lastLocation = await _syncRepository.readLastPickedLocation();
      if (lastLocation != null) {
        lat = lastLocation.latitude;
        lng = lastLocation.longitude;
      }
    }
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(tr(cabinet == null ? 'New cabinet' : 'Edit cabinet')),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(labelText: tr('Name')),
                      ),
                      TextField(
                        controller: locationController,
                        decoration: InputDecoration(
                          labelText: tr('Address/place'),
                        ),
                      ),
                      TextField(
                        controller: commentController,
                        decoration: InputDecoration(labelText: tr('Comment')),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.place, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              lat != null && lng != null
                                  ? '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}'
                                  : tr('Location is not set'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final result = await Navigator.of(context)
                                  .push<LatLng>(
                                    MaterialPageRoute(
                                      builder: (_) => MuffLocationPickerPage(
                                        initial: lat != null && lng != null
                                            ? LatLng(lat!, lng!)
                                            : null,
                                      ),
                                    ),
                                  );
                              if (result != null) {
                                setStateDialog(() {
                                  lat = result.latitude;
                                  lng = result.longitude;
                                });
                                await _syncRepository.writeLastPickedLocation(
                                  result,
                                );
                              }
                            },
                            icon: const Icon(Icons.map),
                            label: Text(tr('On map')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final payload = <String, dynamic>{
                      'name': nameController.text.trim(),
                      'location': locationController.text.trim(),
                      'comment': commentController.text.trim(),
                      'location_lat': lat,
                      'location_lng': lng,
                      'updated_at': DateTime.now(),
                      'updated_by': _actorLabel,
                    };

                    if (cabinet == null) {
                      payload['id'] = _nextCabinetId++;
                      payload['created_by'] = _actorLabel;
                      payload['switches'] = <Map<String, dynamic>>[];
                      payload['cables'] = <Map<String, dynamic>>[];
                      payload['splitters'] = <Map<String, dynamic>>[];
                      payload['connections'] = <Map<String, dynamic>>[];
                      payload['deleted'] = false;
                      payload['dirty'] = true;
                      applyProjectSelection(payload, _activeProject);
                      _cabinets.add(payload);
                    } else {
                      payload['id'] = cabinet['id'];
                      payload['created_by'] = cabinet['created_by'];
                      payload['switches'] =
                          cabinet['switches'] ?? <Map<String, dynamic>>[];
                      payload['cables'] =
                          cabinet['cables'] ?? <Map<String, dynamic>>[];
                      payload['splitters'] =
                          cabinet['splitters'] ?? <Map<String, dynamic>>[];
                      payload['connections'] =
                          cabinet['connections'] ?? <Map<String, dynamic>>[];
                      if (projectIdOf(cabinet) == null &&
                          _activeProject != null) {
                        applyProjectSelection(payload, _activeProject);
                      } else {
                        payload['task_id'] = cabinet['task_id'];
                      }
                      payload['deleted'] = cabinet['deleted'] == true;
                      payload['dirty'] = true;
                      final index = _cabinets.indexWhere(
                        (entry) => entry['id'] == cabinet['id'],
                      );
                      if (index != -1) {
                        _cabinets[index] = payload;
                      }
                    }

                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    if (cabinet == null) {
                      await _recordTaskAddition(
                        kind: tr('Cabinet added'),
                        summary: [
                          if (payload['name']?.toString().trim().isNotEmpty ==
                              true)
                            payload['name'].toString().trim()
                          else
                            tr('Untitled'),
                          if ((payload['location'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            payload['location'].toString().trim(),
                          if ((payload['comment'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            tr('note: {value}', {
                              'value': payload['comment'].toString().trim(),
                            }),
                        ].join(' вЂў '),
                        targetRecordId: payload['id'] as int?,
                      );
                    }
                    navigator.pop();
                    await _selectCabinet(payload);
                    setState(() {});
                  },
                  icon: const Icon(Icons.save),
                  label: Text(tr('Save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _selectCabinet(Map<String, dynamic> cabinet) async {
    setState(() {
      _selectedCabinet = cabinet;
      _selectedCableId = null;
    });
  }

  Future<void> _deleteCabinet(Map<String, dynamic> cabinet) async {
    cabinet['deleted'] = true;
    _touchCabinet(cabinet);
    await _persist();
    if (_selectedCabinet?['id'] == cabinet['id']) {
      _selectedCabinet = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openCabinetLocation(Map<String, dynamic> cabinet) async {
    final lat = cabinet['location_lat'] as double?;
    final lng = cabinet['location_lng'] as double?;
    final initial = lat != null && lng != null
        ? LatLng(lat, lng)
        : await _syncRepository.readLastPickedLocation();
    if (!mounted) {
      return;
    }
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MuffLocationPickerPage(initial: initial),
      ),
    );

    if (result == null) {
      return;
    }

    await _syncRepository.writeLastPickedLocation(result);
    cabinet['location_lat'] = result.latitude;
    cabinet['location_lng'] = result.longitude;
    _touchCabinet(cabinet);
    await _persist();
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic>? _getSwitchById(int id) {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return null;
    }

    for (final item in List<Map<String, dynamic>>.from(
      cabinet['switches'] ?? const [],
    )) {
      if (item['id'] == id) {
        return item;
      }
    }

    return null;
  }

  Map<String, dynamic>? _getCableById(int id) {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return null;
    }

    for (final item in List<Map<String, dynamic>>.from(
      cabinet['cables'] ?? const [],
    )) {
      if (item['id'] == id) {
        return item;
      }
    }

    return null;
  }

  Map<String, dynamic>? _getSplitterById(int id) {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return null;
    }

    for (final item in List<Map<String, dynamic>>.from(
      cabinet['splitters'] ?? const [],
    )) {
      if (item['id'] == id) {
        return item;
      }
    }

    return null;
  }

  List<Map<String, dynamic>> _getSplittersBySide(int side) {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return const [];
    }

    return List<Map<String, dynamic>>.from(cabinet['splitters'] ?? const [])
        .where((splitter) => (splitter['side'] as int? ?? 0) == side)
        .toList(growable: false);
  }

  List<_EndpointChoice> _endpointChoices(Map<String, dynamic> cabinet) {
    final choices = <_EndpointChoice>[];

    for (final cable in List<Map<String, dynamic>>.from(
      cabinet['cables'] ?? const [],
    )) {
      final cableId = cable['id'] as int;
      final fibers = (cable['fibers'] as int?) ?? 1;
      for (var index = 0; index < fibers; index++) {
        final endpoint = _cableEndpoint(cableId, index);
        choices.add(
          _EndpointChoice(
            key: _endpointKey(endpoint),
            label: '${cable['name'] ?? 'Cable'} вЂў Fiber ${index + 1}',
            endpoint: endpoint,
          ),
        );
      }
    }

    for (final sw in List<Map<String, dynamic>>.from(
      cabinet['switches'] ?? const [],
    )) {
      final switchId = sw['id'] as int;
      final ports = (sw['ports'] as int?) ?? 24;
      for (var index = 0; index < ports; index++) {
        final endpoint = _switchEndpoint(switchId, index);
        choices.add(
          _EndpointChoice(
            key: _endpointKey(endpoint),
            label: '${sw['name'] ?? 'Switch'} вЂў Port ${index + 1}',
            endpoint: endpoint,
          ),
        );
      }
    }

    for (final splitter in List<Map<String, dynamic>>.from(
      cabinet['splitters'] ?? const [],
    )) {
      final splitterId = splitter['id'] as int;
      final ratio = (splitter['ratio'] as int?) ?? 8;
      final input = _splitterEndpoint(splitterId, 'input', 0);
      choices.add(
        _EndpointChoice(
          key: _endpointKey(input),
          label: '${splitter['name'] ?? 'Splitter'} вЂў Input',
          endpoint: input,
        ),
      );

      for (var index = 0; index < ratio; index++) {
        final output = _splitterEndpoint(splitterId, 'output', index);
        choices.add(
          _EndpointChoice(
            key: _endpointKey(output),
            label: '${splitter['name'] ?? 'Splitter'} вЂў Output ${index + 1}',
            endpoint: output,
          ),
        );
      }
    }

    return choices;
  }

  String _endpointLabel(Map<String, dynamic> endpoint) {
    if (endpoint['type'] == 'switch') {
      final sw = _getSwitchById(endpoint['switchId'] as int);
      return '${sw?['name'] ?? 'Switch'} port ${(endpoint['portIndex'] as int) + 1}';
    }

    if (endpoint['type'] == 'splitter') {
      final splitter = _getSplitterById(endpoint['splitterId'] as int);
      final name = splitter?['name'] ?? 'Splitter';
      final portType = (endpoint['portType'] as String?) ?? 'output';
      if (portType == 'input') {
        return '$name[Input]';
      }
      return '$name[Output ${(endpoint['portIndex'] as int) + 1}]';
    }

    final cable = _getCableById(endpoint['cableId'] as int);
    return '${cable?['name'] ?? 'Cable'}[${(endpoint['fiberIndex'] as int) + 1}]';
  }

  String _connectionLabel(Map<String, dynamic> connection) {
    if (connection['endpoint1'] is! Map || connection['endpoint2'] is! Map) {
      return 'Point <--> Point';
    }
    final endpoint1 = Map<String, dynamic>.from(connection['endpoint1'] as Map);
    final endpoint2 = Map<String, dynamic>.from(connection['endpoint2'] as Map);
    return '${_endpointLabel(endpoint1)} <--> ${_endpointLabel(endpoint2)}';
  }

  List<String> _portTypesForSwitch(Map<String, dynamic> sw) {
    final portsCount = (sw['ports'] as int?) ?? 24;
    final raw = List<dynamic>.from(sw['port_types'] ?? const []);
    return List<String>.generate(portsCount, (index) {
      final value = index < raw.length ? raw[index]?.toString() ?? '' : '';
      if (_portTypeLabels.containsKey(value)) {
        return value;
      }
      return _portTypeOptical;
    });
  }

  List<String> _portCommentsForSwitch(Map<String, dynamic> sw) {
    final portsCount = (sw['ports'] as int?) ?? 24;
    final raw = List<dynamic>.from(sw['port_comments'] ?? const []);
    return List<String>.generate(portsCount, (index) {
      if (index >= raw.length) {
        return '';
      }
      return raw[index]?.toString() ?? '';
    });
  }

  Color _portTypeColor(String type) {
    switch (type) {
      case _portTypeCopper:
        return Colors.brown.shade300;
      case _portTypePon:
        return Colors.lightGreen.shade300;
      case _portTypeOptical:
      default:
        return Colors.lightBlue.shade200;
    }
  }

  Future<void> _addSwitch() async {
    if (_selectedCabinet == null) {
      return;
    }

    final nameController = TextEditingController(text: 'Switch');
    final modelController = TextEditingController();
    int ports = 24;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(tr('Add switch')),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: tr('Name')),
                    ),
                    TextField(
                      controller: modelController,
                      decoration: InputDecoration(labelText: tr('Model')),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(tr('Ports:')),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: ports,
                          items: [8, 10, 16, 24, 26, 28, 34, 48]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setStateDialog(() {
                              ports = value ?? 24;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final cabinet = _selectedCabinet!;
                    final switches = List<Map<String, dynamic>>.from(
                      cabinet['switches'] ?? const [],
                    );
                    switches.add({
                      'id': DateTime.now().microsecondsSinceEpoch,
                      'name': nameController.text.trim().isEmpty
                          ? tr('Switch')
                          : nameController.text.trim(),
                      'model': modelController.text.trim(),
                      'ports': ports,
                      'port_types': List<String>.filled(
                        ports,
                        _portTypeOptical,
                      ),
                      'port_comments': List<String>.filled(ports, ''),
                    });
                    cabinet['switches'] = switches;
                    _touchCabinet(cabinet);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    await _recordTaskAddition(
                      kind: 'Switch added to cabinet',
                      summary: [
                        '${cabinet['name'] ?? tr('Cabinet')}',
                        '${switches.last['name'] ?? tr('Switch')}',
                        if ((switches.last['model'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          tr('model: {value}', {
                            'value': '${switches.last['model']}',
                          }),
                        tr('ports: {value}', {
                          'value': '${switches.last['ports'] ?? ports}',
                        }),
                      ].join(' вЂў '),
                      targetRecordId: cabinet['id'] as int?,
                    );
                    setState(() {});
                    navigator.pop();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteSwitch(int switchId) async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final switches = List<Map<String, dynamic>>.from(
      cabinet['switches'] ?? const [],
    )..removeWhere((sw) => sw['id'] == switchId);
    final connections =
        List<Map<String, dynamic>>.from(cabinet['connections'] ?? const [])
          ..removeWhere((connection) {
            return _connectionTouchesEndpointWhere(
              connection,
              (endpoint) =>
                  endpoint['type'] == 'switch' &&
                  endpoint['switchId'] == switchId,
            );
          });

    cabinet['switches'] = switches;
    cabinet['connections'] = connections;
    _touchCabinet(cabinet);
    await _persist();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _editSwitch(int switchId) async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final switches = List<Map<String, dynamic>>.from(
      cabinet['switches'] ?? const [],
    );
    final switchIndex = switches.indexWhere((sw) => sw['id'] == switchId);
    if (switchIndex == -1) {
      return;
    }

    final sw = Map<String, dynamic>.from(switches[switchIndex]);
    final nameController = TextEditingController(
      text: (sw['name'] ?? tr('Switch')).toString(),
    );
    final modelController = TextEditingController(
      text: (sw['model'] ?? '').toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr('Edit switch')),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: tr('Name')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: modelController,
                  decoration: InputDecoration(labelText: tr('Model')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Cancel')),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final name = nameController.text.trim();
                switches[switchIndex] = {
                  ...sw,
                  'name': name.isEmpty ? tr('Switch') : name,
                  'model': modelController.text.trim(),
                };
                cabinet['switches'] = switches;
                _touchCabinet(cabinet);
                await _persist();
                if (!mounted) {
                  return;
                }
                setState(() {});
                navigator.pop();
              },
              icon: const Icon(Icons.save),
              label: Text(tr('Save')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editSwitchPortTypes(int switchId) async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final switches = List<Map<String, dynamic>>.from(
      cabinet['switches'] ?? const [],
    );
    final switchIndex = switches.indexWhere((sw) => sw['id'] == switchId);
    if (switchIndex == -1) {
      return;
    }

    final sw = Map<String, dynamic>.from(switches[switchIndex]);
    final portTypes = List<String>.from(_portTypesForSwitch(sw));

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(
                tr('Port types: {name}', {
                  'name': '${sw['name'] ?? tr('Switch')}',
                }),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(portTypes.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 72,
                              child: Text(
                                tr('Port {value}', {'value': '${index + 1}'}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: portTypes[index],
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _portTypeLabels.entries
                                    .map(
                                      (entry) => DropdownMenuItem<String>(
                                        value: entry.key,
                                        child: Text(tr(entry.value)),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setStateDialog(() {
                                    portTypes[index] = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    switches[switchIndex] = {...sw, 'port_types': portTypes};
                    cabinet['switches'] = switches;
                    _touchCabinet(cabinet);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                    navigator.pop();
                  },
                  icon: const Icon(Icons.save),
                  label: Text(tr('Save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic>? _connectionForPort(int switchId, int portIndex) {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return null;
    }

    for (final connection in List<Map<String, dynamic>>.from(
      cabinet['connections'] ?? const [],
    )) {
      if (_connectionTouchesEndpointWhere(
        connection,
        (endpoint) =>
            endpoint['type'] == 'switch' &&
            endpoint['switchId'] == switchId &&
            endpoint['portIndex'] == portIndex,
      )) {
        return connection;
      }
    }

    return null;
  }

  Future<void> _removeConnectionForPort(int switchId, int portIndex) async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final connections =
        List<Map<String, dynamic>>.from(cabinet['connections'] ?? const [])
          ..removeWhere((connection) {
            return _connectionTouchesEndpointWhere(
              connection,
              (endpoint) =>
                  endpoint['type'] == 'switch' &&
                  endpoint['switchId'] == switchId &&
                  endpoint['portIndex'] == portIndex,
            );
          });
    cabinet['connections'] = connections;
    _touchCabinet(cabinet);
    await _persist();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showSwitchPortSheet({
    required int switchId,
    required int portIndex,
  }) async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final switches = List<Map<String, dynamic>>.from(
      cabinet['switches'] ?? const [],
    );
    final switchIndex = switches.indexWhere((sw) => sw['id'] == switchId);
    if (switchIndex == -1) {
      return;
    }

    final sw = Map<String, dynamic>.from(switches[switchIndex]);
    final portTypes = List<String>.from(_portTypesForSwitch(sw));
    final portComments = List<String>.from(_portCommentsForSwitch(sw));
    if (portIndex < 0 || portIndex >= portTypes.length) {
      return;
    }

    String portType = portTypes[portIndex];
    final commentController = TextEditingController(
      text: portComments[portIndex],
    );
    final connection = _connectionForPort(switchId, portIndex);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            final portTypeLabel =
                _portTypeLabels[portType] ?? _portTypeLabels[_portTypeOptical]!;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Port {value}', {'value': '${portIndex + 1}'}),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${sw['name'] ?? tr('Switch')}'
                    '${(sw['model'] ?? '').toString().trim().isEmpty ? '' : ' | ${sw['model']}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: portType,
                    decoration: InputDecoration(labelText: tr('Port type')),
                    items: _portTypeLabels.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(tr(entry.value)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setStateSheet(() {
                        portType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: commentController,
                    decoration: InputDecoration(labelText: tr('Comment')),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        connection == null
                            ? Icons.link_off
                            : Icons.link_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          connection == null
                              ? tr('Port is not connected')
                              : tr('Connected: {value}', {
                                  'value': _connectionLabel(connection),
                                }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _openPortTraceOnMap(
                            switchId: switchId,
                            portIndex: portIndex,
                          );
                        },
                        icon: const Icon(Icons.route_outlined),
                        label: Text(tr('Trace')),
                      ),
                      if (connection != null)
                        TextButton.icon(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await _removeConnectionForPort(switchId, portIndex);
                            if (mounted) {
                              navigator.pop();
                            }
                          },
                          icon: const Icon(Icons.link_off),
                          label: Text(tr('Disconnect')),
                        ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(tr('Cancel')),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          portTypes[portIndex] = portType;
                          portComments[portIndex] = commentController.text
                              .trim();
                          switches[switchIndex] = {
                            ...sw,
                            'port_types': portTypes,
                            'port_comments': portComments,
                          };
                          cabinet['switches'] = switches;
                          _touchCabinet(cabinet);
                          await _persist();
                          if (!mounted) {
                            return;
                          }
                          setState(() {});
                          navigator.pop();
                        },
                        icon: const Icon(Icons.save),
                        label: Text(tr('Save')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('Type: {value}', {'value': tr(portTypeLabel)}),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addSplitter() async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    var name = '';
    var ratio = 8;
    var side = 0;
    var orientation = 'vertical';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(tr('Add splitter')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: tr('Splitter name'),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => name = value.trim(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: ratio,
                      decoration: InputDecoration(
                        labelText: tr('Split ratio'),
                        border: OutlineInputBorder(),
                      ),
                      items: const [2, 4, 8, 16, 32]
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('1:$value'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setStateDialog(() {
                          ratio = value ?? 8;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: side,
                      decoration: InputDecoration(
                        labelText: tr('Side'),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(value: 0, child: Text(tr('Left'))),
                        DropdownMenuItem(value: 1, child: Text(tr('Right'))),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          side = value ?? 0;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: orientation,
                      decoration: InputDecoration(
                        labelText: tr('Output port layout'),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'vertical',
                          child: Text(tr('Vertical')),
                        ),
                        DropdownMenuItem(
                          value: 'horizontal',
                          child: Text(tr('Horizontal')),
                        ),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          orientation = value ?? 'vertical';
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final splitters = List<Map<String, dynamic>>.from(
                      cabinet['splitters'] ?? const [],
                    );
                    splitters.add({
                      'id': DateTime.now().microsecondsSinceEpoch,
                      'name': name.isEmpty
                          ? tr('Splitter 1:{ratio}', {'ratio': '$ratio'})
                          : name,
                      'ratio': ratio,
                      'side': side,
                      'orientation': orientation,
                    });
                    cabinet['splitters'] = splitters;
                    _touchCabinet(cabinet);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    await _recordTaskAddition(
                      kind: 'Splitter added to cabinet',
                      summary: [
                        '${cabinet['name'] ?? 'Cabinet'}',
                        '${splitters.last['name'] ?? 'Splitter'}',
                        '1:${splitters.last['ratio'] ?? ratio}',
                        'side: ${((splitters.last['side'] as int?) ?? side) == 0 ? 'left' : 'right'}',
                        'orientation: ${((splitters.last['orientation'] ?? orientation) == 'vertical') ? 'vertical' : 'horizontal'}',
                      ].join(' вЂў '),
                      targetRecordId: cabinet['id'] as int?,
                    );
                    setState(() {});
                    navigator.pop();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editSplitter(int splitterId) async {
    final cabinet = _selectedCabinet;
    final splitter = _getSplitterById(splitterId);
    if (cabinet == null || splitter == null) {
      return;
    }

    var name = (splitter['name'] as String?) ?? '';
    var ratio = (splitter['ratio'] as int?) ?? 8;
    var side = (splitter['side'] as int?) ?? 0;
    var orientation = (splitter['orientation'] as String?) ?? 'vertical';
    final nameController = TextEditingController(text: name);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(tr('Edit splitter')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: tr('Splitter name'),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => name = value.trim(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: ratio,
                      decoration: InputDecoration(
                        labelText: tr('Split ratio'),
                        border: OutlineInputBorder(),
                      ),
                      items: const [2, 4, 8, 16, 32]
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('1:$value'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setStateDialog(() {
                          ratio = value ?? 8;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: side,
                      decoration: InputDecoration(
                        labelText: tr('Side'),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(value: 0, child: Text(tr('Left'))),
                        DropdownMenuItem(value: 1, child: Text(tr('Right'))),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          side = value ?? 0;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: orientation,
                      decoration: InputDecoration(
                        labelText: tr('Output port layout'),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'vertical',
                          child: Text(tr('Vertical')),
                        ),
                        DropdownMenuItem(
                          value: 'horizontal',
                          child: Text(tr('Horizontal')),
                        ),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          orientation = value ?? 'vertical';
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    splitter['name'] = nameController.text.trim().isEmpty
                        ? tr('Splitter 1:{ratio}', {'ratio': '$ratio'})
                        : nameController.text.trim();
                    splitter['ratio'] = ratio;
                    splitter['side'] = side;
                    splitter['orientation'] = orientation;
                    _touchCabinet(cabinet);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    setState(() {});
                    navigator.pop();
                  },
                  icon: const Icon(Icons.save),
                  label: Text(tr('Save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteSplitter(int splitterId) async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final splitters = List<Map<String, dynamic>>.from(
      cabinet['splitters'] ?? const [],
    )..removeWhere((splitter) => splitter['id'] == splitterId);
    final connections =
        List<Map<String, dynamic>>.from(cabinet['connections'] ?? const [])
          ..removeWhere((connection) {
            return _connectionTouchesEndpointWhere(
              connection,
              (endpoint) =>
                  endpoint['type'] == 'splitter' &&
                  endpoint['splitterId'] == splitterId,
            );
          });

    cabinet['splitters'] = splitters;
    cabinet['connections'] = connections;
    _touchCabinet(cabinet);
    await _persist();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _addCable() async {
    if (_selectedCabinet == null) {
      return;
    }

    String name = '';
    int fibersNumber = 12;
    String scheme = _fiberSchemes.keys.first;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(tr('Add cable')),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: tr('Direction/name'),
                      ),
                      onChanged: (value) => name = value,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(tr('Fibers:')),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: fibersNumber,
                          items: [1, 2, 4, 8, 12, 16, 24, 32, 48, 64, 96]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setStateDialog(() {
                              fibersNumber = value ?? 12;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(tr('Label:')),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: scheme,
                          items: _fiberSchemes.keys
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setStateDialog(() {
                              scheme = value ?? scheme;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final cabinet = _selectedCabinet!;
                    final cables = List<Map<String, dynamic>>.from(
                      cabinet['cables'] ?? const [],
                    );
                    cables.add({
                      'id': DateTime.now().microsecondsSinceEpoch,
                      'name': name.isEmpty ? tr('Cable') : name,
                      'fibers': fibersNumber,
                      'color_scheme': scheme,
                      'fiber_comments': List<String>.filled(fibersNumber, ''),
                    });
                    cabinet['cables'] = cables;
                    _touchCabinet(cabinet);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    await _recordTaskAddition(
                      kind: 'Cable added to cabinet',
                      summary: [
                        '${cabinet['name'] ?? 'Cabinet'}',
                        '${cables.last['name'] ?? 'Cable'}',
                        'fibers: ${cables.last['fibers'] ?? fibersNumber}',
                        if ((cables.last['color_scheme'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          'label: ${cables.last['color_scheme']}',
                      ].join(' вЂў '),
                      targetRecordId: cabinet['id'] as int?,
                    );
                    setState(() {});
                    navigator.pop();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteCable(int cableId) async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final cables = List<Map<String, dynamic>>.from(
      cabinet['cables'] ?? const [],
    )..removeWhere((cable) => cable['id'] == cableId);
    final connections =
        List<Map<String, dynamic>>.from(cabinet['connections'] ?? const [])
          ..removeWhere((connection) {
            return _connectionTouchesEndpointWhere(
              connection,
              (endpoint) =>
                  endpoint['type'] == 'cable' && endpoint['cableId'] == cableId,
            );
          });

    cabinet['cables'] = cables;
    cabinet['connections'] = connections;
    _touchCabinet(cabinet);
    if (_selectedCableId == cableId) {
      _selectedCableId = null;
    }
    await _persist();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _editCableName(int cableId) async {
    final cable = _getCableById(cableId);
    if (cable == null) {
      return;
    }

    final controller = TextEditingController(text: cable['name'] ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr('Edit cable name')),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Cancel')),
            ),
            FilledButton.tonal(
              onPressed: () async {
                final navigator = Navigator.of(context);
                cable['name'] = controller.text.trim();
                if (_selectedCabinet != null) {
                  _touchCabinet(_selectedCabinet!);
                }
                await _persist();
                if (!mounted) {
                  return;
                }
                setState(() {});
                navigator.pop();
              },
              child: Text(tr('Save')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editFiber(int cableId, int fiberIndex) async {
    final cable = _getCableById(cableId);
    if (cable == null) {
      return;
    }

    final fibersCount = (cable['fibers'] as int?) ?? 1;
    final comments = List<String>.from(cable['fiber_comments'] ?? const []);
    while (comments.length < fibersCount) {
      comments.add('');
    }
    if (fiberIndex >= comments.length) {
      return;
    }

    final commentController = TextEditingController(text: comments[fiberIndex]);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('Cable: {name} | Fiber {fiber}', {
                      'name': '${cable['name']}',
                      'fiber': '${fiberIndex + 1}',
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    decoration: InputDecoration(labelText: tr('Comment')),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(tr('Cancel')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          comments[fiberIndex] = commentController.text.trim();
                          cable['fiber_comments'] = comments;
                          if (_selectedCabinet != null) {
                            _touchCabinet(_selectedCabinet!);
                          }
                          await _persist();
                          if (!mounted) {
                            return;
                          }
                          setState(() {});
                          navigator.pop();
                        },
                        icon: const Icon(Icons.save),
                        label: Text(tr('Save')),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String? _endpointPortType(Map<String, dynamic> endpoint) {
    if (endpoint['type'] != 'switch') {
      return null;
    }
    final switchId = endpoint['switchId'] as int?;
    final portIndex = endpoint['portIndex'] as int?;
    if (switchId == null || portIndex == null) {
      return null;
    }

    final sw = _getSwitchById(switchId);
    if (sw == null) {
      return _portTypeOptical;
    }

    final portTypes = _portTypesForSwitch(sw);
    if (portIndex < 0 || portIndex >= portTypes.length) {
      return _portTypeOptical;
    }

    return portTypes[portIndex];
  }

  String? _validateConnectionTypes(
    Map<String, dynamic> endpoint1,
    Map<String, dynamic> endpoint2,
  ) {
    final isCopperToFiber =
        (_endpointPortType(endpoint1) == _portTypeCopper &&
            endpoint2['type'] == 'cable') ||
        (_endpointPortType(endpoint2) == _portTypeCopper &&
            endpoint1['type'] == 'cable');
    if (isCopperToFiber) {
      return 'A copper port cannot be connected to a cable fiber';
    }

    final isPortToPort =
        endpoint1['type'] == 'switch' &&
        endpoint2['type'] == 'switch' &&
        endpoint1['portIndex'] != null &&
        endpoint2['portIndex'] != null;
    if (!isPortToPort) {
      return null;
    }

    final type1 = _endpointPortType(endpoint1);
    final type2 = _endpointPortType(endpoint2);
    if (type1 != null && type2 != null && type1 != type2) {
      return 'Switch ports of different types cannot be connected';
    }

    return null;
  }

  bool _connectionExists(
    List<Map<String, dynamic>> connections,
    Map<String, dynamic> endpoint1,
    Map<String, dynamic> endpoint2,
  ) {
    return connections.any((entry) {
      if (entry['endpoint1'] is! Map || entry['endpoint2'] is! Map) {
        return false;
      }
      final left = Map<String, dynamic>.from(entry['endpoint1'] as Map);
      final right = Map<String, dynamic>.from(entry['endpoint2'] as Map);
      return (_sameEndpoint(left, endpoint1) &&
              _sameEndpoint(right, endpoint2)) ||
          (_sameEndpoint(left, endpoint2) && _sameEndpoint(right, endpoint1));
    });
  }

  bool _isEndpointBusy(
    List<Map<String, dynamic>> connections,
    Map<String, dynamic> endpoint,
  ) {
    return connections.any((connection) {
      if (connection['endpoint1'] is! Map || connection['endpoint2'] is! Map) {
        return false;
      }
      final left = Map<String, dynamic>.from(connection['endpoint1'] as Map);
      final right = Map<String, dynamic>.from(connection['endpoint2'] as Map);
      return _sameEndpoint(left, endpoint) || _sameEndpoint(right, endpoint);
    });
  }

  Future<void> _addConnectionBetweenEndpoints({
    required Map<String, dynamic> endpoint1,
    required Map<String, dynamic> endpoint2,
  }) async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    if (_sameEndpoint(endpoint1, endpoint2)) {
      _showSnack('A point cannot be connected to itself');
      return;
    }

    if (endpoint1['type'] == 'cable' &&
        endpoint2['type'] == 'cable' &&
        endpoint1['cableId'] == endpoint2['cableId']) {
      _showSnack('Fibers of the same cable cannot be connected');
      return;
    }
    if (endpoint1['type'] == 'switch' &&
        endpoint2['type'] == 'switch' &&
        endpoint1['switchId'] == endpoint2['switchId']) {
      _showSnack('Ports of the same switch cannot be connected');
      return;
    }

    final typeError = _validateConnectionTypes(endpoint1, endpoint2);
    if (typeError != null) {
      _showSnack(typeError);
      return;
    }

    final connections = List<Map<String, dynamic>>.from(
      cabinet['connections'] ?? const [],
    );
    if (_isEndpointBusy(connections, endpoint1) ||
        _isEndpointBusy(connections, endpoint2)) {
      _showSnack('The end point is already in use');
      return;
    }

    if (_connectionExists(connections, endpoint1, endpoint2)) {
      _showSnack('This connection already exists');
      return;
    }

    connections.add({
      'endpoint1': Map<String, dynamic>.from(endpoint1),
      'endpoint2': Map<String, dynamic>.from(endpoint2),
    });
    cabinet['connections'] = connections;
    _touchCabinet(cabinet);
    await _persist();
    if (mounted) {
      await _recordTaskAddition(
        kind: 'Connection added to cabinet',
        summary: [
          cabinet['name']?.toString() ?? 'Cabinet',
          '${_endpointLabel(endpoint1)} в†” ${_endpointLabel(endpoint2)}',
        ].join(' вЂў '),
        targetRecordId: cabinet['id'] as int?,
      );
      _scheduleRebuild();
    }
  }

  Future<void> _addConnection() async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final choices = _endpointChoices(cabinet);
    if (choices.length < 2) {
      _showSnack('At least two connection points are required');
      return;
    }

    var endpoint1 = choices.first.endpoint;
    var endpoint2 = choices.last.endpoint;

    List<DropdownMenuItem<String>> endpointItems() => choices
        .map(
          (choice) => DropdownMenuItem<String>(
            value: choice.key,
            child: Text(choice.label),
          ),
        )
        .toList(growable: false);

    Map<String, dynamic> choiceByKey(String key) =>
        choices.firstWhere((choice) => choice.key == key).endpoint;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(tr('Add connection')),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(tr('From:')),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _endpointKey(endpoint1),
                        items: endpointItems(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setStateDialog(() {
                            endpoint1 = choiceByKey(value);
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(tr('To:')),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _endpointKey(endpoint2),
                        items: endpointItems(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setStateDialog(() {
                            endpoint2 = choiceByKey(value);
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await _addConnectionBetweenEndpoints(
                      endpoint1: endpoint1,
                      endpoint2: endpoint2,
                    );
                    if (!mounted) {
                      return;
                    }
                    navigator.pop();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMapPane() {
    final cabinetsWithCoords = _visibleCabinets
        .where(
          (cabinet) =>
              cabinet['location_lat'] != null &&
              cabinet['location_lng'] != null,
        )
        .toList(growable: false);
    final center = cabinetsWithCoords.isNotEmpty
        ? LatLng(
            cabinetsWithCoords.first['location_lat'] as double,
            cabinetsWithCoords.first['location_lng'] as double,
          )
        : const LatLng(44.9521, 34.1024);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        crs: mapCrsById(_selectedTileLayerId),
        initialCenter: center,
        initialZoom: _mapZoom,
        maxZoom: 19,
        onPositionChanged: (position, _) {
          _mapZoom = position.zoom;
        },
      ),
      children: [
        tileLayerById(_selectedTileLayerId),
        MarkerLayer(
          markers: cabinetsWithCoords
              .map((cabinet) {
                final point = LatLng(
                  cabinet['location_lat'] as double,
                  cabinet['location_lng'] as double,
                );
                return Marker(
                  point: point,
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => _showCabinetFromMap(cabinet),
                    child: const Icon(
                      Icons.dns,
                      color: Colors.lightBlue,
                      size: 32,
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }

  void _showCabinetFromMap(Map<String, dynamic> cabinet) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cabinet['name'] ?? tr('Untitled'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(cabinet['location'] ?? ''),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('Close')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() {
                        _selectedCabinet = cabinet;
                        _mapView = false;
                      });
                      Navigator.of(context).pop();
                    },
                    child: Text(tr('Open')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListPane() {
    final visibleCabinets = _visibleCabinets;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visibleCabinets.isEmpty) {
      return Center(
        child: Text(
          tr('There are no cabinets yet. Add the first record.'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: visibleCabinets.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final cabinet = visibleCabinets[index];
        final selected = _selectedCabinet?['id'] == cabinet['id'];
        return Card(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: _statusDot(cabinet['dirty'] == true),
            title: Text(cabinet['name'] ?? tr('Untitled')),
            subtitle: Text(
              [
                if (_projectNameFor(cabinet) != null)
                  tr('Task: {name}', {'name': _projectNameFor(cabinet)!}),
                (cabinet['location'] ?? '').toString(),
              ].where((line) => line.trim().isNotEmpty).join('\n'),
            ),
            isThreeLine: _projectNameFor(cabinet) != null,
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  _showCabinetEditor(cabinet: cabinet);
                }
                if (value == 'geo') {
                  _openCabinetLocation(cabinet);
                }
                if (value == 'delete') {
                  _deleteCabinet(cabinet);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                PopupMenuItem(value: 'geo', child: Text(tr('Location'))),
                PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
              ],
            ),
            onTap: () => _selectCabinet(cabinet),
          ),
        );
      },
    );
  }

  Widget _statusDot(bool dirty) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: dirty ? Colors.red : Colors.green,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildSwitchCard(Map<String, dynamic> sw) {
    final portsCount = (sw['ports'] as int?) ?? 24;
    final portTypes = _portTypesForSwitch(sw);
    final switchName = (sw['name'] ?? tr('Switch')).toString().trim();
    final switchModel = (sw['model'] ?? '').toString().trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        switchName.isEmpty ? tr('Switch') : switchName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      if (switchModel.isNotEmpty)
                        Text(
                          switchModel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(height: 1.1),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('Port types'),
                  onPressed: () => _editSwitchPortTypes(sw['id'] as int),
                  icon: const Icon(Icons.tune),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
                PopupMenuButton<String>(
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editSwitch(sw['id'] as int);
                    }
                    if (value == 'delete') {
                      _deleteSwitch(sw['id'] as int);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(portsCount, (index) {
                final portType = index < portTypes.length
                    ? portTypes[index]
                    : _portTypeOptical;
                final portColor = _portTypeColor(portType);
                final switchId = sw['id'] as int;
                final endpoint = _switchEndpoint(switchId, index);
                return _ConnectionAnchor(
                  registry: _connectionAnchors,
                  anchorKey: _endpointKey(endpoint),
                  color: portColor,
                  child: DragTarget<Map<String, dynamic>>(
                    onWillAcceptWithDetails: (details) => !_sameEndpoint(
                      Map<String, dynamic>.from(details.data),
                      endpoint,
                    ),
                    onAcceptWithDetails: (details) {
                      _scheduleAddConnectionBetweenEndpoints(
                        endpoint1: Map<String, dynamic>.from(details.data),
                        endpoint2: endpoint,
                      );
                    },
                    builder: (context, candidateData, rejectedData) {
                      final hover = candidateData.isNotEmpty;
                      return Draggable<Map<String, dynamic>>(
                        data: endpoint,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: _portSize,
                            height: _portSize,
                            decoration: BoxDecoration(
                              color: portColor,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: (_portSize * 0.38).clamp(8, 12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: _portSquare(
                            index + 1,
                            hover,
                            portColor,
                            portType,
                          ),
                        ),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showSwitchPortSheet(
                            switchId: switchId,
                            portIndex: index,
                          ),
                          child: _portSquare(
                            index + 1,
                            hover,
                            portColor,
                            portType,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortTypeLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: _portTypeLabels.entries
            .map(
              (entry) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _portTypeColor(entry.key),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    entry.value,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(height: 1.0),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _portSquare(
    int label,
    bool highlight,
    Color color,
    String portType, {
    Key? key,
  }) {
    return Container(
      key: key,
      width: _portSize,
      height: _portSize,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: highlight ? Colors.deepOrange : Colors.black54,
          width: highlight ? 2 : 1,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: Colors.deepOrange.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
      child: Tooltip(
        message:
            'Port $label: ${_portTypeLabels[portType] ?? _portTypeLabels[_portTypeOptical]}',
        child: Center(
          child: Text(
            '$label',
            style: TextStyle(fontSize: (_portSize * 0.38).clamp(8, 12)),
          ),
        ),
      ),
    );
  }

  Widget _buildCableList() {
    final cables = List<Map<String, dynamic>>.from(
      _selectedCabinet?['cables'] ?? const [],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cables.isEmpty) Text(tr('No cables')),
        ...cables.map(_buildCableCard),
      ],
    );
  }

  Widget _buildCableCard(Map<String, dynamic> cable) {
    final scheme = cable['color_scheme'] ?? 'default';
    final colors = _fiberSchemes[scheme] ?? _fiberSchemes.values.first;
    final selected = _selectedCableId == cable['id'];
    final cableName = (cable['name'] ?? tr('Cable')).toString().trim();
    final fibersCount = (cable['fibers'] as int?) ?? 1;

    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedCableId = cable['id'] as int;
          });
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cableName.isEmpty ? tr('Cable') : cableName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          tr('Fibers: {value}', {'value': '$fibersCount'}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(height: 1.1),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'rename') {
                        _editCableName(cable['id'] as int);
                      }
                      if (value == 'delete') {
                        _deleteCable(cable['id'] as int);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'rename', child: Text(tr('Rename'))),
                      PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: List.generate(fibersCount, (index) {
                  final color = colors[index % colors.length];
                  final endpoint = _cableEndpoint(cable['id'] as int, index);
                  final fiberWidget = DragTarget<Map<String, dynamic>>(
                    onWillAcceptWithDetails: (details) => !_sameEndpoint(
                      Map<String, dynamic>.from(details.data),
                      endpoint,
                    ),
                    onAcceptWithDetails: (details) {
                      _scheduleAddConnectionBetweenEndpoints(
                        endpoint1: Map<String, dynamic>.from(details.data),
                        endpoint2: endpoint,
                      );
                    },
                    builder: (context, candidateData, rejectedData) {
                      final hover = candidateData.isNotEmpty;
                      return Draggable<Map<String, dynamic>>(
                        data: endpoint,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: _fiberSize,
                            height: _fiberSize,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: (_fiberSize * 0.42).clamp(8, 12),
                                  color: color == Colors.black
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: _fiberCircle(color, index + 1, hover),
                        ),
                        child: GestureDetector(
                          onTap: () => _editFiber(cable['id'] as int, index),
                          child: _fiberCircle(color, index + 1, hover),
                        ),
                      );
                    },
                  );
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ConnectionAnchor(
                        registry: _connectionAnchors,
                        anchorKey: _endpointKey(endpoint),
                        color: color,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [fiberWidget],
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSplitterList() {
    final left = _getSplittersBySide(0);
    final right = _getSplittersBySide(1);
    if (left.isEmpty && right.isEmpty) {
      return Text(tr('No splitters added'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumns = constraints.maxWidth >= 560;
        final leftColumn = _buildSplitterColumn(0, left);
        final rightColumn = _buildSplitterColumn(1, right);
        if (!useColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [leftColumn, const SizedBox(height: 8), rightColumn],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: leftColumn),
            const SizedBox(width: 12),
            Expanded(child: rightColumn),
          ],
        );
      },
    );
  }

  Widget _buildSplitterColumn(int side, List<Map<String, dynamic>> splitters) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(side == 0 ? 'Left' : 'Right'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (splitters.isEmpty) Text(tr('No items')),
        ...splitters.map((splitter) => _buildSplitterCard(splitter, side)),
      ],
    );
  }

  Widget _buildSplitterCard(Map<String, dynamic> splitter, int side) {
    final ratio = (splitter['ratio'] as int?) ?? 8;
    final splitterId = splitter['id'] as int;
    final orientation = (splitter['orientation'] as String?) == 'horizontal'
        ? 'horizontal'
        : 'vertical';
    final inputColor = Colors.teal;
    final outputColor = Colors.indigo;
    final inputEndpoint = _splitterEndpoint(splitterId, 'input', 0);

    final outputs = List.generate(ratio, (index) {
      final endpoint = _splitterEndpoint(splitterId, 'output', index);
      return _buildSplitterPort(
        endpoint: endpoint,
        label: index + 1,
        accentColor: outputColor,
        isInput: false,
      );
    });

    final outputsWidget = orientation == 'horizontal'
        ? Wrap(spacing: 8, runSpacing: 8, children: outputs)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: outputs
                .map(
                  (port) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: port,
                  ),
                )
                .toList(growable: false),
          );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        splitter['name'] ?? tr('Splitter'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'PON 1:$ratio вЂў ${orientation == 'vertical' ? 'vertical' : 'horizontal'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editSplitter(splitterId);
                    }
                    if (value == 'delete') {
                      _deleteSplitter(splitterId);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'IN',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: inputColor.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                _buildSplitterInput(
                  endpoint: inputEndpoint,
                  accentColor: inputColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'OUT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: outputColor.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: outputsWidget),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitterInput({
    required Map<String, dynamic> endpoint,
    required Color accentColor,
  }) {
    return _buildSplitterPort(
      endpoint: endpoint,
      label: null,
      accentColor: accentColor,
      isInput: true,
    );
  }

  Widget _buildSplitterPort({
    required Map<String, dynamic> endpoint,
    required int? label,
    required Color accentColor,
    required bool isInput,
  }) {
    return _ConnectionAnchor(
      registry: _connectionAnchors,
      anchorKey: _endpointKey(endpoint),
      color: accentColor,
      child: DragTarget<Map<String, dynamic>>(
        onWillAcceptWithDetails: (details) =>
            !_sameEndpoint(Map<String, dynamic>.from(details.data), endpoint),
        onAcceptWithDetails: (details) {
          _scheduleAddConnectionBetweenEndpoints(
            endpoint1: Map<String, dynamic>.from(details.data),
            endpoint2: endpoint,
          );
        },
        builder: (context, candidateData, rejectedData) {
          final isHover = candidateData.isNotEmpty;
          return Draggable<Map<String, dynamic>>(
            data: endpoint,
            feedback: Material(
              color: Colors.transparent,
              child: _splitterPortChip(
                accentColor: accentColor,
                label: label,
                highlight: true,
                isInput: isInput,
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: _splitterPortChip(
                accentColor: accentColor,
                label: label,
                highlight: isHover,
                isInput: isInput,
              ),
            ),
            child: _splitterPortChip(
              accentColor: accentColor,
              label: label,
              highlight: isHover,
              isInput: isInput,
            ),
          );
        },
      ),
    );
  }

  Widget _splitterPortChip({
    required Color accentColor,
    required int? label,
    required bool highlight,
    required bool isInput,
  }) {
    return Container(
      width: isInput ? 42 : 34,
      height: 26,
      decoration: BoxDecoration(
        color: isInput ? Colors.teal.shade50 : Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight ? Colors.deepOrange : accentColor,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Center(
        child: Text(
          label == null ? 'IN' : '$label',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: isInput ? Colors.teal.shade900 : Colors.indigo.shade900,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _fiberCircle(Color color, int label, bool highlight, {Key? key}) {
    return Container(
      key: key,
      width: _fiberSize,
      height: _fiberSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: highlight ? Colors.deepOrange : Colors.black,
          width: highlight ? 2 : 1,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: Colors.deepOrange.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          '$label',
          style: TextStyle(
            fontSize: (_fiberSize * 0.42).clamp(8, 12),
            color: color == Colors.black ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedCableDetails() {
    final cable = _selectedCableId == null
        ? null
        : _getCableById(_selectedCableId!);
    if (cable == null) {
      return const SizedBox.shrink();
    }

    final comments = List<String>.from(cable['fiber_comments'] ?? const []);

    final commentItems = comments
        .asMap()
        .entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .map(
          (entry) => Row(
            children: [
              Text('[${entry.key + 1}]: '),
              Expanded(child: Text(entry.value)),
            ],
          ),
        )
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Cable: {name}', {'name': '${cable['name']}'}),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (commentItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('Fiber comments:')),
            ...commentItems,
          ],
        ],
      ),
    );
  }

  void _showCabinetHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => const _CabinetHelpDialog(),
    );
  }

  void _toggleMapView() {
    setState(() {
      _mapView = !_mapView;
    });
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

  void _handleCompactMenuAction(String value) {
    if (value == 'sync') {
      _syncAll();
    } else if (value == 'refresh') {
      _loadFromStorage();
    } else if (value == 'help') {
      _showCabinetHelp();
    } else if (value.startsWith('layer:')) {
      setState(() {
        _selectedTileLayerId = value.substring(6);
      });
    } else if (value.startsWith('project:')) {
      _applyProjectFilter(value.substring(8));
    }
  }

  List<PopupMenuEntry<String>> _buildCompactMenuItems() {
    return [
      PopupMenuItem<String>(
        value: 'sync',
        enabled: !_syncing,
        child: Text(tr('Sync')),
      ),
      PopupMenuItem<String>(
        value: 'refresh',
        enabled: !_syncing,
        child: Text(tr('Refresh')),
      ),
      PopupMenuItem<String>(value: 'help', child: Text(tr('Screen guide'))),
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
    ];
  }

  Widget _buildDetailPane({bool showBack = false}) {
    if (_selectedCabinet == null) {
      return Center(
        child: Text(
          'Select a cabinet on the left',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final cabinet = _selectedCabinet!;
    final switches = List<Map<String, dynamic>>.from(
      cabinet['switches'] ?? const [],
    );
    final connections = List<Map<String, dynamic>>.from(
      cabinet['connections'] ?? const [],
    );
    _connectionAnchors.clear();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBack)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedCabinet = null;
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: Text(tr('Back to list')),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusDot(cabinet['dirty'] == true),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cabinet['name'] ?? tr('Untitled'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: tr('Location'),
                          onPressed: () => _openCabinetLocation(cabinet),
                          icon: const Icon(Icons.map),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(cabinet['location'] ?? ''),
                    if ((cabinet['comment'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(cabinet['comment'] as String),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  tr('Switches'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addSwitch,
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add')),
                ),
              ],
            ),
          ),
          if (switches.isNotEmpty) _buildPortTypeLegend(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _ConnectionLineLayer(
              registry: _connectionAnchors,
              connections: connections,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (switches.isEmpty)
                    Text(tr('No switches'))
                  else
                    ...switches.map(_buildSwitchCard),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    child: Row(
                      children: [
                        Text(
                          tr('Cables'),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _addCable,
                          icon: const Icon(Icons.add),
                          label: Text(tr('Add cable')),
                        ),
                      ],
                    ),
                  ),
                  _buildCableList(),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    child: Row(
                      children: [
                        Text(
                          tr('Splitters'),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _addSplitter,
                          icon: const Icon(Icons.add),
                          label: Text(tr('Add splitter')),
                        ),
                      ],
                    ),
                  ),
                  _buildSplitterList(),
                ],
              ),
            ),
          ),
          if (_selectedCableId != null) ...[
            const Divider(height: 32),
            _buildSelectedCableDetails(),
          ],
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  tr('Connections'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addConnection,
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add')),
                ),
                if (connections.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      cabinet['connections'] = <Map<String, dynamic>>[];
                      _touchCabinet(cabinet);
                      await _persist();
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: Text(tr('Clear all')),
                  ),
              ],
            ),
          ),
          if (connections.isEmpty)
            Padding(
              padding: EdgeInsets.all(12),
              child: Text(tr('There are no connections yet')),
            )
          else
            Column(
              children: connections
                  .map((connection) {
                    return ListTile(
                      dense: true,
                      leading: IconButton(
                        onPressed: () async {
                          connections.remove(connection);
                          cabinet['connections'] = connections;
                          _touchCabinet(cabinet);
                          await _persist();
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                      title: Text(_connectionLabel(connection)),
                    );
                  })
                  .toList(growable: false),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Network cabinets')),
        actions: [
          ResponsiveAppBarActions(
            breakpoint: 600,
            actions: [
              _buildMapLayerMenu(),
              IconButton(
                onPressed: _syncing ? null : _syncAll,
                icon: Icon(
                  Icons.cloud_upload_outlined,
                  color: _hasDirtyRecords
                      ? Colors.redAccent
                      : Colors.greenAccent,
                ),
                tooltip: tr('Sync'),
              ),
              _buildProjectFilterMenu(),
              IconButton(
                onPressed: _toggleMapView,
                icon: Icon(_mapView ? Icons.list : Icons.map),
                tooltip: _mapView ? tr('List') : tr('Map'),
              ),
              IconButton(
                onPressed: _syncing ? null : _loadFromStorage,
                icon: const Icon(Icons.refresh),
                tooltip: tr('Refresh'),
              ),
              IconButton(
                onPressed: _showCabinetHelp,
                icon: const Icon(Icons.info_outline_rounded),
                tooltip: tr('Screen guide'),
              ),
              IconButton(
                onPressed: () => _showCabinetEditor(),
                icon: const Icon(Icons.add),
                tooltip: tr('New cabinet'),
              ),
            ],
            compactActions: [
              IconButton(
                onPressed: () => _showCabinetEditor(),
                icon: const Icon(Icons.add),
                tooltip: tr('New cabinet'),
              ),
              IconButton(
                onPressed: _toggleMapView,
                icon: Icon(_mapView ? Icons.list : Icons.map),
                tooltip: _mapView ? tr('List') : tr('Map'),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Actions'),
                onSelected: _handleCompactMenuAction,
                itemBuilder: (context) => _buildCompactMenuItems(),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildActiveProjectBanner(),
          ScreenInstruction(
            text: tr(
              'Create a cabinet, select it, then add switches, cables, ports, and connections from the detail pane.',
            ),
            margin: const EdgeInsets.all(12),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_mapView) {
                  return _buildMapPane();
                }

                if (constraints.maxWidth >= 960) {
                  return Row(
                    children: [
                      SizedBox(width: 320, child: _buildListPane()),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildDetailPane()),
                    ],
                  );
                }

                return _selectedCabinet == null
                    ? _buildListPane()
                    : _buildDetailPane(showBack: true);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CabinetHelpDialog extends StatelessWidget {
  const _CabinetHelpDialog();

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
          Expanded(child: Text(tr('Network cabinets guide'))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CabinetHelpSection(
                icon: Icons.add_location_alt_outlined,
                title: tr('Create and edit cabinets'),
                body: tr(
                  'Use the plus button to create a cabinet. Add a name, address/place, comment, and map point. Use the cabinet menu to edit, change location, or delete the cabinet.',
                ),
                image: const _CabinetEditorHelpPicture(),
              ),
              _CabinetHelpSection(
                icon: Icons.view_sidebar_outlined,
                title: tr('List and details'),
                body: tr(
                  'Select a cabinet from the list to open its detail pane. On smaller screens, open a cabinet from the list and use Back to list to return.',
                ),
                image: const _CabinetListHelpPicture(),
              ),
              _CabinetHelpSection(
                icon: Icons.map_outlined,
                title: tr('Map view'),
                body: tr(
                  'Use the map/list button to switch views. In map view, tap a cabinet marker to inspect it and open the cabinet notebook.',
                ),
                image: const _CabinetMapHelpPicture(),
              ),
              _CabinetHelpSection(
                icon: Icons.dns_rounded,
                title: tr('Switches and ports'),
                body: tr(
                  'Press Add in the Switches section to create equipment. Choose the port count and port type, then use each port menu to edit comments, change type, or trace the port on the infrastructure map.',
                ),
                image: const _CabinetSwitchHelpPicture(),
              ),
              _CabinetHelpSection(
                icon: Icons.cable_rounded,
                title: tr('Cables and fibers'),
                body: tr(
                  'Press Add cable to add incoming or outgoing cable fibers. Select a cable to see fiber comments. Rename or delete cables from the cable menu.',
                ),
                image: const _CabinetCableHelpPicture(),
              ),
              _CabinetHelpSection(
                icon: Icons.route_rounded,
                title: tr('Connections'),
                body: tr(
                  'Connect fibers and switch ports by dragging one endpoint onto another, or press Add in the Connections section and choose endpoints manually. Connection lines are drawn over the cabinet scheme.',
                ),
                image: const _CabinetConnectionHelpPicture(),
              ),
              _CabinetHelpSection(
                icon: Icons.layers_outlined,
                title: tr('Filters and map layer'),
                body: tr(
                  'Use the task filter to show all cabinets or only cabinets connected with one task. Use the layers button to change the map background.',
                ),
                image: const _CabinetFilterHelpPicture(),
              ),
              _CabinetHelpSection(
                icon: Icons.cloud_upload_outlined,
                title: tr('Sync and refresh'),
                body: tr(
                  'The colored cloud button uploads local changes. Red means there are unsynced records, green means everything is clean. Refresh reloads cabinet records from storage/cloud.',
                ),
                image: const _CabinetSyncHelpPicture(),
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

class _CabinetHelpSection extends StatelessWidget {
  const _CabinetHelpSection({
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

class _CabinetHelpPictureFrame extends StatelessWidget {
  const _CabinetHelpPictureFrame({required this.child});

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

class _CabinetEditorHelpPicture extends StatelessWidget {
  const _CabinetEditorHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _CabinetHelpPictureFrame(
      child: Center(
        child: Icon(Icons.dns_rounded, color: Color(0xFF8BF0B8), size: 48),
      ),
    );
  }
}

class _CabinetListHelpPicture extends StatelessWidget {
  const _CabinetListHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _CabinetHelpPictureFrame(
      child: CustomPaint(painter: _CabinetListHelpPainter()),
    );
  }
}

class _CabinetMapHelpPicture extends StatelessWidget {
  const _CabinetMapHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _CabinetHelpPictureFrame(
      child: Center(
        child: Icon(Icons.place_rounded, color: Colors.lightBlue, size: 48),
      ),
    );
  }
}

class _CabinetSwitchHelpPicture extends StatelessWidget {
  const _CabinetSwitchHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _CabinetHelpPictureFrame(
      child: CustomPaint(painter: _CabinetSwitchHelpPainter()),
    );
  }
}

class _CabinetCableHelpPicture extends StatelessWidget {
  const _CabinetCableHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _CabinetHelpPictureFrame(
      child: CustomPaint(painter: _CabinetCableHelpPainter()),
    );
  }
}

class _CabinetConnectionHelpPicture extends StatelessWidget {
  const _CabinetConnectionHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _CabinetHelpPictureFrame(
      child: CustomPaint(painter: _CabinetConnectionHelpPainter()),
    );
  }
}

class _CabinetFilterHelpPicture extends StatelessWidget {
  const _CabinetFilterHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _CabinetHelpPictureFrame(
      child: Center(
        child: Icon(
          Icons.workspaces_rounded,
          color: Color(0xFFA6F6E8),
          size: 48,
        ),
      ),
    );
  }
}

class _CabinetSyncHelpPicture extends StatelessWidget {
  const _CabinetSyncHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _CabinetHelpPictureFrame(
      child: Center(
        child: Icon(
          Icons.cloud_upload_outlined,
          color: Color(0xFF35C886),
          size: 48,
        ),
      ),
    );
  }
}

class _CabinetListHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final listPaint = Paint()..color = const Color(0xFF143456);
    final selectedPaint = Paint()..color = const Color(0xFF1E466A);
    final detailPaint = Paint()..color = const Color(0xFF123524);
    final gap = size.width * 0.04;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(gap, gap, size.width * 0.36, size.height - gap * 2),
        const Radius.circular(8),
      ),
      listPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.44,
          gap,
          size.width * 0.52,
          size.height - gap * 2,
        ),
        const Radius.circular(8),
      ),
      detailPaint,
    );
    for (var i = 0; i < 3; i++) {
      final top = gap + 12 + i * 20;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(gap + 10, top, size.width * 0.24, 10),
          const Radius.circular(4),
        ),
        i == 0 ? selectedPaint : Paint()
          ..color = const Color(0xFF50749A),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CabinetSwitchHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()..color = const Color(0xFF143456);
    final portPaint = Paint()..color = const Color(0xFF35C886);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.3,
        size.width * 0.64,
        size.height * 0.4,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, bodyPaint);
    for (var i = 0; i < 6; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * (0.24 + i * 0.09),
            size.height * 0.44,
            12,
            12,
          ),
          const Radius.circular(3),
        ),
        portPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CabinetCableHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.brown,
      Colors.grey,
      Colors.white,
    ];
    final cablePaint = Paint()
      ..color = const Color(0xFF1E466A)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.5),
      Offset(size.width * 0.8, size.height * 0.5),
      cablePaint,
    );
    for (var i = 0; i < colors.length; i++) {
      final x = size.width * (0.22 + i * 0.11);
      canvas.drawCircle(
        Offset(x, size.height * 0.5),
        7,
        Paint()..color = colors[i],
      );
      canvas.drawCircle(
        Offset(x, size.height * 0.5),
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CabinetConnectionHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final left = Offset(size.width * 0.24, size.height * 0.66);
    final right = Offset(size.width * 0.76, size.height * 0.34);
    final path = ui.Path()
      ..moveTo(left.dx, left.dy)
      ..cubicTo(
        size.width * 0.42,
        left.dy,
        size.width * 0.58,
        right.dy,
        right.dx,
        right.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFA629)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(left, 10, Paint()..color = Colors.blue);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: right, width: 22, height: 16),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF35C886),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ConnectionAnchorRegistry {
  final Map<String, _ConnectionAnchorEntry> _entries = {};

  void clear() {
    _entries.clear();
  }

  void update({
    required String key,
    required Offset globalCenter,
    required Color color,
  }) {
    _entries[key] = _ConnectionAnchorEntry(
      globalCenter: globalCenter,
      color: color,
    );
  }

  _ConnectionAnchorEntry? operator [](String key) => _entries[key];
}

class _ConnectionAnchorEntry {
  const _ConnectionAnchorEntry({
    required this.globalCenter,
    required this.color,
  });

  final Offset globalCenter;
  final Color color;
}

class _ConnectionAnchor extends SingleChildRenderObjectWidget {
  const _ConnectionAnchor({
    required this.registry,
    required this.anchorKey,
    required this.color,
    required super.child,
  });

  final _ConnectionAnchorRegistry registry;
  final String anchorKey;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderConnectionAnchor(
      registry: registry,
      anchorKey: anchorKey,
      color: color,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderConnectionAnchor renderObject,
  ) {
    renderObject
      ..registry = registry
      ..anchorKey = anchorKey
      ..color = color;
  }
}

class _RenderConnectionAnchor extends RenderProxyBox {
  _RenderConnectionAnchor({
    required _ConnectionAnchorRegistry registry,
    required String anchorKey,
    required Color color,
  }) : _registry = registry,
       _anchorKey = anchorKey,
       _color = color;

  _ConnectionAnchorRegistry _registry;
  String _anchorKey;
  Color _color;

  set registry(_ConnectionAnchorRegistry value) {
    if (_registry == value) {
      return;
    }
    _registry = value;
    markNeedsPaint();
  }

  set anchorKey(String value) {
    if (_anchorKey == value) {
      return;
    }
    _anchorKey = value;
    markNeedsPaint();
  }

  set color(Color value) {
    if (_color == value) {
      return;
    }
    _color = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!hasSize) {
      return;
    }

    _registry.update(
      key: _anchorKey,
      globalCenter: localToGlobal(Offset(size.width / 2, size.height / 2)),
      color: _color,
    );
  }
}

class _ConnectionLineLayer extends SingleChildRenderObjectWidget {
  const _ConnectionLineLayer({
    required this.registry,
    required this.connections,
    required super.child,
  });

  final _ConnectionAnchorRegistry registry;
  final List<Map<String, dynamic>> connections;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderConnectionLineLayer(
      registry: registry,
      connections: connections,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderConnectionLineLayer renderObject,
  ) {
    renderObject
      ..registry = registry
      ..connections = connections;
  }
}

class _RenderConnectionLineLayer extends RenderProxyBox {
  _RenderConnectionLineLayer({
    required _ConnectionAnchorRegistry registry,
    required List<Map<String, dynamic>> connections,
  }) : _registry = registry,
       _connections = connections;

  static const double _lineWidth = 1.25;
  static const double _lineOpacity = 0.38;

  _ConnectionAnchorRegistry _registry;
  List<Map<String, dynamic>> _connections;

  set registry(_ConnectionAnchorRegistry value) {
    if (_registry == value) {
      return;
    }
    _registry = value;
    markNeedsPaint();
  }

  set connections(List<Map<String, dynamic>> value) {
    if (_connections == value) {
      return;
    }
    _connections = value;
    markNeedsPaint();
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  String? _endpointKey(Map<String, dynamic> connection, bool first) {
    final endpoint = connection[first ? 'endpoint1' : 'endpoint2'];
    if (endpoint is! Map) {
      return null;
    }

    final endpointMap = Map<String, dynamic>.from(endpoint);
    if (endpointMap['type'] == 'switch') {
      final switchId = _asInt(endpointMap['switchId']);
      final portIndex = _asInt(endpointMap['portIndex']);
      if (switchId == null || portIndex == null) {
        return null;
      }
      return 's$switchId:$portIndex';
    }

    if (endpointMap['type'] == 'splitter') {
      final splitterId = _asInt(endpointMap['splitterId']);
      final portIndex = _asInt(endpointMap['portIndex']) ?? 0;
      final portType = endpointMap['portType']?.toString() ?? 'output';
      if (splitterId == null) {
        return null;
      }
      return 'splitter:$splitterId:$portType:$portIndex';
    }

    final cableId = _asInt(endpointMap['cableId']);
    final fiberIndex = _asInt(endpointMap['fiberIndex']);
    if (cableId == null || fiberIndex == null) {
      return null;
    }
    return '$cableId:$fiberIndex';
  }

  double _direction(double value) {
    if (value == 0) {
      return 0;
    }
    return value > 0 ? 1 : -1;
  }

  double _segmentLength(Offset a, Offset b) {
    return (a.dx - b.dx).abs() + (a.dy - b.dy).abs();
  }

  double _min3(double a, double b, double c) {
    var value = a < b ? a : b;
    value = value < c ? value : c;
    return value;
  }

  double _routeY(Offset p1, Offset p2, Size size) {
    final verticalDistance = (p1.dy - p2.dy).abs();
    if (verticalDistance >= 18) {
      return (p1.dy + p2.dy) / 2;
    }

    final lowerY = p1.dy > p2.dy ? p1.dy : p2.dy;
    final upperY = p1.dy < p2.dy ? p1.dy : p2.dy;
    final below = lowerY + 16;
    if (below <= size.height - 4) {
      return below;
    }
    return upperY - 16;
  }

  ui.Path _roundedOrthogonalPath(Offset p1, Offset p2, Size size) {
    final trackY = _routeY(p1, p2, size);
    final points = [p1, Offset(p1.dx, trackY), Offset(p2.dx, trackY), p2];
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    final cornerRadius = (_lineWidth * 5).clamp(6.0, 14.0).toDouble();

    for (var index = 1; index < points.length - 1; index += 1) {
      final previous = points[index - 1];
      final current = points[index];
      final next = points[index + 1];
      final incomingLength = _segmentLength(previous, current);
      final outgoingLength = _segmentLength(current, next);
      final radius = _min3(
        cornerRadius,
        incomingLength / 2,
        outgoingLength / 2,
      );

      if (radius <= 0) {
        path.lineTo(current.dx, current.dy);
        continue;
      }

      final incoming = Offset(
        _direction(current.dx - previous.dx),
        _direction(current.dy - previous.dy),
      );
      final outgoing = Offset(
        _direction(next.dx - current.dx),
        _direction(next.dy - current.dy),
      );
      final beforeCorner = Offset(
        current.dx - incoming.dx * radius,
        current.dy - incoming.dy * radius,
      );
      final afterCorner = Offset(
        current.dx + outgoing.dx * radius,
        current.dy + outgoing.dy * radius,
      );

      path
        ..lineTo(beforeCorner.dx, beforeCorner.dy)
        ..quadraticBezierTo(
          current.dx,
          current.dy,
          afterCorner.dx,
          afterCorner.dy,
        );
    }

    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_connections.isEmpty || !hasSize) {
      return;
    }

    final origin = localToGlobal(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    context.canvas.save();
    context.canvas.translate(offset.dx, offset.dy);

    for (final connection in _connections) {
      final leftKey = _endpointKey(connection, true);
      final rightKey = _endpointKey(connection, false);
      if (leftKey == null || rightKey == null) {
        continue;
      }

      final left = _registry[leftKey];
      final right = _registry[rightKey];
      if (left == null || right == null) {
        continue;
      }

      final p1 = left.globalCenter - origin;
      final p2 = right.globalCenter - origin;
      paint.color = left.color.withValues(alpha: _lineOpacity);
      final path = _roundedOrthogonalPath(p1, p2, size);
      context.canvas.drawPath(path, paint);

      final dotPaint = Paint()..color = paint.color;
      context.canvas.drawCircle(p1, 2.25, dotPaint);
      context.canvas.drawCircle(p2, 2.25, dotPaint);
    }

    context.canvas.restore();
  }
}
