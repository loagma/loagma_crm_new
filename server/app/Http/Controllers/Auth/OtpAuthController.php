<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\DeliStaff;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Tymon\JWTAuth\Facades\JWTAuth;
use Tymon\JWTAuth\Exceptions\JWTException;

class OtpAuthController extends Controller
{
    public function sendOtp(Request $request): JsonResponse
    {
        $request->validate(['mobile' => 'required|string|max:20']);

        $staff = DeliStaff::where('mobile', $request->mobile)->first();

        if (!$staff) {
            return response()->json([
                'success' => false,
                'message' => 'Mobile number not registered.',
            ], 404);
        }

        $otp = str_pad((string) random_int(1000, 9999), 4, '0', STR_PAD_LEFT);

        $staff->update([
            'password' => $otp,
        ]);

        Log::info("OTP for {$request->mobile}: $otp");

        return response()->json([
            'success' => true,
            'message' => 'OTP sent successfully.',
        ]);
    }

    public function verifyOtp(Request $request): JsonResponse
    {
        $request->validate([
            'mobile' => 'required|string|max:20',
            'otp'    => 'required|string|max:6',
        ]);

        $staff = DeliStaff::where('mobile', $request->mobile)->first();

        if (!$staff) {
            return response()->json([
                'success' => false,
                'message' => 'Mobile number not registered.',
            ], 404);
        }

        $isValidOtp = $staff->password === $request->otp;

        if (!$isValidOtp) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid OTP.',
            ], 401);
        }

        try {
            $token = JWTAuth::fromUser($staff);
        } catch (JWTException) {
            return response()->json([
                'success' => false,
                'message' => 'Could not create token.',
            ], 500);
        }

        return response()->json([
            'success' => true,
            'message' => 'Login successful.',
            'token'   => $token,
            'data'    => [
                'id'     => $staff->id,
                'name'   => $staff->name,
                'mobile' => $staff->mobile,
                'role'   => $staff->role,
            ],
        ]);
    }

    public function me(): JsonResponse
    {
        $staff = JWTAuth::parseToken()->authenticate();

        return response()->json([
            'success' => true,
            'data'    => [
                'id'     => $staff->id,
                'name'   => $staff->name,
                'mobile' => $staff->mobile,
                'role'   => $staff->role,
            ],
        ]);
    }

    public function logout(): JsonResponse
    {
        try {
            JWTAuth::invalidate(JWTAuth::getToken());
        } catch (JWTException) {
            // token already invalid
        }

        return response()->json([
            'success' => true,
            'message' => 'Logged out successfully.',
        ]);
    }
}
