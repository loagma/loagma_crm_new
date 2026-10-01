<?php

namespace App\Support;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Location of an Indian pincode itself (not of any customer in it), from
 * OpenStreetMap Nominatim's postal-code search. Results are cached by the
 * caller in pincode_geo_crm, so each pincode is looked up once ever.
 *
 * Nominatim's usage policy: max 1 request/second and an identifying
 * User-Agent — lookupMany() spaces requests out accordingly.
 */
class PincodeGeocoder
{
    /** @return array{0: float, 1: float}|null [lat, lng] */
    public static function lookup(string $pincode): ?array
    {
        if (!preg_match('/^\d{6}$/', $pincode)) {
            return null;
        }

        $http = Http::timeout((int) config('telecaller.geocoder_timeout', 10))
            ->withHeaders(['User-Agent' => config('telecaller.geocoder_user_agent')]);
        if ($ca = config('telecaller.geocoder_ca')) {
            $http = $http->withOptions(['verify' => $ca]);
        }

        try {
            $res = $http->get(config('telecaller.geocoder_url'), [
                'postalcode' => $pincode,
                'country'    => 'India',
                'format'     => 'json',
                'limit'      => 1,
            ]);
        } catch (\Throwable $e) {
            Log::warning("Pincode geocode failed for $pincode: {$e->getMessage()}");
            return null;
        }

        $hit = $res->successful() ? ($res->json()[0] ?? null) : null;
        if (!$hit || !isset($hit['lat'], $hit['lon'])) {
            return null;
        }
        $lat = (float) $hit['lat'];
        $lng = (float) $hit['lon'];
        // Reject anything outside India — a postcode match in the wrong country.
        if ($lat < 6 || $lat > 38 || $lng < 68 || $lng > 98) {
            return null;
        }
        return [$lat, $lng];
    }

    /**
     * @param string[] $pincodes
     * @return array<string, array{0: float, 1: float}> found pincodes only
     */
    public static function lookupMany(array $pincodes): array
    {
        $out = [];
        foreach (array_values($pincodes) as $i => $pincode) {
            if ($i > 0) {
                usleep(1_100_000);
            }
            if ($p = self::lookup((string) $pincode)) {
                $out[(string) $pincode] = $p;
            }
        }
        return $out;
    }
}
