create or replace function private.leave_active_couple()
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

    select cm.couple_id
    into target_couple_id
    from public.couple_members cm
    join public.couples c on c.id = cm.couple_id
    where cm.user_id = caller_id
      and cm.left_at is null
      and c.status = 'active'
    for update;

    if target_couple_id is null then
        raise exception using errcode = 'P0001', message = 'no_active_couple';
    end if;

    update public.couple_members
    set left_at = timezone('utc', now())
    where public.couple_members.couple_id = target_couple_id
      and public.couple_members.left_at is null;

    update public.couples
    set status = 'ended'
    where public.couples.id = target_couple_id
      and public.couples.status = 'active';

    return true;
end;
$$;

create or replace function public.leave_active_couple()
returns boolean
language sql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$ select private.leave_active_couple(); $$;

grant execute on function private.leave_active_couple() to authenticated;
revoke all on function private.leave_active_couple() from public, anon;
revoke all on function public.leave_active_couple() from public, anon, authenticated;
grant execute on function public.leave_active_couple() to authenticated;
