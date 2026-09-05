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
        /// The three endpoints Whisparr 3 adds over Radarr answer 200, and each answer binds to its
        /// typed list, which is observed empty.
        /// </summary>
        /// <remarks>
        /// Empty is the true state of a fresh instance, and it cannot be changed from here. Credit
        /// has no write operation anywhere in the spec, so nothing can seed it. Creating a performer
        /// or a studio routes through Whisparr's external metadata service, which the pinned digest
        /// does not pin, so seeding either one would make this suite depend on a third party and
        /// would carry that dependency into CI. The emptiness is therefore stated as a fact. It is
        /// not asserted with a non-empty or a non-null helper, both of which would pass here while
        /// saying nothing about the count. The element types are covered against canned bodies in
        /// the unit project instead.
        /// </remarks>
        [SkippableFact]
        public async Task Whisparr3_only_endpoints_answer_with_empty_typed_lists()
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

            // What reaching this line proves: EnsureSuccess throws unless the status was a success
            // and a body came back, so a typed list in hand means a 200 whose body bound a List of
            // the element type. It does not prove the element type deserializes. All three bodies
            // are empty, and deserializing an empty array enters the element converter zero times,
            // measured on this codebase rather than reasoned about. The element-level evidence for
            // the three types lives in the unit project against canned one-element bodies, in
            // Performer_list_body_deserializes_with_asserted_field_values and its studio and credit
            // siblings. What is left here is to state the count that was observed.
            //
            // xUnit2013 prefers Assert.Empty for these three lines and this repo treats it as an
            // error. It is suppressed here and only here, and the reason is compliance with the
            // wording these three assertions are written against, which names the shape helper it
            // does not accept. Assert.Empty(list) and Assert.Equal(0, list.Count) otherwise pass
            // and fail on identical inputs, so the choice is not a difference in what is proven.
#pragma warning disable xUnit2013
            Assert.Equal(0, performers.Count);
            Assert.Equal(0, studios.Count);
            Assert.Equal(0, credits.Count);
#pragma warning restore xUnit2013
        }

        /// <summary>
        /// An operation whose spec declares no response content still delivers a body, and ReadAs
        /// binds it to a type the caller names.
        /// </summary>
        /// <remarks>
        /// <para>
        /// GetCustomFormatSchema is one of the 92 operations that declare a 2xx and declare no
        /// content for it, so the generated response carries no typed accessor. This is the live
        /// half of the evidence: the unit project pins the classification against canned bodies,
        /// and this pins that a real Whisparr answers one of them with a JSON body that binds.
        /// </para>
        /// <para>
        /// The probe type is declared here rather than taken from Whisparr3.Net.Model, because a
        /// caller of one of these operations has no model to take. Its JsonPropertyName attributes
        /// are required: the client registers no naming policy, so a Pascal-cased member binds
        /// nothing without one and does so silently.
        /// </para>
        /// <para>
        /// Read-only. It adds nothing to the write inventory recorded in this project README.
        /// </para>
        /// </remarks>
        [SkippableFact]
        public async Task Content_less_operation_body_binds_through_read_as()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildProvider();

            IGetCustomFormatSchemaApiResponse response = await provider
                .GetRequiredService<ICustomFormatApi>()
                .GetCustomFormatSchemaAsync();

            response.EnsureSuccess();

            // The body arrived even though the spec named no type for it. Asserted before the
            // deserialization, so a failure here says the body was empty rather than that the type
            // was wrong.
            Assert.False(string.IsNullOrWhiteSpace(response.RawContent));

            List<SpecificationProbe> schema =
                ((Whisparr3.Net.Client.ApiResponse)response).ReadAs<List<SpecificationProbe>>();

            // Field values, not a non-null check. A list of objects whose every member stayed at
            // its default is exactly what a missing JsonPropertyName produces, and a non-null check
            // passes against it.
            Assert.NotEmpty(schema);
            Assert.All(schema, item => Assert.False(string.IsNullOrWhiteSpace(item.Implementation)));
            Assert.Contains(schema, item =>
                string.Equals("ReleaseTitleSpecification", item.Implementation, StringComparison.Ordinal));
        }

        /// <summary>
        /// The shape a caller supplies for the custom-format schema, which the spec does not
        /// describe.
        /// </summary>
        public sealed class SpecificationProbe
        {
            /// <summary>The specification implementation name.</summary>
            [System.Text.Json.Serialization.JsonPropertyName("implementation")]
            public string? Implementation { get; set; }

            /// <summary>The negate flag each specification carries.</summary>
            [System.Text.Json.Serialization.JsonPropertyName("negate")]
            public bool Negate { get; set; }
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
