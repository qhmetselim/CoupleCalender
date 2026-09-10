-- A day color belongs to a real partner memory and must stop being visible
-- when the couple is no longer active. The calendar owner may still read
-- their own historical rows; the former partner may not.
drop policy if exists "Couple members can view day colors" on public.day_colors;
create policy "Couple members can view day colors"
on public.day_colors for select
to authenticated
using (
    calendar_owner_id = (select auth.uid())
    or exists (
        select 1
        from public.couples c
        where c.status = 'active'
          and (
              (c.member_a_id = calendar_owner_id and c.member_b_id = (select auth.uid()))
              or (c.member_b_id = calendar_owner_id and c.member_a_id = (select auth.uid()))
          )
    )
);

drop policy if exists "Partners can assign a day color" on public.day_colors;
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
    and exists (
        select 1
        from public.memories m
        where m.owner_id = calendar_owner_id
          and m.calendar_day = day_colors.calendar_day
    )
);

drop policy if exists "Partners can update an assigned day color" on public.day_colors;
create policy "Partners can update an assigned day color"
on public.day_colors for update
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
)
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
    and exists (
        select 1
        from public.memories m
        where m.owner_id = calendar_owner_id
          and m.calendar_day = day_colors.calendar_day
    )
);
