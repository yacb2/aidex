---
name: reference-dev-mail-catchall
description: Development mail never leaves the machine
metadata:
  type: reference
---

Every project in the fleet points its SMTP settings at a shared local catch-all in development, so a message sent by any project during development is captured locally and delivered nowhere. A project whose settings name a real provider in development is misconfigured, not an exception.
