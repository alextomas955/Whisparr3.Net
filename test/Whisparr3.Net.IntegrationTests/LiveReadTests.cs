// Hand-written test code. See CLAUDE.md, section "Generated vs hand-written".

#nullable enable

using Microsoft.Extensions.DependencyInjection;
using Whisparr3.Net.Api;
using Whisparr3.Net.Model;

namespace Whisparr3.Net.IntegrationTests
{
    /// <summary>
    /// Read assertions issued by a real client against a real Whisparr over a real socket.
    /// </summary>
    /// <remarks>
    /// Every response is classified by EnsureSuccess rather than by reading the generated success
    /// accessor. That accessor deserializes on exactly 200 and returns null on anything else, so a
    /// 401 and an empty collection read the same to a caller, and an assertion built on it would
    /// report a rejected request as an empty result.
    /// </remarks>
    [Collection(WhisparrCollection.Name)]
    public sealed class LiveReadTests(WhisparrFixture fixture)
    {
        /// <summary>
        /// The version and branch the instance reports are the ones spec/PROVENANCE.json recorded
        /// when the spec was captured from this same digest.
        /// </summary>
        [SkippableFact]
        public async Task Status_reports_the_pinned_version_and_branch()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildProvider();

            SystemResource status = (await provider
                .GetRequiredService<ISystemApi>()
                .GetSystemStatusAsync())
                .EnsureSuccess();

            // The version is compared as a string and never parsed into a Version value, so no
            // component of it can be lost on the way to the comparison. Ordinal, so no culture
            // rule can make two different strings equal.
            Assert.True(
                string.Equals(fixture.ExpectedVersion, status.VarVersion, StringComparison.Ordinal),
                $"The instance reports version '{status.VarVersion}'. PROVENANCE.json records '{fixture.ExpectedVersion}'.");

            Assert.True(
                string.Equals(fixture.ExpectedBranch, status.Branch, StringComparison.Ordinal),
                $"The instance reports branch '{status.Branch}'. PROVENANCE.json records '{fixture.ExpectedBranch}'.");
        }

        /// <summary>
        /// Builds a provider pointed at the container this run started.
        /// </summary>
        /// <returns>A provider the caller owns and disposes.</returns>
        /// <remarks>
        /// The base URL comes from the fixture, which read the host port back from the daemon. No
        /// host port is written into this project, and the generated default base address is never
        /// relied on.
        /// </remarks>
        private ServiceProvider BuildProvider()
        {
            ServiceCollection services = new();

            services.AddWhisparr3(new Whisparr3Options
            {
                BaseUrl = fixture.BaseUrl,
                ApiKey = fixture.ApiKey,
            });

            return services.BuildServiceProvider();
        }
    }
}
