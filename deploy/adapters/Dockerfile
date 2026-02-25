FROM golang:1.23-alpine AS builder
WORKDIR /build
COPY go.mod ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o adapter .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=builder /build/adapter /usr/local/bin/adapter
ENTRYPOINT ["adapter"]
