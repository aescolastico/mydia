# Download Clients

Download clients handle the actual downloading of media files. Mydia supports both torrent and usenet clients.

## Supported Clients

### Torrent Clients

| Client | Protocol | Features |
|--------|----------|----------|
| qBittorrent | HTTP API | Categories, labels, seeding |
| Transmission | RPC | Categories, seeding |
| rqbit | HTTP API | Lightweight torrent client, seeding |

### Usenet Clients

| Client | Protocol | Features |
|--------|----------|----------|
| SABnzbd | HTTP API | Categories, priorities |
| NZBGet | JSON-RPC | Categories, priorities |

## Adding Download Clients

### Via Admin UI

1. Navigate to **Admin > Download Clients**
2. Click **Add Download Client**
3. Select client type
4. Enter connection details
5. Test connection
6. Save

### Via Environment Variables

Configure clients at container startup:

```bash
# qBittorrent
DOWNLOAD_CLIENT_1_NAME=qBittorrent
DOWNLOAD_CLIENT_1_TYPE=qbittorrent
DOWNLOAD_CLIENT_1_HOST=qbittorrent
DOWNLOAD_CLIENT_1_PORT=8080
DOWNLOAD_CLIENT_1_USERNAME=admin
DOWNLOAD_CLIENT_1_PASSWORD=adminpass

# Transmission
DOWNLOAD_CLIENT_2_NAME=Transmission
DOWNLOAD_CLIENT_2_TYPE=transmission
DOWNLOAD_CLIENT_2_HOST=transmission
DOWNLOAD_CLIENT_2_PORT=9091
DOWNLOAD_CLIENT_2_USERNAME=admin
DOWNLOAD_CLIENT_2_PASSWORD=adminpass

# rqbit
DOWNLOAD_CLIENT_3_NAME=rqbit
DOWNLOAD_CLIENT_3_TYPE=rqbit
DOWNLOAD_CLIENT_3_HOST=rqbit
DOWNLOAD_CLIENT_3_PORT=3030
# Optional, when rqbit HTTP basic auth is enabled
DOWNLOAD_CLIENT_3_USERNAME=admin
DOWNLOAD_CLIENT_3_PASSWORD=adminpass

# SABnzbd
DOWNLOAD_CLIENT_4_NAME=SABnzbd
DOWNLOAD_CLIENT_4_TYPE=sabnzbd
DOWNLOAD_CLIENT_4_HOST=sabnzbd
DOWNLOAD_CLIENT_4_PORT=8080
DOWNLOAD_CLIENT_4_API_KEY=your-sabnzbd-api-key

# NZBGet
DOWNLOAD_CLIENT_5_NAME=NZBGet
DOWNLOAD_CLIENT_5_TYPE=nzbget
DOWNLOAD_CLIENT_5_HOST=nzbget
DOWNLOAD_CLIENT_5_PORT=6789
DOWNLOAD_CLIENT_5_USERNAME=nzbget
DOWNLOAD_CLIENT_5_PASSWORD=tegbzn6789
```

## Configuration Options

| Option | Description | Example |
|--------|-------------|---------|
| Name | Display name | `qBittorrent` |
| Type | Client type | `qbittorrent` |
| Host | Hostname or IP | `192.168.1.100` |
| Port | Client port | `8080` |
| Username | Auth username | `admin` |
| Password | Auth password | `secret` |
| API Key | API key (SABnzbd) | `abc123` |
| Use SSL | Enable HTTPS | `true` |
| Category | Default category | `mydia` |
| Priority | Client priority | `1` |
| Download Directory | Output directory | `/downloads` |

## rqbit

Mydia connects to a separately running `rqbit server` over rqbit's HTTP API. Mydia does not install, start, or supervise the rqbit process.

Use these connection values when adding rqbit:

- Type: `rqbit`
- Port: `3030` by default
- Username/password: optional, only when rqbit HTTP basic auth is enabled

rqbit supports torrents only. It does not support categories, labels, tags, or Usenet downloads, so Mydia ignores category settings for rqbit clients. Final organization still happens during import when Mydia moves or links completed files into the configured library.

## Client Priority

When multiple clients are configured, priority determines which client is used:

- Higher priority = preferred
- If primary client fails, falls back to lower priority clients

## Categories

Categories help organize downloads:

- Configure a category in your download client
- Set the same category in Mydia
- Downloads are tagged with this category

rqbit does not have categories or labels. For rqbit clients, leave category fields empty and use the download directory plus Mydia's import step for final organization.

## Download Directory

Configure where downloads are saved:

- Set in download client settings
- Ensure Mydia can access this directory
- Use same filesystem as library for hardlinks

## Testing Connection

Always test connections before saving:

1. Click **Test Connection**
2. Verify successful connection
3. Check for any warnings

## Next Steps

- [Indexers](indexers.md) - Configure release searching
- [Environment Variables](../reference/environment-variables.md) - All configuration options
