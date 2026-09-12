If SMTP is down the welcome email is lost permanently. The fix is a persisted outbox table plus a periodic retry job that re-sends failed emails.
