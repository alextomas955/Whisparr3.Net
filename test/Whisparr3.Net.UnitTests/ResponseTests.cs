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
        /// The tag payload the create operation answers with, in the shape the live instance sends
        /// it: label first, then the id the server assigned. The label carries a hyphen and lower
        /// case letters so an ordinal comparison over it means something.
        /// </summary>
        private const string CreatedTagBody =
            "{\"label\":\"created-tag\",\"id\":5}";

        /// <summary>The id inside <see cref="CreatedTagBody"/>.</summary>
        private const int CreatedTagId = 5;

        /// <summary>The label inside <see cref="CreatedTagBody"/>.</summary>
        private const string CreatedTagLabel = "created-tag";

        /// <summary>
        /// A one-element performer list body, taken member by member from
        /// components.schemas.PerformerResource in spec/openapi.generated.json, with the nested
        /// cover taken from components.schemas.MediaCover.
        /// </summary>
        /// <remarks>
        /// sizeOnDisk is above int32 range on purpose. The schema declares it int64 and a value
        /// inside int32 range would pass whether or not the converter performed a 64-bit read.
        /// </remarks>
        private const string PerformerListBody =
            "[{\"id\":5,"
                + "\"fullName\":\"Probe Performer\","
                + "\"name\":\"Probe\","
                + "\"gender\":\"female\","
                + "\"status\":\"active\","
                + "\"country\":\"NL\","
                + "\"height\":170,"
                + "\"sceneCount\":3,"
                + "\"sizeOnDisk\":4294967296,"
                + "\"aliases\":[\"Probe\"],"
                + "\"images\":[{\"coverType\":\"headshot\",\"url\":\"/probe/headshot.jpg\"}]}]";

        /// <summary>
        /// A one-element studio list body, taken member by member from
        /// components.schemas.StudioResource, with the nested cover taken from
        /// components.schemas.MediaCover.
        /// </summary>
        /// <remarks>
        /// sizeOnDisk is above int32 range for the same reason as the performer body, and years is
        /// a second collection of a primitive so the list-of-scalars path is entered as well.
        /// </remarks>
        private const string StudioListBody =
            "[{\"id\":3,"
                + "\"title\":\"Probe Studio\","
                + "\"sortTitle\":\"probe studio\","
                + "\"foreignId\":\"probe-studio-1\","
                + "\"status\":\"active\","
                + "\"monitored\":true,"
                + "\"moviesMonitored\":false,"
                + "\"qualityProfileId\":1,"
                + "\"sceneCount\":2,"
                + "\"sizeOnDisk\":4294967296,"
                + "\"aliases\":[\"Probe\"],"
                + "\"years\":[2024],"
                + "\"images\":[{\"coverType\":\"poster\",\"url\":\"/probe/poster.jpg\"}]}]";

        /// <summary>
        /// A one-element credit list body, taken member by member from
        /// components.schemas.CreditResource, with the nested cover taken from
        /// components.schemas.MediaCover.
        /// </summary>
        /// <remarks>
        /// CreditResource declares no 64-bit member, so this body carries no value above int32
        /// range. It carries a string enum and a nested cover like the other two.
        /// </remarks>
        private const string CreditListBody =
            "[{\"id\":11,"
                + "\"personName\":\"Probe Person\","
                + "\"performerId\":4,"
                + "\"foreignId\":\"probe-person-1\","
                + "\"movieMetadataId\":9,"
                + "\"job\":\"Director\","
                + "\"character\":\"Herself\","
                + "\"order\":0,"
                + "\"type\":\"crew\","
                + "\"canMonitor\":true,"
                + "\"monitored\":false,"
                + "\"images\":[{\"coverType\":\"headshot\",\"url\":\"/probe/person.jpg\"}]}]";

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
        /// PerformerResource is deserialized on the list path, from a body carrying one element.
        /// </summary>
        /// <remarks>
        /// The live suite cannot produce this evidence. The endpoint answers with an empty array on
        /// a fresh instance, an empty array binds the List shell and enters the element converter
        /// zero times, and that was measured on this codebase rather than reasoned about. The two
        /// create and update cases above deserialize a single object, so this is the only case that
        /// covers the same list operation the live test calls.
        /// </remarks>
        [Fact]
        public async Task Performer_list_body_deserializes_with_asserted_field_values()
        {
            using LoopbackCapture capture = new(status: 200, body: PerformerListBody);

            await using ServiceProvider provider = BuildProvider(capture);
            IListPerformerApiResponse response =
                await provider.GetRequiredService<IPerformerApi>().ListPerformerAsync();

            List<PerformerResource> performers = response.EnsureSuccess();

            PerformerResource performer = Assert.Single(performers);

            Assert.Equal(5, performer.Id);
            Assert.True(
                string.Equals("Probe Performer", performer.FullName, StringComparison.Ordinal),
                $"fullName deserialized as '{performer.FullName}'.");
            Assert.True(
                string.Equals("Probe", performer.Name, StringComparison.Ordinal),
                $"name deserialized as '{performer.Name}'.");
            Assert.Equal(Gender.Female, performer.Gender);
            Assert.Equal(PerformerStatus.Active, performer.Status);
            Assert.True(
                string.Equals("NL", performer.Country, StringComparison.Ordinal),
                $"country deserialized as '{performer.Country}'.");
            Assert.Equal(170, performer.Height);
            Assert.Equal(3, performer.SceneCount);
            Assert.Equal(4294967296L, performer.SizeOnDisk);

            string alias = Assert.Single(performer.Aliases!);
            Assert.True(
                string.Equals("Probe", alias, StringComparison.Ordinal),
                $"the single alias deserialized as '{alias}'.");

            MediaCover cover = Assert.Single(performer.Images!);
            Assert.Equal(MediaCoverTypes.Headshot, cover.CoverType);
            Assert.True(
                string.Equals("/probe/headshot.jpg", cover.Url, StringComparison.Ordinal),
                $"the nested cover url deserialized as '{cover.Url}'.");
        }

        /// <summary>
        /// StudioResource is deserialized, which before this case happened nowhere in this
        /// repository, from any body, by any test.
        /// </summary>
        /// <remarks>
        /// The live suite cannot produce this evidence. The endpoint answers with an empty array on
        /// a fresh instance, an empty array binds the List shell and enters the element converter
        /// zero times, and that was measured on this codebase rather than reasoned about. Creating a
        /// studio routes through an external metadata service, so seeding one would make the live
        /// suite depend on a third party.
        /// </remarks>
        [Fact]
        public async Task Studio_list_body_deserializes_with_asserted_field_values()
        {
            using LoopbackCapture capture = new(status: 200, body: StudioListBody);

            await using ServiceProvider provider = BuildProvider(capture);
            IListStudioApiResponse response =
                await provider.GetRequiredService<IStudioApi>().ListStudioAsync();

            List<StudioResource> studios = response.EnsureSuccess();

            StudioResource studio = Assert.Single(studios);

            Assert.Equal(3, studio.Id);
            Assert.True(
                string.Equals("Probe Studio", studio.Title, StringComparison.Ordinal),
                $"title deserialized as '{studio.Title}'.");
            Assert.True(
                string.Equals("probe studio", studio.SortTitle, StringComparison.Ordinal),
                $"sortTitle deserialized as '{studio.SortTitle}'.");
            Assert.True(
                string.Equals("probe-studio-1", studio.ForeignId, StringComparison.Ordinal),
                $"foreignId deserialized as '{studio.ForeignId}'.");
            Assert.Equal(StudioStatus.Active, studio.Status);
            Assert.True(studio.Monitored);
            Assert.False(studio.MoviesMonitored);
            Assert.Equal(1, studio.QualityProfileId);
            Assert.Equal(2, studio.SceneCount);
            Assert.Equal(4294967296L, studio.SizeOnDisk);

            string alias = Assert.Single(studio.Aliases!);
            Assert.True(
                string.Equals("Probe", alias, StringComparison.Ordinal),
                $"the single alias deserialized as '{alias}'.");

            int year = Assert.Single(studio.Years!);
            Assert.Equal(2024, year);

            MediaCover cover = Assert.Single(studio.Images!);
            Assert.Equal(MediaCoverTypes.Poster, cover.CoverType);
            Assert.True(
                string.Equals("/probe/poster.jpg", cover.Url, StringComparison.Ordinal),
                $"the nested cover url deserialized as '{cover.Url}'.");
        }

        /// <summary>
        /// CreditResource is deserialized, which before this case happened nowhere in this
        /// repository, from any body, by any test.
        /// </summary>
        /// <remarks>
        /// A canned body is the only evidence that can exist for this type. The spec declares
        /// exactly two credit operations and both are GET, so no live body can ever be made to
        /// carry an element. The live endpoint answers with an empty array, an empty array binds the
        /// List shell and enters the element converter zero times, and that was measured on this
        /// codebase rather than reasoned about.
        /// </remarks>
        [Fact]
        public async Task Credit_list_body_deserializes_with_asserted_field_values()
        {
            using LoopbackCapture capture = new(status: 200, body: CreditListBody);

            await using ServiceProvider provider = BuildProvider(capture);
            IListCreditApiResponse response =
                await provider.GetRequiredService<ICreditApi>().ListCreditAsync();

            List<CreditResource> credits = response.EnsureSuccess();

            CreditResource credit = Assert.Single(credits);

            Assert.Equal(11, credit.Id);
            Assert.True(
                string.Equals("Probe Person", credit.PersonName, StringComparison.Ordinal),
                $"personName deserialized as '{credit.PersonName}'.");
            Assert.Equal(4, credit.PerformerId);
            Assert.True(
                string.Equals("probe-person-1", credit.ForeignId, StringComparison.Ordinal),
                $"foreignId deserialized as '{credit.ForeignId}'.");
            Assert.Equal(9, credit.MovieMetadataId);
            Assert.True(
                string.Equals("Director", credit.Job, StringComparison.Ordinal),
                $"job deserialized as '{credit.Job}'.");
            Assert.True(
                string.Equals("Herself", credit.Character, StringComparison.Ordinal),
                $"character deserialized as '{credit.Character}'.");
            Assert.Equal(0, credit.Order);
            Assert.Equal(CreditType.Crew, credit.Type);
            Assert.True(credit.CanMonitor);
            Assert.False(credit.Monitored);

            MediaCover cover = Assert.Single(credit.Images!);
            Assert.Equal(MediaCoverTypes.Headshot, cover.CoverType);
            Assert.True(
                string.Equals("/probe/person.jpg", cover.Url, StringComparison.Ordinal),
                $"the nested cover url deserialized as '{cover.Url}'.");
        }

        /// <summary>
        /// The tag create is the operation the live instance answers 201 on while its spec
        /// documents 200 only, so without the hook its body is unreachable through any typed
        /// accessor. This is the synthetic form of the live round trip's first leg.
        /// </summary>
        [Fact]
        public async Task Created_tag_body_is_readable_through_EnsureSuccess()
        {
            using LoopbackCapture capture = new(status: 201, body: CreatedTagBody);

            await using ServiceProvider provider = BuildProvider(capture);
            ICreateTagApiResponse response =
                await provider.GetRequiredService<ITagApi>().CreateTagAsync();

            TagResource created = response.EnsureSuccess();

            Assert.Equal(CreatedTagId, created.Id);
            Assert.Equal(CreatedTagLabel, created.Label);
        }

        /// <summary>
        /// The negative control, and the one test here that must not be dropped. The hook's only
        /// real risk is taking over the ordinary 200 path, and every other tag test would still
        /// pass if it did. The status guard is what leaves this path on the generated default.
        /// </summary>
        [Fact]
        public async Task Ordinary_200_tag_body_still_takes_the_generated_default()
        {
            using LoopbackCapture capture = new(status: 200, body: CreatedTagBody);

            await using ServiceProvider provider = BuildProvider(capture);
            ICreateTagApiResponse response =
                await provider.GetRequiredService<ITagApi>().CreateTagAsync();

            TagResource created = response.EnsureSuccess();

            Assert.Equal(CreatedTagId, created.Id);
            Assert.Equal(CreatedTagLabel, created.Label);
        }

        /// <summary>
        /// The empty-body case, which without the body guard in the hook throws a raw serialization
        /// exception straight out of the accessor and escapes the typed layer untyped.
        /// </summary>
        [Fact]
        public async Task Empty_201_tag_body_surfaces_the_typed_error()
        {
            using LoopbackCapture capture = new(status: 201, body: string.Empty);

            await using ServiceProvider provider = BuildProvider(capture);
            ICreateTagApiResponse response =
                await provider.GetRequiredService<ITagApi>().CreateTagAsync();

            Whisparr3ApiException error =
                Assert.Throws<Whisparr3ApiException>(() => { response.EnsureSuccess(); });

            Assert.Equal(HttpStatusCode.Created, error.StatusCode);
            Assert.Equal("/api/v3/tag", error.Path);
            Assert.True(error.IsSuccessStatusCode);
            Assert.Contains("201", error.Message, StringComparison.Ordinal);
            Assert.Contains("/api/v3/tag", error.Message, StringComparison.Ordinal);
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
