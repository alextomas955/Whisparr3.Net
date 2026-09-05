// Hand-written test support. See CLAUDE.md, section "Generated vs hand-written".

#nullable enable

using System.Text.Json;
using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Configurations;
using DotNet.Testcontainers.Containers;

namespace Whisparr3.Net.IntegrationTests
{
    /// <summary>
    /// Boots one pinned Whisparr container for the whole collection and publishes the values a
    /// test needs to reach it.
    /// </summary>
    /// <remarks>
    /// <para>
    /// This fixture never throws. When Docker is unreachable it records a skip reason and returns,
    /// and every test in the collection starts by skipping on that reason. The alternative fails
    /// rather than skips: an xunit 2.x collection fixture that throws during InitializeAsync
    /// reports every test in the collection as failed, and Build() is exactly where Testcontainers
    /// throws DockerUnavailableException. A green build on a machine without Docker is the whole
    /// point of the arrangement.
    /// </para>
    /// <para>
    /// The key below is not a credential. It is a constant handed to a container that this run
    /// creates and destroys, it is already committed in generator/capture_spec.py, and it
    /// authenticates against nothing else. What does need care is who can reach the container
    /// while it lives, which is why the published port is pinned to the loopback address and why
    /// the host port is read back rather than chosen.
    /// </para>
    /// </remarks>
    public sealed class WhisparrFixture : IAsyncLifetime
    {
        /// <summary>
        /// The port Whisparr listens on inside the container. The host port is never named here.
        /// </summary>
        public const ushort ContainerPort = 6969;

        /// <summary>
        /// The readiness signal, served without a key, and the same path capture_spec.py polls.
        /// A Whisparr 2 image answers 404 here for its whole lifetime, so a 200 says both that the
        /// instance is up and that it is the right major version.
        /// </summary>
        private const string SpecPath = "/docs/v3/openapi.json";

        /// <summary>
        /// The key generator/capture_spec.py already hands this image. Reusing it keeps one value
        /// in the repository rather than two, and it is the only key proven to authenticate
        /// against this digest.
        /// </summary>
        private const string ContainerApiKey = "0123456789abcdef0123456789abcdef";

        /// <summary>
        /// Set to "1" to make the probe report Docker as absent on a machine that has it. This is
        /// the inverse of an opt-in switch: the default is to run, and the variable exists only so
        /// the skip branch can be observed here. Nothing in the shipped library reads it.
        /// </summary>
        private const string ForceNoDockerVariable = "WHISPARR3NET_FORCE_NO_DOCKER";

        /// <summary>
        /// The wait budget. The pinned digest was measured ready in 20 seconds by direct polling
        /// and capture_spec.py allows 90, but Testcontainers adds an image check and a reaper
        /// start ahead of the container, and a cross-targeted run boots two containers at once.
        /// The value is set explicitly rather than left to a library default nobody measured.
        /// </summary>
        private static readonly TimeSpan ReadinessTimeout = TimeSpan.FromSeconds(120);

        private IContainer? _container;

        /// <summary>Why the collection's tests should skip, or null when the container is up.</summary>
        public string? SkipReason { get; private set; }

        /// <summary>The base URL of the container this run started, host and port read back from it.</summary>
        public string BaseUrl { get; private set; } = string.Empty;

        /// <summary>The Docker id of the container this run started.</summary>
        public string ContainerId { get; private set; } = string.Empty;

        /// <summary>The key the container was started with.</summary>
        public string ApiKey => ContainerApiKey;

        /// <summary>The version string spec/PROVENANCE.json records for the pinned digest.</summary>
        public string ExpectedVersion { get; private set; } = string.Empty;

        /// <summary>The branch string spec/PROVENANCE.json records for the pinned digest.</summary>
        public string ExpectedBranch { get; private set; } = string.Empty;

        /// <summary>
        /// Whether a container can be started at all.
        /// </summary>
        /// <remarks>
        /// The second clause is the same value Testcontainers itself guards on before it throws,
        /// so the probe and the library cannot disagree, and reading it costs no process launch.
        /// </remarks>
        public static bool DockerIsAvailable =>
            !string.Equals(
                Environment.GetEnvironmentVariable(ForceNoDockerVariable),
                "1",
                StringComparison.Ordinal)
            && TestcontainersSettings.OS.DockerEndpointAuthConfig is not null;

        /// <summary>
        /// Starts the container, or records why it could not be started.
        /// </summary>
        public async Task InitializeAsync()
        {
            if (!DockerIsAvailable)
            {
                SkipReason = "Docker is not reachable from this process, so no Whisparr container was started.";
                return;
            }

            using (JsonDocument provenance = ReadProvenance())
            {
                ExpectedVersion = RequiredString(provenance, "whisparrVersion");
                ExpectedBranch = RequiredString(provenance, "whisparrBranch");

                _container = new ContainerBuilder(RequiredString(provenance, "imageDigest"))
                    .WithEnvironment("WHISPARR__AUTH__APIKEY", ContainerApiKey)
                    .WithPortBinding(ContainerPort, true)
                    .WithCreateParameterModifier(parameters =>
                    {
                        // WithPortBinding on its own publishes on the wildcard address, which puts
                        // the key above on every interface for as long as the container lives. The
                        // null check is not defensive noise: without it the build fails CS8602
                        // under this repo's nullable setting plus warnings as errors.
                        var bindings = parameters.HostConfig?.PortBindings;
                        if (bindings is null)
                        {
                            return;
                        }

                        foreach (var published in bindings.Values)
                        {
                            foreach (var binding in published)
                            {
                                binding.HostIP = "127.0.0.1";
                            }
                        }
                    })
                    .WithWaitStrategy(Wait.ForUnixContainer()
                        .UntilHttpRequestIsSucceeded(
                            request => request.ForPort(ContainerPort).ForPath(SpecPath),
                            waitStrategy => waitStrategy.WithTimeout(ReadinessTimeout)))
                    .Build();
            }

            await _container.StartAsync().ConfigureAwait(false);

            // Read the host port back rather than assume one. This machine already runs a Whisparr
            // instance, and a port written into source is the one mistake that would reach it.
            BaseUrl = $"http://{_container.Hostname}:{_container.GetMappedPublicPort(ContainerPort)}";
            ContainerId = _container.Id;
        }

        /// <summary>
        /// Destroys the container, if one was started.
        /// </summary>
        public async Task DisposeAsync()
        {
            if (_container is not null)
            {
                await _container.DisposeAsync().ConfigureAwait(false);
            }
        }

        /// <summary>
        /// Reads the embedded copy of spec/PROVENANCE.json.
        /// </summary>
        /// <returns>The parsed document, which the caller owns and disposes.</returns>
        /// <exception cref="InvalidOperationException">The resource is missing from the assembly.</exception>
        private static JsonDocument ReadProvenance()
        {
            using Stream? stream = typeof(WhisparrFixture).Assembly
                .GetManifestResourceStream("PROVENANCE.json");

            if (stream is null)
            {
                throw new InvalidOperationException(
                    "The PROVENANCE.json resource is not embedded in this assembly. Check the "
                        + "EmbeddedResource item and its LogicalName in the project file.");
            }

            return JsonDocument.Parse(stream);
        }

        /// <summary>
        /// Reads one required string out of the provenance document.
        /// </summary>
        /// <param name="provenance">The parsed document.</param>
        /// <param name="name">The key to read.</param>
        /// <returns>The value, never null and never blank.</returns>
        /// <exception cref="InvalidOperationException">The key is absent, or its value is blank.</exception>
        private static string RequiredString(JsonDocument provenance, string name)
        {
            if (!provenance.RootElement.TryGetProperty(name, out JsonElement value))
            {
                throw new InvalidOperationException(
                    $"spec/PROVENANCE.json carries no '{name}' key. The fixture reads all three of "
                        + "its container constants from that file and duplicates none of them.");
            }

            string? text = value.GetString();

            if (string.IsNullOrWhiteSpace(text))
            {
                throw new InvalidOperationException(
                    $"spec/PROVENANCE.json has an empty '{name}' key.");
            }

            return text;
        }
    }

    /// <summary>
    /// The collection every test that needs a live Whisparr belongs to. One container serves them
    /// all, once per target framework.
    /// </summary>
    [CollectionDefinition(Name)]
    public sealed class WhisparrCollection : ICollectionFixture<WhisparrFixture>
    {
        /// <summary>
        /// The collection name, held as a constant so every Collection attribute binds to this
        /// declaration rather than to a repeated string literal.
        /// </summary>
        public const string Name = "whisparr";
    }
}
