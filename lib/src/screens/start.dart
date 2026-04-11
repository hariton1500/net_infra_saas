import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_logger.dart';
import '../core/employee_positions.dart';
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
