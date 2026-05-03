import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/company_module_sync_repository.dart';
import '../core/employee_positions.dart';
import '../core/project_scope.dart';
import '../widgets/responsive_app_bar_actions.dart';
import '../widgets/screen_instruction.dart';
import 'company_team_page.dart';
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
  static const String _taskListFilterAll = 'all';
  static const String _taskListFilterMine = 'mine';

  late final CompanyModuleSyncRepository _syncRepository;
  bool _loadingProjects = true;
  bool _syncingProjects = false;
  List<Map<String, dynamic>> _projectRecords = const [];
  ProjectSelection? _activeProject;
  String _taskListFilter = _taskListFilterMine;

  @override
  void initState() {
    super.initState();
    _syncRepository = CompanyModuleSyncRepository(
      client: widget.controller.client,
    );
    _cleanupLegacyCaches();
    _loadProjects();
  }

  Future<void> _cleanupLegacyCaches() async {
    try {
      await _syncRepository.removeCache(_legacyWorkOrdersCacheKey);
    } catch (error, stackTrace) {
      logUserFacingError(
        tr('Failed to clear the outdated local work order cache.'),
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

  bool get _canManageProjects {
    final role = widget.controller.membership?.role;
    return role == 'owner' ||
        role == 'admin' ||
        canCreateProjectsForPosition(_userPosition);
  }

  List<Map<String, dynamic>> get _projects =>
      _normalizeProjectRecords(_projectRecords);

  bool get _canSwitchTaskListFilter => _canManageProjects;

  String get _effectiveTaskListFilter =>
      _canSwitchTaskListFilter ? _taskListFilter : _taskListFilterMine;

  List<Map<String, dynamic>> get _visibleProjects {
    final projects = _projects;
    if (_effectiveTaskListFilter != _taskListFilterMine) {
      return projects;
    }
    return projects
        .where((project) => _isTaskAssignee(project))
        .toList(growable: false);
  }

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
          final inferredUserId =
              inferredMember?.userId ??
              (normalizedUpdatedBy == _currentUserEmail ? _currentUserId : '');
          final inferredName =
              inferredMember?.fullName ??
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
        tr('Failed to load tasks.'),
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
            'target_screen': entry['target_screen']?.toString() ?? '',
            'target_record_id': entry['target_record_id'],
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

  List<String> _workLogDetailsOf(Map<String, dynamic> entry) {
    final summary = entry['summary']?.toString().trim() ?? '';
    if (summary.isEmpty) {
      return const [];
    }
    return summary
        .split(' • ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  int? _workLogTargetRecordIdOf(Map<String, dynamic> entry) {
    final value = entry['target_record_id'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  String? _workLogTargetScreenOf(Map<String, dynamic> entry) {
    final value = entry['target_screen']?.toString().trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  String? _workLogTargetButtonLabel(Map<String, dynamic> entry) {
    switch (_workLogTargetScreenOf(entry)) {
      case 'muff_notebook':
        return tr('Open closure');
      case 'network_cabinet':
        return tr('Open cabinet');
      case 'infrastructure_map':
        return tr('Open route');
      default:
        return null;
    }
  }

  Future<void> _openWorkLogTarget(Map<String, dynamic> entry) async {
    final targetScreen = _workLogTargetScreenOf(entry);
    final targetRecordId = _workLogTargetRecordIdOf(entry);
    if (targetScreen == null || targetRecordId == null || !mounted) {
      return;
    }

    switch (targetScreen) {
      case 'muff_notebook':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MuffNotebookPage(
              controller: widget.controller,
              initialMuffId: targetRecordId,
            ),
          ),
        );
        if (mounted) {
          await _loadProjects();
        }
        return;
      case 'network_cabinet':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CabinetNotebookPage(
              controller: widget.controller,
              initialCabinetId: targetRecordId,
            ),
          ),
        );
        if (mounted) {
          await _loadProjects();
        }
        return;
      case 'infrastructure_map':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => InfrastructureMapPage(
              controller: widget.controller,
              initialRouteId: targetRecordId,
            ),
          ),
        );
        if (mounted) {
          await _loadProjects();
        }
        return;
    }
  }

  Map<String, dynamic> _currentTaskSnapshot(Map<String, dynamic> task) {
    final id = projectIdOf(task);
    if (id != null) {
      for (final record in _projectRecords) {
        if (projectIdOf(record) == id) {
          return _syncRepository.clone(record);
        }
      }
    }
    return _syncRepository.clone(task);
  }

  Future<void> _updateTaskRecord(
    Map<String, dynamic> task,
    void Function(Map<String, dynamic> updatedTask) mutate,
  ) async {
    final updatedTask = _currentTaskSnapshot(task);
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

  bool _canAdministrateTask(Map<String, dynamic> record) =>
      _isTaskAuthor(record);

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
    return tr('Employee');
  }

  String _memberSubtitle({required String email, required String position}) {
    final parts = <String>[
      if (email.trim().isNotEmpty) email.trim(),
      if (position.trim().isNotEmpty) employeePositionLabel(position.trim()),
    ];
    if (parts.isEmpty) {
      return tr('Employee profile');
    }
    return parts.join(' • ');
  }

  String _formatDate(DateTime value) {
    return AppI18n.instance.formatDateTime(value);
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
          SnackBar(
            content: Text(tr('There are no employees in the company yet.')),
          ),
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
                tr('Task employees "{name}"', {
                  'name': projectNameOf(task) ?? tr('Untitled'),
                }),
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
                  child: Text(tr('Cancel')),
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
                  child: Text(tr('Save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showTaskDetailsDialog(Map<String, dynamic> task) async {
    final currentTask = _currentTaskSnapshot(task);
    final assignees = _assignedEmployeesOf(currentTask)
        .map(
          (employee) => _employeeDisplayName(
            fullName: employee['full_name'] ?? '',
            email: employee['email'] ?? '',
          ),
        )
        .toList(growable: false);
    final workLog = _taskWorkLogOf(currentTask);
    final isActive = _activeProject?.id == projectIdOf(currentTask);
    final isCompleted = _isTaskCompleted(currentTask);
    final isVerified = _isTaskVerified(currentTask);
    final canManageAssignees = _canAdministrateTask(currentTask);
    final canMarkCompleted =
        _isTaskAssignee(currentTask) &&
        !isCompleted &&
        !_isTaskArchived(currentTask);
    final canMarkVerified =
        _canAdministrateTask(currentTask) && isCompleted && !isVerified;
    final canMarkArchived =
        _canAdministrateTask(currentTask) &&
        isVerified &&
        !_isTaskArchived(currentTask);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(projectNameOf(currentTask) ?? tr('Task')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((currentTask['description'] as String?)
                          ?.trim()
                          .isNotEmpty ==
                      true)
                    _TaskDescription(
                      description: (currentTask['description'] as String)
                          .trim(),
                    )
                  else
                    Text(tr('Description is empty.')),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isActive)
                        _TagBadge(
                          label: tr('Active'),
                          backgroundColor: Color(0xFF123524),
                          borderColor: Color(0xFF35C886),
                        ),
                      if (isCompleted)
                        _TagBadge(
                          label: tr('Completed'),
                          backgroundColor: Color(0xFF3A2812),
                          borderColor: Color(0xFFE0A54A),
                        ),
                      if (isVerified)
                        _TagBadge(
                          label: tr('Verified'),
                          backgroundColor: Color(0xFF122E3A),
                          borderColor: Color(0xFF53B6D9),
                        ),
                    ],
                  ),
                  if (_taskCompletedBy(currentTask) != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      tr('Completed by: {name}', {
                        'name': _taskCompletedBy(currentTask)!,
                      }),
                    ),
                  ],
                  if (_taskVerifiedBy(currentTask) != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      tr('Verified by: {name}', {
                        'name': _taskVerifiedBy(currentTask)!,
                      }),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    assignees.isEmpty
                        ? tr('No assignees assigned')
                        : tr('Assigned employees'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
                    tr('Work list'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (workLog.isEmpty)
                    Text(tr('There are no recorded additions yet.'))
                  else
                    Column(
                      children: [
                        for (final entry in workLog)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C1D33),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF1E466A),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatDate(
                                    _syncRepository.parseTime(entry['at']),
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF9FB7CC),
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  entry['kind']?.toString() ?? '',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                for (final detail in _workLogDetailsOf(
                                  entry,
                                )) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Icon(
                                          Icons.circle,
                                          size: 6,
                                          color: Color(0xFF53B6D9),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          detail,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (_workLogTargetButtonLabel(entry) !=
                                    null) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _openWorkLogTarget(entry),
                                      icon: const Icon(
                                        Icons.open_in_new_rounded,
                                      ),
                                      label: Text(
                                        _workLogTargetButtonLabel(entry)!,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  Text(
                    tr('Actions'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canManageAssignees)
                        TextButton(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            navigator.pop();
                            await _showTaskAssigneesEditor(currentTask);
                          },
                          child: Text(tr('Assignees')),
                        ),
                      if (canMarkCompleted)
                        FilledButton.tonal(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await _markTaskCompleted(currentTask);
                            if (!mounted) {
                              return;
                            }
                            navigator.pop();
                          },
                          child: Text(tr('Completed')),
                        ),
                      if (canMarkVerified)
                        FilledButton.tonal(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await _markTaskVerified(currentTask);
                            if (!mounted) {
                              return;
                            }
                            navigator.pop();
                          },
                          child: Text(tr('Verified')),
                        ),
                      if (canMarkArchived)
                        FilledButton.tonal(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await _markTaskArchived(currentTask);
                            if (!mounted) {
                              return;
                            }
                            navigator.pop();
                          },
                          child: Text(tr('Archive')),
                        ),
                      if (!canManageAssignees &&
                          !canMarkCompleted &&
                          !canMarkVerified &&
                          !canMarkArchived)
                        Text(
                          tr(
                            'There are no actions available for this task now.',
                          ),
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
              child: Text(tr('Close')),
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
        'Failed to save tasks.',
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
        ..showSnackBar(SnackBar(content: Text(tr('Failed to save tasks.'))));
    }
  }

  Future<void> _showProjectEditor() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr('New task')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(labelText: tr('Short title')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(labelText: tr('Description')),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Cancel')),
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
                  'created_by_email':
                      widget.controller.currentUser?.email ?? '',
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
                  ..._projectRecords.map(
                    (record) => _syncRepository.clone(record),
                  ),
                  record,
                ];
                await _persistProjects(nextRecords);
                if (!mounted) {
                  return;
                }
                navigator.pop();
              },
              child: Text(tr('Create')),
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
    final authorEmail = project['created_by_email']
        ?.toString()
        .trim()
        .toLowerCase();
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

  void _showMainScreenHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => const _MainScreenHelpDialog(),
    );
  }

  Widget _buildProjectsCard(BuildContext context) {
    final projects = _visibleProjects;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  tr('Tasks'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_canManageProjects)
                  FilledButton.tonalIcon(
                    onPressed: _syncingProjects ? null : _showProjectEditor,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(tr('Create')),
                  ),
              ],
            ),
            if (_canSwitchTaskListFilter) ...[
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment<String>(
                    value: _taskListFilterAll,
                    label: Text(tr('All')),
                  ),
                  ButtonSegment<String>(
                    value: _taskListFilterMine,
                    label: Text(tr('Mine')),
                  ),
                ],
                selected: {_effectiveTaskListFilter},
                onSelectionChanged: (selection) {
                  setState(() {
                    _taskListFilter = selection.first;
                  });
                },
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _activeProject == null
                        ? tr('Active task is turned off.')
                        : tr('Active task: {name}', {
                            'name': _activeProject!.name,
                          }),
                  ),
                ),
                if (_activeProject != null)
                  TextButton(
                    onPressed: _clearActiveProject,
                    child: Text(tr('Turn off')),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingProjects)
              const Center(child: CircularProgressIndicator())
            else if (projects.isEmpty)
              Text(
                _effectiveTaskListFilter == _taskListFilterMine
                    ? tr('You do not have assigned tasks yet.')
                    : tr('There are no tasks yet.'),
              )
            else
              Column(
                children: [
                  for (final project in projects) ...[
                    _ProjectRow(
                      title: projectNameOf(project) ?? tr('Untitled'),
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
                      onManageAssignees: () =>
                          _showTaskAssigneesEditor(project),
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
    final membership = controller.membership;

    return Scaffold(
      appBar: AppBar(
        title: Text(membership?.companyName ?? 'Net Infra SaaS'),
        actions: [
          ResponsiveAppBarActions(
            actions: [
              IconButton(
                tooltip: tr('Profile'),
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
                tooltip: tr('Company team'),
                onPressed: controller.isBusy ? null : _openCompanyTeam,
                icon: const Icon(Icons.groups_2_outlined),
              ),
              IconButton(
                tooltip: tr('Refresh data'),
                onPressed: controller.isBusy ? null : _refreshTeam,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: tr('Screen guide'),
                onPressed: _showMainScreenHelp,
                icon: const Icon(Icons.info_outline_rounded),
              ),
              TextButton(
                onPressed: controller.isBusy ? null : controller.signOut,
                child: Text(tr('Sign out')),
              ),
              const SizedBox(width: 12),
            ],
            compactActions: [
              IconButton(
                tooltip: tr('Profile'),
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
              PopupMenuButton<String>(
                tooltip: tr('Actions'),
                onSelected: (value) {
                  if (value == 'team') {
                    _openCompanyTeam();
                  } else if (value == 'refresh') {
                    _refreshTeam();
                  } else if (value == 'help') {
                    _showMainScreenHelp();
                  } else if (value == 'sign_out') {
                    controller.signOut();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'team',
                    enabled: !controller.isBusy,
                    child: Text(tr('Company team')),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    enabled: !controller.isBusy,
                    child: Text(tr('Refresh data')),
                  ),
                  PopupMenuItem(value: 'help', child: Text(tr('Screen guide'))),
                  PopupMenuItem(
                    value: 'sign_out',
                    enabled: !controller.isBusy,
                    child: Text(tr('Sign out')),
                  ),
                ],
              ),
            ],
          ),
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
                  ScreenInstruction(
                    text: tr(
                      'Choose or create an active task, then open a work section to add map objects, closures, cabinets, and routes to it.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildProjectsCard(context),
                  const SizedBox(height: 20),
                  Text(
                    tr('Work sections'),
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
                          title: tr('Infrastructure map'),
                          description: tr(
                            'Quick access to the map of closures, PON boxes, cable routes, and connection points.',
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => InfrastructureMapPage(
                                  controller: controller,
                                ),
                              ),
                            );
                            if (mounted) {
                              await _loadProjects();
                            }
                          },
                        ),
                        _ActionCard(
                          icon: Icons.notes_rounded,
                          title: tr('Closure notebook'),
                          description: tr(
                            'Operational work with installation nodes, notes, and maintenance.',
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    MuffNotebookPage(controller: controller),
                              ),
                            );
                            if (mounted) {
                              await _loadProjects();
                            }
                          },
                        ),
                        _ActionCard(
                          icon: Icons.timeline_rounded,
                          title: tr('Cable lines'),
                          description: tr(
                            'Cable routes are now built and edited directly on the infrastructure map.',
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => InfrastructureMapPage(
                                  controller: controller,
                                ),
                              ),
                            );
                            if (mounted) {
                              await _loadProjects();
                            }
                          },
                        ),
                        _ActionCard(
                          icon: Icons.dns_rounded,
                          title: tr('Network cabinets'),
                          description: tr(
                            'View cabinets, equipment, and placement point status.',
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    CabinetNotebookPage(controller: controller),
                              ),
                            );
                            if (mounted) {
                              await _loadProjects();
                            }
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
          widget.controller.errorMessage ?? tr('Failed to refresh the data.');
      logUserFacingError(message, source: 'start.refresh');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openCompanyTeam() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CompanyTeamPage(controller: widget.controller),
      ),
    );
    if (mounted) {
      await _refreshTeam();
    }
  }
}

class _MainScreenHelpDialog extends StatelessWidget {
  const _MainScreenHelpDialog();

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
          Expanded(child: Text(tr('Main screen guide'))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MainHelpSection(
                icon: Icons.task_alt_rounded,
                title: tr('Tasks'),
                body: tr(
                  'Tasks group field work. Create a task, assign employees, open task details, then mark it completed, verified, and archived when the workflow is done.',
                ),
                image: const _MainTasksHelpPicture(),
              ),
              _MainHelpSection(
                icon: Icons.play_circle_outline_rounded,
                title: tr('Active task'),
                body: tr(
                  'Activate a task before opening work sections. New closures, cabinets, routes, and map changes are linked to the active task. Use Turn off when you need to work without a task.',
                ),
                image: const _MainActiveTaskHelpPicture(),
              ),
              _MainHelpSection(
                icon: Icons.apps_rounded,
                title: tr('Work sections'),
                body: tr(
                  'Open Infrastructure map for routes and map objects, Closure notebook for mufts and fibers, Cable lines for route entry, and Network cabinets for cabinets, switches, ports, and connections.',
                ),
                image: const _MainSectionsHelpPicture(),
              ),
              _MainHelpSection(
                icon: Icons.groups_2_outlined,
                title: tr('Company team'),
                body: tr(
                  'Use the team button in the top bar to review employees, pending invites, and invite new employees when your role allows it.',
                ),
                image: const _MainTeamHelpPicture(),
              ),
              _MainHelpSection(
                icon: Icons.person_outline_rounded,
                title: tr('Profile'),
                body: tr(
                  'Use the profile button to update your display name and position. Email and company role are read-only.',
                ),
                image: const _MainProfileHelpPicture(),
              ),
              _MainHelpSection(
                icon: Icons.refresh_rounded,
                title: tr('Refresh and sign out'),
                body: tr(
                  'Refresh reloads company data, tasks, employees, and pending invites. Sign out closes the current account session.',
                ),
                image: const _MainRefreshHelpPicture(),
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

class _MainHelpSection extends StatelessWidget {
  const _MainHelpSection({
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

class _MainHelpPictureFrame extends StatelessWidget {
  const _MainHelpPictureFrame({required this.child});

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

class _MainTasksHelpPicture extends StatelessWidget {
  const _MainTasksHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _MainHelpPictureFrame(
      child: CustomPaint(painter: _MainTasksHelpPainter()),
    );
  }
}

class _MainActiveTaskHelpPicture extends StatelessWidget {
  const _MainActiveTaskHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _MainHelpPictureFrame(
      child: Center(
        child: Icon(Icons.task_alt_rounded, color: Color(0xFF8BF0B8), size: 48),
      ),
    );
  }
}

class _MainSectionsHelpPicture extends StatelessWidget {
  const _MainSectionsHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _MainHelpPictureFrame(
      child: CustomPaint(painter: _MainSectionsHelpPainter()),
    );
  }
}

class _MainTeamHelpPicture extends StatelessWidget {
  const _MainTeamHelpPicture();

  @override
  Widget build(BuildContext context) {
    return _MainHelpPictureFrame(
      child: CustomPaint(painter: _MainTeamHelpPainter()),
    );
  }
}

class _MainProfileHelpPicture extends StatelessWidget {
  const _MainProfileHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _MainHelpPictureFrame(
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          color: Color(0xFF53B6D9),
          size: 48,
        ),
      ),
    );
  }
}

class _MainRefreshHelpPicture extends StatelessWidget {
  const _MainRefreshHelpPicture();

  @override
  Widget build(BuildContext context) {
    return const _MainHelpPictureFrame(
      child: Center(
        child: Icon(Icons.refresh_rounded, color: Color(0xFF35C886), size: 48),
      ),
    );
  }
}

class _MainTasksHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final panelPaint = Paint()..color = const Color(0xFF143456);
    final activePaint = Paint()..color = const Color(0xFF35C886);
    final donePaint = Paint()..color = const Color(0xFFE0A54A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.12,
          size.height * 0.16,
          size.width * 0.76,
          size.height * 0.68,
        ),
        const Radius.circular(8),
      ),
      panelPaint,
    );
    for (var i = 0; i < 3; i++) {
      final top = size.height * (0.28 + i * 0.16);
      canvas.drawCircle(
        Offset(size.width * 0.22, top + 4),
        5,
        Paint()..color = i == 0 ? activePaint.color : donePaint.color,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.3, top, size.width * 0.38, 9),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xFF50749A),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MainSectionsHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF143456),
      const Color(0xFF123524),
      const Color(0xFF3A2812),
      const Color(0xFF122E3A),
    ];
    final icons = [
      Icons.map_outlined,
      Icons.notes_rounded,
      Icons.timeline_rounded,
      Icons.dns_rounded,
    ];
    final iconPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < 4; i++) {
      final col = i % 2;
      final row = i ~/ 2;
      final rect = Rect.fromLTWH(
        size.width * (0.18 + col * 0.34),
        size.height * (0.2 + row * 0.32),
        size.width * 0.24,
        size.height * 0.22,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()..color = colors[i],
      );
      iconPainter.text = TextSpan(
        text: String.fromCharCode(icons[i].codePoint),
        style: TextStyle(
          fontFamily: icons[i].fontFamily,
          package: icons[i].fontPackage,
          color: const Color(0xFFF2F7FA),
          fontSize: 24,
        ),
      );
      iconPainter.layout();
      iconPainter.paint(
        canvas,
        Offset(
          rect.center.dx - iconPainter.width / 2,
          rect.center.dy - iconPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MainTeamHelpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rowPaint = Paint()..color = const Color(0xFF143456);
    final badgePaint = Paint()..color = const Color(0xFF35C886);
    for (var i = 0; i < 3; i++) {
      final top = size.height * (0.22 + i * 0.2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.14, top, size.width * 0.72, 18),
          const Radius.circular(6),
        ),
        rowPaint,
      );
      canvas.drawCircle(Offset(size.width * 0.22, top + 9), 5, badgePaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.58, top + 5, size.width * 0.2, 8),
          const Radius.circular(4),
        ),
        badgePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                      _TaskDescription(description: description),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onOpenDetails,
                      child: Text(tr('Open')),
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
                    _TagBadge(
                      label: tr('Verified'),
                      backgroundColor: Color(0xFF122E3A),
                      borderColor: Color(0xFF53B6D9),
                    ),
                  if (isCompleted)
                    _TagBadge(
                      label: tr('Completed'),
                      backgroundColor: Color(0xFF3A2812),
                      borderColor: Color(0xFFE0A54A),
                    ),
                  if (isActive)
                    _TagBadge(
                      label: tr('Active'),
                      backgroundColor: Color(0xFF123524),
                      borderColor: Color(0xFF35C886),
                    )
                  else
                    TextButton(
                      onPressed: onActivate,
                      child: Text(tr('Activate')),
                    ),
                ],
              ),
            ],
          ),
          if (isCompleted && completedBy != null) ...[
            const SizedBox(height: 8),
            Text(
              tr('Marked completed by: {name}', {'name': completedBy!}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (isVerified && verifiedBy != null) ...[
            const SizedBox(height: 6),
            Text(
              tr('Verified by: {name}', {'name': verifiedBy!}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            assignees.isEmpty
                ? tr('No employees assigned')
                : tr('Assigned employees'),
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
              child: Text(tr('Assign employees')),
            ),
          ],
          if (canMarkCompleted) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onMarkCompleted,
              icon: const Icon(Icons.task_alt_rounded),
              label: Text(tr('Mark completed')),
            ),
          ],
          if (canMarkVerified) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onMarkVerified,
              icon: const Icon(Icons.verified_rounded),
              label: Text(tr('Mark verified')),
            ),
          ],
          if (canMarkArchived) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onMarkArchived,
              icon: const Icon(Icons.archive_rounded),
              label: Text(tr('Send to archive')),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskDescription extends StatelessWidget {
  const _TaskDescription({required this.description});

  final String description;

  List<String> get _lines => description
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (lines.length <= 1) {
      return Text(description.trim());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines
          .map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line),
            ),
          )
          .toList(growable: false),
    );
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
