# Operations this repository does not call

The Whisparr 3 API has 272 operations and 131 of them change state on the instance. This
document lists all 131, so that anyone adding a test can check a call against the list before
writing it.

The list is documentation. Nothing reads it at build time and nothing enforces it. What
protects the integration suite is that its container is published on a random loopback port,
so it cannot reach any Whisparr but its own, and that the suite is small enough to read in
full.

The one write the suite performs is `POST /api/v3/tag`, and the tag it creates it deletes
again in the same test.

## Never call these under any circumstances

Seven operations are worse than the rest. They are on the list below like everything else,
and they are named here with a reason each.

### `POST /api/v3/command`, `CreateCommand`

The request body's `name` property is declared `{"type": "string", "nullable": true}` and
nothing more. There is no `enum`, no `const` and no pattern for it anywhere in the spec, so the
generated client offers no type-level constraint on the value at all and the caller is the only
guard. That one string decides what the instance does. It selects between refreshing a movie's
metadata and renaming every file on disk, and both are the same call with a different word in
it.

Read `GET /api/v3/command` to see what an instance is running. Never post one.

### `POST /api/v3/release`, `CreateRelease`

This pushes a release to a download client. It reaches outside the instance, starts a real
download and writes to the file system the instance manages, so its effect outlives the request
and is not undone by deleting anything through the API.

Read `GET /api/v3/release` if you need release data.

### `DELETE /api/v3/moviefile/{id}`, `DeleteMovieFile`

Deletes a movie file from disk, not just its database row. There is no undo and no recycle
step in the API.

### `DELETE /api/v3/moviefile/bulk`, `DeleteMovieFileBulk`

The same deletion, for a list of ids in one request. `DELETE /api/v3/moviefile/*` reads like
one operation and is two, and this is the one that does the most damage per request.

### The three `moviefile` updates

`PUT /api/v3/moviefile/{id}` is `UpdateMovieFile`, `PUT /api/v3/moviefile/bulk` is
`PutMovieFileBulk` and `PUT /api/v3/moviefile/editor` is `PutMovieFileEditor`. One heading
because the reason is the same for all three.

The `moviefile` family carries three `PUT` operations beside its two `DELETE` operations, and a
movie file update moves or rewrites the file it names. They are as destructive as the deletes,
and they are the easiest of the seven to miss, because a warning worded as "do not delete movie
files" does not cover them.

Read `GET /api/v3/moviefile` and `GET /api/v3/moviefile/{id}` instead.

## Read-only, and still unsafe to record

These operations change nothing and are not on the list below. They are named here because
their responses carry credentials, and a test transcript or an exception body from one of them
writes a secret into a log that this library never had and cannot strip.

| Operation | What its response carries |
| --- | --- |
| `GET /api/v3/config/host` | The instance API key and the admin password, both in plaintext. `HostConfigResource` declares `apiKey`, `password`, `passwordConfirmation`, `proxyPassword` and `sslCertPassword`. |
| `GET /api/v3/config/host/{id}` | The same resource, reached by id. |
| `GET /api/v3/log` | Log records from the instance database. Log text can contain the key. |
| `GET /api/v3/log/file/{filename}` | Raw log file text, with no schema at all in the spec. |
| `GET /api/v3/log/file/update/{filename}` | The same, for the updater's log files. |

`Whisparr3ApiException.RawContent` is the verbatim response body and is deliberately not
truncated, so an exception from any of these is as dangerous to log as the response itself.
Log `StatusCode` and `Path` instead.

Note that `PUT /api/v3/config/host/{id}` returns the same resource and also changes it, so it
is unsafe on both counts and appears on the list below as well.

## The full list

All 131 state-mutating operations, grouped by tag and sorted within each group. The order is a
function of the spec alone, so a diff on this section means the spec changed.

The third column is the operation identifier the generated client uses for its method name.

### Authentication

| Method | Path | Operation |
| --- | --- | --- |
| POST | /login | CreateLogin |

### AutoTagging

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/autotagging | CreateAutoTagging |
| DELETE | /api/v3/autotagging/{id} | DeleteAutoTagging |
| PUT | /api/v3/autotagging/{id} | UpdateAutoTagging |

### Backup

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/system/backup/restore/upload | CreateSystemBackupRestoreUpload |
| POST | /api/v3/system/backup/restore/{id} | CreateSystemBackupRestoreById |
| DELETE | /api/v3/system/backup/{id} | DeleteSystemBackup |

### Blocklist

| Method | Path | Operation |
| --- | --- | --- |
| DELETE | /api/v3/blocklist/bulk | DeleteBlocklistBulk |
| DELETE | /api/v3/blocklist/{id} | DeleteBlocklist |

### Collection

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/collection | PutCollection |
| DELETE | /api/v3/collection/{id} | DeleteCollection |
| PUT | /api/v3/collection/{id} | UpdateCollection |

### Command

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/command | CreateCommand |
| DELETE | /api/v3/command/{id} | DeleteCommand |

### CustomFilter

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/customfilter | CreateCustomFilter |
| DELETE | /api/v3/customfilter/{id} | DeleteCustomFilter |
| PUT | /api/v3/customfilter/{id} | UpdateCustomFilter |

### CustomFormat

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/customformat | CreateCustomFormat |
| DELETE | /api/v3/customformat/bulk | DeleteCustomFormatBulk |
| PUT | /api/v3/customformat/bulk | PutCustomFormatBulk |
| DELETE | /api/v3/customformat/{id} | DeleteCustomFormat |
| PUT | /api/v3/customformat/{id} | UpdateCustomFormat |

### DelayProfile

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/delayprofile | CreateDelayProfile |
| PUT | /api/v3/delayprofile/reorder/{id} | UpdateDelayProfileReorder |
| DELETE | /api/v3/delayprofile/{id} | DeleteDelayProfile |
| PUT | /api/v3/delayprofile/{id} | UpdateDelayProfile |

### DownloadClient

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/downloadclient | CreateDownloadClient |
| POST | /api/v3/downloadclient/action/{name} | CreateDownloadClientActionByName |
| DELETE | /api/v3/downloadclient/bulk | DeleteDownloadClientBulk |
| PUT | /api/v3/downloadclient/bulk | PutDownloadClientBulk |
| POST | /api/v3/downloadclient/test | TestDownloadClient |
| POST | /api/v3/downloadclient/testall | TestAllDownloadClient |
| DELETE | /api/v3/downloadclient/{id} | DeleteDownloadClient |
| PUT | /api/v3/downloadclient/{id} | UpdateDownloadClient |

### DownloadClientConfig

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/config/downloadclient/{id} | UpdateDownloadClientConfig |

### History

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/history/failed/{id} | CreateHistoryFailedById |

### HostConfig

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/config/host/{id} | UpdateHostConfig |

### ImportList

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/importlist | CreateImportList |
| POST | /api/v3/importlist/action/{name} | CreateImportListActionByName |
| DELETE | /api/v3/importlist/bulk | DeleteImportListBulk |
| PUT | /api/v3/importlist/bulk | PutImportListBulk |
| POST | /api/v3/importlist/test | TestImportList |
| POST | /api/v3/importlist/testall | TestAllImportList |
| DELETE | /api/v3/importlist/{id} | DeleteImportList |
| PUT | /api/v3/importlist/{id} | UpdateImportList |

### ImportListConfig

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/config/importlist/{id} | UpdateImportListConfig |

### ImportListExclusion

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/exclusions | CreateExclusions |
| DELETE | /api/v3/exclusions/bulk | DeleteExclusionsBulk |
| POST | /api/v3/exclusions/bulk | CreateExclusionsBulk |
| DELETE | /api/v3/exclusions/{id} | DeleteExclusions |
| PUT | /api/v3/exclusions/{id} | UpdateExclusions |

### ImportListMovies

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/importlist/movie | CreateImportListMovie |

### Indexer

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/indexer | CreateIndexer |
| POST | /api/v3/indexer/action/{name} | CreateIndexerActionByName |
| DELETE | /api/v3/indexer/bulk | DeleteIndexerBulk |
| PUT | /api/v3/indexer/bulk | PutIndexerBulk |
| POST | /api/v3/indexer/test | TestIndexer |
| POST | /api/v3/indexer/testall | TestAllIndexer |
| DELETE | /api/v3/indexer/{id} | DeleteIndexer |
| PUT | /api/v3/indexer/{id} | UpdateIndexer |

### IndexerConfig

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/config/indexer/{id} | UpdateIndexerConfig |

### ManualImport

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/manualimport | CreateManualImport |

### MediaManagementConfig

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/config/mediamanagement/{id} | UpdateMediaManagementConfig |

### Metadata

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/metadata | CreateMetadata |
| POST | /api/v3/metadata/action/{name} | CreateMetadataActionByName |
| POST | /api/v3/metadata/test | TestMetadata |
| POST | /api/v3/metadata/testall | TestAllMetadata |
| DELETE | /api/v3/metadata/{id} | DeleteMetadata |
| PUT | /api/v3/metadata/{id} | UpdateMetadata |

### Movie

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/movie | CreateMovie |
| POST | /api/v3/movie/bulk | CreateMovieBulk |
| PATCH | /api/v3/movie/bulk/monitor | PatchMovieBulkMonitor |
| POST | /api/v3/movie/list | CreateMovieList |
| POST | /api/v3/movie/paged | CreateMoviePaged |
| DELETE | /api/v3/movie/{id} | DeleteMovie |
| PATCH | /api/v3/movie/{id} | PatchMovieById |
| PUT | /api/v3/movie/{id} | UpdateMovie |

### MovieEditor

| Method | Path | Operation |
| --- | --- | --- |
| DELETE | /api/v3/movie/editor | DeleteMovieEditor |
| PUT | /api/v3/movie/editor | PutMovieEditor |

### MovieFile

| Method | Path | Operation |
| --- | --- | --- |
| DELETE | /api/v3/moviefile/bulk | DeleteMovieFileBulk |
| PUT | /api/v3/moviefile/bulk | PutMovieFileBulk |
| PUT | /api/v3/moviefile/editor | PutMovieFileEditor |
| DELETE | /api/v3/moviefile/{id} | DeleteMovieFile |
| PUT | /api/v3/moviefile/{id} | UpdateMovieFile |

### MovieImport

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/movie/import | CreateMovieImport |

### NamingConfig

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/config/naming/{id} | UpdateNamingConfig |

### Notification

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/notification | CreateNotification |
| POST | /api/v3/notification/action/{name} | CreateNotificationActionByName |
| POST | /api/v3/notification/test | TestNotification |
| POST | /api/v3/notification/testall | TestAllNotification |
| DELETE | /api/v3/notification/{id} | DeleteNotification |
| PUT | /api/v3/notification/{id} | UpdateNotification |

### Performer

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/performer | CreatePerformer |
| POST | /api/v3/performer/list | CreatePerformerList |
| POST | /api/v3/performer/paged | CreatePerformerPaged |
| DELETE | /api/v3/performer/{id} | DeletePerformer |
| PUT | /api/v3/performer/{id} | UpdatePerformer |

### PerformerEditor

| Method | Path | Operation |
| --- | --- | --- |
| DELETE | /api/v3/performer/editor | DeletePerformerEditor |
| PUT | /api/v3/performer/editor | PutPerformerEditor |

### QualityDefinition

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/qualitydefinition/update | PutQualityDefinitionUpdate |
| PUT | /api/v3/qualitydefinition/{id} | UpdateQualityDefinition |

### QualityProfile

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/qualityprofile | CreateQualityProfile |
| DELETE | /api/v3/qualityprofile/{id} | DeleteQualityProfile |
| PUT | /api/v3/qualityprofile/{id} | UpdateQualityProfile |

### Queue

| Method | Path | Operation |
| --- | --- | --- |
| DELETE | /api/v3/queue/bulk | DeleteQueueBulk |
| DELETE | /api/v3/queue/{id} | DeleteQueue |

### QueueAction

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/queue/grab/bulk | CreateQueueGrabBulk |
| POST | /api/v3/queue/grab/{id} | CreateQueueGrabById |

### Release

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/release | CreateRelease |

### ReleaseProfile

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/releaseprofile | CreateReleaseProfile |
| DELETE | /api/v3/releaseprofile/{id} | DeleteReleaseProfile |
| PUT | /api/v3/releaseprofile/{id} | UpdateReleaseProfile |

### ReleasePush

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/release/push | CreateReleasePush |

### RemotePathMapping

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/remotepathmapping | CreateRemotePathMapping |
| DELETE | /api/v3/remotepathmapping/{id} | DeleteRemotePathMapping |
| PUT | /api/v3/remotepathmapping/{id} | UpdateRemotePathMapping |

### RootFolder

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/rootfolder | CreateRootFolder |
| POST | /api/v3/rootfolder/refresh/{id} | CreateRootFolderRefreshById |
| DELETE | /api/v3/rootfolder/{id} | DeleteRootFolder |

### Studio

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/studio | CreateStudio |
| POST | /api/v3/studio/list | CreateStudioList |
| POST | /api/v3/studio/paged | CreateStudioPaged |
| DELETE | /api/v3/studio/{id} | DeleteStudio |
| PUT | /api/v3/studio/{id} | UpdateStudio |

### StudioEditor

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/studio/editor | PutStudioEditor |

### System

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/system/restart | CreateSystemRestart |
| POST | /api/v3/system/shutdown | CreateSystemShutdown |

### Tag

| Method | Path | Operation |
| --- | --- | --- |
| POST | /api/v3/tag | CreateTag |
| DELETE | /api/v3/tag/{id} | DeleteTag |
| PUT | /api/v3/tag/{id} | UpdateTag |

### UiConfig

| Method | Path | Operation |
| --- | --- | --- |
| PUT | /api/v3/config/ui/{id} | UpdateUiConfig |

## How the count was derived

Measured over `spec/openapi.generated.json`, the committed spec, counting the HTTP methods
declared under every path.

| Method | Operations |
| --- | --- |
| `GET` | 140 |
| `POST` | 56 |
| `PUT` | 39 |
| `DELETE` | 34 |
| `PATCH` | 2 |
| `HEAD` | 1 |
| Total | 272 |

State-mutating is POST plus PUT plus DELETE plus PATCH, which is 131. The read-only surface
is 141, not 140, because HEAD is read-only and is not a GET.

Counting "non-GET" gives 132 and is wrong. It puts the one HEAD operation on the
dangerous list. The two totals are 131 and 141, and they add up to 272.

## What is not enforced

Nothing structurally prevents a contributor adding a call to one of these operations. There is
no allowlist type, no source analyzer over the test project and no run-time check of this list.

The mitigations are what the opening paragraph says they are: the container is published on a
random loopback port, this list is committed, and the suite is small enough that reading it is
the verification. Those are real and they are not the same as enforcement.

If standing enforcement is ever wanted, the honest form is a source analyzer over the test
project that fails the build on a call to a named operation. A run-time harness is the wrong
shape: it can only refuse a call the suite already made, which is after the instance has
already been asked to make the change.
