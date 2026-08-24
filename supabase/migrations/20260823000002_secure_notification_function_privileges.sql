-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default. Keep every
-- notification helper private, then expose only the four authenticated inbox
-- actions through an explicit allow-list.

revoke all on function public.insert_user_notification(
  uuid, uuid, text, text, text, text, text, text, uuid, jsonb,
  boolean, uuid, text, timestamptz
) from public, anon, authenticated;

revoke all on function public.notify_incident_event() from public, anon, authenticated;
revoke all on function public.notify_schedule_event() from public, anon, authenticated;
revoke all on function public.notify_assignment_event() from public, anon, authenticated;
revoke all on function public.notify_profile_event() from public, anon, authenticated;
revoke all on function public.notify_shift_request_event() from public, anon, authenticated;
revoke all on function public.notify_accomplishment_event() from public, anon, authenticated;
revoke all on function public.notify_platform_announcement() from public, anon, authenticated;

revoke all on function public.mark_notification_read(uuid) from public, anon, authenticated;
revoke all on function public.acknowledge_notification(uuid) from public, anon, authenticated;
revoke all on function public.mark_all_notifications_read() from public, anon, authenticated;
revoke all on function public.send_broadcast_notification(text, text, text, text, boolean)
  from public, anon, authenticated;

grant execute on function public.mark_notification_read(uuid),
  public.acknowledge_notification(uuid),
  public.mark_all_notifications_read(),
  public.send_broadcast_notification(text, text, text, text, boolean)
to authenticated;

