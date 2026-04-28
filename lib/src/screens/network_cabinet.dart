import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../auth/auth_controller.dart';
import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/map_tile_providers.dart';
import '../core/project_scope.dart';
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
  final GlobalKey _fiberAreaKey = GlobalKey();
  final Map<String, GlobalKey> _fiberKeys = {};
  final Set<String> _currentFiberKeys = {};
  final Map<String, Offset> _fiberOffsets = {};
  final Map<String, Color> _fiberColorByKey = {};
  final Map<String, int> _fiberSideByKey = {};

  bool _loading = true;
  bool _syncing = false;
  bool _mapView = false;
  Map<String, dynamic>? _selectedCabinet;
  int? _selectedCableId;
  int? _projectFilterId;
  ProjectSelection? _activeProject;
  double _mapZoom = 14;
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

  String _fiberKey(int cableId, int fiberIndex) => '$cableId:$fiberIndex';

  String _portKey(int switchId, int portIndex) => 's$switchId:$portIndex';

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
        await _syncRepository.writeCache(_cacheKey, _cabinets);
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
      final merged = await _syncRepository.syncAll(
        companyId: _companyId!,
        moduleKey: _moduleKey,
        cacheKey: _cacheKey,
        localRecords: _cabinets,
      );
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
                  ? 'Active task: ${activeProject.name}'
                  : 'No active task selected',
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

  void _scheduleFiberLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final areaContext = _fiberAreaKey.currentContext;
      if (areaContext == null) {
        return;
      }

      final areaBox = areaContext.findRenderObject() as RenderBox?;
      if (areaBox == null || !areaBox.hasSize) {
        return;
      }

      _fiberKeys.removeWhere((key, _) => !_currentFiberKeys.contains(key));

      final nextOffsets = <String, Offset>{};
      for (final entry in _fiberKeys.entries) {
        final currentContext = entry.value.currentContext;
        if (currentContext == null) {
          continue;
        }

        final box = currentContext.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) {
          continue;
        }

        final globalPoint = box.localToGlobal(
          Offset(box.size.width / 2, box.size.height / 2),
        );
        nextOffsets[entry.key] = areaBox.globalToLocal(globalPoint);
      }

      var changed = nextOffsets.length != _fiberOffsets.length;
      if (!changed) {
        for (final entry in nextOffsets.entries) {
          final previous = _fiberOffsets[entry.key];
          if (previous == null ||
              (previous - entry.value).distanceSquared > 0.5) {
            changed = true;
            break;
          }
        }
      }

      if (changed && mounted) {
        setState(() {
          _fiberOffsets
            ..clear()
            ..addAll(nextOffsets);
        });
      }
    });
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
                        ].join(' • '),
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
                      ].join(' • '),
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
            return connection['switch1'] == switchId ||
                connection['switch2'] == switchId;
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
                      'spliters': List<int>.filled(fibersNumber, 0),
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
                      ].join(' • '),
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
            return connection['cable1'] == cableId ||
                connection['cable2'] == cableId;
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

    final comments = List<String>.from(cable['fiber_comments'] ?? const []);
    final spliters = List<int>.from(cable['spliters'] ?? const []);
    if (fiberIndex >= comments.length || fiberIndex >= spliters.length) {
      return;
    }

    final commentController = TextEditingController(text: comments[fiberIndex]);
    int spliter = spliters[fiberIndex];

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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(tr('Splitter:')),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: spliter,
                        items: [0, 2, 4, 8, 16, 32]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value == 0 ? 'No' : '$value'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setStateSheet(() {
                            spliter = value ?? 0;
                          });
                        },
                      ),
                    ],
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
                          spliters[fiberIndex] = spliter;
                          cable['fiber_comments'] = comments;
                          cable['spliters'] = spliters;
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

  bool _isFiberBusy(
    List<Map<String, dynamic>> connections,
    int cableId,
    int fiberIndex,
  ) {
    final cable = _getCableById(cableId);
    final spliters = List<int>.from(cable?['spliters'] ?? const []);
    final hasSpliter =
        fiberIndex >= 0 &&
        fiberIndex < spliters.length &&
        spliters[fiberIndex] > 0;
    if (hasSpliter) {
      return false;
    }

    return connections.any((connection) {
      return (connection['cable1'] == cableId &&
              connection['fiber1'] == fiberIndex) ||
          (connection['cable2'] == cableId &&
              connection['fiber2'] == fiberIndex);
    });
  }

  bool _isPortBusy(
    List<Map<String, dynamic>> connections,
    int switchId,
    int portIndex,
  ) {
    return connections.any((connection) {
      return (connection['switch1'] == switchId &&
              connection['port1'] == portIndex) ||
          (connection['switch2'] == switchId &&
              connection['port2'] == portIndex);
    });
  }

  String? _endpointPortType(Map<String, dynamic> endpoint) {
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
            endpoint2['cableId'] != null) ||
        (_endpointPortType(endpoint2) == _portTypeCopper &&
            endpoint1['cableId'] != null);
    if (isCopperToFiber) {
      return 'A copper port cannot be connected to a cable fiber';
    }

    final isPortToPort =
        endpoint1['switchId'] != null &&
        endpoint2['switchId'] != null &&
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
    Map<String, dynamic> connection,
  ) {
    String keyFor(Map<String, dynamic> item, bool first) {
      if (first && item['cable1'] != null && item['fiber1'] != null) {
        return 'f${item['cable1']}:${item['fiber1']}';
      }
      if (first && item['switch1'] != null && item['port1'] != null) {
        return 'p${item['switch1']}:${item['port1']}';
      }
      if (!first && item['cable2'] != null && item['fiber2'] != null) {
        return 'f${item['cable2']}:${item['fiber2']}';
      }
      if (!first && item['switch2'] != null && item['port2'] != null) {
        return 'p${item['switch2']}:${item['port2']}';
      }
      return '';
    }

    final left = keyFor(connection, true);
    final right = keyFor(connection, false);
    if (left.isEmpty || right.isEmpty) {
      return false;
    }

    return connections.any((entry) {
      final entryLeft = keyFor(entry, true);
      final entryRight = keyFor(entry, false);
      return (left == entryLeft && right == entryRight) ||
          (left == entryRight && right == entryLeft);
    });
  }

  bool _isEndpointBusy(
    List<Map<String, dynamic>> connections,
    Map<String, dynamic> endpoint,
  ) {
    if (endpoint['cableId'] != null && endpoint['fiberIndex'] != null) {
      return _isFiberBusy(
        connections,
        endpoint['cableId'] as int,
        endpoint['fiberIndex'] as int,
      );
    }
    if (endpoint['switchId'] != null && endpoint['portIndex'] != null) {
      return _isPortBusy(
        connections,
        endpoint['switchId'] as int,
        endpoint['portIndex'] as int,
      );
    }
    return false;
  }

  Future<void> _addConnectionUnified(Map<String, dynamic> connection) async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final connections = List<Map<String, dynamic>>.from(
      cabinet['connections'] ?? const [],
    );
    final leftEndpoint = connection['cable1'] != null
        ? {'cableId': connection['cable1'], 'fiberIndex': connection['fiber1']}
        : {'switchId': connection['switch1'], 'portIndex': connection['port1']};
    final rightEndpoint = connection['cable2'] != null
        ? {'cableId': connection['cable2'], 'fiberIndex': connection['fiber2']}
        : {'switchId': connection['switch2'], 'portIndex': connection['port2']};

    if (leftEndpoint['cableId'] != null &&
        rightEndpoint['cableId'] != null &&
        leftEndpoint['cableId'] == rightEndpoint['cableId']) {
      _showSnack('Fibers of the same cable cannot be connected');
      return;
    }
    if (leftEndpoint['switchId'] != null &&
        rightEndpoint['switchId'] != null &&
        leftEndpoint['switchId'] == rightEndpoint['switchId']) {
      _showSnack('Ports of the same switch cannot be connected');
      return;
    }

    final typeError = _validateConnectionTypes(leftEndpoint, rightEndpoint);
    if (typeError != null) {
      _showSnack(typeError);
      return;
    }

    if (_isEndpointBusy(connections, leftEndpoint) ||
        _isEndpointBusy(connections, rightEndpoint)) {
      _showSnack('The end point is already in use');
      return;
    }

    if (_connectionExists(connections, connection)) {
      _showSnack('This connection already exists');
      return;
    }

    connections.add(Map<String, dynamic>.from(connection));
    cabinet['connections'] = connections;
    _touchCabinet(cabinet);
    await _persist();
    if (mounted) {
      await _recordTaskAddition(
        kind: 'Connection added to cabinet',
        summary: [
          cabinet['name']?.toString() ?? 'Cabinet',
          '${_connectionLabelPart(connection, true)} ↔ ${_connectionLabelPart(connection, false)}',
        ].join(' • '),
        targetRecordId: cabinet['id'] as int?,
      );
      setState(() {});
    }
  }

  Future<void> _addConnection() async {
    final cabinet = _selectedCabinet;
    if (cabinet == null) {
      return;
    }

    final cables = List<Map<String, dynamic>>.from(
      cabinet['cables'] ?? const [],
    );
    final switches = List<Map<String, dynamic>>.from(
      cabinet['switches'] ?? const [],
    );
    if (cables.isEmpty && switches.isEmpty) {
      _showSnack('Add cables or switches');
      return;
    }

    String leftType = cables.isNotEmpty ? 'cable' : 'switch';
    String rightType = switches.isNotEmpty ? 'switch' : 'cable';
    int? leftCableId = cables.isNotEmpty ? cables.first['id'] as int : null;
    int? rightCableId = cables.isNotEmpty ? cables.first['id'] as int : null;
    int leftFiber = 0;
    int rightFiber = 0;
    int? leftSwitchId = switches.isNotEmpty
        ? switches.first['id'] as int
        : null;
    int? rightSwitchId = switches.isNotEmpty
        ? switches.last['id'] as int
        : null;
    int leftPort = 0;
    int rightPort = 0;

    List<DropdownMenuItem<int>> cableItems() => cables
        .map(
          (cable) => DropdownMenuItem<int>(
            value: cable['id'] as int,
            child: Text(cable['name'] ?? tr('Cable')),
          ),
        )
        .toList(growable: false);

    List<DropdownMenuItem<int>> switchItems() => switches
        .map(
          (sw) => DropdownMenuItem<int>(
            value: sw['id'] as int,
            child: Text(sw['name'] ?? tr('Switch')),
          ),
        )
        .toList(growable: false);

    List<DropdownMenuItem<int>> fiberItems(int cableId) {
      final cable = cables.firstWhere((item) => item['id'] == cableId);
      final fibersCount = (cable['fibers'] as int?) ?? 1;
      return List.generate(
        fibersCount,
        (index) =>
            DropdownMenuItem<int>(value: index, child: Text('${index + 1}')),
      );
    }

    List<DropdownMenuItem<int>> portItems(int switchId) {
      final sw = switches.firstWhere((item) => item['id'] == switchId);
      final portsCount = (sw['ports'] as int?) ?? 24;
      return List.generate(
        portsCount,
        (index) => DropdownMenuItem<int>(
          value: index,
          child: Text(tr('Port {value}', {'value': '${index + 1}'})),
        ),
      );
    }

    Widget endpointEditor({
      required String label,
      required String type,
      required ValueChanged<String?> onTypeChanged,
      required int? cableId,
      required ValueChanged<int?> onCableChanged,
      required int fiberIndex,
      required ValueChanged<int?> onFiberChanged,
      required int? switchId,
      required ValueChanged<int?> onSwitchChanged,
      required int portIndex,
      required ValueChanged<int?> onPortChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: InputDecoration(labelText: tr('Point type')),
            items: [
              if (cables.isNotEmpty)
                DropdownMenuItem(value: 'cable', child: Text(tr('Cable'))),
              if (switches.isNotEmpty)
                DropdownMenuItem(value: 'switch', child: Text(tr('Switch'))),
            ],
            onChanged: onTypeChanged,
          ),
          const SizedBox(height: 8),
          if (type == 'cable' && cables.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              initialValue: cableId,
              decoration: InputDecoration(labelText: tr('Cable')),
              items: cableItems(),
              onChanged: onCableChanged,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: fiberIndex,
              decoration: InputDecoration(labelText: tr('Fiber')),
              items: fiberItems(cableId ?? cables.first['id'] as int),
              onChanged: onFiberChanged,
            ),
          ],
          if (type == 'switch' && switches.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              initialValue: switchId,
              decoration: InputDecoration(labelText: tr('Switch')),
              items: switchItems(),
              onChanged: onSwitchChanged,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: portIndex,
              decoration: InputDecoration(labelText: tr('Port')),
              items: portItems(switchId ?? switches.first['id'] as int),
              onChanged: onPortChanged,
            ),
          ],
        ],
      );
    }

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
                      endpointEditor(
                        label: 'From',
                        type: leftType,
                        onTypeChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setStateDialog(() {
                            leftType = value;
                          });
                        },
                        cableId: leftCableId,
                        onCableChanged: (value) {
                          setStateDialog(() {
                            leftCableId = value;
                            leftFiber = 0;
                          });
                        },
                        fiberIndex: leftFiber,
                        onFiberChanged: (value) {
                          setStateDialog(() {
                            leftFiber = value ?? 0;
                          });
                        },
                        switchId: leftSwitchId,
                        onSwitchChanged: (value) {
                          setStateDialog(() {
                            leftSwitchId = value;
                            leftPort = 0;
                          });
                        },
                        portIndex: leftPort,
                        onPortChanged: (value) {
                          setStateDialog(() {
                            leftPort = value ?? 0;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      endpointEditor(
                        label: 'To',
                        type: rightType,
                        onTypeChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setStateDialog(() {
                            rightType = value;
                          });
                        },
                        cableId: rightCableId,
                        onCableChanged: (value) {
                          setStateDialog(() {
                            rightCableId = value;
                            rightFiber = 0;
                          });
                        },
                        fiberIndex: rightFiber,
                        onFiberChanged: (value) {
                          setStateDialog(() {
                            rightFiber = value ?? 0;
                          });
                        },
                        switchId: rightSwitchId,
                        onSwitchChanged: (value) {
                          setStateDialog(() {
                            rightSwitchId = value;
                            rightPort = 0;
                          });
                        },
                        portIndex: rightPort,
                        onPortChanged: (value) {
                          setStateDialog(() {
                            rightPort = value ?? 0;
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
                    final connections = List<Map<String, dynamic>>.from(
                      cabinet['connections'] ?? const [],
                    );

                    final leftEndpoint = leftType == 'cable'
                        ? {'cableId': leftCableId, 'fiberIndex': leftFiber}
                        : {'switchId': leftSwitchId, 'portIndex': leftPort};
                    final rightEndpoint = rightType == 'cable'
                        ? {'cableId': rightCableId, 'fiberIndex': rightFiber}
                        : {'switchId': rightSwitchId, 'portIndex': rightPort};

                    if (leftEndpoint['cableId'] != null &&
                        rightEndpoint['cableId'] != null &&
                        leftEndpoint['cableId'] == rightEndpoint['cableId']) {
                      _showSnack(
                        'Fibers of the same cable cannot be connected',
                      );
                      return;
                    }
                    if (leftEndpoint['switchId'] != null &&
                        rightEndpoint['switchId'] != null &&
                        leftEndpoint['switchId'] == rightEndpoint['switchId']) {
                      _showSnack(
                        'Ports of the same switch cannot be connected',
                      );
                      return;
                    }

                    final typeError = _validateConnectionTypes(
                      leftEndpoint,
                      rightEndpoint,
                    );
                    if (typeError != null) {
                      _showSnack(typeError);
                      return;
                    }

                    if (_isEndpointBusy(connections, leftEndpoint) ||
                        _isEndpointBusy(connections, rightEndpoint)) {
                      _showSnack('The end point is already in use');
                      return;
                    }

                    final payload = <String, dynamic>{
                      if (leftEndpoint['cableId'] != null) ...{
                        'cable1': leftEndpoint['cableId'],
                        'fiber1': leftEndpoint['fiberIndex'],
                      } else ...{
                        'switch1': leftEndpoint['switchId'],
                        'port1': leftEndpoint['portIndex'],
                      },
                      if (rightEndpoint['cableId'] != null) ...{
                        'cable2': rightEndpoint['cableId'],
                        'fiber2': rightEndpoint['fiberIndex'],
                      } else ...{
                        'switch2': rightEndpoint['switchId'],
                        'port2': rightEndpoint['portIndex'],
                      },
                    };

                    if (_connectionExists(connections, payload)) {
                      _showSnack('This connection already exists');
                      return;
                    }

                    connections.add(payload);
                    cabinet['connections'] = connections;
                    _touchCabinet(cabinet);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    await _recordTaskAddition(
                      kind: 'Connection added to cabinet',
                      summary: [
                        cabinet['name']?.toString() ?? 'Cabinet',
                        '${_connectionLabelPart(payload, true)} ↔ ${_connectionLabelPart(payload, false)}',
                      ].join(' • '),
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

  String _connectionLabelPart(Map<String, dynamic> connection, bool first) {
    if (first && connection['cable1'] != null && connection['fiber1'] != null) {
      final cable = _getCableById(connection['cable1'] as int);
      return '${cable?['name'] ?? 'Cable'}[${(connection['fiber1'] as int) + 1}]';
    }
    if (!first &&
        connection['cable2'] != null &&
        connection['fiber2'] != null) {
      final cable = _getCableById(connection['cable2'] as int);
      return '${cable?['name'] ?? 'Cable'}[${(connection['fiber2'] as int) + 1}]';
    }
    if (first && connection['switch1'] != null && connection['port1'] != null) {
      final sw = _getSwitchById(connection['switch1'] as int);
      return '${sw?['name'] ?? 'Switch'} port ${(connection['port1'] as int) + 1}';
    }
    if (!first &&
        connection['switch2'] != null &&
        connection['port2'] != null) {
      final sw = _getSwitchById(connection['switch2'] as int);
      return '${sw?['name'] ?? 'Switch'} port ${(connection['port2'] as int) + 1}';
    }
    return 'Point';
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
                  child: Text(
                    '${sw['name'] ?? 'Switch'} ${sw['model'] ?? ''}'.trim(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: tr('Port types'),
                  onPressed: () => _editSwitchPortTypes(sw['id'] as int),
                  icon: const Icon(Icons.tune),
                ),
                PopupMenuButton<String>(
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
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _portTypeLabels.entries
                  .map(
                    (entry) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _portTypeColor(entry.key),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: Colors.black26),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          entry.value,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(portsCount, (index) {
                final portType = index < portTypes.length
                    ? portTypes[index]
                    : _portTypeOptical;
                final portColor = _portTypeColor(portType);
                final keyId = _portKey(sw['id'] as int, index);
                _currentFiberKeys.add(keyId);
                _fiberColorByKey[keyId] = portColor;
                _fiberSideByKey[keyId] = 0;
                final anchorKey = _fiberKeys.putIfAbsent(
                  keyId,
                  () => GlobalKey(),
                );
                return DragTarget<Map<String, dynamic>>(
                  onWillAcceptWithDetails: (_) => true,
                  onAcceptWithDetails: (details) {
                    final data = details.data;
                    final connection = data['cableId'] != null
                        ? {
                            'cable1': data['cableId'],
                            'fiber1': data['fiberIndex'],
                            'switch2': sw['id'],
                            'port2': index,
                          }
                        : {
                            'switch1': data['switchId'],
                            'port1': data['portIndex'],
                            'switch2': sw['id'],
                            'port2': index,
                          };
                    _addConnectionUnified(connection);
                  },
                  builder: (context, candidateData, rejectedData) {
                    final hover = candidateData.isNotEmpty;
                    return Draggable<Map<String, dynamic>>(
                      data: {'switchId': sw['id'], 'portIndex': index},
                      feedback: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: portColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 10),
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
                        onTap: () => _openPortTraceOnMap(
                          switchId: sw['id'] as int,
                          portIndex: index,
                        ),
                        child: _portSquare(
                          index + 1,
                          hover,
                          portColor,
                          portType,
                          key: anchorKey,
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
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
      width: 26,
      height: 26,
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
          child: Text('$label', style: const TextStyle(fontSize: 10)),
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
    final spliters = List<int>.from(cable['spliters'] ?? const []);
    final selected = _selectedCableId == cable['id'];

    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedCableId = cable['id'] as int;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cable['name'] ?? 'Cable',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  PopupMenuButton<String>(
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
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate((cable['fibers'] as int?) ?? 1, (
                  index,
                ) {
                  final color = colors[index % colors.length];
                  final spliter = index < spliters.length ? spliters[index] : 0;
                  final keyId = _fiberKey(cable['id'] as int, index);
                  _currentFiberKeys.add(keyId);
                  _fiberColorByKey[keyId] = color;
                  _fiberSideByKey[keyId] = 0;
                  final anchorKey = _fiberKeys.putIfAbsent(
                    keyId,
                    () => GlobalKey(),
                  );
                  final fiberWidget = DragTarget<Map<String, dynamic>>(
                    onWillAcceptWithDetails: (_) => true,
                    onAcceptWithDetails: (details) {
                      final data = details.data;
                      final connection = data['cableId'] != null
                          ? {
                              'cable1': data['cableId'],
                              'fiber1': data['fiberIndex'],
                              'cable2': cable['id'],
                              'fiber2': index,
                            }
                          : {
                              'switch1': data['switchId'],
                              'port1': data['portIndex'],
                              'cable2': cable['id'],
                              'fiber2': index,
                            };
                      _addConnectionUnified(connection);
                    },
                    builder: (context, candidateData, rejectedData) {
                      final hover = candidateData.isNotEmpty;
                      return Draggable<Map<String, dynamic>>(
                        data: {'cableId': cable['id'], 'fiberIndex': index},
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 11,
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
                          child: _fiberCircle(
                            color,
                            index + 1,
                            hover,
                            key: spliter > 0 ? null : anchorKey,
                          ),
                        ),
                      );
                    },
                  );
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      fiberWidget,
                      if (spliter > 0) const SizedBox(width: 6),
                      if (spliter > 0) _spliterBadge(spliter, key: anchorKey),
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

  Widget _fiberCircle(Color color, int label, bool highlight, {Key? key}) {
    return Container(
      key: key,
      width: 28,
      height: 28,
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
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          '$label',
          style: TextStyle(
            fontSize: 11,
            color: color == Colors.black ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _spliterBadge(int spliter, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '1:$spliter',
        style: const TextStyle(color: Colors.white, fontSize: 10),
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
    final spliters = List<int>.from(cable['spliters'] ?? const []);

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

    final spliterItems = spliters
        .asMap()
        .entries
        .where((entry) => entry.value != 0)
        .map(
          (entry) => Row(
            children: [
              Text('[${entry.key + 1}]: '),
              Text(tr('Splitter {value}', {'value': '${entry.value}'})),
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
          if (spliterItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('Splitters:')),
            ...spliterItems,
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
    _currentFiberKeys.clear();
    _fiberColorByKey.clear();
    _fiberSideByKey.clear();
    _scheduleFiberLayout();

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  width: constraints.maxWidth,
                  child: Stack(
                    key: _fiberAreaKey,
                    alignment: Alignment.topLeft,
                    children: [
                      Column(
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
                        ],
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _ConnectionsPainter(
                              connections: connections,
                              positions: _fiberOffsets,
                              colors: _fiberColorByKey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
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
                      title: Text(
                        '${_connectionLabelPart(connection, true)} <--> ${_connectionLabelPart(connection, false)}',
                      ),
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
          PopupMenuButton<String>(
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
          ),
          IconButton(
            onPressed: _syncing ? null : _syncAll,
            icon: Icon(
              Icons.cloud_upload_outlined,
              color: _hasDirtyRecords ? Colors.redAccent : Colors.greenAccent,
            ),
            tooltip: tr('Sync'),
          ),
          PopupMenuButton<String>(
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
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _mapView = !_mapView;
              });
            },
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
                  'Press Add in the Switches section to create equipment. Choose the port count and port type, then use each port menu to edit comments, change type, add splitter data, or trace the port on the infrastructure map.',
                ),
                image: const _CabinetSwitchHelpPicture(),
              ),
              _CabinetHelpSection(
                icon: Icons.cable_rounded,
                title: tr('Cables and fibers'),
                body: tr(
                  'Press Add cable to add incoming or outgoing cable fibers. Select a cable to see fiber comments and splitter marks. Rename or delete cables from the cable menu.',
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

class _ConnectionsPainter extends CustomPainter {
  const _ConnectionsPainter({
    required this.connections,
    required this.positions,
    required this.colors,
  });

  final List<Map<String, dynamic>> connections;
  final Map<String, Offset> positions;
  final Map<String, Color> colors;

  String _fiberKey(int cableId, int fiberIndex) => '$cableId:$fiberIndex';

  String _portKey(int switchId, int portIndex) => 's$switchId:$portIndex';

  Offset? _positionFor(Map<String, dynamic> connection, bool first) {
    String key;
    if (first) {
      if (connection['cable1'] != null && connection['fiber1'] != null) {
        key = _fiberKey(
          connection['cable1'] as int,
          connection['fiber1'] as int,
        );
      } else if (connection['switch1'] != null && connection['port1'] != null) {
        key = _portKey(
          connection['switch1'] as int,
          connection['port1'] as int,
        );
      } else {
        return null;
      }
    } else {
      if (connection['cable2'] != null && connection['fiber2'] != null) {
        key = _fiberKey(
          connection['cable2'] as int,
          connection['fiber2'] as int,
        );
      } else if (connection['switch2'] != null && connection['port2'] != null) {
        key = _portKey(
          connection['switch2'] as int,
          connection['port2'] as int,
        );
      } else {
        return null;
      }
    }

    return positions[key];
  }

  Color _colorFor(Map<String, dynamic> connection, bool first) {
    if (first && connection['cable1'] != null && connection['fiber1'] != null) {
      return colors[_fiberKey(
            connection['cable1'] as int,
            connection['fiber1'] as int,
          )] ??
          Colors.deepOrange;
    }
    if (!first &&
        connection['cable2'] != null &&
        connection['fiber2'] != null) {
      return colors[_fiberKey(
            connection['cable2'] as int,
            connection['fiber2'] as int,
          )] ??
          Colors.deepOrange;
    }
    return Colors.grey;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final connection in connections) {
      final p1 = _positionFor(connection, true);
      final p2 = _positionFor(connection, false);
      if (p1 == null || p2 == null) {
        continue;
      }

      paint.color = _colorFor(connection, true).withValues(alpha: 0.75);
      final midX = (p1.dx + p2.dx) / 2;
      final path = ui.Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(midX, p1.dy, midX, p2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);

      final dotPaint = Paint()..color = paint.color;
      canvas.drawCircle(p1, 3, dotPaint);
      canvas.drawCircle(p2, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) {
    return oldDelegate.connections != connections ||
        oldDelegate.positions != positions ||
        oldDelegate.colors != colors;
  }
}
