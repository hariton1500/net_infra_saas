import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';
import '../core/employee_positions.dart';
import 'profile_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _inviteFormKey = GlobalKey<FormState>();
  final _inviteEmailController = TextEditingController();
  String _selectedRole = 'member';
  String _selectedPosition = employeePositionEngineer;

  @override
  void dispose() {
    _inviteEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final profile = controller.profile;
    final membership = controller.membership;
    final user = controller.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Net Infra SaaS'),
        actions: [
          IconButton(
            tooltip: 'Профиль',
            onPressed: controller.isBusy
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(controller: controller),
                      ),
                    );
                  },
            icon: const Icon(Icons.person_outline_rounded),
          ),
          IconButton(
            tooltip: 'Обновить',
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Wrap(
                    runSpacing: 18,
                    spacing: 18,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 560,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              membership?.companyName ?? 'Компания',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Вы вошли как ${profile?.fullName.isNotEmpty == true ? profile!.fullName : user?.email ?? 'сотрудник'}.',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Роль в компании: ${membership?.role ?? 'member'}',
                            ),
                            const SizedBox(height: 6),
                            Text('Slug компании: ${membership?.slug ?? '-'}'),
                          ],
                        ),
                      ),
                      _MetricCard(
                        title: 'Сотрудники',
                        value: '${controller.teamMembers.length}',
                        caption: 'Активных участников команды',
                      ),
                      _MetricCard(
                        title: 'Инвайты',
                        value: '${controller.pendingInvites.length}',
                        caption: 'Ожидают принятия',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  _InfoCard(
                    title: 'Профиль',
                    lines: [
                      'Email: ${profile?.email ?? user?.email ?? '-'}',
                      'Должность: ${profile?.position.isNotEmpty == true ? profile!.position : '-'}',
                      'Имя: ${profile?.fullName.isNotEmpty == true ? profile!.fullName : '-'}',
                    ],
                  ),
                  _InfoCard(
                    title: 'Компания',
                    lines: [
                      'Название: ${membership?.companyName ?? '-'}',
                      'Slug: ${membership?.slug ?? '-'}',
                      'Роль: ${membership?.role ?? '-'}',
                    ],
                  ),
                  _InfoCard(
                    title: 'Приглашения',
                    lines: controller.canManageTeam
                        ? const [
                            'Ниже можно приглашать сотрудников по email.',
                            'Если сотрудник зарегистрируется с этим email, его membership подключится автоматически.',
                          ]
                        : const [
                            'Список команды и pending invites доступен для просмотра.',
                            'Создание приглашений доступно владельцам и администраторам.',
                          ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 920;

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (controller.canManageTeam) _buildInviteCard(context),
                        if (controller.canManageTeam)
                          const SizedBox(height: 20),
                        _buildTeamCard(context),
                        const SizedBox(height: 20),
                        _buildInvitesCard(context),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            if (controller.canManageTeam)
                              _buildInviteCard(context),
                            if (controller.canManageTeam)
                              const SizedBox(height: 20),
                            _buildInvitesCard(context),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(child: _buildTeamCard(context)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInviteCard(BuildContext context) {
    final controller = widget.controller;

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
                'Создайте приглашение по рабочему email. Сотрудник зарегистрируется с этим email и автоматически попадёт в компанию.',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedPosition,
                decoration: const InputDecoration(labelText: 'Должность'),
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
                    : const Text('Отправить приглашение'),
              ),
            ],
          ),
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
                _PersonRow(
                  title: member.fullName.isEmpty
                      ? member.email
                      : member.fullName,
                  subtitle: member.email,
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

  Widget _buildInvitesCard(BuildContext context) {
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
                _PersonRow(
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
      logUserFacingError(message, source: 'dashboard.invite');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _refreshTeam() async {
    try {
      await widget.controller.refreshCompanyData();
    } catch (_) {
      if (!mounted) {
        return;
      }

      final message =
          widget.controller.errorMessage ?? 'Не удалось обновить данные.';
      logUserFacingError(message, source: 'dashboard.refresh');
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

    return '$day.$month ${value.year} $hour:$minute';
  }

  String _tagWithPosition(String role, String position) {
    final normalizedPosition = position.trim();
    if (normalizedPosition.isEmpty) {
      return role;
    }

    return '$role • $normalizedPosition';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1D33),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1E466A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(caption),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 330,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              for (final line in lines) ...[
                Text(line),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
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
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
