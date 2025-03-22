# PhotoPrism Usage Guide

This guide provides instructions for using PhotoPrism after deployment.

## Quick Start

After successful deployment, PhotoPrism should be running and accessible at [http://localhost:2342](http://localhost:2342) (unless configured differently in your `.env.prod` file).

### Default Login

- Username: `admin`
- Password: `admin` (unless you changed it in the `.env.prod` file)

## Basic Operations

### Importing Photos

1. **Web Upload**:
   - Navigate to "Library" → "Import"
   - Drag and drop photos or use the file selector

2. **Import from Directory**:
   - Place photos in the `import` directory
   - Go to "Library" → "Import"
   - Click "Start Import"

### Managing Your Photos

- **Browse**: Navigate through your photos in the "Photos" section
- **Search**: Use the search bar to find specific photos
- **Albums**: Create and manage albums from the "Albums" section
- **People**: Browse photos by recognized faces in the "People" section

### Organization

- **Labels**: Add and manage labels for your photos
- **Archive**: Move less important photos to the archive
- **Favorites**: Mark your favorite photos with a heart icon

## Common Commands

### Managing the PhotoPrism Instance

```bash
# Start PhotoPrism
npm run podman:up

# Stop PhotoPrism
npm run podman:down

# View logs
npm run podman:logs

# Restart services
npm run podman:restart
```

### Maintenance Tasks

```bash
# Index and repair metadata
podman-compose -f podman/podman-compose.prod.yml --env-file podman/.env.prod exec photoprism photoprism index --cleanup
podman-compose -f podman/podman-compose.prod.yml --env-file podman/.env.prod exec photoprism photoprism repair

# Check for duplicates
podman-compose -f podman/podman-compose.prod.yml --env-file podman/.env.prod exec photoprism photoprism duplicates
```

## Troubleshooting

### Podman Issues

If you encounter Podman-related issues during deployment:

1. **Podman Not Running**
   - Run the Podman troubleshooter: `npm run podman:troubleshoot`
   - On Windows/Mac, ensure Podman machine is started: `podman machine start`
   - On Linux, check Podman service status

2. **Common Podman Error Messages**
   - "Error: unable to connect to Podman": Podman machine not running or not initialized
   - "No such container": Container name is incorrect or container isn't running
   - "Port is already allocated": Another service is using port 2342

3. **Container Won't Start**
   - Check logs for detailed errors: `npm run podman:logs`
   - Verify environment variables in `.env.prod`

### PhotoPrism Issues

1. **Photos not showing up after import**
   - Ensure indexing has completed
   - Check logs for errors: `npm run podman:logs`

2. **Performance Issues**
   - Check system resources with `podman stats`
   - Clear the cache: `podman-compose -f podman/podman-compose.prod.yml --env-file podman/.env.prod exec photoprism photoprism cleanup`

3. **Login Issues**
   - Verify credentials in the `.env.prod` file
   - Restart the services: `npm run podman:restart`

## Advanced Features

### Face Recognition

1. Enable the BRAINS service in your `.env.prod` file:
   ```
   PHOTOPRISM_EXPERIMENTAL=true
   PHOTOPRISM_FACE_RECOGNITION=true
   ```
2. Restart PhotoPrism: `npm run podman:restart`
3. Navigate to "People" to view and classify faces

### Geo-Mapping

- Use the "Places" feature to view photos on a map
- Photos with GPS data will automatically appear on the map

## Additional Resources

- [Official PhotoPrism Documentation](https://docs.photoprism.app/)
- [Community Support](https://github.com/photoprism/photoprism/discussions)
- [Podman Documentation](https://podman.io/docs/)
