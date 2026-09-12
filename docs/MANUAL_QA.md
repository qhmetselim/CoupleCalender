# CoupleCalender Manual QA Plan

This checklist covers release-only scenarios that cannot be truthfully proven
by a simulator build or unit tests. Run it on a signed build with development
Supabase data and disposable test accounts. Never put test passwords, APNs
private keys, access tokens, or invite secrets in the repository.

## Test setup

- [ ] Device A and device B are physical iPhones on supported iOS.
- [ ] Account A and account B have confirmed email addresses.
- [ ] An unrelated account C exists for isolation checks.
- [ ] Development Supabase project is selected.
- [ ] App Group group.asa.CoupleCalender is registered and present in
      profiles.
- [ ] Push Notifications capability and APNs server secrets are configured.
- [ ] Supabase cron jobs and Edge Functions are active.
- [ ] Test build version, commit, device, and environment are recorded.

Record evidence for each section: pass/fail, timestamp, account/device, and a
screen recording or console/reference ID where useful.

## 1. Authentication and account lifecycle

- [ ] Fresh install opens signed out without showing private data.
- [ ] Sign up with a new account works.
- [ ] Email-confirmation-required state is clear and does not falsely claim an
      active session.
- [ ] Invalid credentials show a friendly error and do not expose raw backend
      text.
- [ ] Sign in restores the correct account after relaunch.
- [ ] Sign out clears session, pending notification/widget routes, device-token
      association best-effort, and shared widget snapshot.
- [ ] A logout followed by B login never shows A's partner snapshot or pending
      deep link.
- [ ] Profile creation and display-name update work with trimmed, non-empty
      names.
- [ ] Account Settings shows the current notification status and connection.
- [ ] Account deletion confirmation clearly describes irreversible deletion.
- [ ] Deleting a disposable account removes Auth access, profile data,
      couple/membership data, own memories/interactions, and local widget data.
- [ ] A failed deletion leaves a usable signed-in state and a retry path.

## 2. Pairing and connection isolation

- [ ] A creates a single-use, case-insensitive invite with expiry.
- [ ] Code copy/share does not expose database plaintext or private credentials.
- [ ] B joins with whitespace and lowercase input.
- [ ] Self-join is rejected.
- [ ] Invalid and expired codes are rejected with user-friendly messages.
- [ ] Reusing a consumed code is rejected.
- [ ] A second active/pending pairing attempt is rejected safely.
- [ ] Concurrent attempts to consume the same invite result in one successful
      membership, not two couples.
- [ ] A and B both reach paired state without relaunching.
- [ ] C cannot discover or open A/B private pairing data.
- [ ] Leave/end couple requires confirmation and explains that memories remain
      while partner access ends.
- [ ] After leave, both users lose partner calendar access immediately.
- [ ] After leave, the old Realtime channel is unsubscribed and the widget
      snapshot is cleared.

## 3. Memory and RLS matrix

Use an existing or newly created disposable memory and verify both UI and
server behavior:

| Operation | Owner A | Partner B | Unrelated C |
| --- | --- | --- | --- |
| Read A memory | pass | pass | deny |
| Insert for A calendar | pass | deny | deny |
| Update A content | pass | deny | deny |
| Change owner/day identity | deny | deny | deny |
| Delete A memory | pass | deny | deny |

- [ ] Empty/whitespace content cannot be saved.
- [ ] 10,000-character boundary behaves as documented.
- [ ] Future-day creation is unavailable while future dates remain viewable.
- [ ] Successful create appears in Day, Week, Month, and Year markers without
      manual refresh.
- [ ] Update changes the cached card and keeps the same owner/day identity.
- [ ] Delete confirmation works and removes the memory marker.
- [ ] Network failure preserves editor text or existing card and offers retry.
- [ ] Duplicate same-day creation is handled as a friendly conflict.
- [ ] Partner memory is always read-only: no Add/Edit/Delete controls.
- [ ] Memory deletion does not leave an orphan day color.

## 4. Reactions and day colors

| Operation | Owner A on A memory/day | Partner B on A memory/day | Unrelated C |
| --- | --- | --- | --- |
| Read reaction/color | pass | pass | deny |
| Add reaction | deny | pass | deny |
| Replace/remove own reaction | deny | pass | deny |
| Add/change/remove day color | deny | pass | deny |

- [ ] Reaction picker contains the active catalog options and no hard-coded
      second source of truth.
- [ ] B has at most one reaction row per memory; replacement updates it.
- [ ] B can remove the reaction and A sees the removal.
- [ ] A can see B's reaction but cannot edit it.
- [ ] Color palette uses stable keys; B can set, replace, and remove A's day
      color.
- [ ] A can see the color but cannot change or remove it.
- [ ] Empty memory days expose neither reaction nor color controls.
- [ ] Reaction/color mutation updates Day, Week, Month, and Year presentation
      without a full-calendar reload.

## 5. Two-device Realtime

- [ ] A adds a memory while B is viewing A's calendar; B sees the marker and
      Day View content without manual refresh.
- [ ] A edits and deletes a memory; B sees update/delete.
- [ ] B adds, replaces, and removes a reaction; A sees each state.
- [ ] B sets, changes, and removes a day color; A sees each state.
- [ ] Duplicate/replayed events do not create duplicate local rows.
- [ ] Events for an unrelated couple are ignored.
- [ ] Switching away from paired state unsubscribes the channel.
- [ ] Backgrounding either app, making a change, and returning triggers a
      visible-period reconciliation.
- [ ] Reconnect does not create duplicate channels or duplicate UI updates.

## 6. APNs and notification privacy

- [ ] Permission is requested contextually after pairing, not on first launch.
- [ ] Not Now does not repeatedly show the system prompt.
- [ ] Denied permission links naturally to Settings without blocking the app.
- [ ] Device token registration records the authenticated owner, environment,
      and app version.
- [ ] Switching users on one installation does not retain the old token owner.
- [ ] New memory INSERT sends at most one delivery per active partner device.
- [ ] Memory UPDATE, DELETE, reaction, and day-color changes do not send push.
- [ ] Notification title/body contains no memory content.
- [ ] Custom payload contains only the minimum route metadata.
- [ ] Invalid/unregistered APNs token is deactivated or removed.
- [ ] Transient provider failure does not create an infinite retry loop.
- [ ] A repeated webhook/event does not create duplicate delivery records.
- [ ] Foreground notification behavior is not duplicated by custom banner/toast
      UI.

## 7. Notification and widget routes

- [ ] Foreground notification opens the partner's correct CalendarDay in Day
      mode.
- [ ] Background notification opens the same route.
- [ ] Cold-launch notification survives auth/session restore and paired-state
      loading.
- [ ] Deleted memory produces a normal empty day, not a crash.
- [ ] A stale/foreign owner route is ignored.
- [ ] Widget memory item opens the partner calendar and correct day.
- [ ] A widget route cannot select an arbitrary user UUID.
- [ ] Sign out/unpair clears pending notification and widget routes.

## 8. Widget and App Group

- [ ] App Group group.asa.CoupleCalender is present on both app and widget
      entitlements in the signed build.
- [ ] Small widget renders partner name, latest preview, date, decoration, and
      a useful empty state.
- [ ] Medium widget renders latest preview plus recent-day context without a
      full calendar.
- [ ] Large widget renders a short list of recent partner memories.
- [ ] Widget never initializes Supabase or stores an auth/refresh token.
- [ ] Snapshot is limited to the latest seven partner memories and is sorted
      by calendar day descending.
- [ ] Memory/reaction/color changes update the snapshot and reload only the
      widget kind.
- [ ] Offline widget displays the last valid snapshot.
- [ ] Sign out/unpair immediately clears old partner content even offline.
- [ ] Account A logout then B login cannot reveal A's widget content.
- [ ] Widget previews use generic sample text, not real personal content.
- [ ] Light/dark, small/medium/large Home Screen layouts have no clipping.

## 9. Reports and scheduled generation

- [ ] Completed month opens its stored Monthly Report snapshot.
- [ ] Completed year opens its stored Yearly Report snapshot.
- [ ] Current month says it is available after the month completes and does not
      generate early.
- [ ] Current year says it is available after the year completes and does not
      generate early.
- [ ] Historical eligible month/year can be generated on demand once.
- [ ] Zero-memory completed periods render factual zero states.
- [ ] Repeated ensure calls do not overwrite or duplicate an existing snapshot.
- [ ] Editing old source data after generation does not silently rewrite the
      historical report.
- [ ] Monthly metrics, yearly totals, top reaction/color, active period, and
      breakdowns match independently calculated fixture expectations.
- [ ] Monthly cron runs after the first day of a new month.
- [ ] Yearly cron runs after the first day of a new year.
- [ ] A's report cannot be read by B or C; direct report writes are denied.

## 10. Visual, accessibility, and interaction QA

- [ ] Sign In/Sign Up: focus order, keyboard type, Next/Done, loading, error.
- [ ] Profile setup: natural copy, trimmed name, Dynamic Type.
- [ ] Pairing: readable code, copy/share, expiry, paste, success transition.
- [ ] Calendar: owner, period, and mode are always clear.
- [ ] Day/Week/Month/Year: selected/today/memory/reaction/color states remain
      distinct.
- [ ] Day View: memory text is readable and actions are secondary.
- [ ] Memory editor: keyboard does not cover Save; long text scrolls.
- [ ] Reaction/color sheets: tap targets, selection, labels, scoped loading.
- [ ] Reports: chart/distribution values have accessible summaries.
- [ ] Settings: destructive actions are clearly separated and confirmed.
- [ ] Light mode and dark mode have readable text, contrast, and adaptive
      colors.
- [ ] Dynamic Type is checked at a large accessibility size.
- [ ] VoiceOver labels include date, today/selected, memory, reaction, and
      color state.
- [ ] Reduce Motion does not make core actions confusing.
- [ ] Small iPhone width, regular iPhone, Pro Max, and supported iPad have no
      clipping or overlap.
- [ ] Landscape does not produce catastrophic overlap if supported.

## Release evidence record

| Field | Value |
| --- | --- |
| Build version | |
| Commit | |
| Supabase project/environment | |
| Device A / iOS | |
| Device B / iOS | |
| Account A/B/C identifiers | Do not record passwords or tokens |
| APNs environment | |
| Widget families checked | |
| Evidence links/IDs | |
| Tester/date | |

## Existing backlog retained from Prompts 1–9

- [ ] Two real users invite/pairing.
- [ ] Partner memory visibility and remote memory CRUD.
- [ ] Two-account reaction/day-color visibility.
- [ ] Two-device Realtime.
- [ ] APNs registration, delivery, and deep link.
- [ ] Development/TestFlight APNs behavior.
- [ ] App Group signing and real Home Screen widget.
- [ ] Widget refresh/privacy/deep link.
- [ ] Completed-period report data, cron boundaries, persistence, zero-data,
      and two-account report RLS.
