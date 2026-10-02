#!/bin/sh
# ---------------------------------------------------------------------------
# memcached entrypoint — the SASL database, built from the file secret.
#
# This started life as an inline compose `command:`. It is a file because an
# inline one cannot be trusted: Compose interpolates `$NAME` and `${NAME}` in the
# compose file itself, and its `$$` escape does not cover every form — a rendered
# configuration was observed turning `$$HOSTNAME` into the *host's* hostname and
# `$$MEMCACHED_PASSWORD_FILE` into nothing, which yields an empty password in the
# SASL database and an "Auth failure" for every client while both containers hold
# the same secret. A script has no interpolation, and it can be tested.
#
# The database is keyed `user@realm`, and the realm is the name the server reports
# for itself — not necessarily the short HOSTNAME. One entry is written per name
# this container can present, so a client matches whichever one memcached uses.
# ---------------------------------------------------------------------------
set -eu

password_file="${MEMCACHED_PASSWORD_FILE:-/run/secrets/zulip__memcached_password}"
sasl_conf="${SASL_CONF_PATH:-/home/memcache/memcached.conf}"
sasl_db="${MEMCACHED_SASL_PWDB:-/home/memcache/memcached-sasl-db}"

if [ ! -s "$password_file" ]; then
  echo "memcached: the password secret is missing or empty at $password_file" >&2
  exit 1
fi
if [ ! -r "$password_file" ]; then
  echo "memcached: the password secret at $password_file is not readable by uid $(id -u)" >&2
  exit 1
fi

password="$(cat "$password_file")"
if [ -z "$password" ]; then
  echo "memcached: the password secret at $password_file is empty" >&2
  exit 1
fi

echo 'mech_list: plain' >"$sasl_conf"

# Every name the server may report as its realm, plus the two a client may use.
: >"$sasl_db"
for host in "${HOSTNAME:-}" "$(hostname)" "$(hostname -f 2>/dev/null || true)" localhost 127.0.0.1; do
  [ -n "$host" ] || continue
  echo "zulip@$host:$password" >>"$sasl_db"
done

if [ ! -s "$sasl_db" ]; then
  echo "memcached: the SASL database ended up empty" >&2
  exit 1
fi

exec memcached -S
