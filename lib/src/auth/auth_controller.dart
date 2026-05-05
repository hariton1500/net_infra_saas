import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_i18n.dart';
import '../core/app_logger.dart';
import '../core/employee_positions.dart';

enum AuthView {
  loading,
  signedOut,
  passwordRecovery,
  needsCompanySetup,
  ready,
  error,
}

class ProfileData {
  const ProfileData({
    required this.id,
    required this.email,
    required this.fullName,
    required this.position,
  });

  final String id;
  final String email;
  final String fullName;
  final String position;
}

class CompanyMembershipData {
  const CompanyMembershipData({
    required this.companyId,
    required this.companyName,
    required this.role,
    required this.slug,
  });

  final String companyId;
  final String companyName;
  final String role;
  final String slug;
}

class TeamMemberData {
  const TeamMemberData({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    required this.position,
  });

  final String userId;
  final String email;
  final String fullName;
  final String role;
  final String position;
}

class CompanyInviteData {
  const CompanyInviteData({
    required this.id,
    required this.email,
    required this.role,
    required this.position,
    required this.status,
    required this.token,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String role;
  final String position;
  final String status;
  final String token;
  final DateTime createdAt;
}

class AuthController extends ChangeNotifier {
  AuthController({required SupabaseClient client}) : _client = client;

  static const Duration _authRequestTimeout = Duration(seconds: 12);

  final SupabaseClient _client;

  StreamSubscription<AuthState>? _authSubscription;
  Future<void>? _refreshInFlight;
  bool _refreshQueued = false;

  AuthView _view = AuthView.loading;
  bool _isBusy = false;
  bool _isRecoveringPassword = false;
  String? _errorMessage;
  ProfileData? _profile;
  CompanyMembershipData? _membership;
  List<TeamMemberData> _teamMembers = const [];
  List<CompanyInviteData> _pendingInvites = const [];

  AuthView get view => _view;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  ProfileData? get profile => _profile;
  CompanyMembershipData? get membership => _membership;
  List<TeamMemberData> get teamMembers => _teamMembers;
  List<CompanyInviteData> get pendingInvites => _pendingInvites;
  User? get currentUser => _client.auth.currentUser;
  SupabaseClient get client => _client;
  bool get canAssignEmployeePosition => _membership?.role == 'owner';
  bool get canManageTeam {
    final role = _membership?.role;
    return role == 'owner' || role == 'admin';
  }

  String get suggestedCompanyName {
    final metadata = currentUser?.userMetadata;
    final value = metadata?['company_name'];

    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return '';
  }

  Future<void> initialize() async {
    _authSubscription = _client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) {
        _isRecoveringPassword = true;
        _errorMessage = null;
        _view = AuthView.passwordRecovery;
        notifyListeners();
        return;
      }
      unawaited(refresh());
    });

    await refresh();
  }

  Future<void> refresh() {
    _refreshQueued = true;

    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final operation = Future<void>.microtask(_refreshUntilSettled);
    _refreshInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> _refreshUntilSettled() async {
    while (_refreshQueued) {
      _refreshQueued = false;
      await _refreshSessionState();
    }
  }

  Future<void> _refreshSessionState() async {
    final user = currentUser;

    if (user == null) {
      _isRecoveringPassword = false;
      _profile = null;
      _membership = null;
      _teamMembers = const [];
      _pendingInvites = const [];
      _errorMessage = null;
      _view = AuthView.signedOut;
      notifyListeners();
      return;
    }

    _view = AuthView.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _syncProfileFromUser(user);
      await _acceptPendingInviteIfNeeded();
      _profile = await _fetchProfile(user);
      _membership = await _fetchMembership(user);
      await _loadCompanyDataForRefresh();
      if (currentUser?.id != user.id) {
        return;
      }
      if (_isRecoveringPassword) {
        _view = AuthView.passwordRecovery;
      } else {
        _view = _membership == null
            ? AuthView.needsCompanySetup
            : AuthView.ready;
      }
    } catch (error, stackTrace) {
      if (currentUser?.id != user.id) {
        return;
      }
      _errorMessage = _humanizeError(error);
      logUserFacingError(
        _errorMessage ?? tr('Failed to load session.'),
        source: 'auth.refresh',
        error: error,
        stackTrace: stackTrace,
      );
      _view = AuthView.error;
    }

    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    await _runBusy(() async {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      await refresh();
    });
  }

  Future<String> signUp({
    required String fullName,
    required String position,
    required String companyName,
    required String email,
    required String password,
  }) async {
    return _runBusy(() async {
      final normalizedPosition = _assertValidPosition(position);
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: _authRedirectUrl(),
        data: {
          'full_name': fullName.trim(),
          'company_name': companyName.trim(),
          'locale': AppI18n.instance.locale.languageCode,
          'locale_name': AppI18n.instance.localeName,
        },
      );

      if (response.user == null) {
        throw const AuthException('Supabase did not create a user.');
      }

      if (response.session == null) {
        _view = AuthView.signedOut;
        notifyListeners();
        return tr(
          'The account has been created. Confirm your email and then sign in.',
        );
      }

      await _client.from('profiles').upsert({
        'id': response.user!.id,
        'email': response.user!.email,
        'full_name': fullName.trim(),
        'position': normalizedPosition,
      });
      await refresh();

      if (_membership == null) {
        await _createCompany(companyName: companyName.trim());
      }

      return tr('The company has been created. You can continue working.');
    });
  }

  Future<String> completeCompanySetup({required String companyName}) {
    return _runBusy(() => _createCompany(companyName: companyName.trim()));
  }

  Future<void> signOut() async {
    await _runBusy(() async {
      await _client.auth.signOut();
      _isRecoveringPassword = false;
      _profile = null;
      _membership = null;
      _teamMembers = const [];
      _pendingInvites = const [];
      _view = AuthView.signedOut;
      notifyListeners();
    });
  }

  Future<String> inviteEmployee({
    required String email,
    required String role,
    required String position,
  }) async {
    return _runBusy(() async {
      final normalizedPosition = canAssignEmployeePosition
          ? normalizeEmployeePosition(position)
          : employeePositionEngineer;
      _assertValidPosition(normalizedPosition);
      final response = await _client.rpc(
        'create_company_invite',
        params: {
          'invited_email_input': email.trim(),
          'role_input': role,
          'position_input': normalizedPosition,
        },
      );

      await _loadCompanyData();
      notifyListeners();

      final invite = response as Map<String, dynamic>;
      final token = invite['token'] as String? ?? '';

      return token.isEmpty
          ? tr('Invite created.')
          : tr('Invite created. Invite code: {token}', {'token': token});
    });
  }

  Future<void> refreshCompanyData() async {
    await _runBusy(() async {
      await _loadCompanyData();
      notifyListeners();
    });
  }

  Future<void> updateProfile({
    required String fullName,
    required String position,
  }) async {
    await _runBusy(() async {
      final normalizedPosition = _assertValidPosition(position);
      final user = currentUser;
      if (user == null) {
        throw const AuthException('Authentication required');
      }

      final normalizedFullName = fullName.trim();
      final mergedMetadata = <String, dynamic>{
        ...?user.userMetadata,
        'full_name': normalizedFullName,
      };

      await _client.auth.updateUser(UserAttributes(data: mergedMetadata));
      await _client.from('profiles').upsert({
        'id': user.id,
        'email': user.email,
        'full_name': normalizedFullName,
        'position': normalizedPosition,
      });

      _profile = await _fetchProfile(user);
      await _loadCompanyData();
      notifyListeners();
    });
  }

  Future<void> _syncProfileFromUser(User user) async {
    final fullName = _readString(user.userMetadata, 'full_name');
    final profileData = <String, dynamic>{
      'id': user.id,
      'email': user.email,
      if (fullName.isNotEmpty) 'full_name': fullName,
    };

    await _runAuthRequest(() {
      return _client.from('profiles').upsert(profileData);
    });
  }

  Future<ProfileData> _fetchProfile(User user) async {
    final response = await _runAuthRequest(() {
      return _client
          .from('profiles')
          .select('id, email, full_name, position')
          .eq('id', user.id)
          .maybeSingle();
    });

    if (response == null) {
      return ProfileData(
        id: user.id,
        email: user.email ?? '',
        fullName: _readString(user.userMetadata, 'full_name'),
        position: employeePositionEngineer,
      );
    }

    final data = response;

    return ProfileData(
      id: data['id'] as String,
      email: (data['email'] as String?) ?? (user.email ?? ''),
      fullName: (data['full_name'] as String?) ?? '',
      position: (data['position'] as String?) ?? '',
    );
  }

  Future<CompanyMembershipData?> _fetchMembership(User user) async {
    final membershipResponse = await _runAuthRequest(() {
      return _client
          .from('company_members')
          .select('company_id, role')
          .eq('user_id', user.id)
          .maybeSingle();
    });

    if (membershipResponse == null) {
      return null;
    }

    final companyId = membershipResponse['company_id'] as String;

    final companyResponse = await _runAuthRequest(() {
      return _client
          .from('companies')
          .select('id, name, slug')
          .eq('id', companyId)
          .single();
    });

    return CompanyMembershipData(
      companyId: companyId,
      companyName: companyResponse['name'] as String,
      role: membershipResponse['role'] as String,
      slug: (companyResponse['slug'] as String?) ?? '',
    );
  }

  Future<void> _loadCompanyData() async {
    final membership = _membership;

    if (membership == null) {
      _teamMembers = const [];
      _pendingInvites = const [];
      return;
    }

    final membersResponse = await _runAuthRequest(() {
      return _client
          .from('company_members')
          .select('user_id, role')
          .eq('company_id', membership.companyId)
          .order('created_at');
    });

    final memberRows = (membersResponse as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final userIds = memberRows
        .map((row) => row['user_id'] as String)
        .toList(growable: false);

    Map<String, Map<String, dynamic>> profilesById = const {};

    if (userIds.isNotEmpty) {
      final profilesResponse = await _runAuthRequest(() {
        return _client
            .from('profiles')
            .select('id, email, full_name, position')
            .inFilter('id', userIds);
      });

      profilesById = {
        for (final entry
            in (profilesResponse as List<dynamic>).cast<Map<String, dynamic>>())
          entry['id'] as String: entry,
      };
    }

    _teamMembers = memberRows
        .map((row) {
          final userId = row['user_id'] as String;
          final profile = profilesById[userId] ?? const <String, dynamic>{};

          return TeamMemberData(
            userId: userId,
            email: (profile['email'] as String?) ?? '',
            fullName: (profile['full_name'] as String?) ?? '',
            role: row['role'] as String,
            position: (profile['position'] as String?) ?? '',
          );
        })
        .toList(growable: false);

    final invitesResponse = await _runAuthRequest(() {
      return _client
          .from('company_invites')
          .select(
            'id, invited_email, role, position, status, token, created_at',
          )
          .eq('company_id', membership.companyId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
    });

    _pendingInvites = (invitesResponse as List<dynamic>)
        .map((entry) {
          final row = entry as Map<String, dynamic>;

          return CompanyInviteData(
            id: row['id'] as String,
            email: row['invited_email'] as String,
            role: row['role'] as String,
            position: (row['position'] as String?) ?? '',
            status: row['status'] as String,
            token: row['token'] as String,
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          );
        })
        .toList(growable: false);
  }

  Future<void> _loadCompanyDataForRefresh() async {
    try {
      await _loadCompanyData();
    } catch (error, stackTrace) {
      if (!_isTransientAuthNetworkError(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }

      debugPrint(
        '[WARN][auth.companyData] ${normalizeErrorText(error, fallback: 'Failed to refresh company data.')}',
      );
    }
  }

  Future<String> _createCompany({required String companyName}) async {
    if (companyName.isEmpty) {
      throw AuthException(tr('Please enter a company name.'));
    }

    await _client.rpc(
      'create_company_with_owner',
      params: {'company_name_input': companyName},
    );

    await refresh();
    return tr('The company is connected and the account is ready.');
  }

  Future<void> _acceptPendingInviteIfNeeded() async {
    if (_membership != null) {
      return;
    }

    await _runAuthRequest(() => _client.rpc('accept_company_invite'));
  }

  String _readString(Map<String, dynamic>? source, String key) {
    final value = source?[key];
    if (value is String) {
      return value.trim();
    }

    return '';
  }

  String _humanizeError(Object error) {
    final authMessage = error is AuthException
        ? error.message.trim().toLowerCase()
        : '';
    if (authMessage.isNotEmpty) {
      if (authMessage.contains('user already registered') ||
          authMessage.contains('already registered') ||
          authMessage.contains('already exists')) {
        return tr(
          'An account with this email already exists. Try signing in or resetting the password.',
        );
      }
      return error is AuthException ? error.message : authMessage;
    }

    if (error is PostgrestException && error.message.isNotEmpty) {
      return normalizeErrorText(error.message);
    }

    return normalizeErrorText(error, fallback: tr('Failed to load session.'));
  }

  Future<T> _runAuthRequest<T>(
    Future<T> Function() action, {
    int attempts = 3,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await action().timeout(_authRequestTimeout);
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;

        final canRetry =
            attempt < attempts - 1 && _isTransientAuthNetworkError(error);
        if (!canRetry) {
          Error.throwWithStackTrace(error, stackTrace);
        }

        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  bool _isTransientAuthNetworkError(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }

    final text = error.toString().toLowerCase();
    return text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.runes.any((codeUnit) => codeUnit >= 0x0400 && codeUnit <= 0x04FF);
  }

  String _assertValidPosition(String position) {
    final normalizedPosition = supportedEmployeePositionOrNull(position);
    if (normalizedPosition == null) {
      throw const AuthException('Unsupported position');
    }
    return normalizedPosition;
  }

  Future<T> _runBusy<T>(Future<T> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await action();
    } catch (error, stackTrace) {
      _errorMessage = _humanizeError(error);
      logUserFacingError(
        _errorMessage ?? tr('Something went wrong.'),
        source: 'auth.runBusy',
        error: error,
        stackTrace: stackTrace,
      );
      notifyListeners();
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<String> sendPasswordReset({required String email}) async {
    return _runBusy(() async {
      final normalizedEmail = email.trim();
      if (normalizedEmail.isEmpty) {
        throw AuthException(
          tr('Enter the email address for password recovery.'),
        );
      }

      final redirectTo = _passwordRecoveryRedirectUrl();
      await _client.auth.resetPasswordForEmail(
        normalizedEmail,
        redirectTo: redirectTo,
      );
      return tr(
        'We sent a password recovery email if an account with this address exists.',
      );
    });
  }

  Future<String> completePasswordRecovery({
    required String password,
    required String confirmPassword,
  }) async {
    return _runBusy(() async {
      final normalizedPassword = password.trim();
      final normalizedConfirmPassword = confirmPassword.trim();

      if (normalizedPassword.isEmpty) {
        throw AuthException(tr('Enter a new password.'));
      }
      if (normalizedPassword.length < 8) {
        throw AuthException(tr('Minimum 8 characters.'));
      }
      if (normalizedPassword != normalizedConfirmPassword) {
        throw AuthException(tr('Passwords do not match.'));
      }

      await _client.auth.updateUser(
        UserAttributes(password: normalizedPassword),
      );
      _isRecoveringPassword = false;
      await refresh();
      return tr('Password updated.');
    });
  }

  String? _passwordRecoveryRedirectUrl() {
    return _authRedirectUrl();
  }

  String? _authRedirectUrl() {
    final base = Uri.base;
    if (!base.hasAuthority) {
      return null;
    }
    return base.replace(path: '/', query: '', fragment: '').toString();
  }
}
