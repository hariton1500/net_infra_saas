const String projectsModuleKey = 'projects';
const String projectsCacheKey = 'projects.records.v1';

const String projectCreatorPositionChiefEngineer = 'Главный инженер';
const String projectCreatorPositionEngineer = 'Инженер';

class ProjectSelection {
  const ProjectSelection({
    required this.id,
    required this.name,
    this.authorUserId,
    this.authorEmail,
  });

  final int id;
  final String name;
  final String? authorUserId;
  final String? authorEmail;
}

bool canCreateProjectsForPosition(String position) {
  final normalized = position.trim();
  return normalized == projectCreatorPositionEngineer ||
      normalized == projectCreatorPositionChiefEngineer;
}

int? projectIdOf(Map<String, dynamic> record) {
  final value = record['task_id'] ?? record['project_id'] ?? record['id'];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

String? projectNameOf(Map<String, dynamic> record) {
  final value =
      (record['project_name'] ?? record['name'])?.toString().trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

bool matchesProjectFilter(Map<String, dynamic> record, int? projectId) {
  if (projectId == null) {
    return true;
  }
  return projectIdOf(record) == projectId;
}

void applyProjectSelection(
  Map<String, dynamic> target,
  ProjectSelection? project,
) {
  if (project == null) {
    target.remove('task_id');
    target.remove('project_id');
    target.remove('project_name');
    return;
  }

  target['task_id'] = project.id;
  target.remove('project_id');
  target.remove('project_name');
}
