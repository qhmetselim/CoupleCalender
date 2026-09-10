-- CoupleCalender foundation schema.
-- Daily dates intentionally use PostgreSQL date (not timestamptz) so a user's
-- calendar day cannot move when a client changes time zones.

create extension if not exists pgcrypto;

create schema if not exists private;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
    new.updated_at = timezone('utc', now());
    return new;
end;
$$;

create or replace function private.prevent_memory_owner_change()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
    if new.owner_id <> old.owner_id then
        raise exception 'memory owner cannot be changed';
    end if;
    return new;
end;
$$;

create or replace function private.prevent_reaction_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
    if new.memory_id <> old.memory_id or new.reactor_id <> old.reactor_id then
        raise exception 'reaction identity cannot be changed';
    end if;
    return new;
end;
$$;

create or replace function private.prevent_day_color_identity_change()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
    if new.calendar_owner_id <> old.calendar_owner_id
        or new.calendar_day <> old.calendar_day
        or new.assigned_by_id <> old.assigned_by_id then
        raise exception 'day color identity cannot be changed';
    end if;
    return new;
end;
$$;

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    avatar_url text,
    created_at timestamptz(3) not null default timezone('utc', now()),
    updated_at timestamptz(3) not null default timezone('utc', now()),
    constraint profiles_display_name_length check (
        display_name is null or char_length(trim(display_name)) between 1 and 80
    )
);

create table public.couples (
    id uuid primary key default gen_random_uuid(),
    member_a_id uuid not null references public.profiles(id) on delete restrict,
    member_b_id uuid references public.profiles(id) on delete restrict,
    status text not null default 'pending',
    created_at timestamptz(3) not null default timezone('utc', now()),
    updated_at timestamptz(3) not null default timezone('utc', now()),
    constraint couples_status_check check (status in ('pending', 'active', 'ended')),
    constraint couples_distinct_members check (member_b_id is null or member_a_id <> member_b_id),
    constraint couples_active_has_partner check (status <> 'active' or member_b_id is not null)
);

-- This table is the normalized membership record used by the future invite/join flow.
-- Its partial unique index is the database-level one-active-couple-per-user guard.
create table public.couple_members (
    couple_id uuid not null references public.couples(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    joined_at timestamptz(3) not null default timezone('utc', now()),
    left_at timestamptz(3),
    created_at timestamptz(3) not null default timezone('utc', now()),
    updated_at timestamptz(3) not null default timezone('utc', now()),
    primary key (couple_id, user_id),
    constraint couple_members_membership_dates check (left_at is null or left_at >= joined_at)
);

create table public.reaction_catalog (
    reaction_set text not null,
    reaction_key text not null,
    display_value text not null,
    asset_name text,
    is_active boolean not null default true,
    created_at timestamptz(3) not null default timezone('utc', now()),
    primary key (reaction_set, reaction_key),
    constraint reaction_catalog_key_length check (char_length(reaction_key) between 1 and 80)
);

create table public.memories (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references public.profiles(id) on delete cascade,
    calendar_day date not null,
    content text not null,
    created_at timestamptz(3) not null default timezone('utc', now()),
    updated_at timestamptz(3) not null default timezone('utc', now()),
    constraint memories_content_not_blank check (char_length(trim(content)) > 0),
    constraint memories_content_length check (char_length(content) <= 10_000),
    unique (owner_id, calendar_day)
);

create table public.memory_reactions (
    id uuid primary key default gen_random_uuid(),
    memory_id uuid not null references public.memories(id) on delete cascade,
    reactor_id uuid not null references public.profiles(id) on delete cascade,
    reaction_set text not null,
    reaction_key text not null,
    created_at timestamptz(3) not null default timezone('utc', now()),
    updated_at timestamptz(3) not null default timezone('utc', now()),
    foreign key (reaction_set, reaction_key)
        references public.reaction_catalog (reaction_set, reaction_key),
    unique (memory_id, reactor_id)
);

create table public.day_colors (
    id uuid primary key default gen_random_uuid(),
    calendar_owner_id uuid not null references public.profiles(id) on delete cascade,
    calendar_day date not null,
    assigned_by_id uuid not null references public.profiles(id) on delete cascade,
    color_key text not null,
    created_at timestamptz(3) not null default timezone('utc', now()),
    updated_at timestamptz(3) not null default timezone('utc', now()),
    constraint day_colors_non_owner check (calendar_owner_id <> assigned_by_id),
    constraint day_colors_key_length check (char_length(color_key) between 1 and 80),
    unique (calendar_owner_id, calendar_day)
);

create table public.device_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    token text not null,
    platform text not null default 'ios',
    environment text not null default 'development',
    app_version text,
    created_at timestamptz(3) not null default timezone('utc', now()),
    updated_at timestamptz(3) not null default timezone('utc', now()),
    constraint device_tokens_platform_check check (platform in ('ios', 'ipados')),
    constraint device_tokens_environment_check check (environment in ('development', 'production')),
    unique (user_id, token)
);

create table public.monthly_reports (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    year smallint not null,
    month smallint not null,
    metrics jsonb not null default '{}'::jsonb,
    generated_at timestamptz(3),
    created_at timestamptz(3) not null default timezone('utc', now()),
    updated_at timestamptz(3) not null default timezone('utc', now()),
    constraint monthly_reports_year_check check (year between 2000 and 9999),
    constraint monthly_reports_month_check check (month between 1 and 12),
    unique (user_id, year, month)
);

create table public.yearly_reports (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    year smallint not null,
    metrics jsonb not null default '{}'::jsonb,
    generated_at timestamptz(3),
    created_at timestamptz(3) not null default timezone('utc', now()),
    updated_at timestamptz(3) not null default timezone('utc', now()),
    constraint yearly_reports_year_check check (year between 2000 and 9999),
    unique (user_id, year)
);

create unique index couples_one_active_member_a
    on public.couples (member_a_id)
    where status = 'active';

create unique index couples_one_active_member_b
    on public.couples (member_b_id)
    where status = 'active' and member_b_id is not null;

create unique index couple_members_one_active_couple_per_user
    on public.couple_members (user_id)
    where left_at is null;

create index couple_members_by_couple
    on public.couple_members (couple_id)
    where left_at is null;

create index memories_by_day
    on public.memories (calendar_day);

create index memory_reactions_by_reactor
    on public.memory_reactions (reactor_id);

create index day_colors_by_assigner
    on public.day_colors (assigned_by_id);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger couples_set_updated_at
before update on public.couples
for each row execute function private.set_updated_at();

create trigger couple_members_set_updated_at
before update on public.couple_members
for each row execute function private.set_updated_at();

create trigger memories_set_updated_at
before update on public.memories
for each row execute function private.set_updated_at();

create trigger memories_owner_is_immutable
before update on public.memories
for each row execute function private.prevent_memory_owner_change();

create trigger memory_reactions_set_updated_at
before update on public.memory_reactions
for each row execute function private.set_updated_at();

create trigger memory_reactions_identity_is_immutable
before update on public.memory_reactions
for each row execute function private.prevent_reaction_identity_change();

create trigger day_colors_set_updated_at
before update on public.day_colors
for each row execute function private.set_updated_at();

create trigger day_colors_identity_is_immutable
before update on public.day_colors
for each row execute function private.prevent_day_color_identity_change();

create trigger device_tokens_set_updated_at
before update on public.device_tokens
for each row execute function private.set_updated_at();

create trigger monthly_reports_set_updated_at
before update on public.monthly_reports
for each row execute function private.set_updated_at();

create trigger yearly_reports_set_updated_at
before update on public.yearly_reports
for each row execute function private.set_updated_at();

insert into public.reaction_catalog (reaction_set, reaction_key, display_value)
values
    ('unicode-v1', 'heart', '❤️'),
    ('unicode-v1', 'laugh', '😂'),
    ('unicode-v1', 'joy', '🤣'),
    ('unicode-v1', 'love_eyes', '😍'),
    ('unicode-v1', 'kiss', '😘'),
    ('unicode-v1', 'surprised', '😮'),
    ('unicode-v1', 'sad', '😢'),
    ('unicode-v1', 'cry', '😭'),
    ('unicode-v1', 'angry', '😡'),
    ('unicode-v1', 'thinking', '🤔'),
    ('unicode-v1', 'clap', '👏'),
    ('unicode-v1', 'thumbs_up', '👍'),
    ('unicode-v1', 'thumbs_down', '👎'),
    ('unicode-v1', 'pray', '🙏'),
    ('unicode-v1', 'fire', '🔥'),
    ('unicode-v1', 'sparkles', '✨'),
    ('unicode-v1', 'party', '🎉'),
    ('unicode-v1', 'hundred', '💯'),
    ('unicode-v1', 'eyes', '👀'),
    ('unicode-v1', 'hug', '🤗');

alter table public.profiles enable row level security;
alter table public.couples enable row level security;
alter table public.couple_members enable row level security;
alter table public.reaction_catalog enable row level security;
alter table public.memories enable row level security;
alter table public.memory_reactions enable row level security;
alter table public.day_colors enable row level security;
alter table public.device_tokens enable row level security;
alter table public.monthly_reports enable row level security;
alter table public.yearly_reports enable row level security;

revoke all on schema public from anon;
revoke all on table
    public.profiles,
    public.couples,
    public.couple_members,
    public.reaction_catalog,
    public.memories,
    public.memory_reactions,
    public.day_colors,
    public.device_tokens,
    public.monthly_reports,
    public.yearly_reports
from anon, authenticated;

grant usage on schema public to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select on public.couples, public.couple_members, public.reaction_catalog to authenticated;
grant select, insert, update, delete on public.memories to authenticated;
grant select, insert, update, delete on public.memory_reactions to authenticated;
grant select, insert, update, delete on public.day_colors to authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;
grant select on public.monthly_reports, public.yearly_reports to authenticated;

create policy "Users can view their own or active partner profile"
on public.profiles for select
to authenticated
using (
    id = (select auth.uid())
    or exists (
        select 1
        from public.couples c
        where c.status = 'active'
          and (
              (c.member_a_id = (select auth.uid()) and c.member_b_id = profiles.id)
              or (c.member_b_id = (select auth.uid()) and c.member_a_id = profiles.id)
          )
    )
);

create policy "Users can create their own profile"
on public.profiles for insert
to authenticated
with check (id = (select auth.uid()));

create policy "Users can update their own profile"
on public.profiles for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "Couple members can view their couple"
on public.couples for select
to authenticated
using (
    status in ('pending', 'active')
    and (
        member_a_id = (select auth.uid())
        or member_b_id = (select auth.uid())
    )
);

create policy "Users can view their own couple membership"
on public.couple_members for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Users can view shared memories"
on public.memories for select
to authenticated
using (
    owner_id = (select auth.uid())
    or exists (
        select 1
        from public.couples c
        where c.status = 'active'
          and (
              (c.member_a_id = owner_id and c.member_b_id = (select auth.uid()))
              or (c.member_b_id = owner_id and c.member_a_id = (select auth.uid()))
          )
    )
);

create policy "Users can create their own memories"
on public.memories for insert
to authenticated
with check (owner_id = (select auth.uid()));

create policy "Owners can update their own memories"
on public.memories for update
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy "Owners can delete their own memories"
on public.memories for delete
to authenticated
using (owner_id = (select auth.uid()));

create policy "Authenticated users can view active reaction types"
on public.reaction_catalog for select
to authenticated
using (is_active);

create policy "Couple members can view memory reactions"
on public.memory_reactions for select
to authenticated
using (
    exists (
        select 1
        from public.memories m
        where m.id = memory_id
          and (
              m.owner_id = (select auth.uid())
              or exists (
                  select 1
                  from public.couples c
                  where c.status = 'active'
                    and (
                        (c.member_a_id = m.owner_id and c.member_b_id = (select auth.uid()))
                        or (c.member_b_id = m.owner_id and c.member_a_id = (select auth.uid()))
                    )
              )
          )
    )
);

create policy "Partners can create one reaction per memory"
on public.memory_reactions for insert
to authenticated
with check (
    reactor_id = (select auth.uid())
    and exists (
        select 1
        from public.memories m
        join public.couples c on c.status = 'active'
            and (
                (c.member_a_id = m.owner_id and c.member_b_id = (select auth.uid()))
                or (c.member_b_id = m.owner_id and c.member_a_id = (select auth.uid()))
            )
        where m.id = memory_id
    )
);

create policy "Partners can update their own memory reaction"
on public.memory_reactions for update
to authenticated
using (
    reactor_id = (select auth.uid())
    and exists (
        select 1
        from public.memories m
        join public.couples c on c.status = 'active'
            and (
                (c.member_a_id = m.owner_id and c.member_b_id = (select auth.uid()))
                or (c.member_b_id = m.owner_id and c.member_a_id = (select auth.uid()))
            )
        where m.id = memory_id
    )
)
with check (
    reactor_id = (select auth.uid())
    and exists (
        select 1
        from public.memories m
        join public.couples c on c.status = 'active'
            and (
                (c.member_a_id = m.owner_id and c.member_b_id = (select auth.uid()))
                or (c.member_b_id = m.owner_id and c.member_a_id = (select auth.uid()))
            )
        where m.id = memory_id
    )
);

create policy "Partners can delete their own memory reaction"
on public.memory_reactions for delete
to authenticated
using (reactor_id = (select auth.uid()));

create policy "Couple members can view day colors"
on public.day_colors for select
to authenticated
using (
    calendar_owner_id = (select auth.uid())
    or assigned_by_id = (select auth.uid())
);

create policy "Partners can assign a day color"
on public.day_colors for insert
to authenticated
with check (
    assigned_by_id = (select auth.uid())
    and exists (
        select 1
        from public.couples c
        where c.status = 'active'
          and (
              (c.member_a_id = calendar_owner_id and c.member_b_id = (select auth.uid()))
              or (c.member_b_id = calendar_owner_id and c.member_a_id = (select auth.uid()))
          )
    )
);

create policy "Partners can update an assigned day color"
on public.day_colors for update
to authenticated
using (assigned_by_id = (select auth.uid()))
with check (
    assigned_by_id = (select auth.uid())
    and exists (
        select 1
        from public.couples c
        where c.status = 'active'
          and (
              (c.member_a_id = calendar_owner_id and c.member_b_id = (select auth.uid()))
              or (c.member_b_id = calendar_owner_id and c.member_a_id = (select auth.uid()))
          )
    )
);

create policy "Partners can delete an assigned day color"
on public.day_colors for delete
to authenticated
using (assigned_by_id = (select auth.uid()));

create policy "Users can manage their own device tokens"
on public.device_tokens for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Users can register their own device tokens"
on public.device_tokens for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy "Users can update their own device tokens"
on public.device_tokens for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy "Users can delete their own device tokens"
on public.device_tokens for delete
to authenticated
using (user_id = (select auth.uid()));

create policy "Users can view their own monthly reports"
on public.monthly_reports for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Users can view their own yearly reports"
on public.yearly_reports for select
to authenticated
using (user_id = (select auth.uid()));
