// Hand-written. Nothing in this directory is generator output; see CLAUDE.md, section
// "Generated vs hand-written". Do not add the generator's file-marker header to this file:
// it is a false statement here, and it switches off the analyzer coverage that .editorconfig
// gives this directory and gives nothing else in the repository.

#nullable enable

using System;
using Whisparr3.Net.Client;

namespace Whisparr3.Net
{
    /// <summary>
    /// The error a Whisparr call raises when it did not produce a body the caller can read.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Two different outcomes throw this type, and <see cref="IsSuccessStatusCode"/> is what tells
    /// them apart. A failing status, such as the 401 an unaccepted key produces, throws with the
    /// flag false. A succeeding status whose body cannot be turned into a resource throws with the
    /// flag true. Collapsing those two together is the confusion this layer exists to remove, so
    /// read the flag rather than assuming a thrown exception means the request failed.
    /// </para>
    /// <para>
    /// Every value carried here is read straight off the response. Nothing is captured at the call
    /// site and no reflection is involved.
    /// </para>
    /// </remarks>
    public sealed class Whisparr3ApiException : Exception
    {
        /// <summary>
        /// The number of response body characters the message is allowed to embed.
        /// </summary>
        /// <remarks>
        /// The body is chosen by the Whisparr instance rather than by this library, so embedding it
        /// whole would let a large or hostile response flood a consumer's log through a single
        /// exception. 512 characters is enough to identify a Whisparr error payload and short
        /// enough to sit on one log line. <see cref="RawContent"/> is never truncated; only the
        /// fragment inside <see cref="Exception.Message"/> is.
        /// </remarks>
        private const int MessageBodyCap = 512;

        /// <summary>
        /// The status code the instance answered with.
        /// </summary>
        public System.Net.HttpStatusCode StatusCode { get; }

        /// <summary>
        /// The reason phrase the instance answered with, or null when it sent none.
        /// </summary>
        public string? ReasonPhrase { get; }

        /// <summary>
        /// The route template the operation was declared with, for example "/api/v3/system/status".
        /// </summary>
        /// <value>
        /// The template, not the concrete path. A parameterised operation reports
        /// "/api/v3/performer/{id}" here whatever id was passed, which is what makes this value
        /// usable as a grouping key in a log. Use <see cref="RequestUri"/> for the concrete URI.
        /// </value>
        public string Path { get; }

        /// <summary>
        /// The concrete URI the request was sent to, or null when the response carried none.
        /// </summary>
        /// <value>
        /// The real URI, with any route parameters substituted and the host and port resolved. It
        /// carries no credential: the key travels in the X-Api-Key header and this library never
        /// puts it in a query string.
        /// </value>
        public Uri? RequestUri { get; }

        /// <summary>
        /// The response body exactly as the instance sent it, untruncated.
        /// </summary>
        /// <value>
        /// The verbatim bytes, which for some operations contain instance secrets that this
        /// library never had and cannot strip. GET /api/v3/config/host returns the instance API key
        /// and the admin password in plaintext, and the log-file operations return raw log text
        /// that can contain the key. A consumer that logs this exception verbatim after calling one
        /// of those operations writes a credential into its own logs. Log
        /// <see cref="StatusCode"/> and <see cref="Path"/> there instead.
        /// </value>
        public string RawContent { get; }

        /// <summary>
        /// Whether the status code was a success, which is what separates the two throwing outcomes.
        /// </summary>
        /// <value>
        /// False when the request failed. True when it succeeded but no body could be read, which
        /// covers a 200 whose body is JSON null and a documented non-200 success that arrived empty.
        /// </value>
        public bool IsSuccessStatusCode { get; }

        /// <summary>
        /// Builds the exception from the response that produced it.
        /// </summary>
        /// <param name="response">The response to read status, route template, URI and body from.</param>
        /// <param name="summary">One sentence saying which of the two throwing outcomes this is.</param>
        /// <param name="innerException">The deserialization failure that caused this, when there was one.</param>
        /// <exception cref="ArgumentNullException"><paramref name="response"/> is null.</exception>
        /// <remarks>
        /// One constructor, following the generated ApiException it sits beside rather than the BCL
        /// convention of a message overload and a message-plus-inner overload. Both of those would
        /// let a caller build an instance whose properties contradict its message, and there is no
        /// case in this library where an exception is raised from anything but a response. The
        /// optional inner exception is a parameter rather than a second constructor so the
        /// deserialization cause survives without widening that surface.
        /// </remarks>
        public Whisparr3ApiException(IApiResponse response, string summary, Exception? innerException = null)
            : base(BuildMessage(response, summary), innerException)
        {
            StatusCode = response.StatusCode;

            ReasonPhrase = response.ReasonPhrase;

            Path = response.Path;

            RequestUri = response.RequestUri;

            RawContent = response.RawContent;

            IsSuccessStatusCode = response.IsSuccessStatusCode;
        }

        /// <summary>
        /// Composes the message, embedding at most <see cref="MessageBodyCap"/> body characters.
        /// </summary>
        /// <param name="response">The response the message describes.</param>
        /// <param name="summary">One sentence saying which throwing outcome this is.</param>
        /// <returns>The message.</returns>
        /// <exception cref="ArgumentNullException"><paramref name="response"/> is null.</exception>
        private static string BuildMessage(IApiResponse response, string summary)
        {
            ArgumentNullException.ThrowIfNull(response);

            string reason = string.IsNullOrEmpty(response.ReasonPhrase)
                ? response.StatusCode.ToString()
                : response.ReasonPhrase;

            string body = string.IsNullOrEmpty(response.RawContent)
                ? "(no body)"
                : response.RawContent.Length > MessageBodyCap
                    ? response.RawContent.Substring(0, MessageBodyCap) + " (truncated)"
                    : response.RawContent;

            return $"Whisparr returned {(int)response.StatusCode} {reason} for {response.Path}. "
                + $"{summary} Body: {body}";
        }
    }
}
