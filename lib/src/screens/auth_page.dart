import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/employee_positions.dart';
import '../widgets/screen_instruction.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _signInFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();
  final _resetPasswordFormKey = GlobalKey<FormState>();

  final _signInEmailController = TextEditingController();
  final _signInPasswordController = TextEditingController();

  final _signUpFullNameController = TextEditingController();
  final _signUpCompanyController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPasswordController = TextEditingController();

  final _recoveryEmailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmNewPasswordController = TextEditingController();

  String _selectedSignUpPosition = employeePositionEngineer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpFullNameController.dispose();
    _signUpCompanyController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    _recoveryEmailController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.view == AuthView.passwordRecovery) {
      return Scaffold(
        body: _BackgroundShell(
          child: _AuthHelpShell(
            onHelp: _showAuthHelp,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScreenInstruction(
                            text: tr(
                              'Enter your new password twice, save it, then sign in with the updated credentials.',
                            ),
                          ),
                          const SizedBox(height: 18),
                          _ResetPasswordForm(
                            formKey: _resetPasswordFormKey,
                            passwordController: _newPasswordController,
                            confirmPasswordController:
                                _confirmNewPasswordController,
                            controller: widget.controller,
                            onSubmit: _handleCompletePasswordRecovery,
                            onSignOut: _handleSignOut,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: _BackgroundShell(
        child: _AuthHelpShell(
          onHelp: _showAuthHelp,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 840;
                      final authCard = Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0C1D33),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: TabBar(
                                  controller: _tabController,
                                  indicatorSize: TabBarIndicatorSize.tab,
                                  tabs: [
                                    Tab(text: tr('Sign in')),
                                    Tab(text: tr('Sign up')),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              ScreenInstruction(
                                text: tr(
                                  'Use the sign-in tab for an existing employee account, or create the first company account on the sign-up tab.',
                                ),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 560,
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _SignInForm(
                                      formKey: _signInFormKey,
                                      emailController: _signInEmailController,
                                      passwordController:
                                          _signInPasswordController,
                                      controller: widget.controller,
                                      onSubmit: _handleSignIn,
                                      onForgotPassword:
                                          _openResetPasswordDialog,
                                    ),
                                    _SignUpForm(
                                      formKey: _signUpFormKey,
                                      fullNameController:
                                          _signUpFullNameController,
                                      selectedPosition: _selectedSignUpPosition,
                                      onPositionChanged: (value) {
                                        setState(() {
                                          _selectedSignUpPosition = value;
                                        });
                                      },
                                      companyController:
                                          _signUpCompanyController,
                                      emailController: _signUpEmailController,
                                      passwordController:
                                          _signUpPasswordController,
                                      controller: widget.controller,
                                      onSubmit: _handleSignUp,
                                      onGoToSignIn: _switchToSignIn,
                                      onForgotPassword:
                                          _openResetPasswordDialog,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );

                      if (isCompact) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _BrandPanel(isCompact: true),
                            const SizedBox(height: 24),
                            authCard,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(child: _BrandPanel(isCompact: false)),
                          const SizedBox(width: 24),
                          Expanded(child: authCard),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAuthHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => const _AuthHelpDialog(),
    );
  }

  Future<void> _handleSignIn() async {
    if (!_signInFormKey.currentState!.validate()) {
      return;
    }

    try {
      await widget.controller.signIn(
        email: _signInEmailController.text,
        password: _signInPasswordController.text,
      );
    } catch (_) {
      _showErrorMessage(
        widget.controller.errorMessage ?? tr('Failed to sign in.'),
      );
    }
  }

  Future<void> _handleSignUp() async {
    if (!_signUpFormKey.currentState!.validate()) {
      return;
    }

    try {
      final message = await widget.controller.signUp(
        fullName: _signUpFullNameController.text,
        position: _selectedSignUpPosition,
        companyName: _signUpCompanyController.text,
        email: _signUpEmailController.text,
        password: _signUpPasswordController.text,
      );
      _showMessage(message);
    } catch (_) {
      final message =
          widget.controller.errorMessage ?? tr('Failed to create the account.');
      if (_isDuplicateEmailError(message)) {
        _showDuplicateEmailMessage();
        return;
      }
      _showErrorMessage(message);
    }
  }

  Future<void> _handleCompletePasswordRecovery() async {
    if (!_resetPasswordFormKey.currentState!.validate()) {
      return;
    }

    try {
      final message = await widget.controller.completePasswordRecovery(
        password: _newPasswordController.text,
        confirmPassword: _confirmNewPasswordController.text,
      );
      _showMessage(message);
    } catch (_) {
      _showErrorMessage(
        widget.controller.errorMessage ?? tr('Failed to update the password.'),
      );
    }
  }

  Future<void> _handleSignOut() async {
    try {
      await widget.controller.signOut();
    } catch (_) {
      _showErrorMessage(widget.controller.errorMessage ?? tr('Sign out'));
    }
  }

  Future<void> _openResetPasswordDialog() async {
    final initialEmail = _tabController.index == 0
        ? _signInEmailController.text.trim()
        : _signUpEmailController.text.trim();
    if (initialEmail.isNotEmpty) {
      _recoveryEmailController.text = initialEmail;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr('Reset password')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'Enter your work email. We will send a message with a link to change your password.',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _recoveryEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: tr('Work email')),
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
                final navigator = Navigator.of(context);
                try {
                  final message = await widget.controller.sendPasswordReset(
                    email: _recoveryEmailController.text,
                  );
                  if (!mounted) {
                    return;
                  }
                  navigator.pop();
                  _showMessage(message);
                } catch (_) {
                  _showErrorMessage(
                    widget.controller.errorMessage ??
                        tr('Failed to send the password recovery email.'),
                  );
                }
              },
              child: Text(tr('Send email')),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showErrorMessage(String message) {
    logUserFacingError(message, source: 'auth.page');
    _showMessage(message);
  }

  bool _isDuplicateEmailError(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized ==
            tr(
              'An account with this email already exists. Try signing in or resetting the password.',
            ).toLowerCase() ||
        normalized.contains('email already exists') ||
        normalized.contains('already registered') ||
        normalized.contains('already exists');
  }

  void _showDuplicateEmailMessage() {
    final message = tr(
      'An account with this email already exists. Go to sign in or reset the password.',
    );
    logUserFacingError(message, source: 'auth.page.duplicate_email');
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: tr('Sign in'),
            onPressed: _switchToSignIn,
          ),
        ),
      );
  }

  void _switchToSignIn() {
    _tabController.animateTo(0);
    final email = _signUpEmailController.text.trim();
    if (email.isNotEmpty) {
      _signInEmailController.text = email;
    }
  }
}

class _BackgroundShell extends StatelessWidget {
  const _BackgroundShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071526), Color(0xFF0A1B31), Color(0xFF102744)],
        ),
      ),
      child: child,
    );
  }
}

class _AuthHelpShell extends StatelessWidget {
  const _AuthHelpShell({required this.child, required this.onHelp});

  final Widget child;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: IconButton.filledTonal(
                tooltip: tr('Screen guide'),
                onPressed: onHelp,
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthHelpDialog extends StatelessWidget {
  const _AuthHelpDialog();

  static const _supportEmail = 'hariton1500@gmail.com';

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
          Expanded(child: Text(tr('Authorization guide'))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AuthHelpSection(
                icon: Icons.login_rounded,
                title: tr('Sign in'),
                body: tr(
                  'Use the Sign in tab when your account already exists. Enter your work email and password, then press Sign in to open the company workspace.',
                ),
              ),
              _AuthHelpSection(
                icon: Icons.business_rounded,
                title: tr('Create company'),
                body: tr(
                  'Use the Sign up tab only for the first company account. Enter your name, position, company name, work email, and password. After registration, confirm email if required and sign in.',
                ),
              ),
              _AuthHelpSection(
                icon: Icons.mark_email_read_outlined,
                title: tr('Employee invite'),
                body: tr(
                  'If an administrator invited you, register or sign in with the exact email address from the invite. The workspace membership is attached automatically.',
                ),
              ),
              _AuthHelpSection(
                icon: Icons.lock_reset_rounded,
                title: tr('Reset password'),
                body: tr(
                  'Use Reset password when you cannot sign in. Enter your work email, open the recovery link from email, set a new password twice, and sign in again.',
                ),
              ),
              _AuthHelpSection(
                icon: Icons.support_agent_rounded,
                title: tr('Support'),
                body: tr(
                  'If sign-in, registration, invite, or password recovery does not work, contact support: {email}',
                  {'email': _supportEmail},
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                _supportEmail,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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

class _AuthHelpSection extends StatelessWidget {
  const _AuthHelpSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF0C1D33),
                borderRadius: BorderRadius.circular(22),
              ),
              clipBehavior: Clip.antiAlias,
              child: const _BrandBadge(),
            ),
            const SizedBox(height: 24),
            Text(
              tr('Infrastructure management for companies and their teams'),
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Text(
              tr(
                'Access the company workspace, create the first organization, and prepare employee access on one shared platform.',
              ),
            ),
            SizedBox(height: isCompact ? 24 : 40),
            _FeatureTile(
              title: tr('One account per company'),
              description: tr(
                'The owner creates the workspace and then adds employees.',
              ),
            ),
            const SizedBox(height: 14),
            _FeatureTile(
              title: tr('Supabase sessions'),
              description: tr(
                'The app automatically restores the active user session.',
              ),
            ),
            const SizedBox(height: 14),
            _FeatureTile(
              title: tr('Ready for multi-tenant'),
              description: tr(
                'Profiles, companies, and employee roles are already isolated at the database level.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1D33),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E466A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(description),
        ],
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BrandBadgePainter());
  }
}

class _BrandBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final framePaint = Paint()
      ..color = const Color(0xFF173E61)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final teal = const Color(0xFF1EDDC5);
    final green = const Color(0xFF35C886);
    final white = const Color(0xFFF2F7FA);
    final muted = const Color(0xFF50749A);

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(22),
    );
    canvas.drawRRect(rect, framePaint);

    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width * 0.26;

    final top = Offset(cx, cy - radius);
    final topRight = Offset(cx + radius * 0.86, cy - radius * 0.5);
    final bottomRight = Offset(cx + radius * 0.86, cy + radius * 0.5);
    final bottom = Offset(cx, cy + radius);
    final bottomLeft = Offset(cx - radius * 0.86, cy + radius * 0.5);
    final topLeft = Offset(cx - radius * 0.86, cy - radius * 0.5);
    final center = Offset(cx, cy);

    void drawLine(Offset a, Offset b, Color color, double width) {
      linePaint
        ..color = color
        ..strokeWidth = width;
      canvas.drawLine(a, b, linePaint);
    }

    void drawNode(Offset point, double r, Color color) {
      canvas.drawCircle(point, r, Paint()..color = color);
    }

    drawLine(topLeft, top, white, 4.8);
    drawLine(top, topRight, white, 4.8);
    drawLine(topRight, bottomRight, green, 4.2);
    drawLine(bottomRight, bottom, green, 4.2);
    drawLine(bottom, bottomLeft, green, 4.2);
    drawLine(bottomLeft, topLeft, green, 4.2);

    drawLine(center, top, muted, 3.6);
    drawLine(center, bottom, muted, 3.6);
    drawLine(center, topRight, teal, 3.2);
    drawLine(center, topLeft, teal, 3.2);
    drawLine(center, bottomLeft, const Color(0xFF294E72), 3.2);
    drawLine(center, bottomRight, const Color(0xFF294E72), 3.2);

    drawNode(top, 4.2, white);
    drawNode(topRight, 4.0, const Color(0xFFA6F6E8));
    drawNode(bottomRight, 4.0, green);
    drawNode(bottom, 4.0, green);
    drawNode(bottomLeft, 4.0, green);
    drawNode(topLeft, 4.0, green);
    drawNode(center, 5.2, green);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SignInForm extends StatelessWidget {
  const _SignInForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.controller,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final AuthController controller;
  final Future<void> Function() onSubmit;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Employee sign in'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'Use your work email and password to open the company workspace.',
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: tr('Work email')),
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('Password')),
            validator: _validatePassword,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: controller.isBusy ? null : onForgotPassword,
              child: Text(tr('Reset password')),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: controller.isBusy ? null : onSubmit,
            child: controller.isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr('Sign in')),
          ),
        ],
      ),
    );
  }
}

class _SignUpForm extends StatelessWidget {
  const _SignUpForm({
    required this.formKey,
    required this.fullNameController,
    required this.selectedPosition,
    required this.onPositionChanged,
    required this.companyController,
    required this.emailController,
    required this.passwordController,
    required this.controller,
    required this.onSubmit,
    required this.onGoToSignIn,
    required this.onForgotPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController fullNameController;
  final String selectedPosition;
  final ValueChanged<String> onPositionChanged;
  final TextEditingController companyController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final AuthController controller;
  final Future<void> Function() onSubmit;
  final VoidCallback onGoToSignIn;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Company owner registration'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'Create the first company account. After that, you can add employees.',
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: fullNameController,
            decoration: InputDecoration(labelText: tr('Your name')),
            validator: _validateRequired,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: selectedPosition,
            decoration: InputDecoration(labelText: tr('Position')),
            items: employeePositions
                .map(
                  (position) => DropdownMenuItem<String>(
                    value: position,
                    child: Text(employeePositionLabel(position)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) {
                onPositionChanged(value);
              }
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: companyController,
            decoration: InputDecoration(labelText: tr('Company name')),
            validator: _validateRequired,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: tr('Work email')),
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('Password')),
            validator: _validatePassword,
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: controller.isBusy ? null : onGoToSignIn,
                child: Text(tr('Go to sign in')),
              ),
              TextButton(
                onPressed: controller.isBusy ? null : onForgotPassword,
                child: Text(tr('Reset password')),
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: controller.isBusy ? null : onSubmit,
            child: controller.isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr('Create company')),
          ),
        ],
      ),
    );
  }
}

class _ResetPasswordForm extends StatelessWidget {
  const _ResetPasswordForm({
    required this.formKey,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.controller,
    required this.onSubmit,
    required this.onSignOut,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final AuthController controller;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Set a new password'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'We confirmed the recovery link. You can now set a new password for the account.',
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('New password')),
            validator: _validatePassword,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: confirmPasswordController,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('Repeat new password')),
            validator: (value) {
              final baseValidation = _validatePassword(value);
              if (baseValidation != null) {
                return baseValidation;
              }
              if ((value ?? '') != passwordController.text) {
                return tr('Passwords do not match.');
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: controller.isBusy ? null : onSubmit,
            child: controller.isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr('Save new password')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: controller.isBusy ? null : onSignOut,
            child: Text(tr('Leave recovery mode')),
          ),
        ],
      ),
    );
  }
}

String? _validateRequired(String? value) {
  if (value == null || value.trim().isEmpty) {
    return tr('This field is required.');
  }

  return null;
}

String? _validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) {
    return tr('Enter an email address.');
  }

  if (!value.contains('@')) {
    return tr('Enter a valid email address.');
  }

  return null;
}

String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return tr('Enter a password.');
  }

  if (value.length < 8) {
    return tr('Minimum 8 characters.');
  }

  return null;
}
