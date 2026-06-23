<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Http;

class PincodeController extends Controller
{
    /**
     * Proxy lookup against api.postalpincode.in.
     *
     * The public API is fronted by an expired TLS cert and is unreachable from
     * the Flutter web client (no dart:io, browser refuses the bad cert). The
     * server fetches it (verification disabled) and returns a normalized shape:
     *   { country, state, district, city, areas: [...] }
     */
    public function lookup(string $pincode): JsonResponse
    {
        $pincode = trim($pincode);
        if (!preg_match('/^\d{6}$/', $pincode)) {
            return response()->json(['success' => false, 'message' => 'Invalid pincode'], 422);
        }

        try {
            // A User-Agent is required — the API resets the connection without one.
            $response = Http::withoutVerifying()
                ->withHeaders(['User-Agent' => 'Mozilla/5.0 (LoagmaCRM)'])
                ->timeout(12)
                ->get("https://api.postalpincode.in/pincode/{$pincode}");

            if (!$response->successful()) {
                return response()->json(['success' => false, 'message' => 'Lookup failed'], 502);
            }

            $decoded = $response->json();
            $first = is_array($decoded) ? ($decoded[0] ?? null) : null;

            if (!is_array($first) || strtolower((string) ($first['Status'] ?? '')) === 'error') {
                return response()->json(['success' => false, 'message' => 'No data found'], 404);
            }

            $postOffices = $first['PostOffice'] ?? null;
            if (!is_array($postOffices) || count($postOffices) === 0) {
                return response()->json(['success' => false, 'message' => 'No data found'], 404);
            }

            $top = $postOffices[0];

            $clean = function ($raw): ?string {
                $s = trim((string) ($raw ?? ''));
                if ($s === '' || strtoupper($s) === 'NA' || strtoupper($s) === 'N/A') {
                    return null;
                }
                return $s;
            };

            $areas = collect($postOffices)
                ->map(fn ($po) => trim((string) ($po['Name'] ?? '')))
                ->filter(fn ($name) => $name !== '')
                ->unique()
                ->sort()
                ->values()
                ->all();

            // City: prefer Block → Division → District → first area name
            $city = $clean($top['Block'] ?? null)
                ?? $clean($top['Division'] ?? null)
                ?? $clean($top['District'] ?? null)
                ?? ($areas[0] ?? '');

            return response()->json([
                'success' => true,
                'data' => [
                    'country'  => $clean($top['Country'] ?? null) ?? 'India',
                    'state'    => $clean($top['State'] ?? null) ?? '',
                    'district' => $clean($top['District'] ?? null) ?? '',
                    'city'     => $city,
                    'areas'    => $areas,
                ],
            ]);
        } catch (\Throwable $e) {
            return response()->json(['success' => false, 'message' => 'Lookup error'], 502);
        }
    }
}
