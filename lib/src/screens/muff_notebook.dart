import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/map_tile_providers.dart';
import '../core/project_scope.dart';
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
            label: '${cable['name'] ?? 'Кабель'} • Волокно ${i + 1}',
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
          label: '${splitter['name'] ?? 'Делитель'} • Вход',
          endpoint: input,
        ),
      );

      for (var i = 0; i < ratio; i++) {
        final output = _splitterEndpoint(splitter['id'] as int, 'output', i);
        choices.add(
          _EndpointChoice(
            key: _endpointKey(output),
            label: '${splitter['name'] ?? 'Делитель'} • Выход ${i + 1}',
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
      final name = splitter?['name'] ?? 'Делитель';
      final portType = (endpoint['portType'] as String?) ?? 'output';
      if (portType == 'input') {
        return '$name[Вход]';
      }

      return '$name[Выход ${(endpoint['portIndex'] as int) + 1}]';
    }

    final cable = _getCableById(endpoint['cableId'] as int);
    return '${cable?['name'] ?? 'Кабель'}[${(endpoint['fiberIndex'] as int) + 1}]';
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
    for (final muff in _muffs) {
      if (muff['deleted'] == true) {
        continue;
      }
      final id = projectIdOf(muff);
      final name = projectNameOf(muff);
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
    final selectedMuffId = (_selectedMuff?['id'] as int?) ?? widget.initialMuffId;
    final selectedCableId = _selectedCableId;
    _activeProject = await _syncRepository.readActiveProject();

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
        'Не удалось загрузить муфты из Supabase.',
        source: 'muff_notebook.load',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnack('Не удалось загрузить муфты из облака.');
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
    await _syncRepository.writeCache(_muffsCacheKey, _muffs);
  }

  void _touchMuff(Map<String, dynamic> muff) {
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
        'Не удалось синхронизировать муфты.',
        source: 'muff_notebook.sync',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnack('Ошибка синхронизации муфт.');
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
              title: Text(muff == null ? 'Новая муфта' : 'Редактировать муфту'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Название',
                        ),
                      ),
                      TextField(
                        controller: districtController,
                        decoration: const InputDecoration(labelText: 'Район'),
                      ),
                      TextField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: 'Адрес/место',
                        ),
                      ),
                      TextField(
                        controller: commentController,
                        decoration: const InputDecoration(
                          labelText: 'Комментарий',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: isPonBox,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Это PON бокс'),
                        subtitle: const Text(
                          'Флаг сохраняется в карточке муфты и синхронизируется между сотрудниками.',
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
                                  : 'Геопозиция не задана',
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
                            label: const Text('На карте'),
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
                  child: const Text('Отмена'),
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
                      payload['project_id'] = muff['project_id'];
                      payload['project_name'] = muff['project_name'];
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
                        kind: 'Добавлена муфта',
                        summary: [
                          if (payload['name']?.toString().trim().isNotEmpty ==
                              true)
                            payload['name'].toString().trim()
                          else
                            'Без названия',
                          if ((payload['district'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            'район: ${payload['district'].toString().trim()}',
                          if ((payload['location'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            payload['location'].toString().trim(),
                          if ((payload['comment'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            'примечание: ${payload['comment'].toString().trim()}',
                        ].join(' • '),
                        targetRecordId: payload['id'] as int?,
                      );
                    }
                    navigator.pop();
                    await _selectMuff(payload);
                    setState(() {});
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Сохранить'),
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
    final initial =
        lat != null && lng != null
            ? LatLng(lat, lng)
            : await _syncRepository.readLastPickedLocation();
    if (!mounted) {
      return;
    }
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MuffLocationPickerPage(
          initial: initial,
        ),
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
              title: const Text('Добавить кабель'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Направление/имя',
                      ),
                      onChanged: (value) => name = value,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Волокон:'),
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
                        const Text('Сторона:'),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: side,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Слева')),
                            DropdownMenuItem(value: 1, child: Text('Справа')),
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
                        const Text('Маркировка:'),
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
                  child: const Text('Отмена'),
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
                      'name': name.isEmpty ? 'Кабель' : name,
                      'fibers': fibersNumber,
                      'side': side,
                      'color_scheme': scheme,
                      'fiber_comments': List<String>.filled(fibersNumber, ''),
                    });
                    applyProjectSelection(cables.last, _activeProject);
                    muff['cables'] = cables;
                    _touchMuff(muff);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    await _recordTaskAddition(
                      kind: 'Добавлен кабель в муфту',
                      summary: [
                        '${muff['name'] ?? 'Муфта'}',
                        '${cables.last['name'] ?? 'Кабель'}',
                        'волокон: ${cables.last['fibers'] ?? fibersNumber}',
                        'сторона: ${((cables.last['side'] as int?) ?? side) == 0 ? 'слева' : 'справа'}',
                        if ((cables.last['color_scheme'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          'маркировка: ${cables.last['color_scheme']}',
                      ].join(' • '),
                      targetRecordId: muff['id'] as int?,
                    );
                    setState(() {});
                    navigator.pop();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
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
          title: const Text('Редактировать имя кабеля'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
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
              child: const Text('Сохранить'),
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
              Text('Кабель: ${cable['name']} | Волокно ${fiberIndex + 1}'),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(labelText: 'Комментарий'),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена'),
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
                    label: const Text('Сохранить'),
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
      _showSnack('Нужно минимум две точки подключения');
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
              title: const Text('Добавить соединение'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('От:'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _endpointKey(endpoint1),
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
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Куда:'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _endpointKey(endpoint2),
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
                  child: const Text('Отмена'),
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
                  label: const Text('Добавить'),
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
      _showSnack('Нельзя соединить точку саму с собой');
      return false;
    }

    if ((endpoint1['type'] == 'cable') &&
        (endpoint2['type'] == 'cable') &&
        endpoint1['cableId'] == endpoint2['cableId']) {
      _showSnack('Нельзя соединять волокна одного кабеля');
      return false;
    }

    final connections = _normalizedConnections(muff);
    if (_isEndpointBusy(connections, endpoint1) ||
        _isEndpointBusy(connections, endpoint2)) {
      _showSnack('Точка подключения уже занята');
      return false;
    }

    if (_connectionExists(connections, endpoint1, endpoint2)) {
      _showSnack('Такое соединение уже есть');
      return false;
    }

    connections.add({
      'endpoint1': Map<String, dynamic>.from(endpoint1),
      'endpoint2': Map<String, dynamic>.from(endpoint2),
    });
    applyProjectSelection(connections.last, _activeProject);
    muff['connections'] = connections;
    _touchMuff(muff);
    await _persist();
    if (mounted) {
      await _recordTaskAddition(
        kind: 'Добавлено соединение в муфту',
        summary: [
          muff['name']?.toString() ?? 'Муфта',
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
              title: const Text('Добавить делитель'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Название делителя',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => name = value.trim(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: ratio,
                      decoration: const InputDecoration(
                        labelText: 'Коэффициент деления',
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
                      value: side,
                      decoration: const InputDecoration(
                        labelText: 'Сторона',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Слева')),
                        DropdownMenuItem(value: 1, child: Text('Справа')),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          side = value ?? 0;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: orientation,
                      decoration: const InputDecoration(
                        labelText: 'Расположение выходных портов',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'vertical',
                          child: Text('Вертикально'),
                        ),
                        DropdownMenuItem(
                          value: 'horizontal',
                          child: Text('Горизонтально'),
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
                  child: const Text('Отмена'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final splitters = List<Map<String, dynamic>>.from(
                      muff['splitters'] ?? const [],
                    );
                    splitters.add({
                      'id': DateTime.now().microsecondsSinceEpoch,
                      'name': name.isEmpty ? 'Делитель 1:$ratio' : name,
                      'ratio': ratio,
                      'side': side,
                      'orientation': orientation,
                    });
                    applyProjectSelection(splitters.last, _activeProject);
                    muff['splitters'] = splitters;
                    _touchMuff(muff);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
                    await _recordTaskAddition(
                      kind: 'Добавлен делитель в муфту',
                      summary: [
                        '${muff['name'] ?? 'Муфта'}',
                        '${splitters.last['name'] ?? 'Делитель'}',
                        '1:${splitters.last['ratio'] ?? ratio}',
                        'сторона: ${((splitters.last['side'] as int?) ?? side) == 0 ? 'слева' : 'справа'}',
                        'ориентация: ${((splitters.last['orientation'] ?? orientation) == 'vertical') ? 'вертикально' : 'горизонтально'}',
                      ].join(' • '),
                      targetRecordId: muff['id'] as int?,
                    );
                    setState(() {});
                    navigator.pop();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
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
              title: const Text('Редактировать делитель'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Название делителя',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => name = value.trim(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: ratio,
                      decoration: const InputDecoration(
                        labelText: 'Коэффициент деления',
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
                      value: side,
                      decoration: const InputDecoration(
                        labelText: 'Сторона',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Слева')),
                        DropdownMenuItem(value: 1, child: Text('Справа')),
                      ],
                      onChanged: (value) {
                        setStateDialog(() {
                          side = value ?? 0;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: orientation,
                      decoration: const InputDecoration(
                        labelText: 'Расположение выходных портов',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'vertical',
                          child: Text('Вертикально'),
                        ),
                        DropdownMenuItem(
                          value: 'horizontal',
                          child: Text('Горизонтально'),
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
                  child: const Text('Отмена'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    splitter['name'] = nameController.text.trim().isEmpty
                        ? 'Делитель 1:$ratio'
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
                  label: const Text('Сохранить'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Блокнот муфт'),
        actions: [
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
            onPressed: _syncing ? null : _syncAll,
            icon: Icon(
              Icons.cloud_upload_outlined,
              color: _hasDirtyRecords ? Colors.redAccent : Colors.greenAccent,
            ),
            tooltip: 'Синхронизировать',
          ),
          PopupMenuButton<String>(
            tooltip: 'Фильтр по району',
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
                child: const Text('Все районы'),
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
            onPressed: () {
              setState(() {
                _mapView = !_mapView;
              });
            },
            icon: Icon(_mapView ? Icons.list : Icons.map),
            tooltip: _mapView ? 'Список' : 'Карта',
          ),
          IconButton(
            onPressed: _syncing ? null : _loadFromStorage,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
          IconButton(
            onPressed: () => _showMuffEditor(),
            icon: const Icon(Icons.add),
            tooltip: 'Новая муфта',
          ),
        ],
      ),
      body: LayoutBuilder(
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
                muff['name'] ?? 'Без названия',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_isPonBox(muff)) ...[
                const SizedBox(height: 6),
                _ponBadge(context),
              ],
              const SizedBox(height: 6),
              if (((muff['district'] as String?)?.trim() ?? '').isNotEmpty)
                Text('Район: ${muff['district']}'),
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
                    child: const Text('Закрыть'),
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
                    child: const Text('Открыть'),
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
          'Муфт пока нет. Добавьте первую запись.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    if (visibleMuffs.isEmpty) {
      return Center(
        child: Text(
          'В выбранном районе муфт пока нет.',
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
            title: Text(muff['name'] ?? 'Без названия'),
            subtitle: Text(
              [
                if (_isPonBox(muff)) 'Тип: PON бокс',
                if (projectNameOf(muff) != null)
                  'Задача: ${projectNameOf(muff)}',
                if (((muff['district'] as String?)?.trim() ?? '').isNotEmpty)
                  'Район: ${muff['district']}',
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
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                PopupMenuItem(value: 'geo', child: Text('Геопозиция')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
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
          'Выберите муфту слева',
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
                label: const Text('К списку'),
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
                            muff['name'] ?? 'Без названия',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Геопозиция',
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
                      Text('Район: ${muff['district']}'),
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
                              label: const Text('Изменить'),
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
                  'Кабели',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addCable,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить кабель'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                const Text(
                  'Делители',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addSplitter,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить делитель'),
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
                  'Соединения',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addConnection,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
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
                    label: const Text('Очистить все'),
                  ),
              ],
            ),
          ),
          if (connections.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Соединений пока нет'),
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
          side == 0 ? 'Слева' : 'Справа',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (cables.isEmpty && splitters.isEmpty) const Text('Нет элементов'),
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
                            cable['name'] ?? 'Кабель',
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
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Переименовать'),
                            ),
                            PopupMenuItem(
                              value: 'swap',
                              child: Text('Перенести на другую сторону'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Удалить'),
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
                            children: [
                              fiberWidget,
                            ],
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
    final orientation =
        (splitter['orientation'] as String?) == 'horizontal'
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
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: outputs,
          )
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
                        splitter['name'] ?? 'Делитель',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      //const SizedBox(height: 2),
                      //Text('PON 1:$ratio • ${orientation == 'vertical' ? 'вертикально' : 'горизонтально'}', style: Theme.of(context).textTheme.bodySmall,),
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
            'Кабель: ${cable['name']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (commentItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Комментарии по волокнам:'),
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
      child: const Text(
        'PON бокс',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
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
