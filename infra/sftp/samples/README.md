# Supplier feed samples

These CSV files are copied into the SFTP user's `inbound/` folder every time
the `sftp` container starts (see `../init/seed-inbound.sh`). The
`supplier-sync` batch application polls that folder.

`techsource-supplier_20261101.csv` contains three bad rows on purpose, so the
batch job's error handling can be shown:

| Row | Problem | Expected handling |
|-----|---------|-------------------|
| `SPK-9999` | SKU does not exist in `inventory.products` | Record fails (FK violation), file continues |
| `TS-CAM-4K` | Negative quantity | Rejected by validation before the DB step |
| `TS-HUB-7` | `unit_cost` is not a number | Rejected by validation before the DB step |

The remaining rows load normally, and the run ends as `COMPLETED_WITH_ERRORS`
in `inventory.supplier_sync_runs`.
