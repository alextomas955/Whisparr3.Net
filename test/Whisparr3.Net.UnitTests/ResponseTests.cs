// Hand-written test code. See CLAUDE.md, section "Generated vs hand-written".

#nullable enable

using System.Net;
using Microsoft.Extensions.DependencyInjection;
using Whisparr3.Net.Api;
using Whisparr3.Net.Model;

namespace Whisparr3.Net.UnitTests
{
    /// <summary>
    /// Assertions over the three outcomes a response can have, observed over a real socket.
    /// </summary>
    /// <remarks>
    /// The generated success accessor collapses two of those outcomes into null: it deserializes
    /// only on exactly 200 and returns null otherwise, so a 401 and an empty collection read the
    /// same to a caller. These tests pin the replacement, and they run a real client against a
    /// real listener rather than a mocked handler, so nothing between the call and the socket can
    /// hide behind the assertion.
    /// </remarks>
    public sealed class ResponseTests
    {
        /// <summary>
        /// An obvious non-secret, carrying upper case, lower case, digits and a hyphen so that an
        /// absence assertion over it means something.
        /// </summary>
        private const string SentinelKey = "SENTINEL-Key-123";

        /// <summary>The number of body characters the exception message is allowed to embed.</summary>
        private const int MessageBodyCap = 512;

        /// <summary>
        /// How much fixed framing the message may add around the capped body fragment. The
        /// truncation test asserts a bound rather than an exact string, so the framing wording can
        /// change without the test becoming a copy of the implementation.
        /// </summary>
        private const int FramingAllowance = 256;

        /// <summary>A real system-status payload, trimmed to the fields the assertions name.</summary>
        private const string SystemStatusBody =
            "{\"appName\":\"Whisparr\",\"instanceName\":\"wsp53-v3\",\"version\":\"3.3.8.1097\"}";

        /// <summary>The performer payload the create operation answers with.</summary>
        private const string CreatedPerformerBody =
            "{\"id\":7,\"fullName\":\"Created Performer\"}";

        /// <summary>The performer payload the update operation answers with.</summary>
        private const string UpdatedPerformerBody =
            "{\"id\":9,\"fullName\":\"Accepted Performer\"}";

        /// <summary>The id the update tests address, which the route template does not carry.</summary>
        private const string PerformerId = "7";

        /// <summary>
        /// The bodiless 401 is the shape the live instance actually returns for a prefixed key,
        /// measured against a real Whisparr instance. It is the case that hands the caller nothing
        /// at all, so it is the strongest form of the failure this layer exists to surface.
        /// </summary>
        [Fact]
        public async Task Bodiless_401_throws_a_typed_error_carrying_status_path_and_body()
        {
            using LoopbackCapture capture = new(status: 401, body: string.Empty);

            await using ServiceProvider provider = BuildProvider(capture);
            IGetSystemStatusApiResponse response =
                await provider.GetRequiredService<ISystemApi>().GetSystemStatusAsync();

            Whisparr3ApiException error =
                Assert.Throws<Whisparr3ApiException>(() => { response.EnsureSuccess(); });

            Assert.Equal(HttpStatusCode.Unauthorized, error.StatusCode);
            Assert.Equal("/api/v3/system/status", error.Path);
            Assert.NotNull(error.RequestUri);
            Assert.Equal(string.Empty, error.RawContent);
            Assert.False(error.IsSuccessStatusCode);
        }

        /// <summary>
        /// The third outcome. A 200 whose body deserializes to null also throws, because the caller
        /// asked for a body and there is none, but IsSuccessStatusCode tells it apart from the 401
        /// above. Without that property the two are reported identically, which is the confusion
        /// this layer removes.
        /// </summary>
        [Fact]
        public async Task Success_with_an_unreadable_body_is_distinguishable_from_a_failure()
        {
            using LoopbackCapture capture = new(status: 200, body: "null");

            await using ServiceProvider provider = BuildProvider(capture);
            IGetSystemStatusApiResponse response =
                await provider.GetRequiredService<ISystemApi>().GetSystemStatusAsync();

            Whisparr3ApiException error =
                Assert.Throws<Whisparr3ApiException>(() => { response.EnsureSuccess(); });

            Assert.Equal(HttpStatusCode.OK, error.StatusCode);
            Assert.True(error.IsSuccessStatusCode);
        }

        /// <summary>
        /// The non-generic overload, for the response interfaces that carry no typed success
        /// accessor at all.
        /// </summary>
        /// <remarks>
        /// GetSystemRoutes was chosen for two reasons. Its response interface is declared
        /// IGetSystemRoutesApiResponse : Whisparr3.Net.Client.IApiResponse with no IOk in the base
        /// list, so the generic overload cannot bind to it and the non-generic one is the only path
        /// that exists. And it is a read-shaped operation rather than one of the state-mutating
        /// content-less ones, so the test reads the way a consumer's own call would.
        /// </remarks>
        [Fact]
        public async Task Content_less_operation_failure_throws_through_the_non_generic_overload()
        {
            using LoopbackCapture capture = new(status: 500, body: string.Empty);

            await using ServiceProvider provider = BuildProvider(capture);
            IGetSystemRoutesApiResponse response =
                await provider.GetRequiredService<ISystemApi>().GetSystemRoutesAsync();

            Whisparr3ApiException error =
                Assert.Throws<Whisparr3ApiException>(() => { response.EnsureSuccess(); });

            Assert.Equal(HttpStatusCode.InternalServerError, error.StatusCode);
            Assert.Equal("/api/v3/system/routes", error.Path);
            Assert.False(error.IsSuccessStatusCode);
        }

        /// <summary>
        /// The ordinary path. Field values are asserted rather than non-null, because a non-null
        /// check passes against a resource whose every member is empty.
        /// </summary>
        [Fact]
        public async Task Success_returns_the_body_with_asserted_field_values()
        {
            using LoopbackCapture capture = new(status: 200, body: SystemStatusBody);

            await using ServiceProvider provider = BuildProvider(capture);
            IGetSystemStatusApiResponse response =
                await provider.GetRequiredService<ISystemApi>().GetSystemStatusAsync();

            SystemResource status = response.EnsureSuccess();

            Assert.Equal("Whisparr", status.AppName);
            Assert.Equal("wsp53-v3", status.InstanceName);
            Assert.Equal("3.3.8.1097", status.VarVersion);
        }

        /// <summary>
        /// The credential-leak control for the error surface. It runs against a captured failure
        /// rather than a directly constructed exception, so it covers the whole path from the
        /// request builder through the response into the exception, and would catch a leak
        /// regardless of which mechanism reintroduced one.
        /// </summary>
        [Fact]
        public async Task Exception_surface_does_not_contain_the_api_key()
        {
            using LoopbackCapture capture = new(status: 401, body: string.Empty);

            await using ServiceProvider provider = BuildProvider(capture);
            IGetSystemStatusApiResponse response =
                await provider.GetRequiredService<ISystemApi>().GetSystemStatusAsync();

            Whisparr3ApiException error =
                Assert.Throws<Whisparr3ApiException>(() => { response.EnsureSuccess(); });

            Assert.NotNull(error.RequestUri);
            string uri = error.RequestUri!.ToString();

            Assert.DoesNotContain(SentinelKey, uri, StringComparison.Ordinal);
            Assert.DoesNotContain("apikey", uri, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain(SentinelKey, error.Message, StringComparison.Ordinal);
        }

        /// <summary>
        /// The body is instance-controlled, so an uncapped interpolation turns a large or hostile
        /// response into a log-flooding surface in a consumer's process. The assertion is a length
        /// bound, not an exact string.
        /// </summary>
        [Fact]
        public async Task Message_truncates_a_long_body()
        {
            string longBody = new('x', 4000);

            using LoopbackCapture capture = new(status: 500, body: longBody);

            await using ServiceProvider provider = BuildProvider(capture);
            IGetSystemStatusApiResponse response =
                await provider.GetRequiredService<ISystemApi>().GetSystemStatusAsync();

            Whisparr3ApiException error =
                Assert.Throws<Whisparr3ApiException>(() => { response.EnsureSuccess(); });

            Assert.Equal(4000, error.RawContent.Length);
            Assert.DoesNotContain(longBody, error.Message, StringComparison.Ordinal);
            Assert.True(
                error.Message.Length <= MessageBodyCap + FramingAllowance,
                $"The message was {error.Message.Length} characters, above the {MessageBodyCap} "
                    + $"character body cap plus {FramingAllowance} characters of framing.");
        }

        /// <summary>
        /// A real 201 is a documented success on this operation, and without the hook its body is
        /// unreachable through any typed accessor because the generated one deserializes on
        /// exactly 200.
        /// </summary>
        [Fact]
        public async Task Created_201_body_is_reachable_and_EnsureSuccess_returns_it()
        {
            using LoopbackCapture capture = new(status: 201, body: CreatedPerformerBody);

            await using ServiceProvider provider = BuildProvider(capture);
            ICreatePerformerApiResponse response =
                await provider.GetRequiredService<IPerformerApi>().CreatePerformerAsync();

            PerformerResource created = response.EnsureSuccess();

            Assert.Equal(7, created.Id);
            Assert.Equal("Created Performer", created.FullName);
        }

        /// <summary>
        /// The same for the update operation, whose documented non-200 success is 202.
        /// </summary>
        [Fact]
        public async Task Accepted_202_body_is_reachable_and_EnsureSuccess_returns_it()
        {
            using LoopbackCapture capture = new(status: 202, body: UpdatedPerformerBody);

            await using ServiceProvider provider = BuildProvider(capture);
            IUpdatePerformerApiResponse response =
                await provider.GetRequiredService<IPerformerApi>().UpdatePerformerAsync(PerformerId);

            PerformerResource updated = response.EnsureSuccess();

            Assert.Equal(9, updated.Id);
            Assert.Equal("Accepted Performer", updated.FullName);
        }

        /// <summary>
        /// The empty-body case, which without a guard in the hook throws a raw serialization
        /// exception straight out of the accessor and escapes the typed layer untyped.
        /// </summary>
        [Fact]
        public async Task Created_201_with_an_empty_body_throws_the_typed_error()
        {
            using LoopbackCapture capture = new(status: 201, body: string.Empty);

            await using ServiceProvider provider = BuildProvider(capture);
            ICreatePerformerApiResponse response =
                await provider.GetRequiredService<IPerformerApi>().CreatePerformerAsync();

            Whisparr3ApiException error =
                Assert.Throws<Whisparr3ApiException>(() => { response.EnsureSuccess(); });

            Assert.Equal(HttpStatusCode.Created, error.StatusCode);
            Assert.Equal("/api/v3/performer", error.Path);
            Assert.True(error.IsSuccessStatusCode);
            Assert.Contains("201", error.Message, StringComparison.Ordinal);
            Assert.Contains("/api/v3/performer", error.Message, StringComparison.Ordinal);
        }

        /// <summary>
        /// The hook's one real risk is disturbing the path it is not meant to touch, so the
        /// ordinary 200 is asserted on each affected operation separately rather than sampled.
        /// </summary>
        [Fact]
        public async Task Ok_200_on_the_create_operation_still_returns_the_body()
        {
            using LoopbackCapture capture = new(status: 200, body: CreatedPerformerBody);

            await using ServiceProvider provider = BuildProvider(capture);
            ICreatePerformerApiResponse response =
                await provider.GetRequiredService<IPerformerApi>().CreatePerformerAsync();

            PerformerResource created = response.EnsureSuccess();

            Assert.Equal(7, created.Id);
            Assert.Equal("Created Performer", created.FullName);
        }

        /// <summary>
        /// The same assertion for the update operation.
        /// </summary>
        [Fact]
        public async Task Ok_200_on_the_update_operation_still_returns_the_body()
        {
            using LoopbackCapture capture = new(status: 200, body: UpdatedPerformerBody);

            await using ServiceProvider provider = BuildProvider(capture);
            IUpdatePerformerApiResponse response =
                await provider.GetRequiredService<IPerformerApi>().UpdatePerformerAsync(PerformerId);

            PerformerResource updated = response.EnsureSuccess();

            Assert.Equal(9, updated.Id);
            Assert.Equal("Accepted Performer", updated.FullName);
        }

        /// <summary>
        /// Builds a provider pointed at the capture, through the same single registration call a
        /// consumer makes.
        /// </summary>
        /// <param name="capture">The listener to point the client at.</param>
        /// <returns>A provider whose typed clients reach the capture.</returns>
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
