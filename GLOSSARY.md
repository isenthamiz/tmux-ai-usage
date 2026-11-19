# Glossary

**Provider**: An AI coding agent whose plan quota the plugin reports on: Claude, Codex, or Cursor. One account per provider.

**Plan quota**: The usage allowance granted by a provider's subscription plan, measured within a quota window. Distinct from *spend* (money or tokens against a self-set budget) and *session context* (how full one conversation's context window is), neither of which the plugin reports.

**Quota window**: A period over which a plan quota is measured and after which it resets (e.g. a rolling 5-hour window, a weekly window, a monthly billing cycle). A provider may have several concurrent windows.

**Usage**: The fraction of a quota window's plan quota consumed so far.

**Reset**: The moment a quota window's usage returns to zero.

**Usage bar**: The status-line rendering of one quota window's usage, together with time until reset.

**Usage snapshot**: One provider's usage across all its quota windows as read at a single moment, together with when it was read and whether the reading succeeded. Usage bars are always drawn from a usage snapshot, never from a provider directly.

**Window label**: The short name of a quota window, derived from its length and, for model-scoped windows, the model (e.g. `5h`, `wk`, `mo`, `wk-opus`), so the same window kind has the same name across providers. Used both on the usage bar and when choosing which window a usage bar shows.

**Snapshot status**: Whether a usage snapshot's reading succeeded, and if not, why: `ok`; `signed_out` (the provider no longer accepts the user's sign-in); `missing_dep` (something the reader needs isn't available on this machine); `bad_shape` (the provider answered in a form the plugin doesn't understand); `error` (a transient failure expected to clear by itself). A failed reading keeps the last good usage alongside its status.

**Stale**: A usage snapshot whose last good reading is too old to trust. Staleness is judged at the moment of drawing, not recorded in the snapshot.

**Pending**: A provider for which no usage snapshot exists yet.
