# CoupleCalender Release Readiness

Audit date: 2026-09-12
Repository: qhmetselim/CoupleCalender
Current app version/build: 1.0 (1)
Main bundle: asa.CoupleCalender
Widget bundle: asa.CoupleCalender.CoupleCalenderWidget
Deployment target: iOS 26.1
Target family: iPhone + iPad

## Executive decision

The codebase has a successful unsigned simulator Release build and the main
automated tests pass. It is not yet ready for a signed TestFlight/App Store
submission.

The remaining distribution blocker is Apple signing/provisioning for the
application group and push entitlements. APNs credentials and physical-device
delivery are also not verified in this environment. These are external
configuration and QA requirements, not reasons to disable the capabilities in
the project.

## Status classification

### RELEASE BLOCKER

1. A normally signed iOS archive was attempted and failed because the current
   provisioning profile does not contain:
   - com.apple.security.application-groups
   - group.asa.CoupleCalender
   - aps-environment

   The project entitlements are intentionally retained. Complete the Apple
   Developer setup below, refresh/recreate profiles, and rerun the archive.
2. APNs production credentials and a real-device delivery test are not
   verified. The server function is deployed, but no successful production
   delivery is claimed.
3. Account deletion is implemented as a protected Edge Function and exposed
   in Account Settings, but destructive end-to-end verification with a
   disposable real account is still required before release.
4. The App Store Connect privacy questionnaire, privacy policy/support URLs,
   and final store metadata must be completed by the product owner. The
   repository contains the factual data inventory needed for that submission,
   not the store submission itself.

Apple requires apps that support account creation to provide an in-app way for
users to initiate account deletion:
[Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

### MANUAL QA REQUIRED

- Two real accounts: pairing, partner visibility, leave/unpair, re-pair.
- Remote memory create/edit/delete and owner/partner/unrelated-user RLS.
- Two-account reaction and day-color behavior.
- Two physical devices with Realtime updates and foreground reconciliation.
- APNs token registration, new-memory-only notification delivery, invalid-token
  cleanup, duplicate delivery protection, and notification tap navigation.
- Widget App Group signing, Home Screen installation, all three families, stale
  snapshot behavior, account switching, and sign-out/unpair cleanup.
- Completed historical monthly/yearly reports, zero-data reports, cron
  boundary behavior, snapshot persistence, and report RLS.
- Account deletion from Settings, including auth account removal, couple
  cleanup, device-token cleanup, and local widget/deep-link cleanup.
- Light/dark mode, Dynamic Type, VoiceOver, keyboard, iPad, and small-phone
  checks on real supported devices.

### NON-BLOCKING

- Supabase Performance Advisor currently reports unused indexes in the
  development project. This is expected with little traffic and does not
  indicate a correctness issue.
- Security Advisor reports private.partner_invites as RLS-enabled without a
  policy. This is intentional: the schema is private and the table is not
  granted to API roles. It is not an exposed user-data table.
- appintentsmetadataprocessor has no App Intents to process; no App Intents
  are in scope.
- The UI test diagnostic collection emitted a simctl lookup warning because
  that invocation did not inherit DEVELOPER_DIR; the UI test itself passed.
- Supabase CLI 2.116.0 reports 2.117.0 available. Updating it is not required
  for this release audit.

## Automated evidence

### Xcode

- Main app Debug simulator build: SUCCEEDED.
- Main app Release simulator build: SUCCEEDED.
- Widget target is part of the main app build; the standalone
  CoupleCalenderWidget Release scheme also completed successfully.
- Unit tests: 17 passed.
- UI tests: passed.
- The main build embeds the widget extension and bundles both privacy
  manifests.
- A normally signed device archive was attempted; it failed only at Apple
  provisioning capability validation, as described above.

The local Xcode installation is selected explicitly with
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer because the machine's
default xcode-select path points to Command Line Tools.

### Dependency/toolchain inventory

- Supabase Swift SDK: 2.55.2, resolved in Package.resolved.
- Supabase CLI: 2.116.0.
- No new third-party dependency was added for the release audit.
- No deployment target, bundle identifier, target family, or marketing/build
  version was changed.

## Configuration and secrets

- Config/Local.xcconfig contains machine-local Supabase URL/publishable-key
  values and is ignored by Git.
- Config/Local.xcconfig.example is the shareable template.
- The app validates missing/invalid configuration and rejects strings that
  look like privileged keys.
- Only the Supabase publishable key is compiled into the app.
- No service-role key, Supabase secret key, APNs private key, webhook secret,
  password, or access/refresh token is compiled into the app or widget.
- The widget only reads a sanitized App Group snapshot. It never initializes
  Supabase and never receives an auth token.
- History and tracked-file scans found no PEM private key or sb_secret or
  service-role credential.

Server-side secret names that must be verified in the Supabase project (values
must never be committed or pasted into source) are:

- DATABASE_WEBHOOK_SECRET
- APNS_KEY_ID
- APNS_TEAM_ID
- APNS_BUNDLE_ID (asa.CoupleCalender)
- APNS_PRIVATE_KEY
- SUPABASE_SECRET_KEYS (preferred platform admin-key source) or the platform
  service-role secret used by the server functions

The database webhook URL and webhook secret are stored through the existing
server-side secret/Vault path. Do not place them in migrations or xcconfig.

## Privacy manifest and data inventory

Privacy manifests are present in both targets:

- CoupleCalender/PrivacyInfo.xcprivacy
- CoupleCalenderWidget/PrivacyInfo.xcprivacy

They declare no tracking and no collected data types. UserDefaults access is
declared with Apple reason codes for standard app defaults and App Group
defaults. See [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
and [describing required-reason API use](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_apis).

Factual product data inventory for App Store Connect:

- Supabase Auth: email address and account identifier.
- Profile: display name and optional schema-supported avatar value.
- Memories: user-authored memory content and date-only calendar day.
- Interactions: reaction canonical key/set, day-color key, timestamps, and
  actor/owner relationships.
- Device registration: APNs token, environment, app version, and timestamps.
- Reports: aggregate snapshot metrics; memory text is not copied into reports.
- Pairing: couple/membership/invite lifecycle data; invite code is stored as a
  hash, not plaintext.
- Widget: sanitized active-partner display name and up to seven memory previews
  with minimal decoration data. No auth or notification credentials.

The app has no ads, tracking SDK, social sharing service, or third-party
analytics framework in this repository. The App Store privacy answers must be
reviewed against the final deployed Supabase/Auth configuration before
submission.

## Account deletion

The final hardening change adds a minimal protected account-deletion flow:

- Account Settings presents a destructive confirmation.
- The app clears widget and pending deep-link data locally immediately.
- Device-token removal is best effort and cannot block deletion.
- delete-account requires the caller's bearer session and resolves the caller
  from Supabase Auth server-side; it does not trust a user ID in the request
  body.
- The function removes the caller's couple rows first, then deletes the Auth
  user through the server-side admin API. Existing foreign-key cascades remove
  the caller's profile-owned data.
- Generic errors are returned to the client; secrets and memory content are
  not logged.

The function is deployed to the development Supabase project with JWT
verification enabled. Do not test it against a real account unless that account
is intentionally disposable and its data has been backed up or is known to be
deletable.

## Supabase and database status

New migration:

supabase/migrations/20260912170855_20260912170813_final_release_hardening.sql

It was applied to the development Supabase project as remote migration
20260912170855. It:

- revokes API-role execute access to the legacy public rls_auto_enable helper
  while leaving the existing event-trigger helper intact;
- adds only targeted indexes for invite lookup and canonical reaction keys;
- hardens reaction and day-color delete policies with active-couple and
  real-memory authorization checks.

Existing report, pairing, Realtime, notification, and WidgetKit migrations were
not rewritten. No new schema was added solely for the UI audit.

Remote migration history and deployed Edge Function versions were checked
through the connected Supabase project. The active scheduled report jobs remain:

- couplecalender-monthly-reports: 15 2 1 * *
- couplecalender-yearly-reports: 30 2 1 1 *

Security Advisor has no new warning from this migration. The only remaining
security info is the intentional private-schema no-policy item described
above. Performance Advisor has only zero-traffic unused-index info and no
unindexed-FK warning.

The deployed functions are:

- send-memory-notification: active, custom webhook-secret verification.
- delete-account: active, Supabase JWT verification.

No APNs delivery is claimed until the required Apple credentials are present
and a physical-device test succeeds.

## Apple Developer and signing steps

The project intentionally declares App Group and push capabilities. Apple
capabilities must be enabled on the App IDs and reflected in provisioning
profiles; see [Enable app capabilities](https://developer.apple.com/help/account/configure-app-capabilities/enable-app-capabilities/).

1. In Certificates, Identifiers & Profiles, register the App Group
   group.asa.CoupleCalender.
2. Enable App Groups and Push Notifications on App ID
   asa.CoupleCalender.
3. Enable App Groups on App ID
   asa.CoupleCalender.CoupleCalenderWidget.
4. Confirm the widget App ID and bundle ID match
   asa.CoupleCalender.CoupleCalenderWidget.
5. Refresh or recreate development and distribution provisioning profiles so
   they contain the new entitlements. Automatic signing can then refresh them;
   do not remove entitlements to force an archive.
6. In Xcode, verify the main app and widget both show the App Group capability.
7. Create/refresh the App Store Connect app record, then archive with normal
   signing and validate/upload the archive.
8. Create an Apple APNs token-auth key and add its values only to Supabase
   server-side secrets. Never add the .p8 file to this repository.
9. Test development APNs on a development-signed physical device and
   production APNs with the appropriate TestFlight/App Store build.

Apple profile changes can require provisioning-profile refresh; see
[Updating provisioning profiles](https://developer.apple.com/help/account/provisioning-profiles/update-your-provisioning-profiles/).

## Release sign-off checklist

- [ ] Signed iOS archive succeeds with App Group and push entitlements.
- [ ] Archive validates and uploads to App Store Connect.
- [ ] Supabase server secrets are present and verified without exposing values.
- [ ] Two-account remote QA is complete.
- [ ] Two-device Realtime QA is complete.
- [ ] Physical-device APNs delivery and deep-link QA is complete.
- [ ] Widget App Group installation and privacy cleanup are complete.
- [ ] Account deletion is verified with a disposable account.
- [ ] Reports/cron/snapshot/RLS QA is complete.
- [ ] Store privacy answers, support URL, privacy policy, and review notes are
      complete.
- [ ] Final light/dark/accessibility/keyboard QA is complete.

## Current commit

The final release-hardening commit SHA is reported in the handoff after the
last verification commit.
