# Authorization
## The problem
Postgres comes with row level security, but when running under a bouncer (which grestless effectively is), there is a fundamental problem. 

A bouncer wants to connect to the database using a single user, which in grestless is configured using the `authentication_user` configuration flag. When a request comes in, the bouncer determines the correct role to execute the query as based on the request's authorization, and then drops privileges to that role using `set role`. It will then execute the query, and finally revert to its original role using `reset role` to handle the next request.

The problem here is that `reset role` is not authenticated in any way. A user able to submit queries, no matter how lowly privileged, is always able to execute `reset role` and will then have `authentication_user` privileges for the rest of their query. This obviously breaks the entire authorization scheme.

The way pgbouncer fixes this is by asking clients for the username and password of an actual database user, and then using those credentials to actually log in for the session. This works, but it means that clients need to know actual database users and passwords to be able to log on, which comes with a host of disadvantages:
* An application user cannot log in unless their user name is known to Postgres. This means that application users need to be managed as database roles, which increases operative complexity.
* Authentication mechanisms common on the web (such as OAuth and WebAuthN) cannot be used, as they do not provide a password to the bouncer.
* Row level security policies can only be based on `current_user`. Other information, such as the client's network address, OAuth token, etc., cannot be used in policies.[^1]

Another way of going about this is to simply not allow the client to run SQL. If the client can't run SQL, it follows that they can't run `reset role`, and therefore, there's no security problem. This is how PostgREST solves this issue. However, we would *like* to be able run SQL because we love it, or at least prefer it over an eldritch pseudo-DSL crammed into HTTP query parameters.[^2]

## The grestless solution
Instead of throwing out the child with the bathwater by declaring all SQL to be verboten, grestless should wrap the user-provided SQL query in such a manner that it will execute normally, but cannot run `reset role`. But how can we safely achieve this? Postgres provides no way of disabling `reset role`, neither for the current session nor even globally, and the naive attempt of just grepping the client's query for `reset role` would be foiled by attackers that just spell the same thing differently (consider `execute 're' + 'set ' + 'ro' + 'le';`).

However, when we carefully thumb through the Postgres manual, we will eventually happen upon this short, innocuous sentence:

> SET ROLE cannot be used within a SECURITY DEFINER function.[^3]

What this doesn't state (although suggests, as `set role` and `reset role` are listed on the same manual page) is that `reset role` *also* cannot be used within a `security definer` function. And indeed it can't! Furthermore, this property is not only true for the body of the function itself, but also for any callee functions invoked from it, irrespective of whether those functions are themselves declared `security definer` or not.[^4] We have found our solution, then: if we first store the client's entire SQL query as a stored function with `security definer`, change function ownership to the client's authorized role (making them the `definer` that the function runs as), and finally drop privileges and call that function, we can be certain that nothing the query does will be able to change its role or get access to any functions or data that the role should not have access to.

This way, row level security can be enhanced with any number of facts about the client, while ensuring that these facts are read-only to the client's SQL query.

[^1]: Because in the pgbouncer model the bouncer uses the same role to connect to the database server as it uses to run the client's query, it cannot do the PostgREST dance of first setting up variables or temporary tables that contain other information about the client, then making those variables read-only for the query user, and finally dropping privileges to the query user to run the query. This is because the bouncer's session has no other role to run this setup phase as, and if the bouncer were to use the only role it does have -- the query user itself -- to set up these values, the values would not be read-only and the client could easily craft a malicious query that alters this information to whatever it wants before accessing the table for which the row level security policy executes.

[^2]: And no, GraphQL is not the solution.

[^3]: https://www.postgresql.org/docs/18/sql-set-role.html

[^4]: The reasons for this restriction are not entirely clear to me. The same restriction does *not* apply to views, even though views are `security definer` (aka `security_invoker=false`) by default. A `security invoker` function called from a `security definer` view will happily `reset role` the current session, but a `security invoker` function called from a `security definer` function will fail.
