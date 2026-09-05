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
