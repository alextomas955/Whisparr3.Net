# What this library returns, and what it does not

The Whisparr 3 API declares 273 operations. One of them is a malformed root path, removed during
spec pre-processing, and this library generates all 272 that remain. Not all of them are equally
useful, and a large minority return no value at all.

A reader who calls a generated method, gets nothing back, and finds no explanation has to guess
whether that is a defect in this library or a property of the API it was generated from. It is the
second, and this document is the evidence.

This file is generated. `generator/render_docs.py` writes it from the committed spec and the
prose template beside that script, so every count and every table row here is derived rather than
typed. Edit `generator/templates/SURFACE.md.in` and re-run the renderer; an edit made here is
overwritten. Continuous integration re-renders and diffs, so a document that drifts from the spec
fails the build.

The counts below describe the spec this library was last generated from. They move when Whisparr
adds or removes operations, and that is expected rather than a defect.

## Operations that return nothing

92 of the 272 operations declare no response body. Their generated methods return a
response object like every other method, and that object carries no typed accessor for a body:
`IsOk` and the status, and no `Ok()` to call.

The reason is the same for all of them, and it is in the spec rather than in this library. Each
declares a 2xx response and declares no `content` for that response. With no media type and no
schema, the generator has nothing to bind a return type to. No operation lacks a 2xx response
entirely, so they all fall into that single category.

The body is not lost. Every one of these operations reads the whole response with
`ReadAsStringAsync` and stores it, so `RawContent` on the returned object carries whatever the
server sent. What the spec costs them is the typed accessor, not the data.

`ReadAs<T>()` deserializes that content with the client's own serializer options, so a caller who
knows the shape names it and gets it:

```csharp
var response = await customFormat.GetCustomFormatSchemaAsync();
var schema = response.ReadAs<List<CustomFormatResource>>();
```

A type the caller writes needs a `JsonPropertyName` on every member it expects to bind. The client
registers no naming policy and no case-insensitive matching, so a camel-cased body binds nothing to
a Pascal-cased member, and it does so without raising anything. The generated models already carry
the attributes.

Measured against the pinned image, 18 of these operations were called and every one answered with
a body. Twelve returned JSON. The rest returned plain text, iCalendar, HTML or a binary image, so
the type a caller names is not always a model: `GET /api/v3/system/routes` answers with a Graphviz
graph as `text/plain`, and `RawContent` is the whole of it.

Rebuilding response schemas into the spec is deliberately out of scope. A third of the measured
bodies are not JSON at all, so a schema would be wrong for them, and the rest would need
re-verifying against every refresh. It is a known and deferred gap, not an oversight.

The third column is the operation identifier the generated client uses for its method name. Both
tables in this document are sorted by path and then by method, so a diff on this section means the
spec changed.

| Method | Path | Operation |
| --- | --- | --- |
| GET | /api/v3/autotagging/schema | GetAutoTaggingSchema |
| DELETE | /api/v3/autotagging/{id} | DeleteAutoTagging |
| DELETE | /api/v3/blocklist/bulk | DeleteBlocklistBulk |
| DELETE | /api/v3/blocklist/{id} | DeleteBlocklist |
| PUT | /api/v3/collection | PutCollection |
| DELETE | /api/v3/collection/{id} | DeleteCollection |
| DELETE | /api/v3/command/{id} | DeleteCommand |
| GET | /api/v3/config/naming/examples | GetNamingConfigExamples |
| DELETE | /api/v3/customfilter/{id} | DeleteCustomFilter |
| DELETE | /api/v3/customformat/bulk | DeleteCustomFormatBulk |
| GET | /api/v3/customformat/schema | GetCustomFormatSchema |
| DELETE | /api/v3/customformat/{id} | DeleteCustomFormat |
| DELETE | /api/v3/delayprofile/{id} | DeleteDelayProfile |
| POST | /api/v3/downloadclient/action/{name} | CreateDownloadClientActionByName |
| DELETE | /api/v3/downloadclient/bulk | DeleteDownloadClientBulk |
| POST | /api/v3/downloadclient/test | TestDownloadClient |
| POST | /api/v3/downloadclient/testall | TestAllDownloadClient |
| DELETE | /api/v3/downloadclient/{id} | DeleteDownloadClient |
| DELETE | /api/v3/exclusions/bulk | DeleteExclusionsBulk |
| POST | /api/v3/exclusions/bulk | CreateExclusionsBulk |
| DELETE | /api/v3/exclusions/{id} | DeleteExclusions |
| GET | /api/v3/filesystem | GetFileSystem |
| GET | /api/v3/filesystem/mediafiles | GetFileSystemMediaFiles |
| GET | /api/v3/filesystem/type | GetFileSystemType |
| POST | /api/v3/history/failed/{id} | CreateHistoryFailedById |
| POST | /api/v3/importlist/action/{name} | CreateImportListActionByName |
| DELETE | /api/v3/importlist/bulk | DeleteImportListBulk |
| GET | /api/v3/importlist/movie | GetImportListMovie |
| POST | /api/v3/importlist/movie | CreateImportListMovie |
| POST | /api/v3/importlist/test | TestImportList |
| POST | /api/v3/importlist/testall | TestAllImportList |
| DELETE | /api/v3/importlist/{id} | DeleteImportList |
| POST | /api/v3/indexer/action/{name} | CreateIndexerActionByName |
| DELETE | /api/v3/indexer/bulk | DeleteIndexerBulk |
| POST | /api/v3/indexer/test | TestIndexer |
| POST | /api/v3/indexer/testall | TestAllIndexer |
| DELETE | /api/v3/indexer/{id} | DeleteIndexer |
| GET | /api/v3/log/file/update/{filename} | GetLogFileUpdateByFilename |
| GET | /api/v3/log/file/{filename} | GetLogFileByFilename |
| GET | /api/v3/lookup/movie | GetLookupMovie |
| GET | /api/v3/lookup/performer | GetLookupPerformer |
| GET | /api/v3/lookup/scene | GetLookupScene |
| GET | /api/v3/lookup/studio | GetLookupStudio |
| POST | /api/v3/manualimport | CreateManualImport |
| GET | /api/v3/mediacover/{movieId}/{filename} | GetMediaCoverByMovieIdAndFilename |
| POST | /api/v3/metadata/action/{name} | CreateMetadataActionByName |
| POST | /api/v3/metadata/test | TestMetadata |
| POST | /api/v3/metadata/testall | TestAllMetadata |
| DELETE | /api/v3/metadata/{id} | DeleteMetadata |
| PATCH | /api/v3/movie/bulk/monitor | PatchMovieBulkMonitor |
| DELETE | /api/v3/movie/editor | DeleteMovieEditor |
| PUT | /api/v3/movie/editor | PutMovieEditor |
| DELETE | /api/v3/movie/{id} | DeleteMovie |
| PATCH | /api/v3/movie/{id} | PatchMovieById |
| GET | /api/v3/movie/{id}/folder | GetMovieFolder |
| DELETE | /api/v3/moviefile/bulk | DeleteMovieFileBulk |
| PUT | /api/v3/moviefile/bulk | PutMovieFileBulk |
| PUT | /api/v3/moviefile/editor | PutMovieFileEditor |
| DELETE | /api/v3/moviefile/{id} | DeleteMovieFile |
| POST | /api/v3/notification/action/{name} | CreateNotificationActionByName |
| POST | /api/v3/notification/test | TestNotification |
| POST | /api/v3/notification/testall | TestAllNotification |
| DELETE | /api/v3/notification/{id} | DeleteNotification |
| DELETE | /api/v3/performer/editor | DeletePerformerEditor |
| PUT | /api/v3/performer/editor | PutPerformerEditor |
| DELETE | /api/v3/performer/{id} | DeletePerformer |
| PUT | /api/v3/qualitydefinition/update | PutQualityDefinitionUpdate |
| DELETE | /api/v3/qualityprofile/{id} | DeleteQualityProfile |
| DELETE | /api/v3/queue/bulk | DeleteQueueBulk |
| POST | /api/v3/queue/grab/bulk | CreateQueueGrabBulk |
| POST | /api/v3/queue/grab/{id} | CreateQueueGrabById |
| DELETE | /api/v3/queue/{id} | DeleteQueue |
| POST | /api/v3/release | CreateRelease |
| DELETE | /api/v3/releaseprofile/{id} | DeleteReleaseProfile |
| DELETE | /api/v3/remotepathmapping/{id} | DeleteRemotePathMapping |
| DELETE | /api/v3/rootfolder/{id} | DeleteRootFolder |
| PUT | /api/v3/studio/editor | PutStudioEditor |
| DELETE | /api/v3/studio/{id} | DeleteStudio |
| POST | /api/v3/system/backup/restore/upload | CreateSystemBackupRestoreUpload |
| POST | /api/v3/system/backup/restore/{id} | CreateSystemBackupRestoreById |
| DELETE | /api/v3/system/backup/{id} | DeleteSystemBackup |
| POST | /api/v3/system/restart | CreateSystemRestart |
| GET | /api/v3/system/routes | GetSystemRoutes |
| GET | /api/v3/system/routes/duplicate | GetSystemRoutesDuplicate |
| POST | /api/v3/system/shutdown | CreateSystemShutdown |
| DELETE | /api/v3/tag/{id} | DeleteTag |
| GET | /content/{path} | GetContentByPath |
| GET | /feed/v3/calendar/whisparr.ics | GetCalendarFeed |
| GET | /login | GetLoginPage |
| POST | /login | CreateLogin |
| GET | /logout | GetLogout |
| GET | /{path} | GetStaticResourceByPath |

## Operations that serve the web interface

The operations below exist for Whisparr's own browser interface and for calendar subscribers. They
are generated because this library covers every operation in the spec. Whether any of them is
useful to you is your call; what follows is what each one does. The paths are a hand-kept list in
`generator/render_docs.py`, and the rows come from the spec.

| Method | Path | Operation |
| --- | --- | --- |
| GET | /content/{path} | GetContentByPath |
| GET | /feed/v3/calendar/whisparr.ics | GetCalendarFeed |
| GET | /login | GetLoginPage |
| POST | /login | CreateLogin |
| GET | /logout | GetLogout |
| GET | /{path} | GetStaticResourceByPath |
What each one does.

- `GetStaticResourceByPath` serves any file from Whisparr's web root by path. It answers a browser
  with HTML, JavaScript or images.
- `GetContentByPath` serves the same web assets under the `/content` prefix.
- `GetLoginPage` returns the HTML login form. Authenticating with the API key header does not go
  through it.
- `CreateLogin` submits that form and establishes a browser session cookie. This library
  authenticates every request with the API key header instead.
- `GetLogout` ends that browser session.
- `GetCalendarFeed` returns a working iCalendar document. It declares no content, so the generated
  method exposes no typed accessor for it; the feed itself arrives in `RawContent`.

## Responses that carry credentials

These operations change nothing and are safe to call. Their responses carry secrets, so a log
line, a test transcript or an exception body from one of them writes a credential somewhere this
library never had it and cannot strip it.

| Operation | What its response carries |
| --- | --- |
| `GET /api/v3/config/host` | The instance API key and the admin password, both in plaintext. `HostConfigResource` declares `apiKey`, `password`, `passwordConfirmation`, `proxyPassword` and `sslCertPassword`. |
| `GET /api/v3/config/host/{id}` | The same resource, reached by id. |
| `GET /api/v3/log` | Log records from the instance database. Log text can contain the key. |
| `GET /api/v3/log/file/{filename}` | Raw log file text, with no schema at all in the spec. |
| `GET /api/v3/log/file/update/{filename}` | The same, for the updater's log files. |

`Whisparr3ApiException.RawContent` is the verbatim response body and is deliberately not redacted,
because this library cannot know which fields of an arbitrary body are secret. Redaction, if you
want it, belongs in whatever writes your logs.

## Operations whose effect the spec does not describe

The spec constrains request shapes, not consequences. For most operations the two line up: `DELETE
/api/v3/tag/{id}` deletes a tag. These are the ones where the signature tells you least about what
happens, so they are written down.

- `POST /api/v3/command` takes a `name` declared `{"type": "string", "nullable": true}` and nothing
  more. No `enum`, no `const`, no pattern anywhere in the spec, so the generated client offers no
  type-level constraint and the value alone decides what the instance does. It selects between
  refreshing a movie's metadata and renaming every file on disk. `GET /api/v3/command` reports what
  an instance is currently running. The per-command arguments are described nowhere in the spec
  either. `CommandResource` is `additionalProperties: false` and its generated writer emits a fixed
  property list, so the generated create operation cannot put a command argument on the wire at all.
  `CommandApi.SendCommandAsync(name, payload)` is the hand-written method that can. It writes a flat
  JSON object whose payload members are siblings of `name`, which is the shape the instance binds.
- `POST /api/v3/release` pushes a release to a download client. It reaches outside the instance,
  starts a real download and writes to the file system the instance manages, so its effect outlives
  the request and deleting anything through the API does not undo it.
- `DELETE /api/v3/moviefile/{id}` and `DELETE /api/v3/moviefile/bulk` delete files from disk, not
  just database rows. The API has no undo and no recycle step. The two read like one operation and
  are two, and the bulk form does the most per request.
- `PUT /api/v3/moviefile/{id}`, `PUT /api/v3/moviefile/bulk` and `PUT /api/v3/moviefile/editor` move
  or rewrite the files they name. They are as consequential as the deletes and easier to overlook,
  because a warning about deleting movie files does not cover them.
