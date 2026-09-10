-- Remove a partner-assigned color when its memory is deleted. The helper is
-- private and narrowly scoped so the normal day_colors RLS policies remain
-- unchanged for client operations.
create or replace function private.remove_day_color_for_deleted_memory()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
    delete from public.day_colors
    where calendar_owner_id = old.owner_id
      and calendar_day = old.calendar_day;
    return old;
end;
$$;

revoke all on function private.remove_day_color_for_deleted_memory() from public, anon, authenticated;

drop trigger if exists memories_remove_day_color on public.memories;
create trigger memories_remove_day_color
after delete on public.memories
for each row execute function private.remove_day_color_for_deleted_memory();

-- Keep delete authorization consistent with the insert/update policies. A
-- former partner must not retain write access to an old shared row after the
-- active couple relationship ends.
drop policy if exists "Partners can delete their own memory reaction" on public.memory_reactions;
create policy "Partners can delete their own memory reaction"
on public.memory_reactions for delete
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
);

drop policy if exists "Partners can delete an assigned day color" on public.day_colors;
create policy "Partners can delete an assigned day color"
on public.day_colors for delete
to authenticated
using (
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
