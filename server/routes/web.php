<?php

use App\Http\Controllers\HealthController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::get('/api/health', [HealthController::class, 'index']);

Route::get('/up', [HealthController::class, 'index']);
