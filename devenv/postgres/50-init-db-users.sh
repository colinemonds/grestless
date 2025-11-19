#!/usr/bin/env bash
set -e

psql -v on_error_stop=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    create user $AUTHENTICATED_USER nologin noinherit;
	grant usage on database $POSTGRES_DB to $AUTHENTICATED_USER;
    grant usage on schema public to $AUTHENTICATED_USER;

	create user $AUTHENTICATOR_USER with password '$AUTHENTICATOR_PASSWORD' noinherit;
    grant $AUTHENTICATED_USER to $AUTHENTICATOR_USER;
EOSQL
