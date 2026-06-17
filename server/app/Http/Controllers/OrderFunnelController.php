<?php

namespace App\Http\Controllers;

use App\Models\OrderFunnel;
use App\Models\OrderFunnelResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Str;
use Tymon\JWTAuth\Facades\JWTAuth;

class OrderFunnelController extends Controller
{
    private function authMobile(): string
    {
        return JWTAuth::parseToken()->authenticate()->mobile;
    }

    /** List active funnel stages (dynamic source for the Order Funnel UI). */
    public function options(): JsonResponse
    {
        $options = OrderFunnel::where('is_active', true)
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get(['id', 'slug', 'name', 'sort_order']);

        return response()->json(['success' => true, 'data' => $options]);
    }

    /** Latest saved funnel response for an account (used to prefill the form). */
    public function latestResponse(): JsonResponse
    {
        $mobile    = $this->authMobile();
        $accountId = request()->query('account_id');

        $response = OrderFunnelResponse::where('employee_mobile', $mobile)
            ->when($accountId, fn ($q) => $q->where('account_id', $accountId))
            ->orderBy('created_at', 'desc')
            ->first();

        return response()->json(['success' => true, 'data' => $response]);
    }

    /**
     * Save a funnel response for an account. Persisted only at "Visit Out" —
     * stores the final funnel selection plus visit timing and images.
     */
    public function store(): JsonResponse
    {
        $mobile = $this->authMobile();

        $data = request()->only([
            'account_id', 'account_type', 'beat_plan_id',
            'visit_in_at', 'visit_out_at', 'duration_seconds',
            'funnel_slug', 'general_notes', 'notes_related_to', 'images',
        ]);

        $validated = validator($data, [
            'account_id'       => 'required|string|max:191',
            'account_type'     => 'nullable|in:lead,customer',
            'beat_plan_id'     => 'nullable|integer',
            'visit_in_at'      => 'nullable|date',
            'visit_out_at'     => 'nullable|date',
            'duration_seconds' => 'nullable|integer|min:0',
            'funnel_slug'      => 'required|string|exists:order_funnel_crm,slug',
            'general_notes'    => 'nullable|string',
            'notes_related_to' => 'nullable|string|max:150',
            'images'           => 'nullable|array',
            'images.*'         => 'string|max:500',
        ])->validate();

        // Denormalise the display label so history reads well even if options change.
        $funnel = OrderFunnel::where('slug', $validated['funnel_slug'])->firstOrFail();

        $response = OrderFunnelResponse::create([
            ...$validated,
            'employee_mobile' => $mobile,
            'funnel_name'     => $funnel->name,
        ]);

        return response()->json(['success' => true, 'data' => $response], 201);
    }

    /** Upload a single funnel image; returns its stored relative path. */
    public function uploadImage(): JsonResponse
    {
        $validated = request()->validate([
            'image' => 'required|image|mimes:jpg,jpeg,png,webp|max:5120',
        ]);

        $file = $validated['image'];
        $name = 'funnel_' . Str::uuid()->toString() . '.' . $file->getClientOriginalExtension();
        $path = $file->storeAs('order_funnels', $name, 'public');

        return response()->json([
            'success' => true,
            'path'    => '/storage/' . $path,
        ]);
    }
}
