import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:net_infra_saas/src/core/company_module_sync_repository.dart';
import 'package:net_infra_saas/src/core/project_scope.dart';

void main() {
  SupabaseClient testClient() =>
      SupabaseClient('https://example.supabase.co', 'anon-key');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('local module caches are isolated by company id', () async {
    final companyA = CompanyModuleSyncRepository(
      client: testClient(),
      companyId: 'company-a',
    );
    final companyB = CompanyModuleSyncRepository(
      client: testClient(),
      companyId: 'company-b',
    );

    await companyA.writeCache('records.v1', [
      {'id': 1, 'name': 'A record', 'updated_at': DateTime(2026)},
    ]);

    expect(await companyB.readCache('records.v1'), isEmpty);
    expect(await companyA.readCache('records.v1'), hasLength(1));
  });

  test('active project selection is isolated by company id', () async {
    final companyA = CompanyModuleSyncRepository(
      client: testClient(),
      companyId: 'company-a',
    );
    final companyB = CompanyModuleSyncRepository(
      client: testClient(),
      companyId: 'company-b',
    );

    await companyA.writeActiveProject(
      const ProjectSelection(id: 7, name: 'Company A task'),
    );

    expect(await companyB.readActiveProject(), isNull);
    expect((await companyA.readActiveProject())?.id, 7);
  });
}
