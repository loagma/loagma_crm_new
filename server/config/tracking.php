<?php

return [
    // How many days of location_pings_crm history to keep per employee.
    'retention_days' => (int) env('TRACKING_RETENTION_DAYS', 30),

    // A punched-in employee with no ping for this many hours (or whose
    // attendance date has rolled to a previous day) is auto-closed as
    // "forgot to punch out" the next time an admin views the live list.
    'autoclose_hours' => (int) env('TRACKING_AUTOCLOSE_HOURS', 6),
];
