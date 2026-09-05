# What this library returns, and what it does not

The Whisparr 3 API declares 273 operations. One of them is a malformed root path, removed during
spec pre-processing, and this library generates all 272 that remain. Not all of them are equally
useful, and a large minority return no value at all.

A reader who calls a generated method, gets nothing back, and finds no explanation has to guess
whether that is a defect in this library or a property of the API it was generated from. It is the
second, and this document is the evidence.

Nothing below is hand-counted. `scripts/assert_surface.py` re-derives every number here from
`spec/openapi.raw.json` and `spec/openapi.generated.json`, requires every sentence that states a
count to appear verbatim, and compares both tables against the spec row by row. That script runs on
every push and pull request, so a spec refresh that moves a count turns the build red instead of
leaving this document quietly wrong.

## The operations that return nothing

92 of the 272 operations return no value. The generated method for each of them is declared void or
returns only the HTTP status.

The reason is the same for all 92 and it is in the spec rather than in this library. Each of them
declares a 2xx response and declares no `content` for that response. With no media type and no
schema, the generator has nothing to bind a return type to, so it emits a method that returns
nothing. No operation lacks a 2xx response entirely, so the whole 92 falls into that single
category.

The call still happens. The request is sent, the server answers, and whatever body it sends
arrives. The generated method discards it, because the spec named no type to deserialize it into.

Rebuilding those response schemas from observed real bodies is deliberately out of scope for this
release. It is a known and deferred gap, not an oversight.

The third column is the operation identifier the generated client uses for its method name. Both
tables in this document are sorted by path and then by method, and the gate compares their rows
against the spec in that order rather than as a set, so a diff on this section means the spec
changed.

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

## The operations that are generated but not useful

Six operations across five paths are generated because this library covers every operation in the
spec, not because anyone expects a C# caller to use them. They serve Whisparr's own web interface or
a calendar subscriber. All six also appear in the table above, so all six return nothing as well.

| Method | Path | Operation |
| --- | --- | --- |
| GET | /content/{path} | GetContentByPath |
| GET | /feed/v3/calendar/whisparr.ics | GetCalendarFeed |
| GET | /login | GetLoginPage |
| POST | /login | CreateLogin |
| GET | /logout | GetLogout |
| GET | /{path} | GetStaticResourceByPath |

Six rows, and the two obvious groupings do not add up to six. `GetLoginPage` is one of the three
operations the generator places in its static-resource API, and it is also half of the browser login
and logout pair. Adding the group sizes gives seven. Counting the operations gives six, because
`GetLoginPage` sits under both headings. The table is the count that is right.

What each one is for, and why it is not useful from C#.

- `GetStaticResourceByPath` serves any file from Whisparr's web root by path. It answers a browser
  with HTML, JavaScript or images.
- `GetContentByPath` serves the same web assets under the `/content` prefix.
- `GetLoginPage` returns the HTML login form. A C# caller authenticates with an API key header and
  never sees this page.
- `CreateLogin` submits that form and establishes a browser session. This library authenticates
  every request with an API key instead, so a session cookie buys it nothing.
- `GetLogout` ends that browser session. There is no browser session to end.
- `GetCalendarFeed` returns an iCalendar document for a calendar client to subscribe to. It declares
  no content, so the generated method discards the calendar it just fetched. Point a calendar
  application at the URL rather than calling this from C#.
