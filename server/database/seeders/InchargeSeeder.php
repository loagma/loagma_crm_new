<?php

namespace Database\Seeders;

use App\Models\DeliStaff;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class InchargeSeeder extends Seeder
{
    /**
     * Seed 5 head incharges, 5 zonal incharges and 5 area incharges,
     * each with all profile fields filled. Idempotent — keyed by mobile.
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
        ];

        foreach ($levels as $role => $meta) {
            for ($i = 1; $i <= 5; $i++) {
                $loc    = $cities[$i - 1];
                $mobile = $meta['prefix'] . str_pad((string) $i, 4, '0', STR_PAD_LEFT); // e.g. 9000100001

                $staff = DeliStaff::updateOrCreate(
                    ['mobile' => $mobile],
                    [
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
                    ]
                );

                // `password` is guarded (not in $fillable) — set it directly.
                $staff->password = Hash::make('password123');
                $staff->save();
            }
        }
    }
}
