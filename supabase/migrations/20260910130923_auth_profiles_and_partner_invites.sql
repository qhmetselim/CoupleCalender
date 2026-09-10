-- Prompt 2: email/password auth support, profile requirements, and secure pairing invites.
-- Invite plaintext is returned only to the authenticated caller that creates it.
-- The database stores only a SHA-256 hash and never exposes the private table.

create table private.partner_invites (
    id uuid primary key default extensions.gen_random_uuid(),
    couple_id uuid not null references public.couples(id) on delete cascade,
    inviter_id uuid not null references public.profiles(id) on delete cascade,
    code_hash text not null unique,
    expires_at timestamptz(3) not null,
    consumed_at timestamptz(3),
    consumed_by uuid references public.profiles(id) on delete set null,
    revoked_at timestamptz(3),
    created_at timestamptz(3) not null default timezone('utc', now()),
    constraint partner_invites_expiry_after_creation check (expires_at > created_at),
    constraint partner_invites_consumed_together check (
        (consumed_at is null and consumed_by is null)
        or (consumed_at is not null and consumed_by is not null)
    )
);

create index partner_invites_by_couple
    on private.partner_invites (couple_id, expires_at desc)
    where consumed_at is null and revoked_at is null;

create or replace function private.generate_partner_invite_code()
returns text
language plpgsql
set search_path = pg_catalog, private, extensions
as $$
declare
    alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    bytes bytea := extensions.gen_random_bytes(10);
    code text := '';
begin
    for byte_index in 0..9 loop
        code := code || substr(alphabet, (get_byte(bytes, byte_index) % 32) + 1, 1);
    end loop;
    return code;
end;
$$;

create or replace function private.hash_partner_invite_code(code text)
returns text
language sql
immutable
strict
set search_path = pg_catalog, extensions
as $$
    select encode(extensions.digest(code, 'sha256'::text), 'hex');
$$;

create or replace function private.create_partner_invite()
returns table (
    invite_id uuid,
    invite_code text,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
    caller_id uuid;
    target_couple_id uuid;
    existing_status text;
    existing_member_a_id uuid;
    existing_member_b_id uuid;
    code text;
    generated_code_hash text;
    expiry timestamptz := timezone('utc', now()) + interval '24 hours';
begin
    select auth.uid() into caller_id;
    if caller_id is null then
        raise exception using errcode = 'P0001', message = 'not_authenticated';
    end if;

    if not exists (
        select 1
        from public.profiles p
        where p.id = caller_id
          and p.display_name is not null
          and char_length(trim(p.display_name)) between 1 and 80
    ) then
        raise exception using errcode = 'P0001', message = 'profile_required';
    end if;

    select c.id, c.status, c.member_a_id, c.member_b_id
    into target_couple_id, existing_status, existing_member_a_id, existing_member_b_id
    from public.couple_members cm
    join public.couples c on c.id = cm.couple_id
    where cm.user_id = caller_id
      and cm.left_at is null
    for update;

    if target_couple_id is not null then
        if existing_status = 'active' then
            raise exception using errcode = 'P0001', message = 'already_paired';
        end if;

        if existing_status <> 'pending'
            or existing_member_a_id <> caller_id
            or existing_member_b_id is not null then
            raise exception using errcode = 'P0001', message = 'pairing_unavailable';
        end if;
    else
        begin
            insert into public.couples (member_a_id, status)
            values (caller_id, 'pending')
            returning id into target_couple_id;

            insert into public.couple_members (couple_id, user_id)
            values (target_couple_id, caller_id);
        exception when unique_violation then
            select c.id, c.status, c.member_a_id, c.member_b_id
            into target_couple_id, existing_status, existing_member_a_id, existing_member_b_id
            from public.couple_members cm
            join public.couples c on c.id = cm.couple_id
            where cm.user_id = caller_id
              and cm.left_at is null
            for update;

            if target_couple_id is null
                or existing_status <> 'pending'
                or existing_member_a_id <> caller_id
                or existing_member_b_id is not null then
                raise exception using errcode = 'P0001', message = 'pairing_unavailable';
            end if;
        end;
    end if;

    update private.partner_invites
    set revoked_at = timezone('utc', now())
    where couple_id = target_couple_id
      and consumed_at is null
      and revoked_at is null;

    loop
        code := private.generate_partner_invite_code();
        generated_code_hash := private.hash_partner_invite_code(code);
        exit when not exists (
            select 1 from private.partner_invites pi where pi.code_hash = generated_code_hash
        );
    end loop;

    insert into private.partner_invites (
        couple_id,
        inviter_id,
        code_hash,
        expires_at
    ) values (
        target_couple_id,
        caller_id,
        generated_code_hash,
        expiry
    )
    returning id, expires_at into invite_id, expires_at;

    invite_code := code;
    return next;
end;
$$;

create or replace function private.accept_partner_invite(input_code text)
returns table (
    couple_id uuid,
    partner_id uuid
)
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
    caller_id uuid;
    normalized_code text;
    hashed_code text;
    invite private.partner_invites%rowtype;
    couple public.couples%rowtype;
    caller_membership public.couple_members%rowtype;
begin
    select auth.uid() into caller_id;
    if caller_id is null then
        raise exception using errcode = 'P0001', message = 'not_authenticated';
    end if;

    normalized_code := upper(trim(coalesce(input_code, '')));
    if normalized_code = '' or char_length(normalized_code) > 32 then
        raise exception using errcode = 'P0001', message = 'invite_not_found';
    end if;
    hashed_code := private.hash_partner_invite_code(normalized_code);

    select * into invite
    from private.partner_invites pi
    where pi.code_hash = hashed_code
    for update;

    if not found then
        raise exception using errcode = 'P0001', message = 'invite_not_found';
    end if;
    if invite.consumed_at is not null then
        raise exception using errcode = 'P0001', message = 'invite_already_used';
    end if;
    if invite.revoked_at is not null then
        raise exception using errcode = 'P0001', message = 'invite_not_found';
    end if;
    if invite.expires_at <= timezone('utc', now()) then
        raise exception using errcode = 'P0001', message = 'invite_expired';
    end if;
    if invite.inviter_id = caller_id then
        raise exception using errcode = 'P0001', message = 'cannot_join_self';
    end if;

    if not exists (
        select 1 from public.profiles p where p.id = caller_id
    ) then
        raise exception using errcode = 'P0001', message = 'profile_required';
    end if;

    select * into couple
    from public.couples c
    where c.id = invite.couple_id
    for update;

    if not found
        or couple.status <> 'pending'
        or couple.member_a_id <> invite.inviter_id
        or couple.member_b_id is not null then
        raise exception using errcode = 'P0001', message = 'partner_unavailable';
    end if;

    select cm.* into caller_membership
    from public.couple_members cm
    where cm.user_id = caller_id
      and cm.left_at is null
    for update;

    if found then
        if caller_membership.couple_id = invite.couple_id then
            raise exception using errcode = 'P0001', message = 'invite_already_used';
        end if;
        raise exception using errcode = 'P0001', message = 'already_paired';
    end if;

    if not exists (
        select 1
        from public.couple_members cm
        where cm.couple_id = invite.couple_id
          and cm.user_id = invite.inviter_id
          and cm.left_at is null
    ) then
        raise exception using errcode = 'P0001', message = 'partner_unavailable';
    end if;

    update public.couples
    set member_b_id = caller_id,
        status = 'active'
    where id = invite.couple_id;

    begin
        insert into public.couple_members (couple_id, user_id)
        values (invite.couple_id, caller_id);
    exception when unique_violation then
        raise exception using errcode = 'P0001', message = 'already_paired';
    end;

    update private.partner_invites
    set consumed_at = timezone('utc', now()),
        consumed_by = caller_id
    where id = invite.id;

    update private.partner_invites
    set revoked_at = timezone('utc', now())
    where private.partner_invites.couple_id = invite.couple_id
      and private.partner_invites.id <> invite.id
      and private.partner_invites.consumed_at is null
      and private.partner_invites.revoked_at is null;

    couple_id := invite.couple_id;
    partner_id := invite.inviter_id;
    return next;
end;
$$;

create or replace function private.get_pairing_status()
returns table (
    status text,
    couple_id uuid,
    partner_id uuid,
    pending_invite_expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
    caller_id uuid;
    member public.couple_members%rowtype;
    couple public.couples%rowtype;
begin
    select auth.uid() into caller_id;
    if caller_id is null then
        raise exception using errcode = 'P0001', message = 'not_authenticated';
    end if;

    select cm.* into member
    from public.couple_members cm
    where cm.user_id = caller_id
      and cm.left_at is null;

    if not found then
        status := 'unpaired';
        return next;
        return;
    end if;

    select * into couple from public.couples c where c.id = member.couple_id;
    if not found or couple.status = 'ended' then
        status := 'unpaired';
        return next;
        return;
    end if;

    couple_id := couple.id;
    if couple.status = 'active' then
        status := 'paired';
        if couple.member_a_id = caller_id then
            partner_id := couple.member_b_id;
        else
            partner_id := couple.member_a_id;
        end if;
        return next;
        return;
    end if;

    status := 'pending';
    select max(pi.expires_at)
    into pending_invite_expires_at
    from private.partner_invites pi
    where pi.couple_id = couple.id
      and pi.inviter_id = caller_id
      and pi.consumed_at is null
      and pi.revoked_at is null;
    return next;
end;
$$;

create or replace function private.cancel_partner_invite()
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
    caller_id uuid;
    target_couple_id uuid;
begin
    select auth.uid() into caller_id;
    if caller_id is null then
        raise exception using errcode = 'P0001', message = 'not_authenticated';
    end if;

    select c.id into target_couple_id
    from public.couples c
    join public.couple_members cm on cm.couple_id = c.id
    where c.member_a_id = caller_id
      and c.member_b_id is null
      and c.status = 'pending'
      and cm.user_id = caller_id
      and cm.left_at is null
    for update;

    if target_couple_id is null then
        raise exception using errcode = 'P0001', message = 'no_pending_invite';
    end if;

    update private.partner_invites
    set revoked_at = timezone('utc', now())
    where couple_id = target_couple_id
      and consumed_at is null
      and revoked_at is null;

    update public.couple_members
    set left_at = timezone('utc', now())
    where couple_id = target_couple_id
      and user_id = caller_id
      and left_at is null;

    update public.couples
    set status = 'ended'
    where id = target_couple_id;

    return true;
end;
$$;

-- Only these narrow RPC entry points are exposed through the Data API.
create or replace function public.create_partner_invite()
returns table (invite_id uuid, invite_code text, expires_at timestamptz)
language sql
security definer
set search_path = pg_catalog, public, private, extensions
as $$ select * from private.create_partner_invite(); $$;

create or replace function public.accept_partner_invite(input_code text)
returns table (couple_id uuid, partner_id uuid)
language sql
security definer
set search_path = pg_catalog, public, private, extensions
as $$ select * from private.accept_partner_invite(input_code); $$;

create or replace function public.get_pairing_status()
returns table (status text, couple_id uuid, partner_id uuid, pending_invite_expires_at timestamptz)
language sql
security definer
set search_path = pg_catalog, public, private, extensions
as $$ select * from private.get_pairing_status(); $$;

create or replace function public.cancel_partner_invite()
returns boolean
language sql
security definer
set search_path = pg_catalog, public, private, extensions
as $$ select private.cancel_partner_invite(); $$;

alter table private.partner_invites enable row level security;
revoke all on schema private from public;
revoke all on table private.partner_invites from public, anon, authenticated;

revoke all on function private.create_partner_invite() from public, anon, authenticated;
revoke all on function private.accept_partner_invite(text) from public, anon, authenticated;
revoke all on function private.get_pairing_status() from public, anon, authenticated;
revoke all on function private.cancel_partner_invite() from public, anon, authenticated;

revoke all on function public.create_partner_invite() from public, anon, authenticated;
revoke all on function public.accept_partner_invite(text) from public, anon, authenticated;
revoke all on function public.get_pairing_status() from public, anon, authenticated;
revoke all on function public.cancel_partner_invite() from public, anon, authenticated;

grant execute on function public.create_partner_invite() to authenticated;
grant execute on function public.accept_partner_invite(text) to authenticated;
grant execute on function public.get_pairing_status() to authenticated;
grant execute on function public.cancel_partner_invite() to authenticated;

alter table public.profiles
    add constraint profiles_display_name_required
    check (display_name is not null and char_length(trim(display_name)) between 1 and 80)
    not valid;

drop policy "Users can create their own profile" on public.profiles;
create policy "Users can create their own profile"
on public.profiles for insert
to authenticated
with check (
    id = (select auth.uid())
    and display_name is not null
    and char_length(trim(display_name)) between 1 and 80
);

drop policy "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
on public.profiles for update
to authenticated
using (id = (select auth.uid()))
with check (
    id = (select auth.uid())
    and display_name is not null
    and char_length(trim(display_name)) between 1 and 80
);
