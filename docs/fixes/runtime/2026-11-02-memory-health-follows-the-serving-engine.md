# Memory health follows the serving engine

`mimir.sh memory` now reads the active bridge's health record instead of opening
a client-side SQLite file. This keeps borrowed memory and cross-platform clients
on the serving engine's database and WAL. Offline checks still inspect the local
file. An incomplete or failed bridge health response fails explicitly; transport
availability never overrides the engine's unhealthy result.

The policy self-test supplies its existing fixed clock to date canonicalization,
so the relative-date assertion remains meaningful after the fixture's date.

Validation: `bin/records/test_mimir_bridge_health.py` covers unhealthy, healthy,
incomplete and unavailable bridge responses. Run the policy self-test and shell
syntax check alongside it. No store migration or record replacement is involved.
