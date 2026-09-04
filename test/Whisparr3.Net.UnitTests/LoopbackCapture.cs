// Hand-written test support. See CLAUDE.md, section "Generated vs hand-written".

#nullable enable

using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Whisparr3.Net.UnitTests
{
    /// <summary>
    /// A loopback HTTP listener that records the literal bytes of every request it receives.
    /// </summary>
    /// <remarks>
    /// A mocked HttpMessageHandler cannot stand in for this. A mock returns whatever it was
    /// configured to return and would pass identically whether the header carried the key or the
    /// key behind a bearer scheme prefix, which is the exact defect these tests exist to catch.
    /// The listener binds an ephemeral port on the loopback interface only, and the port is read
    /// back from LocalEndpoint rather than assumed.
    /// </remarks>
    internal sealed class LoopbackCapture : IDisposable
    {
        private readonly TcpListener _listener;
        private readonly int _status;
        private readonly string _body;
        private readonly ConcurrentQueue<string> _requests = new();
        private readonly SemaphoreSlim _recorded = new(0);
        private readonly TaskCompletionSource<string> _first =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        /// <summary>The ephemeral port the listener actually bound.</summary>
        public int Port { get; }

        /// <summary>The base URL a client should be pointed at to reach this listener.</summary>
        public string BaseUrl => $"http://127.0.0.1:{Port}";

        /// <summary>Completes with the text of the first request recorded.</summary>
        public Task<string> FirstRequest => _first.Task;

        /// <summary>Every request text recorded so far, one entry per connection.</summary>
        public IReadOnlyCollection<string> Requests => _requests;

        /// <summary>
        /// Starts the listener.
        /// </summary>
        /// <param name="status">The status code every canned response carries.</param>
        /// <param name="body">The body every canned response carries.</param>
        public LoopbackCapture(int status = 200, string body = "{}")
        {
            _status = status;
            _body = body;
            _listener = new TcpListener(IPAddress.Loopback, 0);
            _listener.Start();
            Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
            _ = Task.Run(AcceptLoopAsync);
        }

        /// <summary>
        /// Waits until the given number of requests have been recorded.
        /// </summary>
        /// <param name="count">How many requests to wait for.</param>
        /// <param name="timeout">How long to wait in total.</param>
        /// <returns>The recorded request texts.</returns>
        /// <exception cref="TimeoutException">Fewer than <paramref name="count"/> requests arrived in time.</exception>
        public async Task<IReadOnlyList<string>> WaitForRequestsAsync(int count, TimeSpan timeout)
        {
            using CancellationTokenSource cancellation = new(timeout);

            for (int i = 0; i < count; i++)
            {
                try
                {
                    await _recorded.WaitAsync(cancellation.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                {
                    throw new TimeoutException(
                        $"Only {_requests.Count} of {count} requests were recorded within {timeout}.");
                }
            }

            return _requests.ToArray();
        }

        private async Task AcceptLoopAsync()
        {
            while (true)
            {
                TcpClient client;

                try
                {
                    client = await _listener.AcceptTcpClientAsync().ConfigureAwait(false);
                }
                catch (Exception)
                {
                    return;
                }

                _ = Task.Run(() => ServeAsync(client));
            }
        }

        private async Task ServeAsync(TcpClient client)
        {
            using (client)
            using (NetworkStream stream = client.GetStream())
            {
                byte[] buffer = new byte[8192];
                StringBuilder text = new();
                int read;

                // Read the request head only. Assertions run over these raw ASCII bytes rather
                // than over a parsed header object, so no transformation between the client and
                // the socket can hide behind the assertion.
                while ((read = await stream.ReadAsync(buffer.AsMemory()).ConfigureAwait(false)) > 0)
                {
                    text.Append(Encoding.ASCII.GetString(buffer, 0, read));

                    if (text.ToString().Contains("\r\n\r\n", StringComparison.Ordinal))
                    {
                        break;
                    }
                }

                string request = text.ToString();
                _requests.Enqueue(request);
                _first.TrySetResult(request);
                _recorded.Release();

                byte[] payload = Encoding.UTF8.GetBytes(_body);
                string head = $"HTTP/1.1 {_status} X\r\n"
                    + "Content-Type: application/json\r\n"
                    + $"Content-Length: {payload.Length}\r\n"
                    + "Connection: close\r\n\r\n";

                await stream.WriteAsync(Encoding.ASCII.GetBytes(head).AsMemory()).ConfigureAwait(false);
                await stream.WriteAsync(payload.AsMemory()).ConfigureAwait(false);
                await stream.FlushAsync().ConfigureAwait(false);
            }
        }

        /// <summary>Stops the listener.</summary>
        public void Dispose()
        {
            _listener.Stop();
            _recorded.Dispose();
        }
    }

    /// <summary>
    /// Reads parts out of a captured request text. Every test uses these rather than its own
    /// parsing, so a negative control exercises the same assertion path as the test it guards.
    /// </summary>
    internal static class CapturedRequest
    {
        /// <summary>
        /// Returns every header line whose name matches, verbatim and with no trailing newline.
        /// </summary>
        /// <param name="captured">The captured request text.</param>
        /// <param name="headerName">The header name to match, compared without case.</param>
        /// <returns>The matching lines.</returns>
        public static IReadOnlyList<string> HeaderLines(string captured, string headerName)
        {
            string prefix = headerName + ":";

            return captured
                .Split("\r\n")
                .Skip(1)
                .TakeWhile(line => line.Length > 0)
                .Where(line => line.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                .ToArray();
        }

        /// <summary>
        /// Returns every request line in the captured text.
        /// </summary>
        /// <param name="captured">The captured request text.</param>
        /// <returns>The matching lines. More than one means bytes from two connections were mixed.</returns>
        public static IReadOnlyList<string> RequestLines(string captured)
        {
            return captured
                .Split("\r\n")
                .Where(line => line.EndsWith(" HTTP/1.1", StringComparison.Ordinal))
                .ToArray();
        }
    }
}
