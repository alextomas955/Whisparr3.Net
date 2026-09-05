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
