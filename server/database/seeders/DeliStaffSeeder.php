<?php

namespace Database\Seeders;

use App\Models\DeliStaff;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DeliStaffSeeder extends Seeder
{
    /**
     * Seed 5 staff for each role: salesman, telecaller, teleadmin,
     * head_incharge, zonal_incharge and area_incharge, with all profile
     * fields filled. Idempotent — keyed by mobile. Incharge mobiles match
     * InchargeSeeder so re-running either does not duplicate rows.
     */
    public function run(): void
    {
        $cities = [
            ['city' => 'Mumbai',    'state' => 'Maharashtra', 'pincode' => '400001', 'lat' => 19.0760, 'lng' => 72.8777],
            ['city' => 'Pune',      'state' => 'Maharashtra', 'pincode' => '411001', 'lat' => 18.5204, 'lng' => 73.8567],
            ['city' => 'Nagpur',    'state' => 'Maharashtra', 'pincode' => '440001', 'lat' => 21.1458, 'lng' => 79.0882],
            ['city' => 'Nashik',    'state' => 'Maharashtra', 'pincode' => '422001', 'lat' => 19.9975, 'lng' => 73.7898],
            ['city' => 'Aurangabad','state' => 'Maharashtra', 'pincode' => '431001', 'lat' => 19.8762, 'lng' => 75.3433],
        ];

        // role => [mobile prefix, names]
        $levels = [
            'head_incharge'  => [
                'prefix' => '900010',
                'names'  => ['Rajesh Sharma', 'Amit Patel', 'Suresh Iyer', 'Vikram Singh', 'Anil Deshmukh'],
            ],
            'zonal_incharge' => [
                'prefix' => '900020',
                'names'  => ['Sanjay Kulkarni', 'Manoj Verma', 'Deepak Joshi', 'Prakash Gupta', 'Ravi Nair'],
            ],
            'area_incharge'  => [
                'prefix' => '900030',
                'names'  => ['Nitin More', 'Sachin Pawar', 'Yogesh Jadhav', 'Kiran Bhosale', 'Mahesh Shinde'],
            ],
            'salesman'       => [
                'prefix' => '900040',
                'names'  => ['Arjun Mehta', 'Rohit Chavan', 'Vishal Kadam', 'Ganesh Thorat', 'Sunil Gaikwad'],
            ],
            'telecaller'     => [
                'prefix' => '900050',
                'names'  => ['Priya Desai', 'Sneha Kulkarni', 'Pooja Patil', 'Anjali Rane', 'Kavita Salunkhe'],
            ],
            'teleadmin'      => [
                'prefix' => '900060',
                'names'  => ['Neha Joshi', 'Swati Bhagat', 'Rekha Naik', 'Meena Sawant', 'Asha Kamble'],
            ],
        ];

        // deli_id has no default / auto-increment on the live table — allocate manually.
        $nextId = (int) DeliStaff::max('deli_id') + 1;

        foreach ($levels as $role => $meta) {
            for ($i = 1; $i <= 5; $i++) {
                $loc    = $cities[$i - 1];
                $mobile = $meta['prefix'] . str_pad((string) $i, 4, '0', STR_PAD_LEFT); // e.g. 9000400001

                $staff = DeliStaff::firstOrNew(['mobile' => $mobile]);

                if (! $staff->exists) {
                    $staff->deli_id = $nextId++;
                }

                $staff->fill([
                    'name'              => $meta['names'][$i - 1],
                    'role'              => $role,
                    'admin_id'          => 1,
                    'pincode'           => $loc['pincode'],
                    'city'              => $loc['city'],
                    'state'             => $loc['state'],
                    'lat'               => $loc['lat'],
                    'lng'               => $loc['lng'],
                    'is_locked'         => false,
                    'punch_in_time'     => '09:00:00',
                    'punch_out_time'    => '18:00:00',
                    'grace_minutes'     => 15,
                    'approval_required' => true,
                ]);

                // `password` is guarded (not in $fillable) — set it directly.
                $staff->password = Hash::make('password123');
                $staff->save();
            }
        }
    }
}
