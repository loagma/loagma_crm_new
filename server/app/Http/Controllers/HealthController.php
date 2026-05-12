<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

class HealthController extends Controller
{
    public function index(Request $request)
    {
        $dbStatus = 'ok';
        $dbDetails = null;

        try {
            // Attempt to get a PDO instance to verify DB connectivity
            DB::connection()->getPdo();
        } catch (Throwable $e) {
            $dbStatus = 'error';
            $dbDetails = $e->getMessage();
            Log::error('Health check DB connection failed: '.$e->getMessage());
        }

        $payload = [
            'status' => $dbStatus === 'ok' ? 'ok' : 'degraded',
            'database' => $dbStatus === 'ok' ? ['status' => 'ok'] : ['status' => 'error', 'error' => $dbDetails],
            'timestamp' => now()->toIso8601String(),
        ];

        $statusCode = $dbStatus === 'ok' ? 200 : 503;

        return response()->json($payload, $statusCode);
    }
}
