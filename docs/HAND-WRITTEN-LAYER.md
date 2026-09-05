# The hand-written layer

`src/Whisparr3.Net/` is openapi-generator output and is rewritten on every regeneration.
`src/hand-written/` is the small layer this repository owns by hand, compiled into the same
assembly by one `Compile` glob in the library project file. It is four files:

| File | What it adds |
|---|---|
| `Whisparr3Options.cs` | The settings a consumer supplies, and the validation that refuses a bad one |
| `Whisparr3ServiceCollectionExtensions.cs` | `AddWhisparr3`, the single registration entry point, and the token provider behind it |
| `Whisparr3ApiException.cs` | The typed error, carrying status, route template, request URI and raw body |
| `ApiResponseExtensions.cs` | `EnsureSuccess`, plus the two hooks that make a 201 and a 202 body readable |

This document records what that layer does, what it costs, and what it deliberately leaves alone.

## The consumer path, proven from a plain console app

The layer is meant to work from a bare `ServiceCollection` with no Generic Host, no application
builder and no logging call of the consumer's own. That claim is proven rather than asserted: a
throwaway console application was built outside this repository, run once, and deleted. Its source,
its project file and its output are recorded below so a reader can reproduce it.

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
