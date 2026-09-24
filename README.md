# Whisparr3.Net

A C# client for Whisparr 3 (Eros), generated from Whisparr's own OpenAPI specification. It covers
every operation in that specification. The package targets `net8.0` and `net10.0`.

## Quickstart

Follow these four steps in order. The order matters: the registration in step 3 validates the
options built in step 2, and refuses before it registers anything.

### 1. Install the package

```
dotnet add package Whisparr3.Net
```

### 2. Create the options

`Whisparr3Options` is a sealed class in the `Whisparr3.Net` namespace. It carries two `required`
init-only members.

- `BaseUrl` is the absolute `http` or `https` URL of your Whisparr instance, for example
  `http://127.0.0.1:6969`.
- `ApiKey` is the key Whisparr issued, used exactly as issued and never trimmed.

Both are `required`, so omitting either is a compile error at your own call site rather than a
runtime surprise. A blank or malformed value is refused inside `AddWhisparr3`, before anything is
registered, rather than at the first request. A bare host and port such as `localhost:6969` is
rejected there too, because it parses as an absolute URI whose scheme is the host name.

The API key is not optional. Whisparr's key enforcement is structural and has no off switch, so a
request that carries no key is refused whatever the instance's authentication settings say.

### 3. Register the client

`AddWhisparr3` is an extension method on `IServiceCollection` and takes the options positionally.
It registers every typed API, the API key token and the base address.

Call it once per service collection. A second call silently wins for both the base address and the
token, so two Whisparr instances need two service collections.

### 4. Make the first call

Resolve `ISystemApi`, call `GetSystemStatusAsync`, and pass the result through `EnsureSuccess` to
get a `SystemResource`.

Here is the whole quickstart as one program. Paste it over `Program.cs` in a new console project
and change the two values from step 2.

```csharp
using System;
using Microsoft.Extensions.DependencyInjection;
using Whisparr3.Net;
using Whisparr3.Net.Api;
using Whisparr3.Net.Model;

var services = new ServiceCollection();

services.AddWhisparr3(new Whisparr3Options
{
    BaseUrl = "http://127.0.0.1:6969",
    ApiKey = "your-api-key-here",
});

await using ServiceProvider provider = services.BuildServiceProvider();

SystemResource status = (await provider
    .GetRequiredService<ISystemApi>()
    .GetSystemStatusAsync())
    .EnsureSuccess();

Console.WriteLine(status.VarVersion);
```

It prints the version string of the instance you pointed it at.

## Two things that will catch you out

Neither is guessable and both bite within the first few minutes.

**The version member is spelled `VarVersion`.** `SystemResource` reports the instance version
through a member named `VarVersion`, not `Version`. The generator renames a member whose natural
name collides with a reserved one, and this is that rename surfacing on the first type you meet.

**`EnsureSuccess` is the classifier, and the generated success accessor is not.** The generated
accessor deserializes on the one status its operation documents and returns `null` on anything
else, so a rejected API key and an empty collection read the same to a caller. `EnsureSuccess`
separates the three outcomes. It returns the body on a success that carries one, and otherwise
throws a `Whisparr3ApiException` whose `IsSuccessStatusCode` tells a failed request apart from a
success with nothing to read. There is an overload per documented status, so it reads a create's
201 and an update's 202 the same way it reads a 200.

Every operation also exposes an `OrDefaultAsync` variant that wraps its whole body in a catch-all
returning `null`. That variant destroys the same distinction. Call the plain variant and use
`EnsureSuccess`.

## Responses that carry credentials

These operations change nothing and are safe to call, but their responses carry secrets. A log
line, a test transcript or an exception body from one of them writes a credential somewhere this
library never had it and cannot strip it.

| Operation | What its response carries |
| --- | --- |
| `GET /api/v3/config/host` | The instance API key and the admin password, both in plaintext. `HostConfigResource` declares `apiKey`, `password`, `passwordConfirmation`, `proxyPassword` and `sslCertPassword`. |
| `GET /api/v3/config/host/{id}` | The same resource, reached by id. |
| `GET /api/v3/log` | Log records from the instance database. Log text can contain the key. |
| `GET /api/v3/log/file/{filename}` | Raw log file text. |
| `GET /api/v3/log/file/update/{filename}` | The same, for the updater's log files. |

`Whisparr3ApiException.RawContent` is the verbatim response body and is deliberately not redacted,
because this library cannot know which fields of an arbitrary body are secret. Redaction, if you
want it, belongs in whatever writes your logs.

## Operations whose effect the specification does not describe

The specification constrains request shapes, not consequences. Three cases are worth knowing before
you call them.

- `POST /api/v3/command` takes a free-form `name` and nothing constrains it. The value alone selects
  between refreshing a movie's metadata and renaming every file on disk. `CommandApi.SendCommandAsync`
  is the hand-written method that can also carry a command's arguments, which no part of the
  specification describes.
- `POST /api/v3/release` pushes a release to a download client. It starts a real download and writes
  to the file system the instance manages, so its effect outlives the request.
- `DELETE /api/v3/moviefile/{id}` and `DELETE /api/v3/moviefile/bulk` delete files from disk, not just
  database rows, and `PUT` on either moves or rewrites them. There is no undo and no recycle step.

## Where to look next

- [CHANGELOG.md](CHANGELOG.md) records every release, and the [public API stability
  policy](CHANGELOG.md#public-api-stability-policy) at the bottom states what a version bump
  promises when a specification refresh renames a generated method.

## License

MIT. See [LICENSE](LICENSE).
