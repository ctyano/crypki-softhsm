# crypki-softhsm

This is an unofficial repository to provide packages for [Athenz](https://www.athenz.io).

It is currently owned and maintained by [ctyano](https://github.com/ctyano).

## How to build

```
make
```

## How to run

```
docker run -d -p :4443:4443 -v $PWD/log:/var/log/crypki -v $PWD/tls-crt:/opt/crypki/tls-crt:ro -v $PWD/shm:/dev/shm --rm --name crypki -h "localhost" ghcr.io/ctyano/crypki-softhsm:latest
```

```
curl -X GET https://localhost:4443/ruok --cert tls-crt/client.crt --key tls-crt/client.key --cacert tls-crt/ca.crt 
```

## List of Distributions

### Docker(OCI) Image

[crypki-softhsm](https://github.com/users/ctyano/packages/container/package/crypki-softhsm)

