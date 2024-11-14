FROM golang:1.23.1-bookworm
ADD ./wasmtime-v3.0.1-s390x-linux-c-api/lib/libwasmtime.a /usr/lib/
