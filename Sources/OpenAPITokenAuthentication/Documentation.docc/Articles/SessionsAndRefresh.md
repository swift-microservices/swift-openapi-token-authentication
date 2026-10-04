# Sessions and refresh

How a session shares sign-in and refresh work, when the middleware retries, and what clears
credentials.

## One session, shared work

``AuthenticationSession`` serializes access to credentials. While a sign-in or a refresh is in
flight, every caller of ``AuthenticationSession/accessToken()`` waits on that same work instead
of starting its own. Share one session across the clients that use the same credentials, and use
separate sessions for separate accounts.

An access token is refreshed on demand when it is within the session's refresh leeway of its
expiration, 30 seconds by default. Only overlapping refreshes share work; a later rejected
response can trigger another refresh.

## When the middleware retries

``AuthenticationMiddleware`` refreshes on HTTP 401 by default. Pass `refreshableStatusCodes`, or a
predicate over the response, to change that. It retries a request once, and only when its body
can be sent again; a request with a single-use body is returned as it is.

## Anonymous requests

The default ``AuthenticationPolicy/required`` policy needs a token. With
``AuthenticationPolicy/ifAvailable``, the middleware still waits for any in-flight sign-in or
refresh, and when the lookup throws ``AuthenticationSessionError/userAuthenticationRequired`` it
sends the request unchanged, without an `Authorization` header and without refresh or retry. Other
lookup errors, such as transport failures and cancellation, propagate. Once a token is attached,
the authenticated refresh and retry behavior applies. The server still enforces authorization.

## Errors and credentials

An ``AuthenticationClient`` classifies rejected credentials with ``AuthenticationClientError``:
``AuthenticationClientError/Code/invalidCredentials`` for sign-in and
``AuthenticationClientError/Code/invalidRefreshToken`` for refresh. Other errors propagate
unchanged.

Missing, expired, or rejected refresh credentials clear the session and its storage, and throw
``AuthenticationSessionError/userAuthenticationRequired``. A temporary refresh failure keeps
valid refresh credentials so a later call can retry.

## Cancellation

Cancelling an API request does not cancel the shared sign-in or refresh work it waits on.
``AuthenticationSession/logout()`` and a replacement sign-in cancel pending work and prevent its
result from restoring credentials. Cancelling an observation of
``AuthenticationSession/states()`` does not cancel authentication.
