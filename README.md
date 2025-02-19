# Discourse Docker Image for foodcoops.at

## Run production
```
docker-compose up -d --remove-orphans
```

## Run in dev mode
```
docker-compose -f docker-compose-dev.yml  up -d --remove-orphans
```


## Test

* import db dump of real data:
    ```
    docker-compose exec -T postgres psql -U discourse discourse < ../discourse_allmunde-2023-10-24.pgsql
    ```
