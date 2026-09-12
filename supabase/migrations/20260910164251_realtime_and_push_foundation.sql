-- Prompt 6: couple-scoped Realtime Broadcast authorization, device-token
-- lifecycle helpers, and server-side memory notification delivery support.
-- No client or anon role is granted access to the notification delivery log.

create extension if not exists pg_net with schema extensions;

-- Realtime Authorization runs this helper while evaluating the requested
-- topic. It deliberately validates the topic before casting it to UUID so a
-- malformed client-supplied topic cannot turn into a database error.
create or replace function private.can_receive_couple_realtime(input_topic text)
returns boolean
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
declare
    requested_couple_id uuid;
begin
    if auth.uid() is null
       or input_topic is null
       or input_topic !~ '^couple:[0-9a-fA-F-]{36}$' then
        return false;
    end if;

    begin
        requested_couple_id := substring(input_topic from 8)::uuid;
    exception when invalid_text_representation then
        return false;
    end;

    return exists (
        select 1
        from public.couple_members cm
        join public.couples c on c.id = cm.couple_id
        where cm.couple_id = requested_couple_id
          and cm.user_id = (select auth.uid())
          and cm.left_at is null
          and c.status = 'active'
          and c.member_b_id is not null
    );
end;
$$;

revoke all on function private.can_receive_couple_realtime(text) from public, anon;
grant execute on function private.can_receive_couple_realtime(text) to authenticated;

drop policy if exists "Active couple members can receive private broadcasts" on realtime.messages;
create policy "Active couple members can receive private broadcasts"
on realtime.messages for select
to authenticated
using (
    realtime.messages.extension = 'broadcast'
    and (select private.can_receive_couple_realtime((select realtime.topic())))
);

-- Broadcast only the rows belonging to the mutating user's currently active
-- couple. The Realtime service enforces the second half of this boundary via
-- the realtime.messages policy above.
create or replace function private.broadcast_memory_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
    memory_owner_id uuid;
    target_couple_id uuid;
begin
    memory_owner_id := case when tg_op = 'DELETE' then old.owner_id else new.owner_id end;

    select c.id into target_couple_id
    from public.couples c
    where c.status = 'active'
      and c.member_b_id is not null
      and (c.member_a_id = memory_owner_id or c.member_b_id = memory_owner_id)
    limit 1;

    if target_couple_id is not null then
        perform realtime.broadcast_changes(
            'couple:' || target_couple_id::text,
            tg_op,
            tg_op,
            tg_table_name,
            tg_table_schema,
            new,
            old
        );
    end if;

    return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function private.broadcast_memory_reaction_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
    reaction_memory_id uuid;
    memory_owner_id uuid;
    target_couple_id uuid;
begin
    reaction_memory_id := case when tg_op = 'DELETE' then old.memory_id else new.memory_id end;

    select m.owner_id into memory_owner_id
    from public.memories m
    where m.id = reaction_memory_id;

    select c.id into target_couple_id
    from public.couples c
    where c.status = 'active'
      and c.member_b_id is not null
      and (c.member_a_id = memory_owner_id or c.member_b_id = memory_owner_id)
    limit 1;

    if target_couple_id is not null then
        perform realtime.broadcast_changes(
            'couple:' || target_couple_id::text,
            tg_op,
            tg_op,
            tg_table_name,
            tg_table_schema,
            new,
            old
        );
    end if;

    return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function private.broadcast_day_color_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
    calendar_owner_id_value uuid;
    target_couple_id uuid;
begin
    calendar_owner_id_value := case
        when tg_op = 'DELETE' then old.calendar_owner_id
        else new.calendar_owner_id
    end;

    select c.id into target_couple_id
    from public.couples c
    where c.status = 'active'
      and c.member_b_id is not null
      and (c.member_a_id = calendar_owner_id_value or c.member_b_id = calendar_owner_id_value)
    limit 1;

    if target_couple_id is not null then
        perform realtime.broadcast_changes(
            'couple:' || target_couple_id::text,
            tg_op,
            tg_op,
            tg_table_name,
            tg_table_schema,
            new,
            old
        );
    end if;

    return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.broadcast_memory_changes() from public, anon, authenticated;
revoke all on function private.broadcast_memory_reaction_changes() from public, anon, authenticated;
revoke all on function private.broadcast_day_color_changes() from public, anon, authenticated;

drop trigger if exists memories_broadcast_changes on public.memories;
create trigger memories_broadcast_changes
after insert or update or delete on public.memories
for each row execute function private.broadcast_memory_changes();

drop trigger if exists memory_reactions_broadcast_changes on public.memory_reactions;
create trigger memory_reactions_broadcast_changes
after insert or update or delete on public.memory_reactions
for each row execute function private.broadcast_memory_reaction_changes();

drop trigger if exists day_colors_broadcast_changes on public.day_colors;
create trigger day_colors_broadcast_changes
after insert or update or delete on public.day_colors
for each row execute function private.broadcast_day_color_changes();

-- A token is an installation identity, not a user identity. This prevents a
-- stale row for the previous account from receiving a future user's pushes.
create unique index if not exists device_tokens_one_owner_per_token
on public.device_tokens (token);

create or replace function private.register_device_token(
    input_token text,
    input_environment text,
    input_app_version text default null
)
returns public.device_tokens
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
    current_user_id uuid := auth.uid();
    normalized_token text := btrim(input_token);
    saved_token public.device_tokens;
begin
    if current_user_id is null then
        raise exception 'not_authenticated';
    end if;
    if normalized_token is null or char_length(normalized_token) not between 1 and 4096 then
        raise exception 'invalid_device_token';
    end if;
    if input_environment not in ('development', 'production') then
        raise exception 'invalid_device_environment';
    end if;

    delete from public.device_tokens
    where token = normalized_token
      and user_id <> current_user_id;

    insert into public.device_tokens (user_id, token, platform, environment, app_version)
    values (current_user_id, normalized_token, 'ios', input_environment, nullif(btrim(input_app_version), ''))
    on conflict (user_id, token) do update set
        environment = excluded.environment,
        platform = excluded.platform,
        app_version = excluded.app_version
    returning * into saved_token;

    return saved_token;
end;
$$;

create or replace function public.register_device_token(
    input_token text,
    input_environment text,
    input_app_version text default null
)
returns public.device_tokens
language sql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
    select private.register_device_token(input_token, input_environment, input_app_version);
$$;

revoke all on function private.register_device_token(text, text, text) from public, anon, authenticated;
revoke all on function public.register_device_token(text, text, text) from public, anon;
grant execute on function public.register_device_token(text, text, text) to authenticated;

create or replace function private.remove_device_token(input_token text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
    if auth.uid() is null then
        return;
    end if;

    delete from public.device_tokens
    where user_id = (select auth.uid())
      and token = btrim(input_token);
end;
$$;

create or replace function public.remove_device_token(input_token text)
returns void
language sql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
    select private.remove_device_token(input_token);
$$;

revoke all on function private.remove_device_token(text) from public, anon, authenticated;
revoke all on function public.remove_device_token(text) from public, anon;
grant execute on function public.remove_device_token(text) to authenticated;

-- The Edge Function uses this table as an idempotency claim log. It is not a
-- client-facing data table: authenticated and anon have no table privileges.
create table if not exists public.notification_deliveries (
    id uuid primary key default extensions.gen_random_uuid(),
    memory_id uuid not null references public.memories(id) on delete cascade,
    notification_type text not null,
    recipient_user_id uuid not null references public.profiles(id) on delete cascade,
    device_token_hash text not null,
    environment text not null,
    status text not null default 'pending',
    attempt_count smallint not null default 0,
    apns_status integer,
    last_error text,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    constraint notification_deliveries_type_check check (notification_type = 'memory_created'),
    constraint notification_deliveries_environment_check check (environment in ('development', 'production')),
    constraint notification_deliveries_status_check check (status in ('pending', 'sent', 'failed', 'invalid_token')),
    constraint notification_deliveries_attempt_check check (attempt_count between 0 and 3),
    constraint notification_deliveries_device_key_unique
        unique (memory_id, notification_type, recipient_user_id, device_token_hash)
);

alter table public.notification_deliveries enable row level security;
revoke all on table public.notification_deliveries from anon, authenticated;
grant all on table public.notification_deliveries to service_role;

drop policy if exists "Only the service role manages notification deliveries" on public.notification_deliveries;
create policy "Only the service role manages notification deliveries"
on public.notification_deliveries for all
to service_role
using (true)
with check (true);

drop trigger if exists notification_deliveries_set_updated_at on public.notification_deliveries;
create trigger notification_deliveries_set_updated_at
before update on public.notification_deliveries
for each row execute function private.set_updated_at();

-- Keep the database mutation independent from APNs. If the two Vault secrets
-- are configured, pg_net queues a non-blocking webhook after the INSERT. If
-- they are absent, memory creation still succeeds and the exact setup step is
-- reported in the project documentation/final handoff.
create or replace function private.enqueue_memory_created_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions, vault, net
as $$
declare
    webhook_url text;
    webhook_secret text;
begin
    select decrypted_secret into webhook_url
    from vault.decrypted_secrets
    where name = 'memory_notification_webhook_url'
    limit 1;

    select decrypted_secret into webhook_secret
    from vault.decrypted_secrets
    where name = 'memory_notification_webhook_secret'
    limit 1;

    if nullif(btrim(webhook_url), '') is not null
       and nullif(btrim(webhook_secret), '') is not null then
        perform net.http_post(
            url := webhook_url,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'x-webhook-secret', webhook_secret
            ),
            body := jsonb_build_object(
                'type', 'INSERT',
                'table', 'memories',
                'schema', 'public',
                'record', to_jsonb(new),
                'old_record', null
            ),
            timeout_milliseconds := 2000
        );
    end if;

    return new;
end;
$$;

revoke all on function private.enqueue_memory_created_notification() from public, anon, authenticated;

drop trigger if exists memories_enqueue_created_notification on public.memories;
create trigger memories_enqueue_created_notification
after insert on public.memories
for each row execute function private.enqueue_memory_created_notification();
