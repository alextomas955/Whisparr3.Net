# Whisparr3.Net

A C# client for Whisparr 3 (Eros), generated from Whisparr's own OpenAPI specification. It covers
every operation in that specification except the one malformed root path, which is 272 operations.
The package targets `net8.0` and `net10.0`.

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
accessor deserializes on exactly 200 and returns `null` on anything else, so a rejected API key and
an empty collection read the same to a caller. `EnsureSuccess` separates the three outcomes. It
returns the body on a success that carries one, and otherwise throws a `Whisparr3ApiException`
whose `IsSuccessStatusCode` tells a failed request apart from a success with nothing to read.

Every operation also exposes an `OrDefaultAsync` variant that wraps its whole body in a catch-all
returning `null`. That variant destroys the same distinction. Call the plain variant and use
`EnsureSuccess`.

## Where to look next

- [docs/SURFACE.md](docs/SURFACE.md) lists the operations that return nothing, with the count and
  the reason in the specification, and the six operations that exist but are not useful from C#.
- [docs/DO-NOT-CALL.md](docs/DO-NOT-CALL.md) lists every operation that changes state on the
  instance, and names the seven that are worse than the rest.
- [docs/HAND-WRITTEN-LAYER.md](docs/HAND-WRITTEN-LAYER.md) describes what this repository adds on
  top of the generated code, and what it deliberately leaves alone.
- [docs/REGENERATION.md](docs/REGENERATION.md) is the procedure for reproducing the generated tree
  from the committed specification.
- [Public API stability policy](CHANGELOG.md#public-api-stability-policy) states what a version
  bump promises, and what happens when a specification refresh renames a generated method.

## License

MIT. See [LICENSE](LICENSE).
