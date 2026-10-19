---
name: Flutter web preview refresh
description: Transient blank preview captures during Flutter web service-worker updates.
---

After rebuilding Flutter web, the first browser capture can occasionally be blank while the existing service worker updates. In this workspace the same mobile viewport rendered normally after a subsequent capture showed the new worker as active.

**Why:** The previous offline-first service worker can serve the prior web build during a rebuild; a blank initial capture did not indicate a layout failure.

**How to apply:** When preview requests return successfully but a Flutter screenshot is blank after a rebuild, check the browser log for service-worker update/activation and retry after activation before changing responsive UI code.
