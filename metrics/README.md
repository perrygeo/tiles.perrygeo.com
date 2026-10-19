# Metrics stack

Local Prometheus + Grafana stack for viewing the tiles server's Prometheus
metrics endpoint, `https://tiles.perrygeo.com/_/metrics`.

## Requirements

- Docker with the Compose plugin (`docker compose version`)

## Usage

From the repo root:

```bash
make watch-metrics   # start the stack, open the dashboard, tail logs
make metrics-down    # stop the stack
make metrics-clean   # stop the stack and delete its data volumes
```

`watch-metrics` runs `docker compose up --detach`, opens the Grafana dashboard
in your browser, and follows the container logs. **Ctrl-C only stops the log
stream** — the containers keep running in the background. Run `make
metrics-down` to stop them.

## URLs

| Service    | URL                                                     | Auth                        |
| ---------- | ------------------------------------------------------- | --------------------------- |
| Grafana    | <http://localhost:3000/d/martin-overview/martin-tile-server> | anonymous (viewer) / `admin` / `admin` |
| Prometheus | <http://localhost:9090>                                 | none (local)                |

Grafana anonymous access is enabled (viewer role) for one-click viewing; sign
in as `admin` / `admin` to edit panels or create new dashboards.

## Layout

```
compose.yaml                                        Prometheus + Grafana services
prometheus/prometheus.yml                           scrape config (targets tiles.perrygeo.com/_/metrics)
grafana/provisioning/datasources/prometheus.yml     auto-provisioned Prometheus datasource
grafana/provisioning/dashboards/dashboards.yml      file-based dashboard provider
grafana/dashboards/martin.json                      starter "Martin tile server" dashboard
```

## Notes

- The scrape target is hardcoded to the public `https://tiles.perrygeo.com/_/metrics`
  endpoint. The endpoint is public, so no credentials are needed.
- Metrics are scraped every 30s and kept in the `prometheus-data` volume, which
  persists across `make metrics-down` / `make watch-metrics`. Use
  `make metrics-clean` to wipe history.
- The provisioned dashboard is editable in the browser. Sign in as
  `admin` / `admin` (the anonymous user is a read-only viewer). Edits are saved
  to the `grafana-data` volume, so they persist across `make metrics-down` /
  `make watch-metrics`. Two caveats:
  - Editing `grafana/dashboards/martin.json` later will overwrite your
    browser edits on the next provisioning reload (the file is the source of
    truth).
  - `make metrics-clean` deletes `grafana-data`, wiping those edits.
  To reset just this dashboard to its file version, edit the JSON file (even a
  no-op change) and restart Grafana.
- Panels that use `rate(...[5m])` (request rate, duration percentiles, cache
  hit ratio) need ~5 minutes of scrape data before they start to render.
  Raw counters appear immediately.
