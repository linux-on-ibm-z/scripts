FROM golang:1.22.2-bullseye
ADD ./wasmtime-v3.0.1-s390x-linux-c-api/lib/libwasmtime.a /usr/lib/
