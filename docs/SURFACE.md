# What this library returns, and what it does not

The Whisparr 3 API declares 273 operations and this library generates all of them. Not all of
them are equally useful, and some return no value at all.

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

45 of the 273 operations declare no response body. Their generated methods return a
response object like every other method, and that object carries no typed accessor for a body:
`IsOk` and the status, and no `Ok()` to call.

The spec is accurate about them. They are the deletes, the five provider `test` endpoints, the two
queue grabs, the bulk monitor patch and the two authentication routes, and on success each answers
with an empty body. Measured against this release: `DELETE /api/v3/tag/{id}` answers 200 with zero
bytes and no content type at all.

Where a body does arrive it is not lost. Every operation reads the whole response with
`ReadAsStringAsync` and stores it, so `RawContent` on the returned object carries whatever the
server sent. `POST /api/v3/indexer/test` is the case to know: a failing test answers 400 with a
JSON array of validation failures, which is an error status rather than one of the 2xx responses
counted here. Measured against this release, that array names each failed validator.

The third column is the operation identifier the generated client uses for its method name. Both
tables in this document are sorted by path and then by method, so a diff on this section means the
spec changed.

| Method | Path | Operation |
| --- | --- | --- |
| DELETE | /api/v3/autotagging/{id} | deleteAutotaggingById |
| DELETE | /api/v3/blocklist/bulk | deleteBlocklistBulk |
| DELETE | /api/v3/blocklist/{id} | deleteBlocklistById |
| DELETE | /api/v3/collection/{id} | deleteCollectionById |
| DELETE | /api/v3/command/{id} | deleteCommandById |
| DELETE | /api/v3/customfilter/{id} | deleteCustomfilterById |
| DELETE | /api/v3/customformat/bulk | deleteCustomformatBulk |
| DELETE | /api/v3/customformat/{id} | deleteCustomformatById |
| DELETE | /api/v3/delayprofile/{id} | deleteDelayprofileById |
| DELETE | /api/v3/downloadclient/bulk | deleteDownloadclientBulk |
| POST | /api/v3/downloadclient/test | postDownloadclientTest |
| DELETE | /api/v3/downloadclient/{id} | deleteDownloadclientById |
| DELETE | /api/v3/exclusions/bulk | deleteExclusionsBulk |
| DELETE | /api/v3/exclusions/{id} | deleteExclusionsById |
| POST | /api/v3/history/failed/{id} | postHistoryFailedById |
| DELETE | /api/v3/importlist/bulk | deleteImportlistBulk |
| POST | /api/v3/importlist/test | postImportlistTest |
| DELETE | /api/v3/importlist/{id} | deleteImportlistById |
| DELETE | /api/v3/indexer/bulk | deleteIndexerBulk |
| POST | /api/v3/indexer/test | postIndexerTest |
| DELETE | /api/v3/indexer/{id} | deleteIndexerById |
| POST | /api/v3/metadata/test | postMetadataTest |
| DELETE | /api/v3/metadata/{id} | deleteMetadataById |
| PATCH | /api/v3/movie/bulk/monitor | patchMovieBulkMonitor |
| DELETE | /api/v3/movie/editor | deleteMovieEditor |
| DELETE | /api/v3/movie/{id} | deleteMovieById |
| DELETE | /api/v3/moviefile/bulk | deleteMoviefileBulk |
| DELETE | /api/v3/moviefile/{id} | deleteMoviefileById |
| POST | /api/v3/notification/test | postNotificationTest |
| DELETE | /api/v3/notification/{id} | deleteNotificationById |
| DELETE | /api/v3/performer/editor | deletePerformerEditor |
| DELETE | /api/v3/performer/{id} | deletePerformerById |
| DELETE | /api/v3/qualityprofile/{id} | deleteQualityprofileById |
| DELETE | /api/v3/queue/bulk | deleteQueueBulk |
| POST | /api/v3/queue/grab/bulk | postQueueGrabBulk |
| POST | /api/v3/queue/grab/{id} | postQueueGrabById |
| DELETE | /api/v3/queue/{id} | deleteQueueById |
| DELETE | /api/v3/releaseprofile/{id} | deleteReleaseprofileById |
| DELETE | /api/v3/remotepathmapping/{id} | deleteRemotepathmappingById |
| DELETE | /api/v3/rootfolder/{id} | deleteRootfolderById |
| DELETE | /api/v3/studio/{id} | deleteStudioById |
| DELETE | /api/v3/system/backup/{id} | deleteSystemBackupById |
| DELETE | /api/v3/tag/{id} | deleteTagById |
| POST | /login | postLogin |
| GET | /logout | getLogout |

## Operations that do not answer with JSON

Six operations declare a `string` body: `GET /api/v3/system/routes` and the two log file routes
answer `text/plain`, the calendar feed answers `text/calendar`, mediacover answers an image, and
localization answers a document the spec types as a string. What arrives is the text itself rather
than a JSON string literal, so the generated accessor raises on the first character.

`EnsureSuccess` has an overload for them that returns the text as it arrived:

```csharp
var response = await system.GetSystemRoutesAsync();
string graph = response.EnsureSuccess();
```

Measured against this release, that route answers 243 KB of Graphviz source. `RawContent` carries
the same string and is there for a caller who wants the body without the status check.

Every other operation binds to a generated model. That was not true before Whisparr 3.6.1, where
92 operations declared a 2xx with no content at all and a caller had to name a shape of their
own.

## Operations that serve the web interface

The operations below exist for Whisparr's own browser interface and for calendar subscribers. They
are generated because this library covers every operation in the spec. Whether any of them is
useful to you is your call; what follows is what each one does. The paths are a hand-kept list in
`generator/render_docs.py`, and the rows come from the spec.

| Method | Path | Operation |
| --- | --- | --- |
| GET | /feed/v3/calendar/whisparr.ics | getFeedV3CalendarWhisparrIcs |
| POST | /login | postLogin |
| GET | /logout | getLogout |
What each one does.

- `PostLogin` submits the browser login form and establishes a session cookie. This library
  authenticates every request with the API key header instead. It declares an empty security
  requirement, so the generated method sends no key.
- `GetLogout` ends that browser session, and likewise takes no key.
- `GetFeedV3CalendarWhisparrIcs` returns an iCalendar document as `text/calendar`.

Whisparr's static assets, its SPA shell and its login page are no longer in the spec at all. The
controller that serves them is excluded from document generation upstream, so this library
generates no method for them.

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
  either. `CommandResource` declares a fixed property list and its generated writer emits exactly
  those properties, so the generated create operation cannot put a command argument on the wire.
  `CommandApi.SendCommandAsync(name, payload)` is the hand-written method that can. It writes a flat
  JSON object whose payload members are siblings of `name`, which is the shape the instance binds.
- `POST /api/v3/release` pushes a release to a download client. It reaches outside the instance,
  starts a real download and writes to the file system the instance manages, so its effect outlives
  the request and deleting anything through the API does not undo it.
- `DELETE /api/v3/moviefile/{id}` and `DELETE /api/v3/moviefile/bulk` delete files from disk, not
  just database rows. The API has no undo and no recycle step. The two read like one operation and
  are two, and the bulk form does the most per request.
- `PUT /api/v3/moviefile/{id}` and `PUT /api/v3/moviefile/bulk` move or rewrite the files they name.
  They are as consequential as the deletes and easier to overlook, because a warning about deleting
  movie files does not cover them.
