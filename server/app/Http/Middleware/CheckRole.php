<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;
use Tymon\JWTAuth\Facades\JWTAuth;
use Tymon\JWTAuth\Exceptions\JWTException;

class CheckRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        try {
            $staff = JWTAuth::parseToken()->authenticate();
        } catch (JWTException) {
            return response()->json(['success' => false, 'message' => 'Unauthorized.'], 401);
        }

        if (!in_array($staff->role, $roles, true)) {
            return response()->json(['success' => false, 'message' => 'Forbidden.'], 403);
        }

        return $next($request);
    }
}
