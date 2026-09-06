# The hand-written layer

`src/Whisparr3.Net/` is openapi-generator output and is rewritten on every regeneration.
`src/hand-written/` is the small layer this repository owns by hand, compiled into the same
assembly by one `Compile` glob in the library project file. It is five files:

| File | What it adds |
|---|---|
| `Whisparr3Options.cs` | The settings a consumer supplies, and the validation that refuses a bad one |
| `Whisparr3ServiceCollectionExtensions.cs` | `AddWhisparr3`, the single registration entry point, and the token provider behind it |
| `Whisparr3ApiException.cs` | The typed error, carrying status, route template, request URI and raw body |
| `ApiResponseExtensions.cs` | `EnsureSuccess` and `ReadAs`, plus three response hooks: the performer create's 201, the performer update's 202, and the tag create's 201 |
| `CommandApi.SendCommand.cs` | `SendCommandAsync`, the command dispatch that puts a flat body on the wire |

This document records what that layer does, what it costs, and what it deliberately leaves alone.

## Configuration

`Whisparr3Options` carries three members. `BaseUrl` and `ApiKey` are `required`, so omitting either
is a compile error at the consumer's own call site. `ConfigureHttpClient` is optional and is
described under resilience below.

Both required settings are validated inside `AddWhisparr3` before anything is registered. A blank
or malformed value throws there, not at the first request, and a rejected configuration leaves the
service collection untouched rather than half-registered.

The base URL check tests the scheme, not just parseability. A bare host and port such as
`localhost:6969` parses as an absolute URI whose scheme equals the host name, so a check that only
asked whether the string parsed would accept it and then fail obscurely inside `HttpClient`. The
value must be an absolute `http` or `https` URL.

The generated base-address constant is never relied on. It is `http://localhost:6969`, and a client
that reached it would send the API key to whatever happens to be listening on that port of the
machine the code runs on. `AddWhisparr3` always sets the base address from the supplied value.

The `required` modifier is a compile-time construct only. A configuration binder builds the options
type through reflection and bypasses it entirely, so it can hand back an instance whose key is
null. That is why the runtime validation is not redundant with the modifier.

```csharp
var services = new ServiceCollection();

services.AddWhisparr3(new Whisparr3Options
{
    BaseUrl = "http://127.0.0.1:6969",
    ApiKey  = apiKey,
});
```

## The API key

The key is required, header-only, and sent as `X-Api-Key` with nothing in front of the value.

There is one sharp edge here, and the wrapper hides it. The generated token constructor defaults
its prefix argument to a bearer scheme token and builds its raw value by concatenating that prefix
in front of the key. The prefixed form is measured against a real instance to return 401 with a
zero-byte body, so the failure hands the caller nothing to read and looks like a permissions
problem rather than a client defect. `AddWhisparr3` passes an empty prefix, once, at registration.

The spec still declares a query-parameter scheme named `apikey`, and this client does not use it.
That is a security decision about a working capability, not a statement that the capability is
unsupported: the query form is measured against a real instance to return 200. A client that used
it would work, and would write the credential into server access logs, proxy logs and browser
history. `Whisparr3Options` therefore exposes no scheme selector.

A null, empty or whitespace key is refused at construction. It is never trimmed and never repaired,
because a credential that needed repairing is a credential that was mistyped. The token provider
holds exactly one token, for the header it was built for, and refuses any other header name rather
than answering with a token that does not belong to it.

## The three outcomes

The generated success accessor deserializes on exactly 200 and returns `null` on anything else. A
401, a 200 whose body is JSON null, and a genuine 201 are therefore the same value to a caller.
`EnsureSuccess` classifies them apart:

| Outcome | Result | `IsSuccessStatusCode` on the exception |
|---|---|---|
| Failing status | throws `Whisparr3ApiException` | `false` |
| Success, body unreadable | throws `Whisparr3ApiException` | `true` |
| Success, body readable | returns the body | not applicable |

Two overloads cover the two response shapes the generated tree emits. The generic one binds to the
response interfaces that carry a typed success accessor. The non-generic one covers the rest, which
are roughly a third of the operations, and returns `void`.

```csharp
var status = (await system.GetSystemStatusAsync()).EnsureSuccess();
```

`EnsureSuccess` reads a body on any success status, for every operation. It routes a response this
library produced through `ApiResponse.ReadAs`, which gates on `IsSuccessStatusCode` rather than on
exactly 200, so a 201 and a 202 are as readable as a 200 with no per-operation help.

Three operations also carry a response hook this layer adds: the performer create, the performer
update and the tag create. The hooks make those operations' real 201, 202 and 201 bodies reachable
through the generated success accessor, which is a separate path from `EnsureSuccess` and still
gates on exactly 200 without them. They stay because a caller who reads the generated `Ok()` or
`TryOk()` directly still needs them, and removing them would silently return that caller to `null`
on a 201. The generated documentation comments on those operations were written before the hooks
existed and say less than the accessor now does, so a reader of those comments alone would not
expect a body there.

The two performer hooks read a status the spec documents, so the generator emits an `IsCreated` and
an `IsAccepted` member for them and each hook reads its own. The tag create hook has no such member
to read. The generator emits `IsCreated` only where the spec documents 201, the tag create's spec
documents 200 only, and the instance answers 201 anyway, so that hook compares the status code
directly. Writing the performer guard there would not compile.

`Whisparr3ApiException.RawContent` is the verbatim response body and is deliberately not truncated.
For `GET /api/v3/config/host` that body contains the instance API key and the admin password in
plaintext, and the log-file operations return raw log text that can contain the key as well.
Logging one of those exceptions verbatim writes a credential this library never asked for. The
exception message embeds at most 512 characters of the body; the untruncated value is on the
property, where the choice to log it is the consumer's own.

## The command dispatch

`POST /api/v3/command` is the one operation whose request body the spec describes wrongly rather
than incompletely. `CommandResource` is `additionalProperties: false`, so the generated writer emits
a fixed property list and the generated create operation cannot put a command argument on the wire
at all. Whisparr declares 42 commands and 25 of them take arguments.

`CommandApi.SendCommandAsync` is what closes that:

```csharp
CommandResource queued = await commands.SendCommandAsync(
    "RefreshStudios", new { studioIds = new[] { 7 } });
```

The payload members are serialized flat, as siblings of `name`, because the server rewinds the
request stream and deserializes the whole body into a concrete command type. Arguments placed under
`CommandResource.Body` reach the server as a command with no arguments.

The parameter is `object?` because no per-command shape is derivable from the spec. Anything that
serializes to a JSON object is accepted, and a command that takes no arguments is dispatched by
omitting the payload. Two payloads are refused with `ArgumentException` before a socket opens: one
that does not serialize to a JSON object, and one carrying its own member named `name` under a
case-insensitive comparison. The second is refused rather than merged, because a differently-cased
key would survive alongside the command name and leave the server two candidates for one property.

The method is declared on the concrete `CommandApi`. `ICommandApi` is generated and is not declared
`partial`, so it cannot carry the method. `AddWhisparr3` registers the concrete type as a transient
delegating to the generated interface registration, so a consumer resolves `CommandApi` and calls
the method with no cast.

## What not to call

Every operation has a second variant whose name ends in `OrDefaultAsync`, and whose entire body is
wrapped in a catch-all that returns null. It swallows configuration errors, transport errors and
authentication failures alike. It is a third silent-null path on top of the two this layer exists
to close.

It exists, it is generated, and no example in this document uses it. Call the plain variant and
call `EnsureSuccess` on the result.

## Resilience, and what it costs

Three Polly policies ship with the generated tree as extension methods on `IHttpClientBuilder`:

| Method | Signature |
|---|---|
| `AddRetryPolicy` | `(int retries)` |
| `AddTimeoutPolicy` | `(TimeSpan timeout)` |
| `AddCircuitBreakerPolicy` | `(int handledEventsAllowedBeforeBreaking, TimeSpan durationOfBreak)` |

They live in the `Whisparr3.Net.Extensions` namespace, so reaching them needs one import beyond the
root namespace:

```csharp
using Whisparr3.Net;
using Whisparr3.Net.Extensions;

services.AddWhisparr3(new Whisparr3Options
{
    BaseUrl = "http://127.0.0.1:6969",
    ApiKey  = apiKey,
    ConfigureHttpClient = builder => builder
        .AddRetryPolicy(3)
        .AddTimeoutPolicy(TimeSpan.FromSeconds(30))
        .AddCircuitBreakerPolicy(5, TimeSpan.FromSeconds(30)),
});
```

`ConfigureHttpClient` is invoked once per typed client, so a policy set there applies to all of
them.

**What this layer gave up to get here.** `AddWhisparr3` registers its token provider directly as a
singleton and registers no token container. The generated registration installs its own rate-limit
provider only when it finds a container and no provider, so registering the provider directly means
that rate limiter is never installed. Measured over 20 sequential loopback calls:

| Configuration | Throughput |
|---|---|
| Generated rate-limit provider installed | 23.5 requests per second |
| Provider registered directly, as this layer does | 555.6 requests per second |

The rate limiter was a self-imposed throughput cap of roughly 23 requests per second, and removing
it is most of why the client is usable. The cost is that it was also the only 429 backoff in the
stack. Polly's transient-error helper, which the generated retry policy is built on, handles 5xx
and 408 and does not handle 429, so nothing in the shipped configuration backs off when Whisparr
answers 429.

A consumer who needs that can add a policy through the same `ConfigureHttpClient` hook, handling
`HttpStatusCode.TooManyRequests` and honouring `Retry-After`. Whisparr's own rate limits are
unmeasured. If verification against a live instance ever observes a 429, this tradeoff should be
revisited rather than worked around at the call site.

## One registration per collection

A second `AddWhisparr3` call on the same collection wins, for both the base address and the token
provider, with no error and no warning. That is measured, and it is a limitation of the generated
registration layer rather than a choice made here: the named client configuration and the token
provider registration are both last-wins, and there is no keyed-instance concept to make two
instances addressable. Two Whisparr instances therefore need two service collections.

The limit is documented rather than made to throw. An early throw would impose a hand-written
policy on top of a generated limitation, and it would break a composition root that a test
legitimately rebuilds. What was actually wrong with the behaviour was that it was invisible, and
this section is the fix for that.

## Dependencies

The library declares four package references, all published by Microsoft: three under
`Microsoft.Extensions.` and `Microsoft.Net.Http.Headers`. The built assemblies reference nothing
beyond the base class library, those packages, and the Polly assemblies they bring with them. That
closure was inspected through the assembly metadata on both target frameworks rather than inferred
from the project file.

Nothing in the public surface dictates how a consumer stores credentials. `Whisparr3Options.ApiKey`
is a plain `string` with no interface behind it, no provider abstraction and no coupling to any
configuration system. Read it from an environment variable, a secret store or a prompt; this
library has no opinion and offers no hook that would give it one.

## The consumer path, proven from a plain console app

The layer is meant to work from a bare `ServiceCollection` with no Generic Host, no application
builder and no logging registration of the consumer's own. That claim is proven rather than
asserted: a throwaway console application was built outside this repository, run once, and deleted.
Its source, its project file and its output are recorded below so a reader can reproduce it.

The project lived at `%TEMP%\whisparr3-ergo09`. Building it outside the repository is deliberate.
A project inside the tree inherits `Directory.Build.props`, which sets `PackageId` and
`TargetFrameworks` for everything under the root, and it would have needed the same two overrides
the test project needs. That would have made the proof a statement about this repository's build
configuration rather than about the consumer path.

### The project file

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>Whisparr3.Ergo09</RootNamespace>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="<repo-root>\src\Whisparr3.Net\Whisparr3.Net.csproj" />
  </ItemGroup>

</Project>
```

`<repo-root>` stands for the absolute path of this clone. A consumer installs the package instead
and needs no `ProjectReference` at all.

### The program

The three consumer-facing `using` directives are exactly the three the namespace layout predicts:
`Whisparr3.Net` for the options type, the registration call and the success accessor,
`Whisparr3.Net.Api` for the typed client interface, and
`Microsoft.Extensions.DependencyInjection` for the collection itself. The three above them belong
to the stub instance the program starts for itself and are not part of the consumer path.

```csharp
// The three using directives below the blank line are the consumer path. The three above it
// belong to the stub instance this program starts for itself, not to the client library.
using System.Net;
using System.Net.Sockets;
using System.Text;

using Microsoft.Extensions.DependencyInjection;
using Whisparr3.Net;
using Whisparr3.Net.Api;

// A stub instance on a loopback port, so the call crosses a real socket and reaches no real server.
const string body = """{"appName":"Whisparr","version":"3.3.8.1097","branch":"eros"}""";

var listener = new TcpListener(IPAddress.Loopback, 0);
listener.Start();
int port = ((IPEndPoint)listener.LocalEndpoint).Port;

var serving = Task.Run(async () =>
{
    using TcpClient socket = await listener.AcceptTcpClientAsync();
    using NetworkStream stream = socket.GetStream();

    var request = new byte[4096];
    int read = await stream.ReadAsync(request);
    Console.WriteLine("--- request bytes off the socket ---");
    Console.WriteLine(Encoding.ASCII.GetString(request, 0, read).TrimEnd());
    Console.WriteLine("--- end request ---");

    string response = "HTTP/1.1 200 OK\r\n"
        + "Content-Type: application/json\r\n"
        + $"Content-Length: {Encoding.UTF8.GetByteCount(body)}\r\n"
        + "Connection: close\r\n"
        + "\r\n"
        + body;

    await stream.WriteAsync(Encoding.UTF8.GetBytes(response));
    await stream.FlushAsync();
});

// The consumer path starts here: a plain ServiceCollection and one registration call.
var services = new ServiceCollection();

services.AddWhisparr3(new Whisparr3Options
{
    BaseUrl = $"http://127.0.0.1:{port}",
    ApiKey = "SENTINEL-Key-123",
});

var provider = services.BuildServiceProvider();

var system = provider.GetRequiredService<ISystemApi>();

var response = await system.GetSystemStatusAsync();

var status = response.EnsureSuccess();

await serving;
listener.Stop();

Console.WriteLine($"appName = {status.AppName}");
Console.WriteLine($"version = {status.VarVersion}");
Console.WriteLine($"branch  = {status.Branch}");

if (status.VarVersion != "3.3.8.1097")
{
    Console.Error.WriteLine("ASSERTION FAILED: the version field did not survive the round trip.");
    return 1;
}

Console.WriteLine("CONSUMER-PATH-OK");
return 0;
```

Two details in that program are worth keeping.

The key is the obvious non-secret `SENTINEL-Key-123`. No real credential appears in this repository,
and this program never contacts a real instance.

The printed member is `VarVersion`, not `Version`. The generator renames the JSON `version` field
because `Version` collides on the generated model, and a consumer reading the OpenAPI document
alone would not predict that name.

### The transcript

Run once with `dotnet run` from the project directory, after `bin/` and `obj/` were removed:

```
--- request bytes off the socket ---
GET /api/v3/system/status HTTP/1.1
Host: 127.0.0.1:22372
X-Api-Key: SENTINEL-Key-123
Accept: application/json
--- end request ---
appName = Whisparr
version = 3.3.8.1097
branch  = eros
CONSUMER-PATH-OK
exit=0
```

The port is ephemeral and differs per run. The three printed values came out of a deserialized
`SystemResource`, not out of the raw body, and the program returns a non-zero exit code if the
version field does not round-trip.

`dotnet --version` reported `10.0.400`. Run on 2026-09-04. The project directory was deleted
afterwards.

## Carried forward

Two items are recorded here. The first was carried forward and has since been measured and acted
on; it is kept because the measurement contradicts the spec and a reader needs to know that. The
second is still open.

A create, read-back and delete round-trip against a real instance has to be written carefully, and
picking a resource whose create the spec documents as 200 is not the way out. Measured against the
pinned image: a tag create answers **201** whatever the spec says, and a tag update answers **202**.
The spec's documented codes describe what the server was thought to do, not what it does. The hook
in this layer makes the tag create's body readable, and a round trip must assert through
`EnsureSuccess` rather than through the generated success accessor.

The operations whose response type carries no typed success accessor are listed in
[SURFACE.md](SURFACE.md), which is generated from the committed specification. Do not copy the
count out of it into prose here or into the published README: it moves with every Whisparr release,
and a copy goes stale silently. Link to the document instead.
