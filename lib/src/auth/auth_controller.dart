import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_logger.dart';

enum AuthView { loading, signedOut, needsCompanySetup, ready, error }

class ProfileData {
  const ProfileData({
    required this.id,
    required this.email,
    required this.fullName,
  });

  final String id;
  final String email;
  final String fullName;
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
  });

  final String userId;
  final String email;
  final String fullName;
  final String role;
}

class CompanyInviteData {
  const CompanyInviteData({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    required this.token,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String role;
  final String status;
  final String token;
  final DateTime createdAt;
}

class AuthController extends ChangeNotifier {
  AuthController({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  StreamSubscription<AuthState>? _authSubscription;

  AuthView _view = AuthView.loading;
  bool _isBusy = false;
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
      unawaited(refresh());
    });

    await refresh();
  }

  Future<void> refresh() async {
    final user = currentUser;

    if (user == null) {
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
      await _loadCompanyData();
      _view = _membership == null ? AuthView.needsCompanySetup : AuthView.ready;
    } catch (error, stackTrace) {
      _errorMessage = _humanizeError(error);
      logUserFacingError(
        _errorMessage ?? 'Не удалось загрузить сессию.',
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
    required String companyName,
    required String email,
    required String password,
  }) async {
    return _runBusy(() async {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'company_name': companyName.trim(),
        },
      );

      if (response.user == null) {
        throw const AuthException('Supabase did not create a user.');
      }

      if (response.session == null) {
        _view = AuthView.signedOut;
        notifyListeners();
        return 'Аккаунт создан. Подтвердите email и затем войдите в систему.';
      }

      await refresh();

      if (_membership == null) {
        await _createCompany(companyName: companyName.trim());
      }

      return 'Компания создана, можно продолжать работу.';
    });
  }

  Future<String> completeCompanySetup({required String companyName}) {
    return _runBusy(() => _createCompany(companyName: companyName.trim()));
  }

  Future<void> signOut() async {
    await _runBusy(() async {
      await _client.auth.signOut();
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
  }) async {
    return _runBusy(() async {
      final response = await _client.rpc(
        'create_company_invite',
        params: {'invited_email_input': email.trim(), 'role_input': role},
      );

      await _loadCompanyData();
      notifyListeners();

      final invite = response as Map<String, dynamic>;
      final token = invite['token'] as String? ?? '';

      return token.isEmpty
          ? 'Приглашение создано.'
          : 'Приглашение создано. Код приглашения: $token';
    });
  }

  Future<void> refreshCompanyData() async {
    await _runBusy(() async {
      await _loadCompanyData();
      notifyListeners();
    });
  }

  Future<void> _syncProfileFromUser(User user) async {
    final fullName = _readString(user.userMetadata, 'full_name');

    await _client.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      if (fullName.isNotEmpty) 'full_name': fullName,
    });
  }

  Future<ProfileData> _fetchProfile(User user) async {
    final response = await _client
        .from('profiles')
        .select('id, email, full_name')
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) {
      return ProfileData(
        id: user.id,
        email: user.email ?? '',
        fullName: _readString(user.userMetadata, 'full_name'),
      );
    }

    final data = response;

    return ProfileData(
      id: data['id'] as String,
      email: (data['email'] as String?) ?? (user.email ?? ''),
      fullName: (data['full_name'] as String?) ?? '',
    );
  }

  Future<CompanyMembershipData?> _fetchMembership(User user) async {
    final membershipResponse = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .maybeSingle();

    if (membershipResponse == null) {
      return null;
    }

    final companyId = membershipResponse['company_id'] as String;

    final companyResponse = await _client
        .from('companies')
        .select('id, name, slug')
        .eq('id', companyId)
        .single();

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

    final membersResponse = await _client
        .from('company_members')
        .select('user_id, role')
        .eq('company_id', membership.companyId)
        .order('created_at');

    final memberRows = (membersResponse as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final userIds = memberRows
        .map((row) => row['user_id'] as String)
        .toList(growable: false);

    Map<String, Map<String, dynamic>> profilesById = const {};

    if (userIds.isNotEmpty) {
      final profilesResponse = await _client
          .from('profiles')
          .select('id, email, full_name')
          .inFilter('id', userIds);

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
          );
        })
        .toList(growable: false);

    final invitesResponse = await _client
        .from('company_invites')
        .select('id, invited_email, role, status, token, created_at')
        .eq('company_id', membership.companyId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    _pendingInvites = (invitesResponse as List<dynamic>)
        .map((entry) {
          final row = entry as Map<String, dynamic>;

          return CompanyInviteData(
            id: row['id'] as String,
            email: row['invited_email'] as String,
            role: row['role'] as String,
            status: row['status'] as String,
            token: row['token'] as String,
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          );
        })
        .toList(growable: false);
  }

  Future<String> _createCompany({required String companyName}) async {
    if (companyName.isEmpty) {
      throw const AuthException('Укажите название компании.');
    }

    await _client.rpc(
      'create_company_with_owner',
      params: {'company_name_input': companyName},
    );

    await refresh();
    return 'Компания подключена, учётная запись готова.';
  }

  Future<void> _acceptPendingInviteIfNeeded() async {
    if (_membership != null) {
      return;
    }

    await _client.rpc('accept_company_invite');
  }

  String _readString(Map<String, dynamic>? source, String key) {
    final value = source?[key];
    if (value is String) {
      return value.trim();
    }

    return '';
  }

  String _humanizeError(Object error) {
    if (error is AuthException && error.message.isNotEmpty) {
      return error.message;
    }

    if (error is PostgrestException && error.message.isNotEmpty) {
      return error.message;
    }

    return error.toString();
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
        _errorMessage ?? 'Произошла ошибка.',
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
}
