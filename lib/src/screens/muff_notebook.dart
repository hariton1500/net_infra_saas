import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/map_tile_providers.dart';
import 'muff_location_picker.dart';

class MuffNotebookPage extends StatefulWidget {
  const MuffNotebookPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<MuffNotebookPage> createState() => _MuffNotebookPageState();
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
  bool _mapView = false;
  Timer? _syncTimer;

  final MapController _mapController = MapController();
  double _mapZoom = 14;

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
    if (filter == null || filter.isEmpty) {
      return _muffs.where((m) => m['deleted'] != true).toList();
    }

    return _muffs
        .where((m) => m['deleted'] != true)
        .where((m) => ((m['district'] as String?)?.trim() ?? '') == filter)
        .toList();
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

  bool get _hasDirtyRecords => _muffs.any(
    (record) => record['deleted'] != true && record['dirty'] == true,
  );

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_syncAll());
    });
  }

  Future<void> _loadFromStorage() async {
    final selectedMuffId = _selectedMuff?['id'] as int?;
    final selectedCableId = _selectedCableId;

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
                      payload['deleted'] = false;
                      payload['dirty'] = true;
                      _muffs.add(payload);
                    } else {
                      payload['id'] = muff['id'];
                      payload['created_by'] = muff['created_by'];
                      payload['cables'] =
                          muff['cables'] ?? <Map<String, dynamic>>[];
                      payload['connections'] =
                          muff['connections'] ?? <Map<String, dynamic>>[];
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
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MuffLocationPickerPage(
          initial: lat != null && lng != null ? LatLng(lat, lng) : null,
        ),
      ),
    );

    if (result != null) {
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
                      'spliters': List<int>.filled(fibersNumber, 0),
                    });
                    muff['cables'] = cables;
                    _touchMuff(muff);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
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

    final connections = List<Map<String, dynamic>>.from(
      muff['connections'] ?? [],
    );
    connections.removeWhere(
      (c) => c['cable1'] == cableId || c['cable2'] == cableId,
    );
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
    final spliters = List<int>.from(cable['spliters'] ?? []);
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
                  Text('Кабель: ${cable['name']} | Волокно ${fiberIndex + 1}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    decoration: const InputDecoration(labelText: 'Комментарий'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Сплиттер:'),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: spliter,
                        items: [0, 2, 4, 8, 16, 32]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value == 0 ? 'Нет' : '$value'),
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
                        child: const Text('Отмена'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          comments[fiberIndex] = commentController.text.trim();
                          spliters[fiberIndex] = spliter;
                          cable['fiber_comments'] = comments;
                          cable['spliters'] = spliters;
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
      },
    );
  }

  Future<void> _addConnection() async {
    final muff = _selectedMuff;
    if (muff == null) {
      return;
    }

    final cables = List<Map<String, dynamic>>.from(muff['cables'] ?? []);
    if (cables.length < 2) {
      _showSnack('Нужно минимум два кабеля');
      return;
    }

    int cable1 = cables.first['id'] as int;
    int cable2 = cables.last['id'] as int;
    int fiber1 = 0;
    int fiber2 = 0;

    List<DropdownMenuItem<int>> cableItems() => cables
        .map(
          (c) => DropdownMenuItem<int>(
            value: c['id'] as int,
            child: Text(c['name'] ?? 'Кабель'),
          ),
        )
        .toList();

    List<DropdownMenuItem<int>> fiberItems(int cableId) {
      final cable = cables.firstWhere((c) => c['id'] == cableId);
      final count = (cable['fibers'] as int?) ?? 1;
      return List.generate(
        count,
        (index) => DropdownMenuItem(value: index, child: Text('${index + 1}')),
      );
    }

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
                  const Text('От:'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      DropdownButton<int>(
                        value: cable1,
                        items: cableItems(),
                        onChanged: (value) {
                          setStateDialog(() {
                            cable1 = value ?? cable1;
                            fiber1 = 0;
                          });
                        },
                      ),
                      DropdownButton<int>(
                        value: fiber1,
                        items: fiberItems(cable1),
                        onChanged: (value) {
                          setStateDialog(() {
                            fiber1 = value ?? 0;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Куда:'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      DropdownButton<int>(
                        value: cable2,
                        items: cableItems(),
                        onChanged: (value) {
                          setStateDialog(() {
                            cable2 = value ?? cable2;
                            fiber2 = 0;
                          });
                        },
                      ),
                      DropdownButton<int>(
                        value: fiber2,
                        items: fiberItems(cable2),
                        onChanged: (value) {
                          setStateDialog(() {
                            fiber2 = value ?? 0;
                          });
                        },
                      ),
                    ],
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
                    final connections = List<Map<String, dynamic>>.from(
                      muff['connections'] ?? [],
                    );

                    if (_isFiberBusy(connections, cable1, fiber1) ||
                        _isFiberBusy(connections, cable2, fiber2)) {
                      _showSnack('Волокно уже используется (без сплиттера)');
                      return;
                    }

                    final exists = connections.any((c) {
                      final c1 = c['cable1'];
                      final f1 = c['fiber1'];
                      final c2 = c['cable2'];
                      final f2 = c['fiber2'];
                      final same =
                          c1 == cable1 &&
                          f1 == fiber1 &&
                          c2 == cable2 &&
                          f2 == fiber2;
                      final reverse =
                          c1 == cable2 &&
                          f1 == fiber2 &&
                          c2 == cable1 &&
                          f2 == fiber1;
                      return same || reverse;
                    });

                    if (exists) {
                      _showSnack('Такое соединение уже есть');
                      return;
                    }

                    connections.add({
                      'cable1': cable1,
                      'fiber1': fiber1,
                      'cable2': cable2,
                      'fiber2': fiber2,
                    });
                    muff['connections'] = connections;
                    _touchMuff(muff);
                    await _persist();
                    if (!mounted) {
                      return;
                    }
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

  Future<void> _addConnectionDirect({
    required int cable1,
    required int fiber1,
    required int cable2,
    required int fiber2,
  }) async {
    final muff = _selectedMuff;
    if (muff == null) {
      return;
    }

    if (cable1 == cable2) {
      _showSnack('Нельзя соединять волокна одного кабеля');
      return;
    }

    final connections = List<Map<String, dynamic>>.from(
      muff['connections'] ?? [],
    );
    if (_isFiberBusy(connections, cable1, fiber1) ||
        _isFiberBusy(connections, cable2, fiber2)) {
      _showSnack('Волокно уже используется (без сплиттера)');
      return;
    }

    final exists = connections.any((c) {
      final c1 = c['cable1'];
      final f1 = c['fiber1'];
      final c2 = c['cable2'];
      final f2 = c['fiber2'];
      final same = c1 == cable1 && f1 == fiber1 && c2 == cable2 && f2 == fiber2;
      final reverse =
          c1 == cable2 && f1 == fiber2 && c2 == cable1 && f2 == fiber1;
      return same || reverse;
    });

    if (exists) {
      _showSnack('Такое соединение уже есть');
      return;
    }

    connections.add({
      'cable1': cable1,
      'fiber1': fiber1,
      'cable2': cable2,
      'fiber2': fiber2,
    });
    muff['connections'] = connections;
    _touchMuff(muff);
    await _persist();
    if (mounted) {
      setState(() {});
    }
  }

  bool _isFiberBusy(
    List<Map<String, dynamic>> connections,
    int cableId,
    int fiberIndex,
  ) {
    if (_fiberHasSpliter(cableId, fiberIndex)) {
      return false;
    }

    return connections.any((c) {
      final c1 = c['cable1'];
      final f1 = c['fiber1'];
      final c2 = c['cable2'];
      final f2 = c['fiber2'];
      return (c1 == cableId && f1 == fiberIndex) ||
          (c2 == cableId && f2 == fiberIndex);
    });
  }

  bool _fiberHasSpliter(int cableId, int fiberIndex) {
    final cable = _getCableById(cableId);
    if (cable == null || cable.isEmpty) {
      return false;
    }

    final spliters = List<int>.from(cable['spliters'] ?? []);
    if (fiberIndex < 0 || fiberIndex >= spliters.length) {
      return false;
    }

    return spliters[fiberIndex] > 0;
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
        initialCenter: center,
        initialZoom: _mapZoom,
        maxZoom: 19,
        onPositionChanged: (position, _) {
          _mapZoom = position.zoom;
        },
      ),
      children: [
        openStreetMapTileLayer,
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
    final connections = List<Map<String, dynamic>>.from(
      muff['connections'] ?? [],
    );
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
                final cable1 = _getCableById(connection['cable1']);
                final cable2 = _getCableById(connection['cable2']);
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
                    '${cable1?['name'] ?? 'Кабель'}[${(connection['fiber1'] as int) + 1}] '
                    '<--> ${cable2?['name'] ?? 'Кабель'}[${(connection['fiber2'] as int) + 1}]',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          side == 0 ? 'Слева' : 'Справа',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (cables.isEmpty) const Text('Нет кабелей'),
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
                        final spliters = List<int>.from(
                          cable['spliters'] ?? [],
                        );
                        final spliter = index < spliters.length
                            ? spliters[index]
                            : 0;
                        final keyId = _fiberKey(cable['id'] as int, index);
                        _currentFiberKeys.add(keyId);
                        _fiberColorByKey[keyId] = color;
                        _fiberSideByKey[keyId] = side;
                        final anchorKey = _fiberKeys.putIfAbsent(
                          keyId,
                          () => GlobalKey(),
                        );

                        final fiberWidget = DragTarget<Map<String, int>>(
                          onWillAcceptWithDetails: (_) => true,
                          onAcceptWithDetails: (details) {
                            final data = details.data;
                            _addConnectionDirect(
                              cable1: data['cableId']!,
                              fiber1: data['fiberIndex']!,
                              cable2: cable['id'] as int,
                              fiber2: index,
                            );
                          },
                          builder: (context, candidateData, rejectedData) {
                            final isHover = candidateData.isNotEmpty;
                            return Draggable<Map<String, int>>(
                              data: {
                                'cableId': cable['id'] as int,
                                'fiberIndex': index,
                              },
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
                                  key: spliter > 0 ? null : anchorKey,
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
                              if (side == 1 && spliter > 0)
                                _spliterBadge(spliter, key: anchorKey),
                              if (side == 1 && spliter > 0)
                                const SizedBox(width: 6),
                              fiberWidget,
                              if (side == 0 && spliter > 0)
                                const SizedBox(width: 6),
                              if (side == 0 && spliter > 0)
                                _spliterBadge(spliter, key: anchorKey),
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
      ],
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
    final cable = _getCableById(_selectedCableId!);
    if (cable == null || cable.isEmpty) {
      return const SizedBox.shrink();
    }

    final comments = List<String>.from(cable['fiber_comments'] ?? []);
    final spliters = List<int>.from(cable['spliters'] ?? []);

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

    final spliterItems = spliters
        .asMap()
        .entries
        .where((entry) => entry.value != 0)
        .map(
          (entry) => Row(
            children: [
              Text('[${entry.key + 1}]: '),
              Text('Сплиттер ${entry.value}'),
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
          if (spliterItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Сплиттеры:'),
            ...spliterItems,
          ],
        ],
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

  String _key(int cableId, int fiberIndex) => '$cableId:$fiberIndex';

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final connection in connections) {
      final c1 = connection['cable1'] as int?;
      final f1 = connection['fiber1'] as int?;
      final c2 = connection['cable2'] as int?;
      final f2 = connection['fiber2'] as int?;
      if (c1 == null || f1 == null || c2 == null || f2 == null) {
        continue;
      }

      final p1 = positions[_key(c1, f1)];
      final p2 = positions[_key(c2, f2)];
      if (p1 == null || p2 == null) {
        continue;
      }

      paint.color = (colors[_key(c1, f1)] ?? Colors.deepOrange).withValues(
        alpha: 0.75,
      );

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
