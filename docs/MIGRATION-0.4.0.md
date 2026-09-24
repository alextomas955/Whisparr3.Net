# Migrating to 0.4.0

Whisparr assigns an `operationId` to every operation as of 3.6.1, and this library takes its
method names from those identifiers. It used to derive them from the URL instead. That renames
212 of the 266 operations carried over from 0.3.0; the other 54 keep their names.

Each row below is one method. Append `Async` for the method itself, and `OrDefaultAsync` for the
variant beside it. The response interface renames with it, so `ICreateTagApiResponse` is now
`IPostTagApiResponse`, and so does the response class.

This file describes one release and does not change. See [CHANGELOG.md](../CHANGELOG.md) for the
rest of what 0.4.0 carries.

## Renamed

### AlternativeTitle

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/alttitle` | `ListAlternativeTitle` | `GetAlttitle` |
| `GET /api/v3/alttitle/{id}` | `GetAlternativeTitleById` | `GetAlttitleById` |

### ApiInfo

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api` | `GetApiInfo` | `GetApi` |

### Authentication

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `POST /login` | `CreateLogin` | `PostLogin` |

### AutoTagging

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/autotagging/{id}` | `DeleteAutoTagging` | `DeleteAutotaggingById` |
| `GET /api/v3/autotagging` | `ListAutoTagging` | `GetAutotagging` |
| `GET /api/v3/autotagging/schema` | `GetAutoTaggingSchema` | `GetAutotaggingSchema` |
| `GET /api/v3/autotagging/{id}` | `GetAutoTaggingById` | `GetAutotaggingById` |
| `POST /api/v3/autotagging` | `CreateAutoTagging` | `PostAutotagging` |
| `PUT /api/v3/autotagging/{id}` | `UpdateAutoTagging` | `PutAutotaggingById` |

### Backup

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/system/backup/{id}` | `DeleteSystemBackup` | `DeleteSystemBackupById` |
| `GET /api/v3/system/backup` | `ListSystemBackup` | `GetSystemBackup` |
| `POST /api/v3/system/backup/restore/upload` | `CreateSystemBackupRestoreUpload` | `PostSystemBackupRestoreUpload` |
| `POST /api/v3/system/backup/restore/{id}` | `CreateSystemBackupRestoreById` | `PostSystemBackupRestoreById` |

### Blocklist

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/blocklist/{id}` | `DeleteBlocklist` | `DeleteBlocklistById` |
| `GET /api/v3/blocklist/movie` | `ListBlocklistMovie` | `GetBlocklistMovie` |

### Calendar

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/calendar` | `ListCalendar` | `GetCalendar` |

### CalendarFeed

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /feed/v3/calendar/whisparr.ics` | `GetCalendarFeed` | `GetFeedV3CalendarWhisparrIcs` |

### Collection

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/collection/{id}` | `DeleteCollection` | `DeleteCollectionById` |
| `GET /api/v3/collection` | `ListCollection` | `GetCollection` |
| `PUT /api/v3/collection/{id}` | `UpdateCollection` | `PutCollectionById` |

### Command

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/command/{id}` | `DeleteCommand` | `DeleteCommandById` |
| `GET /api/v3/command` | `ListCommand` | `GetCommand` |
| `POST /api/v3/command` | `CreateCommand` | `PostCommand` |

### Credit

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/credit` | `ListCredit` | `GetCredit` |

### CustomFilter

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/customfilter/{id}` | `DeleteCustomFilter` | `DeleteCustomfilterById` |
| `GET /api/v3/customfilter` | `ListCustomFilter` | `GetCustomfilter` |
| `GET /api/v3/customfilter/{id}` | `GetCustomFilterById` | `GetCustomfilterById` |
| `POST /api/v3/customfilter` | `CreateCustomFilter` | `PostCustomfilter` |
| `PUT /api/v3/customfilter/{id}` | `UpdateCustomFilter` | `PutCustomfilterById` |

### CustomFormat

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/customformat/bulk` | `DeleteCustomFormatBulk` | `DeleteCustomformatBulk` |
| `DELETE /api/v3/customformat/{id}` | `DeleteCustomFormat` | `DeleteCustomformatById` |
| `GET /api/v3/customformat` | `ListCustomFormat` | `GetCustomformat` |
| `GET /api/v3/customformat/schema` | `GetCustomFormatSchema` | `GetCustomformatSchema` |
| `GET /api/v3/customformat/{id}` | `GetCustomFormatById` | `GetCustomformatById` |
| `POST /api/v3/customformat` | `CreateCustomFormat` | `PostCustomformat` |
| `PUT /api/v3/customformat/bulk` | `PutCustomFormatBulk` | `PutCustomformatBulk` |
| `PUT /api/v3/customformat/{id}` | `UpdateCustomFormat` | `PutCustomformatById` |

### DelayProfile

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/delayprofile/{id}` | `DeleteDelayProfile` | `DeleteDelayprofileById` |
| `GET /api/v3/delayprofile` | `ListDelayProfile` | `GetDelayprofile` |
| `GET /api/v3/delayprofile/{id}` | `GetDelayProfileById` | `GetDelayprofileById` |
| `POST /api/v3/delayprofile` | `CreateDelayProfile` | `PostDelayprofile` |
| `PUT /api/v3/delayprofile/reorder/{id}` | `UpdateDelayProfileReorder` | `PutDelayprofileReorderById` |
| `PUT /api/v3/delayprofile/{id}` | `UpdateDelayProfile` | `PutDelayprofileById` |

### DiskSpace

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/diskspace` | `ListDiskSpace` | `GetDiskspace` |

### DownloadClient

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/downloadclient/bulk` | `DeleteDownloadClientBulk` | `DeleteDownloadclientBulk` |
| `DELETE /api/v3/downloadclient/{id}` | `DeleteDownloadClient` | `DeleteDownloadclientById` |
| `GET /api/v3/downloadclient` | `ListDownloadClient` | `GetDownloadclient` |
| `GET /api/v3/downloadclient/schema` | `ListDownloadClientSchema` | `GetDownloadclientSchema` |
| `GET /api/v3/downloadclient/{id}` | `GetDownloadClientById` | `GetDownloadclientById` |
| `POST /api/v3/downloadclient` | `CreateDownloadClient` | `PostDownloadclient` |
| `POST /api/v3/downloadclient/action/{name}` | `CreateDownloadClientActionByName` | `PostDownloadclientActionByName` |
| `POST /api/v3/downloadclient/test` | `TestDownloadClient` | `PostDownloadclientTest` |
| `POST /api/v3/downloadclient/testall` | `TestAllDownloadClient` | `PostDownloadclientTestall` |
| `PUT /api/v3/downloadclient/bulk` | `PutDownloadClientBulk` | `PutDownloadclientBulk` |
| `PUT /api/v3/downloadclient/{id}` | `UpdateDownloadClient` | `PutDownloadclientById` |

### DownloadClientConfig

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/config/downloadclient` | `GetDownloadClientConfig` | `GetConfigDownloadclient` |
| `GET /api/v3/config/downloadclient/{id}` | `GetDownloadClientConfigById` | `GetConfigDownloadclientById` |
| `PUT /api/v3/config/downloadclient/{id}` | `UpdateDownloadClientConfig` | `PutConfigDownloadclientById` |

### ExtraFile

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/extrafile` | `ListExtraFile` | `GetExtrafile` |

### FileSystem

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/filesystem` | `GetFileSystem` | `GetFilesystem` |
| `GET /api/v3/filesystem/mediafiles` | `GetFileSystemMediaFiles` | `GetFilesystemMediafiles` |
| `GET /api/v3/filesystem/type` | `GetFileSystemType` | `GetFilesystemType` |

### Health

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/health` | `ListHealth` | `GetHealth` |

### History

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/history/movie` | `ListHistoryMovie` | `GetHistoryMovie` |
| `GET /api/v3/history/since` | `ListHistorySince` | `GetHistorySince` |
| `POST /api/v3/history/failed/{id}` | `CreateHistoryFailedById` | `PostHistoryFailedById` |

### HostConfig

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/config/host` | `GetHostConfig` | `GetConfigHost` |
| `GET /api/v3/config/host/{id}` | `GetHostConfigById` | `GetConfigHostById` |
| `PUT /api/v3/config/host/{id}` | `UpdateHostConfig` | `PutConfigHostById` |

### ImportList

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/importlist/bulk` | `DeleteImportListBulk` | `DeleteImportlistBulk` |
| `DELETE /api/v3/importlist/{id}` | `DeleteImportList` | `DeleteImportlistById` |
| `GET /api/v3/importlist` | `ListImportList` | `GetImportlist` |
| `GET /api/v3/importlist/schema` | `ListImportListSchema` | `GetImportlistSchema` |
| `GET /api/v3/importlist/{id}` | `GetImportListById` | `GetImportlistById` |
| `POST /api/v3/importlist` | `CreateImportList` | `PostImportlist` |
| `POST /api/v3/importlist/action/{name}` | `CreateImportListActionByName` | `PostImportlistActionByName` |
| `POST /api/v3/importlist/test` | `TestImportList` | `PostImportlistTest` |
| `POST /api/v3/importlist/testall` | `TestAllImportList` | `PostImportlistTestall` |
| `PUT /api/v3/importlist/bulk` | `PutImportListBulk` | `PutImportlistBulk` |
| `PUT /api/v3/importlist/{id}` | `UpdateImportList` | `PutImportlistById` |

### ImportListConfig

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/config/importlist` | `GetImportListConfig` | `GetConfigImportlist` |
| `GET /api/v3/config/importlist/{id}` | `GetImportListConfigById` | `GetConfigImportlistById` |
| `PUT /api/v3/config/importlist/{id}` | `UpdateImportListConfig` | `PutConfigImportlistById` |

### ImportListExclusion

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/exclusions/{id}` | `DeleteExclusions` | `DeleteExclusionsById` |
| `GET /api/v3/exclusions` | `ListExclusions` | `GetExclusions` |
| `POST /api/v3/exclusions` | `CreateExclusions` | `PostExclusions` |
| `POST /api/v3/exclusions/bulk` | `CreateExclusionsBulk` | `PostExclusionsBulk` |
| `PUT /api/v3/exclusions/{id}` | `UpdateExclusions` | `PutExclusionsById` |

### ImportListMovies

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/importlist/movie` | `GetImportListMovie` | `GetImportlistMovie` |
| `POST /api/v3/importlist/movie` | `CreateImportListMovie` | `PostImportlistMovie` |

### Indexer

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/indexer/{id}` | `DeleteIndexer` | `DeleteIndexerById` |
| `GET /api/v3/indexer` | `ListIndexer` | `GetIndexer` |
| `GET /api/v3/indexer/schema` | `ListIndexerSchema` | `GetIndexerSchema` |
| `POST /api/v3/indexer` | `CreateIndexer` | `PostIndexer` |
| `POST /api/v3/indexer/action/{name}` | `CreateIndexerActionByName` | `PostIndexerActionByName` |
| `POST /api/v3/indexer/test` | `TestIndexer` | `PostIndexerTest` |
| `POST /api/v3/indexer/testall` | `TestAllIndexer` | `PostIndexerTestall` |
| `PUT /api/v3/indexer/{id}` | `UpdateIndexer` | `PutIndexerById` |

### IndexerConfig

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/config/indexer` | `GetIndexerConfig` | `GetConfigIndexer` |
| `GET /api/v3/config/indexer/{id}` | `GetIndexerConfigById` | `GetConfigIndexerById` |
| `PUT /api/v3/config/indexer/{id}` | `UpdateIndexerConfig` | `PutConfigIndexerById` |

### IndexerFlag

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/indexerflag` | `ListIndexerFlag` | `GetIndexerflag` |

### Language

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/language` | `ListLanguage` | `GetLanguage` |

### LogFile

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/log/file` | `ListLogFile` | `GetLogFile` |

### ManualImport

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/manualimport` | `ListManualImport` | `GetManualimport` |
| `POST /api/v3/manualimport` | `CreateManualImport` | `PostManualimport` |

### MediaCover

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/mediacover/{movieId}/{filename}` | `GetMediaCoverByMovieIdAndFilename` | `GetMediacoverByMovieIdByFilename` |

### MediaManagementConfig

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/config/mediamanagement` | `GetMediaManagementConfig` | `GetConfigMediamanagement` |
| `GET /api/v3/config/mediamanagement/{id}` | `GetMediaManagementConfigById` | `GetConfigMediamanagementById` |
| `PUT /api/v3/config/mediamanagement/{id}` | `UpdateMediaManagementConfig` | `PutConfigMediamanagementById` |

### Metadata

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/metadata/{id}` | `DeleteMetadata` | `DeleteMetadataById` |
| `GET /api/v3/metadata` | `ListMetadata` | `GetMetadata` |
| `GET /api/v3/metadata/schema` | `ListMetadataSchema` | `GetMetadataSchema` |
| `POST /api/v3/metadata` | `CreateMetadata` | `PostMetadata` |
| `POST /api/v3/metadata/action/{name}` | `CreateMetadataActionByName` | `PostMetadataActionByName` |
| `POST /api/v3/metadata/test` | `TestMetadata` | `PostMetadataTest` |
| `POST /api/v3/metadata/testall` | `TestAllMetadata` | `PostMetadataTestall` |
| `PUT /api/v3/metadata/{id}` | `UpdateMetadata` | `PutMetadataById` |

### Movie

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/movie/{id}` | `DeleteMovie` | `DeleteMovieById` |
| `GET /api/v3/movie` | `ListMovie` | `GetMovie` |
| `GET /api/v3/movie/list` | `ListMovieList` | `GetMovieList` |
| `GET /api/v3/movie/listbyperformerforeignid` | `ListMovieByPerformerForeignId` | `GetMovieListbyperformerforeignid` |
| `GET /api/v3/movie/listbystudioforeignid` | `ListMovieByStudioForeignId` | `GetMovieListbystudioforeignid` |
| `GET /api/v3/movie/search` | `ListMovieSearch` | `GetMovieSearch` |
| `POST /api/v3/movie` | `CreateMovie` | `PostMovie` |
| `POST /api/v3/movie/bulk` | `CreateMovieBulk` | `PostMovieBulk` |
| `POST /api/v3/movie/list` | `CreateMovieList` | `PostMovieList` |
| `POST /api/v3/movie/paged` | `CreateMoviePaged` | `PostMoviePaged` |
| `PUT /api/v3/movie/{id}` | `UpdateMovie` | `PutMovieById` |

### MovieFile

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/moviefile/bulk` | `DeleteMovieFileBulk` | `DeleteMoviefileBulk` |
| `DELETE /api/v3/moviefile/{id}` | `DeleteMovieFile` | `DeleteMoviefileById` |
| `GET /api/v3/moviefile` | `ListMovieFile` | `GetMoviefile` |
| `GET /api/v3/moviefile/{id}` | `GetMovieFileById` | `GetMoviefileById` |
| `PUT /api/v3/moviefile/bulk` | `PutMovieFileBulk` | `PutMoviefileBulk` |
| `PUT /api/v3/moviefile/{id}` | `UpdateMovieFile` | `PutMoviefileById` |

### MovieFolder

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/movie/{id}/folder` | `GetMovieFolder` | `GetMovieByIdFolder` |

### MovieImport

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `POST /api/v3/movie/import` | `CreateMovieImport` | `PostMovieImport` |

### MovieLookup

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/movie/lookup` | `ListMovieLookup` | `GetMovieLookup` |

### NamingConfig

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/config/naming` | `GetNamingConfig` | `GetConfigNaming` |
| `GET /api/v3/config/naming/examples` | `GetNamingConfigExamples` | `GetConfigNamingExamples` |
| `GET /api/v3/config/naming/{id}` | `GetNamingConfigById` | `GetConfigNamingById` |
| `PUT /api/v3/config/naming/{id}` | `UpdateNamingConfig` | `PutConfigNamingById` |

### Notification

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/notification/{id}` | `DeleteNotification` | `DeleteNotificationById` |
| `GET /api/v3/notification` | `ListNotification` | `GetNotification` |
| `GET /api/v3/notification/schema` | `ListNotificationSchema` | `GetNotificationSchema` |
| `POST /api/v3/notification` | `CreateNotification` | `PostNotification` |
| `POST /api/v3/notification/action/{name}` | `CreateNotificationActionByName` | `PostNotificationActionByName` |
| `POST /api/v3/notification/test` | `TestNotification` | `PostNotificationTest` |
| `POST /api/v3/notification/testall` | `TestAllNotification` | `PostNotificationTestall` |
| `PUT /api/v3/notification/{id}` | `UpdateNotification` | `PutNotificationById` |

### Performer

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/performer/{id}` | `DeletePerformer` | `DeletePerformerById` |
| `GET /api/v3/performer` | `ListPerformer` | `GetPerformer` |
| `GET /api/v3/performer/{performerForeignId}/works` | `ListPerformerWorks` | `GetPerformerByPerformerForeignIdWorks` |
| `POST /api/v3/performer` | `CreatePerformer` | `PostPerformer` |
| `POST /api/v3/performer/list` | `CreatePerformerList` | `PostPerformerList` |
| `POST /api/v3/performer/paged` | `CreatePerformerPaged` | `PostPerformerPaged` |
| `PUT /api/v3/performer/{id}` | `UpdatePerformer` | `PutPerformerById` |

### QualityDefinition

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/qualitydefinition` | `ListQualityDefinition` | `GetQualitydefinition` |
| `GET /api/v3/qualitydefinition/limits` | `GetQualityDefinitionLimits` | `GetQualitydefinitionLimits` |
| `GET /api/v3/qualitydefinition/{id}` | `GetQualityDefinitionById` | `GetQualitydefinitionById` |
| `PUT /api/v3/qualitydefinition/update` | `PutQualityDefinitionUpdate` | `PutQualitydefinitionUpdate` |
| `PUT /api/v3/qualitydefinition/{id}` | `UpdateQualityDefinition` | `PutQualitydefinitionById` |

### QualityProfile

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/qualityprofile/{id}` | `DeleteQualityProfile` | `DeleteQualityprofileById` |
| `GET /api/v3/qualityprofile` | `ListQualityProfile` | `GetQualityprofile` |
| `GET /api/v3/qualityprofile/{id}` | `GetQualityProfileById` | `GetQualityprofileById` |
| `POST /api/v3/qualityprofile` | `CreateQualityProfile` | `PostQualityprofile` |
| `PUT /api/v3/qualityprofile/{id}` | `UpdateQualityProfile` | `PutQualityprofileById` |

### QualityProfileSchema

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/qualityprofile/schema` | `GetQualityProfileSchema` | `GetQualityprofileSchema` |

### Queue

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/queue/{id}` | `DeleteQueue` | `DeleteQueueById` |

### QueueAction

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `POST /api/v3/queue/grab/bulk` | `CreateQueueGrabBulk` | `PostQueueGrabBulk` |
| `POST /api/v3/queue/grab/{id}` | `CreateQueueGrabById` | `PostQueueGrabById` |

### QueueDetails

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/queue/details` | `ListQueueDetails` | `GetQueueDetails` |

### Release

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/release` | `ListRelease` | `GetRelease` |
| `POST /api/v3/release` | `CreateRelease` | `PostRelease` |

### ReleaseProfile

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/releaseprofile/{id}` | `DeleteReleaseProfile` | `DeleteReleaseprofileById` |
| `GET /api/v3/releaseprofile` | `ListReleaseProfile` | `GetReleaseprofile` |
| `GET /api/v3/releaseprofile/{id}` | `GetReleaseProfileById` | `GetReleaseprofileById` |
| `POST /api/v3/releaseprofile` | `CreateReleaseProfile` | `PostReleaseprofile` |
| `PUT /api/v3/releaseprofile/{id}` | `UpdateReleaseProfile` | `PutReleaseprofileById` |

### ReleasePush

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `POST /api/v3/release/push` | `CreateReleasePush` | `PostReleasePush` |

### RemotePathMapping

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/remotepathmapping/{id}` | `DeleteRemotePathMapping` | `DeleteRemotepathmappingById` |
| `GET /api/v3/remotepathmapping` | `ListRemotePathMapping` | `GetRemotepathmapping` |
| `GET /api/v3/remotepathmapping/{id}` | `GetRemotePathMappingById` | `GetRemotepathmappingById` |
| `POST /api/v3/remotepathmapping` | `CreateRemotePathMapping` | `PostRemotepathmapping` |
| `PUT /api/v3/remotepathmapping/{id}` | `UpdateRemotePathMapping` | `PutRemotepathmappingById` |

### RenameMovie

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/rename` | `ListRename` | `GetRename` |

### RootFolder

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/rootfolder/{id}` | `DeleteRootFolder` | `DeleteRootfolderById` |
| `GET /api/v3/rootfolder` | `ListRootFolder` | `GetRootfolder` |
| `GET /api/v3/rootfolder/{id}` | `GetRootFolderById` | `GetRootfolderById` |
| `POST /api/v3/rootfolder` | `CreateRootFolder` | `PostRootfolder` |
| `POST /api/v3/rootfolder/refresh/{id}` | `CreateRootFolderRefreshById` | `PostRootfolderRefreshById` |

### Studio

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/studio/{id}` | `DeleteStudio` | `DeleteStudioById` |
| `GET /api/v3/studio` | `ListStudio` | `GetStudio` |
| `GET /api/v3/studio/{studioForeignId}/works` | `ListStudioWorks` | `GetStudioByStudioForeignIdWorks` |
| `POST /api/v3/studio` | `CreateStudio` | `PostStudio` |
| `POST /api/v3/studio/list` | `CreateStudioList` | `PostStudioList` |
| `POST /api/v3/studio/paged` | `CreateStudioPaged` | `PostStudioPaged` |
| `PUT /api/v3/studio/{id}` | `UpdateStudio` | `PutStudioById` |

### System

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `POST /api/v3/system/restart` | `CreateSystemRestart` | `PostSystemRestart` |
| `POST /api/v3/system/shutdown` | `CreateSystemShutdown` | `PostSystemShutdown` |

### Tag

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `DELETE /api/v3/tag/{id}` | `DeleteTag` | `DeleteTagById` |
| `GET /api/v3/tag` | `ListTag` | `GetTag` |
| `POST /api/v3/tag` | `CreateTag` | `PostTag` |
| `PUT /api/v3/tag/{id}` | `UpdateTag` | `PutTagById` |

### TagDetails

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/tag/detail` | `ListTagDetail` | `GetTagDetail` |

### Task

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/system/task` | `ListSystemTask` | `GetSystemTask` |

### UiConfig

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/config/ui` | `GetUiConfig` | `GetConfigUi` |
| `GET /api/v3/config/ui/{id}` | `GetUiConfigById` | `GetConfigUiById` |
| `PUT /api/v3/config/ui/{id}` | `UpdateUiConfig` | `PutConfigUiById` |

### Update

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/update` | `ListUpdate` | `GetUpdate` |

### UpdateLogFile

| Operation | 0.3.0 | 0.4.0 |
| --- | --- | --- |
| `GET /api/v3/log/file/update` | `ListLogFileUpdate` | `GetLogFileUpdate` |

## Removed

| Operation | 0.3.0 | Why |
| --- | --- | --- |
| `GET /api/v3/performer/{performerForeignId}` | `GetPerformerByPerformerForeignId` | Folded into `GetPerformerById`, which is the same lookup. |
| `GET /api/v3/studio/{studioForeignId}` | `GetStudioByStudioForeignId` | Folded into `GetStudioById`, which is the same lookup. |
| `GET /content/{path}` | `GetContentByPath` | Serves the browser interface. Excluded from the document upstream. |
| `GET /login` | `GetLoginPage` | Serves the browser interface. Excluded from the document upstream. |
| `GET /{path}` | `GetStaticResourceByPath` | Serves the browser interface. Excluded from the document upstream. |
| `PUT /api/v3/moviefile/editor` | `PutMovieFileEditor` | The route is gone from the API. |

## Added

| Operation | 0.4.0 | Tag |
| --- | --- | --- |
| `GET /api/v3/library/search` | `GetLibrarySearch` | LibrarySearch |
| `GET /api/v3/library/search/movie` | `GetLibrarySearchMovie` | LibrarySearch |
| `GET /api/v3/library/search/performer` | `GetLibrarySearchPerformer` | LibrarySearch |
| `GET /api/v3/library/search/scene` | `GetLibrarySearchScene` | LibrarySearch |
| `GET /api/v3/library/search/studio` | `GetLibrarySearchStudio` | LibrarySearch |
| `GET /api/v3/qualityprofile/{id}/inuse` | `GetQualityprofileByIdInuse` | QualityProfile |
| `GET /api/v3/statistics` | `GetStatistics` | Statistics |
