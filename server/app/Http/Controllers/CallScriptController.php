<?php

namespace App\Http\Controllers;

use App\Models\CallScript;
use Illuminate\Http\JsonResponse;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Per-telecaller call scripts (talking points). Each telecaller manages their
 * own list. On first open (none yet) a default set is seeded so the screen is
 * never empty.
 */
class CallScriptController extends Controller
{
    private function mobile(): string
    {
        return (string) JWTAuth::parseToken()->authenticate()->mobile;
    }

    private const DEFAULTS = [
        ['title' => 'Opening / Introduction', 'stage_label' => 'Opening', 'lines' => [
            'Greet by name and introduce yourself + Loagma.',
            'Confirm you are speaking to the decision maker.',
            'State the reason for the call in one sentence.',
            'Ask permission for 2 minutes of their time.',
        ]],
        ['title' => 'Qualifying the Lead', 'stage_label' => 'Qualify', 'lines' => [
            'Ask what products they currently stock.',
            'Understand their monthly order volume.',
            'Identify who places orders and how often.',
            'Note any current supplier pain points.',
        ]],
        ['title' => 'Pitch / Value', 'stage_label' => 'Pitch', 'lines' => [
            'Match 1-2 benefits to their stated needs.',
            'Mention pricing/credit terms briefly.',
            'Share a quick nearby success example.',
            'Keep it short - invite questions.',
        ]],
        ['title' => 'Handling Objections', 'stage_label' => 'Objections', 'lines' => [
            '"Price is high" -> highlight margin + credit terms.',
            '"Already have supplier" -> offer trial order.',
            '"No time" -> schedule a callback.',
            'Acknowledge first, then respond.',
        ]],
        ['title' => 'Closing', 'stage_label' => 'Close', 'lines' => [
            'Summarise what was agreed.',
            'Confirm the next step (order / visit / callback).',
            'Set a clear follow-up date.',
            'Thank them and end on a positive note.',
        ]],
    ];

    public function index(): JsonResponse
    {
        $mobile = $this->mobile();

        if (CallScript::where('employee_mobile', $mobile)->count() === 0) {
            foreach (self::DEFAULTS as $i => $d) {
                CallScript::create([
                    'employee_mobile' => $mobile,
                    'title'           => $d['title'],
                    'stage_label'     => $d['stage_label'],
                    'lines'           => $d['lines'],
                    'sort_order'      => $i,
                ]);
            }
        }

        $scripts = CallScript::where('employee_mobile', $mobile)
            ->orderBy('sort_order')->orderBy('id')->get();

        return response()->json(['success' => true, 'data' => $scripts]);
    }

    public function store(): JsonResponse
    {
        $mobile = $this->mobile();
        $data = $this->validatedInput();

        $script = CallScript::create(array_merge($data, ['employee_mobile' => $mobile]));

        return response()->json(['success' => true, 'data' => $script], 201);
    }

    public function update(string $id): JsonResponse
    {
        $mobile = $this->mobile();
        $script = CallScript::where('employee_mobile', $mobile)->where('id', $id)->first();
        if (!$script) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        $script->update($this->validatedInput());

        return response()->json(['success' => true, 'data' => $script]);
    }

    public function destroy(string $id): JsonResponse
    {
        $mobile = $this->mobile();
        $deleted = CallScript::where('employee_mobile', $mobile)->where('id', $id)->delete();

        return response()->json(['success' => (bool) $deleted]);
    }

    private function validatedInput(): array
    {
        return validator(request()->only(['title', 'stage_label', 'lines', 'sort_order']), [
            'title'       => 'required|string|max:191',
            'stage_label' => 'nullable|string|max:100',
            'lines'       => 'required|array|min:1',
            'lines.*'     => 'required|string|max:500',
            'sort_order'  => 'nullable|integer',
        ])->validate();
    }
}
