-- Supports server-side delivery cleanup and recipient-oriented diagnostics.
create index if not exists notification_deliveries_by_recipient
on public.notification_deliveries (recipient_user_id, status);
