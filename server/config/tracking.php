<?php

return [
    // How many days of location_pings_crm history to keep per employee.
    'retention_days' => (int) env('TRACKING_RETENTION_DAYS', 30),

    // A punched-in employee with no ping for this many hours (or whose
    // attendance date has rolled to a previous day) is auto-closed as
    // "forgot to punch out" the next time an admin views the live list.
    'autoclose_hours' => (int) env('TRACKING_AUTOCLOSE_HOURS', 6),

    // Optional OSRM server for road-snapping the display geometry of CLOSED
    // days in route history (TrackingController::route → RouteSnapper).
    // Empty/unset = snapping off entirely. The public demo server
    // (https://router.project-osrm.org) is acceptable for DEV ONLY — it has
    // no SLA and rate-limits; production should self-host OSRM or leave
    // this off. Snapping is cosmetic: distances always stay raw.
    'osrm_url' => env('OSRM_URL', ''),

    // OSRM routing profile. The public demo only hosts 'driving'; salesmen
    // ride bikes, so a self-hosted 'bike' profile matches reality better.
    'osrm_profile' => env('OSRM_PROFILE', 'driving'),

    // Per-request budget (seconds). A slow/unreachable OSRM must never fail
    // or meaningfully delay the history endpoint — it just falls back raw.
    'osrm_timeout' => (int) env('OSRM_TIMEOUT', 3),

    // Optional CA bundle for the OSRM HTTPS call. Only needed where PHP's
    // curl has no system CA store (the Windows dev machine) — same pattern
    // as DB_SSL_CA. The repo-shipped ISRG Root X1 covers Let's Encrypt
    // hosts like the public demo server. Leave unset in the Docker image.
    'osrm_ca' => env('OSRM_CA', ''),

    // Max trace coordinates per /match request. The public demo server
    // rejects anything above 10 (TooBig — measured, not the documented
    // 100); raise to ~95 on a self-hosted OSRM for better fidelity.
    'osrm_chunk' => (int) env('OSRM_CHUNK', 10),
];
