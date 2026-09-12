-- Prompt 8: deterministic, server-side report snapshots.
-- Reports are calculated from calendar_day and interaction metadata only.
-- Memory content is never copied into the report snapshot.

create or replace function private.monthly_report_metrics(
    input_user_id uuid,
    input_year integer,
    input_month integer
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with period as (
    select
        pg_catalog.make_date(input_year, input_month, 1) as start_day,
        (pg_catalog.make_date(input_year, input_month, 1) + pg_catalog.make_interval(months => 1))::date as end_day
),
period_memories as (
    select m.id, m.calendar_day, m.content
    from public.memories m
    cross join period p
    where m.owner_id = input_user_id
      and m.calendar_day >= p.start_day
      and m.calendar_day < p.end_day
),
period_reactions as (
    select
        mr.memory_id,
        mr.reaction_set,
        mr.reaction_key,
        rc.display_value
    from public.memory_reactions mr
    join period_memories pm on pm.id = mr.memory_id
    left join public.reaction_catalog rc
        on rc.reaction_set = mr.reaction_set
       and rc.reaction_key = mr.reaction_key
),
reaction_frequency as (
    select
        reaction_set,
        reaction_key,
        max(display_value) as display_value,
        count(*)::integer as reaction_count
    from period_reactions
    group by reaction_set, reaction_key
),
period_colors as (
    select dc.color_key
    from public.day_colors dc
    join period_memories pm on pm.calendar_day = dc.calendar_day
    where dc.calendar_owner_id = input_user_id
),
color_frequency as (
    select color_key, count(*)::integer as color_count
    from period_colors
    group by color_key
),
week_frequency as (
    select
        pg_catalog.date_trunc('week', calendar_day)::date as week_start,
        count(*)::integer as memory_count
    from period_memories
    group by pg_catalog.date_trunc('week', calendar_day)::date
)
select pg_catalog.jsonb_build_object(
    'schema_version', 1,
    'period', pg_catalog.jsonb_build_object('year', input_year, 'month', input_month),
    'memory_count', (select count(*)::integer from period_memories),
    'reacted_memory_count', (select count(distinct memory_id)::integer from period_reactions),
    'reaction_count', (select count(*)::integer from period_reactions),
    'reaction_coverage', case
        when (select count(*) from period_memories) = 0 then 0
        else round(
            (select count(distinct memory_id)::numeric from period_reactions)
            / (select count(*)::numeric from period_memories),
            4
        )
    end,
    'reaction_frequency', coalesce(
        (
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'reaction_set', reaction_set,
                    'reaction_key', reaction_key,
                    'display_value', display_value,
                    'count', reaction_count
                )
                order by reaction_count desc, reaction_set asc, reaction_key asc
            )
            from reaction_frequency
        ),
        '[]'::jsonb
    ),
    'most_used_reaction', (
        select pg_catalog.jsonb_build_object(
            'reaction_set', reaction_set,
            'reaction_key', reaction_key,
            'display_value', display_value,
            'count', reaction_count
        )
        from reaction_frequency
        order by reaction_count desc, reaction_set asc, reaction_key asc
        limit 1
    ),
    'day_color_frequency', coalesce(
        (
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object('color_key', color_key, 'count', color_count)
                order by color_count desc, color_key asc
            )
            from color_frequency
        ),
        '[]'::jsonb
    ),
    'most_used_color', (
        select pg_catalog.jsonb_build_object('color_key', color_key, 'count', color_count)
        from color_frequency
        order by color_count desc, color_key asc
        limit 1
    ),
    'memory_day_count', (select count(distinct calendar_day)::integer from period_memories),
    'active_week', (
        select pg_catalog.jsonb_build_object(
            'week_start', pg_catalog.to_char(week_start, 'YYYY-MM-DD'),
            'week_end', pg_catalog.to_char(week_start + 6, 'YYYY-MM-DD'),
            'memory_count', memory_count
        )
        from week_frequency
        order by memory_count desc, week_start asc
        limit 1
    ),
    'longest_memory_character_count', coalesce((select max(pg_catalog.char_length(content)) from period_memories), 0),
    'average_memory_character_count', coalesce(
        round((select avg(pg_catalog.char_length(content)) from period_memories)::numeric, 2),
        0
    )
);
$$;

create or replace function private.yearly_report_metrics(
    input_user_id uuid,
    input_year integer
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with year_period as (
    select
        pg_catalog.make_date(input_year, 1, 1) as start_day,
        pg_catalog.make_date(input_year + 1, 1, 1) as end_day
),
year_memories as (
    select m.id, m.calendar_day, m.content
    from public.memories m
    cross join year_period p
    where m.owner_id = input_user_id
      and m.calendar_day >= p.start_day
      and m.calendar_day < p.end_day
),
year_reactions as (
    select mr.memory_id, mr.reaction_set, mr.reaction_key, rc.display_value, pm.calendar_day
    from public.memory_reactions mr
    join year_memories pm on pm.id = mr.memory_id
    left join public.reaction_catalog rc
        on rc.reaction_set = mr.reaction_set
       and rc.reaction_key = mr.reaction_key
),
reaction_frequency as (
    select reaction_set, reaction_key, max(display_value) as display_value, count(*)::integer as reaction_count
    from year_reactions
    group by reaction_set, reaction_key
),
year_colors as (
    select dc.color_key
    from public.day_colors dc
    join year_memories ym on ym.calendar_day = dc.calendar_day
    where dc.calendar_owner_id = input_user_id
),
color_frequency as (
    select color_key, count(*)::integer as color_count
    from year_colors
    group by color_key
),
months as (
    select generate_series(1, 12)::integer as month
),
monthly_memory_counts as (
    select extract(month from calendar_day)::integer as month, count(*)::integer as memory_count
    from year_memories
    group by extract(month from calendar_day)::integer
),
monthly_reaction_counts as (
    select
        extract(month from calendar_day)::integer as month,
        count(*)::integer as reaction_count,
        count(distinct memory_id)::integer as reacted_memory_count
    from year_reactions
    group by extract(month from calendar_day)::integer
),
monthly_breakdown as (
    select
        months.month,
        coalesce(mmc.memory_count, 0) as memory_count,
        coalesce(mrc.reaction_count, 0) as reaction_count,
        coalesce(mrc.reacted_memory_count, 0) as reacted_memory_count,
        case
            when coalesce(mmc.memory_count, 0) = 0 then 0
            else round(coalesce(mrc.reacted_memory_count, 0)::numeric / mmc.memory_count::numeric, 4)
        end as reaction_coverage
    from months
    left join monthly_memory_counts mmc on mmc.month = months.month
    left join monthly_reaction_counts mrc on mrc.month = months.month
),
active_month as (
    select month, memory_count
    from monthly_breakdown
    where memory_count > 0
    order by memory_count desc, month asc
    limit 1
)
select pg_catalog.jsonb_build_object(
    'schema_version', 1,
    'period', pg_catalog.jsonb_build_object('year', input_year),
    'memory_count', (select count(*)::integer from year_memories),
    'reacted_memory_count', (select count(distinct memory_id)::integer from year_reactions),
    'reaction_count', (select count(*)::integer from year_reactions),
    'reaction_coverage', case
        when (select count(*) from year_memories) = 0 then 0
        else round(
            (select count(distinct memory_id)::numeric from year_reactions)
            / (select count(*)::numeric from year_memories),
            4
        )
    end,
    'reaction_frequency', coalesce(
        (
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'reaction_set', reaction_set,
                    'reaction_key', reaction_key,
                    'display_value', display_value,
                    'count', reaction_count
                )
                order by reaction_count desc, reaction_set asc, reaction_key asc
            )
            from reaction_frequency
        ),
        '[]'::jsonb
    ),
    'most_used_reaction', (
        select pg_catalog.jsonb_build_object(
            'reaction_set', reaction_set,
            'reaction_key', reaction_key,
            'display_value', display_value,
            'count', reaction_count
        )
        from reaction_frequency
        order by reaction_count desc, reaction_set asc, reaction_key asc
        limit 1
    ),
    'day_color_frequency', coalesce(
        (
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object('color_key', color_key, 'count', color_count)
                order by color_count desc, color_key asc
            )
            from color_frequency
        ),
        '[]'::jsonb
    ),
    'most_used_color', (
        select pg_catalog.jsonb_build_object('color_key', color_key, 'count', color_count)
        from color_frequency
        order by color_count desc, color_key asc
        limit 1
    ),
    'most_active_month', (select month from active_month),
    'most_active_month_memory_count', coalesce((select memory_count from active_month), 0),
    'monthly_breakdown', (
        select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
                'month', month,
                'memory_count', memory_count,
                'reaction_count', reaction_count,
                'reacted_memory_count', reacted_memory_count,
                'reaction_coverage', reaction_coverage
            )
            order by month asc
        )
        from monthly_breakdown
    ),
    'longest_memory_character_count', coalesce((select max(pg_catalog.char_length(content)) from year_memories), 0),
    'average_memory_character_count', coalesce(
        round((select avg(pg_catalog.char_length(content)) from year_memories)::numeric, 2),
        0
    )
);
$$;

create or replace function private.generate_monthly_report_for_user(
    input_user_id uuid,
    input_year integer,
    input_month integer
)
returns public.monthly_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
    saved_report public.monthly_reports;
    period_start date;
begin
    if input_user_id is null then
        raise exception 'report_user_required';
    end if;
    if input_year not between 2000 and 9999 or input_month not between 1 and 12 then
        raise exception 'invalid_report_period';
    end if;

    period_start := pg_catalog.make_date(input_year, input_month, 1);
    if period_start >= pg_catalog.date_trunc('month', current_date)::date then
        raise exception 'report_period_incomplete';
    end if;

    insert into public.monthly_reports (user_id, year, month, metrics, generated_at)
    values (
        input_user_id,
        input_year::smallint,
        input_month::smallint,
        private.monthly_report_metrics(input_user_id, input_year, input_month),
        pg_catalog.timezone('utc', pg_catalog.now())
    )
    on conflict (user_id, year, month) do nothing
    returning * into saved_report;

    if not found then
        select * into saved_report
        from public.monthly_reports
        where user_id = input_user_id
          and year = input_year::smallint
          and month = input_month::smallint;
    end if;

    return saved_report;
end;
$$;

create or replace function private.generate_yearly_report_for_user(
    input_user_id uuid,
    input_year integer
)
returns public.yearly_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
    saved_report public.yearly_reports;
begin
    if input_user_id is null then
        raise exception 'report_user_required';
    end if;
    if input_year not between 2000 and 9998 then
        raise exception 'invalid_report_period';
    end if;
    if pg_catalog.make_date(input_year, 1, 1) >= pg_catalog.date_trunc('year', current_date)::date then
        raise exception 'report_period_incomplete';
    end if;

    insert into public.yearly_reports (user_id, year, metrics, generated_at)
    values (
        input_user_id,
        input_year::smallint,
        private.yearly_report_metrics(input_user_id, input_year),
        pg_catalog.timezone('utc', pg_catalog.now())
    )
    on conflict (user_id, year) do nothing
    returning * into saved_report;

    if not found then
        select * into saved_report
        from public.yearly_reports
        where user_id = input_user_id
          and year = input_year::smallint;
    end if;

    return saved_report;
end;
$$;

create or replace function private.ensure_completed_monthly_report_for_current_user(
    input_year smallint,
    input_month smallint
)
returns public.monthly_reports
language sql
security definer
set search_path = ''
as $$
    select private.generate_monthly_report_for_user(
        (select auth.uid()),
        input_year::integer,
        input_month::integer
    );
$$;

create or replace function private.ensure_completed_yearly_report_for_current_user(
    input_year smallint
)
returns public.yearly_reports
language sql
security definer
set search_path = ''
as $$
    select private.generate_yearly_report_for_user(
        (select auth.uid()),
        input_year::integer
    );
$$;

create or replace function public.ensure_completed_monthly_report(
    input_year smallint,
    input_month smallint
)
returns public.monthly_reports
language sql
security invoker
set search_path = ''
as $$
    select private.ensure_completed_monthly_report_for_current_user(input_year, input_month);
$$;

create or replace function public.ensure_completed_yearly_report(
    input_year smallint
)
returns public.yearly_reports
language sql
security invoker
set search_path = ''
as $$
    select private.ensure_completed_yearly_report_for_current_user(input_year);
$$;

create or replace function private.generate_missing_monthly_reports(
    input_year integer,
    input_month integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    profile_id uuid;
    generated_count integer := 0;
begin
    for profile_id in select p.id from public.profiles p order by p.id loop
        perform private.generate_monthly_report_for_user(profile_id, input_year, input_month);
        generated_count := generated_count + 1;
    end loop;
    return generated_count;
end;
$$;

create or replace function private.generate_missing_yearly_reports(input_year integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    profile_id uuid;
    generated_count integer := 0;
begin
    for profile_id in select p.id from public.profiles p order by p.id loop
        perform private.generate_yearly_report_for_user(profile_id, input_year);
        generated_count := generated_count + 1;
    end loop;
    return generated_count;
end;
$$;

create or replace function private.run_monthly_report_cron()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    previous_period date := (current_date - pg_catalog.make_interval(months => 1))::date;
begin
    perform private.generate_missing_monthly_reports(
        extract(year from previous_period)::integer,
        extract(month from previous_period)::integer
    );
end;
$$;

create or replace function private.run_yearly_report_cron()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform private.generate_missing_yearly_reports(extract(year from current_date)::integer - 1);
end;
$$;

revoke all on function private.monthly_report_metrics(uuid, integer, integer) from public, anon, authenticated;
revoke all on function private.yearly_report_metrics(uuid, integer) from public, anon, authenticated;
revoke all on function private.generate_monthly_report_for_user(uuid, integer, integer) from public, anon, authenticated;
revoke all on function private.generate_yearly_report_for_user(uuid, integer) from public, anon, authenticated;
revoke all on function private.ensure_completed_monthly_report_for_current_user(smallint, smallint) from public, anon, authenticated;
revoke all on function private.ensure_completed_yearly_report_for_current_user(smallint) from public, anon, authenticated;
revoke all on function private.generate_missing_monthly_reports(integer, integer) from public, anon, authenticated;
revoke all on function private.generate_missing_yearly_reports(integer) from public, anon, authenticated;
revoke all on function private.run_monthly_report_cron() from public, anon, authenticated;
revoke all on function private.run_yearly_report_cron() from public, anon, authenticated;

revoke all on function public.ensure_completed_monthly_report(smallint, smallint) from public, anon;
revoke all on function public.ensure_completed_yearly_report(smallint) from public, anon;
grant execute on function public.ensure_completed_monthly_report(smallint, smallint) to authenticated;
grant execute on function public.ensure_completed_yearly_report(smallint) to authenticated;
grant execute on function private.ensure_completed_monthly_report_for_current_user(smallint, smallint) to authenticated;
grant execute on function private.ensure_completed_yearly_report_for_current_user(smallint) to authenticated;

revoke all on table public.monthly_reports, public.yearly_reports from anon, authenticated;
grant select on public.monthly_reports, public.yearly_reports to authenticated;

drop policy if exists "Users can view their own monthly reports" on public.monthly_reports;
create policy "Users can view their own monthly reports"
on public.monthly_reports for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can view their own yearly reports" on public.yearly_reports;
create policy "Users can view their own yearly reports"
on public.yearly_reports for select
to authenticated
using ((select auth.uid()) = user_id);

do $schedule$
declare
    existing_job record;
begin
    if exists (select 1 from pg_catalog.pg_namespace where nspname = 'cron') then
        for existing_job in
            select jobid from cron.job where jobname in ('couplecalender-monthly-reports', 'couplecalender-yearly-reports')
        loop
            perform cron.unschedule(existing_job.jobid);
        end loop;

        perform cron.schedule(
            'couplecalender-monthly-reports',
            '15 2 1 * *',
            'select private.run_monthly_report_cron()'
        );
        perform cron.schedule(
            'couplecalender-yearly-reports',
            '30 2 1 1 *',
            'select private.run_yearly_report_cron()'
        );
    end if;
end
$schedule$;
