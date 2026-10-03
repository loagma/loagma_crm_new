<?php

namespace App\Support;

/**
 * The legacy shared tables on prod (`user`, `deli_staff`) use the latin1
 * charset. A value with characters outside latin1 (Hindi/Devanagari, emoji…)
 * is rejected by MariaDB in strict mode with a raw 500 — so the CRM checks
 * first and answers with a readable 422 instead.
 */
class Latin1
{
    public static function fits(?string $value): bool
    {
        if ($value === null || $value === '') {
            return true;
        }
        $converted = @mb_convert_encoding($value, 'ISO-8859-1', 'UTF-8');
        return mb_convert_encoding($converted, 'UTF-8', 'ISO-8859-1') === $value;
    }

    /**
     * Field names (from $fields) whose value in $data can't be stored in a
     * latin1 column.
     *
     * @return list<string>
     */
    public static function badFields(array $data, array $fields): array
    {
        return array_values(array_filter($fields, fn ($f) => isset($data[$f]) && is_string($data[$f]) && !self::fits($data[$f])));
    }
}
