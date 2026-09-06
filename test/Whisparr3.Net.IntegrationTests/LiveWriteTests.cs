// Hand-written test code. See CLAUDE.md, section "Generated vs hand-written".

#nullable enable

using System.Net;
using System.Net.Http.Headers;
using Microsoft.Extensions.DependencyInjection;
using Whisparr3.Net.Api;
using Whisparr3.Net.Model;

namespace Whisparr3.Net.IntegrationTests
{
    /// <summary>
    /// Write assertions issued by a real client against a real Whisparr over a real socket.
    /// </summary>
    /// <remarks>
    /// <para>
    /// One level up from ResponseTests.cs. There the status codes and bodies are canned by a
    /// loopback listener, so the tests prove what the client does with a response it was handed.
    /// Here the responses come from a real Whisparr, so they prove what the server actually
    /// answers. The two disagree on this very operation: the committed spec documents 200 for the
    /// tag create and the instance answers 201.
    /// </para>
    /// <para>
    /// POST /api/v3/command is the most consequential write in the API, because its name is a
    /// free-form string and the name alone decides between refreshing metadata and renaming every
    /// file on disk. That hazard has not gone away. This suite sends exactly one command,
    /// RefreshStudios, and it sends it with an explicit studio id list naming an id a fresh
    /// instance cannot have assigned. That is what makes the dispatch inert here: the command is
    /// accepted, terminates at the database lookup for that id, and never reaches an external
    /// metadata service. The id list is never allowed to default, because a refresh with an empty
    /// or absent list is understood to refresh everything. Apart from that one command and the
    /// unknown name the server rejects, nothing here calls anything but the four tag operations.
    /// </para>
    /// <para>
    /// Every response is classified by EnsureSuccess rather than by reading the generated success
    /// accessor, which deserializes on exactly 200 and returns null on anything else.
    /// </para>
    /// </remarks>
    [Collection(WhisparrCollection.Name)]
    public sealed class LiveWriteTests(WhisparrFixture fixture)
    {
        /// <summary>
        /// The label the round trip writes. An obvious throwaway, and distinctive enough that a
        /// read-back matching it means the write landed rather than that some default value
        /// happened to agree. Nothing in a fresh Whisparr database carries this string.
        /// </summary>
        private const string RoundTripLabel = "w3n-round-trip-probe";

        /// <summary>
        /// The label the deleted-id control writes. Separate from the round trip's own label, so a
        /// failure message names which test left the row behind.
        /// </summary>
        private const string ControlLabel = "w3n-deleted-id-probe";

        /// <summary>
        /// The label the text/json probe sends. The request and the assertion that no tag carries
        /// it both read this constant, so the two cannot drift apart.
        /// </summary>
        private const string TextJsonProbeLabel = "w3n-text-json-probe";

        /// <summary>
        /// A studio id a fresh instance cannot have assigned. Whisparr assigns studio ids from 1
        /// upward and a container that has imported nothing holds no studios at all, so this id
        /// exists on no instance this suite can reach.
        /// </summary>
        private const int UnknownStudioId = 987654321;

        /// <summary>
        /// The one command name this suite dispatches. Measured against the pinned image: with the
        /// id list below it is accepted with 201 and then terminates in under a second at
        /// BasicRepository.Get, with a ModelNotFoundException naming the id. It dies at the
        /// database lookup and never reaches an external metadata service.
        /// </summary>
        private const string DispatchedCommandName = "RefreshStudios";

        /// <summary>
        /// A command name no Whisparr build defines. The server has to reject it, so nothing runs.
        /// </summary>
        private const string UnknownCommandName = "NotARealCommand";

        /// <summary>
        /// Create, read back, delete and list, against a real instance, every leg through the
        /// hand-written layer.
        /// </summary>
        /// <remarks>
        /// The legs are issued in order and each one is asserted before the next is issued, so a
        /// failure names the leg rather than the trip. The id is captured from the create response
        /// and every later leg is addressed by that local, never by a literal: the server assigns
        /// ids and does not reuse them after a delete, so a literal would be right once.
        /// </remarks>
        [SkippableFact]
        public async Task Tag_round_trip_creates_reads_and_deletes()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildProvider();
            ITagApi tags = provider.GetRequiredService<ITagApi>();

            // Leg 1, create. The id is left unset on the request, which is the Option<T> write
            // semantic SerializationTests proves on the request bytes. Without the hook in
            // src/hand-written/ApiResponseExtensions.cs this line throws: the instance answers 201,
            // the generated accessor deserializes on exactly 200, and EnsureSuccess reports a
            // success whose body could not be read.
            TagResource created = (await tags.CreateTagAsync(new TagResource(label: RoundTripLabel)))
                .EnsureSuccess();

            Assert.True(created.Id.HasValue, "The create response carried no id.");
            int createdId = created.Id!.Value;

            Assert.True(
                createdId > 0,
                $"The server assigned id {createdId}, which is not a positive integer.");

            Assert.True(
                string.Equals(RoundTripLabel, created.Label, StringComparison.Ordinal),
                $"The create returned label '{created.Label}'. The request sent '{RoundTripLabel}'.");

            // Leg 2, read back. The id is compared as an integer with no string conversion in
            // between, because TagResource.Id is int32 and a comparison through text would pass on
            // two values that are not the same number.
            TagResource readBack = (await tags.GetTagByIdAsync(createdId)).EnsureSuccess();

            Assert.True(readBack.Id.HasValue, "The read-back carried no id.");
            Assert.Equal(createdId, readBack.Id!.Value);

            Assert.True(
                string.Equals(RoundTripLabel, readBack.Label, StringComparison.Ordinal),
                $"The read-back returned label '{readBack.Label}'. The create wrote '{RoundTripLabel}'.");

            // Leg 3, delete. IDeleteTagApiResponse carries no typed success accessor, so this is
            // the non-generic EnsureSuccess overload, and this is the only place in the phase where
            // that overload meets a real server rather than a loopback stub.
            (await tags.DeleteTagAsync(createdId)).EnsureSuccess();

            // Leg 4, list. The delete's own status code does not prove the row is gone, and this
            // is what does. The assertion is about this test's row, by id and by label, rather than
            // about every tag on the instance. Three tests in this class post to /api/v3/tag and
            // xUnit does not specify method order, so a row left behind by one of the others would
            // otherwise fail this trip with a message about its delete leg.
            List<TagResource> remaining = (await tags.ListTagAsync()).EnsureSuccess();

            Assert.DoesNotContain(remaining, tag => tag.Id == createdId);
            Assert.DoesNotContain(
                remaining,
                tag => string.Equals(RoundTripLabel, tag.Label, StringComparison.Ordinal));
        }

        /// <summary>
        /// A deleted tag and a tag that never existed are the same observable.
        /// </summary>
        /// <remarks>
        /// This is what stops the round trip mistaking a stale read for a successful one. It is a
        /// test of its own rather than a fifth leg on the round trip, so the round trip's failure
        /// message stays about the round trip. The status is named rather than only the exception
        /// type: asserting that something was thrown proves that something happened, not what.
        /// </remarks>
        [SkippableFact]
        public async Task Deleted_tag_id_answers_404()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildProvider();
            ITagApi tags = provider.GetRequiredService<ITagApi>();

            TagResource created = (await tags.CreateTagAsync(new TagResource(label: ControlLabel)))
                .EnsureSuccess();

            Assert.True(created.Id.HasValue, "The create response carried no id.");
            int deletedId = created.Id!.Value;

            (await tags.DeleteTagAsync(deletedId)).EnsureSuccess();

            IGetTagByIdApiResponse response = await tags.GetTagByIdAsync(deletedId);

            Whisparr3ApiException error =
                Assert.Throws<Whisparr3ApiException>(() => { response.EnsureSuccess(); });

            Assert.Equal(HttpStatusCode.NotFound, error.StatusCode);
            Assert.False(error.IsSuccessStatusCode);
        }

        /// <summary>
        /// A real Whisparr accepts a flat command body and answers a readable 201.
        /// </summary>
        /// <remarks>
        /// <para>
        /// The unit suite proves the flat body left the client, on the captured bytes. Only a real
        /// instance proves the body is accepted, that the answer is 201, and that the 201 reads
        /// back as a CommandResource through the hand-written layer. The generated create cannot
        /// put a command argument on the wire at all, so this is the only path that can be proven
        /// here.
        /// </para>
        /// <para>
        /// CommandApi is resolved as the concrete type. SendCommandAsync is declared on it and not
        /// on ICommandApi, which is generator output and is not partial, and AddWhisparr3 registers
        /// the concrete type for exactly this reason. Resolving it here is what proves that
        /// registration works from a consumer's position.
        /// </para>
        /// <para>
        /// Nothing is asserted about the echoed studioIds. The typed CommandResource.Body is a
        /// Command, which is additionalProperties false and whose generated reader ends
        /// default: break;, so the argument is dropped on the way in and no assertion here could
        /// see it. The wire shape is pinned instead by
        /// SerializationTests.Command_dispatch_puts_a_flat_name_and_payload_body_on_the_wire.
        /// </para>
        /// <para>
        /// Nothing is asserted about the outcome either. The 201 is a dispatch acknowledgement and
        /// not a statement about execution, and this command's terminal status is failed by
        /// design, because the id it names does not exist.
        /// </para>
        /// </remarks>
        [SkippableFact]
        public async Task Command_dispatch_is_accepted_and_reads_back_as_a_command_resource()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildProvider();
            CommandApi commands = provider.GetRequiredService<CommandApi>();

            ICreateCommandApiResponse response = await commands.SendCommandAsync(
                DispatchedCommandName,
                new { studioIds = new[] { UnknownStudioId } });

            // The instance answers 201 to an accepted command while the specification declares 200,
            // so the generated Ok accessor reads nothing here and EnsureSuccess is what reads the
            // body. Asserting the status first is what pins that a caller no longer has to compose
            // one for the accepted path.
            Assert.Equal(HttpStatusCode.Created, response.StatusCode);

            CommandResource dispatched = response.EnsureSuccess();

            Assert.True(dispatched.Id.HasValue, "The dispatch response carried no id.");

            Assert.True(
                dispatched.Id!.Value > 0,
                $"The server assigned command id {dispatched.Id!.Value}, which is not a positive integer.");

            Assert.True(
                string.Equals(DispatchedCommandName, dispatched.Name, StringComparison.Ordinal),
                $"The dispatch returned name '{dispatched.Name}'. The request sent '{DispatchedCommandName}'.");
        }

        /// <summary>
        /// A command name the server does not know is a typed 400, not a bodiless success.
        /// </summary>
        /// <remarks>
        /// The status is named rather than only the exception type. The body's shape is
        /// deliberately not asserted: the instance answers with the plain string
        /// "Unknown command type: NotARealCommand", which is not a JSON object, so an assertion
        /// built on a problem-details shape would encode a claim that is false. This case creates
        /// nothing, so it adds nothing to the suite's write inventory beyond the dispatch itself.
        /// </remarks>
        [SkippableFact]
        public async Task Unknown_command_name_surfaces_as_a_failure()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            await using ServiceProvider provider = BuildProvider();
            CommandApi commands = provider.GetRequiredService<CommandApi>();

            ICreateCommandApiResponse response = await commands.SendCommandAsync(UnknownCommandName);

            // The refusal is reported through the status and not by throwing, which is what lets a
            // caller that must not re-issue a command classify the call it made. EnsureSuccess is
            // what turns it into an exception, and that is the caller's choice rather than this
            // method's.
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.False(response.IsSuccessStatusCode);

            Whisparr3ApiException error =
                Assert.Throws<Whisparr3ApiException>(() => { response.EnsureSuccess(); });

            Assert.Equal(HttpStatusCode.BadRequest, error.StatusCode);
            Assert.False(error.IsSuccessStatusCode);
        }

        /// <summary>
        /// The server refuses <c>text/json</c> on the tag create with 415.
        /// </summary>
        /// <remarks>
        /// <para>
        /// This does not go through the generated client, and it cannot. SelectHeaderContentType
        /// returns the first declared media type matching its JSON regex, and text/json is neither
        /// application/json nor a plus-json suffix type, so it matches nothing. The claim holds for
        /// this operation because the tag create declares application/json and nothing else, in
        /// src/Whisparr3.Net/Api/TagApi.cs, so the JSON branch always fires here. It is not a claim
        /// about every operation: when nothing matches, that helper falls back to the first
        /// declared media type, so an operation declaring text/json alone would select it. The only
        /// way to observe what the server does with the header is to set it by hand.
        /// </para>
        /// <para>
        /// It closes the criterion's text/json clause from the server's side rather than only from
        /// the client's. It is one request on the only operation in this phase's safe-POST set, and
        /// it touches nothing on the do-not-call list. That the refused request creates nothing is
        /// asserted below by listing tags and finding no row carrying the probe label, rather than
        /// stated here.
        /// </para>
        /// <para>
        /// The base URL and the key come from the fixture, never from a literal and never from the
        /// environment, so this plain HttpClient can only reach the container this run created.
        /// The response body is deliberately not asserted: it is an ASP.NET Core error payload
        /// whose shape belongs to the framework rather than to Whisparr.
        /// </para>
        /// </remarks>
        [SkippableFact]
        public async Task Text_json_is_refused_with_415()
        {
            Skip.If(fixture.SkipReason is not null, fixture.SkipReason);

            using HttpClient client = new() { BaseAddress = new Uri(fixture.BaseUrl) };
            client.DefaultRequestHeaders.Add("X-Api-Key", fixture.ApiKey);

            using StringContent content = new($"{{\"label\":\"{TextJsonProbeLabel}\"}}");
            content.Headers.ContentType = new MediaTypeHeaderValue("text/json");

            using HttpResponseMessage response =
                await client.PostAsync(new Uri("/api/v3/tag", UriKind.Relative), content);

            Assert.Equal(HttpStatusCode.UnsupportedMediaType, response.StatusCode);

            // The refusal status alone does not prove nothing was written. ListTag is a GET and is
            // not on the do-not-call list, so listing is what turns the no-write claim above into
            // an assertion. Only this probe's own label is looked for, so a row another test left
            // behind fails that test rather than this one.
            await using ServiceProvider provider = BuildProvider();

            List<TagResource> tags = (await provider
                .GetRequiredService<ITagApi>()
                .ListTagAsync())
                .EnsureSuccess();

            Assert.DoesNotContain(
                tags,
                tag => string.Equals(TextJsonProbeLabel, tag.Label, StringComparison.Ordinal));
        }

        /// <summary>
        /// Builds a provider pointed at the container this run started.
        /// </summary>
        /// <returns>A provider the caller owns and disposes.</returns>
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
