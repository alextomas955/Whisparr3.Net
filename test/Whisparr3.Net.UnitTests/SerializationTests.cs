// Hand-written test code. See CLAUDE.md, section "Generated vs hand-written".

#nullable enable

using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Whisparr3.Net.Api;
using Whisparr3.Net.Model;

namespace Whisparr3.Net.UnitTests
{
    /// <summary>
    /// Assertions over the request a configured client puts on a socket for a write operation.
    /// </summary>
    /// <remarks>
    /// These go through LoopbackCapture rather than serializing a resource directly. A direct
    /// serialization asserts against a JsonSerializerOptions the test constructed, which is not
    /// necessarily the one the client uses. Capturing the request proves the semantic on the path a
    /// consumer actually takes. Neither test needs a container, so both stay in the unit project.
    /// </remarks>
    public sealed class SerializationTests
    {
        /// <summary>
        /// An obvious non-secret, in the shape the wire tests use it.
        /// </summary>
        private const string SentinelKey = "SENTINEL-Key-123";

        /// <summary>
        /// The label the captured request carries. It contains the letters of the member name this
        /// test asserts absent, which is why the absence is checked against the parsed JSON member
        /// set rather than against a substring of the body text.
        /// </summary>
        private const string ProbeLabel = "identify-the-label";

        /// <summary>
        /// The command the dispatch cases send. It takes arguments, which is what makes the flat
        /// body assertions mean anything.
        /// </summary>
        private const string DispatchedCommandName = "RefreshStudios";

        /// <summary>
        /// The canned 201 body a dispatch reads back. It carries no JSON null member on purpose:
        /// the generated converter throws for a member that is present and null.
        /// </summary>
        private const string CommandAcceptedBody = "{\"id\":42,\"name\":\"RefreshStudios\"}";

        /// <summary>
        /// The command arguments reach the wire as siblings of the name member, not nested under a
        /// body member.
        /// </summary>
        /// <remarks>
        /// The server rewinds the request stream and deserializes the whole body into a concrete
        /// command type, so a nested arguments object would dispatch the command with no arguments
        /// and still answer 201. The request bytes are the only place the difference is visible.
        /// </remarks>
        [Fact]
        public async Task Command_dispatch_puts_a_flat_name_and_payload_body_on_the_wire()
        {
            using LoopbackCapture capture = new(status: 201, body: CommandAcceptedBody);

            await using ServiceProvider provider = BuildProvider(capture);
            CommandResource command = await Dispatcher(provider)
                .SendCommandAsync(DispatchedCommandName, new { studioIds = new[] { 7 } });

            Assert.True(command.Id == 42, $"The dispatch returned command id '{command.Id}'.");
            Assert.True(
                command.Name == DispatchedCommandName,
                $"The dispatch returned command name '{command.Name}'.");

            string request = await capture.FirstRequest;

            using JsonDocument body = JsonDocument.Parse(CapturedRequest.Body(request));

            Assert.True(
                body.RootElement.TryGetProperty("name", out JsonElement name),
                $"The captured request body carries no name member. Body: {CapturedRequest.Body(request)}");

            Assert.Equal(JsonValueKind.String, name.ValueKind);
            Assert.Equal(DispatchedCommandName, name.GetString());

            Assert.True(
                body.RootElement.TryGetProperty("studioIds", out JsonElement studioIds),
                $"The captured request body carries no studioIds member. Body: {CapturedRequest.Body(request)}");

            JsonElement only = Assert.Single(studioIds.EnumerateArray());
            Assert.Equal(7, only.GetInt32());

            Assert.False(
                body.RootElement.TryGetProperty("body", out _),
                $"The captured request body nests the arguments under a body member. "
                    + $"Body: {CapturedRequest.Body(request)}");
        }

        /// <summary>
        /// A command that takes no arguments is dispatched by omitting the payload, and its body
        /// carries the name and nothing else.
        /// </summary>
        [Fact]
        public async Task Command_dispatch_with_no_payload_sends_the_name_alone()
        {
            using LoopbackCapture capture = new(status: 201, body: CommandAcceptedBody);

            await using ServiceProvider provider = BuildProvider(capture);
            await Dispatcher(provider).SendCommandAsync(DispatchedCommandName);

            string request = await capture.FirstRequest;

            using JsonDocument body = JsonDocument.Parse(CapturedRequest.Body(request));

            Assert.True(
                body.RootElement.TryGetProperty("name", out JsonElement name),
                $"The captured request body carries no name member. Body: {CapturedRequest.Body(request)}");

            Assert.Equal(DispatchedCommandName, name.GetString());

            Assert.Single(body.RootElement.EnumerateObject());
        }

        /// <summary>
        /// A payload carrying its own name member is refused before a socket is opened.
        /// </summary>
        /// <remarks>
        /// The indexer overwrites an exact-case name in place, but a differently-cased key survives
        /// alongside it and both reach the wire, leaving the server two candidates for one
        /// property. Refusing is the alternative to silently dropping or duplicating a caller's
        /// field at a public boundary.
        /// </remarks>
        [Fact]
        public async Task Command_payload_carrying_its_own_name_key_is_refused()
        {
            using LoopbackCapture capture = new(status: 201, body: CommandAcceptedBody);

            await using ServiceProvider provider = BuildProvider(capture);

            ArgumentException error = await Assert.ThrowsAsync<ArgumentException>(
                () => Dispatcher(provider).SendCommandAsync(
                    DispatchedCommandName,
                    new { Name = "collision", studioIds = new[] { 7 } }));

            Assert.Equal("payload", error.ParamName);
            Assert.Contains("Name", error.Message, StringComparison.Ordinal);

            Assert.Empty(capture.Requests);
        }

        /// <summary>
        /// A payload that is not a JSON object is refused before a socket is opened.
        /// </summary>
        /// <remarks>
        /// The parameter is object, which admits scalars, arrays and strings. A boxed scalar
        /// serializes to a JsonValue, and without this guard the cast to JsonObject would raise a
        /// NullReferenceException from inside the library.
        /// </remarks>
        [Fact]
        public async Task Command_payload_that_is_not_a_json_object_is_refused()
        {
            using LoopbackCapture capture = new(status: 201, body: CommandAcceptedBody);

            await using ServiceProvider provider = BuildProvider(capture);

            ArgumentException error = await Assert.ThrowsAsync<ArgumentException>(
                () => Dispatcher(provider).SendCommandAsync(DispatchedCommandName, 42));

            Assert.Equal("payload", error.ParamName);

            Assert.Empty(capture.Requests);
        }

        /// <summary>
        /// The payload is written with the serializer options the client registered, not plain
        /// defaults.
        /// </summary>
        /// <remarks>
        /// An enum is the discriminator. The client registers a JsonStringEnumConverter, so the
        /// member reaches the wire as a string, while the same payload under a bare
        /// JsonSerializerOptions writes a number. The negative control is what shows the first
        /// assertion is not passing on options a caller could have supplied.
        /// </remarks>
        [Fact]
        public async Task Command_payload_serializes_through_the_client_registered_options()
        {
            using LoopbackCapture capture = new(status: 201, body: CommandAcceptedBody);

            var payload = new { studioIds = new[] { 7 }, kind = PayloadProbeKind.Enabled };

            await using ServiceProvider provider = BuildProvider(capture);
            await Dispatcher(provider).SendCommandAsync(DispatchedCommandName, payload);

            string request = await capture.FirstRequest;

            using JsonDocument body = JsonDocument.Parse(CapturedRequest.Body(request));

            Assert.True(
                body.RootElement.TryGetProperty("kind", out JsonElement kind),
                $"The captured request body carries no kind member. Body: {CapturedRequest.Body(request)}");

            Assert.Equal(JsonValueKind.String, kind.ValueKind);
            Assert.Equal("Enabled", kind.GetString());

            using JsonDocument defaults =
                JsonDocument.Parse(JsonSerializer.Serialize(payload, new JsonSerializerOptions()));

            Assert.Equal(
                JsonValueKind.Number,
                defaults.RootElement.GetProperty("kind").ValueKind);
        }

        /// <summary>
        /// An unset Option&lt;T&gt; emits no JSON member at all, proven on the bytes the client put
        /// on a socket.
        /// </summary>
        /// <remarks>
        /// What this proves: TagResourceJsonConverter.WriteProperties writes the id member only
        /// when the id option is set, so a resource constructed with a label alone serializes
        /// without one.
        /// <para>
        /// What it does not prove, and what no live call could: the server is not a witness to this
        /// semantic. A create carrying an explicit id also answers 201 and the server assigns its
        /// own id anyway, so a response-side assertion cannot tell the two requests apart. The
        /// request bytes are the only place the difference is visible.
        /// </para>
        /// </remarks>
        [Fact]
        public async Task Unset_option_emits_no_json_member()
        {
            using LoopbackCapture capture = new(status: 201, body: "{\"label\":\"x\",\"id\":1}");

            await using ServiceProvider provider = BuildProvider(capture);
            await provider.GetRequiredService<ITagApi>()
                .CreateTagAsync(new TagResource(label: ProbeLabel));

            string request = await capture.FirstRequest;

            using JsonDocument body = JsonDocument.Parse(CapturedRequest.Body(request));

            Assert.True(
                body.RootElement.TryGetProperty("label", out JsonElement label),
                $"The captured request body carries no label member. Body: {CapturedRequest.Body(request)}");

            Assert.Equal(ProbeLabel, label.GetString());

            Assert.False(
                body.RootElement.TryGetProperty("id", out _),
                $"The captured request body carries an id member, which an unset Option must not "
                    + $"emit. Body: {CapturedRequest.Body(request)}");
        }

        /// <summary>
        /// The client puts exactly one content-type header on the wire and it is
        /// <c>application/json</c>.
        /// </summary>
        /// <remarks>
        /// This is the client half of the content-type evidence, observed over a real socket rather
        /// than read off the generated contentTypes array. The observed value is the bare media
        /// type with no charset parameter, because the operation overwrites the StringContent
        /// default header with a MediaTypeHeaderValue that carries none. The assertion accepts the
        /// bare media type or the media type followed by a parameter separator, and nothing else. A
        /// parameter is always introduced by a semicolon, so tolerating a parameter appearing later
        /// does not require tolerating a longer media type. An open-ended prefix is what accepted
        /// application/json5 and application/jsonx, neither of which is what this test is about.
        /// </remarks>
        [Fact]
        public async Task Request_content_type_is_application_json()
        {
            using LoopbackCapture capture = new(status: 201, body: "{\"label\":\"x\",\"id\":1}");

            await using ServiceProvider provider = BuildProvider(capture);
            await provider.GetRequiredService<ITagApi>()
                .CreateTagAsync(new TagResource(label: ProbeLabel));

            string request = await capture.FirstRequest;

            string only = Assert.Single(CapturedRequest.HeaderLines(request, "Content-Type"));

            string value = only["Content-Type:".Length..].Trim();

            Assert.True(
                string.Equals(value, "application/json", StringComparison.Ordinal)
                    || value.StartsWith("application/json;", StringComparison.Ordinal),
                $"The request declared Content-Type '{value}'.");
        }

        /// <summary>
        /// The command dispatch declares one content-type header and it is
        /// <c>application/json</c>.
        /// </summary>
        /// <remarks>
        /// The dispatch builds its own StringContent, whose default header is text/plain, and the
        /// server answers 415 to that. The assertion accepts the bare media type or the media type
        /// followed by a parameter separator, and nothing else, for the reason the tag case above
        /// records.
        /// </remarks>
        [Fact]
        public async Task Command_dispatch_content_type_is_application_json()
        {
            using LoopbackCapture capture = new(status: 201, body: CommandAcceptedBody);

            await using ServiceProvider provider = BuildProvider(capture);
            await Dispatcher(provider)
                .SendCommandAsync(DispatchedCommandName, new { studioIds = new[] { 7 } });

            string request = await capture.FirstRequest;

            string only = Assert.Single(CapturedRequest.HeaderLines(request, "Content-Type"));

            string value = only["Content-Type:".Length..].Trim();

            Assert.True(
                string.Equals(value, "application/json", StringComparison.Ordinal)
                    || value.StartsWith("application/json;", StringComparison.Ordinal),
                $"The request declared Content-Type '{value}'.");
        }

        /// <summary>
        /// An enum the client's registered converter writes as a string and plain serializer
        /// defaults write as a number.
        /// </summary>
        private enum PayloadProbeKind
        {
            /// <summary>The default, present so Enabled is not the zero value.</summary>
            Unset = 0,

            /// <summary>The value the dispatch case sends.</summary>
            Enabled = 1,
        }

        /// <summary>
        /// Resolves the command client the dispatch cases call.
        /// </summary>
        /// <param name="provider">The provider to resolve from.</param>
        /// <returns>The registered command client, as the concrete class.</returns>
        /// <remarks>
        /// The resolution goes through ICommandApi, which is what keeps the registration in the
        /// path: a hand-written directory that never compiled would fail here rather than pass.
        /// The cast is needed because ICommandApi is generated, is not partial, and therefore
        /// cannot declare the hand-written dispatch method. A consumer makes the same cast.
        /// </remarks>
        private static CommandApi Dispatcher(ServiceProvider provider)
        {
            return (CommandApi)provider.GetRequiredService<ICommandApi>();
        }

        /// <summary>
        /// Builds a provider pointed at the capture, through the same single registration call a
        /// consumer makes.
        /// </summary>
        /// <param name="capture">The listener to point the client at.</param>
        /// <returns>A provider the caller owns and disposes.</returns>
        private static ServiceProvider BuildProvider(LoopbackCapture capture)
        {
            ServiceCollection services = new();
            services.AddWhisparr3(new Whisparr3Options
            {
                BaseUrl = capture.BaseUrl,
                ApiKey = SentinelKey,
            });

            return services.BuildServiceProvider();
        }
    }
}
