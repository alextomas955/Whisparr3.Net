// Hand-written test code. See CLAUDE.md, section "Generated vs hand-written".

#nullable enable

using Microsoft.Extensions.DependencyInjection;
using Whisparr3.Net.Api;
using Whisparr3.Net.Client;
using Whisparr3.Net.Extensions;

namespace Whisparr3.Net.UnitTests
{
    /// <summary>
    /// Assertions over the literal bytes a configured client puts on a socket.
    /// </summary>
    public sealed class WireTests
    {
        /// <summary>
        /// An obvious non-secret. It carries upper case, lower case, digits and a hyphen, which is
        /// what makes the byte-identity assertion mean anything.
        /// </summary>
        private const string SentinelKey = "SENTINEL-Key-123";

        /// <summary>
        /// The credential Whisparr accepts, in the shape Whisparr accepts it.
        /// </summary>
        [Fact]
        public async Task Configured_key_reaches_the_wire_as_X_Api_Key_with_no_prefix()
        {
            using LoopbackCapture capture = new();

            ServiceCollection services = new();
            services.AddWhisparr3(new Whisparr3Options
            {
                BaseUrl = capture.BaseUrl,
                ApiKey = SentinelKey,
            });

            await using ServiceProvider provider = services.BuildServiceProvider();
            await provider.GetRequiredService<ISystemApi>().GetSystemStatusAsync();

            string request = await capture.FirstRequest;

            Assert.Contains("GET /api/v3/system/status HTTP/1.1", request, StringComparison.Ordinal);

            IReadOnlyList<string> headers = CapturedRequest.HeaderLines(request, "X-Api-Key");
            string only = Assert.Single(headers);
            Assert.Equal("X-Api-Key: " + SentinelKey, only);

            Assert.DoesNotContain("Bearer", request, StringComparison.Ordinal);
            Assert.DoesNotContain("apikey", request, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// The negative control. It exists so the test above cannot pass by the assertion being
        /// blind to a prefix: the same listener and the same helper must be able to see one.
        /// The prefixed form is the generated constructor's default and is measured to return 401
        /// with a zero-byte body against a real Whisparr instance, so it fails in a way that reads
        /// as a permissions problem rather than as a client defect.
        /// </summary>
        [Fact]
        public async Task Prefixed_token_is_visible_to_the_same_assertion_negative_control()
        {
            using LoopbackCapture capture = new();

            // No AddWhisparr3 here. This wires the raw generated path by hand so the prefix the
            // registration entry point suppresses is the one thing that differs.
            ServiceCollection services = new();
            services.AddLogging();
            services.AddSingleton<TokenProvider<ApiKeyToken>>(new PrefixedTokenProvider(SentinelKey));
            services.AddApi(cfg => cfg.AddApiHttpClients(
                client => client.BaseAddress = new Uri(capture.BaseUrl),
                null));

            await using ServiceProvider provider = services.BuildServiceProvider();
            await provider.GetRequiredService<ISystemApi>().GetSystemStatusAsync();

            string request = await capture.FirstRequest;

            IReadOnlyList<string> headers = CapturedRequest.HeaderLines(request, "X-Api-Key");
            string only = Assert.Single(headers);
            Assert.Equal("X-Api-Key: Bearer " + SentinelKey, only);
        }

        /// <summary>
        /// Hands out a token built without overriding the generated prefix argument.
        /// </summary>
        private sealed class PrefixedTokenProvider : TokenProvider<ApiKeyToken>
        {
            private readonly ApiKeyToken _token;

            public PrefixedTokenProvider(string apiKey)
            {
                _token = new ApiKeyToken(apiKey, ClientUtils.ApiKeyHeader.X_Api_Key);
            }

            // protected, not protected internal: the base member is protected internal and this
            // project sits outside the library assembly, where that degrades to protected.
            protected override ValueTask<ApiKeyToken> GetAsync(
                string header = "",
                CancellationToken cancellation = default)
            {
                return new ValueTask<ApiKeyToken>(_token);
            }
        }
    }
}
