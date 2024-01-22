# Discourse Docker Image for foodcoops.at

## Test

* import db dump of real data:
    ```
    docker-compose exec -T postgres psql -U discourse discourse < ../discourse_allmunde-2023-10-24.pgsql
    ```
