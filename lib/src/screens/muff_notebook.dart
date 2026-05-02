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
import 'muff_location_picker.dart';

class MuffNotebookPage extends StatefulWidget {
  const MuffNotebookPage({
    super.key,
    required this.controller,
    this.initialMuffId,
  });

  final AuthController controller;
  final int? initialMuffId;

  @override
  State<MuffNotebookPage> createState() => _MuffNotebookPageState();
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

class _MuffNotebookPageState extends State<MuffNotebookPage> {
  static const String _allDistrictsValue = '__all_districts__';
  static const String _moduleKey = 'muff_notebook';
  static const String _muffsCacheKey = 'muff_notebook.muffs.v3';

  final List<Map<String, dynamic>> _muffs = [];
  List<Map<String, dynamic>> _projectRecords = const [];
  late final CompanyModuleSyncRepository _syncRepository;
  bool _loadingMuffs = true;
  bool _syncing = false;
  Map<String, dynamic>? _selectedMuff;
  int? _selectedCableId;
  String? _districtFilter;
  int? _projectFilterId;
  ProjectSelection? _activeProject;
  bool _mapView = false;
  Timer? _syncTimer;

  final MapController _mapController = MapController();
  double _mapZoom = 14;
  String _selectedTileLayerId = 'osm';

  final GlobalKey _fiberAreaKey = GlobalKey();
  final Map<String, GlobalKey> _fiberKeys = {};
  Map<String, Offset> _fiberOffsets = {};
  final Set<String> _currentFiberKeys = {};
  final Map<String, Color> _fiberColorByKey = {};
  final Map<String, int> _fiberSideByKey = {};

  static int _nextMuffId = 1;

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

  String _fiberKey(int cableId, int fiberIndex) => '$cableId:$fiberIndex';

  String _splitterPortKey(int splitterId, String portType, int portIndex) =>
      'splitter:$splitterId:$portType:$portIndex';

  Map<String, dynamic> _cableEndpoint(int cableId, int fiberIndex) => {
    'type': 'cable',
    'cableId': cableId,
    'fiberIndex': fiberIndex,
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

  bool _sameEndpoint(Map<String, dynamic> a, Map<String, dynamic> b) =>
      _endpointKey(a) == _endpointKey(b);

  Map<String, dynamic> _normalizeConnection(Map<String, dynamic> raw) {
    if (raw['endpoint1'] is Map && raw['endpoint2'] is Map) {
      return {
        'endpoint1': Map<String, dynamic>.from(raw['endpoint1'] as Map),
        'endpoint2': Map<String, dynamic>.from(raw['endpoint2'] as Map),
      };
    }

    return {
      'endpoint1': _cableEndpoint(
        (raw['cable1'] as int?) ?? 0,
        (raw['fiber1'] as int?) ?? 0,
      ),
      'endpoint2': _cableEndpoint(
        (raw['cable2'] as int?) ?? 0,
        (raw['fiber2'] as int?) ?? 0,
      ),
    };
  }

  List<Map<String, dynamic>> _normalizedConnections(Map<String, dynamic> muff) {
    final rawConnections = List<Map<String, dynamic>>.from(
      muff['connections'] ?? [],
    );
    return rawConnections.map(_normalizeConnection).toList(growable: true);
  }

  List<Map<String, dynamic>> _getSplittersBySide(int side) {
    final muff = _selectedMuff;
    if (muff == null) {
      return const [];
    }

    return List<Map<String, dynamic>>.from(muff['splitters'] ?? const [])
        .where((splitter) => (splitter['side'] as int? ?? 0) == side)
        .toList(growable: false);
  }

  Map<String, dynamic>? _getSplitterById(int id) {
    final muff = _selectedMuff;
    if (muff == null) {
      return null;
    }

    final splitters = List<Map<String, dynamic>>.from(
      muff['splitters'] ?? const [],
    );
    for (final splitter in splitters) {
      if (splitter['id'] == id) {
        return splitter;
      }
    }

    return null;
  }

  List<_EndpointChoice> _endpointChoices(Map<String, dynamic> muff) {
    final choices = <_EndpointChoice>[];
    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? const []);
    for (final cable in cables) {
      final fibers = (cable['fibers'] as int?) ?? 1;
      for (var i = 0; i < fibers; i++) {
        final endpoint = _cableEndpoint(cable['id'] as int, i);
        choices.add(
          _EndpointChoice(
            key: _endpointKey(endpoint),
            label: '${cable['name'] ?? 'Cable'} • Fiber ${i + 1}',
            endpoint: endpoint,
          ),
        );
      }
    }

    final splitters = List<Map<String, dynamic>>.from(
      muff['splitters'] ?? const [],
    );
    for (final splitter in splitters) {
      final ratio = (splitter['ratio'] as int?) ?? 8;
      final input = _splitterEndpoint(splitter['id'] as int, 'input', 0);
      choices.add(
        _EndpointChoice(
          key: _endpointKey(input),
          label: '${splitter['name'] ?? 'Splitter'} • Input',
          endpoint: input,
        ),
      );

      for (var i = 0; i < ratio; i++) {
        final output = _splitterEndpoint(splitter['id'] as int, 'output', i);
        choices.add(
          _EndpointChoice(
            key: _endpointKey(output),
            label: '${splitter['name'] ?? 'Splitter'} • Output ${i + 1}',
            endpoint: output,
          ),
        );
      }
    }

    return choices;
  }

  String _endpointLabel(Map<String, dynamic> endpoint) {
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

  bool _isPonBox(Map<String, dynamic> muff) => muff['is_pon_box'] == true;

  List<String> get _districtOptions {
    final districts =
        _muffs
            .where((m) => m['deleted'] != true)
            .map((m) => (m['district'] as String?)?.trim() ?? '')
            .where((district) => district.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return districts;
  }

  List<Map<String, dynamic>> get _visibleMuffs {
    final filter = _districtFilter?.trim();
    final visible = _muffs
        .where((m) => m['deleted'] != true)
        .where((m) => matchesProjectFilter(m, _projectFilterId));
    if (filter == null || filter.isEmpty) {
      return visible.toList();
    }

    return visible
        .where((m) => ((m['district'] as String?)?.trim() ?? '') == filter)
        .toList();
  }

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

  String? _projectNameFor(Map<String, dynamic> record) {
    final projectId = projectIdOf(record);
    if (projectId == null) {
      return null;
    }
    return _projectOptions[projectId];
  }

  bool get _hasDirtyRecords => _muffs.any(
    (record) => record['deleted'] != true && record['dirty'] == true,
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
      targetScreen: 'muff_notebook',
      targetRecordId: targetRecordId,
    );
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_syncAll());
    });
  }

  Future<void> _loadFromStorage() async {
    final selectedMuffId =
        (_selectedMuff?['id'] as int?) ?? widget.initialMuffId;
    final selectedCableId = _selectedCableId;
    _activeProject = await _syncRepository.readActiveProject();
    _projectRecords = await _syncRepository.readCache(projectsCacheKey);

    _muffs
      ..clear()
      ..addAll(await _syncRepository.readCache(_muffsCacheKey));
    _nextMuffId =
        _muffs
            .map((record) => (record['id'] as int?) ?? 0)
            .fold(0, (current, next) => current > next ? current : next) +
        1;
    _rebuildNotebook(
      selectedMuffId: selectedMuffId,
      selectedCableId: selectedCableId,
    );

    try {
      if (!_muffs.any((record) => record['dirty'] == true) &&
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
          localRecords: _muffs,
        );
        _muffs
          ..clear()
          ..addAll(merged);
        await _syncRepository.writeCache(_muffsCacheKey, _muffs);
        _nextMuffId =
            _muffs
                .map((record) => (record['id'] as int?) ?? 0)
                .fold(0, (current, next) => current > next ? current : next) +
            1;
      }
    } catch (error, stackTrace) {
      logUserFacingError(
        'Failed to load closures from Supabase.',
        source: 'muff_notebook.load',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnack('Failed to load closures from the cloud.');
    }

    _rebuildNotebook(
      selectedMuffId: selectedMuffId,
      selectedCableId: selectedCableId,
      loading: false,
    );
  }

  void _applyProjectFilter(String value) {
    final nextFilter = value == '__all_projects__' ? null : int.tryParse(value);
    setState(() {
      _projectFilterId = nextFilter;
      _selectedCableId = null;
      if (_selectedMuff != null &&
          !matchesProjectFilter(_selectedMuff!, _projectFilterId)) {
        _selectedMuff = null;
      }
    });
  }

  Future<void> _persist() async {
    await _refreshActiveProject();
    _hydrateDirtyMuffsWithActiveProject();
    await _syncRepository.writeCache(_muffsCacheKey, _muffs);
  }

  Future<void> _refreshActiveProject() async {
    _activeProject = await _syncRepository.readActiveProject();
  }

  void _hydrateDirtyMuffsWithActiveProject() {
    final activeProject = _activeProject;
    if (activeProject == null) {
      return;
    }

    for (final muff in _muffs) {
      if (muff['dirty'] == true && projectIdOf(muff) == null) {
        applyProjectSelection(muff, activeProject);
      }
    }
  }

  void _touchMuff(Map<String, dynamic> muff) {
    if (projectIdOf(muff) == null && _activeProject != null) {
      applyProjectSelection(muff, _activeProject);
    }
    muff['updated_at'] = DateTime.now();
    muff['dirty'] = true;
  }

  void _rebuildNotebook({
    int? selectedMuffId,
    int? selectedCableId,
    bool loading = false,
  }) {
    _muffs.sort((a, b) {
      final at = _syncRepository.parseTime(a['updated_at']);
      final bt = _syncRepository.parseTime(b['updated_at']);
      return bt.compareTo(at);
    });

    Map<String, dynamic>? selectedMuff;
    if (selectedMuffId != null) {
      for (final muff in _muffs) {
        if (muff['deleted'] == true) {
          continue;
        }
        if (muff['id'] == selectedMuffId) {
          selectedMuff = muff;
          break;
        }
      }
    }

    _selectedMuff = selectedMuff;
    if (selectedMuff == null) {
      _selectedCableId = null;
    } else if (selectedCableId != null &&
        List<Map<String, dynamic>>.from(
          selectedMuff['cables'] ?? [],
        ).any((cable) => cable['id'] == selectedCableId)) {
      _selectedCableId = selectedCableId;
    } else {
      _selectedCableId = null;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loadingMuffs = loading;
    });
  }

  Future<void> _syncAll() async {
    if (_syncing || _companyId == null) {
      return;
    }

    final selectedMuffId = _selectedMuff?['id'] as int?;
    final selectedCableId = _selectedCableId;

    setState(() {
      _syncing = true;
    });

    try {
      await _refreshActiveProject();
      _hydrateDirtyMuffsWithActiveProject();
      final merged = await _syncRepository.syncAll(
        companyId: _companyId!,
        moduleKey: _moduleKey,
        cacheKey: _muffsCacheKey,
        localRecords: _muffs,
      );
      _muffs
        ..clear()
        ..addAll(merged);
      _nextMuffId =
          _muffs
              .map((record) => (record['id'] as int?) ?? 0)
              .fold(0, (current, next) => current > next ? current : next) +
          1;
      _rebuildNotebook(
        selectedMuffId: selectedMuffId,
        selectedCableId: selectedCableId,
      );
    } catch (error, stackTrace) {
      logUserFacingError(
        'Failed to synchronize closures.',
        source: 'muff_notebook.sync',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnack('Closure sync error.');
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  void _applyDistrictFilter(String district) {
    final normalized = district == _allDistrictsValue ? null : district.trim();
    final nextFilter = (normalized == null || normalized.isEmpty)
        ? null
        : normalized;
    final nextVisible = nextFilter == null
        ? _muffs.where((m) => m['deleted'] != true).toList()
        : _muffs
              .where((m) => m['deleted'] != true)
              .where(
                (m) => ((m['district'] as String?)?.trim() ?? '') == nextFilter,
              )
              .toList();

    setState(() {
      _districtFilter = nextFilter;
      if (_selectedMuff != null &&
          !nextVisible.any((m) => m['id'] == _selectedMuff!['id'])) {
        _selectedMuff = null;
      }
    });
  }

  void _scheduleFiberLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final areaCtx = _fiberAreaKey.currentContext;
      if (areaCtx == null) {
        return;
      }

      final areaBox = areaCtx.findRenderObject() as RenderBox?;
      if (areaBox == null || !areaBox.hasSize) {
        return;
      }

      _fiberKeys.removeWhere((key, _) => !_currentFiberKeys.contains(key));

      final newOffsets = <String, Offset>{};
      for (final entry in _fiberKeys.entries) {
        final ctx = entry.value.currentContext;
        if (ctx == null) {
          continue;
        }

        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) {
          continue;
        }

        final side = _fiberSideByKey[entry.key] ?? 0;
        final edgeOffset = side == 0
            ? Offset(box.size.width, box.size.height / 2)
            : Offset(0, box.size.height / 2);
        final globalPoint = box.localToGlobal(edgeOffset);
        newOffsets[entry.key] = areaBox.globalToLocal(globalPoint);
      }

      bool changed = newOffsets.length != _fiberOffsets.length;
      if (!changed) {
        for (final entry in newOffsets.entries) {
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
          _fiberOffsets = newOffsets;
        });
      }
    });
  }

  Future<void> _selectMuff(Map<String, dynamic> muff) async {
    setState(() {
      _selectedMuff = muff;
      _selectedCableId = null;
    });
  }

  Future<void> _showMuffEditor({Map<String, dynamic>? muff}) async {
    final nameController = TextEditingController(text: muff?['name'] ?? '');
    final districtController = TextEditingController(
      text: muff?['district'] ?? '',
    );
    final locationController = TextEditingController(
      text: muff?['location'] ?? '',
    );
    final commentController = TextEditingController(
      text: muff?['comment'] ?? '',
    );
    double? lat = muff?['location_lat'] as double?;
    double? lng = muff?['location_lng'] as double?;
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
    var isPonBox = _isPonBox(muff ?? const <String, dynamic>{});

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(tr(muff == null ? 'New closure' : 'Edit closure')),
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
                        controller: districtController,
                        decoration: InputDecoration(labelText: tr('Area')),
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
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: isPonBox,
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr('This is a PON box')),
                        subtitle: Text(
                          tr(
                            'The flag is saved in the closure card and synced between employees.',
                          ),
                        ),
                        onChanged: (value) {
                          setStateDialog(() {
                            isPonBox = value;
                          });
                        },
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
                      'district': districtController.text.trim(),
                      'location': locationController.text.trim(),
                      'comment': commentController.text.trim(),
                      'is_pon_box': isPonBox,
                      'location_lat': lat,
                      'location_lng': lng,
                      'updated_at': DateTime.now(),
                      'updated_by': _actorLabel,
                    };

                    if (muff == null) {
                      payload['id'] = _nextMuffId++;
                      payload['created_by'] = _actorLabel;
                      payload['cables'] = <Map<String, dynamic>>[];
                      payload['connections'] = <Map<String, dynamic>>[];
                      payload['splitters'] = <Map<String, dynamic>>[];
                      payload['deleted'] = false;
                      payload['dirty'] = true;
                      applyProjectSelection(payload, _activeProject);
                      _muffs.add(payload);
                    } else {
                      payload['id'] = muff['id'];
                      payload['created_by'] = muff['created_by'];
                      payload['cables'] =
                          muff['cables'] ?? <Map<String, dynamic>>[];
                      payload['connections'] =
                          muff['connections'] ?? <Map<String, dynamic>>[];
                      payload['splitters'] =
                          muff['splitters'] ?? <Map<String, dynamic>>[];
                      if (projectIdOf(muff) == null && _activeProject != null) {
                        applyProjectSelection(payload, _activeProject);
                      } else {
                        payload['task_id'] = muff['task_id'];
                      }
                      payload['dirty'] = true;
                      final idx = _muffs.indexWhere(
                        (m) => m['id'] == muff['id'],
                      );
                      if (idx != -1) {
                        _muffs[idx] = payload;
                      }
                    }

                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    if (muff == null) {
                      await _recordTaskAddition(
                        kind: tr('Closure added'),
                        summary: [
                          if (payload['name']?.toString().trim().isNotEmpty ==
                              true)
                            payload['name'].toString().trim()
                          else
                            tr('Untitled'),
                          if ((payload['district'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            tr('area: {value}', {
                              'value': payload['district'].toString().trim(),
                            }),
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
                    await _selectMuff(payload);
                    setState(() {});
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: Text(tr('Save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteMuff(Map<String, dynamic> muff) async {
    muff['deleted'] = true;
    _touchMuff(muff);
    if (_selectedMuff?['id'] == muff['id']) {
      _selectedMuff = null;
    }
    await _persist();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openMuffLocation(Map<String, dynamic> muff) async {
    final lat = muff['location_lat'] as double?;
    final lng = muff['location_lng'] as double?;
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

    if (result != null) {
      await _syncRepository.writeLastPickedLocation(result);
      muff['location_lat'] = result.latitude;
      muff['location_lng'] = result.longitude;
      _touchMuff(muff);
      await _persist();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Map<String, dynamic>? _getCableById(int id) {
    final muff = _selectedMuff;
    if (muff == null) {
      return null;
    }

    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? []);
    return cables.firstWhere((c) => c['id'] == id, orElse: () => {});
  }

  List<Map<String, dynamic>> _getCablesBySide(int side) {
    final muff = _selectedMuff;
    if (muff == null) {
      return [];
    }

    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? []);
    return cables.where((c) => (c['side'] as int? ?? 0) == side).toList();
  }

  Future<void> _addCable() async {
    if (_selectedMuff == null) {
      return;
    }

    String name = '';
    int fibersNumber = 12;
    int side = 0;
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
                        Text(tr('Side:')),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: side,
                          items: [
                            DropdownMenuItem(value: 0, child: Text(tr('Left'))),
                            DropdownMenuItem(
                              value: 1,
                              child: Text(tr('Right')),
                            ),
                          ],
                          onChanged: (value) {
                            setStateDialog(() {
                              side = value ?? 0;
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
                    final muff = _selectedMuff!;
                    final cables = List<Map<String, dynamic>>.from(
                      muff['cables'] ?? [],
                    );
                    cables.add({
                      'id': DateTime.now().microsecondsSinceEpoch,
                      'name': name.isEmpty ? tr('Cable') : name,
                      'fibers': fibersNumber,
                      'side': side,
                      'color_scheme': scheme,
                      'fiber_comments': List<String>.filled(fibersNumber, ''),
                    });
                    muff['cables'] = cables;
                    _touchMuff(muff);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    await _recordTaskAddition(
                      kind: 'Cable added to closure',
                      summary: [
                        '${muff['name'] ?? 'Closure'}',
                        '${cables.last['name'] ?? 'Cable'}',
                        'fibers: ${cables.last['fibers'] ?? fibersNumber}',
                        'side: ${((cables.last['side'] as int?) ?? side) == 0 ? 'left' : 'right'}',
                        if ((cables.last['color_scheme'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          'label: ${cables.last['color_scheme']}',
                      ].join(' • '),
                      targetRecordId: muff['id'] as int?,
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
    final muff = _selectedMuff;
    if (muff == null) {
      return;
    }

    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? []);
    cables.removeWhere((c) => c['id'] == cableId);
    muff['cables'] = cables;

    final connections = _normalizedConnections(muff);
    connections.removeWhere((connection) {
      final endpoint1 = Map<String, dynamic>.from(
        connection['endpoint1'] as Map,
      );
      final endpoint2 = Map<String, dynamic>.from(
        connection['endpoint2'] as Map,
      );
      return endpoint1['cableId'] == cableId || endpoint2['cableId'] == cableId;
    });
    muff['connections'] = connections;

    _touchMuff(muff);
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
    if (cable == null || cable.isEmpty) {
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
                if (_selectedMuff != null) {
                  _touchMuff(_selectedMuff!);
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

  Future<void> _toggleCableSide(int cableId) async {
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) {
      return;
    }

    final current = (cable['side'] as int?) ?? 0;
    cable['side'] = current == 0 ? 1 : 0;
    if (_selectedMuff != null) {
      _touchMuff(_selectedMuff!);
    }
    await _persist();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _editFiber(int cableId, int fiberIndex) async {
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) {
      return;
    }

    final comments = List<String>.from(cable['fiber_comments'] ?? []);
    if (fiberIndex >= comments.length) {
      return;
    }

    final commentController = TextEditingController(text: comments[fiberIndex]);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
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
                      if (_selectedMuff != null) {
                        _touchMuff(_selectedMuff!);
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
  }

  Future<void> _addConnection() async {
    final muff = _selectedMuff;
    if (muff == null) {
      return;
    }

    final choices = _endpointChoices(muff);
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
              content: Column(
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
                  const SizedBox(height: 12),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('Cancel')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final success = await _addConnectionBetweenEndpoints(
                      endpoint1: endpoint1,
                      endpoint2: endpoint2,
                    );
                    if (!success || !mounted) {
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

  Future<void> _addConnectionDirect({
    required Map<String, dynamic> endpoint1,
    required Map<String, dynamic> endpoint2,
  }) async {
    await _addConnectionBetweenEndpoints(
      endpoint1: endpoint1,
      endpoint2: endpoint2,
    );
  }

  Future<bool> _addConnectionBetweenEndpoints({
    required Map<String, dynamic> endpoint1,
    required Map<String, dynamic> endpoint2,
  }) async {
    final muff = _selectedMuff;
    if (muff == null) {
      return false;
    }

    if (_sameEndpoint(endpoint1, endpoint2)) {
      _showSnack('A point cannot be connected to itself');
      return false;
    }

    if ((endpoint1['type'] == 'cable') &&
        (endpoint2['type'] == 'cable') &&
        endpoint1['cableId'] == endpoint2['cableId']) {
      _showSnack('Fibers of the same cable cannot be connected');
      return false;
    }

    final connections = _normalizedConnections(muff);
    if (_isEndpointBusy(connections, endpoint1) ||
        _isEndpointBusy(connections, endpoint2)) {
      _showSnack('Connection point is already occupied');
      return false;
    }

    if (_connectionExists(connections, endpoint1, endpoint2)) {
      _showSnack('This connection already exists');
      return false;
    }

    connections.add({
      'endpoint1': Map<String, dynamic>.from(endpoint1),
      'endpoint2': Map<String, dynamic>.from(endpoint2),
    });
    muff['connections'] = connections;
    _touchMuff(muff);
    await _persist();
    if (mounted) {
      await _recordTaskAddition(
        kind: 'Connection added to closure',
        summary: [
          muff['name']?.toString() ?? 'Closure',
          '${_endpointLabel(endpoint1)} ↔ ${_endpointLabel(endpoint2)}',
        ].join(' • '),
        targetRecordId: muff['id'] as int?,
      );
      setState(() {});
    }
    return true;
  }

  bool _isEndpointBusy(
    List<Map<String, dynamic>> connections,
    Map<String, dynamic> endpoint,
  ) {
    return connections.any((connection) {
      final a = Map<String, dynamic>.from(connection['endpoint1'] as Map);
      final b = Map<String, dynamic>.from(connection['endpoint2'] as Map);
      return _sameEndpoint(a, endpoint) || _sameEndpoint(b, endpoint);
    });
  }

  bool _connectionExists(
    List<Map<String, dynamic>> connections,
    Map<String, dynamic> endpoint1,
    Map<String, dynamic> endpoint2,
  ) {
    return connections.any((connection) {
      final a = Map<String, dynamic>.from(connection['endpoint1'] as Map);
      final b = Map<String, dynamic>.from(connection['endpoint2'] as Map);
      return (_sameEndpoint(a, endpoint1) && _sameEndpoint(b, endpoint2)) ||
          (_sameEndpoint(a, endpoint2) && _sameEndpoint(b, endpoint1));
    });
  }

  Future<void> _addSplitter() async {
    final muff = _selectedMuff;
    if (muff == null) {
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
                      muff['splitters'] ?? const [],
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
                    muff['splitters'] = splitters;
                    _touchMuff(muff);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    await _recordTaskAddition(
                      kind: 'Splitter added to closure',
                      summary: [
                        '${muff['name'] ?? 'Closure'}',
                        '${splitters.last['name'] ?? 'Splitter'}',
                        '1:${splitters.last['ratio'] ?? ratio}',
                        'side: ${((splitters.last['side'] as int?) ?? side) == 0 ? 'left' : 'right'}',
                        'orientation: ${((splitters.last['orientation'] ?? orientation) == 'vertical') ? 'vertical' : 'horizontal'}',
                      ].join(' • '),
                      targetRecordId: muff['id'] as int?,
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
    final muff = _selectedMuff;
    final splitter = _getSplitterById(splitterId);
    if (muff == null || splitter == null) {
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
                    _touchMuff(muff);
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
    final muff = _selectedMuff;
    if (muff == null) {
      return;
    }

    final splitters = List<Map<String, dynamic>>.from(
      muff['splitters'] ?? const [],
    )..removeWhere((splitter) => splitter['id'] == splitterId);
    muff['splitters'] = splitters;

    final connections = _normalizedConnections(muff)
      ..removeWhere((connection) {
        final endpoint1 = Map<String, dynamic>.from(
          connection['endpoint1'] as Map,
        );
        final endpoint2 = Map<String, dynamic>.from(
          connection['endpoint2'] as Map,
        );
        return endpoint1['splitterId'] == splitterId ||
            endpoint2['splitterId'] == splitterId;
      });
    muff['connections'] = connections;

    _touchMuff(muff);
    await _persist();
    if (mounted) {
      setState(() {});
    }
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

  void _showClosureNotebookHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => const _ClosureNotebookHelpDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Closure notebook')),
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
            tooltip: tr('Area filter'),
            icon: Icon(
              _districtFilter == null
                  ? Icons.filter_list
                  : Icons.filter_list_alt,
            ),
            onSelected: _applyDistrictFilter,
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: _allDistrictsValue,
                checked: _districtFilter == null,
                child: Text(tr('All areas')),
              ),
              ..._districtOptions.map(
                (district) => CheckedPopupMenuItem<String>(
                  value: district,
                  checked: _districtFilter == district,
                  child: Text(district),
                ),
              ),
            ],
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
            onPressed: _showClosureNotebookHelp,
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: tr('Screen guide'),
          ),
          IconButton(
            onPressed: () => _showMuffEditor(),
            icon: const Icon(Icons.add),
            tooltip: tr('New closure'),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildActiveProjectBanner(),
          ScreenInstruction(
            text: tr(
              'Create a closure, select it in the list, then add cables, splitters, and connections in the detail pane.',
            ),
            margin: const EdgeInsets.all(12),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_mapView) {
                  return _buildMapPane();
                }

                if (constraints.maxWidth >= 900) {
                  return Row(
                    children: [
                      SizedBox(width: 320, child: _buildListPane()),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildDetailPane()),
                    ],
                  );
                }

                return _selectedMuff == null
                    ? _buildListPane()
                    : _buildDetailPane(showBack: true);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPane() {
    final muffsWithCoords = _visibleMuffs
        .where((m) => m['location_lat'] != null && m['location_lng'] != null)
        .toList();
    final center = muffsWithCoords.isNotEmpty
        ? LatLng(
            muffsWithCoords.first['location_lat'] as double,
            muffsWithCoords.first['location_lng'] as double,
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
          markers: muffsWithCoords.map((muff) {
            final point = LatLng(
              muff['location_lat'] as double,
              muff['location_lng'] as double,
            );
            return Marker(
              point: point,
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => _showMuffFromMap(muff),
                child: const Icon(Icons.place, color: Colors.red, size: 32),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showMuffFromMap(Map<String, dynamic> muff) {
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
                muff['name'] ?? tr('Untitled'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_isPonBox(muff)) ...[
                const SizedBox(height: 6),
                _ponBadge(context),
              ],
              const SizedBox(height: 6),
              if (((muff['district'] as String?)?.trim() ?? '').isNotEmpty)
                Text(tr('Area: {value}', {'value': '${muff['district']}'})),
              if (((muff['district'] as String?)?.trim() ?? '').isNotEmpty)
                const SizedBox(height: 6),
              Text(muff['location'] ?? ''),
              const SizedBox(height: 6),
              Text(
                '${(muff['location_lat'] as double).toStringAsFixed(6)}, '
                '${(muff['location_lng'] as double).toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
                        _selectedMuff = muff;
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
    final visibleMuffs = _visibleMuffs;
    if (_loadingMuffs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visibleMuffs.isEmpty &&
        _muffs.where((muff) => muff['deleted'] != true).isEmpty) {
      return Center(
        child: Text(
          tr('There are no closures yet. Add the first record.'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    if (visibleMuffs.isEmpty) {
      return Center(
        child: Text(
          'There are no closures in the selected area yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: visibleMuffs.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final muff = visibleMuffs[index];
        final selected = _selectedMuff?['id'] == muff['id'];
        return Card(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: _statusDot(muff['dirty'] == true),
            title: Text(muff['name'] ?? 'Untitled'),
            subtitle: Text(
              [
                if (_isPonBox(muff)) 'Type: PON box',
                if (_projectNameFor(muff) != null)
                  'Task: ${_projectNameFor(muff)}',
                if (((muff['district'] as String?)?.trim() ?? '').isNotEmpty)
                  'Area: ${muff['district']}',
                if ((muff['location'] ?? '').toString().trim().isNotEmpty)
                  (muff['location'] ?? '').toString().trim(),
              ].join('\n'),
            ),
            isThreeLine:
                ((muff['district'] as String?)?.trim() ?? '').isNotEmpty &&
                (muff['location'] ?? '').toString().trim().isNotEmpty,
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  _showMuffEditor(muff: muff);
                }
                if (value == 'geo') {
                  _openMuffLocation(muff);
                }
                if (value == 'delete') {
                  _deleteMuff(muff);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                PopupMenuItem(value: 'geo', child: Text(tr('Location'))),
                PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
              ],
            ),
            onTap: () => _selectMuff(muff),
          ),
        );
      },
    );
  }

  Widget _buildDetailPane({bool showBack = false}) {
    if (_selectedMuff == null) {
      return Center(
        child: Text(
          'Select a closure on the left',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final muff = _selectedMuff!;
    final connections = _normalizedConnections(muff);
    _currentFiberKeys.clear();
    _fiberColorByKey.clear();
    _fiberSideByKey.clear();
    _scheduleFiberLayout();

    return SingleChildScrollView(
      child: Column(
        children: [
          if (showBack)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedMuff = null;
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
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusDot(muff['dirty'] == true),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            muff['name'] ?? 'Untitled',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: tr('Location'),
                          onPressed: () => _openMuffLocation(muff),
                          icon: const Icon(Icons.map),
                        ),
                      ],
                    ),
                    if (_isPonBox(muff)) ...[
                      const SizedBox(height: 8),
                      _ponBadge(context),
                    ],
                    const SizedBox(height: 4),
                    if (((muff['district'] as String?)?.trim() ?? '')
                        .isNotEmpty)
                      Text(
                        tr('Area: {value}', {'value': '${muff['district']}'}),
                      ),
                    if (((muff['district'] as String?)?.trim() ?? '')
                        .isNotEmpty)
                      const SizedBox(height: 4),
                    Text(muff['location'] ?? ''),
                    if (muff['location_lat'] != null &&
                        muff['location_lng'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.place, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${(muff['location_lat'] as double).toStringAsFixed(6)}, '
                              '${(muff['location_lng'] as double).toStringAsFixed(6)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _openMuffLocation(muff),
                              icon: const Icon(Icons.map),
                              label: Text(tr('Change')),
                            ),
                          ],
                        ),
                      ),
                    if ((muff['comment'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(muff['comment']),
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
                const Text(
                  'Cables',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                const Text(
                  'Splitters',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              key: _fiberAreaKey,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildCableColumn(0)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildCableColumn(1)),
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
          ),
          const Divider(),
          if (_selectedCableId != null) _buildSelectedCableDetails(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text(
                  'Connections',
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
                      muff['connections'] = <Map<String, dynamic>>[];
                      _touchMuff(muff);
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
              children: connections.map((connection) {
                return ListTile(
                  dense: true,
                  leading: IconButton(
                    onPressed: () async {
                      connections.remove(connection);
                      muff['connections'] = connections;
                      _touchMuff(muff);
                      await _persist();
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                  title: Text(
                    '${_endpointLabel(Map<String, dynamic>.from(connection['endpoint1'] as Map))} '
                    '<--> '
                    '${_endpointLabel(Map<String, dynamic>.from(connection['endpoint2'] as Map))}',
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCableColumn(int side) {
    final cables = _getCablesBySide(side);
    final splitters = _getSplittersBySide(side);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(side == 0 ? 'Left' : 'Right'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (cables.isEmpty && splitters.isEmpty) Text(tr('No items')),
        ...cables.map((cable) {
          final isSelected = _selectedCableId == cable['id'];
          return Card(
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
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
                            cable['name'] ?? tr('Cable'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'rename') {
                              _editCableName(cable['id'] as int);
                            }
                            if (value == 'swap') {
                              _toggleCableSide(cable['id'] as int);
                            }
                            if (value == 'delete') {
                              _deleteCable(cable['id'] as int);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text(tr('Rename')),
                            ),
                            PopupMenuItem(
                              value: 'swap',
                              child: Text(tr('Move to the other side')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(tr('Delete')),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate((cable['fibers'] as int?) ?? 1, (
                        index,
                      ) {
                        final scheme = cable['color_scheme'] ?? 'default';
                        final colors =
                            _fiberSchemes[scheme] ?? _fiberSchemes.values.first;
                        final color = colors[index % colors.length];
                        final keyId = _fiberKey(cable['id'] as int, index);
                        _currentFiberKeys.add(keyId);
                        _fiberColorByKey[keyId] = color;
                        _fiberSideByKey[keyId] = side;
                        final anchorKey = _fiberKeys.putIfAbsent(
                          keyId,
                          () => GlobalKey(),
                        );

                        final endpoint = _cableEndpoint(
                          cable['id'] as int,
                          index,
                        );

                        final fiberWidget = DragTarget<Map<String, dynamic>>(
                          onWillAcceptWithDetails: (_) => true,
                          onAcceptWithDetails: (details) {
                            final data = Map<String, dynamic>.from(
                              details.data,
                            );
                            _addConnectionDirect(
                              endpoint1: data,
                              endpoint2: endpoint,
                            );
                          },
                          builder: (context, candidateData, rejectedData) {
                            final isHover = candidateData.isNotEmpty;
                            return Draggable<Map<String, dynamic>>(
                              data: endpoint,
                              feedback: Material(
                                color: Colors.transparent,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.black,
                                      width: 2,
                                    ),
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
                                child: _fiberCircle(color, index + 1, isHover),
                              ),
                              child: GestureDetector(
                                onTap: () =>
                                    _editFiber(cable['id'] as int, index),
                                child: _fiberCircle(
                                  color,
                                  index + 1,
                                  isHover,
                                  key: anchorKey,
                                ),
                              ),
                            );
                          },
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [fiberWidget],
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
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
    final inputKeyId = _endpointKey(inputEndpoint);
    _currentFiberKeys.add(inputKeyId);
    _fiberColorByKey[inputKeyId] = inputColor;
    _fiberSideByKey[inputKeyId] = side == 0 ? 1 : 0;
    final inputKey = _fiberKeys.putIfAbsent(inputKeyId, () => GlobalKey());

    final outputs = List.generate(ratio, (index) {
      final endpoint = _splitterEndpoint(splitterId, 'output', index);
      final keyId = _endpointKey(endpoint);
      _currentFiberKeys.add(keyId);
      _fiberColorByKey[keyId] = outputColor;
      _fiberSideByKey[keyId] = side == 0 ? 0 : 1;
      final key = _fiberKeys.putIfAbsent(keyId, () => GlobalKey());
      return _buildSplitterPort(
        endpoint: endpoint,
        key: key,
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
                      //const SizedBox(height: 2),
                      //Text('PON 1:$ratio • ${orientation == 'vertical' ? 'vertical' : 'horizontal'}', style: Theme.of(context).textTheme.bodySmall,),
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
                  key: inputKey,
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
    required Key key,
    required Color accentColor,
  }) {
    return _buildSplitterPort(
      endpoint: endpoint,
      key: key,
      label: null,
      accentColor: accentColor,
      isInput: true,
    );
  }

  Widget _buildSplitterPort({
    required Map<String, dynamic> endpoint,
    required Key key,
    required int? label,
    required Color accentColor,
    required bool isInput,
  }) {
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) =>
          !_sameEndpoint(Map<String, dynamic>.from(details.data), endpoint),
      onAcceptWithDetails: (details) {
        _addConnectionDirect(
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
              key: key,
              accentColor: accentColor,
              label: label,
              highlight: isHover,
              isInput: isInput,
            ),
          ),
          child: _splitterPortChip(
            key: key,
            accentColor: accentColor,
            label: label,
            highlight: isHover,
            isInput: isInput,
          ),
        );
      },
    );
  }

  Widget _splitterPortChip({
    Key? key,
    required Color accentColor,
    required int? label,
    required bool highlight,
    required bool isInput,
  }) {
    return Container(
      key: key,
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

  Widget _buildSelectedCableDetails() {
    final cable = _getCableById(_selectedCableId!);
    if (cable == null || cable.isEmpty) {
      return const SizedBox.shrink();
    }

    final comments = List<String>.from(cable['fiber_comments'] ?? []);

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
        .toList();

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
            const SizedBox(height: 6),
            Text(tr('Fiber comments:')),
            ...commentItems,
          ],
        ],
      ),
    );
  }

  Widget _ponBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.secondary.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        tr('PON box'),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ClosureNotebookHelpDialog extends StatelessWidget {
  const _ClosureNotebookHelpDialog();

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
          Expanded(child: Text(tr('Closure notebook guide'))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MuffHelpSection(
                icon: Icons.add_location_alt_outlined,
                title: tr('Create and edit closures'),
                body: tr(
                  'Use the plus button to create a closure. Fill in the name, area, address, comment, map point, and PON box flag. Use the item menu to edit, move on the map, or delete a closure.',
                ),
                image: const _MuffEditorHelpPicture(),
              ),
              _MuffHelpSection(
                icon: Icons.view_sidebar_outlined,
                title: tr('List and details'),
                body: tr(
                  'Select a closure in the left list to open its detail pane. On narrow screens, open a closure from the list and use Back to list to return.',
                ),
                image: const _MuffListHelpPicture(),
              ),
              _MuffHelpSection(
                icon: Icons.map_outlined,
                title: tr('Map view'),
                body: tr(
                  'Switch between list and map with the map/list button. In map view, tap a marker to inspect the closure and open it in the notebook.',
                ),
                image: const _MuffMapHelpPicture(),
              ),
              _MuffHelpSection(
                icon: Icons.cable_rounded,
                title: tr('Cables and fibers'),
                body: tr(
                  'Open a closure and press Add cable. Choose fiber count, side, color scheme, and label. Tap a fiber to add a comment, rename cables from the cable menu, or move them to the other side.',
                ),
                image: const _MuffCableHelpPicture(),
              ),
              _MuffHelpSection(
                icon: Icons.call_split_rounded,
                title: tr('Splitters'),
                body: tr(
                  'Press Add splitter to add a PON splitter. Choose ratio, side, and orientation. Splitter ports can be connected to fibers or other endpoints.',
                ),
                image: const _MuffSplitterHelpPicture(),
              ),
              _MuffHelpSection(
                icon: Icons.route_rounded,
                title: tr('Connections'),
                body: tr(
                  'Create connections by dragging one fiber or splitter port onto another, or press Add in the Connections section and choose endpoints manually. Use Clear all only when the whole connection scheme should be removed.',
                ),
                image: const _MuffConnectionHelpPicture(),
              ),
              _MuffHelpSection(
                icon: Icons.layers_outlined,
                title: tr('Filters and map layer'),
                body: tr(
                  'Use the area filter to show one district, the task filter to show objects linked to a task, and the layers button to change the map background.',
                ),
                image: const _MuffFilterHelpPicture(),
              ),
              _MuffHelpSection(
                icon: Icons.cloud_upload_outlined,
                title: tr('Sync and refresh'),
                body: tr(
                  'The colored cloud button uploads local changes. Red means there are unsynced records, green means the notebook is clean. Refresh reloads records from storage/cloud.',
                ),
                image: const _MuffSyncHelpPicture(),
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

class _MuffHelpSection extends StatelessWidget {
  const _MuffHelpSection({
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

class _MuffHelpPictureFrame extends StatelessWidget {
  const _MuffHelpPictureFrame({required this.child});

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

class _MuffEditorHelpPicture extends StatelessWidget {
  const _MuffEditorHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _MuffHelpPictureFrame(
      child: Center(
        child: Icon(
          Icons.add_location_alt_outlined,
          color: Color(0xFF8BF0B8),
          size: 48,
        ),
      ),
    );
  }
}

class _MuffListHelpPicture extends StatelessWidget {
  const _MuffListHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _MuffHelpPictureFrame(
      child: CustomPaint(painter: _MuffListHelpPainter()),
    );
  }
}

class _MuffMapHelpPicture extends StatelessWidget {
  const _MuffMapHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _MuffHelpPictureFrame(
      child: Center(
        child: Icon(Icons.place_rounded, color: Colors.redAccent, size: 48),
      ),
    );
  }
}

class _MuffCableHelpPicture extends StatelessWidget {
  const _MuffCableHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _MuffHelpPictureFrame(
      child: CustomPaint(painter: _MuffCableHelpPainter()),
    );
  }
}

class _MuffSplitterHelpPicture extends StatelessWidget {
  const _MuffSplitterHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _MuffHelpPictureFrame(
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

class _MuffConnectionHelpPicture extends StatelessWidget {
  const _MuffConnectionHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _MuffHelpPictureFrame(
      child: CustomPaint(painter: _MuffConnectionHelpPainter()),
    );
  }
}

class _MuffFilterHelpPicture extends StatelessWidget {
  const _MuffFilterHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _MuffHelpPictureFrame(
      child: Center(
        child: Icon(Icons.filter_list_alt, color: Color(0xFFA6F6E8), size: 48),
      ),
    );
  }
}

class _MuffSyncHelpPicture extends StatelessWidget {
  const _MuffSyncHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _MuffHelpPictureFrame(
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

class _MuffListHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final listPaint = Paint()..color = const Color(0xFF143456);
    final selectedPaint = Paint()..color = const Color(0xFF1E466A);
    final detailPaint = Paint()..color = const Color(0xFF123524);
    final gap = size.width * 0.04;
    final listRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(gap, gap, size.width * 0.36, size.height - gap * 2),
      const Radius.circular(8),
    );
    final detailRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.44,
        gap,
        size.width * 0.52,
        size.height - gap * 2,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(listRect, listPaint);
    canvas.drawRRect(detailRect, detailPaint);
    for (var i = 0; i < 3; i++) {
      final top = gap + 12 + i * 20;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(gap + 10, top, size.width * 0.24, 10),
          const Radius.circular(4),
        ),
        i == 1 ? selectedPaint : Paint()
          ..color = const Color(0xFF50749A),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MuffCableHelpPainter extends CustomPainter {
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

class _MuffConnectionHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final left = Offset(size.width * 0.24, size.height * 0.35);
    final right = Offset(size.width * 0.76, size.height * 0.65);
    final path = ui.Path()
      ..moveTo(left.dx, left.dy)
      ..cubicTo(
        size.width * 0.48,
        left.dy,
        size.width * 0.52,
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
    canvas.drawCircle(right, 10, Paint()..color = Colors.indigo);
    canvas.drawCircle(
      left,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    canvas.drawCircle(
      right,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
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

  String _key(Map<String, dynamic> endpoint) {
    if (endpoint['type'] == 'splitter') {
      return 'splitter:${endpoint['splitterId']}:${endpoint['portType']}:${endpoint['portIndex']}';
    }

    return '${endpoint['cableId']}:${endpoint['fiberIndex']}';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final connection in connections) {
      final endpoint1Raw = connection['endpoint1'];
      final endpoint2Raw = connection['endpoint2'];
      if (endpoint1Raw is! Map || endpoint2Raw is! Map) {
        continue;
      }

      final endpoint1 = Map<String, dynamic>.from(endpoint1Raw);
      final endpoint2 = Map<String, dynamic>.from(endpoint2Raw);
      final key1 = _key(endpoint1);
      final key2 = _key(endpoint2);
      final p1 = positions[key1];
      final p2 = positions[key2];
      if (p1 == null || p2 == null) {
        continue;
      }

      paint.color = (colors[key1] ?? Colors.deepOrange).withValues(alpha: 0.75);

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
