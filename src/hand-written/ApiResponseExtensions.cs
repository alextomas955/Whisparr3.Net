// Hand-written. Nothing in this directory is generator output; see CLAUDE.md, section
// "Generated vs hand-written". Do not add the generator's file-marker header to this file:
// it is a false statement here, and it switches off the analyzer coverage that .editorconfig
// gives this directory and gives nothing else in the repository.

#nullable enable

using System;
using System.Text.Json;
using Whisparr3.Net.Client;

namespace Whisparr3.Net
{
    /// <summary>
    /// Turns a response into either its body or a typed error.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The generated success accessor deserializes on exactly 200 and returns null on anything
    /// else, so a 401, a documented 201 and an empty collection are all reported to a caller as
    /// null. These two methods classify the same response into three outcomes instead: a success
    /// carrying a body, a success whose body cannot be read, and a failure. The last two both
    /// throw, and Whisparr3ApiException.IsSuccessStatusCode is what tells them apart.
    /// </para>
    /// <para>
    /// Every operation also exposes an OrDefaultAsync variant that wraps its whole body in a
    /// catch-all returning null. That variant destroys the distinction these methods restore. Call
    /// the plain variant and use EnsureSuccess.
    /// </para>
    /// </remarks>
    public static class ApiResponseExtensions
    {
        /// <summary>
        /// Returns the body of a successful response, or throws.
        /// </summary>
        /// <typeparam name="T">The resource the operation returns.</typeparam>
        /// <param name="response">The response to classify.</param>
        /// <returns>The deserialized body, never null.</returns>
        /// <exception cref="ArgumentNullException"><paramref name="response"/> is null.</exception>
        /// <exception cref="Whisparr3ApiException">
        /// The status was not a success, or it was a success whose body could not be read. Read
        /// Whisparr3ApiException.IsSuccessStatusCode to tell those two apart.
        /// </exception>
        /// <remarks>
        /// This overload covers the response interfaces that carry a typed success accessor. The
        /// ones that do not are covered by the non-generic overload below.
        /// </remarks>
        public static T EnsureSuccess<T>(this IOk<T?> response)
            where T : class
        {
            ArgumentNullException.ThrowIfNull(response);

            if (!response.IsSuccessStatusCode)
            {
                throw new Whisparr3ApiException(response, "The request failed.");
            }

            T? body;

            try
            {
                body = response.Ok();
            }
            catch (JsonException e)
            {
                // Without this the accessor's own JsonException escapes the typed layer, so a
                // consumer catching Whisparr3ApiException misses it and gets a serializer error
                // carrying no status, no route template and no URI.
                throw new Whisparr3ApiException(
                    response,
                    "The request succeeded but its body could not be deserialized.",
                    e);
            }
            catch (NotSupportedException e)
            {
                throw new Whisparr3ApiException(
                    response,
                    "The request succeeded but its body could not be deserialized.",
                    e);
            }

            if (body is null)
            {
                // A success with nothing to return. This is not a failure and the exception says
                // so through its IsSuccessStatusCode, which is true here and false above.
                throw new Whisparr3ApiException(response, "The request succeeded but no body could be read.");
            }

            return body;
        }

        /// <summary>
        /// Throws when a response failed, and returns normally when it succeeded.
        /// </summary>
        /// <param name="response">The response to classify.</param>
        /// <exception cref="ArgumentNullException"><paramref name="response"/> is null.</exception>
        /// <exception cref="Whisparr3ApiException">The status was not a success.</exception>
        /// <remarks>
        /// This overload covers the response interfaces that carry no typed success accessor, which
        /// is where the spec documents no response content. There is no body to return, so a
        /// success is simply a normal return.
        /// </remarks>
        public static void EnsureSuccess(this IApiResponse response)
        {
            ArgumentNullException.ThrowIfNull(response);

            if (!response.IsSuccessStatusCode)
            {
                throw new Whisparr3ApiException(response, "The request failed.");
            }
        }
    }
}

namespace Whisparr3.Net.Api
{
    /// <summary>
    /// The second part of the generated performer api, holding the two hooks that make its
    /// documented non-200 successes readable.
    /// </summary>
    /// <remarks>
    /// <para>
    /// This part must stay under src/hand-written/ even though its namespace belongs to the
    /// generated tree. Nothing under src/Whisparr3.Net/ is ever hand-edited, because the generator
    /// deletes its output subdirectories wholesale on every run, and the repo CLAUDE.md states
    /// that rule. Writing these two methods into PerformerApi.cs would work today and vanish on
    /// the next regeneration, silently, with the tests going red long after the change that caused
    /// it.
    /// </para>
    /// <para>
    /// The hook is used rather than an extension method because the serializer options field it
    /// needs is protected on the response base class, so only code inside the class can reach it.
    /// It also adds nothing to the public surface.
    /// </para>
    /// <para>
    /// It fails loudly by design. The generator emits the hook signature only for the response
    /// codes the spec documents, so if a future spec refresh changes either operation's documented
    /// codes this file stops compiling. That is the wanted behaviour. Do not add a defensive
    /// conditional to keep it compiling.
    /// </para>
    /// </remarks>
    public sealed partial class PerformerApi
    {
        /// <summary>
        /// The create operation's response, which documents 201 alongside 200.
        /// </summary>
        public partial class CreatePerformerApiResponse
        {
            /// <summary>
            /// Reads the body of a real 201, which the generated accessor cannot.
            /// </summary>
            /// <param name="suppressDefault">Set when this method produced the result itself.</param>
            /// <param name="result">Receives the created resource.</param>
            partial void OnOk(ref bool suppressDefault, ref Whisparr3.Net.Model.PerformerResource? result)
            {
                // Two guards, and both matter. The status check leaves the ordinary 200 path
                // running the generated default, which is the one path this hook must not
                // disturb. The body check is what stops an empty 201 throwing a raw serialization
                // exception out of the accessor and escaping the typed layer untyped.
                if (!IsCreated || string.IsNullOrWhiteSpace(RawContent))
                {
                    return;
                }

                suppressDefault = true;

                result = System.Text.Json.JsonSerializer.Deserialize<Whisparr3.Net.Model.PerformerResource>(
                    RawContent, _jsonSerializerOptions);
            }
        }

        /// <summary>
        /// The update operation's response, which documents 202 alongside 200.
        /// </summary>
        public partial class UpdatePerformerApiResponse
        {
            /// <summary>
            /// Reads the body of a real 202, which the generated accessor cannot.
            /// </summary>
            /// <param name="suppressDefault">Set when this method produced the result itself.</param>
            /// <param name="result">Receives the updated resource.</param>
            partial void OnOk(ref bool suppressDefault, ref Whisparr3.Net.Model.PerformerResource? result)
            {
                if (!IsAccepted || string.IsNullOrWhiteSpace(RawContent))
                {
                    return;
                }

                suppressDefault = true;

                result = System.Text.Json.JsonSerializer.Deserialize<Whisparr3.Net.Model.PerformerResource>(
                    RawContent, _jsonSerializerOptions);
            }
        }
    }
}

namespace Whisparr3.Net.Api
{
    /// <summary>
    /// The second part of the generated tag api, holding the hook that makes the live create's
    /// undocumented 201 readable.
    /// </summary>
    /// <remarks>
    /// <para>
    /// This part must stay under src/hand-written/ even though its namespace belongs to the
    /// generated tree. Nothing under src/Whisparr3.Net/ is ever hand-edited, because the generator
    /// deletes its output subdirectories wholesale on every run, and the repo CLAUDE.md states
    /// that rule. Writing this method into TagApi.cs would work today and vanish on the next
    /// regeneration, silently, with the tests going red long after the change that caused it.
    /// </para>
    /// <para>
    /// The hook is used rather than an extension method because the serializer options field it
    /// needs is protected on the response base class, so only code inside the class can reach it.
    /// It also adds nothing to the public surface.
    /// </para>
    /// <para>
    /// It fails loudly by design. The generator emits the hook signature only for the response
    /// codes the spec documents, so if a future spec refresh documents 201 for this operation the
    /// generated signature changes shape and this file stops compiling. That is the wanted
    /// behaviour. Do not add a defensive conditional to keep it compiling.
    /// </para>
    /// </remarks>
    public sealed partial class TagApi
    {
        /// <summary>
        /// The create operation's response, which documents 200 while the instance answers 201.
        /// </summary>
        public partial class CreateTagApiResponse
        {
            /// <summary>
            /// Reads the body of a real 201, which the generated accessor cannot.
            /// </summary>
            /// <param name="suppressDefault">Set when this method produced the result itself.</param>
            /// <param name="result">Receives the created resource.</param>
            partial void OnOk(ref bool suppressDefault, ref Whisparr3.Net.Model.TagResource? result)
            {
                // The status is compared directly rather than through an IsCreated member. The
                // generator emits IsCreated only for operations whose spec documents 201, this
                // operation's spec documents 200 only, and no such member exists here. That is a
                // difference from the performer hooks above, not a style choice: their guard
                // would not compile on this class.
                //
                // Two guards, and both matter. The status check leaves the ordinary 200 path
                // running the generated default, which is the one path this hook must not
                // disturb. The body check is what stops an empty 201 throwing a raw serialization
                // exception out of the accessor and escaping the typed layer untyped.
                if ((int)StatusCode != 201 || string.IsNullOrWhiteSpace(RawContent))
                {
                    return;
                }

                suppressDefault = true;

                result = System.Text.Json.JsonSerializer.Deserialize<Whisparr3.Net.Model.TagResource>(
                    RawContent, _jsonSerializerOptions);
            }
        }
    }
}
