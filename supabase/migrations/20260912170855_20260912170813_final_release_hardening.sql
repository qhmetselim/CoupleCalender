-- Final release hardening. This migration does not change the application data
-- model; it closes stale-partner write paths and adds missing FK indexes.

revoke all on function public.rls_auto_enable() from public, anon, authenticated;

create index if not exists partner_invites_by_consumed_by
    on private.partner_invites (consumed_by);

create index if not exists partner_invites_by_inviter
    on private.partner_invites (inviter_id);

create index if not exists memory_reactions_by_catalog
    on public.memory_reactions (reaction_set, reaction_key);

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
    and exists (
        select 1
        from public.memories m
        where m.owner_id = calendar_owner_id
          and m.calendar_day = day_colors.calendar_day
    )
);
