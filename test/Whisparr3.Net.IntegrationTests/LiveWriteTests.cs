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
    /// The create leg is the one operation in this phase's safe-POST set. Every other write in the
    /// API is on the do-not-call list, POST /api/v3/command worst of all, because its name is a
    /// free-form string and the name alone decides between refreshing metadata and renaming every
    /// file on disk. Nothing here calls anything but the four tag operations.
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
            // is what does. It stays an equality: xUnit2013 prefers Assert.Empty here and this repo
            // treats that as an error, but a shape helper would read the same whether the list came
            // back empty or the assertion had nothing to say about a count at all.
            List<TagResource> remaining = (await tags.ListTagAsync()).EnsureSuccess();

#pragma warning disable xUnit2013
            Assert.Equal(0, remaining.Count);
#pragma warning restore xUnit2013
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
        /// The server refuses <c>text/json</c> on the tag create with 415.
        /// </summary>
        /// <remarks>
        /// <para>
        /// This does not go through the generated client, and it cannot. SelectHeaderContentType
        /// returns the first declared media type matching its JSON regex, and text/json is neither
        /// application/json nor a plus-json suffix type, so it matches nothing and the client can
        /// never select it under any declaration order. The only way to observe what the server
        /// does with it is to set the header by hand.
        /// </para>
        /// <para>
        /// It closes the criterion's text/json clause from the server's side rather than only from
        /// the client's. It is one request on the only operation in this phase's safe-POST set, it
        /// creates nothing because the request is refused before a tag is made, and it touches
        /// nothing on the do-not-call list.
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

            using StringContent content = new("{\"label\":\"w3n-text-json-probe\"}");
            content.Headers.ContentType = new MediaTypeHeaderValue("text/json");

            using HttpResponseMessage response =
                await client.PostAsync(new Uri("/api/v3/tag", UriKind.Relative), content);

            Assert.Equal(HttpStatusCode.UnsupportedMediaType, response.StatusCode);
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
