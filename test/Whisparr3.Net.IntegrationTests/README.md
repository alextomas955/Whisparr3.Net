# What this suite is allowed to call

This is a rule for contributors to this repository, not advice for anyone using the library. It
governs what the integration tests may do to a live Whisparr instance. What a consumer of the SDK
calls is their own decision.

`docs/SURFACE.md` records which operations have effects the spec does not describe. Read it before
adding a test that writes.

## What the suite writes today

Counted from the tests rather than described. It creates two tags with `POST /api/v3/tag` and
deletes two tags with `DELETE /api/v3/tag/{id}`. It also attempts one further create by hand with a
`text/json` content type, which the server refuses with 415 and which creates nothing.

That is the whole write inventory. A change to it should be visible in a diff to this file.

## What keeps the suite off any other instance

Two separate protections, and confusing them is how a test ends up pointed somewhere real.

Every client in the suite is built from `WhisparrFixture.BaseUrl`, which is read back from the
daemon after the container starts. No host port and no host name is written into the test project,
so a test cannot address anything else. This is the protection that matters.

The container is separately published on a random loopback port. That keeps its API key off every
interface but the loopback one. It places no constraint on what address a client in the test
process dials, so a contributor who trusts the port binding for that could add a test carrying a
literal URL and believe the binding still protects them. It does not. This machine runs a real
Whisparr of its own on another port.

## What is not enforced

Nothing structurally prevents a contributor adding a call to a destructive operation. There is no
allowlist type, no source analyzer over the test project and no run-time check.

The mitigations are the two above plus the fact that the suite is small enough that reading it is
the verification. Those are real and they are not the same as enforcement.

If standing enforcement is ever wanted, the honest form is a source analyzer over this project that
fails the build on a call to a named operation. A run-time harness is the wrong shape: it can only
refuse a call the suite already made, which is after the instance has been asked to make the change.
