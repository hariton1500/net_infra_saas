import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/employee_positions.dart';
import '../widgets/responsive_app_bar_actions.dart';
import '../widgets/screen_instruction.dart';
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

  String get _selectedInvitePosition {
    final normalized = normalizeEmployeePosition(_selectedPosition);
    return employeePositions.contains(normalized)
        ? normalized
        : employeePositionEngineer;
  }

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
                tooltip: tr('Refresh'),
                onPressed: controller.isBusy ? null : _refreshTeam,
                icon: const Icon(Icons.refresh_rounded),
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
                  if (value == 'refresh') {
                    _refreshTeam();
                  } else if (value == 'sign_out') {
                    controller.signOut();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'refresh',
                    enabled: !controller.isBusy,
                    child: Text(tr('Refresh')),
                  ),
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ScreenInstruction(
                text: tr(
                  'Review company details, manage the team, and use refresh to load the latest employees and invites.',
                ),
              ),
              const SizedBox(height: 20),
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
                              membership?.companyName ?? tr('Company'),
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              tr('You are signed in as {name}.', {
                                'name': profile?.fullName.isNotEmpty == true
                                    ? profile!.fullName
                                    : user?.email ?? tr('Employee'),
                              }),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr('Company role: {role}', {
                                'role': _roleLabel(
                                  membership?.role ?? 'member',
                                ),
                              }),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr('Company slug: {slug}', {
                                'slug': membership?.slug ?? '-',
                              }),
                            ),
                          ],
                        ),
                      ),
                      _MetricCard(
                        title: tr('Employees'),
                        value: '${controller.teamMembers.length}',
                        caption: tr('Active team members'),
                      ),
                      _MetricCard(
                        title: tr('Invites'),
                        value: '${controller.pendingInvites.length}',
                        caption: tr('Awaiting acceptance'),
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
                    title: tr('Profile'),
                    lines: [
                      tr('Email: {value}', {
                        'value': profile?.email ?? user?.email ?? '-',
                      }),
                      tr('Position: {value}', {
                        'value': profile?.position.isNotEmpty == true
                            ? employeePositionLabel(profile!.position)
                            : '-',
                      }),
                      tr('Name: {value}', {
                        'value': profile?.fullName.isNotEmpty == true
                            ? profile!.fullName
                            : '-',
                      }),
                    ],
                  ),
                  _InfoCard(
                    title: tr('Company'),
                    lines: [
                      tr('Title: {value}', {
                        'value': membership?.companyName ?? '-',
                      }),
                      tr('Slug: {value}', {'value': membership?.slug ?? '-'}),
                      tr('Role: {value}', {
                        'value': membership == null
                            ? '-'
                            : _roleLabel(membership.role),
                      }),
                    ],
                  ),
                  _InfoCard(
                    title: tr('Invites'),
                    lines: controller.canManageTeam
                        ? [
                            tr('Below you can invite employees by email.'),
                            tr(
                              'If the employee registers with this email, the membership will be attached automatically.',
                            ),
                          ]
                        : [
                            tr(
                              'The team list and pending invites are available for viewing.',
                            ),
                            tr(
                              'Creating invites is available to owners and administrators.',
                            ),
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
                tr('Invite employee'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  'Create an invite using a work email. The employee will register with this email and automatically join the company.',
                ),
              ),
              const SizedBox(height: 14),
              if (canAssignPosition)
                DropdownButtonFormField<String>(
                  initialValue: _selectedInvitePosition,
                  decoration: InputDecoration(labelText: tr('Position')),
                  items: employeePositions
                      .map(
                        (position) => DropdownMenuItem<String>(
                          value: position,
                          child: Text(employeePositionLabel(position)),
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
                )
              else
                Text(
                  tr(
                    'Only the company owner can assign a position. Employees will use the default position by default.',
                  ),
                ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _inviteEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: tr('Employee email')),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return tr('Enter an email address.');
                  }

                  if (!value.contains('@')) {
                    return tr('Enter a valid email address.');
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: InputDecoration(labelText: tr('Company role')),
                items: [
                  DropdownMenuItem(
                    value: 'member',
                    child: Text(tr('Employee')),
                  ),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text(tr('Administrator')),
                  ),
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
                    : Text(tr('Send invite')),
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
              tr('Company team'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (team.isEmpty)
              Text(tr('There are no employees yet.'))
            else
              for (final member in team) ...[
                _PersonRow(
                  title: member.fullName.trim().isNotEmpty
                      ? member.fullName.trim()
                      : member.email.trim().isNotEmpty
                      ? member.email.trim()
                      : '${tr('Employee')} ${member.userId.substring(0, member.userId.length < 8 ? member.userId.length : 8)}',
                  subtitle: member.email.trim().isNotEmpty
                      ? member.email.trim()
                      : tr('ID: {value}', {'value': member.userId}),
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
              tr('Pending invites'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (invites.isEmpty)
              Text(tr('There are no active invites.'))
            else
              for (final invite in invites) ...[
                _PersonRow(
                  title: invite.email,
                  subtitle: tr('Code: {token} • {date}', {
                    'token': invite.token,
                    'date': _formatDate(invite.createdAt),
                  }),
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
        position: _selectedInvitePosition,
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
          widget.controller.errorMessage ?? tr('Failed to create the invite.');
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
          widget.controller.errorMessage ?? tr('Failed to refresh the data.');
      logUserFacingError(message, source: 'dashboard.refresh');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _formatDate(DateTime value) {
    return AppI18n.instance.formatDateTime(value);
  }

  String _roleLabel(String value) {
    switch (value) {
      case 'owner':
        return tr('Owner');
      case 'admin':
        return tr('Administrator');
      case 'member':
        return tr('Employee');
      default:
        return value;
    }
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
                label: employeePositionLabel(position),
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
        return tr('Owner');
      case 'admin':
        return tr('Administrator');
      case 'member':
        return tr('Employee');
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
