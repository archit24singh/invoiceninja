#!/bin/sh

# Process initializer files by extension
docker_process_init_files() {
    echo
    local f
    for f; do
        case "$f" in
        *.sh)
            if [ -x "$f" ]; then
                in_log INFO "$0: running $f"
                "$f"
            else
                in_log INFO "$0: sourcing $f"
                . "$f"
            fi
            ;;
        *) in_log INFO "$0: ignoring $f" ;;
        esac
        echo
    done
}

php artisan config:cache
php artisan optimize
php artisan package:discover

# Verify DB connectivity; abort if unavailable
DB_READY=$(php artisan tinker --execute='echo app()->call("App\Utils\SystemHealth@dbCheck")["success"];')
if [ "$DB_READY" != "1" ]; then
    php artisan migrate:status
    in_error "Error connecting to DB"
fi

php artisan migrate --force

# Seed and create initial account on first run
IN_INIT=$(php artisan tinker --execute='echo Schema::hasTable("accounts") && !App\Models\Account::all()->first();')
if [ "$IN_INIT" = "1" ]; then
    docker_process_init_files /docker-entrypoint-init.d/*
fi
