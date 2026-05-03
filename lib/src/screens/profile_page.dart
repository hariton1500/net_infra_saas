import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/employee_positions.dart';
import '../core/strings.dart';
import '../widgets/screen_instruction.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late String _selectedPosition;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.profile;
    _fullNameController = TextEditingController(text: profile?.fullName ?? '');
    final normalizedPosition = normalizeEmployeePosition(
      profile?.position ?? '',
    );
    _selectedPosition = employeePositions.contains(normalizedPosition)
        ? normalizedPosition
        : employeePositionEngineer;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final profile = controller.profile;
    final email = profile?.email ?? controller.currentUser?.email ?? '-';
    final role = controller.membership?.role ?? '-';
    final membership = controller.membership;
    final displayName = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : email;

    return Scaffold(
      appBar: AppBar(title: Text(tr(AppStrings.employeeProfile))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _ProfileSummaryCard(
                displayName: displayName,
                position: employeePositionLabel(profile?.position ?? ''),
                companyName: membership?.companyName ?? tr('Company'),
                role: role,
                slug: membership?.slug ?? '-',
                teamSize: controller.teamMembers.length,
                inviteCount: controller.pendingInvites.length,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(AppStrings.personalDetails),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Text(tr(AppStrings.personalDetailsBody)),
                        const SizedBox(height: 16),
                        ScreenInstruction(
                          text: tr(
                            'Edit your display name and position, then save the profile so team lists show the current details.',
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          initialValue: email,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: tr(AppStrings.workEmail),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          initialValue: _roleLabel(role),
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: tr(AppStrings.companyRole),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _fullNameController,
                          decoration: InputDecoration(
                            labelText: tr(AppStrings.employeeName),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return tr(AppStrings.enterEmployeeName);
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPosition,
                          decoration: InputDecoration(
                            labelText: tr(AppStrings.position),
                          ),
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
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: controller.isBusy ? null : _saveProfile,
                          child: controller.isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(tr(AppStrings.saveProfile)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      await widget.controller.updateProfile(
        fullName: _fullNameController.text,
        position: _selectedPosition,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr(AppStrings.profileUpdated))));
    } catch (_) {
      if (!mounted) {
        return;
      }

      final message =
          widget.controller.errorMessage ?? tr(AppStrings.profileUpdateFailed);
      logUserFacingError(message, source: 'profile_page.save');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _roleLabel(String value) {
    switch (value) {
      case 'owner':
        return tr(AppStrings.owner);
      case 'admin':
        return tr(AppStrings.administrator);
      case 'member':
        return tr(AppStrings.employee);
      default:
        return value;
    }
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({
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
                    tr('Employee workspace'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(tr('User: {value}', {'value': displayName})),
                  const SizedBox(height: 6),
                  Text(tr('Company: {value}', {'value': companyName})),
                  const SizedBox(height: 6),
                  Text(tr('Role: {value}', {'value': _roleLabel(role)})),
                  if (position.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(tr('Position: {value}', {'value': position})),
                  ],
                  const SizedBox(height: 6),
                  Text(tr('Slug: {value}', {'value': slug})),
                ],
              ),
            ),
            _MetricBadge(label: tr('Employees'), value: '$teamSize'),
            _MetricBadge(label: tr('Invites'), value: '$inviteCount'),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String value) {
    switch (value) {
      case 'owner':
        return tr(AppStrings.owner);
      case 'admin':
        return tr(AppStrings.administrator);
      case 'member':
        return tr(AppStrings.employee);
      default:
        return value;
    }
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
