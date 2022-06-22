FROM alpine:latest

COPY README.md .

ENTRYPOINT ["/bin/sh", "-c", "echo", "hello"]