#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Użycie:
  db-check.sh --check                  test połączenia
  db-check.sh --list                   wyświetl rekordy z tabeli users
  db-check.sh --add USERNAME EMAIL     dodaj rekord (wypisuje jego id)
  db-check.sh --delete ID              usuń rekord o podanym id
EOF
    exit 1
}

PSQL="psql -v ON_ERROR_STOP=1"

[ $# -ge 1 ] || usage

case "$1" in
    --check)
        $PSQL -c "SELECT current_user, current_database(), inet_server_addr() AS server, s.ssl, s.version AS tls, s.cipher FROM pg_stat_ssl s WHERE s.pid = pg_backend_pid();" -c "SELECT version();"
        ;;
    --list)
        $PSQL -c "SELECT * FROM users ORDER BY id;"
        ;;
    --add)
        [ $# -eq 3 ] || usage
        echo "INSERT INTO users (username, email) VALUES (:'u', :'e') RETURNING id;" \
            | $PSQL -tA -v u="$2" -v e="$3" | head -n 1
        ;;
    --delete)
        [ $# -eq 2 ] || usage
        echo "DELETE FROM users WHERE id = :'id';" | $PSQL -v id="$2"
        ;;
    *)
        usage
        ;;
esac
