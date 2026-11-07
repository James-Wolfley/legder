# Storage contract

## Required storage guarantees

- **Confirm when data is durable.** We need a way to write data and confirm
  that it will survive power loss. Confirmation that it merely reached a
  cache is insufficient.
- **Preserve a recovery copy during changes.** We need somewhere to retain
  durable recovery data that will survive an interrupted write or erase
  elsewhere. Our software chooses when that retained data is no longer needed.
- **Provide reliable reads and completion results.** Reads must return the
  stored data or indicate a problem. Storage must not report successful durable
  completion when persistence is uncertain. A failed operation may still have
  changed some data.

Legder is responsible for keeping the old recovery data until its replacement
is durable and can be selected during recovery. These requirements do not
demand atomic record writes.
