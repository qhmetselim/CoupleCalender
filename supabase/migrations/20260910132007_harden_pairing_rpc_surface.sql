-- Keep the exposed RPC names narrow while leaving privilege escalation in the
-- private helpers. Invoker wrappers do not bypass RLS or appear as exposed
-- SECURITY DEFINER functions in the security advisor.
create or replace function public.create_partner_invite()
returns table (invite_id uuid, invite_code text, expires_at timestamptz)
language sql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$ select * from private.create_partner_invite(); $$;

create or replace function public.accept_partner_invite(input_code text)
returns table (couple_id uuid, partner_id uuid)
language sql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$ select * from private.accept_partner_invite(input_code); $$;

create or replace function public.get_pairing_status()
returns table (status text, couple_id uuid, partner_id uuid, pending_invite_expires_at timestamptz)
language sql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$ select * from private.get_pairing_status(); $$;

create or replace function public.cancel_partner_invite()
returns boolean
language sql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$ select private.cancel_partner_invite(); $$;

-- The private schema is not part of the Data API exposed schema list. These
-- grants let the invoker wrappers call the helpers without exposing the table
-- or granting anon access.
grant usage on schema private to authenticated;
grant execute on function private.create_partner_invite() to authenticated;
grant execute on function private.accept_partner_invite(text) to authenticated;
grant execute on function private.get_pairing_status() to authenticated;
grant execute on function private.cancel_partner_invite() to authenticated;
