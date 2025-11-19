create function escalate_me()
returns text
as $$
begin
	reset role;
	return current_user;
end;
$$ language plpgsql;

----- 

create user testuser;

grant usage on schema public to testuser;

create table public.permission_test (
	id int generated always as identity,
	secrecy_level text,
	secret text,
	check (secrecy_level in ('secret', 'top-secret'))
);

grant select, insert, update, delete on public.permission_test to testuser;

alter table public.permission_test enable row level security;

create policy testuser_read_secret
on public.permission_test
for select
using ((current_user = 'testuser' and secrecy_level = 'secret') or current_user = 'postgres');

insert into public.permission_test (secrecy_level, secret)
values
	('secret', 'Only secret'),
	('top-secret', 'Super secret')
;

select * from public.permission_test;

-----

create function pg_temp.foo()
returns record
security definer
as $$
	select escalate_me(), * -- Fails: "parameter role cannot be set in a security definer function"
	from public.permission_test
$$ language sql;

alter function pg_temp.foo owner to testuser;

set role testuser;

select pg_temp.foo();

select pg_temp.foo;

reset role;
