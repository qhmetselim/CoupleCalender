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
    where private.partner_invites.couple_id = target_couple_id
      and private.partner_invites.consumed_at is null
      and private.partner_invites.revoked_at is null;

    loop
        code := private.generate_partner_invite_code();
        generated_code_hash := private.hash_partner_invite_code(code);
        exit when not exists (
            select 1
            from private.partner_invites pi
            where pi.code_hash = generated_code_hash
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

    if not exists (select 1 from public.profiles p where p.id = caller_id) then
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
    where public.couples.id = invite.couple_id;

    begin
        insert into public.couple_members (couple_id, user_id)
        values (invite.couple_id, caller_id);
    exception when unique_violation then
        raise exception using errcode = 'P0001', message = 'already_paired';
    end;

    update private.partner_invites
    set consumed_at = timezone('utc', now()),
        consumed_by = caller_id
    where private.partner_invites.id = invite.id;

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
