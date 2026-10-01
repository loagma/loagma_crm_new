<?php

return [
    // Pincodes whose points are within this many km of each other are grouped
    // into one internal cluster when ordering a telecaller's plan.
    'allocation_cluster_km' => (float) env('TC_ALLOCATION_CLUSTER_KM', 5.0),

    // Longest From–To range (days, inclusive) a telecaller can pick for a plan.
    'allocation_max_days' => (int) env('TC_ALLOCATION_MAX_DAYS', 366),

    // Pincode → location lookup (OpenStreetMap Nominatim postal-code search).
    // Customer coordinates are never used to place a pincode.
    'geocoder_url'        => env('PINCODE_GEOCODER_URL', 'https://nominatim.openstreetmap.org/search'),
    'geocoder_user_agent' => env('PINCODE_GEOCODER_UA', 'loagma-crm/1.0 (telecaller pincode allocation)'),
    'geocoder_timeout'    => (int) env('PINCODE_GEOCODER_TIMEOUT', 10),
    // Same Let's Encrypt root as OSRM — Windows PHP needs it passed explicitly.
    'geocoder_ca'         => env('PINCODE_GEOCODER_CA', env('OSRM_CA', '')),
];
