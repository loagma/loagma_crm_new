<?php

namespace App\Support;

use App\Models\DeliStaff;
use App\Models\InchargeAssign;

/**
 * Staff reporting hierarchy, resolved from incharge_assign_crm.
 *
 * That table is a generic parent → children edge list keyed by the parent's
 * mobile (stored in head_incharge_id as an int) with the children's mobiles in
 * incharge_ids. It applies at every level:
 *
 *   Head Incharge → Zonal Incharge → Area Incharge → Salesman
 *   Head Incharge → Zonal Incharge → Teleadmin     → Telecaller
 *
 * This is the same walk that AttendanceController / TelecallerController /
 * ComplaintController each carry a private copy of (getAssignedInchargeMobiles
 * + getDescendantMobiles); this class is the shared version. Those controllers
 * are intentionally left untouched for now — moving them onto this is a safe
 * follow-up, not part of introducing it.
 *
 * `admin` sits outside this tree (deli_staff has no hierarchy column and
 * admin is rarely a parent in incharge_assign_crm), so callers special-case
 * admin as "sees everything" — see subtreeForViewer().
 */
class Hierarchy
{
    /**
     * Mobiles of the children directly assigned to $parentMobile.
     *
     * @return list<string>
     */
    public static function childMobiles(string $parentMobile): array
    {
        $assign = InchargeAssign::where('head_incharge_id', (int) $parentMobile)->first();
        if (!$assign || empty($assign->incharge_ids)) {
            return [];
        }
        return array_map('strval', $assign->incharge_ids);
    }

    /**
     * Mobiles of ALL descendants below $parentMobile, walking the tree
     * recursively. One query per interior node; cycle-safe via $visited.
     * Matches the existing controller copies exactly — kept for parity where
     * that behaviour is load-bearing.
     *
     * @return list<string>
     */
    public static function descendantMobiles(string $parentMobile, array &$visited = []): array
    {
        if (isset($visited[$parentMobile])) {
            return [];
        }
        $visited[$parentMobile] = true;

        $descendants = [];
        foreach (self::childMobiles($parentMobile) as $childMobile) {
            $descendants[] = $childMobile;
            $descendants = array_merge(
                $descendants,
                self::descendantMobiles($childMobile, $visited)
            );
        }
        return array_values(array_unique($descendants));
    }

    /**
     * Same result as descendantMobiles() but with a single query: load the
     * whole (small) incharge_assign_crm table once and walk it in PHP. Use
     * this on request paths that resolve a subtree for a senior.
     *
     * @return list<string>
     */
    public static function descendantMobilesFast(string $parentMobile): array
    {
        // parent mobile => list<child mobile>
        $edges = [];
        foreach (InchargeAssign::all(['head_incharge_id', 'incharge_ids']) as $row) {
            $parent = (string) $row->head_incharge_id;
            $edges[$parent] = array_map('strval', $row->incharge_ids ?? []);
        }

        // $result is a list of mobile STRINGS. $seen/$visited only ever get
        // isset()-checked, so PHP coercing a numeric-string key to int there is
        // harmless — but never build the result from array_keys(), that would
        // hand back ints and break strict in_array() comparisons downstream.
        $result  = [];
        $seen    = [];
        $visited = [];
        $stack   = [(string) $parentMobile];
        while ($stack) {
            $node = (string) array_pop($stack);
            if (isset($visited[$node])) {
                continue;
            }
            $visited[$node] = true;
            foreach ($edges[$node] ?? [] as $child) {
                $child = (string) $child;
                if (!isset($seen[$child])) {
                    $seen[$child] = true;
                    $result[] = $child;
                }
                if (!isset($visited[$child])) {
                    $stack[] = $child;
                }
            }
        }
        return $result;
    }

    /**
     * The set of subordinate mobiles a viewer is allowed to see, or null when
     * the viewer is unrestricted (admin). An empty array means "a valid senior
     * with nobody assigned under them" — callers return an empty roster, not a
     * 403.
     *
     * @return list<string>|null
     */
    public static function subtreeForViewer(DeliStaff $viewer): ?array
    {
        if (strtolower(trim($viewer->role ?? '')) === 'admin') {
            return null;
        }
        return self::descendantMobilesFast((string) $viewer->mobile);
    }
}
