drop policy if exists "Members can read company memberships" on public.company_members;

create policy "Users can read own company membership"
on public.company_members
for select
to authenticated
using (user_id = auth.uid());
