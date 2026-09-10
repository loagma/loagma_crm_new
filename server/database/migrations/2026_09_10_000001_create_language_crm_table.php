<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// Master list of languages a person speaks. Referenced (by name) from
// deli_staff.language and LeadsAccount_crm.language via a dropdown that reads
// GET /api/masters/languages.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('language_crm', function (Blueprint $table) {
            $table->id();
            $table->string('name', 100)->unique();
            $table->string('code', 10)->nullable();   // ISO 639-1 where available
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();
        });

        // Indian languages only — the 22 scheduled (8th Schedule) languages plus
        // English and the widely-spoken regional tongues, with "Other" last.
        $now  = now();
        $rows = [
            ['English', 'en'], ['Hindi', 'hi'], ['Bengali', 'bn'], ['Marathi', 'mr'],
            ['Telugu', 'te'], ['Tamil', 'ta'], ['Gujarati', 'gu'], ['Urdu', 'ur'],
            ['Kannada', 'kn'], ['Odia', 'or'], ['Malayalam', 'ml'], ['Punjabi', 'pa'],
            ['Assamese', 'as'], ['Maithili', 'mai'], ['Sanskrit', 'sa'], ['Konkani', 'kok'],
            ['Nepali', 'ne'], ['Sindhi', 'sd'], ['Dogri', 'doi'], ['Manipuri', 'mni'],
            ['Bodo', 'brx'], ['Santali', 'sat'], ['Kashmiri', 'ks'],
            ['Bhojpuri', 'bho'], ['Rajasthani', null], ['Chhattisgarhi', null], ['Haryanvi', null],
            ['Tulu', 'tcy'], ['Other', null],
        ];

        DB::table('language_crm')->insertOrIgnore(
            collect($rows)->values()->map(fn ($r, $i) => [
                'name'       => $r[0],
                'code'       => $r[1],
                'is_active'  => true,
                'sort_order' => $i,
                'created_at' => $now,
                'updated_at' => $now,
            ])->all()
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('language_crm');
    }
};
