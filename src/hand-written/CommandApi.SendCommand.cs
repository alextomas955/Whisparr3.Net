// Hand-written. Nothing in this directory is generator output; see CLAUDE.md, section
// "Generated vs hand-written". Do not add the generator's file-marker header to this file:
// it is a false statement here, and it switches off the analyzer coverage that .editorconfig
// gives this directory and gives nothing else in the repository.

#nullable enable

using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Whisparr3.Net.Client;
using Whisparr3.Net.Model;

namespace Whisparr3.Net.Api
{
    public sealed partial class CommandApi
    {
        /// <summary>
        /// Dispatches a command with its arguments and returns the queued command.
        /// </summary>
        /// <param name="name">The command name, for example <c>RefreshStudios</c>.</param>
        /// <param name="payload">
        /// The command arguments, or null for a command that takes none. Anything that serializes
        /// to a JSON object is accepted: an anonymous type, a record, or a dictionary.
        /// </param>
        /// <param name="cancellationToken">Cancels the request.</param>
        /// <returns>The queued command as the server reports it.</returns>
        /// <exception cref="ArgumentException">
        /// <paramref name="name"/> is null, empty or white space; or <paramref name="payload"/>
        /// does not serialize to a JSON object; or <paramref name="payload"/> carries a member
        /// named <c>name</c> under a case-insensitive comparison. A colliding member is refused
        /// rather than merged because a differently-cased key would survive alongside the command
        /// name and leave the server two candidates for one property. Dropping or duplicating a
        /// caller's field at a public boundary is worse than refusing the call.
        /// </exception>
        /// <exception cref="Whisparr3ApiException">
        /// The status was not a success, or it was a success whose body could not be read.
        /// </exception>
        /// <remarks>
        /// <para>
        /// The payload members are written flat, as siblings of the name member. The server rewinds
        /// the request stream and deserializes the whole body into a concrete command type, so the
        /// arguments do not belong under CommandResource.Body and putting them there sends a
        /// command with no arguments.
        /// </para>
        /// <para>
        /// The parameter is object rather than a type per command because the specification
        /// describes none of the per-command fields. Whisparr has 42 commands and 25 of them take
        /// arguments, and no shape for any of them appears in the specification this client is
        /// generated from.
        /// </para>
        /// <para>
        /// This file stays under src/hand-written/ even though its namespace belongs to the
        /// generated tree. A partial declared here reaches the private serializer options on the
        /// generated class without the file being destroyed on the next regeneration.
        /// </para>
        /// <para>
        /// ICommandApi is generated and is not declared partial, so it cannot carry this method.
        /// AddWhisparr3 therefore registers the concrete CommandApi alongside the interface: inject
        /// CommandApi to reach this method, and ICommandApi when the generated operations are all
        /// that is needed.
        /// </para>
        /// </remarks>
        public async Task<CommandResource> SendCommandAsync(
            string name,
            object? payload = null,
            CancellationToken cancellationToken = default)
        {
            ArgumentException.ThrowIfNullOrWhiteSpace(name);

            JsonObject body;

            if (payload is null)
            {
                body = new JsonObject();
            }
            else
            {
                JsonNode? node = JsonSerializer.SerializeToNode(payload, _jsonSerializerOptions);

                // A boxed scalar serializes to a JsonValue, so this is reachable from a caller and
                // an unguarded null-forgiving operator here would raise a NullReferenceException
                // from inside the library.
                body = node as JsonObject
                    ?? throw new ArgumentException(
                        "A command payload must serialize to a JSON object.", nameof(payload));

                // The loop only reads and the name member is set after it, so the collection is
                // never mutated while it is enumerated.
                foreach (KeyValuePair<string, JsonNode?> member in body)
                {
                    if (string.Equals(member.Key, "name", StringComparison.OrdinalIgnoreCase))
                    {
                        throw new ArgumentException(
                            "A command payload must not carry a member named '" + member.Key
                                + "'. The command name is the name parameter.",
                            nameof(payload));
                    }
                }
            }

            body["name"] = JsonValue.Create(name);

            UriBuilder uriBuilder = new();

            using HttpRequestMessage httpRequestMessage = new();

            uriBuilder.Host = HttpClient.BaseAddress!.Host;
            uriBuilder.Port = HttpClient.BaseAddress.Port;
            uriBuilder.Scheme = HttpClient.BaseAddress.Scheme;
            uriBuilder.Path = HttpClient.BaseAddress.AbsolutePath == "/"
                ? "/api/v3/command"
                : string.Concat(HttpClient.BaseAddress.AbsolutePath.TrimEnd('/'), "/api/v3/command");

            httpRequestMessage.Content = new StringContent(body.ToJsonString());

            // StringContent defaults to text/plain and the server answers 415 to that, so the
            // header is overwritten once the content exists.
            string? contentType = ClientUtils.SelectHeaderContentType(new string[] { "application/json" });

            if (contentType != null)
            {
                httpRequestMessage.Content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
            }

            // The credential is applied per request rather than by a handler, which is what the
            // generated operations do. A DelegatingHandler here would be a second mechanism and
            // would double the header.
            List<TokenBase> tokens = new();
            ApiKeyToken apiKeyToken =
                (ApiKeyToken)await ApiKeyProvider.GetAsync("X-Api-Key", cancellationToken).ConfigureAwait(false);
            tokens.Add(apiKeyToken);
            apiKeyToken.UseInHeader(httpRequestMessage);

            foreach (MediaTypeWithQualityHeaderValue accept in
                ClientUtils.SelectHeaderAcceptArray(new string[] { "application/json" }))
            {
                httpRequestMessage.Headers.Accept.Add(accept);
            }

            httpRequestMessage.Method = HttpMethod.Post;
            httpRequestMessage.RequestUri = uriBuilder.Uri;

            DateTime requestedAt = DateTime.UtcNow;

            using HttpResponseMessage httpResponseMessage =
                await HttpClient.SendAsync(httpRequestMessage, cancellationToken).ConfigureAwait(false);

            string rawContent =
                await httpResponseMessage.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);

            CreateCommandApiResponse apiResponse = new(
                Logger,
                httpRequestMessage,
                httpResponseMessage,
                rawContent,
                "/api/v3/command",
                requestedAt,
                _jsonSerializerOptions);

            // The token provider is shared across every api class, so skipping this would make the
            // client's rate-limit accounting depend on which method met the 429.
            if (apiResponse.StatusCode == (HttpStatusCode)429)
            {
                foreach (TokenBase token in tokens)
                {
                    token.BeginRateLimit();
                }
            }

            return apiResponse.ReadAs<CommandResource>();
        }
    }
}
