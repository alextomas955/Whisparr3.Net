// Hand-written test code. See CLAUDE.md, section "Generated vs hand-written".

#nullable enable

using System.Net;
using Microsoft.Extensions.DependencyInjection;
using Whisparr3.Net.Api;

namespace Whisparr3.Net.IntegrationTests
{
    /// <summary>
    /// The negative control for authentication, issued against a real Whisparr over a real socket.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The generated success accessor deserializes on exactly 200 and returns null on anything
    /// else, so it reports a 401 the same way it reports an empty collection. Reading it raw would
    /// make an authentication failure indistinguishable from an empty result, and a suite that
    /// authenticated as nobody and read empty lists would look identical to a suite that
    /// authenticated correctly and read empty lists.
    /// </para>
    /// <para>
    /// This control is what gives the rest of the live read evidence its meaning. It sends a
    /// well-formed credential the server does not accept, and asserts on the thrown object rather
    /// than on the fact that something was thrown.
    /// </para>
    /// <para>
    /// The second half of the construction refusal is not here. A client built with no key at all
    /// is refused by AddWhisparr3 before anything is registered, which needs no container, and
    /// test/Whisparr3.Net.UnitTests/OptionsTests.cs already covers every clause of it. A
    /// container-free passing test in this project would also change what the Docker-less run
    /// reports, which the skip evidence rests on.
    /// </para>
    /// </remarks>
    [Collection(WhisparrCollection.Name)]
    public sealed class AuthControlTests(WhisparrFixture fixture)
    {
        /// <summary>
        /// A key the server will not accept.
        /// </summary>
        /// <remarks>
        /// 32 hexadecimal characters, the same shape as the real one, and deliberately not the
        /// fixture's key. The shape matters: a 401 for this value is the server rejecting a
        /// well-formed credential, not rejecting a malformed one, so the control proves the
        /// authentication decision rather than an input check.
        /// </remarks>
        private const string WrongApiKey = "deadbeefdeadbeefdeadbeefdeadbeef";

        /// <summary>
        /// The route template the operation is declared with, which the exception reports on Path.
        /// </summary>
        private const string StatusRouteTemplate = "/api/v3/system/status";

        /// <summary>
        /// A wrong key produces a typed error carrying the status, the route template and a
        /// request URI, rather than the null the generated accessor would hand back.
        /// </summary>
        [SkippableFact]
        public async Task Wrong_key_throws_a_typed_error_not_null()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildWrongKeyProvider();

            Whisparr3ApiException thrown = await Assert.ThrowsAsync<Whisparr3ApiException>(
                async () =>
                {
                    IGetSystemStatusApiResponse response = await provider
                        .GetRequiredService<ISystemApi>()
                        .GetSystemStatusAsync();

                    response.EnsureSuccess();
                });

            Assert.Equal(HttpStatusCode.Unauthorized, thrown.StatusCode);

            // The route template, not the concrete path. Compared ordinally so no culture rule
            // decides whether two different strings are the same route.
            Assert.True(
                string.Equals(StatusRouteTemplate, thrown.Path, StringComparison.Ordinal),
                $"The exception reports Path '{thrown.Path}'. The operation is declared with '{StatusRouteTemplate}'.");

            // False here and true for a success whose body cannot be read. This is the property
            // that keeps a rejected request distinct from a succeeding one that returned nothing.
            Assert.False(thrown.IsSuccessStatusCode);

            Assert.NotNull(thrown.RequestUri);
        }

        /// <summary>
        /// Neither the wrong key nor the fixture's real key reaches the request URI or the
        /// exception message.
        /// </summary>
        /// <remarks>
        /// Phase 21 asserted this against a loopback stub that answered with a canned 401. This is
        /// the same assertion against a real socket, a real Whisparr and a real rejection, so it
        /// covers the whole path from the request builder through the response to the exception
        /// and catches a leak whatever mechanism introduced it. The assertion is made on a
        /// captured failure rather than on an exception the test constructed, because an exception
        /// built by the test proves only what the test put into it.
        /// </remarks>
        [SkippableFact]
        public async Task Wrong_key_failure_carries_no_credential()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildWrongKeyProvider();

            Whisparr3ApiException thrown = await Assert.ThrowsAsync<Whisparr3ApiException>(
                async () =>
                {
                    IGetSystemStatusApiResponse response = await provider
                        .GetRequiredService<ISystemApi>()
                        .GetSystemStatusAsync();

                    response.EnsureSuccess();
                });

            string requestUri = thrown.RequestUri?.ToString() ?? string.Empty;

            // Both keys, in both places, four comparisons. The fixture's key is checked as well as
            // the wrong one because a leak of the configured credential is the failure that
            // matters, and this client is configured with the wrong key while the real one is live
            // in the same process.
            Assert.DoesNotContain(WrongApiKey, requestUri, StringComparison.Ordinal);
            Assert.DoesNotContain(fixture.ApiKey, requestUri, StringComparison.Ordinal);
            Assert.DoesNotContain(WrongApiKey, thrown.Message, StringComparison.Ordinal);
            Assert.DoesNotContain(fixture.ApiKey, thrown.Message, StringComparison.Ordinal);
        }

        /// <summary>
        /// Builds a provider whose only difference from the rest of the suite is the key.
        /// </summary>
        /// <returns>A provider wired by AddWhisparr3 against the fixture's base URL.</returns>
        /// <remarks>
        /// Each test builds its own ServiceCollection and its own provider, and shares only the
        /// container with the rest of the suite. That is deliberate. A wrong-key client registered
        /// into a shared provider would disturb another test's authentication state, and the value
        /// of this control is that the authenticated tests beside it are unaffected by it.
        /// </remarks>
        private ServiceProvider BuildWrongKeyProvider()
        {
            ServiceCollection services = new();

            services.AddWhisparr3(new Whisparr3Options
            {
                BaseUrl = fixture.BaseUrl,
                ApiKey = WrongApiKey,
            });

            return services.BuildServiceProvider();
        }
    }
}
