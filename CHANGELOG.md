# Changelog

Every release of Whisparr3.Net is recorded here, newest first. The stability policy the version
numbers refer to is at the bottom of this file and does not move.

## 0.4.0

Regenerated against Whisparr `v3.6.2-release.1727`, the first release branch build carrying
Whisparr's OpenAPI accuracy work. The served document now validates, names every operation and
declares the status each one really answers. Almost everything below follows from that rather than
from a decision taken here.

**If you are upgrading, expect your build to stop compiling.** Every rename is a missing-name
error at your own call site, never a silent behaviour change. The new name is the `operationId`
Whisparr assigns the operation, so `git diff` between the two committed copies of
`spec/openapi.generated.json` gives the complete old-to-new mapping.

### Breaking

- **212 of 266 methods are renamed.** Names now come from the `operationId` Whisparr assigns each
  operation, where before they were derived here from the URL and corrected by a 13-entry override
  table. `ListAlternativeTitleAsync` is `GetAlttitleAsync`, `CreateTagAsync` is `PostTagAsync`,
  `UpdatePerformerAsync` is `PutPerformerByIdAsync`. Response interfaces and classes rename with
  their method. The other 54 keep their names, and there is no compatibility shim.

- **Six operations are gone.** `GetStaticResourceByPathAsync`, `GetContentByPathAsync` and
  `GetLoginPageAsync` served Whisparr's browser interface and are excluded from the document
  upstream. `GetPerformerByPerformerForeignIdAsync` and `GetStudioByStudioForeignIdAsync` fold into
  `GetPerformerByIdAsync` and `GetStudioByIdAsync`, which is the same lookup reached by the same
  route. `PutMovieFileEditorAsync` is gone because `PUT /api/v3/moviefile/editor` is gone.

- **Creates and updates carry `ICreated<T>` and `IAccepted<T>`, not `IOk<T>`.** Whisparr corrected
  46 operations that answered 201 or 202 while documenting 200. `EnsureSuccess` has an overload for
  each, so a call site that used it needs no edit; one that called `Ok()` directly must call
  `Created()` or `Accepted()`.

- **Request bodies are required.** No `[FromBody]` parameter in Whisparr is nullable and a request
  omitting the body is rejected with a 400 before the action runs, so the generated methods take
  the resource positionally rather than as an `Option`.

- **`ApiResponse.ReadAs<T>()` is removed**, along with the three response hooks beside it. `ReadAs`
  existed so a caller could name a shape for the 92 operations that declared a 2xx with no content,
  and the hooks read a real 201 or 202 through an accessor that gated on 200. 228 of the 273
  operations bind to a generated model now and the other 45 genuinely return nothing. Call
  `EnsureSuccess` and take the model.

- **A success status an operation does not document now throws.** The library no longer reads a body
  off a status the document does not declare, because the document is right: measured against the
  pinned release, a tag create answers 201 and a tag update answers 202, both as declared. The
  exception carries the status and reports `IsSuccessStatusCode` as true, so drift upstream is loud
  rather than silent.

### Added

- Seven operations. Five are library search, new in Whisparr 3.6.2: `GetLibrarySearchAsync` across
  everything, plus `GetLibrarySearchMovieAsync`, `GetLibrarySearchPerformerAsync`,
  `GetLibrarySearchSceneAsync` and `GetLibrarySearchStudioAsync` for one kind each.
  `GetStatisticsAsync` and `GetQualityprofileByIdInuseAsync` are the other two.

- `EnsureSuccess` returns the response text verbatim for a string-typed operation. Six of them send
  text rather than a JSON string literal: `GET /api/v3/system/routes`, the two log file routes, the
  calendar feed, mediacover and localization. The overload is non-generic, so the call site reads
  the same as any other.

### Internal

- Spec pre-processing is down to one transform. The `operationId` derivation, its override table
  and the malformed-root-path deletion are all gone, because the document no longer needs them.
  What remains narrows the root security requirement to the header scheme, which is still required:
  generated from the document as served, every request would carry the key in its query string.

- Spec validation is on. The document did not validate before, so the generator ran with
  `validateSpec: false`. It is a gate now rather than a workaround.

- `spec/PROVENANCE.json` records the source container under `image`, which holds a full pullable
  reference, replacing `imageDigest`.

## 0.3.0

Two breaking changes, both from integrating the package into its first real consumer.

- **Breaking.** `CommandApi.SendCommandAsync` now returns `Task<ICreateCommandApiResponse>` instead
  of `Task<CommandResource>`, and reports a refused command through the returned status instead of
  by throwing. It is the shape every generated operation returns, so a command is classified the
  same way as every other call. Call `EnsureSuccess()` on the result to get the `CommandResource`
  and keep the previous throwing behaviour.

  Returning the model gave a caller no status on the accepted path and a status only on the refusal
  path, off a caught exception. A caller that must not re-issue a command, such as a search, had
  nothing to record for the call it made and had to compose a status it never received. Measured
  against 3.4.0.1387: the instance answers 201 to an accepted command and 400 to an unrecognised
  one, and the specification declares only 200, so the generated `Ok()` accessor returns null even
  on the accepted path. `EnsureSuccess()` reads the body on any success status and is what a caller
  wanting the model should use.

- **Breaking.** `Microsoft.Extensions.Http.Polly` is no longer a dependency, and the three generated
  builder extensions `AddRetryPolicy`, `AddTimeoutPolicy` and `AddCircuitBreakerPolicy` are gone.
  They were one-line wrappers over `AddPolicyHandler`, and keeping them added `Polly.dll`,
  `Polly.Extensions.Http.dll` and `Microsoft.Extensions.Http.Polly.dll`, 327 KB in total, to every
  consumer whether or not it called any of the three. The reference also resolved Polly 7.2.4,
  pinning the previous Polly major on a consumer that wanted Polly 8 through
  `Microsoft.Extensions.Http.Resilience`.

  `Whisparr3Options.ConfigureHttpClient` is unchanged and still hands out the `IHttpClientBuilder`
  those wrappers took, so a consumer attaches retry, timeout or a circuit breaker from whichever
  resilience package it already uses. Replace `.AddRetryPolicy(3)` with
  `.AddPolicyHandler(HttpPolicyExtensions.HandleTransientHttpError().RetryAsync(3))` and add
  `Microsoft.Extensions.Http.Polly` to your own project, or use the policy shape of whatever
  resilience package you prefer.

- `CommandApi.SendCommandAsync` now raises `CommandApiEvents.OnCreateCommand` and
  `OnErrorCreateCommand`, and writes the request-completion log line, the same three things the
  generated `CreateCommandAsync` does. The dispatch assembles its own request, so it was skipping
  the generated post-response steps, which made a command the one call a consumer watching the
  api's logs or events could not see. Nothing a caller observes changes: an exception still
  propagates unwrapped.

## 0.2.0

Adds command dispatch, and corrects how a response body is read.

- `CommandApi.SendCommandAsync` dispatches a command with its arguments. The generated create
  cannot: `CommandResource` declares no additional properties, so its writer emits a fixed property
  list, and 25 of Whisparr's 42 commands take arguments that no part of the specification describes.
  The arguments go on the wire as siblings of `name`, which is the shape the instance accepts.
- `AddWhisparr3` now registers the concrete `CommandApi` alongside `ICommandApi`. Inject
  `CommandApi` to reach `SendCommandAsync`; the interface is generator output and cannot carry it.
- `EnsureSuccess` reads a body on any success status rather than on 200 alone. The instance answers
  201 to a create and 202 to an update while the specification declares 200 for both, so every
  create and update previously reported a successful call as a failure.

## 0.1.0

The first release, and the first published to nuget.org.

- Covers every operation the Whisparr 3 (Eros) API declares, generated from Whisparr's own
  OpenAPI specification. The one malformed root path is excluded.
- Targets `net8.0` and `net10.0`, with an assembly and an XML documentation file shipped for each.
- One registration entry point, `AddWhisparr3`, which validates the base URL and the API key and
  registers nothing until both pass.
- One typed error, `Whisparr3ApiException`, carrying the status, the route template, the request
  URI and the raw body, and distinguishing a failed request from a success with no readable body.
- `EnsureSuccess` classifies a response, which the generated success accessor does not.
- A large minority of operations return no value, because the specification declares no response
  content for them.

## Public API stability policy

Version numbers follow semantic versioning, and what they apply to is the public API surface of
the `Whisparr3.Net` package: the hand-written entry points, and every generated API interface,
method signature and model type the package exposes.

**While the major version is 0, that surface is not frozen.** A minor release may rename, change or
remove a public member. In practice this means you should pin an exact version rather than a range,
and read this file before you move.

### A specification refresh can rename a public method

This is the clause that matters most, because it is the one that can break a consumer without
anyone deciding to break it.

Method names in this library are the operation identifiers the specification assigns, taken at
generation time. They are not pinned by a committed map. A Whisparr release that renames an
operation therefore renames the corresponding public method here.

What that does to your build is concrete: it stops compiling, at your own call site, with an error
saying the name no longer exists. It is not a silent behaviour change and it is not deferred to
runtime.

When it happens:

- The rename moves the minor version component while the major version is 0, and will move the
  major component once the major version reaches 1.
- The changelog entry names the rule that produced the renames and gives worked examples. It does
  not reproduce the full list, because the list is derivable: method names are the specification's
  operation identifiers, and both the old and the new `spec/openapi.generated.json` are committed,
  so a diff between the two tags is the complete mapping. A refresh is never summarised as a
  version bump alone.

### How you find out

Two ways, and both are meant to reach you before you upgrade.

- The changelog entry for the release, above. It names every rename by name.
- The refresh itself. Moving to a new Whisparr version arrives in this repository as a pull
  request that shows the regenerated tree, rather than as a direct commit to the default branch, so
  the renamed methods are visible in a diff before they are ever released.
