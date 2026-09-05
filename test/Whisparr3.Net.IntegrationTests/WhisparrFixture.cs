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
    /// One failure path is deliberately kept out of the throwing path: an unreachable Docker
    /// daemon. When Docker is unreachable this fixture records a skip reason and returns, and every
    /// test in the collection starts by skipping on that reason. Throwing there would fail rather
    /// than skip, because an xunit 2.x collection fixture that throws during InitializeAsync
    /// reports every test in the collection as failed, and Build() is exactly where Testcontainers
    /// throws DockerUnavailableException. A green build on a machine without Docker is the whole
    /// point of that arrangement.
    /// </para>
    /// <para>
    /// Every other failure here throws, and should. There are four: a provenance key that is
    /// absent, a provenance value that is blank, a container that will not start, and a run that
    /// declared through WHISPARR3NET_REQUIRE_DOCKER that it requires a live container while none is
    /// reachable. The last one relies on the same collection-wide failure described above, on
    /// purpose rather than in spite of it.
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
        /// The log line that marks the end of the startup task sequence, and the readiness signal
        /// the spec endpoint is not.
        /// </summary>
        /// <remarks>
        /// Whisparr serves the spec while it is still seeding its database. Measured on this
        /// digest: the spec endpoint answered 200 at 13 seconds with 0 quality profiles present in
        /// one boot and 5 in another, and 7 arrived a second or four later. A suite that starts
        /// asserting at the spec signal therefore reads a half-seeded instance, which is how the
        /// profile count assertion first failed against a live container reporting 2. The default
        /// profiles are created by a handler of the application-started event, and this line is
        /// logged by a later handler of the same event, so it cannot be written before the seeding
        /// it follows has returned. Measured over three consecutive boots: at the instant this line
        /// appeared, the instance reported 7 profiles and 29 definitions every time. The thread
        /// count in the full line varies with the host, so it is not matched.
        /// </remarks>
        private const string StartupTasksMarker = "CommandExecutor: Starting";

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
        /// Set to "1" to declare that this run must produce live evidence. A run that declares it
        /// and then finds no reachable daemon fails instead of reporting a green skip.
        /// </summary>
        /// <remarks>
        /// A workflow that exists to carry the live evidence sets this. Without it the default is
        /// unchanged, and a machine with no Docker still gets a green build. The trigger is this
        /// one explicit variable and nothing ambient, because a variable that silently decides
        /// whether a run can fail is the thing this lever guards against.
        /// </remarks>
        private const string RequireDockerVariable = "WHISPARR3NET_REQUIRE_DOCKER";

        /// <summary>
        /// The wait budget, per wait strategy. Two strategies are chained and Testcontainers
        /// evaluates them in sequence, so the worst case before the start call gives up is twice
        /// this value, which is 240 seconds. The pinned digest was measured ready in 20 seconds by
        /// direct polling and capture_spec.py allows 90, but Testcontainers adds an image check and
        /// a reaper start ahead of the container, and a cross-targeted run boots two containers at
        /// once. The value is set explicitly rather than left to a library default nobody measured.
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
        /// Whether this run declared that it requires a live container.
        /// </summary>
        /// <remarks>
        /// True only when WHISPARR3NET_REQUIRE_DOCKER is exactly "1", compared ordinal. A run that
        /// declares this and finds no daemon is an error rather than a green skip, which is what a
        /// workflow carrying the live evidence needs. It adds no test, so the skip transcript of a
        /// run that does not declare it is unchanged.
        /// </remarks>
        public static bool DockerIsRequired =>
            string.Equals(
                Environment.GetEnvironmentVariable(RequireDockerVariable),
                "1",
                StringComparison.Ordinal);

        /// <summary>
        /// Starts the container, or records why it could not be started.
        /// </summary>
        /// <exception cref="InvalidOperationException">
        /// The run declared that it requires a live container and none is reachable, or the
        /// provenance document is missing a key or carries a blank value.
        /// </exception>
        public async Task InitializeAsync()
        {
            if (!DockerIsAvailable)
            {
                if (DockerIsRequired)
                {
                    // Deliberately a throw. An xunit 2.x collection fixture that throws during
                    // initialization fails every test in the collection, which is what turns an
                    // evidence-free run into an error rather than a green skip.
                    throw new InvalidOperationException(
                        $"{RequireDockerVariable} is set, so this run declared that it requires a "
                            + "live Whisparr container, and no Docker daemon is reachable from this "
                            + "process. Nothing was started and nothing was proven.");
                }

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
                    // Two signals, and both are needed. The spec endpoint says the web host is up
                    // and that this is a Whisparr 3 image, because a Whisparr 2 image answers 404
                    // there for its whole lifetime. The log line says the startup tasks that seed
                    // the database have finished, which the spec endpoint does not.
                    .WithWaitStrategy(Wait.ForUnixContainer()
                        .UntilHttpRequestIsSucceeded(
                            request => request.ForPort(ContainerPort).ForPath(SpecPath),
                            waitStrategy => waitStrategy.WithTimeout(ReadinessTimeout))
                        .UntilMessageIsLogged(
                            StartupTasksMarker,
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
