<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;
use Tymon\JWTAuth\Facades\JWTAuth;
use Tymon\JWTAuth\Exceptions\JWTException;

class JwtAuthenticate
{
    public function handle(Request $request, Closure $next): Response
    {
        try {
            if (!$request->hasHeader('Authorization')) {
                return response()->json(['success' => false, 'message' => 'Missing authorization header.'], 401);
            }
            JWTAuth::parseToken()->authenticate();
        } catch (JWTException $e) {
            return response()->json(['success' => false, 'message' => 'Unauthorized: ' . $e->getMessage()], 401);
        } catch (\Exception $e) {
            \Log::error('JWT Auth error', ['error' => $e->getMessage()]);
            return response()->json(['success' => false, 'message' => 'Authentication error.'], 401);
        }

        return $next($request);
    }
}
