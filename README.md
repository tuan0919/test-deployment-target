# test-deployment-target

Smoke app for the InfraDesk deployments pipeline: one nginx service serving a static page.

GitHub: https://github.com/tuan0919/test-deployment-target  
Image: `gmo021.cansportsvg.com:9443/library/test-deployment-target:latest`

## InfraDesk fields

- Repository: `https://github.com/tuan0919/test-deployment-target.git`
- Compose file: `docker-compose.yml`
- Deploy command: `docker compose -f docker-compose.yml up -d --remove-orphans`

There is no `build:` in compose. Rebuild and push the image before a new deploy:

```sh
sg docker -c 'docker build -t gmo021.cansportsvg.com:9443/library/test-deployment-target:latest .'
sg docker -c 'docker push gmo021.cansportsvg.com:9443/library/test-deployment-target:latest'
```
