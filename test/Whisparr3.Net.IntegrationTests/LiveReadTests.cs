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
        /// The instance returns exactly the seven profiles the pinned image seeds, and each one is
        /// named.
        /// </summary>
        [SkippableFact]
        public async Task Quality_profiles_are_the_seven_seeded_profiles()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildProvider();

            List<QualityProfileResource> profiles = (await provider
                .GetRequiredService<IQualityProfileApi>()
                .ListQualityProfileAsync())
                .EnsureSuccess();

            // Seven is a property of the database this image version seeds, not of the API. A spec
            // refresh that moves the digest in spec/PROVENANCE.json can legitimately move it. A
            // future reader should re-measure against the new digest rather than read a change here
            // as a defect. It stays an equality: a lower bound would stop proving anything.
            Assert.Equal(7, profiles.Count);

            IReadOnlyList<string?> names = profiles.Select(profile => profile.Name).ToList();

            // Membership rather than position, because the server documents no ordering for rows of
            // equal rank. Ordinal, because a culture rule can treat two of these names as one
            // string. "HD - 720p/1080p" is the canary: a paraphrase loses the spaces around the
            // dash and the assertion still looks correct.
            Assert.Contains(names, name => string.Equals(name, "Any", StringComparison.Ordinal));
            Assert.Contains(names, name => string.Equals(name, "SD", StringComparison.Ordinal));
            Assert.Contains(names, name => string.Equals(name, "HD-720p", StringComparison.Ordinal));
            Assert.Contains(names, name => string.Equals(name, "HD-1080p", StringComparison.Ordinal));
            Assert.Contains(names, name => string.Equals(name, "Ultra-HD", StringComparison.Ordinal));
            Assert.Contains(names, name => string.Equals(name, "HD - 720p/1080p", StringComparison.Ordinal));
            Assert.Contains(names, name => string.Equals(name, "VR", StringComparison.Ordinal));
        }

        /// <summary>
        /// The instance returns exactly the 29 quality definitions the pinned image seeds.
        /// </summary>
        [SkippableFact]
        public async Task Quality_definitions_number_twenty_nine()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildProvider();

            List<QualityDefinitionResource> definitions = (await provider
                .GetRequiredService<IQualityDefinitionApi>()
                .ListQualityDefinitionAsync())
                .EnsureSuccess();

            // The caveat above the profile count applies here too: 29 is seeded data for this
            // digest, so a spec refresh can move it and the fix is to re-measure, not to loosen.
            Assert.Equal(29, definitions.Count);
        }

        /// <summary>
        /// The three types Whisparr 3 adds over Radarr answer, deserialize into their typed lists,
        /// and are observed empty.
        /// </summary>
        /// <remarks>
        /// Empty is the true state of a fresh instance, and it cannot be changed from here. Credit
        /// has no write operation anywhere in the spec, so nothing can seed it. Creating a performer
        /// or a studio routes through Whisparr's external metadata service, which the pinned digest
        /// does not pin, so seeding either one would make this suite depend on a third party and
        /// would carry that dependency into CI. The emptiness is therefore stated as a fact. It is
        /// not asserted with a non-empty or a non-null helper, both of which would pass here while
        /// proving nothing about deserialization.
        /// </remarks>
        [SkippableFact]
        public async Task Whisparr3_only_types_deserialize_and_are_empty()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildProvider();

            List<PerformerResource> performers = (await provider
                .GetRequiredService<IPerformerApi>()
                .ListPerformerAsync())
                .EnsureSuccess();

            List<StudioResource> studios = (await provider
                .GetRequiredService<IStudioApi>()
                .ListStudioAsync())
                .EnsureSuccess();

            List<CreditResource> credits = (await provider
                .GetRequiredService<ICreditApi>()
                .ListCreditAsync())
                .EnsureSuccess();

            // Reaching this line is already the deserialization evidence: EnsureSuccess throws
            // unless the status was a success and a body came back, so a typed list in hand means a
            // 200 that deserialized. What is left is to state the count that was observed.
            //
            // xUnit2013 prefers Assert.Empty for these three lines and this repo treats it as an
            // error. It is suppressed here and only here, because a shape helper is precisely what
            // the requirement rules out: Assert.Empty would read the same whether the list came
            // back empty or the assertion had nothing to say about a count at all.
#pragma warning disable xUnit2013
            Assert.Equal(0, performers.Count);
            Assert.Equal(0, studios.Count);
            Assert.Equal(0, credits.Count);
#pragma warning restore xUnit2013
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
