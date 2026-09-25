#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/lib/common.sh"

# ============================================================
# PTERODACTYL PANEL INSTALLER
# PutzOfficial Installer
#
# PHP 8.3
# MariaDB
# Redis
# Nginx
# Composer
#
# AUTO EGG IMPORT
# - Egg NodeJS / Bot Vyro
# - Egg Python
#
# Egg source:
# https://raw.githubusercontent.com/rafswijdan80-cell/PutzInstaller/refs/heads/main/eggs/egg-bot-vyro.json
# https://raw.githubusercontent.com/rafswijdan80-cell/PutzInstaller/refs/heads/main/eggs/egg-python.json
#
# IMPORTANT:
# - Nest.author WAJIB diisi
# - Egg.author WAJIB diisi
# - Tidak membutuhkan API token
# - Tidak membuat Egg duplikat
# - Nama Egg dibaca langsung dari JSON
# - Nginx menggunakan folder /public
# ============================================================


# ============================================================
# GLOBAL EGG VARIABLES
# ============================================================

IMPORTED_NODEJS_EGG_NAME=""
IMPORTED_PYTHON_EGG_NAME=""


# ============================================================
# AUTO IMPORT EGG
# ============================================================

import_pterodactyl_eggs() {

    info "Memulai auto-import Egg Pterodactyl..."

    # ========================================================
    # ROOT CHECK
    # ========================================================

    if [[ "${EUID}" -ne 0 ]]; then
        error "Auto-import Egg harus dijalankan sebagai root."
        return 1
    fi

    # ========================================================
    # PANEL CHECK
    # ========================================================

    if [[ ! -f /var/www/pterodactyl/artisan ]]; then
        error "Pterodactyl Panel tidak ditemukan."
        return 1
    fi

    if [[ ! -f /var/www/pterodactyl/composer.json ]]; then
        error "composer.json Pterodactyl tidak ditemukan."
        return 1
    fi

    if ! command -v php >/dev/null 2>&1; then
        error "PHP tidak ditemukan."
        return 1
    fi

    # ========================================================
    # EGG URL
    # ========================================================

    local egg_nodejs_url="https://raw.githubusercontent.com/rafswijdan80-cell/PutzInstaller/refs/heads/main/eggs/egg-bot-vyro.json"

    local egg_python_url="https://raw.githubusercontent.com/rafswijdan80-cell/PutzInstaller/refs/heads/main/eggs/egg-python.json"

    local egg_dir="/tmp/putzofficial-eggs"

    mkdir -p "$egg_dir"

    # ========================================================
    # DOWNLOAD NODEJS EGG
    # ========================================================

    info "Mengambil Egg NodeJS..."

    if ! curl -fsSL \
        --retry 5 \
        --retry-delay 3 \
        --connect-timeout 20 \
        --max-time 180 \
        "$egg_nodejs_url" \
        -o "$egg_dir/egg-bot-vyro.json"; then

        error "Gagal mendownload Egg NodeJS."
        return 1
    fi

    if [[ ! -s "$egg_dir/egg-bot-vyro.json" ]]; then
        error "Egg NodeJS kosong."
        return 1
    fi

    # ========================================================
    # DOWNLOAD PYTHON EGG
    # ========================================================

    info "Mengambil Egg Python..."

    if ! curl -fsSL \
        --retry 5 \
        --retry-delay 3 \
        --connect-timeout 20 \
        --max-time 180 \
        "$egg_python_url" \
        -o "$egg_dir/egg-python.json"; then

        error "Gagal mendownload Egg Python."
        return 1
    fi

    if [[ ! -s "$egg_dir/egg-python.json" ]]; then
        error "Egg Python kosong."
        return 1
    fi

    # ========================================================
    # JSON VALIDATION
    # ========================================================

    info "Memvalidasi JSON Egg..."

    if ! php -r '
        $files = array_slice($argv, 1);

        foreach ($files as $file) {

            if (!is_file($file)) {
                fwrite(
                    STDERR,
                    "FILE_NOT_FOUND:$file\n"
                );

                exit(1);
            }

            try {

                $data = json_decode(
                    file_get_contents($file),
                    true,
                    512,
                    JSON_THROW_ON_ERROR
                );

            } catch (Throwable $e) {

                fwrite(
                    STDERR,
                    "INVALID_JSON:$file:" .
                    $e->getMessage() .
                    "\n"
                );

                exit(1);
            }

            if (
                !isset($data["meta"]["version"]) ||
                $data["meta"]["version"] !== "PTDL_v2"
            ) {

                fwrite(
                    STDERR,
                    "INVALID_EGG_VERSION:$file\n"
                );

                exit(1);
            }

            if (empty($data["name"])) {

                fwrite(
                    STDERR,
                    "EGG_NAME_MISSING:$file\n"
                );

                exit(1);
            }

            if (empty($data["author"])) {

                fwrite(
                    STDERR,
                    "EGG_AUTHOR_MISSING:$file\n"
                );

                exit(1);
            }

            if (
                !filter_var(
                    $data["author"],
                    FILTER_VALIDATE_EMAIL
                )
            ) {

                fwrite(
                    STDERR,
                    "EGG_AUTHOR_INVALID:$file\n"
                );

                exit(1);
            }

            if (
                !isset($data["docker_images"]) ||
                !is_array($data["docker_images"]) ||
                count($data["docker_images"]) < 1
            ) {

                fwrite(
                    STDERR,
                    "DOCKER_IMAGES_MISSING:$file\n"
                );

                exit(1);
            }

            if (
                !isset($data["scripts"]) ||
                !isset($data["scripts"]["installation"])
            ) {

                fwrite(
                    STDERR,
                    "INSTALL_SCRIPT_MISSING:$file\n"
                );

                exit(1);
            }

            if (
                !isset($data["startup"])
            ) {

                fwrite(
                    STDERR,
                    "STARTUP_MISSING:$file\n"
                );

                exit(1);
            }
        }

        exit(0);
    ' \
        "$egg_dir/egg-bot-vyro.json" \
        "$egg_dir/egg-python.json"; then

        error "Validasi Egg gagal."

        error "File sementara:"
        error "$egg_dir"

        return 1
    fi

    log "JSON Egg: OK"


    # ========================================================
    # GET EGG NAMES
    # ========================================================

    IMPORTED_NODEJS_EGG_NAME="$(
        php -r '
            $data = json_decode(
                file_get_contents($argv[1]),
                true
            );

            echo trim((string)($data["name"] ?? ""));
        ' \
        "$egg_dir/egg-bot-vyro.json"
    )"

    IMPORTED_PYTHON_EGG_NAME="$(
        php -r '
            $data = json_decode(
                file_get_contents($argv[1]),
                true
            );

            echo trim((string)($data["name"] ?? ""));
        ' \
        "$egg_dir/egg-python.json"
    )"

    if [[ -z "$IMPORTED_NODEJS_EGG_NAME" ]]; then
        error "Nama Egg NodeJS tidak dapat dibaca."
        return 1
    fi

    if [[ -z "$IMPORTED_PYTHON_EGG_NAME" ]]; then
        error "Nama Egg Python tidak dapat dibaca."
        return 1
    fi

    info "Egg NodeJS: $IMPORTED_NODEJS_EGG_NAME"
    info "Egg Python: $IMPORTED_PYTHON_EGG_NAME"


    # ========================================================
    # CREATE IMPORTER
    # ========================================================

    local importer="/tmp/putzofficial-egg-importer.php"

    cat > "$importer" <<'PHP'
<?php

declare(strict_types=1);

use Illuminate\Support\Str;
use Illuminate\Database\Eloquent\Model;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\Nest;
use Pterodactyl\Models\EggVariable;

require '/var/www/pterodactyl/vendor/autoload.php';

$app = require '/var/www/pterodactyl/bootstrap/app.php';

$kernel = $app->make(
    Illuminate\Contracts\Console\Kernel::class
);

$kernel->bootstrap();


/**
 * ==========================================================
 * OUTPUT
 * ==========================================================
 */

function output_line(string $message): void
{
    echo $message . PHP_EOL;
}


/**
 * ==========================================================
 * FAIL
 * ==========================================================
 */

function fail_import(string $message): never
{
    fwrite(
        STDERR,
        "[ERROR] " . $message . PHP_EOL
    );

    exit(1);
}


/**
 * ==========================================================
 * JSON STRING
 * ==========================================================
 */

function normalize_json_string(
    mixed $value
): ?string {

    if ($value === null) {
        return null;
    }

    if (is_string($value)) {
        return $value;
    }

    return json_encode(
        $value,
        JSON_UNESCAPED_SLASHES |
        JSON_UNESCAPED_UNICODE
    );
}


/**
 * ==========================================================
 * CONFIG VALUE
 * ==========================================================
 */

function normalize_config_value(
    mixed $value,
    string $default = '{}'
): string {

    if ($value === null) {
        return $default;
    }

    if (is_string($value)) {
        return $value;
    }

    $encoded = json_encode(
        $value,
        JSON_UNESCAPED_SLASHES |
        JSON_UNESCAPED_UNICODE
    );

    return $encoded === false
        ? $default
        : $encoded;
}


/**
 * ==========================================================
 * FILLABLE HELPER
 * ==========================================================
 */

function assign_if_fillable(
    Model $model,
    string $field,
    mixed $value
): void {

    if (
        in_array(
            $field,
            $model->getFillable(),
            true
        )
    ) {

        $model->setAttribute(
            $field,
            $value
        );
    }
}


/**
 * ==========================================================
 * GET / CREATE NEST
 * ==========================================================
 */

function get_or_create_nest(
    string $name,
    string $description,
    string $author
): Nest {

    $nest = Nest::query()
        ->where(
            'name',
            $name
        )
        ->first();

    if ($nest) {

        /*
         * IMPORTANT:
         *
         * Pterodactyl membutuhkan author
         * pada Nest di beberapa versi.
         *
         * Jadi jika Nest lama belum memiliki
         * author, kita isi sekarang.
         */

        if (
            empty(
                $nest->getAttribute('author')
            )
        ) {

            $nest->setAttribute(
                'author',
                $author
            );

            $nest->save();

            output_line(
                "[OK] Author Nest diperbaiki: {$name}"
            );
        }

        output_line(
            "[OK] Nest sudah ada: {$name}"
        );

        return $nest;
    }


    /**
     * ------------------------------------------------------
     * CREATE NEW NEST
     * ------------------------------------------------------
     */

    $nest = new Nest();

    $nest->uuid = (string) Str::uuid();

    /*
     * AUTHOR HARUS DISET LANGSUNG
     * SEBELUM save().
     */

    $nest->author = $author;

    assign_if_fillable(
        $nest,
        'name',
        $name
    );

    assign_if_fillable(
        $nest,
        'description',
        $description
    );

    /*
     * Beberapa versi Pterodactyl menjadikan author
     * guarded / tidak fillable.
     *
     * Jadi kita set langsung sekali lagi.
     */

    $nest->author = $author;

    $nest->save();

    output_line(
        "[OK] Nest dibuat: {$name}"
    );

    return $nest;
}


/**
 * ==========================================================
 * IMPORT VARIABLES
 * ==========================================================
 */

function import_variables(
    Egg $egg,
    array $variables
): void {

    if (empty($variables)) {

        output_line(
            "[INFO] Egg tidak memiliki variable."
        );

        return;
    }

    $imported = 0;

    foreach ($variables as $variable) {

        if (!is_array($variable)) {
            continue;
        }

        $envVariable = trim(
            (string) (
                $variable['env_variable']
                ?? ''
            )
        );

        if ($envVariable === '') {
            continue;
        }

        $existing = EggVariable::query()
            ->where(
                'egg_id',
                $egg->id
            )
            ->where(
                'env_variable',
                $envVariable
            )
            ->first();

        if ($existing) {
            continue;
        }

        $model = new EggVariable();

        $model->egg_id = $egg->id;

        $fillable = $model->getFillable();

        $fieldMap = [

            'name' =>
                $variable['name']
                ?? $envVariable,

            'description' =>
                $variable['description']
                ?? '',

            'env_variable' =>
                $envVariable,

            'default_value' =>
                $variable['default_value']
                ?? '',

            'user_viewable' =>
                $variable['user_viewable']
                ?? true,

            'user_editable' =>
                $variable['user_editable']
                ?? true,

            'rules' =>
                $variable['rules']
                ?? 'nullable|string',

            'field_type' =>
                $variable['field_type']
                ?? 'text',
        ];

        foreach (
            $fieldMap as $field => $value
        ) {

            if (
                in_array(
                    $field,
                    $fillable,
                    true
                )
            ) {

                $model->setAttribute(
                    $field,
                    $value
                );
            }
        }

        $model->save();

        $imported++;
    }

    output_line(
        "[OK] Variables imported: {$imported}"
    );
}


/**
 * ==========================================================
 * IMPORT EGG
 * ==========================================================
 */

function import_egg(
    string $jsonFile,
    string $nestName,
    string $nestDescription
): string {

    if (!is_file($jsonFile)) {

        fail_import(
            "Egg file tidak ditemukan: {$jsonFile}"
        );
    }

    $raw = file_get_contents(
        $jsonFile
    );

    if (
        $raw === false ||
        trim($raw) === ''
    ) {

        fail_import(
            "Egg file kosong: {$jsonFile}"
        );
    }


    /**
     * ------------------------------------------------------
     * DECODE
     * ------------------------------------------------------
     */

    try {

        $data = json_decode(
            $raw,
            true,
            512,
            JSON_THROW_ON_ERROR
        );

    } catch (Throwable $e) {

        fail_import(
            "JSON Egg tidak valid: " .
            $e->getMessage()
        );
    }


    /**
     * ------------------------------------------------------
     * VERSION
     * ------------------------------------------------------
     */

    if (
        !isset($data['meta']['version']) ||
        $data['meta']['version'] !== 'PTDL_v2'
    ) {

        fail_import(
            "Egg bukan PTDL_v2: {$jsonFile}"
        );
    }


    /**
     * ------------------------------------------------------
     * NAME
     * ------------------------------------------------------
     */

    $name = trim(
        (string) (
            $data['name'] ?? ''
        )
    );

    if ($name === '') {

        fail_import(
            "Nama Egg kosong: {$jsonFile}"
        );
    }


    /**
     * ------------------------------------------------------
     * AUTHOR
     * ------------------------------------------------------
     */

    $author = trim(
        (string) (
            $data['author']
            ?? 'support@pterodactyl.io'
        )
    );

    if (
        !filter_var(
            $author,
            FILTER_VALIDATE_EMAIL
        )
    ) {

        $author =
            'support@pterodactyl.io';
    }


    /**
     * ------------------------------------------------------
     * DESCRIPTION
     * ------------------------------------------------------
     */

    $description =
        $data['description']
        ?? null;

    if ($description !== null) {

        $description =
            (string) $description;
    }


    /**
     * ------------------------------------------------------
     * FEATURES
     * ------------------------------------------------------
     */

    $features =
        $data['features']
        ?? null;


    /**
     * ------------------------------------------------------
     * DOCKER IMAGES
     * ------------------------------------------------------
     */

    $dockerImages =
        $data['docker_images']
        ?? [];

    if (
        !is_array($dockerImages) ||
        count($dockerImages) < 1
    ) {

        fail_import(
            "docker_images tidak valid untuk Egg {$name}"
        );
    }


    /**
     * ------------------------------------------------------
     * STARTUP
     * ------------------------------------------------------
     */

    $startup =
        $data['startup']
        ?? null;


    /**
     * ------------------------------------------------------
     * CONFIG
     * ------------------------------------------------------
     */

    $config =
        $data['config']
        ?? [];

    if (!is_array($config)) {
        $config = [];
    }


    /**
     * ------------------------------------------------------
     * SCRIPTS
     * ------------------------------------------------------
     */

    $scripts =
        $data['scripts']
        ?? [];

    if (!is_array($scripts)) {
        $scripts = [];
    }

    $installation =
        $scripts['installation']
        ?? [];

    if (!is_array($installation)) {
        $installation = [];
    }


    /**
     * ------------------------------------------------------
     * INSTALL SCRIPT
     * ------------------------------------------------------
     */

    $scriptInstall =
        $installation['script']
        ?? null;

    $scriptContainer =
        $installation['container']
        ?? null;

    $scriptEntry =
        $installation['entrypoint']
        ?? null;


    /**
     * ------------------------------------------------------
     * CONFIG FILES
     * ------------------------------------------------------
     */

    $configFiles =
        normalize_config_value(
            $config['files'] ?? '{}',
            '{}'
        );


    /**
     * ------------------------------------------------------
     * CONFIG STARTUP
     * ------------------------------------------------------
     */

    $configStartup =
        normalize_config_value(
            $config['startup'] ?? '{}',
            '{}'
        );


    /**
     * ------------------------------------------------------
     * CONFIG LOGS
     * ------------------------------------------------------
     */

    $configLogs =
        normalize_config_value(
            $config['logs'] ?? '{}',
            '{}'
        );


    /**
     * ------------------------------------------------------
     * CONFIG STOP
     * ------------------------------------------------------
     */

    $configStop =
        $config['stop']
        ?? null;

    if ($configStop !== null) {

        $configStop =
            (string) $configStop;
    }


    /**
     * ------------------------------------------------------
     * FILE DENYLIST
     * ------------------------------------------------------
     */

    $fileDenylist =
        $data['file_denylist']
        ?? [];

    if (!is_array($fileDenylist)) {
        $fileDenylist = [];
    }


    /**
     * ------------------------------------------------------
     * META UPDATE URL
     * ------------------------------------------------------
     */

    $metaUpdateUrl =
        $data['meta']['update_url']
        ?? null;


    /**
     * ------------------------------------------------------
     * FORCE OUTGOING IP
     * ------------------------------------------------------
     */

    $forceOutgoingIp =
        $data['force_outgoing_ip']
        ?? false;


    /**
     * ------------------------------------------------------
     * SCRIPT PRIVILEGED
     * ------------------------------------------------------
     */

    $scriptPrivileged =
        $installation['privileged']
        ?? false;


    /**
     * ------------------------------------------------------
     * NEST
     * ------------------------------------------------------
     */

    $nest = get_or_create_nest(
        $nestName,
        $nestDescription,
        $author
    );


    /**
     * ------------------------------------------------------
     * DUPLICATE CHECK
     * ------------------------------------------------------
     */

    $existing = Egg::query()
        ->where(
            'nest_id',
            $nest->id
        )
        ->where(
            'name',
            $name
        )
        ->first();

    if ($existing) {

        /*
         * Pastikan Egg existing memiliki author.
         */

        if (
            empty(
                $existing->getAttribute('author')
            )
        ) {

            $existing->author =
                $author;

            $existing->save();

            output_line(
                "[OK] Author Egg diperbaiki: {$name}"
            );
        }

        output_line(
            "[SKIP] Egg sudah ada: {$name}"
        );

        return $name;
    }


    /**
     * ------------------------------------------------------
     * CREATE EGG
     * ------------------------------------------------------
     */

    $egg = new Egg();

    $egg->uuid =
        (string) Str::uuid();

    $egg->nest_id =
        $nest->id;


    /**
     * ------------------------------------------------------
     * BASIC FIELDS
     * ------------------------------------------------------
     */

    assign_if_fillable(
        $egg,
        'name',
        $name
    );

    assign_if_fillable(
        $egg,
        'description',
        $description
    );

    assign_if_fillable(
        $egg,
        'features',
        $features
    );

    assign_if_fillable(
        $egg,
        'docker_images',
        $dockerImages
    );

    assign_if_fillable(
        $egg,
        'force_outgoing_ip',
        (bool) $forceOutgoingIp
    );

    assign_if_fillable(
        $egg,
        'file_denylist',
        $fileDenylist
    );


    /**
     * ------------------------------------------------------
     * CONFIG
     * ------------------------------------------------------
     */

    assign_if_fillable(
        $egg,
        'config_files',
        $configFiles
    );

    assign_if_fillable(
        $egg,
        'config_startup',
        $configStartup
    );

    assign_if_fillable(
        $egg,
        'config_logs',
        $configLogs
    );

    assign_if_fillable(
        $egg,
        'config_stop',
        $configStop
    );

    assign_if_fillable(
        $egg,
        'config_from',
        null
    );


    /**
     * ------------------------------------------------------
     * STARTUP
     * ------------------------------------------------------
     */

    assign_if_fillable(
        $egg,
        'startup',
        $startup
    );


    /**
     * ------------------------------------------------------
     * SCRIPT
     * ------------------------------------------------------
     */

    assign_if_fillable(
        $egg,
        'script_is_privileged',
        (bool) $scriptPrivileged
    );

    assign_if_fillable(
        $egg,
        'script_install',
        $scriptInstall
    );

    assign_if_fillable(
        $egg,
        'script_entry',
        $scriptEntry
    );

    assign_if_fillable(
        $egg,
        'script_container',
        $scriptContainer
    );

    assign_if_fillable(
        $egg,
        'copy_script_from',
        null
    );


    /**
     * ------------------------------------------------------
     * AUTHOR
     * ------------------------------------------------------
     *
     * IMPORTANT:
     * author bukan fillable pada Egg model.
     * Jadi harus di-set langsung.
     */

    $egg->author =
        $author;


    /**
     * ------------------------------------------------------
     * SAVE EGG
     * ------------------------------------------------------
     */

    $egg->save();


    /**
     * ------------------------------------------------------
     * UPDATE URL
     * ------------------------------------------------------
     */

    if (
        $metaUpdateUrl !== null
    ) {

        $egg->update_url =
            (string) $metaUpdateUrl;

        $egg->save();
    }


    /**
     * ------------------------------------------------------
     * VARIABLES
     * ------------------------------------------------------
     */

    import_variables(
        $egg,
        $data['variables']
        ?? []
    );


    /**
     * ------------------------------------------------------
     * SUCCESS
     * ------------------------------------------------------
     */

    output_line(
        "[OK] Egg berhasil diimport: {$name}"
    );

    output_line(
        "[INFO] Author: {$author}"
    );

    output_line(
        "[INFO] Nest: {$nest->name}"
    );

    output_line(
        "[INFO] Egg ID: {$egg->id}"
    );

    return $name;
}


/**
 * ==========================================================
 * MAIN
 * ==========================================================
 */

$nodejsFile =
    $argv[1]
    ?? null;

$pythonFile =
    $argv[2]
    ?? null;

if (
    !$nodejsFile ||
    !$pythonFile
) {

    fail_import(
        "Argument file Egg tidak lengkap."
    );
}


try {

    output_line(
        "================================================"
    );

    output_line(
        "        PUTZOFFICIAL AUTO EGG IMPORT"
    );

    output_line(
        "================================================"
    );


    /**
     * ------------------------------------------------------
     * NODEJS
     * ------------------------------------------------------
     */

    output_line(
        "[INFO] Import Egg NodeJS..."
    );

    $nodeName =
        import_egg(
            $nodejsFile,
            'PutzOfficial NodeJS',
            'NodeJS Eggs - PutzOfficial'
        );


    /**
     * ------------------------------------------------------
     * PYTHON
     * ------------------------------------------------------
     */

    output_line(
        "[INFO] Import Egg Python..."
    );

    $pythonName =
        import_egg(
            $pythonFile,
            'PutzOfficial Python',
            'Python Eggs - PutzOfficial'
        );


    /**
     * ------------------------------------------------------
     * OUTPUT NAMES
     * ------------------------------------------------------
     */

    output_line(
        "================================================"
    );

    output_line(
        "[OK] NODEJS EGG: {$nodeName}"
    );

    output_line(
        "[OK] PYTHON EGG: {$pythonName}"
    );

    output_line(
        "[OK] AUTO EGG IMPORT SELESAI"
    );

    output_line(
        "================================================"
    );


} catch (Throwable $e) {

    fail_import(
        $e->getMessage()
    );
}
PHP


    # ========================================================
    # CHECK IMPORTER
    # ========================================================

    info "Memeriksa syntax importer..."

    if ! php -l "$importer" >/dev/null 2>&1; then

        error "Syntax PHP importer tidak valid."

        php -l "$importer" || true

        return 1
    fi

    log "Syntax importer: OK"


    # ========================================================
    # RUN IMPORTER
    # ========================================================

    info "Mengimport Egg ke Pterodactyl..."

    if ! php "$importer" \
        "$egg_dir/egg-bot-vyro.json" \
        "$egg_dir/egg-python.json"; then

        error "Auto-import Egg gagal."

        error "File Egg tersimpan sementara di:"
        error "$egg_dir"

        rm -f "$importer"

        return 1
    fi


    # ========================================================
    # CLEANUP
    # ========================================================

    rm -rf "$egg_dir"
    rm -f "$importer"


    # ========================================================
    # CACHE CLEAR
    # ========================================================

    info "Membersihkan cache Pterodactyl..."

    cd /var/www/pterodactyl

    php artisan optimize:clear \
        >/dev/null 2>&1 \
        || true

    log "Cache Pterodactyl dibersihkan."


    # ========================================================
    # FINAL EGG CHECK
    # ========================================================

    info "Memverifikasi Egg yang terpasang..."

    local verify_output=""

    verify_output="$(
        cd /var/www/pterodactyl &&
        php artisan tinker --execute="
            \$names = [
                '$IMPORTED_NODEJS_EGG_NAME',
                '$IMPORTED_PYTHON_EGG_NAME'
            ];

            \$eggs = \Pterodactyl\Models\Egg::whereIn(
                'name',
                \$names
            )->get([
                'id',
                'name',
                'author'
            ]);

            foreach (\$eggs as \$egg) {
                echo \$egg->id . '|' .
                     \$egg->name . '|' .
                     \$egg->author . PHP_EOL;
            }
        " 2>/dev/null
    )" || true


    local node_found=0
    local python_found=0

    if echo "$verify_output" |
        grep -Fq "|${IMPORTED_NODEJS_EGG_NAME}|"; then

        node_found=1
    fi

    if echo "$verify_output" |
        grep -Fq "|${IMPORTED_PYTHON_EGG_NAME}|"; then

        python_found=1
    fi


    if [[ "$node_found" -eq 1 ]]; then

        log "Egg NodeJS terdeteksi: $IMPORTED_NODEJS_EGG_NAME"

    else

        warn "Egg NodeJS belum terdeteksi: $IMPORTED_NODEJS_EGG_NAME"

        failed=1
    fi


    if [[ "$python_found" -eq 1 ]]; then

        log "Egg Python terdeteksi: $IMPORTED_PYTHON_EGG_NAME"

    else

        warn "Egg Python belum terdeteksi: $IMPORTED_PYTHON_EGG_NAME"

        failed=1
    fi


    return 0
}


# ============================================================
# PTERODACTYL PANEL INSTALL
# ============================================================

install_panel() {

    # ========================================================
    # ROOT CHECK
    # ========================================================

    if [[ "${EUID}" -ne 0 ]]; then

        error "Installer Panel harus dijalankan sebagai root."

        return 1
    fi


    info "Memulai instalasi Pterodactyl Panel..."


    # ========================================================
    # VARIABLES
    # ========================================================

    local php_version="8.3"

    local domain=""
    local db_pass=""

    local admin_email=""
    local admin_username=""
    local admin_name=""
    local admin_first_name=""
    local admin_last_name=""
    local admin_password=""

    local timezone="Asia/Jakarta"

    local tag=""
    local panel_url=""

    local archive="/tmp/pterodactyl.tar.gz"

    local extract_dir="/tmp/putzofficial-pterodactyl"

    local failed=0


    # ========================================================
    # INPUT
    # ========================================================

    echo

    echo "╭────────────────────────────────────────────────────╮"
    echo "│             PTERODACTYL CONFIGURATION              │"
    echo "╰────────────────────────────────────────────────────╯"

    echo


    domain="$(
        ask_required \
            'Domain Panel, contoh panel.example.com'
    )"


    db_pass="$(
        ask_required \
            'Password database MariaDB'
    )"


    echo

    echo "╭────────────────────────────────────────────────────╮"
    echo "│              ADMIN ACCOUNT CONFIG                  │"
    echo "╰────────────────────────────────────────────────────╯"

    echo


    admin_email="$(
        ask_required \
            'Email administrator'
    )"


    admin_username="$(
        ask_required \
            'Username administrator'
    )"


    admin_name="$(
        ask_required \
            'Nama lengkap administrator'
    )"


    admin_first_name="$(
        ask_required \
            'Nama depan administrator'
    )"


    admin_last_name="$(
        ask_required \
            'Nama belakang administrator'
    )"


    admin_password="$(
        ask_required \
            'Password administrator'
    )"


    echo

    info "Timezone default: ${timezone}"

    echo


    # ========================================================
    # VALIDATE DOMAIN
    # ========================================================

    if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then

        error "Format domain tidak valid: $domain"

        return 1
    fi


    if [[ "$domain" == .* ||
          "$domain" == *..* ||
          "$domain" == -* ||
          "$domain" == *- ]]; then

        error "Format domain tidak valid: $domain"

        return 1
    fi


    # ========================================================
    # VALIDATE EMAIL
    # ========================================================

    if [[ ! "$admin_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then

        error "Format email tidak valid: $admin_email"

        return 1
    fi


    # ========================================================
    # VALIDATE USERNAME
    # ========================================================

    if [[ ! "$admin_username" =~ ^[A-Za-z0-9._-]+$ ]]; then

        error "Username hanya boleh mengandung huruf, angka, titik, underscore, dan minus."

        return 1
    fi


    # ========================================================
    # VALIDATE PASSWORD
    # ========================================================

    if [[ ${#admin_password} -lt 8 ]]; then

        error "Password administrator minimal 8 karakter."

        return 1
    fi


    if [[ ${#db_pass} -lt 8 ]]; then

        error "Password database minimal 8 karakter."

        return 1
    fi


    # ========================================================
    # PACKAGE UPDATE
    # ========================================================

    info "Mengupdate package repository..."

    apt-get update -y


    # ========================================================
    # BASE DEPENDENCIES
    # ========================================================

    info "Menginstall dependency dasar..."

    apt_install \
        ca-certificates \
        curl \
        git \
        unzip \
        tar \
        nginx \
        mariadb-server \
        mariadb-client \
        redis-server \
        software-properties-common \
        apt-transport-https \
        lsb-release \
        gnupg \
        certbot \
        python3-certbot-nginx


    # ========================================================
    # PHP REPOSITORY
    # ========================================================

    info "Memeriksa PHP ${php_version}..."


    if ! apt-cache show \
        "php${php_version}" \
        >/dev/null 2>&1; then

        warn "PHP ${php_version} belum tersedia."

        info "Menambahkan repository PHP..."


        apt_install \
            ca-certificates \
            lsb-release \
            apt-transport-https \
            software-properties-common


        if ! command_exists add-apt-repository; then

            apt_install \
                software-properties-common
        fi


        add-apt-repository \
            -y \
            ppa:ondrej/php


        apt-get update -y
    fi


    # ========================================================
    # PHP PACKAGES
    # ========================================================

    info "Menginstall PHP ${php_version}..."


    apt_install \
        "php${php_version}" \
        "php${php_version}-cli" \
        "php${php_version}-fpm" \
        "php${php_version}-common" \
        "php${php_version}-gd" \
        "php${php_version}-mysql" \
        "php${php_version}-mbstring" \
        "php${php_version}-bcmath" \
        "php${php_version}-xml" \
        "php${php_version}-curl" \
        "php${php_version}-zip" \
        "php${php_version}-tokenizer" \
        "php${php_version}-opcache"


    # ========================================================
    # CLEAN DUPLICATE PDO CONFIG
    # ========================================================

    info "Memeriksa konfigurasi PHP..."


    local cli_conf="/etc/php/${php_version}/cli/conf.d"


    if [[ -d "$cli_conf" ]]; then

        local pdo_files=()


        while IFS= read -r file; do

            pdo_files+=("$file")

        done < <(
            grep -rilE \
                '^[[:space:]]*extension[[:space:]]*=[[:space:]]*pdo(\.so)?[[:space:]]*$' \
                "$cli_conf" \
                2>/dev/null \
                || true
        )


        if [[ "${#pdo_files[@]}" -gt 1 ]]; then

            warn "Ditemukan konfigurasi PDO ganda."


            local keep_pdo=""
            local file=""


            for file in "${pdo_files[@]}"; do

                if [[ "$file" == *"/10-pdo.ini" ]]; then

                    keep_pdo="$file"

                    break
                fi

            done


            if [[ -z "$keep_pdo" ]]; then

                keep_pdo="${pdo_files[0]}"
            fi


            for file in "${pdo_files[@]}"; do

                if [[ "$file" != "$keep_pdo" ]]; then

                    rm -f "$file"
                fi

            done


            log "Konfigurasi PDO duplikat CLI dibersihkan."
        fi
    fi


    # ========================================================
    # PHP ALTERNATIVE
    # ========================================================

    if command_exists update-alternatives; then

        update-alternatives \
            --set php \
            "/usr/bin/php${php_version}" \
            >/dev/null 2>&1 \
            || true

    fi


    # ========================================================
    # PHP CHECK
    # ========================================================

    info "Memeriksa PHP..."


    if ! php -r \
        'exit(extension_loaded("PDO") ? 0 : 1);'; then

        error "PHP PDO belum aktif."

        return 1
    fi

    echo "PDO:OK"


    if ! php -r \
        'exit(extension_loaded("pdo_mysql") ? 0 : 1);'; then

        error "PHP pdo_mysql belum aktif."

        return 1
    fi

    echo "pdo_mysql:OK"


    info "Memeriksa PHP Phar..."


    if ! php -r \
        'exit(extension_loaded("Phar") ? 0 : 1);'; then

        error "PHP Phar belum aktif."

        return 1
    fi

    echo "Phar:OK"


    if ! php -r \
        'exit(extension_loaded("posix") ? 0 : 1);'; then

        error "PHP posix belum aktif."

        return 1
    fi

    echo "posix:OK"


    if ! php -r \
        'exit(extension_loaded("tokenizer") ? 0 : 1);'; then

        error "PHP tokenizer belum aktif."

        return 1
    fi

    echo "tokenizer:OK"


    if ! php -r \
        'exit(extension_loaded("fileinfo") ? 0 : 1);'; then

        error "PHP fileinfo belum aktif."

        return 1
    fi

    echo "fileinfo:OK"


    # ========================================================
    # ICONV
    # ========================================================

    if php -r \
        'exit(extension_loaded("iconv") ? 0 : 1);'; then

        echo "iconv:OK"

    else

        warn "PHP iconv tidak aktif."

        warn "Composer akan menggunakan ignore-platform-req=ext-iconv."

    fi


    # ========================================================
    # SERVICE
    # ========================================================

    info "Mengaktifkan service..."


    systemctl enable --now mariadb

    systemctl enable --now redis-server

    systemctl enable --now \
        "php${php_version}-fpm"

    systemctl enable --now nginx


    # ========================================================
    # SERVICE CHECK
    # ========================================================

    if ! systemctl is-active \
        --quiet mariadb; then

        error "MariaDB gagal dijalankan."

        return 1
    fi


    if ! systemctl is-active \
        --quiet redis-server; then

        error "Redis gagal dijalankan."

        return 1
    fi


    if ! systemctl is-active \
        --quiet "php${php_version}-fpm"; then

        error "PHP-FPM gagal dijalankan."

        return 1
    fi


    if ! systemctl is-active \
        --quiet nginx; then

        error "Nginx gagal dijalankan."

        return 1
    fi


    # ========================================================
    # COMPOSER
    # ========================================================

    if command_exists composer; then

        log "Composer sudah tersedia."

    else

        info "Menginstall Composer..."


        rm -f \
            /tmp/composer-setup.php


        curl -fsSL \
            --retry 5 \
            --retry-delay 3 \
            --connect-timeout 20 \
            --max-time 120 \
            https://getcomposer.org/installer \
            -o /tmp/composer-setup.php


        php \
            /tmp/composer-setup.php \
            --install-dir=/usr/local/bin \
            --filename=composer


        rm -f \
            /tmp/composer-setup.php

    fi


    # ========================================================
    # COMPOSER CHECK
    # ========================================================

    if ! command_exists composer; then

        error "Composer tidak dapat dijalankan."

        return 1
    fi


    info "Memeriksa Composer..."


    if ! composer --version; then

        error "Composer tidak dapat dijalankan."

        return 1
    fi


    log "Composer: OK"


    # ========================================================
    # PANEL DIRECTORY
    # ========================================================

    mkdir -p \
        /var/www


    # ========================================================
    # EXISTING PANEL
    # ========================================================

    if [[ -f /var/www/pterodactyl/artisan ]]; then

        warn "Pterodactyl Panel sudah ditemukan."

        info "Source download dilewati."

    else

        # ====================================================
        # CLEAN BROKEN INSTALLATION
        # ====================================================

        if [[ -d /var/www/pterodactyl ]]; then

            warn "Folder Pterodactyl tidak lengkap."

            info "Membersihkan instalasi gagal sebelumnya..."


            rm -rf \
                /var/www/pterodactyl

        fi


        mkdir -p \
            /var/www/pterodactyl


        # ====================================================
        # GET LATEST RELEASE
        # ====================================================

        info "Mengambil release Pterodactyl..."


        tag="$(
            curl -fsSL \
                --retry 5 \
                --retry-delay 2 \
                --connect-timeout 20 \
                --max-time 120 \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                https://api.github.com/repos/pterodactyl/panel/releases/latest |
            sed -n \
                's/.*"tag_name": "\(.*\)",/\1/p' |
            head -n 1
        )"


        if [[ -z "$tag" ]]; then

            error "Tidak dapat mendapatkan release Pterodactyl dari GitHub."

            return 1
        fi


        panel_url="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"


        info "Release terbaru: $tag"

        info "Downloading panel.tar.gz..."


        rm -f \
            "$archive"


        curl -fL \
            --retry 5 \
            --retry-delay 3 \
            --connect-timeout 20 \
            --max-time 600 \
            "$panel_url" \
            -o "$archive"


        if [[ ! -s "$archive" ]]; then

            error "File panel.tar.gz kosong atau gagal didownload."

            return 1
        fi


        info "Memeriksa archive Pterodactyl..."


        if ! tar -tzf \
            "$archive" \
            >/dev/null 2>&1; then

            error "Archive Pterodactyl rusak atau bukan tar.gz yang valid."

            return 1
        fi


        # ====================================================
        # EXTRACTION
        # ====================================================

        rm -rf \
            "$extract_dir"


        mkdir -p \
            "$extract_dir"


        info "Extracting Pterodactyl..."


        tar -xzf \
            "$archive" \
            -C "$extract_dir"


        rm -f \
            "$archive"


        # ====================================================
        # FIND ARTISAN
        # ====================================================

        local artisan_file=""
        local source_dir=""


        artisan_file="$(
            find "$extract_dir" \
                -type f \
                -name artisan \
                -print \
                -quit
        )"


        if [[ -z "$artisan_file" ]]; then

            error "File artisan tidak ditemukan setelah extraction."

            rm -rf \
                "$extract_dir"

            return 1
        fi


        source_dir="$(
            dirname \
                "$artisan_file"
        )"


        if [[ ! -f "$source_dir/composer.json" ]]; then

            error "composer.json tidak ditemukan bersama artisan."

            rm -rf \
                "$extract_dir"

            return 1
        fi


        if [[ ! -d "$source_dir/public" ]]; then

            error "Folder public Pterodactyl tidak ditemukan."

            rm -rf \
                "$extract_dir"

            return 1
        fi


        # ====================================================
        # COPY SOURCE
        # ====================================================

        info "Menempatkan source Pterodactyl..."


        cp -a \
            "$source_dir"/. \
            /var/www/pterodactyl/


        rm -rf \
            "$extract_dir"


        # ====================================================
        # SOURCE CHECK
        # ====================================================

        if [[ ! -f /var/www/pterodactyl/artisan ]]; then

            error "Source Pterodactyl tidak valid."

            return 1
        fi


        if [[ ! -f /var/www/pterodactyl/composer.json ]]; then

            error "composer.json Pterodactyl tidak ditemukan."

            return 1
        fi


        if [[ ! -d /var/www/pterodactyl/public ]]; then

            error "Folder public Pterodactyl tidak ditemukan."

            return 1
        fi


        log "Pterodactyl source berhasil di-download."

    fi


    # ========================================================
    # PANEL DIRECTORY
    # ========================================================

    cd \
        /var/www/pterodactyl


    # ========================================================
    # ENVIRONMENT
    # ========================================================

    if [[ ! -f .env ]]; then

        info "Membuat .env..."


        if [[ ! -f .env.example ]]; then

            error ".env.example tidak ditemukan."

            return 1
        fi


        cp \
            .env.example \
            .env

    else

        log ".env sudah tersedia."

    fi


    # ========================================================
    # DATABASE PASSWORD ESCAPE
    # ========================================================

    local escaped_db_pass

    escaped_db_pass="${db_pass//\'/\'\'}"


    # ========================================================
    # CREATE DATABASE
    # ========================================================

    info "Membuat database MariaDB..."


    mysql <<SQL
CREATE DATABASE IF NOT EXISTS panel
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS
'pterodactyl'@'127.0.0.1'
IDENTIFIED BY '${escaped_db_pass}';

ALTER USER
'pterodactyl'@'127.0.0.1'
IDENTIFIED BY '${escaped_db_pass}';

GRANT ALL PRIVILEGES
ON panel.*
TO 'pterodactyl'@'127.0.0.1';

FLUSH PRIVILEGES;
SQL


    # ========================================================
    # DATABASE TEST
    # ========================================================

    info "Memeriksa koneksi database..."


    if ! mysql \
        -h 127.0.0.1 \
        -u pterodactyl \
        "-p${db_pass}" \
        -e "SELECT 1;" \
        panel \
        >/dev/null 2>&1; then

        error "Koneksi database Pterodactyl gagal."

        return 1
    fi


    log "Koneksi database: OK"


    # ========================================================
    # COMPOSER DEPENDENCIES
    # ========================================================

    info "Installing Composer dependencies..."


    if ! COMPOSER_ALLOW_SUPERUSER=1 \
        composer install \
            --no-dev \
            --optimize-autoloader \
            --no-interaction \
            --ignore-platform-req=ext-iconv; then

        error "Composer dependencies gagal diinstall."

        error "Periksa log:"
        error "/var/log/putzofficial-installer/install.log"

        return 1
    fi


    log "Composer dependencies: OK"


    # ========================================================
    # APPLICATION KEY
    # ========================================================

    info "Generating application key..."


    if ! php artisan \
        key:generate \
        --force; then

        error "Gagal membuat application key."

        return 1
    fi


    # ========================================================
    # DATABASE ENVIRONMENT
    # ========================================================

    info "Configuring database..."


    if ! php artisan \
        p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database=panel \
        --username=pterodactyl \
        --password="$db_pass"; then

        error "Konfigurasi database Pterodactyl gagal."

        return 1
    fi


    # ========================================================
    # APPLICATION ENVIRONMENT
    # ========================================================

    info "Configuring application..."


    if ! php artisan \
        p:environment:setup \
        --author="$admin_email" \
        --url="https://$domain" \
        --timezone="$timezone" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=127.0.0.1 \
        --redis-port=6379; then

        error "Konfigurasi application environment gagal."

        return 1
    fi


    # ========================================================
    # DATABASE MIGRATION
    # ========================================================

    info "Migrating database..."


    if ! php artisan \
        migrate \
        --seed \
        --force; then

        error "Database migration gagal."

        return 1
    fi


    # ========================================================
    # CREATE ADMIN ACCOUNT
    # ========================================================

    info "Membuat administrator..."


    if ! php artisan \
        p:user:make \
        --email="$admin_email" \
        --username="$admin_username" \
        --name-first="$admin_first_name" \
        --name-last="$admin_last_name" \
        --password="$admin_password" \
        --admin=1; then

        warn "Pembuatan administrator otomatis gagal."

        warn "Coba jalankan manual:"

        echo

        echo "  cd /var/www/pterodactyl"

        echo "  php artisan p:user:make"

        echo

    else

        log "Administrator berhasil dibuat."

    fi


    # ========================================================
    # STORAGE LINK
    # ========================================================

    info "Membuat storage link..."


    php artisan \
        storage:link \
        >/dev/null 2>&1 \
        || true


    # ========================================================
    # PERMISSIONS
    # ========================================================

    info "Mengatur permission..."


    chown -R \
        www-data:www-data \
        /var/www/pterodactyl


    find \
        /var/www/pterodactyl \
        -type d \
        -exec chmod 755 {} \;


    find \
        /var/www/pterodactyl \
        -type f \
        -exec chmod 644 {} \;


    if [[ -d /var/www/pterodactyl/storage ]]; then

        chmod -R 775 \
            /var/www/pterodactyl/storage

    fi


    if [[ -d /var/www/pterodactyl/bootstrap/cache ]]; then

        chmod -R 775 \
            /var/www/pterodactyl/bootstrap/cache

    fi


    # ========================================================
    # AUTO IMPORT EGG
    # ========================================================

    echo

    echo "╭────────────────────────────────────────────────────╮"
    echo "│              AUTO EGG IMPORT                       │"
    echo "╰────────────────────────────────────────────────────╯"

    echo


    if import_pterodactyl_eggs; then

        log "Auto-import Egg: OK"

    else

        warn "Auto-import Egg gagal."

        warn "Panel tetap dilanjutkan."

        failed=1

    fi


    # ========================================================
    # NGINX CONFIG
    # ========================================================

    info "Membuat konfigurasi Nginx..."


    cat > /etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
    listen 80;
    listen [::]:80;

    server_name ${domain};

    root /var/www/pterodactyl/public;

    index index.php index.html;

    charset utf-8;

    client_max_body_size 100m;

    access_log /var/log/nginx/pterodactyl_access.log;
    error_log /var/log/nginx/pterodactyl_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }

    location = /robots.txt {
        access_log off;
        log_not_found off;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;

        fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$document_root;

        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    location ~* \.(?:css|js|jpg|jpeg|gif|png|svg|ico|webp|woff|woff2|ttf)$ {
        expires 7d;
        access_log off;
    }
}
NGINX


    # ========================================================
    # ENABLE NGINX SITE
    # ========================================================

    ln -sf \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf


    # ========================================================
    # REMOVE DEFAULT NGINX SITE
    # ========================================================

    rm -f \
        /etc/nginx/sites-enabled/default


    # ========================================================
    # ENSURE PUBLIC PERMISSIONS
    # ========================================================

    if [[ -d /var/www/pterodactyl/public ]]; then

        chmod 755 \
            /var/www/pterodactyl

        chmod 755 \
            /var/www/pterodactyl/public

        chown -R \
            www-data:www-data \
            /var/www/pterodactyl/public

        find \
            /var/www/pterodactyl/public \
            -type d \
            -exec chmod 755 {} \;

        find \
            /var/www/pterodactyl/public \
            -type f \
            -exec chmod 644 {} \;

    else

        error "Folder public Pterodactyl tidak ditemukan."

        return 1

    fi


    # ========================================================
    # NGINX TEST
    # ========================================================

    info "Memeriksa konfigurasi Nginx..."


    if ! nginx -t; then

        error "Konfigurasi Nginx tidak valid."

        return 1
    fi


    systemctl reload nginx


    # ========================================================
    # LOCAL NGINX TEST
    # ========================================================

    info "Memeriksa response website lokal..."


    local nginx_status=""

    nginx_status="$(
        curl -sS \
            -o /dev/null \
            -w "%{http_code}" \
            -H "Host: ${domain}" \
            http://127.0.0.1/ \
            2>/dev/null \
            || true
    )"


    case "$nginx_status" in

        200|301|302)

            log "Website lokal: HTTP ${nginx_status}"

            ;;

        403)

            error "Website lokal masih menghasilkan HTTP 403."

            error "Periksa:"
            error "/var/log/nginx/pterodactyl_error.log"

            failed=1

            ;;

        404)

            warn "Website lokal menghasilkan HTTP 404."

            warn "Laravel/Nginx perlu diperiksa."

            failed=1

            ;;

        500)

            warn "Website lokal menghasilkan HTTP 500."

            warn "Periksa Laravel/PHP-FPM."

            failed=1

            ;;

        *)

            warn "Response lokal tidak dapat diverifikasi: ${nginx_status:-unknown}"

            ;;

    esac


    # ========================================================
    # SSL
    # ========================================================

    info "Mencoba mengaktifkan SSL..."


    if command_exists certbot; then

        if certbot --nginx \
            -d "$domain" \
            --non-interactive \
            --agree-tos \
            -m "$admin_email" \
            --redirect; then

            log "SSL berhasil dikonfigurasi."

        else

            warn "SSL otomatis belum berhasil."

            warn "Pastikan DNS $domain sudah mengarah ke VPS."

        fi

    else

        warn "Certbot tidak tersedia. SSL dilewati."

    fi


    # ========================================================
    # QUEUE WORKER
    # ========================================================

    info "Membuat Pterodactyl Queue Worker..."


    cat > /etc/systemd/system/pteroq.service <<'SERVICE'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
Wants=redis-server.service

[Service]
User=www-data
Group=www-data

WorkingDirectory=/var/www/pterodactyl

Restart=always
RestartSec=5

ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
SERVICE


    # ========================================================
    # ENABLE QUEUE
    # ========================================================

    systemctl daemon-reload

    systemctl enable --now \
        pteroq


    if systemctl is-active \
        --quiet pteroq; then

        log "Pterodactyl Queue Worker: OK"

    else

        warn "Pterodactyl Queue Worker belum aktif."

        failed=1

    fi


    # ========================================================
    # SCHEDULER
    # ========================================================

    info "Mengaktifkan scheduler..."


    (
        crontab -u www-data -l \
            2>/dev/null |
        grep -v \
            'pterodactyl/artisan schedule:run' \
            || true

        echo \
            '* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1'

    ) | crontab -u www-data -


    # ========================================================
    # FINAL SERVICE CHECK
    # ========================================================

    info "Melakukan pengecekan akhir..."


    if systemctl is-active \
        --quiet nginx; then

        log "Nginx: OK"

    else

        warn "Nginx: FAILED"

        failed=1

    fi


    if systemctl is-active \
        --quiet "php${php_version}-fpm"; then

        log "PHP-FPM: OK"

    else

        warn "PHP-FPM: FAILED"

        failed=1

    fi


    if systemctl is-active \
        --quiet mariadb; then

        log "MariaDB: OK"

    else

        warn "MariaDB: FAILED"

        failed=1

    fi


    if systemctl is-active \
        --quiet redis-server; then

        log "Redis: OK"

    else

        warn "Redis: FAILED"

        failed=1

    fi


    if systemctl is-active \
        --quiet pteroq; then

        log "Pterodactyl Queue: OK"

    else

        warn "Pterodactyl Queue: FAILED"

        failed=1

    fi


    # ========================================================
    # FINAL FILE CHECK
    # ========================================================

    if [[ ! -f /var/www/pterodactyl/artisan ]]; then

        error "File artisan tidak ditemukan."

        return 1
    fi


    if [[ ! -f /var/www/pterodactyl/.env ]]; then

        error ".env Pterodactyl tidak ditemukan."

        return 1
    fi


    if [[ ! -f /var/www/pterodactyl/composer.json ]]; then

        error "composer.json Pterodactyl tidak ditemukan."

        return 1
    fi


    if [[ ! -d /var/www/pterodactyl/public ]]; then

        error "Folder public Pterodactyl tidak ditemukan."

        return 1
    fi


    # ========================================================
    # FINAL EGG CHECK
    # ========================================================

    if [[ -n "$IMPORTED_NODEJS_EGG_NAME" ]]; then

        info "NodeJS Egg: $IMPORTED_NODEJS_EGG_NAME"

    fi


    if [[ -n "$IMPORTED_PYTHON_EGG_NAME" ]]; then

        info "Python Egg: $IMPORTED_PYTHON_EGG_NAME"

    fi


    # ========================================================
    # CLEANUP
    # ========================================================

    rm -rf \
        "$extract_dir" \
        2>/dev/null \
        || true


    rm -f \
        "$archive" \
        2>/dev/null \
        || true


    # ========================================================
    # FINAL RESULT
    # ========================================================

    echo


    if [[ "$failed" -eq 0 ]]; then

        echo "╭────────────────────────────────────────────────────╮"
        echo "│                                                    │"
        echo "│       PUTZOFFICIAL PANEL INSTALLED                │"
        echo "│                                                    │"
        echo "╰────────────────────────────────────────────────────╯"

        echo


        info "Pterodactyl : ${tag:-existing}"

        info "Panel URL   : https://$domain"

        info "Database    : panel"

        info "DB User     : pterodactyl"

        info "PHP         : ${php_version}"

        info "Timezone    : ${timezone}"

        info "Nginx       : active"

        info "PHP-FPM     : active"

        info "Redis       : active"

        info "Queue       : active"

        info "Scheduler   : active"


        if [[ -n "$IMPORTED_NODEJS_EGG_NAME" ]]; then

            info "Egg NodeJS  : $IMPORTED_NODEJS_EGG_NAME"

        fi


        if [[ -n "$IMPORTED_PYTHON_EGG_NAME" ]]; then

            info "Egg Python  : $IMPORTED_PYTHON_EGG_NAME"

        fi


        echo

        info "Administrator:"

        info "Email       : $admin_email"

        info "Username    : $admin_username"

        info "Name        : $admin_name"


        echo

        log "Instalasi Pterodactyl selesai."


    else

        warn "Panel terpasang tetapi ada service/fitur yang perlu diperiksa."

        echo

        warn "Panel URL: https://$domain"

    fi


    echo
}


# ============================================================
# START
# ============================================================

install_panel
