import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/employee_positions.dart';
import '../core/project_scope.dart';
import 'infrastructure_map_page.dart';
import 'muff_notebook.dart';
import 'network_cabinet.dart';
import 'profile_page.dart';

class StartPage extends StatefulWidget {
  const StartPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  static const String _legacyWorkOrdersCacheKey = 'work_orders.records.v1';

  late final CompanyModuleSyncRepository _syncRepository;
  final _inviteFormKey = GlobalKey<FormState>();
  final _inviteEmailController = TextEditingController();
  String _selectedRole = 'member';
  String _selectedPosition = employeePositionEngineer;
  bool _loadingProjects = true;
  bool _syncingProjects = false;
  List<Map<String, dynamic>> _projectRecords = const [];
  ProjectSelection? _activeProject;

  @override
  void initState() {
    super.initState();
    _syncRepository = CompanyModuleSyncRepository(
      client: widget.controller.client,
    );
    _cleanupLegacyCaches();
    _loadProjects();
  }

  @override
  void dispose() {
    _inviteEmailController.dispose();
    super.dispose();
  }

  Future<void> _cleanupLegacyCaches() async {
    try {
      await _syncRepository.removeCache(_legacyWorkOrdersCacheKey);
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось очистить устаревший локальный кэш нарядов.',
        source: 'start.cleanup_legacy_work_orders_cache',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String get _userPosition => widget.controller.profile?.position ?? '';

  String get _currentUserId => widget.controller.currentUser?.id ?? '';

  String get _currentUserEmail =>
      widget.controller.currentUser?.email?.trim().toLowerCase() ?? '';

  bool get _canManageProjects => canCreateProjectsForPosition(_userPosition);

  List<Map<String, dynamic>> get _projects =>
      _normalizeProjectRecords(_projectRecords);

  List<Map<String, dynamic>> _normalizeProjectRecords(
    List<Map<String, dynamic>> source,
  ) {
    final uniqueById = <int, Map<String, dynamic>>{};

    for (final record in source) {
      if (record['deleted'] == true || record['archived'] == true) {
        continue;
      }
      final id = projectIdOf(record);
      if (id == null) {
        continue;
      }
      uniqueById[id] = _syncRepository.clone(record);
    }

    final records = uniqueById.values.toList(growable: false);
    records.sort((a, b) {
      final aName = (a['name'] as String?)?.trim().toLowerCase() ?? '';
      final bName = (b['name'] as String?)?.trim().toLowerCase() ?? '';
      return aName.compareTo(bName);
    });
    return records;
  }

  ({List<Map<String, dynamic>> records, bool didChange})
  _migrateLegacyTaskAuthors(List<Map<String, dynamic>> source) {
    final currentProfile = widget.controller.profile;
    final membersByEmail = <String, TeamMemberData>{
      for (final member in widget.controller.teamMembers)
        member.email.trim().toLowerCase(): member,
    };

    var didChange = false;
    final records = source
        .map((record) {
          final cloned = _syncRepository.clone(record);
          if (_hasTaskAuthorMetadata(cloned) || cloned['deleted'] == true) {
            return cloned;
          }

          final updatedBy = cloned['updated_by']?.toString().trim() ?? '';
          final normalizedUpdatedBy = updatedBy.toLowerCase();
          if (normalizedUpdatedBy.isEmpty) {
            return cloned;
          }

          final inferredMember = membersByEmail[normalizedUpdatedBy];
          final inferredUserId = inferredMember?.userId ??
              (normalizedUpdatedBy == _currentUserEmail ? _currentUserId : '');
          final inferredName = inferredMember?.fullName ??
              (normalizedUpdatedBy == _currentUserEmail
                  ? (currentProfile?.fullName ?? '')
                  : '');
          final inferredEmail = inferredMember?.email.isNotEmpty == true
              ? inferredMember!.email
              : updatedBy;

          cloned['created_by_user_id'] = inferredUserId;
          cloned['created_by_email'] = inferredEmail;
          cloned['created_by_name'] = inferredName;
          cloned['updated_at'] = DateTime.now();
          cloned['dirty'] = true;
          didChange = true;
          return cloned;
        })
        .toList(growable: false);

    return (records: records, didChange: didChange);
  }

  Future<void> _loadProjects() async {
    final companyId = widget.controller.membership?.companyId;
    final activeProject = await _syncRepository.readActiveProject();
    if (companyId == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _activeProject = activeProject;
        _loadingProjects = false;
      });
      return;
    }

    setState(() {
      _loadingProjects = true;
    });

    try {
      var records = await _syncRepository.readCache(projectsCacheKey);
      records = await _syncRepository.pullMerge(
        companyId: companyId,
        moduleKey: projectsModuleKey,
        localRecords: records,
      );
      final migrated = _migrateLegacyTaskAuthors(records);
      records = migrated.records;
      if (migrated.didChange) {
        records = await _syncRepository.syncAll(
          companyId: companyId,
          moduleKey: projectsModuleKey,
          cacheKey: projectsCacheKey,
          localRecords: records,
        );
      }
      records = _normalizeProjectRecords(records);
      await _syncRepository.writeCache(projectsCacheKey, records);

      var nextActiveProject = activeProject;
      if (nextActiveProject != null &&
          !records.any(
            (record) =>
                record['deleted'] != true &&
                projectIdOf(record) == nextActiveProject!.id,
          )) {
        await _syncRepository.clearActiveProject();
        nextActiveProject = null;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _projectRecords = records
            .map((record) => _syncRepository.clone(record))
            .toList(growable: false);
        _activeProject = nextActiveProject;
        _loadingProjects = false;
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось загрузить задачи.',
        source: 'start.projects_load',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeProject = activeProject;
        _loadingProjects = false;
      });
    }
  }

  int _nextProjectId() {
    var maxId = 0;
    for (final record in _projectRecords) {
      final id = projectIdOf(record) ?? 0;
      if (id > maxId) {
        maxId = id;
      }
    }
    return maxId + 1;
  }

  bool _isTaskAssignee(Map<String, dynamic> record) {
    return _assignedEmployeesOf(record).any((employee) {
      final userId = employee['user_id']?.trim() ?? '';
      if (userId.isNotEmpty && userId == _currentUserId) {
        return true;
      }
      final email = employee['email']?.trim().toLowerCase() ?? '';
      return email.isNotEmpty && email == _currentUserEmail;
    });
  }

  bool _isTaskCompleted(Map<String, dynamic> record) =>
      record['completed'] == true;

  bool _isTaskVerified(Map<String, dynamic> record) =>
      record['verified'] == true;

  bool _isTaskArchived(Map<String, dynamic> record) =>
      record['archived'] == true;

  bool _hasTaskAuthorMetadata(Map<String, dynamic> record) {
    final authorId = record['created_by_user_id']?.toString().trim() ?? '';
    final authorEmail =
        record['created_by_email']?.toString().trim().toLowerCase() ?? '';
    return authorId.isNotEmpty || authorEmail.isNotEmpty;
  }

  String? _taskCompletedBy(Map<String, dynamic> record) {
    final value = record['completed_by_name']?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    final email = record['completed_by_email']?.toString().trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return null;
  }

  String? _taskVerifiedBy(Map<String, dynamic> record) {
    final value = record['verified_by_name']?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    final email = record['verified_by_email']?.toString().trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return null;
  }

  List<Map<String, dynamic>> _taskWorkLogOf(Map<String, dynamic> record) {
    final raw = record['work_log'];
    if (raw is! List) {
      return const [];
    }

    final entries = raw
        .whereType<Map>()
        .map(
          (entry) => <String, dynamic>{
            'at': _syncRepository.parseTime(entry['at']),
            'kind': entry['kind']?.toString() ?? '',
            'summary': entry['summary']?.toString() ?? '',
          },
        )
        .toList(growable: false);
    entries.sort(
      (a, b) => _syncRepository
          .parseTime(b['at'])
          .compareTo(_syncRepository.parseTime(a['at'])),
    );
    return entries;
  }

  Future<void> _updateTaskRecord(
    Map<String, dynamic> task,
    void Function(Map<String, dynamic> updatedTask) mutate,
  ) async {
    final updatedTask = _syncRepository.clone(task);
    mutate(updatedTask);
    updatedTask['updated_at'] = DateTime.now();
    updatedTask['updated_by'] = widget.controller.currentUser?.email ?? '';
    updatedTask['dirty'] = true;

    final nextRecords = _projectRecords
        .map((record) {
          if (projectIdOf(record) != projectIdOf(task)) {
            return _syncRepository.clone(record);
          }
          return updatedTask;
        })
        .toList(growable: false);

    await _persistProjects(nextRecords);
  }

  Future<void> _markTaskCompleted(Map<String, dynamic> task) async {
    await _updateTaskRecord(task, (updatedTask) {
      updatedTask['completed'] = true;
      updatedTask['completed_at'] = DateTime.now();
      updatedTask['completed_by_user_id'] = _currentUserId;
      updatedTask['completed_by_email'] =
          widget.controller.currentUser?.email ?? '';
      updatedTask['completed_by_name'] =
          widget.controller.profile?.fullName ?? '';
    });
  }

  Future<void> _markTaskVerified(Map<String, dynamic> task) async {
    await _updateTaskRecord(task, (updatedTask) {
      updatedTask['verified'] = true;
      updatedTask['verified_at'] = DateTime.now();
      updatedTask['verified_by_user_id'] = _currentUserId;
      updatedTask['verified_by_email'] =
          widget.controller.currentUser?.email ?? '';
      updatedTask['verified_by_name'] =
          widget.controller.profile?.fullName ?? '';
    });
  }

  Future<void> _markTaskArchived(Map<String, dynamic> task) async {
    await _updateTaskRecord(task, (updatedTask) {
      updatedTask['archived'] = true;
      updatedTask['archived_at'] = DateTime.now();
      updatedTask['archived_by_user_id'] = _currentUserId;
      updatedTask['archived_by_email'] =
          widget.controller.currentUser?.email ?? '';
      updatedTask['archived_by_name'] =
          widget.controller.profile?.fullName ?? '';
    });

    if (_activeProject?.id == projectIdOf(task)) {
      await _syncRepository.clearActiveProject();
      if (!mounted) {
        return;
      }
      setState(() {
        _activeProject = null;
      });
    }
  }

  bool _isTaskAuthor(Map<String, dynamic> record) {
    final authorId = record['created_by_user_id']?.toString().trim() ?? '';
    if (authorId.isNotEmpty && authorId == _currentUserId) {
      return true;
    }

    final authorEmail =
        record['created_by_email']?.toString().trim().toLowerCase() ?? '';
    return authorEmail.isNotEmpty && authorEmail == _currentUserEmail;
  }

  bool _canAdministrateTask(Map<String, dynamic> record) => _isTaskAuthor(record);

  List<Map<String, String>> _assignedEmployeesOf(Map<String, dynamic> record) {
    final raw = record['assignees'];
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map>()
        .map(
          (entry) => <String, String>{
            'user_id': entry['user_id']?.toString() ?? '',
            'full_name': entry['full_name']?.toString() ?? '',
            'email': entry['email']?.toString() ?? '',
            'position': entry['position']?.toString() ?? '',
          },
        )
        .where((entry) => entry['user_id']!.trim().isNotEmpty)
        .toList(growable: false);
  }

  String _employeeDisplayName({
    required String fullName,
    required String email,
  }) {
    final normalizedName = fullName.trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }
    final normalizedEmail = email.trim();
    if (normalizedEmail.isNotEmpty) {
      return normalizedEmail;
    }
    return 'Сотрудник';
  }

  Future<void> _showTaskAssigneesEditor(Map<String, dynamic> task) async {
    final team = widget.controller.teamMembers;
    if (team.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('В компании пока нет сотрудников.')),
        );
      return;
    }

    final selectedIds = _assignedEmployeesOf(task)
        .map((employee) => employee['user_id'] ?? '')
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                'Сотрудники задачи "${projectNameOf(task) ?? 'Без названия'}"',
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final member in team)
                        CheckboxListTile(
                          value: selectedIds.contains(member.userId),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _employeeDisplayName(
                              fullName: member.fullName,
                              email: member.email,
                            ),
                          ),
                          subtitle: Text(
                            _memberSubtitle(
                              email: member.email,
                              position: member.position,
                            ),
                          ),
                          onChanged: (value) {
                            setModalState(() {
                              if (value == true) {
                                selectedIds.add(member.userId);
                              } else {
                                selectedIds.remove(member.userId);
                              }
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
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final selectedEmployees = team
                        .where((member) => selectedIds.contains(member.userId))
                        .map(
                          (member) => <String, dynamic>{
                            'user_id': member.userId,
                            'full_name': member.fullName,
                            'email': member.email,
                            'position': member.position,
                          },
                        )
                        .toList(growable: false);

                    await _updateTaskRecord(task, (updatedTask) {
                      updatedTask['assignees'] = selectedEmployees;
                    });
                    if (!mounted) {
                      return;
                    }
                    navigator.pop();
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showTaskDetailsDialog(Map<String, dynamic> task) async {
    final assignees = _assignedEmployeesOf(task)
        .map(
          (employee) => _employeeDisplayName(
            fullName: employee['full_name'] ?? '',
            email: employee['email'] ?? '',
          ),
        )
        .toList(growable: false);
    final workLog = _taskWorkLogOf(task);
    final isActive = _activeProject?.id == projectIdOf(task);
    final isCompleted = _isTaskCompleted(task);
    final isVerified = _isTaskVerified(task);
    final canManageAssignees = _canAdministrateTask(task);
    final canMarkCompleted =
        _isTaskAssignee(task) &&
        !isCompleted &&
        !_isTaskArchived(task);
    final canMarkVerified =
        _canAdministrateTask(task) && isCompleted && !isVerified;
    final canMarkArchived =
        _canAdministrateTask(task) && isVerified && !_isTaskArchived(task);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(projectNameOf(task) ?? 'Задача'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((task['description'] as String?)?.trim().isNotEmpty == true)
                    Text((task['description'] as String).trim())
                  else
                    const Text('Описание не заполнено.'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isActive)
                        const _TagBadge(
                          label: 'Активная',
                          backgroundColor: Color(0xFF123524),
                          borderColor: Color(0xFF35C886),
                        ),
                      if (isCompleted)
                        const _TagBadge(
                          label: 'Выполнена',
                          backgroundColor: Color(0xFF3A2812),
                          borderColor: Color(0xFFE0A54A),
                        ),
                      if (isVerified)
                        const _TagBadge(
                          label: 'Проверена',
                          backgroundColor: Color(0xFF122E3A),
                          borderColor: Color(0xFF53B6D9),
                        ),
                    ],
                  ),
                  if (_taskCompletedBy(task) != null) ...[
                    const SizedBox(height: 12),
                    Text('Выполнил: ${_taskCompletedBy(task)}'),
                  ],
                  if (_taskVerifiedBy(task) != null) ...[
                    const SizedBox(height: 6),
                    Text('Проверил: ${_taskVerifiedBy(task)}'),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    assignees.isEmpty
                        ? 'Исполнители не закреплены'
                        : 'Закреплённые сотрудники',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (assignees.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final assignee in assignees)
                          _TagBadge(
                            label: assignee,
                            backgroundColor: const Color(0xFF143456),
                            borderColor: const Color(0xFF2A648E),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'История работ',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (workLog.isEmpty)
                    const Text('Пока нет зафиксированных добавлений.')
                  else
                    Column(
                      children: [
                        for (final entry in workLog)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C1D33),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF1E466A)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatDate(
                                    _syncRepository.parseTime(entry['at']),
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry['kind']?.toString() ?? '',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if ((entry['summary']?.toString().trim() ?? '')
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(entry['summary'].toString().trim()),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Действия',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!isActive)
                        TextButton(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await _activateProject(task);
                            if (!mounted) {
                              return;
                            }
                            navigator.pop();
                          },
                          child: const Text('Активировать'),
                        ),
                      if (canManageAssignees)
                        TextButton(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            navigator.pop();
                            await _showTaskAssigneesEditor(task);
                          },
                          child: const Text('Исполнители'),
                        ),
                      if (canMarkCompleted)
                        FilledButton.tonal(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await _markTaskCompleted(task);
                            if (!mounted) {
                              return;
                            }
                            navigator.pop();
                          },
                          child: const Text('Выполнена'),
                        ),
                      if (canMarkVerified)
                        FilledButton.tonal(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await _markTaskVerified(task);
                            if (!mounted) {
                              return;
                            }
                            navigator.pop();
                          },
                          child: const Text('Проверена'),
                        ),
                      if (canMarkArchived)
                        FilledButton.tonal(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await _markTaskArchived(task);
                            if (!mounted) {
                              return;
                            }
                            navigator.pop();
                          },
                          child: const Text('В архив'),
                        ),
                      if (isActive &&
                          !canManageAssignees &&
                          !canMarkCompleted &&
                          !canMarkVerified &&
                          !canMarkArchived)
                        const Text('Для этой задачи сейчас нет доступных действий.'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _persistProjects(List<Map<String, dynamic>> records) async {
    final companyId = widget.controller.membership?.companyId;
    if (companyId == null) {
      return;
    }

    setState(() {
      _syncingProjects = true;
    });

    try {
      final merged = await _syncRepository.syncAll(
        companyId: companyId,
        moduleKey: projectsModuleKey,
        cacheKey: projectsCacheKey,
        localRecords: records,
      );
      final normalized = _normalizeProjectRecords(merged);
      await _syncRepository.writeCache(projectsCacheKey, normalized);
      if (!mounted) {
        return;
      }
      setState(() {
        _projectRecords = normalized
            .map((record) => _syncRepository.clone(record))
            .toList(growable: false);
        _syncingProjects = false;
      });
    } catch (error, stackTrace) {
      logUserFacingError(
        'Не удалось сохранить задачи.',
        source: 'start.projects_persist',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _syncingProjects = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить задачи.')),
        );
    }
  }

  Future<void> _showProjectEditor() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Новая задача'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Краткое название'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Описание'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                final name = titleController.text.trim();
                if (name.isEmpty) {
                  return;
                }
                final navigator = Navigator.of(context);
                final record = <String, dynamic>{
                  'id': _nextProjectId(),
                  'name': name,
                  'description': descriptionController.text.trim(),
                  'created_by_user_id': _currentUserId,
                  'created_by_email': widget.controller.currentUser?.email ?? '',
                  'created_by_name': widget.controller.profile?.fullName ?? '',
                  'assignees': const <Map<String, dynamic>>[],
                  'work_log': const <Map<String, dynamic>>[],
                  'completed': false,
                  'verified': false,
                  'archived': false,
                  'updated_at': DateTime.now(),
                  'updated_by': widget.controller.currentUser?.email ?? '',
                  'dirty': true,
                  'deleted': false,
                };
                final nextRecords = [
                  ..._projectRecords.map((record) => _syncRepository.clone(record)),
                  record,
                ];
                await _persistProjects(nextRecords);
                if (!mounted) {
                  return;
                }
                navigator.pop();
              },
              child: const Text('Создать'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _activateProject(Map<String, dynamic> project) async {
    final id = projectIdOf(project);
    final name = projectNameOf(project);
    if (id == null || name == null) {
      return;
    }

    final authorUserId = project['created_by_user_id']?.toString().trim();
    final authorEmail =
        project['created_by_email']?.toString().trim().toLowerCase();
    final selection = ProjectSelection(
      id: id,
      name: name,
      authorUserId: authorUserId?.isEmpty == true ? null : authorUserId,
      authorEmail: authorEmail?.isEmpty == true ? null : authorEmail,
    );
    await _syncRepository.writeActiveProject(selection);
    if (!mounted) {
      return;
    }
    setState(() {
      _activeProject = selection;
    });
  }

  Future<void> _clearActiveProject() async {
    await _syncRepository.clearActiveProject();
    if (!mounted) {
      return;
    }
    setState(() {
      _activeProject = null;
    });
  }

  Widget _buildProjectsCard(BuildContext context) {
    final projects = _projects;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Задачи',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (_canManageProjects)
                  FilledButton.tonalIcon(
                    onPressed: _syncingProjects ? null : _showProjectEditor,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Создать'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _activeProject == null
                        ? 'Активная задача выключена.'
                        : 'Активная задача: ${_activeProject!.name}',
                  ),
                ),
                if (_activeProject != null)
                  TextButton(
                    onPressed: _clearActiveProject,
                    child: const Text('Выключить'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingProjects)
              const Center(child: CircularProgressIndicator())
            else if (projects.isEmpty)
              const Text('Задач пока нет.')
            else
              Column(
                children: [
                  for (final project in projects) ...[
                    _ProjectRow(
                      title: projectNameOf(project) ?? 'Без названия',
                      description:
                          (project['description'] as String?)?.trim() ?? '',
                      assignees: _assignedEmployeesOf(project)
                          .map(
                            (employee) => _employeeDisplayName(
                              fullName: employee['full_name'] ?? '',
                              email: employee['email'] ?? '',
                            ),
                          )
                          .toList(growable: false),
                      isActive: _activeProject?.id == projectIdOf(project),
                      isCompleted: _isTaskCompleted(project),
                      completedBy: _taskCompletedBy(project),
                      isVerified: _isTaskVerified(project),
                      verifiedBy: _taskVerifiedBy(project),
                      canManageAssignees: _canAdministrateTask(project),
                      canMarkCompleted:
                          _isTaskAssignee(project) &&
                          !_isTaskCompleted(project) &&
                          !_isTaskArchived(project),
                      canMarkVerified:
                          _canAdministrateTask(project) &&
                          _isTaskCompleted(project) &&
                          !_isTaskVerified(project),
                      canMarkArchived:
                          _canAdministrateTask(project) &&
                          _isTaskVerified(project) &&
                          !_isTaskArchived(project),
                      onOpenDetails: () => _showTaskDetailsDialog(project),
                      onActivate: () => _activateProject(project),
                      onManageAssignees: () => _showTaskAssigneesEditor(project),
                      onMarkCompleted: () => _markTaskCompleted(project),
                      onMarkVerified: () => _markTaskVerified(project),
                      onMarkArchived: () => _markTaskArchived(project),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final profile = controller.profile;
    final membership = controller.membership;
    final displayName = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : profile?.email ?? controller.currentUser?.email ?? 'Сотрудник';

    return Scaffold(
      appBar: AppBar(
        title: Text(membership?.companyName ?? 'Net Infra SaaS'),
        actions: [
          IconButton(
            tooltip: 'Профиль',
            onPressed: controller.isBusy
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            ProfilePage(controller: controller),
                      ),
                    );
                  },
            icon: const Icon(Icons.person_outline_rounded),
          ),
          IconButton(
            tooltip: 'Обновить данные',
            onPressed: controller.isBusy ? null : _refreshTeam,
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton(
            onPressed: controller.isBusy ? null : controller.signOut,
            child: const Text('Выйти'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071526), Color(0xFF0A1B31), Color(0xFF102744)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _HeroCard(
                    displayName: displayName,
                    position: profile?.position ?? '',
                    companyName: membership?.companyName ?? 'Компания',
                    role: membership?.role ?? 'member',
                    slug: membership?.slug ?? '-',
                    teamSize: controller.teamMembers.length,
                    inviteCount: controller.pendingInvites.length,
                  ),
                  const SizedBox(height: 20),
                  _buildProjectsCard(context),
                  const SizedBox(height: 20),
                  Text(
                    'Рабочие разделы',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 1100;
                      final cards = [
                        _ActionCard(
                          icon: Icons.map_outlined,
                          title: 'Карта инфраструктуры',
                          description:
                              'Быстрый переход к карте муфт, PON боксов, кабельных маршрутов и точек подключения.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => InfrastructureMapPage(
                                  controller: controller,
                                ),
                              ),
                            );
                          },
                        ),
                        _ActionCard(
                          icon: Icons.notes_rounded,
                          title: 'Блокнот муфт',
                          description:
                              'Оперативная работа с монтажными узлами, заметками и обслуживанием.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    MuffNotebookPage(controller: controller),
                              ),
                            );
                          },
                        ),
                        _ActionCard(
                          icon: Icons.timeline_rounded,
                          title: 'Кабельные линии',
                          description:
                              'Построение и редактирование кабельных маршрутов теперь выполняется прямо на карте инфраструктуры.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => InfrastructureMapPage(
                                  controller: controller,
                                ),
                              ),
                            );
                          },
                        ),
                        _ActionCard(
                          icon: Icons.dns_rounded,
                          title: 'Сетевые шкафы',
                          description:
                              'Просмотр шкафов, оборудования и состояния точек размещения.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    CabinetNotebookPage(controller: controller),
                              ),
                            );
                          },
                        ),
                      ];

                      if (compact) {
                        return Column(
                          children: [
                            for (final card in cards) ...[
                              card,
                              const SizedBox(height: 14),
                            ],
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < cards.length; i++) ...[
                            Expanded(child: cards[i]),
                            if (i != cards.length - 1)
                              const SizedBox(width: 14),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  if (controller.canManageTeam) ...[
                    Text(
                      'Команда компании',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 920;

                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildInviteCard(context),
                              const SizedBox(height: 20),
                              _buildPendingInvitesCard(context),
                              const SizedBox(height: 20),
                              _buildTeamCard(context),
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  _buildInviteCard(context),
                                  const SizedBox(height: 20),
                                  _buildPendingInvitesCard(context),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(child: _buildTeamCard(context)),
                          ],
                        );
                      },
                    ),
                  ] else ...[
                    _buildTeamCard(context),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInviteCard(BuildContext context) {
    final controller = widget.controller;
    final canAssignPosition = controller.canAssignEmployeePosition;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _inviteFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Пригласить сотрудника',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Приглашение создаётся по рабочему email. После регистрации с этим email сотрудник автоматически попадёт в компанию.',
              ),
              const SizedBox(height: 14),
              if (canAssignPosition)
                DropdownButtonFormField<String>(
                  initialValue: _selectedPosition,
                  items: employeePositions
                      .map(
                        (position) => DropdownMenuItem<String>(
                          value: position,
                          child: Text(position),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: controller.isBusy
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _selectedPosition = value;
                          });
                        },
                  decoration: const InputDecoration(labelText: 'Должность'),
                )
              else
                const Text(
                  'Должность назначает только владелец компании. Для сотрудников по умолчанию будет использована стандартная должность.',
                ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _inviteEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email сотрудника',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите email.';
                  }

                  if (!value.contains('@')) {
                    return 'Введите корректный email.';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(labelText: 'Роль в компании'),
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('member')),
                  DropdownMenuItem(value: 'admin', child: Text('admin')),
                ],
                onChanged: controller.isBusy
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _selectedRole = value;
                        });
                      },
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: controller.isBusy ? null : _submitInvite,
                child: controller.isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Создать приглашение'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingInvitesCard(BuildContext context) {
    final invites = widget.controller.pendingInvites;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ожидающие приглашения',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (invites.isEmpty)
              const Text('Нет активных приглашений.')
            else
              for (final invite in invites) ...[
                _InfoRow(
                  title: invite.email,
                  subtitle:
                      'Код: ${invite.token} • ${_formatDate(invite.createdAt)}',
                  role: invite.role,
                  position: invite.position,
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildTeamCard(BuildContext context) {
    final team = widget.controller.teamMembers;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Команда компании',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (team.isEmpty)
              const Text('Пока нет сотрудников.')
            else
              for (final member in team) ...[
                _InfoRow(
                  title: _memberTitle(member.fullName, member.email),
                  subtitle: _memberSubtitle(
                    email: member.email,
                    position: member.position,
                  ),
                  role: member.role,
                  position: member.position,
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _submitInvite() async {
    if (!_inviteFormKey.currentState!.validate()) {
      return;
    }

    try {
      final message = await widget.controller.inviteEmployee(
        email: _inviteEmailController.text,
        role: _selectedRole,
        position: _selectedPosition,
      );

      _inviteEmailController.clear();
      setState(() {
        _selectedPosition = employeePositionEngineer;
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      final message =
          widget.controller.errorMessage ?? 'Не удалось создать приглашение.';
      logUserFacingError(message, source: 'start.invite');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _refreshTeam() async {
    try {
      await widget.controller.refreshCompanyData();
      await _loadProjects();
    } catch (_) {
      if (!mounted) {
        return;
      }

      final message =
          widget.controller.errorMessage ?? 'Не удалось обновить данные.';
      logUserFacingError(message, source: 'start.refresh');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');

    return '$day.$month.${value.year} $hour:$minute';
  }

  String _memberTitle(String fullName, String email) {
    final normalizedName = fullName.trim();
    final normalizedEmail = email.trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }
    if (normalizedEmail.isNotEmpty) {
      return normalizedEmail;
    }
    return 'Сотрудник без имени';
  }

  String _memberSubtitle({required String email, required String position}) {
    final parts = <String>[
      if (email.trim().isNotEmpty) email.trim(),
      if (position.trim().isNotEmpty) position.trim(),
    ];
    if (parts.isEmpty) {
      return 'Профиль сотрудника';
    }
    return parts.join(' • ');
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.displayName,
    required this.position,
    required this.companyName,
    required this.role,
    required this.slug,
    required this.teamSize,
    required this.inviteCount,
  });

  final String displayName;
  final String position;
  final String companyName;
  final String role;
  final String slug;
  final int teamSize;
  final int inviteCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Wrap(
          spacing: 18,
          runSpacing: 18,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 540,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Рабочий экран сотрудника',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Пользователь: $displayName'),
                  const SizedBox(height: 6),
                  Text('Компания: $companyName'),
                  const SizedBox(height: 6),
                  Text('Роль: $role'),
                  if (position.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Должность: $position'),
                  ],
                  const SizedBox(height: 6),
                  Text('Slug: $slug'),
                ],
              ),
            ),
            _MetricBadge(label: 'Сотрудники', value: '$teamSize'),
            _MetricBadge(label: 'Инвайты', value: '$inviteCount'),
          ],
        ),
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1D33),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1E466A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1D33),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(description),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.title,
    required this.description,
    required this.assignees,
    required this.isActive,
    required this.isCompleted,
    required this.completedBy,
    required this.isVerified,
    required this.verifiedBy,
    required this.canManageAssignees,
    required this.canMarkCompleted,
    required this.canMarkVerified,
    required this.canMarkArchived,
    required this.onOpenDetails,
    required this.onActivate,
    required this.onManageAssignees,
    required this.onMarkCompleted,
    required this.onMarkVerified,
    required this.onMarkArchived,
  });

  final String title;
  final String description;
  final List<String> assignees;
  final bool isActive;
  final bool isCompleted;
  final String? completedBy;
  final bool isVerified;
  final String? verifiedBy;
  final bool canManageAssignees;
  final bool canMarkCompleted;
  final bool canMarkVerified;
  final bool canMarkArchived;
  final VoidCallback onOpenDetails;
  final VoidCallback onActivate;
  final VoidCallback onManageAssignees;
  final VoidCallback onMarkCompleted;
  final VoidCallback onMarkVerified;
  final VoidCallback onMarkArchived;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1D33),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E466A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (description.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(description),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onOpenDetails,
                      child: const Text('Открыть'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isVerified)
                    const _TagBadge(
                      label: 'Проверена',
                      backgroundColor: Color(0xFF122E3A),
                      borderColor: Color(0xFF53B6D9),
                    ),
                  if (isCompleted)
                    const _TagBadge(
                      label: 'Выполнена',
                      backgroundColor: Color(0xFF3A2812),
                      borderColor: Color(0xFFE0A54A),
                    ),
                  if (isActive)
                    const _TagBadge(
                      label: 'Активная',
                      backgroundColor: Color(0xFF123524),
                      borderColor: Color(0xFF35C886),
                    )
                  else
                    TextButton(
                      onPressed: onActivate,
                      child: const Text('Активировать'),
                    ),
                ],
              ),
            ],
          ),
          if (isCompleted && completedBy != null) ...[
            const SizedBox(height: 8),
            Text(
              'Отметил выполнение: $completedBy',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (isVerified && verifiedBy != null) ...[
            const SizedBox(height: 6),
            Text(
              'Проверил: $verifiedBy',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            assignees.isEmpty
                ? 'Сотрудники не закреплены'
                : 'Закреплённые сотрудники',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (assignees.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final assignee in assignees)
                  _TagBadge(
                    label: assignee,
                    backgroundColor: const Color(0xFF143456),
                    borderColor: const Color(0xFF2A648E),
                  ),
              ],
            ),
          ],
          if (canManageAssignees) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onManageAssignees,
              child: const Text('Закрепить сотрудников'),
            ),
          ],
          if (canMarkCompleted) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onMarkCompleted,
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Отметить выполненной'),
            ),
          ],
          if (canMarkVerified) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onMarkVerified,
              icon: const Icon(Icons.verified_rounded),
              label: const Text('Пометить проверенной'),
            ),
          ],
          if (canMarkArchived) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onMarkArchived,
              icon: const Icon(Icons.archive_rounded),
              label: const Text('Отправить в архив'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    required this.subtitle,
    required this.role,
    required this.position,
  });

  final String title;
  final String subtitle;
  final String role;
  final String position;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1D33),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E466A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TagBadge(
                label: _roleLabel(role),
                backgroundColor: const Color(0xFF143456),
                borderColor: const Color(0xFF2A648E),
              ),
              if (position.trim().isNotEmpty)
                _TagBadge(
                  label: position,
                  backgroundColor: const Color(0xFF123524),
                  borderColor: const Color(0xFF35C886),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _roleLabel(String value) {
    switch (value) {
      case 'owner':
        return 'Владелец';
      case 'admin':
        return 'Администратор';
      case 'member':
        return 'Сотрудник';
      default:
        return value;
    }
  }
}

class _TagBadge extends StatelessWidget {
  const _TagBadge({
    required this.label,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String label;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
