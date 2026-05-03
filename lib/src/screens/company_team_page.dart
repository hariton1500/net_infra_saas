import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/employee_positions.dart';
import '../widgets/screen_instruction.dart';

class CompanyTeamPage extends StatefulWidget {
  const CompanyTeamPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<CompanyTeamPage> createState() => _CompanyTeamPageState();
}

class _CompanyTeamPageState extends State<CompanyTeamPage> {
  final _inviteFormKey = GlobalKey<FormState>();
  final _inviteEmailController = TextEditingController();
  String _selectedRole = 'member';
  String _selectedPosition = employeePositionEngineer;

  @override
  void dispose() {
    _inviteEmailController.dispose();
    super.dispose();
  }

  String get _selectedInvitePosition {
    final normalized = normalizeEmployeePosition(_selectedPosition);
    return employeePositions.contains(normalized)
        ? normalized
        : employeePositionEngineer;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Company team')),
        actions: [
          IconButton(
            tooltip: tr('Refresh data'),
            onPressed: controller.isBusy ? null : _refreshTeam,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ScreenInstruction(
                text: tr(
                  'Review company employees, active invites, and invite new employees by work email when your role allows it.',
                ),
              ),
              const SizedBox(height: 20),
              if (controller.canManageTeam) ...[
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
                  'The invite is created by work email. After registering with this email, the employee will automatically join the company.',
                ),
              ),
              const SizedBox(height: 14),
              if (canAssignPosition)
                DropdownButtonFormField<String>(
                  initialValue: _selectedInvitePosition,
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
                  decoration: InputDecoration(labelText: tr('Position')),
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
                    : Text(tr('Create invite')),
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
                _InfoRow(
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
                _InfoRow(
                  title: _memberTitle(
                    member.fullName,
                    member.email,
                    member.userId,
                  ),
                  subtitle: _memberSubtitle(
                    email: member.email,
                    position: member.position,
                    userId: member.userId,
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
      logUserFacingError(message, source: 'company_team.invite');
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
      logUserFacingError(message, source: 'company_team.refresh');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _formatDate(DateTime value) {
    return AppI18n.instance.formatDateTime(value);
  }

  String _memberTitle(String fullName, String email, String userId) {
    final normalizedName = fullName.trim();
    final normalizedEmail = email.trim();
    final normalizedUserId = userId.trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }
    if (normalizedEmail.isNotEmpty) {
      return normalizedEmail;
    }
    if (normalizedUserId.isNotEmpty) {
      return '${tr('Employee')} ${normalizedUserId.substring(0, normalizedUserId.length < 8 ? normalizedUserId.length : 8)}';
    }
    return tr('Employee');
  }

  String _memberSubtitle({
    required String email,
    required String position,
    String userId = '',
  }) {
    final parts = <String>[
      if (email.trim().isNotEmpty) email.trim(),
      if (position.trim().isNotEmpty) employeePositionLabel(position.trim()),
      if (email.trim().isEmpty && userId.trim().isNotEmpty)
        tr('ID: {value}', {'value': userId.trim()}),
    ];
    if (parts.isEmpty) {
      return tr('Employee profile');
    }
    return parts.join(' • ');
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
