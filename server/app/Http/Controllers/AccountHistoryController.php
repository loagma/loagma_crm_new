<?php

namespace App\Http\Controllers;

use App\Models\ActionLog;
use App\Models\CallLog;
use App\Models\DeliStaff;
use App\Models\LeadsAccount;
use App\Services\KnowlarityService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Response;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Per-customer history for the unified worklist-visit screen. Unlike the
 * per-employee endpoints in TelecallerController, these are deliberately
 * scoped to ONE ACCOUNT and return every staff member's entries — a salesman
 * sees the telecaller's calls/notes for that shop and vice versa.
 */
class AccountHistoryController extends Controller
{
    private function mobile(): string
    {
        return (string) JWTAuth::parseToken()->authenticate()->mobile;
    }

    /** deli_staff.mobile => name for a set of mobiles. */
    private function staffNames($mobiles): array
    {
        $m = collect($mobiles)->filter()->unique()->values();
        if ($m->isEmpty()) return [];
        return DeliStaff::whereIn('mobile', $m)->pluck('name', 'mobile')->all();
    }

    // ── Log History ─────────────────────────────────────────────────────────────
    public function actionLogs(string $accountId): JsonResponse
    {
        $this->mobile(); // auth

        $rows = ActionLog::where('account_id', $accountId)
            ->orderByDesc('check_out_at')
            ->orderByDesc('created_at')
            ->limit(200)
            ->get();

        $names = $this->staffNames($rows->pluck('employee_mobile'));

        $data = $rows->map(fn (ActionLog $r) => [
            'id'                 => $r->id,
            'role'               => $r->role,
            'staff_mobile'       => $r->employee_mobile,
            'staff_name'         => $names[$r->employee_mobile] ?? $r->employee_mobile,
            'check_in_at'        => optional($r->check_in_at)->toIso8601String(),
            'check_out_at'       => optional($r->check_out_at)->toIso8601String(),
            'duration_seconds'   => $r->duration_seconds,
            'check_in_lat'       => $r->check_in_lat,
            'check_in_lng'       => $r->check_in_lng,
            'check_out_lat'      => $r->check_out_lat,
            'check_out_lng'      => $r->check_out_lng,
            'status'             => $r->status,
            'outcome_slug'       => $r->outcome_slug,
            'outcome_name'       => $r->outcome_name,
            'general_notes'      => $r->general_notes,
            'notes_related_to'   => $r->notes_related_to,
            'images'             => $r->images ?? [],
            'call_outcome'       => $r->call_outcome,
            'call_status'        => $r->call_status,
            'is_invalid_call'    => $r->is_invalid_call,
            'call_log_id'        => $r->call_log_id,
            'conversation_notes' => $r->conversation_notes,
            'discussion_points'  => $r->discussion_points,
            'customer_stage'     => $r->customer_stage,
            'funnel_stage'       => $r->funnel_stage,
            'payment_collected'  => $r->payment_collected,
            'payment_mode'       => $r->payment_mode,
            'market_note'        => $r->market_note,
            'follow_up_date'     => optional($r->follow_up_date)->toDateString(),
            'follow_up_note'     => $r->follow_up_note,
            'created_at'         => optional($r->created_at)->toIso8601String(),
        ])->values();

        return response()->json(['success' => true, 'data' => $data]);
    }

    // ── Call History ────────────────────────────────────────────────────────────
    public function callHistory(string $accountId): JsonResponse
    {
        $this->mobile(); // auth

        $logs = CallLog::where('account_id', $accountId)
            ->orderByDesc('called_at')
            ->limit(200)
            ->get();

        $names = $this->staffNames($logs->pluck('employee_mobile'));

        $data = $logs->map(function (CallLog $l) use ($names) {
            $raw = $l->raw_payload ?? [];
            return [
                'id'               => $l->id,
                'staff_mobile'     => $l->employee_mobile,
                'staff_name'       => $names[$l->employee_mobile] ?? $l->employee_mobile,
                'outcome'          => $l->call_outcome,
                'notes'            => $l->notes,
                'called_at'        => optional($l->called_at)->toIso8601String(),
                'source'           => $l->source,
                'direction'        => $l->direction,
                'duration_seconds' => $l->duration_seconds,
                'has_recording'    => !empty($l->recording_url),
                'call_uuid'        => $l->knowlarity_call_id,
                'sr_number'        => $raw['knowlarity_number'] ?? null,
            ];
        })->values();

        return response()->json(['success' => true, 'data' => $data]);
    }

    /**
     * Streams a recording for a call that belongs to $accountId — the
     * account-scoped counterpart of TelecallerController::callRecording, so a
     * salesman can play a telecaller's recording for the same shop. Access is
     * gated on the call being for this account (any staff), not on ownership.
     */
    public function callRecording(string $accountId, string $id, KnowlarityService $knowlarity): Response
    {
        $this->mobile(); // auth

        $log = CallLog::where('id', $id)->where('account_id', $accountId)->first();
        if (!$log || !$log->recording_url) {
            abort(404, 'Recording not found');
        }

        [$bytes, $contentType] = $knowlarity->fetchRecording($log->recording_url);
        if ($bytes === '') {
            abort(502, 'Could not fetch recording');
        }
        if (!$contentType || str_contains($contentType, 'octet-stream')) {
            $contentType = 'audio/mpeg';
        }

        $disposition = request()->boolean('download')
            ? "attachment; filename=\"call-recording-{$id}.mp3\""
            : 'inline';

        return response($bytes, 200, [
            'Content-Type'        => $contentType,
            'Content-Length'      => (string) strlen($bytes),
            'Content-Disposition' => $disposition,
        ]);
    }

    // ── Account Details (ledger) ───────────────────────────────────────────────
    /**
     * Best-effort financial snapshot for a customer, derived from the legacy
     * `orders` table (there is no ledger table). Leads return is_customer:false.
     */
    public function ledger(string $accountId): JsonResponse
    {
        $this->mobile(); // auth

        $accountType = request()->query('account_type');

        // A real customer's account_id IS user.userid. A lead has no user row.
        $user = DB::table('user')->where('userid', $accountId)->first(['userid']);
        if ($accountType === 'lead' || !$user) {
            return response()->json([
                'success'     => true,
                'is_customer' => false,
                'data'        => null,
            ]);
        }

        $orders = DB::table('orders')
            ->where('buyer_userid', $accountId)
            ->orderByDesc('order_id')
            ->get(['order_id', 'order_total', 'bill_amount', 'payment_status', 'order_state', 'amountReceivedInfo', 'short_datetime', 'start_time']);

        $today = Carbon::today();
        $unpaidStatuses = ['not_paid', 'pending', 'partially_paid'];

        $lifetimeValue = 0.0;
        $orderCount    = 0;
        $outstanding   = 0.0;
        $aging = ['d0_30' => 0.0, 'd31_60' => 0.0, 'd60_plus' => 0.0];
        $invoices = [];
        $firstAt = null;
        $lastAt  = null;

        foreach ($orders as $o) {
            $total    = (float) ($o->order_total ?: $o->bill_amount ?: 0);
            $received = $this->receivedAmount($o->amountReceivedInfo);
            $balance  = max(0.0, round($total - $received, 2));
            $date     = $this->parseOrderDate($o->short_datetime, $o->start_time);

            $orderCount++;
            $lifetimeValue += $total;
            if ($date) {
                if (!$firstAt || $date->lt($firstAt)) $firstAt = $date;
                if (!$lastAt || $date->gt($lastAt))   $lastAt = $date;
            }

            $isUnpaid = in_array(strtolower((string) $o->payment_status), $unpaidStatuses, true) && $balance > 0.009;
            if ($isUnpaid) {
                $outstanding += $balance;
                $ageDays = $date ? $date->diffInDays($today) : 0;
                if ($ageDays <= 30)      $aging['d0_30']    += $balance;
                elseif ($ageDays <= 60)  $aging['d31_60']   += $balance;
                else                     $aging['d60_plus'] += $balance;
            }

            $invoices[] = [
                'order_id'       => (string) $o->order_id,
                'date'           => $date?->toIso8601String(),
                'total'          => round($total, 2),
                'received'       => round($received, 2),
                'balance'        => $balance,
                'payment_status' => $o->payment_status,
                'order_state'    => $o->order_state,
            ];
        }

        return response()->json([
            'success'     => true,
            'is_customer' => true,
            'data'        => [
                'outstanding'     => round($outstanding, 2),
                'lifetime_value'  => round($lifetimeValue, 2),
                'order_count'     => $orderCount,
                'avg_order_value' => $orderCount ? round($lifetimeValue / $orderCount, 2) : 0,
                'first_order_at'  => $firstAt?->toIso8601String(),
                'last_order_at'   => $lastAt?->toIso8601String(),
                'aging'           => array_map(fn ($v) => round($v, 2), $aging),
                'invoices'        => array_slice($invoices, 0, 100),
            ],
        ]);
    }

    /** cash + online + bank collected on an order, parsed from amountReceivedInfo JSON. */
    private function receivedAmount(?string $json): float
    {
        $info = json_decode((string) $json, true);
        if (!is_array($info)) return 0.0;
        return (float) (($info['cash'] ?? 0) + ($info['online'] ?? 0) + ($info['bank'] ?? 0)
            + ($info['rate_discount'] ?? 0) + ($info['returns'] ?? 0) + ($info['out_of_stock'] ?? 0));
    }

    /** "03-Jul-25 03:44 PM" (short_datetime) or a real start_time -> Carbon|null. */
    private function parseOrderDate(?string $short, $startTime): ?Carbon
    {
        foreach (['d-M-y h:i A', 'd-M-Y h:i A', 'd-M-y H:i', 'd M y h:i A'] as $fmt) {
            try {
                if ($short) return Carbon::createFromFormat($fmt, trim($short));
            } catch (\Throwable $e) {
                // try next
            }
        }
        try {
            return $startTime ? Carbon::parse($startTime) : null;
        } catch (\Throwable $e) {
            return null;
        }
    }
}
